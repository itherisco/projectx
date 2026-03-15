//! WASM Decision Operators
//!
//! This module provides a WASM runtime for executing decision operators
//! in a sandboxed environment.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// WASM Module errors
#[derive(Debug)]
pub enum WasmError {
    #[error("Compilation error: {0}")]
    CompilationError(String),
    #[error("Runtime error: {0}")]
    RuntimeError(String),
    #[error("Instantiation error: {0}")]
    InstantiationError(String),
    #[error("Function not found: {0}")]
    FunctionNotFound(String),
    #[error("Memory error: {0}")]
    MemoryError(String),
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}

/// WASM execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WasmResult {
    pub success: bool,
    pub output: Vec<u8>,
    pub error: Option<String>,
    pub execution_time_ms: u64,
}

/// Decision operator interface
pub trait DecisionOperator: Send + Sync {
    /// Get operator name
    fn name(&self) -> &str;
    
    /// Get operator version
    fn version(&self) -> &str;
    
    /// Execute the operator
    fn execute(&self, input: &[u8]) -> Result<Vec<u8>, WasmError>;
    
    /// Validate input
    fn validate_input(&self, input: &[u8]) -> bool;
}

/// WASM Runtime configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WasmConfig {
    /// Maximum memory pages
    pub max_memory_pages: u32,
    /// Maximum execution time in milliseconds
    pub max_execution_time_ms: u64,
    /// Enable debugging
    pub debug: bool,
    /// WASM boundary stack size
    pub stack_size: u32,
}

impl Default for WasmConfig {
    fn default() -> Self {
        WasmConfig {
            max_memory_pages: 256, // 16MB
            max_execution_time_ms: 1000,
            debug: false,
            stack_size: 1 << 20, // 1MB
        }
    }
}

/// Operator manifest
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorManifest {
    pub name: String,
    pub version: String,
    pub description: String,
    pub entry_point: String,
    pub memory_pages: u32,
    pub input_schema: Option<String>,
    pub output_schema: Option<String>,
}

/// WASM Operator Registry
pub struct OperatorRegistry {
    operators: RwLock<HashMap<String, Arc<dyn DecisionOperator>>>,
    manifests: RwLock<HashMap<String, OperatorManifest>>,
}

impl OperatorRegistry {
    /// Create a new registry
    pub fn new() -> Self {
        OperatorRegistry {
            operators: RwLock::new(HashMap::new()),
            manifests: RwLock::new(HashMap::new()),
        }
    }

    /// Register an operator
    pub fn register(&self, manifest: OperatorManifest, operator: Arc<dyn DecisionOperator>) -> Result<(), WasmError> {
        let name = manifest.name.clone();
        
        let mut operators = self.operators.write().unwrap();
        operators.insert(name.clone(), operator);
        
        let mut manifests = self.manifests.write().unwrap();
        manifests.insert(name, manifest);
        
        Ok(())
    }

    /// Get an operator
    pub fn get(&self, name: &str) -> Option<Arc<dyn DecisionOperator>> {
        let operators = self.operators.read().unwrap();
        operators.get(name).cloned()
    }

    /// Get operator manifest
    pub fn get_manifest(&self, name: &str) -> Option<OperatorManifest> {
        let manifests = self.manifests.read().unwrap();
        manifests.get(name).cloned()
    }

    /// List all operators
    pub fn list_operators(&self) -> Vec<String> {
        let operators = self.operators.read().unwrap();
        operators.keys().cloned().collect()
    }

    /// Unregister an operator
    pub fn unregister(&self, name: &str) -> Result<(), WasmError> {
        let mut operators = self.operators.write().unwrap();
        let mut manifests = self.manifests.write().unwrap();
        
        operators.remove(name);
        manifests.remove(name);
        
        Ok(())
    }
}

impl Default for OperatorRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Decision context for operator execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionContext {
    /// Agent ID
    pub agent_id: String,
    /// Task ID
    pub task_id: String,
    /// Timestamp
    pub timestamp: i64,
    /// Security level
    pub security_level: SecurityLevel,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum SecurityLevel {
    Untrusted,
    Trusted,
    Privileged,
}

/// Decision result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decision {
    pub decision_id: String,
    pub operator_name: String,
    pub context: DecisionContext,
    pub input: Vec<u8>,
    pub output: Vec<u8>,
    pub approved: bool,
    pub timestamp: i64,
    pub execution_time_ms: u64,
}

/// Simple decision engine
pub struct DecisionEngine {
    registry: Arc<OperatorRegistry>,
    decisions: RwLock<Vec<Decision>>,
    config: WasmConfig,
}

impl DecisionEngine {
    /// Create a new decision engine
    pub fn new(config: WasmConfig) -> Self {
        DecisionEngine {
            registry: Arc::new(OperatorRegistry::new()),
            decisions: RwLock::new(Vec::new()),
            config,
        }
    }

    /// Get the registry
    pub fn registry(&self) -> &Arc<OperatorRegistry> {
        &self.registry
    }

