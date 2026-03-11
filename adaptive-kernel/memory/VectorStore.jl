# adaptive-kernel/memory/VectorStore.jl - Qdrant Vector Database Integration
# Provides semantic long-term memory with similarity search
# REST API-based integration (no external Qdrant client required)

module VectorStore

using HTTP
using JSON
using SHA
using Random
using Dates
using UUIDs
using LinearAlgebra
using Logging

export 
    # Core types
    SemanticMemory,
    MemoryEntry,
    VectorStoreConfig,
    
    # Core functions
    create_memory,
    store_memory,
    recall_similar,
    delete_memory,
    list_collections,
    
    # Embedding generation
    generate_embedding,
    generate_embedding_ollama,
    
    # Kernel integration hooks
    store_interaction,
    recall_relevant,
    get_memory_context,
    init_kernel_memory,
    get_kernel_memory,
    set_kernel_memory,
    is_memory_available,
    
    # Utility
    cosine_similarity,
    is_qdrant_available,
    get_memory_stats

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    VectorStoreConfig - Configuration for vector store
"""
@with_kw struct VectorStoreConfig
    qdrant_host::String = "localhost"
    qdrant_port::Int = 6333
    embedding_dim::Int = 384
    default_top_k::Int = 5
    distance_metric::String = "Cosine"  # Cosine, Euclid, Dot
    ollama_host::String = "localhost"
    ollama_port::Int = 11434
    use_ollama::Bool = false  # Set to true if Ollama is available
end

# ============================================================================
# MEMORY TYPES
# ============================================================================

"""
    MemoryEntry - A stored memory with embedding and metadata
"""
mutable struct MemoryEntry
    id::UUID
    collection::String
    content::String
    embedding::Vector{Float32}
    metadata::Dict{String, Any}
    created_at::DateTime
    accessed_at::DateTime
    access_count::Int
    
    function MemoryEntry(
        collection::String,
        content::String,
        embedding::Vector{Float32};
        metadata::Dict{String, Any} = Dict{String, Any}()
    )
        new(
            uuid4(),
            collection,
            content,
            embedding,
            metadata,
            now(),
            now(),
            0
        )
    end
end

"""
    SemanticMemory - Main interface to Qdrant vector database
"""
mutable struct SemanticMemory
    config::VectorStoreConfig
    
    # Connection state
    is_connected::Bool
    
    # Local cache for offline fallbacks
    local_cache::Vector{MemoryEntry}
    cache_by_collection::Dict{String, Vector{Int}}
    
    # Statistics
    total_stored::Int
    total_recalled::Int
    
    # Constructor
    function SemanticMemory(config::VectorStoreConfig = VectorStoreConfig())
        new(
            config,
            false,  # is_connected
            MemoryEntry[],
            Dict{String, Vector{Int}}(),
            0,
            0
        )
    end
end

# ============================================================================
# EMBEDDING GENERATION
# ============================================================================

"""
    generate_embedding - Generate embedding for text
    Tries Ollama first if configured, falls back to deterministic hash-based
"""
function generate_embedding(text::String)::Vector{Float32}
    memory = nothing  # Will be passed when called from store_memory
    
    # Try Ollama if enabled
    if get(ENV, "USE_OLLAMA", "false") == "true"
        try
            return generate_embedding_ollama(text)
        catch e
            @warn "Ollama embedding failed, falling back to hash-based: $e"
        end
    end
    
    # Fallback: deterministic hash-based embedding
    return _generate_hash_embedding(text)
end

function generate_embedding(text::String, memory::SemanticMemory)::Vector{Float32}
    if memory.config.use_ollama
        try
            return generate_embedding_ollama(text, memory.config)
        catch e
            @warn "Ollama embedding failed, falling back to hash-based: $e"
        end
    end
    
    return _generate_hash_embedding(text)
end

"""
    generate_embedding_ollama - Get embedding from local Ollama server
"""
function generate_embedding_ollama(text::String, config::VectorStoreConfig = VectorStoreConfig())::Vector{Float32}
    url = "http://$(config.ollama_host):$(config.ollama_port)/api/embeddings"
    
    body = JSON.json(Dict(
        "model" => "nomic-embed-text",
        "prompt" => text
    ))
    
    response = HTTP.post(url, 
        ["Content-Type" => "application/json"],
        body;
        timeout = 30
    )
    
    if response.status != 200
        error("Ollama API returned status $(response.status)")
    end
    
    data = JSON.parse(String(response.body))
    embedding = Float32.(data["embedding"])
    
    return embedding
end

"""
    _generate_hash_embedding - Deterministic hash-based pseudo-embedding
    Used when Ollama is not available
