//! Stage 4: MQTT Synchronization
//!
//! This stage connects to the MQTT broker and synchronizes with the control plane.
//! It includes:
//! - Connection to MQTT broker
//! - Subscription to control topics
//! - Publishing system ready status
//! - Verifying broker connectivity
//!
//! # Topics Used:
//! - `itheris/control/shutdown` - Receive shutdown commands
//! - `itheris/control/restart` - Receive restart commands
//! - `itheris/control/rollback` - Receive rollback commands
//! - `itheris/status/ready` - Publish system ready status

use crate::iot::mqtt_bridge::{MqttBridge, MqttConfig, QoSLevel, ConnectionState};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

/// MQTT sync configuration
#[derive(Clone, Debug)]
pub struct MqttSyncConfig {
    /// MQTT broker URL
    pub broker_url: String,
    /// Client ID
    pub client_id: String,
    /// Timeout in milliseconds
    pub timeout_ms: u64,
    /// Simulation mode
    pub simulation_mode: bool,
    /// Control topics to subscribe to
    pub control_topics: Vec<String>,
}

/// Control topic subscription
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ControlTopicSubscription {
    pub topic: String,
    pub subscribed_at: String,
    pub success: bool,
}

/// System ready status published
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SystemReadyStatus {
    pub system_id: String,
    pub status: String,
    pub version: String,
    pub timestamp: String,
    pub boot_stage: String,
}

/// Broker health check result
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BrokerHealth {
    pub connected: bool,
    pub latency_ms: u64,
    pub message_count: u64,
    pub last_check: String,
}

/// MQTT sync errors
#[derive(Debug, thiserror::Error)]
pub enum MqttSyncError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),
    
    #[error("Subscription failed: {0}")]
    SubscriptionFailed(String),
    
    #[error("Publish failed: {0}")]
    PublishFailed(String),
    
    #[error("Verification failed: {0}")]
    VerificationFailed(String),
    
    #[error("Not connected")]
    NotConnected,
    
    #[error("Timeout: {0}")]
    Timeout(String),
    
    #[error("Configuration error: {0}")]
    ConfigError(String),
}

/// MQTT sync result type
pub type MqttSyncResult<T> = Result<T, MqttSyncError>;

/// MQTT synchronization handler
pub struct MqttSync {
    config: MqttSyncConfig,
    bridge: Option<MqttBridge>,
    connected: bool,
    subscriptions: Vec<ControlTopicSubscription>,
    ready_status_published: bool,
}

impl MqttSync {
    /// Create a new MQTT sync handler
    pub fn new(config: MqttSyncConfig) -> Self {
        Self {
            config,
            bridge: None,
            connected: false,
            subscriptions: Vec::new(),
            ready_status_published: false,
        }
    }
    
