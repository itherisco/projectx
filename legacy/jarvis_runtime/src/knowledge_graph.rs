//! # Knowledge Graph Engine
//!
//! Relational knowledge storage using petgraph for graph operations.

use crate::entity::{Entity, EntityType};
use crate::relationship::{Relationship, RelationshipType};
use crate::graph_query::{GraphQuery, QueryResult, RelationshipFilter};
use petgraph::graph::{DiGraph, NodeIndex, EdgeIndex};
use petgraph::algo::{dijkstra, all_simple_paths};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, debug};

/// Knowledge graph error types
#[derive(Debug)]
pub enum GraphError {
    EntityNotFound(String),
    RelationshipNotFound(String),
    InvalidOperation(String),
    QueryError(String),
}

impl std::fmt::Display for GraphError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GraphError::EntityNotFound(id) => write!(f, "Entity not found: {}", id),
            GraphError::RelationshipNotFound(id) => write!(f, "Relationship not found: {}", id),
            GraphError::InvalidOperation(msg) => write!(f, "Invalid operation: {}", msg),
            GraphError::QueryError(msg) => write!(f, "Query error: {}", msg),
        }
    }
}

impl std::error::Error for GraphError {}

/// Knowledge graph using petgraph
pub struct KnowledgeGraph {
    graph: DiGraph<Entity, Relationship>,
    entity_index: HashMap<uuid::Uuid, NodeIndex>,
    relationship_index: HashMap<uuid::Uuid, EdgeIndex>,
}

impl KnowledgeGraph {
    /// Create new empty knowledge graph
    pub fn new() -> Self {
        Self {
            graph: DiGraph::new(),
            entity_index: HashMap::new(),
            relationship_index: HashMap::new(),
        }
    }

    /// Add entity to graph
    pub fn add_entity(&mut self, entity: Entity) -> NodeIndex {
        let index = self.graph.add_node(entity.clone());
        self.entity_index.insert(entity.id, index);
        debug!("Added entity {} at index {:?}", entity.id, index);
        index
    }

    /// Add relationship between entities
    pub fn add_relationship(
        &mut self,
        source_id: uuid::Uuid,
        target_id: uuid::Uuid,
        relationship: Relationship,
    ) -> Result<EdgeIndex, GraphError> {
        let source_idx = self.entity_index
            .get(&source_id)
            .ok_or_else(|| GraphError::EntityNotFound(source_id.to_string()))?;
        
        let target_idx = self.entity_index
            .get(&target_id)
            .ok_or_else(|| GraphError::EntityNotFound(target_id.to_string()))?;

        let edge_idx = self.graph.add_edge(*source_idx, *target_idx, relationship.clone());
        self.relationship_index.insert(relationship.id, edge_idx);
        
        debug!("Added relationship {} from {} to {}", relationship.id, source_id, target_id);
        Ok(edge_idx)
    }

    /// Get entity by ID
    pub fn get_entity(&self, id: uuid::Uuid) -> Result<Entity, GraphError> {
        let index = self.entity_index
            .get(&id)
            .ok_or_else(|| GraphError::EntityNotFound(id.to_string()))?;
        
        self.graph.node_weight(*index)
            .cloned()
            .ok_or_else(|| GraphError::EntityNotFound(id.to_string()))
    }

    /// Get all entities of a specific type
    pub fn get_entities_by_type(&self, entity_type: EntityType) -> Vec<Entity> {
        self.graph.node_indices()
            .filter_map(|idx| {
                self.graph.node_weight(idx).and_then(|e| {
                    if e.entity_type == entity_type {
                        Some(e.clone())
                    } else {
                        None
                    }
                })
            })
            .collect()
    }

    /// Get relationships for an entity
    pub fn get_relationships(&self, entity_id: uuid::Uuid) -> Result<Vec<Relationship>, GraphError> {
        let index = self.entity_index
            .get(&entity_id)
            .ok_or_else(|| GraphError::EntityNotFound(entity_id.to_string()))?;

        let mut relationships = Vec::new();

        // Outgoing relationships
        for edge_idx in self.graph.edges(*index) {
            relationships.push(edge_idx.weight().clone());
        }

        // Incoming relationships
        for edge_idx in self.graph.edges_directed(*index, petgraph::Direction::Incoming) {
            relationships.push(edge_idx.weight().clone());
        }

        Ok(relationships)
    }

