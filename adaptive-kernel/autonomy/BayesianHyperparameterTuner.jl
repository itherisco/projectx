# adaptive-kernel/autonomy/BayesianHyperparameterTuner.jl
# Bayesian Hyperparameter Auto-Tuning Module
#
# This module optimizes the 136.1 Hz metabolic tick loop using Bayesian optimization
# with slow-path integration. It tunes metabolic parameters to minimize inference cost
# while maintaining policy entropy within safe bounds.
#
# Architecture:
# - Fast path (136.1 Hz): MetabolicController operates normally
# - Slow path (~73.5s): Bayesian optimizer suggests parameter improvements
# - Integration: Gradual parameter changes applied to avoid destabilizing ThoughtCycle

module BayesianHyperparameterTuner

using Dates
using Statistics
using LinearAlgebra
using Random
using Logging
using JSON

# ============================================================================
# DEPENDENCY IMPORTS
# ============================================================================

# Import from SelfImprovementEngine for ArchitectureMetrics
try
    include(joinpath(@__DIR__, "SelfImprovementEngine.jl"))
    using ..SelfImprovementEngine
    const HAS_SELF_IMPROVEMENT = true
catch e
    @warn "SelfImprovementEngine not available: $e"
    const HAS_SELF_IMPROVEMENT = false
end

# Import from MetabolicController
try
    include(joinpath(@__DIR__, "..", "cognition", "metabolic", "MetabolicController.jl"))
    using ..MetabolicController
    const HAS_METABOLIC_CONTROLLER = true
catch e
    @warn "MetabolicController not available: $e"
    const HAS_METABOLIC_CONTROLLER = false
end

# ============================================================================
# CONSTANTS
# ============================================================================

# Metabolic tick loop frequency
const METABOLIC_TICK_HZ = 136.1
const METABOLIC_TICK_PERIOD_US = 1.0 / METABOLIC_TICK_HZ * 1e6  # ~7.35 µs

# Slow path interval (~73.5 seconds = 10000 ticks)
const DEFAULT_SLOW_PATH_INTERVAL = 73.5

# Parameter bounds
const PARAM_BOUNDS = Dict(
    :learning_rate => (0.0001, 0.1),
    :synaptic_decay => (0.8, 1.0),
    :attention_strength => (0.1, 2.0),
    :metabolic_budget => (0.5, 1.0),
    :homeostatic_threshold => (0.1, 0.5)
)

# Safety constraints
const MIN_ENTROPY = 0.3
const MAX_ENTROPY = 4.5
const MAX_PARAM_CHANGE_PERCENT = 0.10  # 10% max change per update
const DEFAULT_XI = 0.01  # Expected Improvement exploration parameter

# Optimization defaults
const DEFAULT_MAX_ITERATIONS = 50
const DEFAULT_CONVERGENCE_THRESHOLD = 1e-4
const DEFAULT_BETA = 2.5  # UCB exploration parameter

# GP hyperparameters
const GP_LENGTH_SCALE = 0.5
const GP_VARIANCE = 1.0
const GP_NOISE_VARIANCE = 0.01

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    BayesianTunerConfig,
    
    # Types
    Observation,
    BayesianTunerState,
    
    # Core functions
    gaussian_process_sample,
    expected_improvement,
    upper_confidence_bound,
    optimize_hyperparameters,
    evaluate_objective,
    slow_path_tick,
    
    # State management
    create_tuner_state,
    reset_tuner_state,
    is_converged,
    
    # Parameter management
    get_current_params,
    apply_parameter_changes,
    clip_params_to_bounds

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    BayesianTunerConfig - Configuration for Bayesian hyperparameter auto-tuning

