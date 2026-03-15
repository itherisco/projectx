//! # Graph Query API
//!
//! Query API for the knowledge graph.

use crate::entity::{Entity, EntityType};
use crate::relationship::RelationshipType;
use serde::{Deserialize, Serialize};

/// Relationship filter for queries
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RelationshipFilter {
    pub relationship_type: Option<RelationshipType>,
    pub min_weight: Option<f32>,
}

/// Query types for the knowledge graph
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum GraphQuery {
    /// Find entities related to a given entity
    FindRelated {
        entity_id: uuid::Uuid,
        relationship_filter: RelationshipFilter,
        max_depth: Option<usize>,
    },
    /// Find shortest path between two entities
    ShortestPath {
        source_id: uuid::Uuid,
        target_id: uuid::Uuid,
    },
    /// Find all entities of a type
    FindByType {
        entity_type: EntityType,
    },
    /// Find entities by property
    FindByProperty {
        key: String,
        value: serde_json::Value,
    },
    /// Find entities similar to an embedding
    FindSimilar {
        embedding: Vec<f32>,
        limit: usize,
        threshold: f32,
    },
}

/// Query result types
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum QueryResult {
    /// List of entities
    Entities(Vec<Entity>),
    /// Path of entity IDs
    Path(Vec<uuid::Uuid>),
    /// Similarity scores
    Similarities(Vec<SimilarityResult>),
}

/// Similarity result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimilarityResult {
    pub entity_id: uuid::Uuid,
    pub score: f32,
}

/// Query builder for fluent API
pub struct QueryBuilder {
    query: Option<GraphQuery>,
}

impl QueryBuilder {
    pub fn new() -> Self {
        Self { query: None }
    }

    /// Find related entities
    pub fn find_related(mut self, entity_id: uuid::Uuid) -> Self {
        self.query = Some(GraphQuery::FindRelated {
            entity_id,
            relationship_filter: RelationshipFilter::default(),
            max_depth: None,
        });
        self
    }

    /// Filter by relationship type
    pub fn with_relationship_type(mut self, rel_type: RelationshipType) -> Self {
        if let Some(GraphQuery::FindRelated { ref mut relationship_filter, .. }) = self.query {
            relationship_filter.relationship_type = Some(rel_type);
        }
        self
    }

    /// Set max depth
    pub fn with_max_depth(mut self, depth: usize) -> Self {
        if let Some(GraphQuery::FindRelated { ref mut max_depth, .. }) = self.query {
            *max_depth = Some(depth);
        }
        self
    }

    /// Find by type
    pub fn find_by_type(mut self, entity_type: EntityType) -> Self {
        self.query = Some(GraphQuery::FindByType { entity_type });
        self
    }

    /// Find by property
    pub fn find_by_property(mut self, key: String, value: serde_json::Value) -> Self {
        self.query = Some(GraphQuery::FindByProperty { key, value });
        self
    }

    /// Build the query
    pub fn build(self) -> Option<GraphQuery> {
        self.query
    }
}

impl Default for QueryBuilder {
    fn default() -> Self {
        Self::new()
    }
}
