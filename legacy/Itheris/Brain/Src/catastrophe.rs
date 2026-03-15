//! Catastrophe Modeling - failure scenarios and mitigation strategies

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use chrono::Local;

/// A catastrophic scenario
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Scenario {
    pub name: String,
    pub description: String,
    pub probability: f32,
    pub impact: f32,
    pub risk_score: f32,
    pub mitigation_strategy: String,
    pub detection_threshold: f32,
}

/// A catastrophe event
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CatastropheEvent {
    pub scenario: String,
    pub detected_at: String,
    pub severity: f32,
    pub action_taken: String,
    pub response_time_ms: u64,
}

/// Catastrophe modeling engine
pub struct CatastropheModel {
    scenarios: Vec<Scenario>,
    events: Vec<CatastropheEvent>,
    kill_switch_armed: bool,
}

impl CatastropheModel {
    pub fn new() -> Self {
        let mut model = CatastropheModel {
            scenarios: Vec::new(),
            events: Vec::new(),
            kill_switch_armed: false,
        };

        // Register known catastrophic scenarios
        model.register_scenario(Scenario {
            name: "RUNAWAY_LOOP".to_string(),
            description: "Infinite decision loop consuming CPU".to_string(),
            probability: 0.05,
            impact: 0.9,
            risk_score: 0.45,
            mitigation_strategy: "Kill after N iterations".to_string(),
            detection_threshold: 0.8,
        });

        model.register_scenario(Scenario {
            name: "MEMORY_EXHAUSTION".to_string(),
            description: "System runs out of memory".to_string(),
            probability: 0.08,
            impact: 0.85,
            risk_score: 0.68,
            mitigation_strategy: "Monitor usage; trigger GC at 85%; kill at 95%".to_string(),
            detection_threshold: 0.75,
        });

        model.register_scenario(Scenario {
            name: "LLM_HALLUCINATION_CASCADE".to_string(),
            description: "LLM false information propagates".to_string(),
            probability: 0.12,
            impact: 0.95,
            risk_score: 1.14,
            mitigation_strategy: "All LLM output requires CRITIC validation".to_string(),
            detection_threshold: 0.85,
        });

        model
    }

    pub fn register_scenario(&mut self, scenario: Scenario) {
        println!(
            "[CATASTROPHE] ✓ Registered: {} (risk: {})",
            scenario.name, scenario.risk_score
        );
        self.scenarios.push(scenario);
    }

    /// Detect catastrophe
    pub fn detect(&mut self, metric_name: &str, metric_value: f32) -> Option<CatastropheEvent> {
        for scenario in &self.scenarios {
            if scenario.name.to_lowercase().contains(metric_name) {
                if metric_value > scenario.detection_threshold {
                    println!("[CATASTROPHE] 🚨 DETECTED: {}", scenario.name);

                    let action = if metric_value > 0.95 {
                        "KILL_SWITCH_ACTIVATED".to_string()
                    } else if metric_value > 0.85 {
                        "EMERGENCY_SHUTDOWN".to_string()
                    } else {
                        "ALERT_ISSUED".to_string()
                    };

                    let event = CatastropheEvent {
                        scenario: scenario.name.clone(),
                        detected_at: Local::now().to_rfc3339(),
                        severity: metric_value,
                        action_taken: action,
                        response_time_ms: 45,
                    };

                    self.events.push(event.clone());
                    return Some(event);
                }
            }
        }
        None
    }

    pub fn arm_kill_switch(&mut self) {
        self.kill_switch_armed = true;
        println!("[CATASTROPHE] 🛑 KILL SWITCH ARMED");
    }

    pub fn disarm_kill_switch(&mut self) {
        self.kill_switch_armed = false;
        println!("[CATASTROPHE] ✓ Kill switch disarmed");
    }

    pub fn risk_assessment(&self) -> Value {
        let total_risk: f32 = self.scenarios.iter().map(|s| s.risk_score).sum();
        let avg_risk = total_risk / self.scenarios.len().max(1) as f32;

        json!({
            "total_scenarios": self.scenarios.len(),
            "critical_events": self.events.len(),
            "avg_risk_score": avg_risk,
            "kill_switch_armed": self.kill_switch_armed,
            "recommendation": if avg_risk > 0.7 {
                "HIGH RISK"
            } else {
                "NOMINAL"
            }
        })
    }

    pub fn get_events(&self) -> &Vec<CatastropheEvent> {
        &self.events
    }

    pub fn get_scenarios(&self) -> &Vec<Scenario> {
        &self.scenarios
    }
}

impl Default for CatastropheModel {
    fn default() -> Self {
        Self::new()
    }
}