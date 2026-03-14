//! # ITHERIS Daemon - Persistent Runtime
//!
//! Manages the Julia brain with embedded jlrs runtime,
//! crash recovery with watchdog timers, and systemd service support.


use chrono::Utc;
use itheris_daemon::grpc::{start_grpc_server, WardenServiceState};
use itheris_daemon::hardware;
use itheris_daemon::kernel;
use itheris_daemon::julia_runtime;
use itheris_daemon::secure_boot;
use hardware::{init_hardware_guard, HardwareGuard, get_hardware_status};
use kernel::{ActionType, ApprovalResult, ItherisDaemonKernel, KernelAction, KernelStats, RiskLevel};
use julia_runtime::{init_julia_runtime, JuliaConfig, get_julia_runtime};
use secure_boot::{BootStageResult, SecureBootManager};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;
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
    pub grpc_port: u16,
    pub log_level: String,
    pub heartbeat_pin: u32,
    pub heartbeat_frequency_hz: f64,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        DaemonConfig {
            julia_path: "julia".to_string(),
            adaptive_kernel_path: "./adaptive-kernel".to_string(),
            health_check_interval_secs: 30,
            watchdog_timeout_secs: 120,
            http_port: 8080,
            grpc_port: 9090,
            log_level: "info".to_string(),
            heartbeat_pin: 6,  // GPIO6 (Pin 31) - HEARTBEAT_OUT
            heartbeat_frequency_hz: 100.0,  // 100Hz = 10ms period
        }
    }
}

/// Daemon state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
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
    pub hardware_status: Option<hardware::HardwareStatus>,
}

/// ITHERIS Daemon
pub struct ItherisDaemon {
    config: DaemonConfig,
    state: Arc<RwLock<DaemonState>>,
    kernel: Arc<ItherisDaemonKernel>,
    secure_boot: Arc<RwLock<SecureBootManager>>,
    start_time: Arc<RwLock<Option<chrono::DateTime<Utc>>>>,
    health_check_failures: Arc<RwLock<u32>>,
    hardware_guard: Arc<RwLock<Option<HardwareGuard>>>,
    #[allow(dead_code)]
    julia_process: Arc<RwLock<Option<std::process::Child>>>,
}

impl ItherisDaemon {
    /// Create new daemon
    pub fn new(config: DaemonConfig) -> Self {
        ItherisDaemon {
            config: config.clone(),
            state: Arc::new(RwLock::new(DaemonState::Starting)),
            kernel: Arc::new(ItherisDaemonKernel::new()),
            secure_boot: Arc::new(RwLock::new(SecureBootManager::new("./itheris-daemon"))),
            start_time: Arc::new(RwLock::new(None)),
            health_check_failures: Arc::new(RwLock::new(0)),
            hardware_guard: Arc::new(RwLock::new(None)),
            julia_process: Arc::new(RwLock::new(None)),
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
        
        // Initialize hardware watchdog and heartbeat (after secure boot)
        match init_hardware_guard() {
            Ok(guard) => {
                *self.hardware_guard.write().await = Some(guard);
                log::info!("✅ Hardware layer initialized");
            },
            Err(e) => {
                log::warn!("⚠️ Hardware layer initialization warning: {}", e);
            }
        }
        
        // Initialize kernel
        self.kernel.initialize().await
            .map_err(|e| format!("Kernel init failed: {}", e))?;
        
        // Set warden as healthy after successful boot
        self.kernel.set_warden_status(true).await;
        
        // Initialize embedded Julia runtime (replaces subprocess spawning)
        self.set_state(DaemonState::Running).await;
        self.init_julia_embedded().await?;
        
        log::info!("✅ ITHERIS Daemon started successfully with embedded Julia");
        Ok(())
    }
    
    /// Initialize embedded Julia runtime using jlrs
    async fn init_julia_embedded(&self) -> Result<(), String> {
        log::info!("🧠 Initializing embedded Julia runtime via jlrs...");
        
        // Configure Julia runtime with 512MB memory limit (metabolic gating)
        let config = JuliaConfig {
            num_threads: Some(4),
            memory_limit_mb: 512,
            debug: false,
            project_path: Some(self.config.adaptive_kernel_path.clone()),
            sysimage_path: None,
            julia_dir: None,
            async_runtime: true,
        };
        
        init_julia_runtime(config)
            .map_err(|e| format!("Failed to initialize Julia: {}", e))?;
        
        log::info!("   ✓ Julia runtime initialized (embedded mode)");
        log::info!("   ✓ JIT compiler pre-warmed");
        log::info!("   ✓ Memory limit: 512MB (metabolic cap)");
        
        Ok(())
    }
    
    /// Spawn Julia brain subprocess
    #[allow(dead_code)]
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
            .spawn()
            .map_err(|e| format!("Failed to spawn Julia: {}", e))?;
        
        let pid = child.id();
        log::info!("   ✓ Julia brain started (PID: {})", pid);
        
        // Store the process
        *self.julia_process.write().await = Some(child);
        
        Ok(())
    }
    
