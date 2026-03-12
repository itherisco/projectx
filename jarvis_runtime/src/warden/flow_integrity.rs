//! # Flow Integrity Module
//!
//! Cryptographic flow integrity system that issues one-time HMAC tokens
//! for authorizing capability execution. This prevents a "hallucinating" brain
//! from spoofing its own approval.
//!
//! ## Security Properties
//!
//! - **Non-repudiation**: Tokens can't be forged without HMAC secret
//! - **Integrity**: Token is bound to specific capability + params
//! - **Freshness**: Tokens expire and can't be replayed
//! - **Single-use**: Used tokens are invalidated immediately
//!
//! ## Threat Model
//!
//! - Original vulnerability: Kernel.approve() is just a function call
//! - Attack: Prompt injection could redefine the function to always return true
//! - Impact: Unrestricted capability execution without kernel oversight
//!
//! ## Remediation
//!
//! - Kernel issues one-time cryptographic HMAC tokens on approval
//! - Each token encodes: capability_id, params_hash, cycle_number, expiration
//! - ExecutionEngine MUST verify token before running any capability

use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::Sha256;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// Maximum number of active tokens to prevent memory exhaustion
const MAX_ACTIVE_TOKENS: usize = 100;

/// Default token TTL in seconds (60 seconds)
const DEFAULT_TOKEN_TTL: u64 = 60;

/// Flow token - cryptographically sealed execution permit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowToken {
    pub token_id: String,
    pub capability_id: String,
    pub params_hash: String,
    pub cycle_number: u64,
    pub created_at: u64,
    pub expires_at: u64,
    pub hmac: String,
}

/// Request to issue a new flow token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IssueTokenRequest {
    pub capability_id: String,
    pub params: HashMap<String, String>,
    pub cycle_number: u64,
}

/// Request to verify a flow token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifyTokenRequest {
    pub token_id: String,
    pub capability_id: String,
    pub params: HashMap<String, String>,
}

/// Token verification result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifyTokenResult {
    pub valid: bool,
    pub reason: String,
}

/// Token store - manages active and used tokens
pub struct FlowTokenStore {
    active_tokens: HashMap<String, FlowToken>,
    used_tokens: HashSet<String>,
    secret_key: [u8; 32],
    max_tokens: usize,
    token_ttl: u64,
}

impl FlowTokenStore {
    pub fn new(secret_key: [u8; 32]) -> Self {
        Self {
            active_tokens: HashMap::new(),
            used_tokens: HashSet::new(),
            secret_key,
            max_tokens: MAX_ACTIVE_TOKENS,
            token_ttl: DEFAULT_TOKEN_TTL,
        }
    }

    pub fn with_config(secret_key: [u8; 32], max_tokens: usize, token_ttl: u64) -> Self {
        Self {
            active_tokens: HashMap::new(),
            used_tokens: HashSet::new(),
            secret_key,
            max_tokens,
            token_ttl,
        }
    }
}

/// Flow Integrity Gate - Kernel-side token issuer
pub struct FlowIntegrityGate {
    store: Arc<RwLock<FlowTokenStore>>,
}

impl FlowIntegrityGate {
    /// Create a new FlowIntegrityGate with a generated secret key
    pub fn new() -> Self {
        let mut secret_key = [0u8; 32];
        OsRng.fill_bytes(&mut secret_key);
        Self::with_key(secret_key)
    }

    /// Create a new FlowIntegrityGate with a provided secret key
    pub fn with_key(secret_key: [u8; 32]) -> Self {
        Self {
            store: Arc::new(RwLock::new(FlowTokenStore::new(secret_key))),
        }
    }

    /// Create a new FlowIntegrityGate with custom configuration
    pub fn with_config(secret_key: [u8; 32], max_tokens: usize, token_ttl: u64) -> Self {
        Self {
            store: Arc::new(RwLock::new(FlowTokenStore::with_config(
                secret_key,
                max_tokens,
                token_ttl,
            ))),
        }
    }

    /// Issue a new flow token for capability execution
    pub async fn issue_token(&self, request: IssueTokenRequest) -> Option<FlowToken> {
        let mut store = self.store.write().await;

        // Rate limiting: check token store capacity
        if store.active_tokens.len() >= store.max_tokens {
            tracing::warn!(
                "FlowIntegrity: Token store full, rejecting new token request"
            );
            return None;
        }

        // Generate unique token ID using CSPRNG
        let token_id_bytes = Uuid::new_v4().as_bytes();
        let token_id = hex::encode(token_id_bytes);

        // Compute params hash for integrity binding
        let params_json = serde_json::to_string(&request.params).unwrap_or_default();
        let params_hash = hex::encode(sha256(params_json.as_bytes()));

        // Timestamps
        let now_ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let expires_at = now_ts + store.token_ttl;

        // Build payload and compute HMAC
        let payload = build_token_payload(
            token_id_bytes,
            &request.capability_id,
            &params_hash,
            request.cycle_number,
            now_ts,
            expires_at,
        );
        let hmac = compute_hmac(&payload, &store.secret_key);

        // Create token
        let token = FlowToken {
            token_id: token_id.clone(),
            capability_id: request.capability_id.clone(),
            params_hash,
            cycle_number: request.cycle_number,
            created_at: now_ts,
            expires_at,
            hmac: hex::encode(hmac),
        };

        // Store token
        store.active_tokens.insert(token_id, token.clone());

        tracing::debug!(
            "FlowIntegrity: Issued token for capability: {}",
            request.capability_id
        );

        Some(token)
    }

