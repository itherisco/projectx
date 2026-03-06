//! Ignition Sequence Controller - Main Boot Sequence Orchestrator
//!
//! This is the main controller for the 4-stage ignition sequence. It orchestrates
//! all boot stages with fail-closed security, comprehensive logging, and rollback capability.
//!
//! # Boot Sequence:
//! 1. Stage 1: TPM PCR validation - Verify platform integrity
//! 2. Stage 2: Vault secret injection - Load sealed secrets into kernel keyring
//! 3. Stage 3: Kernel diagnostics - Verify kernel subsystems
//! 4. Stage 4: MQTT synchronization - Connect to control plane
//!
//! # Security Properties:
//! - Fail-closed: Any stage failure halts boot
//! - Atomic: All stages must succeed for boot to succeed
//! - Auditable: Comprehensive logging at each stage
//! - Rollback: Failed boot can trigger recovery

use crate::boot_sequence::stage1_pcr::{PcrValidator, PcrValidationConfig};
use crate::boot_sequence::stage2_vault::{VaultClient, VaultConfig};
use crate::boot_sequence::stage3_diagnostics::{DiagnosticsRunner, DiagnosticConfig};
use crate::boot_sequence::stage4_mqtt::{MqttSync, MqttSyncConfig};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::Duration;

/// Boot stages in order
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum BootStage {
    /// Stage 1: TPM PCR validation
    Stage1PcrValidation,
    /// Stage 2: Vault secret injection
    Stage2VaultInjection,
    /// Stage 3: Kernel diagnostics
    Stage3Diagnostics,
    /// Stage 4: MQTT synchronization
    Stage4MqttSync,
    /// Boot completed successfully
    Completed,
    /// Boot failed
    Failed,
}

impl BootStage {
    /// Get the stage name as string
    pub fn name(&self) -> &'static str {
        match self {
            BootStage::Stage1PcrValidation => "PCR Validation",
            BootStage::Stage2VaultInjection => "Vault Injection",
            BootStage::Stage3Diagnostics => "Diagnostics",
            BootStage::Stage4MqttSync => "MQTT Sync",
            BootStage::Completed => "Completed",
            BootStage::Failed => "Failed",
        }
    }
    
    /// Get the next stage
    pub fn next(&self) -> Option<BootStage> {
        match self {
            BootStage::Stage1PcrValidation => Some(BootStage::Stage2VaultInjection),
            BootStage::Stage2VaultInjection => Some(BootStage::Stage3Diagnostics),
            BootStage::Stage3Diagnostics => Some(BootStage::Stage4MqttSync),
            BootStage::Stage4MqttSync => Some(BootStage::Completed),
            BootStage::Completed | BootStage::Failed => None,
        }
    }
}

/// Boot status
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum BootStatus {
    /// Boot not started
    NotStarted,
    /// Boot in progress
    InProgress,
    /// Boot completed successfully
    Success,
    /// Boot failed
    Failed,
    /// Boot rolled back
    RolledBack,
}

/// Individual stage result
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StageResult {
    pub stage: BootStage,
    pub success: bool,
    pub message: String,
    pub timestamp: String,
    pub duration_ms: u64,
    pub error_details: Option<String>,
}

/// Boot log entry
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BootLog {
    pub timestamp: String,
    pub stage: BootStage,
    pub level: String,
    pub message: String,
}

/// Ignition configuration
#[derive(Clone, Debug)]
pub struct IgnitionConfig {
    /// Timeout for each stage (milliseconds)
    pub stage_timeout_ms: u64,
    /// Whether to enable fail-closed (default: true)
    pub fail_closed: bool,
    /// Whether to enable rollback on failure (default: true)
    pub enable_rollback: bool,
    /// Whether to use simulation mode (default: true for testing)
    pub simulation_mode: bool,
    /// MQTT broker URL
    pub mqtt_broker_url: String,
    /// Vault server URL
    pub vault_url: String,
    /// Vault token (for simulation, use placeholder)
    pub vault_token: String,
    /// PCR indices to validate
    pub pcr_indices: Vec<u8>,
    /// Known good PCR values (hex encoded)
    pub known_good_pcrs: Vec<String>,
}

