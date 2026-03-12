# adaptive-kernel/cognition/oneiric/MemoryReplay.jl - Memory Replay System for Dream State
# JARVIS Neuro-Symbolic Architecture - Offline memory consolidation through experience replay
# NEURAL WEIGHT UPDATES - Actual neural network training during dream state

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
# NEURAL NETWORK TYPE DEFINITIONS (Local for weight updates)
# ============================================================================

"""
    SimpleDenseLayer - A simple dense layer for neural network operations
    This is a local definition to avoid import issues.
"""
mutable struct SimpleDenseLayer
    input_dim::Int
    output_dim::Int
    weights::Matrix{Float32}
    bias::Vector{Float32}
    
    function SimpleDenseLayer(input_dim::Int, output_dim::Int)
        scale = sqrt(2.0f0 / (input_dim + output_dim))
        weights = randn(Float32, output_dim, input_dim) * scale
        bias = zeros(Float32, output_dim)
        new(input_dim, output_dim, weights, bias)
    end
end

function (layer::SimpleDenseLayer)(x::Vector{Float32})::Vector{Float32}
    return layer.weights * x .+ layer.bias
end

function (layer::SimpleDenseLayer)(x::Matrix{Float32})::Matrix{Float32}
    return layer.weights * x .+ layer.bias
end

"""
    NeuralBrainRef - Reference to neural brain for weight updates
    Contains the essential weights needed for gradient updates.
"""
mutable struct NeuralBrainRef
    encoder_weights::Matrix{Float32}
    encoder_bias::Vector{Float32}
    policy_weights::Matrix{Float32}
    policy_bias::Vector{Float32}
    value_weights::Matrix{Float32}
    value_bias::Vector{Float32}
    latent_dim::Int
    num_actions::Int
    
    function NeuralBrainRef(latent_dim::Int=128, num_actions::Int=6)
        new(
            randn(Float32, latent_dim, 12) * 0.1f0,
            zeros(Float32, latent_dim),
            randn(Float32, num_actions, latent_dim) * 0.1f0,
            zeros(Float32, num_actions),
            randn(Float32, 1, latent_dim) * 0.1f0,
            zeros(Float32, 1),
            latent_dim,
            num_actions
        )
    end
end

# ============================================================================
# HELPER FUNCTIONS (Local definitions for neural operations)
# ============================================================================

"""
    relu - ReLU activation function
"""
function relu(x::Vector{Float32})::Vector{Float32}
    return max.(0f0, x)
end

function relu(x::Float32)::Float32
    return max(0f0, x)
end

"""
    _encode_local - Encode perception vector to latent representation using brain weights
    This is a local wrapper that works with the NeuralBrain structure.
"""
function _encode_local(weights::Matrix{Float32}, bias::Vector{Float32}, perception::Vector{Float32})::Vector{Float32}
    # Linear transform + ReLU
    latent = weights * perception .+ bias
    return relu.(latent)
