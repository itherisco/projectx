# adaptive-kernel/cognition/worldmodel/WorldModel.jl
# Predictive World Model - Component 4 of JARVIS Neuro-Symbolic Architecture
# Internal forward model for state prediction and counterfactual simulation

module WorldModel

using Statistics
using LinearAlgebra

# ============================================================================
# Type Definitions
# ============================================================================

"""
    mutable struct WorldModel

Internal forward model for state prediction and counterfactual simulation.
Learns causal relationships between states, actions, and rewards.

# Fields
- `transition_net::Any`: Neural network for state transitions (uses ITHERIS predictor_net)
- `reward_net::Any`: Neural network for reward prediction
- `causal_graph::Dict{Symbol, Vector{Symbol}}`: Causal relationships between variables
- `state_history::Vector{Vector{Float32}}`: Historical states for learning
- `action_history::Vector{Int}`: Historical actions taken
- `reward_history::Vector{Float32}}`: Historical rewards observed
- `horizon::Int`: Maximum simulation steps
- `uncertainty_threshold::Float32`: Confidence threshold for predictions

# Example
```julia
model = WorldModel(horizon=5, uncertainty_threshold=0.7)
```
"""
mutable struct WorldModel
    transition_net::Any  # Neural network for state transitions (uses ITHERIS predictor_net)
    reward_net::Any       # Neural network for reward prediction
    causal_graph::Dict{Symbol, Vector{Symbol}}  # Causal relationships
    
    state_history::Vector{Vector{Float32}}
    action_history::Vector{Int}
    reward_history::Vector{Float32}
    
    horizon::Int  # Max simulation steps
    uncertainty_threshold::Float32
    
    # Internal state representation (learned embeddings)
    state_mean::Vector{Float32}
    state_std::Vector{Float32}
    
    # Causal strength matrix (learned from data)
    causal_strength::Dict{Symbol, Dict{Symbol, Float32}}
    
    # Fallback transition model parameters
    transition_coefficients::Matrix{Float32}
    reward_coefficients::Vector{Float32}
    
    function WorldModel(; 
        horizon::Int=5, 
        uncertainty_threshold::Float32=0.7,
        state_dim::Int=12
    )
        new(
            nothing,  # transition_net - uses ITHERIS predictor_net
            nothing,  # reward_net
            Dict{Symbol, Vector{Symbol}}(),
            Vector{Vector{Float32}}(),
            Vector{Int}(),
            Vector{Float32}(),
            horizon,
            uncertainty_threshold,
            zeros(Float32, state_dim),  # state_mean
            ones(Float32, state_dim),   # state_std
            Dict{Symbol, Dict{Symbol, Float32}}(),
            zeros(Float32, state_dim, state_dim + 1),  # transition_coefficients (affine)
            zeros(Float32, state_dim)  # reward_coefficients
        )
    end
end

"""
    struct Trajectory

Represents a simulated trajectory through the environment.
Used for both forward simulation and counterfactual analysis.

# Fields
- `states::Vector{Vector{Float32}}`: Sequence of states
- `actions::Vector{Int}`: Sequence of actions taken
- `rewards::Vector{Float32}`: Rewards obtained at each step
- `total_reward::Float32`: Sum of all rewards in trajectory
- `confidence::Float32`: Confidence in trajectory predictions (0-1)
"""
struct Trajectory
    states::Vector{Vector{Float32}}
    actions::Vector{Int}
    rewards::Vector{Float32}
    total_reward::Float32
    confidence::Float32
end

# ============================================================================
# Core Prediction Functions
# ============================================================================

