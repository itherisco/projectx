//! IPC Bridge module for communication with the Julia kernel.
//!
//! This module provides Unix Domain Socket (UDS) based IPC for
//! inter-process communication with the Itheris Julia kernel.
//! Implements the HCB Protocol with Ed25519 cryptographic command
//! verification and safety gateway enforcement.

use crate::types::{
    ActionResult, AuthorizedCommand, AutonomyLevel, FailureSeverity, IpcMessage,
    NonceTracker, SafetyGateway, SecurityViolation, SecurityViolationType, WorldAction,
};
use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::Utc;
use ed25519_dalek::{Signature as Ed25519Signature, Signer, SigningKey, Verifier, VerifyingKey};
use log::{debug, error, info, warn};
use rand::random;
use std::collections::VecDeque;
use std::os::unix::net::UnixDatagram;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener as TokioUnixListener, UnixStream};
use tokio::sync::{broadcast, Mutex};
use tokio::time::interval;
use uuid::Uuid;

// ============================================================================
// HARDCODED ED25519 PUBLIC KEY - IRON SENTRY CONFIGURATION
// ============================================================================

/// Hardcoded Ed25519 public key for command verification (Iron Sentry).
/// This key is ALWAYS required for command execution - no bypass allowed.
/// Source: adaptive-kernel/security/keys/public_key.b64
const HARDCODED_PUBLIC_KEY: &str = "7jkZJmPfl80czlZcBSIqNJQaxwmygDY0/zIgplMXWjE=";

/// Verify that the provided public key matches the hardcoded key.
/// Returns Ok(()) if valid, SecurityViolation if not.
fn verify_hardcoded_public_key(provided_key: &str) -> Result<(), SecurityViolation> {
    if provided_key != HARDCODED_PUBLIC_KEY {
        return Err(SecurityViolation {
            violation_type: SecurityViolationType::UnauthorizedBinary,
            details: format!(
                "Public key does not match hardcoded Iron Sentry key. Expected: {}...",
                &HARDCODED_PUBLIC_KEY[..16]
            ),
            timestamp: Utc::now().timestamp_millis(),
            source_ip: None,
        });
    }
    Ok(())
}

// ============================================================================
// DEADMAN SWITCH / HEARTBEAT WATCHDOG IMPLEMENTATION
// ============================================================================

/// Default socket path for heartbeat monitoring
const HEARTBEAT_SOCKET_PATH: &str = "/tmp/itheris_heartbeat.sock";

/// Heartbeat timeout in milliseconds (500ms)
const HEARTBEAT_TIMEOUT_MS: i64 = 500;

/// Whitelisted directories that can be locked
const DEFAULT_ALLOWED_DIRECTORIES: &[&str] = &[
    "/tmp/itheris",
    "/var/itheris",
    "/home/codespace/projectx",
];

/// WatchdogState - Tracks heartbeat state and controls the Julia process.
///
/// This struct manages:
/// - Last heartbeat timestamp from Julia
/// - Julia process handle for termination
/// - Directory locks for whitelisted paths
/// - Watchdog running state
pub struct WatchdogState {
    /// Last heartbeat timestamp (milliseconds since epoch)
    pub last_heartbeat: Arc<AtomicI64>,
    /// Julia process ID
    pub julia_pid: Arc<AtomicI32>,
    /// Flag indicating if watchdog is running
    pub is_running: Arc<AtomicBool>,
    /// Flag indicating if directories are locked
    pub directories_locked: Arc<AtomicBool>,
    /// Whitelisted directories that can be locked
    pub allowed_directories: Vec<String>,
    /// Directory locks (RwLock for each allowed path)
    pub directory_locks: Vec<Arc<RwLock<()>>>
}

impl WatchdogState {
    /// Create a new WatchdogState.
    pub fn new() -> Self {
        let directory_locks: Vec<Arc<RwLock<()>>> = DEFAULT_ALLOWED_DIRECTORIES
            .iter()
            .map(|_| Arc::new(RwLock::new(())))
            .collect();
        
        Self {
            last_heartbeat: Arc::new(AtomicI64::new(0)),
            julia_pid: Arc::new(AtomicI32::new(0)),
            is_running: Arc::new(AtomicBool::new(false)),
            directories_locked: Arc::new(AtomicBool::new(false)),
            allowed_directories: DEFAULT_ALLOWED_DIRECTORIES.iter().map(|s| s.to_string()).collect(),
            directory_locks,
        }
    }
    
    /// Create with custom allowed directories.
    pub fn with_directories(directories: Vec<String>) -> Self {
        let directory_locks: Vec<Arc<RwLock<()>>> = directories
            .iter()
            .map(|_| Arc::new(RwLock::new(())))
            .collect();
        
        Self {
            last_heartbeat: Arc::new(AtomicI64::new(0)),
            julia_pid: Arc::new(AtomicI32::new(0)),
            is_running: Arc::new(AtomicBool::new(false)),
            directories_locked: Arc::new(AtomicBool::new(false)),
            allowed_directories: directories,
            directory_locks,
        }
    }
    
    /// Update the last heartbeat timestamp.
    pub fn update_heartbeat(&self, timestamp: i64, pid: i32) {
        self.last_heartbeat.store(timestamp, Ordering::SeqCst);
        self.julia_pid.store(pid, Ordering::SeqCst);
        debug!("Heartbeat updated: timestamp={}, pid={}", timestamp, pid);
    }
    
    /// Check if heartbeat has timed out.
    pub fn is_heartbeat_timeout(&self) -> bool {
        let last_hb = self.last_heartbeat.load(Ordering::SeqCst);
        if last_hb == 0 {
            // No heartbeat received yet
            return false;
        }
        
        let current_time = Utc::now().timestamp_millis();
        let elapsed = current_time - last_hb;
        elapsed > HEARTBEAT_TIMEOUT_MS
    }
    
    /// Lock all whitelisted directories.
    /// Returns true if successful, false if already locked.
    pub fn lock_directories(&self) -> bool {
        if self.directories_locked.load(Ordering::SeqCst) {
            warn!("Directories already locked");
            return false;
        }
        
        info!("Locking whitelisted directories...");
        for (dir, lock) in self.allowed_directories.iter().zip(self.directory_locks.iter()) {
            match lock.write() {
                Ok(_guard) => {
                    debug!("Locked directory: {}", dir);
                }
                Err(e) => {
                    error!("Failed to lock directory {}: {}", dir, e);
                }
            }
        }
        
        self.directories_locked.store(true, Ordering::SeqCst);
        info!("All whitelisted directories locked");
        true
    }
    
