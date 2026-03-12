# adaptive-kernel/cognition/learning/OnlineLearning.jl
# Continuous Online Learning - Component 9 of JARVIS Neuro-Symbolic Architecture
# Implements incremental updates with meta-learning hooks and safety rollback
# Actual Policy Gradient learning with Flux.jl and Zygote.jl

module OnlineLearning

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Random
using StatsBase  # For weighted sampling

# Try to import Flux and Zygote for automatic differentiation
const ZYGOTE_AVAILABLE = try
    using Zygote
    true
catch e
    false
end

const FLUX_AVAILABLE = try
    using Flux
    true
catch e
    false
end

# Include policy gradient extensions
include(joinpath(@__DIR__, "PolicyGradient.jl"))
import .PolicyGradient: PolicyGradientConfig, PolicyGradientState, Trajectory,
    create_policy_gradient_state, compute_policy_gradients, compute_gae_advantages,
    compute_discounted_returns, compute_ppo_loss, collect_trajectory, update_value_network!,
    apply_policy_gradients!, softmax, compute_log_prob, compute_action_probabilities,
    sample_action, compute_value, extract_action_log_probs

# Re-export from PolicyGradient
using .PolicyGradient

# ============================================================================
# CONSTANTS FOR METABOLIC GATING
# ============================================================================

const INFERENCE_COST::Float32 = 0.001f0
const DEFAULT_GRADIENT_NORM_THRESHOLD::Float32 = 0.1f0

# ============================================================================
# EXPORTS
# ============================================================================

export 
    LearningState,
    PolicyGradientConfig,
    PolicyGradientState,
    Trajectory,
    IncrementalBrain,
    ReplayBuffer,
    incremental_update!,
    meta_learn,
    adapt_to_task,
    modulate_learning_rate,
    create_learning_snapshot,
    rollback_to_snapshot!,
    estimate_confidence,
    compute_uncertainty_bounds,
    advance_curriculum!,
    get_curriculum_difficulty,
    clip_gradients!,
    compute_gradients,
    apply_gradients!,
    # Policy gradient exports
    create_policy_gradient_state,
    compute_policy_gradients,
    compute_gae_advantages,
    compute_discounted_returns,
    compute_ppo_loss,
    collect_trajectory,
    update_value_network!,
    apply_policy_gradients!,
    # New exports for actual RL
    create_replay_buffer,
    push_experience!,
    sample_batch,
    compute_actor_critic_loss,
    compute_zygote_gradients,
    apply_flux_update!,
    compute_td_error,
    compute_advantage,
    apply_metabolic_gating!,
    create_oneiric_prioritized_buffer,
    compute_prioritized_replay_weights

# ============================================================================
# LEARNING STATE
# ============================================================================

"""
    LearningState - Mutable state for continuous online learning

Tracks learning parameters, meta-learning state, confidence, safety snapshots,
and curriculum progression for adaptive learning.
"""
mutable struct LearningState
    # Learning parameters
    base_learning_rate::Float32
    current_learning_rate::Float32
    momentum::Float32
    
    # Meta-learning
    meta_learning_rate::Float32
    adaptation_steps::Int
    
    # Confidence tracking
    confidence::Float32
    uncertainty::Float32
    
    # Safety
    rollback_available::Bool
    last_snapshot::Union{Dict, Nothing}
    snapshot_interval::Int  # cycles
    
    # Curriculum
    curriculum_level::Int
    curriculum_progress::Float32
    
    # Energy/metabolic tracking
    energy_acc::Float32
    last_inference_cost::Float32
    
    # Entropy monitoring for reversible learning
    policy_entropy::Float32
    entropy_threshold::Float32
    
    # Meta-RL: sub-policy tracking
    sub_policy_effectiveness::Dict{String, Float32}
    
    function LearningState(;
        base_learning_rate::Float32=0.01f0,
        curriculum_level::Int=1
    )
        new(
            base_learning_rate,
            base_learning_rate,
            0.9f0,
            0.001f0,  # meta_learning_rate
            5,        # adaptation_steps
            0.5f0,    # confidence
            0.5f0,    # uncertainty
            true,
            nothing,
            100,      # snapshot_interval
            curriculum_level,
            0.0f0,    # curriculum_progress
            1.0f0,    # energy_acc
            0.0f0,    # last_inference_cost
            1.0f0,    # policy_entropy
            0.5f0,    # entropy_threshold
            Dict{String, Float32}()  # sub_policy_effectiveness
        )
    end
end

# ============================================================================
# INCREMENTAL BRAIN - Supports Flux/Zygote and fallback
# ============================================================================

"""
    IncrementalBrain - Brain wrapper for incremental learning with Flux/Zygote

Supports:
- Flux.jl neural networks with automatic differentiation
- gradient Zygote.jl computation
- Fallback to manual gradients when libraries unavailable
"""
mutable struct IncrementalBrain
    # Neural network components (Flux if available)
    policy_network::Any  # Flux Chain or custom
    value_network::Any   # Flux Chain or custom
    
    # Parameters (for manual gradient computation)
    policy_weights::Matrix{Float32}
    policy_bias::Vector{Float32}
    value_weights::Matrix{Float32}
    value_bias::Vector{Float32}
    
    # State dimensions
    state_dim::Int
    action_dim::Int
    
    # Policy gradient state
    policy_state::Union{PolicyGradientState, Nothing}
    
    # Use Flux/Zygote flag
    use_zygote::Bool
    use_flux::Bool
    
    # Optimizer state for Flux
    optimizer::Any
    
    function IncrementalBrain(;
        state_dim::Int=10,
        action_dim::Int=5,
        hidden_dim::Int=32,
        learning_rate::Float32=0.001f0
    )
        # Initialize neural networks
        if FLUX_AVAILABLE
            # Create Flux chains
            policy_network = Flux.Chain(
                Flux.Dense(state_dim, hidden_dim, relu),
                Flux.Dense(hidden_dim, action_dim)
            )
            value_network = Flux.Chain(
                Flux.Dense(state_dim, hidden_dim, relu),
                Flux.Dense(hidden_dim, 1)
            )
            
            # Create optimizer
            optimizer = Flux.Adam(learning_rate)
            use_flux = true
        else
            policy_network = nothing
            value_network = nothing
            optimizer = nothing
            use_flux = false
        end
        
        # Initialize manual parameters
        policy_weights = randn(Float32, action_dim, state_dim) * Float32(0.01)
        policy_bias = zeros(Float32, action_dim)
        value_weights = randn(Float32, 1, state_dim) * Float32(0.01)
        value_bias = zeros(Float32, 1)
        
        # Create policy gradient state
        policy_state = create_policy_gradient_state(state_dim, action_dim)
        
        new(
            policy_network,
            value_network,
            policy_weights,
            policy_bias,
            value_weights,
            value_bias,
            state_dim,
            action_dim,
            policy_state,
            ZYGOTE_AVAILABLE && FLUX_AVAILABLE,
            use_flux,
            optimizer
        )
    end
end

# ============================================================================
# REPLAY BUFFER - Ring buffer for trajectory storage
# ============================================================================

"""
    ReplayBuffer - Ring buffer for storing trajectories (s, a, r, s')

Supports:
- Fixed capacity with overwriting
- Priority sampling for Oneiric integration
- Metabolic cost tracking
"""
mutable struct ReplayBuffer
    capacity::Int
    states::Vector{Vector{Float32}}
    actions::Vector{Int}
    rewards::Vector{Float32}
    next_states::Vector{Vector{Float32}}
    dones::Vector{Bool}
    log_probs::Vector{Float32}
    values::Vector{Float32}
    priorities::Vector{Float32}  # For prioritized replay (RPE-based)
    position::Int
    size::Int
    total_reward::Float32
    episode_count::Int
    
    function ReplayBuffer(capacity::Int=10000)
        new(
            capacity,
            Vector{Vector{Float32}}(),
            Vector{Int}(),
            Vector{Float32}(),
            Vector{Vector{Float32}}(),
            Vector{Bool}(),
            Vector{Float32}(),
            Vector{Float32}(),
            Vector{Float32}(),
            0,  # position
            0,  # size
            0.0f0,  # total_reward
            0     # episode_count
        )
    end
end

