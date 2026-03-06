//! Token Rotation Module
//!
//! This module provides automatic token refresh, secure token storage,
//! token validation, verification, and identity chaining between agents.

use crate::identity::oauth_agent_client::{OAuthAgentClient, OAuthToken};
use crate::identity::spiffe_identity::{SpiffeId, SpiffeIdentity, TrustDomain, IdentityProvider};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use thiserror::Error;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration as TokioDuration};

/// Token Rotation Errors
#[derive(Error, Debug)]
pub enum TokenRotationError {
    #[error("Token rotation failed: {0}")]
    RotationFailed(String),
    #[error("Token storage error: {0}")]
    StorageError(String),
    #[error("Token validation error: {0}")]
    ValidationError(String),
    #[error("Identity chain error: {0}")]
    ChainError(String),
    #[error("Token not found: {0}")]
    NotFound(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
}

/// Token Storage Entry
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TokenStorageEntry {
    /// Agent ID
    pub agent_id: String,
    /// Access token
    pub access_token: String,
    /// Refresh token
    pub refresh_token: Option<String>,
    /// Token type
    pub token_type: String,
    /// Expiration timestamp
    pub expires_at: DateTime<Utc>,
    /// Issued at
    pub issued_at: DateTime<Utc>,
    /// Audience
    pub audience: Vec<String>,
    /// Scope
    pub scope: Option<String>,
    /// Encrypted flag
    pub encrypted: bool,
}

/// Token Rotation Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenRotationConfig {
    /// Enable automatic rotation
    pub auto_rotate: bool,
    /// Rotation threshold (seconds before expiry)
    pub rotation_threshold_secs: i64,
    /// Rotation check interval (seconds)
    pub rotation_check_interval_secs: u64,
    /// Maximum rotation attempts
    pub max_rotation_attempts: u32,
    /// Enable secure storage
    pub secure_storage: bool,
    /// Storage path
    pub storage_path: PathBuf,
    /// Enable identity chaining
    pub enable_identity_chaining: bool,
    /// Chain TTL (seconds)
    pub chain_ttl_secs: i64,
}

impl Default for TokenRotationConfig {
    fn default() -> Self {
        TokenRotationConfig {
            auto_rotate: true,
            rotation_threshold_secs: 300, // 5 minutes
            rotation_check_interval_secs: 60, // 1 minute
            max_rotation_attempts: 3,
            secure_storage: true,
            storage_path: PathBuf::from("/var/lib/itheris/tokens"),
            enable_identity_chaining: true,
            chain_ttl_secs: 3600, // 1 hour
        }
    }
}

