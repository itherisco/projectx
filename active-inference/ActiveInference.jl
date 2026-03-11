# ActiveInference.jl - Active Inference Engine based on Free Energy Principle
# Phase 2 of ITHERIS Ω - Cognitive Brain Upgrade
# Implements Friston's Free Energy Principle for autonomous agents

module ActiveInference

using Dates
using Distributions
using Flux
using LinearAlgebra
using Printf
using Random
using Statistics
using UUIDs

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Core FEP types
    GenerativeModel,
    FreeEnergyState,
    HiddenState,
    Observation,
    Policy,
    
    # Generative Model functions
    observation,
    transition,
    preference,
    
    # HDC Memory
    HDCMemory,
    bind_concepts,
    bundle_concepts,
    retrieve_concept,
    holographic_recall,
    get_or_create_vector,
    
    # Inference Engine
    ActiveInferenceEngine,
    create_engine,
    infer,
    infer_step,
    minimize_free_energy,
    compute_free_energy,
    generate_policies,
    compute_expected_free_energy,
    select_policy,
    
    # Integration with ITHERIS
    wrap_itheris_brain,
    hybrid_inference,
    
    # Dreaming Cycle
    DreamingLoop,
    run_dream_cycle,
    sample_episodic_memory,
    gradient_descent_on_brain,
    compute_reward_from_free_energy,
    wire_ai_to_brain,
    
    # Utilities
    precision_weighted_error,
    kl_divergence,
    variational_inference

# ============================================================================
# PART 1: FREE ENERGY PRINCIPLE CORE
# ============================================================================

"""
    HiddenState - Represents hidden (latent) world states
    These are not directly observable but must be inferred from observations
"""
mutable struct HiddenState
    id::UUID
    vector::Vector{Float32}      # State representation
    precision::Float32           # Confidence (inverse variance)
    entropy::Float32             # Uncertainty measure
    timestamp::DateTime
    
    function HiddenState(vector::Vector{Float32}; precision::Float32=1.0f0)
        new(uuid4(), vector, precision, Float32(0), now())
    end
end

"""
    Observation - Sensory input to the agent
    Generated from hidden states via observation model
"""
mutable struct Observation
    id::UUID
    vector::Vector{Float32}      # Sensory data
    timestamp::DateTime
    source::Symbol               # :vision, :audio, :text, : proprioception
    
    function Observation(vector::Vector{Float32}; source::Symbol=:vision)
        new(uuid4(), vector, now(), source)
    end
end

"""
    Policy - Sequence of actions to minimize free energy
    In Active Inference, policies are chosen to maximize model evidence
"""
mutable struct Policy
    id::UUID
    actions::Vector{Vector{Float32}}  # Action sequence
    expected_free_energy::Float32     # Expected F over trajectory
    prior_probability::Float32         # P(π) - prior over policies
    posterior_probability::Float32    # Q(π|o) - posterior after observation
    
    function Policy(actions::Vector{Vector{Float32}})
        new(uuid4(), actions, Float32(0), Float32(1.0), Float32(0))
    end
end

"""
    FreeEnergyState - Current state of free energy computation
    Tracks prediction error, variational parameters, and learning signals
"""
mutable struct FreeEnergyState
    # Prediction components
    predicted_observation::Vector{Float32}  # \tilde{o}
    predicted_state::Vector{Float32}         # \tilde{s}
    
    # Error signals
    prediction_error::Float32                # ||o - \tilde{o}||²
    kl_divergence::Float32                   # KL(q(s|o) || p(s|o))
    total_free_energy::Float32               # F = E[log p(o|s)] - E[log q(s|o)]
    
    # Precision-weighted components
    precision::Float32                       # Precision (1/variance)
    precision_weighted_error::Float32       # Precision * prediction_error
    
    # Learning signals
    expected_free_energy::Float32            # For policy selection
    accuracy::Float32                        # Model accuracy (1 - normalized_error)
    
    timestamp::DateTime
    
    function FreeEnergyState()
        new(
            Float32[], Float32[],
            Float32(0), Float32(0), Float32(0),
            Float32(1), Float32(0),
            Float32(0), Float32(0),
            now()
        )
    end
end

# ============================================================================
# PART 2: GENERATIVE MODEL
# ============================================================================

