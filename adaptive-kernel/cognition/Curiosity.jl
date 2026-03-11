# cognition/Curiosity.jl - Intrinsic Curiosity Module (ICM) for ITHERIS
# Part of JARVIS brain Upgrade 1: Adds intrinsic motivation to make agent proactive
# Based on Pathak et al. (2017) - Intrinsic Curiosity Module

module Curiosity

using Dates
using UUIDs
using LinearAlgebra

# Export all components
export
    ICM,
    ICMConfig,
    create_icm,
    compute_intrinsic_reward,
    update_predictor!,
    reset_icm,
    get_curiosity_loss

# ============================================================================
# ICM CONFIGURATION
# ============================================================================

"""
    ICMConfig - Configuration for the Intrinsic Curiosity Module
"""
struct ICMConfig
    state_dim::Int              # Dimension of state vector
    action_dim::Int             # Dimension of action vector
    feature_dim::Int            # Dimension of feature representation
    hidden_dim::Int             # Hidden layer dimension
    learning_rate::Float64       # Learning rate for predictor
    curiosity_eta::Float64      # Intrinsic reward scaling factor
    optimizer::Any              # Optimizer (Flux.Adam)
    
    function ICMConfig(;
        state_dim::Int = 32,
        action_dim::Int = 8,
        feature_dim::Int = 64,
        hidden_dim::Int = 128,
        learning_rate::Float64 = 0.001,
        curiosity_eta::Float64 = 0.1
    )
        return new(
            state_dim,
            action_dim,
            feature_dim,
            hidden_dim,
            learning_rate,
            curiosity_eta,
            nothing  # Will be set when Flux is available
        )
    end
end

# ============================================================================
# ICM STRUCT
# ============================================================================

"""
    ICM - Intrinsic Curiosity Module
    
    Provides intrinsic motivation by rewarding the agent for learning about
    the environment's dynamics. Uses a forward-dynamics model to predict
    the next state and rewards prediction error as intrinsic curiosity.
    
    # Fields
    - `config::ICMConfig`: Configuration parameters
    - `feature_network::Any`: Encodes states to feature vectors
    - `predictor_network::Any`: Forward-dynamics model predicting next state
    - `optimizer_feature::Any`: Optimizer for feature network
    - `optimizer_predictor::Any`: Optimizer for predictor network
    - `curiosity_history::Vector{Float64}`: History of intrinsic rewards
    - `prediction_error_history::Vector{Float64}`: History of prediction errors
    - `initialized::Bool`: Whether networks are initialized
"""
mutable struct ICM
    config::ICMConfig
    feature_network::Any
    predictor_network::Any
    optimizer_feature::Any
    optimizer_predictor::Any
    curiosity_history::Vector{Float64}
    prediction_error_history::Vector{Float64}
    initialized::Bool
    
    function ICM(config::ICMConfig = ICMConfig())
        return new(
            config,
            nothing,  # feature_network
            nothing,  # predictor_network
            nothing,  # optimizer_feature
            nothing,  # optimizer_predictor
            Float64[],
            Float64[],
            false
        )
    end
end

# ============================================================================
# NEURAL NETWORK INITIALIZATION (Flux-based)
# ============================================================================

"""
    initialize_networks!(icm::ICM) -> Nothing

Initialize the neural networks for the ICM. Uses simple MLPs that can work
with or without Flux.jl. Falls back to linear models if Flux is unavailable.
"""
function initialize_networks!(icm::ICM)::Nothing
    cfg = icm.config
    
    # Try to use Flux if available, otherwise use simple linear model
    try
        # Try importing Flux
        @eval using Flux
        
        # Feature network: state -> feature representation
        # Using simple MLP architecture
        icm.feature_network = Chain(
            Dense(cfg.state_dim, cfg.hidden_dim, relu),
            Dense(cfg.hidden_dim, cfg.feature_dim)
        )
        
        # Predictor network: (feature, action) -> predicted next feature
        icm.predictor_network = Chain(
            Dense(cfg.feature_dim + cfg.action_dim, cfg.hidden_dim, relu),
            Dense(cfg.hidden_dim, cfg.feature_dim)
        )
        
        # Optimizers
        icm.optimizer_feature = Flux.Adam(cfg.learning_rate)
        icm.optimizer_predictor = Flux.Adam(cfg.learning_rate)
        
        icm.initialized = true
        
    catch e
        # Fallback to simple linear model if Flux not available
        @warn "Flux.jl not available, using simple linear model for ICM"
        
        # Simple linear feature projection
        icm.feature_network = randn(cfg.feature_dim, cfg.state_dim) * 0.01
        
        # Simple linear predictor
        icm.predictor_network = randn(cfg.feature_dim, cfg.feature_dim + cfg.action_dim) * 0.01
        
        icm.optimizer_feature = cfg.learning_rate
        icm.optimizer_predictor = cfg.learning_rate
        
        icm.initialized = true
    end
    
    return nothing
