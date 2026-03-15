//! # Capability Registry
//!
//! JSON-based capability registry for dynamic loading and configuration.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Capability registry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityRegistry {
    pub version: String,
    pub capabilities: HashMap<String, CapabilityConfig>,
}

impl Default for CapabilityRegistry {
    fn default() -> Self {
        Self {
            version: "1.0".to_string(),
            capabilities: HashMap::new(),
        }
    }
}

/// Individual capability configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CapabilityConfig {
    pub name: String,
    pub enabled: bool,
    pub timeout_secs: Option<u64>,
    pub config: Option<serde_json::Value>,
}

impl CapabilityRegistry {
    /// Load registry from JSON file
    pub fn load(path: &Path) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let content = std::fs::read_to_string(path)?;
        let registry: CapabilityRegistry = serde_json::from_str(&content)?;
        Ok(registry)
    }

    /// Save registry to JSON file
    pub fn save(&self, path: &Path) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }

    /// Get enabled capabilities
    pub fn enabled_capabilities(&self) -> Vec<&CapabilityConfig> {
        self.capabilities
            .values()
            .filter(|c| c.enabled)
            .collect()
    }
}
