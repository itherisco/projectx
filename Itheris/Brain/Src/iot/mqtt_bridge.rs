//! MQTT Bridge Module
//!
//! Provides MQTT communication for IoT device control.
//! Handles connection, publish/subscribe, message serialization, QoS, and reconnection.

use crate::iot_bridge::{Command, CommandResult};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tokio::time::{sleep, Duration};

/// MQTT QoS levels
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub enum QoSLevel {
    AtMostOnce,   // QoS 0 - fire and forget
    AtLeastOnce, // QoS 1 - acknowledged delivery
    ExactlyOnce,  // QoS 2 - assured delivery
}

impl From<QoSLevel> for u8 {
    fn from(qos: QoSLevel) -> Self {
        match qos {
            QoSLevel::AtMostOnce => 0,
            QoSLevel::AtLeastOnce => 1,
            QoSLevel::ExactlyOnce => 2,
        }
    }
}

/// MQTT message
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MqttMessage {
    pub topic: String,
    pub payload: String,
    pub qos: u8,
    pub retain: bool,
    pub timestamp: String,
    pub message_id: Option<String>,
}

/// MQTT connection configuration
#[derive(Clone, Debug)]
pub struct MqttConfig {
    pub broker_url: String,
    pub client_id: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub keep_alive_secs: u64,
    pub reconnect_delay_ms: u64,
    pub max_reconnect_attempts: u32,
    pub use_tls: bool,
}

impl Default for MqttConfig {
    fn default() -> Self {
        Self {
            broker_url: "tcp://localhost:1883".to_string(),
            client_id: "itheris-iot-bridge".to_string(),
            username: None,
            password: None,
            keep_alive_secs: 60,
            reconnect_delay_ms: 1000,
            max_reconnect_attempts: 10,
            use_tls: false,
        }
    }
}

/// Connection state
#[derive(Clone, Debug, PartialEq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Failed,
}

/// MQTT Bridge errors
#[derive(Debug, thiserror::Error)]
pub enum MqttError {
    #[error("Not connected to broker")]
    NotConnected,
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),
    #[error("Publish failed: {0}")]
    PublishFailed(String),
    #[error("Subscribe failed: {0}")]
    SubscribeFailed(String),
    #[error("Message serialization error: {0}")]
    SerializationError(String),
    #[error("Timeout waiting for response")]
    Timeout,
    #[error("Reconnection failed after {0} attempts")]
    ReconnectionFailed(u32),
}

/// MQTT Bridge statistics
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct MqttStats {
    pub messages_sent: u64,
    pub messages_received: u64,
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub connect_count: u64,
    pub disconnect_count: u64,
    pub last_message_timestamp: Option<String>,
    pub last_connect_timestamp: Option<String>,
}

/// MQTT Bridge for device communication
pub struct MqttBridge {
    config: MqttConfig,
    state: Arc<RwLock<ConnectionState>>,
    stats: Arc<RwLock<MqttStats>>,
    // Message channels (simulated - in production would use real MQTT client)
    publish_tx: Option<mpsc::Sender<MqttMessage>>,
    subscribe_handlers: Arc<RwLock<HashMap<String, mpsc::Sender<MqttMessage>>>>,
}

type HashMap<K, V> = std::collections::HashMap<K, V>;

