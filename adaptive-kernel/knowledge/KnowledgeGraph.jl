# KnowledgeGraph.jl - Core Knowledge Graph Implementation
# Implements Entity-Relation-Event-Belief model for structured knowledge representation

module KnowledgeGraph

export 
    # Core types
    Entity, Relation, Event, Belief, KnowledgeTriple,
    # Graph types
    KnowledgeGraphCore, add_entity!, remove_entity!,
    add_relation!, remove_relation!,
    add_event!, add_belief!,
    get_entity, get_relation, get_events, get_beliefs,
    # Query and reasoning
    query_triples, find_paths, reason_inference

using Dates
using UUIDs
using Base.Threads

# ============================================================================
# Core Knowledge Types
# ============================================================================

"""
    Entity represents a node in the knowledge graph representing a concept.
    
# Fields
- `id::UUID`: Unique identifier
- `name::String`: Human-readable name
- `type::String`: Entity type (person, place, object, concept, etc.)
- `properties::Dict{String, Any}`: Additional metadata
- `created_at::DateTime`: Creation timestamp
- `confidence::Float32`: Belief in the entity's existence/validity [0,1]
"""
mutable struct Entity
    id::UUID
    name::String
    type::String
    properties::Dict{String, Any}
    created_at::DateTime
    confidence::Float32
    
    function Entity(name::String, type::String; 
                    properties::Dict{String, Any}=Dict{String, Any}(),
                    confidence::Float32=1.0f0)
        _validate_confidence(confidence, "Entity confidence")
        new(uuid4(), name, type, properties, now(), confidence)
    end
end

"""
    Relation represents an edge between entities in the knowledge graph.
    
# Fields
- `id::UUID`: Unique identifier
- `source_id::UUID`: Source entity ID
- `target_id::UUID`: Target entity ID
- `relation_type::String`: Type of relationship (is_a, part_of, knows, etc.)
- `properties::Dict{String, Any}`: Additional metadata
- `created_at::DateTime`: Creation timestamp
- `confidence::Float32`: Confidence in the relationship [0,1]
"""
mutable struct Relation
    id::UUID
    source_id::UUID
    target_id::UUID
    relation_type::String
    properties::Dict{String, Any}
    created_at::DateTime
    confidence::Float32
    
    function Relation(source_id::UUID, target_id::UUID, relation_type::String;
                      properties::Dict{String, Any}=Dict{String, Any}(),
                      confidence::Float32=1.0f0)
        _validate_confidence(confidence, "Relation confidence")
        new(uuid4(), source_id, target_id, relation_type, properties, now(), confidence)
    end
end

"""
    Event represents temporal knowledge - something that happens at a specific time.
    
# Fields
- `id::UUID`: Unique identifier
- `name::String`: Event name/description
- `timestamp::DateTime`: When the event occurred
- `duration::Union{Real, Nothing}`: Duration in seconds (if applicable)
- `entities::Vector{UUID}`: Entities involved in the event
- `properties::Dict{String, Any}`: Additional metadata
- `created_at::DateTime`: Creation timestamp
"""
mutable struct Event
    id::UUID
    name::String
    timestamp::DateTime
    duration::Union{Real, Nothing}
    entities::Vector{UUID}
    properties::Dict{String, Any}
    created_at::DateTime
    
    function Event(name::String, timestamp::DateTime;
                  duration::Union{Real, Nothing}=nothing,
                  entities::Vector{UUID}=UUID[],
                  properties::Dict{String, Any}=Dict{String, Any}())
        new(uuid4(), name, timestamp, duration, entities, properties, now())
    end
end

"""
    Belief represents probabilistic knowledge - something the system believes with some uncertainty.
    
# Fields
- `id::UUID`: Unique identifier
- `statement::String`: The belief statement
- `probability::Float32`: Probability the belief is true [0,1]
- `prior_probability::Float32`: Initial probability before evidence
- `evidence::Vector{UUID}`: Supporting evidence entity IDs
- `source::String`: Source of the belief
- `created_at::DateTime`: Creation timestamp
- `updated_at::DateTime`: Last update timestamp
"""
mutable struct Belief
    id::UUID
    statement::String
    probability::Float32
    prior_probability::Float32
    evidence::Vector{UUID}
    source::String
    created_at::DateTime
    updated_at::DateTime
    
    function Belief(statement::String, probability::Float32;
                    prior_probability::Float32=0.5f0,
                    evidence::Vector{UUID}=UUID[],
                    source::String="unknown")
        _validate_confidence(probability, "Belief probability")
        _validate_confidence(prior_probability, "Belief prior probability")
        now_dt = now()
        new(uuid4(), statement, probability, prior_probability, evidence, source, now_dt, now_dt)
    end
end

