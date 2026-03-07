//! # ITHERIS Daemon - Persistent Runtime
//!
//! Manages the Julia brain subprocess with lifecycle management,
//! crash recovery with watchdog timers, and systemd service support.

mod kernel;
mod secure_boot;
mod shared_memory;
mod ffi;
mod julia_runtime;

use chrono::Utc;
use kernel::{ActionType, ApprovalResult, ItherisDaemonKernel, KernelAction, KernelStats, RiskLevel};
use secure_boot::{BootStageResult, SecureBootManager};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::RwLock;
use tokio::time::interval;
use uuid::Uuid;

/// Daemon configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonConfig {
    pub julia_path: String,
    pub adaptive_kernel_path: String,
    pub health_check_interval_secs: u64,
    pub watchdog_timeout_secs: u64,
    pub http_port: u16,
    pub log_level: String,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        DaemonConfig {
            julia_path: "julia".to_string(),
            adaptive_kernel_path: "./adaptive-kernel".to_string(),
            health_check_interval_secs: 30,
            watchdog_timeout_secs: 120,
            http_port: 8080,
            log_level: "info".to_string(),
        }
    }
}

/// Daemon state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DaemonState {
    Starting,
    SecureBoot,
    Running,
    Recovering,
    Stopped,
    Error,
}

/// Health check response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub state: DaemonState,
    pub uptime_secs: u64,
    pub brain_pid: Option<u32>,
    pub brain_healthy: bool,
    pub kernel_stats: KernelStats,
    pub boot_stages: Vec<BootStageResult>,
}

/// ITHERIS Daemon
pub struct ItherisDaemon {
    config: DaemonConfig,
    state: Arc<RwLock<DaemonState>>,
    kernel: Arc<ItherisDaemonKernel>,
    secure_boot: Arc<RwLock<SecureBootManager>>,
    julia_process: Arc<RwLock<Option<Child>>>,
    start_time: Arc<RwLock<Option<chrono::DateTime<Utc>>>>,
    health_check_failures: Arc<RwLock<u32>>,
}

impl ItherisDaemon {
    /// Create new daemon
    pub fn new(config: DaemonConfig) -> Self {
        ItherisDaemon {
            config: config.clone(),
            state: Arc::new(RwLock::new(DaemonState::Starting)),
            kernel: Arc::new(ItherisDaemonKernel::new()),
            secure_boot: Arc::new(RwLock::new(SecureBootManager::new("./itheris-daemon"))),
            julia_process: Arc::new(RwLock::new(None)),
            start_time: Arc::new(RwLock::new(None)),
            health_check_failures: Arc::new(RwLock::new(0)),
        }
    }
    
    /// Initialize and start the daemon
    pub async fn start(&self) -> Result<(), String> {
        log::info!("🚀 Starting ITHERIS Daemon v1.0.0...");
        
        // Set start time
        *self.start_time.write().await = Some(Utc::now());
        
        // Execute secure boot sequence
        self.set_state(DaemonState::SecureBoot).await;
        
        let mut boot_manager = self.secure_boot.write().await;
        match boot_manager.execute_boot_sequence().await {
            Ok(stages) => {
                log::info!("✅ Secure boot completed: {} stages", stages.len());
            },
            Err(e) => {
                log::error!("❌ Secure boot failed: {}", e);
                self.set_state(DaemonState::Error).await;
                return Err(format!("Secure boot failed: {}", e));
            }
        }
        drop(boot_manager);
        
        // Initialize kernel
        self.kernel.initialize().await
            .map_err(|e| format!("Kernel init failed: {}", e))?;
        
        // Set warden as healthy after successful boot
        self.kernel.set_warden_status(true).await;
        
        // Start Julia brain subprocess
        self.set_state(DaemonState::Running).await;
        self.spawn_julia_brain().await?;
        
        log::info!("✅ ITHERIS Daemon started successfully");
        Ok(())
    }
    
    /// Spawn Julia brain subprocess
    async fn spawn_julia_brain(&self) -> Result<(), String> {
        log::info!("🧠 Spawning Julia brain...");
        
        let kernel_path = &self.config.adaptive_kernel_path;
        let run_path = format!("{}/run.jl", kernel_path);
        
        // Verify the path exists
        if !Path::new(&run_path).exists() {
            return Err(format!("Julia brain not found at: {}", run_path));
        }
        
        let mut child = Command::new(&self.config.julia_path)
            .arg("--project=".to_string() + kernel_path)
            .arg(&run_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("Failed to spawn Julia: {}", e))?;
        
        let pid = child.id().unwrap_or(0);
        log::info!("   ✓ Julia brain started (PID: {})", pid);
        
        // Store the process
        *self.julia_process.write().await = Some(child);
        
        Ok(())
    }
    
    /// Stop the daemon gracefully
    pub async fn stop(&self) {
        log::info!("🛑 Stopping ITHERIS Daemon...");
        
        self.set_state(DaemonState::Stopped).await;
        
        // Kill Julia process
        let mut proc = self.julia_process.write().await;
        if let Some(mut child) = proc.take() {
            let _ = child.kill().await;
            log::info!("   ✓ Julia brain stopped");
        }
        
        // Set warden unhealthy
        self.kernel.set_warden_status(false).await;
        
        log::info!("✅ Daemon stopped");
    }
    
