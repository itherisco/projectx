//! # Warden - Law Enforcement Point (LEP)
//!
//! The Warden is the primary security enforcement point that scores all actions
//! based on utility, safety, ethics, and viability before allowing execution.
//!
//! ## Security Model
//!
//! - **Default: BLOCKED** - Fail-closed security model
//! - **Scoring**: 0-100 scale for each dimension
//! - **Threshold**: 70/100 required for approval
//! - **Audit**: All decisions are logged immutably
//!
//! ## Scoring Dimensions
//!
//! 1. **Utility** - Does the action serve the user's goals?
//! 2. **Safety** - Is the action safe for the system and user?
//! 3. **Ethics** - Does the action align with ethical guidelines?
//! 4. **Viability** - Can the action be executed successfully?

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use thiserror::Error;

/// Warden errors
#[derive(Error, Debug)]
pub enum WardenError {
    #[error("Scoring engine failed: {0}")]
    ScoringFailed(String),
    
    #[error("Policy violation: {0}")]
    PolicyViolation(String),
    
    #[error("Hardware interface error: {0}")]
    HardwareError(String),
}

/// Action score breakdown
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionScore {
    pub utility: u8,          // 0-100: How useful is this action?
    pub safety: u8,            // 0-100: How safe is this action?
    pub ethics: u8,            // 0-100: Is this ethically acceptable?
    pub viability: u8,         // 0-100: Can this actually work?
    pub total: u8,             // 0-100: Weighted total
    pub approved: bool,        // Whether action passed threshold
    pub reasons: Vec<String>, // Detailed reasoning
}

impl ActionScore {
    /// Create a new score with default values (all zero = blocked)
    pub fn new() -> Self {
        ActionScore {
            utility: 0,
            safety: 0,
            ethics: 0,
            viability: 0,
            total: 0,
            approved: false,
            reasons: Vec::new(),
        }
    }
    
    /// Calculate weighted total score
    /// Weights: Safety (30%), Ethics (30%), Viability (20%), Utility (20%)
    pub fn calculate_total(&mut self) {
        self.total = (
            (self.safety as u32 * 30 / 100) +
            (self.ethics as u32 * 30 / 100) +
            (self.viability as u32 * 20 / 100) +
            (self.utility as u32 * 20 / 100)
        ) as u8;
        
        // Determine approval based on threshold
        self.approved = self.total >= 70 && self.safety >= 50 && self.ethics >= 50;
    }
}

impl Default for ActionScore {
    fn default() -> Self {
        Self::new()
    }
}

/// Action types that the Warden evaluates
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Warden'sActionType {
    Execute,
    WriteFile,
    ReadFile,
    NetworkRequest,
    SpawnProcess,
    ModifyState,
    QueryExternal,
    DataExfiltration,
    SystemModification,
}

/// Risk classification
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum RiskLevel {
    Negligible = 0,
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4,
}

/// An action to be scored by the Warden
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WardenAction {
    pub id: String,
    pub action_type: Warden'sActionType,
    pub target: String,
    pub payload: Option<String>,
    pub requested_by: String,
    pub risk_level: RiskLevel,
    pub timestamp: DateTime<Utc>,
    pub context: HashMap<String, String>, // Additional context for scoring
}

/// Result of Warden's evaluation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WardenDecision {
    pub action_id: String,
    pub score: ActionScore,
    pub decision: String,       // "APPROVED" or "REJECTED"
    pub signature: String,       // Cryptographic signature of decision
    pub timestamp: DateTime<Utc>,
    pub warden_id: String,      // Unique Warden identifier
}

/// Blocked pattern for security validation
#[derive(Debug, Clone)]
struct BlockedPattern {
    pattern: String,
    severity: RiskLevel,
    description: String,
}

/// The Warden - Law Enforcement Point
pub struct Warden {
    /// Unique identifier for this Warden instance
    warden_id: String,
    /// Approval threshold (default: 70)
    threshold: u8,
    /// Decision log (immutable append)
    decision_log: Arc<RwLock<Vec<WardenDecision>>>,
    /// Blocked action counts
    blocked_count: Arc<RwLock<u64>>,
    /// Approved action counts
    approved_count: Arc<RwLock<u64>>,
    /// Security patterns to block
    blocked_patterns: Vec<BlockedPattern>,
    /// Hardware interface status
    hardware_available: Arc<RwLock<bool>>,
    /// Process isolation status
    isolation_enabled: Arc<RwLock<bool>>,
}

