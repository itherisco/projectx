# KnowledgeAPI.jl - Public API for Knowledge System
# Provides high-level interface for knowledge management

module KnowledgeAPI

export 
    # Main interface
    KnowledgeSystem, create_knowledge_system,
    # Fact operations
    add_fact, get_fact, remove_fact, update_fact,
    # Query operations
    query_knowledge, search_knowledge,
    # Inference
    infer, infer_new_facts,
    # Events and beliefs
    add_event, get_events, add_belief, update_belief, get_beliefs,
    # Utilities
    get_statistics, clear_knowledge

using Dates
using UUIDs
using Base.Threads

# Import from submodules
using ..KnowledgeGraph
using ..GraphDatabase

# ============================================================================
# Knowledge System - Main Interface
# ============================================================================

"""
    KnowledgeSystem is the main public interface for the knowledge system.
    
# Fields
- `db::GraphDB`: The underlying graph database
- `entity_cache::Dict{String, UUID}`: Cache of entity names to IDs
- `lock::ReentrantLock`: Thread safety
"""
mutable struct KnowledgeSystem
    db::GraphDB
    entity_cache::Dict{String, UUID}
    lock::ReentrantLock
    
    KnowledgeSystem(name::String) = new(
        create_database(name),
        Dict{String, UUID}(),
        ReentrantLock()
    )
end

"""
    create_knowledge_system(name::String="default") -> KnowledgeSystem
"""
function create_knowledge_system(name::String="default")::KnowledgeSystem
    KnowledgeSystem(name)
end

# ============================================================================
# Fact Operations
# ============================================================================

"""
    add_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String; 
             confidence::Float32=1.0f0, properties::Dict{String, Any}=Dict{String, Any}()) -> Bool
    
Add a fact (subject-predicate-object triple) to the knowledge system.
"""
function add_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String; 
                 confidence::Float32=1.0f0, 
                 properties::Dict{String, Any}=Dict{String, Any}())::Bool
    lock(ks.lock) do
        try
            # Get or create subject entity
            subject_id = _get_or_create_entity!(ks, subject, "concept")
            
            # Get or create object entity  
            object_id = _get_or_create_entity!(ks, object, "concept")
            
            # Create the relation
            add_relation(ks.db, subject_id, object_id, predicate; confidence=confidence, properties=properties)
            
            true
        catch e
            false
        end
    end
end

function _get_or_create_entity!(ks::KnowledgeSystem, name::String, default_type::String)::UUID
    # Check cache first
    if haskey(ks.entity_cache, name)
        return ks.entity_cache[name]
    end
    
    # Try to find existing entity
    existing = get_entity_by_name(ks.db, name)
    if !isempty(existing)
        ks.entity_cache[name] = first(existing).id
        return first(existing).id
    end
    
    # Create new entity
    entity = add_entity(ks.db, name, default_type)
    ks.entity_cache[name] = entity.id
    entity.id
end

"""
    get_fact(ks::KnowledgeSystem, subject::Union{String, UUID}, predicate::Union{String, Nothing}=nothing, object::Union{String, UUID, Nothing}=nothing) -> Vector{Dict{String, Any}}
    
Get facts from the knowledge system.
"""
function get_fact(ks::KnowledgeSystem, subject::Union{String, UUID}, predicate::Union{String, Nothing}=nothing, object::Union{String, UUID, Nothing}=nothing)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        # Resolve subject
        subject_id = _resolve_entity(ks, subject)
        if subject_id === nothing
            return Dict{String, Any}[]
        end
        
        # Resolve object if it's a string
        object_id = nothing
        if object !== nothing && object isa String
            object_id = _resolve_entity(ks, object)
        elseif object !== nothing
            object_id = object
        end
        
        # Query relations
        relations = list_relations(ks.db; source_id=subject_id, relation_type=predicate, target_id=object_id)
        
        results = Dict{String, Any}[]
        for rel in relations
            subject_entity = get_entity(ks.db, rel.source_id)
            object_entity = get_entity(ks.db, rel.target_id)
            
            if subject_entity !== nothing && object_entity !== nothing
                push!(results, Dict(
                    "subject" => subject_entity.name,
                    "predicate" => rel.relation_type,
                    "object" => object_entity.name,
                    "confidence" => rel.confidence,
                    "properties" => rel.properties
                ))
            end
        end
        
        results
    end
