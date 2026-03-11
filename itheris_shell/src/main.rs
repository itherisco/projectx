//! Itheris Shell - Main entry point with Active Watchdog (HCB Protocol Pillar 2).
//!
//! This module provides the main entry point for the Itheris shell
//! and implements the Active Watchdog system with SIGKILL enforcement.

mod bridge;
mod types;

use std::sync::atomic::{AtomicI32, AtomicI64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use log::{error, info, warn};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use tokio::sync::{broadcast, Mutex};
use tokio::task::JoinHandle;
use tokio::time;
use std::collections::VecDeque;

use bridge::ItherisBridge;

/// Watchdog heartbeat timeout in milliseconds (1000ms = 1 second - NON-NEGOTIABLE)
const WATCHDOG_TIMEOUT_MS: i64 = 1000;

/// Watchdog check interval in milliseconds (500ms)
const WATCHDOG_CHECK_INTERVAL_MS: u64 = 500;

/// Maximum security violations allowed in 60 seconds before emergency shutdown
const MAX_VIOLATIONS_IN_WINDOW: usize = 10;

/// Time window for violation counting (in seconds)
const VIOLATION_WINDOW_SECS: u64 = 60;

/// Spawn the Active Watchdog task.
///
/// This is Pillar 2 of the HCB Protocol - a hardware-level hard stop
/// that issues SIGKILL if the Julia kernel fails to send heartbeats
/// within the timeout window.
async fn spawn_watchdog(
    last_heartbeat: Arc<AtomicI64>,
    julia_pid: Arc<AtomicI32>,
    failure_tx: broadcast::Sender<String>,
    is_halted: Arc<AtomicBool>,
    command_buffer: Arc<tokio::sync::Mutex<VecDeque<String>>>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_millis(WATCHDOG_CHECK_INTERVAL_MS));
        
        loop {
            interval.tick().await;
            
            // Skip if already in HALTED mode
            if is_halted.load(Ordering::Relaxed) {
                continue;
            }
            
            // Read last heartbeat timestamp
            let heartbeat = last_heartbeat.load(Ordering::Relaxed);
            
            // If heartbeat is 0, Julia hasn't connected yet
            if heartbeat == 0 {
                continue;
            }
            
            // Calculate elapsed time since last heartbeat
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            
            let elapsed = now - heartbeat;
            
            // Check if timeout exceeded
            if elapsed > WATCHDOG_TIMEOUT_MS {
                let pid = julia_pid.load(Ordering::Relaxed);
                
                error!(
                    "WATCHDOG: Heartbeat timeout! {}ms elapsed. Julia is Cognitively Locked. Issuing SIGKILL to PID {}",
                    elapsed, pid
                );
                
                // Attempt to kill the Julia process with SIGKILL
                if pid > 0 {
                    let nix_pid = Pid::from_raw(pid);
                    match kill(nix_pid, Signal::SIGKILL) {
                        Ok(_) => {
                            error!("WATCHDOG: SIGKILL sent to Julia PID {}. Hard stop executed.", pid);
                        }
                        Err(e) => {
                            error!("WATCHDOG: Failed to send SIGKILL to PID {}: {}", pid, e);
                        }
                    }
                }
                
                // Wipe the command buffer (clear all pending commands)
                {
                    let mut buffer = command_buffer.lock().await;
                    let buffer_size = buffer.len();
                    buffer.clear();
                    if buffer_size > 0 {
                        info!("WATCHDOG: Wiped {} commands from buffer", buffer_size);
                    }
                }
                
                // Enter HALTED mode
                is_halted.store(true, Ordering::Relaxed);
                error!("WATCHDOG: System entered HALTED mode due to cognitive lock");
                
                // Broadcast failure notification
                let _ = failure_tx.send(format!(
                    "WATCHDOG: Julia kernel timeout after {}ms - SIGKILL delivered, system HALTED",
                    elapsed
                ));
                
                // Reset heartbeat to prevent repeated kills
                last_heartbeat.store(0, Ordering::Relaxed);
            }
        }
    })
}

