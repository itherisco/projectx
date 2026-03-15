//! Cryptographic Authority - Signs all thoughts and decisions
//! Ed25519 implementation with deterministic canonicalization

use ed25519_dalek::{Keypair, PublicKey, Signer, Verifier};
use rand::rngs::OsRng;
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use sha2::{Digest, Sha256};

/// A cryptographically-signed thought from a cognitive identity
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SignedThought {
    pub identity: String,
    pub intent: String,
    pub payload: Value,
    pub evidence: Option<Value>,
    pub timestamp: String,
    pub nonce: String,
    pub signature: String,
    pub message_hash: String,
}

/// The cryptographic authority - manages all signing keys and verification
#[derive(Clone, Debug)]
pub struct CryptoAuthority {
    signing_keys: HashMap<String, Vec<u8>>,
    pub_keys: HashMap<String, PublicKey>,
    thought_log: Vec<SignedThought>,
}

impl CryptoAuthority {
    /// Initialize crypto authority with cognitive identities
    pub fn new(identities: Vec<&str>) -> Self {
        let mut signing_keys = HashMap::new();
        let mut pub_keys = HashMap::new();

        for id in identities {
            let keypair = Keypair::generate(&mut OsRng);
            signing_keys.insert(id.to_string(), keypair.to_bytes().to_vec());
            pub_keys.insert(id.to_string(), keypair.public);

            println!("[CRYPTO] ✓ Key generated for identity: {}", id);
        }

        Self {
            signing_keys,
            pub_keys,
            thought_log: Vec::new(),
        }
    }

    /// Canonicalize message for deterministic signing (prevents signature malleability)
    fn canonicalize(thought: &Value) -> Vec<u8> {
        let canonical = serde_json::to_string(&thought)
            .expect("Failed to serialize thought");
        canonical.into_bytes()
    }

    /// Sign a thought from a cognitive identity
    pub fn sign_thought(
        &mut self,
        identity: &str,
        intent: &str,
        payload: Value,
        evidence: Option<Value>,
        timestamp: String,
        nonce: String,
    ) -> Result<SignedThought, String> {
        // Verify identity exists
        if !self.signing_keys.contains_key(identity) {
            return Err(format!("Unknown identity: {}", identity));
        }

        // Construct canonical message (deterministic order)
        let message = serde_json::json!({
            "identity": identity,
            "intent": intent,
            "payload": payload,
            "evidence": evidence,
            "timestamp": timestamp,
            "nonce": nonce
        });

        // Sign the canonical bytes
        let canonical = Self::canonicalize(&message);
        let signing_key_bytes = &self.signing_keys[identity];
        
        // First convert the bytes array to the right type
        let key_bytes: [u8; 32] = signing_key_bytes.as_slice().try_into()
            .map_err(|_| "Invalid signing key length".to_string())?;
        
        // Then create the keypair from the bytes
        let keypair = Keypair::from_bytes(&key_bytes)
            .map_err(|e| format!("Invalid signing key: {:?}", e))?;
        
        let signature = keypair.sign(&canonical);

        // Compute message hash for audit trail
        let mut hasher = Sha256::new();
        hasher.update(&canonical);
        let message_hash = hex::encode(hasher.finalize());
        let message_hash_for_log = message_hash.clone();

        let signed_thought = SignedThought {
            identity: identity.to_string(),
            intent: intent.to_string(),
            payload,
            evidence,
            timestamp,
            nonce,
            signature: hex::encode(signature.to_bytes()),
            message_hash,
        };

        // Log signed thought to immutable thought log
        self.thought_log.push(signed_thought.clone());

        println!(
            "[CRYPTO] ✓ Signed thought from {}: {} (hash: {}...)",
            identity, intent, &message_hash_for_log[0..16]
        );

        Ok(signed_thought)
    }

    /// Verify a signed thought (recomputes hash and signature)
    pub fn verify_thought(&self, thought: &SignedThought) -> Result<bool, String> {
        // Verify identity is known
        if !self.pub_keys.contains_key(&thought.identity) {
            return Err(format!("Unknown identity: {}", thought.identity));
        }

        // Reconstruct canonical message
        let message = serde_json::json!({
            "identity": thought.identity,
            "intent": thought.intent,
            "payload": thought.payload,
            "evidence": thought.evidence,
            "timestamp": thought.timestamp,
            "nonce": thought.nonce
        });

        let canonical = Self::canonicalize(&message);

        // Decode and verify signature
        let sig_bytes = hex::decode(&thought.signature)
            .map_err(|e| format!("Invalid signature hex: {}", e))?;
        let signature = ed25519_dalek::Signature::from_bytes(&sig_bytes)
            .map_err(|e| format!("Invalid signature format: {}", e))?;

        let pubkey = &self.pub_keys[&thought.identity];
        let verified = pubkey.verify(&canonical, &signature).is_ok();

        // Verify message hash matches
        let mut hasher = Sha256::new();
        hasher.update(&canonical);
        let computed_hash = hex::encode(hasher.finalize());

        if computed_hash != thought.message_hash {
            return Err("Message hash mismatch - data tampered".to_string());
        }

        if verified {
            println!(
                "[CRYPTO] ✓ Verified thought from {}: {}",
                thought.identity, thought.intent
            );
        } else {
            println!(
                "[CRYPTO] ✗ VERIFICATION FAILED: {} → {}",
                thought.identity, thought.intent
            );
        }

        Ok(verified)
    }

    /// Get the thought log (immutable audit trail)
    pub fn get_thought_log(&self) -> &Vec<SignedThought> {
        &self.thought_log
    }

    /// Export public keys for external verification
    pub fn export_public_keys(&self) -> HashMap<String, String> {
        self.pub_keys
            .iter()
            .map(|(id, key)| (id.clone(), hex::encode(key.as_bytes())))
            .collect()
    }

    /// Get thought count
    pub fn thought_count(&self) -> usize {
        self.thought_log.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sign_and_verify() {
        let mut crypto = CryptoAuthority::new(vec!["TEST_IDENTITY"]);
        
        let signed = crypto.sign_thought(
            "TEST_IDENTITY",
            "TEST_INTENT",
            serde_json::json!({"test": "data"}),
            None,
            chrono::Local::now().to_rfc3339(),
            uuid::Uuid::new_v4().to_string(),
        ).unwrap();

        let verified = crypto.verify_thought(&signed).unwrap();
        assert!(verified);
    }

    #[test]
    fn test_unknown_identity() {
        let mut crypto = CryptoAuthority::new(vec!["KNOWN"]);
        
        let result = crypto.sign_thought(
            "UNKNOWN",
            "TEST",
            serde_json::json!({}),
            None,
            chrono::Local::now().to_rfc3339(),
            uuid::Uuid::new_v4().to_string(),
        );

        assert!(result.is_err());
    }
}