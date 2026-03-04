//! # Metrics - Prometheus Metrics
//!
//! Prometheus metrics endpoint for observability.

use prometheus::{Counter, Gauge, Histogram, Registry};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::debug;

/// Metrics collector
pub struct Metrics {
    registry: Registry,
    
    // Runtime metrics
    pub runtime_start_time: Gauge,
    pub active_sessions: Gauge,
    pub events_processed: Counter,
    pub errors_total: Counter,
    
    // Capability metrics
    pub capability_executions: Counter,
    pub capability_duration: Histogram,
    pub capability_errors: Counter,
    
    // Knowledge graph metrics
    pub entities_total: Gauge,
    pub relationships_total: Gauge,
    pub queries_total: Counter,
    
    // HTTP metrics
    pub http_requests_total: Counter,
    pub http_request_duration: Histogram,
    pub http_errors: Counter,
}

impl Metrics {
    /// Create new metrics collector
    pub fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let registry = Registry::new();
        
        let runtime_start_time = Gauge::new("jarvis_runtime_start_time", "Runtime start time")?;
        let active_sessions = Gauge::new("jarvis_active_sessions", "Number of active sessions")?;
        let events_processed = Counter::new("jarvis_events_processed_total", "Total events processed")?;
        let errors_total = Counter::new("jarvis_errors_total", "Total errors")?;
        
        let capability_executions = Counter::new("jarvis_capability_executions_total", "Total capability executions")?;
        let capability_duration = Histogram::new(prometheus::opts!(
            "jarvis_capability_duration_seconds",
            "Capability execution duration"
        ))?;
        let capability_errors = Counter::new("jarvis_capability_errors_total", "Total capability errors")?;
        
        let entities_total = Gauge::new("jarvis_entities_total", "Total entities in knowledge graph")?;
        let relationships_total = Gauge::new("jarvis_relationships_total", "Total relationships in knowledge graph")?;
        let queries_total = Counter::new("jarvis_graph_queries_total", "Total graph queries")?;
        
        let http_requests_total = Counter::new("jarvis_http_requests_total", "Total HTTP requests")?;
        let http_request_duration = Histogram::new(prometheus::opts!(
            "jarvis_http_request_duration_seconds",
            "HTTP request duration"
        ))?;
        let http_errors = Counter::new("jarvis_http_errors_total", "Total HTTP errors")?;
        
        registry.register(Box::new(runtime_start_time.clone()))?;
        registry.register(Box::new(active_sessions.clone()))?;
        registry.register(Box::new(events_processed.clone()))?;
        registry.register(Box::new(errors_total.clone()))?;
        registry.register(Box::new(capability_executions.clone()))?;
        registry.register(Box::new(capability_duration.clone()))?;
        registry.register(Box::new(capability_errors.clone()))?;
        registry.register(Box::new(entities_total.clone()))?;
        registry.register(Box::new(relationships_total.clone()))?;
        registry.register(Box::new(queries_total.clone()))?;
        registry.register(Box::new(http_requests_total.clone()))?;
        registry.register(Box::new(http_request_duration.clone()))?;
        registry.register(Box::new(http_errors.clone()))?;
        
        // Set start time
        runtime_start_time.set(chrono::Utc::now().timestamp() as f64);
        
        Ok(Self {
            registry,
            runtime_start_time,
            active_sessions,
            events_processed,
            errors_total,
            capability_executions,
            capability_duration,
            capability_errors,
            entities_total,
            relationships_total,
            queries_total,
            http_requests_total,
            http_request_duration,
            http_errors,
        })
    }

    /// Get Prometheus registry
    pub fn registry(&self) -> &Registry {
        &self.registry
    }

    /// Record capability execution
    pub fn record_capability(&self, name: &str, duration_secs: f64, error: bool) {
        self.capability_executions.inc();
        self.capability_duration.observe(duration_secs);
        if error {
            self.capability_errors.inc();
        }
    }

    /// Record HTTP request
    pub fn record_http_request(&self, duration_secs: f64, error: bool) {
        self.http_requests_total.inc();
        self.http_request_duration.observe(duration_secs);
        if error {
            self.http_errors.inc();
        }
    }

    /// Update session count
    pub fn set_active_sessions(&self, count: f64) {
        self.active_sessions.set(count);
    }

    /// Update knowledge graph metrics
    pub fn update_graph_metrics(&self, entities: usize, relationships: usize) {
        self.entities_total.set(entities as f64);
        self.relationships_total.set(relationships as f64);
    }

    /// Increment events processed
    pub fn inc_events(&self) {
        self.events_processed.inc();
    }

    /// Increment errors
    pub fn inc_errors(&self) {
        self.errors_total.inc();
    }

    /// Increment queries
    pub fn inc_queries(&self) {
        self.queries_total.inc();
    }
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new().expect("Failed to create metrics")
    }
}
