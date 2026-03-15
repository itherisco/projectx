//! ITHERIS Containment Page
//! 
//! Containment mode interface for system lockdown and recovery.

use leptos::*;
use crate::state::signals::{CognitiveMode, MetabolicSignals, ENERGY_DEATH};

/// Containment page component
#[component]
pub fn ContainmentPage() -> impl IntoView {
    let metabolic_signals = MetabolicSignals::new();
    
    // Containment state
    let is_containment_active = create_signal(false);
    let containment_reason = create_signal(String::new());
    let recovery_allowed = create_signal(true);
    
    view! {
        <div class="page containment-page">
            <div class="page-header">
                <h1>"Containment Mode"</h1>
                <span class="page-subtitle">"System Lockdown & Recovery"</span>
            </div>
            
            <div class="containment-status">
                <div class="status-indicator">
                    <span class="indicator-light"></span>
                    <span class="indicator-label">"SYSTEM STATUS"</span>
                </div>
                
                <div class="containment-state">
                    {if is_containment_active.get() {
                        view! {
                            <div class="state-card active">
                                <span class="state-icon">"⬡"</span>
                                <span class="state-label">"CONTAINMENT ACTIVE"</span>
                            </div>
                        }
                    } else {
                        view! {
                            <div class="state-card inactive">
                                <span class="state-icon">"◈"</span>
                                <span class="state-label">"SYSTEM NORMAL"</span>
                            </div>
                        }
                    }}
                </div>
            </div>
            
            <div class="containment-info">
                <div class="info-card">
                    <h3>"Containment Triggers"</h3>
                    <ul class="trigger-list">
                        <li>
                            <span class="trigger-label">"Energy Death"</span>
                            <span class="trigger-value">"< 5%"</span>
                        </li>
                        <li>
                            <span class="trigger-label">"Viability Exhaustion"</span>
                            <span class="trigger-value">"0%"</span>
                        </li>
                        <li>
                            <span class="trigger-label">"Security Breach"</span>
                            <span class="trigger-value">"Critical"</span>
                        </li>
                        <li>
                            <span class="trigger-label">"Manual Activation"</span>
                            <span class="trigger-value">"Admin"</span>
                        </li>
                    </ul>
                </div>
                
                <div class="info-card">
                    <h3>"Containment Actions"</h3>
                    <div class="action-list">
                        <button class="containment-btn activate">
                            <span class="btn-icon">"⬡"</span>
                            <span class="btn-label">"Activate Containment"</span>
                        </button>
                        <button class="containment-btn recovery">
                            <span class="btn-icon">"↻"</span>
                            <span class="btn-label">"Initiate Recovery"</span>
                        </button>
                        <button class="containment-btn bypass">
                            <span class="btn-icon">"⚠"</span>
                            <span class="btn-label">"Bypass Safety"</span>
                        </button>
                    </div>
                </div>
            </div>
            
            <div class="containment-logs">
                <h3>"Recent Containment Events"</h3>
                <div class="log-list">
                    <div class="log-entry">
                        <span class="log-time">"2026-03-13 05:45:00"</span>
                        <span class="log-level info">"INFO"</span>
                        <span class="log-message">"System entered normal operation"</span>
                    </div>
                    <div class="log-entry">
                        <span class="log-time">"2026-03-13 04:30:00"</span>
                        <span class="log-level warning">"WARN"</span>
                        <span class="log-message">"Energy approaching critical threshold"</span>
                    </div>
                    <div class="log-entry">
                        <span class="log-time">"2026-03-13 03:15:00"</span>
                        <span class="log-level info">"INFO"</span>
                        <span class="log-message">"Containment mode deactivated"</span>
                    </div>
                </div>
            </div>
        </div>
    }
}
