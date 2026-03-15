//! # Entity - Knowledge Graph Node
//!
//! Represents entities (nodes) in the knowledge graph.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Entity types in the knowledge graph
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntityType {
    Concept,
    Person,
    Organization,
    Location,
    Event,
    Object,
    Task,
    Memory,
    File,
    Process,
    Custom(String),
}

impl Default for EntityType {
    fn default() -> Self {
        EntityType::Concept
    }
}

impl EntityType {
    pub fn as_str(&self) -> &str {
        match self {
            EntityType::Concept => "concept",
            EntityType::Person => "person",
            EntityType::Organization => "organization",
            EntityType::Location => "location",
            EntityType::Event => "event",
            EntityType::Object => "object",
            EntityType::Task => "task",
            EntityType::Memory => "memory",
            EntityType::File => "file",
            EntityType::Process => "process",
            EntityType::Custom(s) => s.as_str(),
        }
    }
}

/// Entity represents a node in the knowledge graph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entity {
    /// Unique identifier
    pub id: uuid::Uuid,
    /// Entity name/label
    pub name: String,
    /// Entity type
    pub entity_type: EntityType,
    /// Additional properties as key-value pairs
    pub properties: HashMap<String, serde_json::Value>,
    /// Optional description
    pub description: Option<String>,
    /// Embedding vector for similarity (optional)
    pub embedding: Option<Vec<f32>>,
    /// When entity was created
    pub created_at: DateTime<Utc>,
    /// When entity was last updated
    pub updated_at: DateTime<Utc>,
    /// Confidence score (0-1)
    pub confidence: f32,
    /// Source of this entity
    pub source: Option<String>,
}

impl Entity {
    /// Create a new entity
    pub fn new(name: String, entity_type: EntityType) -> Self {
        let now = Utc::now();
        Self {
            id: uuid::Uuid::new_v4(),
            name,
            entity_type,
            properties: HashMap::new(),
            description: None,
            embedding: None,
            created_at: now,
            updated_at: now,
            confidence: 1.0,
            source: None,
        }
    }

    /// Create entity with ID (for importing)
    pub fn with_id(id: uuid::Uuid, name: String, entity_type: EntityType) -> Self {
        let now = Utc::now();
        Self {
            id,
            name,
            entity_type,
            properties: HashMap::new(),
            description: None,
            embedding: None,
            created_at: now,
            updated_at: now,
            confidence: 1.0,
            source: None,
        }
    }

    /// Add a property
    pub fn with_property(mut self, key: impl Into<String>, value: serde_json::Value) -> Self {
        self.properties.insert(key.into(), value);
        self.updated_at = Utc::now();
        self
    }

    /// Set description
    pub fn with_description(mut self, description: impl Into<String>) -> Self {
        self.description = Some(description.into());
        self.updated_at = Utc::now();
        self
    }

    /// Set embedding
    pub fn with_embedding(mut self, embedding: Vec<f32>) -> Self {
        self.embedding = Some(embedding);
        self.updated_at = Utc::now();
        self
    }

    /// Set confidence
    pub fn with_confidence(mut self, confidence: f32) -> Self {
        self.confidence = confidence.clamp(0.0, 1.0);
        self.updated_at = Utc::now();
        self
    }

    /// Get a property
    pub fn get_property(&self, key: &str) -> Option<&serde_json::Value> {
        self.properties.get(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_entity_creation() {
        let entity = Entity::new("Test Entity".to_string(), EntityType::Concept);
        assert_eq!(entity.name, "Test Entity");
        assert_eq!(entity.entity_type, EntityType::Concept);
        assert!(entity.id != uuid::Uuid::nil());
    }

    #[test]
    fn test_entity_properties() {
        let entity = Entity::new("Test".to_string(), EntityType::Concept)
            .with_property("key", serde_json::json!("value"))
            .with_description("A test entity");

        assert_eq!(entity.get_property("key"), Some(&serde_json::json!("value")));
        assert_eq!(entity.description, Some("A test entity".to_string()));
    }
}
