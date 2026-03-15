//! # Security Alerts Module for Warden Architecture
//! 
//! Alert types, severity levels, aggregation, deduplication, routing,
//! and notification for security events.
//! 
//! ## Features
//! 
//! - Alert types and severity levels
//! - Alert aggregation and deduplication
//! - Alert routing and notification
//! - Alert history and analysis

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use chrono::{DateTime, Utc, Duration};
use uuid::Uuid;

/// Alert severity levels
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlertSeverity {
    Info,
    Warning,
    Error,
    Critical,
}

impl AlertSeverity {
    pub fn as_str(&self) -> &'static str {
        match self {
            AlertSeverity::Info => "INFO",
            AlertSeverity::Warning => "WARNING",
            AlertSeverity::Error => "ERROR",
            AlertSeverity::Critical => "CRITICAL",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "INFO" => AlertSeverity::Info,
            "WARNING" => AlertSeverity::Warning,
            "ERROR" => AlertSeverity::Error,
            "CRITICAL" => AlertSeverity::Critical,
            _ => AlertSeverity::Info,
        }
    }
}

/// Alert types
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AlertType {
    AuthenticationFailure,
    UnauthorizedAccess,
    NetworkEgressBlocked,
    DivergenceDetected,
    ActuationLatencyHigh,
    TpmOperationFailed,
    MqttConnectionLost,
    PolicyViolation,
    AnomalyDetected,
}

impl AlertType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AlertType::AuthenticationFailure => "AUTHENTICATION_FAILURE",
            AlertType::UnauthorizedAccess => "UNAUTHORIZED_ACCESS",
            AlertType::NetworkEgressBlocked => "NETWORK_EGRESS_BLOCKED",
            AlertType::DivergenceDetected => "DIVERGENCE_DETECTED",
            AlertType::ActuationLatencyHigh => "ACTUATION_LATENCY_HIGH",
            AlertType::TpmOperationFailed => "TPM_OPERATION_FAILED",
            AlertType::MqttConnectionLost => "MQTT_CONNECTION_LOST",
            AlertType::PolicyViolation => "POLICY_VIOLATION",
            AlertType::AnomalyDetected => "ANOMALY_DETECTED",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_uppercase().as_str() {
            "AUTHENTICATION_FAILURE" => Some(AlertType::AuthenticationFailure),
            "UNAUTHORIZED_ACCESS" => Some(AlertType::UnauthorizedAccess),
            "NETWORK_EGRESS_BLOCKED" => Some(AlertType::NetworkEgressBlocked),
            "DIVERGENCE_DETECTED" => Some(AlertType::DivergenceDetected),
            "ACTUATION_LATENCY_HIGH" => Some(AlertType::ActuationLatencyHigh),
            "TPM_OPERATION_FAILED" => Some(AlertType::TpmOperationFailed),
            "MQTT_CONNECTION_LOST" => Some(AlertType::MqttConnectionLost),
            "POLICY_VIOLATION" => Some(AlertType::PolicyViolation),
            "ANOMALY_DETECTED" => Some(AlertType::AnomalyDetected),
            _ => None,
        }
    }
}

/// Security alert
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SecurityAlert {
    pub id: String,
    pub alert_type: String,
    pub severity: String,
    pub title: String,
    pub description: String,
    pub source: String,
    pub timestamp: i64,
    pub resolved: bool,
    pub metadata: HashMap<String, String>,
    pub tags: Vec<String>,
}

/// Alert channel for routing
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AlertChannel {
    pub name: String,
    pub channel_type: ChannelType,
    pub config: HashMap<String, String>,
    pub enabled: bool,
}

/// Channel types
#[derive(Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ChannelType {
    Log,
    Webhook,
    Email,
    Sms,
    Console,
}

impl ChannelType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ChannelType::Log => "LOG",
            ChannelType::Webhook => "WEBHOOK",
            ChannelType::Email => "EMAIL",
            ChannelType::Sms => "SMS",
            ChannelType::Console => "CONSOLE",
        }
    }
}

/// Global alert channels
pub static ALERT_CHANNELS: std::sync::OnceLock<Arc<RwLock<Vec<AlertChannel>>>> = 
    std::sync::OnceLock::new();