# Fields
- `enabled::Bool`: Enable/disable auto-tuning
- `slow_path_interval::Float64`: Trigger every ~73.5 seconds (in seconds)
- `min_entropy::Float64`: Minimum policy entropy (0.3 to avoid being "stuck")
- `max_entropy::Float64`: Maximum policy entropy (4.5 to avoid "derangement")
- `acquisition_function::Symbol`: :ei (Expected Improvement) or :ucb (Upper Confidence Bound)
- `beta::Float64`: Exploration parameter for UCB (default: 2.5)
- `max_iterations::Int`: Maximum Bayesian optimization iterations (default: 50)
- `convergence_threshold::Float64`: When to stop (default: 1e-4)
- `xi::Float64`: Exploration parameter for EI (default: 0.01)
- `verbose::Bool`: Enable verbose logging
"""
@with_kw mutable struct BayesianTunerConfig
    enabled::Bool = false
    slow_path_interval::Float64 = DEFAULT_SLOW_PATH_INTERVAL
    min_entropy::Float64 = MIN_ENTROPY
    max_entropy::Float64 = MAX_ENTROPY
    acquisition_function::Symbol = :ei
    beta::Float64 = DEFAULT_BETA
    max_iterations::Int = DEFAULT_MAX_ITERATIONS
    convergence_threshold::Float64 = DEFAULT_CONVERGENCE_THRESHOLD
    xi::Float64 = DEFAULT_XI
    verbose::Bool = true
end

# ============================================================================
# DATA TYPES
# ============================================================================

"""
    Observation - A single observation in the Bayesian optimization

# Fields
- `params::Dict{Symbol, Float64}`: Hyperparameter configuration
- `objective_value::Float64`: Observed objective (inference cost, lower is better)
- `constraint_satisfied::Bool`: Whether entropy constraint was satisfied
- `timestamp::DateTime`: When observation was made
"""
mutable struct Observation
    params::Dict{Symbol, Float64}
    objective_value::Float64
    constraint_satisfied::Bool
    timestamp::DateTime
    
    function Observation(
        params::Dict{Symbol, Float64},
        objective_value::Float64;
        constraint_satisfied::Bool = true
    )
        new(params, objective_value, constraint_satisfied, now())
    end
end

"""
    BayesianTunerState - Runtime state for Bayesian hyperparameter tuner

# Fields
- `config::BayesianTunerConfig`: Current configuration
- `observations::Vector{Observation}`: All observations collected
- `best_params::Dict{Symbol, Float64}`: Best hyperparameters found
- `best_objective::Float64`: Best objective value observed
- `last_update_time::Float64`: Unix timestamp of last update
- `iteration::Int`: Current optimization iteration
- `convergence_history::Vector{Float64}`: History of objective improvements
- `is_converged::Bool`: Whether optimization has converged
- `param_history::Vector{Dict{Symbol, Float64}}`: History of all tested params
"""
mutable struct BayesianTunerState
    config::BayesianTunerConfig
    observations::Vector{Observation}
    best_params::Dict{Symbol, Float64}
    best_objective::Float64
    last_update_time::Float64
    iteration::Int
    convergence_history::Vector{Float64}
    is_converged::Bool
    param_history::Vector{Dict{Symbol, Float64}}
    
    function BayesianTunerState(config::BayesianTunerConfig)
        new(
            config,
            Observation[],
            Dict{Symbol, Float64}(),
            Inf,
            time(),
            0,
            Float64[],
            false,
            Dict{Symbol, Float64}[]
        )
    end
end

# ============================================================================
# PARAMETER MANAGEMENT
# ============================================================================

"""
    get_default_params()::Dict{Symbol, Float64}

Get default hyperparameter values.
"""
function get_default_params()::Dict{Symbol, Float64}
    Dict(
        :learning_rate => 0.001,
        :synaptic_decay => 0.95,
        :attention_strength => 1.0,
        :metabolic_budget => 0.8,
        :homeostatic_threshold => 0.3
    )
end

"""
    clip_params_to_bounds(params::Dict{Symbol, Float64})::Dict{Symbol, Float64}

Clip parameters to valid bounds.
"""
function clip_params_to_bounds(params::Dict{Symbol, Float64})::Dict{Symbol, Float64}
    clipped = Dict{Symbol, Float64}()
    for (key, value) in params
        if haskey(PARAM_BOUNDS, key)
            lo, hi = PARAM_BOUNDS[key]
            clipped[key] = clamp(value, lo, hi)
        else
            clipped[key] = value
        end
    end
    return clipped
end

"""
    get_current_params()::Dict{Symbol, Float64}

Get current hyperparameters from MetabolicController.
"""
function get_current_params()::Dict{Symbol, Float64}
    # Try to get from MetabolicController if available
    if HAS_METABOLIC_CONTROLLER
        try
            # Attempt to read current metabolic parameters
            # This is a placeholder - actual implementation would read from state
            return get_default_params()
        catch e
            @warn "Could not get params from MetabolicController: $e"
        end
    end
    return get_default_params()
end

"""
    apply_parameter_changes(
        current_params::Dict{Symbol, Float64},
        new_params::Dict{Symbol, Float64};
        max_change::Float64 = MAX_PARAM_CHANGE_PERCENT
    )::Dict{Symbol, Float64}

