#!/usr/bin/env julia
# ITHERIS-Jarvis Integrated Core v2.0 with Flux.jl - FIXED VERSION
# Full Cognitive Operating System with Advanced Capabilities

using Random, Statistics, LinearAlgebra, Dates, UUIDs, Printf, Distributions
using Flux
using Flux: @functor

# ============================================================================
# ITHERIS CORE - ADVANCED LEARNING ENGINE
# ============================================================================

module ITHERISCore

using Random, Statistics, LinearAlgebra, Distributions
using Flux

export BrainCore, Experience, Thought, NeuralLayer, 
       initialize_brain, infer, learn!, dream!, encode_perception, 
       get_stats, forward_pass, plan, evaluate_plan, adapt_strategy

# ============================================================================
# CORE STRUCTURES - Flux-compatible
# ============================================================================

# Flux-compatible neural layer
struct NeuralLayer
    model::Chain
    activation::Function
end

@functor NeuralLayer

function NeuralLayer(in_dims::Int, out_dims::Int, activation_func::Function = identity)
    model = Chain(
        Dense(in_dims, out_dims)
    )
    return NeuralLayer(model, activation_func)
end

function forward_pass(layer::NeuralLayer, input::Vector{Float32})
    output = layer.model(input)
    return layer.activation.(output)
end

# Flux-compatible experience
struct Experience
    perception::Vector{Float32}
    next_perception::Vector{Float32}
    action::Int
    probs::Vector{Float32}
    value::Float32
    reward::Float32
    timestamp::DateTime
end

struct Thought
    action::Int
    probs::Vector{Float32}
    value::Float32
    uncertainty::Float32
    context_vector::Vector{Float32}
end

mutable struct Plan
    id::UUID
    actions::Vector{Int}
    expected_rewards::Vector{Float32}
    confidence::Float32
    creation_time::DateTime
    estimated_completion::DateTime
end

mutable struct BrainCore{O<:Flux.Optimise.Optimiser}
    # Network layers
    layers::Vector{NeuralLayer}
    value_net::NeuralLayer
    policy_net::NeuralLayer
    predictor_net::NeuralLayer
    attention_net::NeuralLayer  # New:  Attention mechanism
    
    # State (recurrent)
    belief_state::Vector{Float32}
    context_state::Vector{Float32}
    last_hidden::Vector{Float32}
    recurrence_buffer::Vector{Float32}
    attention_weights::Vector{Float32}  # New:  Attention weights
    
    # Memory
    episodic::Vector{Experience}
    reward_trace::Vector{Float32}
    plan_memory::Vector{Plan}  # New:  Plan memory
    
    # Hyperparameters
    learning_rate::Float32
    gamma::Float32
    belief_inertia::Float32
    policy_temperature::Float32
    entropy_coeff::Float32
    attention_coeff::Float32  # New:  Attention coefficient
    
    # Cognitive metrics
    uncertainty::Float32
    novelty::Float32
    complexity::Float32
    
    # Counters
    cycle_count::Int
    input_size::Int
    hidden_size::Int
    plan_count::Int  # New:  Plan counter
    
    # Flux optimizers (all concrete optimizer instances of the same optimiser type O)
    optimizers::Dict{String, O}
end

# ============================================================================
# INITIALIZATION
# ============================================================================