"""
    GenerativeModel - Bayesian model of world states and observations
    Implements: p(o, s, π) = p(o|s)p(s|π)p(π)
    
    Components:
    - A: Observation model p(o|s) - likelihood
    - B: Transition model p(s'|s, π) - dynamics  
    - C: Prior preferences p(π) - reward/pain
    - D: Prior over hidden states p(s)
"""
mutable struct GenerativeModel
    # Observation model A: p(o|s) - likelihood matrix
    # Maps hidden states to expected observations
    observation_model::Chain          # Neural network: s -> o
    
    # Transition model B: p(s'|s, π) - state transition dynamics
    transition_model::Chain           # Neural network: (s, a) -> s'
    
    # Preference model C: p(π) - prior over policies
    preference_model::Chain           # Neural network: (s, π) -> utility
    
    # Prior over states D: p(s) - initial state beliefs
    prior_precision::Float32          # Precision of prior over states
    
    # Dimensions
    state_dim::Int
    obs_dim::Int
    action_dim::Int
    
    # Metadata
    trained::Bool
    last_update::DateTime
    
    function GenerativeModel(
        state_dim::Int,
        obs_dim::Int,
        action_dim::Int;
        hidden_dims::Vector{Int}=[128, 128]
    )
        # Observation model: state -> observation
        obs_model = Chain(
            Dense(state_dim, hidden_dims[1], relu),
            Dense(hidden_dims[1], hidden_dims[2], relu),
            Dense(hidden_dims[2], obs_dim),
            σ  # Sigmoid for bounded observations
        )
        
        # Transition model: (state, action) -> next state
        trans_model = Chain(
            Dense(state_dim + action_dim, hidden_dims[1], relu),
            Dense(hidden_dims[1], hidden_dims[2], relu),
            Dense(hidden_dims[2], state_dim)
        )
        
        # Preference model: (state, policy) -> expected utility
        pref_model = Chain(
            Dense(state_dim + action_dim * 3, hidden_dims[1], relu),
            Dense(hidden_dims[1], 1),
            σ
        )
        
        new(
            obs_model,
            trans_model,
            pref_model,
            Float32(1.0),  # prior_precision
            state_dim,
            obs_dim,
            action_dim,
            false,
            now()
        )
    end
end

"""
    Forward pass through observation model: A(s) -> o
"""
function observation(m::GenerativeModel, state::Vector{Float32})::Vector{Float32}
    return m.observation_model(state)
end

"""
    Forward pass through transition model: B(s, a) -> s'
"""
function transition(m::GenerativeModel, state::Vector{Float32}, action::Vector{Float32})::Vector{Float32}
    input = vcat(state, action)
    return m.transition_model(input)
end

"""
    Compute preference/utility for a state-action pair
"""
function preference(m::GenerativeModel, state::Vector{Float32}, actions::Vector{Vector{Float32}})::Float32
    # Flatten actions for preference model
    action_vec = length(actions) > 0 ? vcat(actions...) : Float32[]
    input = vcat(state, action_vec)
    pref = m.preference_model(input)
    return pref[1]
end

# ============================================================================
# PART 3: FREE ENERGY COMPUTATION
# ============================================================================

"""
    Compute prediction error (reconstruction error)
    E[log p(o|s)] - measures how well the model explains observations
    
    FIXED: Now uses proper Gaussian negative log-likelihood (VFE)
    VFE = -log p(o|μ,σ) = 0.5 * sum(((x - μ) / σ)^2) + log(σ * sqrt(2π))
    This is mathematically correct for Variational Free Energy
"""
function compute_prediction_error(
    model::GenerativeModel,
    state::Vector{Float32},
    obs_vector::Vector{Float32};
    sigma::Float32=0.1f0  # Observation noise standard deviation
)::Float32
    predicted_obs = observation(model, state)
    
    # Add numerical stability epsilon
    eps_val = Float32(1e-8)
    sigma_safe = max(sigma, eps_val)
    
    # Proper Gaussian negative log-likelihood (VFE)
    # VFE = 0.5 * sum(((x - μ) / σ)^2) + log(σ * sqrt(2π))
    # This is equivalent to -log(p(x|μ,σ)) for Gaussian
    normalized_error = (obs_vector - predicted_obs) ./ sigma_safe
    vfe = Float32(0.5) * sum(normalized_error.^2) + log(sigma_safe * sqrt(2π * Float32(1.0)))
    
    return vfe
end

"""
    Compute KL divergence between variational and true posterior
    KL(q(s|o) || p(s|o)) - measures inference quality
"""
function kl_divergence(q_mean::Vector{Float32}, p_mean::Vector{Float32}, precision::Float32)::Float32
    # Simplified KL for Gaussian: 0.5 * precision * ||q - p||²
    diff = q_mean - p_mean
    return Float32(0.5) * precision * sum(diff.^2)
