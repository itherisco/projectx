# integration/Conversions.jl - Type conversion functions for brain-kernel-jarvis communication
# Converts between JarvisTypes, SharedTypes, and Integration types

module Integration

using Dates
using UUIDs
using Logging

# Import SharedTypes (includes Integration types)
include("../types.jl")
using .SharedTypes

# Export conversion functions
#= FALLBACK_CLEANUP: Removed duck-typed conversion fallback (2026-03-04)
   Performance optimization removed - adds unnecessary complexity =#
export 
    # Forward conversions (existing → Integration)
    convert_to_integration,
    convert_jarvis_proposal_to_integration,
    convert_jarvis_worldstate_to_integration,
    convert_shared_proposal_to_integration,
    
    # Reverse conversions (Integration → existing)
    convert_from_integration,
    convert_integration_to_jarvis_proposal,
    convert_integration_to_shared_proposal,
    
    # Safe conversions with error handling
    safe_convert_to_integration,
    safe_convert_from_integration,
    
    # Helper functions
    parse_risk_string,
    float_to_risk_string

# ============================================================================
# FORWARD CONVERSIONS - Existing Types → Integration Types
# ============================================================================

"""
    convert_to_integration(proposal)::IntegrationActionProposal
Convert any ActionProposal format to IntegrationActionProposal.
Dispatches to the appropriate conversion based on input type for optimal performance.
"""
function convert_to_integration(proposal)::IntegrationActionProposal
    # Dispatch based on proposal type - uses multiple dispatch for type stability
    return convert_jarvis_proposal_to_integration(proposal)
end

"""
    convert_jarvis_proposal_to_integration(proposal)::IntegrationActionProposal
Convert JarvisTypes.ActionProposal to IntegrationActionProposal.

Source: jarvis/src/types.jl:165
Fields: id::UUID, capability_id, confidence, predicted_cost, predicted_reward, 
        risk::Float32, reasoning, impact_estimate, timestamp

Note: For maximum performance, pass concrete types. Duck-typed conversions
fall back to runtime field access which may have lower performance.
"""
function convert_jarvis_proposal_to_integration(
    proposal::Any  # Accept any proposal-like object
)::IntegrationActionProposal
    # Check if it's already in integration format
    if hasfield(typeof(proposal), :risk) && proposal.risk isa Float32
        # Already has Float32 risk - might be Integration type
        return IntegrationActionProposal(
            getfield(proposal, :capability_id),
            Float32(proposal.confidence),
            Float32(proposal.predicted_cost),
            Float32(proposal.predicted_reward),
            Float32(proposal.risk);
            reasoning=getfield(proposal, :reasoning),
            impact=hasfield(typeof(proposal), :impact_estimate) ? Float32(proposal.impact_estimate) : 0.5f0
        )
    end
    # Otherwise treat as SharedTypes with String risk
    return convert_shared_proposal_to_integration(proposal)
end

function convert_jarvis_proposal_to_integration(
    proposal::IntegrationActionProposal
)::IntegrationActionProposal
    # Already in integration format - return as-is
    return proposal
end

#= FALLBACK_CLEANUP: Removed duck-typed conversion fallback (2026-03-04)
   Performance optimization removed - adds unnecessary complexity =#

"""
    convert_shared_proposal_to_integration(proposal)::IntegrationActionProposal
Convert SharedTypes.ActionProposal to IntegrationActionProposal.

Source: adaptive-kernel/types.jl:19
Fields: capability_id, confidence, predicted_cost, predicted_reward, 
        risk::String (not Float32!), reasoning
"""
function convert_shared_proposal_to_integration(
    proposal::Any  # Accept any ActionProposal-like object
)::IntegrationActionProposal
    # Parse risk string to Float32 - handle both String and Float32 risk
    risk_float = if proposal.risk isa String
        parse_risk_string(proposal.risk)
    else
        Float32(proposal.risk)
    end
    
    return IntegrationActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        risk_float;
        reasoning=proposal.reasoning
    )
end

"""
    convert_jarvis_worldstate_to_integration(jarvis_world)::IntegrationWorldState
Convert JarvisTypes.WorldState to IntegrationWorldState.

Source: jarvis/src/types.jl:267
Fields: cpu_load, memory_usage, disk_usage, network_latency, overall_severity, 
        threat_count, trust_level, kernel_approvals, kernel_denials, 
        available_capabilities, last_decision, last_action_id, status
"""
function convert_jarvis_worldstate_to_integration(
    jarvis_world::Any  # Using Any to avoid direct dependency
)::IntegrationWorldState
    # Extract system metrics
    system_metrics = Dict{String, Float32}(
        "cpu_load" => Float32(jarvis_world.cpu_load),
        "memory_usage" => Float32(jarvis_world.memory_usage),
        "disk_usage" => Float32(jarvis_world.disk_usage),
        "network_latency" => Float32(jarvis_world.network_latency)
    )
    
    # Extract security state
    severity = hasfield(typeof(jarvis_world), :overall_severity) ? 
        Float32(jarvis_world.overall_severity) : 0.0f0
    threat_count = hasfield(typeof(jarvis_world), :threat_count) ? 
        jarvis_world.threat_count::Int : 0
    
    # Extract trust level (convert enum to int)
    trust_level = 100  # Default
    if hasfield(typeof(jarvis_world), :trust_level)
        trust_level = _trust_level_to_int(jarvis_world.trust_level)
    end
    
    # Extract last action ID
    last_action_id = hasfield(typeof(jarvis_world), :last_action_id) ? 
        jarvis_world.last_action_id : nothing
    
    return IntegrationWorldState(
        system_metrics=system_metrics,
        severity=severity,
        threat_count=threat_count,
        trust_level=trust_level,
        observations=Dict{String, Any}(),  # Kernel observations would come separately
        facts=Dict{String, String}(),     # Kernel facts would come separately
        cycle=0,  # Would need to track this separately
        last_action_id=last_action_id
    )
