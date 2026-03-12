# Policy Gradient Extensions for OnlineLearning.jl
# Implements REINFORCE with GAE and PPO algorithms

module PolicyGradient

using LinearAlgebra
using Statistics

# ============================================================================
# POLICY GRADIENT TYPES
# ============================================================================

"""
    PolicyGradientConfig - Configuration for policy gradient algorithms
"""
mutable struct PolicyGradientConfig
    gamma::Float32
    lam::Float32
    clip_epsilon::Float32
    value_coef::Float32
    entropy_coef::Float32
    max_gradient_norm::Float32
    
    function PolicyGradientConfig(;
        gamma::Float32=Float32(0.99),
        lam::Float32=Float32(0.95),
        clip_epsilon::Float32=Float32(0.2),
        value_coef::Float32=Float32(0.5),
        entropy_coef::Float32=Float32(0.01),
        max_gradient_norm::Float32=Float32(0.5)
    )
        new(gamma, lam, clip_epsilon, value_coef, entropy_coef, max_gradient_norm)
    end
end

"""
    Trajectory - Storage for collected experience
"""
mutable struct Trajectory
    states::Vector{Vector{Float32}}
    actions::Vector{Int}
    rewards::Vector{Float32}
    dones::Vector{Bool}
    log_probs::Vector{Float32}
    values::Vector{Float32}
    
    function Trajectory()
        new(
            Vector{Vector{Float32}}(),
            Vector{Int}(),
            Vector{Float32}(),
            Vector{Bool}(),
            Vector{Float32}(),
            Vector{Float32}()
        )
    end
end

Base.length(t::Trajectory)::Int = length(t.rewards)

"""
    PolicyGradientState - State for policy gradient learning
"""
mutable struct PolicyGradientState
    config::PolicyGradientConfig
    current_trajectory::Trajectory
    policy_logits::Union{Matrix{Float32}, Nothing}
    value_weights::Union{Matrix{Float32}, Nothing}
    value_bias::Union{Vector{Float32}, Nothing}
    old_log_probs::Vector{Float32}
    policy_loss_history::Vector{Float32}
    value_loss_history::Vector{Float32}
    
    function PolicyGradientState(;
        config::PolicyGradientConfig=PolicyGradientConfig(),
        state_dim::Int=10,
        action_dim::Int=5
    )
        policy_logits = randn(Float32, action_dim, state_dim) * Float32(0.01)
        value_weights = randn(Float32, 1, state_dim) * Float32(0.01)
        value_bias = zeros(Float32, 1)
        
        new(
            config,
            Trajectory(),
            policy_logits,
            value_weights,
            value_bias,
            Vector{Float32}(),
            Vector{Float32}(),
            Vector{Float32}()
        )
    end
end

function create_policy_gradient_state(
    state_dim::Int=10,
    action_dim::Int=5;
    gamma::Float32=Float32(0.99),
    lam::Float32=Float32(0.95),
    clip_epsilon::Float32=Float32(0.2)
)::PolicyGradientState
    config = PolicyGradientConfig(gamma=gamma, lam=lam, clip_epsilon=clip_epsilon)
    PolicyGradientState(config=config, state_dim=state_dim, action_dim=action_dim)
end

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

function softmax(x::Vector{Float32})::Vector{Float32}
    max_x = maximum(x)
    exp_x = exp.(x .- max_x)
    return exp_x ./ sum(exp_x)
end

function compute_log_prob(
    logits::Matrix{Float32},
    state::Vector{Float32},
    action::Int
)::Float32
    action_logits = logits * state
    probs = softmax(action_logits)
    prob = clamp(probs[action], Float32(1e-8), Float32(1.0) - Float32(1e-8))
    return log(prob)
end

function compute_action_probabilities(
    logits::Matrix{Float32},
    state::Vector{Float32}
)::Vector{Float32}
    action_logits = logits * state
    return softmax(action_logits)
end

function sample_action(probs::Vector{Float32})::Int
    r = rand(Float32)
    cumulative = Float32(0.0)
    for (i, p) in enumerate(probs)
        cumulative += p
        if r <= cumulative
            return i
        end
    end
    return length(probs)
end

