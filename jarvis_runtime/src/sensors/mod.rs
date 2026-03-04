//! # Sensors - Continuous Perception Pipeline
//!
//! Event-driven sensors for system monitoring, file watching, network monitoring,
//! and user input streaming. Non-blocking, async-first implementation.

pub mod system_monitor;
pub mod file_watcher;
pub mod network_monitor;
pub mod user_input;

pub use system_monitor::SystemMonitor;
pub use file_watcher::FileWatcher;
pub use network_monitor::NetworkMonitor;
pub use user_input::UserInputStream;

use crate::event_bus::{EventBus, Event, EventPriority};
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::mpsc;

/// Sensor trait for event-driven perception
#[async_trait]
pub trait Sensor: Send + Sync {
    /// Start the sensor
    async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;
    
    /// Stop the sensor
    async fn stop(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>>;
    
    /// Get sensor name
    fn name(&self) -> &str;
    
    /// Check if sensor is running
    fn is_running(&self) -> bool;
}

/// Sensor configuration
#[derive(Debug, Clone)]
pub struct SensorConfig {
    /// Polling interval (for sensors that need it)
    pub poll_interval_secs: u64,
    /// Event bus to publish to
    pub event_bus: Option<Arc<EventBus>>,
    /// Enable/disable sensor
    pub enabled: bool,
}

impl Default for SensorConfig {
    fn default() -> Self {
        Self {
            poll_interval_secs: 60,
            event_bus: None,
            enabled: true,
        }
    }
}

/// Generic sensor wrapper for event publishing
pub struct EventPublishingSensor<S: Sensor> {
    sensor: S,
    event_bus: Arc<EventBus>,
    shutdown_tx: Option<mpsc::Sender<()>>,
}

impl<S: Sensor> EventPublishingSensor<S> {
    pub fn new(sensor: S, event_bus: Arc<EventBus>) -> Self {
        Self {
            sensor,
            event_bus,
            shutdown_tx: None,
        }
    }
    
    pub async fn run(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel(1);
        self.shutdown_tx = Some(shutdown_tx);
        
        self.sensor.start().await?;
        
        // Wait for shutdown signal
        tokio::select! {
            _ = shutdown_rx.recv() => {
                self.sensor.stop().await?;
            }
        }
        
        Ok(())
    }
    
    pub fn stop(&self) {
        if let Some(tx) = &self.shutdown_tx {
            let _ = tx.try_send(());
        }
    }
}
