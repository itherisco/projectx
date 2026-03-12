module Memory

export 
    MemoryStore, 
    ingest_episode!, 
    compress_memory!, 
    failure_catalog, 
    get_adjustments, 
    decay_memory!,
    
    # New exports for semantic memory
    SemanticMemoryStore,
    LatentEmbedding,
    CognitiveSnapshot,
    oneiric_dream_cycle,
    get_memory_footprint,
    recall,
    load_from_tombstone,
    save_to_consolidated,
    
    # Integration
    MemorySystem,
    create_memory_system,
    run_oneiric_consolidation,
    get_combined_footprint,
    recall_from_memory

using Dates, JSON, Base.Threads

# Include semantic memory module
include("SemanticMemory.jl")
using .SemanticMemory

# ============================================================================
# CORE MEMORY STORE (TIER 1: EPISODIC)
# ============================================================================

"""
    MemoryStore - Raw episodic memory store (Tier 1)
    
    This is the foundational memory store that tracks episodes,
    failures, and capability statistics. It serves as the source
    for consolidation into semantic memory.
"""
mutable struct MemoryStore
    episodes::Vector{Dict{String,Any}}
    failures::Vector{Dict{String,Any}}
    capability_stats::Dict{String, Dict{String,Any}}  # success_count, fail_count, avg_error
    last_compaction::DateTime
    stats_lock::ReentrantLock  # Lock for thread-safe capability_stats mutations
    
    # NEW: RPE tracking for prioritization
    rpe_history::Vector{Float32}
    rpe_lock::ReentrantLock
    
    MemoryStore() = new(
        Dict{String,Any}[], 
        Dict{String,Any}[], 
        Dict{String, Dict{String,Any}}(), 
        now(), 
        ReentrantLock(),
        Float32[],
        ReentrantLock()
    )
end

"""
    ingest_episode! - Add a new episode to memory
"""
function ingest_episode!(ms::MemoryStore, episode::Dict{String,Any})
    push!(ms.episodes, episode)
    
    # Track RPE for memory prioritization
    rpe = Float32(get(episode, "prediction_error", get(episode, "rpe", 0.0)))
    if rpe != 0.0
        lock(ms.rpe_lock) do
            push!(ms.rpe_history, rpe)
            # Keep last 10000 RPE values
            if length(ms.rpe_history) > 10000
                ms.rpe_history = ms.rpe_history[end-9999:end]
            end
        end
    end
    
    # Thread-safe update of capability stats
    lock(ms.stats_lock) do
        aid = get(episode, "action_id", "unknown")
        stats = get(ms.capability_stats, aid, Dict("success" => 0, "fail" => 0, "sum_error" => 0.0, "count" => 0))
        if get(episode, "result", false)
            stats["success"] = stats["success"] + 1
        else
            stats["fail"] = stats["fail"] + 1
            push!(ms.failures, Dict("action" => aid, "cycle" => episode["cycle"], "context" => get(episode, "context", Dict())))
        end
        pe = Float64(get(episode, "prediction_error", 0.0))
        stats["sum_error"] = stats["sum_error"] + pe
        stats["count"] = stats["count"] + 1
        ms.capability_stats[aid] = stats
    end
end

function failure_catalog(ms::MemoryStore)
    return ms.failures
end

"""
compress_memory!(ms; window=10)
Compress repeated episodes into summaries, e.g., coalesce identical successive actions.
"""
function compress_memory!(ms::MemoryStore; window::Int=10)
    if length(ms.episodes) < window
        return
    end
    out = Dict{String,Any}[]
    i = 1
    while i <= length(ms.episodes)
        e = ms.episodes[i]
        j = i+1
        count = 1
        while j <= length(ms.episodes) && ms.episodes[j]["action_id"] == e["action_id"]
            count += 1
            j += 1
        end
        if count > 1
            push!(out, Dict("action_id" => e["action_id"], "runs" => count, "last_cycle" => ms.episodes[j-1]["cycle"]))
        else
            push!(out, e)
        end
        i = j
    end
    ms.episodes = out
    ms.last_compaction = now()
end

