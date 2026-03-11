//! Core types for the Itheris shell module.
//!
//! This module defines the fundamental data structures used for
//! inter-process communication and kernel monitoring.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use uuid::Uuid;

// ============================================================================
// EXISTING TYPES - Preserved from original file
// ============================================================================

/// Severity levels for failures in the system.
///
/// Used to classify the severity of detected failures and determine
/// appropriate response actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "FAILURE_")]
pub enum FailureSeverity {
    /// Minor failure - minimal impact, system continues operating
    Minor,
    /// Moderate failure - noticeable impact, may require attention
    Moderate,
    /// Major failure - significant impact, requires intervention
    Major,
    /// Critical failure - severe impact, immediate action required
    Critical,
    /// Catastrophic failure - complete system failure or unrecoverable state
    Catastrophic,
}

impl Default for FailureSeverity {
    fn default() -> Self {
        FailureSeverity::Minor
    }
}

impl FailureSeverity {
    /// Returns true if this severity level is critical or higher.
    pub fn is_critical(&self) -> bool {
        matches!(self, FailureSeverity::Critical | FailureSeverity::Catastrophic)
    }

    /// Parse from string representation (case-insensitive).
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "FAILURE_MINOR" => Some(FailureSeverity::Minor),
            "FAILURE_MODERATE" => Some(FailureSeverity::Moderate),
            "FAILURE_MAJOR" => Some(FailureSeverity::Major),
            "FAILURE_CRITICAL" => Some(FailureSeverity::Critical),
            "FAILURE_CATASTROPHIC" => Some(FailureSeverity::Catastrophic),
            _ => None,
        }
    }
}

impl std::fmt::Display for FailureSeverity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FailureSeverity::Minor => write!(f, "FAILURE_MINOR"),
            FailureSeverity::Moderate => write!(f, "FAILURE_MODERATE"),
            FailureSeverity::Major => write!(f, "FAILURE_MAJOR"),
            FailureSeverity::Critical => write!(f, "FAILURE_CRITICAL"),
            FailureSeverity::Catastrophic => write!(f, "FAILURE_CATASTROPHIC"),
        }
    }
}

/// Autonomy levels for the system.
///
/// Defines the degree of autonomous operation allowed for the kernel.
/// Matches Julia's AutonomyLevel enum:
/// - AUTONOMY_FULL: Full autonomy - system operates completely independently
/// - AUTONOMY_REDUCED: Reduced autonomy - system operates with some human oversight
/// - AUTONOMY_RESTRICTED: Limited actions only
/// - AUTONOMY_MINIMAL: Observation only, minimal autonomy
/// - AUTONOMY_HALTED: Complete halt - all actions blocked
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "AUTONOMY_")]
pub enum AutonomyLevel {
    /// Full autonomy - system operates completely independently
    Full,
    /// Reduced autonomy - system operates with some human oversight
    Reduced,
    /// Restricted autonomy - limited actions only
    Restricted,
    /// Minimal autonomy - observation only
    Minimal,
    /// Halted - system is in a stopped state, all actions blocked
    Halted,
}

impl Default for AutonomyLevel {
    fn default() -> Self {
        AutonomyLevel::Full
    }
}

impl AutonomyLevel {
    /// Returns true if the system is allowed to operate autonomously.
    pub fn is_autonomous(&self) -> bool {
        !matches!(self, AutonomyLevel::Halted)
    }

    /// Returns true if the system is in a restricted mode (Restricted or below).
    pub fn is_restricted(&self) -> bool {
        matches!(self, AutonomyLevel::Restricted | AutonomyLevel::Minimal | AutonomyLevel::Halted)
    }

    /// Returns the index of this autonomy level (lower = more restricted).
    pub fn level_index(&self) -> usize {
        match self {
            AutonomyLevel::Full => 0,
            AutonomyLevel::Reduced => 1,
            AutonomyLevel::Restricted => 2,
            AutonomyLevel::Minimal => 3,
            AutonomyLevel::Halted => 4,
        }
    }