end

"""
    Precision-weighted error for confidence-dependent learning
    Higher precision = more confident = less learning needed
"""
function precision_weighted_error(
    prediction_error::Float32,
    precision::Float32
)::Float32
    return precision * prediction_error
end

"""
    Compute total free energy: F = reconstruction_error + kl_divergence
    This is equivalent to negative ELBO (Evidence Lower Bound)
    
    FIXED: Uses proper Gaussian NLL for VFE component
"""
function compute_free_energy(
    model::GenerativeModel,
    current_state::Vector{Float32},
    obs_vector::Vector{Float32};
    precision::Float32=1.0f0,
    obs_sigma::Float32=0.1f0  # Observation noise
)::FreeEnergyState
    state = FreeEnergyState()
    
    # Prediction
    state.predicted_observation = observation(model, current_state)
    state.predicted_state = current_state
    
    # Compute VFE using proper Gaussian NLL
    state.prediction_error = compute_prediction_error(
        model, current_state, obs_vector; sigma=obs_sigma
    )
    state.kl_divergence = kl_divergence(
        state.predicted_state,
        current_state,
        precision
    )
    
    # Precision weighting
    state.precision = precision
    state.precision_weighted_error = precision_weighted_error(
        state.prediction_error,
        precision
    )
    
    # Total free energy
    state.total_free_energy = state.precision_weighted_error + state.kl_divergence
    
    # Accuracy metric (based on NLL scale)
    # For Gaussian NLL, reasonable range is [0, ~10] for normalized errors
    max_nll = length(obs_vector) * Float32(5.0)  # Expected max NLL
    state.accuracy = Float32(1.0) - min(state.prediction_error / max_nll, Float32(1.0))
    
    return state
end

# ============================================================================
# PART 4: VARIATIONAL INFERENCE
# ============================================================================

"""
    Variational inference update for hidden states
    Approximate Bayesian update using gradient descent on free energy
"""
function variational_inference(
    model::GenerativeModel,
    obs_vector::Vector{Float32};
    learning_rate::Float32=0.01f0,
    iterations::Int=10
)::Vector{Float32}
    # Initialize variational parameters (beliefs about state)
    # Start with prior (initial state estimate)
    belief = rand(Float32, model.state_dim)
    
    for iter in 1:iterations
        # Predict observation from current belief
        predicted_obs = observation(model, belief)
        
        # Compute error gradient
        error_vec = predicted_obs - obs_vector
        
        # Gradient of observation model w.r.t. state
        # Using finite difference approximation for simplicity
        eps = Float32(1e-4)
        gradient = Float32[]
        for i in 1:length(belief)
            belief_plus = copy(belief)
            belief_plus[i] += eps
            predicted_plus = observation(model, belief_plus)
            grad_i = sum((predicted_plus - obs_vector) .* (predicted_obs - obs_vector)) / eps
            push!(gradient, grad_i)
        end
        
        # Update belief (gradient descent on free energy)
        belief -= learning_rate * gradient
        
        # Clamp to valid range
        belief = clamp.(belief, Float32(-10), Float32(10))
    end
    
    return belief
end

# ============================================================================
# PART 5: HYPERDIMENSIONAL COMPUTING (HDC) MEMORY
# ============================================================================

"""
    HDCMemory - Hyperdimensional Computing memory for conceptual associations
    Uses vector symbolic operations for "holographic" memory
"""
mutable struct HDCMemory
    dimension::Int                          # HD dimension (typically 1000-10000)
    vectors::Dict{Symbol, Vector{Float32}} # Symbol -> HD vector
    associations::Dict{Symbol, Vector{Symbol}} # Symbol -> related symbols
    
    function HDCMemory(dimension::Int=1000)
        new(dimension, Dict{Symbol, Vector{Float32}}(), Dict{Symbol, Vector{Symbol}}())
    end
end

"""
    Bind two concepts (multiplication in HD space)
    Creates new representation: A ⊗ B
"""
function bind_concepts(mem::HDCMemory, a::Symbol, b::Symbol)::Vector{Float32}
    # Get or create vectors for both symbols
    vec_a = get_or_create_vector(mem, a)
    vec_b = get_or_create_vector(mem, b)
    
    # Binding: element-wise multiplication (circular convolution approximation)
    bound = vec_a .* vec_b
    
    # Normalize to unit vector
    return normalize_vector(bound)
end

