//! # Health Checks
//!
//! Health check endpoint and status reporting.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::debug;

/// Health status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthState {
    Healthy,
    Degraded,
    Unhealthy,
}

impl Default for HealthState {
    fn default() -> Self {
        HealthState::Healthy
    }
}

/// Individual health check result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheckResult {
    pub name: String,
    pub status: HealthState,
    pub message: Option<String>,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

/// Health check trait
pub trait HealthCheckable: Send + Sync {
    fn name(&self) -> &str;
    fn check(&self) -> impl std::future::Future<Output = HealthCheckResult> + Send;
}

/// Health checker
pub struct HealthCheck {
    checks: Arc<RwLock<HashMap<String, Box<dyn HealthCheckable>>>>,
    last_results: Arc<RwLock<HashMap<String, HealthCheckResult>>>,
}

impl HealthCheck {
    /// Create new health checker
    pub fn new() -> Self {
        Self {
            checks: Arc::new(RwLock::new(HashMap::new())),
            last_results: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Register a health check
    pub async fn register<C: HealthCheckable + 'static>(&self, check: C) {
        let mut checks = self.checks.write().await;
        checks.insert(check.name().to_string(), Box::new(check));
    }

    /// Run all health checks
    pub async fn check_all(&self) -> Vec<HealthCheckResult> {
        let checks = self.checks.read().await;
        let mut results = Vec::new();

        for (name, check) in checks.iter() {
            let result = check.check().await;
            debug!("Health check '{}': {:?}", name, result.status);
            results.push(result.clone());

            // Store last result
            let mut last_results = self.last_results.write().await;
            last_results.insert(name.clone(), result);
        }

        results
    }

    /// Get overall health status
    pub async fn get_status(&self) -> HealthState {
        let results = self.check_all().await;

        if results.iter().any(|r| r.status == HealthState::Unhealthy) {
            HealthState::Unhealthy
        } else if results.iter().any(|r| r.status == HealthState::Degraded) {
            HealthState::Degraded
        } else {
            HealthState::Healthy
        }
    }

    /// Get last check results
    pub async fn get_last_results(&self) -> HashMap<String, HealthCheckResult> {
        self.last_results.read().await.clone()
    }

    /// Get health response for API
    pub async fn get_health_response(&self) -> serde_json::Value {
        let status = self.get_status().await;
        let results = self.check_all().await;

        serde_json::json!({
            "status": status,
            "timestamp": chrono::Utc::now(),
            "checks": results
        })
    }
}

impl Default for HealthCheck {
    fn default() -> Self {
        Self::new()
    }
}

/// Basic health check that always returns healthy
pub struct BasicHealthCheck;

impl HealthCheckable for BasicHealthCheck {
    fn name(&self) -> &str {
        "basic"
    }

    async fn check(&self) -> HealthCheckResult {
        HealthCheckResult {
            name: "basic".to_string(),
            status: HealthState::Healthy,
            message: Some("Basic health check passed".to_string()),
            last_check: chrono::Utc::now(),
        }
    }
}
