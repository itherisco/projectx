//! # Task Orchestrator - Authenticated Task Scheduling
//!
//! This module provides authenticated task orchestration with:
//! - JWT-based authentication
//! - Rate limiting
//! - Metabolic budget enforcement
//! - Priority scheduling
//!
//! ## Security Properties
//!
//! - **Authentication Required**: All task submissions must be authenticated
//! - **Rate Limiting**: Prevents task spam
//! - **Budget Enforcement**: Tasks limited by metabolic budget
//! - **Audit Trail**: All tasks logged

use crate::jwt_auth::{Claims, Role, JWTAuth, AuthConfig};
use chrono::{Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BinaryHeap, HashMap};
use std::sync::RwLock;
use std::time::{Duration as StdDuration, Instant};
use thiserror::Error;
use uuid::Uuid;

/// Task errors
#[derive(Error, Debug)]
pub enum TaskError {
    #[error("Authentication required")]
    AuthRequired,

    #[error("Insufficient permissions")]
    InsufficientPermissions,

    #[error("Rate limited")]
    RateLimited,

    #[error("Budget exceeded")]
    BudgetExceeded,

    #[error("Task not found: {0}")]
    NotFound(String),

    #[error("Invalid task: {0}")]
    InvalidTask(String),
}

/// Task priority
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum TaskPriority {
    Low = 0,
    Normal = 1,
    High = 2,
    Critical = 3,
}

impl Default for TaskPriority {
    fn default() -> Self {
        TaskPriority::Normal
    }
}

/// Task status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Cancelled,
}

/// Task definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    /// Unique task ID
    pub id: String,
    /// Task name
    pub name: String,
    /// Task description
    pub description: String,
    /// Capability to execute
    pub capability: String,
    /// Parameters (JSON)
    pub params: String,
    /// Priority
    pub priority: TaskPriority,
    /// Status
    pub status: TaskStatus,
    /// Created by (user)
    pub created_by: String,
    /// Created at
    pub created_at: u64,
    /// Started at
    pub started_at: Option<u64>,
    /// Completed at
    pub completed_at: Option<u64>,
    /// Estimated cost
    pub estimated_cost: f64,
    /// Actual cost
    pub actual_cost: Option<f64>,
    /// Error message if failed
    pub error: Option<String>,
}

/// Task request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskRequest {
    pub name: String,
    pub description: String,
    pub capability: String,
    pub params: String,
    pub priority: TaskPriority,
    pub estimated_cost: f64,
}

/// Task result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskResult {
    pub success: bool,
    pub task_id: String,
    pub result: Option<String>,
    pub error: Option<String>,
    pub cost: f64,
}

/// Metabolic budget
#[derive(Debug, Clone)]
pub struct MetabolicBudget {
    /// Total budget
    pub total: f64,
    /// Used budget
    pub used: f64,
    /// Reset period in seconds
    pub reset_period: u64,
    /// Last reset timestamp
    pub last_reset: Instant,
}

impl MetabolicBudget {
    fn new(total: f64, reset_period: u64) -> Self {
        Self {
            total,
            used: 0.0,
            reset_period,
            last_reset: Instant::now(),
        }
    }

    fn can_spend(&self, amount: f64) -> bool {
        self.used + amount <= self.total
    }

    fn spend(&mut self, amount: f64) -> bool {
        if self.can_spend(amount) {
            self.used += amount;
            true
        } else {
            false
        }
    }

    fn reset_if_needed(&mut self) {
        if self.last_reset.elapsed() > StdDuration::from_secs(self.reset_period) {
            self.used = 0.0;
            self.last_reset = Instant::now();
        }
    }
}

/// Rate limiter
#[derive(Default)]
struct TaskRateLimiter {
    requests: Vec<Instant>,
    max_requests: usize,
    window_secs: u64,
}

impl TaskRateLimiter {
    fn new(max_requests: usize, window_secs: u64) -> Self {
        Self {
            requests: Vec::new(),
            max_requests,
            window_secs,
        }
    }

    fn allow(&mut self) -> bool {
        let now = Instant::now();
        let window_start = now - StdDuration::from_secs(self.window_secs);
        
        // Remove old requests
        self.requests.retain(|&t| t > window_start);
        
        if self.requests.len() >= self.max_requests {
            return false;
        }
        
        self.requests.push(now);
        true
    }
}