    /// Find related entities
    pub fn find_related(&self, entity_id: uuid::Uuid, relationship_type: Option<RelationshipType>) -> Result<Vec<Entity>, GraphError> {
        let index = self.entity_index
            .get(&entity_id)
            .ok_or_else(|| GraphError::EntityNotFound(entity_id.to_string()))?;

        let mut related = Vec::new();

        // Check outgoing edges
        for edge_idx in self.graph.edges(*index) {
            let rel = edge_idx.weight();
            if relationship_type.as_ref().map_or(true, |rt| rel.relationship_type == *rt) {
                let target_idx = edge_idx.target();
                if let Some(entity) = self.graph.node_weight(target_idx).cloned() {
                    related.push(entity);
                }
            }
        }

        // Check incoming edges
        for edge_idx in self.graph.edges_directed(*index, petgraph::Direction::Incoming) {
            let rel = edge_idx.weight();
            if relationship_type.as_ref().map_or(true, |rt| rel.relationship_type == *rt) {
                let source_idx = edge_idx.source();
                if let Some(entity) = self.graph.node_weight(source_idx).cloned() {
                    related.push(entity);
                }
            }
        }

        Ok(related)
    }

    /// Find shortest path between two entities
    pub fn shortest_path(&self, source_id: uuid::Uuid, target_id: uuid::Uuid) -> Result<Vec<uuid::Uuid>, GraphError> {
        let source_idx = self.entity_index
            .get(&source_id)
            .ok_or_else(|| GraphError::EntityNotFound(source_id.to_string()))?;
        
        let target_idx = self.entity_index
            .get(&target_id)
            .ok_or_else(|| GraphError::EntityNotFound(target_id.to_string()))?;

        let path_map = dijkstra(&self.graph, *source_idx, Some(*target_idx), |_| 1);

        if let Some(_distance) = path_map.get(target_idx) {
            // Reconstruct path
            let mut path = vec![source_id];
            let mut current = *source_idx;

            while current != *target_idx {
                let neighbors: Vec<_> = self.graph.edges(current)
                    .filter(|e| path_map.contains_key(&e.target()))
                    .collect();

                if let Some(next) = neighbors.first() {
                    let next_idx = next.target();
                    if let Some(entity) = self.graph.node_weight(next_idx) {
                        path.push(entity.id);
                        current = next_idx;
                    }
                } else {
                    break;
                }
            }

            Ok(path)
        } else {
            Err(GraphError::QueryError("No path found".to_string()))
        }
    }

    /// Query the graph
    pub fn query(&self, query: GraphQuery) -> Result<QueryResult, GraphError> {
        match query {
            GraphQuery::FindRelated { entity_id, relationship_filter, max_depth } => {
                let related = self.find_related(entity_id, relationship_filter.relationship_type)?;
                Ok(QueryResult::Entities(related))
            }
            GraphQuery::ShortestPath { source_id, target_id } => {
                let path = self.shortest_path(source_id, target_id)?;
                Ok(QueryResult::Path(path))
            }
            GraphQuery::FindByType { entity_type } => {
                let entities = self.get_entities_by_type(entity_type);
                Ok(QueryResult::Entities(entities))
            }
            GraphQuery::FindByProperty { key, value } => {
                let entities = self.find_by_property(&key, &value);
                Ok(QueryResult::Entities(entities))
            }
        }
    }

    /// Find entities by property
    fn find_by_property(&self, key: &str, value: &serde_json::Value) -> Vec<Entity> {
        self.graph.node_indices()
            .filter_map(|idx| {
                self.graph.node_weight(idx).and_then(|e| {
                    if e.properties.get(key) == Some(value) {
                        Some(e.clone())
                    } else {
                        None
                    }
                })
            })
            .collect()
    }

    /// Get all nodes count
    pub fn node_count(&self) -> usize {
        self.graph.node_count()
    }

    /// Get all edges count
    pub fn edge_count(&self) -> usize {
        self.graph.edge_count()
    }
}

impl Default for KnowledgeGraph {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity::EntityType;
    use crate::relationship::RelationshipType;

    #[test]
    fn test_add_entity() {
        let mut graph = KnowledgeGraph::new();
        let entity = Entity::new("test".to_string(), EntityType::Concept);
        graph.add_entity(entity);
        
        assert_eq!(graph.node_count(), 1);
    }

    #[test]
    fn test_add_relationship() {
        let mut graph = KnowledgeGraph::new();
        
        let entity1 = Entity::new("entity1".to_string(), EntityType::Concept);
        let entity2 = Entity::new("entity2".to_string(), EntityType::Concept);
        
        let idx1 = graph.add_entity(entity1);
        let idx2 = graph.add_entity(entity2);
        
        let rel = Relationship::new(
            RelationshipType::RelatedTo,
            idx1,
            idx2,
        );
        
        graph.add_relationship(idx1, idx2, rel).unwrap();
        
        assert_eq!(graph.edge_count(), 1);
    }
}