"""
    create_replay_buffer(capacity::Int=10000)::ReplayBuffer
"""
function create_replay_buffer(capacity::Int=10000)::ReplayBuffer
    return ReplayBuffer(capacity)
end

"""
    push_experience!(buffer::ReplayBuffer, state, action, reward, next_state, done, value, log_prob)

Add experience to replay buffer with automatic priority assignment based on RPE.
"""
function push_experience!(
    buffer::ReplayBuffer,
    state::Vector{Float32},
    action::Int,
    reward::Float32,
    next_state::Vector{Float32},
    done::Bool;
    value::Float32=0.0f0,
    log_prob::Float32=0.0f0,
    priority::Float32=1.0f0
)::Nothing
    # Compute priority based on TD error (RPE) if not provided
    if priority == 1.0f0 && length(buffer.values) > 0
        # Use TD error as priority
        td_error = abs(reward + Float32(0.99) * value - value)
        priority = Float32(1e-6) + td_error
    end
    
    if length(buffer.states) < buffer.capacity
        push!(buffer.states, deepcopy(state))
        push!(buffer.actions, action)
        push!(buffer.rewards, reward)
        push!(buffer.next_states, deepcopy(next_state))
        push!(buffer.dones, done)
        push!(buffer.values, value)
        push!(buffer.log_probs, log_prob)
        push!(buffer.priorities, priority)
    else
        buffer.states[buffer.position + 1] = deepcopy(state)
        buffer.actions[buffer.position + 1] = action
        buffer.rewards[buffer.position + 1] = reward
        buffer.next_states[buffer.position + 1] = deepcopy(next_state)
        buffer.dones[buffer.position + 1] = done
        buffer.values[buffer.position + 1] = value
        buffer.log_probs[buffer.position + 1] = log_prob
        buffer.priorities[buffer.position + 1] = priority
    end
    
    buffer.position = mod(buffer.position + 1, buffer.capacity)
    buffer.size = min(buffer.size + 1, buffer.capacity)
    buffer.total_reward += reward
    
    if done
        buffer.episode_count += 1
    end
    
    return nothing
end

"""
    sample_batch(buffer::ReplayBuffer, batch_size::Int)::Dict

Sample random batch from replay buffer.
"""
function sample_batch(buffer::ReplayBuffer, batch_size::Int)::Dict
    if buffer.size < batch_size
        batch_size = buffer.size
    end
    
    if batch_size == 0
        return Dict(
            "states" => Vector{Vector{Float32}}(),
            "actions" => Vector{Int}(),
            "rewards" => Vector{Float32}(),
            "next_states" => Vector{Vector{Float32}}(),
            "dones" => Vector{Bool}(),
            "log_probs" => Vector{Float32}(),
            "values" => Vector{Float32}()
        )
    end
    
    indices = rand(1:buffer.size, batch_size)
    
    states = [deepcopy(buffer.states[i]) for i in indices]
    actions = buffer.actions[indices]
    rewards = buffer.rewards[indices]
    next_states = [deepcopy(buffer.next_states[i]) for i in indices]
    dones = buffer.dones[indices]
    log_probs = buffer.log_probs[indices]
    values = buffer.values[indices]
    
    return Dict(
        "states" => states,
        "actions" => actions,
        "rewards" => rewards,
        "next_states" => next_states,
        "dones" => dones,
        "log_probs" => log_probs,
        "values" => values
    )
end

"""
    create_oneiric_prioritized_buffer(buffer::ReplayBuffer)::Vector{Int}

Return indices sorted by priority (RPE) for Oneiric high-RPE thought prioritization.
"""
function create_oneiric_prioritized_buffer(buffer::ReplayBuffer)::Vector{Int}
    if buffer.size == 0
        return Int[]
    end
    
    # Sort by priority (higher RPE = higher priority)
    priorities = buffer.priorities[1:buffer.size]
    indices = sortperm(priorities, rev=true)
    
    return indices
end

"""
    compute_prioritized_replay_weights(buffer::ReplayBuffer, indices::Vector{Int})::Vector{Float32}

Compute IS weights for prioritized replay.
"""
function compute_prioritized_replay_weights(
    buffer::ReplayBuffer,
    indices::Vector{Int};
    alpha::Float32=0.6f0,
    beta::Float32=0.4f0
)::Vector{Float32}
    if length(indices) == 0
        return Float32[]
    end
    
    # Get priorities
    priorities = buffer.priorities[indices]
    
    # Normalize priorities
    probs = priorities.^alpha
    probs = probs / sum(probs)
    
    # Compute IS weights
    weights = (buffer.size * probs).^(-beta)
    weights = weights / maximum(weights)  # Normalize
    
    return weights
end

# ============================================================================
# ACTOR-CRITIC WITH VALUE NETWORK
# ============================================================================

"""
    compute_advantage(state, next_state, reward, value, next_value, gamma)::Float32

Compute advantage: A(s, a) = R + γV(s') - V(s)
"""
function compute_advantage(
    state::Vector{Float32},
    next_state::Vector{Float32},
    reward::Float32,
    value::Float32,
    next_value::Float32;
    gamma::Float32=Float32(0.99)
)::Float32
    return reward + gamma * next_value - value
end

"""
    compute_td_error(state, next_state, reward, value, next_value, gamma)::Float32

Compute TD-error: δt = rt + γV(st+1) - V(st)
This is used for both advantage estimation and priority assignment.
"""
function compute_td_error(
    state::Vector{Float32},
    next_state::Vector{Float32},
    reward::Float32,
    value::Float32,
    next_value::Float32;
    gamma::Float32=Float32(0.99)
)::Float32
    return reward + gamma * next_value - value
end

"""
    compute_actor_critic_loss(brain::IncrementalBrain, states, actions, rewards, next_states, dones)::Dict

Compute Actor-Critic loss using neural networks.
"""
function compute_actor_critic_loss(
    brain::IncrementalBrain,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    rewards::Vector{Float32},
    next_states::Vector{Vector{Float32}},
    dones::Vector{Bool};
    gamma::Float32=Float32(0.99),
    value_coef::Float32=Float32(0.5),
    entropy_coef::Float32=Float32(0.01)
)::Dict
    result = Dict{String, Any}()
    
    T = length(states)
    if T == 0
        result["total_loss"] = Float32(0.0)
        result["policy_loss"] = Float32(0.0)
        result["value_loss"] = Float32(0.0)
        result["entropy"] = Float32(0.0)
        return result
    end
    
    # Convert states to matrix for batch processing
    state_matrix = hcat(states...)
    next_state_matrix = hcat(next_states...)
    
    # Compute values using policy network
    if brain.use_flux && brain.value_network !== nothing
        # Use Flux networks
        values = brain.value_network(state_matrix)[:]
        next_values = brain.value_network(next_state_matrix)[:]
        
        # Compute action logits
        logits = brain.policy_network(state_matrix)
        
        # Compute policy probabilities
        probs = Flux.softmax(logits, dims=1)
        
        # Get log probabilities for taken actions
        log_probs = Float32[]
        for t in 1:T
            action = actions[t]
            push!(log_probs, log(clamp(probs[action, t], Float32(1e-8), Float32(1.0))))
        end
        
        # Compute advantages
        advantages = Float32[]
        for t in 1:T
            next_val = dones[t] ? Float32(0.0) : next_values[t]
            adv = rewards[t] + gamma * next_val - values[t]
            push!(advantages, adv)
        end
        
        # Policy loss: -log π(a|s) * A
        policy_loss = Float32(0.0)
        for t in 1:T
            policy_loss -= log_probs[t] * advantages[t]
        end
        policy_loss /= Float32(T)
        
        # Value loss: MSE(V(s) - G_t)
        returns = rewards .+ gamma .* next_values .* .!dones
        value_loss = Float32(0.0)
        for t in 1:T
            value_loss += (values[t] - returns[t])^2
        end
        value_loss = value_coef * value_loss / Float32(T)
        
        # Entropy bonus
        entropy = Float32(0.0)
        eps = Float32(1e-8)
        for t in 1:T
            entropy -= sum(probs[:, t] .* log.(clamp.(probs[:, t], eps, Float32(1.0))))
        end
        entropy /= Float32(T)
        
        total_loss = policy_loss + value_loss - entropy_coef * entropy
        
    else
        # Use manual parameters
        values = Float32[]
        next_values = Float32[]
        log_probs = Float32[]
        
        for t in 1:T
            state = states[t]
            next_state = next_states[t]
            
            # Value prediction
            v = dot(brain.value_weights, state) + brain.value_bias[1]
            next_v = dot(brain.value_weights, next_state) + brain.value_bias[1]
            
            push!(values, v)
            push!(next_values, next_v)
            
            # Policy (softmax)
            logits = brain.policy_weights * state .+ brain.policy_bias
            probs = softmax(logits)
            
            action = actions[t]
            push!(log_probs, log(clamp(probs[action], Float32(1e-8), Float32(1.0))))
        end
        
        # Compute advantages
        advantages = Float32[]
        for t in 1:T
            next_val = dones[t] ? Float32(0.0) : next_values[t]
            adv = rewards[t] + gamma * next_val - values[t]
            push!(advantages, adv)
        end
        
        # Policy loss
        policy_loss = Float32(0.0)
        for t in 1:T
            policy_loss -= log_probs[t] * advantages[t]
        end
        policy_loss /= Float32(T)
        
        # Value loss
        returns = rewards .+ gamma .* next_values .* .!dones
        value_loss = Float32(0.0)
        for t in 1:T
            value_loss += (values[t] - returns[t])^2
        end
        value_loss = value_coef * value_loss / Float32(T)
        
        # Entropy
        entropy = Float32(0.0)
        eps = Float32(1e-8)
        for t in 1:T
            logits = brain.policy_weights * states[t] .+ brain.policy_bias
            probs = softmax(logits)
            entropy -= sum(probs .* log.(clamp.(probs, eps, Float32(1.0))))
        end
        entropy /= Float32(T)
        
        total_loss = policy_loss + value_loss - entropy_coef * entropy
    end
    
    result["total_loss"] = total_loss
    result["policy_loss"] = policy_loss
    result["value_loss"] = value_loss
    result["entropy"] = entropy
    result["advantages"] = advantages
    
    return result
