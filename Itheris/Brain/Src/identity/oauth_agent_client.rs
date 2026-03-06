//! OAuth 2.1 Agent Client
//!
//! This module implements OAuth 2.1 for agent identity management,
//! including short-lived token issuance (RFC 9396), audience binding,
//! token refresh, rotation, and device code flow support.

use crate::identity::spiffe_identity::{SpiffeId, TrustDomain};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;
use uuid::Uuid;

/// OAuth 2.1 Errors
#[derive(Error, Debug)]
pub enum OAuthError {
    #[error("Token expired at {0}")]
    TokenExpired(DateTime<Utc>),
    #[error("Token not yet valid (issued at: {0})")]
    TokenNotYetValid(DateTime<Utc>),
    #[error("Invalid audience: expected {expected}, got {actual}")]
    InvalidAudience { expected: String, actual: String },
    #[error("Invalid issuer: expected {expected}, got {actual}")]
    InvalidIssuer { expected: String, actual: String },
    #[error("Token issuance failed: {0}")]
    IssuanceFailed(String),
    #[error("Token refresh failed: {0}")]
    RefreshFailed(String),
    #[error("Token validation failed: {0}")]
    ValidationFailed(String),
    #[error("HTTP error: {0}")]
    HttpError(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

/// OAuth 2.1 Token Types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TokenType {
    AccessToken,
    RefreshToken,
    IdToken,
}

/// OAuth Token
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OAuthToken {
    /// Access token value
    pub access_token: String,
    /// Token type (Bearer)
    pub token_type: String,
    /// Expiration time (seconds from now)
    pub expires_in: i64,
    /// Refresh token
    pub refresh_token: Option<String>,
    /// Scope
    pub scope: Option<String>,
    /// Issued at
    pub issued_at: DateTime<Utc>,
    /// Expiration time
    pub expires_at: DateTime<Utc>,
    /// Audience
    pub audience: Vec<String>,
    /// Issuer
    pub issuer: String,
    /// Custom claims
    pub claims: HashMap<String, serde_json::Value>,
}

impl OAuthToken {
    /// Create a new OAuth token
    pub fn new(
        access_token: String,
        token_type: &str,
        expires_in: i64,
        audience: Vec<String>,
        issuer: String,
    ) -> Self {
        let now = Utc::now();
        let expires = now + Duration::seconds(expires_in);

        OAuthToken {
            access_token,
            token_type: token_type.to_string(),
            expires_in,
            refresh_token: None,
            scope: None,
            issued_at: now,
            expires_at: expires,
            audience,
            issuer,
            claims: HashMap::new(),
        }
    }

    /// Check if token is expired
    pub fn is_expired(&self) -> bool {
        Utc::now() > self.expires_at
    }

    /// Check if token is valid
    pub fn is_valid(&self) -> bool {
        !self.is_expired()
    }

    /// Check if token expires within given seconds
    pub fn expires_soon(&self, seconds: i64) -> bool {
        let threshold = Utc::now() + Duration::seconds(seconds);
        self.expires_at < threshold
    }

    /// Validate audience
    pub fn validate_audience(&self, expected: &str) -> Result<(), OAuthError> {
        if self.audience.contains(&expected.to_string()) {
            Ok(())
        } else {
            Err(OAuthError::InvalidAudience {
                expected: expected.to_string(),
                actual: self.audience.join(", "),
            })
        }
    }

    /// Validate issuer
    pub fn validate_issuer(&self, expected: &str) -> Result<(), OAuthError> {
        if self.issuer == expected {
            Ok(())
        } else {
            Err(OAuthError::InvalidIssuer {
                expected: expected.to_string(),
                actual: self.issuer,
            })
        }
    }

    /// Get remaining validity in seconds
    pub fn remaining_seconds(&self) -> i64 {
        let now = Utc::now();
        if now >= self.expires_at {
            0
        } else {
            self.expires_at.signed_duration_since(now).num_seconds()
        }
    }

