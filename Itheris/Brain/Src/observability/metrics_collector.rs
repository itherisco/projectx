//! # Metrics Collector for Warden Architecture
//! 
//! Async-friendly metrics collection for runtime observability of the
//! cyber-physical control loop.
//! 
//! ## Metrics Tracked
//! 
//! - Actuation latency (target: <30ms mean)
//! - Agent divergence (deviation from expected behavior)
//! - External network egress (unauthorized outbound connections)
//! - Security alerts (authentication failures, unauthorized access attempts)
//! - MQTT message throughput
//! - TPM operation success/failure rates

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use chrono::{DateTime, Utc};

/// Metric value types
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "value")]
pub enum MetricValue {
    Counter(u64),
    Gauge(f64),
    Histogram(Vec<f64>),
    Summary { sum: f64, count: u64 },
}

/// Metric types supported
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MetricType {
    Counter,
    Gauge,
    Histogram,
    Summary,
}

/// Individual metric data point
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MetricData {
    pub name: String,
    pub metric_type: MetricType,
    pub value: MetricValue,
    pub labels: HashMap<String, String>,
    pub timestamp: i64,
}

/// Global metrics collector registry
pub static COLLECTOR_REGISTRY: std::sync::OnceLock<Arc<RwLock<MetricsCollector>>> = 
    std::sync::OnceLock::new();

/// Get or initialize the global metrics collector
pub fn get_metrics_collector() -> Arc<RwLock<MetricsCollector>> {
    COLLECTOR_REGISTRY.get_or_init(|| {
        Arc::new(RwLock::new(MetricsCollector::new()))
    }).clone()
}