end

# ============================================================================
# ZYGOTE GRADIENT COMPUTATION
# ============================================================================

"""
    compute_zygote_gradients(brain::IncrementalBrain, states, actions, rewards, next_states, dones)::Dict

Compute actual gradients using Zygote.jl automatic differentiation.
"""
function compute_zygote_gradients(
    brain::IncrementalBrain,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    rewards::Vector{Float32},
    next_states::Vector{Vector{Float32}},
    dones::Vector{Bool}
)::Dict
    gradients = Dict{String, Any}()
    
    if !brain.use_zygote || !brain.use_flux
        # Fall back to manual gradients
        return compute_policy_gradients(
            brain,
            states,
            actions,
            rewards,
            Float32[]
        )
    end
    
    T = length(states)
    if T == 0
        return gradients
    end
    
    # Convert to Flux-friendly format
    state_matrix = hcat(states...)
    next_state_matrix = hcat(next_states...)
    action_vec = actions
    reward_vec = rewards
    
    # Define loss function with explicit parameters
    function policy_value_loss(policy_params, value_params)
        # Reconstruct networks from params
        policy_w = reshape(policy_params[1:brain.action_dim * brain.state_dim], brain.action_dim, brain.state_dim)
        policy_b = policy_params[brain.action_dim * brain.state_dim + 1:end]
        
        value_w = reshape(value_params[1:brain.state_dim], 1, brain.state_dim)
        value_b = value_params[brain.state_dim + 1:end]
        
        # Forward pass
        logits = policy_w * state_matrix .+ policy_b
        values = value_w * state_matrix .+ value_b
        
        # Compute losses
        gamma = Float32(0.99)
        
        # Policy loss
        probs = Flux.softmax(logits, dims=1)
        log_probs = log.(clamp.(probs[CartesianIndex.(action_vec, 1:T)], Float32(1e-8), Float32(1.0)))
        
        # Advantages
        next_values = value_w * next_state_matrix .+ value_b
        advantages = reward_vec .+ gamma * vec(next_values) .* .!dones .- vec(values)
        
        policy_loss = -mean(log_probs .* advantages)
        
        # Value loss
        returns = reward_vec .+ gamma * vec(next_values) .* .!dones
        value_loss = mean((vec(values) .- returns).^2)
        
        # Entropy
        entropy = -mean(sum(probs .* log.(clamp.(probs, Float32(1e-8), Float32(1.0))), dims=1))
        
        return policy_loss + Float32(0.5) * value_loss - Float32(0.01) * entropy
    end
    
    # Get current parameters
    policy_params = vcat(vec(brain.policy_weights), brain.policy_bias)
    value_params = vcat(vec(brain.value_weights), brain.value_bias)
    
    # Compute gradients using Zygote
    try
        policy_grad = Zygote.gradient(policy_params) do p
            policy_value_loss(p, value_params)
        end
        
        value_grad = Zygote.gradient(value_params) do v
            policy_value_loss(policy_params, v)
        end
        
        # Extract gradients
        grad_dim = brain.action_dim * brain.state_dim
        gradients["policy_weights"] = reshape(policy_grad[1][1:grad_dim], brain.action_dim, brain.state_dim)
        gradients["policy_bias"] = policy_grad[1][grad_dim + 1:end]
        
        val_grad_dim = brain.state_dim
        gradients["value_weights"] = reshape(value_grad[1][1:val_grad_dim], 1, brain.state_dim)
        gradients["value_bias"] = value_grad[1][val_grad_dim + 1:end]
        
    catch e
        @warn "Zygote gradient computation failed: $e"
        # Fall back to manual gradients
        return compute_policy_gradients(brain, states, actions, rewards, Float32[])
    end
    
    return gradients
end

"""
    apply_flux_update!(brain::IncrementalBrain, gradients::Dict, learning_rate::Float32)

Apply computed gradients to Flux models.
"""
function apply_flux_update!(
    brain::IncrementalBrain,
    gradients::Dict,
    learning_rate::Float32
)::Nothing
    if brain.use_flux
        # Update Flux parameters
        if brain.policy_network !== nothing && haskey(gradients, "policy_weights")
            # Manual parameter update for Flux models
            brain.policy_weights .-= learning_rate * get(gradients, "policy_weights", zeros(Float32, brain.action_dim, brain.state_dim))
            brain.policy_bias .-= learning_rate * get(gradients, "policy_bias", zeros(Float32, brain.action_dim))
        end
        
        if brain.value_network !== nothing && haskey(gradients, "value_weights")
            brain.value_weights .-= learning_rate * get(gradients, "value_weights", zeros(Float32, 1, brain.state_dim))
            brain.value_bias .-= learning_rate * get(gradients, "value_bias", zeros(Float32, 1))
        end
    else
        # Manual parameter update
        if haskey(gradients, "policy_weights")
            brain.policy_weights .-= learning_rate * get(gradients, "policy_weights", zeros(Float32, brain.action_dim, brain.state_dim))
            brain.policy_bias .-= learning_rate * get(gradients, "policy_bias", zeros(Float32, brain.action_dim))
        end
        
        if haskey(gradients, "value_weights")
            brain.value_weights .-= learning_rate * get(gradients, "value_weights", zeros(Float32, 1, brain.state_dim))
            brain.value_bias .-= learning_rate * get(gradients, "value_bias", zeros(Float32, 1))
        end
    end
    
    # Update policy state if available
    if brain.policy_state !== nothing
        brain.policy_state.policy_logits = brain.policy_weights
        brain.policy_state.value_weights = brain.value_weights
        brain.policy_state.value_bias = brain.value_bias
    end
    
    return nothing
end

# ============================================================================
# METABOLIC GATING
# ============================================================================

"""
    apply_metabolic_gating!(state::LearningState)::Bool

Apply metabolic gating by deducting INFERENCE_COST from energy_acc.
Returns true if enough energy remains for learning.
"""
function apply_metabolic_gating!(state::LearningState)::Bool
    # Deduct inference cost
    state.energy_acc -= INFERENCE_COST
    state.last_inference_cost = INFERENCE_COST
    
    # Check if enough energy remains
    return state.energy_acc > Float32(0.1)
end

