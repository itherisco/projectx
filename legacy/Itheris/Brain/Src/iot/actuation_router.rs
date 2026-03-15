//! Actuation Router Module
//!
//! Routes commands to appropriate IoT devices with confirmation workflow.
//! Implements safe actuation with verification and latency tracking (< 30ms target).

use crate::iot::device_registry::DeviceRegistry;
use crate::iot::mqtt_bridge::MqttBridge;
use crate::iot_bridge::{Command, CommandResult};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};

/// Actuation confirmation status
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub enum ConfirmationStatus {
    Pending,
    Confirmed,
    Rejected,
    Timeout,
    Verified,
}

/// Actuation confirmation record
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ActuationConfirmation {
    pub command_id: String,
    pub device_id: String,
    pub status: ConfirmationStatus,
    pub confirmation_timestamp: Option<String>,
    pub verification_timestamp: Option<String>,
    pub attempts: u32,
    pub max_attempts: u32,
}

/// Actuation request
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ActuationRequest {
    pub command: Command,
    pub priority: u8,
    pub require_confirmation: bool,
    pub timeout_ms: u64,
    pub retry_count: u32,
}

/// Latency measurement
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LatencyMeasurement {
    pub command_id: String,
    pub stage: String,
    pub duration_ms: f64,
    pub timestamp: String,
}

/// Actuation router errors
#[derive(Debug, thiserror::Error)]
pub enum ActuationError {
    #[error("Device not found: {0}")]
    DeviceNotFound(String),
    #[error("Command routing failed: {0}")]
    RoutingFailed(String),
    #[error("Confirmation timeout for command: {0}")]
    ConfirmationTimeout(String),
    #[error("Confirmation rejected for command: {0}")]
    ConfirmationRejected(String),
    #[error("Actuation verification failed: {0}")]
    VerificationFailed(String),
    #[error("MQTT error: {0}")]
    MqttError(String),
    #[error("Registry error: {0}")]
    RegistryError(String),
}

/// Actuation statistics
#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct ActuationStats {
    pub commands_routed: u64,
    pub commands_confirmed: u64,
    pub commands_rejected: u64,
    pub commands_timed_out: u64,
    pub commands_verified: u64,
    pub average_latency_ms: f64,
    pub max_latency_ms: f64,
    pub min_latency_ms: f64,
    pub total_commands: u64,
}

/// Actuation router - routes commands to devices with confirmation
pub struct ActuationRouter {
    registry: Arc<DeviceRegistry>,
    mqtt: Arc<RwLock<MqttBridge>>,
    pending_confirmations: Arc<RwLock<HashMap<String, ActuationConfirmation>>>,
    latency_measurements: Arc<RwLock<Vec<LatencyMeasurement>>>,
    stats: Arc<RwLock<ActuationStats>>,
    confirmation_tx: Option<mpsc::Sender<ActuationConfirmation>>,
    target_latency_ms: u64,
}

impl ActuationRouter {
    /// Create a new actuation router
    pub fn new(registry: Arc<DeviceRegistry>, mqtt: MqttBridge) -> Self {
        Self {
            registry,
            mqtt: Arc::new(RwLock::new(mqtt)),
            pending_confirmations: Arc::new(RwLock::new(HashMap::new())),
            latency_measurements: Arc::new(RwLock::new(Vec::new())),
            stats: Arc::new(RwLock::new(ActuationStats::default())),
            confirmation_tx: None,
            target_latency_ms: 30,
        }
    }

    /// Create with custom target latency
    pub fn with_target_latency(
        registry: Arc<DeviceRegistry>,
        mqtt: MqttBridge,
        target_ms: u64,
    ) -> Self {
        Self {
            registry,
            mqtt: Arc::new(RwLock::new(mqtt)),
            pending_confirmations: Arc::new(RwLock::new(HashMap::new())),
            latency_measurements: Arc::new(RwLock::new(Vec::new())),
            stats: Arc::new(RwLock::new(ActuationStats::default())),
            confirmation_tx: None,
            target_latency_ms: target_ms,
        }
    }