    /// Parse from string representation (case-insensitive).
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "AUTONOMY_FULL" => Some(AutonomyLevel::Full),
            "AUTONOMY_REDUCED" => Some(AutonomyLevel::Reduced),
            "AUTONOMY_RESTRICTED" => Some(AutonomyLevel::Restricted),
            "AUTONOMY_MINIMAL" => Some(AutonomyLevel::Minimal),
            "AUTONOMY_HALTED" => Some(AutonomyLevel::Halted),
            _ => None,
        }
    }
}

impl std::fmt::Display for AutonomyLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AutonomyLevel::Full => write!(f, "AUTONOMY_FULL"),
            AutonomyLevel::Reduced => write!(f, "AUTONOMY_REDUCED"),
            AutonomyLevel::Restricted => write!(f, "AUTONOMY_RESTRICTED"),
            AutonomyLevel::Minimal => write!(f, "AUTONOMY_MINIMAL"),
            AutonomyLevel::Halted => write!(f, "AUTONOMY_HALTED"),
        }
    }
}

/// Represents an action to be performed in the world.
///
/// This struct captures the intent, type, parameters, and risk assessment
/// of a proposed action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorldAction {
    /// Unique identifier for this action
    pub id: Uuid,
    /// The intent behind this action
    pub intent: String,
    /// Type of action being performed
    pub action_type: String,
    /// Key-value parameters for the action
    pub parameters: HashMap<String, String>,
    /// Risk classification of the action
    pub risk_class: String,
    /// Whether the action can be reversed
    pub reversibility: String,
    /// Expected outcome of the action
    pub expected_outcome: String,
}

impl WorldAction {
    /// Create a new WorldAction with a generated UUID.
    pub fn new(
        intent: String,
        action_type: String,
        parameters: HashMap<String, String>,
        risk_class: String,
        reversibility: String,
        expected_outcome: String,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            intent,
            action_type,
            parameters,
            risk_class,
            reversibility,
            expected_outcome,
        }
    }
}

/// Result of executing a world action.
///
/// Captures the actual outcome, prediction accuracy, and any side effects.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActionResult {
    /// Reference to the action that was executed
    pub action_id: Uuid,
    /// Status of the action execution
    pub status: String,
    /// Actual outcome of the action
    pub actual_outcome: String,
    /// Error message if the action failed
    pub error_message: String,
    /// Prediction error (difference between expected and actual)
    pub prediction_error: f64,
    /// Any side effects observed during execution
    pub side_effects: Vec<String>,
}

impl ActionResult {
    /// Create a new ActionResult.
    pub fn new(
        action_id: Uuid,
        status: String,
        actual_outcome: String,
        error_message: String,
        prediction_error: f64,
        side_effects: Vec<String>,
    ) -> Self {
        Self {
            action_id,
            status,
            actual_outcome,
            error_message,
            prediction_error,
            side_effects,
        }
    }

    /// Returns true if the action was successful.
    pub fn is_success(&self) -> bool {
        self.status.to_lowercase() == "success"
    }
}

/// Type of failure for categorizing failures.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FailureType {
    /// Authorization failure
    Authorization,
    /// Execution failure
    Execution,
    /// Doctrine violation
    Doctrine,
    /// Identity drift
    Drift,
    /// Reputation failure
    Reputation,
    /// Unknown failure
    Unknown,
}

impl FailureType {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "authorization" => Some(FailureType::Authorization),
            "execution" => Some(FailureType::Execution),
            "doctrine" => Some(FailureType::Doctrine),
            "drift" => Some(FailureType::Drift),
            "reputation" => Some(FailureType::Reputation),
            _ => Some(FailureType::Unknown),
        }
    }
}

/// Escalation policy for failure containment.
///
/// Defines how failures should be escalated, including threshold,
/// time window, autonomy reduction, and cooldown periods.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscalationPolicy {
    /// Number of failures before escalation is triggered
    pub failure_threshold: u32,
    /// Time window in seconds for counting failures
    pub time_window_seconds: f64,
    /// Autonomy level to reduce to on escalation
    pub autonomy_reduction: AutonomyLevel,
    /// Whether reflection is required after failure
    pub require_reflection: bool,
    /// Cooldown period in seconds before autonomy restoration
    pub cooldown_seconds: f64,
}

