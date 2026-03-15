//! ITHERIS Console - Tauri Application Entry Point
//! 
//! Main entry point for the Tauri desktop application.
//! Initializes the gRPC client and mounts the Leptos application.

#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use anyhow::Result;
use std::sync::Arc;
use tauri::Manager;
use tokio::sync::Mutex;
use tracing::{error, info, Level};
use tracing_subscriber::FmtSubscriber;

mod app;

use app::App;
use services::grpc::WardenClient;
use state::signals::MetabolicSignals;

/// Global application state shared across Tauri commands
pub struct AppState {
    pub warden_client: Arc<Mutex<Option<WardenClient>>>,
    pub metabolic_signals: MetabolicSignals,
}

/// Initialize logging for the application
fn init_logging() {
    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .with_target(false)
        .with_thread_ids(false)
        .with_file(true)
        .with_line_number(true)
        .finish();

    tracing::subscriber::set_global_default(subscriber)
        .expect("Failed to set tracing subscriber");
    
    info!("ITHERIS Console logging initialized");
}

/// Connect to Warden gRPC service
async fn connect_warden(state: &AppState) -> Result<()> {
    info!("Connecting to Warden service at localhost:9090");
    
    let client = WardenClient::connect("http://localhost:9090").await?;
    
    let mut guard = state.warden_client.lock().await;
    *guard = Some(client);
    
    info!("Successfully connected to Warden");
    Ok(())
}

/// Tauri command: Get current metabolic state
#[tauri::command]
async fn get_metabolic_state(
    state: tauri::State<'_, AppState>,
) -> Result<state::signals::MetabolicState, String> {
    Ok(state.metabolic_signals.get_state())
}

/// Tauri command: Get current cognitive mode
#[tauri::command]
async fn get_cognitive_mode(
    state: tauri::State<'_, AppState>,
) -> Result<String, String> {
    Ok(state.metabolic_signals.mode.get().display_name().to_string())
}

/// Tauri command: Get energy level
#[tauri::command]
async fn get_energy_level(
    state: tauri::State<'_, AppState>,
) -> Result<f64, String> {
    Ok(state.metabolic_signals.energy.get())
}

/// Tauri command: Connect to Warden
#[tauri::command]
async fn connect_warden_cmd(
    state: tauri::State<'_, AppState>,
) -> Result<String, String> {
    match connect_warden(&state).await {
        Ok(_) => Ok("Connected to Warden".to_string()),
        Err(e) => {
            error!("Failed to connect to Warden: {}", e);
            Err(format!("Failed to connect: {}", e))
        }
    }
}

/// Tauri command: Check connection status
#[tauri::command]
async fn check_connection(
    state: tauri::State<'_, AppState>,
) -> Result<bool, String> {
    let guard = state.warden_client.lock().await;
    Ok(guard.is_some())
}

/// Tauri command: Set cognitive mode
#[tauri::command]
async fn set_cognitive_mode(
    mode: String,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    let cognitive_mode = state::signals::CognitiveMode::from_str(&mode);
    state.metabolic_signals.mode.set(cognitive_mode);
    Ok(())
}

fn main() {
    // Initialize panic hook for better error reporting
    std::panic::set_hook(Box::new(|panic_info| {
        error!("Application panic: {:?}", panic_info);
    }));

    // Initialize logging
    init_logging();

    info!("Starting ITHERIS Console v0.1.0");
    
    // Create shared application state
    let app_state = AppState {
        warden_client: Arc::new(Mutex::new(None)),
        metabolic_signals: MetabolicSignals::new(),
    };

    // Build and run Tauri application
    tauri::Builder::default()
        .manage(app_state)
        .invoke_handler(tauri::generate_handler![
            get_metabolic_state,
            get_cognitive_mode,
            get_energy_level,
            connect_warden_cmd,
            check_connection,
            set_cognitive_mode,
        ])
        .setup(|app| {
            info!("Tauri application setup complete");
            
            // Get the main window
            let window = app.get_webview_window("main").unwrap();
            
            // Set window title
            window.set_title("ITHERIS Console - ProjectX Jarvis").unwrap();
            
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Error while running Tauri application");
}
