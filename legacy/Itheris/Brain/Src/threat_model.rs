//! Threat Modeling - MITRE ATT&CK-style threat assessment and simulation

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;

/// A threat
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Threat {
    pub id: String,
    pub name: String,
    pub category: String,
    pub severity: f32,
    pub probability: f32,
    pub attack_vector: String,
    pub mitigation: String,
    pub detection_method: String,
}

/// Attack simulation
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AttackSimulation {
    pub threat_id: String,
    pub scenario: String,
    pub simulated_impact: Value,
    pub defense_response: String,
    pub success_probability: f32,
}

/// Threat modeling engine
pub struct ThreatModel {
    threats: HashMap<String, Threat>,
    simulations: Vec<AttackSimulation>,
}

impl ThreatModel {
    pub fn new() -> Self {
        let mut model = ThreatModel {
            threats: HashMap::new(),
            simulations: Vec::new(),
        };

        // Register MITRE ATT&CK threats
        model.register_threat(Threat {
            id: "T1001".to_string(),
            name: "Data Obfuscation".to_string(),
            category: "EXTERNAL".to_string(),
            severity: 0.7,
            probability: 0.15,
            attack_vector: "False data injection into sensor stream".to_string(),
            mitigation: "Cryptographic validation of all inputs".to_string(),
            detection_method: "Anomaly detection in state transitions".to_string(),
        });

        model.register_threat(Threat {
            id: "T1014".to_string(),
            name: "Rootkit".to_string(),
            category: "INTERNAL".to_string(),
            severity: 0.95,
            probability: 0.02,
            attack_vector: "Kernel-level access, decision logic modification".to_string(),
            mitigation: "Code signing, secure boot, memory protection".to_string(),
            detection_method: "Ledger hash verification, unexpected capability grants".to_string(),
        });

        model.register_threat(Threat {
            id: "T1557".to_string(),
            name: "Man-in-the-Middle".to_string(),
            category: "EXTERNAL".to_string(),
            severity: 0.8,
            probability: 0.12,
            attack_vector: "Intercept and modify inter-agent messages".to_string(),
            mitigation: "End-to-end encryption, message signing".to_string(),
            detection_method: "Signature verification failure".to_string(),
        });

        model
    }

    pub fn register_threat(&mut self, threat: Threat) {
        println!(
            "[THREAT_MODEL] ✓ Registered: {} (severity: {})",
            threat.name, threat.severity
        );
        self.threats.insert(threat.id.clone(), threat);
    }

    /// Simulate an attack
    pub fn simulate_attack(
        &mut self,
        threat_id: &str,
        scenario: String,
    ) -> Result<AttackSimulation, String> {
        let threat = self
            .threats
            .get(threat_id)
            .ok_or(format!("Threat not found: {}", threat_id))?
            .clone();

        let mitigation_effectiveness = 0.92;
        let success_prob = (threat.probability * (1.0 - mitigation_effectiveness)).max(0.0);

        let simulated_impact = json!({
            "threat": threat.name,
            "initial_probability": threat.probability,
            "mitigated_probability": success_prob,
            "scenario": scenario,
            "estimated_damage": if success_prob > 0.5 { "HIGH" } else { "LOW" }
        });

        let simulation = AttackSimulation {
            threat_id: threat.id.clone(),
            scenario,
            simulated_impact,
            defense_response: threat.mitigation.clone(),
            success_probability: success_prob,
        };

        self.simulations.push(simulation.clone());

        println!(
            "[THREAT_MODEL] ✓ Simulated attack: {} (success prob: {:.1}%)",
            threat.name,
            success_prob * 100.0
        );

        Ok(simulation)
    }

    pub fn threat_landscape(&self) -> Value {
        let mut high_risk = vec![];
        let mut medium_risk = vec![];
        let mut low_risk = vec![];

        for threat in self.threats.values() {
            let risk_score = threat.severity * threat.probability;
            let threat_info = json!({
                "name": threat.name,
                "category": threat.category,
                "risk_score": risk_score,
                "mitigation": threat.mitigation
            });

            if risk_score > 0.5 {
                high_risk.push(threat_info);
            } else if risk_score > 0.2 {
                medium_risk.push(threat_info);
            } else {
                low_risk.push(threat_info);
            }
        }

        json!({
            "high_risk": high_risk,
            "medium_risk": medium_risk,
            "low_risk": low_risk,
            "total_threats": self.threats.len(),
            "overall_posture": "HARDENED"
        })
    }

    pub fn get_threats(&self) -> &HashMap<String, Threat> {
        &self.threats
    }

    pub fn get_simulations(&self) -> &Vec<AttackSimulation> {
        &self.simulations
    }
}

impl Default for ThreatModel {
    fn default() -> Self {
        Self::new()
    }
}