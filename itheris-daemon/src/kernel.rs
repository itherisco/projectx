//! # ITHERIS Fail-Closed Kernel
//!
//! Implements the sovereign runtime kernel with fail-closed security model.
//! If Rust Warden fails: ALL outputs blocked.
//! Default-deny security model.

use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use thiserror::Error;

/// Kernel errors
#[derive(Error, Debug)]
pub enum KernelError {
    #[error("Warden validation failed: {0}")]
    WardenFailed(String),
    
    #[error("Action denied: {0}")]
    ActionDenied(String),
    
    #[error("Capability not found: {0}")]
    CapabilityNotFound(String),
    
    #[error("Kernel subsystem error: {0}")]
    SubsystemError(String),
}

/// Action types that can be approved or denied
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ActionType {
    /// Execute a shell command
    Execute,
    /// Write to filesystem
    WriteFile,
    /// Read from filesystem  
    ReadFile,
    /// Network request
    NetworkRequest,
    /// Create subprocess
    SpawnProcess,
    /// Modify state
    ModifyState,
    /// Query external service
    QueryExternal,
}

impl ActionType {
    pub_str(&self) -> &'static str {
        match self {
            ActionType::Execute => "EXECUTE",
            ActionType::WriteFile => "WRITE_FILE",
            ActionType::ReadFile => "READ_FILE",
            ActionType::NetworkRequest => "NETWORK_REQUEST",
            ActionType::SpawnProcess => "SPAWN_PROCESS",
            ActionType::ModifyState => "MODIFY_STATE",
            ActionType::QueryExternal => "QUERY_EXTERNAL",
        }
    }
}

/// Risk level for an action
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum RiskLevel {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3,
}

/// An action to be approved by the kernel
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelAction {
    pub id: String,
    pub action_type: ActionType,
    pub target: String,
    pub payload: Option<String>,
    pub requested_by: String,
    pub risk_level: RiskLevel,
    pub timestamp: DateTime<Utc>,
}

/// Result of kernel approval
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalResult {
    pub action_id: String,
    pub approved: bool,
    pub reason: String,
    pub warden_signature: Option<String>,
    pub timestamp: DateTime<Utc>,
}

/// Capability grant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Capability {
    pub identity: String,
    pub actions: Vec<ActionType>,
    pub expires_at: DateTime<Utc>,
    pub max_uses: Option<u32>,
    pub used_count: u32,
}

/// The ITHERIS Fail-Closed Kernel
pub struct ItherisDaemonKernel {
    /// Capabilities registry
    capabilities: Arc<RwLock<HashMap<String, Capability>>>,
    /// Decision log (immutable append)
    decision_log: Arc<RwLock<Vec<ApprovalResult>>>,
    /// Warden status (if false, ALL outputs blocked)
    warden_healthy: Arc<RwLock<bool>>,
    /// Blocked actions count
    blocked_count: Arc<RwLock<u64>>,
    /// Approved actions count
    approved_count: Arc<RwLock<u64>>,
}

impl ItherisDaemonKernel {
    /// Create new kernel
    pub fn new() -> Self {
        log::info!("🛡️  Initializing ITHERIS Fail-Closed Kernel...");
        
        ItherisDaemonKernel {
            capabilities: Arc::new(RwLock::new(HashMap::new())),
            decision_log: Arc::new(RwLock::new(Vec::new())),
            warden_healthy: Arc::new(RwLock::new(false)), // Start with warden unhealthy
            blocked_count: Arc::new(RwLock::new(0)),
            approved_count: Arc::new(RwLock::new(0)),
        }
    }
    
    /// Initialize kernel with default capabilities
    pub async fn initialize(&self) -> Result<(), KernelError> {
        log::info!("📋 Initializing kernel capabilities...");
        
        // Grant default capabilities for system identities
        let default_caps = vec![
            ("julia_brain", vec![
                ActionType::ReadFile,
                ActionType::Execute,
                ActionType::QueryExternal,
            ]),
            ("monitoring", vec![
                ActionType::ReadFile,
                ActionType::QueryExternal,
            ]),
            ("health_check", vec![
                ActionType::QueryExternal,
            ]),
        ];
        
        let mut caps = self.capabilities.write().await;
        for (identity, actions) in default_caps {
            caps.insert(identity.to_string(), Capability {
                identity: identity.to_string(),
                actions,
                expires_at: Utc::now() + chrono::Duration::days(365),
                max_uses: None,
                used_count: 0,
            });
        }
        
        log::info!("   ✓ Default capabilities initialized");
        Ok(())
    }
    