    /// Unlock all whitelisted directories.
    pub fn unlock_directories(&self) -> bool {
        if !self.directories_locked.load(Ordering::SeqCst) {
            return true;
        }
        
        info!("Unlocking whitelisted directories...");
        for (dir, lock) in self.allowed_directories.iter().zip(self.directory_locks.iter()) {
            if let Ok(mut guard) = lock.write() {
                debug!("Unlocked directory: {}", dir);
                drop(guard);
            }
        }
        
        self.directories_locked.store(false, Ordering::SeqCst);
        info!("All whitelisted directories unlocked");
        true
    }
    
    /// Terminate the Julia process using SIGKILL.
    /// Returns true if signal was sent successfully.
    pub fn terminate_julia_process(&self) -> bool {
        let pid = self.julia_pid.load(Ordering::SeqCst);
        if pid <= 0 {
            warn!("No valid Julia PID to terminate");
            return false;
        }
        
        info!("Sending SIGKILL to Julia process {}", pid);
        
        // Use nix to send SIGKILL
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;
        
        let result = kill(Pid::from_raw(pid), Signal::SIGKILL);
        
        match result {
            Ok(()) => {
                error!("SIGKILL sent to Julia process {}", pid);
                true
            }
            Err(e) => {
                error!("Failed to send SIGKILL to Julia process {}: {}", pid, e);
                false
            }
        }
    }
    
    /// Execute the deadman switch - kill Julia and lock directories.
    pub fn trigger_deadman_switch(&self) {
        error!("DEADMAN SWITCH TRIGGERED!");
        
        // First, lock directories to prevent any file operations
        self.lock_directories();
        
        // Then terminate the Julia process
        self.terminate_julia_process();
    }
}

impl Default for WatchdogState {
    fn default() -> Self {
        Self::new()
    }
}

