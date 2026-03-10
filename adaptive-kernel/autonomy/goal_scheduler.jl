"""
# Goal Scheduler Module

Priority-based queue for goal scheduling.

Priority classes:
- CRITICAL (1): Must execute immediately
- HIGH (2): Execute soon
- NORMAL (3): Standard priority
- BACKGROUND (4): Low priority, execute when idle

Responsibilities:
- Prevent duplicate goals
- Enforce rate limits
- Select the highest-value goal
"""

module GoalScheduler

using Dates
using UUIDs
using DataStructures

# Import Goal types from GoalGenerator
include("goal_generator.jl")
using .GoalGenerator

# Scheduled goal with execution metadata
struct ScheduledGoal
    goal::Goal
    scheduled_at::DateTime
    attempts::Int
    last_error::Union{String, Nothing}
end

# Scheduler state
mutable struct SchedulerState
    queue::PriorityQueue{UUID, ScheduledGoal}
    completed_ids::Set{UUID}
    rate_limits::Dict{Symbol, Int}  # goals per hour
    last_cleanup::DateTime
    
    SchedulerState() = new(
        PriorityQueue{UUID, ScheduledGoal}(Base.Order.Reverse),
        Set{UUID}(),
        Dict(:total => 100, :critical => 20, :high => 30),
        now()
    )
end

const _scheduler_state = SchedulerState()

"""
Add a goal to the scheduling queue.
Returns false if goal is duplicate or rate-limited.
"""
function schedule(goal::Goal)::Bool
    # Check for duplicate
    if goal.id in _scheduler_state.completed_ids
        return false
    end
    
    # Check if already queued
    if haskey(_scheduler_state.queue, goal.id)
        return false
    end
    
    # Rate limiting check
    if !_check_rate_limit(goal)
        return false
    end
    
    # Create scheduled goal
    scheduled = ScheduledGoal(
        goal,
        now(),
        0,
        nothing
    )
    
    # Add to priority queue (lower priority number = higher priority)
    priority_value = _get_priority_value(goal.priority)
    enqueue!(_scheduler_state.queue, goal.id, scheduled, priority_value)
    
    return true
end

"""
Check rate limits for a goal.
"""
function _check_rate_limit(goal::Goal)::Bool
    # Simple implementation - could be enhanced with actual rate tracking
    return length(_scheduler_state.queue) < 50  # Max 50 queued goals
end

"""
Get priority value for queue ordering.
"""
function _get_priority_value(priority::Priority)::Int
    # Lower value = higher priority in PriorityQueue with Reverse order
    return Int(priority)
end

"""
Get the next goal to execute (highest priority).
"""
function next_goal()::Union{Goal, Nothing}
    if isempty(_scheduler_state.queue)
        return nothing
    end
    
    # Get highest priority goal
    _, scheduled = dequeue_pair!(_scheduler_state.queue)
    
    # Increment attempts
    scheduled.attempts += 1
    
    # Re-queue if within retry limit
    if scheduled.attempts < 3
        enqueue!(_scheduler_state.queue, scheduled.goal.id, scheduled, 
                 _get_priority_value(scheduled.goal.priority))
    end
    
    return scheduled.goal
end

"""
Mark a goal as completed.
"""
function complete(goal_id::UUID)
    push!(_scheduler_state.completed_ids, goal_id)
end

"""
Mark a goal as failed with error.
"""
function fail(goal_id::UUID, error::String)
    if haskey(_scheduler_state.queue, goal_id)
        scheduled = _scheduler_state.queue[goal_id]
        scheduled.last_error = error
        scheduled.attempts += 1
        
        # Re-queue with lower priority if attempts remaining
        if scheduled.attempts < 3
            new_priority = Priority(min(Int(scheduled.goal.priority) + 1, 4))
            enqueue!(_scheduler_state.queue, goal_id, scheduled,
                     _get_priority_value(new_priority))
        end
    end
end

"""
Get queue status.
"""
function get_status()::Dict{String, Any}
    return Dict(
        "queued_goals" => length(_scheduler_state.queue),
        "completed_count" => length(_scheduler_state.completed_ids),
        "rate_limits" => _scheduler_state.rate_limits
    )
end

"""
Get all queued goals (for debugging/monitoring).
"""
function get_queued_goals()::Vector{Goal}
    return [scheduled.goal for scheduled in values(_scheduler_state.queue)]
end

"""
Clear old completed goals from memory.
"""
function cleanup()
    # Keep only recent 1000 completed goals
    while length(_scheduler_state.completed_ids) > 1000
        popfirst!(_scheduler_state.completed_ids)
    end
    _scheduler_state.last_cleanup = now()
end

"""
Check if scheduler has pending goals.
"""
function has_pending()::Bool
    return !isempty(_scheduler_state.queue)
end

end # module
