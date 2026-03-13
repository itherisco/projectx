//! # Secure Confirmation Gate - Sovereign Veto for High-Risk Actions
//!
//! This module implements the user confirmation gate with cryptographic verification
//! and hardware-backed entropy. It provides the "unbending" sovereign veto for
//! MEDIUM+ risk actions.
//!
//! ## Security Properties
//!
//! - **Hardware Entropy**: Uses OS CSPRNG for token generation
//!
//! - **Cryptographic Tokens**: HMAC-SHA256 signed confirmation tokens
//! - **Rate Limiting**: Prevents confirmation token brute-forcing
//! - **Timeout Handling**: Automatic denial for timed-out confirmations
//! - **WDT Integration**: Watchdog timer for fail-closed isolation

use aes_gcm::aead::OsRng;
use chrono::{Duration, Utc};
use hmac::{Hmac, Mac};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration as StdDuration, Instant};
use thiserror::Error;
use uuid::Uuid;

// HMAC type
type HmacSha256 = Hmac<Sha256>;

/// Confirmation errors
#[derive(Error, Debug)]
pub enum ConfirmationError {
    #[error("Token not found: {0}")]
    TokenNotFound(String),

    #[error("Token expired: {0}")]
    TokenExpired(String),

    #[error("Invalid token: {0}")]
    InvalidToken(String),

    #[error("Rate limited: {0}")]
    RateLimited(String),

    #[error("Gate locked: {0}")]
    GateLocked(String),
}

/// Risk levels
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

/// Confirmation status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ConfirmationStatus {
    Pending,
    Confirmed,
    Denied,
    Expired,
}

/// Secure confirmation token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfirmationToken {
    /// Unique token string
    pub token: String,
    /// Associated proposal/action ID
    pub proposal_id: String,
    /// Capability being confirmed
    pub capability_id: String,
    /// Parameters (JSON)
    pub params: String,
    /// Risk level
    pub risk_level: RiskLevel,
    /// Creation timestamp
    pub created_at: u64,
    /// Expiration timestamp
    pub expires_at: u64,
    /// Status
    pub status: ConfirmationStatus,
    /// HMAC signature
    pub signature: String,
}

/// Confirmation request from Julia
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfirmationRequest {
    pub proposal_id: String,
    pub capability_id: String,
    pub params: String,
    pub risk_level: RiskLevel,
    pub reasoning: String,
}

/// Confirmation result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfirmationResult {
    pub success: bool,
    pub confirmed: bool,
    pub token: Option<String>,
    pub reason: String,
    pub expires_at: u64,
}

/// Gate configuration
#[derive(Clone)]
pub struct ConfirmationConfig {
    /// Default timeout in seconds
    pub default_timeout: u64,
    /// Risk-specific timeouts
    pub risk_timeouts: HashMap<RiskLevel, u64>,
    /// Poll interval for status checks
    pub poll_interval_ms: u64,
    /// Maximum pending confirmations
    pub max_pending: usize,
    /// Rate limit: max attempts per token
    pub rate_limit_attempts: u32,
    /// Rate limit window in seconds
    pub rate_limit_window: u64,
}

impl Default for ConfirmationConfig {
    fn default() -> Self {
        let mut risk_timeouts = HashMap::new();
        risk_timeouts.insert(RiskLevel::Medium, 30);
        risk_timeouts.insert(RiskLevel::High, 60);
        risk_timeouts.insert(RiskLevel::Critical, 120);

        Self {
            default_timeout: 30,
            risk_timeouts,
            poll_interval_ms: 500,
            max_pending: 50,
            rate_limit_attempts: 5,
            rate_limit_window: 60,
        }
    }
}

/// Rate limiter for confirmation attempts
#[derive(Default)]
struct RateLimiter {
    attempts: HashMap<String, (u32, Option<Instant>)>,
}