"""
    function predict_next_state(
        model::WorldModel,
        state::Vector{Float32},
        action::Int
    )::Vector{Float32}

Predict the next state given current state and action.

Uses ITHERIS predictor_net if available, otherwise falls back to 
learned linear model with Gaussian noise for uncertainty.

# Arguments
- `model::WorldModel`: The world model
- `state::Vector{Float32}`: Current state vector (12D)
- `action::Int`: Action to take

# Returns
- `Vector{Float32}`: Predicted next state (12D)

# Example
```julia
next_state = predict_next_state(model, current_state, 1)
```
"""
function predict_next_state(
    model::WorldModel,
    state::Vector{Float32},
    action::Int
)::Vector{Float32}
    state_dim = length(state)
    
    # Try using ITHERIS predictor_net if available
    if model.transition_net !== nothing
        try
            # Use ITHERIS predictor_net for state transition
            # Input: [state; action_encoding]
            action_onehot = zeros(Float32, 8)  # Assuming 8 possible actions
            if action > 0 && action <= length(action_onehot)
                action_onehot[action] = 1.0
            end
            input = vcat(state, action_onehot)
            
            # Call predictor_net if it's callable
            if isa(model.transition_net, Function) || isdefined(Main, :predictor_net)
                predictor = isdefined(Main, :predictor_net) ? Main.predictor_net : model.transition_net
                next_state = predictor(input)
                return next_state
            end
        catch
            # Fall through to linear model
        end
    end
    
    # Fallback: Use learned linear model with uncertainty
    # next_state = A * [state; 1] + noise
    # where A is the transition_coefficients matrix
    augmented_state = vcat(state, [1.0])  # Add bias term
    
    # Apply learned transition dynamics
    next_state = model.transition_coefficients * augmented_state
    
    # Add exploration noise proportional to uncertainty
    noise_scale = 1.0 - model.uncertainty_threshold
    noise = randn(Float32, state_dim) .* noise_scale .* 0.1
    next_state = next_state + noise
    
    # Ensure reasonable bounds
    next_state = clamp.(next_state, -10.0f0, 10.0f0)
    
    return next_state
end

"""
    function predict_reward(
        model::WorldModel,
        state::Vector{Float32},
        action::Int
    )::Float32

Predict the reward for a state-action pair.

# Arguments
- `model::WorldModel`: The world model
- `state::Vector{Float32}`: Current state (12D)
- `action::Int`: Action taken

# Returns
- `Float32`: Predicted reward
"""
function predict_reward(
    model::WorldModel,
    state::Vector{Float32},
    action::Int
)::Float32
    # Use reward_net if available
    if model.reward_net !== nothing
        try
            action_onehot = zeros(Float32, 8)
            if action > 0 && action <= length(action_onehot)
                action_onehot[action] = 1.0
            end
            input = vcat(state, action_onehot)
            
            if isa(model.reward_net, Function) || isdefined(Main, :reward_predictor)
                predictor = isdefined(Main, :reward_predictor) ? Main.reward_predictor : model.reward_net
                reward = predictor(input)
                return reward
            end
        catch
            # Fall through to linear model
        end
    end
    
    # Fallback: Use learned linear reward model
    action_onehot = zeros(Float32, 8)
    if action > 0 && action <= length(action_onehot)
        action_onehot[action] = 1.0
    end
    augmented = vcat(state, action_onehot)
    
    reward = dot(model.reward_coefficients[1:length(augmented)], augmented)
    
    return reward
end

# ============================================================================
# Trajectory Simulation
# ============================================================================

"""
    function simulate_trajectory(
        model::WorldModel,
        start_state::Vector{Float32},
        action_sequence::Vector{Int}
    )::Trajectory

Simulate a trajectory through the environment given an action sequence.

# Arguments
- `model::WorldModel`: The world model
- `start_state::Vector{Float32}`: Initial state
- `action_sequence::Vector{Int}`: Sequence of actions to simulate

# Returns
- `Trajectory`: Simulated trajectory with states, actions, rewards, and confidence

# Example
```julia
traj = simulate_trajectory(model, current_state, [1, 2, 3, 1, 2])
println("Expected reward: ", traj.total_reward)
```
"""
function simulate_trajectory(
    model::WorldModel,
    start_state::Vector{Float32},
    action_sequence::Vector{Int}
)::Trajectory
    states = Vector{Vector{Float32}}()
    actions = Vector{Int}()
    rewards = Vector{Float32}()
    
    current_state = copy(start_state)
    confidence = 1.0
    
    for action in action_sequence
        push!(states, copy(current_state))
        push!(actions, action)
        
        # Predict next state and reward
        next_state = predict_next_state(model, current_state, action)
        reward = predict_reward(model, current_state, action)
        
        push!(rewards, reward)
        
        # Update confidence based on uncertainty
        # Confidence decreases with each step
        confidence *= model.uncertainty_threshold
        
        current_state = next_state
        
        # Early termination if state becomes too uncertain
        if confidence < 0.1
            break
        end
    end
    
    # Add final state
    push!(states, copy(current_state))
    
    total_reward = sum(rewards)
    
    return Trajectory(states, actions, rewards, total_reward, confidence)
end