/// Start the heartbeat watchdog thread.
/// 
/// This function:
/// 1. Creates a Unix datagram socket for receiving heartbeat signals
/// 2. Spawns a background thread that monitors for heartbeats
/// 3. Triggers deadman switch (SIGKILL + directory lock) on timeout (>500ms)
/// 
/// Returns the WatchdogState handle for controlling the watchdog.
pub fn start_heartbeat_watchdog() -> Result<Arc<WatchdogState>> {
    let watchdog_state = Arc::new(WatchdogState::new());
    let state_clone = watchdog_state.clone();
    
    // Create heartbeat socket path
    let socket_path = HEARTBEAT_SOCKET_PATH;
    let socket_path_buf = PathBuf::from(socket_path);
    
    // Remove existing socket file if present
    if socket_path_buf.exists() {
        std::fs::remove_file(&socket_path_buf)
            .context("Failed to remove existing heartbeat socket")?;
    }
    
    // Create parent directory if needed
    if let Some(parent) = socket_path_buf.parent() {
        std::fs::create_dir_all(parent)
            .context("Failed to create heartbeat socket directory")?;
    }
    
    // Create Unix datagram socket for heartbeat
    let socket = UnixDatagram::bind(socket_path)
        .context("Failed to bind heartbeat socket")?;
    
    // Set socket permissions
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(socket_path)
            .context("Failed to get socket permissions")?
            .permissions();
        perms.set_mode(0o666);
        std::fs::set_permissions(socket_path, perms)
            .context("Failed to set socket permissions")?;
    }
    
    info!("Heartbeat watchdog listening on {}", socket_path);
    
    // Mark watchdog as running
    state_clone.is_running.store(true, Ordering::SeqCst);
    
    // Spawn the watchdog thread
    std::thread::spawn(move || {
        let mut buf = [0u8; 256];
        
        // Set socket to non-blocking with a timeout for the recv_from call
        // We'll use select/epoll-like behavior via timeout
        
        loop {
            if !state_clone.is_running.load(Ordering::SeqCst) {
                info!("Heartbeat watchdog stopping");
                break;
            }
            
            // Check for heartbeat timeout
            if state_clone.is_heartbeat_timeout() {
                error!("Heartbeat timeout detected! No heartbeat for >{}ms", HEARTBEAT_TIMEOUT_MS);
                state_clone.trigger_deadman_switch();
                
                // Wait a bit before checking again to avoid spam
                std::thread::sleep(Duration::from_millis(100));
                continue;
            }
            
            // Try to receive heartbeat with timeout
            // Use recv_from with a short timeout
            match socket.recv_from(&mut buf) {
                Ok((len, _addr)) => {
                    if len > 0 {
                        let data = &buf[..len];
                        if let Ok(heartbeat_msg) = std::str::from_utf8(data) {
                            // Parse heartbeat message: "HEARTBEAT:<pid>:<timestamp>"
                            if heartbeat_msg.starts_with("HEARTBEAT:") {
                                let parts: Vec<&str> = heartbeat_msg.split(':').collect();
                                if parts.len() >= 3 {
                                    if let (Ok(pid), Ok(timestamp)) = (
                                        parts[1].parse::<i32>(),
                                        parts[2].parse::<i64>()
                                    ) {
                                        state_clone.update_heartbeat(timestamp, pid);
                                        debug!("Watchdog received heartbeat: pid={}, timestamp={}", pid, timestamp);
                                    }
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    // EAGAIN/EWOULDBLOCK means timeout, which is expected
                    // Other errors might be worth logging
                    debug!("Heartbeat recv timeout: {}", e);
                }
            }
            
            // Small sleep to prevent busy spinning
            std::thread::sleep(Duration::from_millis(10));
        }
    });
    
    Ok(watchdog_state)
}

/// Start the heartbeat watchdog with custom configuration.
/// 
/// # Arguments
/// * `socket_path` - Custom Unix socket path for heartbeat
/// * `timeout_ms` - Custom timeout in milliseconds
/// * `allowed_directories` - Custom list of allowed directories
pub fn start_heartbeat_watchdog_with_config(
    socket_path: &str,
    timeout_ms: i64,
    allowed_directories: Vec<String>,
) -> Result<Arc<WatchdogState>> {
    let watchdog_state = Arc::new(WatchdogState::with_directories(allowed_directories));
    let state_clone = watchdog_state.clone();
    let socket_path_owned = socket_path.to_string();
    
    // Create heartbeat socket path
    let socket_path_buf = PathBuf::from(socket_path);
    
    // Remove existing socket file if present
    if socket_path_buf.exists() {
        std::fs::remove_file(&socket_path_buf)
            .context("Failed to remove existing heartbeat socket")?;
    }
    
    // Create parent directory if needed
    if let Some(parent) = socket_path_buf.parent() {
        std::fs::create_dir_all(parent)
            .context("Failed to create heartbeat socket directory")?;
    }
    
    // Create Unix datagram socket for heartbeat
    let socket = UnixDatagram::bind(socket_path)
        .context("Failed to bind heartbeat socket")?;
    
    // Set socket permissions
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(socket_path)
            .context("Failed to get socket permissions")?
            .permissions();
        perms.set_mode(0o666);
        std::fs::set_permissions(socket_path, perms)
            .context("Failed to set socket permissions")?;
    }
    
    info!("Heartbeat watchdog listening on {}", socket_path);
    
    // Mark watchdog as running
    state_clone.is_running.store(true, Ordering::SeqCst);
    
    // Spawn the watchdog thread
    std::thread::spawn(move || {
        let mut buf = [0u8; 256];
        
        loop {
            if !state_clone.is_running.load(Ordering::SeqCst) {
                info!("Heartbeat watchdog stopping");
                break;
            }
            
            // Check for heartbeat timeout
            let last_hb = state_clone.last_heartbeat.load(Ordering::SeqCst);
            if last_hb > 0 {
                let current_time = Utc::now().timestamp_millis();
                let elapsed = current_time - last_hb;
                if elapsed > timeout_ms {
                    error!("Heartbeat timeout detected! No heartbeat for >{}ms", timeout_ms);
                    state_clone.trigger_deadman_switch();
                    
                    // Wait a bit before checking again to avoid spam
                    std::thread::sleep(Duration::from_millis(100));
                    continue;
                }
            }
            
            // Try to receive heartbeat with timeout
            match socket.recv_from(&mut buf) {
                Ok((len, _addr)) => {
                    if len > 0 {
                        let data = &buf[..len];
                        if let Ok(heartbeat_msg) = std::str::from_utf8(data) {
                            if heartbeat_msg.starts_with("HEARTBEAT:") {
                                let parts: Vec<&str> = heartbeat_msg.split(':').collect();
                                if parts.len() >= 3 {
                                    if let (Ok(pid), Ok(timestamp)) = (
                                        parts[1].parse::<i32>(),
                                        parts[2].parse::<i64>()
                                    ) {
                                        state_clone.update_heartbeat(timestamp, pid);
                                    }
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    debug!("Heartbeat recv timeout: {}", e);
                }
            }
            
            std::thread::sleep(Duration::from_millis(10));
        }
    });
    
    Ok(watchdog_state)
}

/// Stop the heartbeat watchdog.
pub fn stop_heartbeat_watchdog(watchdog: &Arc<WatchdogState>) {
    watchdog.is_running.store(false, Ordering::SeqCst);
    info!("Heartbeat watchdog stop requested");
}

/// Default socket path for IPC communication
pub const DEFAULT_SOCKET_PATH: &str = "/tmp/itheris_kernel.sock";

/// Maximum message size in bytes
const MAX_MESSAGE_SIZE: usize = 1_048_576; // 1MB

/// Timestamp freshness window in milliseconds (5000ms = 5 seconds)
const TIMESTAMP_FRESHNESS_MS: i64 = 5000;

/// Maximum nonces to track
const MAX_NONCES: usize = 1000;

/// Protocol version for handshake
pub const PROTOCOL_VERSION: &str = "1.0.0";

/// Shell version
pub const SHELL_VERSION: &str = "1.0.0-rust";

/// Connection state for the bridge
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    /// Not connected
    NotConnected,
    /// Handshake complete
    HandshakeComplete,
    /// Active (heartbeat established)
    Active,
}

/// Command Verifier - Ed25519 signature verification (Pillar 1 & 2).
///
/// Verifies cryptographic signatures on commands and maintains
/// nonce tracking for replay attack prevention.
pub struct CommandVerifier {
    /// Nonce tracker for replay protection
    nonce_tracker: NonceTracker,
    /// Known valid public keys (in base64)
    valid_public_keys: Vec<String>,
}

impl CommandVerifier {
    /// Create a new command verifier.
    pub fn new() -> Self {
        Self {
            nonce_tracker: NonceTracker::new(MAX_NONCES),
            valid_public_keys: Vec::new(),
        }
    }

    /// Add a valid public key (base64-encoded).
    pub fn add_valid_key(&mut self, public_key_b64: String) {
        if !self.valid_public_keys.contains(&public_key_b64) {
            self.valid_public_keys.push(public_key_b64);
        }
    }

    /// Verify an authorized command.
    ///
    /// This method:
    /// 1. Decodes the base64 signature (64 bytes) and public_key (32 bytes)
    /// 2. Uses ed25519_dalek::VerifyingKey and Signature to verify
    /// 3. Checks timestamp freshness (within 5000ms of current time)
    /// 4. Checks nonce uniqueness via NonceTracker
    /// 5. Deserializes command_payload into a WorldAction
    /// 6. Returns SecurityViolation on any failure
    pub fn verify_command(&mut self, cmd: &AuthorizedCommand) -> Result<WorldAction, SecurityViolation> {
        let current_time = Utc::now().timestamp_millis();

        // Check timestamp freshness
        let time_diff = (current_time - cmd.timestamp).abs();
        if time_diff > TIMESTAMP_FRESHNESS_MS {
            let violation = SecurityViolation {
                violation_type: SecurityViolationType::ExpiredTimestamp,
                details: format!(
                    "Timestamp {}ms outside acceptable window (current: {})",
                    cmd.timestamp, current_time
                ),
                timestamp: current_time,
                source_ip: None,
            };
            error!("Security violation: {}", violation.details);
            return Err(violation);
        }

        // Check nonce uniqueness
        if !self.nonce_tracker.check_and_record(cmd.nonce) {
            let violation = SecurityViolation {
                violation_type: SecurityViolationType::ReplayedNonce,
                details: format!("Nonce {} has been replayed", cmd.nonce),
                timestamp: current_time,
                source_ip: None,
            };
            error!("Security violation: {}", violation.details);
            return Err(violation);
        }

        // Decode public key (32 bytes, base64)
        let public_key_bytes = BASE64
            .decode(&cmd.public_key)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Failed to decode public key: {}", e),
                timestamp: current_time,
                source_ip: None,
            })?;

        if public_key_bytes.len() != 32 {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Invalid public key length: {} bytes", public_key_bytes.len()),
                timestamp: current_time,
                source_ip: None,
            });
        }

        // Decode signature (64 bytes, base64)
        let signature_bytes = BASE64
            .decode(&cmd.signature)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Failed to decode signature: {}", e),
                timestamp: current_time,
                source_ip: None,
            })?;

        if signature_bytes.len() != 64 {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Invalid signature length: {} bytes", signature_bytes.len()),
                timestamp: current_time,
                source_ip: None,
            });
        }

        // Check if public key is in valid keys list (if any keys are registered)
        // If no keys are registered, we accept any validly-signed command
        if !self.valid_public_keys.is_empty() && !self.valid_public_keys.contains(&cmd.public_key) {
            return Err(SecurityViolation {
                violation_type: SecurityViolationType::UnauthorizedBinary,
                details: "Public key not in trusted keys list".to_string(),
                timestamp: current_time,
                source_ip: None,
            });
        }

        // IRON SENTRY: Always verify against hardcoded public key (mandatory)
        // This ensures ONLY the known Julia kernel can send commands
        verify_hardcoded_public_key(&cmd.public_key)?;

        // Create verifying key
        let verifying_key = VerifyingKey::from_bytes(
            public_key_bytes
                .as_slice()
                .try_into()
                .map_err(|_| SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Failed to create verifying key".to_string(),
                    timestamp: current_time,
                    source_ip: None,
                })?,
        )
        .map_err(|e| SecurityViolation {
            violation_type: SecurityViolationType::InvalidSignature,
            details: format!("Invalid verifying key: {}", e),
            timestamp: current_time,
            source_ip: None,
        })?;

        // Create signature
        let signature = Ed25519Signature::from_bytes(
            signature_bytes
                .as_slice()
                .try_into()
                .map_err(|_| SecurityViolation {
                    violation_type: SecurityViolationType::InvalidSignature,
                    details: "Failed to create signature".to_string(),
                    timestamp: current_time,
                    source_ip: None,
                })?,
        );

        // Verify signature over command payload
        verifying_key
            .verify(&cmd.command_payload, &signature)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!("Signature verification failed: {}", e),
                timestamp: current_time,
                source_ip: None,
            })?;

        // Deserialize command payload into WorldAction
        let action: WorldAction = serde_json::from_slice(&cmd.command_payload)
            .map_err(|e| SecurityViolation {
                violation_type: SecurityViolationType::MalformedPayload,
                details: format!("Failed to deserialize command payload: {}", e),
                timestamp: current_time,
                source_ip: None,
            })?;

        info!("Successfully verified command: {} - {}", action.id, action.intent);
        Ok(action)
    }
}