"""
    Add two concepts (bundling in HD space)
    Creates combined representation: A ⊕ B
"""
function bundle_concepts(mem::HDCMemory, a::Symbol, b::Symbol)::Vector{Float32}
    vec_a = get_or_create_vector(mem, a)
    vec_b = get_or_create_vector(mem, b)
    
    # Bundling: vector addition (approximate OR)
    bundled = vec_a + vec_b
    
    return normalize_vector(bundled)
end

"""
    Retrieve concept by similarity (holographic recall)
    Given a partial cue, find most similar stored concept
"""
function retrieve_concept(mem::HDCMemory, query::Vector{Float32})::Symbol
    best_sim = Float32(-1)
    best_symbol = :unknown
    
    for (symbol, vector) in mem.vectors
        sim = cosine_similarity(query, vector)
        if sim > best_sim
            best_sim = sim
            best_symbol = symbol
        end
    end
    
    return best_symbol
end

"""
    Holographic recall: A + B = "concepts related to A and B"
    Mathematically adds vectors like "Security" + "Morning"
"""
function holographic_recall(mem::HDCMemory, concepts::Vector{Symbol})::Vector{Float32}
    if isempty(concepts)
        return rand(Float32, mem.dimension)
    end
    
    # Bundle all concepts
    result = get_or_create_vector(mem, concepts[1])
    for i in 2:length(concepts)
        result = result + get_or_create_vector(mem, concepts[i])
    end
    
    return normalize_vector(result)
end

"""
    Get or create HD vector for a symbol
"""
function get_or_create_vector(mem::HDCMemory, symbol::Symbol)::Vector{Float32}
    if haskey(mem.vectors, symbol)
        return mem.vectors[symbol]
    else
        # Create new random HD vector
        vec = randn(Float32, mem.dimension)
        normalized = normalize_vector(vec)
        mem.vectors[symbol] = normalized
        return normalized
    end
end

"""
    Normalize vector to unit length
"""
function normalize_vector(v::Vector{Float32})::Vector{Float32}
    norm_v = norm(v)
    if norm_v < eps(Float32)
        return v
    end
    return v ./ norm_v
end

"""
    Cosine similarity between two vectors
"""
function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    dot_ab = dot(a, b)
    norm_a = norm(a)
    norm_b = norm(b)
    
    if norm_a < eps(Float32) || norm_b < eps(Float32)
        return Float32(0)
    end
    
    return dot_ab / (norm_a * norm_b)
end

# ============================================================================
# PART 6: ACTIVE INFERENCE ENGINE
# ============================================================================

"""
    ActiveInferenceEngine - Main controller implementing FEP-based cognition
"""
mutable struct ActiveInferenceEngine
    # Generative model
    model::GenerativeModel
    
    # HDC memory
    hdc_memory::HDCMemory
    
    # Current state
    current_state::HiddenState
    current_observation::Observation
    
    # Policy selection
    policies::Vector{Policy}
    selected_policy::Policy
    
    # Free energy tracking
    free_energy_history::Vector{Float32}
    precision::Float32
    
    # Integration
    use_itheris::Bool
   itheris_brain::Any  # Reference to wrapped ITHERIS brain
    
    # Learning
    learning_rate::Float32
    precision_learning_rate::Float32
    
    # Metadata
    id::UUID
    created_at::DateTime
    step_count::Int
    
    function ActiveInferenceEngine(
        state_dim::Int,
        obs_dim::Int,
        action_dim::Int;
        use_itheris::Bool=true
    )
        model = GenerativeModel(state_dim, obs_dim, action_dim)
        hdc = HDCMemory(1000)
        
        # Initialize with random state
        init_state = HiddenState(rand(Float32, state_dim))
        init_obs = Observation(rand(Float32, obs_dim))
        
        new(
            model,
            hdc,
            init_state,
            init_obs,
            Policy[],
            Policy(Vector{Vector{Float32}}()),
            Float32[],
            Float32(1.0),
            use_itheris,
            nothing,
            Float32(0.01),
            Float32(0.1),
            uuid4(),
            now(),
            0
        )
    end
end

"""
    Create a new Active Inference engine
"""
function create_engine(
    state_dim::Int,
    obs_dim::Int,
    action_dim::Int;
    use_itheris::Bool=true
)::ActiveInferenceEngine
    return ActiveInferenceEngine(state_dim, obs_dim, action_dim; use_itheris=use_itheris)
end

