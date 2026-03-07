# adaptive-kernel/cognition/oneiric/MemoryReplay.jl - Memory Replay System for Dream State
# JARVIS Neuro-Symbolic Architecture - Offline memory consolidation through experience replay

module MemoryReplay

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Logging

# Import memory store from parent
include(joinpath(@__DIR__, "..", "..", "memory", "Memory.jl"))
using ..Memory

# Import cognitive types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..CognitionTypes

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Replay state
    ReplayState,
    ReplayConfig,
    
    # Core functions
    replay_experiences!,
    compress_to_embeddings!,
    select_memories_for_replay,
    compute_replay_priority,
    should_trigger_replay

# ============================================================================
# REPLAY CONFIGURATION
# ============================================================================

"""
    ReplayConfig - Configuration for memory replay system

# Fields
- `max_replay_batch::Int`: Maximum memories to replay per cycle (default: 50)
- `replay_frequency_hz::Float64`: How often to run replay during dreams (default: 0.5)
- `priority_weight::Float64`: Weight for importance in replay selection (default: 0.6)
- `recency_weight::Float64`: Weight for recency in replay selection (default: 0.3)
- `emotional_weight::Float64`: Weight for emotional intensity (default: 0.1)
- `compression_dim::Int`: Dimension for compressed embeddings (default: 128)
- `min_importance::Float64`: Minimum importance to be considered for replay (default: 0.2)
"""
@with_kw mutable struct ReplayConfig
    max_replay_batch::Int = 50
    replay_frequency_hz::Float64 = 0.5
    priority_weight::Float64 = 0.6
    recency_weight::Float64 = 0.3
    emotional_weight::Float64 = 0.1
    compression_dim::Int = 128
    min_importance::Float64 = 0.2
end

# ============================================================================
# REPLAY STATE
# ============================================================================

"""
    ReplayState - Mutable state for memory replay system

# Fields
- `config::ReplayConfig`: Replay configuration
- `replay_buffer::Vector{Dict}`: Current batch of memories to replay
- `replay_count::Int`: Total number of replay operations performed
- `last_replay_time::Float64`: Unix timestamp of last replay
- `embeddings_cache::Matrix{Float32}`: Cached compressed embeddings
- `priorities::Vector{Float32}`: Priority scores for current replay buffer
"""
mutable struct ReplayState
    config::ReplayConfig
    replay_buffer::Vector{Dict{String, Any}}
    replay_count::Int
    last_replay_time::Float64
    embeddings_cache::Union{Matrix{Float32}, Nothing}
    priorities::Vector{Float32}
    
    function ReplayState(config::ReplayConfig=ReplayConfig())
        new(
            config,
            Dict{String, Any}[],
            0,
            0.0,
            nothing,
            Float32[]
        )
    end
end

# ============================================================================
# PRIORITY COMPUTATION
# ============================================================================

"""
    compute_replay_priority(episode::Dict{String, Any}, current_time::Float64)::Float32

Compute priority score for a memory episode based on importance, recency, and emotional content.

# Arguments
- `episode::Dict{String, Any}`: Memory episode with keys like "importance", "timestamp", "emotional_intensity"
- `current_time::Float64`: Current Unix timestamp

# Returns
- `Float32`: Priority score (0.0-1.0, higher is more important to replay)

# Example
```julia
priority = compute_replay_priority(episode, time())
```
"""
function compute_replay_priority(episode::Dict{String, Any}, current_time::Float64)::Float32
    config = ReplayConfig()
    
    # Extract components
    importance = get(episode, "importance", 0.5)::Float64
    importance = clamp(importance, 0.0, 1.0)
    
    # Recency calculation (exponential decay)
    timestamp = get(episode, "timestamp", current_time)::Float64
    time_elapsed = current_time - timestamp
    recency = exp(-time_elapsed / 86400.0)  # Half-life of 1 day
    recency = Float32(recency)
    
    # Emotional intensity
    emotional = get(episode, "emotional_intensity", 0.5)::Float64
    emotional = clamp(emotional, 0.0, 1.0)
    
    # Compute weighted priority
    priority = Float32(
        config.priority_weight * importance +
        config.recency_weight * recency +
        config.emotional_weight * emotional
    )
    
    return clamp(priority, 0.0f0, 1.0f0)
end

