//! ITHERIS Console - Management Console for ProjectX Jarvis
//! 
//! A bare-metal Type-1 hypervisor management console built with Leptos
//! for reactive WebAssembly-based UI.

pub mod components;
pub mod pages;
pub mod services;
pub mod state;
pub mod app;

// Re-export commonly used types
pub use state::signals::{
    CognitiveMode, MetabolicSignals, MetabolicState, 
    ENERGY_CRITICAL, ENERGY_DEATH, ENERGY_MAX, ENERGY_RECOVERY,
};
pub use state::theme::{Theme, ThemeProvider, CircadianTheme, CIRCADIAN_THEMES};

use leptos::*;

#[cfg(feature = "wasm")]
mod wasm_entry {
    use super::*;
    use wasm_bindgen::prelude::*;
    
    /// Initialize panic hook for better error messages in browser console
    #[wasm_bindgen]
    pub fn init_panic_hook() {
        #[cfg(feature = "console_error_panic_hook")]
        console_error_panic_hook::set_once();
    }
    
    /// WASM entry point for the application
    #[wasm_bindgen(start)]
    pub fn main() -> Result<(), JsValue> {
        // Initialize panic hook
        init_panic_hook();
        
        // Mount the Leptos application to the body
        leptos::mount_to_body(|cx| {
            view! { cx, <App /> }
        });
        
        Ok(())
    }
}

/// Main App component
#[component]
pub fn App() -> impl IntoView {
    // Initialize metabolic signals
    let metabolic_signals = MetabolicSignals::new();

    // Get CSS
    let css = components::bento_grid::get_combined_css();

    view! {
        <style>{css}</style>
        <components::bento_grid::BentoGrid metabolic_signals=metabolic_signals />
    }
}

/// Initialize the application (non-WASM entry point)
#[cfg(not(feature = "wasm"))]
pub fn initialize() {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .init();
    
    tracing::info!("ITHERIS Console initialized");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cognitive_mode_display() {
        assert_eq!(CognitiveMode::ModeActive.display_name(), "ACTIVE");
        assert_eq!(CognitiveMode::ModeDeath.display_name(), "CONTAINMENT");
        assert_eq!(CognitiveMode::ModeDreaming.display_name(), "DREAMING");
    }

    #[test]
    fn test_cognitive_mode_from_str() {
        assert_eq!(CognitiveMode::from_str("active"), CognitiveMode::ModeActive);
        assert_eq!(CognitiveMode::from_str("DREAMING"), CognitiveMode::ModeDreaming);
        assert_eq!(CognitiveMode::from_str("unknown"), CognitiveMode::ModeIdle);
    }

    #[test]
    fn test_metabolic_signals_default() {
        let signals = MetabolicSignals::new();
        assert_eq!(signals.energy.get(), ENERGY_MAX);
        assert_eq!(signals.viability.get(), ENERGY_MAX);
    }

    #[test]
    fn test_energy_color_thresholds() {
        use state::signals::{get_energy_color, ENERGY_CRITICAL, ENERGY_DEATH, ENERGY_RECOVERY};
        
        // High energy should be green
        let color = get_energy_color(ENERGY_MAX);
        assert_eq!(color, "#22c55e");
        
        // Critical should be red
        let color = get_energy_color(ENERGY_CRITICAL - 0.01);
        assert_eq!(color, "#ef4444");
        
        // Below death should be dark red
        let color = get_energy_color(ENERGY_DEATH - 0.01);
        assert_eq!(color, "#991b1b");
    }
}
