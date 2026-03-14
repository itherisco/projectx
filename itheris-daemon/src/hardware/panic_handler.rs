//! # Panic Handler Registration
//!
//! Registers the kill chain as the panic handler and handles critical signals
//! (SIGSEGV, SIGBUS, SIGFPE). Logs panic information and captures crash dumps
//! before executing the kill chain.
//!
//! ## Integration Points
//!
//! - Registers with `std::panic::set_hook()` for Rust panics
//! - Sets up signal handlers for SIGSEGV, SIGBUS, SIGFPE
//! - Integrates with watchdog (WDT fires NMI)
//! - Logs crash information to persistent storage

use crate::hardware::kill_chain;
use chrono::Utc;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// Panic handler initialized flag
static PANIC_HANDLER_INITIALIZED: AtomicBool = AtomicBool::new(false);

/// Crash dump directory
const CRASH_DUMP_DIR: &str = "/var/log/itheris/crashes";

/// Crash information structure
#[derive(Debug, Clone)]
pub struct CrashInfo {
    /// Timestamp of the crash
    pub timestamp: String,
    /// Unix timestamp
    pub unix_time: u64,
    /// Type of crash (panic, segfault, bus error, etc.)
    pub crash_type: String,
    /// Panic message if available
    pub message: Option<String>,
    /// Location if available
    pub location: Option<String>,
    /// Stack trace if available
    pub stack_trace: Option<String>,
    /// Process ID
    pub pid: u32,
    /// Memory stats at crash time
    pub memory_stats: Option<String>,
}

impl CrashInfo {
    /// Create a new crash info from a panic
    pub fn from_panic(info: &std::panic::PanicInfo) -> Self {
        let timestamp = Utc::now().format("%Y-%m-%d %H:%M:%S%.3f UTC").to_string();
        let unix_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let message = info.payload()
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned());
        
        let location = info.location()
            .map(|loc| format!("{}:{}:{}", loc.file(), loc.line(), loc.column()));
        
        let pid = std::process::id();
        
        CrashInfo {
            timestamp,
            unix_time,
            crash_type: "panic".to_string(),
            message,
            location,
            stack_trace: None,
            pid,
            memory_stats: None,
        }
    }
    
    /// Create crash info from signal
    pub fn from_signal(signal_name: &str) -> Self {
        let timestamp = Utc::now().format("%Y-%m-%d %H:%M:%S%.3f UTC").to_string();
        let unix_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        let pid = std::process::id();
        
        CrashInfo {
            timestamp,
            unix_time,
            crash_type: signal_name.to_string(),
            message: None,
            location: None,
            stack_trace: None,
            pid,
            memory_stats: None,
        }
    }
    
    /// Convert to string for logging
    pub fn to_log_string(&self) -> String {
        let mut s = format!(
            "=== CRASH REPORT ===\n\
             Timestamp: {}\n\
             Unix Time: {}\n\
             Crash Type: {}\n\
             PID: {}\n",
            self.timestamp, self.unix_time, self.crash_type, self.pid
        );
        
        if let Some(ref msg) = self.message {
            s.push_str(&format!("Message: {}\n", msg));
        }
        
        if let Some(ref loc) = self.location {
            s.push_str(&format!("Location: {}\n", loc));
        }
        
        if let Some(ref trace) = self.stack_trace {
            s.push_str(&format!("Stack Trace:\n{}\n", trace));
        }
        
        if let Some(ref mem) = self.memory_stats {
            s.push_str(&format!("Memory Stats:\n{}\n", mem));
        }
        
        s.push_str("====================\n");
        
        s
    }
}

/// Initialize the crash dump directory
fn ensure_crash_dir() -> Result<PathBuf, std::io::Error> {
    let path = PathBuf::from(CRASH_DUMP_DIR);
    
    if !path.exists() {
        fs::create_dir_all(&path)?;
    }
    
    Ok(path)
}

/// Write crash dump to persistent storage
pub fn write_crash_dump(crash_info: &CrashInfo) -> Option<PathBuf> {
    // Ensure crash directory exists
    let crash_dir = match ensure_crash_dir() {
        Ok(dir) => dir,
        Err(e) => {
            eprintln!("[PANIC HANDLER] Failed to create crash directory: {}", e);
            return None;
        }
    };
    
    // Generate filename
    let filename = format!(
        "crash_{}_{}.log",
        crash_info.crash_type,
        crash_info.unix_time
    );
    
    let filepath = crash_dir.join(&filename);
    
    // Write crash information
    match OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&filepath)
    {
        Ok(mut file) => {
            let content = crash_info.to_log_string();
            if let Err(e) = file.write_all(content.as_bytes()) {
                eprintln!("[PANIC HANDLER] Failed to write crash dump: {}", e);
                return None;
            }
            
            log::info!("📝 Crash dump written to: {:?}", filepath);
            Some(filepath)
        }
        Err(e) => {
            eprintln!("[PANIC HANDLER] Failed to create crash dump file: {}", e);
            None
        }
    }
}