"""
    select_memories_for_replay(memory_store::MemoryStore, state::ReplayState; max_memories::Int=0)::Vector{Dict{String, Any}}

Select the most important memories for replay based on priority scoring.

# Arguments
- `memory_store::MemoryStore`: The memory store to select from
- `state::ReplayState`: Current replay state
- `max_memories::Int`: Maximum number of memories (0 = use config default)

# Returns
- `Vector{Dict{String, Any}}`: Selected episodes sorted by priority (highest first)

# Example
```julia
selected = select_memories_for_replay(memory_store, replay_state)
```
"""
function select_memories_for_replay(
    memory_store::MemoryStore,
    state::ReplayState;
    max_memories::Int=0
)::Vector{Dict{String, Any}}
    config = state.config
    max_memories = max_memories > 0 ? max_memories : config.max_replay_batch
    
    current_time = time()
    
    # Compute priorities for all episodes
    episode_priorities = Tuple{Dict{String, Any}, Float32}[]
    
    for episode in memory_store.episodes
        # Skip low-importance episodes
        importance = get(episode, "importance", 0.5)
        if importance < config.min_importance
            continue
        end
        
        priority = compute_replay_priority(episode, current_time)
        push!(episode_priorities, (episode, priority))
    end
    
    # Sort by priority (highest first)
    sort!(episode_priorities, by=x -> x[2], rev=true)
    
    # Select top memories
    selected = Dict{String, Any}[]
    for (episode, priority) in episode_priorities[1:min(length(episode_priorities), max_memories)]
        # Add priority to episode for tracking
        episode_with_priority = copy(episode)
        episode_with_priority["replay_priority"] = priority
        push!(selected, episode_with_priority)
    end
    
    return selected
end

# ============================================================================
# REPLAY EXECUTION
# ============================================================================

"""
    replay_experiences!(memory_store::MemoryStore, state::ReplayState)::Dict{String, Any}

Execute memory replay by selecting and reprocessing important experiences.

# Arguments
- `memory_store::MemoryStore`: The memory store containing episodes
- `state::ReplayState`: Current replay state

# Returns
- `Dict{String, Any}`: Replay results with statistics

# Triggers
- Nightly during dream state
- Low energy periods
- Idle system detection

# Example
```julia
results = replay_experiences!(memory_store, replay_state)
```
"""
function replay_experiences!(memory_store::MemoryStore, state::ReplayState)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    # Check if enough time has passed since last replay
    if state.last_replay_time > 0.0
        time_since_last = current_time - state.last_replay_time
        min_interval = 1.0 / config.replay_frequency_hz
        if time_since_last < min_interval
            return Dict{String, Any}(
                "status" => "skipped",
                "reason" => "too_soon",
                "time_since_last" => time_since_last
            )
        end
    end
    
    # Select memories for replay
    selected_memories = select_memories_for_replay(memory_store, state)
    
    if isempty(selected_memories)
        return Dict{String, Any}(
            "status" => "no_memories",
            "reason" => "no_significant_memories",
            "replay_count" => state.replay_count
        )
    end
    
    # Update replay buffer
    state.replay_buffer = selected_memories
    state.priorities = Float32[m["replay_priority"] for m in selected_memories]
    
    # Simulate replay processing (in a real system, this would update neural weights)
    replayed_count = length(selected_memories)
    
    # Update state
    state.replay_count += 1
    state.last_replay_time = current_time
    
    # Log replay statistics
    @info "Memory replay completed" 
        replay_count=replayed_count 
        total_replays=state.replay_count
        avg_priority=mean(state.priorities)
    
    return Dict{String, Any}(
        "status" => "success",
        "replayed_count" => replayed_count,
        "total_replays" => state.replay_count,
        "avg_priority" => mean(state.priorities),
        "max_priority" => maximum(state.priorities),
        "min_priority" => minimum(state.priorities),
        "timestamp" => current_time
    )
end

# ============================================================================
# EMBEDDING COMPRESSION
# ============================================================================

"""
    compress_to_embeddings!(state::ReplayState)::Matrix{Float32}

Convert replay buffer into compressed embeddings for efficient storage and processing.

# Arguments
- `state::ReplayState`: Current replay state with populated buffer

# Returns
- `Matrix{Float32}`: Compressed embeddings (compression_dim x num_memories)

# Example
```julia
embeddings = compress_to_embeddings!(replay_state)
```
"""
function compress_to_embeddings!(state::ReplayState)::Matrix{Float32}
    config = state.config
    buffer = state.replay_buffer
    
    if isempty(buffer)
        return zeros(Float32, config.compression_dim, 0)
    end
    
    n_memories = length(buffer)
    embeddings = zeros(Float32, config.compression_dim, n_memories)
    
    for (i, episode) in enumerate(buffer)
        # Extract raw features from episode
        raw_features = extract_episode_features(episode)
        
        # Compress to lower dimension using random projection
        # (In production, this would use a learned encoder)
        compressed = random_projection(raw_features, config.compression_dim)
        embeddings[:, i] = compressed
    end
    
    # Cache embeddings
    state.embeddings_cache = embeddings
    
    @debug "Compressed embeddings computed" 
        dim=config.compression_dim 
        count=n_memories
    
    return embeddings
end

