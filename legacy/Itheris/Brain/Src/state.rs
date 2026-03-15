//! Global State Management with tamper-evident snapshots

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use sha2::{Digest, Sha256};
use chrono::Local;

/// A snapshot of the system state
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StateSnapshot {
    pub timestamp: String,
    pub version: u32,
    pub data: HashMap<String, Value>,
    pub hash: String,
    pub parent_hash: String,
}

/// Global state manager with cryptographic chain
pub struct GlobalState {
    snapshots: Vec<StateSnapshot>,
    current_state: HashMap<String, Value>,
}

impl GlobalState {
    pub fn new() -> Self {
        GlobalState {
            snapshots: Vec::new(),
            current_state: HashMap::new(),
        }
    }

    /// Compute cryptographic hash of state
    fn compute_hash(state: &HashMap<String, Value>) -> String {
        let canonical = serde_json::to_string(&state)
            .expect("Failed to serialize state");
        let mut hasher = Sha256::new();
        hasher.update(canonical.as_bytes());
        hex::encode(hasher.finalize())
    }

    /// Snapshot current state (immutable checkpoint)
    pub fn snapshot(&mut self) -> StateSnapshot {
        let hash = Self::compute_hash(&self.current_state);
        let parent_hash = self
            .snapshots
            .last()
            .map(|s| s.hash.clone())
            .unwrap_or_else(|| "GENESIS".to_string());

        let snapshot = StateSnapshot {
            timestamp: Local::now().to_rfc3339(),
            version: self.snapshots.len() as u32,
            data: self.current_state.clone(),
            hash,
            parent_hash,
        };

        self.snapshots.push(snapshot.clone());
        println!("[STATE] ✓ Snapshot taken (version: {})", snapshot.version);

        snapshot
    }

    /// Update state with evidence
    pub fn update(&mut self, key: &str, value: Value, reason: &str) {
        self.current_state.insert(key.to_string(), value);
        println!("[STATE] ✓ Updated '{}': {}", key, reason);
    }

    /// Get state value with proof of origin
    pub fn get_with_proof(&self, key: &str) -> Option<(Value, String)> {
        self.current_state.get(key).map(|v| {
            let snapshot = self.snapshots.last().unwrap();
            (v.clone(), snapshot.hash.clone())
        })
    }

    /// Verify state integrity (detect tampering)
    pub fn verify_integrity(&self) -> bool {
        for (i, snapshot) in self.snapshots.iter().enumerate() {
            let computed_hash = Self::compute_hash(&snapshot.data);
            if computed_hash != snapshot.hash {
                println!("[STATE] ✗ Tampering detected at version {}", i);
                return false;
            }

            // Verify chain
            if i > 0 {
                if snapshot.parent_hash != self.snapshots[i - 1].hash {
                    println!("[STATE] ✗ Chain break at version {}", i);
                    return false;
                }
            }
        }

        println!("[STATE] ✓ Integrity verified ({} snapshots)", self.snapshots.len());
        true
    }

    pub fn get_snapshots(&self) -> &Vec<StateSnapshot> {
        &self.snapshots
    }

    pub fn get_current_state(&self) -> &HashMap<String, Value> {
        &self.current_state
    }

    pub fn snapshot_count(&self) -> usize {
        self.snapshots.len()
    }
}

impl Default for GlobalState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_state_integrity() {
        let mut state = GlobalState::new();
        state.update("key", serde_json::json!("value"), "test");
        state.snapshot();
        
        assert!(state.verify_integrity());
    }
}