end

# ============================================================================
# REVERSE CONVERSIONS - Integration Types → Existing Types
# ============================================================================

"""
    convert_from_integration(proposal::IntegrationActionProposal)::SharedTypes.ActionProposal
Convert IntegrationActionProposal to SharedTypes.ActionProposal.
Note: This loses the UUID, timestamp, and impact_estimate fields.
"""
function convert_from_integration(
    proposal::Any  # Accept any IntegrationActionProposal-like object
)::SharedTypes.ActionProposal
    return SharedTypes.ActionProposal(
        proposal.capability_id,
        proposal.confidence,
        proposal.predicted_cost,
        proposal.predicted_reward,
        float_to_risk_string(proposal.risk),  # Convert Float32 to String
        proposal.reasoning
    )
end

"""
    convert_integration_to_jarvis_proposal(proposal::IntegrationActionProposal)::Any
Convert IntegrationActionProposal to a format compatible with Jarvis execution.
Returns a duck-typed dict-like structure that Jarvis can work with.
"""
function convert_integration_to_jarvis_proposal(
    proposal::IntegrationActionProposal
)::Dict{String, Any}
    return Dict{String, Any}(
        "id" => string(proposal.id),
        "capability_id" => proposal.capability_id,
        "confidence" => proposal.confidence,
        "predicted_cost" => proposal.predicted_cost,
        "predicted_reward" => proposal.predicted_reward,
        "risk" => proposal.risk,
        "reasoning" => proposal.reasoning,
        "impact_estimate" => proposal.impact_estimate,
        "timestamp" => string(proposal.timestamp)
    )
end

# ============================================================================
# SAFE CONVERSIONS - With Error Handling
# ============================================================================

"""
    safe_convert_to_integration(proposal)::Union{IntegrationActionProposal, Nothing}
Convert with error handling - returns nothing on failure instead of throwing.
Uses multiple dispatch for known types, falls back to duck-typing for unknown types.
"""
function safe_convert_to_integration(proposal)::Union{IntegrationActionProposal, Nothing}
    try
        if proposal === nothing
            return nothing
        end
        
        # Use duck typing for any proposal-like object
        return convert_shared_proposal_to_integration(proposal)
    catch e
        @error "Failed to convert proposal to integration format" error=e
        return nothing
    end
end

"""
    safe_convert_from_integration(proposal::IntegrationActionProposal)::Union{SharedTypes.ActionProposal, Nothing}
Convert from Integration format with error handling.
"""
function safe_convert_from_integration(
    proposal::Any
)::Union{SharedTypes.ActionProposal, Nothing}
    try
        return convert_from_integration(proposal)
    catch e
        @error "Failed to convert proposal from integration format" error=e
        return nothing
    end
end

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

"""
    parse_risk_string(risk::String)::Float32
Parse risk string to Float32 value.
Returns semantically consistent values:
- "high" or "h": 0.9f0
- "medium" or "m": 0.5f0  
- "low" or "l": 0.1f0
- unknown/empty/invalid: 0.5f0 (default - medium)

These values work symmetrically with float_to_risk_string thresholds:
- < 0.33: low
- >= 0.33 and < 0.66: medium
- >= 0.66: high
"""
function parse_risk_string(risk::String)::Float32
    if isempty(risk)
        return 0.5f0  # Default - empty string treated as unknown
    end
    
    risk_lowercase = lowercase(strip(risk))
    if risk_lowercase == "high" || risk_lowercase == "h"
        return 0.9f0
    elseif risk_lowercase == "medium" || risk_lowercase == "m"
        return 0.5f0
    elseif risk_lowercase == "low" || risk_lowercase == "l"
        return 0.1f0
    else
        # Unknown string - try to parse as number, otherwise use default
        try
            val = Float32(parse(Float64, risk))
            # Clamp to valid range [0.0, 1.0]
            return clamp(val, 0.0f0, 1.0f0)
        catch
            return 0.5f0  # Default - unknown string treated as medium
        end
    end
end

"""
    float_to_risk_string(risk::Float32)::String
Convert Float32 risk value to String representation.
Uses symmetric thresholds matching parse_risk_string:
- < 0.33: "low"
- >= 0.33 and < 0.66: "medium"
- >= 0.66: "high"

This ensures bidirectional consistency with parse_risk_string.
"""
function float_to_risk_string(risk::Float32)::String
    # Use symmetric thresholds matching parse_risk_string:
    # - low: < 0.33 (matches parse_risk_string "low" = 0.1)
    # - medium: >= 0.33 and < 0.66 (matches parse_risk_string "medium" = 0.5)
    # - high: >= 0.66 (matches parse_risk_string "high" = 0.9)
    if risk >= 0.66f0
        return "high"
    elseif risk >= 0.33f0
        return "medium"
    else
        return "low"
    end
end

"""
    _trust_level_to_int(level)::Int
Convert TrustLevel enum to Int (0-100 scale).
"""
function _trust_level_to_int(level)::Int
    try
        # Try to get the value of the enum
        return Int(level)
    catch
        # Default if conversion fails
        return 100
    end
end

end # module Integration
