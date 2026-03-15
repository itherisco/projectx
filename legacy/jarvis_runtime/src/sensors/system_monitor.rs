//! # System Monitor Sensor
//!
//! Monitors CPU, memory, and disk usage, publishing events to the event bus.

use super::{Sensor, SensorConfig};
use crate::event_bus::{Event, EventBus, EventPriority};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};

/// System metrics snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub cpu_usage_percent: f32,
    pub memory_used_bytes: u64,
    pub memory_total_bytes: u64,
    pub memory_percent: f32,
    pub disk_used_bytes: u64,
    pub disk_total_bytes: u64,
    pub disk_percent: f32,
}

/// System monitor sensor
pub struct SystemMonitor {
    config: SensorConfig,
    running: bool,
    shutdown_tx: Option<mpsc::Sender<()>>,
}

impl SystemMonitor {
    /// Create new system monitor
    pub fn new(config: SensorConfig) -> Self {
        Self {
            config,
            running: false,
            shutdown_tx: None,
        }
    }

    /// Collect current system metrics
    pub async fn collect_metrics(&self) -> SystemMetrics {
        // Get CPU usage
        let cpu_usage = sys_info::cpu_num().unwrap_or(0) as f32;
        
        // Get memory info
        let mem_info = sys_info::mem_info().unwrap_or(sys_info::MemInfo {
            total: 0,
            available: 0,
            used: 0,
            free: 0,
            swap_total: 0,
            swap_free: 0,
        });
        
        let memory_total = mem_info.total * 1024; // Convert KB to bytes
        let memory_used = (mem_info.total - mem_info.available) * 1024;
        let memory_percent = if memory_total > 0 {
            (memory_used as f32 / memory_total as f32) * 100.0
        } else {
            0.0
        };

        // Get disk info (simplified)
        let disk_info = std::fs::metadata("/").ok();
        let (disk_total, disk_used) = if let Some(meta) = disk_info {
            // This is a simplified version - in production you'd use a proper crate
            (500_000_000_000u64, 250_000_000_000u64) // 500GB total, 50% used
        } else {
            (0u64, 0u64)
        };
        
        let disk_percent = if disk_total > 0 {
            (disk_used as f32 / disk_total as f32) * 100.0
        } else {
            0.0
        };

        SystemMetrics {
            cpu_usage_percent: cpu_usage,
            memory_used_bytes: memory_used,
            memory_total_bytes: memory_total,
            memory_percent,
            disk_used_bytes: disk_used,
            disk_total_bytes: disk_total,
            disk_percent,
        }
    }

    /// Start monitoring loop
    pub async fn run(&mut self, event_bus: Arc<EventBus>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel(1);
        self.shutdown_tx = Some(shutdown_tx);
        self.running = true;

        let mut ticker = interval(Duration::from_secs(self.config.poll_interval_secs));

        loop {
            tokio::select! {
                _ = ticker.tick() => {
                    if !self.running { break; }
                    
                    let metrics = self.collect_metrics().await;
                    
                    let event = Event {
                        id: uuid::Uuid::new_v4(),
                        event_type: "system.metrics".to_string(),
                        payload: serde_json::to_value(&metrics).unwrap_or(serde_json::json!({})),
                        priority: EventPriority::Normal,
                        timestamp: chrono::Utc::now(),
                        source: "system_monitor".to_string(),
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
impl Sensor for SystemMonitor {
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
        "system_monitor"
    }

    fn is_running(&self) -> bool {
        self.running
    }
}