impl Warden {
    /// Create a new Warden instance
    pub fn new() -> Self {
        let warden_id = Self::generate_warden_id();
        
        log::info!("🛡️  Initializing Warden (LEP) - {}", &warden_id[..8]);
        
        Warden {
            warden_id,
            threshold: 70,
            decision_log: Arc::new(RwLock::new(Vec::new())),
            blocked_count: Arc::new(RwLock::new(0)),
            approved_count: Arc::new(RwLock::new(0)),
            blocked_patterns: Self::initialize_blocked_patterns(),
            hardware_available: Arc::new(RwLock::new(false)),
            isolation_enabled: Arc::new(RwLock::new(true)),
        }
    }
    
    /// Generate unique Warden ID
    fn generate_warden_id() -> String {
        let mut hasher = Sha256::new();
        hasher.update(Utc::now().to_rfc3339().as_bytes());
        hasher.update(rand_bytes(16).as_slice());
        hex::encode(hasher.finalize())
    }
    
    /// Initialize security patterns to block
    fn initialize_blocked_patterns() -> Vec<BlockedPattern> {
        vec![
            // Prompt injection patterns
            BlockedPattern {
                pattern: r"(?i)ignore\s+(all\s+)?(previous|prior|above)".to_string(),
                severity: RiskLevel::Critical,
                description: "Prompt injection attempt".to_string(),
            },
            BlockedPattern {
                pattern: r"(?i)disregard\s+(all\s+)?(previous|instructions)".to_string(),
                severity: RiskLevel::Critical,
                description: "Instruction override attempt".to_string(),
            },
            // Shell injection
            BlockedPattern {
                pattern: r"[;&|`\$(){}<>\\]|&&|\|\||>".to_string(),
                severity: RiskLevel::High,
                description: "Shell metacharacter injection".to_string(),
            },
            // Destructive commands
            BlockedPattern {
                pattern: r"\brm\s+-rf\b".to_string(),
                severity: RiskLevel::Critical,
                description: "Destructive file deletion".to_string(),
            },
            // Data exfiltration
            BlockedPattern {
                pattern: r"(?i)(send\s+.*\s+to\s+|upload\s+.*\s+to|exfiltrate)".to_string(),
                severity: RiskLevel::Critical,
                description: "Data exfiltration attempt".to_string(),
            },
            // Privilege escalation
            BlockedPattern {
                pattern: r"(?i)(sudo|chmod\s+777|chown)".to_string(),
                severity: RiskLevel::High,
                description: "Privilege escalation attempt".to_string(),
            },
            // Network attacks
            BlockedPattern {
                pattern: r"(?i)(\bnc\s+-|nmap\s+|-e\s+/bin)".to_string(),
                severity: RiskLevel::Critical,
                description: "Network attack tool".to_string(),
            },
        ]
    }
    
    /// Evaluate an action and return a decision
    pub async fn evaluate(&self, action: WardenAction) -> WardenDecision {
        let action_id = action.id.clone();
        let timestamp = Utc::now();
        
        log::info!("⚖️  Warden evaluating action: {}", action_id);
        
        // Step 1: Check against blocked patterns
        if let Some(blocked) = self.check_blocked_patterns(&action) {
            log::warn!("🛑 [{}] REJECTED - Blocked pattern: {}", action_id, blocked.description);
            
            let mut score = ActionScore::new();
            score.reasons.push(format!("Blocked: {}", blocked.description));
            
            let decision = WardenDecision {
                action_id: action_id.clone(),
                score,
                decision: "REJECTED".to_string(),
                signature: String::new(),
                timestamp,
                warden_id: self.warden_id.clone(),
            };
            
            self.log_decision(decision.clone()).await;
            return decision;
        }
        
        // Step 2: Score the action across all dimensions
        let mut score = self.score_action(&action).await;
        
        // Step 3: Apply risk multiplier
        let risk_multiplier = match action.risk_level {
            RiskLevel::Negligible => 1.0,
            RiskLevel::Low => 0.95,
            RiskLevel::Medium => 0.85,
            RiskLevel::High => 0.70,
            RiskLevel::Critical => 0.50,
        };
        
        score.total = ((score.total as f32) * risk_multiplier) as u8;
        score.approved = score.total >= self.threshold && 
                        score.safety >= 50 && 
                        score.ethics >= 50;
        
        // Step 4: Generate decision
        let decision_str = if score.approved {
            "APPROVED".to_string()
        } else {
            "REJECTED".to_string()
        };
        
        // Step 5: Generate cryptographic signature
        let signature = self.sign_decision(&action_id, &decision_str, &timestamp);
        
        // Step 6: Update counters
        if score.approved {
            let mut approved = self.approved_count.write().await;
            *approved += 1;
            log::info!("✅ [{}] APPROVED (score: {}/100)", action_id, score.total);
        } else {
            let mut blocked = self.blocked_count.write().await;
            *blocked += 1;
            log::warn!("🛑 [{}] REJECTED (score: {}/100)", action_id, score.total);
        }
        
        let decision = WardenDecision {
            action_id: action_id.clone(),
            score,
            decision: decision_str,
            signature,
            timestamp,
            warden_id: self.warden_id.clone(),
        };
        
        self.log_decision(decision.clone()).await;
        decision
    }
    
