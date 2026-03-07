# GraphDatabase.jl - Graph Database Operations
# Provides database-like operations for the knowledge graph

module GraphDatabase

export 
    # Database operations
    GraphDB, create_database, open_database, close_database,
    # Entity operations
    add_entity, remove_entity, update_entity, get_entity, list_entities,
    # Relation operations  
    add_relation, remove_relation, update_relation, get_relation, list_relations,
    # Query operations
    query, search, fuzzy_search, get_neighbors,
    # Reasoning operations
    reasoning, transitive_closure, common_neighbors, centrality

using Dates
using UUIDs
using Base.Threads

# Import from KnowledgeGraph
using ..KnowledgeGraph

# ============================================================================
# Graph Database Structure
# ============================================================================

"""
    GraphDB is a database wrapper around KnowledgeGraphCore providing 
    additional database-like features such as transactions, persistence hints, etc.
    
# Fields
- `graph::KnowledgeGraphCore`: The underlying knowledge graph
- `name::String`: Database name
- `created_at::DateTime`: Creation timestamp
- `dirty::Bool`: Whether there are unsaved changes
- `lock::ReentrantLock`: Thread safety
"""
mutable struct GraphDB
    graph::KnowledgeGraphCore
    name::String
    created_at::DateTime
    last_modified::DateTime
    dirty::Bool
    lock::ReentrantLock
    
    GraphDB(name::String) = new(
        KnowledgeGraphCore(),
        name,
        now(),
        now(),
        false,
        ReentrantLock()
    )
end

"""
    create_database(name::String) -> GraphDB
"""
function create_database(name::String)::GraphDB
    GraphDB(name)
end

"""
    open_database(name::String) -> GraphDB
"""
function open_database(name::String)::GraphDB
    # In a full implementation, this would load from disk
    create_database(name)
end

"""
    close_database(db::GraphDB)
"""
function close_database(db::GraphDB)
    lock(db.lock) do
        db.dirty = false
    end
end

# ============================================================================
# Entity Database Operations
# ============================================================================

"""
    add_entity(db::GraphDB, name::String, entity_type::String; kwargs...) -> Entity
"""
function add_entity(db::GraphDB, name::String, entity_type::String; kwargs...)::Entity
    lock(db.lock) do
        entity = Entity(name, entity_type; kwargs...)
        add_entity!(db.graph, entity)
        db.dirty = true
        db.last_modified = now()
        entity
    end
end

"""
    remove_entity(db::GraphDB, entity_id::UUID) -> Bool
"""
function remove_entity(db::GraphDB, entity_id::UUID)::Bool
    lock(db.lock) do
        result = remove_entity!(db.graph, entity_id)
        if result
            db.dirty = true
            db.last_modified = now()
        end
        result
    end
end

"""
    update_entity(db::GraphDB, entity_id::UUID; kwargs...) -> Union{Entity, Nothing}
"""
function update_entity(db::GraphDB, entity_id::UUID; kwargs...)::Union{Entity, Nothing}
    lock(db.lock) do
        entity = get_entity(db.graph, entity_id)
        if entity === nothing
            return nothing
        end
        
        for (key, value) in kwargs
            if key == :name
                entity.name = value
            elseif key == :type
                entity.type = value
            elseif key == :properties
                entity.properties = value
            elseif key == :confidence
                entity.confidence = value
            end
        end
        
        db.dirty = true
        db.last_modified = now()
        entity
    end
end

"""
    get_entity(db::GraphDB, entity_id::UUID) -> Union{Entity, Nothing}
"""
function get_entity(db::GraphDB, entity_id::UUID)::Union{Entity, Nothing}
    get_entity(db.graph, entity_id)
end

"""
    get_entity_by_name(db::GraphDB, name::String) -> Vector{Entity}
"""
function get_entity_by_name(db::GraphDB, name::String)::Vector{Entity}
    get_entity_by_name(db.graph, name)
end

"""
    list_entities(db::GraphDB; entity_type::Union{String, Nothing}=nothing) -> Vector{Entity}
"""
function list_entities(db::GraphDB; entity_type::Union{String, Nothing}=nothing)::Vector{Entity}
    lock(db.lock) do
        if entity_type !== nothing
            type_ids = get(db.graph.type_index, entity_type, UUID[])
            return [db.graph.entities[eid] for eid in type_ids if haskey(db.graph.entities, eid)]
        end
        collect(values(db.graph.entities))
    end
end

# ============================================================================
# Relation Database Operations
# ============================================================================

