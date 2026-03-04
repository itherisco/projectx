//! # Capability Manager - Tool Registry and Execution
//!
//! Manages capability registration, auto-loading, and execution with Kernel approval.

use crate::capabilities::{Capability, CapabilityError, CapabilityMetadata, ApprovalToken};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, error, debug, warn};

/// Capability registry entry
struct RegistryEntry {
    capability: Box<dyn Capability>,
    metadata: CapabilityMetadata,
}

/// Capability manager - manages tool registration and execution
pub struct CapabilityManager {
    capabilities: Arc<RwLock<HashMap<String, RegistryEntry>>>,
    #[allow(dead_code)]
    registry_path: Option<String>,
}

impl CapabilityManager {
    /// Create new capability manager
    pub async fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let manager = Self {
            capabilities: Arc::new(RwLock::new(HashMap::new())),
            registry_path: None,
        };
        
        // Auto-load capabilities from default directory
        manager.auto_load_capabilities().await?;
        
        Ok(manager)
    }

    /// Create new capability manager with custom registry path
    pub async fn with_path(registry_path: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let manager = Self {
            capabilities: Arc::new(RwLock::new(HashMap::new())),
            registry_path: Some(registry_path.to_string()),
        };
        
        manager.auto_load_capabilities().await?;
        
        Ok(manager)
    }

    /// Register a capability
    pub async fn register<C: Capability + 'static>(&self, capability: C) -> Result<(), CapabilityError> {
        let name = capability.name().to_string();
        let metadata = CapabilityMetadata::from(&capability);
        
        let mut capabilities = self.capabilities.write().await;
        
        if capabilities.contains_key(&name) {
            warn!("Capability '{}' already registered, overwriting", name);
        }
        
        capabilities.insert(name, RegistryEntry {
            capability: Box::new(capability),
            metadata,
        });
        
        info!("Registered capability: {}", name);
        Ok(())
    }

    /// Unregister a capability
    pub async fn unregister(&self, name: &str) -> Result<(), CapabilityError> {
        let mut capabilities = self.capabilities.write().await;
        
        if capabilities.remove(name).is_some() {
            info!("Unregistered capability: {}", name);
            Ok(())
        } else {
            Err(CapabilityError::NotFound)
        }
    }

    /// Get capability metadata
    pub async fn get_metadata(&self, name: &str) -> Result<CapabilityMetadata, CapabilityError> {
        let capabilities = self.capabilities.read().await;
        
        capabilities
            .get(name)
            .map(|entry| entry.metadata.clone())
            .ok_or(CapabilityError::NotFound)
    }

    /// List all capability names
    pub async fn list_capabilities(&self) -> Vec<String> {
        let capabilities = self.capabilities.read().await;
        capabilities.keys().cloned().collect()
    }

    /// List all capability metadata
    pub async fn list_metadata(&self) -> Vec<CapabilityMetadata> {
        let capabilities = self.capabilities.read().await;
        capabilities.values().map(|entry| entry.metadata.clone()).collect()
    }

    /// Execute a capability with approval
    pub async fn execute(
        &self,
        name: &str,
        input: serde_json::Value,
        approval: &ApprovalToken,
    ) -> Result<serde_json::Value, CapabilityError> {
        let capabilities = self.capabilities.read().await;
        
        let entry = capabilities
            .get(name)
            .ok_or(CapabilityError::NotFound)?;
        
        // Execute the capability
        entry.capability.execute(input, approval).await
    }

    /// Health check - verify all capabilities are operational
    pub async fn health_check(&self) -> bool {
        let capabilities = self.capabilities.read().await;
        
        // Simple health check - just verify we have capabilities loaded
        !capabilities.is_empty()
    }

    /// Auto-load capabilities from directory
    async fn auto_load_capabilities(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // In a real implementation, this would dynamically load capabilities
        // from a plugins directory. For now, we register built-in capabilities.
        
        info!("Auto-loading capabilities...");
        
        // Note: Built-in capabilities would be registered here with feature flags
        // Example:
        // #[cfg(feature = "calendar")]
        // self.register(calendar::CalendarCapability::new()).await?;

        let count = self.capabilities.read().await.len();
        info!("Loaded {} capabilities", count);
        
        Ok(())
    }
}

/// Configuration for capability execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionConfig {
    /// Default timeout in seconds
    pub default_timeout_secs: u64,
    /// Maximum retries on failure
    pub max_retries: u32,
    /// Enable sandbox for all executions
    pub sandbox_by_default: bool,
}

impl Default for ExecutionConfig {
    fn default() -> Self {
        Self {
            default_timeout_secs: 30,
            max_retries: 0,
            sandbox_by_default: true,
        }
    }
}

/// Load capabilities from a directory (stub for dynamic loading)
pub async fn load_from_directory(_path: &std::path::Path) -> Result<Vec<Box<dyn Capability>>, Box<dyn std::error::Error + Send + Sync>> {
    // This would be implemented with dynamic library loading (libloading)
    // For now, return empty list
    Ok(Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    // Test capability
    struct TestCapability;
    
    impl Capability for TestCapability {
        fn name(&self) -> &'static str {
            "test"
        }
        
        fn schema(&self) -> serde_json::Value {
            json!({
                "type": "object",
                "properties": {
                    "value": { "type": "string" }
                },
                "required": ["value"]
            })
        }
        
        async fn execute(&self, input: serde_json::Value, _approval: &ApprovalToken) -> Result<serde_json::Value, CapabilityError> {
            Ok(input)
        }
    }

    #[tokio::test]
    async fn test_register_capability() {
        let manager = CapabilityManager::new().await.unwrap();
        manager.register(TestCapability).await.unwrap();
        
        let names = manager.list_capabilities().await;
        assert!(names.contains(&"test".to_string()));
    }

    #[tokio::test]
    async fn test_execute_capability() {
        let manager = CapabilityManager::new().await.unwrap();
        manager.register(TestCapability).await.unwrap();
        
        let approval = ApprovalToken::new(
            uuid::Uuid::new_v4(),
            vec!["test".to_string()],
            60
        );
        
        let result = manager.execute("test", json!({"value": "hello"}), &approval).await;
        assert!(result.is_ok());
    }
}
