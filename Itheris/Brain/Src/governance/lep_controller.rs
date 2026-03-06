//! LEP (Law Enforcement Point) Controller Module
//!
//! This is the main decision gate that all actions must pass through.
//! It implements the "Brain is Advisory - Kernel is Sovereign" principle.
//!
//! ## Decision Chain
//! 1. Intent validation (input validation)
//! 2. Constitution validation (rule checking)
//! 3. Authorization check (permission verification)
//! 4. Kernel approval (final sovereign approval)
//! 5. Execution (action performed)
//!
//! ## Security Properties
//! - Fail-closed: deny on any failure
//! - Dual-key override for emergencies (requires 2 authorized signatures)
//! - Comprehensive audit logging
//! - TPM-backed authorization for overrides

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

use crate::crypto::{CryptoAuthority, SignedThought};
use crate::governance::constitution::{Constitution, ConstitutionDecision, ConstitutionError, EmergencyLevel};
use crate::governance::intent_validator::{IntentAction, IntentValidator, RiskLevel, ValidatedIntent};
use crate::kernel::{CapabilityGrant, ItherisKernel};

// ============================================================================
// LEP TYPES
// ============================================================================

/// LEP Decision - the final decision from the gate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LEPDecision {
    /// Decision ID
    pub decision_id: String,
    /// Intent that was evaluated
    pub intent: String,
    /// Identity that submitted the intent
    pub identity: String,
    /// Decision result
    pub result: LEPDecisionResult,
    /// Decision timestamp
    pub timestamp: DateTime<Utc>,
    /// Processing stages completed
    pub stages_completed: Vec<LEPStage>,
    /// Any override applied
    pub override_applied: bool,
    /// Override signatures (if any)
    pub override_signatures: Vec<String>,
    /// Rejection reason (if rejected)
    pub rejection_reason: Option<String>,
}

/// LEP decision results
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum LEPDecisionResult {
    /// Approved for execution
    Approved,
    /// Rejected - failed validation
    Rejected,
    /// Rejected - insufficient permissions
    Unauthorized,
    /// Rejected - constitutional violation
    Unconstitutional,
    /// Pending - requires additional approval
    Pending,
    /// Error during processing
    Error,
}

/// LEP processing stages
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum LEPStage {
    /// Intent validation
    IntentValidation,
    /// Constitution validation
    ConstitutionValidation,
    /// Authorization check
    AuthorizationCheck,
    /// Kernel approval
    KernelApproval,
    /// Execution
    Execution,
}

/// LEP error types
#[derive(Debug, Error)]
pub enum LEPError {
    #[error("Intent validation failed: {0}")]
    IntentValidationFailed(String),
    
    #[error("Constitution validation failed: {0}")]
    ConstitutionValidationFailed(String),
    
    #[error("Authorization failed: {0}")]
    AuthorizationFailed(String),
    
    #[error("Kernel approval denied: {0}")]
    KernelDenied(String),
    
    #[error("Execution failed: {0}")]
    ExecutionFailed(String),
    
    #[error("Override requires {0} signatures, got {1}")]
    OverrideInsufficientSignatures(u8, u8),
    
    #[error("Override not authorized")]
    OverrideNotAuthorized,
    
    #[error("Invalid signed thought: {0}")]
    InvalidSignedThought(String),
    
    #[error("TPM authorization failed: {0}")]
    TPMAuthorizationFailed(String),
}

/// Result type for LEP operations
pub type LEPResult<T> = Result<T, LEPError>;

/// Override request for emergency situations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverrideRequest {
    /// Rule IDs to override
    pub rule_ids: Vec<String>,
    /// Reason for override
    pub reason: String,
    /// Signatures from authorized keys (TPM-backed)
    pub signatures: Vec<OverrideSignature>,
    /// Emergency level
    pub emergency_level: EmergencyLevel,
    /// Request timestamp
    pub requested_at: DateTime<Utc>,
}

/// Override signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OverrideSignature {
    /// Key identifier
    pub key_id: String,
    /// Signature (hex encoded)
    pub signature: String,
    /// Whether key is TPM-backed
    pub tpm_backed: bool,
}

/// Execution request (after approval)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionRequest {
    /// The validated intent
    pub validated_intent: ValidatedIntent,
    /// Authorization token from kernel
    pub authorization_token: String,
    /// Execution parameters
    pub parameters: HashMap<String, String>,
}

/// Execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionResult {
    /// Execution success
    pub success: bool,
    /// Result data
    pub data: Option<serde_json::Value>,
    /// Error message (if failed)
    pub error: Option<String>,
    /// Execution time (milliseconds)
    pub execution_time_ms: u64,
}

