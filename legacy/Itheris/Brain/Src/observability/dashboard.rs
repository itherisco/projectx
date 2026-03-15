//! # Dashboard Module for Warden Architecture
//! 
//! Real-time system status, historical data aggregation, and dashboard
//! data structures for frontend consumption.
//! 
//! ## Features
//! 
//! - Real-time system status
//! - Historical data aggregation
//! - Alert threshold configuration
//! - JSON dashboard data API

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use chrono::{DateTime, Utc, Duration};
use super::metrics_collector::{MetricsCollector, ActuationLatencyStats};

/// System status levels
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StatusLevel {
    Healthy,
    Degraded,
    Critical,
    Unknown,
}

impl StatusLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            StatusLevel::Healthy => "HEALTHY",
            StatusLevel::Degraded => "DEGRADED",
            StatusLevel::Critical => "CRITICAL",
            StatusLevel::Unknown => "UNKNOWN",
        }
    }
}

/// Real-time system status
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SystemStatus {
    pub status: String,
    pub uptime_seconds: u64,
    pub timestamp: i64,
    pub components: HashMap<String, ComponentStatus>,
    pub metrics_summary: MetricsSummary,
}

/// Component status within the system
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ComponentStatus {
    pub name: String,
    pub status: String,
    pub last_check: i64,
    pub message: Option<String>,
}

/// Summary of key metrics
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MetricsSummary {
    pub actuation_latency_ms: f64,
    pub actuation_latency_p95_ms: f64,
    pub divergence_score: f64,
    pub mqtt_throughput: f64,
    pub tpm_success_rate: f64,
    pub security_alerts_count: u64,
    pub network_egress_blocked: u64,
}

/// Historical data point
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HistoricalDataPoint {
    pub timestamp: i64,
    pub value: f64,
    pub labels: HashMap<String, String>,
}

/// Historical data aggregation
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HistoricalData {
    pub metric_name: String,
    pub data_points: Vec<HistoricalDataPoint>,
    pub aggregation_window_seconds: u64,
    pub start_time: i64,
    pub end_time: i64,
}

/// Alert threshold configuration
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AlertThreshold {
    pub metric_name: String,
    pub threshold_value: f64,
    pub condition: ThresholdCondition,
    pub severity: String,
    pub enabled: bool,
}

/// Threshold condition types
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThresholdCondition {
    GreaterThan,
    LessThan,
    Equals,
    NotEquals,
    GreaterThanOrEqual,
    LessThanOrEqual,
}

/// Dashboard data structure for frontend
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardData {
    pub system_status: SystemStatus,
    pub historical_data: Vec<HistoricalData>,
    pub active_alerts: Vec<DashboardAlert>,
    pub thresholds: Vec<AlertThreshold>,
    pub last_updated: i64,
}

/// Alert for dashboard display
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardAlert {
    pub id: String,
    pub title: String,
    pub description: String,
    pub severity: String,
    pub timestamp: i64,
    pub source: String,
}

/// Dashboard API for frontend consumption
pub struct DashboardApi {
    collector: std::sync::Arc<tokio::sync::RwLock<MetricsCollector>>,
    thresholds: Vec<AlertThreshold>,
    start_time: std::time::Instant,
}

impl DashboardApi {
    /// Create a new dashboard API
    pub fn new(collector: std::sync::Arc<tokio::sync::RwLock<MetricsCollector>>) -> Self {
        Self {
            collector,
            thresholds: Self::default_thresholds(),
            start_time: std::time::Instant::now(),
        }
    }