    /// Add custom claim
    pub fn set_claim(&mut self, key: &str, value: serde_json::Value) {
        self.claims.insert(key.to_string(), value);
    }

    /// Get custom claim
    pub fn get_claim(&self, key: &str) -> Option<&serde_json::Value> {
        self.claims.get(key)
    }
}

/// Agent Identity
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AgentIdentity {
    /// Unique agent ID
    pub agent_id: String,
    /// SPIFFE ID
    pub spiffe_id: SpiffeId,
    /// Agent type (coordinator, executor, etc.)
    pub agent_type: String,
    /// Agent capabilities
    pub capabilities: Vec<String>,
    /// Current OAuth token
    pub token: Option<OAuthToken>,
    /// Token issued at
    pub token_issued_at: Option<DateTime<Utc>>,
    /// Token refresh threshold (seconds before expiry)
    pub refresh_threshold_secs: i64,
    /// Created at
    pub created_at: DateTime<Utc>,
    /// Last updated
    pub updated_at: DateTime<Utc>,
    /// Status
    pub status: AgentStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AgentStatus {
    Active,
    Suspended,
    Revoked,
    Pending,
}

impl AgentIdentity {
    /// Create a new agent identity
    pub fn new(
        agent_id: String,
        spiffe_id: SpiffeId,
        agent_type: String,
        capabilities: Vec<String>,
    ) -> Self {
        let now = Utc::now();

        AgentIdentity {
            agent_id,
            spiffe_id,
            agent_type,
            capabilities,
            token: None,
            token_issued_at: None,
            refresh_threshold_secs: 300, // 5 minutes
            created_at: now,
            updated_at: now,
            status: AgentStatus::Pending,
        }
    }

    /// Set token
    pub fn set_token(&mut self, token: OAuthToken) {
        self.token = Some(token);
        self.token_issued_at = Some(Utc::now());
        self.updated_at = Utc::now();
        self.status = AgentStatus::Active;
    }

    /// Clear token
    pub fn clear_token(&mut self) {
        self.token = None;
        self.token_issued_at = None;
        self.updated_at = Utc::now();
    }

    /// Check if token needs refresh
    pub fn needs_token_refresh(&self) -> bool {
        if let Some(token) = &self.token {
            token.expires_soon(self.refresh_threshold_secs)
        } else {
            true
        }
    }

    /// Get current access token
    pub fn access_token(&self) -> Option<&str> {
        self.token.as_ref().map(|t| t.access_token.as_str())
    }
}

/// OAuth Agent Client Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthClientConfig {
    /// Authorization server URL
    pub auth_server_url: String,
    /// Client ID
    pub client_id: String,
    /// Client secret
    pub client_secret: Option<String>,
    /// Token endpoint
    pub token_endpoint: String,
    /// Authorization endpoint
    pub authorization_endpoint: String,
    /// Device authorization endpoint
    pub device_authorization_endpoint: Option<String>,
    /// Default scope
    pub default_scope: String,
    /// Default audience
    pub default_audience: String,
    /// Token validity in seconds
    pub token_validity_secs: i64,
    /// Refresh threshold in seconds
    pub refresh_threshold_secs: i64,
}

impl Default for OAuthClientConfig {
    fn default() -> Self {
        OAuthClientConfig {
            auth_server_url: "https://auth.warden-mesh.internal".to_string(),
            client_id: "itheris-agent".to_string(),
            client_secret: None,
            token_endpoint: "/oauth/token".to_string(),
            authorization_endpoint: "/oauth/authorize".to_string(),
            device_authorization_endpoint: Some("/oauth/device".to_string()),
            default_scope: "agent:identity".to_string(),
            default_audience: "warden-mesh".to_string(),
            token_validity_secs: 3600, // 1 hour
            refresh_threshold_secs: 300, // 5 minutes
        }
    }
}

/// OAuth Agent Client
pub struct OAuthAgentClient {
    config: OAuthClientConfig,
    agents: RwLock<HashMap<String, AgentIdentity>>,
    issuer: String,
}

impl OAuthAgentClient {
    /// Create a new OAuth agent client
    pub fn new(config: OAuthClientConfig) -> Self {
        let issuer = config.auth_server_url.clone();
        
        OAuthAgentClient {
            config,
            agents: RwLock::new(HashMap::new()),
            issuer,
        }
    }

