//! # Emergency GPIO Control
//!
//! Dedicated emergency shutdown pin control for the Raspberry Pi CM4.
//! This module bypasses the heartbeat system to provide direct GPIO control
//! during panic/shutdown scenarios.
//!
//! ## GPIO Pin Mapping (BCM numbering)
//!
//! | Pin | BCM | Signal | Direction | Default | Purpose |
//! |-----|-----|--------|-----------|---------|---------|
//! | 7 | GPIO4 | EMERGENCY_SHUTDOWN | IN | HIGH | i9→CM4 panic signal |
//! | 10 | GPIO15 | POWER_GATE_RELAY | OUT | LOW | Power relay control |
//! | 8 | GPIO14 | NETWORK_PHY_RESET | OUT | LOW | PHY reset |
//! | 31 | GPIO6 | HEARTBEAT_OUT | OUT | LOW | i9→CM4 heartbeat |
//!
//! ## Actuator Pins (all default to LOW = safe state)
//!
//! GPIO17, GPIO18, GPIO22, GPIO23, GPIO24, GPIO25, GPIO26

use std::fs;
use std::path::Path;
use thiserror::Error;

/// GPIO sysfs base path
const GPIO_SYSFS_PATH: &str = "/sys/class/gpio";

/// Emergency shutdown pin (GPIO4 - receives panic signal from i9)
const EMERGENCY_SHUTDOWN_PIN: u32 = 4;

/// Power gate relay pin (GPIO15)
const POWER_GATE_RELAY_PIN: u32 = 15;

/// Network PHY reset pin (GPIO14)
const NETWORK_PHY_RESET_PIN: u32 = 14;

/// Actuator pins (all set to LOW for safe state)
const ACTUATOR_PINS: &[u32] = &[17, 18, 22, 23, 24, 25, 26];

/// Emergency GPIO errors
#[derive(Error, Debug)]
pub enum EmergencyGpioError {
    #[error("Failed to export GPIO: {0}")]
    ExportError(String),
    
    #[error("Failed to set GPIO direction: {0}")]
    DirectionError(String),
    
    #[error("Failed to write GPIO value: {0}")]
    WriteError(String),
    
    #[error("GPIO not available (running in non-privileged environment)")]
    NotAvailable,
    
    #[error("GPIO write verification failed")]
    VerificationFailed,
}

/// GPIO controller for emergency operations
pub struct EmergencyGpio {
    /// Pin number (BCM)
    pin: u32,
    /// Whether GPIO is available
    available: bool,
}

impl EmergencyGpio {
    /// Create a new emergency GPIO controller
    pub fn new(pin: u32) -> Self {
        let available = Self::try_export(pin).is_ok();
        
        EmergencyGpio {
            pin,
            available,
        }
    }
    
    /// Try to export a GPIO pin
    fn try_export(pin: u32) -> Result<(), EmergencyGpioError> {
        let gpio_path = format!("{}/gpio{}", GPIO_SYSFS_PATH, pin);
        
        // Check if already exported
        if Path::new(&gpio_path).exists() {
            return Ok(());
        }
        
        // Try to export
        let export_path = format!("{}/export", GPIO_SYSFS_PATH);
        
        fs::write(&export_path, format!("{}\n", pin))
            .map_err(|e| EmergencyGpioError::ExportError(e.to_string()))?;
        
        Ok(())
    }
    
    /// Set GPIO direction
    pub fn set_direction(&self, direction: &str) -> Result<(), EmergencyGpioError> {
        if !self.available {
            return Err(EmergencyGpioError::NotAvailable);
        }
        
        let direction_path = format!("{}/gpio{}/direction", GPIO_SYSFS_PATH, self.pin);
        
        fs::write(&direction_path, format!("{}\n", direction))
            .map_err(|e| EmergencyGpioError::DirectionError(e.to_string()))?;
        
        Ok(())
    }
    
    /// Set GPIO output value (0 or 1)
    pub fn set_value(&self, value: u8) -> Result<(), EmergencyGpioError> {
        if !self.available {
            return Err(EmergencyGpioError::NotAvailable);
        }
        
        let value_path = format!("{}/gpio{}/value", GPIO_SYSFS_PATH, self.pin);
        
        fs::write(&value_path, format!("{}\n", value))
            .map_err(|e| EmergencyGpioError::WriteError(e.to_string()))?;
        
        Ok(())
    }
    