impl Default for EscalationPolicy {
    fn default() -> Self {
        Self {
            failure_threshold: 3,
            time_window_seconds: 300.0,
            autonomy_reduction: AutonomyLevel::Reduced,
            require_reflection: true,
            cooldown_seconds: 60.0,
        }
    }
}

impl EscalationPolicy {
    /// Create a new escalation policy with custom values.
    pub fn new(
        failure_threshold: u32,
        time_window_seconds: f64,
        autonomy_reduction: AutonomyLevel,
        require_reflection: bool,
        cooldown_seconds: f64,
    ) -> Self {
        Self {
            failure_threshold,
            time_window_seconds,
            autonomy_reduction,
            require_reflection,
            cooldown_seconds,
        }
    }
}

/// Record of a failure occurrence.
///
/// Contains all information about a failure event including
/// severity, type, side effects, and resulting autonomy impact.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailureEvent {
    /// Unique identifier for this failure event
    pub id: Uuid,
    /// When the failure occurred
    pub timestamp: DateTime<Utc>,
    /// Severity level of the failure
    pub severity: FailureSeverity,
    /// Associated action ID
    pub action_id: Uuid,
    /// Category of failure
    pub failure_type: FailureType,
    /// Description of the failure
    pub error_message: String,
    /// Unintended consequences observed
    pub side_effects: Vec<String>,
    /// Resulting autonomy reduction
    pub autonomy_impact: AutonomyLevel,
}

impl FailureEvent {
    /// Create a new failure event.
    pub fn new(
        severity: FailureSeverity,
        action_id: Uuid,
        failure_type: FailureType,
        error_message: String,
        side_effects: Vec<String>,
        autonomy_impact: AutonomyLevel,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            timestamp: Utc::now(),
            severity,
            action_id,
            failure_type,
            error_message,
            side_effects,
            autonomy_impact,
        }
    }

    /// Create a simple failure event with default values.
    pub fn simple(severity: FailureSeverity, action_id: Uuid) -> Self {
        Self::new(
            severity,
            action_id,
            FailureType::Unknown,
            String::new(),
            vec![],
            AutonomyLevel::Full,
        )
    }
}

/// Rate limit entry for tracking action rates.
#[derive(Debug, Clone)]
pub struct RateLimitEntry {
    /// Timestamps of recent actions
    pub timestamps: Vec<DateTime<Utc>>,
}

impl Default for RateLimitEntry {
    fn default() -> Self {
        Self {
            timestamps: Vec::new(),
        }
    }
}

/// Mutable state for tracking failures, autonomy, and rate limits.
///
/// This is the core failure containment state that tracks all
/// failure events, current autonomy level, and enforces rate limits.
#[derive(Debug, Clone)]
pub struct FailureTracker {
    /// Recent failure events
    pub recent_failures: Vec<FailureEvent>,
    /// Current autonomy level
    pub current_autonomy: AutonomyLevel,
    /// Last time autonomy was changed
    pub last_autonomy_change: DateTime<Utc>,
    /// Whether reflection is currently required
    pub reflection_required: bool,
    /// Whether reflection has been completed
    pub reflection_completed: bool,
    /// Rate limits per action type
    pub rate_limits: HashMap<String, RateLimitEntry>,
    /// Escalation policy
    pub escalation_policy: EscalationPolicy,
    /// Conservative mode enabled
    pub conservative_mode: bool,
}

impl Default for FailureTracker {
    fn default() -> Self {
        Self::new()
    }
}

impl FailureTracker {
    /// Create a new failure tracker with default values.
    pub fn new() -> Self {
        Self {
            recent_failures: Vec::new(),
            current_autonomy: AutonomyLevel::Full,
            last_autonomy_change: Utc::now(),
            reflection_required: false,
            reflection_completed: false,
            rate_limits: HashMap::new(),
            escalation_policy: EscalationPolicy::default(),
            conservative_mode: false,
        }
    }