/// Identity Chain Entry
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct IdentityChainEntry {
    /// Source agent ID
    pub source_agent_id: String,
    /// Target agent ID
    pub target_agent_id: String,
    /// Chain type
    pub chain_type: ChainType,
    /// Created at
    pub created_at: DateTime<Utc>,
    /// Expires at
    pub expires_at: DateTime<Utc>,
    /// Is active
    pub active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ChainType {
    Delegation,
    Impersonation,
    Federation,
}

impl IdentityChainEntry {
    /// Create a new chain entry
    pub fn new(
        source_agent_id: &str,
        target_agent_id: &str,
        chain_type: ChainType,
        ttl_secs: i64,
    ) -> Self {
        let now = Utc::now();
        
        IdentityChainEntry {
            source_agent_id: source_agent_id.to_string(),
            target_agent_id: target_agent_id.to_string(),
            chain_type,
            created_at: now,
            expires_at: now + Duration::seconds(ttl_secs),
            active: true,
        }
    }

    /// Check if chain is valid
    pub fn is_valid(&self) -> bool {
        self.active && Utc::now() < self.expires_at
    }

    /// Invalidate the chain
    pub fn invalidate(&mut self) {
        self.active = false;
    }
}

/// Secure Token Storage
pub struct SecureTokenStorage {
    config: TokenRotationConfig,
    tokens: RwLock<HashMap<String, TokenStorageEntry>>,
}

impl SecureTokenStorage {
    /// Create a new secure token storage
    pub fn new(config: TokenRotationConfig) -> Self {
        SecureTokenStorage {
            config,
            tokens: RwLock::new(HashMap::new()),
        }
    }

    /// Store a token
    pub fn store_token(&self, agent_id: &str, token: &OAuthToken, refresh_token: Option<String>) -> Result<(), TokenRotationError> {
        let entry = TokenStorageEntry {
            agent_id: agent_id.to_string(),
            access_token: token.access_token.clone(),
            refresh_token,
            token_type: token.token_type.clone(),
            expires_at: token.expires_at,
            issued_at: token.issued_at,
            audience: token.audience.clone(),
            scope: token.scope.clone(),
            encrypted: self.config.secure_storage,
        };

        let mut tokens = self.tokens.write().unwrap();
        tokens.insert(agent_id.to_string(), entry);

        // In production, also persist to disk if secure_storage is enabled
        if self.config.secure_storage {
            self.persist_tokens()?;
        }

        Ok(())
    }

    /// Get a token
    pub fn get_token(&self, agent_id: &str) -> Result<TokenStorageEntry, TokenRotationError> {
        let tokens = self.tokens.read().unwrap();
        
        tokens
            .get(agent_id)
            .cloned()
            .ok_or_else(|| TokenRotationError::NotFound(format!("Token not found for agent: {}", agent_id)))
    }

    /// Delete a token
    pub fn delete_token(&self, agent_id: &str) -> Result<(), TokenRotationError> {
        let mut tokens = self.tokens.write().unwrap();
        
        if tokens.remove(agent_id).is_none() {
            return Err(TokenRotationError::NotFound(format!("Token not found for agent: {}", agent_id)));
        }

        if self.config.secure_storage {
            self.persist_tokens()?;
        }

        Ok(())
    }

    /// List all tokens
    pub fn list_tokens(&self) -> Vec<TokenStorageEntry> {
        let tokens = self.tokens.read().unwrap();
        tokens.values().cloned().collect()
    }

    /// Check if token needs rotation
    pub fn needs_rotation(&self, agent_id: &str) -> bool {
        if let Ok(entry) = self.get_token(agent_id) {
            let threshold = Utc::now() + Duration::seconds(self.config.rotation_threshold_secs);
            entry.expires_at < threshold
        } else {
            true
        }
    }

    /// Get expired tokens
    pub fn get_expired_tokens(&self) -> Vec<TokenStorageEntry> {
        let tokens = self.tokens.read().unwrap();
        let now = Utc::now();
        
        tokens
            .values()
            .filter(|t| t.expires_at < now)
            .cloned()
            .collect()
    }

    /// Persist tokens to disk
    fn persist_tokens(&self) -> Result<(), TokenRotationError> {
        // In production, this would encrypt and write to disk
        // For now, just ensure directory exists
        if !self.config.storage_path.exists() {
            std::fs::create_dir_all(&self.config.storage_path)?;
        }
        Ok(())
    }

    /// Load tokens from disk
    pub fn load_tokens(&self) -> Result<(), TokenRotationError> {
        // In production, this would decrypt and load from disk
        Ok(())
    }
}

/// Token Rotation Manager
pub struct TokenRotationManager {
    config: TokenRotationConfig,
    oauth_client: Arc<OAuthAgentClient>,
    storage: Arc<SecureTokenStorage>,
    identity_chains: RwLock<HashMap<String, IdentityChainEntry>>,
    rotation_tx: Option<mpsc::Sender<RotationCommand>>,
}

#[derive(Debug, Clone)]
enum RotationCommand {
    Rotate { agent_id: String },
    CheckAll,
    Shutdown,
}

impl TokenRotationManager {
    /// Create a new token rotation manager
    pub fn new(config: TokenRotationConfig, oauth_client: Arc<OAuthAgentClient>) -> Self {
        let storage = Arc::new(SecureTokenStorage::new(config.clone()));
        
        TokenRotationManager {
            config,
            oauth_client,
            storage,
            identity_chains: RwLock::new(HashMap::new()),
            rotation_tx: None,
        }
    }

    /// Start automatic rotation
    pub async fn start_rotation(&mut self) {
        let (tx, mut rx) = mpsc::channel::<RotationCommand>(100);
        self.rotation_tx = Some(tx);

        let config = self.config.clone();
        let oauth_client = self.oauth_client.clone();
        let storage = self.storage.clone();

        tokio::spawn(async move {
            let mut check_interval = interval(TokioDuration::from_secs(config.rotation_check_interval_secs));
            
            loop {
                tokio::select! {
                    _ = check_interval.tick() => {
                        // Check all tokens for rotation
                        let tokens = storage.list_tokens();
                        
                        for token_entry in tokens {
                            if storage.needs_rotation(&token_entry.agent_id) {
                                // Attempt rotation
                                let mut attempts = 0;
                                let mut success = false;
                                
                                while attempts < config.max_rotation_attempts && !success {
                                    match oauth_client.refresh_token(&token_entry.agent_id) {
                                        Ok(new_token) => {
                                            // Store new token
                                            let refresh_token = new_token.refresh_token.clone();
                                            if let Err(e) = storage.store_token(
                                                &token_entry.agent_id,
                                                &new_token,
                                                refresh_token
                                            ) {
                                                log::error!("Failed to store rotated token: {}", e);
                                            } else {
                                                success = true;
                                                log::info!("Token rotated successfully for agent: {}", token_entry.agent_id);
                                            }
                                        }
                                        Err(e) => {
                                            log::error!("Token rotation failed for agent {}: {}", token_entry.agent_id, e);
                                        }
                                    }
                                    
                                    attempts += 1;
                                }
                            }
                        }
                    }
                    Some(cmd) = rx.recv() => {
                        match cmd {
                            RotationCommand::Rotate { agent_id } => {
                                if let Err(e) = oauth_client.refresh_token(&agent_id) {
                                    log::error!("Manual rotation failed for agent {}: {}", agent_id, e);
                                }
                            }
                            RotationCommand::CheckAll => {
                                // Manual check
                            }
                            RotationCommand::Shutdown => {
                                break;
                            }
                        }
                    }
                }
            }
        });
    }

    /// Stop automatic rotation
    pub async fn stop_rotation(&self) {
        if let Some(tx) = &self.rotation_tx {
            let _ = tx.send(RotationCommand::Shutdown).await;
        }
    }

    /// Rotate token for a specific agent
    pub async fn rotate_token(&self, agent_id: &str) -> Result<OAuthToken, TokenRotationError> {
        // Get current token from storage
        let entry = self.storage.get_token(agent_id)?;
        
        // Check if rotation is needed
        if !self.storage.needs_rotation(agent_id) {
            // Return stored token
            return self.oauth_client.validate_token(agent_id, &entry.access_token)
                .map_err(|e| TokenRotationError::ValidationError(e.to_string()));
        }

        // Perform rotation
        let new_token = self.oauth_client.refresh_token(agent_id)
            .map_err(|e| TokenRotationError::RotationFailed(e.to_string()))?;

        // Store new token
        let refresh_token = new_token.refresh_token.clone();
        self.storage.store_token(agent_id, &new_token, refresh_token)?;

        Ok(new_token)
    }

    /// Validate a token
    pub fn validate_token(&self, agent_id: &str, token: &str) -> Result<OAuthToken, TokenRotationError> {
        self.oauth_client.validate_token(agent_id, token)
            .map_err(|e| TokenRotationError::ValidationError(e.to_string()))
    }

    /// Get token status
    pub fn get_token_status(&self, agent_id: &str) -> Result<TokenStatus, TokenRotationError> {
        let entry = self.storage.get_token(agent_id)?;
        
        let now = Utc::now();
        let remaining = entry.expires_at.signed_duration_since(now);
        
        let needs_rotation = remaining.num_seconds() < self.config.rotation_threshold_secs;
        
        Ok(TokenStatus {
            agent_id: agent_id.to_string(),
            expires_at: entry.expires_at,
            remaining_seconds: remaining.num_seconds(),
            needs_rotation,
            is_expired: remaining.is_zero() || remaining.is_negative(),
        })
    }

    /// Create identity chain between agents
    pub fn create_identity_chain(
        &self,
        source_agent_id: &str,
        target_agent_id: &str,
        chain_type: ChainType,
    ) -> Result<IdentityChainEntry, TokenRotationError> {
        // Verify both agents exist
        let _ = self.oauth_client.get_agent(source_agent_id)
            .ok_or_else(|| TokenRotationError::ChainError(format!("Source agent not found: {}", source_agent_id)))?;
        
        let _ = self.oauth_client.get_agent(target_agent_id)
            .ok_or_else(|| TokenRotationError::ChainError(format!("Target agent not found: {}", target_agent_id)))?;

        let chain = IdentityChainEntry::new(
            source_agent_id,
            target_agent_id,
            chain_type,
            self.config.chain_ttl_secs,
        );

        let key = format!("{}:{}", source_agent_id, target_agent_id);
        let mut chains = self.identity_chains.write().unwrap();
        chains.insert(key, chain.clone());

        Ok(chain)
    }

    /// Validate identity chain
    pub fn validate_identity_chain(&self, source_agent_id: &str, target_agent_id: &str) -> Result<IdentityChainEntry, TokenRotationError> {
        let key = format!("{}:{}", source_agent_id, target_agent_id);
        let chains = self.identity_chains.read().unwrap();
        
        let chain = chains.get(&key)
            .ok_or_else(|| TokenRotationError::ChainError(format!("No chain found between {} and {}", source_agent_id, target_agent_id)))?;
        
        if !chain.is_valid() {
            return Err(TokenRotationError::ChainError("Chain is expired or invalidated".to_string()));
        }

        Ok(chain.clone())
    }

    /// Get chains for an agent
    pub fn get_agent_chains(&self, agent_id: &str) -> Vec<IdentityChainEntry> {
        let chains = self.identity_chains.read().unwrap();
        
        chains
            .values()
            .filter(|c| c.source_agent_id == agent_id || c.target_agent_id == agent_id)
            .filter(|c| c.is_valid())
            .cloned()
            .collect()
    }

    /// Invalidate identity chain
    pub fn invalidate_chain(&self, source_agent_id: &str, target_agent_id: &str) -> Result<(), TokenRotationError> {
        let key = format!("{}:{}", source_agent_id, target_agent_id);
        let mut chains = self.identity_chains.write().unwrap();
        
        if let Some(chain) = chains.get_mut(&key) {
            chain.invalidate();
            Ok(())
        } else {
            Err(TokenRotationError::ChainError(format!("Chain not found: {}", key)))
        }
    }

    /// Get storage
    pub fn storage(&self) -> &Arc<SecureTokenStorage> {
        &self.storage
    }
}

/// Token Status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenStatus {
    pub agent_id: String,
    pub expires_at: DateTime<Utc>,
    pub remaining_seconds: i64,
    pub needs_rotation: bool,
    pub is_expired: bool,
}