"""
    KnowledgeTriple represents a subject-predicate-object triple.
"""
struct KnowledgeTriple
    subject::UUID
    predicate::String
    object::UUID
    confidence::Float32
end

# ============================================================================
# Knowledge Graph Core Structure
# ============================================================================

"""
    KnowledgeGraphCore is the main graph data structure holding all knowledge.
    
# Fields
- `entities::Dict{UUID, Entity}`: Map of entity ID to Entity
- `relations::Dict{UUID, Relation}`: Map of relation ID to Relation
- `events::Vector{Event}`: All events
- `beliefs::Vector{Belief}`: All beliefs
- `entity_index::Dict{String, Vector{UUID}}`: Name to entity IDs
- `type_index::Dict{String, Vector{UUID}}`: Type to entity IDs
- `relation_index::Dict{String, Vector{UUID}}`: Relation type to relation IDs
- `lock::ReentrantLock`: Thread safety
"""
mutable struct KnowledgeGraphCore
    entities::Dict{UUID, Entity}
    relations::Dict{UUID, Relation}
    events::Vector{Event}
    beliefs::Vector{Belief}
    entity_index::Dict{String, Vector{UUID}}       # name -> entity IDs
    type_index::Dict{String, Vector{UUID}}          # type -> entity IDs
    relation_index::Dict{String, Vector{UUID}}     # relation_type -> relation IDs
    lock::ReentrantLock
    
    KnowledgeGraphCore() = new(
        Dict{UUID, Entity}(),
        Dict{UUID, Relation}(),
        Event[],
        Belief[],
        Dict{String, Vector{UUID}}(),
        Dict{String, Vector{UUID}}(),
        Dict{String, Vector{UUID}}(),
        ReentrantLock()
    )
end

# ============================================================================
# Validation Helpers
# ============================================================================

function _validate_confidence(value::Float32, field_name::String)
    if isnan(value) || isinf(value)
        throw(ArgumentError("Invalid $field_name: cannot be NaN or Inf"))
    end
    if value < 0.0f0 || value > 1.0f0
        throw(ArgumentError("$field_name must be in [0, 1], got $value"))
    end
end

# ============================================================================
# Entity Operations
# ============================================================================

"""
    add_entity!(kg::KnowledgeGraphCore, entity::Entity) -> Entity
    
Add an entity to the knowledge graph.
"""
function add_entity!(kg::KnowledgeGraphCore, entity::Entity)
    lock(kg.lock) do
        kg.entities[entity.id] = entity
        
        # Update name index
        if !haskey(kg.entity_index, entity.name)
            kg.entity_index[entity.name] = UUID[]
        end
        push!(kg.entity_index[entity.name], entity.id)
        
        # Update type index
        if !haskey(kg.type_index, entity.type)
            kg.type_index[entity.type] = UUID[]
        end
        push!(kg.type_index[entity.type], entity.id)
        
        entity
    end
end

"""
    remove_entity!(kg::KnowledgeGraphCore, entity_id::UUID) -> Bool
    
Remove an entity and all its relations from the graph.
"""
function remove_entity!(kg::KnowledgeGraphCore, entity_id::UUID)::Bool
    lock(kg.lock) do
        if !haskey(kg.entities, entity_id)
            return false
        end
        
        entity = kg.entities[entity_id]
        
        # Remove all relations involving this entity
        to_remove = UUID[]
        for (rid, rel) in kg.relations
            if rel.source_id == entity_id || rel.target_id == entity_id
                push!(to_remove, rid)
            end
        end
        for rid in to_remove
            remove_relation!(kg, rid)
        end
        
        # Remove from indices
        if haskey(kg.entity_index, entity.name)
            filter!(id -> id != entity_id, kg.entity_index[entity.name])
        end
        if haskey(kg.type_index, entity.type)
            filter!(id -> id != entity_id, kg.type_index[entity.type])
        end
        
        delete!(kg.entities, entity_id)
        true
    end
end

"""
    get_entity(kg::KnowledgeGraphCore, entity_id::UUID) -> Union{Entity, Nothing}
"""
function get_entity(kg::KnowledgeGraphCore, entity_id::UUID)
    lock(kg.lock) do
        get(kg.entities, entity_id, nothing)
    end
end

"""
    get_entity_by_name(kg::KnowledgeGraphCore, name::String) -> Vector{Entity}
"""
function get_entity_by_name(kg::KnowledgeGraphCore, name::String)
    lock(kg.lock) do
        entity_ids = get(kg.entity_index, name, UUID[])
        [kg.entities[eid] for eid in entity_ids if haskey(kg.entities, eid)]
    end
end

# ============================================================================
# Relation Operations
# ============================================================================