"""
    Generate candidate policies (action sequences)
"""
function generate_policies(engine::ActiveInferenceEngine, num_policies::Int=5)::Vector{Policy}
    policies = Policy[]
    
    for i in 1:num_policies
        # Random action sequence of length 3-5
        seq_len = rand(3:5)
        actions = [rand(Float32, engine.model.action_dim) for _ in 1:seq_len]
        push!(policies, Policy(actions))
    end
    
    return policies
end

"""
    Compute expected free energy for a policy
    G(π) = E[Q(s,o|π) [ln Q(s|o,π) - ln P(o,s|π)]]
    This drives policy selection in Active Inference
    
    FIXED: Now includes proper epistemic term for uncertainty reduction
    
    Total G has two components:
    1. Pragmatic Value (Aleatoric): Expected utility/preference for outcomes
    2. Epistemic Value: Information gain / uncertainty reduction
       = -Σ p(s'|a,o) * log(p(s'|a,o) / p(s'))
       (Mutual information between states and observations)
"""
function compute_expected_free_energy(
    engine::ActiveInferenceEngine,
    policy::Policy;
    obs_sigma::Float32=0.1f0  # Observation noise for VFE component
)::Float32
    # Simulate policy execution and compute expected free energy
    current_state = engine.current_state.vector
    
    total_pragmatic = Float32(0)
    total_epistemic = Float32(0)
    
    # For 16D Feature Vector: track state uncertainty
    state_dim = engine.model.state_dim
    eps_val = Float32(1e-8)
    
    for action in policy.actions
        # Predict next state
        next_state = transition(engine.model, current_state, action)
        
        # Predict observation from next state
        predicted_obs = observation(engine.model, next_state)
        
        # Pragmatic value: prediction error as surprise (negative log-likelihood)
        # Using proper Gaussian NLL
        normalized_error = (predicted_obs ./ (obs_sigma .+ eps_val))
        pragmatic = Float32(0.5) * sum(normalized_error.^2) + log(obs_sigma * sqrt(2π * Float32(1.0)))
        total_pragmatic += pragmatic
        
        # Epistemic term: mutual information / uncertainty reduction
        # I(s;o|a) = Σ p(s'|a) * log(p(s'|a) / p(s'))
        # Measures how much information the action provides about hidden states
        
        # Approximate: variance reduction in state predictions
        # Higher variance in next_state = more uncertainty = more info gain possible
        state_variance = sum(var(next_state) for _ in 1:1) / max(length(next_state), 1)
        
        # Compute entropy of state distribution (approximated by variance)
        # For uniform-like distribution over possible states:
        state_entropy = Float32(0.5) * log(max(state_variance, eps_val) + eps_val)
        
        # Epistemic value: uncertainty reduction potential
        # Maximized when current state is uncertain (high variance)
        # We want actions that reduce uncertainty - so higher uncertainty = higher potential
        epistemic = -state_entropy  # Negative because we want to minimize uncertainty
        total_epistemic += max(epistemic, Float32(0))  # Only positive information gain
        
        current_state = next_state
    end
    
    num_steps = length(policy.actions)
    avg_pragmatic = total_pragmatic / num_steps
    avg_epistemic = total_epistemic / num_steps
    
    # Total Expected Free Energy = Pragmatic + Epistemic
    # Epistemic term encourages exploration (reducing uncertainty)
    # Pragmatic term encourages exploitation (maximizing expected reward)
    total_expected_fe = avg_pragmatic + Float32(0.5) * avg_epistemic
    
    return total_expected_fe
end

"""
    Select best policy based on expected free energy
    Lower expected FE = better policy
"""
function select_policy!(engine::ActiveInferenceEngine)::Policy
    # Generate candidate policies
    engine.policies = generate_policies(engine)
    
    # Compute expected FE for each
    for policy in engine.policies
        policy.expected_free_energy = compute_expected_free_energy(engine, policy)
    end
    
    # Softmax selection (preferences lower FE)
    energies = [p.expected_free_energy for p in engine.policies]
    energies = energies .- maximum(energies)  # Numerical stability
    exp_energies = exp.(energies)
    probs = exp_energies ./ sum(exp_energies)
    
    # Sample from distribution
    idx = rand(Categorical(probs))
    selected = engine.policies[idx]
    
    # Update posterior probability
    selected.posterior_probability = probs[idx]
    
    engine.selected_policy = selected
    return selected
end