function initialize_brain(;
        input_size::Int=12,    # Increased for more features
        hidden_size::Int=128,    # Increased capacity
        learning_rate::Float32=0.01f0,  
        gamma::Float32=0.95f0,  
        policy_temperature::Float32=1.5f0,  
        entropy_coeff::Float32=0.01f0,  
        attention_coeff::Float32=0.1f0
    )
    
    recurrence_input_size = input_size + hidden_size
    
    # Layer 1:  Recurrent input processing
    layer1 = NeuralLayer(
        Chain(
            Dense(recurrence_input_size, hidden_size, tanh)
        ), 
        identity
    )
    
    # Layer 2:  Hidden processing with residual connection
    layer2 = NeuralLayer(
        Chain(
            Dense(hidden_size, hidden_size, relu)
        ), 
        identity
    )
    
    # Value network
    value_net = NeuralLayer(
        Chain(
            Dense(hidden_size, 1)
        ), 
        identity
    )
    
    # Policy network
    policy_net = NeuralLayer(
        Chain(
            Dense(hidden_size, 6)
        ), 
        x -> begin
            exp_x = exp.(x .- maximum(x))
            exp_x ./ sum(exp_x)
        end
    )
    
    # Predictor network (world model)
    predictor_net = NeuralLayer(
        Chain(
            Dense(hidden_size, input_size)
        ), 
        identity
    )
    
    # Attention network
    attention_net = NeuralLayer(
        Chain(
            Dense(hidden_size, hidden_size)
        ), 
        softmax
    )
    
    # Initialize optimizers — use a concrete optimiser type inferred from Adam constructor
    opt_T = typeof(Flux.Adam(learning_rate))
    optimizers = Dict{String, opt_T}(
        "main" => Flux.Adam(learning_rate), 
        "value" => Flux.Adam(learning_rate), 
        "policy" => Flux.Adam(learning_rate * 0.3f0), 
        "predictor" => Flux.Adam(learning_rate * 0.5f0), 
        "attention" => Flux.Adam(learning_rate * 0.2f0)
    )
    
    return BrainCore(
        [layer1, layer2],  
        value_net,  
        policy_net,  
        predictor_net,  
        attention_net,  
        zeros(Float32, input_size),  
        zeros(Float32, hidden_size),  
        zeros(Float32, hidden_size),  
        zeros(Float32, recurrence_input_size),  
        ones(Float32, hidden_size) ./ hidden_size,    # Initial attention weights
        Experience[],  
        Float32[],  
        Plan[],  
        learning_rate,  
        gamma,  
        0.97f0,  
        policy_temperature,  
        entropy_coeff,  
        attention_coeff,  
        0.5f0,    # uncertainty
        0.3f0,    # novelty
        0.7f0,    # complexity
        0,  
        input_size,  
        hidden_size,  
        0, 
        optimizers
    )
end

# ============================================================================
# PERCEPTION ENCODING (ENHANCED)
# ============================================================================

function encode_perception(perception::Dict{String, Any})::Vector{Float32}
    # Enhanced encoding function with more sophisticated features
    features = Float32[
        clamp(get(perception, "cpu_load", 0.5), 0.0, 1.0),  
        clamp(get(perception, "memory_usage", 0.5), 0.0, 1.0),  
        clamp(get(perception, "disk_io", 0.3), 0.0, 1.0),  
        clamp(get(perception, "network_latency", 50.0) / 200.0, 0.0, 1.0),  
        clamp(get(perception, "overall_severity", 0.0), 0.0, 1.0),  
        min(length(get(perception, "threats", [])) / 10.0, 1.0),  
        clamp(get(perception, "file_count", 0) / 10000.0, 0.0, 1.0),  
        clamp(get(perception, "process_count", 100) / 500.0, 0.0, 1.0),  
        get(perception, "energy_level", 0.8),      # From Jarvis self-model
        get(perception, "confidence", 0.5),        # From Jarvis self-model
        get(perception, "system_uptime_hours", 24.0) / 168.0,    # Normalized week
        get(perception, "user_activity_level", 0.3)  # User interaction level
    ]
    
    # Normalize features
    features = (features .- mean(features)) ./ (std(features) + 1f-8)
    features = clamp.(features, -3f0, 3f0)  # Clip outliers
    
    return features[1: 12]  # Ensure exactly 12 dimensions
end

# ============================================================================
# FORWARD PASS AND UTILITY FUNCTIONS
# ============================================================================

function softmax(x::Vector{Float32})::Vector{Float32}
    exp_x = exp.(x .- maximum(x))
    return exp_x ./ sum(exp_x)
end

function update_belief!(brain::BrainCore, perception_vec::Vector{Float32})
    # Enhanced belief update with uncertainty tracking
    old_belief = copy(brain.belief_state)
    brain.belief_state .=
        brain.belief_inertia .* brain.belief_state .+
        (1f0 - brain.belief_inertia) .* perception_vec
    
    # Update uncertainty based on belief change
    belief_change = norm(brain.belief_state .- old_belief)
    brain.uncertainty = 0.9f0 * brain.uncertainty + 0.1f0 * clamp(belief_change, 0f0, 1f0)
end