    /// Create with default configuration
    pub fn default_client() -> Self {
        Self::new(OAuthClientConfig::default())
    }

    /// Register an agent
    pub fn register_agent(
        &self,
        agent_id: String,
        spiffe_id: SpiffeId,
        agent_type: &str,
        capabilities: Vec<String>,
    ) -> Result<AgentIdentity, OAuthError> {
        let identity = AgentIdentity::new(
            agent_id.clone(),
            spiffe_id,
            agent_type.to_string(),
            capabilities,
        );

        let mut agents = self.agents.write().unwrap();
        agents.insert(agent_id, identity.clone());

        Ok(identity)
    }

    /// Get an agent by ID
    pub fn get_agent(&self, agent_id: &str) -> Option<AgentIdentity> {
        let agents = self.agents.read().unwrap();
        agents.get(agent_id).cloned()
    }

    /// Issue a token for an agent (RFC 9396 - short-lived tokens)
    pub fn issue_token(&self, agent_id: &str, audience: Option<String>, scope: Option<String>) -> Result<OAuthToken, OAuthError> {
        let mut agents = self.agents.write().unwrap();
        
        let agent = agents.get_mut(agent_id)
            .ok_or_else(|| OAuthError::IssuanceFailed(format!("Agent not found: {}", agent_id)))?;

        // Build token claims
        let aud = audience.unwrap_or_else(|| self.config.default_audience.clone());
        let scp = scope.unwrap_or_else(|| self.config.default_scope.clone());

        // Generate access token (in production, this would call the authorization server)
        let access_token = self.generate_access_token(agent);
        
        // Create token
        let mut token = OAuthToken::new(
            access_token,
            "Bearer",
            self.config.token_validity_secs,
            vec![aud.clone()],
            self.issuer.clone(),
        );
        
        token.scope = Some(scp);
        
        // Add agent claims (RFC 9396)
        token.set_claim("agent_id", serde_json::json!(agent.agent_id));
        token.set_claim("agent_type", serde_json::json!(agent.agent_type));
        token.set_claim("spiffe_id", serde_json::json!(agent.spiffe_id.to_string()));
        token.set_claim("capabilities", serde_json::json!(agent.capabilities));

        // Set refresh token (for token rotation)
        let refresh_token = self.generate_refresh_token(agent);
        token.refresh_token = Some(refresh_token);

        // Update agent
        agent.set_token(token.clone());

        Ok(token)
    }

    /// Refresh a token (RFC 9396)
    pub fn refresh_token(&self, agent_id: &str) -> Result<OAuthToken, OAuthError> {
        let mut agents = self.agents.write().unwrap();
        
        let agent = agents.get_mut(agent_id)
            .ok_or_else(|| OAuthError::RefreshFailed(format!("Agent not found: {}", agent_id)))?;

        // Check if we have a refresh token
        if let Some(token) = &agent.token {
            if let Some(refresh_token) = &token.refresh_token {
                // Validate refresh token (in production, call authorization server)
                // For now, issue new token directly
                return self.issue_token_internal(agent, token);
            }
        }

        // No refresh token available, issue new token
        self.issue_token_internal(agent, None)
    }