/// Task Orchestrator
pub struct TaskOrchestrator {
    /// Tasks by ID
    tasks: HashMap<String, Task>,
    /// Pending task queue (by priority)
    pending_queue: BinaryHeap<Task>,
    /// JWT authentication
    auth: JWTAuth,
    /// Metabolic budget
    budget: MetabolicBudget,
    /// Rate limiter
    rate_limiter: TaskRateLimiter,
    /// Task counter
    task_counter: u64,
}

impl TaskOrchestrator {
    /// Create new orchestrator
    pub fn new(budget_total: f64, budget_reset_secs: u64, rate_limit: u32, rate_window_secs: u64) -> Self {
        Self {
            tasks: HashMap::new(),
            pending_queue: BinaryHeap::new(),
            auth: JWTAuth::with_defaults(),
            budget: MetabolicBudget::new(budget_total, budget_reset_secs),
            rate_limiter: TaskRateLimiter::new(rate_limit as usize, rate_window_secs),
            task_counter: 0,
        }
    }

    /// Create with default config
    pub fn with_defaults() -> Self {
        Self::new(1000.0, 3600, 100, 60)
    }

    /// Submit a task (authenticated)
    pub fn submit_task(
        &mut self,
        request: &TaskRequest,
        auth_token: &str,
    ) -> Result<TaskResult, TaskError> {
        // Check rate limit
        if !self.rate_limiter.allow() {
            return Err(TaskError::RateLimited);
        }

        // Authenticate
        let claims = match self.auth.validate_token(auth_token) {
            Ok(c) => c,
            Err(_) => return Err(TaskError::AuthRequired),
        };

        // Check permissions
        let has_permission = claims.roles.iter().any(|r| {
            matches!(r, Role::Admin | Role::User | Role::Service)
        });
        
        if !has_permission {
            return Err(TaskError::InsufficientPermissions);
        }

        // Check budget
        self.budget.reset_if_needed();
        if !self.budget.can_spend(request.estimated_cost) {
            return Err(TaskError::BudgetExceeded);
        }

        // Validate capability
        if request.capability.is_empty() {
            return Err(TaskError::InvalidTask("Capability required".to_string()));
        }

        // Create task
        self.task_counter += 1;
        let task_id = format!("task_{}_{}", Utc::now().timestamp(), self.task_counter);
        
        let now = Utc::now().timestamp() as u64;
        
        let task = Task {
            id: task_id.clone(),
            name: request.name.clone(),
            description: request.description.clone(),
            capability: request.capability.clone(),
            params: request.params.clone(),
            priority: request.priority,
            status: TaskStatus::Pending,
            created_by: claims.sub.clone(),
            created_at: now,
            started_at: None,
            completed_at: None,
            estimated_cost: request.estimated_cost,
            actual_cost: None,
            error: None,
        };

        // Store and queue
        self.tasks.insert(task_id.clone(), task.clone());
        self.pending_queue.push(task);

        // Reserve budget
        let _ = self.budget.spend(request.estimated_cost);

        Ok(TaskResult {
            success: true,
            task_id,
            result: None,
            error: None,
            cost: request.estimated_cost,
        })
    }

    /// Get next pending task (for workers)
    pub fn get_next_task(&mut self) -> Option<Task> {
        let task = self.pending_queue.pop()?;
        
        // Update status
        if let Some(t) = self.tasks.get_mut(&task.id) {
            t.status = TaskStatus::Running;
            t.started_at = Some(Utc::now().timestamp() as u64);
            return Some(t.clone());
        }
        
        None
    }

    /// Complete a task
    pub fn complete_task(
        &mut self,
        task_id: &str,
        result: Option<String>,
        error: Option<String>,
        actual_cost: f64,
    ) -> Result<TaskResult, TaskError> {
        let task = self
            .tasks
            .get_mut(task_id)
            .ok_or_else(|| TaskError::NotFound(task_id.to_string()))?;

        task.status = if error.is_some() {
            TaskStatus::Failed
        } else {
            TaskStatus::Completed
        };
        
        task.completed_at = Some(Utc::now().timestamp() as u64);
        task.actual_cost = Some(actual_cost);
        task.error = error.clone();

        Ok(TaskResult {
            success: error.is_none(),
            task_id: task_id.to_string(),
            result,
            error,
            cost: actual_cost,
        })
    }