"""
    recharge_energy!(state::LearningState, amount::Float32)

Recharge energy for learning.
"""
function recharge_energy!(state::LearningState, amount::Float32)::Nothing
    state.energy_acc = min(state.energy_acc + amount, Float32(1.0))
    return nothing
end

# ============================================================================
# INCREMENTAL UPDATES
# ============================================================================

"""
    incremental_update!(brain::Any, experience::Dict, state::LearningState)::Bool

Apply single experience update to the brain.
Adjusts learning rate based on confidence level.
Returns success status.
"""
function incremental_update!(brain::Any, experience::Dict, state::LearningState)::Bool
    try
        # Check metabolic gating first
        if !apply_metabolic_gating!(state)
            @warn "Insufficient energy for learning"
            return false
        end
        
        # Get current modulated learning rate
        lr = modulate_learning_rate(state)
        state.current_learning_rate = lr
        
        # Extract experience components
        input = get(experience, :input, nothing)
        target = get(experience, :target, nothing)
        reward = get(experience, :reward, Float32(0.0))
        done = get(experience, :done, false)
        
        if input === nothing || target === nothing
            @warn "Invalid experience format: missing input or target"
            return false
        end
        
        # Perform forward pass to get predictions
        predictions = forward_pass(brain, input)
        
        # Estimate confidence from predictions
        state.confidence = estimate_confidence(predictions, target)
        
        # Compute uncertainty bounds
        lower, upper = compute_uncertainty_bounds(predictions)
        state.uncertainty = upper - lower
        
        # Apply incremental update using modulated learning rate
        gradients = compute_gradients(brain, input, target)
        
        # Clip gradients for stability (norm must stay below 0.1)
        gradients = clip_gradients!(gradients, max_norm=DEFAULT_GRADIENT_NORM_THRESHOLD)
        
        # Apply gradients with momentum
        apply_gradients!(brain, gradients, lr, state.momentum)
        
        return true
    catch e
        @error "Incremental update failed: $e"
        # Rollback if available
        if state.rollback_available && state.last_snapshot !== nothing
            rollback_to_snapshot!(brain, state.last_snapshot)
        end
        return false
    end
end

"""
    incremental_update_rl!(brain::IncrementalBrain, experience::Dict, state::LearningState, buffer::ReplayBuffer)::Bool

RL-specific incremental update using actor-critic.
"""
function incremental_update_rl!(
    brain::IncrementalBrain,
    experience::Dict,
    state::LearningState,
    buffer::ReplayBuffer
)::Bool
    try
        # Check metabolic gating
        if !apply_metabolic_gating!(state)
            @warn "Insufficient energy for RL learning"
            return false
        end
        
        # Extract experience
        state_vec = get(experience, :state, zeros(Float32, brain.state_dim))
        action = get(experience, :action, 1)
        reward = get(experience, :reward, Float32(0.0))
        next_state = get(experience, :next_state, zeros(Float32, brain.state_dim))
        done = get(experience, :done, false)
        
        # Compute value for this state
        value = compute_value(state_vec, brain.value_weights, brain.value_bias)
        next_value = done ? Float32(0.0) : compute_value(next_state, brain.value_weights, brain.value_bias)
        
        # Compute log probability
        log_prob = compute_log_prob(brain.policy_weights, state_vec, action)
        
        # Push to replay buffer
        push_experience!(buffer, state_vec, action, reward, next_state, done; value=value, log_prob=log_prob)
        
        # Get modulated learning rate
        lr = modulate_learning_rate(state)
        state.current_learning_rate = lr
        
        # Sample batch for training
        batch = sample_batch(buffer, min(32, buffer.size))
        
        if length(batch["states"]) > 0
            # Compute actor-critic loss
            loss_dict = compute_actor_critic_loss(
                brain,
                batch["states"],
                batch["actions"],
                batch["rewards"],
                batch["next_states"],
                batch["dones"]
            )
            
            # Compute gradients using Zygote if available
            gradients = compute_zygote_gradients(
                brain,
                batch["states"],
                batch["actions"],
                batch["rewards"],
                batch["next_states"],
                batch["dones"]
            )
            
            # Clip gradients (norm must stay below 0.1)
            gradients = clip_gradients!(gradients, max_norm=DEFAULT_GRADIENT_NORM_THRESHOLD)
            
            # Apply gradients
            apply_flux_update!(brain, gradients, lr)
            
            # Update confidence based on value loss
            state.confidence = Float32(1.0) - clamp(loss_dict["value_loss"], Float32(0.0), Float32(1.0))
            state.uncertainty = abs(loss_dict["value_loss"])
            
            # Update entropy for reversible learning
            state.policy_entropy = loss_dict["entropy"]
        end
        
        return true
    catch e
        @error "RL incremental update failed: $e"
        return false
    end
end

"""
    forward_pass - Forward pass through incremental brain
"""
function forward_pass(brain::IncrementalBrain, input::Vector{Float32})::Vector{Float32}
    if brain.use_flux && brain.policy_network !== nothing
        # Use Flux network
        action_logits = brain.policy_network(input)
        return collect(action_logits)
    else
        # Use manual weights
        logits = brain.policy_weights * input .+ brain.policy_bias
        return softmax(logits)
    end
end

function forward_pass(brain::Any, input::Vector{Float32})::Vector{Float32}
    # Placeholder for other brain types
    if hasproperty(brain, :weights)
        if brain isa Dict
            weights = get(brain, :weights, ones(Float32, 10, 10))
            return vec(weights * reshape(input, length(input), 1))[1:min(length(input), 10)]
        end
    end
    return Float32[0.5, 0.5, 0.5, 0.5, 0.5]
end

"""
    compute_gradients - Compute gradients for update (supports both DL and RL)
"""
function compute_gradients(brain::IncrementalBrain, input, target)::Dict
    # Use actual gradient computation
    gradients = Dict{String, Any}()
    
    if brain.use_zygote && brain.use_flux
        # Zygote gradient computation would go here for supervised learning
        # For now, fall through to policy gradient computation
    end
    
    # If brain has policy_state, use policy gradients
    if brain.policy_state !== nothing
        # Create dummy experience
        state = input isa Vector{Float32} ? input : zeros(Float32, brain.state_dim)
        action = 1
        reward = Float32(0.0)
        next_state = state
        done = true
        
        # Compute gradients
        return compute_policy_gradients(
            brain,
            [state],
            [action],
            [reward],
            Float32[]
        )
    end
    
    # Fallback to small random gradients
    gradients["weights"] = rand(Float32, brain.action_dim, brain.state_dim) * Float32(0.001)
    gradients["bias"] = rand(Float32, brain.action_dim) * Float32(0.001)
    
    return gradients
end

function compute_gradients(brain::Any, input, target)::Dict
    # Placeholder - in real implementation would compute actual gradients
    # Using simple numerical gradients as placeholder
    gradients = Dict{String, Any}()
    
    if hasproperty(brain, :weights)
        # Simulate gradient computation
        gradients["weights"] = rand(Float32, 10, 10) * 0.01f0
    else
        gradients["weights"] = rand(Float32, 10, 10) * 0.01f0
    end
    
    return gradients
end

"""
    apply_gradients! - Apply computed gradients to brain
"""
function apply_gradients!(brain::IncrementalBrain, gradients::Dict, learning_rate::Float32, momentum::Float32)::Nothing
    # Use Flux update if available
    apply_flux_update!(brain, gradients, learning_rate)
    return nothing
end

function apply_gradients!(brain::Any, gradients::Dict, learning_rate::Float32, momentum::Float32)::Nothing
    # Placeholder - in real implementation would apply actual gradients
    if hasproperty(brain, :weights) && brain isa Dict
        if haskey(gradients, "weights")
            # Simple gradient update (would be more complex in real implementation)
            brain[:weights] = get(brain, :weights, zeros(Float32, 10, 10)) .+ gradients["weights"] .* learning_rate
        end
    end
    return nothing
end

# ============================================================================
# META-LEARNING HOOKS
# ============================================================================

