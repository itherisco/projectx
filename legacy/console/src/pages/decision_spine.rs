//! ITHERIS Decision Spine Page
//! 
//! Detailed decision spine view with proposal history and analysis.

use leptos::*;
use crate::state::signals::{CognitiveMode, MetabolicSignals};

/// Decision Spine page component
#[component]
pub fn DecisionSpinePage() -> impl IntoView {
    let metabolic_signals = MetabolicSignals::new();
    
    // Mock proposals for demo
    let proposals = create_signal(vec![
        ProposalRow {
            id: "prop-001".to_string(),
            rationale: "Optimize memory allocation for cognitive processes".to_string(),
            priority: 0.85,
            reward: 0.75,
            risk: 0.15,
            score: 0.60,
            approved: true,
            timestamp: "2026-03-13T05:30:00Z".to_string(),
        },
        ProposalRow {
            id: "prop-002".to_string(),
            rationale: "Enable oneiric state for memory consolidation".to_string(),
            priority: 0.70,
            reward: 0.90,
            risk: 0.05,
            score: 0.85,
            approved: true,
            timestamp: "2026-03-13T05:25:00Z".to_string(),
        },
        ProposalRow {
            id: "prop-003".to_string(),
            rationale: "Reduce energy consumption in idle state".to_string(),
            priority: 0.60,
            reward: 0.65,
            risk: 0.20,
            score: 0.45,
            approved: false,
            timestamp: "2026-03-13T05:20:00Z".to_string(),
        },
    ]);
    
    view! {
        <div class="page decision-spine-page">
            <div class="page-header">
                <h1>"Decision Spine"</h1>
                <span class="page-subtitle">"Proposal Evaluation & Commitment"</span>
            </div>
            
            <div class="decision-stats">
                <div class="stat-card">
                    <span class="stat-label">"Total Proposals"</span>
                    <span class="stat-value">"1,247"</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">"Approved"</span>
                    <span class="stat-value approved">"892"</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">"Rejected"</span>
                    <span class="stat-value rejected">"355"</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">"Approval Rate"</span>
                    <span class="stat-value">"71.5%"</span>
                </div>
            </div>
            
            <div class="proposals-table">
                <table>
                    <thead>
                        <tr>
                            <th>"ID"</th>
                            <th>"Rationale"</th>
                            <th>"Priority"</th>
                            <th>"Reward"</th>
                            <th>"Risk"</th>
                            <th>"Score"</th>
                            <th>"Status"</th>
                            <th>"Time"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {proposals.get().into_iter().map(|p| {
                            view! {
                                <tr class:approved=p.approved class:rejected=!p.approved>
                                    <td class="id">{p.id}</td>
                                    <td class="rationale">{p.rationale}</td>
                                    <td class="score">{format!("{:.2}", p.priority)}</td>
                                    <td class="score">{format!("{:.2}", p.reward)}</td>
                                    <td class="score">{format!("{:.2}", p.risk)}</td>
                                    <td class="score">{format!("{:.2}", p.score)}</td>
                                    <td class="status">
                                        <span class={if p.approved { "badge approved" } else { "badge rejected" }}>
                                            {if p.approved { "APPROVED" } else { "REJECTED" }}
                                        </span>
                                    </td>
                                    <td class="timestamp">{p.timestamp}</td>
                                </tr>
                            }
                        }).collect_view()}
                    </tbody>
                </table>
            </div>
        </div>
    }
}

/// Proposal row data
#[derive(Clone)]
pub struct ProposalRow {
    pub id: String,
    pub rationale: String,
    pub priority: f64,
    pub reward: f64,
    pub risk: f64,
    pub score: f64,
    pub approved: bool,
    pub timestamp: String,
}
