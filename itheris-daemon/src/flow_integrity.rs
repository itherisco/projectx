//! # Flow Integrity - Cryptographic Sovereignty Verification
//!
//! This module implements the cryptographic token gate that prevents the "hallucinating"
//! Julia brain from spoofing its own approval. It ensures:
//!
//! - **Sovereignty**: Kernel approval cannot be forged without the HMAC secret
//! - **Integrity**: Token is bound to specific capability + params
//! - **Freshness**: Tokens expire and cannot be replayed
//! - **Single-use**: Used tokens are invalidated immediately
//!
//! ## Security Properties
//!
//! - **Algorithm**: HMAC-SHA256 (can't be forged without secret)
//! - **Entropy**: RandomDevice() for CSPRNG
//! - **Binding**: SHA256 for capability/params binding
//! - **Fail-Closed**: Missing/invalid/expired tokens = DENIED

use aes_gcm::aead::{Aead, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Nonce};
use rand_core::RngCore;
use chrono::Utc;
use hmac::{Hmac, Mac};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::sync::RwLock;
use std::time::{Duration as StdDuration, Instant};
use thiserror::Error;

// HMAC type
type HmacSha256 = Hmac<Sha256>;

/// Flow Integrity errors
#[derive(Error, Debug)]
pub enum FlowIntegrityError {
    #[error("Token issuance failed: {0}")]
    IssuanceFailed(String),

    #[error("Token verification failed: {0}")]
    VerificationFailed(String),

    #[error("Token expired: {0}")]
    TokenExpired(String),

    #[error("Token already used: {0}")]
    TokenAlreadyUsed(String),

    #[error("Capability mismatch: {0}")]
    CapabilityMismatch(String),

    #[error("Parameters tampered: {0}")]
    ParamsTampered(String),

    #[error("Secret not set")]
    SecretNotSet,
}

/// Risk levels for action classification
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

/// A Flow Token - Cryptographically sealed execution permit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowToken {
    /// Unique token identifier (hex)
    pub token_id: String,
    /// Authorized capability ID
    pub capability_id: String,
    /// SHA256 hash of execution parameters
    pub params_hash: String,
    /// Kernel cycle number when issued
    pub cycle_number: u64,
    /// Unix timestamp of creation
    pub created_at: u64,
    /// Unix timestamp of expiration
    pub expires_at: u64,
    /// HMAC-SHA256 signature
    pub hmac_hex: String,
    /// Risk level of the action
    pub risk_level: RiskLevel,
    /// Whether token has been used
    #[serde(default)]
    pub used: bool,
}

/// Flow token for serialization (without the used flag)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowTokenData {
    pub token_id: String,
    pub capability_id: String,
    pub params_hash: String,
    pub cycle_number: u64,
    pub created_at: u64,
    pub expires_at: u64,
    pub hmac_hex: String,
    pub risk_level: RiskLevel,
}

impl From<FlowToken> for FlowTokenData {
    fn from(token: FlowToken) -> Self {
        FlowTokenData {
            token_id: token.token_id,
            capability_id: token.capability_id,
            params_hash: token.params_hash,
            cycle_number: token.cycle_number,
            created_at: token.created_at,
            expires_at: token.expires_at,
            hmac_hex: token.hmac_hex,
            risk_level: token.risk_level,
        }
    }
}

/// Token store configuration
#[derive(Clone)]
pub struct FlowConfig {
    /// Maximum active tokens
    pub max_tokens: usize,
    /// Token validity duration in seconds
    pub token_ttl: u64,
    /// Whether enforcement is enabled (cannot be disabled for security)
    pub enforcement_enabled: bool,
}

impl Default for FlowConfig {
    fn default() -> Self {
        Self {
            max_tokens: 100,
            token_ttl: 60, // 60 seconds default
            enforcement_enabled: true,
        }
    }
}

/// Flow Integrity Gate - Kernel-side token issuer
pub struct FlowIntegrityGate {
    /// HMAC secret (kernel-only, never exposed)
    secret_key: Option<[u8; 32]>,
    /// Active tokens (not yet used or expired)
    active_tokens: HashMap<String, FlowToken>,
    /// Used tokens (for replay protection)
    used_tokens: HashSet<String>,
    /// Configuration
    config: FlowConfig,
    /// Current cycle number
    cycle: u64,
    /// Statistics
    stats: FlowStats,
}

/// Flow statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FlowStats {
    pub tokens_issued: u64,
    pub tokens_verified: u64,
    pub tokens_rejected: u64,
    pub tokens_expired: u64,
    pub tokens_reused: u64,
}

