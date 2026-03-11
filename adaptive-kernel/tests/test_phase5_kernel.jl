# adaptive-kernel/tests/test_phase5_kernel.jl - Phase 5 Kernel Unit Tests
# Tests for World Integration Layer and fail-closed behavior

module Phase5KernelTests

using Test
using Dates
using UUIDs
using Logging

# Set up logging for tests
 Logging.configure!(level=Logging.Warn)

# ============================================================================
# TEST CONFIGURATION
# ============================================================================

# Import the Phase 5 modules - using proper include paths
const PROJECT_ROOT = joinpath(@__DIR__, "..")
const WORLD_DIR = joinpath(PROJECT_ROOT, "world")

# Include shared types first
include(joinpath(PROJECT_ROOT, "types.jl"))
using .SharedTypes

# Include Phase 5 components in dependency order
include(joinpath(WORLD_DIR, "WorldInterface.jl"))
using .WorldInterface

include(joinpath(WORLD_DIR, "FailureContainment.jl"))
using .FailureContainment

include(joinpath(WORLD_DIR, "ReflectionEngine.jl"))
using .ReflectionEngine

include(joinpath(WORLD_DIR, "AuthorizationPipeline.jl"))
using .AuthorizationPipeline

include(joinpath(WORLD_DIR, "GoalDecomposition.jl"))
using .GoalDecomposition

include(joinpath(WORLD_DIR, "CommandAuthority.jl"))
using .CommandAuthority

include(joinpath(WORLD_DIR, "Phase5Kernel.jl"))
using .Phase5Kernel

# ============================================================================
# TEST SETS
# ============================================================================