/// Token Validator
pub struct TokenValidator {
    oauth_client: Arc<OAuthAgentClient>,
    storage: Arc<SecureTokenStorage>,
}

impl TokenValidator {
    /// Create a new token validator
    pub fn new(oauth_client: Arc<OAuthAgentClient>, storage: Arc<SecureTokenStorage>) -> Self {
        TokenValidator {
            oauth_client,
            storage,
        }
    }

    /// Validate token with full checks
    pub fn validate(&self, agent_id: &str, token: &str) -> Result<ValidationResult, TokenRotationError> {
        // First check storage
        let storage_entry = match self.storage.get_token(agent_id) {
            Ok(entry) => entry,
            Err(_) => {
                // Fall back to OAuth client validation
                let validated = self.oauth_client.validate_token(agent_id, token)
                    .map_err(|e| TokenRotationError::ValidationError(e.to_string()))?;
                
                return Ok(ValidationResult {
                    valid: validated.is_valid(),
                    agent_id: agent_id.to_string(),
                    expires_at: validated.expires_at,
                    remaining_seconds: validated.remaining_seconds(),
                    errors: vec![],
                });
            }
        };

        // Verify token matches
        if storage_entry.access_token != token {
            return Ok(ValidationResult {
                valid: false,
                agent_id: agent_id.to_string(),
                expires_at: storage_entry.expires_at,
                remaining_seconds: 0,
                errors: vec!["Token mismatch".to_string()],
            });
        }

        // Check expiration
        let now = Utc::now();
        let remaining = storage_entry.expires_at.signed_duration_since(now);
        
        if remaining.is_negative() {
            return Ok(ValidationResult {
                valid: false,
                agent_id: agent_id.to_string(),
                expires_at: storage_entry.expires_at,
                remaining_seconds: 0,
                errors: vec!["Token expired".to_string()],
            });
        }

        // Check audience if specified
        // (In production, validate against requested audience)

        Ok(ValidationResult {
            valid: true,
            agent_id: agent_id.to_string(),
            expires_at: storage_entry.expires_at,
            remaining_seconds: remaining.num_seconds(),
            errors: vec![],
        })
    }