"""
    add_relation!(kg::KnowledgeGraphCore, relation::Relation) -> Relation
    
Add a relation to the knowledge graph.
"""
function add_relation!(kg::KnowledgeGraphCore, relation::Relation)
    lock(kg.lock) do
        # Validate source and target exist
        if !haskey(kg.entities, relation.source_id)
            throw(ArgumentError("Source entity $(relation.source_id) does not exist"))
        end
        if !haskey(kg.entities, relation.target_id)
            throw(ArgumentError("Target entity $(relation.target_id) does not exist"))
        end
        
        kg.relations[relation.id] = relation
        
        # Update relation type index
        if !haskey(kg.relation_index, relation.relation_type)
            kg.relation_index[relation.relation_type] = UUID[]
        end
        push!(kg.relation_index[relation.relation_type], relation.id)
        
        relation
    end
end

"""
    remove_relation!(kg::KnowledgeGraphCore, relation_id::UUID) -> Bool
"""
function remove_relation!(kg::KnowledgeGraphCore, relation_id::UUID)::Bool
    lock(kg.lock) do
        if !haskey(kg.relations, relation_id)
            return false
        end
        
        rel = kg.relations[relation_id]
        
        # Remove from type index
        if haskey(kg.relation_index, rel.relation_type)
            filter!(id -> id != relation_id, kg.relation_index[rel.relation_type])
        end
        
        delete!(kg.relations, relation_id)
        true
    end
end

"""
    get_relation(kg::KnowledgeGraphCore, relation_id::UUID) -> Union{Relation, Nothing}
"""
function get_relation(kg::KnowledgeGraphCore, relation_id::UUID)
    lock(kg.lock) do
        get(kg.relations, relation_id, nothing)
    end
end

"""
    get_relations(kg::KnowledgeGraphCore; source_id=nothing, target_id=nothing, relation_type=nothing) -> Vector{Relation}
"""
function get_relations(kg::KnowledgeGraphCore; 
                       source_id::Union{UUID, Nothing}=nothing,
                       target_id::Union{UUID, Nothing}=nothing,
                       relation_type::Union{String, Nothing}=nothing)
    lock(kg.lock) do
        results = Relation[]
        for rel in values(kg.relations)
            if source_id !== nothing && rel.source_id != source_id
                continue
            end
            if target_id !== nothing && rel.target_id != target_id
                continue
            end
            if relation_type !== nothing && rel.relation_type != relation_type
                continue
            end
            push!(results, rel)
        end
        results
    end
end

# ============================================================================
# Event Operations
# ============================================================================

"""
    add_event!(kg::KnowledgeGraphCore, event::Event) -> Event
"""
function add_event!(kg::KnowledgeGraphCore, event::Event)
    lock(kg.lock) do
        push!(kg.events, event)
        event
    end
end

"""
    get_events(kg::KnowledgeGraphCore; 
               start_time::Union{DateTime, Nothing}=nothing,
               end_time::Union{DateTime, Nothing}=nothing,
               entity_id::Union{UUID, Nothing}=nothing) -> Vector{Event}
"""
function get_events(kg::KnowledgeGraphCore;
                   start_time::Union{DateTime, Nothing}=nothing,
                   end_time::Union{DateTime, Nothing}=nothing,
                   entity_id::Union{UUID, Nothing}=nothing)
    lock(kg.lock) do
        results = Event[]
        for event in kg.events
            if start_time !== nothing && event.timestamp < start_time
                continue
            end
            if end_time !== nothing && event.timestamp > end_time
                continue
            end
            if entity_id !== nothing && entity_id ∉ event.entities
                continue
            end
            push!(results, event)
        end
        results
    end
end

# ============================================================================
# Belief Operations
# ============================================================================

"""
    add_belief!(kg::KnowledgeGraphCore, belief::Belief) -> Belief
"""
function add_belief!(kg::KnowledgeGraphCore, belief::Belief)
    lock(kg.lock) do
        push!(kg.beliefs, belief)
        belief
    end
end

"""
    get_beliefs(kg::KnowledgeGraphCore; 
                min_probability::Union{Float32, Nothing}=nothing,
                source::Union{String, Nothing}=nothing) -> Vector{Belief}
"""
function get_beliefs(kg::KnowledgeGraphCore;
                    min_probability::Union{Float32, Nothing}=nothing,
                    source::Union{String, Nothing}=nothing)
    lock(kg.lock) do
        results = Belief[]
        for belief in kg.beliefs
            if min_probability !== nothing && belief.probability < min_probability
                continue
            end
            if source !== nothing && belief.source != source
                continue
            end
            push!(results, belief)
        end
        results
    end
end

