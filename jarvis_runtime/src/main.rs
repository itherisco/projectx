//! # JARVIS Runtime - Main Entry Point
//!
//! Production-grade async runtime daemon for JARVIS intelligent platform.
//! Supports daemon mode, foreground mode, and development mode.

use clap::{Parser, ValueEnum};
use jarvis_runtime::{
    JarvisRuntime, JarvisState, RuntimeConfig, RuntimeMode,
    Supervisor, SupervisorConfig, RestartPolicy,
    ApiServer, create_router,
    init_logging,
    VERSION,
};
use std::sync::Arc;
use tokio::signal;
use tracing::{info, error, warn};

/// JARVIS Runtime CLI
#[derive(Parser, Debug)]
#[command(name = "jarvisd")]
#[command(version = VERSION)]
#[command(about = "JARVIS Production Runtime Daemon")]
struct Args {
    /// Runtime mode
    #[arg(value_enum, short, long, default_value = "foreground")]
    mode: RunMode,

    /// Listen address for API server
    #[arg(short, long, default_value = "127.0.0.1:8080")]
    listen: String,

    /// Log level
    #[arg(short, long, default_value = "info")]
    log_level: String,

    /// Config file path
    #[arg(short, long)]
    config: Option<String>,

    /// Enable debug mode
    #[arg(short, long)]
    debug: bool,

    /// Maximum restarts before giving up
    #[arg(long, default_value = "5")]
    max_restarts: u32,

    /// Restart delay in seconds
    #[arg(long, default_value = "2")]
    restart_delay: u64,

    /// Enable systemd mode
    #[arg(long)]
    systemd: bool,
}

#[derive(Copy, Clone, ValueEnum, Debug)]
enum RunMode {
    Daemon,
    Foreground,
    Dev,
}

impl From<RunMode> for RuntimeMode {
    fn from(mode: RunMode) -> Self {
        match mode {
            RunMode::Daemon => RuntimeMode::Daemon,
            RunMode::Foreground => RuntimeMode::Foreground,
            RunMode::Dev => RuntimeMode::Dev,
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Parse arguments
    let args = Args::parse();

    // Initialize logging
    let log_level = if args.debug { "debug" } else { &args.log_level };
    init_logging(log_level);

    info!("JARVIS Runtime v{} starting...", VERSION);
    info!("Mode: {:?}", args.mode);
    info!("Listen: {}", args.listen);

    // Load configuration
    let config = if let Some(config_path) = &args.config {
        RuntimeConfig::load(config_path)?
    } else {
        RuntimeConfig::default()
    };

    // Create supervisor configuration
    let supervisor_config = SupervisorConfig {
        restart_policy: RestartPolicy::ExponentialBackoff {
            max_retries: args.max_restarts,
            initial_delay: args.restart_delay,
            max_delay: 60,
        },
        health_check_interval: std::time::Duration::from_secs(30),
        shutdown_timeout: std::time::Duration::from_secs(10),
    };

    // Initialize runtime state
    let state = JarvisState::new(config).await?;

    // Create supervisor
    let supervisor = Supervisor::new(state, supervisor_config);

    // Create API server
    let app = create_router(Arc::clone(&supervisor.state()));
    let api_server = ApiServer::new(args.listen.parse()?, app);

    // Handle shutdown signals
    let shutdown = async {
        let ctrl_c = async {
            signal::ctrl_c()
                .await
                .expect("failed to listen for Ctrl+C");
        };

        #[cfg(unix)]
        let terminate = async {
            signal::unix::signal(signal::unix::SignalKind::terminate())
                .expect("failed to listen for SIGTERM")
                .recv()
                .await;
        };

        #[cfg(not(unix))]
        let terminate = std::future::pending::<()>();

        tokio::select! {
            _ = ctrl_c => {
                info!("Received Ctrl+C, shutting down...");
            }
            _ = terminate => {
                info!("Received SIGTERM, shutting down...");
            }
        }
    };

    // Run supervisor with graceful shutdown
    supervisor.run(shutdown, api_server).await?;

    info!("JARVIS Runtime shutdown complete");
    Ok(())
}
