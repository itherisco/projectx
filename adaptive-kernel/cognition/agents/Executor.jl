# cognition/agents/Executor.jl - Executor Agent
# Converts approved decisions into Kernel-compliant actions
# Zero planning, just executes actions from the HierarchicalPlanner

module Executor

using Dates
using UUIDs

# Import types
include("../types.jl")
using ..CognitionTypes

# Import spine
include("../spine/DecisionSpine.jl")
using ..DecisionSpine

# Import Planning for hierarchical execution
include("../../planning/HierarchicalPlanner.jl")
using .HierarchicalPlanner: HierarchicalPlanner, has_active_mission, step_option!, start_mission!, get_option_progress, Mission

export ExecutorAgent, generate_proposal, evaluate_decision, execute_option_step

# ============================================================================
# EXECUTOR AGENT IMPLEMENTATION
# ============================================================================

"""
    create_executor - Create an Executor agent instance
"""
function create_executor(id::String = "executor_001")::ExecutorAgent
    return ExecutorAgent(id)
end

"""
    generate_proposal - Executor generates action proposal
    Zero planning - just converts decision to executable form
"""
function generate_proposal(
    agent::ExecutorAgent,
    perception::Dict{String, Any},
    memory::TacticalMemory
)::AgentProposal
    
    # Get pending decisions from perception
    pending_decision = get(perception, "pending_decision", "")
    
    if isempty(pending_decision)
        # No decision to execute - propose idle
        return AgentProposal(
            agent.id,
            :executor,
            "maintain_state",
            0.9,
            reasoning = "No pending decisions - maintain current state",
            weight = 1.0
        )
    end
    
    # Validate decision is executable
    is_executable, validation_msg = validate_executable(pending_decision, perception)
    
    if !is_executable
        # Return non-executable decision as rejection
        return AgentProposal(
            agent.id,
            :executor,
            "reject: $validation_msg",
            0.95,
            reasoning = "Decision failed validation: $validation_msg",
            weight = 1.0
        )
    end
    
    # Convert to Kernel-compliant action
    executable_action = convert_to_kernel_action(pending_decision, perception)
    
    return AgentProposal(
        agent.id,
        :executor,
        executable_action,
        0.85,
        reasoning = "Converted decision to executable form: $executable_action",
        weight = 1.0,
        evidence = ["validation_passed"]
    )
end

"""
    validate_executable - Check if decision can be executed
"""
function validate_executable(
    decision::String,
    perception::Dict{String, Any}
)::Tuple{Bool, String}
    
    # Check 1: Decision is not empty
    if isempty(strip(decision))
        return false, "empty_decision"
    end
    
    # Check 2: Required resources available
    required_resources = get(perception, "required_resources", Dict{String, Any}())
    available_resources = get(perception, "available_resources", Dict{String, Any}())
    
    for (resource, amount) in required_resources
        available = get(available_resources, resource, 0)
        if available < amount
            return false, "insufficient_$resource"
        end
    end
    
    # Check 3: System not in error state
    system_status = get(perception, "system_status", "nominal")
    if system_status == "error"
        return false, "system_in_error"
    end
    
    return true, "validated"
end

"""
    convert_to_kernel_action - Convert decision to Kernel-compliant action format
"""
function convert_to_kernel_action(
    decision::String,
    perception::Dict{String, Any}
)::String
    # Extract action type from decision
    action_type = lowercase(split(decision, ":")[1])
    
    # Map to capability
    capability_map = Dict(
        "execute" => "safe_execute",
        "write" => "safe_write",
        "read" => "safe_read",
        "http" => "safe_http_request",
        "shell" => "safe_shell"
    )
    
    capability = get(capability_map, action_type, "unknown")
    
    # Build Kernel-compliant action string
    params = get(perception, "action_params", Dict{String, Any}())
    
    return "$capability:$(json(params))"
end

"""
    evaluate_decision - Post-execution evaluation
"""
function evaluate_decision(
    agent::ExecutorAgent,
    decision::String,
    outcome::DecisionOutcome,
    metrics::AgentMetrics
)::Dict{String, Any}
    
    success = outcome.status == OUTCOME_EXECUTED
    
    # Update metrics
    update_accuracy!(metrics, success)
    
    return Dict(
        "agent_id" => agent.id,
        "decision" => decision,
        "success" => success,
        "accuracy" => get_accuracy(metrics)
    )
end

# JSON helper (simplified)
function json(d::Dict)::String
    return string(d)
end

"""
    execute_option_step - Execute one step of an option from the hierarchical planner
    Returns the next primitive action to execute, or nothing if option is complete
"""
function execute_option_step(
    agent::ExecutorAgent,
    planner::HierarchicalPlanner,
    state::Dict{Symbol, Any}
)::Union{String, Nothing}
    
    # Check if there's an active mission
    if !has_active_mission(planner)
        return nothing
    end
    
    # Step through the current option
    action = step_option!(planner, state)
    
    if action !== nothing
        @info "Executor proceeding with action: $action"
    end
    
    return action
end

"""
    start_mission_execution - Start executing a mission
"""
function start_mission_execution(
    agent::ExecutorAgent,
    planner::HierarchicalPlanner,
    mission::Mission
)
    start_mission!(planner, mission)
    @info "Executor starting mission: $(mission.description)"
end

"""
    get_execution_status - Get the current execution status from planner
"""
function get_execution_status(
    planner::HierarchicalPlanner
)::Dict{Symbol, Any}
    
    return get_option_progress(planner)
end

end # module Executor