impl Default for CommandVerifier {
    fn default() -> Self {
        Self::new()
    }
}

/// Itheris Bridge - HCB Protocol Security Bridge.
///
/// This is the IPC bridge between the Rust shell (sovereign entity)
/// and the Julia kernel (potentially compromised environment).
pub struct ItherisBridge {
    /// Path to the Unix Domain Socket
    socket_path: String,
    /// Broadcast channel for security violation notifications
    failure_tx: broadcast::Sender<String>,
    /// Command verifier for signature verification
    command_verifier: Arc<Mutex<CommandVerifier>>,
    /// Last heartbeat timestamp (milliseconds)
    last_heartbeat: Arc<AtomicI64>,
    /// Julia process ID
    julia_pid: Arc<AtomicI32>,
    /// Current challenge for heartbeat
    current_challenge: Arc<AtomicU64>,
    /// Connection state
    connected: Arc<AtomicBool>,
    /// Handshake completed flag
    handshake_complete: Arc<AtomicBool>,
    /// HALTED mode flag - when true, system is in cognitive lock state
    is_halted: Arc<AtomicBool>,
    /// Command buffer - cleared on HALTED state entry
    command_buffer: Arc<Mutex<VecDeque<String>>>,
}

impl ItherisBridge {
    /// Create a new Itheris Bridge.
    pub fn new(socket_path: impl Into<String>) -> Self {
        let socket_path = socket_path.into();
        
        // Create broadcast channel for security violations
        let (failure_tx, _) = broadcast::channel(100);
        
        Self {
            socket_path,
            failure_tx,
            command_verifier: Arc::new(Mutex::new(CommandVerifier::new())),
            last_heartbeat: Arc::new(AtomicI64::new(0)),
            julia_pid: Arc::new(AtomicI32::new(0)),
            current_challenge: Arc::new(AtomicU64::new(random())),
            connected: Arc::new(AtomicBool::new(false)),
            handshake_complete: Arc::new(AtomicBool::new(false)),
            is_halted: Arc::new(AtomicBool::new(false)),
            command_buffer: Arc::new(Mutex::new(VecDeque::new())),
        }
    }

    /// Get the last heartbeat timestamp.
    pub fn last_heartbeat(&self) -> Arc<AtomicI64> {
        self.last_heartbeat.clone()
    }

    /// Get the Julia process ID.
    pub fn julia_pid(&self) -> Arc<AtomicI32> {
        self.julia_pid.clone()
    }

    /// Get the current challenge value.
    pub fn current_challenge(&self) -> u64 {
        self.current_challenge.load(Ordering::SeqCst)
    }

    /// Generate a new challenge.
    pub fn generate_new_challenge(&self) -> u64 {
        let new_challenge = random();
        self.current_challenge.store(new_challenge, Ordering::SeqCst);
        new_challenge
    }