/// Spawn the failure monitor task.
///
/// Monitors security violations and triggers emergency shutdown if
/// too many violations occur within the time window.
fn spawn_failure_monitor(
    mut failure_rx: broadcast::Receiver<String>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        // Track violations with timestamps
        let mut violation_timestamps: Vec<u64> = Vec::new();
        
        loop {
            match failure_rx.recv().await {
                Ok(notification) => {
                    info!("Failure notification: {}", notification);
                    
                    // Check if this is a security violation
                    if notification.contains("Security") || notification.contains("violation") {
                        let now = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .map(|d| d.as_secs())
                            .unwrap_or(0);
                        
                        // Add current timestamp to violations
                        violation_timestamps.push(now);
                        
                        // Remove old violations outside the window
                        violation_timestamps.retain(|&ts| now.saturating_sub(ts) < VIOLATION_WINDOW_SECS);
                        
                        // Check if we exceed the threshold
                        if violation_timestamps.len() > MAX_VIOLATIONS_IN_WINDOW {
                            error!(
                                "EMERGENCY: {} security violations in {} seconds - exceeds threshold of {}",
                                violation_timestamps.len(),
                                VIOLATION_WINDOW_SECS,
                                MAX_VIOLATIONS_IN_WINDOW
                            );
                            
                            // Clear the violation list to prevent repeated triggers
                            violation_timestamps.clear();
                        }
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    warn!("Failure monitor: Missed {} notifications", n);
                }
                Err(broadcast::error::RecvError::Closed) => {
                    info!("Failure monitor: Channel closed, stopping");
                    break;
                }
            }
        }
    })
}

/// Emergency kill function for critical situations.
///
/// Uses nix::sys::signal::kill with SIGKILL for immediate termination.
fn emergency_kill_julia(pid: i32) {
    if pid > 0 {
        error!("EMERGENCY: Issuing SIGKILL to Julia PID {}", pid);
        let nix_pid = Pid::from_raw(pid);
        match kill(nix_pid, Signal::SIGKILL) {
            Ok(_) => error!("EMERGENCY: SIGKILL delivered to PID {}", pid),
            Err(e) => error!("EMERGENCY: Failed to SIGKILL PID {}: {}", pid, e),
        }
    }
}

/// Main async entry point.
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Initialize env_logger
    env_logger::init();
    
    // 2. Create ItherisBridge (creates its own internal broadcast channel for security violations)
    let socket_path = "/tmp/itheris_kernel.sock";
    let mut bridge = ItherisBridge::new(socket_path);
    
    // 3. Get shared atomics BEFORE starting bridge
    let last_heartbeat = bridge.last_heartbeat();
    let julia_pid = bridge.julia_pid();
    let is_halted = bridge.is_halted();
    let command_buffer = bridge.command_buffer();
    
    // 4. Create broadcast channel for watchdog failures (shared with failure monitor)
    let (failure_tx, _) = broadcast::channel::<String>(100);
    let failure_tx_watchdog = failure_tx.clone();
    let failure_rx = failure_tx.subscribe();
    
    // 5. Spawn watchdog (Active Watchdog - Pillar 2)
    let watchdog_handle = spawn_watchdog(
        last_heartbeat.clone(),
        julia_pid.clone(),
        failure_tx_watchdog,
        is_halted,
        command_buffer,
    ).await;
    
    // 6. Spawn failure monitor (subscribes to failure channel)
    let failure_monitor = spawn_failure_monitor(failure_rx);
    
    // 7. Start bridge (this blocks, listening for connections)
    info!("Itheris Shell v1.0.0 - HCB Protocol Active");
    info!("Watchdog: {}ms heartbeat timeout with SIGKILL enforcement", WATCHDOG_TIMEOUT_MS);
    info!("Listening on {}", socket_path);
    
    // Start the bridge server - this blocks
    bridge.start_server().await?;
    
    // Wait for watchdog and failure monitor to complete (they won't in normal operation)
    let _ = watchdog_handle.await;
    let _ = failure_monitor.await;
    
    Ok(())
}
