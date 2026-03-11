//! JARVIS Nerves - System 1: Reflex Layer
//! 
//! This module implements the "System 1" cognitive process - fast, instinctual
//! responses that don't require the full Julia brain (System 2).
//! 
//! ## Architecture
//! 
//! ```mermaid
//! graph LR
//!     Input[User Input] --> Classifier
//!     Classifier -->|High Confidence| Execute[Execute Reflex]
//!     Classifier -->|Low Confidence| Wakeup[Wake System 2]
//!     Execute --> Response
//!     Wakeup --> Julia[Julia Kernel]
//! ```
//! 
//! ## Command Classification
//! 
//! - **Reflex Commands**: Simple, well-known commands that can be executed instantly
//! - **Complex Commands**: Require deep reasoning, escalate to System 2 (Julia)
//! 
//! The classifier uses a hybrid approach:
//! 1. First, try rule-based matching (instant, zero-cost)
//! 2. If no match, optionally use ML classifier (mistral.rs when available)
//! 3. Default to escalation if uncertain

pub mod commands;
pub mod classifier;

pub use commands::{
    ReflexCommand,
    ReflexResult,
    CommandClassification,
    BUILT_IN_COMMANDS,
};
pub use classifier::{
    ReflexClassifier,
    ClassifierConfig,
    ClassificationResult,
};

use std::sync::Arc;
use tokio::sync::RwLock;
use serde::{Deserialize, Serialize};
use log::{info, debug, warn};

/// Priority levels for messages between System 1 and System 2
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessagePriority {
    /// Routine command - processed in order
    Routine,
    /// Urgent - should be processed soon
    Urgent,
    /// Wakeup - System 1 requesting System 2 to handle a complex problem
    Wakeup,
}

/// A message sent between System 1 and System 2
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgedMessage {
    /// Priority of the message
    pub priority: MessagePriority,
    /// The actual payload (command text or structured data)
    pub payload: String,
    /// Timestamp when the message was created
    pub timestamp: i64,
    /// Optional correlation ID for tracking
    pub correlation_id: Option<String>,
    /// Latency tracking: time from input to classification (ms)
    pub classify_latency_ms: u64,
}

impl BridgedMessage {
    pub fn new(priority: MessagePriority, payload: String) -> Self {
        Self {
            priority,
            payload,
            timestamp: chrono::Utc::now().timestamp_millis(),
            correlation_id: None,
            classify_latency_ms: 0,
        }
    }
    
    pub fn with_correlation(mut self, id: String) -> Self {
        self.correlation_id = Some(id);
        self
    }
    
    pub fn with_latency(mut self, latency_ms: u64) -> Self {
        self.classify_latency_ms = latency_ms;
        self
    }
}

/// System 1 Status - exposed to HUD for real-time display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct System1Status {
    /// Whether the reflex layer is active and ready
    pub is_active: bool,
    /// Current state: idle, classifying, executing, waiting
    pub state: System1State,
    /// Last classification confidence (0.0 - 1.0)
    pub last_confidence: f32,
    /// Last classification result
    pub last_classification: Option<String>,
    /// Number of reflex commands executed
    pub reflex_count: u64,
    /// Number of times System 2 was woken up
    pub wakeup_count: u64,
    /// Average classification latency in milliseconds
    pub avg_classify_latency_ms: f64,
    /// Whether ML classifier is available
    pub ml_available: bool,
}

impl Default for System1Status {
    fn default() -> Self {
        Self {
            is_active: false,
            state: System1State::Idle,
            last_confidence: 0.0,
            last_classification: None,
            reflex_count: 0,
            wakeup_count: 0,
            avg_classify_latency_ms: 0.0,
            ml_available: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum System1State {
    Idle,
    Classifying,
    Executing,
    Waiting,
}

impl std::fmt::Display for System1State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            System1State::Idle => write!(f, "idle"),
            System1State::Classifying => write!(f, "classifying"),
            System1State::Executing => write!(f, "executing"),
            System1State::Waiting => write!(f, "waiting"),
        }
    }
}

/// The main System 1 Reflex Layer
pub struct ReflexLayer {
    /// Classifier for determining reflex vs complex
    classifier: ReflexClassifier,
    /// Current status for monitoring
    status: Arc<RwLock<System1Status>>,
    /// Configuration
    config: ReflexLayerConfig,
    /// Channel to send escalations to System 2 (Julia kernel)
    /// TODO: Implement actual channel to Julia - this is the System 1/2 bridge
    /// Options: tokio::sync::mpsc channel, websocket, or jlrs call
    system2_sender: Arc<tokio::sync::mpsc::Sender<BridgedMessage>>,
}

#[derive(Debug, Clone)]
pub struct ReflexLayerConfig {
    /// Confidence threshold for reflex classification
    /// If confidence >= threshold, execute as reflex
    /// If confidence < threshold, wake System 2
    pub reflex_threshold: f32,
    /// Maximum time to spend on classification (ms)
    pub max_classify_time_ms: u64,
    /// Whether to enable ML classification
    pub enable_ml: bool,
}

impl Default for ReflexLayerConfig {
    fn default() -> Self {
        Self {
            reflex_threshold: 0.85,
            max_classify_time_ms: 50,
            enable_ml: true,
        }
    }
}

impl ReflexLayer {
    /// Create a new ReflexLayer
    pub fn new(config: ReflexLayerConfig) -> Self {
        let classifier = ReflexClassifier::new(config.clone());
        
        // Create a dummy channel for now (will be replaced)
        let (tx, _rx) = tokio::sync::mpsc::channel(100);
        
        Self {
            classifier,
            status: Arc::new(RwLock::new(System1Status::default())),
            config,
            system2_sender: Arc::new(tx),  // Dummy sender - will be replaced
        }
    }
    
