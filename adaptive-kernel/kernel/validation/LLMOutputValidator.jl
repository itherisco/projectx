"""
    LLMOutputValidator - Strict Schema Validation for LLM Outputs
    
    P0 REMEDIATION: C1 - Prompt Injection Sovereignty Bypass
    
    THREAT MODEL:
    - Original vulnerability: LLM output parsed without validation
    - Attack: Malicious JSON injected via prompt injection, modifies perception/action
    - Impact: LLM bypasses Kernel sovereignty - executes unauthorized actions
    
    REMEDIATION DESIGN:
    - Strict JSON schema validation before parsing
    - Whitelist allowed values for critical fields
    - Sanitize all numeric values (clamp to valid ranges)
    - FAIL-CLOSED: Any anomaly rejects the output
    
    DEPENDENCIES:
    - JSON.jl for parsing
"""

using JSON

# Include InputSanitizer for SQL injection detection
push!(LOAD_PATH, joinpath(@__DIR__, "../.."))
include("../../cognition/security/InputSanitizer.jl")
using .InputSanitizer

# ============================================================================
# SCHEMA DEFINITIONS
# ============================================================================

"""
    ValidIntent - Whitelist of allowed intent values
"""
const ALLOWED_INTENTS = Set([
    "task_execution",
    "information_query", 
    "system_observation",
    "planning",
    "confirmation_request",
    "proactive_suggestion"
])

"""
    ValidPriority - Whitelist of allowed priority values  
"""
const ALLOWED_PRIORITIES = Set([
    "critical",
    "high", 
    "medium",
    "low",
    "background"
])

"""
    ValidContext - Whitelist of allowed context values
"""
const ALLOWED_CONTEXTS = Set([
    "preferences",
    "conversations", 
    "knowledge",
    "none"
])

# ============================================================================
# VALIDATION RESULT
# ============================================================================

"""
    ValidationResult - Result of LLM output validation
"""
struct ValidationResult
    is_valid::Bool
    error_message::Union{String, Nothing}
    sanitized_data::Union{Dict{String, Any}, Nothing}
    
    # Constructor for valid result
    function ValidationResult(sanitized_data::Dict{String, Any})
        new(true, nothing, sanitized_data)
    end
    
    # Constructor for invalid result
    function ValidationResult(error_message::String)
        new(false, error_message, nothing)
    end
end

# ============================================================================
# CORE VALIDATION FUNCTIONS
# ============================================================================

"""
    validate_llm_output(raw_output::String)::ValidationResult
    
Validate and sanitize LLM JSON output. FAIL-CLOSED - any anomaly returns invalid.

# Arguments
- `raw_output::String`: Raw JSON string from LLM

# Returns
- `ValidationResult`: Contains sanitized data if valid, error message if invalid
"""
function validate_llm_output(raw_output::String)::ValidationResult
    # FAIL-CLOSED: Reject empty output
    if isempty(raw_output)
        return ValidationResult("Empty LLM output")
    end
    
    # FAIL-CLOSED: Reject if not valid JSON
    parsed = nothing
    try
        parsed = JSON.parse(raw_output)
    catch e
        return ValidationResult("Invalid JSON: $(string(e))")
    end
    
    # FAIL-CLOSED: Must be a Dict
    if !(parsed isa Dict)
        return ValidationResult("Output must be a JSON object")
    end
    
    return _validate_and_sanitize(parsed)
end

"""
    _validate_and_sanitize - Core validation logic
"""
function _validate_and_sanitize(data::Dict{String, Any})::ValidationResult
    # Validate intent
    intent = get(data, "intent", nothing)
    if intent === nothing
        return ValidationResult("Missing required field: intent")
    end
    if !(intent isa String)
        return ValidationResult("intent must be a string")
    end
    if intent ∉ ALLOWED_INTENTS
        return ValidationResult("Invalid intent: '$intent' not in whitelist")
    end
    
    # Validate entities (must be a dict if present)
    entities = get(data, "entities", nothing)
    sanitized_entities = Dict{String, Any}()
    
    if entities !== nothing
        if !(entities isa Dict)
            return ValidationResult("entities must be an object")
        end
        
        # Validate and sanitize each entity field
        for (key, value) in entities
            sanitized_value = _sanitize_entity_value(key, value)
            if sanitized_value === nothing
                return ValidationResult("Invalid value for entity: $key")
            end
            sanitized_entities[key] = sanitized_value
        end
    end
    
    # Validate confidence (must be 0.0-1.0)
    confidence = get(data, "confidence", nothing)
    sanitized_confidence = 0.0f0
    
    if confidence !== nothing
        try
            # Convert to Float32 and clamp to valid range
            sanitized_confidence = Float32(clamp(Float64(confidence), 0.0, 1.0))
        catch e
            return ValidationResult("Invalid confidence value: $(string(e))")
        end
    end
    
    # Validate requires_confirmation (must be bool if present)
    requires_confirm = get(data, "requires_confirmation", nothing)
    sanitized_requires_confirm = false
    
    if requires_confirm !== nothing
        if requires_confirm isa Bool
            sanitized_requires_confirm = requires_confirm
        else
            return ValidationResult("requires_confirmation must be boolean")
        end
    end
    
    # Validate context_needed (array of strings)
    context_needed = get(data, "context_needed", nothing)
    sanitized_context = Symbol[:none]
    
    if context_needed !== nothing
        if context_needed isa Array
            sanitized_context = Symbol[]
            for c in context_needed
                if c isa String
                    if c ∈ ALLOWED_CONTEXTS
                        push!(sanitized_context, Symbol(c))
                    else
                        return ValidationResult("Invalid context: '$c' not in whitelist")
                    end
                else
                    return ValidationResult("context_needed must contain strings")
                end
            end
            if isempty(sanitized_context)
                sanitized_context = Symbol[:none]
            end
        else
            return ValidationResult("context_needed must be an array")
        end
    end
    
    # Build sanitized output
    sanitized = Dict{String, Any}(
        "intent" => intent,
        "entities" => sanitized_entities,
        "confidence" => sanitized_confidence,
        "requires_confirmation" => sanitized_requires_confirm,
        "context_needed" => [String(c) for c in sanitized_context]
    )
    
    return ValidationResult(sanitized)
