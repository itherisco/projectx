//! ITHERIS State Management - Reactive Signals
//! 
//! This module provides the reactive state management for the ITHERIS management console.
//! Uses Leptos signals for fine-grained reactivity without Virtual DOM.

use leptos::*;
use serde::{Deserialize, Serialize};

/// Maximum energy level constant
pub const ENERGY_MAX: f64 = 1.0;

/// Death threshold - when energy drops below this, system enters containment
pub const ENERGY_DEATH: f64 = 0.05;

/// Critical threshold for warnings
pub const ENERGY_CRITICAL: f64 = 0.15;

/// Recovery threshold
pub const ENERGY_RECOVERY: f64 = 0.30;

/// Cognitive modes available to the ITHERIS system
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum CognitiveMode {
    /// Active processing mode - full cognitive capabilities
    ModeActive = 0,
    /// Idle mode - minimal processing
    ModeIdle = 1,
    /// Recovery mode - energy conservation
    ModeRecovery = 2,
    /// Critical mode - minimal functionality
    ModeCritical = 3,
    /// Dreaming/oneiric state - memory consolidation
    ModeDreaming = 4,
    /// Death/containment mode - system locked
    ModeDeath = 5,
}

impl CognitiveMode {
    /// Convert string to CognitiveMode
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "active" => CognitiveMode::ModeActive,
            "idle" => CognitiveMode::ModeIdle,
            "recovery" => CognitiveMode::ModeRecovery,
            "critical" => CognitiveMode::ModeCritical,
            "dreaming" | "oneiric" => CognitiveMode::ModeDreaming,
            "death" | "containment" => CognitiveMode::ModeDeath,
            _ => CognitiveMode::ModeIdle,
        }
    }

    /// Get display name for the mode
    pub fn display_name(&self) -> &'static str {
        match self {
            CognitiveMode::ModeActive => "ACTIVE",
            CognitiveMode::ModeIdle => "IDLE",
            CognitiveMode::ModeRecovery => "RECOVERY",
            CognitiveMode::ModeCritical => "CRITICAL",
            CognitiveMode::ModeDreaming => "DREAMING",
            CognitiveMode::ModeDeath => "CONTAINMENT",
        }
    }

    /// Check if mode allows decision making
    pub fn can_decide(&self) -> bool {
        matches!(self, CognitiveMode::ModeActive)
    }
}

impl Default for CognitiveMode {
    fn default() -> Self {
        CognitiveMode::ModeIdle
    }
}

/// Metabolic state containing energy and viability information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetabolicState {
    pub energy_level: f64,
    pub viability_budget: f64,
    pub tick_count: u64,
    pub cognitive_mode: CognitiveMode,
    pub is_dreaming: bool,
}

impl Default for MetabolicState {
    fn default() -> Self {
        Self {
            energy_level: ENERGY_MAX,
            viability_budget: ENERGY_MAX,
            tick_count: 0,
            cognitive_mode: CognitiveMode::ModeIdle,
            is_dreaming: false,
        }
    }
}

/// Global metabolic state signals
#[derive(Clone)]
pub struct MetabolicSignals {
    /// Current energy level (0.0 - 1.0)
    pub energy: Signal<f64>,
    /// Current viability budget (0.0 - 1.0)
    pub viability: Signal<f64>,
    /// Total tick count
    pub tick_count: Signal<u64>,
    /// Current cognitive mode
    pub cognitive_mode: Signal<CognitiveMode>,
    /// Whether system is dreaming
    pub is_dreaming: Signal<bool>,
    /// Whether containment mode is active (energy < ENERGY_DEATH)
    pub containment_active: Signal<bool>,
}

impl MetabolicSignals {
    /// Create new metabolic signals with initial state
    pub fn new() -> Self {
        let (energy, set_energy) = create_signal(ENERGY_MAX);
        let (viability, set_viability) = create_signal(ENERGY_MAX);
        let (tick_count, set_tick_count) = create_signal(0u64);
        let (cognitive_mode, set_cognitive_mode) = create_signal(CognitiveMode::ModeIdle);
        let (is_dreaming, set_is_dreaming) = create_signal(false);
        
        // Create derived signal for containment mode
        let containment_active = create_memo(move |_| energy.get() < ENERGY_DEATH);
        
        // Set up reaction for containment mode transition
        create_effect(move |_| {
            let current_energy = energy.get();
            if current_energy < ENERGY_DEATH {
                // Transition to containment mode
                set_cognitive_mode.set(CognitiveMode::ModeDeath);
                tracing::warn!(
                    energy_level = current_energy,
                    "CONTAINMENT MODE ACTIVATED - Energy below death threshold"
                );
            }
        });
        
        Self {
            energy,
            viability,
            tick_count,
            cognitive_mode,
            is_dreaming,
            containment_active,
        }
    }

    /// Update state from a metabolic snapshot
    pub fn update_from_snapshot(&self, energy: f64, viability: f64, tick_count: u64, cognitive_mode: &str, is_dreaming: bool) {
        self.energy.set(energy);
        self.viability.set(viability);
        self.tick_count.set(tick_count);
        self.cognitive_mode.set(CognitiveMode::from_str(cognitive_mode));
        self.is_dreaming.set(is_dreaming);
    }
}

impl Default for MetabolicSignals {
    fn default() -> Self {
        Self::new()
    }
}

/// Get energy color based on level
pub fn get_energy_color(energy: f64) -> &'static str {
    if energy >= ENERGY_MAX {
        "#22c55e" // Green
    } else if energy >= ENERGY_RECOVERY {
        "#3b82f6" // Blue
    } else if energy >= ENERGY_CRITICAL {
        "#f59e0b" // Orange
    } else if energy >= ENERGY_DEATH {
        "#ef4444" // Red
    } else {
        "#991b1b" // Dark red (containment)
    }
}

/// Get energy status text
pub fn get_energy_status(energy: f64) -> &'static str {
    if energy >= ENERGY_MAX {
        "OPTIMAL"
    } else if energy >= ENERGY_RECOVERY {
        "HEALTHY"
    } else if energy >= ENERGY_CRITICAL {
        "DEGRADED"
    } else if energy >= ENERGY_DEATH {
        "CRITICAL"
    } else {
        "CONTAINMENT"
    }
}

/// Get viability color
pub fn get_viability_color(viability: f64) -> &'static str {
    if viability >= 0.8 {
        "#22c55e" // Green
    } else if viability >= 0.5 {
        "#3b82f6" // Blue
    } else if viability >= 0.3 {
        "#f59e0b" // Orange
    } else {
        "#ef4444" // Red
    }
}
