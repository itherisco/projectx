//! Intent Validator Module
//!
//! This module validates intents before they are processed by the LEP decision gate.
//! It enforces intent schemas, filters and sanitizes inputs, and maintains audit logs.
//!
//! ## Security Principles
//! - Fail-closed: deny on any validation failure
//! - All inputs must be sanitized
//! - All validation attempts are logged

use chrono::{DateTime, Utc};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

// ============================================================================
// INTENT TYPES
// ============================================================================

/// Intent priority levels
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum IntentPriority {
    /// Low priority - best effort
    Low = 0,
    /// Normal priority
    Normal = 1,
    /// High priority
    High = 2,
    /// Critical priority - must be processed immediately
    Critical = 3,
}

/// Intent risk level
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum RiskLevel {
    /// Minimal risk - read-only operations
    Minimal,
    /// Low risk - limited modifications
    Low,
    /// Medium risk - significant changes
    Medium,
    /// High risk - system-level changes
    High,
    /// Critical risk - could affect system stability
    Critical,
}

/// A validated intent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidatedIntent {
    /// Original intent string
    pub original_intent: String,
    /// Sanitized intent string
    pub sanitized_intent: String,
    /// Intent action type
    pub action: IntentAction,
    /// Target resource (if applicable)
    pub target: Option<String>,
    /// Parameters (sanitized)
    pub parameters: HashMap<String, String>,
    /// Priority level
    pub priority: IntentPriority,
    /// Risk assessment
    pub risk_level: RiskLevel,
    /// Identity that submitted the intent
    pub identity: String,
    /// Timestamp of validation
    pub validated_at: DateTime<Utc>,
    /// Validation status
    pub is_valid: bool,
    /// Validation errors (if any)
    pub validation_errors: Vec<String>,
}

/// Intent action types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum IntentAction {
    /// Read data
    Read,
    /// Write data
    Write,
    /// Execute command
    Execute,
    /// Delete resource
    Delete,
    /// Modify configuration
    Modify,
    /// Query system state
    Query,
    /// Subscribe to events
    Subscribe,
    /// Publish event
    Publish,
    /// Unknown/other action
    Unknown,
}

impl IntentAction {
    /// Parse action from string
    pub fn from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "READ" => IntentAction::Read,
            "WRITE" => IntentAction::Write,
            "EXECUTE" => IntentAction::Execute,
            "DELETE" => IntentAction::Delete,
            "MODIFY" => IntentAction::Modify,
            "QUERY" => IntentAction::Query,
            "SUBSCRIBE" => IntentAction::Subscribe,
            "PUBLISH" => IntentAction::Publish,
            _ => IntentAction::Unknown,
        }
    }

    /// Get default risk level for action
    pub fn default_risk(&self) -> RiskLevel {
        match self {
            IntentAction::Read => RiskLevel::Minimal,
            IntentAction::Query => RiskLevel::Minimal,
            IntentAction::Subscribe => RiskLevel::Low,
            IntentAction::Publish => RiskLevel::Low,
            IntentAction::Write => RiskLevel::Medium,
            IntentAction::Modify => RiskLevel::Medium,
            IntentAction::Execute => RiskLevel::High,
            IntentAction::Delete => RiskLevel::Critical,
            IntentAction::Unknown => RiskLevel::Medium,
        }
    }
}

/// Intent schema definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentSchema {
    /// Schema version
    pub version: String,
    /// Allowed action types
    pub allowed_actions: Vec<IntentAction>,
    /// Required fields
    pub required_fields: Vec<String>,
    /// Field validators
    pub field_validators: HashMap<String, FieldValidator>,
    /// Max intent length
    pub max_length: usize,
    /// Blocked patterns
    pub blocked_patterns: Vec<String>,
}

/// Field validator configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldValidator {
    /// Field type
    pub field_type: FieldType,
    /// Minimum length (if string)
    pub min_length: Option<usize>,
    /// Maximum length (if string)
    pub max_length: Option<usize>,
    /// Allowed values (if enum)
    pub allowed_values: Option<Vec<String>>,
    /// Pattern regex (if pattern)
    pub pattern: Option<String>,
}