    /// Verify and consume a flow token
    pub async fn verify_token(&self, request: VerifyTokenRequest) -> VerifyTokenResult {
        let mut store = self.store.write().await;

        // FAIL-CLOSED: if token is missing, deny execution
        let Some(token) = store.active_tokens.get(&request.token_id) else {
            // Check if it was already used
            if store.used_tokens.contains(&request.token_id) {
                return VerifyTokenResult {
                    valid: false,
                    reason: "TOKEN_ALREADY_USED".to_string(),
                };
            }
            return VerifyTokenResult {
                valid: false,
                reason: "TOKEN_NOT_FOUND".to_string(),
            };
        };

        // Check 1: Expiration
        let now_ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        if now_ts > token.expires_at {
            return VerifyTokenResult {
                valid: false,
                reason: "TOKEN_EXPIRED".to_string(),
            };
        }

        // Check 2: HMAC verification (re-compute and compare)
        let params_json = serde_json::to_string(&request.params).unwrap_or_default();
        let params_hash = hex::encode(sha256(params_json.as_bytes()));

        // Re-build original payload to verify HMAC
        let payload = build_token_payload(
            &hex::decode(&request.token_id).unwrap_or_default(),
            &token.capability_id,
            &token.params_hash,
            token.cycle_number,
            token.created_at,
            token.expires_at,
        );
        let expected_hmac = compute_hmac(&payload, &store.secret_key);

        if hex::encode(expected_hmac) != token.hmac {
            return VerifyTokenResult {
                valid: false,
                reason: "INVALID_HMAC".to_string(),
            };
        }

        // Check 3: Capability binding (anti-redirect)
        if token.capability_id != request.capability_id {
            return VerifyTokenResult {
                valid: false,
                reason: "CAPABILITY_MISMATCH".to_string(),
            };
        }

        // Check 4: Params hash (anti-tampering)
        if params_hash != token.params_hash {
            return VerifyTokenResult {
                valid: false,
                reason: "PARAMS_TAMPERED".to_string(),
            };
        }

        // Check 5: Single-use (mark as used)
        store.active_tokens.remove(&request.token_id);
        store.used_tokens.insert(request.token_id.clone());

        tracing::debug!(
            "FlowIntegrity: Token verified for capability: {}",
            request.capability_id
        );

        VerifyTokenResult {
            valid: true,
            reason: "TOKEN_VALID".to_string(),
        }
    }

    /// Get number of active tokens
    pub async fn active_token_count(&self) -> usize {
        let store = self.store.read().await;
        store.active_tokens.len()
    }

    /// Cleanup expired tokens
    pub async fn cleanup_expired_tokens(&self) -> usize {
        let mut store = self.store.write().await;
        let now_ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let expired_keys: Vec<String> = store
            .active_tokens
            .iter()
            .filter(|(_, token)| now_ts > token.expires_at)
            .map(|(id, _)| id.clone())
            .collect();

        for key in &expired_keys {
            store.active_tokens.remove(key);
        }

        expired_keys.len()
    }
}

/// Build token payload for HMAC computation
fn build_token_payload(
    token_id: &[u8],
    capability_id: &str,
    params_hash: &str,
    cycle_number: u64,
    created_at: u64,
    expires_at: u64,
) -> Vec<u8> {
    let mut payload = Vec::new();
    payload.extend_from_slice(token_id);
    payload.extend_from_slice(capability_id.as_bytes());
    payload.extend_from_slice(params_hash.as_bytes());
    payload.extend_from_slice(&cycle_number.to_le_bytes());
    payload.extend_from_slice(&created_at.to_le_bytes());
    payload.extend_from_slice(&expires_at.to_le_bytes());
    payload
}

/// Compute HMAC-SHA256 for a payload
fn compute_hmac(payload: &[u8], secret_key: &[u8; 32]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(secret_key).expect("HMAC can take key of any size");
    mac.update(payload);
    mac.finalize().into_bytes().to_vec()
}

/// Compute SHA256 hash
fn sha256(data: &[u8]) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_flow_token_issuance_and_verification() {
        let gate = FlowIntegrityGate::new();
        
        let request = IssueTokenRequest {
            capability_id: "safe_shell".to_string(),
            params: HashMap::from([("command".to_string(), "echo test".to_string())]),
            cycle_number: 1,
        };

        let token = gate.issue_token(request.clone()).await;
        assert!(token.is_some());

        let verify_request = VerifyTokenRequest {
            token_id: token.unwrap().token_id,
            capability_id: request.capability_id,
            params: request.params,
        };

        let result = gate.verify_token(verify_request).await;
        assert!(result.valid);
        assert_eq!(result.reason, "TOKEN_VALID");
    }

    #[tokio::test]
    async fn test_token_reuse_prevention() {
        let gate = FlowIntegrityGate::new();
        
        let request = IssueTokenRequest {
            capability_id: "safe_shell".to_string(),
            params: HashMap::new(),
            cycle_number: 1,
        };

        let token = gate.issue_token(request.clone()).await.unwrap();
        
        let verify_request = VerifyTokenRequest {
            token_id: token.token_id.clone(),
            capability_id: request.capability_id.clone(),
            params: request.params.clone(),
        };

        // First verification should succeed
        let result1 = gate.verify_token(verify_request.clone()).await;
        assert!(result1.valid);

        // Second verification should fail (token already used)
        let result2 = gate.verify_token(verify_request).await;
        assert!(!result2.valid);
        assert_eq!(result2.reason, "TOKEN_ALREADY_USED");
    }
}