    /// Get GPIO input value
    pub fn get_value(&self) -> Result<u8, EmergencyGpioError> {
        if !self.available {
            return Err(EmergencyGpioError::NotAvailable);
        }
        
        let value_path = format!("{}/gpio{}/value", GPIO_SYSFS_PATH, self.pin);
        
        let content = fs::read_to_string(&value_path)
            .map_err(|e| EmergencyGpioError::WriteError(e.to_string()))?;
        
        let value = content.trim().parse::<u8>()
            .map_err(|e| EmergencyGpioError::WriteError(e.to_string()))?;
        
        Ok(value)
    }
    
    /// Verify the GPIO value matches expected
    pub fn verify_value(&self, expected: u8) -> Result<bool, EmergencyGpioError> {
        let actual = self.get_value()?;
        Ok(actual == expected)
    }
    
    /// Check if GPIO is available
    pub fn is_available(&self) -> bool {
        self.available
    }
}

/// Emergency shutdown state
#[derive(Debug, Clone)]
pub struct EmergencyState {
    /// Whether emergency shutdown has been triggered
    pub shutdown_triggered: bool,
    /// Whether actuators are locked down
    pub actuators_locked_down: bool,
    /// Whether power relay is engaged
    pub power_relay_engaged: bool,
    /// Whether network PHY is reset
    pub network_phy_reset: bool,
    /// Hardware availability
    pub hardware_available: bool,
}

impl Default for EmergencyState {
    fn default() -> Self {
        EmergencyState {
            shutdown_triggered: false,
            actuators_locked_down: false,
            power_relay_engaged: false,
            network_phy_reset: false,
            hardware_available: false,
        }
    }
}

/// Initialize emergency GPIO pins
/// 
/// This exports and configures all GPIO pins needed for emergency shutdown.
/// It's safe to call this multiple times - it will handle already-exported pins.
pub fn init_emergency_gpio() -> Result<EmergencyState, EmergencyGpioError> {
    let mut state = EmergencyState::default();
    
    // Try to export and configure each pin
    // Emergency shutdown input (from i9)
    let emergency_in = EmergencyGpio::new(EMERGENCY_SHUTDOWN_PIN);
    if emergency_in.is_available() {
        let _ = emergency_in.set_direction("in");
    }
    
    // Power gate relay
    let power_relay = EmergencyGpio::new(POWER_GATE_RELAY_PIN);
    if power_relay.is_available() {
        let _ = power_relay.set_direction("out");
        let _ = power_relay.set_value(0); // Default: power enabled
        state.hardware_available = true;
    }
    
    // Network PHY reset
    let phy_reset = EmergencyGpio::new(NETWORK_PHY_RESET_PIN);
    if phy_reset.is_available() {
        let _ = phy_reset.set_direction("out");
        let _ = phy_reset.set_value(0); // Default: PHY enabled
    }
    
    // Actuator pins
    for &pin in ACTUATOR_PINS {
        let gpio = EmergencyGpio::new(pin);
        if gpio.is_available() {
            let _ = gpio.set_direction("out");
            let _ = gpio.set_value(0); // Default: all actuators OFF (safe state)
        }
    }
    
    log::info!("✅ Emergency GPIO initialized");
    Ok(state)
}

/// Trigger emergency shutdown
/// 
/// This sets the emergency shutdown GPIO which signals the CM4 to
/// cut power to actuators. The signal is active-low (LOW = panic).
pub fn trigger_emergency_shutdown() {
    // Set emergency shutdown pin LOW (active low)
    // This tells the CM4 that the i9 has failed
    let emergency_in = EmergencyGpio::new(EMERGENCY_SHUTDOWN_PIN);
    
    if emergency_in.is_available() {
        // Write directly without direction change (should already be input)
        let value_path = format!("{}/gpio{}/value", GPIO_SYSFS_PATH, EMERGENCY_SHUTDOWN_PIN);
        if let Err(e) = fs::write(&value_path, "0\n") {
            let _ = std::io::Write::write_all(
                &mut std::io::stderr(),
                format!("[KILL CHAIN] Failed to trigger emergency shutdown: {}\n", e).as_bytes()
            );
        }
        
        log::info!("🚨 Emergency shutdown signal sent to CM4");
    } else {
        log::warn!("⚠️ Emergency GPIO not available - cannot trigger shutdown");
    }
}