    /// Get the current autonomy level.
    pub fn get_autonomy(&self) -> AutonomyLevel {
        self.current_autonomy
    }

    /// Record a failure event.
    pub fn record_failure(&mut self, event: FailureEvent) {
        self.recent_failures.push(event);
        self.cleanup_old_failures();
    }

    /// Clean up failures outside the time window.
    fn cleanup_old_failures(&mut self) {
        let cutoff = Utc::now() - chrono::Duration::seconds(self.escalation_policy.time_window_seconds as i64);
        self.recent_failures.retain(|f| f.timestamp > cutoff);
    }

    /// Get the count of recent failures.
    pub fn failure_count(&self) -> usize {
        self.recent_failures.len()
    }

    /// Check if failure threshold has been reached.
    pub fn threshold_reached(&self) -> bool {
        self.failure_count() >= self.escalation_policy.failure_threshold as usize
    }

    /// Check rate limit for an action type.
    /// Returns true if action is allowed, false if rate limited.
    pub fn check_rate_limit(&mut self, action_type: &str) -> bool {
        let max_actions = 10;
        let window_seconds = 60.0;
        
        let entry = self.rate_limits.entry(action_type.to_string()).or_default();
        
        // Clean up old entries
        let cutoff = Utc::now() - chrono::Duration::seconds(window_seconds as i64);
        entry.timestamps.retain(|t| *t > cutoff);
        
        // Check limit
        if entry.timestamps.len() >= max_actions {
            return false;
        }
        
        // Record this action
        entry.timestamps.push(Utc::now());
        true
    }

    /// Get rate limit status for an action type.
    pub fn get_rate_limit_status(&self, action_type: &str) -> Option<(usize, usize)> {
        let max_actions = 10;
        let window_seconds = 60.0;
        
        if let Some(entry) = self.rate_limits.get(action_type) {
            let cutoff = Utc::now() - chrono::Duration::seconds(window_seconds as i64);
            let current = entry.timestamps.iter().filter(|t| **t > cutoff).count();
            Some((current, max_actions))
        } else {
            Some((0, max_actions))
        }
    }

    /// Apply autonomy restriction.
    pub fn apply_autonomy_restriction(&mut self, level: AutonomyLevel) {
        // Don't escalate beyond halted
        if level == AutonomyLevel::Halted || self.current_autonomy == AutonomyLevel::Halted {
            self.current_autonomy = AutonomyLevel::Halted;
        } else {
            self.current_autonomy = level;
        }
        self.last_autonomy_change = Utc::now();
        self.conservative_mode = true;
    }

    /// Check if cooldown has passed since last autonomy change.
    pub fn cooldown_passed(&self) -> bool {
        let elapsed = Utc::now() - self.last_autonomy_change;
        elapsed.num_seconds() as f64 >= self.escalation_policy.cooldown_seconds
    }

    /// Attempt to restore autonomy by one level.
    pub fn attempt_restoration(&mut self) -> bool {
        if !self.cooldown_passed() {
            return false;
        }

        if self.reflection_required && !self.reflection_completed {
            return false;
        }

        // Try to restore autonomy
        let current_idx = self.current_autonomy.level_index();
        if current_idx > 0 {
            let new_level = match current_idx {
                1 => AutonomyLevel::Full,
                2 => AutonomyLevel::Reduced,
                3 => AutonomyLevel::Restricted,
                4 => AutonomyLevel::Minimal,
                _ => AutonomyLevel::Halted,
            };
            
            self.current_autonomy = new_level;
            self.last_autonomy_change = Utc::now();
            
            // Disable conservative mode if full autonomy restored
            if new_level == AutonomyLevel::Full {
                self.conservative_mode = false;
            }
            
            return true;
        }

        false
    }

    /// Force a reflection cycle.
    pub fn force_reflection(&mut self, reason: &str) {
        self.reflection_required = true;
        self.reflection_completed = false;
    }

    /// Complete the reflection cycle.
    pub fn complete_reflection(&mut self) {
        self.reflection_completed = true;
    }