    /// Set warden health status
    pub async fn set_warden_status(&self, healthy: bool) {
        let mut status = self.warden_healthy.write().await;
        *status = healthy;
        
        if healthy {
            log::info!("✅ Warden: HEALTHY - Kernel accepting actions");
        } else {
            log::warn!("⚠️  Warden: FAILED - Kernel entering fail-closed mode");
        }
    }
    
    /// Get warden status
    pub async fn is_warden_healthy(&self) -> bool {
        *self.warden_healthy.read().await
    }
    
    /// Grant capability to identity
    pub async fn grant_capability(&self, identity: &str, actions: Vec<ActionType>, expires_at: DateTime<Utc>) {
        let mut caps = self.capabilities.write().await;
        caps.insert(identity.to_string(), Capability {
            identity: identity.to_string(),
            actions,
            expires_at,
            max_uses: None,
            used_count: 0,
        });
        log::info!("   ✓ Granted capability to {}", identity);
    }
    
    /// Revoke capability
    pub async fn revoke_capability(&self, identity: &str) {
        let mut caps = self.capabilities.write().await;
        caps.remove(identity);
        log::warn!("   ⚠️  Revoked capability from {}", identity);
    }
    
    /// THE CORE FUNCTION: Approve or deny an action
    /// 
    /// This implements fail-closed security:
    /// - If Warden is unhealthy: ALL actions denied
    /// - If identity lacks capability: action denied
    /// - If action expired: action denied
    pub async fn approve(&self, action: KernelAction) -> ApprovalResult {
        let action_id = action.id.clone();
        let timestamp = Utc::now();
        
        // STEP 1: Check Warden status (FAIL-ClOSED)
        // If Warden fails, we deny EVERYTHING
        let warden_healthy = self.is_warden_healthy().await;
        
        if !warden_healthy {
            log::warn!("🛑 [{}] ACTION DENIED - Warden unhealthy (fail-closed)", action_id);
            
            let mut blocked = self.blocked_count.write().await;
            *blocked += 1;
            
            let result = ApprovalResult {
                action_id: action_id.clone(),
                approved: false,
                reason: "WARDEN_FAILED: All outputs blocked due to security subsystem failure".to_string(),
                warden_signature: None,
                timestamp,
            };
            
            self.log_decision(result.clone()).await;
            return result;
        }
        
        // STEP 2: Check capability exists
        let caps = self.capabilities.read().await;
        let capability = caps.get(&action.requested_by);
        
        match capability {
            Some(cap) => {
                // Check expiration
                if cap.expires_at < timestamp {
                    log::warn!("🛑 [{}] ACTION DENIED - Capability expired for {}", action_id, action.requested_by);
                    
                    let mut blocked = self.blocked_count.write().await;
                    *blocked += 1;
                    
                    let result = ApprovalResult {
                        action_id: action_id.clone(),
                        approved: false,
                        reason: format!("CAPABILITY_EXPIRED: {} capability expired at {}", action.requested_by, cap.expires_at),
                        warden_signature: None,
                        timestamp,
                    };
                    
                    drop(caps);
                    self.log_decision(result.clone()).await;
                    return result;
                }
                
                // Check action is permitted
                if !cap.actions.contains(&action.action_type) {
                    log::warn!("🛑 [{}] ACTION DENIED - {} lacks permission for {:?}", action_id, action.requested_by, action.action_type);
                    
                    let mut blocked = self.blocked_count.write().await;
                    *blocked += 1;
                    
                    let result = ApprovalResult {
                        action_id: action_id.clone(),
                        approved: false,
                        reason: format!("PERMISSION_DENIED: {} not authorized for {:?}", action.requested_by, action.action_type),
                        warden_signature: None,
                        timestamp,
                    };
                    
                    drop(caps);
                    self.log_decision(result.clone()).await;
                    return result;
                }
            },
            None => {
                log::warn!("🛑 [{}] ACTION DENIED - Unknown identity: {}", action_id, action.requested_by);
                
                let mut blocked = self.blocked_count.write().await;
                *blocked += 1;
                
                let result = ApprovalResult {
                    action_id: action_id.clone(),
                    approved: false,
                    reason: format!("IDENTITY_UNKNOWN: {} not registered", action.requested_by),
                    warden_signature: None,
                    timestamp,
                };
                
                drop(caps);
                self.log_decision(result.clone()).await;
                return result;
            }
        }
        
        // STEP 3: Risk-based additional validation
        if action.risk_level >= RiskLevel::High {
            log::warn!("⚠️  [{}] High-risk action requires additional verification", action_id);
            
            // For critical actions, require additional evidence
            if action.risk_level == RiskLevel::Critical {
                if action.payload.is_none() {
                    log::warn!("🛑 [{}] ACTION DENIED - Critical action without evidence", action_id);
                    
                    let mut blocked = self.blocked_count.write().await;
                    *blocked += 1;
                    
                    let result = ApprovalResult {
                        action_id: action_id.clone(),
                        approved: false,
                        reason: "EVIDENCE_REQUIRED: Critical action requires cryptographic evidence".to_string(),
                        warden_signature: None,
                        timestamp,
                    };
                    
                    self.log_decision(result.clone()).await;
                    return result;
                }
            }
        }
        
        // STEP 4: Approve the action
        log::info!("✅ [{}] ACTION APPROVED - {} for {}", action_id, action.action_type.as_str(), action.requested_by);
        
        let mut approved = self.approved_count.write().await;
        *approved += 1;
        
        // Generate warden signature (simulated)
        let mut hasher = Sha256::new();
        hasher.update(action_id.as_bytes());
        hasher.update(action.requested_by.as_bytes());
        hasher.update(timestamp.to_rfc3339().as_bytes());
        let signature = hex::encode(hasher.finalize());
        
        let result = ApprovalResult {
            action_id: action_id.clone(),
            approved: true,
            reason: "APPROVED".to_string(),
            warden_signature: Some(signature),
            timestamp,
        };
        
        self.log_decision(result.clone()).await;
        result
    }
    