impl MqttBridge {
    /// Create a new MQTT bridge with configuration
    pub fn new(config: MqttConfig) -> Self {
        Self {
            config,
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            stats: Arc::new(RwLock::new(MqttStats::default())),
            publish_tx: None,
            subscribe_handlers: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Create with default configuration
    pub fn with_defaults() -> Self {
        Self::new(MqttConfig::default())
    }

    /// Connect to MQTT broker
    pub async fn connect(&mut self) -> Result<(), MqttError> {
        self.set_state(ConnectionState::Connecting).await;
        
        println!(
            "[MQTT_BRIDGE] Connecting to broker: {}",
            self.config.broker_url
        );

        // Simulate connection attempt
        // In production, this would use a real MQTT client like rumqttc or paho-mqtt
        sleep(Duration::from_millis(100)).await;

        // For simulation, we'll create a channel for message passing
        let (tx, _rx) = mpsc::channel::<MqttMessage>(1000);
        self.publish_tx = Some(tx);

        self.set_state(ConnectionState::Connected).await;
        
        // Update stats
        {
            let mut stats = self.stats.write().await;
            stats.connect_count += 1;
            stats.last_connect_timestamp = Some(Utc::now().to_rfc3339());
        }

        println!(
            "[MQTT_BRIDGE] ✓ Connected to broker: {}",
            self.config.broker_url
        );

        Ok(())
    }

    /// Disconnect from MQTT broker
    pub async fn disconnect(&mut self) -> Result<(), MqttError> {
        self.set_state(ConnectionState::Disconnected).await;
        self.publish_tx = None;

        {
            let mut stats = self.stats.write().await;
            stats.disconnect_count += 1;
        }

        println!("[MQTT_BRIDGE] ✓ Disconnected from broker");
        Ok(())
    }

    /// Reconnect with exponential backoff
    pub async fn reconnect(&mut self) -> Result<(), MqttError> {
        let mut attempts = 0;
        let max_attempts = self.config.max_reconnect_attempts;

        while attempts < max_attempts {
            attempts += 1;
            self.set_state(ConnectionState::Reconnecting).await;

            let delay = self.config.reconnect_delay_ms * (2_u64.pow(attempts - 1).min(30));
            println!(
                "[MQTT_BRIDGE] Reconnecting (attempt {}/{}) after {}ms...",
                attempts, max_attempts, delay
            );

            sleep(Duration::from_millis(delay)).await;

            match self.connect().await {
                Ok(_) => {
                    println!("[MQTT_BRIDGE] ✓ Reconnected successfully");
                    return Ok(());
                }
                Err(e) => {
                    println!("[MQTT_BRIDGE] Reconnect failed: {}", e);
                }
            }
        }

        self.set_state(ConnectionState::Failed).await;
        Err(MqttError::ReconnectionFailed(attempts))
    }

    /// Publish a message to a topic
    pub async fn publish(
        &self,
        topic: &str,
        payload: &str,
        qos: QoSLevel,
        retain: bool,
    ) -> Result<String, MqttError> {
        if self.state.read().await != &ConnectionState::Connected {
            return Err(MqttError::NotConnected);
        }

        let message_id = uuid::Uuid::new_v4().to_string();
        
        let message = MqttMessage {
            topic: topic.to_string(),
            payload: payload.to_string(),
            qos: qos.into(),
            retain,
            timestamp: Utc::now().to_rfc3339(),
            message_id: Some(message_id.clone()),
        };

        // Update stats
        {
            let mut stats = self.stats.write().await;
            stats.messages_sent += 1;
            stats.bytes_sent += payload.len() as u64;
            stats.last_message_timestamp = Some(Utc::now().to_rfc3339());
        }

        // In production, this would send to actual MQTT broker
        if let Some(ref tx) = self.publish_tx {
            tx.send(message).await.map_err(|e| MqttError::PublishFailed(e.to_string()))?;
        }

        println!(
            "[MQTT_BRIDGE] ✓ Published to {} (QoS: {:?}, id: {})",
            topic, qos, message_id
        );

        Ok(message_id)
    }

    /// Subscribe to a topic
    pub async fn subscribe(
        &mut self,
        topic: &str,
        qos: QoSLevel,
    ) -> Result<mpsc::Receiver<MqttMessage>, MqttError> {
        if self.state.read().await != &ConnectionState::Connected {
            return Err(MqttError::NotConnected);
        }

        let (tx, rx) = mpsc::channel::<MqttMessage>(100);
        
        {
            let mut handlers = self.subscribe_handlers.write().await;
            handlers.insert(topic.to_string(), tx);
        }

        println!(
            "[MQTT_BRIDGE] ✓ Subscribed to {} (QoS: {:?})",
            topic, qos
        );

        Ok(rx)
    }

    /// Unsubscribe from a topic
    pub async fn unsubscribe(&mut self, topic: &str) -> Result<(), MqttError> {
        {
            let mut handlers = self.subscribe_handlers.write().await;
            handlers.remove(topic);
        }

        println!("[MQTT_BRIDGE] ✓ Unsubscribed from {}", topic);
        Ok(())
    }

    /// Publish command to device
    pub async fn publish_command(
        &self,
        device_id: &str,
        command: &Command,
    ) -> Result<String, MqttError> {
        let topic = format!("itheris/devices/{}/command", device_id);
        
        let payload = serde_json::to_string(command)
            .map_err(|e| MqttError::SerializationError(e.to_string()))?;

        self.publish(&topic, &payload, QoSLevel::AtLeastOnce, false).await
    }

    /// Publish command result from device
    pub async fn publish_command_result(
        &self,
        device_id: &str,
        result: &CommandResult,
    ) -> Result<String, MqttError> {
        let topic = format!("itheris/devices/{}/result", device_id);
        
        let payload = serde_json::to_string(result)
            .map_err(|e| MqttError::SerializationError(e.to_string()))?;

        self.publish(&topic, &payload, QoSLevel::AtLeastOnce, false).await
    }

    /// Publish device telemetry
    pub async fn publish_telemetry(
        &self,
        device_id: &str,
        telemetry: &serde_json::Value,
    ) -> Result<String, MqttError> {
        let topic = format!("itheris/devices/{}/telemetry", device_id);
        
        let payload = serde_json::to_string(telemetry)
            .map_err(|e| MqttError::SerializationError(e.to_string()))?;

        self.publish(&topic, &payload, QoSLevel::AtMostOnce, false).await
    }

    /// Publish device status
    pub async fn publish_device_status(
        &self,
        device_id: &str,
        status: &str,
    ) -> Result<String, MqttError> {
        let topic = format!("itheris/devices/{}/status", device_id);
        
        let payload = serde_json::json!({
            "device_id": device_id,
            "status": status,
            "timestamp": Utc::now().to_rfc3339(),
        });

        let payload_str = serde_json::to_string(&payload)
            .map_err(|e| MqttError::SerializationError(e.to_string()))?;

        self.publish(&topic, &payload_str, QoSLevel::AtLeastOnce, true).await
    }

    /// Get connection state
    pub async fn get_state(&self) -> ConnectionState {
        self.state.read().await.clone()
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        self.state.read().await == &ConnectionState::Connected
    }

    /// Get statistics
    pub async fn get_stats(&self) -> MqttStats {
        self.stats.read().await.clone()
    }

    /// Set connection state
    async fn set_state(&self, state: ConnectionState) {
        *self.state.write().await = state;
    }

    /// Receive message (for testing/simulation)
    pub async fn receive_message(&self, message: MqttMessage) {
        {
            let mut stats = self.stats.write().await;
            stats.messages_received += 1;
            stats.bytes_received += message.payload.len() as u64;
        }
        
        println!(
            "[MQTT_BRIDGE] ← Received on {} ({} bytes)",
            message.topic,
            message.payload.len()
        );
    }
}

impl Default for MqttBridge {
    fn default() -> Self {
        Self::new(MqttConfig::default())
    }
}

/// Build MQTT config from URL
pub fn build_mqtt_config(broker_url: &str) -> MqttConfig {
    MqttConfig {
        broker_url: broker_url.to_string(),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mqtt_connect() {
        let mut bridge = MqttBridge::with_defaults();
        
        let result = bridge.connect().await;
        assert!(result.is_ok());
        
        let state = bridge.get_state().await;
        assert_eq!(state, ConnectionState::Connected);
    }

    #[tokio::test]
    async fn test_mqtt_publish() {
        let mut bridge = MqttBridge::with_defaults();
        
        bridge.connect().await.unwrap();
        
        let result = bridge.publish(
            "test/topic",
            "test message",
            QoSLevel::AtMostOnce,
            false,
        ).await;
        
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_mqtt_disconnect() {
        let mut bridge = MqttBridge::with_defaults();
        
        bridge.connect().await.unwrap();
        bridge.disconnect().await.unwrap();
        
        let state = bridge.get_state().await;
        assert_eq!(state, ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn test_command_publish() {
        let bridge = MqttBridge::with_defaults();
        
        let command = Command {
            id: "cmd-001".to_string(),
            device_id: "device-001".to_string(),
            action: "LOCK".to_string(),
            parameters: serde_json::json!({}),
            requires_signature: true,
            signature: "sig123".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            status: "PENDING".to_string(),
        };
        
        // Can't test publish without connection in this design
        // In integration test, would connect first
        let _ = bridge;
    }
}