"""
    extract_episode_features(episode::Dict{String, Any})::Vector{Float32}

Extract numerical features from a memory episode for compression.

# Arguments
- `episode::Dict{String, Any}`: Memory episode

# Returns
- `Vector{Float32}`: Feature vector (256-dimensional)
"""
function extract_episode_features(episode::Dict{String, Any})::Vector{Float32}
    features = Float32[]
    
    # Importance
    push!(features, Float32(get(episode, "importance", 0.5)))
    
    # Emotional intensity
    push!(features, Float32(get(episode, "emotional_intensity", 0.5)))
    
    # Prediction error
    push!(features, Float32(get(episode, "prediction_error", 0.0)))
    
    # Action outcome (success/failure encoded)
    outcome = get(episode, "result", false)
    push!(features, outcome ? 1.0f0 : 0.0f0)
    
    # Pad or truncate to fixed size
    target_size = 256
    while length(features) < target_size
        push!(features, 0.0f0)
    end
    
    return features[1:min(length(features), target_size)]
end

"""
    random_projection(features::Vector{Float32}, target_dim::Int)::Vector{Float32}

Simple random projection for dimensionality reduction.

# Arguments
- `features::Vector{Float32}`: Input features
- `target_dim::Int`: Target dimensionality

# Returns
- `Vector{Float32}`: Projected features
"""
function random_projection(features::Vector{Float32}, target_dim::Int)::Vector{Float32}
    # Use a simple hash-based projection for reproducibility
    n_features = length(features)
    projected = zeros(Float32, target_dim)
    
    # Simple random projection using deterministic seeding
    rng = MersenneTwister(42)
    
    for i in 1:target_dim
        weight_sum = 0.0f0
        for j in 1:n_features
            # Random weight from standard normal
            w = randn(rng, Float32)
            weight_sum += w * features[j]
        end
        projected[i] = weight_sum / sqrt(Float32(n_features))
    end
    
    # Normalize
    norm_val = norm(projected)
    if norm_val > 0
        projected ./= norm_val
    end
    
    return projected
end

# ============================================================================
# TRIGGER CONDITIONS
# ============================================================================

"""
    should_trigger_replay(
        energy_level::Float32,
        is_idle::Bool,
        time_since_replay::Float64;
        energy_threshold::Float32=0.30,
        idle_minimum::Float64=60.0
    )::Bool

Determine if memory replay should be triggered based on system conditions.

# Arguments
- `energy_level::Float32`: Current energy level (0.0-1.0)
- `is_idle::Bool`: Whether the system is idle
- `time_since_replay::Float64`: Seconds since last replay
- `energy_threshold::Float32`: Maximum energy to trigger replay (default: 0.30)
- `idle_minimum::Float64`: Minimum idle time in seconds (default: 60.0)

# Returns
- `Bool`: true if replay should be triggered

# Example
```julia
if should_trigger_replay(0.25, true, 300.0)
    replay_experiences!(memory_store, replay_state)
end
```
"""
function should_trigger_replay(
    energy_level::Float32,
    is_idle::Bool,
    time_since_replay::Float64;
    energy_threshold::Float32=0.30,
    idle_minimum::Float64=60.0
)::Bool
    # Must be low energy or idle
    low_energy = energy_level <= energy_threshold
    sufficiently_idle = is_idle && time_since_replay >= idle_minimum
    
    # Trigger conditions:
    # 1. Low energy and has been some time
    # 2. System is idle for sufficient duration
    return (low_energy && time_since_replay >= 60.0) || sufficiently_idle
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    reset_replay_state!(state::ReplayState)

Reset the replay state for a new dream cycle.

# Arguments
- `state::ReplayState`: State to reset
"""
function reset_replay_state!(state::ReplayState)
    empty!(state.replay_buffer)
    empty!(state.priorities)
    state.embeddings_cache = nothing
    # Keep replay_count and last_replay_time for tracking
end

"""
    get_replay_statistics(state::ReplayState)::Dict{String, Any}

Get comprehensive statistics about the replay system.

# Arguments
- `state::ReplayState`: Current replay state

# Returns
- `Dict{String, Any}`: Statistics dictionary
"""
function get_replay_statistics(state::ReplayState)::Dict{String, Any}
    return Dict{String, Any}(
        "total_replays" => state.replay_count,
        "last_replay_time" => state.last_replay_time,
        "current_buffer_size" => length(state.replay_buffer),
        "cache_available" => state.embeddings_cache !== nothing,
        "avg_priority" => isempty(state.priorities) ? 0.0 : mean(state.priorities),
        "config" => Dict(
            "max_replay_batch" => state.config.max_replay_batch,
            "replay_frequency_hz" => state.config.replay_frequency_hz,
            "compression_dim" => state.config.compression_dim
        )
    )
end

end # module MemoryReplay
