//! # Itheris Warden - Rust Security Layer
//!
//! This module exports all the security-critical modules migrated from Julia:
//!
//! - **Secrets Management** (`secrets.rs`): TPM 2.0 + AES-256-GCM
//! - **JWT Authentication** (`jwt_auth.rs`): Secure token handling
//! - **Flow Integrity** (`flow_integrity.rs`): Cryptographic sovereignty verification
//! - **Risk Classification** (`risk_classifier.rs`): LEP veto equation
//! - **Secure Confirmation** (`secure_confirmation.rs`): Sovereign veto gate
//! - **Task Orchestration** (`task_orchestrator.rs`): Authenticated scheduling
//! - **Safe Shell** (`safe_shell.rs`): Jailed command execution
//! - **Safe HTTP** (`safe_http.rs`): Async HTTP with rate limiting
//!
//! ## Fail-Closed Security Architecture
//!
//! The Itheris Warden implements a fail-closed (fail-secure) architecture:
//!
//! 1. **kernel_init()**: Returns -3 (FATAL) if initialization fails
//! 2. **emergency_halt()**: Commands Julia to immediately stop all operations
//! 3. **emergency_seal()**: Permanently locks the kernel (Phase 6)
//! 4. **Panic handlers**: Prevent unsafe continued operation
//!
//! Julia is strictly advisory - it can PROPOSE but never EXECUTE without
//! Rust kernel approval.
//!
//! ## Migration Status
//!
//! | Module | Julia Source | Rust Target | Status |
//! |--------|--------------|-------------|--------|
//! | SecretsManager | jarvis/src/config/SecretsManager.jl | secrets.rs | ✅ Complete |
//! | JWTAuth | jarvis/src/auth/JWTAuth.jl | jwt_auth.rs | ✅ Complete |
//! | FlowIntegrity | adaptive-kernel/kernel/trust/FlowIntegrity.jl | flow_integrity.rs | ✅ Complete |
//! | RiskClassifier | adaptive-kernel/kernel/trust/RiskClassifier.jl | risk_classifier.rs | ✅ Complete |
//! | SecureConfirmationGate | adaptive-kernel/kernel/trust/SecureConfirmationGate.jl | secure_confirmation.rs | ✅ Complete |
//! | TaskOrchestrator | jarvis/src/orchestration/TaskOrchestrator.jl | task_orchestrator.rs | ✅ Complete |
//! | safe_shell | adaptive-kernel/capabilities/safe_shell.jl | safe_shell.rs | ✅ Complete |
//! | safe_http_request | adaptive-kernel/capabilities/safe_http_request.jl | safe_http.rs | ✅ Complete |

// Public exports
pub mod secrets;
pub mod jwt_auth;
pub mod flow_integrity;
pub mod risk_classifier;
pub mod secure_confirmation;
pub mod task_orchestrator;
pub mod safe_shell;
pub mod safe_http;
pub mod ffi; // FFI bridge for Julia interop
pub mod shared_memory; // Shared memory ring buffer for IPC
pub mod emergency; // Emergency halt and seal mechanism (Phase 6)

// Re-export commonly used types
pub use secrets::{SecretsManager, SecretsError};
pub use jwt_auth::{JWTAuth, AuthError, Claims, Role, AuthConfig};
pub use flow_integrity::{FlowIntegrityGate, FlowIntegrityError, FlowToken, RiskLevel as FlowRiskLevel};
pub use risk_classifier::{RiskClassifier, RiskError, RiskLevel, Classification};
pub use secure_confirmation::{SecureConfirmationGate, ConfirmationError, ConfirmationRequest, ConfirmationResult};
pub use task_orchestrator::{TaskOrchestrator, TaskError, Task, TaskRequest, TaskResult};
pub use safe_shell::{SafeShell, SafeShellError, ShellResult};
pub use safe_http::{SafeHttp, HttpError, HttpRequest, HttpResponse};
pub use emergency::{
    trigger_emergency_halt, 
    emergency_seal, 
    init_panic_handlers, 
    can_proceed, 
    is_sealed, 
    is_halt_active,
    EmergencyStatus,
    EmergencyError,
};

// Re-export FFI functions for Julia interop
pub use ffi::*;

