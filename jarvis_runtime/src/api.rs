//! # API Server
//!
//! Axum-based REST API server with WebSocket support.

use axum::{
    extract::State,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, error};

use crate::supervisor::Supervisor;

/// API state
pub struct ApiState {
    pub supervisor: Arc<Supervisor>,
}

/// Chat request
#[derive(Debug, Deserialize)]
pub struct ChatRequest {
    pub message: String,
    pub session_id: Option<String>,
}

/// Chat response
#[derive(Debug, Serialize)]
pub struct ChatResponse {
    pub response: String,
    pub session_id: String,
    pub suggestions: Vec<String>,
}

/// Memory request
#[derive(Debug, Deserialize)]
pub struct MemoryRequest {
    pub query: Option<String>,
    pub limit: Option<usize>,
}

/// Suggestion response
#[derive(Debug, Serialize)]
pub struct SuggestionResponse {
    pub suggestions: Vec<crate::proactive::Suggestion>,
}

/// Capability response
#[derive(Debug, Serialize)]
pub struct CapabilityResponse {
    pub capabilities: Vec<crate::capabilities::CapabilityMetadata>,
}

/// Health response
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub timestamp: String,
}

/// Create the API router
pub fn create_router(supervisor: Arc<Supervisor>) -> Router {
    let state = ApiState { supervisor };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/health", get(health_handler))
        .route("/chat", post(chat_handler))
        .route("/memory", get(memory_handler))
        .route("/suggestions", get(suggestions_handler))
        .route("/capabilities", get(capabilities_handler))
        .route("/metrics", get(metrics_handler))
        .layer(cors)
        .with_state(Arc::new(RwLock::new(state)))
}

/// Health handler
async fn health_handler(
    State(state): State<Arc<RwLock<ApiState>>>,
) -> axum::Json<HealthResponse> {
    let state = state.read().await;
    let health_status = state.supervisor.get_health_status().await;
    
    let overall = if health_status.iter().all(|h| h.healthy) {
        "healthy"
    } else {
        "degraded"
    };

    axum::Json(HealthResponse {
        status: overall.to_string(),
        timestamp: chrono::Utc::now().to_rfc3339(),
    })
}

/// Chat handler
async fn chat_handler(
    State(state): State<Arc<RwLock<ApiState>>>,
    axum::Json(req): axum::Json<ChatRequest>,
) -> axum::Json<ChatResponse> {
    // In production, this would call the Julia Kernel
    let response = format!("Processed: {}", req.message);
    let session_id = req.session_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    axum::Json(ChatResponse {
        response,
        session_id,
        suggestions: vec![],
    })
}

/// Memory handler
async fn memory_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
    axum::Json(_req): axum::Json<MemoryRequest>,
) -> axum::Json<serde_json::Value> {
    // Return memory data
    axum::Json(serde_json::json!({
        "memories": []
    }))
}

/// Suggestions handler
async fn suggestions_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> axum::Json<SuggestionResponse> {
    axum::Json(SuggestionResponse {
        suggestions: vec![],
    })
}

/// Capabilities handler
async fn capabilities_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> axum::Json<CapabilityResponse> {
    axum::Json(CapabilityResponse {
        capabilities: vec![],
    })
}

/// Metrics handler
async fn metrics_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> String {
    // Return Prometheus metrics format
    "# HELP jarvis_runtime_up Runtime up\n".to_string()
}

/// API server
pub struct ApiServer {
    addr: SocketAddr,
    router: Router,
}

impl ApiServer {
    /// Create new API server
    pub fn new(addr: SocketAddr, router: Router) -> Self {
        Self { addr, router }
    }

    /// Start the API server
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        info!("Starting API server on {}", self.addr);
        
        let listener = tokio::net::TcpListener::bind(self.addr).await?;
        
        axum::serve(listener, self.router)
            .await?;
            
        Ok(())
    }
}
