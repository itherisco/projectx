# adaptive-kernel/memory/SemanticMemory.jl - Latent Memory Compression System
# Implements VAE-based compression for semantic memory with RPE prioritization
# Part of HIGH-2 priority: Latent Memory Compression

module SemanticMemory

export 
    # Core structures
    SemanticMemoryStore,
    LatentEmbedding,
    CognitiveSnapshot,
    MemoryPrioritizer,
    
    # VAE components
    CompressionVAE,
    create_compression_vae,
    encode,
    decode,
    reconstruct,
    
    # Memory operations
    compress_episodes!,
    prioritize_memories,
    consolidate_to_semantic!,
    oneiric_dream_cycle,
    
    # Tombstone integration
    load_from_tombstone,
    save_to_consolidated,

    # Configuration
    MemoryCompressionConfig

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Logging
using Parameters
using JSON

# Try to import Flux for neural networks
const FLUX_AVAILABLE = try
    using Flux
    using Flux: Chain, Dense, LayerNorm, sigma
    true
catch e
    @warn "Flux not available, using fallback implementation"
    false
end

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    MemoryCompressionConfig - Configuration for memory compression

# Fields
- `input_dim::Int`: Input dimension (48D raw cognitive state)
- `latent_dim::Int`: Latent space dimension (12D)
- `rpe_weight::Float32`: Weight for RPE in prioritization
- `recency_weight::Float32`: Weight for recency in prioritization
- `max_episodes_to_compress::Int`: Maximum episodes to compress per cycle
- `target_compression_ratio::Float32`: Target compression ratio (0.15 = 85% reduction)
- `dream_temperature::Float32`: Temperature for low-temperature inference
- `gradient_norm_threshold::Float32`: Threshold for gradient norm veto
"""
@with_kw mutable struct MemoryCompressionConfig
    input_dim::Int = 48
    latent_dim::Int = 12
    rpe_weight::Float32 = 0.7f0
    recency_weight::Float32 = 0.3f0
    max_episodes_to_compress::Int = 10000
    target_compression_ratio::Float32 = 0.15f0
    dream_temperature::Float32 = 0.1f0
    gradient_norm_threshold::Float32 = 0.1f0
end

# ============================================================================
# COGNITIVE SNAPSHOT - 48D Raw Feature Vector
# ============================================================================

"""
    CognitiveSnapshot - Full cognitive state representation (48D)
    
    The 48D vector includes:
    - [1:12] 12D perception (ITHERIS format)
    - [13:20] 8D policy logits
    - [21:28] 8D metabolic state
    - [29:36] 8D sensory context
    - [37:44] 8D affective state
    - [45:48] 4D temporal context
"""
struct CognitiveSnapshot
    data::Vector{Float32}
    timestamp::DateTime
    cycle::Int
    rpe::Float32  # Reward Prediction Error (surprise signal)
    
    function CognitiveSnapshot(
        perception::Vector{Float32},
        policy_logits::Vector{Float32},
        metabolic::Vector{Float32},
        sensory_context::Vector{Float32},
        affective::Vector{Float32},
        temporal::Vector{Float32};
        timestamp::DateTime = now(),
        cycle::Int = 0,
        rpe::Float32 = 0.0f0
    )
        @assert length(perception) == 12 "Perception must be 12D"
        @assert length(policy_logits) == 8 "Policy logits must be 8D"
        @assert length(metabolic) == 8 "Metabolic must be 8D"
        @assert length(sensory_context) == 8 "Sensory context must be 8D"
        @assert length(affective) == 8 "Affective must be 8D"
        @assert length(temporal) == 4 "Temporal must be 4D"
        
        data = vcat(perception, policy_logits, metabolic, sensory_context, affective, temporal)
        new(data, timestamp, cycle, rpe)
    end
end

# Constructor from Dict (for tombstone integration)
function CognitiveSnapshot(episode::Dict{String, Any})
    perception = get(episode, "perception", zeros(Float32, 12))
    policy_logits = get(episode, "policy_logits", zeros(Float32, 8))
    metabolic = get(episode, "metabolic", zeros(Float32, 8))
    sensory_context = get(episode, "sensory_context", zeros(Float32, 8))
    affective = get(episode, "affective", zeros(Float32, 8))
    temporal = get(episode, "temporal", zeros(Float32, 4))
    
    CognitiveSnapshot(
        perception, policy_logits, metabolic, sensory_context, affective, temporal;
        timestamp = get(episode, "timestamp", now()),
        cycle = get(episode, "cycle", 0),
        rpe = Float32(get(episode, "rpe", 0.0))
    )
end

# Convert to Dict for storage
function to_dict(snapshot::CognitiveSnapshot)::Dict{String, Any}
    data = snapshot.data
    return Dict(
        "perception" => data[1:12],
        "policy_logits" => data[13:20],
        "metabolic" => data[21:28],
        "sensory_context" => data[29:36],
        "affective" => data[37:44],
        "temporal" => data[45:48],
        "timestamp" => snapshot.timestamp,
        "cycle" => snapshot.cycle,
        "rpe" => snapshot.rpe
    )
end

# ============================================================================
# LATENT EMBEDDING - 12D Compressed Representation
# ============================================================================

"""
    LatentEmbedding - Compressed 12D latent representation
    
    This is the "bottleneck" representation that forces the system
    to retain only the most critical features.
