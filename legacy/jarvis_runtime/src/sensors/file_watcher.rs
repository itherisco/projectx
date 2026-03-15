//! # File Watcher Sensor
//!
//! Uses notify crate for file system event monitoring.

use super::{Sensor, SensorConfig};
use crate::event_bus::{Event, EventBus, EventPriority};
use async_trait::async_trait;
use notify::{Config, Event as NotifyEvent, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::mpsc;

/// File system event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEvent {
    pub path: PathBuf,
    pub event_type: String,
}

/// File watcher sensor
pub struct FileWatcher {
    config: SensorConfig,
    running: bool,
    watcher: Option<RecommendedWatcher>,
    shutdown_tx: Option<mpsc::Sender<()>>,
    watched_paths: Vec<PathBuf>,
}

impl FileWatcher {
    /// Create new file watcher
    pub fn new(config: SensorConfig) -> Self {
        Self {
            config,
            running: false,
            watcher: None,
            shutdown_tx: None,
            watched_paths: Vec::new(),
        }
    }

    /// Add a path to watch
    pub fn watch(&mut self, path: PathBuf) {
        self.watched_paths.push(path);
    }

    /// Start watching files
    pub async fn run(&mut self, event_bus: Arc<EventBus>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel(1);
        self.shutdown_tx = Some(shutdown_tx);
        self.running = true;

        let event_bus_clone = Arc::clone(&event_bus);

        let watcher = RecommendedWatcher::new(
            move |result: Result<NotifyEvent, notify::Error>| {
                if let Ok(event) = result {
                    let file_event = FileEvent {
                        path: event.paths.first().cloned().unwrap_or_default(),
                        event_type: format!("{:?}", event.kind),
                    };

                    let evt = Event {
                        id: uuid::Uuid::new_v4(),
                        event_type: "filesystem.event".to_string(),
                        payload: serde_json::to_value(&file_event).unwrap_or(serde_json::json!({})),
                        priority: EventPriority::Normal,
                        timestamp: chrono::Utc::now(),
                        source: "file_watcher".to_string(),
                        correlation_id: None,
                    };

                    let _ = event_bus_clone.publish(evt);
                }
            },
            Config::default(),
        )?;

        self.watcher = Some(watcher);

        // Watch all configured paths
        if let Some(ref mut watcher) = self.watcher {
            for path in &self.watched_paths {
                watcher.watch(path, RecursiveMode::Recursive)?;
            }
        }

        // Wait for shutdown
        shutdown_rx.recv().await;

        self.running = false;
        Ok(())
    }
}

#[async_trait]
impl Sensor for FileWatcher {
    async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
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
        "file_watcher"
    }

    fn is_running(&self) -> bool {
        self.running
    }
}
