//! Monitoring & Observability - metrics, alerts, and health checks

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use chrono::Local;

/// A metric measurement
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Metric {
    pub name: String,
    pub value: f32,
    pub unit: String,
    pub timestamp: String,
    pub tags: HashMap<String, String>,
}

/// An alert
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Alert {
    pub id: String,
    pub metric_name: String,
    pub threshold: f32,
    pub current_value: f32,
    pub condition: String, // GREATER_THAN, LESS_THAN, EQUALS
    pub severity: String,  // INFO, WARNING, CRITICAL
    pub timestamp: String,
    pub resolved: bool,
}

/// Monitoring system
pub struct Monitor {
    metrics: HashMap<String, Vec<Metric>>,
    alerts: Vec<Alert>,
    alert_rules: Vec<(String, f32, String)>,
}

impl Monitor {
    pub fn new() -> Self {
        Monitor {
            metrics: HashMap::new(),
            alerts: Vec::new(),
            alert_rules: Vec::new(),
        }
    }

    /// Register an alert rule
    pub fn register_alert_rule(&mut self, metric_name: &str, threshold: f32, condition: &str) {
        self.alert_rules
            .push((metric_name.to_string(), threshold, condition.to_string()));
        println!(
            "[MONITOR] ✓ Alert rule: {} {} {}",
            metric_name, condition, threshold
        );
    }

    /// Record a metric
    pub fn record_metric(
        &mut self,
        name: &str,
        value: f32,
        unit: &str,
        tags: HashMap<String, String>,
    ) {
        let metric = Metric {
            name: name.to_string(),
            value,
            unit: unit.to_string(),
            timestamp: Local::now().to_rfc3339(),
            tags,
        };

        self.metrics
            .entry(name.to_string())
            .or_insert_with(Vec::new)
            .push(metric.clone());

        // Check alert rules - collect needed data first to avoid borrow issues
        let alerts_to_create: Vec<(String, f32, String)> = self.alert_rules.iter()
            .filter(|(rule_metric, _, _)| rule_metric == name)
            .filter_map(|(rule_metric, threshold, condition)| {
                let triggered = match condition.as_str() {
                    "GREATER_THAN" => value > *threshold,
                    "LESS_THAN" => value < *threshold,
                    "EQUALS" => (value - threshold).abs() < 0.01,
                    _ => false,
                };
                if triggered {
                    Some((name.to_string(), *threshold, condition.clone()))
                } else {
                    None
                }
            })
            .collect();

        // Now create alerts (mutable borrow)
        for (alert_name, threshold, condition) in alerts_to_create {
            self.create_alert(&alert_name, value, threshold, &condition);
        }
    }

    /// Create an alert
    fn create_alert(
        &mut self,
        metric_name: &str,
        current_value: f32,
        threshold: f32,
        condition: &str,
    ) {
        let severity = if (current_value - threshold).abs() > threshold * 0.5 {
            "CRITICAL"
        } else {
            "WARNING"
        };

        let alert = Alert {
            id: uuid::Uuid::new_v4().to_string(),
            metric_name: metric_name.to_string(),
            threshold,
            current_value,
            condition: condition.to_string(),
            severity: severity.to_string(),
            timestamp: Local::now().to_rfc3339(),
            resolved: false,
        };

        println!(
            "[MONITOR] 🚨 Alert: {} = {} (threshold: {}) [{}]",
            metric_name, current_value, threshold, severity
        );

        self.alerts.push(alert);
    }

    /// Resolve an alert
    pub fn resolve_alert(&mut self, alert_id: &str) -> Result<(), String> {
        if let Some(alert) = self.alerts.iter_mut().find(|a| a.id == alert_id) {
            alert.resolved = true;
            println!("[MONITOR] ✓ Alert resolved: {}", alert_id);
            Ok(())
        } else {
            Err(format!("Alert not found: {}", alert_id))
        }
    }

    /// Get health summary
    pub fn health_summary(&self) -> Value {
        let active_alerts = self.alerts.iter().filter(|a| !a.resolved).count();
        let critical_alerts = self
            .alerts
            .iter()
            .filter(|a| !a.resolved && a.severity == "CRITICAL")
            .count();

        json!({
            "total_metrics": self.metrics.len(),
            "total_alerts": self.alerts.len(),
            "active_alerts": active_alerts,
            "critical_alerts": critical_alerts,
            "health": if critical_alerts > 0 { "DEGRADED" } else { "HEALTHY" }
        })
    }

    pub fn get_metrics(&self) -> &HashMap<String, Vec<Metric>> {
        &self.metrics
    }

    pub fn get_alerts(&self) -> &Vec<Alert> {
        &self.alerts
    }

    pub fn alert_count(&self) -> usize {
        self.alerts.len()
    }
}

impl Default for Monitor {
    fn default() -> Self {
        Self::new()
    }
}

use uuid;