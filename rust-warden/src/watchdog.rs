//! Watchdog Timer Module
//!
//! This module provides hardware watchdog timer functionality for
//! fail-closed protection of the Julia Digital Brain.

use crate::HypervisorError;

/// Watchdog error types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WatchdogError {
    /// Watchdog not available
    NotAvailable,
    /// MSR access failed
    MsrAccessFailed,
    /// Configuration failed
    ConfigFailed,
    /// Kick failed
    KickFailed,
}

/// Watchdog type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WatchdogType {
    /// Intel PATROL
    Patrol,
    /// AMD watchdog
    Amd,
    /// Software watchdog
    Software,
    /// None available
    None,
}

/// PATROL Watchdog MSR addresses
mod patrol_msr {
    pub const WDT_CONTROL: u32 = 0x123B;
    pub const WDT_COUNT: u32 = 0x123C;
    pub const WDT_CONFIG: u32 = 0x123D;
    pub const WDT_STATUS: u32 = 0x123E;
    
    // Control bits
    pub const CTRL_ENABLE: u64 = 0x01;
    pub const CTRL_STARTS: u64 = 0x02;
    pub const CTRL_TRIGGER: u64 = 0x04;
    pub const CTRL_PRETIMEOUT: u64 = 0x08;
    pub const CTRL_BIOS_LOCK: u64 = 0x80;
}

/// Julia heartbeat information
#[derive(Debug)]
pub struct JuliaHeartbeat {
    /// Last heartbeat timestamp (TSC)
    last_heartbeat: u64,
    /// Expected interval in milliseconds
    expected_interval_ms: u32,
    /// Missed heartbeat count
    missed_count: u32,
}

impl JuliaHeartbeat {
    /// Create new heartbeat monitor
    pub fn new(interval_ms: u32) -> Self {
        Self {
            last_heartbeat: 0,
            expected_interval_ms: interval_ms,
            missed_count: 0,
        }
    }

    /// Record heartbeat from Julia
    pub fn record_heartbeat(&mut self) {
        self.last_heartbeat = unsafe { x86_64::instructions::rdtsc() };
        self.missed_count = 0;
    }

    /// Check if Julia is alive
    pub fn check_alive(&mut self) -> bool {
        let now = unsafe { x86_64::instructions::rdtsc() };
        
        if self.last_heartbeat == 0 {
            return true; // No heartbeat yet
        }
        
        // Simplified TSC to ms conversion
        // In real implementation, use TSC frequency
        let tsc_per_ms = 3_000_000; // Approximate for 3GHz CPU
        let elapsed_ms = (now - self.last_heartbeat) / tsc_per_ms;
        
        if elapsed_ms > self.expected_interval_ms as u64 + 100 {
            self.missed_count += 1;
            println!("[HEARTBEAT] Missed: count={}, elapsed={}ms", 
                self.missed_count, elapsed_ms);
            false
        } else {
            true
        }
    }

    /// Get missed count
    pub fn missed_count(&self) -> u32 {
        self.missed_count
    }

    /// Reset heartbeat
    pub fn reset(&mut self) {
        self.last_heartbeat = 0;
        self.missed_count = 0;
    }
}

/// Watchdog configuration
pub struct WatchdogConfig {
    /// Watchdog timeout in milliseconds
    pub timeout_ms: u32,
    /// Kick interval in milliseconds
    pub kick_interval_ms: u32,
    /// Pre-timeout notification interval (ms)
    pub pretimeout_ms: u32,
    /// Enable GPIO lockdown on timeout
    pub enable_lockdown: bool,
}

impl Default for WatchdogConfig {
    fn default() -> Self {
        Self {
            timeout_ms: 500,
            kick_interval_ms: 400,
            pretimeout_ms: 100,
            enable_lockdown: true,
        }
    }
}

/// Watchdog timer
pub struct Watchdog {
    /// Watchdog type
    watchdog_type: WatchdogType,
    /// Configuration
    config: WatchdogConfig,
    /// Running state
    running: bool,
    /// Last kick time
    last_kick: u64,
    /// Julia heartbeat monitor
    heartbeat: JuliaHeartbeat,
}

impl Watchdog {
    /// Create new watchdog with specified timeout
    pub fn new(timeout_ms: u32) -> Result<Self, HypervisorError> {
        let config = WatchdogConfig {
            timeout_ms,
            kick_interval_ms: (timeout_ms as f32 * 0.8) as u32,
            pretimeout_ms: 100,
            enable_lockdown: true,
        };
        
        // Detect watchdog type
        let watchdog_type = Self::detect_watchdog();
        
        let mut wdt = Self {
            watchdog_type,
            config,
            running: false,
            last_kick: 0,
            heartbeat: JuliaHeartbeat::new(500),
        };
        
        // Initialize hardware watchdog
        if let Err(e) = wdt.init_hardware() {
            println!("[WDT] Hardware watchdog not available: {:?}, using software", e);
            wdt.watchdog_type = WatchdogType::Software;
        } else {
            wdt.running = true;
            println!("[WDT] Intel PATROL watchdog initialized ({}ms timeout)", timeout_ms);
        }
        
        Ok(wdt)
    }

