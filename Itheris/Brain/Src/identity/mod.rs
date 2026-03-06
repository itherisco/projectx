//! Agent Identity System
//!
//! This module provides comprehensive identity management for agents in the
//! Warden mesh system, implementing SPIFFE, OAuth 2.1, and mTLS identity.
//!
//! # Architecture
//!
//! The identity system is composed of three main components:
//!
//! 1. **SPIFFE Identity** ([`spiffe_identity`]) - SPIFFE-based workload identity
//!    - SPIFFE ID format: `spiffe://warden-mesh/{agent-type}-{agent-number}`
//!    - X.509 SVID management
//!    - Workload API integration
//!    - Identity verification
//!
//! 2. **OAuth 2.1 Agent Client** ([`oauth_agent_client`]) - OAuth-based authentication
//!    - Short-lived token issuance (RFC 9396)
//!    - Audience binding
//!    - Token refresh and rotation
//!    - Device code flow support
//!
//! 3. **Token Rotation** ([`token_rotation`]) - Automatic token management
//!    - Secure token storage
//!    - Automatic token refresh
//!    - Identity chaining between agents
//!    - Token validation and verification
//!
//! # Example
//!
//! ```rust
//! use itheris::identity::{
//!     spiffe_identity::{SpiffeId, IdentityProvider, TrustDomain},
//!     oauth_agent_client::{OAuthAgentClient, OAuthClientConfig},
//!     token_rotation::{TokenRotationManager, TokenRotationConfig},
//! };
//! use std::sync::Arc;
//!
//! // Create SPIFFE identity provider
//! let trust_domain = TrustDomain::new("warden-mesh").unwrap();
//! let identity_provider = Arc::new(IdentityProvider::new(trust_domain));
//!
//! // Create OAuth client
//! let oauth_config = OAuthClientConfig::default();
//! let oauth_client = Arc::new(OAuthAgentClient::new(oauth_config));
//!
//! // Register agent with OAuth
//! let spiffe_id = SpiffeId::for_agent("coordinator", "01").unwrap();
//! oauth_client.register_agent(
//!     "coordinator-01".to_string(),
//!     spiffe_id,
//!     "coordinator",
//!     vec!["plan".to_string(), "execute".to_string()],
//! ).unwrap();
//!
//! // Issue token
//! let token = oauth_client.issue_token("coordinator-01", None, None).unwrap();
//! println!("Token issued: {}", token.access_token);
//! ```

// Re-export all public types
pub mod spiffe_identity;
pub mod oauth_agent_client;
pub mod token_rotation;

// Re-exports from submodules
pub use spiffe_identity::{
    IdentityProvider, IdentityVerifier, SpiffeError, SpiffeId, SpiffeIdentity,
    TrustDomain, VerificationResult, WorkloadApiClient,
};

pub use oauth_agent_client::{
    AgentIdentity, AgentStatus, DeviceAuthorizationResponse, OAuthAgentClient,
    OAuthClientConfig, OAuthError, OAuthToken, TokenRequest, TokenType,
};

pub use token_rotation::{
    ChainType, IdentityChainEntry, SecureTokenStorage, TokenRotationConfig,
    TokenRotationError, TokenRotationManager, TokenStatus, TokenValidator,
    ValidationResult,
};

// Re-export SVID types
pub use spiffe_identity::svid::{Svid, X509Bundle, X509Certificate, X509Svid};

/// Identity system version
pub const IDENTITY_VERSION: &str = "1.0.0";

/// Default trust domain
pub const DEFAULT_TRUST_DOMAIN: &str = "warden-mesh";

/// Agent ID prefix
pub const AGENT_ID_PREFIX: &str = "agent";

/// Create a standard agent SPIFFE ID
///
/// # Example
/// ```
/// let id = create_agent_spiffe_id("coordinator", "01");
/// assert_eq!(id, "spiffe://warden-mesh/coordinator-agent-01");
/// ```
pub fn create_agent_spiffe_id(agent_type: &str, agent_number: &str) -> String {
    format!("spiffe://{}/{}-agent-{}", DEFAULT_TRUST_DOMAIN, agent_type, agent_number)
}

/// Validate agent ID format
pub fn validate_agent_id(agent_id: &str) -> bool {
    // Agent ID should match pattern: agent-type-number
    // e.g., "coordinator-01", "executor-02"
    let parts: Vec<&str> = agent_id.split('-').collect();
    if parts.len() != 2 {
        return false;
    }
    
    // First part should be alphabetic
    if !parts[0].chars().all(|c| c.is_ascii_alphabetic()) {
        return false;
    }
    
    // Second part should be numeric
    if !parts[1].chars().all(|c| c.is_ascii_digit()) {
        return false;
    }
    
    true
}

/// Build complete identity manager
pub mod manager {
    use super::*;
    use std::sync::Arc;
    
    /// Identity Manager - combines all identity components
    pub struct IdentityManager {
        pub identity_provider: Arc<IdentityProvider>,
        pub oauth_client: Arc<OAuthAgentClient>,
        pub rotation_manager: Arc<RwLock<Option<TokenRotationManager>>>,
    }
    
    impl IdentityManager {
        /// Create a new identity manager
        pub fn new() -> Self {
            let trust_domain = TrustDomain::new(DEFAULT_TRUST_DOMAIN).unwrap();
            let identity_provider = Arc::new(IdentityProvider::new(trust_domain));
            let oauth_client = Arc::new(OAuthAgentClient::default_client());
            
            IdentityManager {
                identity_provider,
                oauth_client,
                rotation_manager: Arc::new(RwLock::new(None)),
            }
        }
        
        /// Start automatic token rotation
        pub async fn start_rotation(&self) {
            let config = TokenRotationConfig::default();
            let mut manager = TokenRotationManager::new(config, self.oauth_client.clone());
            manager.start_rotation().await;
            
            let mut rotation = self.rotation_manager.write().unwrap();
            *rotation = Some(manager);
        }
        
        /// Stop automatic token rotation
        pub async fn stop_rotation(&self) {
            let rotation = self.rotation_manager.read().unwrap();
            if let Some(manager) = rotation.as_ref() {
                manager.stop_rotation().await;
            }
        }
    }
    
    impl Default for IdentityManager {
        fn default() -> Self {
            Self::new()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_create_agent_spiffe_id() {
        let id = create_agent_spiffe_id("coordinator", "01");
        assert_eq!(id, "spiffe://warden-mesh/coordinator-agent-01");
        
        let id = create_agent_spiffe_id("executor", "42");
        assert_eq!(id, "spiffe://warden-mesh/executor-agent-42");
    }
    
    #[test]
    fn test_validate_agent_id() {
        assert!(validate_agent_id("coordinator-01"));
        assert!(validate_agent_id("executor-99"));
        assert!(validate_agent_id("validator-001"));
        
        assert!(!validate_agent_id("coordinator"));
        assert!(!validate_agent_id("01"));
        assert!(!validate_agent_id("coordinator-01-extra"));
        assert!(!validate_agent_id("coordinator-abc"));
    }
    
    #[test]
    fn test_identity_manager_creation() {
        let manager = manager::IdentityManager::new();
        assert!(manager.oauth_client.get_agent("nonexistent").is_none());
    }
}