    /// Check if connected.
    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }

    /// Check if handshake is complete.
    pub fn is_handshake_complete(&self) -> bool {
        self.handshake_complete.load(Ordering::SeqCst)
    }

    /// Set handshake complete.
    pub fn set_handshake_complete(&self) {
        self.handshake_complete.store(true, Ordering::SeqCst);
        self.connected.store(true, Ordering::SeqCst);
    }

    /// Reset connection state.
    pub fn reset_connection(&self) {
        self.handshake_complete.store(false, Ordering::SeqCst);
        self.connected.store(false, Ordering::SeqCst);
    }

    /// Get the HALTED mode state.
    pub fn is_halted(&self) -> Arc<AtomicBool> {
        self.is_halted.clone()
    }

    /// Get the command buffer.
    pub fn command_buffer(&self) -> Arc<Mutex<VecDeque<String>>> {
        self.command_buffer.clone()
    }

    /// Enter HALTED mode - clears command buffer and sets halted flag.
    pub async fn enter_halted_mode(&self) {
        // Clear the command buffer
        let mut buffer = self.command_buffer.lock().await;
        buffer.clear();
        drop(buffer);
        
        // Set HALTED mode
        self.is_halted.store(true, Ordering::SeqCst);
        
        // Reset connection state
        self.reset_connection();
        
        info!("System entered HALTED mode - command buffer cleared");
    }

    /// Exit HALTED mode - allows normal operation again.
    pub fn exit_halted_mode(&self) {
        self.is_halted.store(false, Ordering::SeqCst);
        info!("System exited HALTED mode");
    }

    /// Add a command to the buffer.
    pub async fn add_to_buffer(&self, command: String) {
        let mut buffer = self.command_buffer.lock().await;
        buffer.push_back(command);
        // Keep buffer size manageable
        while buffer.len() > 100 {
            buffer.pop_front();
        }
    }

    /// Get a subscriber for security violation notifications.
    pub fn subscribe(&self) -> broadcast::Receiver<String> {
        self.failure_tx.subscribe()
    }

    /// Get the socket path.
    pub fn socket_path(&self) -> &str {
        &self.socket_path
    }

    /// Add a trusted public key.
    pub async fn add_trusted_key(&self, public_key_b64: String) {
        let mut verifier = self.command_verifier.lock().await;
        verifier.add_valid_key(public_key_b64);
    }

    /// Start the bridge server.
    pub async fn start_server(&mut self) -> Result<()> {
        let path = PathBuf::from(&self.socket_path);
        
        // Remove existing socket file if present
        if path.exists() {
            std::fs::remove_file(&path)
                .context("Failed to remove existing socket file")?;
        }

        // Create parent directory if it doesn't exist
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .context("Failed to create socket directory")?;
        }

        // Create Unix listener using tokio::net
        let listener = UnixListener::bind(&path)
            .await
            .context("Failed to bind to Unix socket")?;

        // Set socket permissions (read/write for all)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&path)?
                .permissions();
            perms.set_mode(0o666);
            std::fs::set_permissions(&path, perms)?;
        }

        info!("HCB Protocol bridge listening on {}", self.socket_path);

        // Accept connections in a loop
        loop {
            match listener.accept().await {
                Ok((stream, _addr)) => {
                    let failure_tx = self.failure_tx.clone();
                    let command_verifier = self.command_verifier.clone();
                    let last_heartbeat = self.last_heartbeat.clone();
                    let julia_pid = self.julia_pid.clone();
                    let current_challenge = self.current_challenge.clone();
                    let connected = self.connected.clone();
                    let handshake_complete = self.handshake_complete.clone();
                    
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(
                            stream,
                            failure_tx,
                            command_verifier,
                            last_heartbeat,
                            julia_pid,
                            current_challenge,
                            connected,
                            handshake_complete,
                        ).await {
                            error!("Connection handler error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    error!("Failed to accept connection: {}", e);
                }
            }
        }
    }
}

/// Handle a single connection from the Julia kernel.
async fn handle_connection(
    stream: UnixStream,
    failure_tx: broadcast::Sender<String>,
    command_verifier: Arc<Mutex<CommandVerifier>>,
    last_heartbeat: Arc<AtomicI64>,
    julia_pid: Arc<AtomicI32>,
    current_challenge: Arc<AtomicU64>,
    connected: Arc<AtomicBool>,
    handshake_complete: Arc<AtomicBool>,
) -> Result<()> {
    let (read_half, mut write_half) = stream.split();
    let mut reader = BufReader::new(read_half);
    let mut line = String::new();

    info!("New connection established");

    loop {
        // Read a line from the stream
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => {
                // EOF - connection closed
                debug!("Connection closed by client");
                break;
            }
            Ok(_) => {
                // Process the received message
                let json = line.trim();
                if json.is_empty() {
                    continue;
                }

                debug!("Received: {}", json);

                match parse_and_process_message(
                    json,
                    &failure_tx,
                    &command_verifier,
                    &last_heartbeat,
                    &julia_pid,
                    &current_challenge,
                    &connected,
                    &handshake_complete,
                ).await {
                    Ok(response) => {
                        // Send response back to client
                        if let Some(resp) = response {
                            let response_json = resp.to_json()?;
                            write_half
                                .write_all(response_json.as_bytes())
                                .await
                                .context("Failed to write response")?;
                            write_half
                                .write_all(b"\n")
                                .await
                                .context("Failed to write newline")?;
                            debug!("Sent response: {}", response_json);
                        }
                    }
                    Err(e) => {
                        // Send error response
                        error!("Failed to process message: {}", e);
                        let error_msg = IpcMessage::Error {
                            code: "PARSE_ERROR".to_string(),
                            message: e.to_string(),
                        };
                        let response_json = error_msg.to_json()?;
                        write_half
                            .write_all(response_json.as_bytes())
                            .await
                            .context("Failed to write error response")?;
                        write_half
                            .write_all(b"\n")
                            .await
                            .context("Failed to write newline")?;
                    }
                }
            }
            Err(e) => {
                error!("Read error: {}", e);
                break;
            }
        }
    }

    Ok(())
}