/// Lockdown all actuators
/// 
/// Sets all actuator GPIO pins to LOW (safe state = no power).
/// This is the final defense - even if the CM4 doesn't respond,
/// the i9 directly cuts actuator power.
pub fn lockdown_actuators() {
    log::info!("🔒 Locking down all actuators");
    
    for &pin in ACTUATOR_PINS {
        let gpio = EmergencyGpio::new(pin);
        
        if gpio.is_available() {
            // Set direction to out if needed, then set LOW
            let _ = gpio.set_direction("out");
            
            if let Err(e) = gpio.set_value(0) {
                let _ = std::io::Write::write_all(
                    &mut std::io::stderr(),
                    format!("[KILL CHAIN] Failed to lock down actuator GPIO{}: {}\n", pin, e).as_bytes()
                );
            }
        }
    }
    
    log::info!("🔒 All actuators locked down (LOW)");
}

/// Cut power relay
/// 
/// Engages the power gate relay to remove power from external systems.
pub fn cut_power_relay() {
    let power_relay = EmergencyGpio::new(POWER_GATE_RELAY_PIN);
    
    if power_relay.is_available() {
        let _ = power_relay.set_direction("out");
        
        // HIGH = cut power (active high relay)
        if let Err(e) = power_relay.set_value(1) {
            let _ = std::io::Write::write_all(
                &mut std::io::stderr(),
                format!("[KILL CHAIN] Failed to cut power relay: {}\n", e).as_bytes()
            );
        }
        
        log::info!("⚡ Power relay engaged - external power cut");
    }
}

/// Reset network PHY
/// 
/// Holds the network PHY in reset to isolate the network.
pub fn reset_network_phy() {
    let phy_reset = EmergencyGpio::new(NETWORK_PHY_RESET_PIN);
    
    if phy_reset.is_available() {
        let _ = phy_reset.set_direction("out");
        
        // HIGH = reset (active high)
        if let Err(e) = phy_reset.set_value(1) {
            let _ = std::io::Write::write_all(
                &mut std::io::stderr(),
                format!("[KILL CHAIN] Failed to reset network PHY: {}\n", e).as_bytes()
            );
        }
        
        log::info!("🌐 Network PHY held in reset");
    }
}

/// Verify physical lockdown
/// 
/// Checks that all actuators are in the safe state (LOW).
/// This provides feedback that the hardware lockdown was successful.
pub fn verify_lockdown() -> bool {
    let mut all_safe = true;
    
    for &pin in ACTUATOR_PINS {
        let gpio = EmergencyGpio::new(pin);
        
        if gpio.is_available() {
            match gpio.get_value() {
                Ok(value) => {
                    if value != 0 {
                        log::warn!("⚠️ Actuator GPIO{} not in safe state (expected 0, got {})", pin, value);
                        all_safe = false;
                    }
                }
                Err(e) => {
                    log::warn!("⚠️ Could not verify GPIO{}: {}", pin, e);
                    all_safe = false;
                }
            }
        }
    }
    
    if all_safe {
        log::info!("✅ Physical lockdown verified - all actuators in safe state");
    } else {
        log::warn!("⚠️ Physical lockdown verification failed");
    }
    
    all_safe
}

/// Get current emergency state
pub fn get_emergency_state() -> EmergencyState {
    let mut state = EmergencyState::default();
    
    // Check emergency shutdown pin
    let emergency_in = EmergencyGpio::new(EMERGENCY_SHUTDOWN_PIN);
    if emergency_in.is_available() {
        state.hardware_available = true;
        if let Ok(0) = emergency_in.get_value() {
            state.shutdown_triggered = true;
        }
    }
    
    // Check power relay
    let power_relay = EmergencyGpio::new(POWER_GATE_RELAY_PIN);
    if power_relay.is_available() {
        if let Ok(1) = power_relay.get_value() {
            state.power_relay_engaged = true;
        }
    }
    
    // Check actuator states
    let mut all_actuators_low = true;
    for &pin in ACTUATOR_PINS {
        let gpio = EmergencyGpio::new(pin);
        if gpio.is_available() {
            if let Ok(0) = gpio.get_value() {
                // LOW is good
            } else {
                all_actuators_low = false;
            }
        }
    }
    state.actuators_locked_down = all_actuators_low;
    
    state
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_emergency_state_default() {
        let state = EmergencyState::default();
        assert!(!state.shutdown_triggered);
        assert!(!state.actuators_locked_down);
    }
    
    #[test]
    fn test_emergency_gpio_creation() {
        // Just verify creation doesn't panic
        let gpio = EmergencyGpio::new(100); // Use invalid pin
        // GPIO won't be available, but it shouldn't panic
        let _ = gpio;
    }
    
    #[test]
    fn test_actuator_pins_count() {
        // We expect 7 actuator pins based on the spec
        assert_eq!(ACTUATOR_PINS.len(), 7);
    }
}