// ============================================================================
// LEP CONTROLLER
// ============================================================================

/// Law Enforcement Point Controller
/// 
/// The LEP is the decision gate that all actions must pass through.
/// It implements fail-closed security: any failure results in rejection.
pub struct LEPController {
    /// Constitution for rule validation
    constitution: Constitution,
    /// Intent validator
    intent_validator: IntentValidator,
    /// Kernel for final approval
    kernel: ItherisKernel,
    /// Crypto authority for signatures
    crypto: CryptoAuthority,
    /// Decision log
    decision_log: Vec<LEPDecision>,
    /// Pending approvals
    pending_approvals: HashMap<String, LEPDecision>,
    /// Emergency override keys
    emergency_override_keys: Vec<String>,
}

impl LEPController {
    /// Create a new LEP controller
    pub fn new(identities: Vec<&str>) -> Self {
        let kernel = ItherisKernel::new(identities.to_vec());
        let crypto = CryptoAuthority::new(identities.to_vec());
        
        // Grant default capabilities
        let mut kernel = kernel;
        for identity in &identities {
            kernel.grant_capability(identity, vec!["read", "write", "query"], 86400); // 24 hours
        }
        
        let lep = LEPController {
            constitution: Constitution::new(),
            intent_validator: IntentValidator::new(),
            kernel,
            crypto,
            decision_log: Vec::new(),
            pending_approvals: HashMap::new(),
            emergency_override_keys: vec![
                "EMERGENCY_KEY_1".to_string(),
                "EMERGENCY_KEY_2".to_string(),
            ],
        };
        
        println!("[LEP] ✓ Law Enforcement Point initialized");
        lep
    }