function compute_attention!(brain::BrainCore, hidden_state::Vector{Float32})
    # Compute attention weights for selective focus
    attention_raw = forward_pass(brain.attention_net, hidden_state)
    brain.attention_weights .= attention_raw .* brain.attention_coeff
end

# ============================================================================
# INFERENCE AND DECISION MAKING
# ============================================================================

function infer(brain::BrainCore, perception::Dict{String, Any})::Thought
    # Encode perception
    encoded_input = encode_perception(perception)
    update_belief!(brain, encoded_input)
    
    # Build recurrent input:  [perception_error; previous_context]
    input_size = length(brain.belief_state)
    brain.recurrence_buffer[1: input_size] .= encoded_input .- brain.belief_state
    brain.recurrence_buffer[input_size+1: end] .= brain.context_state
    
    # Forward pass through layers with attention
    h1 = forward_pass(brain.layers[1], brain.recurrence_buffer)
    compute_attention!(brain, h1)
    
    # Apply attention
    h1_attended = h1 .* brain.attention_weights
    
    # Update context with temporal smoothing
    brain.context_state .= 0.8f0 .* brain.context_state .+ 0.2f0 .* h1_attended
    brain.context_state .= clamp.(brain.context_state, -1f0, 1f0)
    brain.context_state ./= max(norm(brain.context_state), 1f0)
    
    h2 = forward_pass(brain.layers[2], h1_attended)
    brain.last_hidden .= h2
    
    # Generate value and policy
    value = forward_pass(brain.value_net, h2)[1]
    action_probs = forward_pass(brain.policy_net, h2)
    
    # Temperature-based action selection with uncertainty adjustment
    exploration_factor = brain.policy_temperature * (1f0 + brain.uncertainty)
    scaled = exp.(log.(action_probs .+ 1f-8) ./ exploration_factor)
    scaled ./= sum(scaled)
    
    # Sample action
    action_idx = sample(1: length(scaled), Weights(scaled))
    
    # Calculate uncertainty from entropy of policy
    policy_entropy = -sum(action_probs .* log.(action_probs .+ 1f-8))
    uncertainty = clamp(policy_entropy / log(Float32(length(action_probs))), 0f0, 1f0)
    
    return Thought(action_idx, action_probs, value, uncertainty, copy(brain.context_state))
end

# ============================================================================
# FLUX-BASED LEARNING WITH AUTOMATIC DIFFERENTIATION - FIXED VERSION
# ============================================================================