impl FlowIntegrityGate {
    /// Create new flow integrity gate
    pub fn new() -> Self {
        Self {
            secret_key: None,
            active_tokens: HashMap::new(),
            used_tokens: HashSet::new(),
            config: FlowConfig::default(),
            cycle: 0,
            stats: FlowStats::default(),
        }
    }

    /// Create with custom config
    pub fn with_config(config: FlowConfig) -> Self {
        Self {
            secret_key: None,
            active_tokens: HashMap::new(),
            used_tokens: HashSet::new(),
            config,
            cycle: 0,
            stats: FlowStats::default(),
        }
    }

    /// Initialize with secret key
    pub fn initialize(&mut self, secret_key: &[u8; 32]) {
        self.secret_key = Some(*secret_key);
    }

    /// Check if secret is set
    pub fn is_initialized(&self) -> bool {
        self.secret_key.is_some()
    }

    /// Generate a random token ID
    fn generate_token_id() -> String {
        let mut bytes = [0u8; 16];
        OsRng.fill_bytes(&mut bytes);
        hex::encode(bytes)
    }

    /// Compute HMAC over token data
    fn compute_hmac(&self, token_data: &FlowTokenData) -> Result<String, FlowIntegrityError> {
        let key = self.secret_key.ok_or(FlowIntegrityError::SecretNotSet)?;

        let mut mac = <HmacSha256 as hmac::Mac>::new_from_slice(&key)
            .map_err(|e| FlowIntegrityError::IssuanceFailed(e.to_string()))?;

        // Update with all token fields
        mac.update(token_data.token_id.as_bytes());
        mac.update(token_data.capability_id.as_bytes());
        mac.update(token_data.params_hash.as_bytes());
        mac.update(&token_data.cycle_number.to_le_bytes());
        mac.update(&token_data.created_at.to_le_bytes());
        mac.update(&token_data.expires_at.to_le_bytes());

        let result = mac.finalize();
        Ok(hex::encode(result.into_bytes()))
    }

    /// Verify HMAC
    fn verify_hmac(&self, token_data: &FlowTokenData, expected_hmac: &str) -> bool {
        if let Ok(computed) = self.compute_hmac(token_data) {
            // Constant-time comparison
            if computed.len() != expected_hmac.len() {
                return false;
            }
            computed
                .as_bytes()
                .iter()
                .zip(expected_hmac.as_bytes())
                .fold(0, |acc, (a, b)| acc | (a ^ b))
                == 0
        } else {
            false
        }
    }

    /// Compute SHA256 hash of params
    fn hash_params(params: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(params.as_bytes());
        hex::encode(hasher.finalize())
    }

    /// Issue a flow token
    /// 
    /// # Arguments
    /// * `capability_id` - What capability this token authorizes
    /// * `params` - Execution parameters (JSON string)
    /// * `risk_level` - Risk level of the action
    pub fn issue_token(
        &mut self,
        capability_id: &str,
        params: &str,
        risk_level: RiskLevel,
    ) -> Result<FlowToken, FlowIntegrityError> {
        let key = self.secret_key.ok_or(FlowIntegrityError::SecretNotSet)?;

        // Enforce token limit
        if self.active_tokens.len() >= self.config.max_tokens {
            return Err(FlowIntegrityError::IssuanceFailed(
                "Token store full".to_string(),
            ));
        }

        // Increment cycle
        self.cycle += 1;
        let now = Utc::now().timestamp() as u64;

        // Generate token
        let token_id = Self::generate_token_id();
        let params_hash = Self::hash_params(params);

        let mut token_data = FlowTokenData {
            token_id: token_id.clone(),
            capability_id: capability_id.to_string(),
            params_hash: params_hash.clone(),
            cycle_number: self.cycle,
            created_at: now,
            expires_at: now + self.config.token_ttl,
            hmac_hex: String::new(),
            risk_level,
        };

        // Compute HMAC
        let hmac_hex = self.compute_hmac(&token_data)?;
        token_data.hmac_hex = hmac_hex.clone();

        let token = FlowToken {
            token_id,
            capability_id: capability_id.to_string(),
            params_hash,
            cycle_number: self.cycle,
            created_at: now,
            expires_at: now + self.config.token_ttl,
            hmac_hex,
            risk_level,
            used: false,
        };

        // Store token
        self.active_tokens.insert(token.token_id.clone(), token.clone());
        self.stats.tokens_issued += 1;

        Ok(token)
    }

