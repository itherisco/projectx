//! ITHERIS Decision Spine Tile Component
//! 
//! Leptos component for displaying decision proposals from the Decision Spine.

use leptos::*;
use serde::{Deserialize, Serialize};

/// Decision proposal from the Decision Spine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalData {
    pub id: String,
    pub rationale: String,
    pub priority: f64,
    pub reward: f64,
    pub risk: f64,
    pub score: f64,
    pub approved: bool,
    pub hallucination_score: f64,
    pub veto_reason: String,
}

/// DecisionSpineTile - Displays decision proposals
#[component]
pub fn DecisionSpineTile(proposals: Signal<Vec<ProposalData>>) -> impl IntoView {
    let approved_count = move || {
        proposals()
            .iter()
            .filter(|p| p.approved)
            .count()
    };

    let pending_count = move || {
        proposals()
            .iter()
            .filter(|p| !p.approved)
            .count()
    };

    let avg_hallucination = move || {
        let ps = proposals();
        if ps.is_empty() {
            return 0.0;
        }
        ps.iter().map(|p| p.hallucination_score).sum::<f64>() / ps.len() as f64
    };

    view! {
        <div class="decision-spine-tile">
            <div class="tile-header">
                <h3>"DECISION SPINE"</h3>
                <div class="proposal-stats">
                    <span class="stat approved">{approved_count()} " approved"</span>
                    <span class="stat pending">{pending_count()} " pending"</span>
                </div>
            </div>

            <div class="hallucination-meter">
                <span class="meter-label">"HALLUCINATION SCORE"</span>
                <div class="meter-bar">
                    <div 
                        class="meter-fill"
                        style=move || format!(
                            "width: {}%; background-color: {};",
                            avg_hallucination() * 100.0,
                            if avg_hallucination() > 0.5 { "#ef4444" } else if avg_hallucination() > 0.2 { "#f59e0b" } else { "#22c55e" }
                        )
                    />
                </div>
                <span class="meter-value">{move || format!("{:.1}%", avg_hallucination() * 100.0)}</span>
            </div>

            <div class="proposals-list">
                <For each=proposals>
                    {move |proposal: ProposalData| {
                        view! {
                            <div class="proposal-card" class:approved=proposal.approved>
                                <div class="proposal-header">
                                    <span class="proposal-id">#{proposal.id.chars().take(8).collect::<String>()}</span>
                                    <span class="proposal-status" class:approved=proposal.approved>
                                        {if proposal.approved { "✓ APPROVED" } else { "○ PENDING" }}
                                    </span>
                                </div>
                                <p class="proposal-rationale">{proposal.rationale}</p>
                                <div class="proposal-metrics">
                                    <span class="metric">
                                        <span class="metric-label">"PRI:"</span>
                                        <span class="metric-value">{format!("{:.2}", proposal.priority)}</span>
                                    </span>
                                    <span class="metric">
                                        <span class="metric-label">"REW:"</span>
                                        <span class="metric-value positive">"+{:.2}"</span>
                                    </span>
                                    <span class="metric">
                                        <span class="metric-label">"RSK:"</span>
                                        <span class="metric-value negative">"-{:.2}"</span>
                                    </span>
                                    <span class="metric score">
                                        <span class="metric-label">"SCR:"</span>
                                        <span class="metric-value">{format!("{:.2}", proposal.score)}</span>
                                    </span>
                                </div>
                            </div>
                        }
                    }}
                </For>
            </div>
        </div>
    }
}

pub const DECISION_SPINE_CSS: &str = r#"
.decision-spine-tile {
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border: 1px solid #0f3460;
    border-radius: 12px;
    padding: 20px;
    height: 100%;
    display: flex;
    flex-direction: column;
}

.decision-spine-tile .tile-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 1px solid #0f3460;
}

.decision-spine-tile h3 {
    color: #e2e8f0;
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 2px;
    margin: 0;
}

.proposal-stats {
    display: flex;
    gap: 12px;
    font-size: 12px;
}

.proposal-stats .stat {
    padding: 4px 8px;
    border-radius: 4px;
    font-family: 'JetBrains Mono', monospace;
}

.proposal-stats .stat.approved {
    background: rgba(34, 197, 94, 0.2);
    color: #22c55e;
}

.proposal-stats .stat.pending {
    background: rgba(245, 158, 11, 0.2);
    color: #f59e0b;
}

.hallucination-meter {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 20px;
    padding: 12px;
    background: #0f172a;
    border-radius: 8px;
}

.meter-label {
    color: #64748b;
    font-size: 11px;
    letter-spacing: 1px;
    white-space: nowrap;
}

.meter-bar {
    flex: 1;
    height: 8px;
    background: #1e293b;
    border-radius: 4px;
    overflow: hidden;
}

.meter-fill {
    height: 100%;
    border-radius: 4px;
    transition: width 0.3s ease, background-color 0.3s ease;
}

.meter-value {
    font-family: 'JetBrains Mono', monospace;
    color: #e2e8f0;
    font-size: 12px;
    min-width: 50px;
    text-align: right;
}

.proposals-list {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.proposal-card {
    background: #0f172a;
    border: 1px solid #1e293b;
    border-radius: 8px;
    padding: 12px;
    transition: all 0.2s ease;
}

.proposal-card.approved {
    border-color: #22c55e;
    background: rgba(34, 197, 94, 0.05);
}

.proposal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
}

.proposal-id {
    font-family: 'JetBrains Mono', monospace;
    color: #64748b;
    font-size: 11px;
}

.proposal-status {
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1px;
    color: #f59e0b;
}

.proposal-status.approved {
    color: #22c55e;
}

.proposal-rationale {
    color: #94a3b8;
    font-size: 12px;
    margin: 0 0 12px 0;
    line-height: 1.5;
}

.proposal-metrics {
    display: flex;
    gap: 16px;
    flex-wrap: wrap;
}

.metric {
    display: flex;
    gap: 4px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
}

.metric-label {
    color: #64748b;
}

.metric-value {
    color: #e2e8f0;
}

.metric-value.positive {
    color: #22c55e;
}

.metric-value.negative {
    color: #ef4444;
}

.metric.score .metric-value {
    color: #3b82f6;
    font-weight: 700;
}
"#;