    /// Detect available watchdog
    fn detect_watchdog() -> WatchdogType {
        // Check for Intel PATROL
        if Self::check_patrol_present() {
            return WatchdogType::Patrol;
        }
        
        // Check AMD
        if Self::check_amd_present() {
            return WatchdogType::Amd;
        }
        
        WatchdogType::Software
    }

    /// Check for Intel PATROL
    fn check_patrol_present() -> bool {
        // In real implementation, check via ACPI
        // For now, return false (no hardware watchdog in simulation)
        false
    }

    /// Check for AMD watchdog
    fn check_amd_present() -> bool {
        // Check AMD watchdog MSR
        false
    }

    /// Initialize hardware watchdog
    fn init_hardware(&mut self) -> Result<(), WatchdogError> {
        match self.watchdog_type {
            WatchdogType::Patrol => self.init_patrol(),
            WatchdogType::Amd => self.init_amd(),
            WatchdogType::Software | WatchdogType::None => {
                Err(WatchdogError::NotAvailable)
            }
        }
    }

    /// Initialize Intel PATROL
    fn init_patrol(&self) -> Result<(), WatchdogError> {
        // In real implementation:
        // 1. Check if BIOS has locked the watchdog
        // 2. Configure timeout
        // 3. Enable watchdog
        
        println!("[WDT] PATROL: Would configure timeout={}ms", self.config.timeout_ms);
        
        Ok(())
    }

    /// Initialize AMD watchdog
    fn init_amd(&self) -> Result<(), WatchdogError> {
        println!("[WDT] AMD: Would configure watchdog");
        
        Ok(())
    }

    /// Kick the watchdog
    pub fn kick(&self) -> Result<(), HypervisorError> {
        match self.watchdog_type {
            WatchdogType::Patrol => self.kick_patrol(),
            WatchdogType::Amd => self.kick_amd(),
            WatchdogType::Software => {
                // Software watchdog - just update timestamp
                Ok(())
            }
            WatchdogType::None => Ok(()),
        }
    }

    /// Kick Intel PATROL
    fn kick_patrol(&self) -> Result<(), HypervisorError> {
        // Write to count MSR to reset timer
        // In real implementation:
        // msr::wrmsr(WDT_COUNT, timeout_secs);
        
        Ok(())
    }

    /// Kick AMD watchdog
    fn kick_amd(&self) -> Result<(), HypervisorError> {
        Ok(())
    }

    /// Record Julia heartbeat
    pub fn record_julia_heartbeat(&mut self) {
        self.heartbeat.record_heartbeat();
    }

    /// Check Julia status
    pub fn check_julia(&mut self) -> bool {
        let alive = self.heartbeat.check_alive();
        
        if !alive {
            println!("[WDT] Julia heartbeat missed!");
            
            // If multiple heartbeats missed, trigger lockdown
            if self.heartbeat.missed_count() >= 3 {
                self.trigger_lockdown();
            }
        }
        
        alive
    }

    /// Trigger GPIO lockdown
    fn trigger_lockdown(&self) {
        println!("[WDT] CRITICAL: Triggering GPIO lockdown!");
        println!("[WDT] - Setting actuators to safe state");
        println!("[WDT] - Resetting network PHY");
        println!("[WDT] - Memory resealing triggered");
        
        // In real implementation:
        // 1. Set all GPIO outputs to safe state
        // 2. Reset network PHY
        // 3. Trigger memory resealing via TPM
    }

    /// Get watchdog type
    pub fn watchdog_type(&self) -> WatchdogType {
        self.watchdog_type
    }

    /// Check if running
    pub fn is_running(&self) -> bool {
        self.running
    }

    /// Stop watchdog
    pub fn stop(&mut self) {
        if self.running {
            match self.watchdog_type {
                WatchdogType::Patrol => {
                    // Disable PATROL
                }
                WatchdogType::Amd => {
                    // Disable AMD watchdog
                }
                _ => {}
            }
            
            self.running = false;
            println!("[WDT] Stopped");
        }
    }
}

impl Drop for Watchdog {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Global watchdog instance for supervisory loop
static mut WATCHDOG: Option<Watchdog> = None;

/// Initialize global watchdog
pub fn init_watchdog(timeout_ms: u32) -> Result<(), HypervisorError> {
    unsafe {
        WATCHDOG = Some(Watchdog::new(timeout_ms)?);
    }
    Ok(())
}

/// Kick global watchdog
pub fn kick_watchdog() {
    unsafe {
        if let Some(ref wdt) = WATCHDOG {
            let _ = wdt.kick();
        }
    }
}

/// Record Julia heartbeat globally
pub fn record_heartbeat() {
    unsafe {
        if let Some(ref mut wdt) = WATCHDOG {
            wdt.record_julia_heartbeat();
        }
    }
}

/// Check Julia status globally
pub fn check_julia_status() -> bool {
    unsafe {
        if let Some(ref mut wdt) = WATCHDOG {
            wdt.check_julia()
        } else {
            true
        }
    }
}