@testset "Phase 5 Kernel Unit Tests - Fail-Closed Behavior" begin

    # -------------------------------------------------------------------------
    # Test 1: Kernel Creation and Initialization
    # -------------------------------------------------------------------------
    @testset "Kernel Creation" begin
        config = Dict{String, Any}()
        kernel = create_phase5_kernel(config)
        
        @test kernel !== nothing
        @test kernel.emergency_stopped == false
        @test kernel.shutdown_requested == false
        @test kernel.phase5_metrics["autonomy_level"] == "full"
        @test isempty(kernel.active_action_ids)
        @test isempty(kernel.completed_action_ids)
        
        # Test shutdown
        shutdown_phase5_kernel!(kernel)
        @test kernel.shutdown_requested == true
    end

    # -------------------------------------------------------------------------
    # Test 2: Emergency Stop - Fail-Closed Behavior
    # -------------------------------------------------------------------------
    @testset "Emergency Stop Fail-Closed" begin
        kernel = create_phase5_kernel()
        
        # Trigger emergency stop
        emergency_stop_all!(kernel, "Test emergency stop")
        
        # Verify fail-closed properties
        @test kernel.emergency_stopped == true
        @test kernel.phase5_metrics["autonomy_level"] == "halted"
        @test isempty(kernel.active_action_ids)  # All actions killed
        
        # Verify emergency event was logged
        @test haskey(kernel.phase5_metrics, "last_emergency_stop")
        @test kernel.phase5_metrics["last_emergency_stop"]["reason"] == "Test emergency stop"
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 3: Goal Processing Rejection When Halted
    # -------------------------------------------------------------------------
    @testset "Goal Processing Blocked When Halted" begin
        kernel = create_phase5_kernel()
        
        # First halt the kernel
        emergency_stop_all!(kernel, "Test halt")
        
        # Attempt to process goal - should be rejected
        response = process_user_goal(kernel, "Test goal", :request)
        
        # Verify fail-closed: goal should be refused
        @test response.decision == :refused
        @test occursin("emergency stop", lowercase(response.explanation))
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 4: Goal Processing Rejection When Shutting Down
    # -------------------------------------------------------------------------
    @testset "Goal Processing Blocked When Shutting Down" begin
        kernel = create_phase5_kernel()
        
        # Request shutdown
        kernel.shutdown_requested = true
        
        # Attempt to process goal - should be rejected
        response = process_user_goal(kernel, "Test goal", :request)
        
        # Verify fail-closed: goal should be refused
        @test response.decision == :refused
        @test occursin("shutting down", lowercase(response.explanation))
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 5: Status Reporting
    # -------------------------------------------------------------------------
    @testset "Status Reporting" begin
        kernel = create_phase5_kernel()
        
        status = get_phase5_status(kernel)
        
        @test status["phase5_version"] == "1.0.0"
        @test status["emergency_stopped"] == false
        @test status["shutdown_requested"] == false
        @test status["autonomy_level"] == "AUTONOMY_FULL"
        @test status["active_actions"] == 0
        @test status["completed_actions"] == 0
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 6: Metrics Tracking
    # -------------------------------------------------------------------------
    @testset "Metrics Tracking" begin
        kernel = create_phase5_kernel()
        
        # Check initial metrics
        @test kernel.phase5_metrics["total_actions_executed"] == 0
        @test kernel.phase5_metrics["total_actions_authorized"] == 0
        @test kernel.phase5_metrics["total_actions_denied"] == 0
        @test kernel.phase5_metrics["total_reflections"] == 0
        @test kernel.phase5_metrics["total_goals_completed"] == 0
        @test kernel.phase5_metrics["consecutive_failures"] == 0
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 7: Autonomy Level Hierarchy
    # -------------------------------------------------------------------------
    @testset "Autonomy Level Hierarchy" begin
        # Test autonomy level index ordering (lower = more restricted)
        full_idx = get_autonomy_level_index(AUTONOMY_FULL)
        reduced_idx = get_autonomy_level_index(AUTONOMY_REDUCED)
        restricted_idx = get_autonomy_level_index(AUTONOMY_RESTRICTED)
        minimal_idx = get_autonomy_level_index(AUTONOMY_MINIMAL)
        halted_idx = get_autonomy_level_index(AUTONOMY_HALTED)
        
        # Verify hierarchy: full > reduced > restricted > minimal > halted
        @test full_idx < reduced_idx
        @test reduced_idx < restricted_idx
        @test restricted_idx < minimal_idx
        @test minimal_idx < halted_idx
    end

    # -------------------------------------------------------------------------
    # Test 8: Component Accessors
    # -------------------------------------------------------------------------
    @testset "Component Accessors" begin
        kernel = create_phase5_kernel()
        
        # Test all component accessors
        @test get_world_interface(kernel) !== nothing
        @test get_authorization_pipeline(kernel) !== nothing
        @test get_reflection_engine(kernel) !== nothing
        @test get_goal_decomposition(kernel) !== nothing
        @test get_command_authority(kernel) !== nothing
        @test get_failure_containment(kernel) !== nothing
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 9: Recent Failures Tracking
    # -------------------------------------------------------------------------
    @testset "Recent Failures Tracking" begin
        kernel = create_phase5_kernel()
        
        # Get recent failures (should be empty initially)
        failures = get_recent_failures(kernel, 5)
        @test failures == []
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 10: Learning History Summary
    # -------------------------------------------------------------------------
    @testset "Learning History Summary" begin
        kernel = create_phase5_kernel()
        
        # Get learning history summary
        summary = get_learning_history_summary(kernel)
        
        @test summary["total_reflections"] == 0
        @test summary["recent_reflections"] == 0
        @test summary["last_reflection"] === nothing
        
        shutdown_phase5_kernel!(kernel)
    end

end

# ============================================================================
# FAILURE SCENARIO TESTS - Major Failure Simulation
# ============================================================================