    /// Get task status
    pub fn get_task(&self, task_id: &str) -> Option<&Task> {
        self.tasks.get(task_id)
    }

    /// Cancel a task
    pub fn cancel_task(&mut self, task_id: &str, auth_token: &str) -> Result<(), TaskError> {
        // Authenticate
        let claims = self.auth.validate_token(auth_token)
            .map_err(|_| TaskError::AuthRequired)?;

        let task = self
            .tasks
            .get_mut(task_id)
            .ok_or_else(|| TaskError::NotFound(task_id.to_string()))?;

        // Only creator or admin can cancel
        if task.created_by != claims.sub && !claims.roles.contains(&Role::Admin) {
            return Err(TaskError::InsufficientPermissions);
        }

        task.status = TaskStatus::Cancelled;
        task.completed_at = Some(Utc::now().timestamp() as u64);

        Ok(())
    }

    /// Get budget status
    pub fn get_budget_status(&self) -> (f64, f64, f64) {
        (self.budget.total, self.budget.used, self.budget.total - self.budget.used)
    }

    /// Get pending count
    pub fn pending_count(&self) -> usize {
        self.pending_queue.len()
    }
}

impl Default for TaskOrchestrator {
    fn default() -> Self {
        Self::with_defaults()
    }
}

// Global orchestrator
use once_cell::sync::Lazy;

static TASK_ORCHESTRATOR: Lazy<RwLock<TaskOrchestrator>> = Lazy::new(|| {
    RwLock::new(TaskOrchestrator::with_defaults())
});

/// Initialize orchestrator
pub fn init(budget: f64, reset_secs: u64, rate_limit: u32, rate_window: u64) {
    *TASK_ORCHESTRATOR.write().unwrap() = TaskOrchestrator::new(budget, reset_secs, rate_limit, rate_window);
}

/// Submit task
pub fn submit_task(request: &TaskRequest, auth_token: &str) -> Result<TaskResult, TaskError> {
    TASK_ORCHESTRATOR.write().unwrap().submit_task(request, auth_token)
}

/// Get next task
pub fn get_next_task() -> Option<Task> {
    TASK_ORCHESTRATOR.write().unwrap().get_next_task()
}

/// Complete task
pub fn complete_task(task_id: &str, result: Option<String>, error: Option<String>, cost: f64) -> Result<TaskResult, TaskError> {
    TASK_ORCHESTRATOR.write().unwrap().complete_task(task_id, result, error, cost)
}

/// Get task
pub fn get_task(task_id: &str) -> Option<Task> {
    TASK_ORCHESTRATOR.read().unwrap().get_task(task_id).cloned()
}

/// Cancel task
pub fn cancel_task(task_id: &str, auth_token: &str) -> Result<(), TaskError> {
    TASK_ORCHESTRATOR.write().unwrap().cancel_task(task_id, auth_token)
}

/// Get budget status
pub fn get_budget_status() -> (f64, f64, f64) {
    TASK_ORCHESTRATOR.read().unwrap().get_budget_status()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_task_submission() {
        let mut orchestrator = TaskOrchestrator::with_defaults();
        
        // Create auth token
        let token = orchestrator.auth.create_token("test_user", vec![Role::User])
            .unwrap();
        
        let request = TaskRequest {
            name: "Test Task".to_string(),
            description: "Test".to_string(),
            capability: "safe_shell".to_string(),
            params: r#"{"command": "echo test"}"#.to_string(),
            priority: TaskPriority::Normal,
            estimated_cost: 10.0,
        };
        
        let result = orchestrator.submit_task(&request, &token).unwrap();
        assert!(result.success);
    }

    #[test]
    fn test_budget_enforcement() {
        let mut orchestrator = TaskOrchestrator::new(50.0, 3600, 100, 60);
        
        let token = orchestrator.auth.create_token("test_user", vec![Role::User])
            .unwrap();
        
        let request = TaskRequest {
            name: "Expensive Task".to_string(),
            description: "Test".to_string(),
            capability: "safe_shell".to_string(),
            params: "{}".to_string(),
            priority: TaskPriority::Normal,
            estimated_cost: 100.0, // More than budget
        };
        
        let result = orchestrator.submit_task(&request, &token);
        assert!(matches!(result, Err(TaskError::BudgetExceeded)));
    }
}