    /// Get current system status
    pub async fn get_system_status(&self) -> SystemStatus {
        let collector = self.collector.read().await;
        
        let latency_stats = collector.get_actuation_latency_stats();
        let network_egress = collector.get_network_egress();
        let alert_counts = collector.get_security_alert_counts();

        let total_alerts: u64 = alert_counts.values().sum();
        let blocked_egress = *network_egress.get("total_blocked").unwrap_or(&0);

        // Determine overall status
        let status = if latency_stats.mean > 30.0 || blocked_egress > 10 {
            StatusLevel::Critical
        } else if latency_stats.mean > 20.0 || total_alerts > 5 {
            StatusLevel::Degraded
        } else {
            StatusLevel::Healthy
        };

        SystemStatus {
            status: status.as_str().to_string(),
            uptime_seconds: self.start_time.elapsed().as_secs(),
            timestamp: Utc::now().timestamp(),
            components: self.get_components_status(&collector),
            metrics_summary: MetricsSummary {
                actuation_latency_ms: latency_stats.mean,
                actuation_latency_p95_ms: latency_stats.p95,
                divergence_score: collector.get_metrics()
                    .get("agent_divergence_mean")
                    .map(|m| match &m.value {
                        super::metrics_collector::MetricValue::Gauge(v) => *v,
                        _ => 0.0,
                    })
                    .unwrap_or(0.0),
                mqtt_throughput: collector.get_metrics()
                    .get("mqtt_throughput")
                    .map(|m| match &m.value {
                        super::metrics_collector::MetricValue::Gauge(v) => *v,
                        _ => 0.0,
                    })
                    .unwrap_or(0.0),
                tpm_success_rate: collector.get_metrics()
                    .get("tpm_operation_success_rate")
                    .map(|m| match &m.value {
                        super::metrics_collector::MetricValue::Gauge(v) => *v,
                        _ => 0.0,
                    })
                    .unwrap_or(100.0),
                security_alerts_count: total_alerts,
                network_egress_blocked: blocked_egress,
            },
        }
    }

    /// Get component statuses
    fn get_components_status(&self, collector: &MetricsCollector) -> HashMap<String, ComponentStatus> {
        let mut components = HashMap::new();

        // IoT Bridge status
        let iot_status = if collector.get_metrics().contains_key("mqtt_throughput") {
            "OPERATIONAL"
        } else {
            "NOT_INITIALIZED"
        };
        components.insert("iot_bridge".to_string(), ComponentStatus {
            name: "IoT Bridge".to_string(),
            status: iot_status.to_string(),
            last_check: Utc::now().timestamp(),
            message: None,
        });

        // TPM status
        let tpm_status = if collector.get_metrics().contains_key("tpm_operation_success_rate") {
            "OPERATIONAL"
        } else {
            "NOT_INITIALIZED"
        };
        components.insert("tpm".to_string(), ComponentStatus {
            name: "TPM".to_string(),
            status: tpm_status.to_string(),
            last_check: Utc::now().timestamp(),
            message: None,
        });

        // Security status
        let security_status = if collector.get_security_alert_counts().values().sum::<u64>() > 10 {
            "ALERTS_ACTIVE"
        } else {
            "SECURE"
        };
        components.insert("security".to_string(), ComponentStatus {
            name: "Security".to_string(),
            status: security_status.to_string(),
            last_check: Utc::now().timestamp(),
            message: None,
        });

        components
    }

    /// Get historical data for a metric
    pub async fn get_historical_data(
        &self,
        metric_name: &str,
        window_seconds: u64,
    ) -> HistoricalData {
        let collector = self.collector.read().await;
        let now = Utc::now().timestamp();
        let start_time = now - window_seconds as i64;

        let data_points = collector.get_metrics()
            .get(metric_name)
            .map(|metric| {
                vec![HistoricalDataPoint {
                    timestamp: metric.timestamp,
                    value: match &metric.value {
                        super::metrics_collector::MetricValue::Gauge(v) => *v,
                        super::metrics_collector::MetricValue::Counter(v) => *v as f64,
                        super::metrics_collector::MetricValue::Summary { sum, .. } => *sum,
                        super::metrics_collector::MetricValue::Histogram(buckets) => {
                            buckets.iter().sum()
                        }
                    },
                    labels: metric.labels.clone(),
                }]
            })
            .unwrap_or_default();

        HistoricalData {
            metric_name: metric_name.to_string(),
            data_points,
            aggregation_window_seconds: window_seconds,
            start_time,
            end_time: now,
        }
    }

    /// Get all thresholds
    pub fn get_thresholds(&self) -> Vec<AlertThreshold> {
        self.thresholds.clone()
    }