end

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
    should_trigger_replay,
    
    # NEW: Neural weight update functions
    perform_neural_weight_updates!,
    compute_rpe_priority,
    update_encoder_weights!,
    update_policy_weights!,
    update_value_weights!,
    consolidate_to_semantic_memory!,
    set_neural_brain!,
    get_neural_weight_statistics

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
- `dream_replay_count::Int`: Number of thoughts to replay during Oneiric dreaming (default: 10000)
- `rpe_weight::Float64`: Weight for Reward Prediction Error in priority (default: 0.7)
- `learning_rate::Float64`: Learning rate for neural weight updates (default: 0.001)
- `semantic_consolidation_threshold::Float64`: Threshold for semantic memory (default: 0.8)
- `enable_neural_updates::Bool`: Enable actual neural weight updates (default: true)
"""
@with_kw mutable struct ReplayConfig
    max_replay_batch::Int = 50
    replay_frequency_hz::Float64 = 0.5
    priority_weight::Float64 = 0.6
    recency_weight::Float64 = 0.3
    emotional_weight::Float64 = 0.1
    compression_dim::Int = 128
    min_importance::Float64 = 0.2
    # Neural weight update parameters
    dream_replay_count::Int = 10000  # 10,000 high-RPE thoughts during dreaming
    rpe_weight::Float64 = 0.7       # RPE weight for priority selection
    learning_rate::Float64 = 0.001f0
    semantic_consolidation_threshold::Float64 = 0.8f0
    enable_neural_updates::Bool = true
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
- `neural_brain::Union{NeuralBrainRef, Nothing}`: Reference to neural brain for weight updates
- `total_weight_updates::Int`: Total number of weight updates performed
- `last_update_time::Float64`: Unix timestamp of last weight update
- `semantic_embeddings::Matrix{Float32}`: Compressed semantic memory embeddings
- `rpe_history::Vector{Float32}`: History of RPE values for priority
"""
mutable struct ReplayState
    config::ReplayConfig
    replay_buffer::Vector{Dict{String, Any}}
    replay_count::Int
    last_replay_time::Float64
    embeddings_cache::Union{Matrix{Float32}, Nothing}
    priorities::Vector{Float32}
    
    # Neural brain integration
    neural_brain::Union{NeuralBrainRef, Nothing}
    
    # Weight update tracking
    total_weight_updates::Int
    last_update_time::Float64
    
    # Semantic memory
    semantic_embeddings::Union{Matrix{Float32}, Nothing}
    
    # RPE tracking
    rpe_history::Vector{Float32}
    
    function ReplayState(config::ReplayConfig=ReplayConfig())
        new(
            config,
            Dict{String, Any}[],
            0,
            0.0,
            nothing,
            Float32[],
            nothing,  # neural_brain
            0,       # total_weight_updates
            0.0,    # last_update_time
            nothing, # semantic_embeddings
            Float32[]  # rpe_history
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
    compute_rpe_priority(episode::Dict{String, Any}, current_time::Float64)::Float32

Compute priority score based on Reward Prediction Error (RPE). High RPE memories
are more surprising and thus more important for learning.

# Arguments
- `episode::Dict{String, Any}`: Memory episode with "prediction_error" or computed from "expected_reward" vs "actual_reward"
- `current_time::Float64`: Current Unix timestamp

# Returns
- `Float32`: RPE-based priority score (0.0-1.0, higher means more surprising/important)

# Notes
- RPE = |actual_reward - expected_reward|
- Episodes with high RPE indicate prediction errors, making them crucial for learning
"""
function compute_rpe_priority(episode::Dict{String, Any}, current_time::Float64)::Float32
    config = ReplayConfig()
    
    # Compute RPE from episode data
    # Method 1: Direct prediction error field
    prediction_error = get(episode, "prediction_error", 0.0)::Float64
    
    # Method 2: Compute from expected vs actual reward
    if prediction_error == 0.0
        expected_reward = get(episode, "expected_reward", 0.5)::Float64
        actual_reward = get(episode, "actual_reward", 0.5)::Float64
        prediction_error = abs(Float32(expected_reward - actual_reward))
    end
    
    # Method 3: Compute from result quality
    if prediction_error == 0.0
        result = get(episode, "result", false)::Bool
        confidence = get(episode, "confidence", 0.5)::Float64
        # High confidence but wrong result = high prediction error
        if result
            prediction_error = 1.0f0 - confidence
        else
            prediction_error = confidence
        end
    end
    
    # Normalize RPE to [0, 1]
    rpe_normalized = clamp(prediction_error, 0.0f0, 1.0f0)
    
    # Add recency weighting for RPE (more recent = more relevant)
    timestamp = get(episode, "timestamp", current_time)::Float64
    time_elapsed = current_time - timestamp
    recency = exp(-time_elapsed / 86400.0)  # Half-life of 1 day
    recency = Float32(recency)
    
    # Combine RPE with recency using configured weight
    priority = Float32(
        config.rpe_weight * rpe_normalized +
        (1.0f0 - config.rpe_weight) * recency
    )
    
    return clamp(priority, 0.0f0, 1.0f0)
end

"""
    set_neural_brain!(state::ReplayState, brain::NeuralBrain)

Set the neural brain reference for weight updates.

# Arguments
- `state::ReplayState`: Current replay state
- `brain::NeuralBrain`: Neural brain to use for weight updates
"""
function set_neural_brain!(state::ReplayState, brain::NeuralBrainRef)
    state.neural_brain = brain
    @info "Neural brain set for memory replay" 
        latent_dim=brain.latent_dim 
        num_actions=brain.num_actions
end
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
        energy_threshold::Float32=0.30f0,
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
    energy_threshold::Float32=0.30f0,
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

# ============================================================================
# NEURAL WEIGHT UPDATE FUNCTIONS
# ============================================================================

"""
    update_encoder_weights!(
        brain::NeuralBrain,
        input::Vector{Float32},
        target_latent::Vector{Float32},
        learning_rate::Float32
    )::Float32

Perform gradient descent update on encoder weights.

# Arguments
- `brain::NeuralBrain`: Neural brain with encoder network
- `input::Vector{Float32}`: Input perception vector (12-dimensional)
- `target_latent::Vector{Float32}`: Target latent representation
- `learning_rate::Float32`: Learning rate for gradient update

# Returns
- `Float32`: Loss value before update
"""
function update_encoder_weights!(
    brain::NeuralBrainRef,
    input::Vector{Float32},
    target_latent::Vector{Float32},
    learning_rate::Float32
)::Float32
    # Forward pass through encoder
    latent = brain.encoder_weights * input .+ brain.encoder_bias
    
    # Apply ReLU activation
    latent = relu.(latent)
    
    # Compute loss (MSE between current and target latent)
    error = latent .- target_latent
    loss = sum(error .^ 2) / length(error)
    
    # Compute gradient
    grad = 2.0f0 .* error ./ length(error)
    
    # Apply ReLU gradient (zero for negative values)
    grad = grad .* (latent .> 0f0)
    
    # Update encoder weights using gradient descent
    grad_weight = reshape(grad, length(grad), 1) * reshape(input, 1, length(input))
    brain.encoder_weights .-= learning_rate .* grad_weight
    brain.encoder_bias .-= learning_rate .* grad
    
    return loss
end

"""
    update_policy_weights!(
        brain::NeuralBrainRef,
        latent::Vector{Float32},
        target_logits::Vector{Float32},
        learning_rate::Float32
    )::Float32

Perform gradient descent update on policy network weights.

# Arguments
- `brain::NeuralBrainRef`: Neural brain with policy network
- `latent::Vector{Float32}`: Latent representation from encoder
- `target_logits::Vector{Float32}`: Target action logits
- `learning_rate::Float32`: Learning rate for gradient update

# Returns
- `Float32`: Loss value before update
"""
function update_policy_weights!(
    brain::NeuralBrainRef,
    latent::Vector{Float32},
    target_logits::Vector{Float32},
    learning_rate::Float32
)::Float32
    # Forward pass through policy network
    logits = brain.policy_weights * latent .+ brain.policy_bias
    
    # Compute loss (MSE between current and target logits)
    error = logits .- target_logits
    loss = sum(error .^ 2) / length(error)
    
    # Compute gradient
    grad = 2.0f0 .* error ./ length(error)
    
    # Update policy weights
    grad_weight = reshape(grad, length(grad), 1) * reshape(latent, 1, length(latent))
    brain.policy_weights .-= learning_rate .* grad_weight
    brain.policy_bias .-= learning_rate .* grad
    
    return loss
end

"""
    update_value_weights!(
        brain::NeuralBrainRef,
        latent::Vector{Float32},
        target_value::Float32,
        learning_rate::Float32
    )::Float32

Perform gradient descent update on value network weights.

# Arguments
- `brain::NeuralBrainRef`: Neural brain with value network
- `latent::Vector{Float32}`: Latent representation from encoder
- `target_value::Float32`: Target value estimate
- `learning_rate::Float32`: Learning rate for gradient update

# Returns
- `Float32`: Loss value before update
"""
function update_value_weights!(
    brain::NeuralBrainRef,
    latent::Vector{Float32},
    target_value::Float32,
    learning_rate::Float32
)::Float32
    # Forward pass through value network
    current_value = (brain.value_weights * latent .+ brain.value_bias)[1]
    
    # Compute loss (MSE between current and target value)
    error = current_value - target_value
    loss = error * error
    
    # Compute gradient
    grad = 2.0f0 * error
    
    # Update value weights
    grad_weight = grad * reshape(latent, 1, length(latent))
    brain.value_weights .-= learning_rate .* grad_weight
    brain.value_bias .-= learning_rate .* grad
    
    return loss
end

"""
    perform_neural_weight_updates!(
        state::ReplayState,
        memory_store::MemoryStore
    )::Dict{String, Any}

Perform actual neural network weight updates using replayed memories.
This is the core function that implements proper neural weight updates
during Oneiric (dreaming) state.

# Arguments
- `state::ReplayState`: Current replay state with neural brain reference
- `memory_store::MemoryStore`: Memory store containing episodes

# Returns
- `Dict{String, Any}`: Results with weight update statistics

# Notes
- Replays up to `dream_replay_count` (default 10,000) high-RPE thoughts
- Updates encoder, policy, and value network weights
- Uses RPE-based priority selection for replay
"""
function perform_neural_weight_updates!(
    state::ReplayState,
    memory_store::MemoryStore
)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    # Check if neural brain is available
    if state.neural_brain === nothing
        return Dict{String, Any}(
            "status" => "no_neural_brain",
            "reason" => "Neural brain not set for replay state"
        )
    end
    
    if !config.enable_neural_updates
        return Dict{String, Any}(
            "status" => "disabled",
            "reason" => "Neural updates disabled in config"
        )
    end
    
    brain = state.neural_brain
    lr = config.learning_rate
    
    # Select memories with high RPE priority
    rpe_priorities = Tuple{Dict{String, Any}, Float32}[]
    
    for episode in memory_store.episodes
        # Skip low-importance episodes
        importance = get(episode, "importance", 0.5)
        if importance < config.min_importance
            continue
        end
        
        # Use RPE-based priority
        priority = compute_rpe_priority(episode, current_time)
        push!(rpe_priorities, (episode, priority))
    end
    
    # Sort by RPE priority (highest first)
    sort!(rpe_priorities, by=x -> x[2], rev=true)
    
    # Replay up to dream_replay_count thoughts
    replay_count = min(config.dream_replay_count, length(rpe_priorities))
    
    if replay_count == 0
        return Dict{String, Any}(
            "status" => "no_memories",
            "reason" => "No high-RPE memories found for replay"
        )
    end
    
    # Track statistics
    encoder_losses = Float32[]
    policy_losses = Float32[]
    value_losses = Float32[]
    rpe_values = Float32[]
    
    # Perform weight updates
    for (episode, rpe) in rpe_priorities[1:replay_count]
        push!(rpe_values, rpe)
        
        # Extract features from episode
        features = extract_episode_features(episode)
        
        # Create perception vector from episode
        # Map episode features to 12D perception vector
        perception = Vector{Float32}(undef, 12)
        perception[1] = get(episode, "cpu_usage", 0.5f0)
        perception[2] = get(episode, "memory_usage", 0.5f0)
        perception[3] = get(episode, "importance", 0.5f0)
        perception[4] = get(episode, "emotional_intensity", 0.5f0)
        perception[5] = get(episode, "severity", 0.0f0)
        perception[6] = rpe  # Use RPE as feature
        perception[7] = get(episode, "confidence", 0.5f0)
        perception[8] = get(episode, "result", false) ? 1.0f0 : 0.0f0
        perception[9] = get(episode, "expected_reward", 0.5f0)
        perception[10] = get(episode, "actual_reward", 0.5f0)
        perception[11] = Float32(get(episode, "timestamp", current_time) / 86400.0)
        perception[12] = clamp(rpe * 2.0f0, 0.0f0, 1.0f0)  # RPE normalized
        
        # Forward pass through brain using local encoder
        latent = _encode_local(brain.encoder_weights, brain.encoder_bias, perception)
        
        # Generate target values for learning
        # Target latent: slightly modified version for consolidation
        target_latent = copy(latent)
        if length(target_latent) > 0
            # Add small noise for exploration during replay
            noise = randn(Float32, length(target_latent)) * 0.01f0
            target_latent = target_latent .+ noise
        end
        
        # Target policy logits: reinforce good actions
        actual_reward = get(episode, "actual_reward", 0.5f0)
        target_logits = brain.policy_weights * latent .+ brain.policy_bias
        if actual_reward > 0.5f0
            # Reinforce current logits
            target_logits = target_logits .+ 0.1f0
        else
            # Push away from current
            target_logits = target_logits .- 0.1f0
        end
        
        # Target value: TD learning target
        target_value = Float32(actual_reward)
        
        # Update encoder
        enc_loss = update_encoder_weights!(brain, perception, target_latent, lr)
        push!(encoder_losses, enc_loss)
        
        # Update policy
        pol_loss = update_policy_weights!(brain, latent, target_logits, lr)
        push!(policy_losses, pol_loss)
        
        # Update value
        val_loss = update_value_weights!(brain, latent, target_value, lr)
        push!(value_losses, val_loss)
    end
    
    # Update state
    state.total_weight_updates += replay_count
    state.last_update_time = current_time
    
    # Track RPE history
    append!(state.rpe_history, rpe_values)
    if length(state.rpe_history) > 10000
        state.rpe_history = state.rpe_history[end-9999:end]
    end
    
    @info "Neural weight updates completed"
        replay_count=replay_count
        total_updates=state.total_weight_updates
        avg_encoder_loss=isempty(encoder_losses) ? 0.0 : mean(encoder_losses)
        avg_policy_loss=isempty(policy_losses) ? 0.0 : mean(policy_losses)
        avg_value_loss=isempty(value_losses) ? 0.0 : mean(value_losses)
        avg_rpe=mean(rpe_values)
    
    return Dict{String, Any}(
        "status" => "success",
        "replayed_count" => replay_count,
        "total_weight_updates" => state.total_weight_updates,
        "avg_encoder_loss" => isempty(encoder_losses) ? 0.0 : mean(encoder_losses),
        "avg_policy_loss" => isempty(policy_losses) ? 0.0 : mean(policy_losses),
        "avg_value_loss" => isempty(value_losses) ? 0.0 : mean(value_losses),
        "max_rpe" => maximum(rpe_values),
        "avg_rpe" => mean(rpe_values),
        "min_rpe" => minimum(rpe_values),
        "timestamp" => current_time
    )
end

"""
    consolidate_to_semantic_memory!(
        state::ReplayState,
        memory_store::MemoryStore
    )::Dict{String, Any}

Consolidate episodic memories into compressed semantic memory embeddings.
This distills high-value episodes into latent representations for
efficient storage and retrieval.

# Arguments
- `state::ReplayState`: Current replay state
- `memory_store::MemoryStore`: Memory store containing episodes

# Returns
- `Dict{String, Any}`: Consolidation results with semantic embeddings
"""
function consolidate_to_semantic_memory!(
    state::ReplayState,
    memory_store::MemoryStore
)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    if isempty(memory_store.episodes)
        return Dict{String, Any}(
            "status" => "no_episodes",
            "reason" => "No episodes to consolidate"
        )
    end
    
    # Select high-importance episodes for semantic memory
    consolidation_candidates = Dict{String, Any}[]
    
    for episode in memory_store.episodes
        importance = get(episode, "importance", 0.5)
        if importance >= config.semantic_consolidation_threshold
            push!(consolidation_candidates, episode)
        end
    end
    
    if isempty(consolidation_candidates)
        return Dict{String, Any}(
            "status" => "no_candidates",
            "reason" => "No episodes meet consolidation threshold"
        )
    end
    
    # Compress to semantic embeddings
    # Use the embeddings cache or compute new ones
    n_memories = length(consolidation_candidates)
    semantic_dim = config.compression_dim
    
    # Create semantic embedding matrix
    semantic_embeddings = zeros(Float32, semantic_dim, n_memories)
    
    for (i, episode) in enumerate(consolidation_candidates)
        # Extract features
        features = extract_episode_features(episode)
        
        # Compress using random projection (could be replaced with learned encoder)
        compressed = random_projection(features, semantic_dim)
        
        # Apply importance weighting
        importance = get(episode, "importance", 0.5)
        semantic_embeddings[:, i] = compressed * Float32(importance)
    end
    
    # Update state
    state.semantic_embeddings = semantic_embeddings
    
    @info "Semantic memory consolidation completed"
        episode_count=n_memories
        embedding_dim=semantic_dim
    
    return Dict{String, Any}(
        "status" => "success",
        "consolidated_count" => n_memories,
        "embedding_dim" => semantic_dim,
        "embedding_matrix_size" => size(semantic_embeddings),
        "timestamp" => current_time
    )
end

"""
    get_neural_weight_statistics(state::ReplayState)::Dict{String, Any}

Get comprehensive statistics about neural weight updates.

# Arguments
- `state::ReplayState`: Current replay state

# Returns
- `Dict{String, Any}`: Statistics about neural updates
"""
function get_neural_weight_statistics(state::ReplayState)::Dict{String, Any}
    stats = Dict{String, Any}(
        "total_weight_updates" => state.total_weight_updates,
        "last_update_time" => state.last_update_time,
        "neural_brain_connected" => state.neural_brain !== nothing
    )
    
    if state.neural_brain !== nothing
        brain = state.neural_brain
        stats["latent_dim"] = brain.latent_dim
        stats["num_actions"] = brain.num_actions
        stats["training_step"] = brain.training_step
    end
    
    if !isempty(state.rpe_history)
        stats["avg_rpe"] = mean(state.rpe_history)
        stats["max_rpe"] = maximum(state.rpe_history)
        stats["min_rpe"] = minimum(state.rpe_history)
    end
    
    if state.semantic_embeddings !== nothing
        stats["semantic_memory_size"] = size(state.semantic_embeddings)
    end
    
    return stats
end

end