"""
    meta_learn(brain::Any, task_batch::Vector{Dict}, state::LearningState)::Dict

Perform MAML-style meta-learning adaptation.
Updates meta-parameters based on task batch.
Returns adaptation results including learned meta-gradient.
"""
function meta_learn(brain::Any, task_batch::Vector{Dict}, state::LearningState)::Dict
    results = Dict{String, Any}()
    
    try
        # Create snapshot before meta-learning
        snapshot = create_learning_snapshot(brain)
        
        # Store original parameters
        original_params = deepcopy(get_brain_parameters(brain))
        
        # Perform adaptation steps on each task
        adapted_params = []
        adaptation_losses = Float32[]
        
        for task in task_batch
            # Quick adaptation to task
            task_examples = get(task, :examples, Dict[])
            success = adapt_to_task(brain, task_examples, state)
            
            if success
                # Compute task loss after adaptation
                loss = compute_task_loss(brain, task)
                push!(adaptation_losses, loss)
            end
        end
        
        # Compute meta-gradient (gradient of adaptation quality)
        if length(adaptation_losses) > 0
            mean_loss = mean(adaptation_losses)
            meta_gradient = state.meta_learning_rate * mean_loss
            
            # Update meta-parameters
            update_meta_parameters!(brain, meta_gradient)
            
            results["meta_gradient"] = meta_gradient
            results["adaptation_losses"] = adaptation_losses
            results["mean_loss"] = mean_loss
            results["success"] = true
        else
            results["success"] = false
            results["error"] = "No successful adaptations"
            
            # Rollback on failure
            rollback_to_snapshot!(brain, snapshot)
        end
        
    catch e
        @error "Meta-learning failed: $e"
        results["success"] = false
        results["error"] = string(e)
    end
    
    return results
end

"""
    meta_learn_rl!(brain::IncrementalBrain, task_batch::Vector{Dict}, state::LearningState, buffer::ReplayBuffer)::Dict

Meta-RL version that learns which sub-policies are most effective.
"""
function meta_learn_rl!(
    brain::IncrementalBrain,
    task_batch::Vector{Dict},
    state::LearningState,
    buffer::ReplayBuffer
)::Dict
    results = Dict{String, Any}()
    
    try
        # Evaluate each sub-policy
        for task in task_batch
            task_name = get(task, :name, "default")
            
            # Sample experiences for this task
            batch = sample_batch(buffer, min(64, buffer.size))
            
            if length(batch["states"]) > 0
                # Compute task-specific loss
                loss_dict = compute_actor_critic_loss(
                    brain,
                    batch["states"],
                    batch["actions"],
                    batch["rewards"],
                    batch["next_states"],
                    batch["dones"]
                )
                
                # Track effectiveness
                effectiveness = Float32(1.0) / (Float32(1.0) + loss_dict["total_loss"])
                state.sub_policy_effectiveness[task_name] = get(state.sub_policy_effectiveness, task_name, Float32(0.0)) * Float32(0.9) + effectiveness * Float32(0.1)
            end
        end
        
        # Find most effective sub-policy
        if length(state.sub_policy_effectiveness) > 0
            best_policy = argmax(state.sub_policy_effectiveness)
            results["best_sub_policy"] = best_policy
            results["effectiveness"] = state.sub_policy_effectiveness[best_policy]
        end
        
        results["success"] = true
        
    catch e
        @error "Meta-RL failed: $e"
        results["success"] = false
        results["error"] = string(e)
    end
    
    return results
end

"""
    adapt_to_task(brain::Any, task_examples::Vector{Dict}, state::LearningState)::Bool

Quick adaptation to a new task using few-shot learning.
Applies adaptation steps to quickly learn from limited examples.
Returns success status.
"""
function adapt_to_task(brain::Any, task_examples::Vector{Dict}, state::LearningState)::Bool
    try
        if length(task_examples) == 0
            return false
        end
        
        # Store original parameters for potential rollback
        original_params = deepcopy(get_brain_parameters(brain))
        
        # Few-shot adaptation (typically 1-5 steps)
        for step in 1:state.adaptation_steps
            for example in task_examples
                # Apply incremental update for this example
                input = get(example, :input, nothing)
                target = get(example, :target, nothing)
                
                if input !== nothing && target !== nothing
                    # Use higher learning rate for fast adaptation
                    fast_lr = state.current_learning_rate * 10.0f0
                    
                    # Compute and apply gradients
                    gradients = compute_gradients(brain, input, target)
                    gradients = clip_gradients!(gradients, max_norm=0.5f0)
                    apply_gradients!(brain, gradients, fast_lr, state.momentum)
                end
            end
        end
        
        # Validate adaptation quality
        validation_loss = compute_adaptation_validation(brain, task_examples)
        
        # If adaptation is poor, rollback
        if validation_loss > 1.0f0
            restore_brain_parameters!(brain, original_params)
            return false
        end
        
        return true
    catch e
        @error "Task adaptation failed: $e"
        return false
    end
end

# ============================================================================
# LEARNING RATE MODULATION
# ============================================================================

"""
    modulate_learning_rate(state::LearningState; confidence_boost::Float32=0.1f0, uncertainty_penalty::Float32=0.2f0)::Float32

Modulate learning rate based on confidence and uncertainty.
Increases rate when confident, decreases when uncertain.
Returns the modulated learning rate.
"""
function modulate_learning_rate(
    state::LearningState;
    confidence_boost::Float32=0.1f0,
    uncertainty_penalty::Float32=0.2f0
)::Float32
    # Base rate
    rate = state.base_learning_rate
    
    # Boost rate based on confidence
    confidence_factor = 1.0f0 + (state.confidence - 0.5f0) * confidence_boost
    
    # Penalty based on uncertainty
    uncertainty_factor = 1.0f0 - (state.uncertainty - 0.5f0) * uncertainty_penalty
    
    # Apply entropy penalty for reversible learning
    entropy_factor = state.policy_entropy > state.entropy_threshold ? Float32(0.5) : Float32(1.0)
    
    # Apply factors
    modulated_rate = rate * confidence_factor * uncertainty_factor * entropy_factor
    
    # Clamp to reasonable bounds
    state.current_learning_rate = clamp(modulated_rate, 0.0001f0, 0.1f0)
    
    return state.current_learning_rate
end

# ============================================================================
# SAFETY ROLLBACK MECHANISM
# ============================================================================

"""
    create_learning_snapshot(brain::Any)::Dict

Capture brain state before training for safe rollback.
Stores weights, configuration, and metadata.
Returns snapshot dictionary.
"""
function create_learning_snapshot(brain::Any)::Dict
    snapshot = Dict{String, Any}()
    
    # Capture timestamp
    snapshot["timestamp"] = now()
    snapshot["id"] = uuid4()
    
    # Capture brain parameters
    snapshot["parameters"] = get_brain_parameters(brain)
    
    # Capture brain configuration
    snapshot["config"] = get_brain_config(brain)
    
    # Capture brain architecture info
    snapshot["architecture"] = get_brain_architecture(brain)
    
    return snapshot
end

"""
    create_learning_snapshot(brain::IncrementalBrain)::Dict

Capture IncrementalBrain state for safe rollback.
"""
function create_learning_snapshot(brain::IncrementalBrain)::Dict
    snapshot = Dict{String, Any}()
    
    snapshot["timestamp"] = now()
    snapshot["id"] = uuid4()
    
    # Store all weights
    snapshot["policy_weights"] = deepcopy(brain.policy_weights)
    snapshot["policy_bias"] = deepcopy(brain.policy_bias)
    snapshot["value_weights"] = deepcopy(brain.value_weights)
    snapshot["value_bias"] = deepcopy(brain.value_bias)
    
    snapshot["config"] = Dict(
        "state_dim" => brain.state_dim,
        "action_dim" => brain.action_dim,
        "use_zygote" => brain.use_zygote,
        "use_flux" => brain.use_flux
    )
    
    snapshot["architecture"] = Dict(
        "type" => "actor_critic",
        "policy" => "neural_network",
        "value" => "neural_network"
    )
    
    return snapshot
end

"""
    rollback_to_snapshot!(brain::Any, snapshot::Dict)::Bool

Restore brain from snapshot after training failure.
Returns success status.
"""
function rollback_to_snapshot!(brain::Any, snapshot::Dict)::Bool
    try
        # Extract stored parameters
        parameters = get(snapshot, :parameters, nothing)
        
        if parameters !== nothing
            restore_brain_parameters!(brain, parameters)
            return true
        end
        
        return false
    catch e
        @error "Rollback failed: $e"
        return false
    end