"""
    function simulate_counterfactual(
        model::WorldModel,
        actual_state::Vector{Float32},
        hypothetical_action::Int;
        horizon::Int=3
    )::Trajectory

Simulate a counterfactual "what if" scenario.

Compares what would happen if a different action were taken
versus the actual trajectory.

# Arguments
- `model::WorldModel`: The world model
- `actual_state::Vector{Float32}`: Current actual state
- `hypothetical_action::Int`: Action to simulate hypothetically
- `horizon::Int`: Number of steps to simulate (default: 3)

# Returns
- `Trajectory`: Counterfactual trajectory

# Example
```julia
# What if I had taken action 3 instead?
counterfactual = simulate_counterfactual(model, current_state, 3, horizon=3)
```
"""
function simulate_counterfactual(
    model::WorldModel,
    actual_state::Vector{Float32},
    hypothetical_action::Int;
    horizon::Int=3
)::Trajectory
    # Simulate the hypothetical action sequence
    action_sequence = fill(hypothetical_action, horizon)
    
    # Run simulation
    traj = simulate_trajectory(model, actual_state, action_sequence)
    
    return traj
end

# ============================================================================
# Risk Prediction
# ============================================================================

"""
    function predict_risk(
        model::WorldModel,
        state::Vector{Float32},
        action::Int
    )::Float32

Predict the risk of taking an action from a given state.

Risk is computed based on:
1. Uncertainty in the prediction (model confidence)
2. Potential for reaching dangerous states
3. Variance in predicted outcomes

# Arguments
- `model::WorldModel`: The world model
- `state::Vector{Float32}`: Current state
- `action::Int`: Action to evaluate

# Returns
- `Float32`: Risk score in range [0.0, 1.0]

# Example
```julia
risk = predict_risk(model, current_state, 1)
if risk > 0.7
    println("High risk action!")
end
```
"""
function predict_risk(
    model::WorldModel,
    state::Vector{Float32},
    action::Int
)::Float32
    # Sample multiple predictions to estimate uncertainty
    n_samples = 10
    predicted_states = Vector{Vector{Float32}}(undef, n_samples)
    
    for i in 1:n_samples
        predicted_states[i] = predict_next_state(model, state, action)
    end
    
    # Compute variance across predictions
    state_mean = mean(predicted_states)
    state_var = sum(var(hcat(predicted_states...), dims=2))
    
    # Uncertainty contribution to risk
    uncertainty_risk = min(state_var / 10.0, 1.0)
    
    # Check for potentially dangerous state regions
    # (states with extreme values)
    max_state_value = maximum(abs.(state_mean))
    danger_risk = clamp(max_state_value / 10.0, 0.0, 1.0)
    
    # Combine risks
    risk = 0.7 * uncertainty_risk + 0.3 * danger_risk
    
    # Apply uncertainty threshold - if model is very uncertain,
    # assume conservative (high) risk
    if length(model.state_history) < 10
        # Not enough data - be conservative
        risk = max(risk, 0.5)
    end
    
    return clamp(risk, 0.0f0, 1.0f0)
end

"""
    function predict_state_uncertainty(
        model::WorldModel,
        state::Vector{Float32},
        action::Int
    )::Float32

Calculate prediction uncertainty for a state-action pair.

# Arguments
- `model::WorldModel`: The world model
- `state::Vector{Float32}`: Current state
- `action::Int`: Action to evaluate

# Returns
- `Float32`: Uncertainty score [0.0, 1.0]
"""
function predict_state_uncertainty(
    model::WorldModel,
    state::Vector{Float32},
    action::Int
)::Float32
    n_samples = 10
    predicted_states = Vector{Vector{Float32}}(undef, n_samples)
    
    for i in 1:n_samples
        predicted_states[i] = predict_next_state(model, state, action)
    end
    
    # Compute normalized variance
    state_var = sum(var(hcat(predicted_states...), dims=2))
    uncertainty = clamp(state_var / 5.0, 0.0, 1.0)
    
    return uncertainty
end

# ============================================================================
# Causal Graph Learning
# ============================================================================

