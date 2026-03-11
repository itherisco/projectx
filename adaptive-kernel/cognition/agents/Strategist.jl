# cognition/agents/Strategist.jl - Strategist Agent
# Long-horizon planning, identifies leverage, asymmetries, second-order effects

module Strategist

using Dates
using UUIDs
using Logging

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

# Import Memory for semantic recall
include("../../memory/Memory.jl")
using ..Memory

# Import Planning for hierarchical planning
include("../../planning/HierarchicalPlanner.jl")
using .HierarchicalPlanner: HierarchicalPlanner, Mission, create_mission, add_mission!

export StrategistAgent, generate_proposal, identify_leverage, create_mission_from_strategy

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
    
    # STEP 0: Check for prior experience (Semantic Recall)
    prior_context = nothing
    try
        prior_context = check_prior_experience(situation)
        if prior_context !== nothing
            @info "Found prior experience for situation: $(prior_context["num_experiences"]) similar cases"
        end
    catch e
        @debug "Could not query semantic memory: $e"
    end
    
    # Identify leverage points
    leverage = identify_leverage(perception, doctrine, tactical, adversary)
    
    # Generate long-horizon plan
    plan = generate_long_horizon_plan(leverage, agent.planning_horizon)
    
    # Identify asymmetries
    asymmetries = identify_asymmetries(perception, adversary)
    
    # Calculate second-order effects
    second_order = calculate_second_order_effects(plan, perception)
    
    confidence = calculate_strategist_confidence(leverage, asymmetries, second_order)
    
    # Build reasoning with prior context if available
    reasoning = if prior_context !== nothing
        "Prior: $(round(prior_context["best_match_similarity"], digits=2)) similarity. " *
        "Plan: $(join(leverage, ", ")). Asym: $(join(asymmetries, ", ")). Effects: $(length(second_order))."
    else
        "Long-horizon plan with leverage: $(join(leverage, ", ")). Asymmetries: $(join(asymmetries, ", ")). Second-order effects: $(length(second_order)) identified."
    end
    
    return AgentProposal(
        agent.id,
        :strategist,
        plan,
        confidence,
        reasoning = reasoning,
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

"""
    create_mission_from_strategy - Convert strategic proposal to a mission
    Creates a hierarchical mission from the Strategist's analysis
"""
function create_mission_from_strategy(
    agent::StrategistAgent,
    strategy::String,
    target_state::Dict{Symbol, Any};
    deadline::Union{DateTime, Nothing} = nothing,
    planner::Union{HierarchicalPlanner, Nothing} = nothing
)::Union{Mission, Nothing}
    
    # Extract key information from strategy
    description = "Strategy: $strategy"
    
    # Build target state based on the strategy
    final_target = merge!(Dict{Symbol, Any}(), target_state)
    
    # Add strategic markers
    final_target[:strategy_implemented] = true
    final_target[:leverage_exploited] = join(agent.identified_leverage, ", ")
    
    # Create the mission
    mission = create_mission(description, final_target; deadline = deadline)
    
    # If planner is provided, add mission to planner
    if planner !== nothing
        add_mission!(planner, mission)
        @info "Strategist created mission: $(mission.description)"
    end
    
    return mission
end

"""
    propose_mission_from_analysis - Propose a mission based on strategic analysis
    Analyzes current situation and proposes appropriate missions
"""
function propose_mission_from_analysis(
    agent::StrategistAgent,
    perception::Dict{String, Any};
    planner::Union{HierarchicalPlanner, Nothing} = nothing
)::Union{Mission, Nothing}
    
    # Identify leverage points
    doctrine = get(perception, "doctrine", nothing)
    tactical = get(perception, "tactical", nothing)
    adversary = get(perception, "adversary", AdversaryModels())
    
    leverage = identify_leverage(perception, doctrine, tactical, adversary)
    
    if isempty(leverage)
        return nothing
    end
    
    # Build target state from leverage analysis
    target_state = Dict{Symbol, Any}(
        :leverage_exploited => true,
        :leverage_points => leverage,
        :status => "leverage_implemented"
    )
    
    # Create mission
    mission_description = "Exploit leverage: $(join(leverage, ", "))"
    mission = create_mission(mission_description, target_state)
    
    if planner !== nothing
        add_mission!(planner, mission)
        @info "Strategist proposed mission from analysis: $(mission.description)"
    end
    
    return mission
end

end # module Strategist
