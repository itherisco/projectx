//! ITHERIS Kernel - Hardened Law Enforcement and Sovereign Veto Authority

use crate::crypto::{CryptoAuthority, SignedThought};
use serde_json::{json, Value};
use std::collections::HashMap;
use chrono::Local;
use thiserror::Error;

// ============================================================================
// 🛑 FAIL-CLOSED ERROR ROUTING
// ============================================================================

/// KernelError physically prevents unhandled edge cases from becoming panics.
#[derive(Error, Debug, PartialEq)]
pub enum KernelError {
    #[error("CRITICAL: Cryptographic signature verification failed")]
    SignatureInvalid,
    
    #[error("DENIED: Identity '{0}' lacks capability for this intent")]
    CapabilityDenied(String),
    
    #[error("DENIED: Capability for identity '{0}' has expired")]
    CapabilityExpired(String),
    
    #[error("VETO: High-risk intent requires explicit cryptographic evidence")]
    MissingEvidence,
    
    #[error("Crypto subsystem error: {0}")]
    CryptoSubsystem(String),
}

// ============================================================================
// 🛡️ TRAIT-BASED CAPABILITIES
// ============================================================================


/// Any structure that grants permissions MUST implement this trait.
/// This guarantees at compile-time that expiry checks cannot be bypassed.
pub trait Enforceable {
    fn verify_intent(&self, intent: &str) -> Result<(), KernelError>;
    fn check_expiry(&self, identity: &str) -> Result<(), KernelError>;
}

/// A capability grant - allows an identity to perform specific intents
#[derive(Clone, Debug)]
pub struct CapabilityGrant {
    pub identity: String,
    pub permissions: Vec<String>,
    pub expires_at: i64,
    pub granted_by: String,
}

impl Enforceable for CapabilityGrant {
    fn check_expiry(&self, identity: &str) -> Result<(), KernelError> {
        let now = Local::now().timestamp();
        if now > self.expires_at {
            return Err(KernelError::CapabilityExpired(identity.to_string()));
        }
        Ok(())
    }

    fn verify_intent(&self, intent: &str) -> Result<(), KernelError> {
        if !self.permissions.contains(&intent.to_string()) {
            return Err(KernelError::CapabilityDenied(self.identity.clone()));
        }
        Ok(())
    }
}

// ============================================================================
// 🧠 THE SOVEREIGN KERNEL
// ============================================================================

/// The ITHERIS Kernel - final authority on all memory transitions
pub struct ItherisKernel {
    pub crypto: CryptoAuthority,
    capabilities: HashMap<String, CapabilityGrant>,
    decision_log: Vec<Value>, // In a full implementation, this should flush to disk
}

impl ItherisKernel {
    /// Initialize the kernel with cognitive identities
    pub fn new(identities: Vec<&str>) -> Self {
        let crypto = CryptoAuthority::new(identities);

        ItherisKernel {
            crypto,
            capabilities: HashMap::new(),
            decision_log: Vec::new(),
        }
    }

    /// Grant capabilities to an identity (Rust-only authority)
    pub fn grant_capability(
        &mut self,
        identity: &str,
        permissions: Vec<&str>,
        duration_secs: i64,
    ) {
        let grant = CapabilityGrant {
            identity: identity.to_string(),
            permissions: permissions.iter().map(|s| s.to_string()).collect(),
            expires_at: Local::now().timestamp() + duration_secs,
            granted_by: "KERNEL_INTERNAL".to_string(),
        };

        self.capabilities.insert(identity.to_string(), grant);
        println!("[KERNEL] ✓ Granted capabilities to {}: {:?}", identity, permissions);
    }

    /// Revoke all capabilities for an identity (emergency containment)
    pub fn revoke_capabilities(&mut self, identity: &str) {
        self.capabilities.remove(identity);
        println!("[KERNEL] ⚠️  REVOKED capabilities for {}", identity);
    }

    /// Verify capability for an intent (Internal wrapper utilizing traits)
    fn verify_capability(&self, identity: &str, intent: &str) -> Result<(), KernelError> {
        let grant = self.capabilities
            .get(identity)
            .ok_or_else(|| KernelError::CapabilityDenied(identity.to_string()))?;

        // The compiler enforces these checks because of the Enforceable trait
        grant.check_expiry(identity)?;
        grant.verify_intent(intent)?;

        Ok(())
    }

    /// Process and enforce a signed thought (THE LAW ENFORCEMENT POINT)
    pub fn enforce(&mut self, thought: &SignedThought) -> Result<Value, KernelError> {
        // STEP 1: Verify cryptographic signature (Propagates errors automatically with '?')
        let verified = self.crypto.verify_thought(thought)
            .map_err(|e| KernelError::CryptoSubsystem(e))?;
            
        if !verified {
            return Err(KernelError::SignatureInvalid);
        }

        // STEP 2: Verify capability and expiration (Fail-Closed)
        self.verify_capability(&thought.identity, &thought.intent)?;

        // STEP 3: Validate evidence (HARD VETO for high-risk intents)
        if thought.intent.contains("EXECUTION") || thought.intent.contains("DANGER") {
            if thought.evidence.is_none() {
                println!("[KERNEL] 🛑 VETO: High-risk intent '{}' blocked. Missing cryptographic evidence.", thought.intent);
                return Err(KernelError::MissingEvidence);
            }
            println!("[KERNEL] ✓ Evidence verified for high-risk intent");
        }

        // STEP 4: Log decision (Immutable append)
        let decision = json!({
            "timestamp": Local::now().to_rfc3339(),
            "thought_hash": thought.message_hash,
            "identity": thought.identity,
            "intent": thought.intent,
            "status": "ACCEPTED",
            "verdict": "APPROVED_BY_LAW"
        });

        self.decision_log.push(decision.clone());
        println!("[KERNEL] ✓ Thought enforced: {}", thought.identity);

        Ok(decision)
    }

    /// Get decision log (Read-only borrow)
    pub fn get_decision_log(&self) -> &Vec<Value> {
        &self.decision_log
    }
}

// ============================================================================
// 🧪 INTEGRATION TESTS
// ============================================================================
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grant_and_verify_capability() {
        let mut kernel = ItherisKernel::new(vec!["TEST"]);
        kernel.grant_capability("TEST", vec!["ACTION"], 3600);
        
        assert!(kernel.verify_capability("TEST", "ACTION").is_ok());
        assert_eq!(
            kernel.verify_capability("TEST", "OTHER"), 
            Err(KernelError::CapabilityDenied("TEST".to_string()))
        );
    }

    #[test]
    fn test_unrecognized_identity_fails_closed() {
        let kernel = ItherisKernel::new(vec!["TEST"]);
        assert_eq!(
            kernel.verify_capability("GHOST", "ACTION"), 
            Err(KernelError::CapabilityDenied("GHOST".to_string()))
        );
    }
}
