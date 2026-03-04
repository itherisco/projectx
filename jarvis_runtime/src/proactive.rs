//! # Proactive Intelligence Engine
//!
//! Pattern detection, preference inference, and scheduled reasoning for proactive suggestions.

use crate::inference::{InferenceEngine, InferenceResult};
use crate::pattern_detector::{Pattern, PatternDetector};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, debug};

/// Confidence level for suggestions
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Confidence(f32);

impl Confidence {
    pub fn new(value: f32) -> Self {
        Self(value.clamp(0.0, 1.0))
    }

    pub fn value(&self) -> f32 {
        self.0
    }

    pub fn is_high(&self) -> bool {
        self.0 >= 0.8
    }

    pub fn is_medium(&self) -> bool {
        self.0 >= 0.5 && self.0 < 0.8
    }

    pub fn is_low(&self) -> bool {
        self.0 < 0.5
    }
}

impl Default for Confidence {
    fn default() -> Self {
        Self(0.5)
    }
}

/// Proactive suggestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Suggestion {
    /// Unique ID
    pub id: uuid::Uuid,
    /// Suggestion type
    pub suggestion_type: SuggestionType,
    /// Human-readable message
    pub message: String,
    /// Confidence score
    pub confidence: Confidence,
    /// Related entities/context
    pub context: Vec<uuid::Uuid>,
    /// Action to take (if auto-executable)
    pub suggested_action: Option<SuggestedAction>,
    /// When the suggestion was generated
    pub generated_at: chrono::DateTime<chrono::Utc>,
    /// Whether this has been presented to user
    pub presented: bool,
    /// Whether user acted on this
    pub acted_upon: Option<bool>,
    /// Inference provenance
    pub provenance: String,
}

/// Suggestion types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SuggestionType {
    TaskReminder,
    PatternSuggestion,
    PreferenceLearning,
    ProactiveHelp,
    ResourceOptimization,
    SecurityAlert,
}

/// Suggested action
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedAction {
    pub action_type: String,
    pub capability: String,
    pub parameters: serde_json::Value,
}

/// Proactive engine
pub struct ProactiveEngine {
    pattern_detector: Arc<PatternDetector>,
    inference_engine: Arc<InferenceEngine>,
    suggestions: Arc<RwLock<Vec<Suggestion>>>,
    enabled: Arc<RwLock<bool>>,
}

impl ProactiveEngine {
    /// Create new proactive engine
    pub fn new() -> Self {
        Self {
            pattern_detector: Arc::new(PatternDetector::new()),
            inference_engine: Arc::new(InferenceEngine::new()),
            suggestions: Arc::new(RwLock::new(Vec::new())),
            enabled: Arc::new(RwLock::new(true)),
        }
    }

    /// Enable/disable proactive suggestions
    pub async fn set_enabled(&self, enabled: bool) {
        let mut e = self.enabled.write().await;
        *e = enabled;
    }

    /// Check if enabled
    pub async fn is_enabled(&self) -> bool {
        *self.enabled.read().await
    }

    /// Analyze memory for patterns
    pub async fn analyze_patterns(&self, memory_items: &[serde_json::Value]) -> Result<Vec<Pattern>, Box<dyn std::error::Error + Send + Sync>> {
        self.pattern_detector.detect_patterns(memory_items).await
    }

    /// Run inference on user behavior
    pub async fn run_inference(&self, context: &serde_json::Value) -> Result<InferenceResult, Box<dyn std::error::Error + Send + Sync>> {
        self.inference_engine.infer(context).await
    }

    /// Generate suggestions based on patterns and inferences
    pub async fn generate_suggestions(
        &self,
        patterns: Vec<Pattern>,
        inferences: Vec<InferenceResult>,
    ) -> Vec<Suggestion> {
        let mut suggestions = Vec::new();

        // Generate task reminders from patterns
        for pattern in patterns {
            if let Some(suggestion) = self.pattern_to_suggestion(pattern).await {
                suggestions.push(suggestion);
            }
        }

        // Generate preference suggestions from inferences
        for inference in inferences {
            if let Some(suggestion) = self.inference_to_suggestion(inference).await {
                suggestions.push(suggestion);
            }
        }

        // Store suggestions
        let mut stored = self.suggestions.write().await;
        *stored = suggestions.clone();

        info!("Generated {} suggestions", suggestions.len());
        suggestions
    }

    /// Convert pattern to suggestion
    async fn pattern_to_suggestion(&self, pattern: Pattern) -> Option<Suggestion> {
        if pattern.confidence.0 < 0.5 {
            return None;
        }

        Some(Suggestion {
            id: uuid::Uuid::new_v4(),
            suggestion_type: SuggestionType::PatternSuggestion,
            message: format!("Detected pattern: {}", pattern.pattern_type),
            confidence: Confidence::new(pattern.confidence.0 * 0.8),
            context: pattern.related_entities,
            suggested_action: None,
            generated_at: chrono::Utc::now(),
            presented: false,
            acted_upon: None,
            provenance: format!("PatternDetector:{}", pattern.id),
        })
    }

    /// Convert inference to suggestion
    async fn inference_to_suggestion(&self, inference: InferenceResult) -> Option<Suggestion> {
        if inference.confidence.0 < 0.5 {
            return None;
        }

        Some(Suggestion {
            id: uuid::Uuid::new_v4(),
            suggestion_type: SuggestionType::PreferenceLearning,
            message: inference.description.clone(),
            confidence: Confidence::new(inference.confidence.0 * 0.7),
            context: inference.evidence.clone(),
            suggested_action: None,
            generated_at: chrono::Utc::now(),
            presented: false,
            acted_upon: None,
            provenance: format!("InferenceEngine:{}", inference.id),
        })
    }

    /// Get pending suggestions
    pub async fn get_pending_suggestions(&self) -> Vec<Suggestion> {
        let suggestions = self.suggestions.read().await;
        suggestions.iter()
            .filter(|s| !s.presented)
            .cloned()
            .collect()
    }

    /// Mark suggestion as presented
    pub async fn mark_presented(&self, suggestion_id: uuid::Uuid) {
        let mut suggestions = self.suggestions.write().await;
        if let Some(s) = suggestions.iter_mut().find(|s| s.id == suggestion_id) {
            s.presented = true;
        }
    }

    /// Mark suggestion as acted upon
    pub async fn mark_acted_upon(&self, suggestion_id: uuid::Uuid, success: bool) {
        let mut suggestions = self.suggestions.write().await;
        if let Some(s) = suggestions.iter_mut().find(|s| s.id == suggestion_id) {
            s.acted_upon = Some(success);
        }
    }
}

impl Default for ProactiveEngine {
    fn default() -> Self {
        Self::new()
    }
}
