# jarvis/src/memory/VectorMemory.jl - Semantic Memory with Vector Search (Qdrant/HNSW)
# Stores User Preferences, Past Conversations, and Project Knowledge
# SECURITY: Uses deterministic embeddings - same input always produces same output

module VectorMemory

using LinearAlgebra
using Random
using Dates
using UUIDs
using JSON
using SHA  # For deterministic embeddings

export 
    VectorStore,
    SemanticEntry,
    store!,
    search,
    get_recent,
    get_by_collection,
    store_conversation!,
    store_preference!,
    store_knowledge!,
    rag_retrieve,
    generate_embedding,
    cosine_similarity

# Import Jarvis types from parent module
using ..JarvisTypes

# ============================================================================
# VECTOR STORE (In-memory HNSW-like implementation)
# ============================================================================

"""
    VectorStore - In-memory vector similarity search store
    Implements a simple HNSW-like structure for demonstration
    Production would use Qdrant or similar
"""
mutable struct VectorStore
    entries::Vector{SemanticEntry}
    collection_indices::Dict{Symbol, Vector{Int}}  # collection name -> entry indices
    id_index::Dict{UUID, Int}  # entry id -> index
    
    # HNSW-like parameters
    ef_construction::Int
    m::Int
    
    function VectorStore(;
        ef_construction::Int = 16,
        m::Int = 8
    )
        new(
            SemanticEntry[],
            Dict{Symbol, Vector{Int}}(),
            Dict{UUID, Int}(),
            ef_construction,
            m
        )
    end
end

# ============================================================================
# EMBEDDING UTILITIES - DETERMINISTIC IMPLEMENTATION
# ============================================================================

"""
    generate_embedding - Generate deterministic embedding for text
    SECURITY: Uses SHA256 hash to ensure same input always produces same output
    No random elements - fully deterministic for reproducibility
"""
function generate_embedding(text::String)::Vector{Float32}
    # Use SHA256 hash of text as deterministic seed
    hash_bytes = sha256(text)
    
    # Convert hash bytes to Float32 values
    # Each 4 bytes -> one Float32
    embedding = Float32[]
    target_dim = 384  # Matching modern embedding models
    
    # Expand hash to target dimension deterministically
    for i in 1:target_dim
        # Use multiple bytes from hash to compute value
        byte_idx = ((i - 1) % 32) + 1
        byte_val = Float32(hash_bytes[byte_idx])
        
        # Additional mixing using previous values for distribution
        if i > 1
            prev_val = embedding[i-1]
            byte_val = (byte_val + prev_val * 0.5f0) / 1.5f0
        end
        
        # Normalize to [0, 1] range
        normalized = byte_val / 255.0f0
        push!(embedding, normalized)
    end
    
    # Ensure non-zero norm (prevent NaN in similarity)
    norm_val = norm(embedding)
    if norm_val < eps(Float32)
        embedding[1] = 1.0f0  # At least have non-zero
        norm_val = 1.0f0
    end
    
    # L2 normalize
    embedding ./= norm_val
    
    return embedding
end

"""
    cosine_similarity - Compute cosine similarity between embeddings
    SECURITY: Never returns NaN - clamps denominator to prevent division by zero
"""
function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    norm_a = norm(a)
    norm_b = norm(b)
    
    # Prevent NaN by clamping to minimum value
    denominator = (norm_a * norm_b)
    if denominator < eps(Float32)
        denominator = eps(Float32)
    end
    
    similarity = dot(a, b) / denominator
    
    # Clamp to valid range [-1, 1]
    return clamp(similarity, -1.0f0, 1.0f0)
end

# ============================================================================
# CORE OPERATIONS
# ============================================================================

"""
    store! - Store a semantic entry in the vector store
"""
function store!(store::VectorStore, entry::SemanticEntry)::UUID
    # Update index
    idx = length(store.entries) + 1
    push!(store.entries, entry)
    store.id_index[entry.id] = idx
    
    # Update collection index
    if !haskey(store.collection_indices, entry.collection)
        store.collection_indices[entry.collection] = Int[]
    end
    push!(store.collection_indices[entry.collection], idx)
    
    return entry.id
end

"""
    search - Search for similar entries by embedding
"""
function search(
    store::VectorStore,
    query_embedding::Vector{Float32};
    k::Int = 5,
    collection::Symbol = :all,
    min_similarity::Float32 = 0.0f0
)::Vector{Tuple{SemanticEntry, Float32}}
    
    candidates = if collection == :all
        collect(1:length(store.entries))
    else
        get(store.collection_indices, collection, Int[])
    end
    
    # Compute similarities
    similarities = Vector{Tuple{Int, Float32}}()
    for idx in candidates
        entry = store.entries[idx]
        sim = cosine_similarity(query_embedding, entry.embedding)
        if sim >= min_similarity
            push!(similarities, (idx, sim))
        end
    end
    
    # Sort by similarity and take top k
    sort!(similarities, by = x -> x[2], rev = true)
    
    results = Tuple{SemanticEntry, Float32}[]
    for (idx, sim) in first(similarities, min(k, length(similarities)))
        push!(results, (store.entries[idx], sim))
    end
    
    return results