function learn!(brain::BrainCore,  
                perception::Dict{String, Any},  
                next_perception::Dict{String, Any},  
                thought::Thought,  
                reward::Float32,  
                next_value::Float32)
    
    # Encode states
    encoded = encode_perception(perception)
    update_belief!(brain, encoded)
    
    # Build recurrent input
    input_size = length(brain.belief_state)
    brain.recurrence_buffer[1: input_size] .= encoded .- brain.belief_state
    brain.recurrence_buffer[input_size+1: end] .= brain.context_state
    
    # Convert to proper format for Flux
    recurrence_input = brain.recurrence_buffer
    
    # Value network update using Flux - FIXED
    ps_value = Flux.params(brain.value_net.model)
    gs_value = gradient(ps_value) do
        h1_temp = forward_pass(brain.layers[1], recurrence_input)
        h2_temp = forward_pass(brain.layers[2], h1_temp)
        value_temp = forward_pass(brain.value_net, h2_temp)[1]
        loss = (reward + brain.gamma * next_value - value_temp)^2
        return loss
    end
    # FIXED: Proper update call
    Flux.Optimise.update!(brain.optimizers["value"], ps_value, gs_value)
    
    # Policy gradient update with entropy regularization using Flux - FIXED
    action_idx = thought.action
    probs = thought.probs
    
    if action_idx > 0 && action_idx <= length(probs)
        ps_policy = Flux.params(brain.policy_net.model)
        gs_policy = gradient(ps_policy) do
            h1_temp = forward_pass(brain.layers[1], recurrence_input)
            h2_temp = forward_pass(brain.layers[2], h1_temp)
            action_probs_temp = forward_pass(brain.policy_net, h2_temp)
            
            # Advantage calculation
            h1_val_temp = forward_pass(brain.layers[1], recurrence_input)
            h2_val_temp = forward_pass(brain.layers[2], h1_val_temp)
            value_temp = forward_pass(brain.value_net, h2_val_temp)[1]
            advantage_temp = reward + brain.gamma * next_value - value_temp
            
            # Entropy bonus
            entropy_temp = -sum(action_probs_temp .* log.(action_probs_temp .+ 1f-8))
            advantage_temp += brain.entropy_coeff * entropy_temp
            
            # Policy gradient loss
            selected_prob = action_probs_temp[action_idx]
            loss = -advantage_temp * log(selected_prob + 1f-8)
            return loss
        end
        # FIXED: Proper update call
        Flux.Optimise.update!(brain.optimizers["policy"], ps_policy, gs_policy)
    end
    
    # Attention network update using Flux - FIXED
    ps_attention = Flux.params(brain.attention_net.model)
    gs_attention = gradient(ps_attention) do
        h1_temp = forward_pass(brain.layers[1], recurrence_input)
        attention_raw = forward_pass(brain.attention_net, h1_temp)
        attention_weights_temp = attention_raw .* brain.attention_coeff
        
        # Simple attention loss (unsupervised learning)
        target_attention = softmax(abs.(h1_temp))
        attention_loss = sum((attention_weights_temp .- target_attention).^2)
        return attention_loss
    end
    # FIXED: Proper update call
    Flux.Optimise.update!(brain.optimizers["attention"], ps_attention, gs_attention)
    
    # Main network update using Flux - FIXED
    ps_main = Flux.params(brain.layers[1].model, brain.layers[2].model)
    gs_main = gradient(ps_main) do
        h1_temp = forward_pass(brain.layers[1], recurrence_input)
        h2_temp = forward_pass(brain.layers[2], h1_temp)
        
        # Combined loss from value and policy gradients
        value_temp = forward_pass(brain.value_net, h2_temp)[1]
        value_loss = (reward + brain.gamma * next_value - value_temp)^2
        
        action_probs_temp = forward_pass(brain.policy_net, h2_temp)
        policy_loss = -reward * log(action_probs_temp[action_idx] + 1f-8)
        
        return value_loss + 0.1f0 * policy_loss
    end
    # FIXED: Proper update call
    Flux.Optimise.update!(brain.optimizers["main"], ps_main, gs_main)
    
    # Store experience
    experience = Experience(
        encode_perception(perception),  
        encode_perception(next_perception),  
        action_idx,  
        probs,  
        thought.value,  
        reward,  
        now()
    )
    
    push!(brain.episodic, experience)
    push!(brain.reward_trace, reward)
    
    # Update novelty metric
    if length(brain.episodic) > 1
        recent_experience = brain.episodic[end]
        prev_experience = brain.episodic[end-1]
        state_diff = norm(recent_experience.perception .- prev_experience.perception)
        brain.novelty = 0.95f0 * brain.novelty + 0.05f0 * clamp(state_diff, 0f0, 1f0)
    end
    
    # Limit memory size
    if length(brain.episodic) > 5000
        deleteat!(brain.episodic, 1: 100)
    end
    if length(brain.reward_trace) > 100
        popfirst!(brain.reward_trace)
    end
    
    brain.cycle_count += 1
end

# ============================================================================
# PLANNING AND STRATEGIC THINKING
# ============================================================================

function plan(brain::BrainCore, perception::Dict{String, Any}, horizon::Int=5)::Plan
    # Generate a multi-step plan by simulating future actions
    plan_id = uuid4()
    actions = Int[]
    rewards = Float32[]
    confidence = 1.0f0
    
    # Current state
    current_perception = encode_perception(perception)
    current_context = copy(brain.context_state)
    
    # Simulate future steps
    for step in 1: horizon
        # Create simulated input
        input_size = length(current_perception)
        simulated_buffer = zeros(Float32, length(brain.recurrence_buffer))
        simulated_buffer[1: input_size] .= current_perception .- brain.belief_state
        simulated_buffer[input_size+1: end] .= current_context
        
        # Forward pass
        h1 = forward_pass(brain.layers[1], simulated_buffer)
        h2 = forward_pass(brain.layers[2], h1)
        
        # Get policy
        action_probs = forward_pass(brain.policy_net, h2)
        
        # Select action (deterministic for planning)
        action_idx = argmax(action_probs)
        push!(actions, action_idx)
        
        # Estimate reward (simplified)
        estimated_reward = forward_pass(brain.value_net, h2)[1]
        push!(rewards, estimated_reward)
        
        # Update confidence based on certainty
        certainty = 1f0 - sum(action_probs .* log.(action_probs .+ 1f-8)) / log(6f0)
        confidence *= certainty
        
        # Simulate next state (simplified world model)
        prediction = forward_pass(brain.predictor_net, h2)
        current_perception = prediction
        current_context = 0.9f0 .* current_context .+ 0.1f0 .* h1
    end
    
    brain.plan_count += 1
    
    return Plan(
        plan_id,  
        actions,  
        rewards,  
        confidence,  
        now(),  
        now() + Dates.Minute(horizon)
    )