"""
    add_relation(db::GraphDB, source_id::UUID, target_id::UUID, relation_type::String; kwargs...) -> Relation
"""
function add_relation(db::GraphDB, source_id::UUID, target_id::UUID, relation_type::String; kwargs...)::Relation
    lock(db.lock) do
        relation = Relation(source_id, target_id, relation_type; kwargs...)
        add_relation!(db.graph, relation)
        db.dirty = true
        db.last_modified = now()
        relation
    end
end

"""
    add_relation_by_name(db::GraphDB, source_name::String, target_name::String, relation_type::String; kwargs...) -> Union{Relation, Nothing}
"""
function add_relation_by_name(db::GraphDB, source_name::String, target_name::String, relation_type::String; kwargs...)::Union{Relation, Nothing}
    lock(db.lock) do
        source_entities = get_entity_by_name(db.graph, source_name)
        target_entities = get_entity_by_name(db.graph, target_name)
        
        if isempty(source_entities) || isempty(target_entities)
            return nothing
        end
        
        source_id = first(source_entities).id
        target_id = first(target_entities).id
        
        relation = Relation(source_id, target_id, relation_type; kwargs...)
        add_relation!(db.graph, relation)
        db.dirty = true
        db.last_modified = now()
        relation
    end
end

"""
    remove_relation(db::GraphDB, relation_id::UUID) -> Bool
"""
function remove_relation(db::GraphDB, relation_id::UUID)::Bool
    lock(db.lock) do
        result = remove_relation!(db.graph, relation_id)
        if result
            db.dirty = true
            db.last_modified = now()
        end
        result
    end
end

"""
    update_relation(db::GraphDB, relation_id::UUID; kwargs...) -> Union{Relation, Nothing}
"""
function update_relation(db::GraphDB, relation_id::UUID; kwargs...)::Union{Relation, Nothing}
    lock(db.lock) do
        relation = get_relation(db.graph, relation_id)
        if relation === nothing
            return nothing
        end
        
        for (key, value) in kwargs
            if key == :relation_type
                # Remove from old index
                if haskey(db.graph.relation_index, relation.relation_type)
                    filter!(id -> id != relation_id, db.graph.relation_index[relation.relation_type])
                end
                relation.relation_type = value
                # Add to new index
                if !haskey(db.graph.relation_index, value)
                    db.graph.relation_index[value] = UUID[]
                end
                push!(db.graph.relation_index[value], relation_id)
            elseif key == :properties
                relation.properties = value
            elseif key == :confidence
                relation.confidence = value
            end
        end
        
        db.dirty = true
        db.last_modified = now()
        relation
    end
end

"""
    get_relation(db::GraphDB, relation_id::UUID) -> Union{Relation, Nothing}
"""
function get_relation(db::GraphDB, relation_id::UUID)::Union{Relation, Nothing}
    get_relation(db.graph, relation_id)
end

"""
    list_relations(db::GraphDB; relation_type::Union{String, Nothing}=nothing, source_id::Union{UUID, Nothing}=nothing, target_id::Union{UUID, Nothing}=nothing) -> Vector{Relation}
"""
function list_relations(db::GraphDB; 
                       relation_type::Union{String, Nothing}=nothing,
                       source_id::Union{UUID, Nothing}=nothing,
                       target_id::Union{UUID, Nothing}=nothing)::Vector{Relation}
    get_relations(db.graph; relation_type=relation_type, source_id=source_id, target_id=target_id)
end

# ============================================================================
# Query Operations
# ============================================================================

"""
    query(db::GraphDB, query_spec::Dict{String, Any}) -> Vector{Dict{String, Any}}
    
Query the graph database with a specification.
"""
function query(db::GraphDB, query_spec::Dict{String, Any})::Vector{Dict{String, Any}}
    lock(db.lock) do
        results = Dict{String, Any}[]
        
        # Query by entity type
        if haskey(query_spec, "entity_type")
            entities = list_entities(db, entity_type=query_spec["entity_type"])
            for ent in entities
                push!(results, Dict(
                    "type" => "entity",
                    "id" => ent.id,
                    "name" => ent.name,
                    "entity_type" => ent.type,
                    "properties" => ent.properties,
                    "confidence" => ent.confidence
                ))
            end
        end
        
        # Query by relation type
        if haskey(query_spec, "relation_type")
            relations = list_relations(db, relation_type=query_spec["relation_type"])
            for rel in relations
                push!(results, Dict(
                    "type" => "relation",
                    "id" => rel.id,
                    "source_id" => rel.source_id,
                    "target_id" => rel.target_id,
                    "relation_type" => rel.relation_type,
                    "properties" => rel.properties,
                    "confidence" => rel.confidence
                ))
            end
        end
        
        # Query by entity name (exact match)
        if haskey(query_spec, "name")
            entities = get_entity_by_name(db.graph, query_spec["name"])
            for ent in entities
                push!(results, Dict(
                    "type" => "entity",
                    "id" => ent.id,
                    "name" => ent.name,
                    "entity_type" => ent.type,
                    "properties" => ent.properties,
                    "confidence" => ent.confidence
                ))
            end
        end
        
        results
    end
