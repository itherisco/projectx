//! # JARVIS Runtime - Async Event Loop
//!
//! Tokio-based async runtime with service management and graceful shutdown.

use crate::service::Service;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};
use tracing::{info, error, debug};

/// Runtime execution mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeMode {
    /// Background daemon mode
    Daemon,
    /// Foreground interactive mode
    Foreground,
    /// Development mode with hot reload
    Dev,
}

impl Default for RuntimeMode {
    fn default() -> Self {
        RuntimeMode::Foreground
    }
}

/// Runtime configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeConfig {
    /// Execution mode
    pub mode: RuntimeMode,
    /// Working directory
    pub working_dir: PathBuf,
    /// PID file path (for daemon mode)
    pub pid_file: Option<PathBuf>,
    /// Graceful shutdown timeout
    pub shutdown_timeout_secs: u64,
    /// Maximum concurrent tasks
    pub max_concurrent_tasks: usize,
    /// Enable structured logging
    pub structured_logging: bool,
    /// Log directory
    pub log_dir: PathBuf,
    /// Data directory
    pub data_dir: PathBuf,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            mode: RuntimeMode::Foreground,
            working_dir: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
            pid_file: None,
            shutdown_timeout_secs: 30,
            max_concurrent_tasks: 100,
            structured_logging: true,
            log_dir: PathBuf::from("/var/log/jarvis"),
            data_dir: PathBuf::from("/var/lib/jarvis"),
        }
    }
}

impl RuntimeConfig {
    /// Load configuration from file
    pub fn load(path: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let content = std::fs::read_to_string(path)?;
        let config: RuntimeConfig = toml::from_str(&content)?;
        Ok(config)
    }

    /// Save configuration to file
    pub fn save(&self, path: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}

/// Runtime state
#[derive(Debug, Clone)]
pub enum RuntimeState {
    Starting,
    Running,
    ShuttingDown,
    Stopped,
    Failed(String),
}

/// JARVIS Runtime - Core async event loop
pub struct JarvisRuntime {
    config: RuntimeConfig,
    state: Arc<RwLock<RuntimeState>>,
    shutdown_tx: broadcast::Sender<()>,
    services: Arc<RwLock<Vec<Box<dyn Service + Send + Sync>>>>,
}

impl JarvisRuntime {
    /// Create new runtime with configuration
    pub fn new(config: RuntimeConfig) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);
        
        Self {
            config,
            state: Arc::new(RwLock::new(RuntimeState::Starting)),
            shutdown_tx,
            services: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Get configuration
    pub fn config(&self) -> &RuntimeConfig {
        &self.config
    }

    /// Get current runtime state
    pub async fn state(&self) -> RuntimeState {
        self.state.read().await.clone()
    }

    /// Register a service with the runtime
    pub async fn register_service<S>(&self, service: S)
    where
        S: Service + Send + Sync + 'static,
    {
        let mut services = self.services.write().await;
        services.push(Box::new(service));
        debug!("Service registered, total: {}", services.len());
    }

    /// Start all registered services
    pub async fn start_services(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Starting services...");
        let services = self.services.read().await;
        
        for service in services.iter() {
            service.start().await?;
        }
        
        *self.state.write().await = RuntimeState::Running;
        info!("All services started");
        Ok(())
    }

    /// Stop all registered services
    pub async fn stop_services(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Stopping services...");
        *self.state.write().await = RuntimeState::ShuttingDown;
        
        let mut services = self.services.write().await;
        
        // Stop in reverse order
        for service in services.iter().rev() {
            if let Err(e) = service.shutdown().await {
                error!("Error shutting down service: {}", e);
            }
        }
        
        services.clear();
        *self.state.write().await = RuntimeState::Stopped;
        info!("All services stopped");
        Ok(())
    }

    /// Get shutdown channel receiver
    pub fn shutdown_rx(&self) -> broadcast::Receiver<()> {
        self.shutdown_tx.subscribe()
    }

    /// Signal shutdown
    pub fn shutdown(&self) {
        let _ = self.shutdown_tx.send(());
    }

    /// Run in daemon mode (background)
    pub async fn run_daemon(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Running in daemon mode");
        
        // Write PID file if configured
        if let Some(ref pid_file) = self.config.pid_file {
            let pid = std::process::id();
            std::fs::write(pid_file, pid.to_string())?;
            info!("PID written to {:?}", pid_file);
        }

        // Start services
        self.start_services().await?;

        // Wait for shutdown signal
        let mut rx = self.shutdown_rx();
        rx.recv().await.ok();

        // Stop services
        self.stop_services().await?;

        // Clean up PID file
        if let Some(ref pid_file) = self.config.pid_file {
            std::fs::remove_file(pid_file).ok();
        }

        Ok(())
    }

    /// Run in foreground mode
    pub async fn run_foreground(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Running in foreground mode");
        self.start_services().await?;
        
        let mut rx = self.shutdown_rx();
        rx.recv().await.ok();
        
        self.stop_services().await?;
        Ok(())
    }

    /// Run in development mode
    pub async fn run_dev(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Running in development mode");
        
        // Development mode could enable hot reload, debug logging, etc.
        self.start_services().await?;
        
        let mut rx = self.shutdown_rx();
        rx.recv().await.ok();
        
        self.stop_services().await?;
        Ok(())
    }

    /// Run with mode
    pub async fn run(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        match self.config.mode {
            RuntimeMode::Daemon => self.run_daemon().await,
            RuntimeMode::Foreground => self.run_foreground().await,
            RuntimeMode::Dev => self.run_dev().await,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_runtime_config_default() {
        let config = RuntimeConfig::default();
        assert_eq!(config.mode, RuntimeMode::Foreground);
    }

    #[tokio::test]
    async fn test_runtime_state() {
        let runtime = JarvisRuntime::new(RuntimeConfig::default());
        let state = runtime.state().await;
        assert!(matches!(state, RuntimeState::Starting));
    }
}
