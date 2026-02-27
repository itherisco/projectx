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
export 
    # Forward conversions (existing → Integration)
    convert_to_integration,
    convert_jarvis_proposal_to_integration,
    convert_jarvis_proposal_duck,  # Duck-typed fallback
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
    proposal::SharedTypes.ActionProposal
)::IntegrationActionProposal
    # SharedTypes already has typed risk as String - convert
    return convert_shared_proposal_to_integration(proposal)
end

function convert_jarvis_proposal_to_integration(
    proposal::IntegrationActionProposal
)::IntegrationActionProposal
    # Already in integration format - return as-is
    return proposal
end

"""
    convert_jarvis_proposal_duck(proposal)::IntegrationActionProposal
Fallback for duck-typed proposals with runtime field access.
Use only when concrete type is unknown.
"""
function convert_jarvis_proposal_duck(
    proposal::Any
)::IntegrationActionProposal
    # Extract fields - handle both JarvisTypes.ActionProposal and duck-typed proposals
    capability_id = hasfield(typeof(proposal), :capability_id) ?
        proposal.capability_id::String : error("Missing required field: capability_id")
    confidence = hasfield(typeof(proposal), :confidence) ?
        Float32(proposal.confidence) : error("Missing required field: confidence")
    predicted_cost = hasfield(typeof(proposal), :predicted_cost) ?
        Float32(proposal.predicted_cost) : error("Missing required field: predicted_cost")
    predicted_reward = hasfield(typeof(proposal), :predicted_reward) ?
        Float32(proposal.predicted_reward) : error("Missing required field: predicted_reward")
    risk = hasfield(typeof(proposal), :risk) ?
        Float32(proposal.risk) : error("Missing required field: risk")
    reasoning = hasfield(typeof(proposal), :reasoning) ?
        getfield(proposal, :reasoning)::String : ""
    impact_estimate = hasfield(typeof(proposal), :impact_estimate) ? 
        Float32(proposal.impact_estimate) : 0.5f0
    timestamp = hasfield(typeof(proposal), :timestamp) ? 
        proposal.timestamp::DateTime : now()
    
    return IntegrationActionProposal(
        capability_id,
        confidence,
        predicted_cost,
        predicted_reward,
        risk;
        reasoning=reasoning,
        impact=impact_estimate
    )
end

"""
    convert_shared_proposal_to_integration(proposal)::IntegrationActionProposal
Convert SharedTypes.ActionProposal to IntegrationActionProposal.

Source: adaptive-kernel/types.jl:19
Fields: capability_id, confidence, predicted_cost, predicted_reward, 
        risk::String (not Float32!), reasoning
"""
function convert_shared_proposal_to_integration(
    proposal::SharedTypes.ActionProposal
)::IntegrationActionProposal
    # Parse risk string to Float32
    risk_float = parse_risk_string(proposal.risk)
    
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
    proposal::IntegrationActionProposal
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
        
        # Use typed conversion via multiple dispatch (type-stable for known types)
        return convert_jarvis_proposal_to_integration(proposal)
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
    proposal::IntegrationActionProposal
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
Values chosen to be consistent with float_to_risk_string thresholds:
- high: >= 0.5
- medium: >= 0.2 and < 0.5
- low: < 0.2
"""
function parse_risk_string(risk::String)::Float32
    risk_lowercase = lowercase(strip(risk))
    if risk_lowercase == "high" || risk_lowercase == "h"
        return 0.8f0
    elseif risk_lowercase == "medium" || risk_lowercase == "m"
        return 0.35f0  # Just under 0.5 threshold, above 0.2
    elseif risk_lowercase == "low" || risk_lowercase == "l"
        return 0.1f0  # Below 0.2 threshold
    else
        # Try to parse as number
        try
            return Float32(parse(Float64, risk))
        catch
            return 0.3f0  # Default - will be "medium" with current thresholds
        end
    end
end

"""
    float_to_risk_string(risk::Float32)::String
Convert Float32 risk value to String representation.
Uses consistent thresholds: 0.5 for high, 0.2 for medium (matching SystemIntegrator)
"""
function float_to_risk_string(risk::Float32)::String
    if risk >= 0.5f0
        return "high"
    elseif risk >= 0.2f0
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