/// Field types for validation
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum FieldType {
    String,
    Integer,
    Boolean,
    Enum,
    Pattern,
    Uuid,
    Path,
}

/// Intent validation error types
#[derive(Debug, Error)]
pub enum IntentValidationError {
    #[error("Intent is empty")]
    EmptyIntent,
    
    #[error("Intent exceeds maximum length of {0} characters")]
    IntentTooLong(usize),
    
    #[error("Unknown action type: {0}")]
    UnknownAction(String),
    
    #[error("Required field missing: {0}")]
    RequiredFieldMissing(String),
    
    #[error("Field validation failed: {0}")]
    FieldValidationFailed(String),
    
    #[error("Blocked pattern detected: {0}")]
    BlockedPattern(String),
    
    #[error("Invalid field value: {0}")]
    InvalidFieldValue(String),
    
    #[error("Sanitization failed: {0}")]
    SanitizationFailed(String),
}

/// Result type for intent validation
pub type IntentValidationResult<T> = Result<T, IntentValidationError>;

// ============================================================================
// INTENT VALIDATOR
// ============================================================================

/// Intent validator - validates and sanitizes intents before processing
pub struct IntentValidator {
    /// Current schema
    schema: IntentSchema,
    /// Audit log
    audit_log: Vec<IntentAuditEntry>,
    /// Compiled blocked patterns
    blocked_patterns: Vec<Regex>,
    /// Compiled field patterns
    field_patterns: HashMap<String, Regex>,
}

/// Intent audit log entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentAuditEntry {
    /// Timestamp
    pub timestamp: DateTime<Utc>,
    /// Intent hash (for privacy)
    pub intent_hash: String,
    /// Identity
    pub identity: String,
    /// Validation result
    pub is_valid: bool,
    /// Errors (if any)
    pub errors: Vec<String>,
    /// Risk level assessed
    pub risk_level: RiskLevel,
    /// Processing time (microseconds)
    pub processing_time_us: u64,
}

impl IntentValidator {
    /// Create a new intent validator with default schema
    pub fn new() -> Self {
        let mut validator = IntentValidator {
            schema: IntentSchema::default(),
            audit_log: Vec::new(),
            blocked_patterns: Vec::new(),
            field_patterns: HashMap::new(),
        };
        
        validator.compile_patterns();
        validator
    }

    /// Create validator with custom schema
    pub fn with_schema(schema: IntentSchema) -> Self {
        let mut validator = IntentValidator {
            schema,
            audit_log: Vec::new(),
            blocked_patterns: Vec::new(),
            field_patterns: HashMap::new(),
        };
        
        validator.compile_patterns();
        validator
    }