    /// Watchdog - monitor Julia brain health
    pub async fn watchdog(&self) {
        log::info!("🐕 Starting watchdog...");
        
        let mut ticker = interval(Duration::from_secs(self.config.health_check_interval_secs));
        
        loop {
            ticker.tick().await;
            
            let state = *self.state.read().await;
            if state != DaemonState::Running {
                continue;
            }
            
            // Check Julia process
            let mut proc = self.julia_process.write().await;
            let is_healthy = if let Some(ref mut child) = *proc {
                match child.try_wait() {
                    Ok(Some(_)) => {
                        log::warn!("⚠️ Julia brain exited unexpectedly");
                        false
                    },
                    Ok(None) => true,
                    Err(e) => {
                        log::error!("Error checking Julia: {}", e);
                        false
                    }
                }
            } else {
                false
            };
            
            drop(proc);
            
            if !is_healthy {
                let mut failures = self.health_check_failures.write().await;
                *failures += 1;
                
                log::warn!("⚠️ Brain health check failed (count: {})", *failures);
                
                if *failures >= 3 {
                    log::error!("🛑 Brain unresponsive - initiating recovery");
                    self.set_state(DaemonState::Recovering).await;
                    self.kernel.set_warden_status(false).await;
                    
                    // Attempt recovery
                    if let Err(e) = self.spawn_julia_brain().await {
                        log::error!("Recovery failed: {}", e);
                    } else {
                        self.kernel.set_warden_status(true).await;
                        *self.health_check_failures.write().await = 0;
                        self.set_state(DaemonState::Running).await;
                    }
                }
            } else {
                *self.health_check_failures.write().await = 0;
            }
        }
    }
    
    /// Set daemon state
    async fn set_state(&self, state: DaemonState) {
        let old_state = *self.state.read().await;
        *self.state.write().await = state;
        log::info!("State: {:?} -> {:?}", old_state, state);
    }
    
    /// Get health status
    pub async fn health_check(&self) -> HealthResponse {
        let state = *self.state.read().await;
        
        // Get Julia process status
        let (pid, healthy) = {
            let proc = self.julia_process.read().await;
            if let Some(ref child) = *proc {
                let status = child.try_wait().map(|s| s.is_some()).unwrap_or(false);
                (child.id(), !status)
            } else {
                (None, false)
            }
        };
        
        // Get kernel stats
        let kernel_stats = self.kernel.get_stats().await;
        
        // Get boot stages
        let boot_stages = self.secure_boot.read().await.get_boot_log().clone();
        
        // Calculate uptime
        let uptime = if let Some(start) = *self.start_time.read().await {
            (Utc::now() - start).num_seconds() as u64
        } else {
            0
        };
        
        HealthResponse {
            status: if state == DaemonState::Running && healthy { "healthy".to_string() } else { "degraded".to_string() },
            state,
            uptime_secs: uptime,
            brain_pid: pid,
            brain_healthy: healthy,
            kernel_stats,
            boot_stages,
        }
    }
    
    /// Approve an action through the kernel
    pub async fn approve_action(&self, action: KernelAction) -> ApprovalResult {
        self.kernel.approve(action).await
    }
    
    /// Get kernel decision log
    pub async fn get_decision_log(&self) -> Vec<ApprovalResult> {
        self.kernel.get_decision_log().await
    }
}

/// HTTP server for health monitoring and control
async fn start_http_server(daemon: Arc<ItherisDaemon>, port: u16) {
    use axum::{Router, routing::get, Json, extract::State};
    use std::net::SocketAddr;
    
    #[derive(Clone)]
    struct DaemonState {
        daemon: Arc<ItherisDaemon>,
    }
    
    async fn health(State(state): State<DaemonState>) -> Json<HealthResponse> {
        Json(state.daemon.health_check().await)
    }
    
    async fn stats(State(state): State<DaemonState>) -> Json<serde_json::Value> {
        let kernel_stats = state.daemon.kernel.get_stats().await;
        Json(serde_json::json!({
            "approved": kernel_stats.approved,
            "blocked": kernel_stats.blocked,
            "warden_healthy": kernel_stats.warden_healthy,
            "capabilities": kernel_stats.capabilities_count,
        }))
    }
    
    async fn approve(State(state): State<DaemonState>, Json(action): Json<KernelAction>) -> Json<ApprovalResult> {
        Json(state.daemon.approve_action(action).await)
    }
    
    async fn log(State(state): State<DaemonState>) -> Json<Vec<ApprovalResult>> {
        Json(state.daemon.get_decision_log().await)
    }
    
    let app = Router::new()
        .route("/health", get(health))
        .route("/stats", get(stats))
        .route("/approve", axum::routing::post(approve))
        .route("/log", get(log))
        .with_state(DaemonState { daemon: daemon.clone() });
    
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    log::info!("🌐 HTTP server listening on http://{}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[tokio::main]
async fn main() -> Result<(), String> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();
    
    log::info!("===========================================");
    log::info!("  ITHERIS Sovereign Runtime Daemon v1.0");
    log::info!("===========================================");
    
    // Load configuration (or use defaults)
    let config = DaemonConfig::default();
    
    // Create daemon
    let daemon = Arc::new(ItherisDaemon::new(config.clone()));
    
    // Start the daemon
    daemon.start().await?;
    
    // Start HTTP server for health monitoring
    let daemon_for_http = daemon.clone();
    tokio::spawn(async move {
        start_http_server(daemon_for_http, config.http_port).await;
    });
    
    // Start watchdog
    daemon.watchdog().await;
    
    Ok(())
}