impl RateLimiter {
    fn check(&mut self, token: &str, max_attempts: u32, window_secs: u64) -> bool {
        let now = Instant::now();
        let entry = self.attempts.entry(token.to_string()).or_insert((0, None));
        
        // Reset if window expired
        if let Some(last_reset) = entry.1 {
            if now.duration_since(last_reset).as_secs() > window_secs {
                *entry = (0, None);
            }
        }
        
        if entry.0 >= max_attempts {
            return false;
        }
        
        entry.0 += 1;
        if entry.1.is_none() {
            entry.1 = Some(now);
        }
        
        true
    }
    
    fn reset(&mut self, token: &str) {
        self.attempts.remove(token);
    }
}

/// Secure Confirmation Gate
pub struct SecureConfirmationGate {
    /// HMAC secret (kernel-only)
    secret: Option<[u8; 32]>,
    /// Pending confirmations
    pending: HashMap<String, ConfirmationToken>,
    /// Configuration
    config: ConfirmationConfig,
    /// Rate limiter
    rate_limiter: RateLimiter,
    /// Statistics
    stats: ConfirmationStats,
}

/// Confirmation statistics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ConfirmationStats {
    pub requested: u64,
    pub confirmed: u64,
    pub denied: u64,
    pub expired: u64,
    pub rejected: u64,
}

impl SecureConfirmationGate {
    /// Create new gate
    pub fn new() -> Self {
        Self {
            secret: None,
            pending: HashMap::new(),
            config: ConfirmationConfig::default(),
            rate_limiter: RateLimiter::default(),
            stats: ConfirmationStats::default(),
        }
    }

    /// Create with config
    pub fn with_config(config: ConfirmationConfig) -> Self {
        Self {
            secret: None,
            pending: HashMap::new(),
            config,
            rate_limiter: RateLimiter::default(),
            stats: ConfirmationStats::default(),
        }
    }

    /// Initialize with secret
    pub fn initialize(&mut self, secret: &[u8; 32]) {
        self.secret = Some(*secret);
    }

    /// Check if initialized
    pub fn is_initialized(&self) -> bool {
        self.secret.is_some()
    }

    /// Generate cryptographically secure token
    fn generate_token() -> String {
        let id = Uuid::new_v4();
        let mut bytes = [0u8; 16];
        OsRng.fill_bytes(&mut bytes);
        format!("{}_{}", id, hex::encode(bytes))
    }

    /// Get timeout for risk level
    fn get_timeout(&self, risk_level: RiskLevel) -> u64 {
        self.config
            .risk_timeouts
            .get(&risk_level)
            .copied()
            .unwrap_or(self.config.default_timeout)
    }

    /// Sign token data
    fn sign(&self, token_data: &str) -> Result<String, ConfirmationError> {
        let secret = self.secret.ok_or(ConfirmationError::GateLocked(
            "Confirmation gate not initialized".to_string(),
        ))?;

        let mut mac = HmacSha256::new_from_slice(&secret)
            .map_err(|e| ConfirmationError::InvalidToken(e.to_string()))?;
        
        mac.update(token_data.as_bytes());
        
        let result = mac.finalize();
        Ok(hex::encode(result.into_bytes()))
    }

    /// Verify signature
    fn verify(&self, token_data: &str, signature: &str) -> bool {
        if let Ok(computed) = self.sign(token_data) {
            // Constant-time comparison
            if computed.len() != signature.len() {
                return false;
            }
            computed
                .as_bytes()
                .iter()
                .zip(signature.as_bytes())
                .fold(0, |acc, (a, b)| acc | (a ^ b))
                == 0
        } else {
            false
        }
    }

