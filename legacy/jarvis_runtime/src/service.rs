//! # Service Trait
//!
//! Base trait for all runtime services with lifecycle management.

use async_trait::async_trait;
use std::fmt;

/// Service trait for lifecycle management
#[async_trait]
pub trait Service: fmt::Debug + Send + Sync {
    /// Service name for identification
    fn name(&self) -> &str;

    /// Start the service
    async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;

    /// Stop the service gracefully
    async fn shutdown(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;

    /// Check if service is healthy
    async fn health_check(&self) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        Ok(true)
    }
}

/// Service error types
#[derive(Debug)]
pub enum ServiceError {
    NotStarted,
    AlreadyRunning,
    NotRunning,
    ShutdownFailed(String),
    HealthCheckFailed(String),
}

impl fmt::Display for ServiceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServiceError::NotStarted => write!(f, "Service not started"),
            ServiceError::AlreadyRunning => write!(f, "Service already running"),
            ServiceError::NotRunning => write!(f, "Service not running"),
            ServiceError::ShutdownFailed(msg) => write!(f, "Shutdown failed: {}", msg),
            ServiceError::HealthCheckFailed(msg) => write!(f, "Health check failed: {}", msg),
        }
    }
}

impl std::error::Error for ServiceError {}

/// Service state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceState {
    Created,
    Starting,
    Running,
    Stopping,
    Stopped,
    Failed,
}

impl fmt::Display for ServiceState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServiceState::Created => write!(f, "created"),
            ServiceState::Starting => write!(f, "starting"),
            ServiceState::Running => write!(f, "running"),
            ServiceState::Stopping => write!(f, "stopping"),
            ServiceState::Stopped => write!(f, "stopped"),
            ServiceState::Failed => write!(f, "failed"),
        }
    }
}
