//! ITHERIS Console - Tauri Native Entry Point
//! 
//! Native Tauri application entry point for desktop deployment.

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

/// Global application state shared across Tauri commands
pub struct AppState {
    pub metabolic_signals: crate::state::signals::MetabolicSignals,
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

/// Tauri command: Get current metabolic state
#[tauri::command]
fn get_metabolic_state(
    state: tauri::State<'_, AppState>,
) -> Result<crate::state::signals::MetabolicState, String> {
    Ok(state.metabolic_signals.get_state())
}

/// Tauri command: Get current cognitive mode
#[tauri::command]
fn get_cognitive_mode(
    state: tauri::State<'_, AppState>,
) -> Result<String, String> {
    Ok(state.metabolic_signals.mode.get().display_name().to_string())
}

/// Tauri command: Get energy level
#[tauri::command]
fn get_energy_level(
    state: tauri::State<'_, AppState>,
) -> Result<f64, String> {
    Ok(state.metabolic_signals.energy.get())
}

/// Tauri command: Set cognitive mode
#[tauri::command]
fn set_cognitive_mode(
    mode: String,
    state: tauri::State<'_, AppState>,
) -> Result<(), String> {
    let cognitive_mode = crate::state::signals::CognitiveMode::from_str(&mode);
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
        metabolic_signals: crate::state::signals::MetabolicSignals::new(),
    };

    // Build and run Tauri application
    tauri::Builder::default()
        .manage(app_state)
        .invoke_handler(tauri::generate_handler![
            get_metabolic_state,
            get_cognitive_mode,
            get_energy_level,
            set_cognitive_mode,
        ])
        .setup(|app| {
            info!("Tauri application setup complete");
            
            // Get the main window
            if let Some(window) = app.get_webview_window("main") {
                // Set window title
                let _ = window.set_title("ITHERIS Console - ProjectX Jarvis");
            }
            
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Error while running Tauri application");
}