    /// Make a decision
    pub fn decide(&self, operator_name: &str, context: DecisionContext, input: Vec<u8>) -> Result<Decision, WasmError> {
        let start = std::time::Instant::now();
        
        // Get operator
        let operator = self.registry.get(operator_name)
            .ok_or_else(|| WasmError::FunctionNotFound(operator_name.to_string()))?;
        
        // Validate input
        if !operator.validate_input(&input) {
            return Err(WasmError::RuntimeError("Invalid input".to_string()));
        }
        
        // Execute
        let output = operator.execute(&input)?;
        
        let execution_time = start.elapsed().as_millis() as u64;
        
        // Check time limit
        if execution_time > self.config.max_execution_time_ms {
            return Err(WasmError::RuntimeError("Execution timeout".to_string()));
        }
        
        // Create decision record
        let decision = Decision {
            decision_id: uuid::Uuid::new_v4().to_string(),
            operator_name: operator_name.to_string(),
            context: context.clone(),
            input: input.clone(),
            output: output.clone(),
            approved: true,
            timestamp: chrono::Utc::now().timestamp(),
            execution_time_ms: execution_time,
        };
        
        // Store decision
        {
            let mut decisions = self.decisions.write().unwrap();
            decisions.push(decision.clone());
        }
        
        Ok(decision)
    }

    /// Get decision history
    pub fn get_decisions(&self, limit: Option<usize>) -> Vec<Decision> {
        let decisions = self.decisions.read().unwrap();
        let limit = limit.unwrap_or(decisions.len());
        decisions.iter().rev().take(limit).cloned().collect()
    }

    /// Get decisions for an agent
    pub fn get_agent_decisions(&self, agent_id: &str) -> Vec<Decision> {
        let decisions = self.decisions.read().unwrap();
        decisions
            .iter()
            .filter(|d| d.context.agent_id == agent_id)
            .cloned()
            .collect()
    }
}

/// Mock WASM operator for testing
pub struct MockOperator {
    name: String,
    version: String,
    should_succeed: bool,
}

impl MockOperator {
    pub fn new(name: &str, version: &str, should_succeed: bool) -> Self {
        MockOperator {
            name: name.to_string(),
            version: version.to_string(),
            should_succeed,
        }
    }
}

impl DecisionOperator for MockOperator {
    fn name(&self) -> &str {
        &self.name
    }

    fn version(&self) -> &str {
        &self.version
    }

    fn execute(&self, input: &[u8]) -> Result<Vec<u8>, WasmError> {
        if self.should_succeed {
            // Echo back input with success marker
            let mut output = vec![0x01]; // Success
            output.extend_from_slice(input);
            Ok(output)
        } else {
            Err(WasmError::RuntimeError("Mock failure".to_string()))
        }
    }

    fn validate_input(&self, input: &[u8]) -> bool {
        // Accept any input
        !input.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_operator_registry() {
        let registry = OperatorRegistry::new();
        
        let manifest = OperatorManifest {
            name: "test-operator".to_string(),
            version: "1.0.0".to_string(),
            description: "Test operator".to_string(),
            entry_point: "test".to_string(),
            memory_pages: 64,
            input_schema: None,
            output_schema: None,
        };
        
        let operator = Arc::new(MockOperator::new("test-operator", "1.0.0", true));
        
        registry.register(manifest, operator).unwrap();
        
        let retrieved = registry.get("test-operator");
        assert!(retrieved.is_some());
        
        let manifest = registry.get_manifest("test-operator");
        assert!(manifest.is_some());
    }

    #[test]
    fn test_decision_engine() {
        let config = WasmConfig::default();
        let engine = DecisionEngine::new(config);
        
        // Register an operator
        let manifest = OperatorManifest {
            name: "decision-op".to_string(),
            version: "1.0.0".to_string(),
            description: "Decision operator".to_string(),
            entry_point: "decide".to_string(),
            memory_pages: 64,
            input_schema: None,
            output_schema: None,
        };
        
        let operator = Arc::new(MockOperator::new("decision-op", "1.0.0", true));
        engine.registry().register(manifest, operator).unwrap();
        
        // Make a decision
        let context = DecisionContext {
            agent_id: "agent-001".to_string(),
            task_id: "task-001".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            security_level: SecurityLevel::Trusted,
            metadata: HashMap::new(),
        };
        
        let input = b"test input";
        let decision = engine.decide("decision-op", context, input.to_vec()).unwrap();
        
        assert!(decision.approved);
        assert!(decision.output.starts_with(&[0x01]));
    }

    #[test]
    fn test_mock_operator() {
        let op = MockOperator::new("mock", "1.0.0", true);
        
        assert_eq!(op.name(), "mock");
        assert_eq!(op.version(), "1.0.0");
        
        let result = op.execute(b"test");
        assert!(result.is_ok());
        
        let op_fail = MockOperator::new("mock-fail", "1.0.0", false);
        let result = op_fail.execute(b"test");
        assert!(result.is_err());
    }

    #[test]
    fn test_decision_history() {
        let config = WasmConfig::default();
        let engine = DecisionEngine::new(config);
        
        // Register operator
        let manifest = OperatorManifest {
            name: "history-op".to_string(),
            version: "1.0.0".to_string(),
            description: "History operator".to_string(),
            entry_point: "run".to_string(),
            memory_pages: 64,
            input_schema: None,
            output_schema: None,
        };
        
        let operator = Arc::new(MockOperator::new("history-op", "1.0.0", true));
        engine.registry().register(manifest, operator).unwrap();
        
        // Make multiple decisions
        for i in 0..5 {
            let context = DecisionContext {
                agent_id: format!("agent-{:03}", i),
                task_id: format!("task-{:03}", i),
                timestamp: chrono::Utc::now().timestamp(),
                security_level: SecurityLevel::Trusted,
                metadata: HashMap::new(),
            };
            
            let _ = engine.decide("history-op", context, vec![i as u8]);
        }
        
        let history = engine.get_decisions(Some(3));
        assert_eq!(history.len(), 3);
    }

    #[test]
    fn test_wasm_config() {
        let config = WasmConfig::default();
        
        assert_eq!(config.max_memory_pages, 256);
        assert_eq!(config.max_execution_time_ms, 1000);
        assert!(!config.debug);
    }
}
