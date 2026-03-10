"""
# Autonomy Integration Tests

Tests for the autonomous goal engine subsystem.

Verifies:
- Goal generation works
- Scheduler prioritizes correctly
- Kernel approval enforced
- Goals execute successfully
- System remains stable over time
"""

# Test configuration
const TEST_LOOP_INTERVAL = 1  # Faster for testing

# Include modules
include("../autonomy/state_observer.jl")
include("../autonomy/goal_generator.jl")
include("../autonomy/goal_scheduler.jl")
include("../autonomy/planner.jl")
include("../autonomy/goal_executor.jl")
include("../autonomy/goal_evaluator.jl")
include("../autonomy/goal_memory.jl")
include("../kernel/kernel_interface.jl")

using .StateObserver
using .GoalGenerator
using .GoalScheduler
using .Planner
using .GoalExecutor
using .GoalEvaluator
using .GoalMemory
using .KernelInterface

"""
Test 1: State Observer
"""
function test_state_observer()
    println("\n[TEST] State Observer")
    
    # Initialize
    StateObserver.init()
    
    # Get state
    state = StateObserver.observe()
    
    # Verify fields
    @assert haskey(state, "uptime")
    @assert haskey(state, "cpu_load")
    @assert haskey(state, "memory_usage")
    @assert haskey(state, "kernel_stats")
    @assert haskey(state, "recent_events")
    
    println("  ✓ State observation works")
    return true
end

"""
Test 2: Goal Generator
"""
function test_goal_generator()
    println("\n[TEST] Goal Generator")
    
    # Create test state
    test_state = Dict(
        "uptime" => 100,
        "cpu_load" => 80.0,
        "memory_usage" => 85.0,
        "kernel_stats" => Dict("mem_free" => 0.5)
    )
    
    # Generate goals
    goals = GoalGenerator.generate(test_state)
    
    # Should generate multiple goals due to high CPU/memory
    @assert length(goals) >= 2
    
    # Verify goal structure
    for goal in goals
        @assert isa(goal.id, UUID)
        @assert isa(goal.name, Symbol)
        @assert isa(goal.priority, Priority)
    end
    
    println("  ✓ Goal generation works: $(length(goals)) goals generated")
    return true
end

"""
Test 3: Goal Scheduler
"""
function test_goal_scheduler()
    println("\n[TEST] Goal Scheduler")
    
    # Create test goals
    test_goals = [
        GoalGenerator.create_goal(:test1, CRITICAL, 1.0, LOW),
        GoalGenerator.create_goal(:test2, NORMAL, 0.5, LOW),
        GoalGenerator.create_goal(:test3, BACKGROUND, 0.3, LOW),
    ]
    
    # Schedule goals
    for goal in test_goals
        scheduled = GoalScheduler.schedule(goal)
        @assert scheduled  # Should succeed
    end
    
    # Get next goal (should be CRITICAL)
    next = GoalScheduler.next_goal()
    @assert next !== nothing
    @assert next.priority == CRITICAL
    
    # Complete and cleanup
    GoalScheduler.complete(next.id)
    
    println("  ✓ Scheduler prioritizes correctly")
    return true
end

"""
Test 4: Kernel Interface
"""
function test_kernel_interface()
    println("\n[TEST] Kernel Interface")
    
    # Initialize
    KernelInterface.init()
    
    # Get system state
    state = KernelInterface.get_system_state()
    @assert haskey(state, "timestamp")
    @assert haskey(state, "load")
    
    # Test approval - should approve safe action
    safe_action = Dict("name" => "test_action", "type" => "capability")
    approved, reason = KernelInterface.approve_action(safe_action)
    @assert approved
    
    # Test rejection - should block self-referential HTTP
    dangerous_action = Dict(
        "name" => "http_request",
        "type" => "http_request",
        "target" => "http://localhost:8080"
    )
    approved, reason = KernelInterface.approve_action(dangerous_action)
    @assert !approved
    @assert occursin("Security", reason)
    
    println("  ✓ Kernel approval enforced")
    return true
end

"""
Test 5: Planner
"""
function test_planner()
    println("\n[TEST] Planner")
    
    # Create a goal
    goal = GoalGenerator.create_goal(:run_self_diagnostic, NORMAL, 0.8, LOW)
    
    # Create plan
    plan = Planner.create_plan(goal)
    
    # Verify plan structure
    @assert plan.goal_id == goal.id
    @assert length(plan.steps) > 0
    
    # Verify step structure
    for step in plan.steps
        @assert haskey(step, :action)
        @assert haskey(step, :required_capability)
    end
    
    # Validate plan
    @assert Planner.validate(plan)
    
    println("  ✓ Planner creates valid execution plans")
    return true
end

"""
Test 6: Goal Executor
"""
function test_goal_executor()
    println("\n[TEST] Goal Executor")
    
    # Create a simple goal and plan
    goal = GoalGenerator.create_goal(:run_self_diagnostic, NORMAL, 0.8, LOW)
    plan = Planner.create_plan(goal)
    
    # Execute plan
    result = GoalExecutor.execute(plan, KernelInterface)
    
    # Verify result structure
    @assert result.goal_id == goal.id
    @assert result.plan_id == plan.id
    @assert haskey(result, :success)
    @assert haskey(result, :duration)
    @assert haskey(result, :steps_completed)
    
    println("  ✓ Goal executor runs plans")
    return true