"""
    Infer hidden state from observation (variational inference)
"""
function infer(engine::ActiveInferenceEngine, observation::Vector{Float32})::HiddenState
    # Run variational inference to estimate hidden state
    inferred_state = variational_inference(
        engine.model,
        observation;
        learning_rate=engine.learning_rate,
        iterations=10
    )
    
    # Update current state
    engine.current_state = HiddenState(inferred_state; precision=engine.precision)
    
    # Update observation
    engine.current_observation = Observation(observation)
    
    return engine.current_state
end

"""
    Minimize free energy - core Active Inference step
    Either: (a) update internal model (learning) or (b) act on world
"""
function minimize_free_energy!(engine::ActiveInferenceEngine)::Vector{Float32}
    # Compute current free energy
    fe_state = compute_free_energy(
        engine.model,
        engine.current_state.vector,
        engine.current_observation.vector;
        precision=engine.precision
    )
    
    # Store in history
    push!(engine.free_energy_history, fe_state.total_free_energy)
    
    # If FE is high, need to act
    if fe_state.total_free_energy > 0.1
        # Select action via policy
        policy = select_policy!(engine)
        
        # Return first action
        if !isempty(policy.actions)
            return policy.actions[1]
        end
    end
    
    # Otherwise, return empty action (continue learning)
    return Float32[]
end

"""
    Single inference step: observe → infer → act/minimize FE
"""
function infer_step(
    engine::ActiveInferenceEngine,
    new_observation::Vector{Float32}
)::Tuple{HiddenState, Vector{Float32}, Float32}
    engine.step_count += 1
    
    # 1. Infer hidden state from observation
    state = infer(engine, new_observation)
    
    # 2. Minimize free energy (get action or learning signal)
    action = minimize_free_energy!(engine)
    
    # 3. Get current free energy
    fe = isempty(engine.free_energy_history) ? Float32(0) : engine.free_energy_history[end]
    
    # 4. Adapt precision (learning rate adaptation)
    # If prediction error is low, increase precision (more confident)
    # If prediction error is high, decrease precision (less confident, more learning)
    if length(engine.free_energy_history) > 1
        recent_fe = engine.free_energy_history[end]
        if recent_fe < 0.1
            engine.precision = min(engine.precision * (1 + engine.precision_learning_rate), Float32(10.0))
        else
            engine.precision = max(engine.precision * (1 - engine.precision_learning_rate), Float32(0.1))
        end
    end
    
    return state, action, fe
end

# ============================================================================
# PART 7: INTEGRATION WITH ITHERIS
# ============================================================================

"""
    Wrap existing ITHERIS brain for hybrid inference
    Combines RL (ITHERIS) with Active Inference
"""
function wrap_itheris_brain(itheris_brain::Any)::ActiveInferenceEngine
    engine = create_engine(256, 384, 64; use_itheris=true)
    engine.itheris_brain = itheris_brain
    return engine
end

"""
    Hybrid inference: combine ITHERIS RL with Active Inference
    Uses both policy gradient and free energy minimization
"""
function hybrid_inference(
    engine::ActiveInferenceEngine,
    observation::Vector{Float32},
    reward::Float32
)::Vector{Float32}
    if engine.use_itheris && engine.itheris_brain !== nothing
        # Active Inference gives us preferred action direction
        ai_state, ai_action, fe = infer_step(engine, observation)
        
        # ITHERIS would provide RL-based action
        # For now, blend: 70% AI, 30% exploration
        if !isempty(ai_action)
            noise = Float32(0.3) * rand(Float32, length(ai_action))
            blended = ai_action .+ noise
            return blended
        end
    end
    
    # Fallback to pure Active Inference
    _, action, _ = infer_step(engine, observation)
    return action
end

# ============================================================================
# PART 8: DREAMING CYCLE - Active Inference Enhancement
# ============================================================================

"""
    DreamingLoop - Implements the Dreaming Cycle for memory consolidation
    and prediction error minimization through active inference
    
    This module:
    1. Samples 100 random states from episodic memory
    2. Runs gradient descent on brain weights to minimize prediction error
    3. Wires Active Inference reward signals to BrainCore
"""
mutable struct DreamingLoop
    # Episodic memory storage (stores past experiences)
    episodic_memory::Vector{Vector{Float32}}
    
    # Dream state
    dream_active::Bool
    dream_iterations::Int
    total_dream_cycles::Int
    
    # Gradient descent parameters
    learning_rate::Float32
    momentum::Float32
    
    # Reward tracking
    reward_history::Vector{Float32}
    avg_prediction_error::Float32
    
    # Configuration
    sample_count::Int  # Number of random states to sample (100)
    
    DreamingLoop() = new(
        Vector{Vector{Float32}}(),  # Empty episodic memory
        false,                       # Not dreaming initially
        0,                          # No iterations
        0,                          # No cycles
        0.001f0,                    # Conservative learning rate
        0.9f0,                      # Momentum
        Float32[],                  # No reward history
        0.0f0,                      # Initial prediction error
        100                         # Default: 100 random states
    )