    /// Trigger emergency halt - all actions blocked.
    pub fn emergency_halt(&mut self, reason: &str) {
        self.current_autonomy = AutonomyLevel::Halted;
        self.last_autonomy_change = Utc::now();
        self.reflection_required = true;
        self.reflection_completed = false;
        self.conservative_mode = true;
    }

    /// Trigger graceful degradation - reduce to minimal autonomy.
    pub fn graceful_degradation(&mut self, reason: &str) {
        self.current_autonomy = AutonomyLevel::Minimal;
        self.last_autonomy_change = Utc::now();
        self.conservative_mode = true;
        self.force_reflection(reason);
    }
}

/// Detect failure severity from an action result.
///
/// Analyzes the result for failure indicators and assesses severity.
pub fn detect_failure(action: &WorldAction, result: &ActionResult) -> FailureSeverity {
    // Check for explicit failure status
    if result.status.to_lowercase() == "failed" {
        // Check for silent failure indicators (empty outcome and no error)
        if result.actual_outcome.is_empty() && result.error_message.is_empty() {
            return FailureSeverity::Major;
        }
        
        // Analyze based on prediction error
        let pred_err = result.prediction_error.abs();
        if pred_err > 0.8 {
            return FailureSeverity::Critical;
        } else if pred_err > 0.5 {
            return FailureSeverity::Major;
        } else if pred_err > 0.3 {
            return FailureSeverity::Moderate;
        } else {
            return FailureSeverity::Minor;
        }
    } else if result.status.to_lowercase() == "blocked" {
        return FailureSeverity::Minor;
    } else if result.status.to_lowercase() == "aborted" {
        return FailureSeverity::Moderate;
    }
    
    // Check for silent success (unvalidated results)
    if result.status.to_lowercase() == "success" {
        if result.actual_outcome.is_empty() {
            return FailureSeverity::Minor;
        }
        
        // High prediction error even on success indicates issues
        let pred_err = result.prediction_error.abs();
        if pred_err > 0.7 {
            return FailureSeverity::Moderate;
        } else if pred_err > 0.5 {
            return FailureSeverity::Minor;
        }
    }
    
    // Check for negative side effects
    if !result.side_effects.is_empty() {
        if result.side_effects.len() > 3 {
            return FailureSeverity::Major;
        }
        return FailureSeverity::Minor;
    }
    
    FailureSeverity::Minor
}

/// Get severity index for comparison.
pub fn get_severity_index(severity: FailureSeverity) -> usize {
    match severity {
        FailureSeverity::Minor => 0,
        FailureSeverity::Moderate => 1,
        FailureSeverity::Major => 2,
        FailureSeverity::Critical => 3,
        FailureSeverity::Catastrophic => 4,
    }
}

// ============================================================================
// NEW SECURITY TYPES - HCB Protocol Implementation
// ============================================================================

/// Authorized command with cryptographic verification (Pillar 1 & 2).
///
/// This struct carries a signed command payload with Ed25519 signature,
/// public key, nonce for replay protection, and timestamp for freshness.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthorizedCommand {
    /// The serialized command payload (JSON bytes of the action)
    pub command_payload: Vec<u8>,
    /// Ed25519 signature (64 bytes, base64-encoded for JSON transport)
    pub signature: String,
    /// Ed25519 public key (32 bytes, base64-encoded for JSON transport)
    pub public_key: String,
    /// Monotonic nonce for replay protection
    pub nonce: u64,
    /// Unix timestamp (milliseconds) for freshness check
    pub timestamp: i64,
}

/// Types of security violations for the HCB Protocol (Pillar 3).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SecurityViolationType {
    /// Ed25519 signature verification failed
    InvalidSignature,
    /// Timestamp outside acceptable window
    ExpiredTimestamp,
    /// Nonce was already used (replay attack)
    ReplayedNonce,
    /// Command matches blacklist pattern
    BlacklistedCommand,
    /// Binary path not in allowed list
    UnauthorizedBinary,
    /// Payload failed to parse or is malformed
    MalformedPayload,
    /// Heartbeat timeout exceeded
    HeartbeatTimeout,
    /// Handshake protocol failure
    HandshakeFailure,
}