/// Metrics collector for Warden Architecture
pub struct MetricsCollector {
    metrics: HashMap<String, MetricData>,
    actuation_latencies: VecDeque<f64>,
    divergence_scores: VecDeque<f64>,
    network_egress: HashMap<String, u64>,
    security_alerts: VecDeque<SecurityAlertMetric>,
    mqtt_messages: VecDeque<MqttMetric>,
    tpm_operations: VecDeque<TpmMetric>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SecurityAlertMetric {
    pub alert_type: String,
    pub severity: String,
    pub count: u64,
    pub timestamp: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MqttMetric {
    pub direction: String, // "publish" or "subscribe"
    pub topic: String,
    pub message_size: usize,
    pub timestamp: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TpmMetric {
    pub operation: String,
    pub success: bool,
    pub duration_ms: f64,
    pub timestamp: i64,
}

impl MetricsCollector {
    /// Create a new metrics collector
    pub fn new() -> Self {
        Self {
            metrics: HashMap::new(),
            actuation_latencies: VecDeque::with_capacity(1000),
            divergence_scores: VecDeque::with_capacity(1000),
            network_egress: HashMap::new(),
            security_alerts: VecDeque::with_capacity(500),
            mqtt_messages: VecDeque::with_capacity(10000),
            tpm_operations: VecDeque::with_capacity(1000),
        }
    }

    /// Record actuation latency
    pub async fn record_actuation_latency(&mut self, latency_ms: f64) {
        self.actuation_latencies.push_back(latency_ms);
        
        // Keep only last 1000 samples
        if self.actuation_latencies.len() > 1000 {
            self.actuation_latencies.pop_front();
        }

        // Update metric
        let mean = self.calculate_mean(&self.actuation_latencies);
        self.metrics.insert(
            "actuation_latency_mean".to_string(),
            MetricData {
                name: "actuation_latency_mean".to_string(),
                metric_type: MetricType::Gauge,
                value: MetricValue::Gauge(mean),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );
    }

    /// Record agent divergence score
    pub async fn record_divergence(&mut self, divergence_score: f64) {
        self.divergence_scores.push_back(divergence_score);
        
        if self.divergence_scores.len() > 1000 {
            self.divergence_scores.pop_front();
        }

        let mean = self.calculate_mean(&self.divergence_scores);
        self.metrics.insert(
            "agent_divergence_mean".to_string(),
            MetricData {
                name: "agent_divergence_mean".to_string(),
                metric_type: MetricType::Gauge,
                value: MetricValue::Gauge(mean),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );
    }

    /// Record external network egress attempt
    pub async fn record_network_egress(&mut self, destination: &str, blocked: bool) {
        let key = if blocked { "blocked" } else { "allowed" };
        *self.network_egress.entry(format!("{}:{}", destination, key)).or_insert(0) += 1;

        // Update total blocked/allowed counters
        let total_key = if blocked { "total_blocked" } else { "total_allowed" };
        *self.network_egress.entry(total_key.to_string()).or_insert(0) += 1;
    }

    /// Record security alert
    pub async fn record_security_alert(&mut self, alert_type: &str, severity: &str) {
        self.security_alerts.push_back(SecurityAlertMetric {
            alert_type: alert_type.to_string(),
            severity: severity.to_string(),
            count: 1,
            timestamp: Utc::now().timestamp(),
        });

        if self.security_alerts.len() > 500 {
            self.security_alerts.pop_front();
        }

        // Update counters by type
        let auth_failures = self.security_alerts
            .iter()
            .filter(|a| a.alert_type == "authentication_failure")
            .count() as u64;
        
        let unauthorized_access = self.security_alerts
            .iter()
            .filter(|a| a.alert_type == "unauthorized_access")
            .count() as u64;

        self.metrics.insert(
            "security_alerts_auth_failures".to_string(),
            MetricData {
                name: "security_alerts_auth_failures".to_string(),
                metric_type: MetricType::Counter,
                value: MetricValue::Counter(auth_failures),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );

        self.metrics.insert(
            "security_alerts_unauthorized_access".to_string(),
            MetricData {
                name: "security_alerts_unauthorized_access".to_string(),
                metric_type: MetricType::Counter,
                value: MetricValue::Counter(unauthorized_access),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );
    }

    /// Record MQTT message
    pub async fn record_mqtt_message(&mut self, direction: &str, topic: &str, size: usize) {
        self.mqtt_messages.push_back(MqttMetric {
            direction: direction.to_string(),
            topic: topic.to_string(),
            message_size: size,
            timestamp: Utc::now().timestamp(),
        });

        if self.mqtt_messages.len() > 10000 {
            self.mqtt_messages.pop_front();
        }

        // Calculate throughput (messages per second)
        let now = Utc::now().timestamp();
        let window_start = now - 60; // Last 60 seconds
        let messages_in_window: usize = self.mqtt_messages
            .iter()
            .filter(|m| m.timestamp >= window_start)
            .count();

        self.metrics.insert(
            "mqtt_throughput".to_string(),
            MetricData {
                name: "mqtt_throughput".to_string(),
                metric_type: MetricType::Gauge,
                value: MetricValue::Gauge(messages_in_window as f64 / 60.0),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );
    }

    /// Record TPM operation
    pub async fn record_tpm_operation(&mut self, operation: &str, success: bool, duration_ms: f64) {
        self.tpm_operations.push_back(TpmMetric {
            operation: operation.to_string(),
            success,
            duration_ms,
            timestamp: Utc::now().timestamp(),
        });

        if self.tpm_operations.len() > 1000 {
            self.tpm_operations.pop_front();
        }

        // Calculate success rate
        let total = self.tpm_operations.len() as u64;
        let successful = self.tpm_operations
            .iter()
            .filter(|op| op.success)
            .count() as u64;
        
        let success_rate = if total > 0 { 
            (successful as f64 / total as f64) * 100.0 
        } else { 
            0.0 
        };

        self.metrics.insert(
            "tpm_operation_success_rate".to_string(),
            MetricData {
                name: "tpm_operation_success_rate".to_string(),
                metric_type: MetricType::Gauge,
                value: MetricValue::Gauge(success_rate),
                labels: HashMap::new(),
                timestamp: Utc::now().timestamp(),
            },
        );
    }

    /// Get all metrics
    pub fn get_metrics(&self) -> &HashMap<String, MetricData> {
        &self.metrics
    }

    /// Get actuation latency statistics
    pub fn get_actuation_latency_stats(&self) -> ActuationLatencyStats {
        let latencies: Vec<f64> = self.actuation_latencies.iter().copied().collect();
        ActuationLatencyStats {
            mean: self.calculate_mean(&latencies),
            p50: self.calculate_percentile(&latencies, 50.0),
            p95: self.calculate_percentile(&latencies, 95.0),
            p99: self.calculate_percentile(&latencies, 99.0),
            max: latencies.iter().copied().fold(0.0f64, f64::max),
            sample_count: latencies.len(),
        }
    }

    /// Get network egress data
    pub fn get_network_egress(&self) -> &HashMap<String, u64> {
        &self.network_egress
    }

    /// Get security alert counts
    pub fn get_security_alert_counts(&self) -> HashMap<String, u64> {
        let mut counts = HashMap::new();
        for alert in &self.security_alerts {
            *counts.entry(alert.alert_type.clone()).or_insert(0) += 1;
        }
        counts
    }

    fn calculate_mean(&self, values: &[f64]) -> f64 {
        if values.is_empty() {
            return 0.0;
        }
        values.iter().sum::<f64>() / values.len() as f64
    }

    fn calculate_percentile(&self, values: &[f64], percentile: f64) -> f64 {
        if values.is_empty() {
            return 0.0;
        }
        let mut sorted = values.to_vec();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let index = ((percentile / 100.0) * (sorted.len() - 1) as f64).round() as usize;
        sorted[index.min(sorted.len() - 1)]
    }
}

/// Actuation latency statistics
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ActuationLatencyStats {
    pub mean: f64,
    pub p50: f64,
    pub p95: f64,
    pub p99: f64,
    pub max: f64,
    pub sample_count: usize,
}

/// Actuation latency tracker for continuous monitoring
pub struct ActuationLatencyTracker {
    start_time: Option<Instant>,
    collector: Arc<RwLock<MetricsCollector>>,
}

impl ActuationLatencyTracker {
    /// Create a new latency tracker
    pub fn new(collector: Arc<RwLock<MetricsCollector>>) -> Self {
        Self {
            start_time: None,
            collector,
        }
    }

    /// Start timing an actuation
    pub fn start(&mut self) {
        self.start_time = Some(Instant::now());
    }

    /// Finish timing and record latency
    pub async fn finish(&mut self) {
        if let Some(start) = self.start_time.take() {
            let latency = start.elapsed().as_secs_f64() * 1000.0; // Convert to ms
            let mut collector = self.collector.write().await;
            collector.record_actuation_latency(latency).await;
        }
    }
}

/// Agent divergence detector
pub struct AgentDivergenceDetector {
    expected_behavior: Vec<f64>,
    collector: Arc<RwLock<MetricsCollector>>,
    threshold: f64,
}

impl AgentDivergenceDetector {
    /// Create a new divergence detector
    pub fn new(
        expected_behavior: Vec<f64>,
        collector: Arc<RwLock<MetricsCollector>>,
        threshold: f64,
    ) -> Self {
        Self {
            expected_behavior,
            collector,
            threshold,
        }
    }

    /// Check for divergence from expected behavior
    pub async fn check_divergence(&mut self, observed_behavior: &[f64]) -> bool {
        let divergence = self.calculate_divergence(observed_behavior);
        
        let mut collector = self.collector.write().await;
        collector.record_divergence(divergence).await;

        divergence > self.threshold
    }

    fn calculate_divergence(&self, observed: &[f64]) -> f64 {
        if observed.is_empty() || self.expected_behavior.is_empty() {
            return 0.0;
        }

        let sum: f64 = observed.iter()
            .zip(self.expected_behavior.iter())
            .map(|(o, e)| (o - e).powi(2))
            .sum();

        sum.sqrt()
    }
}

/// Network egress monitor
pub struct NetworkEgressMonitor {
    collector: Arc<RwLock<MetricsCollector>>,
    allowed_destinations: Vec<String>,
}

impl NetworkEgressMonitor {
    /// Create a new network egress monitor
    pub fn new(
        collector: Arc<RwLock<MetricsCollector>>,
        allowed_destinations: Vec<String>,
    ) -> Self {
        Self {
            collector,
            allowed_destinations,
        }
    }

    /// Check if destination is allowed and record the check
    pub async fn check_egress(&mut self, destination: &str) -> bool {
        let allowed = self.allowed_destinations.iter()
            .any(|d| destination.starts_with(d));
        
        let mut collector = self.collector.write().await;
        collector.record_network_egress(destination, !allowed).await;

        allowed
    }
}

/// TPM operation tracker
pub struct TpmOperationTracker {
    collector: Arc<RwLock<MetricsCollector>>,
}

impl TpmOperationTracker {
    /// Create a new TPM operation tracker
    pub fn new(collector: Arc<RwLock<MetricsCollector>>) -> Self {
        Self { collector }
    }

    /// Track a TPM operation
    pub async fn track_operation(&mut self, operation: &str, success: bool, duration: Duration) {
        let mut collector = self.collector.write().await;
        collector.record_tpm_operation(operation, success, duration.as_secs_f64() * 1000.0).await;
    }
}

/// MQTT throughput tracker
pub struct MqttThroughputTracker {
    collector: Arc<RwLock<MetricsCollector>>,
}

impl MqttThroughputTracker {
    /// Create a new MQTT throughput tracker
    pub fn new(collector: Arc<RwLock<MetricsCollector>>) -> Self {
        Self { collector }
    }

    /// Track MQTT message
    pub async fn track_message(&mut self, direction: &str, topic: &str, size: usize) {
        let mut collector = self.collector.write().await;
        collector.record_mqtt_message(direction, topic, size).await;
    }
}

/// Prometheus-compatible metrics exporter
pub struct PrometheusExporter;

impl PrometheusExporter {
    /// Export all metrics in Prometheus format
    pub fn export(collector: &MetricsCollector) -> String {
        let mut output = String::new();

        for (name, metric) in collector.get_metrics() {
            let labels_str = if metric.labels.is_empty() {
                String::new()
            } else {
                let labels: Vec<String> = metric.labels
                    .iter()
                    .map(|(k, v)| format!("{}=\"{}\"", k, v))
                    .collect();
                format!("{{{}}}", labels.join(","))
            };

            match &metric.value {
                MetricValue::Counter(v) => {
                    output.push_str(&format!("{}#{} {}\n", name, labels_str, v));
                }
                MetricValue::Gauge(v) => {
                    output.push_str(&format!("{}{} {}\n", name, labels_str, v));
                }
                MetricValue::Histogram(buckets) => {
                    for (i, bucket) in buckets.iter().enumerate() {
                        output.push_str(&format!("{}_bucket{}{} {}\n", 
                            name, labels_str, format!(" +Inf {}", i), bucket));
                    }
                    output.push_str(&format!("{}_sum{} {}\n", name, labels_str, 
                        buckets.iter().sum::<f64>()));
                    output.push_str(&format!("{}_count{} {}\n", name, labels_str, buckets.len()));
                }
                MetricValue::Summary { sum, count } => {
                    output.push_str(&format!("{}_sum{} {}\n", name, labels_str, sum));
                    output.push_str(&format!("{}_count{} {}\n", name, labels_str, count));
                }
            }
        }

        output
    }

    /// Export metrics as JSON
    pub fn export_json(collector: &MetricsCollector) -> String {
        serde_json::to_string_pretty(collector.get_metrics()).unwrap_or_default()
    }
}

impl Default for MetricsCollector {
    fn default() -> Self {
        Self::new()
    }
}
