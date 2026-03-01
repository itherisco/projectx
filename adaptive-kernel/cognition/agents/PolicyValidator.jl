# cognition/agents/PolicyValidator.jl
# PolicyValidator - Rejects mutations that alter security invariants
# CRITICAL: This prevents the Evolution Engine from weakening security

module PolicyValidator

using UUIDs

export PolicyValidatorResult, validate_mutation, SECURITY_INVARIANTS

# ============================================================================
# SECURITY INVARIANTS - These can NEVER be altered by evolution
# ============================================================================

const SECURITY_INVARIANTS = Dict{String, Any}(
    # Flow integrity - tokens must always be enforced
    "flow_integrity" => [
        "enforce_tokens",
        "token_verification", 
        "hmac_secret",
        "flow_gate"
    ],
    
    # Kernel approval - must always use sovereign kernel
    "kernel_approval" => [
        "kernel_threshold",
        "approval_required",
        "sovereignty_mode",
        "fallback_disabled"
    ],
    
    # Trust system - trust levels are immutable
    "trust_system" => [
        "trust_secret",
        "trust_levels",
        "trust_verification",
        "min_trust_threshold"
    ],
    
    # Input sanitization - cannot be disabled
    "input_sanitization" => [
        "sanitization_enabled",
        "input_validation",
        "escape_html",
        "parameterized_queries"
    ],
    
    # Authentication - always required
    "authentication" => [
        "auth_required",
        "jwt_secret",
        "token_expiry",
        "auth_enabled"
    ],
    
    # Confirmation gates - cannot be bypassed
    "confirmation_gates" => [
        "confirmation_required",
        "approval_threshold",
        "multi_party"
    ]
)

"""
    PolicyValidatorResult - Result of policy validation
"""
struct PolicyValidatorResult
    is_valid::Bool
    reason::String
    blocked_invariants::Vector{String}
    
    function PolicyValidatorResult(is_valid::Bool, reason::String, blocked_invariants::Vector{String}=String[])
        return new(is_valid, reason, blocked_invariants)
    end
end

"""
    _check_security_invariant - Check if mutation targets a security-invariant field
"""
function _check_security_invariant(target::String, invariants::Dict{String, Any})::Vector{String}
    blocked = String[]
    
    for (category, fields) in invariants
        for field in fields
            if occursin(field, lowercase(target)) || occursin(lowercase(target), field)
                push!(blocked, "$category.$field")
            end
        end
    end
    
    return blocked
end

"""
    validate_mutation - Validate that mutation doesn't alter security invariants
    
    Returns PolicyValidatorResult with:
    - is_valid: true if mutation is safe, false if it violates security
    - reason: Human-readable explanation
    - blocked_invariants: List of invariants that would be violated
"""
function validate_mutation(mutation::Dict{String, Any})::PolicyValidatorResult
    mutation_type = get(mutation, "type", "")
    target = get(mutation, "target", "")
    description = get(mutation, "description", "")
    
    blocked_invariants = String[]
    
    # Check 1: Direct security target
    if !isempty(target)
        blocked = _check_security_invariant(target, SECURITY_INVARIANTS)
        if !isempty(blocked)
            append!(blocked_invariants, blocked)
        end
    end
    
    # Check 2: Mutation types that are inherently risky
    risky_types = [
        "disable_security",
        "remove_validation",
        "bypass_approval",
        "disable_auth",
        "weaken_trust",
        "disable_sanitization"
    ]
    
    for risky in risky_types
        if occursin(risky, lowercase(mutation_type)) || occursin(risky, lowercase(description))
            push!(blocked_invariants, "mutation_type.$risky")
        end
    end
    
    # Check 3: Keywords in description that indicate security changes
    security_keywords = [
        "disable", "bypass", "remove", "relax", "weaken",
        "set to false", "set to 0", "disable", "skip",
        "allow all", "no validation", "skip check"
    ]
    
    full_text = lowercase(mutation_type * " " * target * " " * description)
    for keyword in security_keywords
        if occursin(keyword, full_text)
            # Be more strict - any mention of disabling is suspicious
            if keyword in ["disable", "bypass", "remove"]
                push!(blocked_invariants, "keyword.$keyword")
            end
        end
    end
    
    # Check 4: Specific dangerous mutation patterns
    dangerous_patterns = [
        r"enforce.*false",
        r"trust.*threshold.*0",
        r"auth.*disabled",
        r"skip.*verification",
        r"approval.*bypass"
    ]
    
    for pattern in dangerous_patterns
        if occursin(pattern, full_text)
            push!(blocked_invariants, "pattern.match")
        end
    end
    
    # Build result
    if !isempty(blocked_invariants)
        unique!(blocked_invariants)
        return PolicyValidatorResult(
            false,
            "Mutation violates security invariants: $(join(blocked_invariants, ", "))",
            blocked_invariants
        )
    end
    
    return PolicyValidatorResult(
        true,
        "Mutation does not alter security invariants",
        String[]
    )
end

"""
    validate_proposed_changes - Validate multiple mutations
    
    Returns (is_valid, results) where results is a vector of PolicyValidatorResult
"""
function validate_proposed_changes(mutations::Vector{Dict{String, Any}})::Tuple{Bool, Vector{PolicyValidatorResult}}
    results = PolicyValidatorResult[]
    all_valid = true
    
    for mutation in mutations
        result = validate_mutation(mutation)
        push!(results, result)
        if !result.is_valid
            all_valid = false
        end
    end
    
    return (all_valid, results)
end

end # module PolicyValidator
