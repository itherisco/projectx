//! # ITHERIS Sovereign Intelligence Kernel v5.0
//! 
//! A complete, cryptographically-verified, sovereign intelligence system
//! with multi-agent cognition, external integrations, and immutable audit trails.
//!
//! This kernel can run in two modes:
//! - **User-space** (default): Standard application with ZMQ/Tokio IPC
//! - **Bare-metal** (feature "bare-metal"): Ring 0 microkernel with GDT/IDT/paging
//!
//! Author: badra222
//! Date: 2026-01-17

pub mod crypto;
pub mod crypto_version_manager;
pub mod openssl_config;
pub mod kernel;
pub mod debate;
pub mod state;
pub mod federation;
pub mod llm_advisor;
pub mod catastrophe;
pub mod iot_bridge;
pub mod iot;
pub mod ledger;
pub mod threat_model;
pub mod api_bridge;
pub mod database;
pub mod pipeline;
pub mod monitoring;
pub mod panic_translation;
pub mod security;
pub mod identity;
pub mod execution;
pub mod wasm;
pub mod governance;
pub mod boot_sequence;
pub mod observability;

// Test modules
#[cfg(test)]
pub mod warden_validation_tests;

// Bare-metal modules (Ring 0)
#[cfg(feature = "bare-metal")]
pub mod boot;

#[cfg(feature = "bare-metal")]
pub mod memory;

#[cfg(feature = "bare-metal")]
pub mod ipc;

#[cfg(feature = "bare-metal")]
pub mod tpm;

#[cfg(feature = "bare-metal")]
pub mod container;

// Re-exports
pub use crypto::{CryptoAuthority, SignedThought};
pub use crypto_version_manager::{
    OpenSslVersionManager, OpenSslVersion, VersionDetectionResult, 
    OpenSslEnvironmentConfig, initialize_ssl_environment, 
    get_system_openssl_version, check_julia_openssl_compatibility,
    KNOWN_GOOD_OPENSSL_VERSIONS, MIN_SUPPORTED_OPENSSL_VERSION,
    MAX_SUPPORTED_OPENSSL_VERSION,
};
pub use openssl_config::{
    OpenSslConfig, TlsContext, TlsVersion, CipherSuiteConfig, 
    CertValidationConfig, TlsError, JwtValidationResult, 
    TlsHandshakeResult, CryptoPrimitiveResult,
    verify_all_crypto_primitives, verify_jwt_validation, 
    verify_tls_stability, get_recommended_config, get_development_config,
};
pub use kernel::ItherisKernel;
pub use debate::{DebateEngine, Position, Challenge, DebateOutcome};
pub use state::GlobalState;
pub use federation::{Federation, Agent, Message};
pub use llm_advisor::{LLMAdvisor, Advice};
pub use catastrophe::{CatastropheModel, Scenario, CatastropheEvent};
pub use iot_bridge::{IoTBridge, Device, Command, CommandResult};
pub use ledger::{ImmutableLedger, LedgerBlock, LedgerEntry};
pub use threat_model::{ThreatModel, Threat, AttackSimulation};
pub use api_bridge::{APIBridge, ExternalAPI, APIRequest, APIResponse};
pub use database::{DatabaseManager, Database, DatabaseType, Query, QueryResult};
pub use pipeline::{PipelineManager, DataPipeline, PipelineStage, PipelineExecution};
pub use monitoring::{Monitor, Metric, Alert};
pub use panic_translation::{TranslatedPanic, FFIResult, JuliaExceptionCode, catch_panic, catch_panic_ptr, free_translated_panic, raise_julia_exception, install_panic_hook, panic_in_progress};
pub use security::{TpmUnsealAuthority, KeyManager, PcrPolicy, SealedSecret, KeyMetadata, KeyType};