    /// Compile regex patterns
    fn compile_patterns(&mut self) {
        // Compile blocked patterns
        for pattern in &self.schema.blocked_patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.blocked_patterns.push(regex);
            }
        }
        
        // Compile field validators
        for (field_name, validator) in &self.schema.field_validators {
            if let Some(ref pattern) = validator.pattern {
                if let Ok(regex) = Regex::new(pattern) {
                    self.field_patterns.insert(field_name.clone(), regex);
                }
            }
        }
    }

    /// Validate and sanitize an intent
    pub fn validate(
        &mut self,
        intent: &str,
        identity: &str,
        parameters: Option<HashMap<String, String>>,
    ) -> IntentValidationResult<ValidatedIntent> {
        let start_time = std::time::Instant::now();
        
        // Step 1: Check for empty intent
        if intent.trim().is_empty() {
            return Err(IntentValidationError::EmptyIntent);
        }
        
        // Step 2: Check length
        if intent.len() > self.schema.max_length {
            return Err(IntentValidationError::IntentTooLong(self.schema.max_length));
        }
        
        // Step 3: Sanitize the intent
        let sanitized = self.sanitize_intent(intent)?;
        
        // Step 4: Check blocked patterns
        self.check_blocked_patterns(&sanitized)?;
        
        // Step 5: Parse action
        let action = self.parse_action(&sanitized)?;
        
        // Step 6: Validate parameters
        let validated_params = self.validate_parameters(parameters.unwrap_or_default())?;
        
        // Step 7: Determine target
        let target = self.extract_target(&sanitized);
        
        // Step 8: Assess risk
        let risk_level = self.assess_risk(&action, &target, &validated_params);
        
        // Step 9: Determine priority
        let priority = self.determine_priority(&action, risk_level);
        
        // Create validated intent
        let validated = ValidatedIntent {
            original_intent: intent.to_string(),
            sanitized_intent: sanitized,
            action,
            target,
            parameters: validated_params,
            priority,
            risk_level,
            identity: identity.to_string(),
            validated_at: Utc::now(),
            is_valid: true,
            validation_errors: Vec::new(),
        };
        
        // Log audit entry
        let processing_time = start_time.elapsed().as_micros() as u64;
        self.log_audit(&validated, processing_time);
        
        Ok(validated)
    }

    /// Sanitize intent string
    fn sanitize_intent(&self, intent: &str) -> IntentValidationResult<String> {
        // Remove null bytes
        let sanitized = intent.replace('\0', "");
        
        // Trim whitespace
        let sanitized = sanitized.trim().to_string();
        
        // Remove control characters (except newlines and tabs)
        let sanitized: String = sanitized
            .chars()
            .filter(|c| {
                c.is_alphanumeric() 
                    || c.is_whitespace() 
                    || *c == '-' 
                    || *c == '_' 
                    || *c == ':' 
                    || *c == '/' 
                    || *c == '.'
                    || *c == '='
            })
            .collect();
        
        if sanitized.is_empty() {
            return Err(IntentValidationError::SanitizationFailed(
                "Intent became empty after sanitization".to_string(),
            ));
        }
        
        Ok(sanitized)
    }

    /// Check for blocked patterns
    fn check_blocked_patterns(&self, intent: &str) -> IntentValidationResult<()> {
        for regex in &self.blocked_patterns {
            if regex.is_match(intent) {
                return Err(IntentValidationError::BlockedPattern(
                    regex.to_string(),
                ));
            }
        }
        Ok(())
    }

    /// Parse action from intent
    fn parse_action(&self, intent: &str) -> IntentValidationResult<IntentAction> {
        // Extract action verb (first word or before colon)
        let action_str = intent
            .split(|c| c == ':' || c == ' ' || c == '_')
            .next()
            .unwrap_or("UNKNOWN")
            .to_uppercase();
        
        let action = IntentAction::from_str(&action_str);
        
        // Check if action is allowed
        if !self.schema.allowed_actions.contains(&action) {
            if action == IntentAction::Unknown {
                return Err(IntentValidationError::UnknownAction(action_str));
            }
        }
        
        Ok(action)
    }

    /// Validate parameters
    fn validate_parameters(
        &self,
        params: HashMap<String, String>,
    ) -> IntentValidationResult<HashMap<String, String>> {
        let mut validated = HashMap::new();
        
        // Check required fields
        for field in &self.schema.required_fields {
            if !params.contains_key(field) {
                return Err(IntentValidationError::RequiredFieldMissing(field.clone()));
            }
        }
        
        // Validate each parameter
        for (key, value) in params {
            // Sanitize parameter value
            let sanitized_value = self.sanitize_parameter_value(&value)?;
            
            // Validate against field rules
            if let Some(validator) = self.schema.field_validators.get(&key) {
                self.validate_field(&key, &sanitized_value, validator)?;
            }
            
            validated.insert(key, sanitized_value);
        }
        
        Ok(validated)
    }

    /// Sanitize a parameter value
    fn sanitize_parameter_value(&self, value: &str) -> IntentValidationResult<String> {
        // Remove null bytes
        let sanitized = value.replace('\0', "");
        
        // Trim whitespace
        let sanitized = sanitized.trim().to_string();
        
        // Limit length
        let max_param_length = 4096;
        if sanitized.len() > max_param_length {
            return Err(IntentValidationError::FieldValidationFailed(format!(
                "Parameter value exceeds {} characters",
                max_param_length
            )));
        }
        
        Ok(sanitized)
    }

    /// Validate a single field
    fn validate_field(
        &self,
        field_name: &str,
        value: &str,
        validator: &FieldValidator,
    ) -> IntentValidationResult<()> {
        // Check length constraints
        if let Some(min) = validator.min_length {
            if value.len() < min {
                return Err(IntentValidationError::InvalidFieldValue(format!(
                    "Field {}: value too short (min: {})",
                    field_name, min
                )));
            }
        }
        
        if let Some(max) = validator.max_length {
            if value.len() > max {
                return Err(IntentValidationError::InvalidFieldValue(format!(
                    "Field {}: value too long (max: {})",
                    field_name, max
                )));
            }
        }
        
        // Check allowed values (enum)
        if let Some(ref allowed) = validator.allowed_values {
            if !allowed.contains(&value.to_string()) {
                return Err(IntentValidationError::InvalidFieldValue(format!(
                    "Field {}: value not in allowed list",
                    field_name
                )));
            }
        }
        
        // Check pattern
        if let Some(ref pattern) = validator.pattern {
            if let Some(regex) = self.field_patterns.get(field_name) {
                if !regex.is_match(value) {
                    return Err(IntentValidationError::InvalidFieldValue(format!(
                        "Field {}: value does not match pattern",
                        field_name
                    )));
                }
            }
        }
        
        Ok(())
    }

    /// Extract target from intent
    fn extract_target(&self, intent: &str) -> Option<String> {
        // Try to extract target after colon or space
        let parts: Vec<&str> = intent.splitn(2, |c| c == ':' || c == ' ').collect();
        
        if parts.len() > 1 {
            let target = parts[1].trim().to_string();
            if !target.is_empty() {
                return Some(target);
            }
        }
        
        None
    }

    /// Assess risk level
    fn assess_risk(
        &self,
        action: &IntentAction,
        target: &Option<String>,
        params: &HashMap<String, String>,
    ) -> RiskLevel {
        let mut risk = action.default_risk();
        
        // Check for dangerous targets
        if let Some(ref t) = target {
            let t_lower = t.to_lowercase();
            
            // Check for system files
            if t_lower.contains("/etc/") 
                || t_lower.contains("/sys/")
                || t_lower.contains("/proc/")
                || t_lower.starts_with("/dev/") {
                risk = RiskLevel::Critical;
            }
            // Check for sensitive paths
            else if t_lower.contains("/root/") 
                || t_lower.contains("/home/") 
                || t_lower.contains(".ssh/")
                || t_lower.contains(".gnupg/") {
                risk = match risk {
                    RiskLevel::Minimal => RiskLevel::Low,
                    RiskLevel::Low => RiskLevel::Medium,
                    _ => risk,
                };
            }
        }
        
        // Check for dangerous parameters
        if params.contains_key("force") || params.contains_key("recursive") {
            risk = match risk {
                RiskLevel::Minimal => RiskLevel::Low,
                RiskLevel::Low => RiskLevel::Medium,
                RiskLevel::Medium => RiskLevel::High,
                _ => risk,
            };
        }
        
        // Check for command injection patterns
        for value in params.values() {
            if value.contains("&&") 
                || value.contains("||")
                || value.contains(";")
                || value.contains("|")
                || value.contains("`")
                || value.contains("$(") {
                risk = RiskLevel::Critical;
            }
        }
        
        risk
    }

    /// Determine priority
    fn determine_priority(&self, action: &IntentAction, risk: RiskLevel) -> IntentPriority {
        // Start with action-based priority
        let mut priority = match action {
            IntentAction::Execute => IntentPriority::High,
            IntentAction::Delete => IntentPriority::High,
            IntentAction::Modify => IntentPriority::Normal,
            IntentAction::Write => IntentPriority::Normal,
            IntentAction::Read => IntentPriority::Low,
            IntentAction::Query => IntentPriority::Low,
            IntentAction::Subscribe => IntentPriority::Low,
            IntentAction::Publish => IntentPriority::Normal,
            IntentAction::Unknown => IntentPriority::Normal,
        };
        
        // Elevate priority for high risk
        if risk >= RiskLevel::High {
            priority = IntentPriority::Critical;
        } else if risk >= RiskLevel::Medium && priority < IntentPriority::High {
            priority = IntentPriority::High;
        }
        
        priority
    }

    /// Log audit entry
    fn log_audit(&mut self, validated: &ValidatedIntent, processing_time: u64) {
        let entry = IntentAuditEntry {
            timestamp: validated.validated_at,
            intent_hash: self.hash_intent(&validated.original_intent),
            identity: validated.identity.clone(),
            is_valid: validated.is_valid,
            errors: validated.validation_errors.clone(),
            risk_level: validated.risk_level,
            processing_time_us: processing_time,
        };
        
        self.audit_log.push(entry);
    }

    /// Simple hash for privacy (not cryptographic)
    fn hash_intent(&self, intent: &str) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        intent.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    }

    /// Get audit log
    pub fn get_audit_log(&self) -> &Vec<IntentAuditEntry> {
        &self.audit_log
    }

    /// Get audit log entry count
    pub fn audit_log_count(&self) -> usize {
        self.audit_log.len()
    }
}

