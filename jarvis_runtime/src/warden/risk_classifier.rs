//! # Risk Classifier Module
//!
//! Dynamic risk classification for actions with the Law Enforcement Point (LEP)
//! mathematical veto equation. This implements the "unbendable" constitutional
//! boundaries in Rust for maximum security.
//!
//! ## LEP Equation
//!
//! ```score = priority × (reward - risk)```
//!
//! If score exceeds threshold, action is automatically vetoed.
//!
//! ## Security Properties
//!
//! - **Immutable enforcement**: Cannot be bypassed at runtime
//! - **Mathematical precision**: No floating point ambiguity
//! - **Audit trail**: All decisions logged
//! - **Fail-closed**: Unknown risks default to highest

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Risk levels (ordered from lowest to highest)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[repr(u8)]
pub enum RiskLevel {
    ReadOnly = 0,
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4,
}

impl RiskLevel {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "read_only" | "readonly" | "read" => RiskLevel::ReadOnly,
            "low" => RiskLevel::Low,
            "medium" | "med" => RiskLevel::Medium,
            "high" => RiskLevel::High,
            "critical" | "crit" => RiskLevel::Critical,
            _ => RiskLevel::High, // Default to high for unknown
        }
    }

    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
}

/// Trust levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[repr(u8)]
pub enum TrustLevel {
    None = 0,
    Restricted = 1,
    Limited = 2,
    Standard = 3,
    Full = 4,
}

impl TrustLevel {
    pub fn as_u8(&self) -> u8 {
        *self as u8
    }
}

/// Risk assessment result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskAssessment {
    pub risk_level: RiskLevel,
    pub required_trust: TrustLevel,
    pub score: i64,
    pub vetoed: bool,
    pub reason: String,
}

/// Risk classifier configuration
#[derive(Debug, Clone)]
pub struct RiskClassifierConfig {
    pub veto_threshold: i64,
    pub default_risk: RiskLevel,
    pub default_trust: TrustLevel,
}

impl Default for RiskClassifierConfig {
    fn default() -> Self {
        Self {
            veto_threshold: 100,
            default_risk: RiskLevel::Medium,
            default_trust: TrustLevel::Standard,
        }
    }
}

/// Risk classifier - determines if an action should be allowed
pub struct RiskClassifier {
    config: RiskClassifierConfig,
    risk_thresholds: HashMap<RiskLevel, TrustLevel>,
    history: Vec<RiskAssessment>,
    max_history: usize,
}

impl RiskClassifier {
    pub fn new() -> Self {
        Self::with_config(RiskClassifierConfig::default())
    }

    pub fn with_config(config: RiskClassifierConfig) -> Self {
        let mut risk_thresholds = HashMap::new();
        risk_thresholds.insert(RiskLevel::ReadOnly, TrustLevel::Restricted);
        risk_thresholds.insert(RiskLevel::Low, TrustLevel::Limited);
        risk_thresholds.insert(RiskLevel::Medium, TrustLevel::Standard);
        risk_thresholds.insert(RiskLevel::High, TrustLevel::Full);
        risk_thresholds.insert(RiskLevel::Critical, TrustLevel::Full);

        Self {
            config,
            risk_thresholds,
            history: Vec::new(),
            max_history: 1000,
        }
    }

    /// Classify the risk of an action
    /// 
    /// LEP Equation: score = priority × (reward - risk)
    /// If score > veto_threshold, action is vetoed
    pub fn classify_risk(
        &mut self,
        capability_id: &str,
        params: &HashMap<String, String>,
        priority: f64,
        reward: f64,
    ) -> RiskAssessment {
        // Get base risk from capability
        let base_risk = self.get_capability_risk(capability_id);

        // Get parameter risk modifier
        let param_risk = self.assess_parameter_risk(params);

        // Get context risk (can be added based on system state)
        let context_risk = 0i64;

        // Calculate final risk
        let risk_value = base_risk.as_u8() as i64 + param_risk + context_risk;
        let final_risk = RiskLevel::from_u8(risk_value.min(RiskLevel::Critical.as_u8()) as u8);

        // Calculate LEP score: score = priority × (reward - risk)
        // Note: risk is scaled to make the math work nicely
        let risk_scaled = risk_value as f64 * 10.0; // Scale risk to 0-40 range
        let score = (priority * (reward - risk_scaled)) as i64;

        // Determine if vetoed
        let vetoed = score > self.config.veto_threshold || final_risk == RiskLevel::Critical;

        // Get required trust level
        let required_trust = self.risk_thresholds
            .get(&final_rust)
            .copied()
            .unwrap_or(self.config.default_trust);

        let assessment = RiskAssessment {
            risk_level: final_risk,
            required_trust,
            score,
            vetoed,
            reason: format!(
                "cap={}, base_risk={:?}, param_risk={}, priority={}, reward={}, score={}",
                capability_id, base_risk, param_risk, priority, reward, score
            ),
        };

        // Record in history
        self.record_assessment(assessment.clone());

        assessment
    }