end

"""
    create_icm(;kwargs...) -> ICM

Create and initialize an ICM with given configuration.
"""
function create_icm(;kwargs...)::ICM
    config = ICMConfig(;kwargs...)
    icm = ICM(config)
    initialize_networks!(icm)
    return icm
end

# ============================================================================
# FEATURE EXTRACTION
# ============================================================================

"""
    get_features(icm::ICM, state::Vector{Float64}) -> Vector{Float64}

Extract feature representation from state using the feature network.
"""
function get_features(icm::ICM, state::Vector{Float64})::Vector{Float64}
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    # Ensure state has correct dimension
    if length(state) != cfg.state_dim
        # Pad or truncate to match expected dimension
        if length(state) < cfg.state_dim
            state_padded = vcat(state, zeros(Float64, cfg.state_dim - length(state)))
        else
            state_padded = state[1:cfg.state_dim]
        end
    else
        state_padded = state
    end
    
    try
        @eval using Flux
        # Use Flux network
        features = icm.feature_network(state_padded)
        return vec(features)  # Ensure it's a Vector
    catch e
        # Fallback to linear projection
        return icm.feature_network * state_padded
    end
end

"""
    get_features(icm::ICM, state::Matrix{Float64}) -> Matrix{Float64}

Batch feature extraction.
"""
function get_features(icm::ICM, state::Matrix{Float64})::Matrix{Float64}
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    # Ensure state has correct dimensions
    if size(state, 1) != cfg.state_dim
        error("State dimension mismatch: expected $(cfg.state_dim), got $(size(state, 1))")
    end
    
    try
        @eval using Flux
        return icm.feature_network(state)
    catch e
        # Fallback to linear projection
        return icm.feature_network * state
    end
end

# ============================================================================
# FORWARD DYNAMICS PREDICTION
# ============================================================================

"""
    predict_next_features(icm::ICM, features::Vector{Float64}, action::Vector{Float64}) -> Vector{Float64}

Predict next state features given current features and action.
"""
function predict_next_features(icm::ICM, features::Vector{Float64}, action::Vector{Float64})::Vector{Float64}
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    # Ensure action has correct dimension
    if length(action) != cfg.action_dim
        if length(action) < cfg.action_dim
            action_padded = vcat(action, zeros(Float64, cfg.action_dim - length(action)))
        else
            action_padded = action[1:cfg.action_dim]
        end
    else
        action_padded = action
    end
    
    # Concatenate features and action
    combined = vcat(features, action_padded)
    
    try
        @eval using Flux
        predicted = icm.predictor_network(combined)
        return vec(predicted)
    catch e
        # Fallback to linear prediction
        return icm.predictor_network * combined
    end
end

"""
    predict_next_features(icm::ICM, features::Matrix{Float64}, actions::Matrix{Float64}) -> Matrix{Float64}

Batch prediction of next state features.
"""
function predict_next_features(icm::ICM, features::Matrix{Float64}, actions::Matrix{Float64})::Matrix{Float64}
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    # Ensure correct dimensions
    if size(actions, 1) != cfg.action_dim
        error("Action dimension mismatch")
    end
    
    # Concatenate along feature dimension
    combined = vcat(features, actions)
    
    try
        @eval using Flux
        return icm.predictor_network(combined)
    catch e
        return icm.predictor_network * combined
    end
end

# ============================================================================
# INTRINSIC REWARD COMPUTATION
# ============================================================================