end

"""
    search(db::GraphDB, query::String) -> Vector{Dict{String, Any}}
    
Full-text search across the graph.
"""
function search(db::GraphDB, query::String)::Vector{Dict{String, Any}}
    lock(db.lock) do
        results = Dict{String, Any}[]
        query_lower = lowercase(query)
        
        # Search entities
        for entity in values(db.graph.entities)
            if occursin(query_lower, lowercase(entity.name)) ||
               occursin(query_lower, lowercase(entity.type)) ||
               any(occursin(query_lower, lowercase(v)) for v in values(entity.properties))
                push!(results, Dict(
                    "type" => "entity",
                    "id" => entity.id,
                    "name" => entity.name,
                    "entity_type" => entity.type,
                    "matched_on" => "name/type/properties"
                ))
            end
        end
        
        # Search relations
        for relation in values(db.graph.relations)
            if occursin(query_lower, lowercase(relation.relation_type)) ||
               any(occursin(query_lower, lowercase(v)) for v in values(relation.properties))
                push!(results, Dict(
                    "type" => "relation",
                    "id" => relation.id,
                    "source_id" => relation.source_id,
                    "target_id" => relation.target_id,
                    "relation_type" => relation.relation_type,
                    "matched_on" => "relation_type/properties"
                ))
            end
        end
        
        # Search beliefs
        for belief in db.graph.beliefs
            if occursin(query_lower, lowercase(belief.statement))
                push!(results, Dict(
                    "type" => "belief",
                    "id" => belief.id,
                    "statement" => belief.statement,
                    "probability" => belief.probability,
                    "source" => belief.source
                ))
            end
        end
        
        results
    end
end

"""
    fuzzy_search(db::GraphDB, query::String; threshold::Float64=0.5) -> Vector{Dict{String, Any}}
    
Fuzzy search with similarity threshold.
"""
function fuzzy_search(db::GraphDB, query::String; threshold::Float64=0.5)::Vector{Dict{String, Any}}
    lock(db.lock) do
        results = Dict{String, Any}[]
        
        # Simple fuzzy match using character overlap
        for entity in values(db.graph.entities)
            similarity = _calculate_similarity(query, entity.name)
            if similarity >= threshold
                push!(results, Dict(
                    "type" => "entity",
                    "id" => entity.id,
                    "name" => entity.name,
                    "entity_type" => entity.type,
                    "similarity" => similarity
                ))
            end
        end
        
        sort!(results, by=x->get(x, "similarity", 0.0), rev=true)
    end
end

function _calculate_similarity(s1::String, s2::String)::Float64
    # Jaccard similarity on character n-grams
    s1_lower = lowercase(s1)
    s2_lower = lowercase(s2)
    
    if isempty(s1_lower) || isempty(s2_lower)
        return 0.0
    end
    
    # Character bigrams
    function bigrams(s::String)
        n = length(s)
        if n < 2
            return Set([s])
        end
        Set([s[i:i+1] for i in 1:n-1])
    end
    
    b1 = bigrams(s1_lower)
    b2 = bigrams(s2_lower)
    
    intersection = length(intersect(b1, b2))
    union = length(union(b1, b2))
    
    union > 0 ? Float64(intersection) / Float64(union) : 0.0
end

"""
    get_neighbors(db::GraphDB, entity_id::UUID; relation_type::Union{String, Nothing}=nothing, direction::Symbol=:both) -> Vector{Dict{String, Any}}
    
Get all neighboring entities.
"""
function get_neighbors(db::GraphDB, entity_id::UUID; 
                       relation_type::Union{String, Nothing}=nothing,
                       direction::Symbol=:both)::Vector{Dict{String, Any}}
    lock(db.lock) do
        neighbors = Dict{String, Any}[]
        
        for rel in values(db.graph.relations)
            if relation_type !== nothing && rel.relation_type != relation_type
                continue
            end
            
            if direction ∈ [:outgoing, :both] && rel.source_id == entity_id
                if haskey(db.graph.entities, rel.target_id)
                    target = db.graph.entities[rel.target_id]
                    push!(neighbors, Dict(
                        "entity" => target,
                        "relation" => rel,
                        "direction" => "outgoing"
                    ))
                end
            end
            
            if direction ∈ [:incoming, :both] && rel.target_id == entity_id
                if haskey(db.graph.entities, rel.source_id)
                    source = db.graph.entities[rel.source_id]
                    push!(neighbors, Dict(
                        "entity" => source,
                        "relation" => rel,
                        "direction" => "incoming"
                    ))
                end
            end
        end
        
        neighbors
    end
