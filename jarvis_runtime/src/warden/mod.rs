//! # Warden Security Layer
//!
//! The Warden layer is the sovereign security enforcement layer of the JARVIS system.
//! All security-critical operations are implemented here in Rust for:
//! - Memory safety (no buffer overflows, use-after-free)
//! - Type safety (strict compile-time checks)
//! - Performance (async-capable, low overhead)
//! - Cryptographic primitives (AES-256-GCM, HMAC-SHA256)
//!
//! ## Key Invariants
//!
//! - **Kernel is sovereign** - No capability executes without Warden approval
//! - **Fail-closed** - Any error or uncertainty results in denial
//! - **Immutable enforcement** - Security checks cannot be bypassed at runtime
//!
//! ## Modules
//!
//! - `flow_integrity`: Cryptographic HMAC tokens for action authorization
//! - `secrets`: AES-256-GCM encryption with TPM 2.0 support
//! - `auth`: JWT-based authentication with secure session management
//! - `risk_classifier`: Dynamic risk assessment for actions
//! - `confirmation`: Cryptographic confirmation tokens
//! - `capabilities`: Safe execution primitives (shell, HTTP)

pub mod flow_integrity;
pub mod secrets;
pub mod auth;
pub mod risk_classifier;
pub mod confirmation;
pub mod capabilities;

pub use flow_integrity::{FlowToken, FlowIntegrityGate, IssueTokenRequest, VerifyTokenRequest};
pub use secrets::{SecretsManager, Secret};
pub use auth::{JWTAuth, JWTClaims, AuthConfig};
pub use risk_classifier::{RiskClassifier, RiskLevel, RiskAssessment};
pub use confirmation::{SecureConfirmationGate, ConfirmationToken, ConfirmationRequest};
pub use capabilities::{SafeShell, SafeHttpRequest, ShellCommand, HttpRequest, CapabilityResult};

use thiserror::Error;

#[derive(Error, Debug)]
pub enum WardenError {
    #[error("Security violation: {0}")]
    SecurityViolation(String),
    
    #[error("Cryptographic error: {0}")]
    CryptoError(String),
    
    #[error("")]
Token expired    TokenExpired,
    
    #[error("Token invalid")]
    TokenInvalid,
    
    #[error("Configuration error: {0}")]
    ConfigError(String),
    
    #[error("Execution error: {0}")]
    ExecutionError(String),
}

pub type WardenResult<T> = Result<T, WardenError>;