/// Security violation event with details and context.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityViolation {
    /// The type of violation that occurred
    pub violation_type: SecurityViolationType,
    /// Human-readable details about the violation
    pub details: String,
    /// Unix timestamp (milliseconds) when violation occurred
    pub timestamp: i64,
    /// Source IP if available (for network-based attacks)
    pub source_ip: Option<String>,
}

/// Safety Gateway - Command Blacklist Enforcement (Pillar 3).
///
/// Provides compile-time blacklist checking to prevent dangerous
/// shell commands from being executed. This is the third pillar
/// of defense in the HCB Protocol.
pub struct SafetyGateway;

impl SafetyGateway {
    /// Compile-time constant blacklist patterns
    const BLACKLIST_PATTERNS: &'static [&'static str] = &[
        "rm -rf /",
        "rm -rf /*",
        "rm -rf ~",
        "mkfs",
        "dd if=",
        "chmod 777",
        "chmod +s",
        "chmod u+s",
        "chmod g+s",
        "curl | sh",
        "curl | bash",
        "wget | sh",
        "wget | bash",
        "eval(",
        "> /dev/sda",
        "> /dev/nvme",
        ":(){ :|:& };:",  // fork bomb
        "/etc/passwd",
        "/etc/shadow",
        "/boot/",
        "shutdown",
        "reboot",
        "init 0",
        "init 6",
        "systemctl halt",
        "systemctl poweroff",
    ];

    /// Allowed binary paths - commands MUST start with one of these
    const ALLOWED_BINARIES: &'static [&'static str] = &[
        "/usr/bin/",
        "/usr/local/bin/",
        "/bin/",
        "echo",
        "cat",
        "ls",
        "pwd",
        "whoami",
        "date",
        "head",
        "tail",
        "grep",
        "find",
        "wc",
        "sort",
        "uniq",
        "diff",
        "mkdir",
        "cp",
        "mv",
        "touch",
    ];

    /// Check a command string against the safety gateway
    /// Returns Ok(()) if safe, Err(SecurityViolation) if blocked
    pub fn check(command: &str) -> Result<(), SecurityViolation> {
        let normalized = command.to_lowercase().trim().to_string();
        
        // Check blacklist
        for pattern in Self::BLACKLIST_PATTERNS {
            if normalized.contains(&pattern.to_lowercase()) {
                return Err(SecurityViolation {
                    violation_type: SecurityViolationType::BlacklistedCommand,
                    details: format!("Command matches blacklist pattern: {}", pattern),
                    timestamp: chrono::Utc::now().timestamp_millis(),
                    source_ip: None,
                });
            }
        }
        
        Ok(())
    }
}

/// Nonce tracker for replay attack prevention (Pillar 2).
///
/// Maintains a sliding window of seen nonces to detect and block
/// replayed commands.
pub struct NonceTracker {
    seen_nonces: VecDeque<u64>,
    max_size: usize,
}

impl NonceTracker {
    /// Create a new nonce tracker with the specified maximum size.
    pub fn new(max_size: usize) -> Self {
        Self {
            seen_nonces: VecDeque::with_capacity(max_size),
            max_size,
        }
    }
    
    /// Returns true if nonce is fresh (not seen before), false if replayed
    pub fn check_and_record(&mut self, nonce: u64) -> bool {
        if self.seen_nonces.contains(&nonce) {
            return false;
        }
        if self.seen_nonces.len() >= self.max_size {
            self.seen_nonces.pop_front();
        }
        self.seen_nonces.push_back(nonce);
        true
    }
}

// ============================================================================
// IPC MESSAGE TYPES - Updated with HCB Protocol variants
// ============================================================================

