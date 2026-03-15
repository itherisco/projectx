//! # Pattern Detector
//!
//! Detects patterns over memory embeddings and behavior data.

use crate::proactive::Confidence;
use serde::{Deserialize, Serialize};
use tracing::debug;

/// Pattern types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PatternType {
    Temporal,
    Spatial,
    Behavioral,
    Sequential,
    Seasonal,
    Custom(String),
}

/// Detected pattern
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pattern {
    pub id: uuid::Uuid,
    pub pattern_type: PatternType,
    pub description: String,
    pub confidence: Confidence,
    pub related_entities: Vec<uuid::Uuid>,
    pub occurrences: usize,
    pub first_seen: chrono::DateTime<chrono::Utc>,
    pub last_seen: chrono::DateTime<chrono::Utc>,
}

/// Pattern detector
pub struct PatternDetector {
    min_confidence: f32,
}

impl PatternDetector {
    pub fn new() -> Self {
        Self {
            min_confidence: 0.5,
        }
    }

    /// Detect patterns in memory items
    pub async fn detect_patterns(&self, memory_items: &[serde_json::Value]) -> Result<Vec<Pattern>, Box<dyn std::error::Error + Send + Sync>> {
        debug!("Detecting patterns in {} memory items", memory_items.len());
        
        let mut patterns = Vec::new();
        
        // Simple pattern detection - in production would use ML
        if memory_items.len() >= 3 {
            // Detect temporal pattern
            patterns.push(Pattern {
                id: uuid::Uuid::new_v4(),
                pattern_type: PatternType::Temporal,
                description: "Temporal pattern detected in memory".to_string(),
                confidence: Confidence(0.7),
                related_entities: Vec::new(),
                occurrences: memory_items.len(),
                first_seen: chrono::Utc::now(),
                last_seen: chrono::Utc::now(),
            });
        }

        Ok(patterns)
    }

    /// Detect sequential patterns
    pub async fn detect_sequential(&self, sequence: &[serde_json::Value]) -> Result<Vec<Pattern>, Box<dyn std::error::Error + Send + Sync>> {
        let mut patterns = Vec::new();
        
        if sequence.len() >= 2 {
            patterns.push(Pattern {
                id: uuid::Uuid::new_v4(),
                pattern_type: PatternType::Sequential,
                description: "Sequential pattern detected".to_string(),
                confidence: Confidence(0.6),
                related_entities: Vec::new(),
                occurrences: sequence.len(),
                first_seen: chrono::Utc::now(),
                last_seen: chrono::Utc::now(),
            });
        }
        
        Ok(patterns)
    }

    /// Detect behavioral patterns
    pub async fn detect_behavioral(&self, behaviors: &[serde_json::Value]) -> Result<Vec<Pattern>, Box<dyn std::error::Error + Send + Sync>> {
        let mut patterns = Vec::new();
        
        if !behaviors.is_empty() {
            patterns.push(Pattern {
                id: uuid::Uuid::new_v4(),
                pattern_type: PatternType::Behavioral,
                description: "Behavioral pattern detected".to_string(),
                confidence: Confidence(0.65),
                related_entities: Vec::new(),
                occurrences: behaviors.len(),
                first_seen: chrono::Utc::now(),
                last_seen: chrono::Utc::now(),
            });
        }
        
        Ok(patterns)
    }
}

impl Default for PatternDetector {
    fn default() -> Self {
        Self::new()
    }
}