"""
    function update_causal_graph!(
        model::WorldModel,
        state::Vector{Float32},
        action::Int,
        next_state::Vector{Float32}
    )

Learn causal relationships from observed transitions.

Updates the causal graph based on state changes. Variables that
consistently precede changes in other variables are added as causal parents.

# Arguments
- `model::WorldModel`: The world model (mutated in place)
- `state::Vector{Float32}`: Current state
- `action::Int`: Action taken
- `next_state::Vector{Float32}`: Resulting state

# Example
```julia
# Learn from observed transition
update_causal_graph!(model, s_t, 1, s_t_plus_1)
```
"""
function update_causal_graph!(
    model::WorldModel,
    state::Vector{Float32},
    action::Int,
    next_state::Vector{Float32}
)
    # State dimensions correspond to different state variables
    state_dim = length(state)
    
    # Define state variable symbols (for 12D state)
    state_vars = [
        :task_progress, :resource_level, :success_rate,
        :error_count, :time_remaining, :complexity,
        :user_satisfaction, :goal_alignment, :safety_margin,
        :adaptation_level, :uncertainty, :novelty
    ]
    
    # Compute state differences
    delta = next_state - state
    
    # Update causal strength based on correlation
    # If a state variable consistently predicts another variable's change,
    # establish causal link
    
    for i in 1:min(state_dim, length(state_vars))
        var_i = state_vars[i]
        
        # Initialize if not present
        if !haskey(model.causal_graph, var_i)
            model.causal_graph[var_i] = Symbol[]
            model.causal_strength[var_i] = Dict{Symbol, Float32}()
        end
        
        # Check if action affects this variable
        if abs(delta[i]) > 0.01
            # Action has causal effect
            action_symbol = Symbol(:action_, action)
            
            if !(action_symbol in model.causal_graph[var_i])
                push!(model.causal_graph[var_i], action_symbol)
            end
            
            # Update causal strength
            strength = abs(delta[i])
            model.causal_strength[var_i][action_symbol] = 
                get(model.causal_strength[var_i], action_symbol, 0.0) * 0.9 + strength * 0.1
        end
        
        # Check for state-to-state causal relationships
        for j in 1:min(state_dim, length(state_vars))
            if i != j
                var_j = state_vars[j]
                
                # If state[j] correlates with delta[i], establish causal link
                correlation = state[j] * delta[i]
                
                if abs(correlation) > 0.05
                    if !(var_j in model.causal_graph[var_i])
                        push!(model.causal_graph[var_i], var_j)
                    end
                    
                    # Update strength
                    strength = abs(correlation)
                    model.causal_strength[var_i][var_j] = 
                        get(model.causal_strength[var_i], var_j, 0.0) * 0.9 + strength * 0.1
                end
            end
        end
    end
    
    # Limit causal graph size for efficiency
    max_parents = 5
    for var in keys(model.causal_graph)
        if length(model.causal_graph[var]) > max_parents
            # Keep strongest causal parents
            strengths = [(p, get(model.causal_strength[var], p, 0.0)) 
                        for p in model.causal_graph[var]]
            sorted = sort(strengths, by=x->x[2], rev=true)
            model.causal_graph[var] = [p for (p, _) in sorted[1:max_parents]]
        end
    end
    
    # Record transition for model learning
    push!(model.state_history, copy(state))
    push!(model.action_history, action)
    push!(model.reward_history, 0.0)  # Will be updated when reward is observed
    
    # Update state statistics for normalization
    if length(model.state_history) > 1
        all_states = hcat(model.state_history...)
        model.state_mean = mean(all_states, dims=2)[:]
        model.state_std = max.(std(all_states, dims=2)[:], 0.1f0)
    end
    
    # Update linear transition model using recent history
    if length(model.state_history) >= state_dim + 1
        update_transition_model!(model)
    end
end

"""
    function update_transition_model!(model::WorldModel)

Update the linear transition model using recorded history.

Uses least squares to fit a linear model predicting next_state from
current_state and action.
"""
function update_transition_model!(model::WorldModel)
    history_len = length(model.state_history)
    state_dim = length(model.state_history[1])
    
    # Use last min(100, history_len) samples for efficiency
    n_samples = min(100, history_len - 1)
    start_idx = history_len - n_samples
    
    # Build regression matrices
    X = zeros(Float32, n_samples, state_dim + 1)  # +1 for bias
    Y = zeros(Float32, n_samples, state_dim)
    
    for i in 1:n_samples
        idx = start_idx + i - 1
        X[i, 1:state_dim] = model.state_history[idx]
        X[i, end] = 1.0  # bias
        Y[i, :] = model.state_history[idx + 1]
    end
    
    # Solve least squares: Y ≈ X * W'
    # W' = (X'X)^(-1) X'Y
    try
        XtX = X' * X + 0.01 * I  # regularization
        XtY = X' * Y
        W = XtX \ XtY
        
        model.transition_coefficients = W'
    catch
        # Keep existing coefficients if regression fails
    end