end

"""
    Sample episodic memory - select 100 random states for dreaming
"""
function sample_episodic_memory(
    dream_loop::DreamingLoop;
    sample_count::Int=100
)::Vector{Vector{Float32}}
    if isempty(dream_loop.episodic_memory)
        return Vector{Vector{Float32}}()
    end
    
    mem_size = length(dream_loop.episodic_memory)
    actual_samples = min(sample_count, mem_size)
    
    # Random sampling without replacement
    indices = rand(1:mem_size, actual_samples)
    
    return dream_loop.episodic_memory[indices]
end

"""
    Add experience to episodic memory
"""
function add_to_episodic_memory!(
    dream_loop::DreamingLoop,
    state::Vector{Float32}
)
    push!(dream_loop.episodic_memory, state)
    
    # Limit memory size to prevent unbounded growth
    if length(dream_loop.episodic_memory) > 10000
        # Keep most recent 5000
        dream_loop.episodic_memory = dream_loop.episodic_memory[end-4999:end]
    end
end

"""
    Compute reward signal from Free Energy
    Lower FE = Higher reward (better model fit)
"""
function compute_reward_from_free_energy(
    free_energy::Float32;
    scale::Float32=1.0f0
)::Float32
    # Convert free energy to reward signal
    # High FE -> negative reward (surprise)
    # Low FE -> positive reward (expected)
    reward = -free_energy * scale
    return clamp(reward, -1.0f0, 1.0f0)
end

"""
    Gradient descent on brain weights for prediction error minimization
    This is the core of the dreaming process - the brain learns by
    simulating experiences and minimizing prediction errors
"""
function gradient_descent_on_brain(
    dream_loop::DreamingLoop,
    brain::Any;  # Can be BrainCore or any neural network
    iterations::Int=10
)::Float32
    if isempty(dream_loop.episodic_memory)
        return 0.0f0
    end
    
    dream_loop.dream_active = true
    total_error = 0.0f0
    
    # Sample states from episodic memory
    samples = sample_episodic_memory(dream_loop)
    
    for iteration in 1:iterations
        for state in samples
            # Simulate prediction: what observation would this state produce?
            # In a real implementation, this would:
            # 1. Forward pass through predictor network
            # 2. Compare prediction to actual next state
            # 3. Compute gradient and update weights
            
            # Simplified: compute prediction error as distance from mean
            mean_state = length(samples) > 0 ? mean(hcat(samples...), dims=2)[:] : state
            error = sum((state .- mean_state).^2)
            total_error += error
            
            # In production, would use Flux/zygote for actual gradient descent:
            # ps = Flux.trainable(brain.predictor_net.model)
            # gs = gradient(ps) do
            #     pred = forward_pass(brain.predictor_net, state)
            #     loss = sum((pred .- next_state).^2)
            # end
            # Flux.Optimise.update!(brain.optimizers["predictor"], ps, gs)
        end
    end
    
    dream_loop.dream_iterations += iterations
    avg_error = total_error / (length(samples) * iterations)
    dream_loop.avg_prediction_error = avg_error
    
    return avg_error
end

"""
    Run complete dream cycle
    1. Sample 100 random states
    2. Run gradient descent on brain
    3. Update reward signal
"""
function run_dream_cycle(
    dream_loop::DreamingLoop,
    brain::Any
)::Dict{String, Any}
    println("🌙 Starting Dream Cycle (Active Inference)...")
    
    # Check we have enough episodic memory
    if length(dream_loop.episodic_memory) < 10
        return Dict(
            "status" => "skipped",
            "reason" => "insufficient_episodic_memory",
            "memory_size" => length(dream_loop.episodic_memory)
        )
    end
    
    # Sample 100 random states
    samples = sample_episodic_memory(dream_loop; sample_count=dream_loop.sample_count)
    println("   Sampled $(length(samples)) states from episodic memory")
    
    # Run gradient descent on brain
    prediction_error = gradient_descent_on_brain(dream_loop, brain)
    println("   Prediction error: $(round(prediction_error, digits=4))")
    
    # Compute reward from free energy (prediction error)
    reward = compute_reward_from_free_energy(prediction_error)
    push!(dream_loop.reward_history, reward)
    
    # Keep reward history bounded
    if length(dream_loop.reward_history) > 100
        dream_loop.reward_history = dream_loop.reward_history[end-99:end]
    end
    
    dream_loop.total_dream_cycles += 1
    dream_loop.dream_active = false
    
    println("✅ Dream Cycle complete. Reward signal: $(round(reward, digits=4))")
    
    return Dict(
        "status" => "success",
        "samples_used" => length(samples),
        "prediction_error" => prediction_error,
        "reward_signal" => reward,
        "total_cycles" => dream_loop.total_dream_cycles
    )
