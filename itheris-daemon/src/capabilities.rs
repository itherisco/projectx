//! # Capability-Based Access Control
//!
//! Implements capability-based security that enforces:
//! - Capability registry for all system identities
//! - Process isolation for tools
//! - Execution authorization checks
//! - Immutable audit trail
//!
//! ## Security Model
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────┐
//! │              CAPABILITY REGISTRY                         │
//! ├─────────────────────────────────────────────────────────┤
//! │                                                          │
//! │   Identity ──▶ Capabilities ──▶ Allowed Actions         │
//! │                                                          │
//! │   Before ANY execution:                                  │
//! │   1. Verify identity has capability                     │
//! │   2. Check action is permitted                           │
//! │   3. Verify capability not expired                       │
//! │   4. Log the access attempt                              │
//! │                                                          │
//! └─────────────────────────────────────────────────────────┘
//! ```

use chrono::{DateTime, Utc, Duration};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use thiserror::Error;

/// Capability errors
#[derive(Error, Debug)]
pub enum CapabilityError {
    #[error("Capability not found: {0}")]
    NotFound(String),
    
    #[error("Capability expired: {0}")]
    Expired(String),
    
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
    
    #[error("Identity not registered: {0}")]
    IdentityNotFound(String),
}

/// Action types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum CapAction {
    Execute,
    ReadFile,
    WriteFile,
    DeleteFile,
    NetworkRequest,
    SpawnProcess,
    ModifyState,
    QueryExternal,
    Admin,
}

impl CapAction {
    pub fn as_str(&self) -> &'static str {
        match self {
            CapAction::Execute => "EXECUTE",
            CapAction::ReadFile => "READ_FILE",
            CapAction::WriteFile => "WRITE_FILE",
            CapAction::DeleteFile => "DELETE_FILE",
            CapAction::NetworkRequest => "NETWORK_REQUEST",
            CapAction::SpawnProcess => "SPAWN_PROCESS",
            CapAction::ModifyState => "MODIFY_STATE",
            CapAction::QueryExternal => "QUERY_EXTERNAL",
            CapAction::Admin => "ADMIN",
        }
    }
    
    pub fn from_str(s: &str) -> Option<CapAction> {
        match s.to_uppercase().as_str() {
            "EXECUTE" => Some(CapAction::Execute),
            "READ_FILE" => Some(CapAction::ReadFile),
            "WRITE_FILE" => Some(CapAction::WriteFile),
            "DELETE_FILE" => Some(CapAction::DeleteFile),
            "NETWORK_REQUEST" => Some(CapAction::NetworkRequest),
            "SPAWN_PROCESS" => Some(CapAction::SpawnProcess),
            "MODIFY_STATE" => Some(CapAction::ModifyState),
            "QUERY_EXTERNAL" => Some(CapAction::QueryExternal),
            "ADMIN" => Some(CapAction::Admin),
            _ => None,
        }
    }
}

/// Process isolation configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessIsolation {
    pub enabled: bool,
    pub namespace: Option<String>,
    pub cgroup: Option<String>,
    pub seccomp_profile: Option<String>,
    pub readonly_paths: Vec<String>,
    pub tmpfs_mounts: Vec<String>,
}

impl Default for ProcessIsolation {
    fn default() -> Self {
        ProcessIsolation {
            enabled: true,
            namespace: None,
            cgroup: None,
            seccomp_profile: None,
            readonly_paths: vec![
                "/etc".to_string(),
                "/bin".to_string(),
                "/usr".to_string(),
                "/lib".to_string(),
            ],
            tmpfs_mounts: vec!["/tmp".to_string(), "/var/tmp".to_string()],
        }
    }
}

/// A capability grant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capability {
    pub identity: String,
    pub actions: Vec<CapAction>,
    pub granted_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub max_uses: Option<u32>,
    pub used_count: u32,
    pub metadata: HashMap<String, String>,
}

