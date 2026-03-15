//! # Capabilities - Tool Abstraction Trait
//!
//! Defines the base capability trait for all tools in JARVIS.
//! All execution requires Kernel approval token.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Capability error types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CapabilityError {
    /// Execution requires approval
    RequiresApproval,
    /// Schema validation failed
    SchemaValidationFailed(String),
    /// Execution timeout
    Timeout,
    /// Execution failed
    ExecutionFailed(String),
    /// Tool not found
    NotFound,
    /// Invalid input
    InvalidInput(String),
    /// Sandbox violation
    SandboxViolation,
}

impl std::fmt::Display for CapabilityError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CapabilityError::RequiresApproval => write!(f, "Kernel approval required"),
            CapabilityError::SchemaValidationFailed(msg) => write!(f, "Schema validation failed: {}", msg),
            CapabilityError::Timeout => write!(f, "Execution timed out"),
            CapabilityError::ExecutionFailed(msg) => write!(f, "Execution failed: {}", msg),
            CapabilityError::NotFound => write!(f, "Capability not found"),
            CapabilityError::InvalidInput(msg) => write!(f, "Invalid input: {}", msg),
            CapabilityError::SandboxViolation => write!(f, "Sandbox security violation"),
        }
    }
}

impl std::error::Error for CapabilityError {}

/// Kernel approval token - required for all capability execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalToken {
    pub token_id: uuid::Uuid,
    pub user_id: uuid::Uuid,
    pub capabilities: Vec<String>,
    pub expires_at: chrono::DateTime<chrono::Utc>,
    pub issued_at: chrono::DateTime<chrono::Utc>,
}

impl ApprovalToken {
    /// Create new approval token
    pub fn new(user_id: uuid::Uuid, capabilities: Vec<String>, validity_secs: i64) -> Self {
        let now = chrono::Utc::now();
        Self {
            token_id: uuid::Uuid::new_v4(),
            user_id,
            capabilities,
            expires_at: now + chrono::Duration::seconds(validity_secs),
            issued_at: now,
        }
    }

    /// Check if token is valid
    pub fn is_valid(&self) -> bool {
        chrono::Utc::now() < self.expires_at
    }

    /// Check if token allows a specific capability
    pub fn allows(&self, capability: &str) -> bool {
        self.is_valid() && (self.capabilities.contains(&capability.to_string()) || self.capabilities.contains(&"*".to_string()))
    }
}

/// Base capability trait for all tools
#[async_trait]
pub trait Capability: Send + Sync {
    /// Unique capability name
    fn name(&self) -> &'static str;

    /// JSON schema for input validation
    fn schema(&self) -> Value;

    /// Execute capability with approved input
    async fn execute(&self, input: Value, approval: &ApprovalToken) -> Result<Value, CapabilityError>;

    /// Get capability description
    fn description(&self) -> &str {
        ""
    }

    /// Get capability category
    fn category(&self) -> &str {
        "general"
    }

    /// Get timeout for execution (default 30 seconds)
    fn timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(30)
    }

    /// Check if capability requires sandbox
    fn requires_sandbox(&self) -> bool {
        false
    }

    /// Validate input against schema
    fn validate_input(&self, input: &Value) -> Result<(), CapabilityError> {
        let schema = self.schema();
        
        // Basic JSON schema validation
        if let Some(required_fields) = schema.get("required").and_then(|v| v.as_array()) {
            let obj = input.as_object().ok_or_else(|| 
                CapabilityError::InvalidInput("Expected object".to_string())
            )?;
            
            for field in required_fields {
                let field_name = field.as_str().ok_or_else(|| 
                    CapabilityError::InvalidInput("Invalid schema".to_string())
                )?;
                
                if !obj.contains_key(field_name) {
                    return Err(CapabilityError::SchemaValidationFailed(
                        format!("Missing required field: {}", field_name)
                    ));
                }
            }
        }
        
        Ok(())
    }
}

/// Metadata about a capability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityMetadata {
    pub name: String,
    pub description: String,
    pub category: String,
    pub schema: Value,
    pub timeout_secs: u64,
    pub requires_sandbox: bool,
}

impl<T: Capability> From<&T> for CapabilityMetadata {
    fn from(cap: &T) -> Self {
        Self {
            name: cap.name().to_string(),
            description: cap.description().to_string(),
            category: cap.category().to_string(),
            schema: cap.schema(),
            timeout_secs: cap.timeout().as_secs(),
            requires_sandbox: cap.requires_sandbox(),
        }
    }
}

/// Wrapper for executing capabilities with timeout and error handling
pub async fn execute_with_timeout<C: Capability>(
    cap: &C,
    input: Value,
    approval: &ApprovalToken,
) -> Result<Value, CapabilityError> {
    // Validate input first
    cap.validate_input(&input)?;

    // Check approval
    if !approval.allows(cap.name()) {
        return Err(CapabilityError::RequiresApproval);
    }

    // Execute with timeout
    tokio::time::timeout(
        cap.timeout(),
        cap.execute(input, approval)
    )
    .await
    .map_err(|_| CapabilityError::Timeout)?
}