    /// Quick check if token is valid
    pub fn is_valid(&self, agent_id: &str) -> bool {
        if let Ok(entry) = self.storage.get_token(agent_id) {
            !entry.expires_at < Utc::now()
        } else {
            false
        }
    }
}

/// Validation Result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub valid: bool,
    pub agent_id: String,
    pub expires_at: DateTime<Utc>,
    pub remaining_seconds: i64,
    pub errors: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_storage() {
        let config = TokenRotationConfig::default();
        let storage = SecureTokenStorage::new(config);
        
        let token = OAuthToken::new(
            "test_token".to_string(),
            "Bearer",
            3600,
            vec!["test".to_string()],
            "test-issuer".to_string(),
        );
        
        storage.store_token("agent-001", &token, Some("refresh".to_string())).unwrap();
        
        let retrieved = storage.get_token("agent-001").unwrap();
        assert_eq!(retrieved.access_token, "test_token");
    }

    #[test]
    fn test_needs_rotation() {
        let config = TokenRotationConfig::default();
        let storage = SecureTokenStorage::new(config);
        
        // Initially no token, needs rotation
        assert!(storage.needs_rotation("agent-001"));
        
        // Add a valid token
        let token = OAuthToken::new(
            "test_token".to_string(),
            "Bearer",
            3600,
            vec!["test".to_string()],
            "test-issuer".to_string(),
        );
        
        storage.store_token("agent-002", &token, None).unwrap();
        
        // Should not need rotation
        assert!(!storage.needs_rotation("agent-002"));
    }

    #[test]
    fn test_identity_chain() {
        let config = TokenRotationConfig::default();
        let oauth_client = Arc::new(OAuthAgentClient::default_client());
        let manager = TokenRotationManager::new(config, oauth_client);
        
        // Register agents
        let spiffe_id = SpiffeId::for_agent("test", "01").unwrap();
        oauth_client.register_agent(
            "agent-001".to_string(),
            spiffe_id.clone(),
            "test",
            vec![],
        ).unwrap();
        
        let spiffe_id2 = SpiffeId::for_agent("test", "02").unwrap();
        oauth_client.register_agent(
            "agent-002".to_string(),
            spiffe_id2,
            "test",
            vec![],
        ).unwrap();
        
        // Create chain
        let chain = manager.create_identity_chain(
            "agent-001",
            "agent-002",
            ChainType::Delegation,
        ).unwrap();
        
        assert!(chain.is_valid());
        
        // Validate chain
        let validated = manager.validate_identity_chain("agent-001", "agent-002").unwrap();
        assert!(validated.is_valid());
    }

    #[test]
    fn test_token_validator() {
        let config = TokenRotationConfig::default();
        let oauth_client = Arc::new(OAuthAgentClient::default_client());
        let storage = Arc::new(SecureTokenStorage::new(config.clone()));
        
        // Register agent and issue token
        let spiffe_id = SpiffeId::for_agent("validator", "01").unwrap();
        oauth_client.register_agent(
            "agent-validator".to_string(),
            spiffe_id,
            "validator",
            vec![],
        ).unwrap();
        
        let token = oauth_client.issue_token("agent-validator", None, None).unwrap();
        
        // Store token
        storage.store_token("agent-validator", &token, token.refresh_token.clone()).unwrap();
        
        // Create validator
        let validator = TokenValidator::new(oauth_client, storage);
        
        // Validate
        let result = validator.validate("agent-validator", &token.access_token).unwrap();
        assert!(result.valid);
    }

    #[test]
    fn test_chain_invalidation() {
        let config = TokenRotationConfig::default();
        let oauth_client = Arc::new(OAuthAgentClient::default_client());
        let manager = TokenRotationManager::new(config, oauth_client);
        
        // Register agents
        let spiffe_id = SpiffeId::for_agent("chain", "01").unwrap();
        oauth_client.register_agent(
            "source-agent".to_string(),
            spiffe_id.clone(),
            "test",
            vec![],
        ).unwrap();
        
        let spiffe_id2 = SpiffeId::for_agent("chain", "02").unwrap();
        oauth_client.register_agent(
            "target-agent".to_string(),
            spiffe_id2,
            "test",
            vec![],
        ).unwrap();
        
        // Create and invalidate chain
        manager.create_identity_chain(
            "source-agent",
            "target-agent",
            ChainType::Federation,
        ).unwrap();
        
        manager.invalidate_chain("source-agent", "target-agent").unwrap();
        
        // Validation should fail
        let result = manager.validate_identity_chain("source-agent", "target-agent");
        assert!(result.is_err());
    }
}