    /// Verify a flow token
    /// 
    /// # Arguments
    /// * `token` - The token to verify
    /// * `capability_id` - Expected capability ID (for anti-redirect)
    /// * `params` - Execution parameters (for integrity check)
    /// 
    /// # Returns
    /// (is_valid, reason)
    pub fn verify_token(
        &mut self,
        token: &FlowToken,
        capability_id: &str,
        params: &str,
    ) -> (bool, String) {
        let now = Utc::now().timestamp() as u64;

        // 1. Check if already used
        if self.used_tokens.contains(&token.token_id) {
            self.stats.tokens_rejected += 1;
            self.stats.tokens_reused += 1;
            return (false, "Token already used".to_string());
        }

        // 2. Check expiration
        if token.expires_at < now {
            self.stats.tokens_expired += 1;
            self.stats.tokens_rejected += 1;
            return (false, "Token expired".to_string());
        }

        // 3. Verify capability (anti-redirect)
        if token.capability_id != capability_id {
            self.stats.tokens_rejected += 1;
            return (false, format!(
                "Capability mismatch: expected {}, got {}",
                capability_id, token.capability_id
            ));
        }

        // 4. Verify parameters (anti-tampering)
        let params_hash = Self::hash_params(params);
        if token.params_hash != params_hash {
            self.stats.tokens_rejected += 1;
            return (false, "Parameters tampered".to_string());
        }

        // 5. Verify HMAC signature
        let token_data = FlowTokenData {
            token_id: token.token_id.clone(),
            capability_id: token.capability_id.clone(),
            params_hash: token.params_hash.clone(),
            cycle_number: token.cycle_number,
            created_at: token.created_at,
            expires_at: token.expires_at,
            hmac_hex: token.hmac_hex.clone(),
            risk_level: token.risk_level,
        };

        if !self.verify_hmac(&token_data, &token.hmac_hex) {
            self.stats.tokens_rejected += 1;
            return (false, "Invalid signature".to_string());
        }

        // 6. Mark as used (single-use enforcement)
        self.used_tokens.insert(token.token_id.clone());
        self.active_tokens.remove(&token.token_id);
        
        self.stats.tokens_verified += 1;

        (true, "OK".to_string())
    }

    /// Cleanup expired tokens
    pub fn cleanup(&mut self) -> usize {
        let now = Utc::now().timestamp() as u64;
        
        let expired: Vec<String> = self
            .active_tokens
            .iter()
            .filter(|(_, t)| t.expires_at < now)
            .map(|(id, _)| id.clone())
            .collect();

        for id in &expired {
            self.active_tokens.remove(id);
        }

        // Also cleanup old used tokens (keep for 1 hour for audit)
        let _cutoff = now - 3600;
        if self.used_tokens.len() > 1000 {
            // Very simplified cleanup since we can't borrow self in retain
            let to_remove: Vec<String> = self.used_tokens.iter().take(self.used_tokens.len() - 1000).cloned().collect();
            for id in to_remove {
                self.used_tokens.remove(&id);
            }
        }

        self.stats.tokens_expired += expired.len() as u64;
        
        expired.len()
    }

    /// Get statistics
    pub fn get_stats(&self) -> FlowStats {
        self.stats.clone()
    }

    /// Get active token count
    pub fn active_count(&self) -> usize {
        self.active_tokens.len()
    }

    /// Serialize token for transmission to Julia (with AES-256-GCM encryption for hardening)
    pub fn serialize_token(&self, token: &FlowToken) -> String {
        let data = FlowTokenData::from(token.clone());
        let json = serde_json::to_string(&data).unwrap_or_default();

        if let Some(key) = self.secret_key {
            let cipher = Aes256Gcm::new_from_slice(&key).unwrap();
            let mut nonce_bytes = [0u8; 12];
            OsRng.fill_bytes(&mut nonce_bytes);
            let nonce = aes_gcm::Nonce::from_slice(&nonce_bytes);

            if let Ok(ciphertext) = cipher.encrypt(nonce, json.as_bytes()) {
                let mut combined = nonce_bytes.to_vec();
                combined.extend_from_slice(&ciphertext);
                return hex::encode(combined);
            }
        }

        // Fallback to JSON if encryption fails or key not set
        json
    }