"""
    compute_intrinsic_reward(icm::ICM, state::Vector{Float64}, next_state::Vector{Float64}, action::Vector{Float64}) -> Float64

Compute intrinsic reward based on prediction error.

The intrinsic reward is calculated as:
    r_intrinsic = η * ||φ(st+1) - φ̂(st+1)||²

where:
    - φ(st+1) = actual next state features
    - φ̂(st+1) = predicted next state features
    - η = curiosity_eta (scaling factor)
"""
function compute_intrinsic_reward(
    icm::ICM,
    state::Vector{Float64},
    next_state::Vector{Float64},
    action::Vector{Float64}
)::Float64
    
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    # Get actual next state features
    actual_features = get_features(icm, next_state)
    
    # Get current state features
    current_features = get_features(icm, state)
    
    # Predict next state features
    predicted_features = predict_next_features(icm, current_features, action)
    
    # Compute prediction error (L2 squared norm)
    prediction_error = sum((actual_features - predicted_features).^2)
    
    # Scale by curiosity eta
    intrinsic_reward = icm.config.curiosity_eta * prediction_error
    
    # Update history
    push!(icm.curiosity_history, intrinsic_reward)
    push!(icm.prediction_error_history, prediction_error)
    
    # Keep history bounded
    if length(icm.curiosity_history) > 1000
        icm.curiosity_history = icm.curiosity_history[end-999:end]
        icm.prediction_error_history = icm.prediction_error_history[end-999:end]
    end
    
    return intrinsic_reward
end

"""
    compute_intrinsic_reward(
        icm::ICM,
        state::Matrix{Float64},
        next_state::Matrix{Float64},
        action::Matrix{Float64}
    ) -> Vector{Float64}

Batch computation of intrinsic rewards.
"""
function compute_intrinsic_reward(
    icm::ICM,
    state::Matrix{Float64},
    next_state::Matrix{Float64},
    action::Matrix{Float64}
)::Vector{Float64}
    
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    batch_size = size(state, 2)
    
    # Get actual and predicted features
    actual_features = get_features(icm, next_state)
    current_features = get_features(icm, state)
    predicted_features = predict_next_features(icm, current_features, action)
    
    # Compute prediction errors for batch
    errors = sum((actual_features - predicted_features).^2, dims=1)
    intrinsic_rewards = cfg.curiosity_eta * vec(errors)
    
    # Update history with mean
    push!(icm.curiosity_history, mean(intrinsic_rewards))
    push!(icm.prediction_error_history, mean(errors))
    
    return intrinsic_rewards
end

# ============================================================================
# PREDICTOR TRAINING
# ============================================================================

"""
    get_curiosity_loss(icm::ICM, state::Vector{Float64}, action::Vector{Float64}, next_state::Vector{Float64}) -> Float64

Compute the curiosity loss (inverse loss for training).
The loss is the prediction error: ||φ(st+1) - φ̂(st+1)||²
"""
function get_curiosity_loss(
    icm::ICM,
    state::Vector{Float64},
    action::Vector{Float64},
    next_state::Vector{Float64}
)::Float64
    
    # Get features
    current_features = get_features(icm, state)
    actual_next_features = get_features(icm, next_state)
    
    # Predict
    predicted_next_features = predict_next_features(icm, current_features, action)
    
    # Compute loss
    loss = sum((actual_next_features - predicted_next_features).^2)
    
    return loss
end

"""
    update_predictor!(icm::ICM, state, action, next_state) -> Float64

Update the predictor network to minimize prediction error.
This is the inverse curiosity loss - we want to minimize the prediction error
for states we care about (not maximize like the intrinsic reward).

Returns the loss value after update.
"""
function update_predictor!(
    icm::ICM,
    state::Vector{Float64},
    action::Vector{Float64},
    next_state::Vector{Float64}
)::Float64
    
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    try
        @eval using Flux
        
        # Get features
        current_features = get_features(icm, state)
        actual_next_features = get_features(icm, next_state)
        
        # Create combined input
        action_padded = length(action) == cfg.action_dim ? action : 
            vcat(action, zeros(Float64, cfg.action_dim - length(action)))
        combined = vcat(current_features, action_padded)
        
        # Compute loss and gradients
        loss() = sum((actual_next_features - icm.predictor_network(combined)).^2)
        
        # Update predictor network
        grads = Flux.gradient(() -> loss(), params(icm.predictor_network))
        Flux.update!(icm.optimizer_predictor, params(icm.predictor_network), grads)
        
        return loss()
        
    catch e
        # Fallback: simple gradient descent update
        current_features = get_features(icm, state)
        actual_next_features = get_features(icm, next_state)
        
        action_padded = length(action) == cfg.action_dim ? action : 
            vcat(action, zeros(Float64, cfg.action_dim - length(action)))
        combined = vcat(current_features, action_padded)
        
        # Prediction
        predicted = icm.predictor_network * combined
        
        # Error
        error = actual_next_features - predicted
        
        # Simple gradient update (learning_rate * error)
        icm.predictor_network .+= cfg.learning_rate * error * combined'
        
        return sum(error.^2)
    end
end