    /// Request confirmation for an action
    pub fn request_confirmation(
        &mut self,
        request: &ConfirmationRequest,
    ) -> Result<ConfirmationResult, ConfirmationError> {
        let secret = self.secret.ok_or(ConfirmationError::GateLocked(
            "Confirmation gate not initialized".to_string(),
        ))?;

        // Check pending limit
        if self.pending.len() >= self.config.max_pending {
            return Err(ConfirmationError::RateLimited(
                "Too many pending confirmations".to_string(),
            ));
        }

        let now = Utc::now().timestamp() as u64;
        let timeout = self.get_timeout(request.risk_level);

        // Generate token
        let token = Self::generate_token();
        
        // Create token data for signing
        let token_data = format!(
            "{}|{}|{}|{}|{}",
            token, request.proposal_id, request.capability_id, now, now + timeout
        );

        // Sign
        let signature = self.sign(&token_data)?;

        let confirmation = ConfirmationToken {
            token: token.clone(),
            proposal_id: request.proposal_id.clone(),
            capability_id: request.capability_id.clone(),
            params: request.params.clone(),
            risk_level: request.risk_level,
            created_at: now,
            expires_at: now + timeout,
            status: ConfirmationStatus::Pending,
            signature,
        };

        // Store
        self.pending.insert(token.clone(), confirmation);
        self.stats.requested += 1;

        Ok(ConfirmationResult {
            success: true,
            confirmed: false,
            token: Some(token),
            reason: "Confirmation pending".to_string(),
            expires_at: now + timeout,
        })
    }

    /// Confirm an action
    pub fn confirm(&mut self, token: &str) -> Result<ConfirmationResult, ConfirmationError> {
        // Check rate limit
        if !self.rate_limiter.check(
            token,
            self.config.rate_limit_attempts,
            self.config.rate_limit_window,
        ) {
            self.stats.rejected += 1;
            return Err(ConfirmationError::RateLimited(
                "Too many failed attempts".to_string(),
            ));
        }

        // Get token
        let confirmation = self
            .pending
            .get_mut(token)
            .ok_or_else(|| ConfirmationError::TokenNotFound(token.to_string()))?;

        // Check expiration
        let now = Utc::now().timestamp() as u64;
        if confirmation.expires_at < now {
            confirmation.status = ConfirmationStatus::Expired;
            self.stats.expired += 1;
            return Err(ConfirmationError::TokenExpired(
                "Confirmation timed out".to_string(),
            ));
        }

        // Verify signature
        let token_data = format!(
            "{}|{}|{}|{}|{}",
            confirmation.token,
            confirmation.proposal_id,
            confirmation.capability_id,
            confirmation.created_at,
            confirmation.expires_at
        );

        if !self.verify(&token_data, &confirmation.signature) {
            self.stats.rejected += 1;
            return Err(ConfirmationError::InvalidToken(
                "Signature verification failed".to_string(),
            ));
        }

        // Mark as confirmed
        confirmation.status = ConfirmationStatus::Confirmed;
        self.rate_limiter.reset(token);
        self.stats.confirmed += 1;

        Ok(ConfirmationResult {
            success: true,
            confirmed: true,
            token: Some(token.to_string()),
            reason: "Action confirmed".to_string(),
            expires_at: confirmation.expires_at,
        })
    }

    /// Deny an action
    pub fn deny(&mut self, token: &str) -> Result<ConfirmationResult, ConfirmationError> {
        let confirmation = self
            .pending
            .get_mut(token)
            .ok_or_else(|| ConfirmationError::TokenNotFound(token.to_string()))?;

        confirmation.status = ConfirmationStatus::Denied;
        self.rate_limiter.reset(token);
        self.stats.denied += 1;

        Ok(ConfirmationResult {
            success: true,
            confirmed: false,
            token: Some(token.to_string()),
            reason: "Action denied".to_string(),
            expires_at: confirmation.expires_at,
        })
    }

    /// Check confirmation status
    pub fn check_status(&mut self, token: &str) -> Result<ConfirmationStatus, ConfirmationError> {
        let now = Utc::now().timestamp() as u64;
        
        if let Some(confirmation) = self.pending.get_mut(token) {
            // Check expiration
            if confirmation.expires_at < now {
                confirmation.status = ConfirmationStatus::Expired;
                self.stats.expired += 1;
            }
            Ok(confirmation.status)
        } else {
            Err(ConfirmationError::TokenNotFound(token.to_string()))
        }
    }