    /// Update a threshold
    pub fn update_threshold(&mut self, threshold: AlertThreshold) {
        if let Some(existing) = self.thresholds.iter_mut().find(|t| t.metric_name == threshold.metric_name) {
            *existing = threshold;
        } else {
            self.thresholds.push(threshold);
        }
    }

    /// Get full dashboard data
    pub async fn get_dashboard_data(&self) -> DashboardData {
        let system_status = self.get_system_status().await;
        
        // Get historical data for key metrics
        let mut historical_data = Vec::new();
        let key_metrics = [
            "actuation_latency_mean",
            "agent_divergence_mean",
            "mqtt_throughput",
            "tpm_operation_success_rate",
        ];

        for metric in &key_metrics {
            historical_data.push(self.get_historical_data(metric, 3600).await);
        }

        DashboardData {
            system_status,
            historical_data,
            active_alerts: Vec::new(), // Would be populated from alerts module
            thresholds: self.get_thresholds(),
            last_updated: Utc::now().timestamp(),
        }
    }

    /// Export dashboard data as JSON
    pub async fn export_json(&self) -> String {
        let data = self.get_dashboard_data().await;
        serde_json::to_string_pretty(&data).unwrap_or_default()
    }

    /// Default thresholds for Warden Architecture
    fn default_thresholds() -> Vec<AlertThreshold> {
        vec![
            AlertThreshold {
                metric_name: "actuation_latency_mean".to_string(),
                threshold_value: 30.0,
                condition: ThresholdCondition::GreaterThan,
                severity: "WARNING".to_string(),
                enabled: true,
            },
            AlertThreshold {
                metric_name: "actuation_latency_mean".to_string(),
                threshold_value: 100.0,
                condition: ThresholdCondition::GreaterThan,
                severity: "CRITICAL".to_string(),
                enabled: true,
            },
            AlertThreshold {
                metric_name: "agent_divergence_mean".to_string(),
                threshold_value: 0.5,
                condition: ThresholdCondition::GreaterThan,
                severity: "WARNING".to_string(),
                enabled: true,
            },
            AlertThreshold {
                metric_name: "security_alerts_auth_failures".to_string(),
                threshold_value: 5.0,
                condition: ThresholdCondition::GreaterThan,
                severity: "CRITICAL".to_string(),
                enabled: true,
            },
            AlertThreshold {
                metric_name: "tpm_operation_success_rate".to_string(),
                threshold_value: 95.0,
                condition: ThresholdCondition::LessThan,
                severity: "WARNING".to_string(),
                enabled: true,
            },
        ]
    }
}

/// Historical aggregation helper
pub struct HistoricalAggregation {
    data_window: VecDeque<HistoricalDataPoint>,
    max_size: usize,
}

impl HistoricalAggregation {
    /// Create a new historical aggregation
    pub fn new(max_size: usize) -> Self {
        Self {
            data_window: VecDeque::with_capacity(max_size),
            max_size,
        }
    }

    /// Add a data point
    pub fn add_point(&mut self, point: HistoricalDataPoint) {
        self.data_window.push_back(point);
        if self.data_window.len() > self.max_size {
            self.data_window.pop_front();
        }
    }

    /// Get aggregated data
    pub fn get_aggregated(&self) -> Vec<HistoricalDataPoint> {
        self.data_window.iter().cloned().collect()
    }

    /// Calculate average
    pub fn average(&self) -> f64 {
        if self.data_window.is_empty() {
            return 0.0;
        }
        let sum: f64 = self.data_window.iter().map(|p| p.value).sum();
        sum / self.data_window.len() as f64
    }

    /// Calculate min
    pub fn min(&self) -> f64 {
        self.data_window.iter()
            .map(|p| p.value)
            .fold(f64::INFINITY, f64::min)
    }

    /// Calculate max
    pub fn max(&self) -> f64 {
        self.data_window.iter()
            .map(|p| p.value)
            .fold(f64::NEG_INFINITY, f64::max)
    }
}

impl Default for HistoricalAggregation {
    fn default() -> Self {
        Self::new(1000)
    }
}