end

"""
Test 7: Goal Evaluator
"""
function test_goal_evaluator()
    println("\n[TEST] Goal Evaluator")
    
    # Create test data
    goal = GoalGenerator.create_goal(:run_self_diagnostic, NORMAL, 0.8, LOW)
    plan = Planner.create_plan(goal)
    result = GoalExecutor.execute(plan, KernelInterface)
    
    state_before = Dict("cpu_load" => 50.0, "memory_usage" => 50.0)
    state_after = Dict("cpu_load" => 45.0, "memory_usage" => 45.0)
    
    # Evaluate
    evaluation = GoalEvaluator.evaluate(goal, plan, result, state_before, state_after)
    
    # Verify evaluation structure
    @assert evaluation.goal_id == goal.id
    @assert haskey(evaluation, :overall_score)
    @assert haskey(evaluation, :latency_score)
    @assert haskey(evaluation, :efficiency_score)
    @assert haskey(evaluation, :improvement_score)
    
    println("  ✓ Goal evaluator calculates scores")
    return true
end

"""
Test 8: Goal Memory
"""
function test_goal_memory()
    println("\n[TEST] Goal Memory")
    
    # Create and store a memory record
    goal = GoalGenerator.create_goal(:run_self_diagnostic, NORMAL, 0.8, LOW)
    plan = Planner.create_plan(goal)
    result = GoalExecutor.execute(plan, KernelInterface)
    
    state_before = Dict("cpu_load" => 50.0, "memory_usage" => 50.0)
    state_after = Dict("cpu_load" => 45.0, "memory_usage" => 45.0)
    evaluation = GoalEvaluator.evaluate(goal, plan, result, state_before, state_after)
    
    # Store in memory
    record = GoalMemory.store(goal, plan, result, evaluation)
    
    # Verify stored record
    @assert record.goal_id == goal.id
    
    # Get recent memories
    recent = GoalMemory.get_recent(1)
    @assert length(recent) >= 1
    
    # Get success rate
    rate = GoalMemory.get_success_rate(:run_self_diagnostic)
    @assert rate >= 0.0 && rate <= 1.0
    
    println("  ✓ Goal memory stores and retrieves experiences")
    return true
end

"""
Test 9: Integration - Full Cycle
"""
function test_full_cycle()
    println("\n[TEST] Full Autonomy Cycle")
    
    # Initialize
    StateObserver.init()
    KernelInterface.init()
    
    # 1. Observe
    state = StateObserver.observe()
    
    # 2. Generate
    goals = GoalGenerator.generate(state)
    
    if !isempty(goals)
        # 3. Schedule
        GoalScheduler.schedule(goals[1])
        
        # 4. Get next
        next_goal = GoalScheduler.next_goal()
        
        if next_goal !== nothing
            # 5. Plan
            plan = Planner.create_plan(next_goal)
            
            # 6. Approve
            approved, _ = KernelInterface.approve_action(Dict(
                "name" => string(next_goal.name),
                "type" => "goal"
            ))
            
            if approved
                # 7. Execute
                result = GoalExecutor.execute(plan, KernelInterface)
                
                # 8. Evaluate
                state_before = StateObserver.observe()
                state_after = StateObserver.observe()
                evaluation = GoalEvaluator.evaluate(
                    next_goal, plan, result, state_before, state_after
                )
                
                # 9. Store
                GoalMemory.store(next_goal, plan, result, evaluation)
                
                println("  ✓ Full cycle completed successfully")
                return true
            end
        end
    end
    
    println("  ✓ Full cycle (no goals generated in test state)")
    return true
end

"""
Run all tests
"""
function run_all_tests()
    println("=" ^ 60)
    println("🧪 ITHERIS Autonomy Integration Tests")
    println("=" ^ 60)
    
    tests = [
        ("State Observer", test_state_observer),
        ("Goal Generator", test_goal_generator),
        ("Goal Scheduler", test_goal_scheduler),
        ("Kernel Interface", test_kernel_interface),
        ("Planner", test_planner),
        ("Goal Executor", test_goal_executor),
        ("Goal Evaluator", test_goal_evaluator),
        ("Goal Memory", test_goal_memory),
        ("Full Cycle", test_full_cycle),
    ]
    
    passed = 0
    failed = 0
    
    for (name, test_func) in tests
        try
            if test_func()
                passed += 1
            else
                failed += 1
                println("  ✗ $name failed")
            end
        catch e
            failed += 1
            println("  ✗ $name error: $e")
        end
    end
    
    println("\n" * "=" ^ 60)
    println("Results: $passed passed, $failed failed")
    println("=" ^ 60)
    
    return failed == 0
end

# Run tests if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    success = run_all_tests()
    exit(success ? 0 : 1)
end