"""
get_adjustments(ms, capability_ids)
Return multipliers for planning based on observed statistics.
"""
function get_adjustments(ms::MemoryStore, capability_ids::Vector{String})
    # default multipliers
    cost_mul = 1.0f0
    reward_mul = 1.0f0
    unc_off = 0.0f0
    for id in capability_ids
        stats = get(ms.capability_stats, id, nothing)
        if stats !== nothing && stats["count"] > 0
            avg_err = stats["sum_error"]/stats["count"]
            # If high error, reduce expected reward and increase uncertainty
            if avg_err > 0.5
                reward_mul *= 0.8f0
                unc_off += 0.1f0
            elseif avg_err < 0.1
                reward_mul *= 1.05f0
                unc_off -= 0.02f0
            end
            # If many failures, increase cost multiplier
            if stats["fail"] > stats["success"]
                cost_mul *= 1.2f0
            end
        end
    end
    return Dict(:cost_multiplier => Float32(cost_mul), :reward_multiplier => Float32(reward_mul), :uncertainty_offset => Float32(unc_off))
end

"""
decay_memory!(ms; half_life_cycles=100)
Apply forgetting pressure by decaying counts.
"""
function decay_memory!(ms::MemoryStore; half_life_cycles::Int=100)
    # Thread-safe decay of capability_stats
    lock(ms.stats_lock) do
        for (k,v) in ms.capability_stats
            v["success"] = max(0, Int(floor(v["success"] * 0.995)))
            v["fail"] = max(0, Int(floor(v["fail"] * 0.995)))
            v["sum_error"] = v["sum_error"] * 0.995
            v["count"] = max(1, Int(floor(v["count"] * 0.995)))
            ms.capability_stats[k] = v
        end
    end
    
    # Decay RPE history
    lock(ms.rpe_lock) do
        if !isempty(ms.rpe_history)
            ms.rpe_history = ms.rpe_history .* 0.995f0
        end
    end
end

# ============================================================================
# INTEGRATION WITH SEMANTIC MEMORY (HIGH-2)
# ============================================================================

"""
    MemorySystem - Unified memory system integrating episodic and semantic stores
"""
mutable struct MemorySystem
    # Tier 1: Episodic memory
    episodic::MemoryStore
    
    # Tier 2: Semantic memory (latent embeddings)
    semantic::Any  # Will be SemanticMemoryStore if available
    
    # Configuration
    enable_compression::Bool
    enable_dream_consolidation::Bool
    
    # Warden integration
    gradient_norm_threshold::Float32
    last_gradient_norm::Float32
    
    function MemorySystem(;enable_compression::Bool = true, enable_dream_consolidation::Bool = true)
        new(
            MemoryStore(),
            nothing,
            enable_compression,
            enable_dream_consolidation,
            0.1f0,  # Default gradient norm threshold from spec
            0.0f0
        )
    end
end

"""
    create_memory_system - Factory function to create a unified memory system
"""
function create_memory_system(;config::Union{Dict{String, Any}, Nothing} = nothing)::MemorySystem
    system = MemorySystem()
    
    if config !== nothing
        system.enable_compression = get(config, "enable_compression", true)
        system.enable_dream_consolidation = get(config, "enable_dream_consolidation", true)
        system.gradient_norm_threshold = Float32(get(config, "gradient_norm_threshold", 0.1))
    end
    
    # Try to initialize semantic memory
    try
        include(joinpath(@__DIR__, "SemanticMemory.jl"))
        system.semantic = SemanticMemory.SemanticMemoryStore()
        @info "Semantic memory store initialized"
    catch e
        @warn "Failed to initialize semantic memory: $e"
    end
    
    return system
end

