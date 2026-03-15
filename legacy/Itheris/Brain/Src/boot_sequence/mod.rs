//! Boot Sequence Module - 4-Stage Ignition System
//!
//! This module provides a comprehensive 4-stage boot sequence with fail-closed security:
//! - Stage 1: TPM PCR validation
//! - Stage 2: Vault secret injection
//! - Stage 3: Kernel diagnostics
//! - Stage 4: MQTT synchronization
//!
//! All stages must complete successfully for the system to boot. Any failure triggers
//! fail-closed behavior, preventing the system from starting in an insecure state.

pub mod ignition_sequence;
pub mod stage1_pcr;
pub mod stage2_vault;
pub mod stage3_diagnostics;
pub mod stage4_mqtt;

// Re-exports for convenience
pub use ignition_sequence::{
    IgnitionController, IgnitionConfig, IgnitionError, IgnitionResult, 
    BootStage, BootStatus, BootLog, StageResult,
};

pub use stage1_pcr::{
    PcrValidator, PcrValidationConfig, PcrError, PcrResult, PcrBank,
    PcrReadResult, SecureBootStatus, TpmQuote,
};

pub use stage2_vault::{
    VaultClient, VaultConfig, VaultError, VaultResult, SecretInjection,
    SecretMetadata, KeyringInjection,
};

pub use stage3_diagnostics::{
    DiagnosticsRunner, DiagnosticConfig, DiagnosticError, DiagnosticResult,
    MemoryIntegrity, CryptoSubsystem, IpcChannel, ModuleIntegrity,
    DiagnosticReport,
};

pub use stage4_mqtt::{
    MqttSync, MqttSyncConfig, MqttSyncError, MqttSyncResult, 
    ControlTopicSubscription, SystemReadyStatus, BrokerHealth,
};