// Identity system re-exports
pub use identity::{
    // SPIFFE identity
    SpiffeId, SpiffeIdentity, IdentityProvider, IdentityVerifier, TrustDomain,
    VerificationResult, WorkloadApiClient,
    // OAuth client
    OAuthAgentClient, OAuthClientConfig, OAuthToken, AgentIdentity, AgentStatus,
    DeviceAuthorizationResponse, TokenRequest,
    // Token rotation
    TokenRotationManager, TokenRotationConfig, TokenRotationError,
    SecureTokenStorage, TokenStatus, TokenValidator, ValidationResult,
    IdentityChainEntry, ChainType,
    // SVID
    X509Svid, X509Bundle, X509Certificate,
    // Utilities
    create_agent_spiffe_id, validate_agent_id, IDENTITY_VERSION, DEFAULT_TRUST_DOMAIN,
    manager::IdentityManager,
};

// Execution system re-exports
pub use execution::{
    BashSandbox, ExecutionRequest, ExecutionResult, ExecutionPolicy,
    ExecutionError, CommandWhitelist, ResourceLimits, ResourceUsage,
    EnvFilter, SecurityChecker,
};

// WASM system re-exports
pub use wasm::{
    WasmConfig, WasmError, WasmResult, DecisionOperator, OperatorRegistry,
    OperatorManifest, DecisionEngine, DecisionContext, Decision, SecurityLevel,
};

// Governance system re-exports (LEP decision gate)
pub use governance::{
    // Constitution
    Constitution, ConstitutionDecision, ConstitutionError, ConstitutionResult,
    ConstitutionalAmendment, ConstitutionalRule, EmergencyLevel, ResourceLimits,
    RuleSeverity, RuleType, TemporalConstraints,
    // Intent Validator
    FieldType, FieldValidator, IntentAction, IntentAuditEntry, IntentSchema,
    IntentValidationError, IntentValidationResult, IntentValidator, RiskLevel,
    ValidatedIntent, IntentPriority,
    // LEP Controller
    ExecutionRequest, ExecutionResult, LEPDecision, LEPDecisionResult,
    LEPError, LEPResult, LEPStage, LEPController, OverrideRequest, OverrideSignature,
};

// Observability system re-exports (monitoring dashboards)
pub use observability::
    // Metrics collector
    MetricsCollector, MetricValue, MetricType, ActuationLatencyTracker,
    AgentDivergenceDetector, NetworkEgressMonitor, TpmOperationTracker,
    MqttThroughputTracker, PrometheusExporter, COLLECTOR_REGISTRY,
    ActuationLatencyStats, get_metrics_collector,
    // Dashboard
    DashboardData, SystemStatus, HistoricalData, AlertThreshold,
    DashboardApi, HistoricalAggregation, StatusLevel, ComponentStatus,
    MetricsSummary, HistoricalDataPoint, DashboardAlert,
    // Alerts
    SecurityAlert, AlertSeverity, AlertType, AlertAggregator,
    AlertRouter, AlertNotifier, AlertHistory, DeduplicationWindow,
    ALERT_CHANNELS, create_security_alert, aggregate_alerts,
    AlertChannel, ChannelType, AlertAnalysis;

// Bare-metal re-exports
#[cfg(feature = "bare-metal")]
pub use boot;

#[cfg(feature = "bare-metal")]
pub use memory;

#[cfg(feature = "bare-metal")]
pub use ipc::{self, IPCEntry, IPCEntryType, IPCFlags, IPCError, IPCResult, SyncIpcRingBuffer, SharedSyncBuffer, ring_buffer::RING_BUFFER_CAPACITY, shm::{ShmRegion, ShmLock, ShmReadGuard, ShmWriteGuard, ShmSequence, ShmError, ShmResult}};

#[cfg(feature = "bare-metal")]
pub use tpm;

#[cfg(feature = "bare-metal")]
pub use boot_sequence;

/// System version
pub const ITHERIS_VERSION: &str = "5.0.0";
/// System name
pub const ITHERIS_NAME: &str = "ITHERIS";
/// Authority
pub const AUTHORITY: &str = "badra222";
/// Whether running in bare-metal mode
#[cfg(feature = "bare-metal")]
pub const IS_BARE_METAL: bool = true;
#[cfg(not(feature = "bare-metal"))]
pub const IS_BARE_METAL: bool = false;