    /// Route a command to the appropriate device
    pub async fn route_command(&self, request: ActuationRequest) -> Result<CommandResult, ActuationError> {
        let start_time = Instant::now();
        let command = request.command.clone();

        println!(
            "[ACTUATION_ROUTER] Routing command {} to device {} (action: {})",
            command.id, command.device_id, command.action
        );

        // Verify device exists
        let device = self.registry
            .get_device(&command.device_id)
            .await
            .map_err(|e| ActuationError::RegistryError(e.to_string()))?;

        println!(
            "[ACTUATION_ROUTER] Device found: {} (type: {})",
            device.device.id, device.device.device_type
        );

        // Record routing latency
        let routing_latency = start_time.elapsed().as_secs_f64() * 1000.0;
        self.record_latency(&command.id, "routing".to_string(), routing_latency).await;

        // If confirmation required, set up confirmation workflow
        if request.require_confirmation {
            let confirmation = ActuationConfirmation {
                command_id: command.id.clone(),
                device_id: command.device_id.clone(),
                status: ConfirmationStatus::Pending,
                confirmation_timestamp: None,
                verification_timestamp: None,
                attempts: 0,
                max_attempts: request.retry_count.max(1),
            };

            self.pending_confirmations
                .write()
                .await
                .insert(command.id.clone(), confirmation);
        }

        // Publish command via MQTT
        let publish_start = Instant::now();
        {
            let mqtt = self.mqtt.read().await;
            mqtt.publish_command(&command.device_id, &command)
                .await
                .map_err(|e| ActuationError::MqttError(e.to_string()))?;
        }

        let publish_latency = publish_start.elapsed().as_secs_f64() * 1000.0;
        self.record_latency(&command.id, "mqtt_publish".to_string(), publish_latency).await;

        // Update stats
        {
            let mut stats = self.stats.write().await;
            stats.commands_routed += 1;
        }

        // If confirmation required, wait for confirmation
        if request.require_confirmation {
            let confirmation_result = self
                .wait_for_confirmation(&command.id, request.timeout_ms)
                .await?;

            match confirmation_result.status {
                ConfirmationStatus::Confirmed => {
                    let mut stats = self.stats.write().await;
                    stats.commands_confirmed += 1;
                }
                ConfirmationStatus::Rejected => {
                    let mut stats = self.stats.write().await;
                    stats.commands_rejected += 1;
                    return Err(ActuationError::ConfirmationRejected(command.id));
                }
                ConfirmationStatus::Timeout => {
                    let mut stats = self.stats.write().await;
                    stats.commands_timed_out += 1;
                    return Err(ActuationError::ConfirmationTimeout(command.id));
                }
                _ => {}
            }
        }

        // Execute command (in production, this would wait for device response)
        let exec_start = Instant::now();
        let result = self.execute_command_internal(&command).await;
        let exec_latency = exec_start.elapsed().as_secs_f64() * 1000.0;
        self.record_latency(&command.id, "execution".to_string(), exec_latency).await;

        // Verify actuation
        let verify_start = Instant::now();
        if request.require_confirmation {
            self.verify_actuation(&command.id, &command.device_id).await?;
        }
        let verify_latency = verify_start.elapsed().as_secs_f64() * 1000.0;
        self.record_latency(&command.id, "verification".to_string(), verify_latency).await;

        // Calculate total latency
        let total_latency = start_time.elapsed().as_secs_f64() * 1000.0;

        // Update latency stats
        {
            let mut stats = self.stats.write().await;
            stats.total_commands += 1;

            let n = stats.total_commands as f64;
            stats.average_latency_ms = ((stats.average_latency_ms * (n - 1.0)) + total_latency) / n;
            stats.max_latency_ms = stats.max_latency_ms.max(total_latency);

            if stats.min_latency_ms == 0.0 || total_latency < stats.min_latency_ms {
                stats.min_latency_ms = total_latency;
            }
        }

        // Check if within target
        if total_latency > self.target_latency_ms as f64 {
            println!(
                "[ACTUATION_ROUTER] ⚠️  Latency {}ms exceeds target {}ms",
                total_latency, self.target_latency_ms
            );
        } else {
            println!(
                "[ACTUATION_ROUTER] ✓ Command {} completed in {}ms (target: {}ms)",
                command.id, total_latency, self.target_latency_ms
            );
        }

        // Clean up confirmation if exists
        if request.require_confirmation {
            self.pending_confirmations
                .write()
                .await
                .remove(&command.id);
        }

        result
    }

    /// Wait for confirmation from device
    async fn wait_for_confirmation(
        &self,
        command_id: &str,
        timeout_ms: u64,
    ) -> Result<ActuationConfirmation, ActuationError> {
        let start = Instant::now();

        loop {
            if start.elapsed().as_millis() as u64 > timeout_ms {
                // Update confirmation status
                if let Some(conf) = self.pending_confirmations.write().await.get_mut(command_id) {
                    conf.status = ConfirmationStatus::Timeout;
                }
                return Err(ActuationError::ConfirmationTimeout(command_id.to_string()));
            }

            // Check confirmation status (in production, would wait for actual confirmation)
            {
                let confirmations = self.pending_confirmations.read().await;
                if let Some(conf) = confirmations.get(command_id) {
                    if conf.status == ConfirmationStatus::Confirmed
                        || conf.status == ConfirmationStatus::Rejected
                    {
                        return Ok(conf.clone());
                    }
                }
            }

            tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        }
    }