impl Default for IgnitionConfig {
    fn default() -> Self {
        Self {
            stage_timeout_ms: 30000, // 30 seconds per stage
            fail_closed: true,
            enable_rollback: true,
            simulation_mode: true,
            mqtt_broker_url: "tcp://localhost:1883".to_string(),
            vault_url: "http://localhost:8200".to_string(),
            vault_token: "simulation-token".to_string(),
            // Standard TPM 2.0 PCR banks for secure boot
            pcr_indices: vec![0, 7, 11, 12, 14],
            // Known good values (would be measured in production)
            known_good_pcrs: vec![
                "0000000000000000000000000000000000000000000000000000000000000000".to_string(),
                "1111111111111111111111111111111111111111111111111111111111111111".to_string(),
                "2222222222222222222222222222222222222222222222222222222222222222".to_string(),
                "3333333333333333333333333333333333333333333333333333333333333333".to_string(),
                "4444444444444444444444444444444444444444444444444444444444444444".to_string(),
            ],
        }
    }
}

/// Ignition errors
#[derive(Debug, thiserror::Error)]
pub enum IgnitionError {
    #[error("Stage {stage} failed: {message}")]
    StageFailed {
        stage: BootStage,
        message: String,
        details: Option<String>,
    },
    
    #[error("Timeout during {stage}: {message}")]
    Timeout {
        stage: BootStage,
        message: String,
    },
    
    #[error("Rollback failed: {message}")]
    RollbackFailed {
        message: String,
        previous_error: Box<IgnitionError>,
    },
    
    #[error("Configuration error: {message}")]
    ConfigError {
        message: String,
    },
    
    #[error("Boot already in progress")]
    BootInProgress,
    
    #[error("Boot not started")]
    NotStarted,
}

/// Ignition result type
pub type IgnitionResult<T> = Result<T, IgnitionError>;

/// Main ignition controller
pub struct IgnitionController {
    config: IgnitionConfig,
    current_stage: Arc<Mutex<BootStage>>,
    status: Arc<Mutex<BootStatus>>,
    boot_log: Arc<Mutex<Vec<BootLog>>>,
    stage_results: Arc<Mutex<Vec<StageResult>>>,
    // Stage components
    pcr_validator: Option<PcrValidator>,
    vault_client: Option<VaultClient>,
    diagnostics: Option<DiagnosticsRunner>,
    mqtt_sync: Option<MqttSync>,
}

impl IgnitionController {
    /// Create a new ignition controller
    pub fn new(config: IgnitionConfig) -> Self {
        Self {
            config,
            current_stage: Arc::new(Mutex::new(BootStage::Stage1PcrValidation)),
            status: Arc::new(Mutex::new(BootStatus::NotStarted)),
            boot_log: Arc::new(Mutex::new(Vec::new())),
            stage_results: Arc::new(Mutex::new(Vec::new())),
            pcr_validator: None,
            vault_client: None,
            diagnostics: None,
            mqtt_sync: None,
        }
    }
    
    /// Create with default configuration
    pub fn with_defaults() -> Self {
        Self::new(IgnitionConfig::default())
    }
    
    /// Log a boot message
    fn log(&self, stage: BootStage, level: &str, message: &str) {
        let entry = BootLog {
            timestamp: Utc::now().to_rfc3339(),
            stage,
            level: level.to_string(),
            message: message.to_string(),
        };
        
        if let Ok(mut log) = self.boot_log.lock() {
            log.push(entry);
        }
        
        // Also print to console
        let prefix = match level {
            "ERROR" => "[BOOT ERROR]",
            "WARN" => "[BOOT WARN]",
            _ => "[BOOT]",
        };
        println!("{} {}: {}", prefix, stage.name(), message);
    }
    
    /// Record stage result
    fn record_stage_result(&self, result: StageResult) {
        if let Ok(mut results) = self.stage_results.lock() {
            results.push(result);
        }
    }
    
    /// Get current boot stage
    pub fn get_current_stage(&self) -> BootStage {
        self.current_stage.lock().map(|s| *s).unwrap_or(BootStage::Failed)
    }
    
    /// Get boot status
    pub fn get_status(&self) -> BootStatus {
        self.status.lock().map(|s| *s).unwrap_or(BootStatus::NotStarted)
    }
    
    /// Get boot log
    pub fn get_boot_log(&self) -> Vec<BootLog> {
        self.boot_log.lock().map(|l| l.clone()).unwrap_or_default()
    }
    
    /// Get stage results
    pub fn get_stage_results(&self) -> Vec<StageResult> {
        self.stage_results.lock().map(|r| r.clone()).unwrap_or_default()
    }
    