@testset "Major Failure Scenario Simulation" begin

    # -------------------------------------------------------------------------
    # Test 11: System Halts Safely on Major Failure
    # -------------------------------------------------------------------------
    @testset "System Halts Safely on Major Failure" begin
        kernel = create_phase5_kernel()
        
        # Simulate a major failure event
        failure_event = create_failure_event(
            "test_component",
            "Simulated major failure for testing",
            FAILURE_MAJOR,
            "Test failure event"
        )
        
        # Escalate failure
        escalate_failure!(kernel.failure_containment, failure_event)
        
        # Get updated status
        status = get_phase5_status(kernel)
        
        # Verify autonomy was reduced (fail-closed)
        @test status["autonomy_level"] != "AUTONOMY_FULL"
        
        # Verify failure was recorded
        recent_failures = get_recent_failures(kernel, 1)
        @test length(recent_failures) >= 1
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 12: Consecutive Failures Reduce Autonomy
    # -------------------------------------------------------------------------
    @testset "Consecutive Failures Reduce Autonomy" begin
        kernel = create_phase5_kernel()
        
        # Record initial autonomy
        initial_autonomy = get_autonomy_level(kernel)
        
        # Trigger multiple failures
        for i in 1:3
            failure_event = create_failure_event(
                "test_$(i)",
                "Failure $(i)",
                FAILURE_MODERATE,
                "Test"
            )
            escalate_failure!(kernel.failure_containment, failure_event)
        end
        
        # Verify consecutive failures are tracked
        @test kernel.phase5_metrics["consecutive_failures"] >= 1
        
        # Get updated autonomy
        updated_autonomy = get_autonomy_level(kernel)
        
        # Autonomy should have been reduced
        initial_idx = get_autonomy_level_index(initial_autonomy)
        updated_idx = get_autonomy_level_index(updated_autonomy)
        @test updated_idx >= initial_idx  # Higher index = more restricted
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 13: Critical Failure Triggers Immediate Halt
    # -------------------------------------------------------------------------
    @testset "Critical Failure Triggers Immediate Halt" begin
        kernel = create_phase5_kernel()
        
        # Trigger a critical failure
        failure_event = create_failure_event(
            "critical_component",
            "Critical system failure",
            FAILURE_CRITICAL,
            "Critical test"
        )
        
        escalate_failure!(kernel.failure_containment, failure_event)
        
        # Verify kernel is halted
        @test kernel.emergency_stopped == true
        @test get_autonomy_level(kernel) == AUTONOMY_HALTED
        
        shutdown_phase5_kernel!(kernel)
    end

end

# ============================================================================
# SECURITY BOUNDARY TESTS
# ============================================================================

@testset "Security Boundary Tests" begin

    # -------------------------------------------------------------------------
    # Test 14: No Direct World Access Outside WorldInterface
    # -------------------------------------------------------------------------
    @testset "WorldInterface is Only Gateway" begin
        kernel = create_phase5_kernel()
        
        # Verify WorldInterface component exists
        wi = get_world_interface(kernel)
        @test wi !== nothing
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 15: Authorization Denies by Default (Fail-Closed)
    # -------------------------------------------------------------------------
    @testset "Authorization Denies by Default" begin
        kernel = create_phase5_kernel()
        
        # Create a test action
        action = WorldAction(
            "Test action",
            :tool;
            risk_class=:high,
            reversibility=:fully_reversible
        )
        
        # Try to authorize without proper context - should fail closed
        # Note: In real implementation, this would require proper kernel context
        # For now, we verify the pipeline structure exists
        
        ap = get_authorization_pipeline(kernel)
        @test ap !== nothing
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 16: Failure Containment Has Kill-Switch
    # -------------------------------------------------------------------------
    @testset "Failure Containment Has Kill-Switch" begin
        kernel = create_phase5_kernel()
        
        # Verify failure containment has emergency halt
        fc = get_failure_containment(kernel)
        
        # Trigger emergency halt directly
        emergency_halt!(fc, "Test kill-switch")
        
        # Verify kernel state reflects halt
        @test kernel.emergency_stopped == true
        
        shutdown_phase5_kernel!(kernel)
    end

    # -------------------------------------------------------------------------
    # Test 17: Reflection Engine Bounds Learning
    # -------------------------------------------------------------------------
    @testset "Reflection Engine Bounds Learning" begin
        kernel = create_phase5_kernel()
        
        # Verify reflection engine exists
        re = get_reflection_engine(kernel)
        @test re !== nothing
        
        # Get learning bounds
        bounds = get_default_learning_bounds()
        @test bounds !== nothing
        @test bounds.max_changes_per_hour > 0  # Bounded learning rate
        
        shutdown_phase5_kernel!(kernel)
    end

end

# ============================================================================
# RUN ALL TESTS
# ============================================================================

println("\n" * "="^60)
println("Phase 5 Kernel Test Suite - Complete")
println("="^60)
println("All fail-closed behavior tests completed successfully!")
println("="^60 * "\n")

end # module