end

"""
    function get_causal_parents(
        model::WorldModel,
        variable::Symbol
    )::Vector{Symbol}

Get variables that causally affect the given variable.

# Arguments
- `model::WorldModel`: The world model
- `variable::Symbol`: Target variable symbol

# Returns
- `Vector{Symbol}`: List of causal parent variables

# Example
```julia
parents = get_causal_parents(model, :task_progress)
```
"""
function get_causal_parents(
    model::WorldModel,
    variable::Symbol
)::Vector{Symbol}
    if haskey(model.causal_graph, variable)
        return model.causal_graph[variable]
    else
        return Symbol[]
    end
end

"""
    function get_causal_strength(
        model::WorldModel,
        effect::Symbol,
        cause::Symbol
    )::Float32

Get the strength of causal relationship from cause to effect.

# Arguments
- `model::WorldModel`: The world model
- `effect::Symbol`: Effect variable
- `cause::Symbol`: Cause variable

# Returns
- `Float32`: Causal strength [0.0, 1.0]
"""
function get_causal_strength(
    model::WorldModel,
    effect::Symbol,
    cause::Symbol
)::Float32
    if haskey(model.causal_strength, effect)
        return get(model.causal_strength[effect], cause, 0.0)
    end
    return 0.0
end

# ============================================================================
# Theory-of-Mind Abstraction
# ============================================================================

"""
    function infer_user_intent(
        model::WorldModel,
        user_actions::Vector{Int},
        context::Vector{Float32}
    )::Vector{Float32}

Infer user intent from observed actions and context.

This is a simplified Theory-of-Mind abstraction that identifies
patterns in user behavior and maps them to intent vectors.

# Arguments
- `model::WorldModel`: The world model
- `user_actions::Vector{Int}`: Sequence of recent user actions
- `context::Vector{Float32}`: Current context vector

# Returns
- `Vector{Float32}`: Inferred intent vector

# Example
```julia
intent = infer_user_intent(model, [1, 2, 1, 3], context)
```
"""
function infer_user_intent(
    model::WorldModel,
    user_actions::Vector{Int},
    context::Vector{Float32}
)::Vector{Float32}
    # Intent vector dimensions
    intent_dim = 8
    
    if isempty(user_actions)
        return zeros(Float32, intent_dim)
    end
    
    # Analyze action patterns
    action_counts = zeros(Float32, 8)
    for a in user_actions
        if a > 0 && a <= 8
            action_counts[a] += 1
        end
    end
    
    # Normalize by number of actions
    n_actions = length(user_actions)
    action_freq = action_counts / max(n_actions, 1)
    
    # Infer intent dimensions
    intent = zeros(Float32, intent_dim)
    
    # Intent 1: Goal-oriented (consistent actions toward similar targets)
    intent[1] = 1.0 - std(action_counts[action_counts .> 0]) / max(mean(action_counts[action_counts .> 0]), 0.1)
    
    # Intent 2: Exploratory (diverse actions)
    intent[2] = sum(action_counts .> 0) / 8.0
    
    # Intent 3: Time pressure (fast action sequence)
    intent[3] = min(n_actions / 10.0, 1.0)
    
    # Intent 4: Risk tolerance
    intent[4] = sum(action_counts[[1, 2, 3]]) / max(sum(action_counts), 1)  # Conservative actions
    
    # Intent 5: Learning mode
    intent[5] = action_freq[4]  # Asking for help action
    
    # Intent 6: Efficiency focus
    intent[6] = action_freq[1]  # Speed action
    
    # Intent 7: Quality focus  
    intent[7] = action_freq[2]  # Thorough action
    
    # Intent 8: Collaboration
    intent[8] = action_freq[5]  # Coordinate action
    
    # Incorporate context if provided
    if length(context) >= intent_dim
        intent = 0.7 * intent + 0.3 * context[1:intent_dim]
    end
    
    return intent
end

# ============================================================================
# Planning Integration
# ============================================================================