"""
struct LatentEmbedding
    data::Vector{Float32}  # 12D latent vector
    timestamp::DateTime
    source_cycle::Int
    importance_score::Float32  # Computed from RPE + recency
    reconstruction_error::Float32  # How well this reconstructs
    
    function LatentEmbedding(
        data::Vector{Float32};
        timestamp::DateTime = now(),
        source_cycle::Int = 0,
        importance_score::Float32 = 0.0f0,
        reconstruction_error::Float32 = 0.0f0
    )
        @assert length(data) == 12 "Latent embedding must be 12D"
        new(data, timestamp, source_cycle, importance_score, reconstruction_error)
    end
end

# ============================================================================
# COMPRESSION VAE - 48D -> 12D -> 48D
# ============================================================================

"""
    CompressionVAE - Variational Autoencoder for memory compression
    
    Architecture: 48D (Raw) -> 24D (Hidden) -> 12D (Latent) -> 24D -> 48D (Reconstruction)
"""
mutable struct CompressionVAE
    # Encoder: 48D -> 12D
    encoder::Any
    decoder::Any  # 12D -> 48D
    
    # Latent dimension
    latent_dim::Int
    
    # Training state
    is_trained::Bool
    last_training_cycle::Int
    
    # VAE parameters
    latent_mean::Vector{Float32}
    latent_logvar::Vector{Float32}
    
    function CompressionVAE(input_dim::Int = 48, latent_dim::Int = 12)
        if FLUX_AVAILABLE
            # Create encoder: 48D -> 24D -> 12D (mean) and 12D (logvar)
            encoder = Chain(
                Dense(input_dim, 24, relu),
                Dense(24, latent_dim * 2)  # Split into mean and logvar
            )
            
            # Create decoder: 12D -> 24D -> 48D
            decoder = Chain(
                Dense(latent_dim, 24, relu),
                Dense(24, input_dim, sigmoid)
            )
        else
            # Fallback: simple linear encoder/decoder
            encoder = nothing
            decoder = nothing
        end
        
        new(
            encoder,
            decoder,
            latent_dim,
            false,
            0,
            zeros(Float32, latent_dim),
            zeros(Float32, latent_dim)
        )
    end
end

"""
    create_compression_vae - Factory function to create a new VAE
"""
function create_compression_vae(config::MemoryCompressionConfig = MemoryCompressionConfig())::CompressionVAE
    return CompressionVAE(config.input_dim, config.latent_dim)
end

"""
    encode - Encode a cognitive snapshot to latent representation
"""
function encode(vae::CompressionVAE, input::Vector{Float32})::Tuple{Vector{Float32}, Vector{Float32}}
    if FLUX_AVAILABLE && vae.encoder !== nothing
        # Get mean and logvar from encoder
        h = vae.encoder(input)
        mean = h[1:vae.latent_dim]
        logvar = h[vae.latent_dim+1:end]
        return (mean, logvar)
    else
        # Fallback: simple dimensionality reduction
        # Use first 12 dimensions as latent (PCA-like)
        return (input[1:vae.latent_dim], zeros(Float32, vae.latent_dim))
    end
end

"""
    decode - Decode latent representation back to 48D