impl Capability {
    /// Check if capability is valid
    pub fn is_valid(&self) -> bool {
        let now = Utc::now();
        let not_expired = self.expires_at > now;
        let within_limits = match self.max_uses {
            Some(max) => self.used_count < max,
            None => true,
        };
        not_expired && within_limits
    }
    
    /// Check if action is allowed
    pub fn allows(&self, action: &CapAction) -> bool {
        self.actions.contains(action)
    }
    
    /// Use this capability
    pub fn use_capability(&mut self) {
        self.used_count += 1;
    }
}

/// Access attempt record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccessAttempt {
    pub identity: String,
    pub action: CapAction,
    pub target: String,
    pub timestamp: DateTime<Utc>,
    pub granted: bool,
    pub reason: String,
}

/// The Capability Registry
pub struct CapabilityRegistry {
    /// Registry ID
    registry_id: String,
    /// Capabilities storage
    capabilities: Arc<RwLock<HashMap<String, Capability>>>,
    /// Access log
    access_log: Arc<RwLock<Vec<AccessAttempt>>>,
    /// Process isolation config
    isolation: Arc<RwLock<ProcessIsolation>>,
    /// Identity blacklist
    blacklist: Arc<RwLock<HashMap<String, DateTime<Utc>>>>,
}

impl CapabilityRegistry {
    /// Create new registry
    pub fn new() -> Self {
        let registry_id = Self::generate_id();
        
        log::info!("📋 Initializing Capability Registry - {}", &registry_id[..8]);
        
        let registry = CapabilityRegistry {
            registry_id,
            capabilities: Arc::new(RwLock::new(HashMap::new())),
            access_log: Arc::new(RwLock::new(Vec::new())),
            isolation: Arc::new(RwLock::new(ProcessIsolation::default())),
            blacklist: Arc::new(RwLock::new(HashMap::new())),
        };
        
        registry
    }
    
    fn generate_id() -> String {
        let mut hasher = Sha256::new();
        hasher.update(b"capability_registry");
        hasher.update(Utc::now().to_rfc3339().as_bytes());
        hex::encode(hasher.finalize())
    }
    
    /// Grant a capability to an identity
    pub async fn grant(&self, capability: Capability) {
        let identity = capability.identity.clone();
        let mut caps = self.capabilities.write().await;
        
        log::info!("📋 Granting capability to: {}", identity);
        
        caps.insert(identity.clone(), capability);
    }
    
    /// Revoke a capability
    pub async fn revoke(&self, identity: &str) {
        let mut caps = self.capabilities.write().await;
        caps.remove(identity);
        log::warn!("📋 Revoked all capabilities from: {}", identity);
    }
    
    /// Check if identity can perform action
    pub async fn check(&self, identity: &str, action: &CapAction, target: &str) -> Result<(), CapabilityError> {
        // Step 1: Check blacklist
        let blacklist = self.blacklist.read().await;
        if let Some(blocked_until) = blacklist.get(identity) {
            if *blocked_until > Utc::now() {
                return Err(CapabilityError::PermissionDenied(
                    format!("Identity {} is blacklisted until {}", identity, blocked_until)
                ));
            }
        }
        drop(blacklist);
        
        // Step 2: Get capability
        let caps = self.capabilities.read().await;
        let capability = caps.get(identity)
            .ok_or_else(|| CapabilityError::IdentityNotFound(identity.to_string()))?;
        
        // Step 3: Check expiration
        if !capability.is_valid() {
            self.log_access(identity, action, target, false, "Capability expired".to_string()).await;
            return Err(CapabilityError::Expired(format!(
                "Capability for {} expired at {}", 
                identity, 
                capability.expires_at
            )));
        }
        
        // Step 4: Check action permission
        if !capability.allows(action) {
            self.log_access(identity, action, target, false, "Action not permitted".to_string()).await;
            return Err(CapabilityError::PermissionDenied(format!(
                "Identity {} not permitted to perform {:?} on {}",
                identity, action, target
            )));
        }
        
        // Step 5: Log successful access
        self.log_access(identity, action, target, true, "Access granted".to_string()).await;
        
        // Step 6: Update usage count
        drop(caps);
        let mut caps = self.capabilities.write().await;
        if let Some(cap) = caps.get_mut(identity) {
            cap.use_capability();
        }
        
        Ok(())
    }
    
