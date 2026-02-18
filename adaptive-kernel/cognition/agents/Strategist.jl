# cognition/agents/Strategist.jl - Strategist Agent
# Long-horizon planning, identifies leverage, asymmetries, second-order effects

module Strategist

using Dates
using UUIDs

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

export StrategistAgent, generate_proposal, identify_leverage

# ============================================================================
# STRATEGIST AGENT IMPLEMENTATION
# ============================================================================

"""
    create_strategist - Create a Strategist agent instance
"""
function create_strategist(id::String = "strategist_001")::StrategistAgent
    return StrategistAgent(id)
end

"""
    generate_proposal - Strategist generates strategic proposal
    Long-horizon planning with leverage identification
"""
function generate_proposal(
    agent::StrategistAgent,
    perception::Dict{String, Any},
    doctrine::DoctrineMemory,
    tactical::TacticalMemory,
    adversary::AdversaryModels
)::AgentProposal
    
    # Get current situation
    situation = get(perception, "situation", "unknown")
    
    # Identify leverage points
    leverage = identify_leverage(perception, doctrine, tactical, adversary)
    
    # Generate long-horizon plan
    plan = generate_long_horizon_plan(leverage, agent.planning_horizon)
    
    # Identify asymmetries
    asymmetries = identify_asymmetries(perception, adversary)
    
    # Calculate second-order effects
    second_order = calculate_second_order_effects(plan, perception)
    
    confidence = calculate_strategist_confidence(leverage, asymmetries, second_order)
    
    return AgentProposal(
        agent.id,
        :strategist,
        plan,
        confidence,
        reasoning = "Long-horizon plan with leverage: $(join(leverage, ", ")). Asymmetries: $(join(asymmetries, ", ")). Second-order effects: $(length(second_order)) identified.",
        weight = 1.0,
        evidence = ["leverage_analysis", "asymmetry_analysis", "second_order_analysis"]
    )
end

"""
    identify_leverage - Find leverage points in current situation
"""
function identify_leverage(
    perception::Dict{String, Any},
    doctrine::DoctrineMemory,
    tactical::TacticalMemory,
    adversary::AdversaryModels
)::Vector{String}
    
    leverage_points = String[]
    
    # Analyze resource asymmetries
    resources = get(perception, "resources", Dict{String, Any}())
    for (resource, info) in resources
        if get(info, "advantage", false)
            push!(leverage_points, "resource_$resource")
        end
    end
    
    # Analyze capability gaps in adversary models
    for (model_name, model_data) in adversary.models
        gaps = get(model_data, "capability_gaps", String[])
        for gap in gaps
            push!(leverage_points, "gap_$model_name_$gap")
        end
    end
    
    # Analyze timing windows
    timing = get(perception, "timing", Dict{String, Any}())
    if get(timing, "window_open", false)
        push!(leverage_points, "timing_window")
    end
    
    # Analyze information advantages
    info_advantage = get(perception, "information_advantage", false)
    if info_advantage
        push!(leverage_points, "information_advantage")
    end
    
    return leverage_points
end

"""
    generate_long_horizon_plan - Generate plan across multiple steps
"""
function generate_long_horizon_plan(
    leverage::Vector{String},
    horizon::Int
)::String
    
    if isempty(leverage)
        return "expand_capabilities:before_strategic_action"
    end
    
    # Sort leverage by priority
    sorted_leverage = sort(leverage, by = l -> startswith(l, "timing") ? 1 : 
                                             startswith(l, "information") ? 2 : 3)
    
    # Build sequential plan
    steps = String[]
    for (i, point) in enumerate(sorted_leverage[1:min(horizon, length(sorted_leverage))])
        push!(steps, "exploit_$point")
    end
    
    # Add final consolidation step
    push!(steps, "consolidate_position")
    
    return join(steps, " -> ")
end

"""
    identify_asymmetries - Find asymmetric advantages/disadvantages
"""
function identify_asymmetries(
    perception::Dict{String, Any},
    adversary::AdversaryModels
)::Vector{String}
    
    asymmetries = String[]
    
    # Cost asymmetries
    costs = get(perception, "costs", Dict{String, Float64}())
    for (actor, cost) in costs
        if cost < get(costs, "us", Inf)
            push!(asymmetries, "cost_advantage_$actor")
        end
    end
    
    # Speed asymmetries
    speeds = get(perception, "speeds", Dict{String, Float64}())
    our_speed = get(speeds, "us", 0.0)
    for (actor, speed) in speeds
        if actor != "us" && our_speed > speed
            push!(asymmetries, "speed_advantage_$actor")
        end
    end
    
    # Knowledge asymmetries
    knowledge = get(perception, "knowledge", Dict{String, Bool}())
    if get(knowledge, "we_know_they_dont", false)
        push!(asymmetries, "knowledge_advantage")
    end
    
    return asymmetries
end

"""
    calculate_second_order_effects - Predict second and third-order consequences
"""
function calculate_second_order_effects(
    plan::String,
    perception::Dict{String, Any}
)::Vector{String}
    
    effects = String[]
    
    # Parse plan steps
    steps = split(plan, " -> ")
    
    for step in steps
        # Each action has potential second-order effects
        if startswith(step, "exploit_")
            push!(effects, "target_may_adapt")
            push!(effects, "others_may_copy")
        elseif startswith(step, "consolidate")
            push!(effects, "reduces_flexibility")
            push!(effects, "increases_commitment")
        end
    end
    
    return effects
end

"""
    calculate_strategist_confidence - Calculate confidence based on analysis quality
"""
function calculate_strategist_confidence(
    leverage::Vector{String},
    asymmetries::Vector{String},
    second_order::Vector{String}
)::Float64
    
    base_confidence = 0.5
    
    # More leverage = higher confidence
    leverage_bonus = min(0.2, 0.05 * length(leverage))
    
    # More asymmetries = higher confidence  
    asymmetry_bonus = min(0.15, 0.05 * length(asymmetries))
    
    # More second-order effects considered = higher confidence
    second_order_bonus = min(0.15, 0.03 * length(second_order))
    
    return clamp(base_confidence + leverage_bonus + asymmetry_bonus + second_order_bonus, 0.0, 1.0)
end

"""
    update_leverage_discovery - Record newly discovered leverage
"""
function update_leverage_discovery!(
    agent::StrategistAgent,
    new_leverage::Vector{String}
)
    for leverage in new_leverage
        if !(leverage in agent.identified_leverage)
            push!(agent.identified_leverage, leverage)
        end
    end
end

end # module Strategist