function compute_value(
    state::Vector{Float32},
    value_weights::Matrix{Float32},
    value_bias::Vector{Float32}
)::Float32
    return dot(value_weights, state) + value_bias[1]
end

"""
    compute_discounted_returns(rewards, gamma)

Compute discounted cumulative returns from rewards.
G_t = r_t + γ * r_{t+1} + γ² * r_{t+2} + ...
"""
function compute_discounted_returns(
    rewards::Vector{Float32},
    gamma::Float32
)::Vector{Float32}
    T = length(rewards)
    returns = zeros(Float32, T)
    cumulative = Float32(0.0)
    for t in reverse(1:T)
        cumulative = rewards[t] + gamma * cumulative
        returns[t] = cumulative
    end
    return returns
end

"""
    compute_gae_advantages(rewards, values, dones, gamma, lam)

Compute Generalized Advantage Estimation (GAE).
A_t = Σ (γλ)^l * δ_t+l
δ_t = r_t + γV(s_t+1) - V(s_t)
"""
function compute_gae_advantages(
    rewards::Vector{Float32},
    values::Vector{Float32},
    dones::Vector{Bool},
    gamma::Float32,
    lam::Float32
)::Tuple{Vector{Float32}, Vector{Float32}}
    T = length(rewards)
    advantages = zeros(Float32, T)
    returns = zeros(Float32, T)
    next_value = Float32(0.0)
    gae = Float32(0.0)
    
    for t in reverse(1:T)
        current_value = values[t]
        if dones[t]
            delta = rewards[t] - current_value
            next_value = Float32(0.0)
        else
            delta = rewards[t] + gamma * next_value - current_value
        end
        gae = delta + gamma * lam * gae
        advantages[t] = gae
        returns[t] = advantages[t] + current_value
        next_value = current_value
    end
    
    return advantages, returns
end

function extract_action_log_probs(
    logits::Matrix{Float32},
    states::Vector{Vector{Float32}},
    actions::Vector{Int}
)::Vector{Float32}
    log_probs = Float32[]
    for (state, action) in zip(states, actions)
        lp = compute_log_prob(logits, state, action)
        push!(log_probs, lp)
    end
    return log_probs
end

"""
    compute_policy_gradients(brain, states, actions, advantages, old_log_probs)

Compute REINFORCE policy gradients with advantage estimation.
∇J(θ) = E[∇log π(a|s) * A(s,a)]
"""
function compute_policy_gradients(
    brain::Any,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    advantages::Vector{Float32},
    old_log_probs::Vector{Float32}
)::Dict
    gradients = Dict{String, Any}()
    
    if !hasproperty(brain, :policy_state) || brain.policy_state === nothing
        @warn "No policy gradient state found, using fallback gradients"
        gradients["policy_gradients"] = randn(Float32, 5, 10) * Float32(0.01)
        gradients["value_gradients"] = (randn(Float32, 1, 10) * Float32(0.01), zeros(Float32, 1))
        return gradients
    end
    
    pg_state = brain.policy_state
    config = pg_state.config
    policy_logits = pg_state.policy_logits
    value_weights = pg_state.value_weights
    value_bias = pg_state.value_bias
    
    if policy_logits === nothing || value_weights === nothing
        @warn "Policy or value network not initialized"
        gradients["policy_gradients"] = randn(Float32, 5, 10) * Float32(0.01)
        gradients["value_gradients"] = (randn(Float32, 1, 10) * Float32(0.01), zeros(Float32, 1))
        return gradients
    end
    
    T = length(states)
    if T == 0
        gradients["policy_gradients"] = zeros(Float32, size(policy_logits))
        gradients["value_gradients"] = (zeros(Float32, size(value_weights)), zeros(Float32, size(value_bias)))
        return gradients
    end
    
    policy_grad = zeros(Float32, size(policy_logits))
    
    for t in 1:T
        state = states[t]
        action = actions[t]
        advantage = advantages[t]
        probs = compute_action_probabilities(policy_logits, state)
        action_prob = clamp(probs[action], Float32(1e-8), Float32(1.0))
        grad_log_prob = zeros(Float32, length(probs))
        for a in 1:length(probs)
            if a == action
                grad_log_prob[a] = (Float32(1.0) - probs[a]) / action_prob
            else
                grad_log_prob[a] = -probs[a] / action_prob
            end
        end
        policy_grad .+= (grad_log_prob * transpose(state)) * advantage / Float32(T)
    end
    
    value_grad_weights = zeros(Float32, size(value_weights))
    value_grad_bias = zeros(Float32, size(value_bias))
    
    for t in 1:T
        state = states[t]
        value_pred = compute_value(state, value_weights, value_bias)
        return_estimate = value_pred + advantages[t]
        error = value_pred - return_estimate
        value_grad_weights .+= Float32(2.0) * error * transpose(state) / Float32(T)
        value_grad_bias[1] += Float32(2.0) * error / Float32(T)
    end
    
    # Entropy bonus
    entropy_bonus = Float32(0.0)
    eps = Float32(1e-8)
    for state in states
        probs = compute_action_probabilities(policy_logits, state)
        entropy_bonus -= sum(p .* log.(clamp.(p, eps, Float32(1.0))))
    end
    entropy_bonus /= Float32(T)
    
    # Simplified entropy gradient
    for t in 1:T
        state = states[t]
        probs = compute_action_probabilities(policy_logits, state)
        entropy_term = sum(probs .* log.(clamp.(probs, eps, Float32(1.0))))
        entropy_grad = probs .* (entropy_term .- log.(clamp.(probs, eps, Float32(1.0))) .- Float32(1.0))
        policy_grad .+= config.entropy_coef * (entropy_grad * transpose(state)) / Float32(T)
    end
    
    gradients["policy_gradients"] = policy_grad
    gradients["value_gradients"] = (value_grad_weights, value_grad_bias)
    gradients["policy_loss"] = -mean(advantages)
    gradients["entropy"] = entropy_bonus
    
    return gradients