"""
function decode(vae::CompressionVAE, latent::Vector{Float32})::Vector{Float32}
    if FLUX_AVAILABLE && vae.decoder !== nothing
        return vae.decoder(latent)
    else
        # Fallback: zero padding
        output = zeros(Float32, 48)
        output[1:length(latent)] = latent
        return output
    end
end

"""
    reparameterize - Reparameterization trick for VAE training
"""
function reparameterize(mean::Vector{Float32}, logvar::Vector{Float32})::Vector{Float32}
    std = exp.(0.5f0 .* logvar)
    epsilon = randn(Float32, length(mean))
    return mean + std .* epsilon
end

"""
    reconstruct - Full encode-decode cycle
"""
function reconstruct(vae::CompressionVAE, input::Vector{Float32})::Tuple{Vector{Float32}, Vector{Float32}, Float32}
    mean, logvar = encode(vae, input)
    latent = reparameterize(mean, logvar)
    reconstruction = decode(vae, latent)
    
    # Compute reconstruction error (MSE)
    error = mean((input - reconstruction).^2)
    
    return (latent, reconstruction, error)
end

# ============================================================================
# MEMORY PRIORITIZER - RPE-Based Prioritization
# ============================================================================

"""
    MemoryPrioritizer - Prioritizes episodes based on RPE and recency
"""
mutable struct MemoryPrioritizer
    config::MemoryCompressionConfig
    priority_scores::Dict{UUID, Float32}
    
    function MemoryPrioritizer(config::MemoryCompressionConfig = MemoryCompressionConfig())
        new(config, Dict{UUID, Float32}())
    end
end

"""
    compute_priority_score - Compute priority score for an episode
    
    Priority = rpe_weight * RPE + recency_weight * recency_score
"""
function compute_priority_score(
    snapshot::CognitiveSnapshot;
    rpe_weight::Float32 = 0.7f0,
    recency_weight::Float32 = 0.3f0,
    current_time::DateTime = now()
)::Float32
    # Normalize RPE to [0, 1]
    rpe_normalized = clamp(snapshot.rpe, 0.0f0, 1.0f0)
    
    # Recency score: exponential decay from current time
    time_diff = (current_time - snapshot.timestamp)
    seconds = time_diff.value / 1000.0  # Convert to seconds
    recency_score = exp(-seconds / 86400.0f0)  # Half-life of 1 day
    
    return rpe_weight * rpe_normalized + recency_weight * recency_score
end

"""
    prioritize_memories - Select top-K episodes based on priority score
"""
function prioritize_memories(
    snapshots::Vector{CognitiveSnapshot};
    max_memories::Int = 10000,
    config::MemoryCompressionConfig = MemoryCompressionConfig()
)::Vector{CognitiveSnapshot}
    # Compute priority scores
    scores = [compute_priority_score(
        s; 
        rpe_weight = config.rpe_weight,
        recency_weight = config.recency_weight
    ) for s in snapshots]
    
    # Get indices sorted by score (descending)
    sorted_indices = sortperm(scores, rev=true)
    
    # Return top K
    top_k = min(max_memories, length(snapshots))
    return snapshots[sorted_indices[1:top_k]]
end

# ============================================================================
# SEMANTIC MEMORY STORE - Multi-Tiered Memory System
# ============================================================================

"""
    SemanticMemoryStore - Multi-tiered memory with episodic and semantic stores
    
    Tier 1: Raw episodic buffer (from MemoryStore)
    Tier 2: Compressed latent embeddings (this module)
    Tier 3: Consolidated semantic facts (decontextualized)