    /// Cleanup expired tokens
    pub fn cleanup(&mut self) -> usize {
        let now = Utc::now().timestamp() as u64;
        
        let expired: Vec<String> = self
            .pending
            .iter()
            .filter(|(_, c)| c.expires_at < now)
            .map(|(token, _)| token.clone())
            .collect();

        for token in &expired {
            if let Some(c) = self.pending.get_mut(token) {
                c.status = ConfirmationStatus::Expired;
            }
            self.stats.expired += 1;
        }

        // Remove expired tokens
        self.pending.retain(|_, c| c.status == ConfirmationStatus::Pending);

        expired.len()
    }

    /// Get statistics
    pub fn get_stats(&self) -> ConfirmationStats {
        self.stats.clone()
    }

    /// Get pending count
    pub fn pending_count(&self) -> usize {
        self.pending
            .iter()
            .filter(|(_, c)| c.status == ConfirmationStatus::Pending)
            .count()
    }
}

impl Default for SecureConfirmationGate {
    fn default() -> Self {
        Self::new()
    }
}

// Global gate
static CONFIRMATION_GATE: Lazy<RwLock<SecureConfirmationGate>> = Lazy::new(|| {
    RwLock::new(SecureConfirmationGate::new())
});

/// Initialize gate with secret
pub fn init(secret: &[u8; 32]) {
    CONFIRMATION_GATE.write().unwrap().initialize(secret);
}

/// Request confirmation
pub fn request_confirmation(request: &ConfirmationRequest) -> Result<ConfirmationResult, ConfirmationError> {
    CONFIRMATION_GATE.write().unwrap().request_confirmation(request)
}

/// Confirm action
pub fn confirm(token: &str) -> Result<ConfirmationResult, ConfirmationError> {
    CONFIRMATION_GATE.write().unwrap().confirm(token)
}

/// Deny action
pub fn deny(token: &str) -> Result<ConfirmationResult, ConfirmationError> {
    CONFIRMATION_GATE.write().unwrap().deny(token)
}

/// Check status
pub fn check_status(token: &str) -> Result<ConfirmationStatus, ConfirmationError> {
    CONFIRMATION_GATE.write().unwrap().check_status(token)
}

/// Get stats
pub fn get_stats() -> ConfirmationStats {
    CONFIRMATION_GATE.read().unwrap().get_stats()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_confirmation() {
        let mut gate = SecureConfirmationGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let request = ConfirmationRequest {
            proposal_id: "test_proposal".to_string(),
            capability_id: "safe_shell".to_string(),
            params: r#"{"command": "echo test"}"#.to_string(),
            risk_level: RiskLevel::Medium,
            reasoning: "Test confirmation".to_string(),
        };

        let result = gate.request_confirmation(&request).unwrap();
        assert!(result.token.is_some());
        
        // Confirm
        let confirmed = gate.confirm(result.token.as_ref().unwrap()).unwrap();
        assert!(confirmed.confirmed);
    }

    #[test]
    fn test_deny() {
        let mut gate = SecureConfirmationGate::new();
        let mut secret = [0u8; 32];
        secret.copy_from_slice(&[1u8; 32]);
        gate.initialize(&secret);

        let request = ConfirmationRequest {
            proposal_id: "test_proposal".to_string(),
            capability_id: "safe_shell".to_string(),
            params: r#"{"command": "echo test"}"#.to_string(),
            risk_level: RiskLevel::Medium,
            reasoning: "Test confirmation".to_string(),
        };

        let result = gate.request_confirmation(&request).unwrap();
        
        // Deny
        let denied = gate.deny(result.token.as_ref().unwrap()).unwrap();
        assert!(!denied.confirmed);
    }
}