"""
function _generate_hash_embedding(text::String)::Vector{Float32}
    # Use SHA256 hash of text as deterministic seed
    hash_bytes = sha256(text)
    
    embedding = Vector{Float32}(undef, 384)
    target_dim = 384
    
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
        embedding[i] = normalized
    end
    
    # Ensure non-zero norm (prevent NaN in similarity)
    norm_val = norm(embedding)
    if norm_val < eps(Float32)
        embedding[1] = 1.0f0
        norm_val = 1.0f0
    end
    
    # L2 normalize
    embedding ./= norm_val
    
    return embedding
end

"""
    cosine_similarity - Compute cosine similarity between embeddings
"""
function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    norm_a = norm(a)
    norm_b = norm(b)
    
    denominator = (norm_a * norm_b)
    if denominator < eps(Float32)
        denominator = eps(Float32)
    end
    
    similarity = dot(a, b) / denominator
    return clamp(similarity, -1.0f0, 1.0f0)
end

# ============================================================================
# QDRANT API FUNCTIONS
# ============================================================================

"""
    _get_qdrant_url - Build Qdrant API URL
"""
function _get_qdrant_url(config::VectorStoreConfig, endpoint::String)::String
    return "http://$(config.qdrant_host):$(config.qdrant_port)$endpoint"
end

"""
    is_qdrant_available - Check if Qdrant is running and accessible
"""
function is_qdrant_available(memory::SemanticMemory)::Bool
    try
        url = _get_qdrant_url(memory.config, "/collections")
        response = HTTP.get(url; timeout = 5)
        memory.is_connected = response.status == 200
        return memory.is_connected
    catch e
        memory.is_connected = false
        @warn "Qdrant not available: $e"
        return false
    end
end

"""
    create_collection - Create a Qdrant collection
"""
function _create_collection(config::VectorStoreConfig, collection_name::String)::Bool
    url = _get_qdrant_url(config, "/collections/$collection_name")
    
    # Check if already exists
    try
        HTTP.get(url; timeout = 5)
        @info "Collection '$collection_name' already exists"
        return true
    catch
        # Collection doesn't exist, create it
    end
    
    body = JSON.json(Dict(
        "vectors" => Dict(
            "size" => config.embedding_dim,
            "distance" => config.distance_metric
        )
    ))
    
    try
        response = HTTP.put(url, 
            ["Content-Type" => "application/json"],
            body;
            timeout = 30
        )
        return response.status in [200, 201]
    catch e
        @error "Failed to create collection: $e"
        return false
    end
end

"""
    list_collections - List all collections in Qdrant
"""
function list_collections(memory::SemanticMemory)::Vector{String}
    if !is_qdrant_available(memory)
        # Return cached collections
        return collect(keys(memory.cache_by_collection))
    end
    
    url = _get_qdrant_url(memory.config, "/collections")
    
    try
        response = HTTP.get(url; timeout = 10)
        if response.status == 200
            data = JSON.parse(String(response.body))
            return [col["name"] for col in data["result"]["collections"]]
        end
    catch e
        @error "Failed to list collections: $e"
    end
    
    return String[]
end

# ============================================================================
# CORE MEMORY OPERATIONS
# ============================================================================

"""
    create_memory - Initialize a semantic memory with Qdrant collection
"""
function create_memory(
    collection_name::String,
    embedding_dim::Int = 384;
    qdrant_host::String = "localhost",
    qdrant_port::Int = 6333
)::SemanticMemory
    
    config = VectorStoreConfig(
        qdrant_host = qdrant_host,
        qdrant_port = qdrant_port,
        embedding_dim = embedding_dim
    )
    
    memory = SemanticMemory(config)
    
    # Try to connect to Qdrant
    if is_qdrant_available(memory)
        success = _create_collection(config, collection_name)
        if success
            @info "Created/verified Qdrant collection: $collection_name"
        else
            @warn "Failed to create Qdrant collection, using local cache"
        end
    else
        @info "Qdrant unavailable, using in-memory cache"
    end
    
    return memory
end

"""
    store_memory - Store a memory with embedding in Qdrant
"""
function store_memory(
    memory::SemanticMemory,
    collection::String,
    content::String,
    metadata::Dict{String, Any} = Dict{String, Any}()
)::Union{UUID, Nothing}
    
    # Generate embedding
    embedding = generate_embedding(content, memory)
    
    # Create memory entry
    entry = MemoryEntry(collection, content, embedding; metadata = metadata)
    
    # Try to store in Qdrant
    if memory.is_connected
        success = _store_in_qdrant(memory, collection, entry)
        if success
            memory.total_stored += 1
            return entry.id
        end
    end
    
    # Fallback: store in local cache
    return _store_locally(memory, entry)
end

"""
    _store_in_qdrant - Store a point in Qdrant