    /// Internal token issuance
    fn issue_token_internal(&self, agent: &mut AgentIdentity, _old_token: Option<&OAuthToken>) -> Result<OAuthToken, OAuthError> {
        let access_token = self.generate_access_token(agent);
        
        let mut token = OAuthToken::new(
            access_token,
            "Bearer",
            self.config.token_validity_secs,
            vec![self.config.default_audience.clone()],
            self.issuer.clone(),
        );
        
        token.scope = Some(self.config.default_scope.clone());
        
        // Add agent claims
        token.set_claim("agent_id", serde_json::json!(agent.agent_id));
        token.set_claim("agent_type", serde_json::json!(agent.agent_type));
        token.set_claim("spiffe_id", serde_json::json!(agent.spiffe_id.to_string()));
        token.set_claim("capabilities", serde_json::json!(agent.capabilities));

        // Generate new refresh token
        let refresh_token = self.generate_refresh_token(agent);
        token.refresh_token = Some(refresh_token);

        agent.set_token(token.clone());

        Ok(token)
    }

    /// Validate a token
    pub fn validate_token(&self, agent_id: &str, token: &str) -> Result<OAuthToken, OAuthError> {
        let agents = self.agents.read().unwrap();
        
        let agent = agents.get(agent_id)
            .ok_or_else(|| OAuthError::ValidationFailed(format!("Agent not found: {}", agent_id)))?;

        let current_token = agent.token.as_ref()
            .ok_or_else(|| OAuthError::ValidationFailed("No token issued".to_string()))?;

        // Check if token matches
        if current_token.access_token != token {
            return Err(OAuthError::ValidationFailed("Token mismatch".to_string()));
        }

        // Check expiration
        if current_token.is_expired() {
            return Err(OAuthError::TokenExpired(current_token.expires_at));
        }

        // Validate audience
        current_token.validate_audience(&self.config.default_audience)?;

        // Validate issuer
        current_token.validate_issuer(&self.issuer)?;

        Ok(current_token.clone())
    }

    /// Revoke a token
    pub fn revoke_token(&self, agent_id: &str) -> Result<(), OAuthError> {
        let mut agents = self.agents.write().unwrap();
        
        let agent = agents.get_mut(agent_id)
            .ok_or_else(|| OAuthError::ValidationFailed(format!("Agent not found: {}", agent_id)))?;

        agent.clear_token();
        agent.status = AgentStatus::Revoked;

        Ok(())
    }

    /// Start device code flow
    pub fn start_device_flow(&self, agent_id: &str) -> Result<DeviceAuthorizationResponse, OAuthError> {
        // Check if device authorization endpoint is configured
        if self.config.device_authorization_endpoint.is_none() {
            return Err(OAuthError::IssuanceFailed("Device flow not supported".to_string()));
        }

        let agents = self.agents.read().unwrap();
        
        let _agent = agents.get(agent_id)
            .ok_or_else(|| OAuthError::IssuanceFailed(format!("Agent not found: {}", agent_id)))?;

        // In production, this would call the device authorization endpoint
        // For now, return mock response
        Ok(DeviceAuthorizationResponse {
            device_code: format!("DC-{}", Uuid::new_v4()),
            user_code: format!("WARDEN-{}", &Uuid::new_v4().to_string()[..8].to_uppercase()),
            verification_uri: format!("{}/device", self.config.auth_server_url),
            verification_uri_complete: format!("{}/device?code={}", self.config.auth_server_url, Uuid::new_v4()),
            expires_in: 1800, // 30 minutes
            interval: 5,
        })
    }

    /// Poll for device flow completion
    pub fn poll_device_flow(&self, agent_id: &str, device_code: &str) -> Result<OAuthToken, OAuthError> {
        // In production, poll the token endpoint with the device code
        // For now, issue a token directly
        self.issue_token(agent_id, None, None)
    }

    /// List all registered agents
    pub fn list_agents(&self) -> Vec<AgentIdentity> {
        let agents = self.agents.read().unwrap();
        agents.values().cloned().collect()
    }

    /// Generate access token
    fn generate_access_token(&self, agent: &AgentIdentity) -> String {
        let mut data = format!(
            "{}/{}/{}",
            agent.agent_id,
            agent.spiffe_id,
            Utc::now().timestamp()
        );
        
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        let result = hasher.finalize();
        
        format!("at_{}", hex::encode(result))
    }