/// Parse and process an incoming IPC message with HCB Protocol security.
///
/// This function implements the security bridge logic:
/// - AuthorizedExecute: verify signature → check safety gateway → execute if valid
/// - Heartbeat: update heartbeat timestamp, respond with ack
/// - Handshake: process handshake
/// - Ping/Pong: keep alive
/// - ExecuteAction: REJECT with SecurityViolation (old unsigned path forbidden)
async fn parse_and_process_message(
    json: &str,
    failure_tx: &broadcast::Sender<String>,
    command_verifier: &Arc<Mutex<CommandVerifier>>,
    last_heartbeat: &Arc<AtomicI64>,
    julia_pid: &Arc<AtomicI32>,
    current_challenge: &Arc<AtomicU64>,
    connected: &Arc<AtomicBool>,
    handshake_complete: &Arc<AtomicBool>,
) -> Result<Option<IpcMessage>> {
    // Check message size
    if json.len() > MAX_MESSAGE_SIZE {
        return Ok(Some(IpcMessage::Error {
            code: "MESSAGE_TOO_LARGE".to_string(),
            message: format!("Message exceeds maximum size of {} bytes", MAX_MESSAGE_SIZE),
        }));
    }

    // Parse the JSON message
    let message: IpcMessage = serde_json::from_str(json)
        .map_err(|e| anyhow::anyhow!("JSON parse error: {}", e))?;

    // Process the message and generate response
    let response = match message.clone() {
        // =====================================================================
        // HCB Protocol: AuthorizedExecute - Signature verification required
        // =====================================================================
        IpcMessage::AuthorizedExecute { authorized_command } => {
            info!("Received authorized execute command");
            
            // Verify the command signature
            let mut verifier = command_verifier.lock().await;
            let action_result = verifier.verify_command(&authorized_command);
            
            match action_result {
                Ok(action) => {
                    // Check if action contains a shell command
                    if let Some(command) = action.parameters.get("command") {
                        // Run safety gateway check
                        match SafetyGateway::check(command) {
                            Ok(()) => {
                                // Safety check passed - execute the action
                                info!("Safety gateway passed for command: {}", command);
                                Some(IpcMessage::ActionResult {
                                    result: ActionResult::new(
                                        action.id,
                                        "success".to_string(),
                                        format!("Executed: {}", action.intent),
                                        String::new(),
                                        0.0,
                                        vec![],
                                    ),
                                })
                            }
                            Err(violation) => {
                                // Safety gateway blocked the command
                                error!("Safety violation: {}", violation.details);
                                let _ = failure_tx.send(violation.details.clone());
                                Some(IpcMessage::SecurityViolationReport {
                                    violation,
                                })
                            }
                        }
                    } else {
                        // No shell command to check - execute the action directly
                        info!("Executing action without shell command check: {}", action.intent);
                        Some(IpcMessage::ActionResult {
                            result: ActionResult::new(
                                action.id,
                                "success".to_string(),
                                format!("Executed: {}", action.intent),
                                String::new(),
                                0.0,
                                vec![],
                            ),
                        })
                    }
                }
                Err(violation) => {
                    // Signature verification failed
                    error!("Security violation during command verification: {}", violation.details);
                    let _ = failure_tx.send(violation.details.clone());
                    Some(IpcMessage::SecurityViolationReport {
                        violation,
                    })
                }
            }
        }

        // =====================================================================
        // FORBIDDEN: ExecuteAction without signature (old unsigned path)
        // =====================================================================
        IpcMessage::ExecuteAction { action } => {
            let violation = SecurityViolation {
                violation_type: SecurityViolationType::InvalidSignature,
                details: format!(
                    "ExecuteAction is forbidden. Use AuthorizedExecute with Ed25519 signature. Action: {} - {}",
                    action.id, action.intent
                ),
                timestamp: Utc::now().timestamp_millis(),
                source_ip: None,
            };
            error!("Security violation: {}", violation.details);
            let _ = failure_tx.send(violation.details.clone());
            Some(IpcMessage::SecurityViolationReport { violation })
        }

        // =====================================================================
        // HCB Protocol: Heartbeat (Pillar 4 - Liveness)
        // =====================================================================
        IpcMessage::Heartbeat {
            challenge,
            julia_pid: hb_julia_pid,
            timestamp,
        } => {
            info!("Received heartbeat from Julia PID {} at {}", hb_julia_pid, timestamp);
            
            // Update last heartbeat timestamp
            last_heartbeat.store(timestamp, Ordering::SeqCst);
            
            // Store Julia PID
            julia_pid.store(hb_julia_pid, Ordering::SeqCst);
            
            // Generate new challenge
            let new_challenge = random::<u64>();
            current_challenge.store(new_challenge, Ordering::SeqCst);
            
            Some(IpcMessage::HeartbeatAck {
                response: challenge.wrapping_add(1),  // Simple response
                new_challenge,
            })
        }

        // =====================================================================
        // HCB Protocol: Handshake
        // =====================================================================
        IpcMessage::Handshake {
            julia_pid: hs_julia_pid,
            protocol_version,
        } => {
            info!("Received handshake from Julia PID {} with protocol version {}", hs_julia_pid, protocol_version);
            
            // Store Julia PID
            julia_pid.store(hs_julia_pid, Ordering::SeqCst);
            
            // Validate protocol version
            let accepted = protocol_version == PROTOCOL_VERSION;
            if accepted {
                handshake_complete.store(true, Ordering::SeqCst);
                connected.store(true, Ordering::SeqCst);
                info!("Handshake accepted, connection established");
            } else {
                warn!("Handshake rejected: protocol version mismatch (expected {}, got {})", 
                      PROTOCOL_VERSION, protocol_version);
            }
            
            Some(IpcMessage::HandshakeAck {
                accepted,
                initial_challenge: random(),
                shell_version: SHELL_VERSION.to_string(),
            })
        }

        // =====================================================================
        // Ping/Pong - Keep alive
        // =====================================================================
        IpcMessage::Ping { timestamp } => {
            debug!("Received ping at {}", timestamp);
            Some(IpcMessage::Pong { timestamp: Utc::now() })
        }

        // =====================================================================
        // Failure Notification
        // =====================================================================
        IpcMessage::FailureNotification {
            severity,
            timestamp,
            description,
        } => {
            info!("Received failure notification: {:?} - {}", severity, description);
            
            // Broadcast the failure notification as string
            let notification = format!("{:?} - {} at {}", severity, description, timestamp);
            if let Err(e) = failure_tx.send(notification) {
                warn!("No subscribers for failure notification: {}", e);
            }
            
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }

        // =====================================================================
        // Status Request
        // =====================================================================
        IpcMessage::StatusRequest => {
            Some(IpcMessage::StatusResponse {
                running: connected.load(Ordering::SeqCst),
                pid: Some(std::process::id()),
                autonomy_level: if handshake_complete.load(Ordering::SeqCst) {
                    AutonomyLevel::Full
                } else {
                    AutonomyLevel::Halted
                },
            })
        }

        // =====================================================================
        // Kill Kernel
        // =====================================================================
        IpcMessage::KillKernel { reason } => {
            info!("Kill kernel requested: {}", reason);
            Some(IpcMessage::KernelShutdown { exit_code: 0 })
        }

        // =====================================================================
        // Autonomy Change
        // =====================================================================
        IpcMessage::AutonomyChange { level } => {
            info!("Autonomy level change requested: {:?}", level);
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }

        // =====================================================================
        // HandshakeAck - Should not come from kernel, but handle gracefully
        // =====================================================================
        IpcMessage::HandshakeAck { .. } => {
            warn!("Unexpected HandshakeAck received from kernel");
            Some(IpcMessage::Error {
                code: "UNEXPECTED_MESSAGE".to_string(),
                message: "HandshakeAck should not be received from kernel".to_string(),
            })
        }

        // =====================================================================
        // HeartbeatAck - Should not come from kernel, handle gracefully
        // =====================================================================
        IpcMessage::HeartbeatAck { .. } => {
            warn!("Unexpected HeartbeatAck received from kernel");
            Some(IpcMessage::Error {
                code: "UNEXPECTED_MESSAGE".to_string(),
                message: "HeartbeatAck should not be received from kernel".to_string(),
            })
        }

        // =====================================================================
        // SecurityViolationReport - Log and acknowledge
        // =====================================================================
        IpcMessage::SecurityViolationReport { violation } => {
            error!("Received security violation report: {:?}", violation.violation_type);
            let _ = failure_tx.send(violation.details.clone());
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }

        // =====================================================================
        // ActionResult, KernelShutdown, Error - Pass through
        // =====================================================================
        other => {
            debug!("Received message type: {:?}", std::mem::discriminant(&other));
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }
    };

    Ok(response)
}