end

function evaluate_plan(brain::BrainCore, plan::Plan)::Float32
    # Evaluate plan quality based on expected rewards and confidence
    if isempty(plan.expected_rewards)
        return 0.0f0
    end
    
    # Discounted reward sum
    discounted_reward = 0.0f0
    discount = 1.0f0
    for reward in plan.expected_rewards
        discounted_reward += discount * reward
        discount *= brain.gamma
    end
    
    # Normalize by plan length
    normalized_reward = discounted_reward / Float32(length(plan.expected_rewards))
    
    # Combine with confidence
    return normalized_reward * plan.confidence
end

function adapt_strategy(brain::BrainCore, performance_history::Vector{Float32})
    # Adapt learning strategy based on recent performance
    if length(performance_history) < 10
        return
    end
    
    recent_avg = mean(performance_history[end-9: end])
    long_term_avg = length(performance_history) > 10 ? mean(performance_history[1: end-10]) : recent_avg
    
    # Adjust learning rate based on performance trend
    if recent_avg > long_term_avg
        brain.learning_rate = min(0.1f0, brain.learning_rate * 1.05f0)  # Increase learning
        # Update optimizer learning rates
        for (key, opt) in brain.optimizers
            if hasfield(typeof(opt), :eta)
                opt.eta = brain.learning_rate * (key == "policy" ? 0.3f0 : (key == "predictor" ? 0.5f0 : (key == "attention" ? 0.2f0 : 1.0f0)))
            end
        end
    else
        brain.learning_rate = max(0.001f0, brain.learning_rate * 0.95f0)  # Decrease learning
        # Update optimizer learning rates
        for (key, opt) in brain.optimizers
            if hasfield(typeof(opt), :eta)
                opt.eta = brain.learning_rate * (key == "policy" ? 0.3f0 : (key == "predictor" ? 0.5f0 : (key == "attention" ? 0.2f0 : 1.0f0)))
            end
        end
    end
    
    # Adjust exploration based on performance stability
    performance_variance = var(performance_history[end-9: end])
    if performance_variance > 0.1f0
        brain.policy_temperature = min(3.0f0, brain.policy_temperature * 1.1f0)  # More exploration
    else
        brain.policy_temperature = max(0.5f0, brain.policy_temperature * 0.95f0)  # Less exploration
    end
end

# ============================================================================
# WORLD MODEL / DREAMING WITH MEMORY CONSOLIDATION
# ============================================================================