end

# ============================================================================
# Reasoning Operations
# ============================================================================

"""
    reasoning(db::GraphDB, entity_id::UUID; method::Symbol=:inference, kwargs...) -> Vector{KnowledgeTriple}
    
Perform reasoning on the graph.
"""
function reasoning(db::GraphDB, entity_id::UUID; method::Symbol=:inference, kwargs...)::Vector{KnowledgeTriple}
    lock(db.lock) do
        if method == :inference
            reason_inference(db.graph, entity_id; kwargs...)
        elseif method == :transitive_closure
            transitive_closure(db.graph, entity_id; kwargs...)
        else
            throw(ArgumentError("Unknown reasoning method: $method"))
        end
    end
end

"""
    transitive_closure(db::GraphDB, entity_id::UUID; max_depth::Int=5) -> Vector{KnowledgeTriple}
    
Get all entities reachable from entity_id.
"""
function transitive_closure(db::GraphDB, entity_id::UUID; max_depth::Int=5)::Vector{KnowledgeTriple}
    lock(db.lock) do
        results = KnowledgeTriple[]
        visited = Set{UUID}()
        
        function traverse(current::UUID, depth::Int)
            if depth > max_depth || current in visited
                return
            end
            push!(visited, current)
            
            for rel in values(db.graph.relations)
                if rel.source_id == current
                    push!(results, KnowledgeTriple(current, rel.relation_type, rel.target_id, rel.confidence))
                    traverse(rel.target_id, depth + 1)
                end
            end
        end
        
        traverse(entity_id, 0)
        results
    end
end

"""
    common_neighbors(db::GraphDB, entity1_id::UUID, entity2_id::UUID) -> Vector{Entity}
    
Find entities that are neighbors of both given entities.
"""
function common_neighbors(db::GraphDB, entity1_id::UUID, entity2_id::UUID)::Vector{Entity}
    lock(db.lock) do
        neighbors1 = Set{UUID}()
        neighbors2 = Set{UUID}()
        
        for rel in values(db.graph.relations)
            if rel.source_id == entity1_id
                push!(neighbors1, rel.target_id)
            end
            if rel.source_id == entity2_id
                push!(neighbors2, rel.target_id)
            end
            if rel.target_id == entity1_id
                push!(neighbors1, rel.source_id)
            end
            if rel.target_id == entity2_id
                push!(neighbors2, rel.source_id)
            end
        end
        
        common = intersect(neighbors1, neighbors2)
        [db.graph.entities[nid] for nid in common if haskey(db.graph.entities, nid)]
    end
end

"""
    centrality(db::GraphDB, entity_id::UUID) -> Dict{String, Float64}
    
Calculate centrality metrics for an entity.
"""
function centrality(db::GraphDB, entity_id::UUID)::Dict{String, Float64}
    lock(db.lock) do
        in_degree = 0
        out_degree = 0
        
        for rel in values(db.graph.relations)
            if rel.source_id == entity_id
                out_degree += 1
            end
            if rel.target_id == entity_id
                in_degree += 1
            end
        end
        
        total_degree = in_degree + out_degree
        
        Dict(
            "in_degree" => Float64(in_degree),
            "out_degree" => Float64(out_degree),
            "total_degree" => Float64(total_degree),
            "normalized_degree" => total_degree / max(1, length(db.graph.relations))
        )
    end
end

# ============================================================================
# Database Info
# ============================================================================

"""
    get_stats(db::GraphDB) -> Dict{String, Any}
"""
function get_stats(db::GraphDB)::Dict{String, Any}
    lock(db.lock) do
        entity_stats = get_entity_stats(db.graph)
        Dict(
            "name" => db.name,
            "created_at" => db.created_at,
            "last_modified" => db.last_modified,
            "dirty" => db.dirty,
            "entity_count" => entity_stats["entity_count"],
            "relation_count" => entity_stats["relation_count"],
            "event_count" => entity_stats["event_count"],
            "belief_count" => entity_stats["belief_count"],
            "entity_types" => entity_stats["entity_types"],
            "relation_types" => entity_stats["relation_types"]
        )
    end
end

end # module