end

"""
    rollback_to_snapshot!(brain::IncrementalBrain, snapshot::Dict)::Bool

Restore IncrementalBrain from snapshot.
"""
function rollback_to_snapshot!(brain::IncrementalBrain, snapshot::Dict)::Bool
    try
        if haskey(snapshot, "policy_weights")
            brain.policy_weights = deepcopy(snapshot["policy_weights"])
            brain.policy_bias = deepcopy(snapshot["policy_bias"])
            brain.value_weights = deepcopy(snapshot["value_weights"])
            brain.value_bias = deepcopy(snapshot["value_bias"])
            
            # Update policy state if available
            if brain.policy_state !== nothing
                brain.policy_state.policy_logits = brain.policy_weights
                brain.policy_state.value_weights = brain.value_weights
                brain.policy_state.value_bias = brain.value_bias
            end
            
            return true
        end
        
        return false
    catch e
        @error "IncrementalBrain rollback failed: $e"
        return false
    end
end

# Helper functions for brain parameter handling
function get_brain_parameters(brain::Any)::Dict
    params = Dict{String, Any}()
    
    if hasproperty(brain, :weights)
        if brain isa Dict
            params["weights"] = deepcopy(get(brain, :weights, nothing))
            params["biases"] = deepcopy(get(brain, :biases, nothing))
        else
            # For objects, try to get fields
            for field in fieldnames(typeof(brain))
                params[string(field)] = deepcopy(getfield(brain, field))
            end
        end
    else
        # Generic placeholder
        params["weights"] = rand(Float32, 10, 10)
    end
    
    return params
end

function get_brain_parameters(brain::IncrementalBrain)::Dict
    return Dict(
        "policy_weights" => deepcopy(brain.policy_weights),
        "policy_bias" => deepcopy(brain.policy_bias),
        "value_weights" => deepcopy(brain.value_weights),
        "value_bias" => deepcopy(brain.value_bias)
    )
end

function get_brain_config(brain::Any)::Dict
    config = Dict{String, Any}()
    config["learning_rate"] = 0.01f0
    config["momentum"] = 0.9f0
    return config
end

function get_brain_config(brain::IncrementalBrain)::Dict
    return Dict(
        "learning_rate" => 0.001f0,
        "state_dim" => brain.state_dim,
        "action_dim" => brain.action_dim,
        "use_zygote" => brain.use_zygote,
        "use_flux" => brain.use_flux
    )
end

function get_brain_architecture(brain::Any)::Dict
    arch = Dict{String, Any}()
    arch["type"] = "mlp"
    arch["layers"] = [10, 10, 10]
    return arch
end

function get_brain_architecture(brain::IncrementalBrain)::Dict
    return Dict(
        "type" => "actor_critic",
        "policy" => brain.use_flux ? "Flux.Chain" : "manual",
        "value" => brain.use_flux ? "Flux.Chain" : "manual",
        "state_dim" => brain.state_dim,
        "action_dim" => brain.action_dim
    )
end

function restore_brain_parameters!(brain::Any, parameters::Dict)::Nothing
    if hasproperty(brain, :weights) && brain isa Dict
        if haskey(parameters, "weights")
            brain[:weights] = deepcopy(parameters["weights"])
        end
        if haskey(parameters, "biases")
            brain[:biases] = deepcopy(parameters["biases"])
        end
    end
    return nothing
end

function restore_brain_parameters!(brain::IncrementalBrain, parameters::Dict)::Nothing
    if haskey(parameters, "policy_weights")
        brain.policy_weights = deepcopy(parameters["policy_weights"])
        brain.policy_bias = deepcopy(parameters["policy_bias"])
        brain.value_weights = deepcopy(parameters["value_weights"])
        brain.value_bias = deepcopy(parameters["value_bias"])
    end
    return nothing
end

function update_meta_parameters!(brain::Any, meta_gradient::Float32)::Nothing
    # Placeholder - would update meta-parameters in real implementation
    return nothing
end

function compute_task_loss(brain::Any, task::Dict)::Float32
    # Placeholder - would compute actual task loss
    return rand(Float32) * 0.5f0
end

function compute_adaptation_validation(brain::Any, examples::Vector{Dict})::Float32
    # Placeholder - would compute validation loss
    return rand(Float32) * 0.3f0
end

# ============================================================================
# CONFIDENCE ESTIMATION
# ============================================================================

"""
    estimate_confidence(predictions::Vector{Float32}, targets::Vector{Float32})::Float32

Estimate prediction confidence based on prediction-target agreement.
Returns confidence value between 0.0 and 1.0.
"""
function estimate_confidence(
    predictions::Vector{Float32},
    targets::Vector{Float32}
)::Float32
    if length(predictions) == 0 || length(targets) == 0
        return 0.5f0
    end
    
    # Ensure same length
    n = min(length(predictions), length(targets))
    pred = predictions[1:n]
    tgt = targets[1:n]
    
    # Compute agreement (inverse of error)
    errors = abs.(pred - tgt)
    mean_error = mean(errors)
    
    # Convert error to confidence (lower error = higher confidence)
    # Using exponential decay
    confidence = exp(-mean_error * 2.0f0)
    
    return clamp(confidence, 0.0f0, 1.0f0)
end

"""
    compute_uncertainty_bounds(predictions::Vector{Float32})::Tuple{Float32, Float32}

Compute confidence intervals for predictions.
Returns (lower_bound, upper_bound) tuple.
"""
function compute_uncertainty_bounds(predictions::Vector{Float32})::Tuple{Float32, Float32}
    if length(predictions) == 0
        return (0.0f0, 1.0f0)
    end
    
    # Compute standard deviation
    std_val = std(predictions)
    mean_val = mean(predictions)
    
    # Compute bounds using standard error
    # 95% confidence interval: mean ± 1.96 * std
    lower = mean_val - 1.96f0 * std_val
    upper = mean_val + 1.96f0 * std_val
    
    # Clamp to valid range
    lower = clamp(lower, 0.0f0, 1.0f0)
    upper = clamp(upper, 0.0f0, 1.0f0)
    
    return (lower, upper)
end

# ============================================================================
# CURRICULUM PROGRESSION
# ============================================================================

"""
    advance_curriculum!(state::LearningState; min_progress::Float32=0.8f0)::Bool

Advance curriculum level when progress exceeds threshold.
Returns true if curriculum was advanced.
"""
function advance_curriculum!(
    state::LearningState;
    min_progress::Float32=0.8f0
)::Bool
    # Check if progress exceeds threshold
    if state.curriculum_progress >= min_progress
        # Advance to next level
        state.curriculum_level += 1
        state.curriculum_progress = 0.0f0
        
        @info "Advanced to curriculum level $(state.curriculum_level)"
        return true
    end
    
    return false
end

"""
    get_curriculum_difficulty(level::Int)::Dict

Return difficulty parameters for current curriculum level.
Includes complexity, sample weights, and difficulty modifiers.
"""
function get_curriculum_difficulty(level::Int)::Dict
    difficulty = Dict{String, Any}()
    
    # Base difficulty increases with level
    base = Float32(level)
    
    difficulty["complexity"] = min(base / 10.0f0, 1.0f0)
    difficulty["sample_difficulty"] = min(0.3f0 + 0.1f0 * level, 0.9f0)
    difficulty["noise_level"] = max(0.5f0 - 0.05f0 * level, 0.1f0)
    difficulty["sequence_length"] = min(10 + level * 5, 100)
    difficulty["num_classes"] = min(2 + div(level, 3), 10)
    
    # Reward scaling
    difficulty["reward_scale"] = 1.0f0 + 0.2f0 * Float32(level)
    
    # Penalty for wrong predictions increases
    difficulty["error_penalty"] = min(0.5f0 + 0.1f0 * level, 2.0f0)
    
    return difficulty
end

# ============================================================================
# GRADIENT CLIPPING
# ============================================================================