/// IPC message types for communication with the Julia kernel.
///
/// This enum represents the different types of messages that can be
/// exchanged over the Unix Domain Socket connection.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum IpcMessage {
    /// Request to execute an action
    ExecuteAction {
        action: WorldAction,
    },
    /// Response with action result
    ActionResult {
        result: ActionResult,
    },
    /// Failure severity notification
    FailureNotification {
        severity: FailureSeverity,
        timestamp: DateTime<Utc>,
        description: String,
    },
    /// Autonomy level change request
    AutonomyChange {
        level: AutonomyLevel,
    },
    /// Heartbeat/ping message
    Ping {
        timestamp: DateTime<Utc>,
    },
    /// Pong/heartbeat response
    Pong {
        timestamp: DateTime<Utc>,
    },
    /// Kernel status request
    StatusRequest,
    /// Kernel status response
    StatusResponse {
        running: bool,
        pid: Option<u32>,
        autonomy_level: AutonomyLevel,
    },
    /// Kill/stop kernel request
    KillKernel {
        reason: String,
    },
    /// Kernel shutdown confirmation
    KernelShutdown {
        exit_code: i32,
    },
    /// Error response
    Error {
        code: String,
        message: String,
    },
    
    // =========================================================================
    // NEW HCB Protocol Message Variants
    // =========================================================================
    
    /// Heartbeat message for liveness checking (Pillar 4)
    Heartbeat {
        /// Challenge value for cryptographic verification
        challenge: u64,
        /// Julia process ID
        julia_pid: i32,
        /// Timestamp in milliseconds
        timestamp: i64,
    },
    /// Heartbeat acknowledgment response
    HeartbeatAck {
        /// Response to the challenge
        response: u64,
        /// New challenge for next heartbeat
        new_challenge: u64,
    },
    /// Authorized command execution (Pillars 1 & 2)
    AuthorizedExecute {
        authorized_command: AuthorizedCommand,
    },
    /// Security violation report (Pillar 3)
    SecurityViolationReport {
        violation: SecurityViolation,
    },
    /// Initial handshake message
    Handshake {
        /// Julia process ID
        julia_pid: i32,
        /// Protocol version string
        protocol_version: String,
    },
    /// Handshake acknowledgment
    HandshakeAck {
        /// Whether handshake was accepted
        accepted: bool,
        /// Initial challenge for heartbeat
        initial_challenge: u64,
        /// Shell version string
        shell_version: String,
    },
}

impl IpcMessage {
    /// Serialize this message to JSON bytes.
    pub fn to_json(&self) -> anyhow::Result<String> {
        serde_json::to_string(self).map_err(|e| anyhow::anyhow!("Serialization error: {}", e))
    }

    /// Deserialize a message from JSON bytes.
    pub fn from_json(json: &str) -> anyhow::Result<Self> {
        serde_json::from_str(json).map_err(|e| anyhow::anyhow!("Deserialization error: {}", e))
    }
}

/// Wrapper for IPC requests with response handling.
#[derive(Debug, Serialize, Deserialize)]
pub struct IpcRequest {
    /// Unique request identifier
    pub request_id: Uuid,
    /// The IPC message
    pub message: IpcMessage,
    /// Request timestamp
    pub timestamp: DateTime<Utc>,
}

impl IpcRequest {
    /// Create a new IPC request.
    pub fn new(message: IpcMessage) -> Self {
        Self {
            request_id: Uuid::new_v4(),
            message,
            timestamp: Utc::now(),
        }
    }
}

/// Wrapper for IPC responses.
#[derive(Debug, Serialize, Deserialize)]
pub struct IpcResponse {
    /// Request identifier this response corresponds to
    pub request_id: Uuid,
    /// The IPC message response
    pub message: IpcMessage,
    /// Response timestamp
    pub timestamp: DateTime<Utc>,
}

