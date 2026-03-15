//! # User Input Stream Sensor
//!
//! Streams user input events (keyboard, mouse, etc.) to the event bus.

use super::{Sensor, SensorConfig};
use crate::event_bus::{Event, EventBus, EventPriority};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::mpsc;

/// User input event types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum UserInputEvent {
    /// Text input event
    TextInput { text: String },
    /// Command entered
    Command { command: String, args: Vec<String> },
    /// Key press
    KeyPress { key: String, modifiers: Vec<String> },
    /// Mouse click
    MouseClick { x: i32, y: i32, button: String },
    /// Voice input
    VoiceInput { transcription: String, confidence: f32 },
}

/// User input stream sensor
pub struct UserInputStream {
    config: SensorConfig,
    running: bool,
    input_tx: Option<mpsc::Sender<UserInputEvent>>,
    shutdown_tx: Option<mpsc::Sender<()>>,
}

impl UserInputStream {
    /// Create new user input stream
    pub fn new(config: SensorConfig) -> Self {
        Self {
            config,
            running: false,
            input_tx: None,
            shutdown_tx: None,
        }
    }

    /// Get sender for user input events
    pub fn input_sender(&self) -> Option<mpsc::Sender<UserInputEvent>> {
        self.input_tx.clone()
    }

    /// Start listening for user input
    pub async fn run(&mut self, event_bus: Arc<EventBus>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let (input_tx, mut input_rx) = mpsc::channel(100);
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel(1);
        
        self.input_tx = Some(input_tx);
        self.shutdown_tx = Some(shutdown_tx);
        self.running = true;

        loop {
            tokio::select! {
                Some(input) = input_rx.recv() => {
                    let event = Event {
                        id: uuid::Uuid::new_v4(),
                        event_type: "user.input".to_string(),
                        payload: serde_json::to_value(&input).unwrap_or(serde_json::json!({})),
                        priority: EventPriority::High,
                        timestamp: chrono::Utc::now(),
                        source: "user_input".to_string(),
                        correlation_id: None,
                    };
                    
                    let _ = event_bus.publish(event);
                }
                _ = shutdown_rx.recv() => {
                    break;
                }
            }
        }

        self.running = false;
        Ok(())
    }

    /// Send a text input event
    pub async fn send_text(&self, text: String) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if let Some(tx) = &self.input_tx {
            tx.send(UserInputEvent::TextInput { text }).await?;
        }
        Ok(())
    }

    /// Send a command input event
    pub async fn send_command(&self, command: String, args: Vec<String>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if let Some(tx) = &self.input_tx {
            tx.send(UserInputEvent::Command { command, args }).await?;
        }
        Ok(())
    }
}

#[async_trait]
impl Sensor for UserInputStream {
    async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.running = true;
        Ok(())
    }

    async fn stop(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.running = false;
        if let Some(tx) = &self.shutdown_tx {
            let _ = tx.try_send(());
        }
        Ok(())
    }

    fn name(&self) -> &str {
        "user_input_stream"
    }

    fn is_running(&self) -> bool {
        self.running
    }
}