"""
function _store_in_qdrant(memory::SemanticMemory, collection::String, entry::MemoryEntry)::Bool
    url = _get_qdrant_url(memory.config, "/collections/$collection/points")
    
    # Convert UUID to string for JSON
    point_id = string(entry.id)
    
    body = JSON.json(Dict(
        "points" => [
            Dict(
                "id" => point_id,
                "vector" => Vector(entry.embedding),
                "payload" => merge(entry.metadata, Dict(
                    "content" => entry.content,
                    "collection" => entry.collection,
                    "created_at" => string(entry.created_at)
                ))
            )
        ]
    ))
    
    try
        response = HTTP.put(url,
            ["Content-Type" => "application/json"],
            body;
            timeout = 30
        )
        return response.status in [200, 201]
    catch e
        @warn "Failed to store in Qdrant: $e"
        return false
    end
end

"""
    _store_locally - Store in local cache when Qdrant unavailable
"""
function _store_locally(memory::SemanticMemory, entry::MemoryEntry)::UUID
    idx = length(memory.local_cache) + 1
    push!(memory.local_cache, entry)
    
    # Update collection index
    if !haskey(memory.cache_by_collection, entry.collection)
        memory.cache_by_collection[entry.collection] = Int[]
    end
    push!(memory.cache_by_collection[entry.collection], idx)
    
    memory.total_stored += 1
    return entry.id
end

"""
    recall_similar - Search for similar memories using semantic similarity
"""
function recall_similar(
    memory::SemanticMemory,
    collection::String,
    query::String;
    top_k::Int = 5,
    min_similarity::Float32 = 0.0f0
)::Vector{Tuple{MemoryEntry, Float32}}
    
    memory.total_recalled += 1
    
    # Generate query embedding
    query_embedding = generate_embedding(query, memory)
    
    # Try Qdrant first
    if memory.is_connected
        results = _search_qdrant(memory, collection, query_embedding, top_k)
        if !isempty(results)
            return results
        end
    end
    
    # Fallback: local search
    return _search_locally(memory, collection, query_embedding, top_k, min_similarity)
end

"""
    _search_qdrant - Search in Qdrant
"""
function _search_qdrant(
    memory::SemanticMemory,
    collection::String,
    query_embedding::Vector{Float32},
    top_k::Int
)::Vector{Tuple{MemoryEntry, Float32}}
    
    url = _get_qdrant_url(memory.config, "/collections/$collection/points/search")
    
    body = JSON.json(Dict(
        "vector" => Vector(query_embedding),
        "top" => top_k,
        "score_threshold" => 0.0
    ))
    
    try
        response = HTTP.post(url,
            ["Content-Type" => "application/json"],
            body;
            timeout = 30
        )
        
        if response.status == 200
            data = JSON.parse(String(response.body))
            results = Tuple{MemoryEntry, Float32}[]
            
            for point in data["result"]
                entry = MemoryEntry(
                    collection,
                    get(point["payload"], "content", ""),
                    Vector{Float32}(query_embedding);  # We don't have the stored vector
                    metadata = point["payload"]
                )
                entry.id = UUID(point["id"])
                score = Float32(point["score"])
                push!(results, (entry, score))
            end
            
            return results
        end
    catch e
        @warn "Qdrant search failed: $e"
    end
    
    return Tuple{MemoryEntry, Float32}[]
end

"""
    _search_locally - Search in local cache
"""
function _search_locally(
    memory::SemanticMemory,
    collection::String,
    query_embedding::Vector{Float32},
    top_k::Int,
    min_similarity::Float32
)::Vector{Tuple{MemoryEntry, Float32}}
    
    # Get candidates from collection
    indices = get(memory.cache_by_collection, collection, Int[])
    
    if isempty(indices)
        return Tuple{MemoryEntry, Float32}[]
    end
    
    # Compute similarities
    similarities = Vector{Tuple{Int, Float32}}()
    for idx in indices
        entry = memory.local_cache[idx]
        sim = cosine_similarity(query_embedding, entry.embedding)
        if sim >= min_similarity
            push!(similarities, (idx, sim))
        end
    end
    
    # Sort by similarity and take top k
    sort!(similarities, by = x -> x[2], rev = true)
    
    results = Tuple{MemoryEntry, Float32}[]
    for (idx, sim) in first(similarities, min(top_k, length(similarities)))
        entry = memory.local_cache[idx]
        entry.accessed_at = now()
        entry.access_count += 1
        push!(results, (entry, sim))
    end
    
    return results
end

"""
    delete_memory - Delete a memory by ID
