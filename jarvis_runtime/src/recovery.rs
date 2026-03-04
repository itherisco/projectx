//! # Recovery - Crash Recovery and State Snapshotting
//!
//! Implements crash recovery supervisor, exponential backoff retries,
//! and persistent state snapshotting.

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::PathBuf;
use tokio::sync::mpsc;
use tracing::{info, error, debug};

/// Snapshot of runtime state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    /// Snapshot ID
    pub id: uuid::Uuid,
    /// Timestamp when snapshot was created
    pub timestamp: chrono::DateTime<chrono::Utc>,
    /// State data (JSON)
    pub state: serde_json::Value,
    /// Snapshot version
    pub version: String,
}

/// Recovery manager
pub struct RecoveryManager {
    snapshot_dir: PathBuf,
    max_snapshots: usize,
    snapshots: VecDeque<Snapshot>,
}

impl RecoveryManager {
    /// Create new recovery manager
    pub fn new(snapshot_dir: PathBuf) -> Self {
        Self {
            snapshot_dir,
            max_snapshots: 5,
            snapshots: VecDeque::new(),
        }
    }

    /// Create a snapshot
    pub async fn snapshot(&mut self, state: serde_json::Value) -> Result<Snapshot, Box<dyn std::error::Error + Send + Sync>> {
        let snapshot = Snapshot {
            id: uuid::Uuid::new_v4(),
            timestamp: chrono::Utc::now(),
            state,
            version: env!("CARGO_PKG_VERSION").to_string(),
        };

        // Add to queue
        self.snapshots.push_back(snapshot.clone());

        // Remove old snapshots
        while self.snapshots.len() > self.max_snapshots {
            self.snapshots.pop_front();
        }

        // Save to disk
        self.save_snapshot(&snapshot).await?;

        info!("Created snapshot {}", snapshot.id);
        Ok(snapshot)
    }

    /// Load latest snapshot
    pub async fn load_latest(&self) -> Result<Option<Snapshot>, Box<dyn std::error::Error + Send + Sync>> {
        let mut entries = std::fs::read_dir(&self.snapshot_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map_or(false, |ext| ext == "json"))
            .collect::<Vec<_>>();

        entries.sort_by_key(|e| std::cmp::Reverse(e.metadata().ok().and_then(|m| m.modified().ok())));

        if let Some(latest) = entries.first() {
            let content = std::fs::read_to_string(latest.path())?;
            let snapshot: Snapshot = serde_json::from_str(&content)?;
            Ok(Some(snapshot))
        } else {
            Ok(None)
        }
    }

    /// Save snapshot to disk
    async fn save_snapshot(&self, snapshot: &Snapshot) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        std::fs::create_dir_all(&self.snapshot_dir)?;
        let path = self.snapshot_dir.join(format!("{}.json", snapshot.id));
        let content = serde_json::to_string_pretty(snapshot)?;
        std::fs::write(path, content)?;
        Ok(())
    }

    /// Set maximum snapshots to keep
    pub fn set_max_snapshots(&mut self, max: usize) {
        self.max_snapshots = max;
    }

    /// Get all snapshots
    pub fn get_snapshots(&self) -> Vec<&Snapshot> {
        self.snapshots.iter().collect()
    }
}

/// Exponential backoff retry strategy
#[derive(Debug, Clone)]
pub struct ExponentialBackoff {
    current_attempt: u32,
    max_attempts: u32,
    initial_delay_ms: u64,
    max_delay_ms: u64,
    multiplier: f64,
}

impl ExponentialBackoff {
    /// Create new exponential backoff
    pub fn new(max_attempts: u32, initial_delay_ms: u64, max_delay_ms: u64) -> Self {
        Self {
            current_attempt: 0,
            max_attempts,
            initial_delay_ms,
            max_delay_ms,
            multiplier: 2.0,
        }
    }

    /// Get current delay
    pub fn delay(&self) -> std::time::Duration {
        let delay = (self.initial_delay_ms as f64 * self.multiplier.powf(self.current_attempt as f64)) as u64;
        std::time::Duration::from_millis(delay.min(self.max_delay_ms))
    }

    /// Check if should retry
    pub fn should_retry(&self) -> bool {
        self.current_attempt < self.max_attempts
    }

    /// Increment attempt
    pub fn next(&mut self) {
        self.current_attempt += 1;
    }

    /// Reset
    pub fn reset(&mut self) {
        self.current_attempt = 0;
    }
}

/// Retry wrapper with exponential backoff
pub async fn retry_with_backoff<F, T, E, Fut>(
    max_attempts: u32,
    initial_delay_ms: u64,
    max_delay_ms: u64,
    mut operation: F,
) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<T, E>>,
    E: std::fmt::Debug,
{
    let mut backoff = ExponentialBackoff::new(max_attempts, initial_delay_ms, max_delay_ms);

    loop {
        match operation().await {
            Ok(result) => return Ok(result),
            Err(e) => {
                if !backoff.should_retry() {
                    error!("Max retries reached, last error: {:?}", e);
                    return Err(e);
                }

                let delay = backoff.delay();
                debug!("Retrying after {:?} (attempt {}/{})", delay, backoff.current_attempt + 1, max_attempts);
                
                tokio::time::sleep(delay).await;
                backoff.next();
            }
        }
    }
}