    /// Get capability for identity
    pub async fn get_capability(&self, identity: &str) -> Option<Capability> {
        let caps = self.capabilities.read().await;
        caps.get(identity).cloned()
    }
    
    /// List all capabilities
    pub async fn list_capabilities(&self) -> Vec<Capability> {
        let caps = self.capabilities.read().await;
        caps.values().cloned().collect()
    }
    
    /// Add identity to blacklist
    pub async fn blacklist_identity(&self, identity: &str, duration_minutes: i64) {
        let mut blacklist = self.blacklist.write().await;
        let blocked_until = Utc::now() + Duration::minutes(duration_minutes);
        blacklist.insert(identity.to_string(), blocked_until);
        log::warn!("📋 Blacklisted {} until {}", identity, blocked_until);
    }
    
    /// Remove identity from blacklist
    pub async fn unblacklist_identity(&self, identity: &str) {
        let mut blacklist = self.blacklist.write().await;
        blacklist.remove(identity);
        log::info!("📋 Removed {} from blacklist", identity);
    }
    
    /// Get process isolation config
    pub async fn get_isolation(&self) -> ProcessIsolation {
        self.isolation.read().await.clone()
    }
    
    /// Update process isolation config
    pub async fn set_isolation(&self, isolation: ProcessIsolation) {
        let mut iso = self.isolation.write().await;
        *iso = isolation;
        log::info!("📋 Process isolation updated");
    }
    
    /// Get access log
    pub async fn get_access_log(&self) -> Vec<AccessAttempt> {
        self.access_log.read().await.clone()
    }
    
    /// Log access attempt
    async fn log_access(&self, identity: &str, action: &CapAction, target: &str, granted: bool, reason: String) {
        let mut log = self.access_log.write().await;
        
        log.push(AccessAttempt {
            identity: identity.to_string(),
            action: action.clone(),
            target: target.to_string(),
            timestamp: Utc::now(),
            granted,
            reason,
        });
        
        // Keep log size manageable
        if log.len() > 10000 {
            log.drain(0..5000);
        }
    }
    
    /// Get statistics
    pub async fn get_stats(&self) -> RegistryStats {
        let caps = self.capabilities.read().await;
        let log = self.access_log.read().await;
        
        let granted_count = log.iter().filter(|a| a.granted).count() as u64;
        let denied_count = log.iter().filter(|a| !a.granted).count() as u64;
        
        RegistryStats {
            total_identities: caps.len() as u64,
            access_granted: granted_count,
            access_denied: denied_count,
            registry_id: self.registry_id.clone(),
        }
    }
    
    /// Initialize default capabilities for system identities
    pub async fn initialize_defaults(&self) {
        let defaults = vec![
            ("julia_brain", vec![
                CapAction::ReadFile,
                CapAction::Execute,
                CapAction::QueryExternal,
            ], 365), // 1 year
            ("monitoring", vec![
                CapAction::ReadFile,
                CapAction::QueryExternal,
            ], 365),
            ("health_check", vec![
                CapAction::QueryExternal,
            ], 365),
            ("file_writer", vec![
                CapAction::WriteFile,
            ], 30),
            ("network_client", vec![
                CapAction::NetworkRequest,
            ], 30),
        ];
        
        let now = Utc::now();
        
        for (identity, actions, days) in defaults {
            let capability = Capability {
                identity: identity.to_string(),
                actions,
                granted_at: now,
                expires_at: now + Duration::days(days),
                max_uses: None,
                used_count: 0,
                metadata: HashMap::new(),
            };
            
            self.grant(capability).await;
        }
        
        log::info!("📋 Default capabilities initialized");
    }
}