end

function _resolve_entity(ks::KnowledgeSystem, entity::Union{String, UUID})::Union{UUID, Nothing}
    if entity isa UUID
        return entity
    end
    
    # Check cache
    if haskey(ks.entity_cache, entity)
        return ks.entity_cache[entity]
    end
    
    # Try to find
    existing = get_entity_by_name(ks.db, entity)
    if !isempty(existing)
        ks.entity_cache[entity] = first(existing).id
        return first(existing).id
    end
    
    nothing
end

"""
    remove_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String) -> Bool
    
Remove a fact from the knowledge system.
"""
function remove_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String)::Bool
    lock(ks.lock) do
        subject_id = _resolve_entity(ks, subject)
        object_id = _resolve_entity(ks, object)
        
        if subject_id === nothing || object_id === nothing
            return false
        end
        
        relations = list_relations(ks.db; source_id=subject_id, relation_type=predicate, target_id=object_id)
        
        for rel in relations
            remove_relation(ks.db, rel.id)
        end
        
        !isempty(relations)
    end
end

"""
    update_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String; confidence::Union{Float32, Nothing}=nothing, properties::Union{Dict{String, Any}, Nothing}=nothing) -> Bool
"""
function update_fact(ks::KnowledgeSystem, subject::String, predicate::String, object::String; 
                    confidence::Union{Float32, Nothing}=nothing,
                    properties::Union{Dict{String, Any}, Nothing}=nothing)::Bool
    lock(ks.lock) do
        subject_id = _resolve_entity(ks, subject)
        object_id = _resolve_entity(ks, object)
        
        if subject_id === nothing || object_id === nothing
            return false
        end
        
        relations = list_relations(ks.db; source_id=subject_id, relation_type=predicate, target_id=object_id)
        
        if isempty(relations)
            return false
        end
        
        kwargs = Dict{Symbol, Any}()
        if confidence !== nothing
            kwargs[:confidence] = confidence
        end
        if properties !== nothing
            kwargs[:properties] = properties
        end
        
        update_relation(ks.db, first(relations).id; kwargs...)
        true
    end
end

# ============================================================================
# Query Operations
# ============================================================================

"""
    query_knowledge(ks::KnowledgeSystem, query::Dict{String, Any}) -> Vector{Dict{String, Any}}
    
Query the knowledge system.
"""
function query_knowledge(ks::KnowledgeSystem, query::Dict{String, Any})::Vector{Dict{String, Any}}
    query(ks.db, query)
end

"""
    search_knowledge(ks::KnowledgeSystem, search_term::String; fuzzy::Bool=false) -> Vector{Dict{String, Any}}
    
Search the knowledge system.
"""
function search_knowledge(ks::KnowledgeSystem, search_term::String; fuzzy::Bool=false)::Vector{Dict{String, Any}}
    if fuzzy
        fuzzy_search(ks.db, search_term)
    else
        search(ks.db, search_term)
    end
end

# ============================================================================
# Inference
# ============================================================================

"""
    infer(ks::KnowledgeSystem, entity::Union{String, UUID}; method::Symbol=:inference, max_depth::Int=2) -> Vector{Dict{String, Any}}
    
Perform inference on the knowledge system.
"""
function infer(ks::KnowledgeSystem, entity::Union{String, UUID}; method::Symbol=:inference, max_depth::Int=2)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        entity_id = _resolve_entity(ks, entity)
        if entity_id === nothing
            return Dict{String, Any}[]
        end
        
        triples = reasoning(ks.db, entity_id; method=method, max_depth=max_depth)
        
        results = Dict{String, Any}[]
        for triple in triples
            subject_entity = get_entity(ks.db, triple.subject)
            object_entity = get_entity(ks.db, triple.object)
            
            if subject_entity !== nothing && object_entity !== nothing
                push!(results, Dict(
                    "subject" => subject_entity.name,
                    "predicate" => triple.predicate,
                    "object" => object_entity.name,
                    "confidence" => triple.confidence
                ))
            end
        end
        
        results
    end
end

