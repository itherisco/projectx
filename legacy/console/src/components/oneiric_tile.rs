//! ITHERIS Oneiric State Indicator Component
//! 
//! Leptos component for displaying the oneiric (dreaming) state.

use leptos::*;

/// Oneiric state types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OneiricPhase {
    /// Awake state
    Awake,
    /// N1 - Light sleep
    N1,
    /// N2 - Sleep spindles
    N2,
    /// N3 - Deep sleep
    N3,
    /// REM - Rapid eye movement / dreaming
    REM,
}

impl OneiricPhase {
    pub fn display_name(&self) -> &'static str {
        match self {
            OneiricPhase::Awake => "AWAKE",
            OneiricPhase::N1 => "N1 LIGHT",
            OneiricPhase::N2 => "N2 SPINDLE",
            OneiricPhase::N3 => "N3 DEEP",
            OneiricPhase::REM => "REM DREAM",
        }
    }

    pub fn color(&self) -> &'static str {
        match self {
            OneiricPhase::Awake => "#22c55e",
            OneiricPhase::N1 => "#3b82f6",
            OneiricPhase::N2 => "#8b5cf6",
            OneiricPhase::N3 => "#6366f1",
            OneiricPhase::REM => "#a855f7",
        }
    }
}

/// OneiricTile - Displays oneiric/dreaming state
#[component]
pub fn OneiricTile(
    /// Current oneiric phase
    phase: Signal<OneiricPhase>,
    /// Whether dreaming is active
    is_dreaming: Signal<bool>,
) -> impl IntoView {
    let phase_color = move || phase().color();

    view! {
        <div class="oneiric-tile" class:active=is_dreaming>
            <div class="tile-header">
                <h3>"ONEIRIC STATE"</h3>
                <div class="dreaming-badge" class:visible=is_dreaming>
                    <span class="badge-dot"></span>
                    <span>"DREAMING"</span>
                </div>
            </div>

            <div class="phase-display" style=move || format!("border-color: {}; color: {};", phase_color(), phase_color())>
                <span class="phase-icon">
                    {move || match phase() {
                        OneiricPhase::Awake => "☀",
                        OneiricPhase::N1 => "◐",
                        OneiricPhase::N2 => "◔",
                        OneiricPhase::N3 => "◑",
                        OneiricPhase::REM => "◉",
                    }}
                </span>
                <span class="phase-name">{move || phase().display_name()}</span>
            </div>

            <div class="sleep-architecture">
                <h4>"SLEEP ARCHITECTURE"</h4>
                <div class="hypnogram">
                    <div class="hypnogram-bar n1" style="opacity: 0.3;"></div>
                    <div class="hypnogram-bar n2" style="opacity: 0.5;"></div>
                    <div class="hypnogram-bar n3" style="opacity: 0.7;"></div>
                    <div class="hypnogram-bar rem" class:active=move || phase() == OneiricPhase::REM></div>
                </div>
                <div class="hypnogram-labels">
                    <span>"N1"</span>
                    <span>"N2"</span>
                    <span>"N3"</span>
                    <span>"REM"</span>
                </div>
            </div>

            <div class="memory-consolidation">
                <h4>"MEMORY CONSOLIDATION"</h4>
                <div class="consolidation-stats">
                    <div class="stat-item">
                        <span class="stat-label">"Synaptic Homeostasis"</span>
                        <div class="stat-bar">
                            <div class="stat-fill" style="width: 75%; background: #22c55e;"></div>
                        </div>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">"Memory Replay"</span>
                        <div class="stat-bar">
                            <div class="stat-fill" style="width: 60%; background: #3b82f6;"></div>
                        </div>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">"Hallucination Training"</span>
                        <div class="stat-bar">
                            <div class="stat-fill" style="width: 45%; background: #a855f7;"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    }
}

pub const ONEIRIC_TILE_CSS: &str = r#"
.oneiric-tile {
    background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%);
    border: 1px solid #4c1d95;
    border-radius: 12px;
    padding: 20px;
    transition: all 0.3s ease;
}

.oneiric-tile.active {
    box-shadow: 0 0 30px rgba(168, 85, 247, 0.3);
    animation: dream-glow 2s infinite;
}

@keyframes dream-glow {
    0%, 100% { box-shadow: 0 0 30px rgba(168, 85, 247, 0.3); }
    50% { box-shadow: 0 0 50px rgba(168, 85, 247, 0.5); }
}

.oneiric-tile .tile-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 1px solid #4c1d95;
}

.oneiric-tile h3 {
    color: #e2e8f0;
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 2px;
    margin: 0;
}

.dreaming-badge {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    background: rgba(168, 85, 247, 0.2);
    border: 1px solid #a855f7;
    border-radius: 20px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1px;
    color: #a855f7;
    opacity: 0;
    transition: opacity 0.3s ease;
}

.dreaming-badge.visible {
    opacity: 1;
}

.badge-dot {
    width: 6px;
    height: 6px;
    background: #a855f7;
    border-radius: 50%;
    animation: dot-pulse 1s infinite;
}

@keyframes dot-pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.5; transform: scale(0.8); }
}

.phase-display {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 16px;
    padding: 24px;
    background: rgba(0, 0, 0, 0.3);
    border: 2px solid;
    border-radius: 12px;
    margin-bottom: 20px;
    transition: all 0.3s ease;
}

.phase-icon {
    font-size: 48px;
    animation: phase-breath 4s infinite ease-in-out;
}

@keyframes phase-breath {
    0%, 100% { transform: scale(1); opacity: 0.8; }
    50% { transform: scale(1.1); opacity: 1; }
}

.phase-name {
    font-size: 24px;
    font-weight: 700;
    letter-spacing: 4px;
}

.sleep-architecture, .memory-consolidation {
    margin-top: 20px;
}

.sleep-architecture h4, .memory-consolidation h4 {
    color: #94a3b8;
    font-size: 11px;
    letter-spacing: 1px;
    margin: 0 0 12px 0;
}

.hypnogram {
    display: flex;
    gap: 4px;
    height: 40px;
    margin-bottom: 4px;
}

.hypnogram-bar {
    flex: 1;
    background: #1e1b4b;
    border-radius: 4px;
    transition: all 0.3s ease;
}

.hypnogram-bar.rem {
    background: #4c1d95;
}

.hypnogram-bar.rem.active {
    background: #a855f7;
    box-shadow: 0 0 15px rgba(168, 85, 247, 0.5);
    animation: rem-active 1s infinite;
}

@keyframes rem-active {
    0%, 100% { opacity: 0.8; }
    50% { opacity: 1; }
}

.hypnogram-labels {
    display: flex;
    justify-content: space-around;
    color: #64748b;
    font-size: 10px;
    letter-spacing: 1px;
}

.consolidation-stats {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.stat-item {
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.stat-label {
    color: #94a3b8;
    font-size: 11px;
    letter-spacing: 0.5px;
}

.stat-bar {
    height: 6px;
    background: #1e1b4b;
    border-radius: 3px;
    overflow: hidden;
}

.stat-fill {
    height: 100%;
    border-radius: 3px;
    transition: width 0.5s ease;
}
"#;