    /// Generate refresh token
    fn generate_refresh_token(&self, agent: &AgentIdentity) -> String {
        let data = format!(
            "{}/{}/refresh/{}",
            agent.agent_id,
            agent.spiffe_id,
            Uuid::new_v4()
        );
        
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        let result = hasher.finalize();
        
        format!("rt_{}", hex::encode(result))
    }
}

/// Device Authorization Response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceAuthorizationResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub verification_uri_complete: String,
    pub expires_in: i64,
    pub interval: i64,
}

/// Token Request for device flow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenRequest {
    pub grant_type: String,
    pub device_code: Option<String>,
    pub client_id: Option<String>,
    pub refresh_token: Option<String>,
}

impl TokenRequest {
    pub fn device_code_flow(device_code: &str, client_id: &str) -> Self {
        TokenRequest {
            grant_type: "urn:ietf:params:oauth:grant-type:device_code".to_string(),
            device_code: Some(device_code.to_string()),
            client_id: Some(client_id.to_string()),
            refresh_token: None,
        }
    }

    pub fn refresh_token_flow(refresh_token: &str) -> Self {
        TokenRequest {
            grant_type: "refresh_token".to_string(),
            device_code: None,
            client_id: None,
            refresh_token: Some(refresh_token.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oauth_agent_client() {
        let client = OAuthAgentClient::default_client();
        
        let spiffe_id = SpiffeId::for_agent("coordinator", "01").unwrap();
        
        let identity = client.register_agent(
            "agent-001".to_string(),
            spiffe_id,
            "coordinator",
            vec!["plan".to_string(), "execute".to_string()],
        ).unwrap();
        
        assert_eq!(identity.agent_type, "coordinator");
    }

    #[test]
    fn test_token_issuance() {
        let client = OAuthAgentClient::default_client();
        
        let spiffe_id = SpiffeId::for_agent("executor", "01").unwrap();
        
        client.register_agent(
            "agent-002".to_string(),
            spiffe_id.clone(),
            "executor",
            vec!["execute".to_string()],
        ).unwrap();
        
        let token = client.issue_token("agent-002", None, None).unwrap();
        
        assert!(token.is_valid());
        assert_eq!(token.token_type, "Bearer");
    }

    #[test]
    fn test_token_refresh() {
        let client = OAuthAgentClient::default_client();
        
        let spiffe_id = SpiffeId::for_agent("test", "01").unwrap();
        
        client.register_agent(
            "agent-003".to_string(),
            spiffe_id,
            "test",
            vec![],
        ).unwrap();
        
        // Issue initial token
        let token1 = client.issue_token("agent-003", None, None).unwrap();
        
        // Refresh token
        let token2 = client.refresh_token("agent-003").unwrap();
        
        // Tokens should be different
        assert_ne!(token1.access_token, token2.access_token);
        assert!(token2.is_valid());
    }

    #[test]
    fn test_token_validation() {
        let client = OAuthAgentClient::default_client();
        
        let spiffe_id = SpiffeId::for_agent("validator", "01").unwrap();
        
        client.register_agent(
            "agent-004".to_string(),
            spiffe_id,
            "validator",
            vec!["validate".to_string()],
        ).unwrap();
        
        let token = client.issue_token("agent-004", None, None).unwrap();
        
        // Validate correct token
        let result = client.validate_token("agent-004", &token.access_token);
        assert!(result.is_ok());
        
        // Validate incorrect token
        let result = client.validate_token("agent-004", "invalid_token");
        assert!(result.is_err());
    }

    #[test]
    fn test_device_flow() {
        let client = OAuthAgentClient::default_client();
        
        let spiffe_id = SpiffeId::for_agent("device", "01").unwrap();
        
        client.register_agent(
            "device-agent-001".to_string(),
            spiffe_id,
            "device",
            vec![],
        ).unwrap();
        
        let response = client.start_device_flow("device-agent-001").unwrap();
        
        assert!(!response.device_code.is_empty());
        assert!(!response.user_code.is_empty());
    }
}
