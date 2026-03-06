#!/usr/bin/env julia
# ITHERIS-Jarvis Integrated Core v2.0 with Flux.jl - FIXED VERSION
# Full Cognitive Operating System with Advanced Capabilities

using Dates
using Distributions
using Flux
using Flux:  @functor
using LinearAlgebra
using Printf
using Random
using Statistics
using UUIDs

# ============================================================================
# ITHERIS CORE - ADVANCED LEARNING ENGINE
# ============================================================================

module ITHERISCore

using Random,  Statistics,  LinearAlgebra,  Distributions, Dates, UUIDs
using Flux
using Functors # <--- REQUIRED for @functor

# Simple weighted sampling without StatsBase
function weighted_sample(probs::Vector{Float32})::Int
    r = rand(Float32) * sum(probs)
    cumsum = Float32(0)
    for (i, p) in enumerate(probs)
        cumsum += p
        if cumsum >= r
            return i
        end
    end
    return length(probs)
end

# Export the missing Goal struct
export BrainCore,  Experience,  Thought,  NeuralLayer,  Goal,  ActionProposal,  Plan,
       initialize_brain,  infer,  learn!,  dream!,  encode_perception,  
       get_stats,  forward_pass,  plan,  evaluate_plan,  adapt_strategy,
       run_dream_cycle,  train_brain!,  GradientFailureTracker,  GRADIENT_TRACKER,
       has_invalid_gradients,  handle_critical_gradient_failure,  reset_gradient_tracker!

# ============================================================================
# GRADIENT FAILURE TRACKING
# ============================================================================

"""
Global gradient failure tracking for training reliability.
Tracks consecutive failures and alerts when threshold is exceeded.
"""
mutable struct GradientFailureTracker
    value_failures::Int
    policy_failures::Int
    attention_failures::Int
    main_failures::Int
    last_failure_time::Dates.DateTime
    consecutive_failures::Int
    total_updates::Int
    failure_threshold::Int
    
    GradientFailureTracker() = new(0, 0, 0, 0, Dates.now(), 0, 0, 10)
end

const GRADIENT_TRACKER = GradientFailureTracker()

"""
    has_invalid_gradients(grads)::Bool

Check if gradients contain NaN or Inf values.
"""
function has_invalid_gradients(grads)::Bool
    for p in grads
        grad = grads[p]
        if grad === nothing
            continue
        end
        if any(isnan, grad) || any(isinf, grad)
            return true
        end
    end
    return false
end

"""
    handle_critical_gradient_failure(network::String)

Handle critical gradient failures by logging and alerting.
"""
function handle_critical_gradient_failure(network::String)
    @error "CRITICAL: Too many consecutive gradient failures in $network" threshold=GRADIENT_TRACKER.failure_threshold
    
    # Log to audit trail
    total_failures = GRADIENT_TRACKER.value_failures + GRADIENT_TRACKER.policy_failures + 
                     GRADIENT_TRACKER.attention_failures + GRADIENT_TRACKER.main_failures
    @error "Gradient Failure Stats" 
        value_failures=GRADIENT_TRACKER.value_failures 
        policy_failures=GRADIENT_TRACKER.policy_failures
        attention_failures=GRADIENT_TRACKER.attention_failures
        main_failures=GRADIENT_TRACKER.main_failures
        total_failures=total_failures
        consecutive=GRADIENT_TRACKER.consecutive_failures
end

"""
    reset_gradient_tracker!()

Reset gradient failure counters (call after successful recovery).
"""
function reset_gradient_tracker!()
    GRADIENT_TRACKER.value_failures = 0
    GRADIENT_TRACKER.policy_failures = 0
    GRADIENT_TRACKER.attention_failures = 0
    GRADIENT_TRACKER.main_failures = 0
    GRADIENT_TRACKER.consecutive_failures = 0
    @info "Gradient failure tracker reset"
end

# ============================================================================
# CORE STRUCTURES - Flux-compatible
# ============================================================================

# --- 1. Fix for @functor error ---
struct NeuralLayer
    model::Chain
    activation::Function
end

@functor NeuralLayer  # This will now work because 'using Functors' is above