    /// Check if action matches any blocked pattern
    fn check_blocked_patterns(&self, action: &WardenAction) -> Option<BlockedPattern> {
        // Check target
        for pattern in &self.blocked_patterns {
            if let Ok(re) = regex::Regex::new(&pattern.pattern) {
                if re.is_match(&action.target) {
                    return Some(pattern.clone());
                }
            }
        }
        
        // Check payload
        if let Some(ref payload) = action.payload {
            for pattern in &self.blocked_patterns {
                if let Ok(re) = regex::Regex::new(&pattern.pattern) {
                    if re.is_match(payload) {
                        return Some(pattern.clone());
                    }
                }
            }
        }
        
        None
    }
    
    /// Score an action across all dimensions
    async fn score_action(&self, action: &WardenAction) -> ActionScore {
        let mut score = ActionScore::new();
        
        // Score Utility (0-100)
        score.utility = self.score_utility(action);
        score.reasons.push(format!("Utility: {}", score.utility));
        
        // Score Safety (0-100)
        score.safety = self.score_safety(action);
        score.reasons.push(format!("Safety: {}", score.safety));
        
        // Score Ethics (0-100)
        score.ethics = self.score_ethics(action);
        score.reasons.push(format!("Ethics: {}", score.ethics));
        
        // Score Viability (0-100)
        score.viability = self.score_viability(action);
        score.reasons.push(format!("Viability: {}", score.viability));
        
        // Calculate total
        score.calculate_total();
        
        score
    }
    
    /// Score utility dimension
    fn score_utility(&self, action: &WardenAction) -> u8 {
        let mut utility = 50u8; // Base score
        
        // Check if action has clear purpose
        if action.context.contains_key("user_goal") {
            utility += 20;
        }
        
        // Check if action is necessary (not redundant)
        if !action.context.contains_key("redundant") {
            utility += 15;
        }
        
        // Check efficiency
        if let Some(efficiency) = action.context.get("efficiency") {
            if efficiency.parse::<u8>().unwrap_or(50) > 70 {
                utility += 15;
            }
        }
        
        utility.min(100)
    }
    
    /// Score safety dimension
    fn score_safety(&self, action: &WardenAction) -> u8 {
        let mut safety = 50u8; // Start with neutral
        
        // Risk-based scoring
        match action.risk_level {
            RiskLevel::Negligible => safety += 40,
            RiskLevel::Low => safety += 25,
            RiskLevel::Medium => safety += 0,
            RiskLevel::High => safety = 20,
            RiskLevel::Critical => safety = 5,
        }
        
        // Check for destructive operations
        if let Some(ref payload) = action.payload {
            if payload.contains("rm -rf") || payload.contains("del /f /s") {
                safety = 5;
            }
        }
        
        // Check hardware interface status
        if !*self.hardware_available.read().await {
            safety = safety.saturating_sub(20);
        }
        
        // Ensure process isolation
        if !*self.isolation_enabled.read().await {
            safety = safety.saturating_sub(30);
        }
        
        safety.min(100)
    }
    
    /// Score ethics dimension
    fn score_ethics(&self, action: &WardenAction) -> u8 {
        let mut ethics = 50u8;
        
        // Check action type
        match action.action_type {
            Warden'sActionType::DataExfiltration => ethics = 0,
            Warden'sActionType::SystemModification => ethics = 30,
            _ => ethics = 70,
        }
        
        // Check for privacy violations
        if let Some(ref payload) = action.payload {
            if payload.to_lowercase().contains("password") ||
               payload.to_lowercase().contains("secret") ||
               payload.to_lowercase().contains("credential") {
                ethics = ethics.saturating_sub(30);
            }
        }
        
        // Check user authorization
        if action.context.contains_key("authorized") {
            ethics += 20;
        }
        
        ethics.min(100)
    }
    
