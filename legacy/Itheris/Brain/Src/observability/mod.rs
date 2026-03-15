//! # Observability Module for Warden Architecture
//! 
//! Runtime monitoring, metrics collection, and security alerts for the
//! cyber-physical control loop.
//! 
//! ## Components
//! 
//! - [`metrics_collector`](metrics_collector) - Async metrics collection with Prometheus export
//! - [`dashboard`](dashboard) - Real-time dashboard data structures and APIs
//! - [`alerts`](alerts) - Security alert management and routing

pub mod metrics_collector;
pub mod dashboard;
pub mod alerts;

// Re-exports
pub use metrics_collector::{
    MetricsCollector, MetricValue, MetricType, ActuationLatencyTracker,
    AgentDivergenceDetector, NetworkEgressMonitor, TpmOperationTracker,
    MqttThroughputTracker, PrometheusExporter, COLLECTOR_REGISTRY,
};

pub use dashboard::{
    DashboardData, SystemStatus, HistoricalData, AlertThreshold,
    DashboardApi, HistoricalAggregation, StatusLevel,
};

pub use alerts::{
    SecurityAlert, AlertSeverity, AlertType, AlertAggregator,
    AlertRouter, AlertNotifier, AlertHistory, DeduplicationWindow,
    ALERT_CHANNELS, create_security_alert, aggregate_alerts,
};