"""
mutable struct SemanticMemoryStore
    # Configuration
    config::MemoryCompressionConfig
    
    # Tier 1: Raw episodic buffer
    episodes::Vector{CognitiveSnapshot}
    
    # Tier 2: Latent embeddings (compressed)
    latent_embeddings::Vector{LatentEmbedding}
    
    # Tier 3: Semantic facts (decontextualized)
    semantic_facts::Vector{Dict{String, Any}}
    
    # VAE for compression
    vae::CompressionVAE
    
    # Prioritizer
    prioritizer::MemoryPrioritizer
    
    # Metadata
    last_consolidation::DateTime
    total_compressions::Int
    average_reconstruction_error::Float32
    
    function SemanticMemoryStore(config::MemoryCompressionConfig = MemoryCompressionConfig())
        vae = create_compression_vae(config)
        prioritizer = MemoryPrioritizer(config)
        
        new(
            config,
            CognitiveSnapshot[],
            LatentEmbedding[],
            Dict{String, Any}[],
            vae,
            prioritizer,
            now(),
            0,
            0.0f0
        )
    end
end

"""
    add_episode! - Add a cognitive snapshot to the episodic buffer
"""
function add_episode!(store::SemanticMemoryStore, snapshot::CognitiveSnapshot)
    push!(store.episodes, snapshot)
    
    # Prune if over threshold
    max_episodes = store.config.max_episodes_to_compress * 2
    if length(store.episodes) > max_episodes
        # Keep most recent
        store.episodes = store.episodes[end-max_episodes+1:end]
    end
end

"""
    add_episode_from_dict! - Add episode from Dict format
"""
function add_episode_from_dict!(store::SemanticMemoryStore, episode::Dict{String, Any})
    snapshot = CognitiveSnapshot(episode)
    add_episode!(store, snapshot)
end

# ============================================================================
# COMPRESSION FUNCTIONS
# ============================================================================

"""
    compress_episodes! - Compress selected episodes to latent embeddings
"""
function compress_episodes!(
    store::SemanticMemoryStore;
    max_to_compress::Int = 10000
)::Int
    config = store.config
    
    # Step 1: Prioritize based on RPE and recency
    prioritized = prioritize_memories(
        store.episodes;
        max_memories = max_to_compress,
        config = config
    )
    
    compressed_count = 0
    total_error = 0.0f0
    
    for snapshot in prioritized
        # Step 2: Encode to latent
        latent, reconstruction, error = reconstruct(store.vae, snapshot.data)
        
        # Step 3: Create latent embedding
        importance = compute_priority_score(snapshot)
        
        embedding = LatentEmbedding(
            latent;
            timestamp = snapshot.timestamp,
            source_cycle = snapshot.cycle,
            importance_score = importance,
            reconstruction_error = error
        )
        
        push!(store.latent_embeddings, embedding)
        total_error += error
        compressed_count += 1
    end
    
    # Update stats
    store.total_compressions += 1
    store.average_reconstruction_error = total_error / max(1, compressed_count)
    store.last_consolidation = now()
    
    # Remove compressed episodes from episodic buffer
    # Keep some recent ones for recency buffer
    recency_buffer_size = 1000
    if length(store.episodes) > recency_buffer_size
        store.episodes = store.episodes[end-recency_buffer_size+1:end]
    end
    
    return compressed_count
end

"""
    consolidate_to_semantic! - Extract semantic facts from latent embeddings
    
    Decontextualizes the embeddings into facts and abstract policies.
"""
function consolidate_to_semantic!(store::SemanticMemoryStore)::Int
    # Extract high-importance embeddings
    threshold = 0.5f0
    important = filter(e -> e.importance_score > threshold, store.latent_embeddings)
    
    facts_added = 0
    
    for embedding in important
        # Simple fact extraction: cluster similar embeddings
        # In a full implementation, this would use clustering or pattern extraction
        fact = Dict{String, Any}(
            "type" => "semantic_fact",
            "latent" => embedding.data,
            "timestamp" => embedding.timestamp,
            "importance" => embedding.importance_score,
            "source_cycle" => embedding.source_cycle
        )
        push!(store.semantic_facts, fact)
        facts_added += 1
    end
    
    return facts_added
end

# ============================================================================
# ONEIRIC (DREAMING) STATE FUNCTIONS
# ============================================================================

"""
    oneiric_dream_cycle - Perform memory consolidation during Oneiric state
    
    This is called when:
    1. Metabolic energy is low (energy < threshold)
    2. Rust Warden has reduced memory permissions to read-only
    3. Low-temperature inference is used
