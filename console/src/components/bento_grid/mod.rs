//! ITHERIS Bento Grid Layout Component
//! 
//! Main dashboard layout using a bento grid system.

use leptos::*;
use crate::components::metabolic_tile::MetabolicTile;
use crate::components::decision_spine_tile::DecisionSpineTile;
use crate::components::oneiric_tile::{OneiricTile, OneiricPhase};
use crate::components::unsealing_tile::UnsealingTile;
use crate::state::signals::MetabolicSignals;

/// BentoGrid - Main dashboard layout
#[component]
pub fn BentoGrid(metabolic_signals: MetabolicSignals) -> impl IntoView {
    // For demo purposes, create mock proposals
    let mock_proposals = create_signal(vec![
        crate::components::decision_spine_tile::ProposalData {
            id: "prop-001".to_string(),
            rationale: "Optimize memory allocation for cognitive processes".to_string(),
            priority: 0.85,
            reward: 0.75,
            risk: 0.15,
            score: 0.60,
            approved: true,
            hallucination_score: 0.08,
            veto_reason: String::new(),
        },
        crate::components::decision_spine_tile::ProposalData {
            id: "prop-002".to_string(),
            rationale: "Enable oneiric state for memory consolidation".to_string(),
            priority: 0.70,
            reward: 0.90,
            risk: 0.05,
            score: 0.85,
            approved: true,
            hallucination_score: 0.12,
            veto_reason: String::new(),
        },
    ]);

    // Demo oneiric phase
    let oneiric_phase = create_signal(OneiricPhase::REM);
    let is_dreaming = create_signal(true);

    view! {
        <div class="bento-grid">
            <header class="grid-header">
                <div class="logo">
                    <span class="logo-icon">"◈"</span>
                    <h1>"ITHERIS"</h1>
                    <span class="version">"v0.1.0"</span>
                </div>
                <div class="header-status">
                    <span class="status-indicator online"></span>
                    <span>"WARDEN CONNECTED"</span>
                </div>
            </header>

            <div class="grid-container">
                // Metabolic Tile - spans 2 columns
                <div class="grid-item metabolic">
                    <MetabolicTile signals=metabolic_signals />
                </div>

                // Decision Spine Tile - spans 2 columns
                <div class="grid-item decisions">
                    <DecisionSpineTile proposals=mock_proposals.0 />
                </div>

                // Oneiric State Tile - spans 1 column
                <div class="grid-item oneiric">
                    <OneiricTile phase=oneiric_phase.0 is_dreaming=is_dreaming.0 />
                </div>

                // TPM Unsealing Tile - spans 1 column
                <div class="grid-item unsealing">
                    <UnsealingTile />
                </div>
            </div>
        </div>
    }
}

/// Combined CSS for all components
pub fn get_combined_css() -> String {
    format!(
        "{}\n{}\n{}\n{}\n{}",
        crate::components::metabolic_tile::METABOLIC_TILE_CSS,
        crate::components::decision_spine_tile::DECISION_SPINE_CSS,
        crate::components::oneiric_tile::ONEIRIC_TILE_CSS,
        crate::components::unsealing_tile::UNSEALING_TILE_CSS,
        BENTO_GRID_CSS
    )
}

const BENTO_GRID_CSS: &str = r#"
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0a0a0f;
    color: #e2e8f0;
    min-height: 100vh;
}

.bento-grid {
    min-height: 100vh;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 20px;
}

.grid-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px 24px;
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border: 1px solid #0f3460;
    border-radius: 12px;
}

.logo {
    display: flex;
    align-items: center;
    gap: 12px;
}

.logo-icon {
    font-size: 28px;
    color: #3b82f6;
    animation: logo-pulse 2s infinite;
}

@keyframes logo-pulse {
    0%, 100% { opacity: 0.8; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.05); }
}

.logo h1 {
    font-size: 24px;
    font-weight: 700;
    letter-spacing: 4px;
    background: linear-gradient(135deg, #3b82f6 0%, #8b5cf6 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
}

.version {
    font-size: 10px;
    color: #64748b;
    letter-spacing: 1px;
    padding: 2px 6px;
    background: #0f172a;
    border-radius: 4px;
}

.header-status {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    letter-spacing: 1px;
    color: #22c55e;
}

.status-indicator {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #22c55e;
    animation: status-blink 2s infinite;
}

@keyframes status-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
}

.grid-container {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    grid-template-rows: auto auto;
    gap: 20px;
    flex: 1;
}

.grid-item {
    min-height: 300px;
}

.grid-item.metabolic {
    grid-column: span 2;
}

.grid-item.decisions {
    grid-column: span 2;
}

.grid-item.oneiric {
    grid-column: span 1;
}

.grid-item.unsealing {
    grid-column: span 1;
}

/* Responsive adjustments */
@media (max-width: 1200px) {
    .grid-container {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .grid-item.metabolic,
    .grid-item.decisions,
    .grid-item.oneiric,
    .grid-item.unsealing {
        grid-column: span 1;
    }
}

@media (max-width: 768px) {
    .grid-container {
        grid-template-columns: 1fr;
    }
    
    .grid-item {
        grid-column: span 1 !important;
    }
    
    .grid-header {
        flex-direction: column;
        gap: 12px;
    }
}

/* Global scrollbar styling */
::-webkit-scrollbar {
    width: 8px;
    height: 8px;
}

::-webkit-scrollbar-track {
    background: #0f172a;
}

::-webkit-scrollbar-thumb {
    background: #334155;
    border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
    background: #475569;
}
"#;