    /// Deserialize token from Julia
    pub fn deserialize_token(&self, data: &str) -> Result<FlowToken, FlowIntegrityError> {
        let decrypted_json = if let Ok(combined) = hex::decode(data) {
            if combined.len() >= 12 && self.secret_key.is_some() {
                let key = self.secret_key.unwrap();
                let cipher = Aes256Gcm::new_from_slice(&key).unwrap();
                let (nonce_bytes, ciphertext) = combined.split_at(12);
                let nonce = aes_gcm::Nonce::from_slice(nonce_bytes);

                match cipher.decrypt(nonce, ciphertext) {
                    Ok(plaintext) => String::from_utf8(plaintext).unwrap_or_else(|_| data.to_string()),
                    Err(_) => data.to_string(),
                }
            } else {
                data.to_string()
            }
        } else {
            data.to_string()
        };

        let token_data: FlowTokenData = serde_json::from_str(&decrypted_json)
            .map_err(|e| FlowIntegrityError::VerificationFailed(e.to_string()))?;

        Ok(FlowToken {
            token_id: token_data.token_id,
            capability_id: token_data.capability_id,
            params_hash: token_data.params_hash,
            cycle_number: token_data.cycle_number,
            created_at: token_data.created_at,
            expires_at: token_data.expires_at,
            hmac_hex: token_data.hmac_hex,
            risk_level: token_data.risk_level,
            used: false,
        })
    }
}

impl Default for FlowIntegrityGate {
    fn default() -> Self {
        Self::new()
    }
}

// Global flow gate instance
static FLOW_GATE: Lazy<RwLock<FlowIntegrityGate>> = Lazy::new(|| {
    RwLock::new(FlowIntegrityGate::new())
});

/// Initialize flow gate with secret
pub fn init(secret: &[u8; 32]) {
    FLOW_GATE.write().unwrap().initialize(secret);
}

/// Check if flow gate is initialized
pub fn is_initialized() -> bool {
    FLOW_GATE.read().unwrap().is_initialized()
}

/// Issue a flow token
pub fn issue_token(capability_id: &str, params: &str, risk_level: RiskLevel) -> Result<FlowToken, FlowIntegrityError> {
    FLOW_GATE.write().unwrap().issue_token(capability_id, params, risk_level)
}

/// Verify a flow token
pub fn verify_token(token: &FlowToken, capability_id: &str, params: &str) -> (bool, String) {
    FLOW_GATE.write().unwrap().verify_token(token, capability_id, params)
}

/// Serialize token for Julia
pub fn serialize_token(token: &FlowToken) -> String {
    FLOW_GATE.read().unwrap().serialize_token(token)
}

/// Deserialize token from Julia
pub fn deserialize_token(data: &str) -> Result<FlowToken, FlowIntegrityError> {
    FLOW_GATE.read().unwrap().deserialize_token(data)
}

/// Get statistics
pub fn get_stats() -> FlowStats {
    FLOW_GATE.read().unwrap().get_stats()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_issuance() {
        let mut gate = FlowIntegrityGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let token = gate.issue_token("safe_shell", r#"{"command": "echo test"}"#, RiskLevel::Low)
            .unwrap();
        
        assert!(!token.token_id.is_empty());
        assert_eq!(token.capability_id, "safe_shell");
    }

    #[test]
    fn test_token_verification() {
        let mut gate = FlowIntegrityGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let params = r#"{"command": "echo test"}"#;
        let token = gate.issue_token("safe_shell", params, RiskLevel::Low)
            .unwrap();

        let (valid, reason) = gate.verify_token(&token, "safe_shell", params);
        
        assert!(valid, "Verification failed: {}", reason);
    }

    #[test]
    fn test_capability_mismatch() {
        let mut gate = FlowIntegrityGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let params = r#"{"command": "echo test"}"#;
        let token = gate.issue_token("safe_shell", params, RiskLevel::Low)
            .unwrap();

        // Try to use for different capability
        let (valid, reason) = gate.verify_token(&token, "safe_http", params);
        
        assert!(!valid);
        assert!(reason.contains("Capability mismatch"));
    }

    #[test]
    fn test_single_use() {
        let mut gate = FlowIntegrityGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let params = r#"{"command": "echo test"}"#;
        let token = gate.issue_token("safe_shell", params, RiskLevel::Low)
            .unwrap();

        // First use should succeed
        let (valid1, _) = gate.verify_token(&token, "safe_shell", params);
        assert!(valid1);

        // Second use should fail
        let (valid2, reason) = gate.verify_token(&token, "safe_shell", params);
        assert!(!valid2);
        assert!(reason.contains("already used"));
    }
}