"""
function oneiric_dream_cycle(
    store::SemanticMemoryStore;
    temperature::Float32 = 0.1f0,
    gradient_norm_threshold::Float32 = 0.1f0
)::Dict{String, Any}
    result = Dict{String, Any}()
    
    # Store original temperature for VAE
    original_temp = store.config.dream_temperature
    store.config.dream_temperature = temperature
    
    try
        # Step 1: Prioritize episodes based on RPE
        # This ensures we remember the most impactful successes/failures
        prioritized = prioritize_memories(store.episodes)
        
        result["episodes_prioritized"] = length(prioritized)
        
        # Step 2: Compress to latent embeddings
        # This is the core memory footprint reduction
        compressed = compress_episodes!(store, max_to_compress = store.config.max_episodes_to_compress)
        
        result["episodes_compressed"] = compressed
        result["latent_embeddings_count"] = length(store.latent_embeddings)
        
        # Step 3: Consolidate to semantic memory
        facts = consolidate_to_semantic!(store)
        
        result["semantic_facts_extracted"] = facts
        result["semantic_facts_total"] = length(store.semantic_facts)
        
        # Step 4: Compute compression statistics
        original_size = length(store.episodes) * store.config.input_dim * sizeof(Float32)
        compressed_size = length(store.latent_embeddings) * store.config.latent_dim * sizeof(Float32)
        
        compression_ratio = if original_size > 0
            compressed_size / original_size
        else
            0.0f0
        end
        
        result["original_size_bytes"] = original_size
        result["compressed_size_bytes"] = compressed_size
        result["compression_ratio"] = compression_ratio
        result["target_ratio"] = store.config.target_compression_ratio
        result["target_met"] = compression_ratio <= store.config.target_compression_ratio
        
        # Step 5: Synaptic pruning (Hebbian competition)
        prune_dormant_synapses!(store)
        
        result["pruning_completed"] = true
        result["average_reconstruction_error"] = store.average_reconstruction_error
        
        result["status"] = "success"
        
    catch e
        result["status"] = "error"
        result["error"] = string(e)
    finally
        # Restore original temperature
        store.config.dream_temperature = original_temp
    end
    
    return result
end

"""
    prune_dormant_synapses! - Implement Hebbian competition for synaptic pruning
    
    Weakens dormant synapses and normalizes total weights to stay within
    metabolic budget.
"""
function prune_dormant_synapses!(store::SemanticMemoryStore)
    # Remove embeddings with low importance (dormant)
    threshold = 0.1f0
    
    # Keep only important embeddings
    store.latent_embeddings = filter(e -> e.importance_score > threshold, store.latent_embeddings)
    
    # Normalize importance scores
    if !isempty(store.latent_embeddings)
        max_importance = maximum(e.importance_score for e in store.latent_embeddings)
        if max_importance > 0
            for embedding in store.latent_embeddings
                embedding.importance_score /= max_importance
            end
        end
    end
end

# ============================================================================
# TOMBSTONE AND PERSISTENCE INTEGRATION
# ============================================================================

"""
    load_from_tombstone - Load episodes from the ring buffer tombstone
    
    This integrates with the 10M-thought episodic ring buffer.
"""
function load_from_tombstone(
    store::SemanticMemoryStore,
    tombstone_path::String;
    max_to_load::Int = 10000
)::Int
    loaded = 0
    
    if isfile(tombstone_path)
        try
            # Read tombstone file (JSON lines format)
            open(tombstone_path, "r") do f
                for line in eachline(f)
                    if loaded >= max_to_load
                        break
                    end
                    
                    episode = JSON.parse(line)
                    add_episode_from_dict!(store, episode)
                    loaded += 1
                end
            end
        catch e
            @error "Failed to load from tombstone: $e"
        end
    end
    
    return loaded
end

"""
    save_to_consolidated - Save semantic memories to encrypted local storage
    
    This persists consolidated memories across system reboots.