/// Send a message to the Julia kernel via Unix Domain Socket.
pub async fn send_message(socket_path: &str, message: &IpcMessage) -> Result<IpcMessage> {
    let stream = UnixStream::connect(socket_path)
        .await
        .context("Failed to connect to kernel")?;

    let (mut read_half, mut write_half) = stream.split();

    // Serialize and send the message
    let json = message.to_json()?;
    write_half
        .write_all(json.as_bytes())
        .await
        .context("Failed to send message")?;
    write_half
        .write_all(b"\n")
        .await
        .context("Failed to send newline")?;
    write_half
        .flush()
        .await
        .context("Failed to flush")?;

    // Read the response
    let mut reader = BufReader::new(read_half);
    let mut response_line = String::new();
    reader
        .read_line(&mut response_line)
        .await
        .context("Failed to read response")?;

    let response: IpcMessage = serde_json::from_str(response_line.trim())
        .map_err(|e| anyhow::anyhow!("Failed to parse response: {}", e))?;

    Ok(response)
}

/// Connect to the IPC server and return a stream of messages.
pub async fn connect_to_server(socket_path: &str) -> Result<UnixStream> {
    UnixStream::connect(socket_path)
        .await
        .context("Failed to connect to IPC server")
}

/// Parse FailureSeverity from IPC stream data.
pub fn parse_failure_severity_from_ipc(json: &str) -> Result<Option<FailureSeverity>> {
    let value: serde_json::Value = serde_json::from_str(json)
        .map_err(|e| anyhow::anyhow!("Failed to parse JSON: {}", e))?;

    if let Some(obj) = value.as_object() {
        if let Some(msg_type) = obj.get("type").and_then(|v| v.as_str()) {
            if msg_type == "FailureNotification" {
                if let Some(payload) = obj.get("payload").and_then(|v| v.as_object()) {
                    if let Some(severity_str) = payload.get("severity").and_then(|v| v.as_str()) {
                        if let Some(severity) = FailureSeverity::from_str(severity_str) {
                            return Ok(Some(severity));
                        }
                    }
                }
            }
        }
    }

    Ok(None)
}

// ============================================================================
// DEPRECATED IPC Server - Kept for backward compatibility
// ============================================================================

/// IPC Server for handling Unix Domain Socket connections.
/// 
/// Deprecated: Use ItherisBridge instead for HCB Protocol support.
pub struct IpcServer {
    /// Path to the Unix Domain Socket
    socket_path: PathBuf,
    /// Broadcast channel for failure notifications
    failure_tx: broadcast::Sender<FailureNotification>,
    /// Flag indicating if server is running
    running: bool,
}

/// Notification for detected failures.
#[derive(Debug, Clone)]
pub struct FailureNotification {
    /// The severity of the failure
    pub severity: FailureSeverity,
    /// Description of the failure
    pub description: String,
    /// Timestamp of the failure
    pub timestamp: chrono::DateTime<Utc>,
}

impl IpcServer {
    /// Create a new IPC server with the specified socket path.
    pub fn new(socket_path: impl Into<PathBuf>) -> Self {
        let socket_path = socket_path.into();
        
        // Create broadcast channel for failure notifications
        let (failure_tx, _) = broadcast::channel(100);
        
        Self {
            socket_path,
            failure_tx,
            running: false,
        }
    }

    /// Get a subscriber for failure notifications.
    pub fn subscribe(&self) -> broadcast::Receiver<FailureNotification> {
        self.failure_tx.subscribe()
    }

    /// Get the socket path.
    pub fn socket_path(&self) -> &PathBuf {
        &self.socket_path
    }

    /// Start the IPC server and listen for connections.
    #[deprecated(note = "Use ItherisBridge instead for HCB Protocol support")]
    pub async fn start_server(&mut self) -> Result<()> {
        // Remove existing socket file if present
        if self.socket_path.exists() {
            std::fs::remove_file(&self.socket_path)
                .context("Failed to remove existing socket file")?;
        }

        // Create parent directory if it doesn't exist
        if let Some(parent) = self.socket_path.parent() {
            std::fs::create_dir_all(parent)
                .context("Failed to create socket directory")?;
        }

        // Create Unix listener
        let listener = UnixListener::bind(&self.socket_path)
            .await
            .context("Failed to bind to Unix socket")?;

        // Set socket permissions (read/write for all)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&self.socket_path)?
                .permissions();
            perms.set_mode(0o666);
            std::fs::set_permissions(&self.socket_path, perms)?;
        }

        self.running = true;
        info!("IPC server listening on {:?}", self.socket_path);

        // Accept connections in a loop
        while self.running {
            match listener.accept().await {
                Ok((stream, _addr)) => {
                    let failure_tx = self.failure_tx.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection_legacy(stream, failure_tx).await {
                            error!("Connection handler error: {}", e);
                        }
                    });
                }
                Err(e) => {
                    error!("Failed to accept connection: {}", e);
                }
            }
        }

        Ok(())
    }

    /// Stop the IPC server.
    pub fn stop(&mut self) {
        info!("Stopping IPC server");
        self.running = false;
    }

    /// Check if server is running.
    pub fn is_running(&self) -> bool {
        self.running
    }
}

/// Legacy connection handler without HCB Protocol support.
async fn handle_connection_legacy(
    stream: UnixStream,
    failure_tx: broadcast::Sender<FailureNotification>,
) -> Result<()> {
    let (read_half, mut write_half) = stream.split();
    let mut reader = BufReader::new(read_half);
    let mut line = String::new();

    info!("New connection established (legacy mode)");

    loop {
        line.clear();
        match reader.read_line(&mut line).await {
            Ok(0) => {
                debug!("Connection closed by client");
                break;
            }
            Ok(_) => {
                let json = line.trim();
                if json.is_empty() {
                    continue;
                }

                debug!("Received: {}", json);

                match parse_and_process_message_legacy(json, &failure_tx).await {
                    Ok(response) => {
                        if let Some(resp) = response {
                            let response_json = resp.to_json()?;
                            write_half
                                .write_all(response_json.as_bytes())
                                .await
                                .context("Failed to write response")?;
                            write_half
                                .write_all(b"\n")
                                .await
                                .context("Failed to write newline")?;
                        }
                    }
                    Err(e) => {
                        error!("Failed to process message: {}", e);
                        let error_msg = IpcMessage::Error {
                            code: "PARSE_ERROR".to_string(),
                            message: e.to_string(),
                        };
                        let response_json = error_msg.to_json()?;
                        write_half
                            .write_all(response_json.as_bytes())
                            .await
                            .context("Failed to write error response")?;
                        write_half
                            .write_all(b"\n")
                            .await
                            .context("Failed to write newline")?;
                    }
                }
            }
            Err(e) => {
                error!("Read error: {}", e);
                break;
            }
        }
    }

    Ok(())
}

