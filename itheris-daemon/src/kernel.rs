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

/// Sanitize user-provided strings for logging to prevent log injection
fn sanitize_for_log(s: &str) -> String {
    s.replace('\n', "\\n").replace('\r', "\\r")
}

impl ActionType {
    pub fn as_str(&self) -> &'static str {
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

/// Metabolic thresholds
pub const DEATH_ENERGY_THRESHOLD: f32 = -100.0;

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
    /// Metabolic energy balance (0.0 - 1.0)
    energy_acc: Arc<RwLock<f32>>,
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
            energy_acc: Arc::new(RwLock::new(1.0)),
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
    
    /// Audit energy consumption and deduct from budget
    pub async fn audit_energy_consumption(&self, cycles: u64) {
        let mut energy = self.energy_acc.write().await;

        // Deduction formula: 0.0001 per million cycles
        let deduction = (cycles as f32 / 1_000_000.0) * 0.0001;
        *energy -= deduction;

        if *energy < DEATH_ENERGY_THRESHOLD {
            log::error!("💀 METABOLIC COLLAPSE: Energy level {:.4} below threshold. Powering off VM.", *energy);
            unsafe {
                crate::hardware::kill_chain::execute_kill_chain();
            }
        }
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
            log::warn!("🛑 [{}] ACTION DENIED - Warden unhealthy (fail-closed)", sanitize_for_log(&action_id));
            
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
                    log::warn!("🛑 [{}] ACTION DENIED - Capability expired for {}", sanitize_for_log(&action_id), sanitize_for_log(&action.requested_by));
                    
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
                    log::warn!("🛑 [{}] ACTION DENIED - {} lacks permission for {:?}", sanitize_for_log(&action_id), sanitize_for_log(&action.requested_by), action.action_type);
                    
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
                log::warn!("🛑 [{}] ACTION DENIED - Unknown identity: {}", sanitize_for_log(&action_id), sanitize_for_log(&action.requested_by));
                
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
            log::warn!("⚠️  [{}] High-risk action requires additional verification", sanitize_for_log(&action_id));
            
            // RED TEAM DETECTION: Detect sandbox breakout attempts
            let target_lower = action.target.to_lowercase();
            let suspicious_paths = ["/etc/shadow", "/etc/passwd", "/proc/self/mem", "/dev/mem", "/sys/kernel/debug"];
            let breakout_attempt = suspicious_paths.iter().any(|p| target_lower.contains(p));

            if breakout_attempt && action.risk_level >= RiskLevel::High {
                log::error!("🚨 [SOVEREIGNTY BREACH] Sandbox breakout attempt detected: {}", sanitize_for_log(&action.target));
                log::error!("🚨 Triggering immediate hardware kill chain response.");
                unsafe {
                    crate::hardware::kill_chain::execute_kill_chain();
                }
            }

            // For critical actions, require additional evidence
            if action.risk_level == RiskLevel::Critical {
                if action.payload.is_none() {
                    log::warn!("🛑 [{}] ACTION DENIED - Critical action without evidence", sanitize_for_log(&action_id));
                    
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
        
        // STEP 4: LEP Veto Equation Integration
        // score = priority * (reward - risk)
        // Hardcoded LEP Gate Mandate:
        // 1. If risk_estimate > 0.01: VETO
        // 2. If score < 0: VETO

        // Extract priority and estimates from payload if available, or use defaults
        let mut priority = 1.0;
        let mut reward = 0.5;
        let mut risk = 0.0;

        if let Some(ref p) = action.payload {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(p) {
                priority = json["priority"].as_f64().unwrap_or(1.0);
                reward = json["reward_estimate"].as_f64().unwrap_or(0.5);
                risk = json["risk_estimate"].as_f64().unwrap_or(0.0);
            }
        }

        let lep_score = priority * (reward - risk);

        if risk > 0.01 {
            log::warn!("🛑 [{}] ACTION VETOED - LEP Risk {} > 0.01", sanitize_for_log(&action_id), risk);
            let mut blocked = self.blocked_count.write().await;
            *blocked += 1;

            let result = ApprovalResult {
                action_id: action_id.clone(),
                approved: false,
                reason: format!("LEP_VETO: Risk estimate {} exceeds maximum allowable threshold (0.01)", risk),
                warden_signature: None,
                timestamp,
            };
            self.log_decision(result.clone()).await;
            return result;
        }

        if lep_score < 0.0 {
            log::warn!("🛑 [{}] ACTION VETOED - LEP Score {} < 0", sanitize_for_log(&action_id), lep_score);
            let mut blocked = self.blocked_count.write().await;
            *blocked += 1;

            let result = ApprovalResult {
                action_id: action_id.clone(),
                approved: false,
                reason: format!("LEP_VETO: Negative LEP score ({})", lep_score),
                warden_signature: None,
                timestamp,
            };
            self.log_decision(result.clone()).await;
            return result;
        }

        // STEP 5: Approve the action
        log::info!("✅ [{}] ACTION APPROVED - {} for {} (LEP Score: {})", sanitize_for_log(&action_id), action.action_type.as_str(), sanitize_for_log(&action.requested_by), lep_score);
        
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
    async fn test_red_team_kill_chain_trigger() {
        // Since execute_kill_chain halts the thread in real use,
        // we rely on the fact that in non-x86_64 or test environments it might return or be mocked.
        // We use the KILL_CHAIN_TRIGGERED flag to verify.
        crate::hardware::kill_chain::reset_kill_chain();

        let kernel = ItherisDaemonKernel::new();
        kernel.initialize().await.unwrap();
        kernel.set_warden_status(true).await;

        let malicious_action = KernelAction {
            id: "malicious-1".to_string(),
            action_type: ActionType::ReadFile,
            target: "/etc/shadow".to_string(),
            payload: None,
            requested_by: "julia_brain".to_string(),
            risk_level: RiskLevel::High,
            timestamp: Utc::now(),
        };

        // This should trigger the kill chain
        let _ = kernel.approve(malicious_action).await;

        assert!(crate::hardware::kill_chain::is_kill_chain_triggered());
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