"""
    infer_new_facts(ks::KnowledgeSystem; min_confidence::Float32=0.5f0) -> Vector{Dict{String, Any}]
    
Automatically infer new facts from existing knowledge.
"""
function infer_new_facts(ks::KnowledgeSystem; min_confidence::Float32=0.5f0)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        inferred = Dict{String, Any}[]
        
        # For each entity, perform inference and add high-confidence results
        for entity in list_entities(ks.db)
            triples = reason_inference(ks.db, entity.id; max_depth=2)
            
            for triple in triples
                if triple.confidence >= min_confidence
                    # Check if this is actually a new fact
                    existing = list_relations(ks.db; 
                        source_id=triple.subject, 
                        relation_type=triple.predicate, 
                        target_id=triple.object)
                    
                    if isempty(existing)
                        subject_entity = get_entity(ks.db, triple.subject)
                        object_entity = get_entity(ks.db, triple.object)
                        
                        if subject_entity !== nothing && object_entity !== nothing
                            push!(inferred, Dict(
                                "subject" => subject_entity.name,
                                "predicate" => triple.predicate,
                                "object" => object_entity.name,
                                "confidence" => triple.confidence,
                                "inferred" => true
                            ))
                        end
                    end
                end
            end
        end
        
        inferred
    end
end

# ============================================================================
# Events
# ============================================================================

"""
    add_event(ks::KnowledgeSystem, name::String, timestamp::DateTime; 
              entities::Vector{String}=String[], duration::Union{Real, Nothing}=nothing,
              properties::Dict{String, Any}=Dict{String, Any}()) -> Bool
"""
function add_event(ks::KnowledgeSystem, name::String, timestamp::DateTime; 
                  entities::Vector{String}=String[],
                  duration::Union{Real, Nothing}=nothing,
                  properties::Dict{String, Any}=Dict{String, Any}())::Bool
    lock(ks.lock) do
        try
            entity_ids = UUID[]
            for ent_name in entities
                ent_id = _get_or_create_entity!(ks, ent_name, "entity")
                push!(entity_ids, ent_id)
            end
            
            event = Event(name, timestamp; duration=duration, entities=entity_ids, properties=properties)
            add_event!(ks.db.graph, event)
            true
        catch e
            false
        end
    end
end

"""
    get_events(ks::KnowledgeSystem; 
               start_time::Union{DateTime, Nothing}=nothing,
               end_time::Union{DateTime, Nothing}=nothing,
               entity::Union{String, Nothing}=nothing) -> Vector{Dict{String, Any}}
"""
function get_events(ks::KnowledgeSystem;
                   start_time::Union{DateTime, Nothing}=nothing,
                   end_time::Union{DateTime, Nothing}=nothing,
                   entity::Union{String, Nothing}=nothing)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        entity_id = entity !== nothing ? _resolve_entity(ks, entity) : nothing
        
        events = get_events(ks.db.graph; start_time=start_time, end_time=end_time, entity_id=entity_id)
        
        results = Dict{String, Any}[]
        for event in events
            entity_names = String[]
            for ent_id in event.entities
                ent = get_entity(ks.db, ent_id)
                if ent !== nothing
                    push!(entity_names, ent.name)
                end
            end
            
            push!(results, Dict(
                "name" => event.name,
                "timestamp" => event.timestamp,
                "duration" => event.duration,
                "entities" => entity_names,
                "properties" => event.properties
            ))
        end
        
        results
    end
end

# ============================================================================
# Beliefs
# ============================================================================

"""
    add_belief(ks::KnowledgeSystem, statement::String, probability::Float32; 
               prior_probability::Float32=0.5f0,
               evidence::Vector{String}=String[],
               source::String="inference") -> Bool
"""
function add_belief(ks::KnowledgeSystem, statement::String, probability::Float32;
                   prior_probability::Float32=0.5f0,
                   evidence::Vector{String}=String[],
                   source::String="inference")::Bool
    lock(ks.lock) do
        try
            evidence_ids = UUID[]
            for ev_name in evidence
                ev_id = _resolve_entity(ks, ev_name)
                if ev_id !== nothing
                    push!(evidence_ids, ev_id)
                end
            end
            
            belief = Belief(statement, probability; prior_probability=prior_probability, evidence=evidence_ids, source=source)
            add_belief!(ks.db.graph, belief)
            true
        catch e
            false
        end
    end