"""
    update_predictor!(icm::ICM, states::Matrix{Float64}, actions::Matrix{Float64}, next_states::Matrix{Float64}) -> Float64

Batch update of the predictor network.
"""
function update_predictor!(
    icm::ICM,
    states::Matrix{Float64},
    actions::Matrix{Float64},
    next_states::Matrix{Float64}
)::Float64
    
    if !icm.initialized
        initialize_networks!(icm)
    end
    
    cfg = icm.config
    
    try
        @eval using Flux
        
        # Get features
        current_features = get_features(icm, states)
        actual_next_features = get_features(icm, next_states)
        
        # Combine features and actions
        combined = vcat(current_features, actions)
        
        # Compute loss
        loss() = sum((actual_next_features - icm.predictor_network(combined)).^2) / size(states, 2)
        
        # Update
        grads = Flux.gradient(() -> loss(), params(icm.predictor_network))
        Flux.update!(icm.optimizer_predictor, params(icm.predictor_network), grads)
        
        return loss()
        
    catch e
        # Fallback
        current_features = get_features(icm, states)
        actual_next_features = get_features(icm, next_states)
        combined = vcat(current_features, actions)
        
        predicted = icm.predictor_network * combined
        error = actual_next_features - predicted
        
        # Average gradient across batch
        avg_error = mean(error, dims=2)
        icm.predictor_network .+= cfg.learning_rate * avg_error * combined'
        
        return sum(error.^2) / size(states, 2)
    end
end

# ============================================================================
# RESET FUNCTIONALITY
# ============================================================================

"""
    reset_icm(icm::ICM) -> Nothing

Reset the ICM to initial state, reinitializing all networks.
"""
function reset_icm(icm::ICM)::Nothing
    # Reinitialize networks
    initialize_networks!(icm)
    
    # Clear history
    empty!(icm.curiosity_history)
    empty!(icm.prediction_error_history)
    
    return nothing
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_average_curiosity(icm::ICM; window::Int = 100) -> Float64

Get average intrinsic reward over recent window.
"""
function get_average_curiosity(icm::ICM; window::Int = 100)::Float64
    if isempty(icm.curiosity_history)
        return 0.0
    end
    
    history = length(icm.curiosity_history) <= window ? 
        icm.curiosity_history : 
        icm.curiosity_history[end-window+1:end]
    
    return mean(history)
end

"""
    get_average_prediction_error(icm::ICM; window::Int = 100) -> Float64

Get average prediction error over recent window.
"""
function get_average_prediction_error(icm::ICM; window::Int = 100)::Float64
    if isempty(icm.prediction_error_history)
        return 0.0
    end
    
    history = length(icm.prediction_error_history) <= window ? 
        icm.prediction_error_history : 
        icm.prediction_error_history[end-window+1:end]
    
    return mean(history)
end

"""
    get_curiosity_stats(icm::ICM) -> Dict{String, Float64}

Get comprehensive curiosity statistics.
"""
function get_curiosity_stats(icm::ICM)::Dict{String, Float64}
    return Dict(
        "avg_curiosity" => get_average_curiosity(icm),
        "max_curiosity" => isempty(icm.curiosity_history) ? 0.0 : maximum(icm.curiosity_history),
        "min_curiosity" => isempty(icm.curiosity_history) ? 0.0 : minimum(icm.curiosity_history),
        "avg_prediction_error" => get_average_prediction_error(icm),
        "total_samples" => length(icm.curiosity_history)
    )
end

# ============================================================================
# INTEGRATION WITH DECISION SPINE
# ============================================================================

"""
    combine_rewards(external_reward::Float64, intrinsic_reward::Float64; 
                   intrinsic_weight::Float64 = 0.5) -> Float64

Combine extrinsic and intrinsic rewards for decision making.

Total reward = (1 - intrinsic_weight) * external_reward + intrinsic_weight * intrinsic_reward
"""
function combine_rewards(
    external_reward::Float64, 
    intrinsic_reward::Float64;
    intrinsic_weight::Float64 = 0.5
)::Float64
    return (1.0 - intrinsic_weight) * external_reward + intrinsic_weight * intrinsic_reward
end

"""
    get_curiosity_bonus(icm::ICM; bonus_threshold::Float64 = 0.1) -> Float64

Get a bonus based on curiosity - rewards states where the agent is learning.
Returns a positive bonus if prediction error is high (exploration bonus).
"""
function get_curiosity_bonus(icm::ICM; bonus_threshold::Float64 = 0.1)::Float64
    avg_error = get_average_prediction_error(icm)
    
    if avg_error > bonus_threshold
        return avg_error  # Bonus proportional to how much we're learning
    else
        return 0.0
    end
end

end # module Curiosity
