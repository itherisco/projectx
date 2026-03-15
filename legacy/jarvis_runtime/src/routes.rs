//! # Routes
//!
//! API route handlers.

use crate::api::{ApiState, ChatRequest, ChatResponse, HealthResponse, MemoryRequest, SuggestionResponse, CapabilityResponse};
use crate::supervisor::Supervisor;
use axum::{
    extract::State,
    Json,
};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Create API routes
pub fn create_router(supervisor: Arc<Supervisor>) -> axum::Router {
    let state = ApiState { supervisor };

    let cors = tower_http::cors::CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods(tower_http::cors::Any)
        .allow_headers(tower_http::cors::Any);

    axum::Router::new()
        .route("/health", axum::routing::get(health_handler))
        .route("/chat", axum::routing::post(chat_handler))
        .route("/memory", axum::routing::get(memory_handler))
        .route("/suggestions", axum::routing::get(suggestions_handler))
        .route("/capabilities", axum::routing::get(capabilities_handler))
        .route("/metrics", axum::routing::get(metrics_handler))
        .layer(cors)
        .with_state(Arc::new(RwLock::new(state)))
}

/// Health endpoint
async fn health_handler(
    State(state): State<Arc<RwLock<ApiState>>>,
) -> Json<HealthResponse> {
    let state = state.read().await;
    let health_status = state.supervisor.get_health_status().await;
    
    let overall = if health_status.iter().all(|h| h.healthy) {
        "healthy"
    } else {
        "degraded"
    };

    Json(HealthResponse {
        status: overall.to_string(),
        timestamp: chrono::Utc::now().to_rfc3339(),
    })
}

/// Chat endpoint
async fn chat_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
    Json(req): Json<ChatRequest>,
) -> Json<ChatResponse> {
    let response = format!("Processed: {}", req.message);
    let session_id = req.session_id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    Json(ChatResponse {
        response,
        session_id,
        suggestions: vec![],
    })
}

/// Memory endpoint
async fn memory_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
    Json(_req): Json<MemoryRequest>,
) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "memories": []
    }))
}

/// Suggestions endpoint
async fn suggestions_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> Json<SuggestionResponse> {
    Json(SuggestionResponse {
        suggestions: vec![],
    })
}

/// Capabilities endpoint
async fn capabilities_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> Json<CapabilityResponse> {
    Json(CapabilityResponse {
        capabilities: vec![],
    })
}

/// Metrics endpoint
async fn metrics_handler(
    State(_state): State<Arc<RwLock<ApiState>>>,
) -> String {
    "# HELP jarvis_up JARVIS is up\n".to_string()
}
