"""
# Autonomous Goal Engine

Central runtime loop that integrates all autonomy components.

Loop cycle (5-second interval):
1. Observe state
2. Generate goals
3. Schedule goals
4. Select next goal
5. Create plan
6. Kernel approval
7. Execute plan
8. Evaluate result
9. Update memory
10. Repeat

This transforms ITHERIS from a passive assistant into a true autonomous AI runtime.
"""

module GoalEngine

using Dates
using UUIDs

# Include all submodules
include("state_observer.jl")
include("goal_generator.jl")
include("goal_scheduler.jl")
include("planner.jl")
include("goal_executor.jl")
include("goal_evaluator.jl")
include("goal_memory.jl")

# Import kernel interface from kernel directory
include("../kernel/kernel_interface.jl")

using .StateObserver
using .GoalGenerator
using .GoalScheduler
using .Planner
using .GoalExecutor
using .GoalEvaluator
using .GoalMemory
using .KernelInterface

# Engine configuration
const LOOP_INTERVAL_SECONDS = 5
const MAX_GOALS_PER_HOUR = 100
const MAX_EXECUTION_TIME = 300  # 5 minutes

# Engine state
mutable struct EngineState
    running::Bool
    loop_count::Int
    goals_generated::Int
    goals_completed::Int
    goals_failed::Int
    last_error::Union{String, Nothing}
    paused::Bool
    pause_reason::Union{String, Nothing}
    
    EngineState() = new(false, 0, 0, 0, 0, nothing, false, nothing)
end

const _engine_state = EngineState()

"""
Start the autonomous goal engine.
This runs continuously until stopped.
"""
function start()
    println("=" ^ 60)
    println("🚀 ITHERIS Autonomous Goal Engine: Starting")
    println("=" ^ 60)
    
    # Initialize all components
    _initialize()
    
    _engine_state.running = true
    
    try
        while _engine_state.running
            # Check if paused
            if _engine_state.paused
                sleep(LOOP_INTERVAL_SECONDS)
                continue
            end
            
            # Execute one cycle
            _cycle()
            
            # Sleep for configured interval
            sleep(LOOP_INTERVAL_SECONDS)
            
        end
    catch e
        println("[GoalEngine] Error in main loop: $e")
        _engine_state.last_error = string(e)
        _engine_state.running = false
    end
    
    println("[GoalEngine] Engine stopped")
end

"""
Execute one autonomous cycle.
"""
function _cycle()
    _engine_state.loop_count += 1
    
    try
        # Step 1: Observe system state
        state = StateObserver.observe()
        
        # Step 2: Generate goals from state
        potential_goals = GoalGenerator.generate(state)
        
        if !isempty(potential_goals)
            println("[GoalEngine] Cycle $(_engine_state.loop_count): Generated $(length(potential_goals)) goals")
            
            # Step 3: Schedule goals
            for goal in potential_goals
                GoalScheduler.schedule(goal)
                _engine_state.goals_generated += 1
            end
        end
        
        # Step 4: Get next goal from scheduler
        next = GoalScheduler.next_goal()
        
        if next !== nothing
            println("[GoalEngine] Selected goal: $(next.name)")
            
            # Step 5: Create execution plan
            plan = Planner.create_plan(next)
            
            if Planner.validate(plan)
                println("[GoalEngine] Created plan with $(length(plan.steps)) steps")
                
                # Capture state before execution
                state_before = StateObserver.observe()
                
                # Step 6 & 7: Kernel approval and execution
                approved, reason = KernelInterface.approve_action(Dict(
                    "name" => string(next.name),
                    "type" => "goal_execution",
                    "goal_id" => string(next.id)
                ))
                
                if approved
                    println("[GoalEngine] Kernel approved execution")
                    
                    result = GoalExecutor.execute(plan, KernelInterface)
                    
                    # Capture state after execution
                    state_after = StateObserver.observe()
                    
                    # Step 8: Evaluate result
                    evaluation = GoalEvaluator.evaluate(
                        next, plan, result, state_before, state_after
                    )
                    
                    println("[GoalEngine] Evaluation: $(evaluation.overall_score) - $(evaluation.evaluation)")
                    
                    # Step 9: Update memory
                    GoalMemory.store(next, plan, result, evaluation)
                    
                    # Track success/failure
                    if result.success
                        _engine_state.goals_completed += 1
                    else
                        _engine_state.goals_failed += 1
                    end
                    
                    # Mark goal as complete in scheduler
                    GoalScheduler.complete(next.id)
                    
                else
                    println("[GoalEngine] Kernel rejected: $reason")
                end
            else
                println("[GoalEngine] Invalid plan - skipping goal")
            end
        else
            # No goals ready - log status
            if _engine_state.loop_count % 12 == 0  # Every minute
                println("[GoalEngine] No pending goals, system idle")
            end
        end
        
    catch e
        println("[GoalEngine] Cycle error: $e")
        _engine_state.last_error = string(e)
    end
end

"""
Initialize all engine components.
"""
function _initialize()
    println("[GoalEngine] Initializing components...")
    
    # Initialize kernel interface
    KernelInterface.init()
    
    # Initialize state observer
    StateObserver.init()
    
    println("[GoalEngine] All components initialized")
    println("[GoalEngine] Loop interval: $(LOOP_INTERVAL_SECONDS)s")
    println("[GoalEngine] Max goals/hour: $MAX_GOALS_PER_HOUR")
end

"""
Stop the engine.
"""
function stop()
    println("[GoalEngine] Stopping engine...")
    _engine_state.running = false
end

"""
Pause the engine (safety feature).
"""
function pause(reason::String="Manual pause")
    println("[GoalEngine] Paused: $reason")
    _engine_state.paused = true
    _engine_state.pause_reason = reason
end

"""
Resume the engine.
"""
function resume()
    println("[GoalEngine] Resuming...")
    _engine_state.paused = false
    _engine_state.pause_reason = nothing
end

"""
Get engine status.
"""
function status()::Dict{String, Any}
    return Dict(
        "running" => _engine_state.running,
        "paused" => _engine_state.paused,
        "pause_reason" => _engine_state.pause_reason,
        "loop_count" => _engine_state.loop_count,
        "goals_generated" => _engine_state.goals_generated,
        "goals_completed" => _engine_state.goals_completed,
        "goals_failed" => _engine_state.goals_failed,
        "success_rate" => _engine_state.goals_completed > 0 ? 
            _engine_state.goals_completed / (_engine_state.goals_completed + _engine_state.goals_failed) : 0.0,
        "last_error" => _engine_state.last_error,
        "scheduler_status" => GoalScheduler.get_status(),
        "executor_stats" => GoalExecutor.get_stats(),
        "memory_stats" => GoalMemory.get_stats()
    )
end

"""
Get telemetry data for monitoring.
"""
function telemetry()::Dict{String, Any}
    return Dict(
        "active_goals" => length(GoalScheduler.get_queued_goals()),
        "completed_goals" => _engine_state.goals_completed,
        "goal_success_rate" => _engine_state.goals_completed > 0 ?
            _engine_state.goals_completed / (_engine_state.goals_completed + _engine_state.goals_failed) : 0.0,
        "goal_queue_length" => length(GoalScheduler.get_queued_goals()),
        "recent_goals" => [string(g.name) for g in GoalScheduler.get_queued_goals()],
        "memory_episodes" => length(GoalMemory.get_recent(5)),
        "loop_count" => _engine_state.loop_count
    )
end

end # module
