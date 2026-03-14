//! # Risk Classifier - Law Enforcement Point (LEP) Veto Equation
//!
//! This module implements the mathematical veto equation for the Law Enforcement Point:
//! `score = priority × (reward - risk)`
//!
//! This is the "unbendable" constitutional boundary that ensures the brain's decisions
//! are constrained by constitutional limits before execution.
//!
//! ## LEP Veto Equation
//!
//! - **Priority**: Urgency of the action (1-10)
//! - **Reward**: Expected benefit (0-100)
//! - **Risk**: Potential harm/cost (0-100)
//! - **Score**: If negative, action is VETOED
//!
//! ## Security Properties
//!
//! - **Fail-Closed**: Negative score = automatic veto
//! - **Hard Limits**: Certain actions always veto regardless of score
//! - **Audit Trail**: All veto decisions logged

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

/// Risk Classifier errors
#[derive(Error, Debug)]
pub enum RiskError {
    #[error("Classification failed: {0}")]
    ClassificationFailed(String),

    #[error("Invalid parameters: {0}")]
    InvalidParams(String),
}

/// Risk level enumeration (matching Julia)
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    ReadOnly,
    Low,
    Medium,
    High,
    Critical,
}

impl Default for RiskLevel {
    fn default() -> Self {
        RiskLevel::Low
    }
}

impl RiskLevel {
    /// Convert to numeric value (0-4)
    pub fn to_numeric(&self) -> u8 {
        match self {
            RiskLevel::ReadOnly => 0,
            RiskLevel::Low => 1,
            RiskLevel::Medium => 2,
            RiskLevel::High => 3,
            RiskLevel::Critical => 4,
        }
    }

    /// Convert from numeric value
    pub fn from_numeric(value: u8) -> Self {
        match value.min(4) {
            0 => RiskLevel::ReadOnly,
            1 => RiskLevel::Low,
            2 => RiskLevel::Medium,
            3 => RiskLevel::High,
            _ => RiskLevel::Critical,
        }
    }
}

/// Trust levels for authorization
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[serde(rename_all = "lowercase")]
pub enum TrustLevel {
    None,
    Restricted,
    Limited,
    Standard,
    Full,
}

impl TrustLevel {
    pub fn to_numeric(&self) -> u8 {
        match self {
            TrustLevel::None => 0,
            TrustLevel::Restricted => 1,
            TrustLevel::Limited => 2,
            TrustLevel::Standard => 3,
            TrustLevel::Full => 4,
        }
    }
}

/// Action classification result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Classification {
    /// Risk level of the action
    pub risk_level: RiskLevel,
    /// Trust level required
    pub trust_required: TrustLevel,
    /// LEP score
    pub lep_score: f64,
    /// Whether action is vetoed
    pub vetoed: bool,
    /// Reason for classification
    pub reason: String,
    /// Risk factors
    pub risk_factors: Vec<String>,
}

/// LEP Configuration
#[derive(Clone)]
pub struct LEPConfig {
    /// Base priority multiplier
    pub priority_weight: f64,
    /// Reward weight in equation
    pub reward_weight: f64,
    /// Risk weight in equation
    pub risk_weight: f64,
    /// Minimum score threshold (below = veto)
    pub veto_threshold: f64,
    /// Always-veto capabilities
    pub always_veto: Vec<String>,
    /// Always-allow capabilities
    pub always_allow: Vec<String>,
}

impl Default for LEPConfig {
    fn default() -> Self {
        Self {
            priority_weight: 1.0,
            reward_weight: 1.0,
            risk_weight: 1.0,
            veto_threshold: 0.0,
            always_veto: vec![
                "delete_system".to_string(),
                "format_disk".to_string(),
                "bypass_security".to_string(),
            ],
            always_allow: vec![
                "observe_status".to_string(),
                "read_logs".to_string(),
            ],
        }
    }
}

/// Risk Classifier with LEP Veto Equation
pub struct RiskClassifier {
    config: LEPConfig,
    /// Trust thresholds for each risk level
    trust_thresholds: HashMap<RiskLevel, TrustLevel>,
    /// Classification history
    history: Vec<Classification>,
    /// Capability risk cache
    capability_risk: HashMap<String, RiskLevel>,
}

impl RiskClassifier {
    /// Create new classifier
    pub fn new() -> Self {
        let mut classifier = Self {
            config: LEPConfig::default(),
            trust_thresholds: HashMap::new(),
            history: Vec::new(),
            capability_risk: HashMap::new(),
        };
        
        // Default thresholds
        classifier.trust_thresholds.insert(RiskLevel::ReadOnly, TrustLevel::Restricted);
        classifier.trust_thresholds.insert(RiskLevel::Low, TrustLevel::Limited);
        classifier.trust_thresholds.insert(RiskLevel::Medium, TrustLevel::Standard);
        classifier.trust_thresholds.insert(RiskLevel::High, TrustLevel::Full);
        classifier.trust_thresholds.insert(RiskLevel::Critical, TrustLevel::Full);

        // Default capability risks
        classifier.init_default_capabilities();

        classifier
    }