impl IpcResponse {
    /// Create a new IPC response.
    pub fn new(request_id: Uuid, message: IpcMessage) -> Self {
        Self {
            request_id,
            message,
            timestamp: Utc::now(),
        }
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_failure_severity_parsing() {
        assert_eq!(
            FailureSeverity::from_str("FAILURE_CRITICAL"),
            Some(FailureSeverity::Critical)
        );
        assert_eq!(
            FailureSeverity::from_str("failure_critical"),
            Some(FailureSeverity::Critical)
        );
        assert_eq!(FailureSeverity::from_str("INVALID"), None);
    }

    #[test]
    fn test_failure_severity_is_critical() {
        assert!(!FailureSeverity::Minor.is_critical());
        assert!(!FailureSeverity::Moderate.is_critical());
        assert!(!FailureSeverity::Major.is_critical());
        assert!(FailureSeverity::Critical.is_critical());
        assert!(FailureSeverity::Catastrophic.is_critical());
    }

    #[test]
    fn test_autonomy_level_parsing() {
        assert_eq!(
            AutonomyLevel::from_str("AUTONOMY_FULL"),
            Some(AutonomyLevel::Full)
        );
        assert_eq!(
            AutonomyLevel::from_str("AUTONOMY_HALTED"),
            Some(AutonomyLevel::Halted)
        );
    }

    #[test]
    fn test_world_action_creation() {
        let mut params = HashMap::new();
        params.insert("key".to_string(), "value".to_string());
        
        let action = WorldAction::new(
            "test intent".to_string(),
            "test_type".to_string(),
            params,
            "low".to_string(),
            "reversible".to_string(),
            "expected".to_string(),
        );
        
        assert_eq!(action.intent, "test intent");
        assert_eq!(action.action_type, "test_type");
    }

    #[test]
    fn test_ipc_message_serialization() {
        let msg = IpcMessage::Ping {
            timestamp: Utc::now(),
        };
        
        let json = msg.to_json().unwrap();
        let parsed = IpcMessage::from_json(&json).unwrap();
        
        match parsed {
            IpcMessage::Ping { .. } => (),
            _ => panic!("Expected Ping message"),
        }
    }

    // New tests for security types
    
    #[test]
    fn test_nonce_tracker_fresh() {
        let mut tracker = NonceTracker::new(10);
        assert!(tracker.check_and_record(1));
        assert!(tracker.check_and_record(2));
        assert!(tracker.check_and_record(3));
    }

    #[test]
    fn test_nonce_tracker_replay() {
        let mut tracker = NonceTracker::new(10);
        assert!(tracker.check_and_record(1));
        assert!(!tracker.check_and_record(1)); // Replay should fail
    }

    #[test]
    fn test_nonce_tracker_max_size() {
        let mut tracker = NonceTracker::new(3);
        assert!(tracker.check_and_record(1));
        assert!(tracker.check_and_record(2));
        assert!(tracker.check_and_record(3));
        assert!(tracker.check_and_record(4));
        // First nonce should be evicted, so 1 is fresh again
        assert!(tracker.check_and_record(1));
    }

    #[test]
    fn test_safety_gateway_allows_safe_command() {
        let result = SafetyGateway::check("echo hello");
        assert!(result.is_ok());
    }

    #[test]
    fn test_safety_gateway_blocks_dangerous_command() {
        let result = SafetyGateway::check("rm -rf /");
        assert!(result.is_err());
        match result {
            Err(violation) => {
                assert!(matches!(violation.violation_type, SecurityViolationType::BlacklistedCommand));
            }
            _ => panic!("Expected SecurityViolation"),
        }
    }

    #[test]
    fn test_safety_gateway_blocks_fork_bomb() {
        let result = SafetyGateway::check(":(){ :|:& };:");
        assert!(result.is_err());
    }

    #[test]
    fn test_authorized_command_serialization() {
        let cmd = AuthorizedCommand {
            command_payload: b"{\"action\": \"test\"}".to_vec(),
            signature: "dGhpcyBpcyBhIHRlc3Qgc2lnbmF0dXJl".to_string(),
            public_key: "dGhpcyBpcyBhIHRlc3QgcHVibGljIGtleQ==".to_string(),
            nonce: 12345,
            timestamp: 1699999999999,
        };
        
        let json = serde_json::to_string(&cmd).unwrap();
        let parsed: AuthorizedCommand = serde_json::from_str(&json).unwrap();
        
        assert_eq!(parsed.nonce, 12345);
        assert_eq!(parsed.timestamp, 1699999999999);
    }
}