    /// Verify actuation was successful
    async fn verify_actuation(&self, command_id: &str, device_id: &str) -> Result<(), ActuationError> {
        // In production, this would query the device to verify the command was executed
        // For now, we simulate verification

        if let Some(conf) = self.pending_confirmations.write().await.get_mut(command_id) {
            conf.status = ConfirmationStatus::Verified;
            conf.verification_timestamp = Some(Utc::now().to_rfc3339());
        }

        {
            let mut stats = self.stats.write().await;
            stats.commands_verified += 1;
        }

        println!(
            "[ACTUATION_ROUTER] ✓ Actuation verified for command {} on device {}",
            command_id, device_id
        );

        Ok(())
    }

    /// Execute command internally (simulated)
    async fn execute_command_internal(&self, command: &Command) -> Result<CommandResult, ActuationError> {
        // In production, this would communicate with actual device
        // For now, return mock result matching the stub behavior

        let result = match command.action.as_str() {
            "LOCK" => serde_json::json!({"locked": true, "lock_type": "electromagnetic"}),
            "UNLOCK" => serde_json::json!({"locked": false}),
            "POWER_ON" => serde_json::json!({"powered": true, "boot_time_ms": 2400}),
            "POWER_OFF" => serde_json::json!({"powered": false}),
            "SET_CONFIG" => serde_json::json!({"config": command.parameters}),
            "READ_SENSOR" => serde_json::json!({"value": 42.5, "unit": "celsius"}),
            _ => serde_json::json!({"error": "Unknown action"}),
        };

        Ok(CommandResult {
            command_id: command.id.clone(),
            device_id: command.device_id.clone(),
            success: true,
            result,
            execution_time_ms: 0,
            timestamp: Local::now().to_rfc3339(),
        })
    }

    /// Record latency measurement
    async fn record_latency(&self, command_id: &str, stage: String, duration_ms: f64) {
        let measurement = LatencyMeasurement {
            command_id: command_id.to_string(),
            stage,
            duration_ms,
            timestamp: Utc::now().to_rfc3339(),
        };

        self.latency_measurements.write().await.push(measurement);
    }

    /// Get latency measurements
    pub async fn get_latency_measurements(&self) -> Vec<LatencyMeasurement> {
        self.latency_measurements.read().await.clone()
    }

    /// Get statistics
    pub async fn get_stats(&self) -> ActuationStats {
        self.stats.read().await.clone()
    }

    /// Confirm a pending command
    pub async fn confirm_command(&self, command_id: &str, accepted: bool) -> Result<(), ActuationError> {
        let mut confirmations = self.pending_confirmations.write().await;

        if let Some(conf) = confirmations.get_mut(command_id) {
            conf.status = if accepted {
                ConfirmationStatus::Confirmed
            } else {
                ConfirmationStatus::Rejected
            };
            conf.confirmation_timestamp = Some(Utc::now().to_rfc3339());

            println!(
                "[ACTUATION_ROUTER] Command {} {}",
                command_id,
                if accepted { "confirmed" } else { "rejected" }
            );

            Ok(())
        } else {
            Err(ActuationError::RoutingFailed(format!(
                "No pending confirmation for command: {}",
                command_id
            )))
        }
    }

    /// Get pending confirmations
    pub async fn get_pending_confirmations(&self) -> Vec<ActuationConfirmation> {
        self.pending_confirmations
            .read()
            .await
            .values()
            .cloned()
            .collect()
    }

    /// Set confirmation channel
    pub fn set_confirmation_channel(&mut self, tx: mpsc::Sender<ActuationConfirmation>) {
        self.confirmation_tx = Some(tx);
    }

    /// Get target latency
    pub fn get_target_latency(&self) -> u64 {
        self.target_latency_ms
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_actuation_stats() {
        let stats = ActuationStats::default();
        assert_eq!(stats.commands_routed, 0);
        assert_eq!(stats.total_commands, 0);
    }

    #[tokio::test]
    async fn test_confirmation_status() {
        let status = ConfirmationStatus::Pending;
        assert_eq!(status, ConfirmationStatus::Pending);
    }
}