end

"""
    compute_ppo_loss(brain, states, actions, advantages, old_log_probs)

Compute PPO (Proximal Policy Optimization) clipped loss.
L^CLIP(θ) = E[min(r(θ)*A, clip(r(θ), 1-ε, 1+ε)*A)]
"""
function compute_ppo_loss(
    brain::Any,
    states::Vector{Vector{Float32}},
    actions::Vector{Int},
    advantages::Vector{Float32},
    old_log_probs::Vector{Float32}
)::Dict
    result = Dict{String, Any}()
    
    if !hasproperty(brain, :policy_state) || brain.policy_state === nothing
        @warn "No policy gradient state for PPO"
        result["loss"] = Float32(0.0)
        result["clip_fraction"] = Float32(0.0)
        return result
    end
    
    pg_state = brain.policy_state
    config = pg_state.config
    policy_logits = pg_state.policy_logits
    
    if policy_logits === nothing
        result["loss"] = Float32(0.0)
        result["clip_fraction"] = Float32(0.0)
        return result
    end
    
    T = length(states)
    if T == 0
        result["loss"] = Float32(0.0)
        result["clip_fraction"] = Float32(0.0)
        return result
    end
    
    clip_eps = config.clip_epsilon
    policy_losses = Float32[]
    clip_fractions = Float32[]
    
    for t in 1:T
        state = states[t]
        action = actions[t]
        advantage = advantages[t]
        old_log_prob = old_log_probs[t]
        new_log_prob = compute_log_prob(policy_logits, state, action)
        ratio = exp(new_log_prob - old_log_prob)
        ratio_clamped = clamp(ratio, Float32(1.0) - clip_eps, Float32(1.0) + clip_eps)
        surr1 = ratio * advantage
        surr2 = ratio_clamped * advantage
        policy_loss = min(surr1, surr2)
        push!(policy_losses, policy_loss)
        if abs(ratio - Float32(1.0)) > clip_eps
            push!(clip_fractions, Float32(1.0))
        else
            push!(clip_fractions, Float32(0.0))
        end
    end
    
    ppo_loss = -mean(policy_losses)
    clip_fraction = mean(clip_fractions)
    result["loss"] = ppo_loss
    result["clip_fraction"] = clip_fraction
    result["surrogate_loss"] = -mean(policy_losses)
    
    return result
end

