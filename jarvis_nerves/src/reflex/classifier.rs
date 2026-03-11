//! JARVIS Nerves - System 1: Command Classifier
//! 
//! This module implements the classification logic for determining whether
//! a command should be handled by System 1 (reflex) or escalated to System 2.
//! 
//! ## Classification Strategy
//! 
//! 1. **Rule-based matching** (always available): Fast pattern matching against known commands
//! 2. **ML-based classification** (optional): Uses mistral.rs for uncertainty handling
//! 3. **Fallback**: When ML is unavailable or uncertain, escalate to System 2

use super::commands::{ReflexCommand, BuiltInCommands, BUILT_IN_COMMANDS, CommandClassification};
use super::ReflexLayerConfig;
use log::{debug, warn, info};

/// Result of classifying an input
#[derive(Debug, Clone)]
pub struct ClassificationResult {
    /// The classification decision
    pub decision: CommandClassification,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Which method was used for classification
    pub method: ClassificationMethod,
    /// Optional reasoning
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ClassificationMethod {
    /// Rule-based pattern matching
    RuleBased,
    /// ML-based classification (mistral.rs)
    ML,
    /// Default escalation (fallback)
    DefaultEscalation,
}

/// Configuration for the classifier
#[derive(Debug, Clone)]
pub struct ClassifierConfig {
    /// Confidence threshold for reflex classification
    pub reflex_threshold: f32,
    /// Maximum time to spend on ML classification (ms)
    pub ml_timeout_ms: u64,
    /// Whether to enable ML classification
    pub enable_ml: bool,
}

impl Default for ClassifierConfig {
    fn default() -> Self {
        Self {
            reflex_threshold: 0.85,
            ml_timeout_ms: 100,
            enable_ml: true,
        }
    }
}

/// The classifier that determines reflex vs complex
pub struct ReflexClassifier {
    /// Built-in command patterns
    built_in: BuiltInCommands,
    /// Configuration
    config: ClassifierConfig,
    /// ML model (optional)
    ml_model: Option<MLClassifier>,
    /// Feedback history for learning
    feedback_history: Vec<FeedbackEntry>,
}

struct MLClassifier {
    // Placeholder for mistral.rs integration
    // In production, this would hold the loaded model
    initialized: bool,
}

impl MLClassifier {
    fn new() -> Self {
        Self { initialized: false }
    }
    
    async fn initialize(&mut self) -> Result<(), MLError> {
        // In production, this would load the mistral.rs model
        // For now, we'll simulate ML initialization
        info!("Initializing ML classifier (simulated)...");
        
        // Try to load mistral.rs if feature is enabled
        #[cfg(feature = "slm")]
        {
            // Load actual model here
            // let model = mistral_rs::InferenceClient).await::new(...?;
            self.initialized = true;
            info!("ML classifier initialized (SLM mode)");
        }
        
        #[cfg(not(feature = "slm"))]
        {
            // ML not available without slm feature
            return Err(MLError::NotCompiled("SLM feature not enabled".to_string()));
        }
        
        Ok(())
    }
    
    async fn classify(&self, input: &str) -> Result<MLClassification, MLError> {
        if !self.initialized {
            return Err(MLError::NotInitialized);
        }
        
        // In production, this would use mistral.rs for classification
        // For now, return a default response
        Ok(MLClassification {
            is_reflex: false,
            confidence: 0.5,
            reasoning: "ML classification placeholder".to_string(),
        })
    }
}

struct MLClassification {
    is_reflex: bool,
    confidence: f32,
    reasoning: String,
}

#[derive(Debug, Clone)]
struct FeedbackEntry {
    input: String,
    system1_decision: String,
    system2_result: String,
    corrected: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum MLError {
    #[error("ML model not compiled: {0}")]
    NotCompiled(String),
    
    #[error("ML model not initialized")]
    NotInitialized,
    
    #[error("ML inference failed: {0}")]
    InferenceFailed(String),
    
    #[error("ML timeout")]
    Timeout,
}

impl ReflexClassifier {
    pub fn new(config: ReflexLayerConfig) -> Self {
        Self {
            built_in: BuiltInCommands::new(),
            config: ClassifierConfig {
                reflex_threshold: config.reflex_threshold,
                ml_timeout_ms: config.max_classify_time_ms,
                enable_ml: config.enable_ml,
            },
            ml_model: None,
            feedback_history: Vec::new(),
        }
    }
    
    /// Initialize ML model (optional)
    pub async fn initialize_ml(&mut self) -> Result<(), MLError> {
        if !self.config.enable_ml {
            return Err(MLError::NotCompiled("ML disabled in config".to_string()));
        }
        
        let mut ml = MLClassifier::new();
        ml.initialize().await?;
        
        self.ml_model = Some(ml);
        Ok(())
    }
    