"""
function delete_memory(
    memory::SemanticMemory,
    collection::String,
    memory_id::UUID
)::Bool
    
    if memory.is_connected
        return _delete_from_qdrant(memory, collection, memory_id)
    else
        return _delete_locally(memory, collection, memory_id)
    end
end

"""
    _delete_from_qdrant - Delete from Qdrant
"""
function _delete_from_qdrant(memory::SemanticMemory, collection::String, memory_id::UUID)::Bool
    url = _get_qdrant_url(memory.config, "/collections/$collection/points/delete")
    
    body = JSON.json(Dict(
        "points" => [string(memory_id)]
    ))
    
    try
        response = HTTP.post(url,
            ["Content-Type" => "application/json"],
            body;
            timeout = 30
        )
        return response.status in [200, 201]
    catch e
        @warn "Failed to delete from Qdrant: $e"
        return false
    end
end

"""
    _delete_locally - Delete from local cache
"""
function _delete_locally(memory::SemanticMemory, collection::String, memory_id::UUID)::Bool
    indices = get(memory.cache_by_collection, collection, Int[])
    
    for (i, idx) in enumerate(indices)
        if memory.local_cache[idx].id == memory_id
            # Remove from cache
            deleteat!(memory.local_cache, idx)
            
            # Update indices (decrement those after the deleted one)
            for j in eachindex(indices)
                if indices[j] > idx
                    indices[j] -= 1
                end
            end
            
            # Remove from collection index
            deleteat!(indices, i)
            memory.cache_by_collection[collection] = indices
            
            return true
        end
    end
    
    return false
end

# ============================================================================
# KERNEL INTEGRATION - Global Memory Instance
# ============================================================================

# Global semantic memory instance for kernel integration
const _kernel_memory = Ref{Union{SemanticMemory, Nothing}}(nothing)
const _memory_initialized = Ref{Bool}(false)

"""
    init_kernel_memory(; qdrant_host="localhost", qdrant_port=6333, 
                      collection_name="kernel_interactions", embedding_dim=384) -> SemanticMemory

Initialize the global kernel memory instance. This should be called once during kernel startup.
"""
function init_kernel_memory(;
    qdrant_host::String="localhost",
    qdrant_port::Int=6333,
    collection_name::String="kernel_interactions",
    embedding_dim::Int=384,
    use_ollama::Bool=false,
    ollama_host::String="localhost",
    ollama_port::Int=11434
)::SemanticMemory
    
    config = VectorStoreConfig(
        qdrant_host=qdrant_host,
        qdrant_port=qdrant_port,
        embedding_dim=embedding_dim,
        use_ollama=use_ollama,
        ollama_host=ollama_host,
        ollama_port=ollama_port
    )
    
    memory = create_memory(collection_name, embedding_dim; 
        qdrant_host=qdrant_host, 
        qdrant_port=qdrant_port
    )
    
    # Override with custom config
    memory.config = config
    
    # Check connection
    is_qdrant_available(memory)
    
    _kernel_memory[] = memory
    _memory_initialized[] = true
    
    @info "Kernel memory initialized" 
          collection=collection_name 
          connected=memory.is_connected
    
    return memory
end

"""
    get_kernel_memory() -> Union{SemanticMemory, Nothing}

Get the global kernel memory instance.
"""
function get_kernel_memory()::Union{SemanticMemory, Nothing}
    return _kernel_memory[]
end

"""
    set_kernel_memory(memory::SemanticMemory) -> Nothing

Set the global kernel memory instance.
"""
function set_kernel_memory(memory::SemanticMemory)::Nothing
    _kernel_memory[] = memory
    _memory_initialized[] = true
    return nothing
end

"""
    is_memory_available() -> Bool

Check if kernel memory is initialized and available.
"""
function is_memory_available()::Bool
    return _memory_initialized[] && _kernel_memory[] !== nothing
end

# ============================================================================
# KERNEL INTEGRATION HOOKS
# ============================================================================

"""
    store_interaction(user_message::String, assistant_response::String; 
                      metadata::Dict=Dict()) -> Union{UUID, Nothing}

Store a user-assistant interaction pair in semantic memory.
This enables the kernel to remember past conversations.

# Arguments
- `user_message`: The user's input message
- `assistant_response`: The assistant's response
- `metadata`: Optional metadata (e.g., session_id, user_id, topic)

