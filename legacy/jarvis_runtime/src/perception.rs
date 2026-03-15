//! # Perception Pipeline
//!
//! Event-driven perception that processes sensor data and forwards to attention.

use crate::event_bus::{Event, EventBus, EventProcessor};
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{info, debug};

/// Attention processor that receives events and determines what to focus on
pub struct AttentionProcessor {
    event_bus: Arc<EventBus>,
    kernel_channel: mpsc::Sender<Event>,
    attention_threshold: f32,
}

impl AttentionProcessor {
    /// Create new attention processor
    pub fn new(event_bus: Arc<EventBus>, kernel_channel: mpsc::Sender<Event>, attention_threshold: f32) -> Self {
        Self {
            event_bus,
            kernel_channel,
            attention_threshold,
        }
    }

    /// Process events from the event bus
    pub async fn run(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut receiver = self.event_bus.receiver();

        loop {
            match receiver.recv().await {
                Ok(event) => {
                    let priority_score = self.calculate_attention_score(&event);
                    
                    debug!(
                        "Event {} has attention score {:.2}",
                        event.event_type,
                        priority_score
                    );

                    if priority_score >= self.attention_threshold {
                        // Forward to kernel for processing
                        if let Err(e) = self.kernel_channel.send(event).await {
                            debug!("Kernel channel error: {}", e);
                        }
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    debug!("Lagged {} events", n);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }

        Ok(())
    }

    /// Calculate attention score for an event
    fn calculate_attention_score(&self, event: &Event) -> f32 {
        let base_score = match event.priority {
            crate::event_bus::EventPriority::Critical => 1.0,
            crate::event_bus::EventPriority::High => 0.75,
            crate::event_bus::EventPriority::Normal => 0.5,
            crate::event_bus::EventPriority::Low => 0.25,
        };

        // Adjust based on event type
        let type_multiplier = match event.event_type.as_str() {
            "user.input" => 1.5,
            "system.metrics" => 0.5,
            "filesystem.event" => 0.7,
            "network.stats" => 0.3,
            _ => 1.0,
        };

        base_score * type_multiplier
    }
}

#[async_trait]
impl EventProcessor for AttentionProcessor {
    async fn process(&self, event: Event) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.kernel_channel.send(event).await?;
        Ok(())
    }

    fn name(&self) -> &str {
        "AttentionProcessor"
    }
}