    /// Connect to MQTT broker
    pub fn connect(&mut self) -> MqttSyncResult<()> {
        println!("[STAGE4] Connecting to MQTT broker at {}...", self.config.broker_url);
        
        let mqtt_config = MqttConfig {
            broker_url: self.config.broker_url.clone(),
            client_id: self.config.client_id.clone(),
            username: None,
            password: None,
            keep_alive_secs: 60,
            reconnect_delay_ms: 1000,
            max_reconnect_attempts: 3,
            use_tls: false,
        };
        
        let mut bridge = MqttBridge::new(mqtt_config);
        
        if self.config.simulation_mode {
            // In simulation mode, use async connect
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                bridge.connect().await
            }).map_err(|e| MqttSyncError::ConnectionFailed(e.to_string()))?;
        } else {
            // Try to connect
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                bridge.connect().await
            }).map_err(|e| MqttSyncError::ConnectionFailed(e.to_string()))?;
        }
        
        self.bridge = Some(bridge);
        self.connected = true;
        
        println!("[STAGE4] Connected to MQTT broker");
        Ok(())
    }
    
    /// Subscribe to control topics
    pub fn subscribe_to_controls(&mut self) -> MqttSyncResult<()> {
        println!("[STAGE4] Subscribing to control topics...");
        
        if !self.connected {
            return Err(MqttSyncError::NotConnected);
        }
        
        let rt = tokio::runtime::Runtime::new().unwrap();
        
        for topic in &self.config.control_topics {
            let result = rt.block_on(async {
                if let Some(ref mut bridge) = self.bridge {
                    bridge.subscribe(topic, QoSLevel::AtLeastOnce).await
                } else {
                    Err(crate::iot::mqtt_bridge::MqttError::NotConnected)
                }
            });
            
            let success = result.is_ok();
            
            self.subscriptions.push(ControlTopicSubscription {
                topic: topic.clone(),
                subscribed_at: Utc::now().to_rfc3339(),
                success,
            });
            
            if !success {
                println!("[STAGE4] WARNING: Failed to subscribe to {}", topic);
            } else {
                println!("[STAGE4] Subscribed to {}", topic);
            }
        }
        
        // Check all subscriptions succeeded
        let all_success = self.subscriptions.iter().all(|s| s.success);
        if !all_success {
            return Err(MqttSyncError::SubscriptionFailed("Some topics failed to subscribe".to_string()));
        }
        
        println!("[STAGE4] All control topics subscribed");
        Ok(())
    }
    
    /// Publish system ready status
    pub fn publish_ready_status(&mut self) -> MqttSyncResult<()> {
        println!("[STAGE4] Publishing system ready status...");
        
        if !self.connected {
            return Err(MqttSyncError::NotConnected);
        }
        
        let status = SystemReadyStatus {
            system_id: "itheris".to_string(),
            status: "ready".to_string(),
            version: "5.0.0".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            boot_stage: "completed".to_string(),
        };
        
        let payload = serde_json::to_string(&status)
            .map_err(|e| MqttSyncError::PublishFailed(e.to_string()))?;
        
        let rt = tokio::runtime::Runtime::new().unwrap();
        
        rt.block_on(async {
            if let Some(ref mut bridge) = self.bridge {
                bridge.publish(
                    "itheris/status/ready",
                    &payload,
                    QoSLevel::AtLeastOnce,
                    true, // Retain
                ).await
            } else {
                Err(crate::iot::mqtt_bridge::MqttError::NotConnected)
            }
        }).map_err(|e| MqttSyncError::PublishFailed(e.to_string()))?;
        
        self.ready_status_published = true;
        
        println!("[STAGE4] System ready status published");
        Ok(())
    }
    
    /// Verify broker connectivity
    pub fn verify_connection(&self) -> MqttSyncResult<bool> {
        println!("[STAGE4] Verifying MQTT broker connectivity...");
        
        if !self.connected {
            return Err(MqttSyncError::NotConnected);
        }
        
        // In production, would ping broker and check latency
        // For simulation, verify state
        let rt = tokio::runtime::Runtime::new().unwrap();
        
        let state = rt.block_on(async {
            if let Some(ref bridge) = self.bridge {
                bridge.get_state().await
            } else {
                ConnectionState::Disconnected
            }
        });
        
        let is_connected = state == ConnectionState::Connected;
        
        if is_connected {
            println!("[STAGE4] Broker connectivity verified");
        } else {
            println!("[STAGE4] Broker connectivity check failed");
        }
        
        Ok(is_connected)
    }
    
    /// Disconnect from MQTT broker
    pub fn disconnect(&mut self) -> MqttSyncResult<()> {
        println!("[STAGE4] Disconnecting from MQTT broker...");
        
        if let Some(ref mut bridge) = self.bridge {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                bridge.disconnect().await
            }).ok();
        }
        
        self.connected = false;
        
        println!("[STAGE4] Disconnected from MQTT broker");
        Ok(())
    }
    
    /// Check if connected
    pub fn is_connected(&self) -> bool {
        self.connected
    }
    
    /// Get subscriptions
    pub fn get_subscriptions(&self) -> &[ControlTopicSubscription] {
        &self.subscriptions
    }
    
    /// Get ready status published
    pub fn is_ready_published(&self) -> bool {
        self.ready_status_published
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_mqtt_sync_creation() {
        let config = MqttSyncConfig {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-test".to_string(),
            timeout_ms: 5000,
            simulation_mode: true,
            control_topics: vec![
                "itheris/control/shutdown".to_string(),
                "itheris/control/restart".to_string(),
            ],
        };
        
        let sync = MqttSync::new(config);
        assert!(!sync.is_connected());
    }
    
    #[test]
    fn test_mqtt_connect_in_simulation() {
        let config = MqttSyncConfig {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-test".to_string(),
            timeout_ms: 5000,
            simulation_mode: true,
            control_topics: vec![
                "itheris/control/shutdown".to_string(),
            ],
        };
        
        let mut sync = MqttSync::new(config);
        let result = sync.connect();
        
        assert!(result.is_ok());
        assert!(sync.is_connected());
    }
    
    #[test]
    fn test_mqtt_subscribe_in_simulation() {
        let config = MqttSyncConfig {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-test".to_string(),
            timeout_ms: 5000,
            simulation_mode: true,
            control_topics: vec![
                "itheris/control/shutdown".to_string(),
            ],
        };
        
        let mut sync = MqttSync::new(config);
        let _ = sync.connect();
        let result = sync.subscribe_to_controls();
        
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_mqtt_publish_ready_status() {
        let config = MqttSyncConfig {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-test".to_string(),
            timeout_ms: 5000,
            simulation_mode: true,
            control_topics: vec![
                "itheris/control/shutdown".to_string(),
            ],
        };
        
        let mut sync = MqttSync::new(config);
        let _ = sync.connect();
        let _ = sync.subscribe_to_controls();
        let result = sync.publish_ready_status();
        
        assert!(result.is_ok());
        assert!(sync.is_ready_published());
    }
    
    #[test]
    fn test_mqtt_verify_connection() {
        let config = MqttSyncConfig {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-test".to_string(),
            timeout_ms: 5000,
            simulation_mode: true,
            control_topics: vec![],
        };
        
        let mut sync = MqttSync::new(config);
        let _ = sync.connect();
        let result = sync.verify_connection();
        
        assert!(result.is_ok());
        assert!(result.unwrap());
    }
}