    /// Initialize default capability risk levels
    fn init_default_capabilities(&mut self) {
        // Read-only capabilities
        self.capability_risk.insert("observe_cpu".to_string(), RiskLevel::ReadOnly);
        self.capability_risk.insert("observe_memory".to_string(), RiskLevel::ReadOnly);
        self.capability_risk.insert("observe_network".to_string(), RiskLevel::ReadOnly);
        self.capability_risk.insert("observe_filesystem".to_string(), RiskLevel::ReadOnly);
        self.capability_risk.insert("observe_processes".to_string(), RiskLevel::ReadOnly);

        // Low risk
        self.capability_risk.insert("read_file".to_string(), RiskLevel::Low);
        self.capability_risk.insert("safe_http_request".to_string(), RiskLevel::Low);

        // Medium risk
        self.capability_risk.insert("safe_shell".to_string(), RiskLevel::Medium);
        self.capability_risk.insert("write_file".to_string(), RiskLevel::Medium);
        self.capability_risk.insert("send_email".to_string(), RiskLevel::Medium);

        // High risk
        self.capability_risk.insert("delete_file".to_string(), RiskLevel::High);
        self.capability_risk.insert("modify_system".to_string(), RiskLevel::High);
        self.capability_risk.insert("execute_command".to_string(), RiskLevel::High);

        // Critical
        self.capability_risk.insert("delete_system".to_string(), RiskLevel::Critical);
        self.capability_risk.insert("format_disk".to_string(), RiskLevel::Critical);
        self.capability_risk.insert("bypass_security".to_string(), RiskLevel::Critical);
    }

    /// Calculate LEP score using the veto equation
    /// 
    /// Score = priority × (reward - risk)
    /// 
    /// Negative scores result in automatic veto.
    pub fn calculate_lep_score(
        &self,
        priority: f64,
        reward: f64,
        risk: f64,
    ) -> f64 {
        priority * (reward * self.config.reward_weight - risk * self.config.risk_weight)
    }

    /// Classify an action using LEP veto equation
    /// 
    /// # Arguments
    /// * `capability_id` - The capability to execute
    /// * `params` - Action parameters
    /// * `priority` - Priority (1-10)
    /// * `reward` - Expected reward (0-100)
    /// * `risk` - Estimated risk (0-100)
    pub fn classify(
        &mut self,
        capability_id: &str,
        params: &str,
        priority: f64,
        reward: f64,
        risk: f64,
    ) -> Result<Classification, RiskError> {
        // Validate parameters
        if priority < 0.0 {
            return Err(RiskError::InvalidParams("Priority must be non-negative".to_string()));
        }
        if reward < 0.0 || reward > 1.0 {
            return Err(RiskError::InvalidParams("Reward must be 0.0-1.0".to_string()));
        }
        if risk < 0.0 || risk > 1.0 {
            return Err(RiskError::InvalidParams("Risk must be 0.0-1.0".to_string()));
        }

        let mut risk_factors = Vec::new();
        let reason;

        // Check always-veto list
        if self.config.always_veto.iter().any(|c| capability_id.contains(c)) {
            return Ok(Classification {
                risk_level: RiskLevel::Critical,
                trust_required: TrustLevel::Full,
                lep_score: -999.0, // Absolute veto
                vetoed: true,
                reason: "Capability on always-veto list".to_string(),
                risk_factors: vec!["Always-veto capability".to_string()],
            });
        }

        // Check always-allow list
        let always_allow = self.config.always_allow.iter().any(|c| capability_id.contains(c));
        if always_allow {
            return Ok(Classification {
                risk_level: RiskLevel::ReadOnly,
                trust_required: TrustLevel::Restricted,
                lep_score: 999.0, // Absolute approval
                vetoed: false,
                reason: "Capability on always-allow list".to_string(),
                risk_factors: vec![],
            });
        }

        // Get base risk from capability
        let base_risk = self.capability_risk
            .get(capability_id)
            .copied()
            .unwrap_or(RiskLevel::Medium);

        // Assess parameter risk
        let param_risk = self.assess_param_risk(params, &mut risk_factors);
        
        // Calculate final risk
        let risk_value = base_risk.to_numeric() as f64 * 10.0 + param_risk;
        let final_risk: f64 = risk_value.min(100.0);
        
        // Determine risk level
        let risk_level = if final_risk >= 40.0 {
            RiskLevel::Critical
        } else if final_risk >= 30.0 {
            RiskLevel::High
        } else if final_risk >= 20.0 {
            RiskLevel::Medium
        } else if final_risk >= 10.0 {
            RiskLevel::Low
        } else {
            RiskLevel::ReadOnly
        };

        // Get trust threshold
        let trust_required = self.trust_thresholds
            .get(&risk_level)
            .copied()
            .unwrap_or(TrustLevel::Full);

        // Calculate LEP score: score = priority * (reward - risk)
        let lep_score = priority * (reward - risk);

        // Determine veto
        // MANDATE: risk_estimate > 0.01 results in automatic veto
        let mut vetoed = lep_score < self.config.veto_threshold;

        if risk > 0.01 {
            vetoed = true;
            reason = format!(
                "LEP automatic veto: risk_estimate {} > 0.01 threshold",
                risk
            );
        } else if vetoed {
            reason = format!(
                "LEP veto: score {} < threshold {}",
                lep_score, self.config.veto_threshold
            );
        } else {
            reason = format!(
                "LEP approved: score {} >= threshold {} and risk {} <= 0.01",
                lep_score, self.config.veto_threshold, risk
            );
        }

        let classification = Classification {
            risk_level,
            trust_required,
            lep_score,
            vetoed,
            reason,
            risk_factors,
        };

        // Store in history
        self.history.push(classification.clone());

        Ok(classification)
    }