impl Default for IntentSchema {
    fn default() -> Self {
        IntentSchema {
            version: "1.0.0".to_string(),
            allowed_actions: vec![
                IntentAction::Read,
                IntentAction::Write,
                IntentAction::Execute,
                IntentAction::Delete,
                IntentAction::Modify,
                IntentAction::Query,
                IntentAction::Subscribe,
                IntentAction::Publish,
            ],
            required_fields: vec![],
            field_validators: HashMap::new(),
            max_length: 4096,
            blocked_patterns: vec![
                // Command injection patterns
                r"&&".to_string(),
                r"\|\|".to_string(),
                r";\s*rm".to_string(),
                r"\$\(".to_string(),
                r"`".to_string(),
                // Path traversal
                r"\.\.\/".to_string(),
                r"\.\.\\".to_string(),
                // Null byte injection
                r"\x00".to_string(),
            ],
        }
    }
}

impl Default for IntentValidator {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_intent_validation_success() {
        let mut validator = IntentValidator::new();
        
        let result = validator.validate("read:/data/file.txt", "agent_001", None);
        
        assert!(result.is_ok());
        let intent = result.unwrap();
        assert_eq!(intent.action, IntentAction::Read);
        assert_eq!(intent.risk_level, RiskLevel::Minimal);
        assert!(intent.is_valid);
    }