/// Get or initialize alert channels
pub fn get_alert_channels() -> Arc<RwLock<Vec<AlertChannel>>> {
    ALERT_CHANNELS.get_or_init(|| {
        Arc::new(RwLock::new(vec![
            AlertChannel {
                name: "console".to_string(),
                channel_type: ChannelType::Console,
                config: HashMap::new(),
                enabled: true,
            },
            AlertChannel {
                name: "log".to_string(),
                channel_type: ChannelType::Log,
                config: HashMap::new(),
                enabled: true,
            },
        ]))
    }).clone()
}

/// Create a security alert
pub fn create_security_alert(
    alert_type: AlertType,
    severity: AlertSeverity,
    title: &str,
    description: &str,
    source: &str,
    metadata: HashMap<String, String>,
) -> SecurityAlert {
    SecurityAlert {
        id: Uuid::new_v4().to_string(),
        alert_type: alert_type.as_str().to_string(),
        severity: severity.as_str().to_string(),
        title: title.to_string(),
        description: description.to_string(),
        source: source.to_string(),
        timestamp: Utc::now().timestamp(),
        resolved: false,
        metadata,
        tags: vec![alert_type.as_str().to_string()],
    }
}

/// Deduplication window for alerts
pub struct DeduplicationWindow {
    seen_hashes: HashSet<u64>,
    window_duration: Duration,
    last_cleanup: DateTime<Utc>,
}

impl DeduplicationWindow {
    /// Create a new deduplication window
    pub fn new(window_seconds: i64) -> Self {
        Self {
            seen_hashes: HashSet::new(),
            window_duration: Duration::seconds(window_seconds),
            last_cleanup: Utc::now(),
        }
    }

    /// Check if alert is duplicate
    pub fn is_duplicate(&mut self, alert: &SecurityAlert) -> bool {
        // Clean up old entries periodically
        let now = Utc::now();
        if (now - self.last_cleanup) > self.window_duration {
            self.seen_hashes.clear();
            self.last_cleanup = now;
        }

        // Calculate hash of alert content
        let hash = self.calculate_hash(alert);
        
        if self.seen_hashes.contains(&hash) {
            return true;
        }

        self.seen_hashes.insert(hash);
        false
    }

    fn calculate_hash(&self, alert: &SecurityAlert) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        
        let mut hasher = DefaultHasher::new();
        alert.alert_type.hash(&mut hasher);
        alert.severity.hash(&mut hasher);
        alert.source.hash(&mut hasher);
        
        // Hash timestamp to window
        let window_index = alert.timestamp / self.window_duration.num_seconds();
        window_index.hash(&mut hasher);
        
        hasher.finish()
    }
}

/// Alert aggregator for combining similar alerts
pub struct AlertAggregator {
    aggregation_window: Duration,
    aggregated_alerts: HashMap<String, AggregatedAlert>,
}

#[derive(Clone, Debug)]
pub struct AggregatedAlert {
    pub alert_type: String,
    pub count: u64,
    pub first_seen: i64,
    pub last_seen: i64,
    pub severity: String,
    pub sources: HashSet<String>,
}

impl AlertAggregator {
    /// Create a new alert aggregator
    pub fn new(window_seconds: i64) -> Self {
        Self {
            aggregation_window: Duration::seconds(window_seconds),
            aggregated_alerts: HashMap::new(),
        }
    }

    /// Add alert to aggregation
    pub fn add_alert(&mut self, alert: &SecurityAlert) {
        let key = format!("{}:{}", alert.alert_type, alert.severity);
        
        if let Some(aggregated) = self.aggregated_alerts.get_mut(&key) {
            aggregated.count += 1;
            aggregated.last_seen = alert.timestamp;
            aggregated.sources.insert(alert.source.clone());
        } else {
            self.aggregated_alerts.insert(key, AggregatedAlert {
                alert_type: alert.alert_type.clone(),
                count: 1,
                first_seen: alert.timestamp,
                last_seen: alert.timestamp,
                severity: alert.severity.clone(),
                sources: vec![alert.source.clone()].into_iter().collect(),
            });
        }
    }