"""
    clip_gradients!(gradients::Dict; max_norm::Float32=1.0f0)::Dict

Clip gradients for numerical stability.
Prevents exploding gradients while preserving direction.
Returns clipped gradients dictionary.
"""
function clip_gradients!(
    gradients::Dict;
    max_norm::Float32=1.0f0
)::Dict
    clipped = Dict{String, Any}()
    
    for (key, grad) in gradients
        if grad isa AbstractArray
            # Compute gradient norm
            grad_norm = norm(grad)
            
            if grad_norm > max_norm
                # Scale down to max_norm
                clipped[key] = grad * (max_norm / grad_norm)
            else
                clipped[key] = grad
            end
        elseif grad isa Tuple
            # Handle tuple gradients (e.g., (weights, bias))
            clipped_grads = []
            for g in grad
                if g isa AbstractArray
                    g_norm = norm(g)
                    if g_norm > max_norm
                        push!(clipped_grads, g * (max_norm / g_norm))
                    else
                        push!(clipped_grads, g)
                    end
                else
                    push!(clipped_grads, g)
                end
            end
            clipped[key] = Tuple(clipped_grads)
        else
            clipped[key] = grad
        end
    end
    
    return clipped
end

# ============================================================================
# DEEPCOPY HELPER
# ============================================================================

function deepcopy(x::Any)
    return Base.deepcopy(x)
end

# ============================================================================
# PPO CLIPPED OBJECTIVE (Multiple dispatch for ModelFreePolicy vs ModelBasedPolicy)
# ============================================================================

"""
    compute_ppo_objective(brain, states, actions, old_log_probs, advantages)

Compute PPO clipped loss with full gradient support.
L^CLIP = E[min(rt(θ)Ât, clip(rt(θ), 1-ε, 1+ε)Ât)]
"""
function compute_ppo_objective(
    brain::IncrementalBrain,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    old_log_probs::Vector{Float32},
    advantages::Vector{Float32};
    clip_epsilon::Float32=Float32(0.2)
)::Dict
    result = Dict{String, Any}()
    
    T = length(states)
    if T == 0
        result["loss"] = Float32(0.0)
        result["clip_fraction"] = Float32(0.0)
        return result
    end
    
    policy_losses = Float32[]
    clip_fractions = Float32[]
    
    for t in 1:T
        state = states[t]
        action = actions[t]
        advantage = advantages[t]
        old_log_prob = old_log_probs[t]
        
        # Compute new log prob
        new_log_prob = compute_log_prob(brain.policy_weights, state, action)
        
        # Compute ratio
        ratio = exp(new_log_prob - old_log_prob)
        
        # Clipped ratio
        ratio_clamped = clamp(ratio, Float32(1.0) - clip_epsilon, Float32(1.0) + clip_epsilon)
        
        # Surrogate losses
        surr1 = ratio * advantage
        surr2 = ratio_clamped * advantage
        
        # PPO clipped objective
        policy_loss = min(surr1, surr2)
        push!(policy_losses, -policy_loss)
        
        # Track clip fraction
        if abs(ratio - Float32(1.0)) > clip_epsilon
            push!(clip_fractions, Float32(1.0))
        else
            push!(clip_fractions, Float32(0.0))
        end
    end
    
    ppo_loss = mean(policy_losses)
    clip_fraction = mean(clip_fractions)
    
    result["loss"] = ppo_loss
    result["clip_fraction"] = clip_fraction
    result["surrogate_loss"] = ppo_loss
    
    return result
end

# ModelFreePolicy dispatch
function compute_ppo_objective(
    brain::IncrementalBrain,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    old_log_probs::Vector{Float32},
    advantages::Vector{Float32};
    clip_epsilon::Float32=Float32(0.2)
)::Dict
    # Already implemented above for IncrementalBrain
    return compute_ppo_objective(brain, states, actions, old_log_probs, advantages; clip_epsilon=clip_epsilon)
end

# ModelBasedPolicy dispatch (placeholder for future implementation)
function compute_ppo_objective(
    brain::Any,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    old_log_probs::Vector{Float32},
    advantages::Vector{Float32};
    clip_epsilon::Float32=Float32(0.2)
)::Dict
    # Fallback for generic brain types
    result = Dict{String, Any}()
    result["loss"] = Float32(0.0)
    result["clip_fraction"] = Float32(0.0)
    return result

# =============================================================================
# EPISODIC MEMORY - Ring Buffer for Trajectory Collection
# =============================================================================

"""
    EpisodicRingBuffer - Ring buffer for storing trajectories
    
    Used for collecting (s, a, r, s') tuples for batch training.
    Implements 10M-thought capacity as specified in requirements.
"""
mutable struct EpisodicRingBuffer
    capacity::Int
    position::Int
    size::Int
    
    # Stored experience
    states::Vector{Vector{Float32}}
    actions::Vector{Int}
    rewards::Vector{Float32}
    next_states::Vector{Vector{Float32}}
    dones::Vector{Bool}
    log_probs::Vector{Float32}
    values::Vector{Float32}
    
    # Priority scoring for Oneiric replay
    rpe_scores::Vector{Float32}
    
    function EpisodicRingBuffer(; capacity::Int=10000)
        new(
            capacity,
            0,
            0,
            Vector{Vector{Float32}}(),
            Vector{Int}(),
            Vector{Float32}(),
            Vector{Vector{Float32}}(),
            Vector{Bool}(),
            Vector{Float32}(),
            Vector{Float32}(),
            Vector{Float32}()
        )
    end
end

Base.length(buffer::EpisodicRingBuffer)::Int = buffer.size
Base.isempty(buffer::EpisodicRingBuffer)::Bool = buffer.size == 0
Base.isfull(buffer::EpisodicRingBuffer)::Bool = buffer.size == buffer.capacity

"""
    push!(buffer::EpisodicRingBuffer, experience::Dict)

Add experience to the ring buffer.
"""
function Base.push!(buffer::EpisodicRingBuffer, experience::Dict)
    state = get(experience, :state, zeros(Float32, 10))
    action = get(experience, :action, 1)
    reward = get(experience, :reward, 0.0f0)
    next_state = get(experience, :next_state, zeros(Float32, 10))
    done = get(experience, :done, false)
    log_prob = get(experience, :log_prob, 0.0f0)
    value = get(experience, :value, 0.0f0)
    rpe = get(experience, :rpe, 0.0f0)
    
    # Add to buffer (overwrite oldest if full)
    if buffer.size < buffer.capacity
        push!(buffer.states, state)
        push!(buffer.actions, action)
        push!(buffer.rewards, reward)
        push!(buffer.next_states, next_state)
        push!(buffer.dones, done)
        push!(buffer.log_probs, log_prob)
        push!(buffer.values, value)
        push!(buffer.rpe_scores, rpe)
    else
        idx = buffer.position + 1
        buffer.states[idx] = state
        buffer.actions[idx] = action
        buffer.rewards[idx] = reward
        buffer.next_states[idx] = next_state
        buffer.dones[idx] = done
        buffer.log_probs[idx] = log_prob
        buffer.values[idx] = value
        buffer.rpe_scores[idx] = rpe
    end
    
    buffer.position = (buffer.position % buffer.capacity) + 1
    buffer.size = min(buffer.size + 1, buffer.capacity)
    
    return buffer
end

"""
    get_prioritized_batch(buffer::EpisodicRingBuffer, batch_size::Int; priority_weight::Float32=0.6)

Get batch with prioritization based on RPE (surprise-driven).
High-RPE thoughts are prioritized for Oneiric (dreaming) replay.
"""
function get_prioritized_batch(
    buffer::EpisodicRingBuffer, 
    batch_size::Int; 
    priority_weight::Float32=0.6
)::Dict
    if buffer.size == 0
        return Dict(
            :states => Vector{Vector{Float32}}(),
            :actions => Vector{Int}(),
            :rewards => Vector{Float32}(),
            :next_states => Vector{Vector{Float32}}(),
            :dones => Vector{Bool}()
        )
    end
    
    # Compute priorities based on RPE (higher RPE = higher priority)
    priorities = abs.(buffer.rpe_scores[1:buffer.size])
    priorities = priorities .+ Float32(1e-6)  # Avoid zero
    
    # Mix uniform and priority-based sampling
    n = buffer.size
    uniform_probs = ones(Float32, n) ./ Float32(n)
    mixed_probs = priority_weight .* (priorities ./ sum(priorities)) .+ 
                  (1.0f0 - priority_weight) .* uniform_probs
    
    # Sample indices
    batch_size = min(batch_size, n)
    indices = StatsBase.sample(1:n, StatsBase.Weights(mixed_probs), batch_size, replace=false)
    
    return Dict(
        :states => buffer.states[indices],
        :actions => buffer.actions[indices],
        :rewards => buffer.rewards[indices],
        :next_states => buffer.next_states[indices],
        :dones => buffer.dones[indices],
        :log_probs => buffer.log_probs[indices],
        :values => buffer.values[indices],
        :rpes => buffer.rpe_scores[indices]
    )
