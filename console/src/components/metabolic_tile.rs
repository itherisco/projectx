//! ITHERIS Metabolic Tile Component
//! 
//! Leptos component for displaying metabolic energy status.
//! Uses signals for reactivity (no Virtual DOM).

use crate::state::signals::{
    get_energy_color, get_energy_status, get_viability_color, CognitiveMode, MetabolicSignals,
    ENERGY_CRITICAL, ENERGY_DEATH, ENERGY_MAX, ENERGY_RECOVERY,
};
use leptos::*;

/// MetabolicTile - Displays metabolic energy bar and viability budget
/// 
/// # Props
/// * `signals` - MetabolicSignals instance for reactive state
#[component]
pub fn MetabolicTile(signals: MetabolicSignals) -> impl IntoView {
    // Reactive reads using signals
    let energy = signals.energy;
    let viability = signals.viability;
    let cognitive_mode = signals.cognitive_mode;
    let containment_active = signals.containment_active;
    let is_dreaming = signals.is_dreaming;
    let tick_count = signals.tick_count;

    view! {
        <div class="metabolic-tile" class:containment=containment_active>
            // Header
            <div class="tile-header">
                <h3>"METABOLIC STATUS"</h3>
                <span class="tick-counter">"TICK: " {tick_count}</span>
            </div>

            // Energy Section
            <div class="energy-section">
                <div class="section-label">
                    <span>"ENERGY LEVEL"</span>
                    <span class="energy-value">{move || format!("{:.1}%", energy() * 100.0)}</span>
                </div>
                
                <div class="energy-bar-container">
                    <div 
                        class="energy-bar"
                        style=move || format!(
                            "width: {}%; background-color: {};",
                            energy() * 100.0,
                            get_energy_color(energy())
                        )
                    />
                    // Threshold markers
                    <div class="threshold-marker critical" style="left: 15%;" title="Critical: 15%"></div>
                    <div class="threshold-marker recovery" style="left: 30%;" title="Recovery: 30%"></div>
                    <div class="threshold-marker death" style="left: 5%;" title="Death: 5%"></div>
                </div>
                
                <div class="status-indicator" style=move || format!("color: {}", get_energy_color(energy()))>
                    {move || get_energy_status(energy())}
                </div>
            </div>

            // Viability Section
            <div class="viability-section">
                <div class="section-label">
                    <span>"VIABILITY BUDGET"</span>
                    <span class="viability-value">{move || format!("{:.1}%", viability() * 100.0)}</span>
                </div>
                
                <div class="viability-bar-container">
                    <div 
                        class="viability-bar"
                        style=move || format!(
                            "width: {}%; background-color: {};",
                            viability() * 100.0,
                            get_viability_color(viability())
                        )
                    />
                </div>
            </div>

            // Cognitive Mode Section
            <div class="cognitive-mode-section">
                <span class="mode-label">"COGNITIVE MODE"</span>
                <div class="mode-display" class:active=move || cognitive_mode() == CognitiveMode::ModeActive>
                    {move || cognitive_mode().display_name()}
                </div>
                
                // Dreaming indicator
                <div class="dreaming-indicator" class:visible=is_dreaming>
                    <span class="dreaming-icon">"◈"</span>
                    <span>"ONEIRIC STATE"</span>
                </div>
            </div>

            // Containment Mode Overlay
            {move || {
                if containment_active() {
                    Some(view! {
                        <div class="containment-overlay">
                            <div class="containment-alert">
                                <span class="alert-icon">"⚠"</span>
                                <span>"CONTAINMENT MODE ACTIVE"</span>
                                <span class="alert-subtitle">"Energy below death threshold"</span>
                            </div>
                        </div>
                    })
                } else {
                    None
                }
            }}
        </div>
    }
}

/// Styles for the MetabolicTile component
pub const METABOLIC_TILE_CSS: &str = r#"
.metabolic-tile {
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border: 1px solid #0f3460;
    border-radius: 12px;
    padding: 20px;
    position: relative;
    overflow: hidden;
    transition: all 0.3s ease;
}

.metabolic-tile.containment {
    border-color: #ef4444;
    box-shadow: 0 0 20px rgba(239, 68, 68, 0.3);
    animation: pulse-containment 2s infinite;
}

@keyframes pulse-containment {
    0%, 100% { box-shadow: 0 0 20px rgba(239, 68, 68, 0.3); }
    50% { box-shadow: 0 0 40px rgba(239, 68, 68, 0.5); }
}

.tile-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 1px solid #0f3460;
}

.tile-header h3 {
    color: #e2e8f0;
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 2px;
    margin: 0;
}

.tick-counter {
    color: #64748b;
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
}

.energy-section, .viability-section {
    margin-bottom: 20px;
}

.section-label {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
    color: #94a3b8;
    font-size: 12px;
    letter-spacing: 1px;
}

.energy-value, .viability-value {
    font-family: 'JetBrains Mono', monospace;
    color: #e2e8f0;
    font-weight: 600;
}

.energy-bar-container, .viability-bar-container {
    position: relative;
    height: 12px;
    background: #0f172a;
    border-radius: 6px;
    overflow: hidden;
}

.energy-bar, .viability-bar {
    height: 100%;
    border-radius: 6px;
    transition: width 0.3s ease, background-color 0.3s ease;
}

.threshold-marker {
    position: absolute;
    top: 0;
    width: 2px;
    height: 100%;
    opacity: 0.5;
}

.threshold-marker.critical { background: #f59e0b; }
.threshold-marker.recovery { background: #3b82f6; }
.threshold-marker.death { background: #ef4444; }

.status-indicator {
    text-align: center;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 2px;
    margin-top: 8px;
}

.cognitive-mode-section {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding-top: 15px;
    border-top: 1px solid #0f3460;
}

.mode-label {
    color: #64748b;
    font-size: 11px;
    letter-spacing: 1px;
}

.mode-display {
    background: #0f172a;
    color: #94a3b8;
    padding: 8px 20px;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 2px;
    transition: all 0.3s ease;
}

.mode-display.active {
    background: #065f46;
    color: #34d399;
    box-shadow: 0 0 15px rgba(52, 211, 153, 0.3);
}

.dreaming-indicator {
    display: flex;
    align-items: center;
    gap: 6px;
    color: #a855f7;
    font-size: 11px;
    letter-spacing: 1px;
    opacity: 0;
    transition: opacity 0.3s ease;
}

.dreaming-indicator.visible {
    opacity: 1;
    animation: dream-pulse 1.5s infinite;
}

@keyframes dream-pulse {
    0%, 100% { opacity: 0.7; }
    50% { opacity: 1; }
}

.dreaming-icon {
    font-size: 14px;
}

.containment-overlay {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(127, 29, 29, 0.2);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10;
}

.containment-alert {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    color: #ef4444;
    font-weight: 700;
    letter-spacing: 2px;
    text-align: center;
    padding: 20px;
    background: rgba(0, 0, 0, 0.7);
    border-radius: 8px;
    border: 2px solid #ef4444;
}

.alert-icon {
    font-size: 32px;
    animation: alert-blink 1s infinite;
}

@keyframes alert-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
}

.alert-subtitle {
    font-size: 10px;
    font-weight: 400;
    letter-spacing: 1px;
    color: #fca5a5;
}
"#;

/// Include the CSS in the module
pub fn metabolic_tile_styles() -> String {
    METABOLIC_TILE_CSS.to_string()
}
