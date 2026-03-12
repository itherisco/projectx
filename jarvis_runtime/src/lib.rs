//! # JARVIS Runtime - Production-Grade Async Runtime
//!
//! A Tokio-based async runtime for the JARVIS intelligent platform.
// persistent! Provides daemon mode, tool ecosystem, continuous perception,
//! knowledge graph, proactive intelligence, and user session management.
//!
//! ## Architecture
//!
//! - **Runtime**: Async event loop with supervisor pattern
//! - **Tools**: Capability-based execution with Kernel approval
//! - **Sensors**: Event-driven perception pipeline
//! - **Knowledge**: Relational graph storage
//! - **Intelligence**: Pattern detection and inference
//! - **Sessions**: Multi-user isolation with JWT auth
//!
//! ## Key Invariants
//!
//! - Kernel is sovereign - no tool executes without approval token
//! - All input sanitized and schema-validated
//! - Fail-closed on error
//! - No global mutable state

// ============================================================================
// MODULE DECLARATIONS
// ============================================================================

// Part 1: Persistent Runtime
pub mod runtime;
pub mod supervisor;
pub mod service;

// Part 2: Tool Ecosystem
pub mod capabilities;
pub mod capability_manager;
pub mod registry;

// Part 3: Continuous Perception Pipeline
pub mod perception;
pub mod event_bus;
pub mod sensors;

// Part 4: Knowledge Graph Engine
pub mod knowledge_graph;
pub mod entity;
pub mod relationship;
pub mod graph_query;

// Part 5: Proactive Intelligence
pub mod proactive;
pub mod inference;
pub mod pattern_detector;

// Part 6: User Sessions & Personalization
pub mod user;
pub mod session;
pub mod auth;

// Part 7: Production Hardening
pub mod recovery;
pub mod metrics;
pub mod health;

// Part 8: Service Interfaces
pub mod api;
pub mod routes;

// Part 9: Warden Security Layer (Sovereign)
pub mod warden;

// Re-exports
pub use runtime::{JarvisRuntime, RuntimeConfig, RuntimeMode};
pub use supervisor::{Supervisor, SupervisorConfig, RestartPolicy};
pub use service::Service;
pub use capabilities::{Capability, CapabilityError};
pub use capability_manager::CapabilityManager;
pub use event_bus::{EventBus, Event, EventPriority};
pub use sensors::{Sensor, SystemMonitor, FileWatcher, NetworkMonitor, UserInputStream};
pub use knowledge_graph::KnowledgeGraph;
pub use entity::{Entity, EntityType};
pub use relationship::{Relationship, RelationshipType};
pub use graph_query::{GraphQuery, QueryResult};
pub use proactive::{ProactiveEngine, Suggestion, Confidence};
pub use inference::{InferenceEngine, InferenceResult};
pub use pattern_detector::{PatternDetector, Pattern};
pub use user::{User, TrustLevel, UserPreferences};
pub use session::{Session, SessionManager};
pub use auth::{Auth, JWTClaims};
pub use recovery::{RecoveryManager, Snapshot};
pub use metrics::Metrics;
pub use health::{HealthCheck, HealthStatus};
pub use api::ApiServer;
pub use routes::create_router;

// Error types
pub use crate::capabilities::CapabilityError as ToolError;
pub use crate::auth::AuthError;
pub use crate::session::SessionError;
pub use crate::knowledge_graph::GraphError;

// ============================================================================
// PUBLIC API
// ============================================================================

use std::sync::Arc;
use tokio::sync::RwLock;

/// Global runtime state shared across components
pub struct JarvisState {
    pub runtime: Arc<JarvisRuntime>,
    pub capabilities: Arc<CapabilityManager>,
    pub event_bus: Arc<EventBus>,
    pub knowledge_graph: Arc<RwLock<KnowledgeGraph>>,
    pub session_manager: Arc<SessionManager>,
    pub proactive_engine: Arc<ProactiveEngine>,
    pub metrics: Arc<Metrics>,
    pub health: Arc<HealthCheck>,
}

impl JarvisState {
    /// Create new runtime state
    pub async fn new(config: RuntimeConfig) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let runtime = Arc::new(JarvisRuntime::new(config));
        let capabilities = Arc::new(CapabilityManager::new().await?);
        let event_bus = Arc::new(EventBus::new(1024));
        let knowledge_graph = Arc::new(RwLock::new(KnowledgeGraph::new()));
        let session_manager = Arc::new(SessionManager::new());
        let proactive_engine = Arc::new(ProactiveEngine::new());
        let metrics = Arc::new(Metrics::new());
        let health = Arc::new(HealthCheck::new());

        Ok(Self {
            runtime,
            capabilities,
            event_bus,
            knowledge_graph,
            session_manager,
            proactive_engine,
            metrics,
            health,
        })
    }
}

/// Initialize logging subsystem
pub fn init_logging(level: &str) {
    use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
    
    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(level));
    
    tracing_subscriber::registry()
        .with(env_filter)
        .with(tracing_subscriber::fmt::layer())
        .init();
}

/// Version information
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