"""
    update_belief!(kg::KnowledgeGraphCore, belief_id::UUID; probability::Union{Float32, Nothing}=nothing, statement::Union{String, Nothing}=nothing) -> Union{Belief, Nothing}
"""
function update_belief!(kg::KnowledgeGraphCore, belief_id::UUID; 
                       probability::Union{Float32, Nothing}=nothing,
                       statement::Union{String, Nothing}=nothing)
    lock(kg.lock) do
        for belief in kg.beliefs
            if belief.id == belief_id
                if probability !== nothing
                    _validate_confidence(probability, "Belief probability update")
                    belief.probability = probability
                end
                if statement !== nothing
                    belief.statement = statement
                end
                belief.updated_at = now()
                return belief
            end
        end
        nothing
    end
end

# ============================================================================
# Query and Reasoning
# ============================================================================

"""
    query_triples(kg::KnowledgeGraphCore; subject=nothing, predicate=nothing, object=nothing) -> Vector{KnowledgeTriple}
"""
function query_triples(kg::KnowledgeGraphCore;
                      subject::Union{UUID, Nothing}=nothing,
                      predicate::Union{String, Nothing}=nothing,
                      object::Union{UUID, Nothing}=nothing)
    lock(kg.lock) do
        results = KnowledgeTriple[]
        for rel in values(kg.relations)
            if subject !== nothing && rel.source_id != subject
                continue
            end
            if predicate !== nothing && rel.relation_type != predicate
                continue
            end
            if object !== nothing && rel.target_id != object
                continue
            end
            push!(results, KnowledgeTriple(rel.source_id, rel.relation_type, rel.target_id, rel.confidence))
        end
        results
    end
end

"""
    find_paths(kg::KnowledgeGraphCore, source_id::UUID, target_id::UUID; max_depth::Int=3) -> Vector{Vector{UUID}}
    
Find all paths between two entities up to max_depth.
"""
function find_paths(kg::KnowledgeGraphCore, source_id::UUID, target_id::UUID; max_depth::Int=3)
    lock(kg.lock) do
        all_paths = Vector{UUID}[]
        
        # Build adjacency list
        adjacency = Dict{UUID, Vector{UUID}}()
        for rel in values(kg.relations)
            if !haskey(adjacency, rel.source_id)
                adjacency[rel.source_id] = UUID[]
            end
            push!(adjacency[rel.source_id], rel.target_id)
        end
        
        # BFS to find paths
        function bfs(current::UUID, path::Vector{UUID}, visited::Set{UUID})
            if current == target_id
                push!(all_paths, copy(path))
                return
            end
            if length(path) >= max_depth
                return
            end
            
            neighbors = get(adjacency, current, UUID[])
            for neighbor in neighbors
                if neighbor ∉ visited
                    push!(visited, neighbor)
                    push!(path, neighbor)
                    bfs(neighbor, path, visited)
                    pop!(path)
                    pop!(visited, neighbor)
                end
            end
        end
        
        bfs(source_id, [source_id], Set([source_id]))
        all_paths
    end
end

"""
    reason_inference(kg::KnowledgeGraphCore, entity_id::UUID; max_depth::Int=2) -> Vector{KnowledgeTriple}
    
Perform inference by following relations from an entity.
"""
function reason_inference(kg::KnowledgeGraphCore, entity_id::UUID; max_depth::Int=2)
    lock(kg.lock) do
        inferred = KnowledgeTriple[]
        
        # Get all outgoing relations
        for rel in values(kg.relations)
            if rel.source_id == entity_id
                push!(inferred, KnowledgeTriple(entity_id, rel.relation_type, rel.target_id, rel.confidence))
                
                # Follow to second level if requested
                if max_depth >= 2
                    for rel2 in values(kg.relations)
                        if rel2.source_id == rel.target_id
                            push!(inferred, KnowledgeTriple(entity_id, 
                                "$(rel.relation_type)->$(rel2.relation_type)", 
                                rel2.target_id, 
                                rel.confidence * rel2.confidence))
                        end
                    end
                end
            end
        end
        
        # Get all incoming relations
        for rel in values(kg.relations)
            if rel.target_id == entity_id
                push!(inferred, KnowledgeTriple(rel.source_id, rel.relation_type, entity_id, rel.confidence))
            end
        end
        
        inferred
    end
end

"""
    get_entity_stats(kg::KnowledgeGraphCore) -> Dict{String, Any}
"""
function get_entity_stats(kg::KnowledgeGraphCore)
    lock(kg.lock) do
        Dict(
            "entity_count" => length(kg.entities),
            "relation_count" => length(kg.relations),
            "event_count" => length(kg.events),
            "belief_count" => length(kg.beliefs),
            "entity_types" => Dict(typ => length(ids) for (typ, ids) in kg.type_index),
            "relation_types" => Dict(rel => length(ids) for (rel, ids) in kg.relation_index)
        )
    end
end

end # module
