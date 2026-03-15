//! # Supervisor - Crash Recovery and Health Monitoring
//!
//! Manages service lifecycle with crash restart policies, health checks,
//! and graceful shutdown via SIGTERM.

use crate::{JarvisState, RuntimeConfig};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tokio::time::interval;
use tracing::{info, error, warn, debug};

/// Restart policy for failed services
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RestartPolicy {
    /// Always restart on failure
    Always,
    /// Never restart on failure
    Never,
    /// Restart with exponential backoff
    ExponentialBackoff {
        max_retries: u32,
        initial_delay: u64,
        max_delay: u64,
    },
    /// Restart with fixed delay
    FixedDelay {
        retries: u32,
        delay_secs: u64,
    },
}

impl Default for RestartPolicy {
    fn default() -> Self {
        RestartPolicy::ExponentialBackoff {
            max_retries: 5,
            initial_delay: 1,
            max_delay: 60,
        }
    }
}

/// Supervisor configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SupervisorConfig {
    /// Restart policy for crashed services
    pub restart_policy: RestartPolicy,
    /// Health check interval
    pub health_check_interval: Duration,
    /// Graceful shutdown timeout
    pub shutdown_timeout: Duration,
}

impl Default for SupervisorConfig {
    fn default() -> Self {
        Self {
            restart_policy: RestartPolicy::default(),
            health_check_interval: Duration::from_secs(30),
            shutdown_timeout: Duration::from_secs(10),
        }
    }
}

/// Supervisor state
#[derive(Debug, Clone)]
pub struct SupervisorState {
    pub is_running: bool,
    pub restart_count: u32,
    pub last_restart: Option<Instant>,
    pub consecutive_failures: u32,
}

impl Default for SupervisorState {
    fn default() -> Self {
        Self {
            is_running: false,
            restart_count: 0,
            last_restart: None,
            consecutive_failures: 0,
        }
    }
}

/// Service health status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub healthy: bool,
    pub service_name: String,
    pub message: String,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

/// Supervisor - Manages service lifecycle with crash recovery
pub struct Supervisor {
    state: Arc<JarvisState>,
    config: SupervisorConfig,
    supervisor_state: Arc<RwLock<SupervisorState>>,
}

impl Supervisor {
    /// Create new supervisor with configuration
    pub fn new(state: Arc<JarvisState>, config: SupervisorConfig) -> Self {
        Self {
            state,
            config,
            supervisor_state: Arc::new(RwLock::new(SupervisorState::default())),
        }
    }

    /// Get access to runtime state
    pub fn state(&self) -> &Arc<JarvisState> {
        &self.state
    }

    /// Get supervisor state
    pub async fn get_state(&self) -> SupervisorState {
        self.supervisor_state.read().await.clone()
    }

    /// Run the supervisor with graceful shutdown handling
    pub async fn run<F, Fut>(&self, shutdown: F, _api_server: impl std::future::Future<Output = ()> + Send)
    where
        F: std::future::Future<Output = ()> + Send,
        Fut: std::future::Future<Output = ()> + Send,
    {
        info!("Starting supervisor...");

        // Mark as running
        {
            let mut state = self.supervisor_state.write().await;
            state.is_running = true;
        }

        // Start health check monitor
        let health_state = Arc::clone(&self.supervisor_state);
        let health_interval = self.config.health_check_interval;
        
        let health_monitor = tokio::spawn(async move {
            let mut ticker = interval(health_interval);
            loop {
                ticker.tick().await;
                let current_state = health_state.read().await;
                if !current_state.is_running {
                    break;
                }
                debug!("Health check tick");
                // Health checks would go here
            }
        });

        // Wait for shutdown signal
        shutdown.await;

        info!("Supervisor received shutdown signal");

        // Stop health monitor
        health_monitor.abort();

        // Graceful shutdown
        if let Err(e) = self.shutdown().await {
            error!("Error during shutdown: {}", e);
        }

        info!("Supervisor shutdown complete");
    }

    /// Handle service crash with restart policy
    pub async fn handle_crash(&self, service_name: &str) -> bool {
        let mut state = self.supervisor_state.write().await;
        state.consecutive_failures += 1;
        
        info!(
            "Service '{}' crashed (consecutive failures: {})",
            service_name,
            state.consecutive_failures
        );

        let should_restart = match self.config.restart_policy {
            RestartPolicy::Always => true,
            RestartPolicy::Never => false,
            RestartPolicy::ExponentialBackoff { max_retries, .. } => {
                state.restart_count < max_retries
            }
            RestartPolicy::FixedDelay { retries, .. } => {
                state.restart_count < retries
            }
        };

        if should_restart {
            state.restart_count += 1;
            state.last_restart = Some(Instant::now());
            info!("Will restart service '{}' (restart count: {})", service_name, state.restart_count);
        } else {
            warn!(
                "Service '{}' exceeded restart limit, not restarting",
                service_name
            );
            state.is_running = false;
        }

        should_restart
    }

    /// Perform graceful shutdown
    pub async fn shutdown(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Initiating graceful shutdown...");
        
        let mut state = self.supervisor_state.write().await;
        state.is_running = false;

        // Stop the runtime
        self.state.runtime.stop_services().await?;

        info!("Supervisor shutdown complete");
        Ok(())
    }

    /// Get health status of all monitored services
    pub async fn get_health_status(&self) -> Vec<HealthStatus> {
        let mut statuses = Vec::new();

        // Check runtime health
        let runtime_state = self.state.runtime.state().await;
        statuses.push(HealthStatus {
            healthy: matches!(runtime_state, crate::runtime::RuntimeState::Running),
            service_name: "runtime".to_string(),
            message: format!("Runtime state: {:?}", runtime_state),
            last_check: chrono::Utc::now(),
        });

        // Check capabilities health
        let capabilities_healthy = self.state.capabilities.health_check().await;
        statuses.push(HealthStatus {
            healthy: capabilities_healthy,
            service_name: "capabilities".to_string(),
            message: if capabilities_healthy { "OK".to_string() } else { "Degraded".to_string() },
            last_check: chrono::Utc::now(),
        });

        statuses
    }
}

/// Calculate exponential backoff delay
pub fn calculate_backoff(
    attempt: u32,
    initial_delay_ms: u64,
    max_delay_ms: u64,
) -> Duration {
    let delay = initial_delay_ms * 2u64.pow(attempt.min(10));
    Duration::from_millis(delay.min(max_delay_ms))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backoff_calculation() {
        let delay = calculate_backoff(0, 1000, 60000);
        assert_eq!(delay.as_millis(), 1000);

        let delay = calculate_backoff(1, 1000, 60000);
        assert_eq!(delay.as_millis(), 2000);

        let delay = calculate_backoff(5, 1000, 60000);
        assert_eq!(delay.as_millis(), 32000);
    }
}