    /// Get aggregated alerts
    pub fn get_aggregated(&self) -> Vec<AggregatedAlert> {
        self.aggregated_alerts.values().cloned().collect()
    }

    /// Aggregate a list of alerts
    pub fn aggregate(alerts: &[SecurityAlert]) -> Vec<AggregatedAlert> {
        let mut aggregator = Self::new(300); // 5 minute window
        for alert in alerts {
            aggregator.add_alert(alert);
        }
        aggregator.get_aggregated()
    }
}

/// Aggregate alerts helper function
pub fn aggregate_alerts(alerts: &[SecurityAlert]) -> Vec<AggregatedAlert> {
    AlertAggregator::aggregate(alerts)
}

/// Alert router for directing alerts to channels
pub struct AlertRouter {
    channels: Arc<RwLock<Vec<AlertChannel>>>,
    routing_rules: Vec<RoutingRule>,
}

#[derive(Clone, Debug)]
pub struct RoutingRule {
    pub alert_type: Option<String>,
    pub severity: Option<String>,
    pub channel_name: String,
    pub enabled: bool,
}

impl AlertRouter {
    /// Create a new alert router
    pub fn new(channels: Arc<RwLock<Vec<AlertChannel>>>) -> Self {
        Self {
            channels,
            routing_rules: Vec::new(),
        }
    }

    /// Add routing rule
    pub fn add_rule(&mut self, rule: RoutingRule) {
        self.routing_rules.push(rule);
    }

    /// Route alert to appropriate channels
    pub async fn route(&self, alert: &SecurityAlert) -> Vec<String> {
        let channels = self.channels.read().await;
        let mut routed = Vec::new();

        for rule in &self.routing_rules {
            if !rule.enabled {
                continue;
            }

            // Check if alert matches rule
            let type_match = rule.alert_type.as_ref()
                .map(|t| t == &alert.alert_type)
                .unwrap_or(true);
            
            let severity_match = rule.severity.as_ref()
                .map(|s| s == &alert.severity)
                .unwrap_or(true);

            if type_match && severity_match {
                // Check if channel exists and is enabled
                if let Some(channel) = channels.iter().find(|c| c.name == rule.channel_name) {
                    if channel.enabled {
                        routed.push(channel.name.clone());
                    }
                }
            }
        }

        // Always add console for critical alerts
        if alert.severity == AlertSeverity::Critical.as_str() {
            if !routed.contains(&"console".to_string()) {
                routed.push("console".to_string());
            }
        }

        routed
    }
}

/// Alert notifier for sending alerts to channels
pub struct AlertNotifier {
    router: AlertRouter,
    history: Arc<RwLock<AlertHistory>>,
}

impl AlertNotifier {
    /// Create a new alert notifier
    pub fn new(router: AlertRouter, history: Arc<RwLock<AlertHistory>>) -> Self {
        Self { router, history }
    }

    /// Send alert
    pub async fn send(&self, alert: &SecurityAlert) {
        // Route alert
        let channels = self.router.route(alert).await;

        // Send to each channel
        for channel in &channels {
            self.send_to_channel(alert, channel).await;
        }

        // Record in history
        let mut history = self.history.write().await;
        history.record(alert.clone()).await;
    }

    /// Send alert to specific channel
    async fn send_to_channel(&self, alert: &SecurityAlert, channel: &str) {
        match channel {
            "console" => {
                println!(
                    "[ALERT][{}][{}] {} - {}",
                    alert.severity,
                    alert.alert_type,
                    alert.title,
                    alert.description
                );
            }
            "log" => {
                // Would integrate with logging system
                log::warn!(
                    "[ALERT][{}][{}] {} - {}",
                    alert.severity,
                    alert.alert_type,
                    alert.title,
                    alert.description
                );
            }
            _ => {
                // Handle other channel types
            }
        }
    }
}

/// Alert history for analysis
pub struct AlertHistory {
    alerts: VecDeque<SecurityAlert>,
    max_size: usize,
    by_type: HashMap<String, u64>,
    by_severity: HashMap<String, u64>,
}