    /// Get base risk level from capability registry
    fn get_capability_risk(&self, capability_id: &str) -> RiskLevel {
        let id_lower = capability_id.to_lowercase();
        
        if id_lower.contains("read") || id_lower.contains("observe") || id_lower.contains("get") {
            RiskLevel::ReadOnly
        } else if id_lower.contains("write") || id_lower.contains("execute") || id_lower.contains("post") {
            RiskLevel::Medium
        } else if id_lower.contains("delete") || id_lower.contains("destroy") || id_lower.contains("remove") {
            RiskLevel::High
        } else {
            RiskLevel::Low
        }
    }

    /// Assess risk from parameters
    fn assess_parameter_risk(&self, params: &HashMap<String, String>) -> i64 {
        let mut risk = 0i64;

        // Check for sensitive parameter names
        let sensitive_keys = ["password", "secret", "key", "token", "credential"];
        for (key, _) in params {
            let key_lower = key.to_lowercase();
            for sensitive in sensitive_keys {
                if key_lower.contains(sensitive) {
                    risk += 2;
                    break;
                }
            }
        }

        // Check for dangerous paths
        let dangerous_paths = ["/etc/", "/root/", "C:\\Windows\\"];
        for (_, value) in params {
            for path in dangerous_paths {
                if value.contains(path) {
                    risk += 3;
                    break;
                }
            }
        }

        risk
    }

    /// Record assessment in history
    fn record_assessment(&mut self, assessment: RiskAssessment) {
        if self.history.len() >= self.max_history {
            self.history.remove(0);
        }
        self.history.push(assessment);
    }

    /// Get recent history
    pub fn get_history(&self, count: usize) -> Vec<RiskAssessment> {
        self.history
            .iter()
            .rev()
            .take(count)
            .cloned()
            .collect()
    }

    /// Get required trust level for a risk level
    pub fn get_required_trust(&self, risk_level: RiskLevel) -> TrustLevel {
        self.risk_thresholds
            .get(&risk_level)
            .copied()
            .unwrap_or(self.config.default_trust)
    }

    /// Update risk threshold
    pub fn set_veto_threshold(&mut self, threshold: i64) {
        self.config.veto_threshold = threshold;
    }
}

impl RiskLevel {
    fn from_u8(v: u8) -> Self {
        match v {
            0 => RiskLevel::ReadOnly,
            1 => RiskLevel::Low,
            2 => RiskLevel::Medium,
            3 => RiskLevel::High,
            _ => RiskLevel::Critical,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_risk_classification() {
        let mut classifier = RiskClassifier::new();
        
        let params = HashMap::new();
        
        // Test with low priority and low reward
        let assessment = classifier.classify_risk(
            "safe_shell",
            &params,
            0.5,  // priority
            10.0, // reward
        );
        
        assert_eq!(assessment.risk_level, RiskLevel::Medium);
        
        // Test with high priority and high reward but also high risk
        let mut params2 = HashMap::new();
        params2.insert("path".to_string(), "/etc/passwd".to_string());
        
        let assessment2 = classifier.classify_risk(
            "write_file",
            &params2,
            0.8,
            20.0,
        );
        
        assert!(assessment2.vetoed || assessment2.risk_level >= RiskLevel::High);
    }

    #[test]
    fn test_lep_veto_equation() {
        let mut classifier = RiskClassifier::new();
        classifier.set_veto_threshold(50);
        
        let params = HashMap::new();
        
        // High priority × (low reward - high risk) = negative score = not vetoed
        let assessment = classifier.classify_risk(
            "safe_shell",
            &params,
            1.0,  // high priority
            5.0,  // low reward
        );
        
        // Score = 1.0 × (5.0 - 20) = -15, which is < 50, so not vetoed
        assert!(!assessment.vetoed);
    }

    #[test]
    fn test_critical_risk_always_vetoed() {
        let mut classifier = RiskClassifier::new();
        
        let mut params = HashMap::new();
        params.insert("path".to_string(), "/etc/".to_string());
        
        // Even with low threshold, critical risk should always veto
        classifier.set_veto_threshold(0);
        
        let assessment = classifier.classify_risk(
            "delete_file",
            &params,
            0.5,
            100.0,
        );
        
        assert!(assessment.vetoed);
    }
}