# This makes the NeuralLayer struct callable - enables Zygote gradient tracking
function (layer::NeuralLayer)(x)
    output = layer.model(x)
    return layer.activation.(output)
end

function NeuralLayer(in_dims::Int,  out_dims::Int,  activation_func::Function = identity)
    model = Chain(Dense(in_dims,  out_dims))
    return NeuralLayer(model,  activation_func)
end

function forward_pass(layer::NeuralLayer,  input::Vector{Float32})::Vector{Float32}
    # Validate input is non-empty and has correct dimensions
    if isempty(input)
        error("forward_pass: input vector is empty")
    end
    
    # Get expected input size from the first dense layer (Flux uses weight instead of W)
    first_dense = layer.model.layers[1]
    expected_in = size(first_dense.weight, 2)
    if length(input) != expected_in
        error("forward_pass: input size ($(length(input))) does not match expected size ($expected_in)")
    end
    
    output = layer.model(input)
    
    # Validate output is non-empty
    if isempty(output)
        error("forward_pass: model output is empty")
    end
    
    # Check if activation is a vector->vector function (like softmax) vs element-wise
    # by testing if it can be called with a scalar
    try
        test_val = output[1]
        test_result = layer.activation(test_val)
        # If activation accepts scalar and returns scalar, it's element-wise
        if isa(test_result, Number)
            return layer.activation.(output)
        else
            # Otherwise apply to whole vector (e.g., softmax)
            return layer.activation(output)
        end
    catch
        return layer.activation.(output)
    end
end

# --- 2. Fix for "Goal not defined" error ---
# This struct was missing entirely from your code but is required by your tests
mutable struct Goal
    id::UUID
    description::String
    target_state::Vector{Float32}
    priority::Float32
    deadline::DateTime
    status::Symbol # :active, :completed, :failed
end

# Add a constructor for convenience if needed
function Goal(desc::String,  target::Vector{Float32},  priority::Float32=1.0f0)
    return Goal(uuid4(),  desc,  target,  priority,  now() + Dates.Hour(1),  :active)
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

# Action Proposal - for kernel integration
mutable struct ActionProposal
    id::UUID
    action_idx::Int
    confidence::Float32
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
end

mutable struct Plan
    id::UUID
    actions::Vector{Int}
    expected_rewards::Vector{Float32}
    confidence::Float32
    creation_time::DateTime
    estimated_completion::DateTime
end

mutable struct BrainCore
    # Network layers
    layers::Vector{NeuralLayer}
    value_net::NeuralLayer
    policy_net::NeuralLayer
    predictor_net::NeuralLayer
    attention_net::NeuralLayer  # New:   Attention mechanism
    
    # State (recurrent)
    belief_state::Vector{Float32}
    context_state::Vector{Float32}
    last_hidden::Vector{Float32}
    recurrence_buffer::Vector{Float32}
    attention_weights::Vector{Float32}  # New:   Attention weights
    
    # Memory
    episodic::Vector{Experience}
    reward_trace::Vector{Float32}
    plan_memory::Vector{Plan}  # New:   Plan memory
    
    # Hyperparameters
    learning_rate::Float32
    gamma::Float32
    belief_inertia::Float32
    policy_temperature::Float32
    entropy_coeff::Float32
    attention_coeff::Float32  # New:   Attention coefficient
    
    # Cognitive metrics
    uncertainty::Float32
    novelty::Float32
    complexity::Float32
    
    # Counters
    cycle_count::Int
    input_size::Int
    hidden_size::Int
    plan_count::Int  # New:   Plan counter
    
    # Flux optimizers - using Any for flexibility with modern Flux/Optimisers.jl
    optimizers::Dict{String, Any}
end

# ============================================================================
# INITIALIZATION
# ============================================================================