"""
    sync_to_semantic! - Sync episodes from episodic to semantic memory
"""
function sync_to_semantic!(system::MemorySystem)::Int
    if system.semantic === nothing
        return 0
    end
    
    synced = 0
    for episode in system.episodic.episodes
        try
            # Convert episode dict to CognitiveSnapshot format
            snapshot = Dict{String, Any}(
                "perception" => get(episode, "perception", zeros(Float32, 12)),
                "policy_logits" => get(episode, "policy_logits", zeros(Float32, 8)),
                "metabolic" => get(episode, "metabolic", zeros(Float32, 8)),
                "sensory_context" => get(episode, "sensory_context", zeros(Float32, 8)),
                "affective" => get(episode, "affective", zeros(Float32, 8)),
                "temporal" => get(episode, "temporal", zeros(Float32, 4)),
                "timestamp" => get(episode, "timestamp", now()),
                "cycle" => get(episode, "cycle", 0),
                "rpe" => get(episode, "prediction_error", get(episode, "rpe", 0.0))
            )
            SemanticMemory.add_episode_from_dict!(system.semantic, snapshot)
            synced += 1
        catch e
            @warn "Failed to sync episode to semantic memory: $e"
        end
    end
    
    return synced
end

"""
    run_oneiric_consolidation - Run memory consolidation during Oneiric (dream) state
    
    This is called when:
    1. Metabolic energy is low
    2. Rust Warden has reduced memory permissions to read-only
    3. Low-temperature inference is used
    
    Returns a result dict with compression statistics.
"""
function run_oneiric_consolidation(
    system::MemorySystem;
    temperature::Float32 = 0.1f0,
    force::Bool = false
)::Dict{String, Any}
    result = Dict{String, Any}()
    
    if system.semantic === nothing
        result["status"] = "error"
        result["error"] = "Semantic memory not initialized"
        return result
    end
    
    # Check if compression is enabled
    if !system.enable_compression && !force
        result["status"] = "skipped"
        result["reason"] = "compression disabled"
        return result
    end
    
    # First sync episodes to semantic store
    synced = sync_to_semantic!(system)
    result["episodes_synced"] = synced
    
    # Run the oneiric dream cycle
    try
        dream_result = SemanticMemory.oneiric_dream_cycle(
            system.semantic;
            temperature = temperature,
            gradient_norm_threshold = system.gradient_norm_threshold
        )
        
        # Check gradient norm (Warden oversight)
        gradient_norm = get(dream_result, "average_reconstruction_error", 0.0f0)
        system.last_gradient_norm = gradient_norm
        
        if gradient_norm > system.gradient_norm_threshold
            result["status"] = "vetoed"
            result["reason"] = "gradient norm exceeded threshold"
            result["gradient_norm"] = gradient_norm
            result["threshold"] = system.gradient_norm_threshold
            return result
        end
        
        # Merge results
        result["status"] = "success"
        result["compression"] = dream_result
        
        # Get footprint stats
        footprint = SemanticMemory.get_memory_footprint(system.semantic)
        result["footprint"] = footprint
        
    catch e
        result["status"] = "error"
        result["error"] = string(e)
    end
    
    return result
end

"""
    get_combined_footprint - Get memory footprint from both stores
"""
function get_combined_footprint(system::MemorySystem)::Dict{String, Any}
    footprint = Dict{String, Any}()
    
    # Episodic footprint
    episodic_size = length(system.episodic.episodes) * 2000  # Approximate
    footprint["episodic"] = Dict(
        "count" => length(system.episodic.episodes),
        "size_bytes" => episodic_size
    )
    
    # Semantic footprint
    if system.semantic !== nothing
        semantic_footprint = SemanticMemory.get_memory_footprint(system.semantic)
        footprint["semantic"] = semantic_footprint
        
        # Total
        footprint["total_bytes"] = episodic_size + semantic_footprint["total_size_bytes"]
        footprint["compression_ratio"] = semantic_footprint["compression_ratio"]
        footprint["target_met"] = semantic_footprint["target_met"]
    else
        footprint["total_bytes"] = episodic_size
        footprint["semantic"] = Dict("status" => "not_initialized")
    end
    
    return footprint
end

"""
    recall_from_memory - Attempt to recall a memory from semantic store
"""
function recall_from_memory(system::MemorySystem, cycle::Int)::Union{Vector{Float32}, Nothing}
    if system.semantic === nothing
        return nothing
    end
    
    return SemanticMemory.recall(system.semantic, cycle)
end

end # module