"""
    update_value_network!(brain, states, returns; learning_rate)

Update value network to minimize MSE between predicted and actual returns.
L = (V(s) - G_t)²
"""
function update_value_network!(
    brain::Any,
    states::Vector{Vector{Float32}},
    returns::Vector{Float32};
    learning_rate::Float32=Float32(0.001)
)::Float32
    if !hasproperty(brain, :policy_state) || brain.policy_state === nothing
        return Float32(0.0)
    end
    
    pg_state = brain.policy_state
    value_weights = pg_state.value_weights
    value_bias = pg_state.value_bias
    
    if value_weights === nothing || value_bias === nothing
        return Float32(0.0)
    end
    
    T = length(states)
    if T == 0
        return Float32(0.0)
    end
    
    total_loss = Float32(0.0)
    
    for t in 1:T
        state = states[t]
        target = returns[t]
        value_pred = compute_value(state, value_weights, value_bias)
        error = value_pred - target
        loss = error * error
        total_loss += loss
        grad = Float32(2.0) * error
        value_weights .-= learning_rate * grad * transpose(state)
        value_bias[1] -= learning_rate * grad
    end
    
    mean_loss = total_loss / Float32(T)
    push!(pg_state.value_loss_history, mean_loss)
    if length(pg_state.value_loss_history) > 100
        popfirst!(pg_state.value_loss_history)
    end
    
    return mean_loss
end

"""
    collect_trajectory(brain, env, initial_state, max_steps)

Collect a trajectory by running the policy in the environment.
"""
function collect_trajectory(
    brain::Any,
    env::Any,
    initial_state::Vector{Float32},
    max_steps::Int
)::Trajectory
    trajectory = Trajectory()
    
    if hasproperty(brain, :policy_state) && brain.policy_state !== nothing
        pg_state = brain.policy_state
    else
        pg_state = create_policy_gradient_state(length(initial_state), 5)
    end
    
    policy_logits = pg_state.policy_logits
    value_weights = pg_state.value_weights
    value_bias = pg_state.value_bias
    state = deepcopy(initial_state)
    
    for step in 1:max_steps
        if policy_logits !== nothing
            probs = compute_action_probabilities(policy_logits, state)
            action = sample_action(probs)
            log_prob = log(clamp(probs[action], Float32(1e-8), Float32(1.0)))
        else
            action = rand(1:5)
            log_prob = log(Float32(0.2))
        end
        
        if value_weights !== nothing
            value = compute_value(state, value_weights, value_bias)
        else
            value = Float32(0.0)
        end
        
        reward = Float32(0.0)
        done = (step >= max_steps)
        
        push!(trajectory.states, deepcopy(state))
        push!(trajectory.actions, action)
        push!(trajectory.rewards, reward)
        push!(trajectory.dones, done)
        push!(trajectory.log_probs, log_prob)
        push!(trajectory.values, value)
        
        if done
            break
        end
        
        state = state + randn(Float32, length(state)) * Float32(0.1)
    end
    
    return trajectory
end

"""
    apply_policy_gradients!(brain, gradients, learning_rate)

Apply computed policy and value gradients to the networks.
"""
function apply_policy_gradients!(
    brain::Any,
    gradients::Dict,
    learning_rate::Float32
)::Nothing
    if !hasproperty(brain, :policy_state) || brain.policy_state === nothing
        return nothing
    end
    
    pg_state = brain.policy_state
    
    if haskey(gradients, "policy_gradients") && pg_state.policy_logits !== nothing
        policy_grad = gradients["policy_gradients"]
        pg_state.policy_logits .+= learning_rate * policy_grad
    end
    
    if haskey(gradients, "value_gradients") && pg_state.value_weights !== nothing
        value_grad = gradients["value_gradients"]
        if value_grad isa Tuple
            value_grad_weights, value_grad_bias = value_grad
            pg_state.value_weights .+= learning_rate * value_grad_weights
            pg_state.value_bias .+= learning_rate * value_grad_bias
        end
    end
    
    if haskey(gradients, "policy_loss")
        push!(pg_state.policy_loss_history, gradients["policy_loss"])
        if length(pg_state.policy_loss_history) > 100
            popfirst!(pg_state.policy_loss_history)
        end
    end
    
    return nothing
end

end # module PolicyGradient