/// The main panic handler callback
/// 
/// This is called when a panic occurs. It:
/// 1. Logs panic information
/// 2. Writes crash dump to persistent storage
/// 3. Executes the kill chain
fn panic_handler_impl(info: &std::panic::PanicInfo) {
    // Create crash info
    let crash_info = CrashInfo::from_panic(info);
    
    // Log to stderr first (most reliable during panic)
    let _ = writeln!(std::io::stderr(), "{}", crash_info.to_log_string());
    
    // Write crash dump
    let dump_path = write_crash_dump(&crash_info);
    
    // Log via the logging system if possible
    if let Some(ref path) = dump_path {
        log::error!("💥 PANIC - Crash dump saved to: {:?}", path);
    } else {
        log::error!("💥 PANIC - Failed to save crash dump");
    }
    
    if let Some(ref msg) = crash_info.message {
        log::error!("💥 PANIC: {}", msg);
    }
    
    if let Some(ref loc) = crash_info.location {
        log::error!("💥 Location: {}", loc);
    }
    
    log::error!("💥 Executing kill chain...");
    
    // Execute the kill chain
    // We spawn a thread because we can't safely execute it in the panic context
    kill_chain::spawn_kill_chain_thread();
    
    // Give the thread a moment to start
    std::thread::sleep(std::time::Duration::from_millis(100));
}

/// Register the panic handler
/// 
/// This sets up:
/// 1. std::panic::set_hook() for Rust panics
/// 2. Signal handlers for SIGSEGV, SIGBUS, SIGFPE
pub fn register_panic_handler() -> Result<(), String> {
    if PANIC_HANDLER_INITIALIZED.load(Ordering::SeqCst) {
        log::warn!("⚠️ Panic handler already registered");
        return Ok(());
    }
    
    log::info!("🛡️ Registering panic handler...");
    
    // Register the panic hook
    std::panic::set_hook(Box::new(|info| {
        panic_handler_impl(info);
    }));
    
    // Register signal handlers (Unix only)
    #[cfg(unix)]
    {
        unsafe {
            // Setup SIGSEGV handler
            let sigsegv_handler: libc::sighandler_t = transmute(signal_handler::<{ libc::SIGSEGV }> as *const ());
            libc::signal(libc::SIGSEGV, sigsegv_handler);
            
            // Setup SIGBUS handler
            let sigbus_handler: libc::sighandler_t = transmute(signal_handler::<{ libc::SIGBUS }> as *const ());
            libc::signal(libc::SIGBUS, sigbus_handler);
            
            // Setup SIGFPE handler
            let sigfpe_handler: libc::sighandler_t = transmute(signal_handler::<{ libc::SIGFPE }> as *const ());
            libc::signal(libc::SIGFPE, sigfpe_handler);
        }
    }
    
    PANIC_HANDLER_INITIALIZED.store(true, Ordering::SeqCst);
    
    log::info!("✅ Panic handler registered successfully");
    Ok(())
}

/// Signal handler for critical signals
#[cfg(unix)]
unsafe fn signal_handler<const SIG: i32>(_signum: i32) {
    // Create crash info from signal
    let signal_name = match SIG {
        libc::SIGSEGV => "SIGSEGV",
        libc::SIGBUS => "SIGBUS",
        libc::SIGFPE => "SIGFPE",
        _ => "UNKNOWN",
    };
    
    let crash_info = CrashInfo::from_signal(signal_name);
    
    // Log to stderr
    let _ = writeln!(std::io::stderr(), "{}", crash_info.to_log_string());
    
    // Write crash dump
    let dump_path = write_crash_dump(&crash_info);
    
    if let Some(ref path) = dump_path {
        let _ = writeln!(std::io::stderr(), "Crash dump saved to: {:?}", path);
    }
    
    // Execute kill chain
    kill_chain::spawn_kill_chain_thread();
    
    // Give the thread a moment to start
    std::thread::sleep(std::time::Duration::from_millis(100));
    
    // Exit with error code
    std::process::exit(1);
}

/// Check if panic handler is registered
pub fn is_panic_handler_registered() -> bool {
    PANIC_HANDLER_INITIALIZED.load(Ordering::SeqCst)
}

/// Get list of recent crash dumps
pub fn get_recent_crashes() -> Vec<PathBuf> {
    let crash_dir = match ensure_crash_dir() {
        Ok(dir) => dir,
        Err(_) => return Vec::new(),
    };
    
    let mut crashes = Vec::new();
    
    if let Ok(entries) = fs::read_dir(&crash_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "log").unwrap_or(false) {
                if let Ok(metadata) = fs::metadata(&path) {
                    if let Ok(modified) = metadata.modified() {
                        // Only include crashes from last 24 hours
                        let now = SystemTime::now();
                        if let Ok(duration) = now.duration_since(modified) {
                            if duration.as_secs() < 86400 {
                                crashes.push(path);
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Sort by modification time (newest first)
    crashes.sort_by(|a, b| {
        let a_time = fs::metadata(a).and_then(|m| m.modified()).ok();
        let b_time = fs::metadata(b).and_then(|m| m.modified()).ok();
        
        match (a_time, b_time) {
            (Some(at), Some(bt)) => bt.cmp(&at),
            _ => std::cmp::Ordering::Equal,
        }
    });
    
    crashes
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_crash_info_creation() {
        let crash_info = CrashInfo::from_signal("SIGSEGV");
        
        assert_eq!(crash_info.crash_type, "SIGSEGV");
        assert!(!crash_info.timestamp.is_empty());
        assert!(crash_info.pid > 0);
    }
    
    #[test]
    fn test_crash_info_to_string() {
        let crash_info = CrashInfo::from_signal("SIGSEGV");
        
        let log_str = crash_info.to_log_string();
        assert!(log_str.contains("CRASH REPORT"));
        assert!(log_str.contains("SIGSEGV"));
    }
    
    #[test]
    fn test_panic_handler_initial_state() {
        // Reset for test
        PANIC_HANDLER_INITIALIZED.store(false, Ordering::SeqCst);
        
        assert!(!is_panic_handler_registered());
    }
}
