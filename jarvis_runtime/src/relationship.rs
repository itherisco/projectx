//! # Relationship - Knowledge Graph Edge
//!
//! Represents typed relationships (edges) between entities.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use petgraph::graph::{NodeIndex};

/// Relationship types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RelationshipType {
    /// Generic relationship
    RelatedTo,
    /// Is-a relationship
    IsA,
    /// Part-of relationship  
    PartOf,
    /// Belongs to
    BelongsTo,
    /// Created by
    CreatedBy,
    /// Owns
    Owns,
    /// Follows (temporal)
    Follows,
    /// Before (temporal)
    Before,
    /// After (temporal)
    After,
    /// Causes
    Causes,
    /// Enables
    Enables,
    /// Similar to
    SimilarTo,
    /// Custom type
    Custom(String),
}

impl Default for RelationshipType {
    fn default() -> Self {
        RelationshipType::RelatedTo
    }
}

impl RelationshipType {
    pub fn as_str(&self) -> &str {
        match self {
            RelationshipType::RelatedTo => "related_to",
            RelationshipType::IsA => "is_a",
            RelationshipType::PartOf => "part_of",
            RelationshipType::BelongsTo => "belongs_to",
            RelationshipType::CreatedBy => "created_by",
            RelationshipType::Owns => "owns",
            RelationshipType::Follows => "follows",
            RelationshipType::Before => "before",
            RelationshipType::After => "after",
            RelationshipType::Causes => "causes",
            RelationshipType::Enables => "enables",
            RelationshipType::SimilarTo => "similar_to",
            RelationshipType::Custom(s) => s.as_str(),
        }
    }
}

/// Relationship between two entities
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Relationship {
    /// Unique identifier
    pub id: uuid::Uuid,
    /// Type of relationship
    pub relationship_type: RelationshipType,
    /// Source entity (node index)
    pub source: NodeIndex,
    /// Target entity (node index)
    pub target: NodeIndex,
    /// Relationship weight/confidence (0-1)
    pub weight: f32,
    /// Optional properties
    pub properties: serde_json::Value,
    /// When relationship was created
    pub created_at: DateTime<Utc>,
    /// Optional expiration
    pub expires_at: Option<DateTime<Utc>>,
    /// Provenance - how this relationship was determined
    pub provenance: Option<String>,
}

impl Relationship {
    /// Create a new relationship
    pub fn new(relationship_type: RelationshipType, source: NodeIndex, target: NodeIndex) -> Self {
        Self {
            id: uuid::Uuid::new_v4(),
            relationship_type,
            source,
            target,
            weight: 1.0,
            properties: serde_json::json!({}),
            created_at: Utc::now(),
            expires_at: None,
            provenance: None,
        }
    }

    /// Create with weight
    pub fn with_weight(mut self, weight: f32) -> Self {
        self.weight = weight.clamp(0.0, 1.0);
        self
    }

    /// Create with properties
    pub fn with_properties(mut self, properties: serde_json::Value) -> Self {
        self.properties = properties;
        self
    }

    /// Create with expiration
    pub fn with_expiration(mut self, expires_at: DateTime<Utc>) -> Self {
        self.expires_at = Some(expires_at);
        self
    }

    /// Create with provenance
    pub fn with_provenance(mut self, provenance: impl Into<String>) -> Self {
        self.provenance = Some(provenance.into());
        self
    }

    /// Check if relationship is expired
    pub fn is_expired(&self) -> bool {
        if let Some(expires) = self.expires_at {
            Utc::now() > expires
        } else {
            false
        }
    }
}