# Returns
- UUID of stored memory, or nothing if storage failed
"""
function store_interaction(
    user_message::String, 
    assistant_response::String;
    metadata::Dict{String, Any}=Dict{String, Any}()
)::Union{UUID, Nothing}
    
    memory = get_kernel_memory()
    if memory === nothing
        @warn "Kernel memory not initialized - cannot store interaction"
        return nothing
    end
    
    # Combine user message and assistant response for storage
    # This creates a complete conversation context
    combined_content = "User: $user_message\nAssistant: $assistant_response"
    
    # Add metadata
    full_metadata = merge(Dict{String, Any}(
        "user_message" => user_message,
        "assistant_response" => assistant_response,
        "timestamp" => string(now()),
        "type" => "interaction"
    ), metadata)
    
    # Store in "interactions" collection
    collection = get(metadata, "collection", "interactions")
    
    try
        memory_id = store_memory(memory, collection, combined_content; metadata=full_metadata)
        @debug "Stored interaction" memory_id=memory_id collection=collection
        return memory_id
    catch e
        @error "Failed to store interaction" exception=e
        return nothing
    end
end

"""
    recall_relevant(query::String; k::Int=5, collection::String="interactions") -> Vector{Tuple{MemoryEntry, Float32}}

Retrieve relevant past interactions based on semantic similarity.

# Arguments
- `query`: The search query
- `k`: Number of results to retrieve (default: 5)
- `collection`: Collection to search in (default: "interactions")

# Returns
- Vector of (MemoryEntry, similarity_score) tuples
"""
function recall_relevant(
    query::String; 
    k::Int=5,
    collection::String="interactions"
)::Vector{Tuple{MemoryEntry, Float32}}
    
    memory = get_kernel_memory()
    if memory === nothing
        @warn "Kernel memory not initialized - cannot recall"
        return Tuple{MemoryEntry, Float32}[]
    end
    
    try
        results = recall_similar(memory, collection, query; top_k=k)
        @debug "Recalled interactions" query=query num_results=length(results)
        return results
    catch e
        @error "Failed to recall relevant interactions" exception=e
        return Tuple{MemoryEntry, Float32}[]
    end
end

"""
    get_memory_context(query::String; k::Int=5, collection::String="interactions") -> String

Get formatted memory context for LLM prompts.
This creates a context string from relevant past interactions.

# Arguments
- `query`: The current user query
- `k`: Number of past interactions to retrieve (default: 5)
- `collection`: Collection to search in (default: "interactions")

# Returns
- Formatted string with relevant context from past interactions
"""
function get_memory_context(
    query::String; 
    k::Int=5,
    collection::String="interactions"
)::String
    
    results = recall_relevant(query; k=k, collection=collection)
    
    if isempty(results)
        return "No relevant past interactions found."
    end
    
    # Format as conversation history
    context_parts = String[]
    
    for (entry, score) in results
        # Extract user and assistant messages from stored content
        content = entry.content
        
        # Parse the combined content
        user_msg = ""
        assistant_msg = ""
        
        if occursin("User: ", content) && occursin("\nAssistant: ", content)
            user_part = split(content, "\nAssistant: ")[1]
            user_msg = replace(user_part, "User: " => "")
            assistant_msg = split(content, "\nAssistant: ")[2]
        else
            # Fallback: use full content
            user_msg = content
            assistant_msg = ""
        end
        
        # Format this memory
        timestamp = occursin(r"\d{4}-\d{2}-\d{2}", entry.metadata["timestamp"]) ? 
            entry.metadata["timestamp"] : string(entry.created_at)
        
        memory_str = """
        Previous conversation:
        - Time: $timestamp
        - Relevance: $(round(score, digits=2))
        - User said: "$user_msg"
        - Assistant responded: "$assistant_msg"
        """
        
        push!(context_parts, memory_str)
    end
    
    return join(context_parts, "\n\n")
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_memory_stats - Get memory statistics
"""
function get_memory_stats(memory::SemanticMemory)::Dict{String, Any}
    return Dict(
        "is_connected" => memory.is_connected,
        "total_stored" => memory.total_stored,
        "total_recalled" => memory.total_recalled,
        "cache_size" => length(memory.local_cache),
        "collections" => collect(keys(memory.cache_by_collection)),
        "config" => Dict(
            "qdrant_host" => memory.config.qdrant_host,
            "qdrant_port" => memory.config.qdrant_port,
            "embedding_dim" => memory.config.embedding_dim,
            "use_ollama" => memory.config.use_ollama
        )
    )
end

end # module VectorStore