Apply gradual parameter changes to avoid destabilizing the system.
"""
function apply_parameter_changes(
    current_params::Dict{Symbol, Float64},
    new_params::Dict{Symbol, Float64};
    max_change::Float64 = MAX_PARAM_CHANGE_PERCENT
)::Dict{Symbol, Float64}
    applied = Dict{Symbol, Float64}()
    
    for (key, new_value) in new_params
        if haskey(current_params, key)
            current_value = current_params[key]
            # Calculate max allowed change
            max_delta = abs(current_value) * max_change
            delta = new_value - current_value
            # Clip delta to max allowed
            clipped_delta = clamp(delta, -max_delta, max_delta)
            applied[key] = current_value + clipped_delta
        else
            applied[key] = new_value
        end
    end
    
    # Ensure all parameters are within bounds
    return clip_params_to_bounds(applied)
end

# ============================================================================
# GAUSSIAN PROCESS FUNCTIONS
# ============================================================================

"""
    rbf_kernel(x1::Vector{Float64}, x2::Vector{Float64}, length_scale::Float64)::Float64

Radial Basis Function (RBF) kernel for Gaussian Process.
"""
function rbf_kernel(x1::Vector{Float64}, x2::Vector{Float64}, length_scale::Float64)::Float64
    diff = x1 .- x2
    sq_dist = dot(diff, diff)
    return GP_VARIANCE * exp(-0.5 * sq_dist / (length_scale^2))
end

"""
    build_kernel_matrix(points::Vector{Vector{Float64}}, noise::Float64)::Matrix{Float64}

Build the kernel matrix with noise on diagonal.
"""
function build_kernel_matrix(points::Vector{Vector{Float64}}, noise::Float64)::Matrix{Float64}
    n = length(points)
    K = zeros(n, n)
    for i in 1:n
        for j in 1:n
            K[i, j] = rbf_kernel(points[i], points[j], GP_LENGTH_SCALE)
        end
        K[i, i] += noise  # Add noise to diagonal
    end
    return K
end

"""
    params_to_vector(params::Dict{Symbol, Float64})::Vector{Float64}

Convert parameter dict to vector for GP.
"""
function params_to_vector(params::Dict{Symbol, Float64})::Vector{Float64}
    keys = [:learning_rate, :synaptic_decay, :attention_strength, 
            :metabolic_budget, :homeostatic_threshold]
    return Float64[params[k] for k in keys]
end

"""
    vector_to_params(vec::Vector{Float64})::Dict{Symbol, Float64}

Convert vector back to parameter dict.
"""
function vector_to_params(vec::Vector{Float64})::Dict{Symbol, Float64}
    keys = [:learning_rate, :synaptic_decay, :attention_strength, 
            :metabolic_budget, :homeostatic_threshold]
    return Dict(zip(keys, vec))
end

"""
    gaussian_process_sample(
        config_space::Dict{Symbol, Tuple{Float64, Float64}},
        n_samples::Int
    )::Vector{Dict{Symbol, Float64}}

Sample from prior using Gaussian Process.
Returns initial observations for Bayesian optimization.
"""
function gaussian_process_sample(
    config_space::Dict{Symbol, Tuple{Float64, Float64}},
    n_samples::Int
)::Vector{Dict{Symbol, Float64}}
    samples = Vector{Dict{Symbol, Float64}}()
    
    for _ in 1:n_samples
        sample = Dict{Symbol, Float64}()
        for (key, bounds) in config_space
            lo, hi = bounds
            # Sample uniformly within bounds (GP prior)
            sample[key] = lo + rand() * (hi - lo)
        end
        push!(samples, sample)
    end
    
    return samples
end

"""
    gp_predict(
        X_train::Vector{Vector{Float64}},
        y_train::Vector{Float64},
        X_test::Vector{Float64}
    )::Tuple{Float64, Float64}