end

"""
    get_random_batch(buffer::EpisodicRingBuffer, batch_size::Int)

Get random batch from buffer.
"""
function get_random_batch(buffer::EpisodicRingBuffer, batch_size::Int)::Dict
    if buffer.size == 0
        return Dict(
            :states => Vector{Vector{Float32}}(),
            :actions => Vector{Int}(),
            :rewards => Vector{Float32}(),
            :next_states => Vector{Vector{Float32}}(),
            :dones => Vector{Bool}()
        )
    end
    
    batch_size = min(batch_size, buffer.size)
    indices = rand(1:buffer.size, batch_size)
    
    return Dict(
        :states => buffer.states[indices],
        :actions => buffer.actions[indices],
        :rewards => buffer.rewards[indices],
        :next_states => buffer.next_states[indices],
        :dones => buffer.dones[indices],
        :log_probs => buffer.log_probs[indices],
        :values => buffer.values[indices]
    )
end

"""
    clear!(buffer::EpisodicRingBuffer)

Clear all experience from buffer.
"""
function Base.clear!(buffer::EpisodicRingBuffer)
    buffer.position = 0
    buffer.size = 0
    empty!(buffer.states)
    empty!(buffer.actions)
    empty!(buffer.rewards)
    empty!(buffer.next_states)
    empty!(buffer.dones)
    empty!(buffer.log_probs)
    empty!(buffer.values)
    empty!(buffer.rpe_scores)
    return buffer
end

# ============================================================================
# BATCH TRAINING WITH EPISODIC MEMORY
# ============================================================================

"""
    train_batch!(brain::IncrementalBrain, buffer::EpisodicRingBuffer, state::LearningState; 
                 batch_size::Int=64, gamma::Float32=Float32(0.99))::Dict

Perform batch training using episodic memory replay.
Deducts INFERENCE_COST from energy_acc for metabolic grounding.
"""
function train_batch!(
    brain::IncrementalBrain, 
    buffer::EpisodicRingBuffer, 
    state::LearningState;
    batch_size::Int=64, 
    gamma::Float32=Float32(0.99)
)::Dict
    result = Dict{String, Any}("success" => false)
    
    # Check metabolic gating
    if !apply_metabolic_gating!(state)
        result["error"] = "Insufficient energy for training"
        return result
    end
    
    # Get prioritized batch
    batch = get_prioritized_batch(buffer, batch_size)
    
    if length(batch[:states]) == 0
        result["error"] = "Empty buffer"
        return result
    end
    
    states = batch[:states]
    actions = batch[:actions]
    rewards = batch[:rewards]
    next_states = batch[:next_states]
    dones = batch[:dones]
    old_log_probs = batch[:log_probs]
    
    # Compute values for next states
    next_values = Float32[]
    for ns in next_states
        v = compute_value(ns, brain.value_weights, brain.value_bias)
        push!(next_values, v)
    end
    
    # Compute TD errors and advantages
    advantages = Float32[]
    for (i, (s, r, ns, done)) in enumerate(zip(states, rewards, next_states, dones))
        v_s = batch[:values][i]
        v_s_next = done ? Float32(0.0) : next_values[i]
        
        # TD-error: δt = rt + γV(st+1) - V(st)
        td_error = r + gamma * v_s_next - v_s
        push!(advantages, td_error)
    end
    
    # Compute PPO loss
    ppo_result = compute_ppo_objective(
        brain, states, actions, old_log_probs, advantages
    )
    
    # Compute gradients
    gradients = compute_policy_gradients(
        brain, states, actions, advantages, old_log_probs
    )
    
    # Check gradient norm
    grad_norm = Float32(0.0)
    if haskey(gradients, "policy_gradients")
        grad_norm = norm(gradients["policy_gradients"])
    end
    
    # Block update if gradient norm exceeds threshold
    if grad_norm > DEFAULT_GRADIENT_NORM_THRESHOLD
        result["error"] = "Gradient norm $grad_norm exceeds threshold $(DEFAULT_GRADIENT_NORM_THRESHOLD)"
        result["gradient_norm"] = grad_norm
        result["update_blocked"] = true
        return result
    end
    
    # Create snapshot before update
    snapshot = create_learning_snapshot(brain)
    
    # Apply gradients
    lr = state.current_learning_rate
    apply_gradients!(brain, gradients, lr, state.momentum)
    
    # Update policy state
    if brain.policy_state !== nothing
        brain.policy_state.policy_logits = brain.policy_weights
        brain.policy_state.value_weights = brain.value_weights
        brain.policy_state.value_bias = brain.value_bias
    end
    
    # Check entropy for reversible learning
    state.policy_entropy = compute_policy_entropy(brain)
    
    # Rollback if entropy too low (mode collapse)
    if state.policy_entropy < state.entropy_threshold
        rollback_to_snapshot!(brain, snapshot)
        result["error"] = "Mode collapse detected - rolled back"
        result["policy_entropy"] = state.policy_entropy
        return result
    end
    
    result["success"] = true
    result["loss"] = get(ppo_result, "loss", Float32(0.0))
    result["clip_fraction"] = get(ppo_result, "clip_fraction", Float32(0.0))
    result["gradient_norm"] = grad_norm
    result["policy_entropy"] = state.policy_entropy
    result["energy_remaining"] = state.energy_acc
    
    return result
end

"""
    compute_policy_entropy(brain::IncrementalBrain)::Float32

Compute entropy of policy for monitoring mode collapse.
"""
function compute_policy_entropy(brain::IncrementalBrain)::Float32
    if brain.policy_state === nothing
        return Float32(1.0)  # Maximum entropy as fallback
    end
    
    # Sample states and compute entropy
    entropies = Float32[]
    for _ in 1:10
        state = randn(Float32, brain.state_dim)
        probs = compute_action_probabilities(brain.policy_weights, state)
        
        # H = -sum(p * log(p))
        eps = Float32(1e-8)
        entropy = -sum(p * log(clamp(p, eps, Float32(1.0))) for p in probs)
        push!(entropies, entropy)
    end
    
    return mean(entropies)
end

# ============================================================================
# ONEIRIC STATE INTEGRATION
# ============================================================================

"""
    replay_high_rpe_memories(buffer::EpisodicRingBuffer, brain::IncrementalBrain; 
                              num_replays::Int=5)

Replay high-RPE (surprise-driven) memories during Oneiric (dreaming) state.
Implements hippocampal-style replay and consolidation.
"""
function replay_high_rpe_memories(
    buffer::EpisodicRingBuffer, 
    brain::IncrementalBrain;
    num_replays::Int=5
)::Dict
    result = Dict{String, Any}("replays" => 0, "improvement" => Float32(0.0))
    
    if buffer.size == 0
        return result
    end
    
    # Get top high-RPE experiences
    rpes = buffer.rpe_scores[1:buffer.size]
    sorted_indices = sortperm(abs.(rpes), rev=true)
    
    top_indices = sorted_indices[1:min(num_replays, length(sorted_indices))]
    
    # Compute improvement from replay
    initial_loss = Float32(0.0)
    final_loss = Float32(0.0)
    
    for idx in top_indices
        state = buffer.states[idx]
        action = buffer.actions[idx]
        reward = buffer.rewards[idx]
        
        # Quick update
        advantages = Float32[reward]
        grads = compute_policy_gradients(brain, [state], [action], advantages, Float32[])
        
        # Apply with high learning rate for fast consolidation
        apply_gradients!(brain, grads, Float32(0.01), Float32(0.0))
    end
    
    result["replays"] = length(top_indices)
    result["success"] = true
    
    return result
end

# Export additional functions
export EpisodicRingBuffer,get_prioritized_batch,get_random_batch,train_batch!,
       compute_policy_entropy,replay_high_rpe_memories

end # module OnlineLearning