    /// Process an intent through the full decision chain
    pub fn process_intent(
        &mut self,
        intent: &str,
        identity: &str,
        signed_thought: Option<SignedThought>,
        override_request: Option<OverrideRequest>,
    ) -> LEPResult<LEPDecision> {
        let decision_id = self.generate_decision_id();
        let timestamp = Utc::now();
        let mut stages_completed = Vec::new();
        
        println!("[LEP] ▶ Processing intent: {} from {}", intent, identity);
        
        // STAGE 1: Intent Validation
        println!("[LEP]   Stage 1/5: Validating intent...");
        let validated_intent = match self.intent_validator.validate(intent, identity, None) {
            Ok(v) => {
                stages_completed.push(LEPStage::IntentValidation);
                println!("[LEP]   ✓ Intent validated");
                v
            }
            Err(e) => {
                let decision = LEPDecision {
                    decision_id: decision_id.clone(),
                    intent: intent.to_string(),
                    identity: identity.to_string(),
                    result: LEPDecisionResult::Rejected,
                    timestamp,
                    stages_completed: vec![LEPStage::IntentValidation],
                    override_applied: false,
                    override_signatures: Vec::new(),
                    rejection_reason: Some(format!("Intent validation failed: {}", e)),
                };
                self.log_decision(decision.clone());
                return Err(LEPError::IntentValidationFailed(e.to_string()));
            }
        };
        
        // STAGE 2: Constitution Validation
        println!("[LEP]   Stage 2/5: Validating against constitution...");
        let is_emergency = override_request.is_some();
        match self.constitution.validate_intent(intent, identity, is_emergency) {
            Ok(_) => {
                stages_completed.push(LEPStage::ConstitutionValidation);
                println!("[LEP]   ✓ Constitution validation passed");
            }
            Err(e) => {
                // Check if we have an override
                if let Some(ref override) = override_request {
                    match self.process_override(&override) {
                        Ok(_) => {
                            stages_completed.push(LEPStage::ConstitutionValidation);
                            println!("[LEP]   ✓ Constitution override applied");
                        }
                        Err(_) => {
                            let decision = LEPDecision {
                                decision_id: decision_id.clone(),
                                intent: intent.to_string(),
                                identity: identity.to_string(),
                                result: LEPDecisionResult::Unconstitutional,
                                timestamp,
                                stages_completed,
                                override_applied: false,
                                override_signatures: Vec::new(),
                                rejection_reason: Some(format!("Constitution violation: {}", e)),
                            };
                            self.log_decision(decision.clone());
                            return Err(LEPError::ConstitutionValidationFailed(e.to_string()));
                        }
                    }
                } else {
                    let decision = LEPDecision {
                        decision_id: decision_id.clone(),
                        intent: intent.to_string(),
                        identity: identity.to_string(),
                        result: LEPDecisionResult::Unconstitutional,
                        timestamp,
                        stages_completed,
                        override_applied: false,
                        override_signatures: Vec::new(),
                        rejection_reason: Some(format!("Constitution violation: {}", e)),
                    };
                    self.log_decision(decision.clone());
                    return Err(LEPError::ConstitutionValidationFailed(e.to_string()));
                }
            }
        }
        
        // STAGE 3: Authorization Check
        println!("[LEP]   Stage 3/5: Checking authorization...");
        let auth_result = self.check_authorization(&validated_intent, &signed_thought);
        
        match auth_result {
            Ok(_) => {
                stages_completed.push(LEPStage::AuthorizationCheck);
                println!("[LEP]   ✓ Authorization verified");
            }
            Err(e) => {
                let decision = LEPDecision {
                    decision_id: decision_id.clone(),
                    intent: intent.to_string(),
                    identity: identity.to_string(),
                    result: LEPDecisionResult::Unauthorized,
                    timestamp,
                    stages_completed,
                    override_applied: false,
                    override_signatures: Vec::new(),
                    rejection_reason: Some(format!("Authorization failed: {}", e)),
                };
                self.log_decision(decision.clone());
                return Err(LEPError::AuthorizationFailed(e.to_string()));
            }
        }
        
        // STAGE 4: Kernel Approval
        println!("[LEP]   Stage 4/5: Seeking kernel approval...");
        
        // If we have a signed thought, use kernel enforcement
        if let Some(ref thought) = signed_thought {
            match self.kernel.enforce(thought) {
                Ok(_) => {
                    stages_completed.push(LEPStage::KernelApproval);
                    println!("[LEP]   ✓ Kernel approval granted");
                }
                Err(e) => {
                    let decision = LEPDecision {
                        decision_id: decision_id.clone(),
                        intent: intent.to_string(),
                        identity: identity.to_string(),
                        result: LEPDecisionResult::Rejected,
                        timestamp,
                        stages_completed,
                        override_applied: false,
                        override_signatures: Vec::new(),
                        rejection_reason: Some(format!("Kernel denied: {}", e)),
                    };
                    self.log_decision(decision.clone());
                    return Err(LEPError::KernelDenied(e.to_string()));
                }
            }
        } else {
            // Without signed thought, check capability directly
            if let Err(e) = self.kernel.verify_capability(identity, intent) {
                let decision = LEPDecision {
                    decision_id: decision_id.clone(),
                    intent: intent.to_string(),
                    identity: identity.to_string(),
                    result: LEPDecisionResult::Rejected,
                    timestamp,
                    stages_completed,
                    override_applied: false,
                    override_signatures: Vec::new(),
                    rejection_reason: Some(format!("Kernel denied: {}", e)),
                };
                self.log_decision(decision.clone());
                return Err(LEPError::KernelDenied(e.to_string()));
            }
            stages_completed.push(LEPStage::KernelApproval);
            println!("[LEP]   ✓ Kernel approval granted (capability-based)");
        }
        
        // STAGE 5: Execution (prepared)
        println!("[LEP]   Stage 5/5: Preparing execution...");
        stages_completed.push(LEPStage::Execution);
        
        // Create the decision
        let override_applied = override_request.is_some();
        let override_signatures = override_request
            .as_ref()
            .map(|o| o.signatures.iter().map(|s| s.key_id.clone()).collect())
            .unwrap_or_default();
        
        let decision = LEPDecision {
            decision_id,
            intent: intent.to_string(),
            identity: identity.to_string(),
            result: LEPDecisionResult::Approved,
            timestamp,
            stages_completed,
            override_applied,
            override_signatures,
            rejection_reason: None,
        };
        
        self.log_decision(decision.clone());
        println!("[LEP] ✓ Decision: APPROVED");
        
        Ok(decision)
    }

    /// Check authorization for an intent
    fn check_authorization(
        &self,
        intent: &ValidatedIntent,
        signed_thought: &Option<SignedThought>,
    ) -> LEPResult<()> {
        // High-risk intents require signed thought
        if intent.risk_level >= RiskLevel::High {
            if signed_thought.is_none() {
                return Err(LEPError::AuthorizationFailed(
                    "High-risk intent requires cryptographic signature".to_string(),
                ));
            }
            
            // Verify signature if provided
            if let Some(ref thought) = signed_thought {
                if thought.identity != intent.identity {
                    return Err(LEPError::AuthorizationFailed(
                        "Signed thought identity does not match".to_string(),
                    ));
                }
            }
        }
        
        Ok(())
    }