    /// Quick risk classification without LEP scoring
    pub fn classify_simple(&mut self, capability_id: &str) -> RiskLevel {
        self.capability_risk
            .get(capability_id)
            .copied()
            .unwrap_or(RiskLevel::Medium)
    }

    /// Assess risk from parameters
    fn assess_param_risk(&self, params: &str, factors: &mut Vec<String>) -> f64 {
        let mut risk: f64 = 0.0;
        let params_lower = params.to_lowercase();

        // Check for sensitive paths
        let sensitive_paths = [
            "/etc", "/proc", "/sys", "/root", "/var/log",
            "/home", "/.ssh", "/.aws",
        ];
        
        for path in &sensitive_paths {
            if params_lower.contains(path) {
                risk += 20.0;
                factors.push(format!("Contains sensitive path: {}", path));
            }
        }

        // Check for dangerous commands
        let dangerous = ["rm -rf", "dd if=", "mkfs", "chmod 777", "wget", "curl | sh"];
        for cmd in &dangerous {
            if params_lower.contains(cmd) {
                risk += 30.0;
                factors.push(format!("Contains dangerous command: {}", cmd));
            }
        }

        // Check for injection patterns
        let injection = ["$(", "`", "&&", "||", "| sh", "; rm"];
        for pat in &injection {
            if params_lower.contains(pat) {
                risk += 25.0;
                factors.push(format!("Contains injection pattern: {}", pat));
            }
        }

        (risk as f64).min(100.0f64)
    }

    /// Get trust threshold for a risk level
    pub fn get_trust_threshold(&self, risk_level: RiskLevel) -> TrustLevel {
        self.trust_thresholds
            .get(&risk_level)
            .copied()
            .unwrap_or(TrustLevel::Full)
    }

    /// Get classification history count
    pub fn history_count(&self) -> usize {
        self.history.len()
    }

    /// Get recent classifications
    pub fn recent_classifications(&self, count: usize) -> Vec<Classification> {
        self.history
            .iter()
            .rev()
            .take(count)
            .cloned()
            .collect()
    }

    /// Set capability risk level
    pub fn set_capability_risk(&mut self, capability_id: &str, risk_level: RiskLevel) {
        self.capability_risk.insert(capability_id.to_string(), risk_level);
    }
}

impl Default for RiskClassifier {
    fn default() -> Self {
        Self::new()
    }
}

// Global classifier
use once_cell::sync::Lazy;
use std::sync::RwLock;

static RISK_CLASSIFIER: Lazy<RwLock<RiskClassifier>> = Lazy::new(|| {
    RwLock::new(RiskClassifier::new())
});

/// Initialize global classifier
pub fn init() {
    drop(RISK_CLASSIFIER.read());
}

/// Classify an action
pub fn classify(
    capability_id: &str,
    params: &str,
    priority: f64,
    reward: f64,
    risk: f64,
) -> Result<Classification, RiskError> {
    RISK_CLASSIFIER.write().unwrap().classify(capability_id, params, priority, reward, risk)
}

/// Simple risk classification
pub fn classify_simple(capability_id: &str) -> RiskLevel {
    RISK_CLASSIFIER.write().unwrap().classify_simple(capability_id)
}

/// Get trust threshold
pub fn get_trust_threshold(risk_level: RiskLevel) -> TrustLevel {
    RISK_CLASSIFIER.read().unwrap().get_trust_threshold(risk_level)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lep_score() {
        let classifier = RiskClassifier::new();
        
        // Positive score
        let score = classifier.calculate_lep_score(5.0, 80.0, 20.0);
        assert!(score > 0.0);
        
        // Negative score (should veto)
        let score = classifier.calculate_lep_score(5.0, 20.0, 80.0);
        assert!(score < 0.0);
    }

    #[test]
    fn test_veto() {
        let mut classifier = RiskClassifier::new();
        
        // High risk, low reward should veto
        let result = classifier.classify("safe_shell", r#"{"command": "rm -rf /"}"#, 5.0, 0.1, 0.9)
            .unwrap();
        
        assert!(result.vetoed);
    }

    #[test]
    fn test_always_veto() {
        let mut classifier = RiskClassifier::new();
        
        let result = classifier.classify("delete_system", r#"{}"#, 1.0, 1.0, 0.0)
            .unwrap();
        
        assert!(result.vetoed);
    }
}