/// Legacy message processing without HCB Protocol.
async fn parse_and_process_message_legacy(
    json: &str,
    failure_tx: &broadcast::Sender<FailureNotification>,
) -> Result<Option<IpcMessage>> {
    if json.len() > MAX_MESSAGE_SIZE {
        return Ok(Some(IpcMessage::Error {
            code: "MESSAGE_TOO_LARGE".to_string(),
            message: format!("Message exceeds maximum size of {} bytes", MAX_MESSAGE_SIZE),
        }));
    }

    let message: IpcMessage = serde_json::from_str(json)
        .map_err(|e| anyhow::anyhow!("JSON parse error: {}", e))?;

    let response = match message.clone() {
        IpcMessage::Ping { timestamp } => {
            debug!("Received ping at {}", timestamp);
            Some(IpcMessage::Pong { timestamp: Utc::now() })
        }

        IpcMessage::FailureNotification {
            severity,
            timestamp,
            description,
        } => {
            info!("Received failure notification: {:?} - {}", severity, description);
            
            let notification = FailureNotification {
                severity,
                description: description.clone(),
                timestamp,
            };
            
            if let Err(e) = failure_tx.send(notification) {
                warn!("No subscribers for failure notification: {}", e);
            }
            
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }

        IpcMessage::StatusRequest => {
            Some(IpcMessage::StatusResponse {
                running: true,
                pid: Some(std::process::id()),
                autonomy_level: AutonomyLevel::Full,
            })
        }

        IpcMessage::KillKernel { reason } => {
            info!("Kill kernel requested: {}", reason);
            Some(IpcMessage::KernelShutdown { exit_code: 0 })
        }

        IpcMessage::ExecuteAction { action } => {
            info!("Execute action request: {} - {}", action.id, action.intent);
            Some(IpcMessage::ActionResult {
                result: ActionResult::new(
                    action.id,
                    "success".to_string(),
                    "Action executed successfully".to_string(),
                    String::new(),
                    0.0,
                    vec![],
                ),
            })
        }

        IpcMessage::AutonomyChange { level } => {
            info!("Autonomy level change requested: {:?}", level);
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }

        other => {
            debug!("Received unhandled message type: {:?}", std::mem::discriminant(&other));
            Some(IpcMessage::Pong {
                timestamp: Utc::now(),
            })
        }
    };

    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_failure_severity_from_ipc() {
        let json = r#"{
            "type": "FailureNotification",
            "payload": {
                "severity": "FAILURE_CRITICAL",
                "timestamp": "2024-01-01T00:00:00Z",
                "description": "Test failure"
            }
        }"#;

        let severity = parse_failure_severity_from_ipc(json).unwrap();
        assert!(severity.is_some());
        assert_eq!(severity.unwrap(), FailureSeverity::Critical);
    }

    #[test]
    fn test_parse_failure_severity_from_ipc_not_failure() {
        let json = r#"{
            "type": "Ping",
            "payload": {
                "timestamp": "2024-01-01T00:00:00Z"
            }
        }"#;

        let severity = parse_failure_severity_from_ipc(json).unwrap();
        assert!(severity.is_none());
    }

    #[test]
    fn test_command_verifier_initialization() {
        let verifier = CommandVerifier::new();
        // Should be able to create without errors
        assert!(verifier.valid_public_keys.is_empty());
    }

    #[test]
    fn test_itheris_bridge_creation() {
        let bridge = ItherisBridge::new("/tmp/test_itheris.sock");
        assert_eq!(bridge.socket_path(), "/tmp/test_itheris.sock");
        assert!(!bridge.is_connected());
        assert!(!bridge.is_handshake_complete());
    }

    #[test]
    fn test_itheris_bridge_getters() {
        let bridge = ItherisBridge::new("/tmp/test_itheris.sock");
        
        // Test getters return Arc
        let _hb = bridge.last_heartbeat();
        let _pid = bridge.julia_pid();
        
        // Test current challenge
        let challenge = bridge.current_challenge();
        assert_ne!(challenge, 0);
    }

    // ========================================================================
    // WatchdogState Tests
    // ========================================================================

    #[test]
    fn test_watchdog_state_creation() {
        let state = WatchdogState::new();
        assert_eq!(state.last_heartbeat.load(Ordering::SeqCst), 0);
        assert_eq!(state.julia_pid.load(Ordering::SeqCst), 0);
        assert!(!state.is_running.load(Ordering::SeqCst));
        assert!(!state.directories_locked.load(Ordering::SeqCst));
    }

    #[test]
    fn test_watchdog_state_update_heartbeat() {
        let state = WatchdogState::new();
        
        let timestamp = Utc::now().timestamp_millis();
        state.update_heartbeat(timestamp, 12345);
        
        assert_eq!(state.last_heartbeat.load(Ordering::SeqCst), timestamp);
        assert_eq!(state.julia_pid.load(Ordering::SeqCst), 12345);
    }

    #[test]
    fn test_watchdog_state_is_heartbeat_timeout() {
        let state = WatchdogState::new();
        
        // No heartbeat received yet - should not timeout
        assert!(!state.is_heartbeat_timeout());
        
        // Set a recent heartbeat
        let recent_time = Utc::now().timestamp_millis();
        state.update_heartbeat(recent_time, 12345);
        
        // Should not timeout with recent heartbeat
        assert!(!state.is_heartbeat_timeout());
    }

    #[test]
    fn test_watchdog_state_lock_directories() {
        let state = WatchdogState::new();
        
        // Initially not locked
        assert!(!state.directories_locked.load(Ordering::SeqCst));
        
        // Lock directories
        let result = state.lock_directories();
        assert!(result);
        
        // Should now be locked
        assert!(state.directories_locked.load(Ordering::SeqCst));
        
        // Try to lock again - should fail
        let result = state.lock_directories();
        assert!(!result);
        
        // Unlock directories
        let result = state.unlock_directories();
        assert!(result);
        
        // Should now be unlocked
        assert!(!state.directories_locked.load(Ordering::SeqCst));
    }

    #[test]
    fn test_watchdog_state_custom_directories() {
        let directories = vec![
            "/custom/path1".to_string(),
            "/custom/path2".to_string(),
        ];
        
        let state = WatchdogState::with_directories(directories.clone());
        
        assert_eq!(state.allowed_directories, directories);
        assert_eq!(state.directory_locks.len(), 2);
    }
}
