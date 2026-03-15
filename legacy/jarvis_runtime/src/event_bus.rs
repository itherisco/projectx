//! # Event Bus - Async Event Streaming
//!
//! Tokio-based broadcast channel for event-driven perception pipeline.
//! Non-blocking, pub-sub event distribution.

use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::broadcast;
use tracing::{info, debug, warn};
use chrono::{DateTime, Utc};

/// Event priority levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EventPriority {
    Low,
    Normal,
    High,
    Critical,
}

impl Default for EventPriority {
    fn default() -> Self {
        EventPriority::Normal
    }
}

/// Base event type for the event bus
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Unique event ID
    pub id: uuid::Uuid,
    /// Event type identifier
    pub event_type: String,
    /// Event payload (JSON)
    pub payload: serde_json::Value,
    /// Event priority
    pub priority: EventPriority,
    /// Timestamp when event was created
    pub timestamp: DateTime<Utc>,
    /// Source of the event
    pub source: String,
    /// Optional correlation ID
    pub correlation_id: Option<uuid::Uuid>,
}

impl Event {
    /// Create a new event
    pub fn new(event_type: String, payload: serde_json::Value, source: String) -> Self {
        Self {
            id: uuid::Uuid::new_v4(),
            event_type,
            payload,
            priority: EventPriority::Normal,
            timestamp: Utc::now(),
            source,
            correlation_id: None,
        }
    }

    /// Create a high-priority event
    pub fn critical(event_type: String, payload: serde_json::Value, source: String) -> Self {
        Self {
            priority: EventPriority::Critical,
            ..Self::new(event_type, payload, source)
        }
    }

    /// Create an event with correlation
    pub fn with_correlation(
        event_type: String,
        payload: serde_json::Value,
        source: String,
        correlation_id: uuid::Uuid,
    ) -> Self {
        Self {
            correlation_id: Some(correlation_id),
            ..Self::new(event_type, payload, source)
        }
    }
}

/// Event subscription handle
#[derive(Debug, Clone)]
pub struct EventSubscription {
    pub id: uuid::Uuid,
    pub event_types: Vec<String>,
    pub min_priority: EventPriority,
}

/// Event bus using tokio::broadcast
pub struct EventBus {
    tx: broadcast::Sender<Event>,
    #[allow(dead_code)]
    capacity: usize,
    subscriptions: Arc<tokio::sync::RwLock<Vec<EventSubscription>>>,
}

impl EventBus {
    /// Create new event bus with specified channel capacity
    pub fn new(capacity: usize) -> Self {
        let (tx, _) = broadcast::channel(capacity);
        
        Self {
            tx,
            capacity,
            subscriptions: Arc::new(tokio::sync::RwLock::new(Vec::new())),
        }
    }

    /// Publish an event to all subscribers
    pub fn publish(&self, event: Event) -> Result<usize, broadcast::error::SendError<Event>> {
        debug!("Publishing event: {} from {}", event.event_type, event.source);
        self.tx.send(event)
    }

    /// Subscribe to events
    pub async fn subscribe(
        &self,
        event_types: Vec<String>,
        min_priority: EventPriority,
    ) -> EventSubscription {
        let subscription = EventSubscription {
            id: uuid::Uuid::new_v4(),
            event_types,
            min_priority,
        };
        
        let mut subs = self.subscriptions.write().await;
        subs.push(subscription.clone());
        
        subscription
    }

    /// Unsubscribe from events
    pub async fn unsubscribe(&self, subscription_id: uuid::Uuid) {
        let mut subs = self.subscriptions.write().await;
        subs.retain(|s| s.id != subscription_id);
    }

    /// Get event receiver for subscribing to all events
    pub fn receiver(&self) -> broadcast::Receiver<Event> {
        self.tx.subscribe()
    }

    /// Get receiver that filters by event types
    pub fn filtered_receiver(&self, event_types: Vec<String>) -> FilteredEventReceiver {
        FilteredEventReceiver {
            receiver: self.tx.subscribe(),
            event_types,
        }
    }
}

/// Filtered event receiver
pub struct FilteredEventReceiver {
    receiver: broadcast::Receiver<Event>,
    event_types: Vec<String>,
}

impl FilteredEventReceiver {
    /// Receive the next matching event
    pub async fn recv(&mut self) -> Result<Event, broadcast::error::RecvError> {
        loop {
            let event = self.receiver.recv().await?;
            
            if self.event_types.contains(&event.event_type) {
                return Ok(event);
            }
            
            // Skip non-matching events
            debug!("Skipping event: {}", event.event_type);
        }
    }
}

/// Event processor trait
#[async_trait::async_trait]
pub trait EventProcessor: Send + Sync {
    /// Process an event
    async fn process(&self, event: Event) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;
    
    /// Get processor name
    fn name(&self) -> &str;
}

/// Event processor that forwards to the event bus
pub struct EventBusProcessor {
    bus: Arc<EventBus>,
    event_types: Vec<String>,
}

impl EventBusProcessor {
    pub fn new(bus: Arc<EventBus>, event_types: Vec<String>) -> Self {
        Self { bus, event_types }
    }
}

#[async_trait::async_trait]
impl EventProcessor for EventBusProcessor {
    async fn process(&self, event: Event) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if self.event_types.contains(&event.event_type) || self.event_types.is_empty() {
            self.bus.publish(event)?;
        }
        Ok(())
    }
    
    fn name(&self) -> &str {
        "EventBusProcessor"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_event_publish() {
        let bus = EventBus::new(10);
        let event = Event::new("test".to_string(), serde_json::json!({"value": 1}), "test".to_string());
        
        let result = bus.publish(event);
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_event_subscribe() {
        let bus = EventBus::new(10);
        let _ = bus.subscribe(vec!["test".to_string()], EventPriority::Normal).await;
        
        let subs = bus.subscriptions.read().await;
        assert_eq!(subs.len(), 1);
    }
}