Predict mean and variance at a test point using GP.
"""
function gp_predict(
    X_train::Vector{Vector{Float64}},
    y_train::Vector{Float64},
    X_test::Vector{Float64}
)::Tuple{Float64, Float64}
    n = length(X_train)
    
    if n == 0
        return 0.0, GP_VARIANCE
    end
    
    # Build kernel matrix
    K = build_kernel_matrix(X_train, GP_NOISE_VARIANCE)
    
    # Compute kernel vector
    k_star = [rbf_kernel(X_train[i], X_test, GP_LENGTH_SCALE) for i in 1:n]
    
    try
        # Solve linear system
        K_inv = inv(K)
        
        # Mean prediction
        mean_pred = dot(k_star, K_inv * y_train)
        
        # Variance prediction
        k_star_star = rbf_kernel(X_test, X_test, GP_LENGTH_SCALE)
        var_pred = k_star_star - dot(k_star, K_inv * k_star)
        var_pred = max(var_pred, GP_NOISE_VARIANCE)  # Ensure positive variance
        
        return mean_pred, var_pred
    catch e
        # If matrix is singular, return prior
        return 0.0, GP_VARIANCE
    end
end

# ============================================================================
# ACQUISITION FUNCTIONS
# ============================================================================

"""
    normal_cdf(x::Float64)::Float64

Standard normal CDF using error function approximation.
"""
function normal_cdf(x::Float64)::Float64
    return 0.5 * (1.0 + erf(x / sqrt(2)))
end

"""
    normal_pdf(x::Float64)::Float64

Standard normal PDF.
"""
function normal_pdf(x::Float64)::Float64
    return exp(-0.5 * x^2) / sqrt(2π)
end

"""
    expected_improvement(
        mean::Float64,
        std::Float64,
        best_f::Float64,
        xi::Float64
    )::Float64

Calculate Expected Improvement acquisition function.

EI = (mean - best_f + xi) * Φ(z) + std * φ(z)
where z = (mean - best_f + xi) / std
"""
function expected_improvement(
    mean::Float64,
    std::Float64,
    best_f::Float64,
    xi::Float64
)::Float64
    # Handle numerical edge cases
    if std < 1e-10
        return max(0.0, mean - best_f + xi)
    end
    
    z = (mean - best_f + xi) / std
    
    # Standard normal CDF and PDF
    cdf_z = normal_cdf(z)
    pdf_z = normal_pdf(z)
    
    # Expected Improvement formula
    ei = (mean - best_f + xi) * cdf_z + std * pdf_z
    
    return max(0.0, ei)
end

"""
    upper_confidence_bound(
        mean::Float64,
        std::Float64,
        beta::Float64
    )::Float64

Calculate Upper Confidence Bound acquisition function.

UCB = mean + beta * std
"""
function upper_confidence_bound(
    mean::Float64,
    std::Float64,
    beta::Float64
)::Float64
    return mean + beta * std
end

"""
    compute_acquisition(
        mean::Float64,
        std::Float64,
        config::BayesianTunerConfig;
        best_f::Float64 = 0.0
    )::Float64

Compute acquisition function value based on config.
"""
function compute_acquisition(
    mean::Float64,
    std::Float64,
    config::BayesianTunerConfig;
    best_f::Float64 = 0.0
)::Float64
    if config.acquisition_function == :ei
        return expected_improvement(mean, std, best_f, config.xi)
    elseif config.acquisition_function == :ucb
        return upper_confidence_bound(mean, std, config.beta)
    else
        @warn "Unknown acquisition function: $(config.acquisition_function), using EI"
        return expected_improvement(mean, std, best_f, config.xi)
    end
end

# ============================================================================
# OPTIMIZATION FUNCTIONS
# ============================================================================

"""
    optimize_hyperparameters(
        current_params::Dict{Symbol, Float64},
        observations::Vector{Observation}
    )::Dict{Symbol, Float64}

Run Bayesian optimization step to select next hyperparameters.
"""
function optimize_hyperparameters(
    current_params::Dict{Symbol, Float64},
    observations::Vector{Observation}
)::Dict{Symbol, Float64}
    
    if isempty(observations)
        # No observations yet, return random sample
        return gaussian_process_sample(PARAM_BOUNDS, 1)[1]
    end
    
    # Extract training data
    X_train = [params_to_vector(obs.params) for obs in observations]
    y_train = Float64[obs.objective_value for obs in observations]
    
    # Find best observed value
    best_idx = argmin(y_train)
    best_f = y_train[best_idx]
    
    # Grid search over parameter space to find next point
    best_acquisition = -Inf
    best_point = current_params
    
    # Generate candidate points
    n_candidates = 1000
    candidates = gaussian_process_sample(PARAM_BOUNDS, n_candidates)
    
    for candidate in candidates
        x_vec = params_to_vector(candidate)
        mean, var = gp_predict(X_train, y_train, x_vec)
        std = sqrt(var)
        
        acquisition = compute_acquisition(mean, std, 
            BayesianTunerConfig(acquisition_function = :ei);  # Use EI for selection
            best_f = best_f
        )
        
        if acquisition > best_acquisition
            best_acquisition = acquisition
            best_point = candidate
        end
    end
    
    return clip_params_to_bounds(best_point)
end

"""
    evaluate_objective(
        params::Dict{Symbol, Float64},
        metrics::T
    )::Float64 where T