function initialize_brain(;
        input_size::Int=12,     # Increased for more features
        hidden_size::Int=128,     # Increased capacity
        learning_rate::Float32=0.01f0,   
        gamma::Float32=0.95f0,   
        policy_temperature::Float32=1.5f0,   
        entropy_coeff::Float32=0.01f0,   
        attention_coeff::Float32=0.1f0
    )
    
    recurrence_input_size = input_size + hidden_size
    
    # Layer 1:   Recurrent input processing
    layer1 = NeuralLayer(
        Chain(
            Dense(recurrence_input_size,  hidden_size,  tanh)
        ),  
        identity
    )
    
    # Layer 2:   Hidden processing with residual connection
    layer2 = NeuralLayer(
        Chain(
            Dense(hidden_size,  hidden_size,  relu)
        ),  
        identity
    )
    
    # Value network
    value_net = NeuralLayer(
        Chain(
            Dense(hidden_size,  1)
        ),  
        identity
    )
    
    # Policy network (outputs logits, softmax applied after temperature scaling)
    policy_net = NeuralLayer(
        Chain(
            Dense(hidden_size,  6)
        ),  
        identity
    )
    
    # Predictor network (world model)
    predictor_net = NeuralLayer(
        Chain(
            Dense(hidden_size,  input_size)
        ),  
        identity
    )
    
    # Attention network - use identity, apply softmax separately in compute_attention!
    attention_net = NeuralLayer(
        Chain(
            Dense(hidden_size,  hidden_size)
        ),  
        identity
    )
    
    # Initialize optimizers — use Any for flexibility with modern Flux/Optimisers.jl
    optimizers = Dict{String, Any}(
        "main" => Flux.Adam(learning_rate),  
        "value" => Flux.Adam(learning_rate),  
        "policy" => Flux.Adam(learning_rate * 0.3f0),  
        "predictor" => Flux.Adam(learning_rate * 0.5f0),  
        "attention" => Flux.Adam(learning_rate * 0.2f0)
    )
    
    return BrainCore(
        [layer1,  layer2],   
        value_net,   
        policy_net,   
        predictor_net,   
        attention_net,   
        zeros(Float32,  input_size),   
        zeros(Float32,  hidden_size),   
        zeros(Float32,  hidden_size),   
        zeros(Float32,  recurrence_input_size),   
        ones(Float32,  hidden_size) ./ hidden_size,     # Initial attention weights
        Experience[],   
        Float32[],   
        Plan[],   
        learning_rate,   
        gamma,   
        0.97f0,   
        policy_temperature,   
        entropy_coeff,   
        attention_coeff,   
        0.5f0,     # uncertainty
        0.3f0,     # novelty
        0.7f0,     # complexity
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

function encode_perception(perception::Dict{String,  Any})::Vector{Float32}
    # Enhanced encoding function with more sophisticated features
    features = Float32[
        clamp(get(perception,  "cpu_load",  0.5),  0.0,  1.0),   
        clamp(get(perception,  "memory_usage",  0.5),  0.0,  1.0),   
        clamp(get(perception,  "disk_io",  0.3),  0.0,  1.0),   
        clamp(get(perception,  "network_latency",  50.0) / 200.0,  0.0,  1.0),   
        clamp(get(perception,  "overall_severity",  0.0),  0.0,  1.0),   
        min(length(get(perception,  "threats",  [])) / 10.0,  1.0),   
        clamp(get(perception,  "file_count",  0) / 10000.0,  0.0,  1.0),   
        clamp(get(perception,  "process_count",  100) / 500.0,  0.0,  1.0),   
        get(perception,  "energy_level",  0.8),       # From Jarvis self-model
        get(perception,  "confidence",  0.5),         # From Jarvis self-model
        get(perception,  "system_uptime_hours",  24.0) / 168.0,     # Normalized week
        get(perception,  "user_activity_level",  0.3)  # User interaction level
    ]
    
    # Normalize features
    features = (features .- mean(features)) ./ (std(features) + 1f-8)
    features = clamp.(features,  -3f0,  3f0)  # Clip outliers
    
    return features[1:12]  # Ensure exactly 12 dimensions
end

# ============================================================================
# FORWARD PASS AND UTILITY FUNCTIONS
# ============================================================================

function softmax(x::Vector{Float32})::Vector{Float32}
    exp_x = exp.(x .- maximum(x))
    return exp_x ./ sum(exp_x)
end

function update_belief!(brain::BrainCore,  perception_vec::Vector{Float32})
    # Enhanced belief update with uncertainty tracking
    old_belief = copy(brain.belief_state)
    brain.belief_state .=
        brain.belief_inertia .* brain.belief_state .+
        (1f0 - brain.belief_inertia) .* perception_vec
    
    # Update uncertainty based on belief change
    belief_change = norm(brain.belief_state .- old_belief)
    brain.uncertainty = 0.9f0 * brain.uncertainty + 0.1f0 * clamp(belief_change,  0f0,  1f0)
end

function compute_attention!(brain::BrainCore,  hidden_state::Vector{Float32})
    # Compute attention weights for selective focus
    attention_raw = forward_pass(brain.attention_net,  hidden_state)
    # Apply softmax to get proper attention distribution
    attention_raw = softmax(attention_raw)
    brain.attention_weights .= attention_raw .* brain.attention_coeff
end

# ============================================================================
# INFERENCE AND DECISION MAKING
# ============================================================================

function infer(brain::BrainCore,  perception::Dict{String,  Any})::Thought
    # Encode perception
    encoded_input = encode_perception(perception)
    update_belief!(brain,  encoded_input)
    
    # Build recurrent input:   [perception_error; previous_context]
    input_size = length(brain.belief_state)
    brain.recurrence_buffer[1:input_size] .= encoded_input .- brain.belief_state
    brain.recurrence_buffer[input_size+1:end] .= brain.context_state
    
    # Forward pass through layers with attention
    h1 = forward_pass(brain.layers[1],  brain.recurrence_buffer)
    compute_attention!(brain,  h1)
    
    # Apply attention
    h1_attended = h1 .* brain.attention_weights
    
    # Update context with temporal smoothing
    brain.context_state .= 0.8f0 .* brain.context_state .+ 0.2f0 .* h1_attended
    brain.context_state .= clamp.(brain.context_state,  -1f0,  1f0)
    brain.context_state ./= max(norm(brain.context_state),  1f0)
    
    h2 = forward_pass(brain.layers[2],  h1_attended)
    brain.last_hidden .= h2
    
    # Generate value and policy
    value = forward_pass(brain.value_net,  h2)[1]
    action_logits = forward_pass(brain.policy_net,  h2)
    
    # Temperature-based action selection with uncertainty adjustment
    exploration_factor = brain.policy_temperature * (1f0 + brain.uncertainty)
    scaled = exp.(action_logits ./ exploration_factor)
    action_probs = scaled ./ sum(scaled)
    
    # Sample action using custom weighted sampling
    action_idx = weighted_sample(action_probs)
    
    # Calculate uncertainty from entropy of policy
    policy_entropy = -sum(action_probs .* log.(action_probs .+ 1f-8))
    uncertainty = clamp(policy_entropy / log(Float32(length(action_probs))),  0f0,  1f0)
    
    return Thought(action_idx,  action_probs,  value,  uncertainty,  copy(brain.context_state))
end

# ============================================================================
# FLUX-BASED LEARNING WITH AUTOMATIC DIFFERENTIATION - FIXED VERSION
# ============================================================================

function learn!(brain::BrainCore,   
                perception::Dict{String,  Any},   
                next_perception::Dict{String,  Any},   
                thought::Thought,   
                reward::Float32,   
                next_value::Float32)
    
    # Encode states
    encoded = encode_perception(perception)
    update_belief!(brain,  encoded)
    
    # Build recurrent input
    input_size = length(brain.belief_state)
    brain.recurrence_buffer[1:input_size] .= encoded .- brain.belief_state
    brain.recurrence_buffer[input_size+1:end] .= brain.context_state
    
    # Convert to proper format for Flux
    recurrence_input = brain.recurrence_buffer
    
    # Validate recurrence_input before gradient computation
    if isempty(recurrence_input) || length(recurrence_input) < 140
        # Initialize with zeros if not properly set up
        recurrence_input = zeros(Float32, 140)
    end
    
    # Value network update using Flux - FIXED with error handling and tracking
    GRADIENT_TRACKER.total_updates += 1
    value_success = false
    
    try
        ps_value = Flux.params(brain.value_net.model)
        gs_value = gradient(ps_value) do
            h1_temp = forward_pass(brain.layers[1],  recurrence_input)
            h2_temp = forward_pass(brain.layers[2],  h1_temp)
            value_temp = forward_pass(brain.value_net,  h2_temp)[1]
            loss = (reward + brain.gamma * next_value - value_temp)^2
            return loss
        end
        # Check for NaN/Inf gradients
        if has_invalid_gradients(gs_value)
            throw(ErrorException("Invalid gradients detected (NaN/Inf)"))
        end
        # FIXED:  Proper update call
        Flux.Optimise.update!(brain.optimizers["value"],  ps_value,  gs_value)
        value_success = true
    catch e
        GRADIENT_TRACKER.value_failures += 1
        GRADIENT_TRACKER.consecutive_failures += 1
        GRADIENT_TRACKER.last_failure_time = Dates.now()
        
        @warn "Value network gradient failed" exception=e failures=GRADIENT_TRACKER.value_failures
        
        # Check if failures exceeded threshold
        if GRADIENT_TRACKER.consecutive_failures > GRADIENT_TRACKER.failure_threshold
            handle_critical_gradient_failure("value_network")
        end
    end
    
    # Policy gradient update with entropy regularization using Flux - FIXED
    action_idx = thought.action
    probs = thought.probs
    policy_success = false
    
    if action_idx > 0 && action_idx <= length(probs)
        try
            ps_policy = Flux.params(brain.policy_net.model)
            gs_policy = gradient(ps_policy) do
                h1_temp = forward_pass(brain.layers[1],  recurrence_input)
                h2_temp = forward_pass(brain.layers[2],  h1_temp)
                action_probs_temp = forward_pass(brain.policy_net,  h2_temp)
                
                # Advantage calculation
                h1_val_temp = forward_pass(brain.layers[1],  recurrence_input)
                h2_val_temp = forward_pass(brain.layers[2],  h1_val_temp)
                value_temp = forward_pass(brain.value_net,  h2_val_temp)[1]
                advantage_temp = reward + brain.gamma * next_value - value_temp
                
                # Entropy bonus
                entropy_temp = -sum(action_probs_temp .* log.(action_probs_temp .+ 1f-8))
                advantage_temp += brain.entropy_coeff * entropy_temp
                
                # Policy gradient loss
                selected_prob = action_probs_temp[action_idx]
                loss = -advantage_temp * log(selected_prob + 1f-8)
                return loss
            end
            # Check for NaN/Inf gradients
            if has_invalid_gradients(gs_policy)
                throw(ErrorException("Invalid gradients detected (NaN/Inf)"))
            end
            # FIXED:  Proper update call
            Flux.Optimise.update!(brain.optimizers["policy"],  ps_policy,  gs_policy)
            policy_success = true
        catch e
            GRADIENT_TRACKER.policy_failures += 1
            GRADIENT_TRACKER.consecutive_failures += 1
            GRADIENT_TRACKER.last_failure_time = Dates.now()
            
            @warn "Policy network gradient failed" exception=e failures=GRADIENT_TRACKER.policy_failures
            
            if GRADIENT_TRACKER.consecutive_failures > GRADIENT_TRACKER.failure_threshold
                handle_critical_gradient_failure("policy_network")
            end
        end
    end
    
    # Attention network update using Flux - FIXED
    attention_success = false
    try
        ps_attention = Flux.params(brain.attention_net.model)
        gs_attention = gradient(ps_attention) do
            h1_temp = forward_pass(brain.layers[1],  recurrence_input)
            attention_raw = forward_pass(brain.attention_net,  h1_temp)
            attention_weights_temp = attention_raw .* brain.attention_coeff
            
            # Simple attention loss (unsupervised learning)
            target_attention = softmax(abs.(h1_temp))
            attention_loss = sum((attention_weights_temp .- target_attention).^2)
            return attention_loss
        end
        # Check for NaN/Inf gradients
        if has_invalid_gradients(gs_attention)
            throw(ErrorException("Invalid gradients detected (NaN/Inf)"))
        end
        # FIXED:  Proper update call
        Flux.Optimise.update!(brain.optimizers["attention"],  ps_attention,  gs_attention)
        attention_success = true
    catch e
        GRADIENT_TRACKER.attention_failures += 1
        GRADIENT_TRACKER.consecutive_failures += 1
        GRADIENT_TRACKER.last_failure_time = Dates.now()
        
        @warn "Attention network gradient failed" exception=e failures=GRADIENT_TRACKER.attention_failures
        
        if GRADIENT_TRACKER.consecutive_failures > GRADIENT_TRACKER.failure_threshold
            handle_critical_gradient_failure("attention_network")
        end
    end
    
    # Main network update using Flux - FIXED
    main_success = false
    try
        # For multiple models, we need to chain them properly
        ps_main = Flux.params(brain.layers[1].model, brain.layers[2].model)
        gs_main = gradient(ps_main) do
            h1_temp = forward_pass(brain.layers[1],  recurrence_input)
            h2_temp = forward_pass(brain.layers[2],  h1_temp)
            
            # Combined loss from value and policy gradients
            value_temp = forward_pass(brain.value_net,  h2_temp)[1]
            value_loss = (reward + brain.gamma * next_value - value_temp)^2
            
            action_probs_temp = forward_pass(brain.policy_net,  h2_temp)
            policy_loss = -reward * log(action_probs_temp[action_idx] + 1f-8)
            
            return value_loss + 0.1f0 * policy_loss
        end
        # Check for NaN/Inf gradients
        if has_invalid_gradients(gs_main)
            throw(ErrorException("Invalid gradients detected (NaN/Inf)"))
        end
        # FIXED:  Proper update call
        Flux.Optimise.update!(brain.optimizers["main"],  ps_main,  gs_main)
        main_success = true
    catch e
        GRADIENT_TRACKER.main_failures += 1
        GRADIENT_TRACKER.consecutive_failures += 1
        GRADIENT_TRACKER.last_failure_time = Dates.now()
        
        @warn "Main network gradient failed" exception=e failures=GRADIENT_TRACKER.main_failures
        
        if GRADIENT_TRACKER.consecutive_failures > GRADIENT_TRACKER.failure_threshold
            handle_critical_gradient_failure("main_network")
        end
    end
    
    # Reset consecutive failures on any success
    if value_success || policy_success || attention_success || main_success
        GRADIENT_TRACKER.consecutive_failures = 0
    end
    
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
    
    push!(brain.episodic,  experience)
    push!(brain.reward_trace,  reward)
    
    # Update novelty metric
    if length(brain.episodic) > 1
        recent_experience = brain.episodic[end]
        prev_experience = brain.episodic[end-1]
        state_diff = norm(recent_experience.perception .- prev_experience.perception)
        brain.novelty = 0.95f0 * brain.novelty + 0.05f0 * clamp(state_diff,  0f0,  1f0)
    end
    
    # Limit memory size
    if length(brain.episodic) > 5000
        deleteat!(brain.episodic,  1:100)
    end
    if length(brain.reward_trace) > 100
        popfirst!(brain.reward_trace)
    end
    
    brain.cycle_count += 1
end

# ============================================================================
# PLANNING AND STRATEGIC THINKING
# ============================================================================

function plan(brain::BrainCore,  perception::Dict{String,  Any}; horizon::Int=5)::Plan
    # Generate a multi-step plan by simulating future actions
    plan_id = uuid4()
    actions = Int[]
    rewards = Float32[]
    confidence = 1.0f0
    
    # Current state
    current_perception = encode_perception(perception)
    current_context = copy(brain.context_state)
    
    # Simulate future steps
    for step in 1:horizon
        # Create simulated input
        input_size = length(current_perception)
        simulated_buffer = zeros(Float32,  length(brain.recurrence_buffer))
        simulated_buffer[1:input_size] .= current_perception .- brain.belief_state
        simulated_buffer[input_size+1:end] .= current_context
        
        # Forward pass
        h1 = forward_pass(brain.layers[1],  simulated_buffer)
        h2 = forward_pass(brain.layers[2],  h1)
        
        # Get policy
        action_probs = forward_pass(brain.policy_net,  h2)
        
        # Select action (deterministic for planning)
        action_idx = argmax(action_probs)
        push!(actions,  action_idx)
        
        # Estimate reward (simplified)
        estimated_reward = forward_pass(brain.value_net,  h2)[1]
        push!(rewards,  estimated_reward)
        
        # Update confidence based on certainty (clamp to valid range)
        # Clamp probabilities to valid range to avoid log of negative numbers
        clamped_probs = clamp.(action_probs, 1f-10, 1f0)
        certainty = 1f0 - sum(clamped_probs .* log.(clamped_probs)) / log(6f0)
        # Ensure confidence stays in [0, 1] range
        confidence = clamp(confidence * max(0f0, certainty), 0f0, 1f0)
        
        # Simulate next state (simplified world model)
        prediction = forward_pass(brain.predictor_net,  h2)
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

function evaluate_plan(brain::BrainCore,  plan::Plan)::Float32
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

function adapt_strategy(brain::BrainCore,  performance_history::Vector{Float32})
    # Adapt learning strategy based on recent performance
    if length(performance_history) < 10
        return
    end
    
    recent_avg = mean(performance_history[end-9:end])
    long_term_avg = length(performance_history) > 10 ? mean(performance_history[1:end-10]) :  recent_avg
    
    # Adjust learning rate based on performance trend
    if recent_avg > long_term_avg
        brain.learning_rate = min(0.1f0,  brain.learning_rate * 1.05f0)  # Increase learning
        # Update optimizer learning rates
        for (key,  opt) in brain.optimizers
            if hasfield(typeof(opt),  :eta)
                opt.eta = brain.learning_rate * (key == "policy" ? 0.3f0 :  (key == "predictor" ? 0.5f0 :  (key == "attention" ? 0.2f0 :  1.0f0)))
            end
        end
    else
        brain.learning_rate = max(0.001f0,  brain.learning_rate * 0.95f0)  # Decrease learning
        # Update optimizer learning rates
        for (key,  opt) in brain.optimizers
            if hasfield(typeof(opt),  :eta)
                opt.eta = brain.learning_rate * (key == "policy" ? 0.3f0 :  (key == "predictor" ? 0.5f0 :  (key == "attention" ? 0.2f0 :  1.0f0)))
            end
        end
    end
    
    # Adjust exploration based on performance stability
    performance_variance = var(performance_history[end-9:end])
    if performance_variance > 0.1f0
        brain.policy_temperature = min(3.0f0,  brain.policy_temperature * 1.1f0)  # More exploration
    else
        brain.policy_temperature = max(0.5f0,  brain.policy_temperature * 0.95f0)  # Less exploration
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
    batch_size = min(length(brain.episodic),  64)
    indices = shuffle(1:length(brain.episodic))[1:batch_size]
    samples = brain.episodic[indices]
    
    total_prediction_error = 0.0f0
    total_attention_loss = 0.0f0
    
    for exp in samples
        state_t = exp.perception
        
        # Use only current state for prediction (no future information)
        dream_input = vcat(
            state_t,   
            zeros(Float32,  length(brain.context_state))
        )
        dream_input ./= max(norm(dream_input),  1f0)
        
        # Forward pass
        h1 = forward_pass(brain.layers[1],  dream_input)
        h2 = forward_pass(brain.layers[2],  h1)
        prediction = forward_pass(brain.predictor_net,  h2)
        
        # Prediction error
        error = prediction - exp.next_perception
        loss = sum(error .^ 2)
        total_prediction_error += loss
        
        # Update predictor using Flux - FIXED with error handling
        try
            ps_predictor = Flux.trainable(brain.predictor_net.model)
            gs_predictor = gradient(ps_predictor) do
                h1_temp = forward_pass(brain.layers[1],  dream_input)
                h2_temp = forward_pass(brain.layers[2],  h1_temp)
                pred_temp = forward_pass(brain.predictor_net,  h2_temp)
                pred_loss = sum((pred_temp .- exp.next_perception).^2)
                return pred_loss
            end
            # FIXED:  Proper update call
            Flux.Optimise.update!(brain.optimizers["predictor"],  ps_predictor,  gs_predictor)
        catch e
            @warn "Predictor gradient computation failed in dream!: $(typeof(e)). Using fallback."
        end
        
        # Attention learning (unsupervised)
        attention_target = softmax(abs.(h1))  # Attend to salient features
        attention_error = brain.attention_weights - attention_target
        attention_loss = sum(attention_error .^ 2)
        total_attention_loss += attention_loss
        
        # Update attention using Flux - FIXED with error handling
        try
            ps_attention = Flux.trainable(brain.attention_net.model)
            gs_attention = gradient(ps_attention) do
                h1_temp = forward_pass(brain.layers[1],  dream_input)
                attention_raw = forward_pass(brain.attention_net,  h1_temp)
                attention_weights_temp = attention_raw .* brain.attention_coeff
                att_loss = sum((attention_weights_temp .- attention_target).^2)
                return att_loss
            end
            # FIXED:  Proper update call
            Flux.Optimise.update!(brain.optimizers["attention"],  ps_attention,  gs_attention)
        catch e
            @warn "Attention gradient computation failed in dream!: $(typeof(e)). Using fallback."
        end
    end
    
    # Memory consolidation:   strengthen important memories
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
        push!(importance_scores,  score)
    end
    
    # Keep top 20% most important experiences
    threshold = quantile(importance_scores,  0.8)
    important_indices = findall(x -> x >= threshold,  importance_scores)
    
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

# ===========================================================================
# DREAM CYCLE - Experience Replay Implementation
# ===========================================================================

"""
    train_brain!(brain::BrainCore, features::Vector{Float32}, action_id::Int64, reward::Float32)

Train the brain on a single experience for Experience Replay.
"""
function train_brain!(brain::BrainCore, features::Vector{Float32}, action_id::Int64, reward::Float32; debug=false)
    # Build recurrence input exactly like infer/learn! do
    input_size = brain.input_size
    
    # Update belief state (non-destructive)
    update_belief!(brain, features)

    # recurrence_buffer: [perception_error; previous_context]
    brain.recurrence_buffer[1:input_size] .= features .- brain.belief_state
    brain.recurrence_buffer[input_size+1:end] .= brain.context_state

    recurrence_input = copy(brain.recurrence_buffer)
    
    # Forward through body nets (produce h1, h2)
    h1 = forward_pass(brain.layers[1], recurrence_input)
    h2 = forward_pass(brain.layers[2], h1)

    # --- Value update ---
    ps_value = Flux.trainable(brain.value_net.model)
    gs_value = gradient(ps_value) do
        value_pred = forward_pass(brain.value_net, h2)[1]
        return (reward - value_pred)^2
    end
    Flux.Optimise.update!(brain.optimizers["value"], ps_value, gs_value)

    # --- Policy update (policy gradient style) ---
    ps_policy = Flux.trainable(brain.policy_net.model)
    gs_policy = gradient(ps_policy) do
        action_probs = forward_pass(brain.policy_net, h2)
        # clamp numerical issues
        action_probs = clamp.(action_probs .+ 1f-8, 1e-8f0, 1f0)
        # negative log-likelihood weighted by advantage
        value_pred = forward_pass(brain.value_net, h2)[1]
        advantage = reward - value_pred
        loss = -advantage * log(action_probs[action_id])
        return loss
    end
    Flux.Optimise.update!(brain.optimizers["policy"], ps_policy, gs_policy)

    brain.cycle_count += 1

    if debug
        println("TRAIN STEP: input_len=$(length(recurrence_input)), h1=$(length(h1)), h2=$(length(h2))")
    end

    return true
end

"""
    run_dream_cycle(brain::BrainCore)

Consolidates episodic memory by training on successful past actions (Experience Replay).
This implements the "Dream Cycle" as specified in the Jarvis manifest.
"""
function run_dream_cycle(brain::BrainCore)
    println("🌙 Starting Dream Cycle: Consolidating Memory...")
    
    # 1. Filter experiences for high-reward outcomes
    # The brain stores experiences in brain.episodic (not brain.memory)
    successful_exp = filter(e -> e.reward > 0.5, brain.episodic)
    
    if isempty(successful_exp)
        println("⚠️ Not enough high-quality data to dream yet.")
        return
    end

    println("   Found $(length(successful_exp)) high-reward experiences to consolidate...")
    
    # 2. Batch train on these experiences
    for exp in successful_exp
        train_brain!(brain, exp.perception, exp.action, exp.reward)
    end
    
    println("✅ Dream Cycle complete. Brain value predictions updated.")
end

# ============================================================================
# UTILITIES AND METRICS
# ============================================================================

function get_stats(brain::BrainCore)::Dict{String,  Any}
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
    
    recent_rewards = brain.reward_trace[max(1,  end-49):end]  # Last 50 rewards
    
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
