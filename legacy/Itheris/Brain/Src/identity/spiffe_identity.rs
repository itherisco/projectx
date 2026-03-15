//! Agent Identity System - SPIFFE Identity Implementation
//!
//! This module provides SPIFFE-based identity management for agents in the
//! Warden mesh, following the SPIFFE standard for workload identity.
//!
//! # SPIFFE ID Format
//! `spiffe://warden-mesh/{agent-type}-{agent-number}`
//!
//! # Example
//! `spiffe://warden-mesh/coordinator-agent-01`

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;
use uuid::Uuid;

mod workload_api;
mod svid;

pub use workload_api::WorkloadApiClient;
pub use svid::{Svid, X509Svid};

/// Errors that can occur in SPIFFE identity management
#[derive(Error, Debug)]
pub enum SpiffeError {
    #[error("Invalid SPIFFE ID format: {0}")]
    InvalidSpiffeId(String),
    #[error("SVID not found: {0}")]
    SvidNotFound(String),
    #[error("SVID expired at {0}")]
    SvidExpired(DateTime<Utc>),
    #[error("SVID not yet valid (valid_from: {0})")]
    SvidNotYetValid(DateTime<Utc>),
    #[error("Trust domain mismatch: expected {expected}, got {actual}")]
    TrustDomainMismatch { expected: String, actual: String },
    #[error("Signature verification failed")]
    SignatureVerificationFailed,
    #[error("Workload API error: {0}")]
    WorkloadApiError(String),
    #[error("Certificate parsing error: {0}")]
    CertificateError(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

/// SPIFFE Trust Domain
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct TrustDomain(String);

impl TrustDomain {
    pub fn new(domain: &str) -> Result<Self, SpiffeError> {
        if domain.is_empty() {
            return Err(SpiffeError::InvalidSpiffeId("Trust domain cannot be empty".to_string()));
        }
        // Basic validation - trust domain should not contain special chars
        if domain.contains("://") || domain.contains(" ") {
            return Err(SpiffeError::InvalidSpiffeId(format!("Invalid trust domain: {}", domain)));
        }
        Ok(TrustDomain(domain.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for TrustDomain {
    fn default() -> Self {
        TrustDomain::new("warden-mesh").unwrap()
    }
}

/// SPIFFE ID - unique identifier for a workload
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct SpiffeId {
    trust_domain: TrustDomain,
    path: String,
}

impl SpiffeId {
    /// Create a new SPIFFE ID
    ///
    /// # Example
    /// ```
    /// let id = SpiffeId::new("warden-mesh", "/coordinator-agent-01").unwrap();
    /// assert_eq!(id.to_string(), "spiffe://warden-mesh/coordinator-agent-01");
    /// ```
    pub fn new(trust_domain: &str, path: &str) -> Result<Self, SpiffeError> {
        // Validate trust domain
        let td = TrustDomain::new(trust_domain)?;

        // Validate path - must start with /
        if !path.starts_with('/') {
            return Err(SpiffeError::InvalidSpiffeId(format!(
                "Path must start with /: {}",
                path
            )));
        }

        // Validate path characters
        let valid_chars = path.chars().all(|c| {
            c.is_ascii_alphanumeric() || c == '/' || c == '-' || c == '_'
        });
        if !valid_chars {
            return Err(SpiffeError::InvalidSpiffeId(format!(
                "Invalid characters in path: {}",
                path
            )));
        }

        Ok(SpiffeId {
            trust_domain: td,
            path: path.to_string(),
        })
    }

    /// Create agent SPIFFE ID with standard format
    ///
    /// # Example
    /// ```
    /// let id = SpiffeId::for_agent("coordinator", "01").unwrap();
    /// assert_eq!(id.to_string(), "spiffe://warden-mesh/coordinator-agent-01");
    /// ```
    pub fn for_agent(agent_type: &str, agent_number: &str) -> Result<Self, SpiffeError> {
        let path = format!("/{}-agent-{}", agent_type, agent_number);
        SpiffeId::new("warden-mesh", &path)
    }

    /// Parse SPIFFE ID from string
    pub fn parse(s: &str) -> Result<Self, SpiffeError> {
        let prefix = "spiffe://";
        if !s.starts_with(prefix) {
            return Err(SpiffeError::InvalidSpiffeId(format!(
                "Must start with {}: {}",
                prefix, s
            )));
        }

        let remainder = &s[prefix.len()..];
        let parts: Vec<&str> = remainder.splitn(2, '/').collect();
        if parts.len() < 2 || parts[1].is_empty() {
            return Err(SpiffeError::InvalidSpiffeId(format!(
                "Invalid SPIFFE ID format: {}",
                s
            )));
        }

        SpiffeId::new(parts[0], &format!("/{}", parts[1]))
    }

    /// Get the trust domain
    pub fn trust_domain(&self) -> &TrustDomain {
        &self.trust_domain
    }

    /// Get the path component
    pub fn path(&self) -> &str {
        &self.path
    }

    /// Get the agent type from path (e.g., "coordinator" from "/coordinator-agent-01")
    pub fn agent_type(&self) -> Option<&str> {
        let path = self.path.trim_start_matches('/');
        let parts: Vec<&str> = path.splitn(2, '-').collect();
        if parts.is_empty() {
            None
        } else {
            Some(parts[0])
        }
    }

    /// Get the agent number from path (e.g., "01" from "/coordinator-agent-01")
    pub fn agent_number(&self) -> Option<&str> {
        let path = self.path.trim_start_matches('/');
        let parts: Vec<&str> = path.splitn(3, '-').collect();
        if parts.len() >= 3 && parts[1] == "agent" {
            Some(parts[2])
        } else {
            None
        }
    }
}

impl std::fmt::Display for SpiffeId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "spiffe://{}{}", self.trust_domain.as_str(), self.path)
    }
}

/// SPIFFE Identity Document
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpiffeIdentity {
    pub spiffe_id: SpiffeId,
    pub svid: X509Svid,
    pub bundle: Vec<u8>, // X.509 trust bundle
    pub federated_bundles: HashMap<String, Vec<u8>>,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

impl SpiffeIdentity {
    /// Create a new SPIFFE identity
    pub fn new(
        spiffe_id: SpiffeId,
        svid: X509Svid,
        bundle: Vec<u8>,
        federated_bundles: HashMap<String, Vec<u8>>,
        validity_secs: i64,
    ) -> Self {
        let now = Utc::now();
        let expires = now + chrono::Duration::seconds(validity_secs);

        SpiffeIdentity {
            spiffe_id,
            svid,
            bundle,
            federated_bundles,
            created_at: now,
            expires_at: expires,
        }
    }

    /// Check if the identity is currently valid
    pub fn is_valid(&self) -> Result<(), SpiffeError> {
        let now = Utc::now();

        if now < self.created_at {
            return Err(SpiffeError::SvidNotYetValid(self.created_at));
        }

        if now > self.expires_at {
            return Err(SpiffeError::SvidExpired(self.expires_at));
        }

        Ok(())
    }

    /// Get remaining validity duration
    pub fn remaining_validity(&self) -> chrono::Duration {
        let now = Utc::now();
        if now >= self.expires_at {
            chrono::Duration::zero()
        } else {
            self.expires_at.signed_duration_since(now)
        }
    }

    /// Check if identity needs renewal (less than 5 minutes remaining)
    pub fn needs_renewal(&self) -> bool {
        self.remaining_validity() < chrono::Duration::minutes(5)
    }
}

/// Identity Provider - manages SPIFFE identities for agents
pub struct IdentityProvider {
    trust_domain: TrustDomain,
    identities: RwLock<HashMap<String, SpiffeIdentity>>,
    workload_client: Option<Arc<WorkloadApiClient>>,
}

impl IdentityProvider {
    /// Create a new identity provider
    pub fn new(trust_domain: TrustDomain) -> Self {
        IdentityProvider {
            trust_domain,
            identities: RwLock::new(HashMap::new()),
            workload_client: None,
        }
    }

    /// Create with Workload API client
    pub fn with_workload_api(trust_domain: TrustDomain, client: WorkloadApiClient) -> Self {
        IdentityProvider {
            trust_domain,
            identities: RwLock::new(HashMap::new()),
            workload_client: Some(Arc::new(client)),
        }
    }

    /// Register an identity for an agent
    pub fn register_identity(&self, identity: SpiffeIdentity) -> Result<(), SpiffeError> {
        identity.is_valid()?;

        let spiffe_id_str = identity.spiffe_id.to_string();
        let mut identities = self.identities.write().unwrap();
        identities.insert(spiffe_id_str, identity);
        Ok(())
    }

    /// Get identity by SPIFFE ID
    pub fn get_identity(&self, spiffe_id: &SpiffeId) -> Result<SpiffeIdentity, SpiffeError> {
        let identities = self.identities.read().unwrap();
        let key = spiffe_id.to_string();

        identities
            .get(&key)
            .cloned()
            .ok_or_else(|| SpiffeError::SvidNotFound(key))
    }

    /// Get identity by agent type and number
    pub fn get_agent_identity(&self, agent_type: &str, agent_number: &str) -> Result<SpiffeIdentity, SpiffeError> {
        let spiffe_id = SpiffeId::for_agent(agent_type, agent_number)?;
        self.get_identity(&spiffe_id)
    }

    /// Verify an identity
    pub fn verify_identity(&self, spiffe_id: &SpiffeId) -> Result<SpiffeIdentity, SpiffeError> {
        // Check trust domain matches
        if spiffe_id.trust_domain() != &self.trust_domain {
            return Err(SpiffeError::TrustDomainMismatch {
                expected: self.trust_domain.as_str().to_string(),
                actual: spiffe_id.trust_domain().as_str().to_string(),
            });
        }

        // Get and validate identity
        let identity = self.get_identity(spiffe_id)?;
        identity.is_valid()?;

        Ok(identity)
    }

    /// Revoke an identity
    pub fn revoke_identity(&self, spiffe_id: &SpiffeId) -> Result<(), SpiffeError> {
        let mut identities = self.identities.write().unwrap();
        let key = spiffe_id.to_string();

        if identities.remove(&key).is_none() {
            return Err(SpiffeError::SvidNotFound(key));
        }

        Ok(())
    }

    /// List all registered identities
    pub fn list_identities(&self) -> Vec<SpiffeIdentity> {
        let identities = self.identities.read().unwrap();
        identities.values().cloned().collect()
    }

    /// Fetch identity from Workload API (if configured)
    pub async fn fetch_from_workload_api(&self, spiffe_id: &SpiffeId) -> Result<SpiffeIdentity, SpiffeError> {
        let client = self.workload_client.as_ref()
            .ok_or_else(|| SpiffeError::WorkloadApiError("No Workload API client configured".to_string()))?;

        client.fetch_svid(spiffe_id).await
    }
}

impl Default for IdentityProvider {
    fn default() -> Self {
        IdentityProvider::new(TrustDomain::default())
    }
}

/// Identity verification result
#[derive(Debug, Serialize, Deserialize)]
pub struct VerificationResult {
    pub valid: bool,
    pub spiffe_id: String,
    pub trust_domain: String,
    pub expires_at: DateTime<Utc>,
    pub errors: Vec<String>,
}

impl VerificationResult {
    pub fn success(identity: &SpiffeIdentity) -> Self {
        VerificationResult {
            valid: true,
            spiffe_id: identity.spiffe_id.to_string(),
            trust_domain: identity.spiffe_id.trust_domain().as_str().to_string(),
            expires_at: identity.expires_at,
            errors: vec![],
        }
    }

    pub fn failure(spiffe_id: &str, errors: Vec<String>) -> Self {
        VerificationResult {
            valid: false,
            spiffe_id: spiffe_id.to_string(),
            trust_domain: String::new(),
            expires_at: Utc::now(),
            errors,
        }
    }
}

/// Identity verifier - verifies incoming identity claims
pub struct IdentityVerifier {
    trust_domain: TrustDomain,
    provider: Arc<IdentityProvider>,
}

impl IdentityVerifier {
    pub fn new(trust_domain: TrustDomain, provider: Arc<IdentityProvider>) -> Self {
        IdentityVerifier {
            trust_domain,
            provider,
        }
    }

    /// Verify a SPIFFE ID and return verification result
    pub fn verify(&self, spiffe_id_str: &str) -> VerificationResult {
        // Parse SPIFFE ID
        let spiffe_id = match SpiffeId::parse(spiffe_id_str) {
            Ok(id) => id,
            Err(e) => {
                return VerificationResult::failure(
                    spiffe_id_str,
                    vec![format!("Invalid SPIFFE ID: {}", e)],
                );
            }
        };

        // Verify trust domain
        if spiffe_id.trust_domain() != &self.trust_domain {
            return VerificationResult::failure(
                spiffe_id_str,
                vec![format!(
                    "Trust domain mismatch: expected {}, got {}",
                    self.trust_domain.as_str(),
                    spiffe_id.trust_domain().as_str()
                )],
            );
        }

        // Get and verify identity
        match self.provider.get_identity(&spiffe_id) {
            Ok(identity) => {
                match identity.is_valid() {
                    Ok(()) => VerificationResult::success(&identity),
                    Err(e) => VerificationResult::failure(
                        spiffe_id_str,
                        vec![format!("Identity validation failed: {}", e)],
                    ),
                }
            }
            Err(e) => VerificationResult::failure(
                spiffe_id_str,
                vec![format!("Identity not found: {}", e)],
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spiffe_id_format() {
        let id = SpiffeId::for_agent("coordinator", "01").unwrap();
        assert_eq!(id.to_string(), "spiffe://warden-mesh/coordinator-agent-01");
    }

    #[test]
    fn test_spiffe_id_parse() {
        let parsed = SpiffeId::parse("spiffe://warden-mesh/coordinator-agent-01").unwrap();
        assert_eq!(parsed.agent_type(), Some("coordinator"));
        assert_eq!(parsed.agent_number(), Some("01"));
    }

    #[test]
    fn test_trust_domain_validation() {
        assert!(TrustDomain::new("").is_err());
        assert!(TrustDomain::new("valid-domain").is_ok());
    }

    #[test]
    fn test_identity_provider() {
        let provider = IdentityProvider::default();
        
        // Create a mock SVID
        let spiffe_id = SpiffeId::for_agent("test", "01").unwrap();
        let svid = X509Svid::new(
            vec![0u8; 64], // mock certificate
            vec![0u8; 32], // mock private key
        );
        
        let identity = SpiffeIdentity::new(
            spiffe_id.clone(),
            svid,
            vec![],
            HashMap::new(),
            3600,
        );
        
        provider.register_identity(identity).unwrap();
        
        let retrieved = provider.get_agent_identity("test", "01").unwrap();
        assert_eq!(retrieved.spiffe_id, spiffe_id);
    }

    #[test]
    fn test_identity_expiry() {
        let spiffe_id = SpiffeId::for_agent("test", "01").unwrap();
        let svid = X509Svid::new(
            vec![0u8; 64],
            vec![0u8; 32],
        );
        
        // Create expired identity (validity of -1 second)
        let identity = SpiffeIdentity::new(
            spiffe_id.clone(),
            svid,
            vec![],
            HashMap::new(),
            -1,
        );
        
        assert!(identity.is_valid().is_err());
    }

    #[test]
    fn test_identity_verifier() {
        let provider = Arc::new(IdentityProvider::default());
        
        let spiffe_id = SpiffeId::for_agent("test", "01").unwrap();
        let svid = X509Svid::new(
            vec![0u8; 64],
            vec![0u8; 32],
        );
        
        let identity = SpiffeIdentity::new(
            spiffe_id.clone(),
            svid,
            vec![],
            HashMap::new(),
            3600,
        );
        
        provider.register_identity(identity).unwrap();
        
        let verifier = IdentityVerifier::new(TrustDomain::default(), provider);
        
        let result = verifier.verify("spiffe://warden-mesh/test-agent-01");
        assert!(result.valid);
        
        let invalid_result = verifier.verify("spiffe://other-domain/test-agent-01");
        assert!(!invalid_result.valid);
    }
}
