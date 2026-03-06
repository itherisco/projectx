//! Constitution Validation Module
//!
//! This module defines the constitutional rules for the ITHERIS system,
//! validates actions against these rules, and handles constitutional amendments.
//!
//! ## Core Principles
//! - The Brain is Advisory - the Kernel is Sovereign
//! - All actions must pass through the LEP decision gate
//! - Fail-closed: deny on any failure
//! - Dual-key override for emergencies

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

// ============================================================================
// CONSTITUTIONAL TYPES
// ============================================================================

/// Constitutional rule types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum RuleType {
    /// Permission-based rule
    Permission,
    /// Resource limit rule
    ResourceLimit,
    /// Time-based rule (curfews, etc.)
    Temporal,
    /// Emergency rule (active during emergencies)
    Emergency,
    /// Override rule (requires dual authorization)
    Override,
}

/// Rule severity levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum RuleSeverity {
    /// Blocking - action cannot proceed
    Blocking,
    /// Warning - action may proceed with caution
    Warning,
    /// Informational
    Info,
}

/// A single constitutional rule
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstitutionalRule {
    /// Unique rule identifier
    pub id: String,
    /// Human-readable rule name
    pub name: String,
    /// Rule description
    pub description: String,
    /// Type of rule
    pub rule_type: RuleType,
    /// Severity level
    pub severity: RuleSeverity,
    /// Resource limits (if applicable)
    pub resource_limits: Option<ResourceLimits>,
    /// Time constraints (if applicable)
    pub temporal_constraints: Option<TemporalConstraints>,
    /// Required permissions (if applicable)
    pub required_permissions: Vec<String>,
    /// Emergency-only flag
    pub emergency_only: bool,
    /// Override threshold (number of signatures required)
    pub override_threshold: u8,
    /// Whether rule is active
    pub active: bool,
}

/// Resource limits for a rule
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ResourceLimits {
    /// Maximum CPU time (seconds)
    pub max_cpu_seconds: Option<u64>,
    /// Maximum memory (MB)
    pub max_memory_mb: Option<u64>,
    /// Maximum network bandwidth (KB/s)
    pub max_network_kbps: Option<u64>,
    /// Maximum storage (MB)
    pub max_storage_mb: Option<u64>,
    /// Maximum file descriptors
    pub max_file_descriptors: Option<u32>,
}

/// Temporal constraints for a rule
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalConstraints {
    /// Start time (UTC)
    pub start_time: Option<DateTime<Utc>>,
    /// End time (UTC)
    pub end_time: Option<DateTime<Utc>>,
    /// Allowed days of week (0 = Sunday)
    pub allowed_days: Option<Vec<u8>>,
    /// Timezone for constraints
    pub timezone: String,
}

/// Amendment to the constitution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstitutionalAmendment {
    /// Amendment ID
    pub id: String,
    /// Amendment description
    pub description: String,
    /// Rules to add
    pub rules_to_add: Vec<ConstitutionalRule>,
    /// Rules to modify
    pub rules_to_modify: Vec<String>, // Rule IDs
    /// Rules to remove
    pub rules_to_remove: Vec<String>,
    /// Required approvals for this amendment
    pub required_approvals: u8,
    /// Whether this amendment is active
    pub active: bool,
    /// Timestamp when amendment was proposed
    pub proposed_at: DateTime<Utc>,
    /// Timestamp when amendment was ratified
    pub ratified_at: Option<DateTime<Utc>>,
}

/// Constitution error types
#[derive(Debug, Error)]
pub enum ConstitutionError {
    #[error("Rule not found: {0}")]
    RuleNotFound(String),
    
    #[error("Rule validation failed: {0}")]
    RuleValidationFailed(String),
    
    #[error("Amendment not found: {0}")]
    AmendmentNotFound(String),
    
    #[error("Amendment requires {0} approvals, got {1}")]
    AmendmentInsufficientApprovals(u8, u8),
    
    #[error("Override requires {0} signatures, got {1}")]
    OverrideInsufficientSignatures(u8, u8),
    