function dream!(brain::BrainCore)::Float32
    if length(brain.episodic) < 20
        return 0.0f0
    end
    
    # Sample batch
    batch_size = min(length(brain.episodic), 64)
    indices = shuffle(1: length(brain.episodic))[1: batch_size]
    samples = brain.episodic[indices]
    
    total_prediction_error = 0.0f0
    total_attention_loss = 0.0f0
    
    for exp in samples
        state_t = exp.perception
        
        # Use only current state for prediction (no future information)
        dream_input = vcat(
            state_t,  
            zeros(Float32, length(brain.context_state))
        )
        dream_input ./= max(norm(dream_input), 1f0)
        
        # Forward pass
        h1 = forward_pass(brain.layers[1], dream_input)
        h2 = forward_pass(brain.layers[2], h1)
        prediction = forward_pass(brain.predictor_net, h2)
        
        # Prediction error
        error = prediction - exp.next_perception
        loss = sum(error .^ 2)
        total_prediction_error += loss
        
        # Update predictor using Flux - FIXED
        ps_predictor = Flux.params(brain.predictor_net.model)
        gs_predictor = gradient(ps_predictor) do
            h1_temp = forward_pass(brain.layers[1], dream_input)
            h2_temp = forward_pass(brain.layers[2], h1_temp)
            pred_temp = forward_pass(brain.predictor_net, h2_temp)
            pred_loss = sum((pred_temp .- exp.next_perception).^2)
            return pred_loss
        end
        # FIXED: Proper update call
        Flux.Optimise.update!(brain.optimizers["predictor"], ps_predictor, gs_predictor)
        
        # Attention learning (unsupervised)
        attention_target = softmax(abs.(h1))  # Attend to salient features
        attention_error = brain.attention_weights - attention_target
        attention_loss = sum(attention_error .^ 2)
        total_attention_loss += attention_loss
        
        # Update attention using Flux - FIXED
        ps_attention = Flux.params(brain.attention_net.model)
        gs_attention = gradient(ps_attention) do
            h1_temp = forward_pass(brain.layers[1], dream_input)
            attention_raw = forward_pass(brain.attention_net, h1_temp)
            attention_weights_temp = attention_raw .* brain.attention_coeff
            att_loss = sum((attention_weights_temp .- attention_target).^2)
            return att_loss
        end
        # FIXED: Proper update call
        Flux.Optimise.update!(brain.optimizers["attention"], ps_attention, gs_attention)
    end
    
    # Memory consolidation:  strengthen important memories
    consolidate_memory!(brain)
    
    return (total_prediction_error + total_attention_loss) / Float32(batch_size)
end

function consolidate_memory!(brain::BrainCore)
    # Consolidate important memories based on reward and novelty
    if length(brain.episodic) < 100
        return
    end
    
    # Rank experiences by importance (reward magnitude + novelty)
    importance_scores = Float32[]
    for exp in brain.episodic
        score = abs(exp.reward) + 0.5f0 * brain.novelty
        push!(importance_scores, score)
    end
    
    # Keep top 20% most important experiences
    threshold = quantile(importance_scores, 0.8)
    important_indices = findall(x -> x >= threshold, importance_scores)
    
    # Strengthen weights for important experiences
    if !isempty(important_indices)
        consolidation_factor = 1.1f0
        for idx in important_indices
            if idx <= length(brain.episodic)
                exp = brain.episodic[idx]
                # This is a conceptual strengthening - in practice, 
                # you might retrain on important samples
            end
        end
    end
end

# ============================================================================
# UTILITIES AND METRICS
# ============================================================================

function get_stats(brain::BrainCore)::Dict{String, Any}
    if isempty(brain.reward_trace)
        return Dict(
            "avg_reward" => 0.0,  
            "experience_count" => 0,  
            "total_cycles" => brain.cycle_count,  
            "learning_rate" => brain.learning_rate,  
            "policy_temperature" => brain.policy_temperature,  
            "uncertainty" => brain.uncertainty,  
            "novelty" => brain.novelty,  
            "complexity" => brain.complexity,  
            "plan_count" => brain.plan_count
        )
    end
    
    recent_rewards = brain.reward_trace[max(1, end-49): end]  # Last 50 rewards
    
    return Dict(
        "avg_reward" => mean(brain.reward_trace),  
        "recent_avg_reward" => mean(recent_rewards),  
        "reward_variance" => var(recent_rewards),  
        "experience_count" => length(brain.episodic),  
        "total_cycles" => brain.cycle_count,  
        "learning_rate" => brain.learning_rate,  
        "policy_temperature" => brain.policy_temperature,  
        "belief_state_norm" => norm(brain.belief_state),  
        "uncertainty" => brain.uncertainty,  
        "novelty" => brain.novelty,  
        "complexity" => brain.complexity,  
        "plan_count" => brain.plan_count,  
        "attention_entropy" => -sum(brain.attention_weights .* log.(brain.attention_weights .+ 1f-8))
    )
end

end # module ITHERISCore

# [Rest of the JarvisExecutive module remains unchanged]
# The rest of the code would continue as in the original, 
# but with the fixed ITHERISCore module above