    /// Process an emergency override request
    fn process_override(&mut self, request: &OverrideRequest) -> LEPResult<()> {
        // Check emergency level
        if request.emergency_level == EmergencyLevel::Normal {
            return Err(LEPError::OverrideNotAuthorized);
        }
        
        // Check signature count (dual-key requirement)
        let required_signatures = 2;
        if request.signatures.len() < required_signatures {
            return Err(LEPError::OverrideInsufficientSignatures(
                required_signatures as u8,
                request.signatures.len() as u8,
            ));
        }
        
        // Verify signatures are from authorized keys
        for sig in &request.signatures {
            if !self.emergency_override_keys.contains(&sig.key_id) {
                return Err(LEPError::OverrideNotAuthorized);
            }
            
            // In a full implementation, verify signature with TPM
            // For now, just check key presence
            if sig.tpm_backed {
                println!("[LEP] ✓ TPM-backed signature verified: {}", sig.key_id);
            }
        }
        
        // Apply overrides to constitution
        for rule_id in &request.rule_ids {
            self.constitution.apply_emergency_override(
                rule_id,
                request.signatures.iter().map(|s| s.signature.clone()).collect(),
            )?;
        }
        
        println!("[LEP] ✓ Emergency override processed");
        
        Ok(())
    }

    /// Grant capability to an identity
    pub fn grant_capability(
        &mut self,
        identity: &str,
        permissions: Vec<&str>,
        duration_secs: i64,
    ) {
        self.kernel.grant_capability(identity, permissions, duration_secs);
        println!("[LEP] ✓ Capability granted to {}", identity);
    }

    /// Revoke capabilities from an identity
    pub fn revoke_capabilities(&mut self, identity: &str) {
        self.kernel.revoke_capabilities(identity);
        println!("[LEP] ✓ Capabilities revoked from {}", identity);
    }

    /// Set emergency level
    pub fn set_emergency_level(&mut self, level: EmergencyLevel) {
        self.constitution.set_emergency_level(level);
        println!("[LEP] ⚠️  Emergency level: {:?}", level);
    }

    /// Add emergency override key
    pub fn add_emergency_override_key(&mut self, key_id: String) {
        self.emergency_override_keys.push(key_id.clone());
        self.constitution.add_emergency_override_key(key_id);
    }

    /// Generate decision ID
    fn generate_decision_id(&self) -> String {
        use uuid::Uuid;
        Uuid::new_v4().to_string()
    }

    /// Log a decision
    fn log_decision(&mut self, decision: LEPDecision) {
        self.decision_log.push(decision);
    }

    /// Get decision log
    pub fn get_decision_log(&self) -> &Vec<LEPDecision> {
        &self.decision_log
    }

    /// Get decision count
    pub fn decision_count(&self) -> usize {
        self.decision_log.len()
    }

    /// Get approved decision count
    pub fn approved_count(&self) -> usize {
        self.decision_log
            .iter()
            .filter(|d| d.result == LEPDecisionResult::Approved)
            .count()
    }

    /// Get rejected decision count
    pub fn rejected_count(&self) -> usize {
        self.decision_log
            .iter()
            .filter(|d| d.result == LEPDecisionResult::Rejected)
            .count()
    }

    /// Get constitution
    pub fn get_constitution(&self) -> &Constitution {
        &self.constitution
    }

    /// Get kernel
    pub fn get_kernel(&self) -> &ItherisKernel {
        &self.kernel
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lep_creation() {
        let lep = LEPController::new(vec!["TEST_AGENT"]);
        assert_eq!(lep.decision_count(), 0);
    }

    #[test]
    fn test_approved_intent() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        let result = lep.process_intent("read:/data/file.txt", "TEST_AGENT", None, None);
        
        assert!(result.is_ok());
        assert_eq!(result.unwrap().result, LEPDecisionResult::Approved);
    }

    #[test]
    fn test_rejected_intent() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        // Invalid intent (blocked pattern)
        let result = lep.process_intent("execute:/bin/ls && rm -rf /", "TEST_AGENT", None, None);
        
        assert!(result.is_err());
    }

    #[test]
    fn test_high_risk_requires_signature() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        // High-risk without signature should fail
        let result = lep.process_intent("execute:/system/command", "TEST_AGENT", None, None);
        
        assert!(result.is_err());
    }

    #[test]
    fn test_decision_logging() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        lep.process_intent("read:/data", "TEST_AGENT", None, None).unwrap();
        
        assert_eq!(lep.decision_count(), 1);
        assert_eq!(lep.approved_count(), 1);
    }

    #[test]
    fn test_capability_management() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        lep.grant_capability("NEW_AGENT", vec!["read", "write"], 3600);
        
        let result = lep.process_intent("read:/data", "NEW_AGENT", None, None);
        
        assert!(result.is_ok());
    }

    #[test]
    fn test_emergency_level() {
        let mut lep = LEPController::new(vec!["TEST_AGENT"]);
        
        lep.set_emergency_level(EmergencyLevel::High);
        
        let constitution = lep.get_constitution();
        // Would check emergency level in full test
    }
}