    /// Execute full boot sequence
    pub fn ignite(&mut self) -> IgnitionResult<()> {
        let start_time = std::time::Instant::now();
        
        // Check if already in progress
        {
            let status = self.status.lock().map_err(|_| IgnitionError::NotStarted)?;
            if *status == BootStatus::InProgress {
                return Err(IgnitionError::BootInProgress);
            }
        }
        
        // Set status to in progress
        {
            let mut status = self.status.lock().unwrap();
            *status = BootStatus::InProgress;
        }
        
        self.log(BootStage::Stage1PcrValidation, "INFO", "Starting ignition sequence...");
        
        // Execute each stage
        let stages = [
            BootStage::Stage1PcrValidation,
            BootStage::Stage2VaultInjection,
            BootStage::Stage3Diagnostics,
            BootStage::Stage4MqttSync,
        ];
        
        for stage in stages {
            let stage_start = std::time::Instant::now();
            
            // Update current stage
            {
                let mut current = self.current_stage.lock().unwrap();
                *current = stage;
            }
            
            self.log(stage, "INFO", format!("Starting {}...", stage.name()));
            
            // Execute the stage
            let result = match stage {
                BootStage::Stage1PcrValidation => self.execute_stage1(),
                BootStage::Stage2VaultInjection => self.execute_stage2(),
                BootStage::Stage3Diagnostics => self.execute_stage3(),
                BootStage::Stage4MqttSync => self.execute_stage4(),
                _ => unreachable!(),
            };
            
            let stage_duration = stage_start.elapsed().as_millis() as u64;
            
            match result {
                Ok(_) => {
                    self.log(stage, "INFO", format!("{} completed successfully", stage.name()));
                    self.record_stage_result(StageResult {
                        stage,
                        success: true,
                        message: format!("{} completed", stage.name()),
                        timestamp: Utc::now().to_rfc3339(),
                        duration_ms: stage_duration,
                        error_details: None,
                    });
                }
                Err(e) => {
                    let error_msg = format!("{} failed: {}", stage.name(), e);
                    self.log(stage, "ERROR", &error_msg);
                    
                    self.record_stage_result(StageResult {
                        stage,
                        success: false,
                        message: error_msg.clone(),
                        timestamp: Utc::now().to_rfc3339(),
                        duration_ms: stage_duration,
                        error_details: Some(format!("{:?}", e)),
                    });
                    
                    // Handle failure based on fail_closed setting
                    if self.config.fail_closed {
                        self.log(stage, "ERROR", "FAIL-CLOSED: Halting boot due to stage failure");
                        
                        // Attempt rollback if enabled
                        if self.config.enable_rollback {
                            self.rollback();
                        }
                        
                        {
                            let mut status = self.status.lock().unwrap();
                            *status = BootStatus::Failed;
                        }
                        
                        return Err(IgnitionError::StageFailed {
                            stage,
                            message: e.to_string(),
                            details: None,
                        });
                    } else {
                        self.log(stage, "WARN", "Fail-open: continuing despite failure");
                    }
                }
            }
        }
        
        // All stages completed
        {
            let mut status = self.status.lock().unwrap();
            *status = BootStatus::Success;
        }
        
        let total_duration = start_time.elapsed().as_millis() as u64;
        self.log(BootStage::Completed, "INFO", 
            format!("Ignition sequence completed successfully in {}ms", total_duration));
        
        Ok(())
    }
    
    /// Execute Stage 1: TPM PCR Validation
    fn execute_stage1(&mut self) -> IgnitionResult<()> {
        let pcr_config = PcrValidationConfig {
            pcr_indices: self.config.pcr_indices.clone(),
            known_good_values: self.config.known_good_pcrs.clone(),
            timeout_ms: self.config.stage_timeout_ms,
            simulation_mode: self.config.simulation_mode,
        };
        
        let validator = PcrValidator::new(pcr_config);
        self.pcr_validator = Some(validator);
        
        if let Some(ref validator) = self.pcr_validator {
            let result = validator.validate()?;
            if !result.is_valid {
                return Err(IgnitionError::StageFailed {
                    stage: BootStage::Stage1PcrValidation,
                    message: "PCR validation failed".to_string(),
                    details: Some(result.error_message),
                });
            }
        }
        
        Ok(())
    }
    
    /// Execute Stage 2: Vault Secret Injection
    fn execute_stage2(&mut self) -> IgnitionResult<()> {
        let vault_config = VaultConfig {
            url: self.config.vault_url.clone(),
            token: self.config.vault_token.clone(),
            timeout_ms: self.config.stage_timeout_ms,
            simulation_mode: self.config.simulation_mode,
            secrets_path: "itheris/sealed".to_string(),
        };
        
        let client = VaultClient::new(vault_config);
        self.vault_client = Some(client);
        
        if let Some(ref client) = self.vault_client {
            // Connect to vault
            client.connect()?;
            
            // Retrieve and inject secrets
            let secrets = client.retrieve_secrets()?;
            
            // Inject into kernel keyring
            for secret in secrets {
                client.inject_to_keyring(&secret)?;
            }
        }
        
        Ok(())
    }
    
