//! # JARVIS Runtime Tests
//!
//! Integration tests for the JARVIS runtime.

#[cfg(test)]
mod tests {
    use jarvis_runtime::{
        JarvisRuntime, JarvisState, RuntimeConfig, RuntimeMode,
        CapabilityManager, Capability, ApprovalToken,
        KnowledgeGraph, Entity, EntityType,
        Relationship, RelationshipType,
        SessionManager, Auth,
        HealthCheck, HealthState,
    };
    use serde_json::json;

    // =========================================================================
    // Runtime Tests
    // =========================================================================

    #[tokio::test]
    async fn test_runtime_creation() {
        let config = RuntimeConfig {
            mode: RuntimeMode::Dev,
            ..Default::default()
        };
        let runtime = JarvisRuntime::new(config);
        
        let state = runtime.state().await;
        assert!(matches!(state, crate::runtime::RuntimeState::Starting));
    }

    #[tokio::test]
    async fn test_runtime_config_defaults() {
        let config = RuntimeConfig::default();
        assert_eq!(config.mode, RuntimeMode::Foreground);
        assert_eq!(config.shutdown_timeout_secs, 30);
    }

    // =========================================================================
    // Capability Tests
    // =========================================================================

    #[tokio::test]
    async fn test_capability_manager() {
        let manager = CapabilityManager::new().await.unwrap();
        assert!(manager.health_check().await);
    }

    // =========================================================================
    // Knowledge Graph Tests
    // =========================================================================

    #[tokio::test]
    async fn test_knowledge_graph() {
        let mut graph = KnowledgeGraph::new();
        
        // Add entities
        let entity1 = Entity::new("Test Entity".to_string(), EntityType::Concept);
        let entity2 = Entity::new("Another Entity".to_string(), EntityType::Person);
        
        let idx1 = graph.add_entity(entity1);
        let idx2 = graph.add_entity(entity2);
        
        assert_eq!(graph.node_count(), 2);
 relationship
        let        
        // Add rel = Relationship::new(RelationshipType::RelatedTo, idx1, idx2);
        graph.add_relationship(idx1, idx2, rel).unwrap();
        
        assert_eq!(graph.edge_count(), 1);
    }

    // =========================================================================
    // Session Tests
    // =========================================================================

    #[tokio::test]
    async fn test_session_manager() {
        let manager = SessionManager::new();
        
        let user_id = uuid::Uuid::new_v4();
        let token = "test_token_123".to_string();
        
        let session = manager.create_session(user_id, token.clone()).await;
        assert_eq!(session.token, token);
        assert!(session.is_valid());
    }

    #[tokio::test]
    async fn test_session_expiration() {
        let manager = SessionManager::new();
        
        let user_id = uuid::Uuid::new_v4();
        let session = manager.create_session(user_id, "test".to_string()).await;
        
        // Session should be valid initially
        assert!(session.is_valid());
    }

    // =========================================================================
    // Auth Tests
    // =========================================================================

    #[tokio::test]
    async fn test_auth_register() {
        let auth = Auth::new("test_secret".to_string());
        
        let user = auth.register(
            "testuser".to_string(),
            "password123".to_string(),
            None,
        ).await;
        
        assert!(user.is_ok());
    }

    #[tokio::test]
    async fn test_auth_authenticate() {
        let auth = Auth::new("test_secret".to_string());
        
        // Register user
        auth.register(
            "testuser".to_string(),
            "password123".to_string(),
            None,
        ).await.unwrap();
        
        // Authenticate
        let result = auth.authenticate("testuser", "password123").await;
        assert!(result.is_ok());
        
        // Wrong password
        let result = auth.authenticate("testuser", "wrong").await;
        assert!(result.is_err());
    }

    // =========================================================================
    // Health Check Tests
    // =========================================================================

    #[tokio::test]
    async fn test_health_check() {
        let health = HealthCheck::new();
        
        let status = health.get_status().await;
        assert_eq!(status, HealthState::Healthy);
    }

    // =========================================================================
    // Integration Test - Full Stack
    // =========================================================================

    #[tokio::test]
    async fn test_full_integration() async -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Create runtime
        let config = RuntimeConfig {
            mode: RuntimeMode::Dev,
            ..Default::default()
        };
        
        let state = JarvisState::new(config).await?;
        
        // Check all components are initialized
        assert!(state.capabilities.health_check().await);
        assert!(state.health.get_status().await == HealthState::Healthy);
        
        Ok(())
    }
}