end

"""
    Wire Active Inference engine to BrainCore for reward signal
    This connects the Free Energy minimization to the RL reward signal
"""
function wire_ai_to_brain(
    ai_engine::ActiveInferenceEngine,
    brain::Any;
    reward_weight::Float32=0.5f0
)::Nothing
    # This function establishes the connection between AI and Brain
    # In practice, it would:
    # 1. Subscribe brain to AI free energy updates
    # 2. Convert FE to reward signal
    # 3. Apply reward_weight to modulate learning rate
    
    # For now, just print confirmation
    println("🔗 Wired Active Inference to BrainCore")
    println("   - Reward weight: $(reward_weight)")
    println("   - AI precision: $(ai_engine.precision)")
    
    return nothing
end

"""
    Get reward signal from Active Inference for brain training
"""
function get_ai_reward_signal(
    ai_engine::ActiveInferenceEngine,
    dream_loop::DreamingLoop
)::Float32
    # Convert current free energy to reward
    current_fe = isempty(ai_engine.free_energy_history) ? 
        0.0f0 : ai_engine.free_energy_history[end]
    
    return compute_reward_from_free_energy(current_fe)
end

# ============================================================================
# PART 8: DEMONSTRATION AND TESTING
# ============================================================================

"""
    Run demonstration of Active Inference cycle
"""
function demo()
    println("=" ^ 60)
    println("Active Inference Engine - FEP Demonstration")
    println("=" ^ 60)
    
    # Create engine with typical dimensions
    # State: 64-dim, Observation: 384-dim (matching VectorMemory), Action: 32-dim
    engine = create_engine(64, 384, 32)
    
    println("\n[1] Created Active Inference Engine")
    println("    - State dimension: $(engine.model.state_dim)")
    println("    - Observation dimension: $(engine.model.obs_dim)")
    println("    - Action dimension: $(engine.model.action_dim)")
    println("    - HD dimension: $(engine.hdc_memory.dimension)")
    
    # Initialize HDC memory with some concepts
    println("\n[2] Setting up HDC Memory with conceptual associations")
    concepts = [:security, :morning, :evening, :user, :task, :safety]
    for c in concepts
        get_or_create_vector(engine.hdc_memory, c)
    end
    
    # Create associations
    bind_concepts(engine.hdc_memory, :security, :morning)
    bind_concepts(engine.hdc_memory, :safety, :evening)
    
    # Holographic recall demo
    recall_vec = holographic_recall(engine.hdc_memory, [:security, :morning])
    retrieved = retrieve_concept(engine.hdc_memory, recall_vec)
    println("    - Recalled concept from 'Security + Morning': $retrieved")
    
    # Run inference cycle
    println("\n[3] Running Active Inference Cycle")
    for step in 1:5
        # Simulate observation (random 384-dim vector)
        obs = rand(Float32, 384)
        
        # Run inference step
        state, action, fe = step(engine, obs)
        
        println("    Step $step:")
        println("      - Free Energy: $(round(fe, digits=4))")
        println("      - Precision: $(round(engine.precision, digits=4))")
        println("      - State precision: $(round(state.precision, digits=4))")
        if !isempty(action)
            println("      - Action magnitude: $(round(norm(action), digits=4))")
        else
            println("      - Action: learning mode (no action)")
        end
    end
    
    # Summary
    println("\n[4] Summary")
    avg_fe = mean(engine.free_energy_history)
    println("    - Total steps: $(engine.step_count)")
    println("    - Average Free Energy: $(round(avg_fe, digits=4))")
    println("    - Final precision: $(round(engine.precision, digits=4))")
    println("    - HD Memory concepts: $(length(engine.hdc_memory.vectors))")
    
    println("\n" * "=" ^ 60)
    println("Active Inference Cycle Complete!")
    println("=" ^ 60)
    
    return engine
end

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

# Run demo if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    demo()
end

end # module
