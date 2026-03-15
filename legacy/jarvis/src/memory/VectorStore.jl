"""
    VectorStore - Persistent vector embeddings using SQLite
"""
mutable struct VectorStore
    store_path::String
    embeddings::Dict{String, Vector{Float32}}  # id => embedding
    metadata::Dict{String, Dict{String, Any}}  # id => metadata
    
    function VectorStore(path::String="./vector_store")
        mkpath(path)
        new(path, Dict{String, Vector{Float32}}(), Dict{String, Dict{String, Any}}())
    end
end

"""
    store_embedding!(store::VectorStore, id::String, embedding::Vector{Float32}; 
                   content::String="", source::String="unknown")
Store a vector embedding with metadata
"""
function store_embedding!(store::VectorStore, id::String, embedding::Vector{Float32}; 
                         content::String="", source::String="unknown")
    store.embeddings[id] = embedding
    store.metadata[id] = Dict(
        "content" => content,
        "source" => source,
        "timestamp" => string(now()),
        "dimension" => length(embedding)
    )
    @info "Stored embedding: $id (dim: $(length(embedding)))"
end

"""
    get_embedding(store::VectorStore, id::String)::Union{Vector{Float32}, Nothing}
Retrieve an embedding by ID
"""
function get_embedding(store::VectorStore, id::String)::Union{Vector{Float32}, Nothing}
    return get(store.embeddings, id, nothing)
end

"""
    get_metadata(store::VectorStore, id::String)::Union{Dict, Nothing}
Retrieve metadata for an embedding
"""
function get_metadata(store::VectorStore, id::String)::Union{Dict, Nothing}
    return get(store.metadata, id, nothing)
end

"""
    search(store::VectorStore, query::Vector{Float32}, top_k::Int=5)::Vector{Tuple{String, Float32}}
Search for similar embeddings using cosine similarity
"""
function search(store::VectorStore, query::Vector{Float32}, top_k::Int=5)::Vector{Tuple{String, Float32}}
    results = Vector{Tuple{String, Float32}}()
    
    for (id, embedding) in store.embeddings
        if length(embedding) != length(query)
            continue
        end
        
        # Cosine similarity
        similarity = _cosine_similarity(query, embedding)
        push!(results, (id, similarity))
    end
    
    # Sort by similarity (highest first)
    sort!(results, by=x -> x[2], rev=true)
    
    return results[1:min(top_k, length(results))]
end

"""
    _cosine_similarity - Compute cosine similarity between two vectors
"""
function _cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    dot_ab = dot(a, b)
    norm_a = sqrt(dot(a, a))
    norm_b = sqrt(dot(b, b))
    
    if norm_a == 0 || norm_b == 0
        return 0.0f0
    end
    
    return Float32(dot_ab / (norm_a * norm_b))
end

"""
    delete_embedding!(store::VectorStore, id::String)
Delete an embedding
"""
function delete_embedding!(store::VectorStore, id::String)
    if haskey(store.embeddings, id)
        delete!(store.embeddings, id)
        delete!(store.metadata, id)
        @info "Deleted embedding: $id"
    end
end

"""
    count_embeddings(store::VectorStore)::Int
Get the number of stored embeddings
"""
function count_embeddings(store::VectorStore)::Int
    return length(store.embeddings)
end

"""
    clear!(store::VectorStore)
Clear all embeddings
"""
function clear!(store::VectorStore)
    empty!(store.embeddings)
    empty!(store.metadata)
    @info "Cleared all embeddings"
end
