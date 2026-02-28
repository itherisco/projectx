"""
    RiskClassifier - Dynamic risk classification for actions
"""

# Types are included by Trust.jl before this file
# RiskLevel and TrustLevel are available in scope

mutable struct RiskClassifier
    risk_thresholds::Dict{RiskLevel, TrustLevel}
    history::Vector{Any}  # Circular buffer of TrustEvent
    
    function RiskClassifier()
        new(
            Dict(
                READ_ONLY => TRUST_RESTRICTED,
                LOW => TRUST_LIMITED,
                MEDIUM => TRUST_STANDARD,
                HIGH => TRUST_FULL,
                CRITICAL => TRUST_FULL
            ),
            Vector{Any}()
        )
    end
end

"""
    TrustEvent - Record of trust decision
"""
struct TrustEvent
    timestamp::DateTime
    action_id::String
    risk_level::RiskLevel
    trust_level::TrustLevel
    confirmed::Bool
end

"""
    classify_action_risk(proposal_id::String, capability_id::String, params::Dict)::RiskLevel
Classify the risk level of an action
"""
function classify_action_risk(proposal_id::String, capability_id::String, params::Dict)::RiskLevel
    # Base risk from capability
    base_risk = _get_capability_risk(capability_id)
    
    # Parameter risk modifier
    param_risk = _assess_parameter_risk(params)
    
    # Context risk modifier
    context_risk = _assess_context_risk()
    
    # Calculate final risk (convert enum to int for calculation)
    base_risk_int = Int(base_risk)
    modifier_risk = param_risk + context_risk
    final_risk = max(base_risk_int, modifier_risk)
    
    return RiskLevel(min(final_risk, Int(CRITICAL)))
end

"""
    _get_capability_risk - Get base risk from capability registry
"""
function _get_capability_risk(capability_id::String)::RiskLevel
    # In practice, would query the capability registry
    # For now, use heuristics based on capability name
    if occursin("read", lowercase(capability_id)) || occursin("observe", lowercase(capability_id))
        return READ_ONLY
    elseif occursin("write", lowercase(capability_id)) || occursin("execute", lowercase(capability_id))
        return MEDIUM
    elseif occursin("delete", lowercase(capability_id)) || occursin("destroy", lowercase(capability_id))
        return HIGH
    end
    return LOW
end

"""
    _assess_parameter_risk - Assess risk from parameters
"""
function _assess_parameter_risk(params::Dict)::Int
    risk = 0
    
    # Check for sensitive parameters
    sensitive_keys = ["password", "secret", "key", "token", "credential"]
    for (key, value) in params
        key_lower = lowercase(key)
        for sensitive in sensitive_keys
            if occursin(sensitive, key_lower)
                risk += 2
                break
            end
        end
    end
    
    # Check for dangerous values
    dangerous_paths = ["/etc/", "/root/", "C:\\Windows\\"]
    path_value = get(params, "path", get(params, "file", ""))
    for path in dangerous_paths
        if occursin(path, path_value)
            risk += 3
            break
        end
    end
    
    return risk
end

"""
    _assess_context_risk - Assess risk from current context
"""
function _assess_context_risk()::Int
    # In practice, would check:
    # - Time of day
    # - User trust level
    # - Recent failure history
    # - System load
    
    # For now, return 0 (no context risk)
    return 0
end

"""
    get_required_trust(classifier::RiskClassifier, risk_level::RiskLevel)::TrustLevel
Get the trust level required for a given risk level
"""
function get_required_trust(classifier::RiskClassifier, risk_level::RiskLevel)::TrustLevel
    return get(classifier.risk_thresholds, risk_level, TRUST_FULL)
end

"""
    record_decision!(classifier::RiskClassifier, event::TrustEvent)
Record a trust decision in history
"""
function record_decision!(classifier::RiskClassifier, event::TrustEvent)
    push!(classifier.history, event)
    
    # Keep history bounded
    if length(classifier.history) > 1000
        popfirst!(classifier.history)
    end
end

# ============================================================================
# TRUST VERIFICATION (Finding 8 - HMAC Verification)
# ============================================================================

"""
    verify_and_get_trust(secure_level::SecureTrustLevel, required_trust::TrustLevel)::Tuple{Bool, TrustLevel}
Verify a secure trust level and return if it's sufficient for the required trust.

# Arguments
- `secure_level::SecureTrustLevel`: The HMAC-verified trust level
- `required_trust::TrustLevel`: The minimum trust level required

# Returns
- `Tuple{Bool, TrustLevel}`: (is_valid_and_sufficient, actual_trust_level)
"""
function verify_and_get_trust(secure_level::SecureTrustLevel, required_trust::TrustLevel)::Tuple{Bool, TrustLevel}
    # First verify the HMAC
    if !verify_trust(secure_level)
        @warn "Trust level HMAC verification failed - possible tampering detected"
        return (false, TRUST_NONE)
    end
    
    # Then check if trust level is sufficient
    actual_level = get(secure_level)
    is_sufficient = Int(actual_level) >= Int(required_trust)
    
    return (is_sufficient, actual_level)
end

"""
    require_verified_trust(secure_level::SecureTrustLevel, required_trust::TrustLevel)::Bool
Require verified trust level for an operation. Throws error if verification fails.
"""
function require_verified_trust(secure_level::SecureTrustLevel, required_trust::TrustLevel)::Bool
    is_valid, _ = verify_and_get_trust(secure_level, required_trust)
    if !is_valid
        error("Trust verification failed - operation denied")
    end
    return true
end

"""
    check_trust_transition_valid(current_level::TrustLevel, new_level::TrustLevel)::Bool
Check if a trust level transition is valid (can only increase by one level at a time).
"""
function check_trust_transition_valid(current_level::TrustLevel, new_level::TrustLevel)::Bool
    current_int = Int(current_level)
    new_int = Int(new_level)
    
    # Cannot decrease trust
    if new_int < current_int
        return false
    end
    
    # Can only increase by one level at a time
    if new_int - current_int > 1
        return false
    end
    
    return true
end
