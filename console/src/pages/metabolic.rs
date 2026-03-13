//! ITHERIS Metabolic Page
//! 
//! Detailed metabolic state view with energy, viability, and mode controls.

use leptos::*;
use crate::state::signals::{
    CognitiveMode, MetabolicSignals, 
    ENERGY_MAX, ENERGY_CRITICAL, ENERGY_DEATH, ENERGY_RECOVERY,
};

/// Metabolic page component
#[component]
pub fn MetabolicPage() -> impl IntoView {
    let metabolic_signals = MetabolicSignals::new();
    
    // Energy level signal
    let energy = metabolic_signals.energy;
    let viability = metabolic_signals.viability;
    let mode = metabolic_signals.mode;
    let tick_count = metabolic_signals.tick_count;
    
    view! {
        <div class="page metabolic-page">
            <div class="page-header">
                <h1>"Metabolic State"</h1>
                <span class="page-subtitle">"Energy Management & Viability"</span>
            </div>
            
            <div class="metabolic-grid">
                <div class="metric-card energy">
                    <h3>"Energy Level"</h3>
                    <div class="metric-display">
                        <span class="metric-value>{format!("{:.1}%", energy.get() * 100.0)}</span>
                        <div class="metric-bar">
                            <div 
                                class="metric-fill" 
                                style=format!("width: {}%", energy.get() * 100.0)
                            ></div>
                        </div>
                    </div>
                    <div class="metric-labels">
                        <span class="threshold critical">"CRITICAL: 15%"</span>
                        <span class="threshold death">"DEATH: 5%"</span>
                    </div>
                </div>
                
                <div class="metric-card viability">
                    <h3>"Viability Budget"</h3>
                    <div class="metric-display">
                        <span class="metric-value>{format!("{:.1}%", viability.get() * 100.0)}</span>
                        <div class="metric-bar">
                            <div 
                                class="metric-fill viability-fill" 
                                style=format!("width: {}%", viability.get() * 100.0)
                            ></div>
                        </div>
                    </div>
                </div>
                
                <div class="metric-card mode">
                    <h3>"Cognitive Mode"</h3>
                    <div class="mode-display">
                        <span class="mode-value>{mode.get().display_name()}</span>
                    </div>
                    <div class="mode-controls">
                        <button 
                            class="mode-btn"
                            on_click=move |_| {
                                metabolic_signals.mode.set(CognitiveMode::ModeActive);
                            }
                        >
                            "ACTIVE"
                        </button>
                        <button 
                            class="mode-btn"
                            on_click=move |_| {
                                metabolic_signals.mode.set(CognitiveMode::ModeIdle);
                            }
                        >
                            "IDLE"
                        </button>
                        <button 
                            class="mode-btn"
                            on_click=move |_| {
                                metabolic_signals.mode.set(CognitiveMode::ModeDreaming);
                            }
                        >
                            "DREAMING"
                        </button>
                    </div>
                </div>
                
                <div class="metric-card tick">
                    <h3>"Tick Count"</h3>
                    <div class="tick-display">
                        <span class="tick-value>{tick_count.get()}</span>
                    </div>
                </div>
            </div>
            
            <div class="metabolic-chart">
                <h3>"Energy History"</h3>
                <div class="chart-placeholder">
                    <div class="chart-line">
                        <span class="chart-point" style="left: 0%; bottom: 80%;"></span>
                        <span class="chart-point" style="left: 20%; bottom: 75%;"></span>
                        <span class="chart-point" style="left: 40%; bottom: 85%;"></span>
                        <span class="chart-point" style="left: 60%; bottom: 70%;"></span>
                        <span class="chart-point" style="left: 80%; bottom: 78%;"></span>
                        <span class="chart-point" style="left: 100%; bottom: 72%;"></span>
                    </div>
                    <div class="chart-axis-y">
                        <span>"100%"</span>
                        <span>"75%"</span>
                        <span>"50%"</span>
                        <span>"25%"</span>
                        <span>"0%"</span>
                    </div>
                </div>
            </div>
        </div>
    }
}