impl AlertHistory {
    /// Create a new alert history
    pub fn new(max_size: usize) -> Self {
        Self {
            alerts: VecDeque::with_capacity(max_size),
            max_size,
            by_type: HashMap::new(),
            by_severity: HashMap::new(),
        }
    }

    /// Record an alert
    pub async fn record(&mut self, alert: SecurityAlert) {
        // Update counters
        *self.by_type.entry(alert.alert_type.clone()).or_insert(0) += 1;
        *self.by_severity.entry(alert.severity.clone()).or_insert(0) += 1;

        // Add to queue
        self.alerts.push_back(alert);

        // Remove oldest if over capacity
        if self.alerts.len() > self.max_size {
            if let Some(oldest) = self.alerts.pop_front() {
                // Decrement counters
                if let Some(count) = self.by_type.get_mut(&oldest.alert_type) {
                    if *count > 0 { *count -= 1; }
                }
                if let Some(count) = self.by_severity.get_mut(&oldest.severity) {
                    if *count > 0 { *count -= 1; }
                }
            }
        }
    }

    /// Get all alerts
    pub fn get_all(&self) -> Vec<SecurityAlert> {
        self.alerts.iter().cloned().collect()
    }

    /// Get alerts by type
    pub fn get_by_type(&self, alert_type: &str) -> Vec<SecurityAlert> {
        self.alerts
            .iter()
            .filter(|a| a.alert_type == alert_type)
            .cloned()
            .collect()
    }

    /// Get alerts by severity
    pub fn get_by_severity(&self, severity: &str) -> Vec<SecurityAlert> {
        self.alerts
            .iter()
            .filter(|a| a.severity == severity)
            .cloned()
            .collect()
    }

    /// Get unresolved alerts
    pub fn get_unresolved(&self) -> Vec<SecurityAlert> {
        self.alerts
            .iter()
            .filter(|a| !a.resolved)
            .cloned()
            .collect()
    }

    /// Resolve an alert
    pub fn resolve(&mut self, alert_id: &str) -> Result<(), String> {
        if let Some(alert) = self.alerts.iter_mut().find(|a| a.id == alert_id) {
            alert.resolved = true;
            Ok(())
        } else {
            Err(format!("Alert not found: {}", alert_id))
        }
    }

    /// Get count by type
    pub fn count_by_type(&self) -> &HashMap<String, u64> {
        &self.by_type
    }

    /// Get count by severity
    pub fn count_by_severity(&self) -> &HashMap<String, u64> {
        &self.by_severity
    }

    /// Get total count
    pub fn total_count(&self) -> usize {
        self.alerts.len()
    }

    /// Get unresolvable count
    pub fn unresolved_count(&self) -> usize {
        self.alerts.iter().filter(|a| !a.resolved).count()
    }

    /// Analyze alert patterns
    pub fn analyze(&self) -> AlertAnalysis {
        let mut patterns = Vec::new();

        // Find most common alert type
        if let Some((alert_type, count)) = self.by_type.iter().max_by_key(|(_, c)| *c) {
            patterns.push(format!("Most common: {} ({})", alert_type, count));
        }

        // Find most common severity
        if let Some((severity, count)) = self.by_severity.iter().max_by_key(|(_, c)| *c) {
            patterns.push(format!("Most frequent severity: {} ({})", severity, count));
        }

        // Check for critical alerts
        if let Some(critical_count) = self.by_severity.get(AlertSeverity::Critical.as_str()) {
            if *critical_count > 10 {
                patterns.push(format!("HIGH CRITICAL ALERT COUNT: {}", critical_count));
            }
        }

        AlertAnalysis {
            total_alerts: self.alerts.len(),
            unresolved_count: self.unresolved_count(),
            by_type: self.by_type.clone(),
            by_severity: self.by_severity.clone(),
            patterns,
        }
    }
}

/// Alert analysis result
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AlertAnalysis {
    pub total_alerts: usize,
    pub unresolved_count: usize,
    pub by_type: HashMap<String, u64>,
    pub by_severity: HashMap<String, u64>,
    pub patterns: Vec<String>,
}

impl Default for AlertHistory {
    fn default() -> Self {
        Self::new(1000)
    }
}