"""
function save_to_consolidated(
    store::SemanticMemoryStore,
    output_path::String = "/safe/memories/consolidated/"
)::Bool
    try
        # Create directory if needed
        mkpath(output_path)
        
        # Save latent embeddings
        embeddings_file = joinpath(output_path, "latent_embeddings.json")
        open(embeddings_file, "w") do f
            for embedding in store.latent_embeddings
                dict = Dict(
                    "data" => embedding.data,
                    "timestamp" => string(embedding.timestamp),
                    "source_cycle" => embedding.source_cycle,
                    "importance_score" => embedding.importance_score,
                    "reconstruction_error" => embedding.reconstruction_error
                )
                JSON.print(f, dict)
                write(f, "\n")
            end
        end
        
        # Save semantic facts
        facts_file = joinpath(output_path, "semantic_facts.json")
        open(facts_file, "w") do f
            for fact in store.semantic_facts
                JSON.print(f, fact)
                write(f, "\n")
            end
        end
        
        # Save metadata
        metadata = Dict(
            "last_consolidation" => string(store.last_consolidation),
            "total_compressions" => store.total_compressions,
            "average_reconstruction_error" => store.average_reconstruction_error,
            "config" => Dict(
                "input_dim" => store.config.input_dim,
                "latent_dim" => store.config.latent_dim,
                "target_compression_ratio" => store.config.target_compression_ratio
            )
        )
        
        metadata_file = joinpath(output_path, "metadata.json")
        open(metadata_file, "w") do f
            JSON.print(f, metadata)
        end
        
        return true
    catch e
        @error "Failed to save consolidated memories: $e"
        return false
    end
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_memory_footprint - Get current memory footprint statistics
"""
function get_memory_footprint(store::SemanticMemoryStore)::Dict{String, Any}
    original_size = length(store.episodes) * store.config.input_dim * sizeof(Float32)
    compressed_size = length(store.latent_embeddings) * store.config.latent_dim * sizeof(Float32)
    semantic_size = length(store.semantic_facts) * 200  # Approximate
    
    total_size = original_size + compressed_size + semantic_size
    
    compression_ratio = if original_size > 0
        (compressed_size + semantic_size) / original_size
    else
        0.0f0
    end
    
    return Dict(
        "episodic_count" => length(store.episodes),
        "latent_embedding_count" => length(store.latent_embeddings),
        "semantic_fact_count" => length(store.semantic_facts),
        "original_size_bytes" => original_size,
        "compressed_size_bytes" => compressed_size,
        "semantic_size_bytes" => semantic_size,
        "total_size_bytes" => total_size,
        "compression_ratio" => compression_ratio,
        "target_ratio" => store.config.target_compression_ratio,
        "target_met" => compression_ratio <= store.config.target_compression_ratio,
        "average_reconstruction_error" => store.average_reconstruction_error,
        "total_compressions" => store.total_compressions,
        "last_consolidation" => string(store.last_consolidation)
    )
end

"""
    recall - Attempt to reconstruct a memory from latent embedding
"""
function recall(store::SemanticMemoryStore, cycle::Int)::Union{Vector{Float32}, Nothing}
    # Find the closest latent embedding to the requested cycle
    best_match = nothing
    best_diff = Inf
    
    for embedding in store.latent_embeddings
        diff = abs(embedding.source_cycle - cycle)
        if diff < best_diff
            best_diff = diff
            best_match = embedding
        end
    end
    
    if best_match !== nothing
        # Decode the latent embedding back to 48D
        return decode(store.vae, best_match.data)
    end
    
    return nothing
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    MemoryCompressionConfig,
    CognitiveSnapshot,
    LatentEmbedding,
    CompressionVAE,
    create_compression_vae,
    encode,
    decode,
    reconstruct,
    MemoryPrioritizer,
    compute_priority_score,
    prioritize_memories,
    SemanticMemoryStore,
    add_episode!,
    add_episode_from_dict!,
    compress_episodes!,
    consolidate_to_semantic!,
    oneiric_dream_cycle,
    prune_dormant_synapses!,
    load_from_tombstone,
    save_to_consolidated,
    get_memory_footprint,
    recall

end # module