Compute objective function for given parameters.

Primary: Minimize INFERENCE_COST
Constraint: policy_entropy must be between min_entropy and max_entropy

Returns objective value (penalized if entropy out of bounds).
"""
function evaluate_objective(
    params::Dict{Symbol, Float64},
    metrics
)::Float64
    # Extract metrics
    if HAS_SELF_IMPROVEMENT && metrics isa ArchitectureMetrics
        inference_cost = metrics.inference_cost
        entropy = metrics.entropy
    else
        # Default values if metrics not available
        inference_cost = 0.005
        entropy = 1.0
    end
    
    # Get constraint bounds from default config
    min_entropy = MIN_ENTROPY
    max_entropy = MAX_ENTROPY
    
    # Check entropy constraint
    constraint_satisfied = (min_entropy <= entropy <= max_entropy)
    
    # Apply penalty if constraint violated
    if !constraint_satisfied
        penalty = 10.0 * abs(entropy - (min_entropy + max_entropy) / 2)
        return inference_cost + penalty
    end
    
    return inference_cost
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    create_tuner_state(config::BayesianTunerConfig)::BayesianTunerState

Create and initialize tuner state.
"""
function create_tuner_state(config::BayesianTunerConfig)::BayesianTunerState
    return BayesianTunerState(config)
end

"""
    create_tuner_state(;
        enabled::Bool = false,
        slow_path_interval::Float64 = DEFAULT_SLOW_PATH_INTERVAL,
        acquisition_function::Symbol = :ei,
        kwargs...
    )::BayesianTunerState

Create tuner state with custom parameters.
"""
function create_tuner_state(;
    enabled::Bool = false,
    slow_path_interval::Float64 = DEFAULT_SLOW_PATH_INTERVAL,
    acquisition_function::Symbol = :ei,
    kwargs...
)::BayesianTunerState
    config = BayesianTunerConfig(
        enabled = enabled,
        slow_path_interval = slow_path_interval,
        acquisition_function = acquisition_function;
        kwargs...
    )
    return BayesianTunerState(config)
end

"""
    reset_tuner_state(state::BayesianTunerState)::BayesianTunerState

Reset tuner state to initial values.
"""
function reset_tuner_state(state::BayesianTunerState)::BayesianTunerState
    state.observations = Observation[]
    state.best_params = Dict{Symbol, Float64}()
    state.best_objective = Inf
    state.iteration = 0
    state.convergence_history = Float64[]
    state.is_converged = false
    state.param_history = Dict{Symbol, Float64}[]
    state.last_update_time = time()
    return state
end

"""
    is_converged(state::BayesianTunerState)::Bool

Check if optimization has converged.
"""
function is_converged(state::BayesianTunerState)::Bool
    if length(state.convergence_history) < 10
        return false
    end
    
    # Check if recent improvements are below threshold
    recent = state.convergence_history[end-9:end]
    if length(recent) < 10
        return false
    end
    
    max_improvement = maximum(recent)
    return max_improvement < state.config.convergence_threshold
end

# ============================================================================
# SLOW PATH INTEGRATION
# ============================================================================

"""
    add_observation!(
        state::BayesianTunerState,
        params::Dict{Symbol, Float64},
        objective_value::Float64,
        constraint_satisfied::Bool
    )::Nothing

Add a new observation to the state.
"""
function add_observation!(
    state::BayesianTunerState,
    params::Dict{Symbol, Float64},
    objective_value::Float64,
    constraint_satisfied::Bool
)::Nothing
    obs = Observation(params, objective_value; constraint_satisfied = constraint_satisfied)
    push!(state.observations, obs)
    push!(state.param_history, params)
    
    # Update best if improved
    if objective_value < state.best_objective
        improvement = state.best_objective - objective_value
        state.best_objective = objective_value
        state.best_params = copy(params)
        push!(state.convergence_history, improvement)
    end
    
    state.last_update_time = time()
    state.iteration += 1
    
    return nothing
end