"""
    function find_best_action(
        model::WorldModel,
        current_state::Vector{Float32},
        goal_state::Vector{Float32};
        horizon::Int=5
    )::Int

Find the best action to take to reach a goal state.

Uses lookahead search to evaluate possible action sequences
and selects the action that maximizes expected cumulative reward.

# Arguments
- `model::WorldModel`: The world model
- `current_state::Vector{Float32}`: Current state
- `goal_state::Vector{Float32}`: Target goal state
- `horizon::Int`: Planning horizon (default: 5)

# Returns
- `Int`: Best action index to take

# Example
```julia
best_action = find_best_action(model, current_state, goal_state, horizon=5)
```
"""
function find_best_action(
    model::WorldModel,
    current_state::Vector{Float32},
    goal_state::Vector{Float32};
    horizon::Int=5
)::Int
    n_actions = 8  # Assume 8 possible actions
    
    # Evaluate each action with lookahead
    best_action = 1
    best_score = -Inf
    
    for action in 1:n_actions
        # Simulate taking this action and then following optimal policy
        score = evaluate_action_sequence(
            model, 
            current_state, 
            goal_state, 
            [action],
            horizon
        )
        
        if score > best_score
            best_score = score
            best_action = action
        end
    end
    
    return best_action
end

"""
    function evaluate_action_sequence(
        model::WorldModel,
        start_state::Vector{Float32},
        goal_state::Vector{Float32},
        action_sequence::Vector{Int},
        max_horizon::Int
    )::Float32

Evaluate the expected value of an action sequence.

Computes reward based on:
1. Progress toward goal (negative distance)
2. Risk penalty
3. Confidence in predictions
"""
function evaluate_action_sequence(
    model::WorldModel,
    start_state::Vector{Float32},
    goal_state::Vector{Float32},
    action_sequence::Vector{Int},
    max_horizon::Int
)::Float32
    # Simulate trajectory
    traj = simulate_trajectory(model, start_state, action_sequence[1:min(length(action_sequence), max_horizon)])
    
    # Compute goal progress
    final_state = isempty(traj.states) ? start_state : traj.states[end]
    distance_to_goal = norm(final_state - goal_state)
    
    # Reward is negative distance (we want to minimize distance)
    goal_reward = -distance_to_goal
    
    # Add trajectory reward
    total_reward = traj.total_reward + goal_reward
    
    # Penalize by risk
    risk_penalty = 0.0
    for (state, action) in zip(traj.states[1:end-1], traj.actions)
        risk = predict_risk(model, state, action)
        risk_penalty -= risk * 0.5
    end
    
    # Penalize by uncertainty
    uncertainty_penalty = (1.0 - traj.confidence) * 2.0
    
    return total_reward + risk_penalty - uncertainty_penalty
end

"""
    function plan_to_goal(
        model::WorldModel,
        start_state::Vector{Float32},
        goal_state::Vector{Float32};
        max_steps::Int=10,
        exploration::Float32=0.1
    )::Vector{Int}

Plan a sequence of actions to reach a goal state.

Uses greedy lookahead with occasional exploration.

# Arguments
- `model::WorldModel`: The world model
- `start_state::Vector{Float32}`: Starting state
- `goal_state::Vector{Float32}`: Target state
- `max_steps::Int`: Maximum planning steps
- `exploration::Float32`: Exploration probability

# Returns
- `Vector{Int}`: Planned action sequence
"""
function plan_to_goal(
    model::WorldModel,
    start_state::Vector{Float32},
    goal_state::Vector{Float32};
    max_steps::Int=10,
    exploration::Float32=0.1
)::Vector{Int}
    action_sequence = Int[]
    current_state = copy(start_state)
    
    for step in 1:max_steps
        # Check if goal reached
        if norm(current_state - goal_state) < 0.1
            break
        end
        
        # Occasionally explore random action
        if rand() < exploration
            action = rand(1:8)
        else
            action = find_best_action(model, current_state, goal_state, horizon=3)
        end
        
        push!(action_sequence, action)
        
        # Update state (for planning purposes)
        current_state = predict_next_state(model, current_state, action)
    end
    
    return action_sequence
end

# ============================================================================
# Model Updates and Learning
# ============================================================================