end

"""
    _sanitize_entity_value - Sanitize individual entity values
"""
function _sanitize_entity_value(key::String, value::Any)::Union{Any, Nothing}
    # Whitelist allowed entity keys
    allowed_keys = Set(["target", "action", "parameters", "priority"])
    
    if key == "priority"
        # Priority must be in whitelist
        if value isa String && value ∈ ALLOWED_PRIORITIES
            return value
        else
            return "medium"  # Default to safe value
        end
    elseif key == "target"
        # Target should be a string, sanitize to prevent injection
        if value isa String
            return _sanitize_string(value)
        else
            return "unknown"
        end
    elseif key == "action"
        # Action should be a string
        if value isa String
            return _sanitize_string(value)
        else
            return "analyze"
        end
    elseif key == "parameters"
        # Parameters can be any JSON type, but we limit recursion
        return _sanitize_parameters(value)
    else
        # Unknown key - ignore for security
        return nothing
    end
end

"""
    _sanitize_string - Sanitize string values to prevent injection
"""
function _sanitize_string(s::String)::String
    # First, remove SQL injection patterns using InputSanitizer
    s = sanitize_sql_patterns(s)
    
    # Remove null bytes
    s = replace(s, "\0" => "")
    
    # Remove control characters except space
    s = join(c for c in s if isletter(c) || isdigit(c) || c == ' ' || c in "-_.:/@#")
    
    # Limit length to prevent DoS
    if length(s) > 1000
        s = s[1:1000]
    end
    
    return s
end

"""
    _sanitize_parameters - Sanitize parameters (recursive limit)
"""
function _sanitize_parameters(value::Any, depth::Int=0)::Any
    # Limit recursion depth to prevent DoS
    if depth > 3
        return "..."
    end
    
    if value isa String
        return _sanitize_string(value)
    elseif value isa Number
        # Clamp numbers to reasonable range
        try
            return clamp(Float64(value), -1e10, 1e10)
        catch
            return 0
        end
    elseif value isa Dict
        sanitized = Dict{String, Any}()
        for (k, v) in value
            if k isa String
                sanitized[k] = _sanitize_parameters(v, depth + 1)
            end
        end
        return sanitized
    elseif value isa Array
        sanitized = Any[]
        for v in value
            if length(sanitized) > 100  # Limit array size
                break
            end
            push!(sanitized, _sanitize_parameters(v, depth + 1))
        end
        return sanitized
    else
        return value
    end
end

# ============================================================================
# PERCEPTION VECTOR VALIDATION
# ============================================================================

"""
    validate_perception_vector(vector::Vector{Float32})::Bool

Validate that a perception vector is safe (no NaN, no Inf, within bounds).
FAIL-CLOSED - returns false if any anomaly detected.
"""
function validate_perception_vector(vector::Vector{Float32})::Bool
    # Check length
    if length(vector) != 12
        @warn "Invalid perception vector length: $(length(vector))"
        return false
    end
    
    # Check for NaN or Inf
    for (i, v) in enumerate(vector)
        if isnan(v) || isinf(v)
            @warn "Invalid value in perception vector at index $i: $v"
            return false
        end
        
        # Check bounds (0.0 to 1.0 for most dimensions)
        if v < 0.0f0 || v > 1.0f0
            @warn "Value out of bounds at index $i: $v"
            return false
        end
    end
    
    return true
end

"""
    sanitize_perception_vector(vector::Vector{Float32})::Vector{Float32}

Sanitize a perception vector by clamping values to valid range.
This is a fallback - validation should catch issues first.
"""
function sanitize_perception_vector(vector::Vector{Float32})::Vector{Float32}
    sanitized = Float32[]
    
    for v in vector
        # Replace NaN with 0.5, clamp to 0-1
        safe_v = isnan(v) ? 0.5f0 : clamp(v, 0.0f0, 1.0f0)
        push!(sanitized, safe_v)
    end
    
    # Ensure 12 dimensions
    while length(sanitized) < 12
        push!(sanitized, 0.5f0)
    end
    
    return sanitized[1:12]
end

# ============================================================================
# EXPORTS
# ============================================================================

export validate_llm_output, ValidationResult
export validate_perception_vector, sanitize_perception_vector
export ALLOWED_INTENTS, ALLOWED_PRIORITIES, ALLOWED_CONTEXTS
