"""
# Goal Memory Module

Stores goal experiences for learning.

Each record contains:
- goal: Goal struct
- plan: Plan struct  
- execution_result: ExecutionResult
- evaluation: Evaluation
- timestamp: DateTime

Integrates with:
- vector memory
- knowledge graph
- episodic memory

This allows the system to improve goal selection over time.
"""

module GoalMemory

using Dates
using UUIDs

# Import types from other modules
include("goal_generator.jl")
include("planner.jl")
include("goal_executor.jl")
include("goal_evaluator.jl")

using .GoalGenerator
using .Planner
using .GoalExecutor
using .GoalEvaluator

# Memory record structure
struct MemoryRecord
    goal_id::UUID
    goal_name::Symbol
    plan_id::UUID
    execution_result::ExecutionResult
    evaluation::Evaluation
    timestamp::DateTime
    goal_context::Dict{String, Any}
end

# Memory state
mutable struct MemoryState
    episodic_memory::Vector{MemoryRecord}
    max_episodic_size::Int
    goal_success_history::Dict{Symbol, Vector{Bool}}  # Track success by goal type
    average_scores::Dict{Symbol, Float64}  # Average score by goal type
    
    MemoryState() = new(
        MemoryRecord[],
        1000,  # Keep last 1000 episodes
        Dict{Symbol, Vector{Bool}}(),
        Dict{Symbol, Float64}()
    )
end

const _memory_state = MemoryState()

"""
Store a goal execution in memory.
"""
function store(
    goal::Goal,
    plan::Plan,
    result::ExecutionResult,
    evaluation::Evaluation
)::MemoryRecord
    record = MemoryRecord(
        goal.id,
        goal.name,
        plan.id,
        result,
        evaluation,
        now(),
        goal.context
    )
    
    # Add to episodic memory
    push!(_memory_state.episodic_memory, record)
    
    # Trim if needed
    if length(_memory_state.episodic_memory) > _memory_state.max_episodic_size
        popfirst!(_memory_state.episodic_memory)
    end
    
    # Update success history
    _update_success_history(goal.name, result.success)
    
    # Update average scores
    _update_average_score(goal.name, evaluation.overall_score)
    
    return record
end

"""
Get recent memory records.
"""
function get_recent(limit::Int=10)::Vector{MemoryRecord}
    return _memory_state.episodic_memory[max(1, end-limit+1):end]
end

"""
Get memory records for a specific goal type.
"""
function get_by_goal_type(goal_name::Symbol, limit::Int=10)::Vector{MemoryRecord}
    filtered = filter(r -> r.goal_name == goal_name, _memory_state.episodic_memory)
    return filtered[max(1, end-limit+1):end]
end

"""
Get success rate for a specific goal type.
"""
function get_success_rate(goal_name::Symbol)::Float64
    history = get(_memory_state.goal_success_history, goal_name, Bool[])
    if isempty(history)
        return 0.5  # Unknown = neutral
    end
    return sum(history) / length(history)
end

"""
Get average score for a specific goal type.
"""
function get_average_score(goal_name::Symbol)::Float64
    return get(_memory_state.average_scores, goal_name, 0.5)
end

"""
Learn from past experiences to inform future goal selection.
This is the core learning function.
"""
function learn()::Dict{Symbol, Any}
    learnings = Dict{Symbol, Any}()
    
    for (goal_name, history) in _memory_state.goal_success_history
        success_rate = get_success_rate(goal_name)
        avg_score = get_average_score(goal_name)
        
        # Determine if goal is worth pursuing
        if success_rate > 0.7 && avg_score > 0.6
            learnings[goal_name] = Dict(
                "recommend" => true,
                "reason" => "High success rate and good scores",
                "success_rate" => success_rate,
                "avg_score" => avg_score
            )
        elseif success_rate < 0.3 || avg_score < 0.3
            learnings[goal_name] = Dict(
                "recommend" => false,
                "reason" => "Low success rate or poor scores",
                "success_rate" => success_rate,
                "avg_score" => avg_score
            )
        else
            learnings[goal_name] = Dict(
                "recommend" => true,
                "reason" => "Neutral performance - continue monitoring",
                "success_rate" => success_rate,
                "avg_score" => avg_score
            )
        end
    end
    
    return learnings
end

"""
Get memory statistics.
"""
function get_stats()::Dict{String, Any}
    total = length(_memory_state.episodic_memory)
    
    # Calculate overall success rate
    all_success = vcat(values(_memory_state.goal_success_history)...)
    overall_success_rate = isempty(all_success) ? 0.5 : sum(all_success) / length(all_success)
    
    return Dict(
        "total_episodes" => total,
        "unique_goal_types" => length(_memory_state.goal_success_history),
        "overall_success_rate" => overall_success_rate,
        "history_sizes" => Dict(string(k) => length(v) for (k, v) in _memory_state.goal_success_history)
    )
end

"""
Clear old memories (maintenance).
"""
function cleanup(older_than_days::Int=7)
    cutoff = now() - Hour(older_than_days * 24)
    filter!(r -> r.timestamp > cutoff, _memory_state.episodic_memory)
end

# Internal helpers
function _update_success_history(goal_name::Symbol, success::Bool)
    if !haskey(_memory_state.goal_success_history, goal_name)
        _memory_state.goal_success_history[goal_name] = Bool[]
    end
    push!(_memory_state.goal_success_history[goal_name], success)
    
    # Keep only last 100 entries per goal type
    if length(_memory_state.goal_success_history[goal_name]) > 100
        popfirst!(_memory_state.goal_success_history[goal_name])
    end
end

function _update_average_score(goal_name::Symbol, score::Float64)
    if !haskey(_memory_state.average_scores, goal_name)
        _memory_state.average_scores[goal_name] = 0.0
    end
    
    # Running average
    current_avg = _memory_state.average_scores[goal_name]
    history_len = length(get(_memory_state.goal_success_history, goal_name, [true]))
    _memory_state.average_scores[goal_name] = (current_avg * (history_len - 1) + score) / history_len
end

# Forward exports for external use
export MemoryRecord, MemoryState, store, get_recent, get_by_goal_type
export get_success_rate, get_average_score, learn, get_stats, cleanup

end # module