    /// Stop the daemon gracefully
    pub async fn stop(&self) {
        log::info!("🛑 Stopping ITHERIS Daemon...");
        
        self.set_state(DaemonState::Stopped).await;
        
        // Release hardware guard (stops heartbeat gracefully)
        *self.hardware_guard.write().await = None;
        log::info!("   ✓ Hardware resources released");
        
        // Stop embedded Julia runtime
        if let Ok(runtime) = get_julia_runtime() {
            if let Ok(mut r) = runtime.write() {
                let _ = r.stop();
                log::info!("   ✓ Julia runtime stopped");
            }
        }
        
        // Set warden unhealthy
        self.kernel.set_warden_status(false).await;
        
        log::info!("✅ Daemon stopped");
    }
    
    /// Watchdog - monitor embedded Julia runtime health
    pub async fn watchdog(&self) {
        log::info!("🐕 Starting watchdog for embedded Julia...");
        
        let mut ticker = interval(Duration::from_secs(self.config.health_check_interval_secs));
        
        // Hardware watchdog kick ticker (every 500ms)
        let mut hw_kick_ticker = interval(Duration::from_millis(500));
        
        loop {
            // Handle hardware watchdog kick every 500ms
            tokio::select! {
                _ = hw_kick_ticker.tick() => {
                    // Kick the hardware watchdog
                    if let Some(ref guard) = *self.hardware_guard.read().await {
                        guard.kick_watchdog();
                    }
                }
                _ = ticker.tick() => {
                    // Existing health check logic
                    let state = *self.state.read().await;
                    if state != DaemonState::Running {
                        continue;
                    }
                    
                    // Check embedded Julia runtime health
                    let is_healthy = match get_julia_runtime() {
                        Ok(runtime) => {
                            match runtime.read() {
                                Ok(r) => r.is_running(),
                                Err(_) => false,
                            }
                        }
                        Err(_) => false,
                    };
                    
                    if !is_healthy {
                        let mut failures = self.health_check_failures.write().await;
                        *failures += 1;
                        
                        log::warn!("⚠️ Julia runtime health check failed (count: {})", *failures);
                        
                        if *failures >= 3 {
                            log::error!("🛑 Julia runtime unresponsive - initiating recovery");
                            self.set_state(DaemonState::Recovering).await;
                            self.kernel.set_warden_status(false).await;
                            
                            // Attempt recovery by reinitializing
                            if let Err(e) = self.init_julia_embedded().await {
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
        
        // Get embedded Julia runtime status
        let healthy = match get_julia_runtime() {
            Ok(runtime) => {
                match runtime.read() {
                    Ok(r) => r.is_running(),
                    Err(_) => false,
                }
            }
            Err(_) => false,
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
        
        // Get hardware status
        let hardware_status = if self.hardware_guard.read().await.is_some() {
            Some(get_hardware_status())
        } else {
            None
        };
        
        HealthResponse {
            status: if state == DaemonState::Running && healthy { "healthy".to_string() } else { "degraded".to_string() },
            state,
            uptime_secs: uptime,
            brain_pid: None, // Embedded runtime doesn't have a separate PID
            brain_healthy: healthy,
            kernel_stats,
            boot_stages,
            hardware_status,
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
    
    // Start gRPC server for frontend communication
    let grpc_state = Arc::new(WardenServiceState::new());
    let _daemon_for_grpc = daemon.clone();
    tokio::spawn(async move {
        if let Err(e) = start_grpc_server(grpc_state.clone(), config.grpc_port).await {
            log::error!("❌ gRPC server error: {}", e);
        }
    });
    log::info!("🔌 gRPC server will start on port {}", config.grpc_port);
    
    // Start watchdog
    daemon.watchdog().await;
    
    Ok(())
}