    /// Log decision (immutable append)
    async fn log_decision(&self, result: ApprovalResult) {
        let mut log = self.decision_log.write().await;
        log.push(result);
    }
    
    /// Get decision log
    pub async fn get_decision_log(&self) -> Vec<ApprovalResult> {
        self.decision_log.read().await.clone()
    }
    
    /// Get kernel statistics
    pub async fn get_stats(&self) -> KernelStats {
        KernelStats {
            approved: *self.approved_count.read().await,
            blocked: *self.blocked_count.read().await,
            warden_healthy: *self.warden_healthy.read().await,
            capabilities_count: self.capabilities.read().await.len() as u64,
        }
    }
}

impl Default for ItherisDaemonKernel {
    fn default() -> Self {
        Self::new()
    }
}

/// Kernel statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelStats {
    pub approved: u64,
    pub blocked: u64,
    pub warden_healthy: bool,
    pub capabilities_count: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_fail_closed_when_warden_down() {
        let kernel = ItherisDaemonKernel::new();
        
        // Warden starts unhealthy
        let action = KernelAction {
            id: "test-1".to_string(),
            action_type: ActionType::Execute,
            target: "test".to_string(),
            payload: None,
            requested_by: "test".to_string(),
            risk_level: RiskLevel::Low,
            timestamp: Utc::now(),
        };
        
        let result = kernel.approve(action).await;
        assert!(!result.approved);
        assert!(result.reason.contains("WARDEN_FAILED"));
    }
    
    #[tokio::test]
    async fn test_approve_when_warden_healthy() {
        let kernel = ItherisDaemonKernel::new();
        kernel.initialize().await.unwrap();
        
        // Set warden healthy
        kernel.set_warden_status(true).await;
        
        let action = KernelAction {
            id: "test-2".to_string(),
            action_type: ActionType::Execute,
            target: "test".to_string(),
            payload: None,
            requested_by: "julia_brain".to_string(),
            risk_level: RiskLevel::Low,
            timestamp: Utc::now(),
        };
        
        let result = kernel.approve(action).await;
        assert!(result.approved);
    }
    
    #[tokio::test]
    async fn test_deny_unknown_identity() {
        let kernel = ItherisDaemonKernel::new();
        kernel.initialize().await.unwrap();
        kernel.set_warden_status(true).await;
        
        let action = KernelAction {
            id: "test-3".to_string(),
            action_type: ActionType::Execute,
            target: "test".to_string(),
            payload: None,
            requested_by: "unknown_identity".to_string(),
            risk_level: RiskLevel::Low,
            timestamp: Utc::now(),
        };
        
        let result = kernel.approve(action).await;
        assert!(!result.approved);
        assert!(result.reason.contains("IDENTITY_UNKNOWN"));
    }
}
