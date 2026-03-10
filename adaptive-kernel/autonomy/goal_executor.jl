"""
# Goal Executor Module

Executes plans with kernel approval and error handling.

Responsibilities:
- Sequential execution of plan steps
- Tool invocation
- Error handling
- Execution logging

Execution results include:
- success: Bool
- duration: Float64
- resource_cost: Float64
- error_messages: Vector{String}
"""

module GoalExecutor

using Dates
using UUIDs

# Import Plan types
include("planner.jl")
using .Planner

# Execution result structure
struct ExecutionResult
    plan_id::UUID
    goal_id::UUID
    success::Bool
    started_at::DateTime
    completed_at::DateTime
    duration::Float64  # seconds
    steps_completed::Int
    total_steps::Int
    resource_cost::Float64
    error_messages::Vector{String}
    step_results::Vector{Dict{String, Any}}
end

# Executor state
mutable struct ExecutorState
    executing::Bool
    current_plan_id::Union{UUID, Nothing}
    max_execution_time::Float64
    total_executed::Int
    total_failed::Int
    
    ExecutorState() = new(false, nothing, 300.0, 0, 0)  # 5 min max
end

const _executor_state = ExecutorState()

"""
Execute a plan with kernel approval for each step.
Returns ExecutionResult.
"""
function execute(plan::Plan, kernel_interface)::ExecutionResult
    _executor_state.executing = true
    _executor_state.current_plan_id = plan.id
    
    start_time = now()
    error_messages = String[]
    step_results = Dict{String, Any}[]
    steps_completed = 0
    
    try
        # Execute each step sequentially
        for (idx, step) in enumerate(plan.steps)
            # Request kernel approval for this step
            action_dict = Dict(
                "name" => step.action,
                "type" => "capability",
                "capability" => step.required_capability,
                "params" => step.params
            )
            
            approved, reason = kernel_interface.approve_action(action_dict)
            
            if !approved
                push!(error_messages, "Kernel rejected step $(idx): $(step.action) - $reason")
                break
            end
            
            # Execute the step (placeholder - would call actual capability)
            step_result = _execute_step(step)
            push!(step_results, step_result)
            
            if step_result["success"]
                steps_completed += 1
            else
                push!(error_messages, "Step $(idx) failed: $(step_result["error"])")
                break
            end
        end
        
    catch e
        push!(error_messages, "Execution error: $(string(e))")
    end
    
    completed_at = now()
    duration = (completed_at - start_time).value / 1000.0
    
    _executor_state.executing = false
    _executor_state.current_plan_id = nothing
    
    success = steps_completed == length(plan.steps)
    
    if success
        _executor_state.total_executed += 1
    else
        _executor_state.total_failed += 1
    end
    
    return ExecutionResult(
        plan.id,
        plan.goal_id,
        success,
        start_time,
        completed_at,
        duration,
        steps_completed,
        length(plan.steps),
        duration * 0.1,  # Simplified resource cost
        error_messages,
        step_results
    )
end

"""
Execute a single step (placeholder implementation).
"""
function _execute_step(step::PlanStep)::Dict{String, Any}
    # This would integrate with actual capability execution
    # For now, simulate successful execution
    return Dict(
        "action" => step.action,
        "capability" => step.required_capability,
        "success" => true,
        "result" => "Completed: $(step.expected_result)",
        "error" => nothing
    )
end

"""
Check if executor is currently busy.
"""
function is_busy()::Bool
    return _executor_state.executing
end

"""
Get executor statistics.
"""
function get_stats()::Dict{String, Any}
    return Dict(
        "executing" => _executor_state.executing,
        "current_plan" => _executor_state.current_plan_id,
        "total_executed" => _executor_state.total_executed,
        "total_failed" => _executor_state.total_failed,
        "success_rate" => _executor_state.total_executed > 0 ? 
            _executor_state.total_executed / (_executor_state.total_executed + _executor_state.total_failed) : 0.0
    )
end

"""
Abort current execution (safety feature).
"""
function abort()
    if _executor_state.executing
        println("[GoalExecutor] Aborting current execution")
        _executor_state.executing = false
        _executor_state.current_plan_id = nothing
    end
end

end # module
