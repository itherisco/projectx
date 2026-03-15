//! # Network Monitor Sensor
//!
//! Passive network statistics monitoring.

use super::{Sensor, SensorConfig};
use crate::event_bus::{Event, EventBus, EventPriority};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};

/// Network statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkStats {
    pub bytes_received: u64,
    pub bytes_sent: u64,
    pub packets_received: u64,
    pub packets_sent: u64,
    pub errors_in: u64,
    pub errors_out: u64,
}

/// Network monitor sensor
pub struct NetworkMonitor {
    config: SensorConfig,
    running: bool,
    shutdown_tx: Option<mpsc::Sender<()>>,
}

impl NetworkMonitor {
    /// Create new network monitor
    pub fn new(config: SensorConfig) -> Self {
        Self {
            config,
            running: false,
            shutdown_tx: None,
        }
    }

    /// Collect network statistics (simplified)
    pub async fn collect_stats(&self) -> NetworkStats {
        // In production, this would read from /proc/net/dev on Linux
        // or use platform-specific APIs
        NetworkStats {
            bytes_received: 0,
            bytes_sent: 0,
            packets_received: 0,
            packets_sent: 0,
            errors_in: 0,
            errors_out: 0,
        }
    }

    /// Start monitoring
    pub async fn run(&mut self, event_bus: Arc<EventBus>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel(1);
        self.shutdown_tx = Some(shutdown_tx);
        self.running = true;

        let mut ticker = interval(Duration::from_secs(self.config.poll_interval_secs));

        loop {
            tokio::select! {
                _ = ticker.tick() => {
                    if !self.running { break; }
                    
                    let stats = self.collect_stats().await;
                    
                    let event = Event {
                        id: uuid::Uuid::new_v4(),
                        event_type: "network.stats".to_string(),
                        payload: serde_json::to_value(&stats).unwrap_or(serde_json::json!({})),
                        priority: EventPriority::Low,
                        timestamp: chrono::Utc::now(),
                        source: "network_monitor".to_string(),
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
}

#[async_trait]
impl Sensor for NetworkMonitor {
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
        "network_monitor"
    }

    fn is_running(&self) -> bool {
        self.running
    }
}