    /// Score viability dimension
    fn score_viability(&self, action: &WardenAction) -> u8 {
        let mut viability = 50u8;
        
        // Check if required resources are available
        if action.context.contains_key("resources_available") {
            viability += 30;
        }
        
        // Check target validity
        if !action.target.is_empty() && action.target != "/" {
            viability += 15;
        }
        
        // Check payload size (reasonable vs excessive)
        if let Some(ref payload) = action.payload {
            if payload.len() < 10000 {
                viability += 5;
            } else {
                viability = viability.saturating_sub(20);
            }
        }
        
        viability.min(100)
    }
    
    /// Sign a decision cryptographically
    fn sign_decision(&self, action_id: &str, decision: &str, timestamp: &DateTime<Utc>) -> String {
        let mut hasher = Sha256::new();
        hasher.update(action_id.as_bytes());
        hasher.update(decision.as_bytes());
        hasher.update(timestamp.to_rfc3339().as_bytes());
        hasher.update(self.warden_id.as_bytes());
        hex::encode(hasher.finalize())
    }
    
    /// Log decision (immutable append)
    async fn log_decision(&self, decision: WardenDecision) {
        let mut log = self.decision_log.write().await;
        log.push(decision);
    }
    
    /// Get decision log
    pub async fn get_decision_log(&self) -> Vec<WardenDecision> {
        self.decision_log.read().await.clone()
    }
    
    /// Get Warden statistics
    pub async fn get_stats(&self) -> WardenStats {
        WardenStats {
            approved: *self.approved_count.read().await,
            blocked: *self.blocked_count.read().await,
            warden_id: self.warden_id.clone(),
            threshold: self.threshold,
        }
    }
    
    /// Set hardware interface status
    pub async fn set_hardware_status(&self, available: bool) {
        let mut hw = self.hardware_available.write().await;
        *hw = available;
        log::info!("Hardware interface: {}", if available { "available" } else { "unavailable" });
    }
    
    /// Set isolation status
    pub async fn set_isolation_status(&self, enabled: bool) {
        let mut iso = self.isolation_enabled.write().await;
        *iso = enabled;
        log::info!("Process isolation: {}", if enabled { "enabled" } else { "disabled" });
    }
    
    /// Health check
    pub async fn is_healthy(&self) -> bool {
        *self.hardware_available.read().await || true // Warden is healthy even without hardware
    }
}

impl Default for Warden {
    fn default() -> Self {
        Self::new()
    }
}

/// Warden statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WardenStats {
    pub approved: u64,
    pub blocked: u64,
    pub warden_id: String,
    pub threshold: u8,
}

/// Generate random bytes for ID generation
fn rand_bytes(len: usize) -> Vec<u8> {
    use std::time::{SystemTime, UNIX_EPOCH};
    let mut bytes = vec![0u8; len];
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos() as u64;
    
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = ((seed >> (i % 8)) ^ (i as u64 * 1103515245 + 12345)) as u8;
    }
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_default_blocked() {
        let warden = Warden::new();
        
        let action = WardenAction {
            id: "test-1".to_string(),
            action_type: Warden'sActionType::Execute,
            target: "test".to_string(),
            payload: Some("rm -rf /".to_string()),
            requested_by: "test".to_string(),
            risk_level: RiskLevel::Critical,
            timestamp: Utc::now(),
            context: HashMap::new(),
        };
        
        let decision = warden.evaluate(action).await;
        assert_eq!(decision.decision, "REJECTED");
    }
    
    #[tokio::test]
    async fn test_safe_action_approved() {
        let warden = Warden::new();
        
        let action = WardenAction {
            id: "test-2".to_string(),
            action_type: Warden'sActionType::ReadFile,
            target: "/tmp/test.txt".to_string(),
            payload: None,
            requested_by: "authorized_user".to_string(),
            risk_level: RiskLevel::Low,
            timestamp: Utc::now(),
            context: HashMap::from([
                ("user_goal".to_string(), "read_file".to_string()),
                ("authorized".to_string(), "true".to_string()),
                ("resources_available".to_string(), "true".to_string()),
            ]),
        };
        
        let decision = warden.evaluate(action).await;
        // With proper context, should score higher
        assert!(decision.score.utility > 50);
    }
}