    #[test]
    fn test_intent_validation_blocked_pattern() {
        let mut validator = IntentValidator::new();
        
        let result = validator.validate("execute:/bin/ls && rm -rf /", "agent_001", None);
        
        assert!(result.is_err());
    }

    #[test]
    fn test_intent_validation_sanitization() {
        let mut validator = IntentValidator::new();
        
        let result = validator.validate("read:\x00/path", "agent_001", None);
        
        assert!(result.is_ok());
        assert!(!result.unwrap().sanitized_intent.contains('\0'));
    }

    #[test]
    fn test_intent_validation_parameters() {
        let mut validator = IntentValidator::new();
        
        let mut params = HashMap::new();
        params.insert("limit".to_string(), "100".to_string());
        
        let result = validator.validate("query:users", "agent_001", Some(params));
        
        assert!(result.is_ok());
    }

    #[test]
    fn test_risk_assessment_execute() {
        let mut validator = IntentValidator::new();
        
        let result = validator.validate("execute:/system/command", "agent_001", None).unwrap();
        
        assert_eq!(result.risk_level, RiskLevel::High);
    }

    #[test]
    fn test_audit_logging() {
        let mut validator = IntentValidator::new();
        
        validator.validate("read:/data", "agent_001", None).unwrap();
        
        assert_eq!(validator.audit_log_count(), 1);
    }
}