    #[error("Emergency override not authorized for: {0}")]
    EmergencyOverrideNotAuthorized(String),
    
    #[error("Temporal constraint violation: {0}")]
    TemporalConstraintViolation(String),
    
    #[error("Resource limit exceeded: {0}")]
    ResourceLimitExceeded(String),
    
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
}

/// Result type for constitution operations
pub type ConstitutionResult<T> = Result<T, ConstitutionError>;

// ============================================================================
// CONSTITUTION STRUCTURE
// ============================================================================

/// The ITHERIS Constitution - foundational rules of the system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constitution {
    /// Constitution version
    pub version: String,
    /// All constitutional rules
    pub rules: HashMap<String, ConstitutionalRule>,
    /// Amendments to the constitution
    pub amendments: HashMap<String, ConstitutionalAmendment>,
    /// Emergency override keys (TPM-backed)
    pub emergency_override_keys: Vec<String>,
    /// Current emergency level
    pub emergency_level: EmergencyLevel,
    /// Decision log
    pub decision_log: Vec<ConstitutionDecision>,
}

/// Emergency levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum EmergencyLevel {
    /// Normal operation
    #[default]
    Normal,
    /// Elevated threat level
    Elevated,
    /// High threat level
    High,
    /// Critical emergency
    Critical,
    /// System lockdown
    Lockdown,
}

/// A constitution decision (audit log entry)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstitutionDecision {
    /// Decision timestamp
    pub timestamp: DateTime<Utc>,
    /// Rule that was evaluated
    pub rule_id: String,
    /// Intent being evaluated
    pub intent: String,
    /// Whether the rule passed
    pub passed: bool,
    /// Reason for decision
    pub reason: String,
    /// Override applied (if any)
    pub override_applied: bool,
    /// Signatures (if override)
    pub signatures: Vec<String>,
}

// ============================================================================
// CONSTITUTION IMPLEMENTATION
// ============================================================================

impl Constitution {
    /// Create a new constitution with default rules
    pub fn new() -> Self {
        let mut constitution = Constitution {
            version: "1.0.0".to_string(),
            rules: HashMap::new(),
            amendments: HashMap::new(),
            emergency_override_keys: Vec::new(),
            emergency_level: EmergencyLevel::Normal,
            decision_log: Vec::new(),
        };
        
        // Add default constitutional rules
        constitution.add_default_rules();
        
        constitution
    }