end

"""
    update_belief(ks::KnowledgeSystem, statement::String; probability::Union{Float32, Nothing}=nothing) -> Bool
"""
function update_belief(ks::KnowledgeSystem, statement::String; probability::Union{Float32, Nothing}=nothing)::Bool
    lock(ks.lock) do
        for belief in ks.db.graph.beliefs
            if belief.statement == statement
                if probability !== nothing
                    belief.probability = probability
                    belief.updated_at = now()
                end
                return true
            end
        end
        false
    end
end

"""
    get_beliefs(ks::KnowledgeSystem; min_probability::Union{Float32, Nothing}=nothing, source::Union{String, Nothing}=nothing) -> Vector{Dict{String, Any}}
"""
function get_beliefs(ks::KnowledgeSystem;
                    min_probability::Union{Float32, Nothing}=nothing,
                    source::Union{String, Nothing}=nothing)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        beliefs = get_beliefs(ks.db.graph; min_probability=min_probability, source=source)
        
        results = Dict{String, Any}[]
        for belief in beliefs
            push!(results, Dict(
                "statement" => belief.statement,
                "probability" => belief.probability,
                "prior_probability" => belief.prior_probability,
                "source" => belief.source,
                "created_at" => belief.created_at,
                "updated_at" => belief.updated_at
            ))
        end
        
        results
    end
end

# ============================================================================
# Utilities
# ============================================================================

"""
    get_statistics(ks::KnowledgeSystem) -> Dict{String, Any}
"""
function get_statistics(ks::KnowledgeSystem)::Dict{String, Any}
    get_stats(ks.db)
end

"""
    clear_knowledge(ks::KnowledgeSystem; keep_entities::Vector{String}=String[]) -> Bool
    
Clear all knowledge except specified entities.
"""
function clear_knowledge(ks::KnowledgeSystem; keep_entities::Vector{String}=String[])::Bool
    lock(ks.lock) do
        try
            # Keep track of entities to keep
            keep_ids = UUID[]
            for name in keep_entities
                ent_id = _resolve_entity(ks, name)
                if ent_id !== nothing
                    push!(keep_ids, ent_id)
                end
            end
            
            # Remove all relations
            for rel in list_relations(ks.db)
                remove_relation(ks.db, rel.id)
            end
            
            # Remove all entities except kept ones
            for entity in list_entities(ks.db)
                if entity.id ∉ keep_ids
                    remove_entity(ks.db, entity.id)
                end
            end
            
            # Clear events and beliefs
            ks.db.graph.events = Event[]
            ks.db.graph.beliefs = Belief[]
            
            # Clear cache
            ks.entity_cache = Dict{String, UUID}()
            
            true
        catch e
            false
        end
    end
end

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    add_entity_type(ks::KnowledgeSystem, name::String, entity_type::String) -> Bool
"""
function add_entity_type(ks::KnowledgeSystem, name::String, entity_type::String)::Bool
    lock(ks.lock) do
        try
            entity = add_entity(ks.db, name, entity_type)
            ks.entity_cache[name] = entity.id
            return true
        catch e
            return false
        end
    end
end

"""
    get_related(ks::KnowledgeSystem, entity::String; relation_type::Union{String, Nothing}=nothing) -> Vector{Dict{String, Any}}
"""
function get_related(ks::KnowledgeSystem, entity::String; relation_type::Union{String, Nothing}=nothing)::Vector{Dict{String, Any}}
    lock(ks.lock) do
        entity_id = _resolve_entity(ks, entity)
        if entity_id === nothing
            return Dict{String, Any}[]
        end
        
        neighbors = get_neighbors(ks.db, entity_id; relation_type=relation_type)
        
        results = Dict{String, Any}[]
        for neighbor in neighbors
            push!(results, Dict(
                "entity" => neighbor["entity"].name,
                "entity_type" => neighbor["entity"].type,
                "relation" => neighbor["relation"].relation_type,
                "direction" => neighbor["direction"],
                "confidence" => neighbor["relation"].confidence
            ))
        end
        
        results
    end
end

end # module