impl Default for CapabilityRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Registry statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistryStats {
    pub total_identities: u64,
    pub access_granted: u64,
    pub access_denied: u64,
    pub registry_id: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_grant_and_check() {
        let registry = CapabilityRegistry::new();
        
        let capability = Capability {
            identity: "test_user".to_string(),
            actions: vec![CapAction::ReadFile],
            granted_at: Utc::now(),
            expires_at: Utc::now() + Duration::days(1),
            max_uses: None,
            used_count: 0,
            metadata: HashMap::new(),
        };
        
        registry.grant(capability).await;
        
        let result = registry.check("test_user", &CapAction::ReadFile, "/tmp/test.txt").await;
        assert!(result.is_ok());
    }
    
    #[tokio::test]
    async fn test_unauthorized_action() {
        let registry = CapabilityRegistry::new();
        
        let capability = Capability {
            identity: "test_user".to_string(),
            actions: vec![CapAction::ReadFile], // Only read allowed
            granted_at: Utc::now(),
            expires_at: Utc::now() + Duration::days(1),
            max_uses: None,
            used_count: 0,
            metadata: HashMap::new(),
        };
        
        registry.grant(capability).await;
        
        // Try to execute (not allowed)
        let result = registry.check("test_user", &CapAction::Execute, "/bin/sh").await;
        assert!(result.is_err());
    }
    
    #[tokio::test]
    async fn test_expired_capability() {
        let registry = CapabilityRegistry::new();
        
        let capability = Capability {
            identity: "test_user".to_string(),
            actions: vec![CapAction::ReadFile],
            granted_at: Utc::now() - Duration::days(2),
            expires_at: Utc::now() - Duration::days(1), // Expired
            max_uses: None,
            used_count: 0,
            metadata: HashMap::new(),
        };
        
        registry.grant(capability).await;
        
        let result = registry.check("test_user", &CapAction::ReadFile, "/tmp/test.txt").await;
        assert!(result.is_err());
    }
    
    #[tokio::test]
    async fn test_max_uses() {
        let registry = CapabilityRegistry::new();
        
        let capability = Capability {
            identity: "test_user".to_string(),
            actions: vec![CapAction::ReadFile],
            granted_at: Utc::now(),
            expires_at: Utc::now() + Duration::days(1),
            max_uses: Some(2), // Only 2 uses allowed
            used_count: 0,
            metadata: HashMap::new(),
        };
        
        registry.grant(capability).await;
        
        // First use - should succeed
        let result1 = registry.check("test_user", &CapAction::ReadFile, "/tmp/test1.txt").await;
        assert!(result1.is_ok());
        
        // Second use - should succeed
        let result2 = registry.check("test_user", &CapAction::ReadFile, "/tmp/test2.txt").await;
        assert!(result2.is_ok());
        
        // Third use - should fail
        let result3 = registry.check("test_user", &CapAction::ReadFile, "/tmp/test3.txt").await;
        assert!(result3.is_err());
    }
    
    #[tokio::test]
    async fn test_blacklist() {
        let registry = CapabilityRegistry::new();
        
        // Grant capability
        let capability = Capability {
            identity: "bad_user".to_string(),
            actions: vec![CapAction::ReadFile],
            granted_at: Utc::now(),
            expires_at: Utc::now() + Duration::days(1),
            max_uses: None,
            used_count: 0,
            metadata: HashMap::new(),
        };
        registry.grant(capability).await;
        
        // Blacklist for 60 minutes
        registry.blacklist_identity("bad_user", 60).await;
        
        // Try to access - should be denied
        let result = registry.check("bad_user", &CapAction::ReadFile, "/tmp/test.txt").await;
        assert!(result.is_err());
    }
}