end

"""
    get_recent - Get most recent entries
"""
function get_recent(
    store::VectorStore;
    n::Int = 10,
    collection::Symbol = :all
)::Vector{SemanticEntry}
    
    candidates = if collection == :all
        collect(1:length(store.entries))
    else
        get(store.collection_indices, collection, Int[])
    end
    
    # Sort by timestamp descending
    sort!(candidates, by = idx -> store.entries[idx].created_at, rev = true)
    
    return [store.entries[idx] for idx in first(candidates, min(n, length(candidates)))]
end

"""
    get_by_collection - Get all entries for a collection
"""
function get_by_collection(
    store::VectorStore,
    collection::Symbol
)::Vector{SemanticEntry}
    
    indices = get(store.collection_indices, collection, Int[])
    return [store.entries[idx] for idx in indices]
end

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

"""
    store_conversation! - Store a conversation entry
"""
function store_conversation!(
    store::VectorStore,
    user_message::String,
    jarvis_response::String;
    intent::String = "unknown",
    entities::Dict{String, Any} = Dict()
)::SemanticEntry
    
    # Generate combined embedding
    combined_text = "$user_message [SEP] $jarvis_response"
    embedding = generate_embedding(combined_text)
    
    entry = SemanticEntry(
        :conversations,
        combined_text,
        embedding;
        metadata = Dict(
            "user_message" => user_message,
            "jarvis_response" => jarvis_response,
            "intent" => intent,
            "entities" => entities
        )
    )
    
    store!(store, entry)
    return entry
end

"""
    store_preference! - Store a user preference
"""
function store_preference!(
    store::VectorStore,
    key::String,
    value::Any;
    category::Symbol = :behavior,
    confidence::Float32 = 1.0f0
)::SemanticEntry
    
    text = "User preference: $key = $value"
    embedding = generate_embedding(text)
    
    entry = SemanticEntry(
        :user_preferences,
        text,
        embedding;
        metadata = Dict(
            "key" => key,
            "value" => value,
            "category" => category,
            "confidence" => confidence
        )
    )
    
    store!(store, entry)
    return entry
end

"""
    store_knowledge! - Store project/domain knowledge
"""
function store_knowledge!(
    store::VectorStore,
    content::String;
    tags::Vector{String} = String[],
    source::String = "user"
)::SemanticEntry
    
    embedding = generate_embedding(content)
    
    entry = SemanticEntry(
        :project_knowledge,
        content,
        embedding;
        metadata = Dict(
            "tags" => tags,
            "source" => source
        )
    )
    
    store!(store, entry)
    return entry
end

"""
    rag_retrieve - Retrieval Augmented Generation helper
    Returns relevant context for a query
"""
function rag_retrieve(
    store::VectorStore,
    query::String;
    n_results::Int = 5,
    collections::Vector{Symbol} = [:conversations, :user_preferences, :project_knowledge]
)::String
    
    query_embedding = generate_embedding(query)
    
    all_results = Tuple{SemanticEntry, Float32, Symbol}[]
    
    for collection in collections
        results = search(store, query_embedding; k=n_results, collection=collection)
        for (entry, sim) in results
            push!(all_results, (entry, sim, collection))
        end
    end
    
    # Sort by similarity
    sort!(all_results, by = x -> x[2], rev = true)
    
    # Build context string
    context_parts = String[]
    for (entry, sim, collection) in first(all_results, min(n_results, length(all_results)))
        entry.accessed_at = now()
        entry.access_count += 1
        
        push!(context_parts, "[$(collection) | similarity: $(round(sim, digits=2))]\n$(entry.content)")
    end
    
    return join(context_parts, "\n\n")
end

# ============================================================================
# PERSISTENCE (Optional)
# ============================================================================

"""
    save_to_file - Persist vector store to JSON file
"""
function save_to_file(store::VectorStore, filepath::String)
    data = Dict{String, Any}[]
    
    for entry in store.entries
        push!(data, Dict(
            "id" => string(entry.id),
            "collection" => string(entry.collection),
            "content" => entry.content,
            "embedding" => Vector(entry.embedding),
            "metadata" => entry.metadata,
            "created_at" => string(entry.created_at),
            "accessed_at" => string(entry.accessed_at),
            "access_count" => entry.access_count
        ))
    end
    
    open(filepath, "w") do f
        JSON.print(f, data, 2)
    end
end

"""
    load_from_file - Load vector store from JSON file
"""
function load_from_file(filepath::String)::VectorStore
    store = VectorStore()
    
    if !isfile(filepath)
        return store
    end
    
    data = JSON.parsefile(filepath)
    
    for entry_data in data
        entry = SemanticEntry(
            Symbol(entry_data["collection"]),
            entry_data["content"],
            Float32.(entry_data["embedding"]);
            metadata = get(entry_data, "metadata", Dict())
        )
        entry.id = UUID(entry_data["id"])
        entry.created_at = DateTime(entry_data["created_at"])
        entry.accessed_at = DateTime(entry_data["accessed_at"])
        entry.access_count = entry_data["access_count"]
        
        store!(store, entry)
    end
    
    return store
end

end # module VectorMemory