    /// Classify an input command
    pub async fn classify(&self, input: &str) -> Result<ClassificationResult, ReflexError> {
        // Step 1: Try rule-based matching (always available, instant)
        debug!("Classifying input: {}", input);
        
        if let Some(cmd) = self.built_in.match_command(input) {
            // Check if this is a complex command that should go to System 2
            let is_complex = matches!(
                cmd,
                ReflexCommand::Unknown 
                | ReflexCommand::Custom(_)
            );
            
            if is_complex {
                // Unknown commands get escalated
                return Ok(ClassificationResult {
                    decision: CommandClassification::Complex("Unknown command - requires System 2".to_string()),
                    confidence: 1.0,
                    method: ClassificationMethod::RuleBased,
                    reason: Some("Command not in built-in repertoire".to_string()),
                });
            }
            
            // Known command - execute as reflex with high confidence
            return Ok(ClassificationResult {
                decision: CommandClassification::Reflex(cmd),
                confidence: 0.95,
                method: ClassificationMethod::RuleBased,
                reason: Some("Known command matched via pattern".to_string()),
            });
        }
        
        // Step 2: If no rule match, try ML classification (if available)
        if let Some(ref ml) = self.ml_model {
            match tokio::time::timeout(
                std::time::Duration::from_millis(self.config.ml_timeout_ms),
                ml.classify(input)
            ).await {
                Ok(Ok(ml_result)) => {
                    let confidence = ml_result.confidence;
                    
                    if confidence >= self.config.reflex_threshold && ml_result.is_reflex {
                        // ML says reflex with high confidence
                        return Ok(ClassificationResult {
                            decision: CommandClassification::Reflex(ReflexCommand::Custom(input.to_string())),
                            confidence,
                            method: ClassificationMethod::ML,
                            reason: Some(ml_result.reasoning),
                        });
                    } else {
                        // ML says escalate
                        return Ok(ClassificationResult {
                            decision: CommandClassification::Complex(ml_result.reasoning),
                            confidence: 1.0 - confidence,
                            method: ClassificationMethod::ML,
                            reason: Some(ml_result.reasoning),
                        });
                    }
                }
                Ok(Err(e)) => {
                    warn!("ML classification failed: {}, falling back to escalation", e);
                }
                Err(_) => {
                    warn!("ML classification timed out, falling back to escalation");
                }
            }
        }
        
        // Step 3: Default escalation when uncertain
        Ok(ClassificationResult {
            decision: CommandClassification::Complex("No matching pattern - requires System 2 reasoning".to_string()),
            confidence: 0.5,
            method: ClassificationMethod::DefaultEscalation,
            reason: Some("Unmatched input, defaulting to escalation".to_string()),
        })
    }
    
    /// Record feedback from System 2 for learning
    pub async fn record_feedback(&mut self, input: &str, system1_decision: &str, system2_result: &str) {
        let corrected = system1_decision != system2_result;
        
        self.feedback_history.push(FeedbackEntry {
            input: input.to_string(),
            system1_decision: system1_decision.to_string(),
            system2_result: system2_result.to_string(),
            corrected,
        });
        
        // Keep only recent feedback (last 1000 entries)
        if self.feedback_history.len() > 1000 {
            self.feedback_history.remove(0);
        }
        
        if corrected {
            warn!("Classification correction: System1={}, System2={}", 
                system1_decision, system2_result);
        }
        
        // In production, this would trigger model retraining
        self.update_model().await;
    }
    
    /// Update the model based on feedback (placeholder)
    async fn update_model(&self) {
        // Count corrections
        let corrections = self.feedback_history.iter()
            .filter(|f| f.corrected)
            .count();
        
        let total = self.feedback_history.len();
        
        if total > 10 {
            let error_rate = corrections as f32 / total as f32;
            debug!("Feedback summary: {}/{} corrections ({:.1}%)", 
                corrections, total, error_rate * 100.0);
            
            // In production, if error rate is high, retrain the model
            if error_rate > 0.2 {
                warn!("High error rate detected - consider retraining classifier");
            }
        }
    }
    
    /// Get classification accuracy from feedback
    pub fn get_accuracy(&self) -> f32 {
        if self.feedback_history.is_empty() {
            return 1.0;
        }
        
        let correct = self.feedback_history.iter()
            .filter(|f| !f.corrected)
            .count();
        
        correct as f32 / self.feedback_history.len() as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_rule_based_classification() {
        let config = ReflexLayerConfig {
            enable_ml: false, // Disable ML for this test
            ..Default::default()
        };
        let classifier = ReflexClassifier::new(config);
        
        let result = classifier.classify("check system status").await.unwrap();
        
        assert!(matches!(result.decision, CommandClassification::Reflex(ReflexCommand::CheckStatus)));
        assert!(result.confidence > 0.9);
    }
    
    #[tokio::test]
    async fn test_unknown_command_escalation() {
        let config = ReflexLayerConfig {
            enable_ml: false,
            ..Default::default()
        };
        let classifier = ReflexClassifier::new(config);
        
        let result = classifier.classify("what's the meaning of life").await.unwrap();
        
        assert!(matches!(result.decision, CommandClassification::Complex(_)));
    }
    
    #[test]
    fn test_feedback_tracking() {
        let config = ReflexLayerConfig::default();
        let mut classifier = ReflexClassifier::new(config);
        
        // Simulate feedback
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            classifier.record_feedback("test input", "reflex", "complex").await;
        });
        
        assert_eq!(classifier.get_accuracy(), 0.0); // 0% since 1 correction
    }
}
