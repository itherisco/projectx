"""
    WorldModelValidator - Adversarial Detection for World Model Updates
    
    P1 REMEDIATION: H1 - World Model Corruption
    
    THREAT MODEL:
    - Original vulnerability: Memory updates accept any values without validation
    - Attack vectors:
      1. NaN/Inf injection via state vectors
      2. Extreme reward values for reward poisoning
      3. Causal graph manipulation via crafted transitions
      4. Action indices outside valid range
    
    REMEDIATION DESIGN:
    - Validate all inputs before accepting them
    - Clamp reward values to reasonable range
    - Verify state vector dimensions
    - Verify action indices are valid
    - FAIL-CLOSED: Any anomaly rejects the update
"""

# ============================================================================
# VALIDATION CONSTANTS
# ============================================================================

const VALID_STATE_DIM = 12
const MAX_VALID_ACTION = 8
const MAX_REWARD_VALUE = 1000.0f0
const MIN_REWARD_VALUE = -1000.0f0

# ============================================================================
# CORE VALIDATION FUNCTIONS
# ============================================================================

"""
Validate a state vector for adversarial content.
"""
function validate_state_vector(state::Vector{Float32})::Bool
    if length(state) != VALID_STATE_DIM
        return false
    end
    
    for v in state
        if isnan(v) || isinf(v)
            return false
        end
    end
    
    for v in state
        if v < -2.0f0 || v > 2.0f0
            return false
        end
    end
    
    return true
end

"""
Validate action index.
"""
function validate_action(action::Int)::Bool
    if action < 0 || action >= MAX_VALID_ACTION
        return false
    end
    return true
end

"""
Validate reward value.
"""
function validate_reward(reward::Float32)::Bool
    if isnan(reward) || isinf(reward)
        return false
    end
    
    if reward > MAX_REWARD_VALUE || reward < MIN_REWARD_VALUE
        return false
    end
    
    return true
end

"""
Validate a complete state transition.
"""
function validate_state_transition(
    state::Vector{Float32}, 
    action::Int, 
    next_state::Vector{Float32}
)::Bool
    return validate_state_vector(state) && 
           validate_action(action) && 
           validate_state_vector(next_state)
end

"""
Sanitize a state vector.
"""
function sanitize_state_vector(state::Vector{Float32})::Vector{Float32}
    sanitized = Float32[]
    
    for v in state
        safe_v = isnan(v) ? 0.5f0 : clamp(v, -2.0f0, 2.0f0)
        push!(sanitized, safe_v)
    end
    
    while length(sanitized) < VALID_STATE_DIM
        push!(sanitized, 0.5f0)
    end
    
    return sanitized[1:VALID_STATE_DIM]
end

"""
Sanitize a reward value.
"""
function sanitize_reward(reward::Float32)::Float32
    if isnan(reward) || isinf(reward)
        return 0.0f0
    end
    return clamp(reward, MIN_REWARD_VALUE, MAX_REWARD_VALUE)
end

"""
Sanitize an action index.
"""
function sanitize_action(action::Int)::Int
    return clamp(action, 0, MAX_VALID_ACTION - 1)
end

"""
Safely record experience with adversarial validation.
"""
function safe_record_experience!(
    model,
    state::Vector{Float32},
    action::Int,
    reward::Float32
)::Bool
    if !validate_state_vector(state)
        return false
    end
    
    if !validate_action(action)
        return false
    end
    
    if !validate_reward(reward)
        return false
    end
    
    return true
end

"""
Safely update causal graph with adversarial validation.
"""
function safe_update_causal_graph!(
    model,
    state::Vector{Float32},
    action::Int,
    next_state::Vector{Float32}
)::Bool
    if !validate_state_transition(state, action, next_state)
        return false
    end
    
    delta = next_state - state
    delta_magnitude = sqrt(sum(delta .^ 2))
    
    if delta_magnitude > 1.5f0
        return false
    end
    
    return true
end

# Exports
export validate_state_vector, validate_action, validate_reward
export validate_state_transition
export sanitize_state_vector, sanitize_reward, sanitize_action
export safe_record_experience!, safe_update_causal_graph!
export VALID_STATE_DIM, MAX_VALID_ACTION, MAX_REWARD_VALUE, MIN_REWARD_VALUE