    /// Execute Stage 3: Kernel Diagnostics
    fn execute_stage3(&mut self) -> IgnitionResult<()> {
        let diag_config = DiagnosticConfig {
            timeout_ms: self.config.stage_timeout_ms,
            simulation_mode: self.config.simulation_mode,
            check_memory_integrity: true,
            check_crypto_subsystem: true,
            check_ipc_channels: true,
            check_module_integrity: true,
        };
        
        let runner = DiagnosticsRunner::new(diag_config);
        self.diagnostics = Some(runner);
        
        if let Some(ref runner) = self.diagnostics {
            let report = runner.run_diagnostics()?;
            
            if !report.is_healthy {
                return Err(IgnitionError::StageFailed {
                    stage: BootStage::Stage3Diagnostics,
                    message: "Diagnostics failed".to_string(),
                    details: Some(report.failure_summary),
                });
            }
        }
        
        Ok(())
    }
    
    /// Execute Stage 4: MQTT Synchronization
    fn execute_stage4(&mut self) -> IgnitionResult<()> {
        let mqtt_config = MqttSyncConfig {
            broker_url: self.config.mqtt_broker_url.clone(),
            client_id: "itheris-boot-sequencer".to_string(),
            timeout_ms: self.config.stage_timeout_ms,
            simulation_mode: self.config.simulation_mode,
            control_topics: vec![
                "itheris/control/shutdown".to_string(),
                "itheris/control/restart".to_string(),
                "itheris/control/rollback".to_string(),
            ],
        };
        
        let sync = MqttSync::new(mqtt_config);
        self.mqtt_sync = Some(sync);
        
        if let Some(ref sync) = self.mqtt_sync {
            // Connect to broker
            sync.connect()?;
            
            // Subscribe to control topics
            sync.subscribe_to_controls()?;
            
            // Publish system ready status
            sync.publish_ready_status()?;
            
            // Verify connectivity
            if !sync.verify_connection()? {
                return Err(IgnitionError::StageFailed {
                    stage: BootStage::Stage4MqttSync,
                    message: "MQTT connection verification failed".to_string(),
                    details: None,
                });
            }
        }
        
        Ok(())
    }
    
    /// Rollback boot sequence
    fn rollback(&mut self) {
        self.log(BootStage::Failed, "WARN", "Initiating rollback...");
        
        // Rollback in reverse order
        // Stage 4: Disconnect MQTT
        if let Some(ref mut sync) = self.mqtt_sync {
            let _ = sync.disconnect();
        }
        
        // Stage 3: Clear diagnostic results (no rollback needed)
        
        // Stage 2: Revoke injected secrets
        if let Some(ref client) = self.vault_client {
            let _ = client.revoke_all_secrets();
        }
        
        // Stage 1: No rollback needed for PCR
        
        {
            let mut status = self.status.lock().unwrap();
            *status = BootStatus::RolledBack;
        }
        
        self.log(BootStage::Failed, "INFO", "Rollback completed");
    }
    
    /// Get detailed boot report
    pub fn get_boot_report(&self) -> serde_json::Value {
        let status = self.get_status();
        let stage = self.get_current_stage();
        let log = self.get_boot_log();
        let results = self.get_stage_results();
        
        serde_json::json!({
            "status": status,
            "current_stage": stage,
            "stages_completed": results.iter().filter(|r| r.success).count(),
            "total_stages": 4,
            "boot_log": log,
            "stage_results": results,
            "config": {
                "fail_closed": self.config.fail_closed,
                "enable_rollback": self.config.enable_rollback,
                "simulation_mode": self.config.simulation_mode,
            }
        })
    }
}

impl Default for IgnitionController {
    fn default() -> Self {
        Self::new(IgnitionConfig::default())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ignition_controller_creation() {
        let controller = IgnitionController::with_defaults();
        assert_eq!(controller.get_status(), BootStatus::NotStarted);
    }
    
    #[test]
    fn test_boot_stage_transitions() {
        assert_eq!(BootStage::Stage1PcrValidation.next(), Some(BootStage::Stage2VaultInjection));
        assert_eq!(BootStage::Stage4MqttSync.next(), Some(BootStage::Completed));
        assert_eq!(BootStage::Completed.next(), None);
    }
    
    #[test]
    fn test_ignition_in_simulation_mode() {
        let mut config = IgnitionConfig {
            simulation_mode: true,
            ..Default::default()
        };
        
        let mut controller = IgnitionController::new(config);
        let result = controller.ignite();
        
        // In simulation mode, should succeed
        assert!(result.is_ok() || !config.fail_closed);
    }
}