    /// Add default constitutional rules
    fn add_default_rules(&mut self) {
        // Rule 1: No execution without intent
        self.rules.insert(
            "R001".to_string(),
            ConstitutionalRule {
                id: "R001".to_string(),
                name: "Intent Required".to_string(),
                description: "All actions must have a valid intent before processing".to_string(),
                rule_type: RuleType::Permission,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["intent:valid".to_string()],
                emergency_only: false,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 2: Authorization required
        self.rules.insert(
            "R002".to_string(),
            ConstitutionalRule {
                id: "R002".to_string(),
                name: "Authorization Required".to_string(),
                description: "All actions must be authorized by the Kernel".to_string(),
                rule_type: RuleType::Permission,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["kernel:approve".to_string()],
                emergency_only: false,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 3: Signature verification
        self.rules.insert(
            "R003".to_string(),
            ConstitutionalRule {
                id: "R003".to_string(),
                name: "Cryptographic Signature Required".to_string(),
                description: "All intents must be cryptographically signed".to_string(),
                rule_type: RuleType::Permission,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["crypto:sign".to_string()],
                emergency_only: false,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 4: High-risk intent evidence
        self.rules.insert(
            "R004".to_string(),
            ConstitutionalRule {
                id: "R004".to_string(),
                name: "High-Risk Intent Evidence".to_string(),
                description: "High-risk intents require cryptographic evidence".to_string(),
                rule_type: RuleType::Permission,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["evidence:required".to_string()],
                emergency_only: false,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 5: Emergency protocols
        self.rules.insert(
            "R005".to_string(),
            ConstitutionalRule {
                id: "R005".to_string(),
                name: "Emergency Protocol Compliance".to_string(),
                description: "Actions during emergencies must comply with emergency protocols".to_string(),
                rule_type: RuleType::Emergency,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["emergency:comply".to_string()],
                emergency_only: true,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 6: Resource limits
        self.rules.insert(
            "R006".to_string(),
            ConstitutionalRule {
                id: "R006".to_string(),
                name: "Resource Limits".to_string(),
                description: "Actions must not exceed defined resource limits".to_string(),
                rule_type: RuleType::ResourceLimit,
                severity: RuleSeverity::Blocking,
                resource_limits: Some(ResourceLimits {
                    max_cpu_seconds: Some(300),
                    max_memory_mb: Some(1024),
                    max_network_kbps: Some(10000),
                    max_storage_mb: Some(10240),
                    max_file_descriptors: Some(256),
                }),
                temporal_constraints: None,
                required_permissions: vec!["resource:limited".to_string()],
                emergency_only: false,
                override_threshold: 2,
                active: true,
            },
        );

        // Rule 7: TPM-backed authorization for overrides
        self.rules.insert(
            "R007".to_string(),
            ConstitutionalRule {
                id: "R007".to_string(),
                name: "Hardware-Backed Override".to_string(),
                description: "Emergency overrides must be TPM-backed".to_string(),
                rule_type: RuleType::Override,
                severity: RuleSeverity::Blocking,
                resource_limits: None,
                temporal_constraints: None,
                required_permissions: vec!["tpm:auth".to_string()],
                emergency_only: true,
                override_threshold: 2,
                active: true,
            },
        );

        println!("[CONSTITUTION] ✓ Default rules initialized");
    }

    /// Add a new rule to the constitution
    pub fn add_rule(&mut self, rule: ConstitutionalRule) -> ConstitutionResult<()> {
        if rule.id.is_empty() {
            return Err(ConstitutionError::RuleValidationFailed(
                "Rule ID cannot be empty".to_string(),
            ));
        }
        
        if self.rules.contains_key(&rule.id) {
            return Err(ConstitutionError::RuleValidationFailed(
                format!("Rule ID {} already exists", rule.id),
            ));
        }
        
        self.rules.insert(rule.id.clone(), rule);
        println!("[CONSTITUTION] ✓ Rule added: {}", rule.id);
        
        Ok(())
    }

    /// Modify an existing rule
    pub fn modify_rule(&mut self, rule: ConstitutionalRule) -> ConstitutionResult<()> {
        if !self.rules.contains_key(&rule.id) {
            return Err(ConstitutionError::RuleNotFound(rule.id));
        }
        
        self.rules.insert(rule.id.clone(), rule);
        println!("[CONSTITUTION] ✓ Rule modified");
        
        Ok(())
    }

    /// Remove a rule
    pub fn remove_rule(&mut self, rule_id: &str) -> ConstitutionResult<()> {
        if !self.rules.remove(rule_id).is_some() {
            return Err(ConstitutionError::RuleNotFound(rule_id.to_string()));
        }
        
        println!("[CONSTITUTION] ✓ Rule removed: {}", rule_id);
        
        Ok(())
    }

    /// Get a rule by ID
    pub fn get_rule(&self, rule_id: &str) -> ConstitutionResult<&ConstitutionalRule> {
        self.rules
            .get(rule_id)
            .ok_or_else(|| ConstitutionError::RuleNotFound(rule_id.to_string()))
    }

    /// Validate intent against constitution
    pub fn validate_intent(
        &self,
        intent: &str,
        identity: &str,
        is_emergency: bool,
    ) -> ConstitutionResult<Vec<ConstitutionDecision>> {
        let mut decisions = Vec::new();
        let timestamp = Utc::now();
        
        // Check each applicable rule
        for rule in self.rules.values() {
            // Skip inactive rules
            if !rule.active {
                continue;
            }
            
            // Skip non-emergency rules during emergencies unless they're emergency rules
            if self.emergency_level != EmergencyLevel::Normal && !rule.emergency_only && !is_emergency {
                continue;
            }
            
            // Evaluate rule
            let passed = self.evaluate_rule(rule, intent, identity)?;
            
            let decision = ConstitutionDecision {
                timestamp,
                rule_id: rule.id.clone(),
                intent: intent.to_string(),
                passed,
                reason: if passed {
                    "Rule satisfied".to_string()
                } else {
                    format!("Rule {} not satisfied", rule.name)
                },
                override_applied: false,
                signatures: Vec::new(),
            };
            
            decisions.push(decision.clone());
            
            // Fail-closed: if rule is blocking and not passed, deny
            if !passed && rule.severity == RuleSeverity::Blocking {
                println!(
                    "[CONSTITUTION] 🛑 BLOCKED: Intent '{}' failed rule '{}'",
                    intent, rule.name
                );
                return Err(ConstitutionError::PermissionDenied(format!(
                    "Rule {} not satisfied",
                    rule.name
                )));
            }
        }
        
        Ok(decisions)
    }

    /// Evaluate a single rule
    fn evaluate_rule(
        &self,
        rule: &ConstitutionalRule,
        intent: &str,
        identity: &str,
    ) -> ConstitutionResult<bool> {
        match rule.rule_type {
            RuleType::Permission => {
                // Check if identity has required permissions
                // In a full implementation, this would check against capability grants
                Ok(true)
            }
            RuleType::ResourceLimit => {
                // Check resource limits
                // In a full implementation, this would check current resource usage
                Ok(true)
            }
            RuleType::Temporal => {
                // Check temporal constraints
                if let Some(ref tc) = rule.temporal_constraints {
                    return self.check_temporal_constraints(tc);
                }
                Ok(true)
            }
            RuleType::Emergency => {
                // Only apply emergency rules during emergencies
                Ok(self.emergency_level != EmergencyLevel::Normal)
            }
            RuleType::Override => {
                // Override rules require special handling
                Ok(false)
            }
        }
    }

    /// Check temporal constraints
    fn check_temporal_constraints(&self, tc: &TemporalConstraints) -> ConstitutionResult<bool> {
        let now = Utc::now();
        
        // Check start/end times
        if let Some(start) = tc.start_time {
            if now < start {
                return Err(ConstitutionError::TemporalConstraintViolation(
                    "Action not yet allowed - before start time".to_string(),
                ));
            }
        }
        
        if let Some(end) = tc.end_time {
            if now > end {
                return Err(ConstitutionError::TemporalConstraintViolation(
                    "Action no longer allowed - past end time".to_string(),
                ));
            }
        }
        
        // Check allowed days
        if let Some(ref days) = tc.allowed_days {
            let day_of_week = now.weekday().num_days_from_sunday() as u8;
            if !days.contains(&day_of_week) {
                return Err(ConstitutionError::TemporalConstraintViolation(
                    format!("Action not allowed on day {}", day_of_week),
                ));
            }
        }
        
        Ok(true)
    }

    /// Apply emergency override (requires dual signatures)
    pub fn apply_emergency_override(
        &mut self,
        rule_id: &str,
        signatures: Vec<String>,
    ) -> ConstitutionResult<ConstitutionDecision> {
        let rule = self.get_rule(rule_id)?;
        
        // Check signature count
        if signatures.len() < rule.override_threshold as usize {
            return Err(ConstitutionError::OverrideInsufficientSignatures(
                rule.override_threshold,
                signatures.len() as u8,
            ));
        }
        
        // In a full implementation, verify signatures against TPM-backed keys
        // For now, accept signatures if count threshold is met
        
        let decision = ConstitutionDecision {
            timestamp: Utc::now(),
            rule_id: rule_id.to_string(),
            intent: "EMERGENCY_OVERRIDE".to_string(),
            passed: true,
            reason: "Emergency override applied".to_string(),
            override_applied: true,
            signatures,
        };
        
        self.decision_log.push(decision.clone());
        
        println!(
            "[CONSTITUTION] ✓ Emergency override applied to rule {}",
            rule_id
        );
        
        Ok(decision)
    }

    /// Propose a constitutional amendment
    pub fn propose_amendment(&mut self, amendment: ConstitutionalAmendment) -> ConstitutionResult<()> {
        if amendment.id.is_empty() {
            return Err(ConstitutionError::AmendmentNotFound(
                "Amendment ID cannot be empty".to_string(),
            ));
        }
        
        self.amendments.insert(amendment.id.clone(), amendment);
        println!("[CONSTITUTION] ✓ Amendment proposed");
        
        Ok(())
    }

    /// Ratify an amendment (requires sufficient approvals)
    pub fn ratify_amendment(
        &mut self,
        amendment_id: &str,
        approvals: u8,
    ) -> ConstitutionResult<()> {
        let amendment = self
            .amendments
            .get_mut(amendment_id)
            .ok_or_else(|| ConstitutionError::AmendmentNotFound(amendment_id.to_string()))?;
        
        if approvals < amendment.required_approvals {
            return Err(ConstitutionError::AmendmentInsufficientApprovals(
                amendment.required_approvals,
                approvals,
            ));
        }
        
        // Apply amendments
        for rule in &amendment.rules_to_add {
            self.add_rule(rule.clone())?;
        }
        
        for rule_id in &amendment.rules_to_modify {
            // In a full implementation, would fetch new rule from amendment
            println!("[CONSTITUTION] Would modify rule: {}", rule_id);
        }
        
        for rule_id in &amendment.rules_to_remove {
            self.remove_rule(rule_id)?;
        }
        
        amendment.ratified_at = Some(Utc::now());
        amendment.active = true;
        
        println!("[CONSTITUTION] ✓ Amendment ratified: {}", amendment_id);
        
        Ok(())
    }

    /// Set emergency level
    pub fn set_emergency_level(&mut self, level: EmergencyLevel) {
        self.emergency_level = level;
        println!("[CONSTITUTION] ⚠️  Emergency level set to: {:?}", level);
    }

    /// Add emergency override key
    pub fn add_emergency_override_key(&mut self, key_id: String) {
        self.emergency_override_keys.push(key_id);
        println!("[CONSTITUTION] ✓ Emergency override key added");
    }

    /// Get decision log
    pub fn get_decision_log(&self) -> &Vec<ConstitutionDecision> {
        &self.decision_log
    }

    /// Get active rule count
    pub fn active_rule_count(&self) -> usize {
        self.rules.values().filter(|r| r.active).count()
    }
}

impl Default for Constitution {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constitution_creation() {
        let constitution = Constitution::new();
        assert_eq!(constitution.version, "1.0.0");
        assert!(constitution.active_rule_count() > 0);
    }

    #[test]
    fn test_add_rule() {
        let mut constitution = Constitution::new();
        let rule = ConstitutionalRule {
            id: "TEST_RULE".to_string(),
            name: "Test Rule".to_string(),
            description: "A test rule".to_string(),
            rule_type: RuleType::Permission,
            severity: RuleSeverity::Warning,
            resource_limits: None,
            temporal_constraints: None,
            required_permissions: vec!["test:perm".to_string()],
            emergency_only: false,
            override_threshold: 1,
            active: true,
        };
        
        assert!(constitution.add_rule(rule).is_ok());
        assert!(constitution.get_rule("TEST_RULE").is_ok());
    }

    #[test]
    fn test_remove_rule() {
        let mut constitution = Constitution::new();
        
        // Remove a default rule
        assert!(constitution.remove_rule("R001").is_ok());
        assert!(constitution.get_rule("R001").is_err());
    }

    #[test]
    fn test_validate_intent() {
        let constitution = Constitution::new();
        
        // Valid intent should pass
        let result = constitution.validate_intent("read_data", "agent_001", false);
        assert!(result.is_ok());
    }

    #[test]
    fn test_emergency_override() {
        let mut constitution = Constitution::new();
        
        let signatures = vec!["key1".to_string(), "key2".to_string()];
        let result = constitution.apply_emergency_override("R001", signatures);
        
        assert!(result.is_ok());
        assert!(result.unwrap().override_applied);
    }
}