"""
    slow_path_tick(state::BayesianTunerState)::Dict{Symbol, Float64}

Execute one step of Bayesian optimization (called every ~73.5 seconds).

This is the slow path that:
1. Gets current architecture metrics
2. Evaluates current parameters
3. Runs Bayesian optimization step
4. Returns recommended parameter changes
"""
function slow_path_tick(state::BayesianTunerState)::Dict{Symbol, Float64}
    if !state.config.enabled
        return get_current_params()
    end
    
    # Check convergence
    if is_converged(state)
        state.is_converged = true
        if state.config.verbose
            @info "Bayesian optimizer converged at iteration $(state.iteration)"
        end
        return state.best_params
    end
    
    # Check max iterations
    if state.iteration >= state.config.max_iterations
        if state.config.verbose
            @info "Max iterations reached: $(state.config.max_iterations)"
        end
        return state.best_params
    end
    
    # Get current parameters
    current_params = get_current_params()
    
    # If we have enough observations, run optimization step
    if length(state.observations) >= 2
        # Get recommended next parameters
        next_params = optimize_hyperparameters(current_params, state.observations)
        
        # Apply gradual changes
        applied_params = apply_parameter_changes(current_params, next_params)
        
        # Log the optimization step
        if state.config.verbose
            @info "Bayesian optimization step $(state.iteration + 1):" * 
                  " current=$(current_params), next=$(next_params), applied=$(applied_params)"
        end
        
        return applied_params
    else
        # Not enough observations, sample randomly
        new_params = gaussian_process_sample(PARAM_BOUNDS, 1)[1]
        
        if state.config.verbose
            @info "Sampling random params (need more observations): $new_params"
        end
        
        return clip_params_to_bounds(new_params)
    end
end

"""
    update_with_metrics!(
        state::BayesianTunerState,
        params::Dict{Symbol, Float64},
        metrics
    )::Nothing

Update tuner state with new metrics after applying parameters.
"""
function update_with_metrics!(
    state::BayesianTunerState,
    params::Dict{Symbol, Float64},
    metrics
)::Nothing
    # Evaluate objective
    objective_value = evaluate_objective(params, metrics)
    
    # Check constraint satisfaction
    if HAS_SELF_IMPROVEMENT && metrics isa ArchitectureMetrics
        entropy = metrics.entropy
        constraint_satisfied = (state.config.min_entropy <= entropy <= state.config.max_entropy)
    else
        constraint_satisfied = true
    end
    
    # Add observation
    add_observation!(state, params, objective_value, constraint_satisfied)
    
    # Check convergence after update
    if is_converged(state)
        state.is_converged = true
    end
    
    return nothing
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_tuner_status(state::BayesianTunerState)::Dict{Symbol, Any}

Get current status of the tuner.
"""
function get_tuner_status(state::BayesianTunerState)::Dict{Symbol, Any}
    return Dict(
        :enabled => state.config.enabled,
        :iteration => state.iteration,
        :n_observations => length(state.observations),
        :best_objective => state.best_objective,
        :best_params => state.best_params,
        :is_converged => state.is_converged,
        :acquisition_function => state.config.acquisition_function,
        :last_update => state.last_update_time
    )
end

"""
    to_json(state::BayesianTunerState)::String

Serialize tuner state to JSON.
"""
function to_json(state::BayesianTunerState)::String
    status = get_tuner_status(state)
    return JSON.json(status)
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    create_default_tuner()::BayesianTunerState

Create tuner with default configuration.
"""
function create_default_tuner()::BayesianTunerState
    config = BayesianTunerConfig(
        enabled = false,
        slow_path_interval = DEFAULT_SLOW_PATH_INTERVAL,
        acquisition_function = :ei,
        max_iterations = DEFAULT_MAX_ITERATIONS,
        convergence_threshold = DEFAULT_CONVERGENCE_THRESHOLD
    )
    return BayesianTunerState(config)
end

"""
    create_active_tuner()::BayesianTunerState

Create tuner with active configuration for optimization.
"""
function create_active_tuner()::BayesianTunerState
    config = BayesianTunerConfig(
        enabled = true,
        slow_path_interval = DEFAULT_SLOW_PATH_INTERVAL,
        acquisition_function = :ei,
        max_iterations = DEFAULT_MAX_ITERATIONS,
        convergence_threshold = DEFAULT_CONVERGENCE_THRESHOLD,
        verbose = true
    )
    return BayesianTunerState(config)
end

end # module BayesianHyperparameterTuner