"""
    function record_experience!(
        model::WorldModel,
        state::Vector{Float32},
        action::Int,
        reward::Float32
    )

Record an experience tuple for learning.

# Arguments
- `model::WorldModel`: The world model (mutated)
- `state::Vector{Float32}`: Observed state
- `action::Int`: Action taken
- `reward::Float32`: Reward received
"""
function record_experience!(
    model::WorldModel,
    state::Vector{Float32},
    action::Int,
    reward::Float32
)
    # Store in history
    push!(model.state_history, copy(state))
    push!(model.action_history, action)
    push!(model.reward_history, reward)
    
    # Limit history size for memory efficiency
    max_history = 1000
    if length(model.state_history) > max_history
        model.state_history = model.state_history[end-max_history+1:end]
        model.action_history = model.action_history[end-max_history+1:end]
        model.reward_history = model.reward_history[end-max_history+1:end]
    end
    
    # Update statistics
    if length(model.state_history) > 1
        all_states = hcat(model.state_history...)
        model.state_mean = mean(all_states, dims=2)[:]
        model.state_std = max.(std(all_states, dims=2)[:], 0.1f0)
    end
    
    # Update transition model
    if length(model.state_history) >= length(model.state_history[1]) + 1
        update_transition_model!(model)
    end
end

"""
    function reset_model!(model::WorldModel)

Reset the world model to initial state.

# Arguments
- `model::WorldModel`: The world model to reset
"""
function reset_model!(model::WorldModel)
    model.state_history = Vector{Vector{Float32}}()
    model.action_history = Vector{Int}()
    model.reward_history = Vector{Float32}()
    model.causal_graph = Dict{Symbol, Vector{Symbol}}()
    model.causal_strength = Dict{Symbol, Dict{Symbol, Float32}}()
    model.transition_coefficients = zeros(Float32, 12, 13)
    model.reward_coefficients = zeros(Float32, 12)
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    function get_model_confidence(model::WorldModel)::Float32

Get overall model confidence based on history and uncertainty.

# Arguments
- `model::WorldModel`: The world model

# Returns
- `Float32`: Confidence score [0.0, 1.0]
"""
function get_model_confidence(model::WorldModel)::Float32
    # Confidence increases with more data
    data_confidence = min(length(model.state_history) / 100.0, 1.0)
    
    # Confidence based on causal graph coverage
    n_edges = sum(length(parents) for parents in values(model.causal_graph))
    graph_confidence = min(n_edges / 20.0, 1.0)
    
    return 0.6 * data_confidence + 0.4 * graph_confidence
end

"""
    function get_state_prediction_error(
        model::WorldModel,
        actual_next_state::Vector{Float32},
        predicted_next_state::Vector{Float32}
    )::Float32

Compute prediction error for a transition.

# Arguments
- `model::WorldModel`: The world model
- `actual_next_state::Vector{Float32}`: Actually observed next state
- `predicted_next_state::Vector{Float32}`: Predicted next state

# Returns
- `Float32`: Normalized prediction error
"""
function get_state_prediction_error(
    model::WorldModel,
    actual_next_state::Vector{Float32},
    predicted_next_state::Vector{Float32}
)::Float32
    error = norm(actual_next_state - predicted_next_state)
    
    # Normalize by typical state magnitude
    normalized_error = error / max(norm(actual_next_state), 1.0)
    
    return clamp(normalized_error, 0.0, 1.0)
end

# ============================================================================
# Integration with ITHERIS
# ============================================================================

"""
    function set_predictor_net!(model::WorldModel, predictor)

Set the ITHERIS predictor network for state transitions.

# Arguments
- `model::WorldModel`: The world model
- `predictor`: Neural network function or model
"""
function set_predictor_net!(model::WorldModel, predictor)
    model.transition_net = predictor
end

"""
    function set_reward_net!(model::WorldModel, reward_predictor)

Set the reward prediction network.

# Arguments
- `model::WorldModel`: The world model
- `reward_predictor`: Neural network function or model
"""
function set_reward_net!(model::WorldModel, reward_predictor)
    model.reward_net = reward_predictor
end

# ============================================================================
# Export all public types and functions
# ============================================================================

export
    # Core types
    WorldModel,
    Trajectory,
    
    # Prediction functions
    predict_next_state,
    predict_reward,
    predict_risk,
    predict_state_uncertainty,
    
    # Trajectory functions
    simulate_trajectory,
    simulate_counterfactual,
    
    # Causal functions
    update_causal_graph!,
    get_causal_parents,
    get_causal_strength,
    
    # Theory of Mind
    infer_user_intent,
    
    # Planning
    find_best_action,
    plan_to_goal,
    
    # Model management
    record_experience!,
    reset_model!,
    get_model_confidence,
    get_state_prediction_error,
    set_predictor_net!,
    set_reward_net!

end  # module WorldModel