    /// Set the System 2 channel for escalations
    /// This should be called by JarvisNerves to connect System 1 to System 2
    pub fn set_system2_channel(&self, sender: tokio::sync::mpsc::Sender<BridgedMessage>) {
        // Replace the sender with the real one
        let sender = Arc::new(sender);
        info!("System 1 -> System 2 channel connected");
    }
    
    /// Initialize the layer - load models if available
    pub async fn initialize(&self) -> Result<(), ReflexError> {
        info!("Initializing System 1 Reflex Layer...");
        
        let mut status = self.status.write().await;
        status.is_active = true;
        status.state = System1State::Idle;
        
        // Try to initialize ML classifier
        if self.config.enable_ml {
            match self.classifier.initialize_ml().await {
                Ok(_) => {
                    status.ml_available = true;
                    info!("ML classifier initialized successfully");
                }
                Err(e) => {
                    warn!("ML classifier not available: {}, using rule-based only", e);
                    status.ml_available = false;
                }
            }
        }
        
        info!("System 1 Reflex Layer initialized");
        Ok(())
    }
    
    /// Process an input command - classify and either execute or escalate
    pub async fn process(&self, input: &str) -> Result<ProcessResult, ReflexError> {
        let start_time = std::time::Instant::now();
        
        // Update status
        {
            let mut status = self.status.write().await;
            status.state = System1State::Classifying;
        }
        
        // Classify the command
        let classification = self.classifier.classify(input).await?;
        
        let classify_latency = start_time.elapsed().as_millis() as u64;
        
        // Update status with classification results
        {
            let mut status = self.status.write().await;
            status.last_confidence = classification.confidence;
            status.last_classification = Some(format!("{:?}", classification.decision));
            
            // Update latency tracking
            let old_avg = status.avg_classify_latency_ms;
            let count = status.reflex_count + status.wakeup_count;
            status.avg_classify_latency_ms = 
                (old_avg * (count as f64) + classify_latency as f64) / ((count + 1) as f64);
        }
        
        match classification.decision {
            CommandClassification::Reflex(cmd) => {
                info!("Executing reflex command: {:?}", cmd);
                
                // Update status
                {
                    let mut status = self.status.write().await;
                    status.state = System1State::Executing;
                    status.reflex_count += 1;
                }
                
                // Execute the reflex command
                let result = commands::execute_reflex_command(&cmd).await;
                
                {
                    let mut status = self.status.write().await;
                    status.state = System1State::Idle;
                }
                
                Ok(ProcessResult {
                    decision: classification.decision,
                    result: ReflexResult::Executed(result?),
                    latency_ms: start_time.elapsed().as_millis() as u64,
                    confidence: classification.confidence,
                })
            }
            
            CommandClassification::Complex(reason) => {
                info!("Escalating to System 2: {}", reason);
                
                // Update status
                {
                    let mut status = self.status.write().await;
                    status.state = System1State::Waiting;
                    status.wakeup_count += 1;
                }
                
                // Create message to wake System 2
                let message = BridgedMessage::new(
                    MessagePriority::Wakeup,
                    input.to_string(),
                ).with_latency(classify_latency);
                
                // Try to send to System 2 (via channel)
                // Note: Using Arc<Sender> - always available but may be disconnected
                match self.system2_sender.send(message.clone()).await {
                    Ok(_) => info!("Message sent to System 2"),
                    Err(e) => warn!("System 2 channel error (receiver may be dropped): {}", e),
                }
                
                Ok(ProcessResult {
                    decision: classification.decision,
                    result: ReflexResult::Escalated(message),
                    latency_ms: start_time.elapsed().as_millis() as u64,
                    confidence: classification.confidence,
                })
            }
        }
    }
    
    /// Get current status for HUD display
    pub async fn get_status(&self) -> System1Status {
        self.status.read().await.clone()
    }
    
    /// Record feedback from System 2 for learning
    pub async fn record_feedback(&self, input: &str, system1_decision: &str, system2_result: &str) {
        self.classifier.record_feedback(input, system1_decision, system2_result).await;
    }
}

/// Result of processing an input
pub struct ProcessResult {
    pub decision: CommandClassification,
    pub result: ReflexResult,
    pub latency_ms: u64,
    pub confidence: f32,
}

/// Error types for the reflex layer
#[derive(Debug, thiserror::Error)]
pub enum ReflexError {
    #[error("Classification failed: {0}")]
    ClassificationFailed(String),
    
    #[error("Execution failed: {0}")]
    ExecutionFailed(String),
    
    #[error("ML initialization failed: {0}")]
    MlInitFailed(String),
    
    #[error("Timeout: classification took too long")]
    Timeout,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_reflex_layer_init() {
        let layer = ReflexLayer::new(ReflexLayerConfig::default());
        layer.initialize().await.unwrap();
        
        let status = layer.get_status().await;
        assert!(status.is_active);
    }
    
    #[tokio::test]
    async fn test_known_command_classification() {
        let layer = ReflexLayer::new(ReflexLayerConfig::default());
        layer.initialize().await.unwrap();
        
        let result = layer.process("check system status").await.unwrap();
        
        // Known commands should be classified as reflex
        match result.decision {
            CommandClassification::Reflex(_) => {},
            CommandClassification::Complex(_) => panic!("Expected reflex for known command"),
        }
    }
}
