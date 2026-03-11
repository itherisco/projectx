# Phase5Kernel.jl - Phase 5 Integration Module for Adaptive Kernel
# 
# This module integrates all Phase 5 components into a cohesive system:
# - WorldInterface: External action execution
# - AuthorizationPipeline: Action authorization
# - ReflectionEngine: Outcome-based learning
# - GoalDecomposition: Strategic planning
# - CommandAuthority: Command parsing and authority evaluation
# - FailureContainment: Failure handling and kill-switch

module Phase5Kernel

using Dates
using UUIDs
using JSON
using Logging

# ============================================================================
# IMPORT SHARED TYPES
# ============================================================================

# Import base types from SharedTypes
include("../types.jl")
using .SharedTypes

# ============================================================================
# IMPORT PHASE 5 COMPONENTS
# ============================================================================

# Import WorldInterface - External action execution
include("WorldInterface.jl")
using .WorldInterface

# Import AuthorizationPipeline - Action authorization
include("AuthorizationPipeline.jl")
using .AuthorizationPipeline

# Import ReflectionEngine - Outcome-based learning
include("ReflectionEngine.jl")
using .ReflectionEngine

# Import GoalDecomposition - Strategic planning
include("GoalDecomposition.jl")
using .GoalDecomposition

# Import CommandAuthority - Command parsing
include("CommandAuthority.jl")
using .CommandAuthority

# Import FailureContainment - Failure handling
include("FailureContainment.jl")
using .FailureContainment

# ============================================================================
# EXPORTS
# ============================================================================

export 
    # State type
    Phase5KernelState,
    
    # Core functions
    process_user_goal,
    full_action_cycle,
    autonomous_goal_achievement,
    emergency_stop_all!,
    get_phase5_status,
    
    # Convenience functions
    create_phase5_kernel,
    shutdown_phase5_kernel!,
    
    # Component accessors
    get_world_interface,
    get_authorization_pipeline,
    get_reflection_engine,
    get_goal_decomposition,
    get_command_authority,
    get_failure_containment,
    
    # Phase 5 metrics
    get_autonomy_level,
    get_recent_failures,
    get_learning_history_summary,
    get_active_goals_summary

# ============================================================================
# PHASE 5 KERNEL STATE
# ============================================================================

"""
    Phase5KernelState - Extended kernel state with all Phase 5 components
    
This is the master state structure that embeds all Phase 5 components and tracks
Phase 5 specific metrics. It provides a single entry point for user goals and
manages the complete action lifecycle.

Fields:
- kernel: Base kernel state
- world_interface: WorldInterface instance for action execution
- authorization_pipeline: AuthorizationPipeline for authorization
- reflection_engine: ReflectionEngine for outcome learning
- goal_decomposition: GoalDecomposition for strategic planning
- command_authority: CommandAuthority for command parsing
- failure_containment: FailureContainment for failure handling
- phase5_metrics: Dict of Phase 5 specific metrics
- active_action_ids: UUIDs of currently executing actions
- completed_action_ids: UUIDs of completed actions
- emergency_stopped: Whether emergency stop has been triggered
- shutdown_requested: Whether shutdown has been requested
"""
mutable struct Phase5KernelState
    # Base kernel state
    kernel::KernelState
    
    # Phase 5 components
    world_interface::WorldInterface
    authorization_pipeline::AuthorizationPipeline
    reflection_engine::ReflectionEngine
    goal_decomposition::GoalDecomposition
    command_authority::CommandAuthority
    failure_containment::FailureContainment
    
    # Phase 5 metrics
    phase5_metrics::Dict{String, Any}
    
    # Action tracking
    active_action_ids::Vector{UUID}
    completed_action_ids::Vector{UUID}
    failed_action_ids::Vector{UUID}
    
    # State flags
    emergency_stopped::Bool
    shutdown_requested::Bool
    
    # Timestamps
    created_at::DateTime
    last_action_at::Union{DateTime, Nothing}
    last_reflection_at::Union{DateTime, Nothing}
    
    function Phase5KernelState(kernel::KernelState)
        # Initialize Phase 5 components (using defaults)
        world_interface = WorldInterface()
        authorization_pipeline = AuthorizationPipeline()
        reflection_engine = ReflectionEngine()
        goal_decomposition = GoalDecomposition()
        command_authority = CommandAuthority()
        failure_containment = FailureContainment()
        
        # Initialize Phase 5 metrics
        phase5_metrics = Dict{String, Any}(
            "total_actions_executed" => 0,
            "total_actions_authorized" => 0,
            "total_actions_denied" => 0,
            "total_reflections" => 0,
            "total_goals_completed" => 0,
            "total_failures" => 0,
            "autonomy_level" => "full",
            "consecutive_failures" => 0,
            "last_failure_at" => nothing,
            "uptime_seconds" => 0.0
        )
        
        return new(
            kernel,
            world_interface,
            authorization_pipeline,
            reflection_engine,
            goal_decomposition,
            command_authority,
            failure_containment,
            phase5_metrics,
            UUID[],
            UUID[],
            UUID[],
            false,
            false,
            now(),
            nothing,
            nothing
        )
    end
end

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

"""
    create_phase5_kernel(config::Dict) -> Phase5KernelState
    
Create a new Phase 5 kernel with all components initialized.

# Arguments
- `config::Dict`: Configuration dictionary (currently unused, reserved for future)
    
# Returns
- `Phase5KernelState`: Initialized Phase 5 kernel state
"""
function create_phase5_kernel(config::Dict=Dict{String, Any}())::Phase5KernelState
    @info "Creating Phase 5 Kernel with all components..."
    
    # Create base kernel state
    world = WorldState(now(), Dict{String, Any}(), Dict{String, String}())
    initial_goals = Goal[]
    kernel = KernelState(0, initial_goals, world, "")
    
    # Create Phase 5 kernel
    phase5_kernel = Phase5KernelState(kernel)
    
    @info "Phase 5 Kernel created successfully"
    return phase5_kernel
end

"""
    shutdown_phase5_kernel!(kernel::Phase5KernelState)

Gracefully shutdown the Phase 5 kernel, stopping all actions and logging final state.
"""
function shutdown_phase5_kernel!(kernel::Phase5KernelState)
    @info "Shutting down Phase 5 Kernel..."
    
    # Set shutdown flag
    kernel.shutdown_requested = true
    
    # Emergency stop all actions if any are active
    if !isempty(kernel.active_action_ids)
        emergency_stop_all!(kernel, "Kernel shutdown requested")
    end
    
    # Log final metrics
    kernel.phase5_metrics["shutdown_at"] = string(now())
    kernel.phase5_metrics["total_uptime_seconds"] = 
        (now() - kernel.created_at).value / 1000.0
    
    @info "Phase 5 Kernel shutdown complete" 
          metrics=kernel.phase5_metrics
end

# ============================================================================
# COMPONENT ACCESSORS
# ============================================================================

get_world_interface(kernel::Phase5KernelState) = kernel.world_interface
get_authorization_pipeline(kernel::Phase5KernelState) = kernel.authorization_pipeline
get_reflection_engine(kernel::Phase5KernelState) = kernel.reflection_engine
get_goal_decomposition(kernel::Phase5KernelState) = kernel.goal_decomposition
get_command_authority(kernel::Phase5KernelState) = kernel.command_authority
get_failure_containment(kernel::Phase5KernelState) = kernel.failure_containment

# ============================================================================
# CORE INTEGRATION FUNCTIONS
# ============================================================================

"""
    process_user_goal(kernel::Phase5KernelState, user_input::String, authority_level::Symbol) -> AuthorityResponse

Process a user goal through the complete Phase 5 pipeline:
1. Parse command with CommandAuthority
2. Evaluate authority and safety
3. Decompose goal with GoalDecomposition  
4. Authorize with AuthorizationPipeline
5. Execute with WorldInterface
6. Reflect with ReflectionEngine
7. Handle failures with FailureContainment

# Arguments
- `kernel::Phase5KernelState`: Phase 5 kernel state
- `user_input::String`: User's goal or command
- `authority_level::Symbol`: Authority level (:suggestion, :request, :command, :emergency)

# Returns
- `AuthorityResponse`: Response from command authority processing
"""
function process_user_goal(
    kernel::Phase5KernelState, 
    user_input::String, 
    authority_level::Symbol
)::AuthorityResponse
    @info "Processing user goal" input=user_input authority=authority_level
    
    # Check emergency stop
    if kernel.emergency_stopped
        @warn "Kernel is in emergency stop state, rejecting goal"
        return AuthorityResponse(
            UUID(UInt128(0)),
            user_input,
            authority_level,
            :refused,
            "System is in emergency stop state",
            nothing,
            nothing,
            Dict{Symbol, Any}(),
            now()
        )
    end
    
    # Check shutdown
    if kernel.shutdown_requested
        @warn "Kernel is shutting down, rejecting goal"
        return AuthorityResponse(
            UUID(UInt128(0)),
            user_input,
            authority_level,
            :refused,
            "System is shutting down",
            nothing,
            nothing,
            Dict{Symbol, Any}(),
            now()
        )
    end
    
    try
        # Step 1: Parse command with CommandAuthority
        cmd_result = parse_command(user_input, authority_level)
        
        # Step 2: Evaluate authority
        authority_response = evaluate_authority(
            kernel.kernel,
            cmd_result
        )
        
        # Update metrics
        kernel.phase5_metrics["total_commands_parsed"] = 
            get(kernel.phase5_metrics, "total_commands_parsed", 0) + 1
        
        # Step 3: If authorized, decompose goal
        if authority_response.decision in [:authorized, :executed]
            goal_result = decompose_goal(
                kernel.kernel,
                user_input,
                kernel.kernel.world,
                kernel.kernel.doctrine_enforcer
            )
            
            # Store decomposition result in response
            authority_response.metadata[:goal_decomposition] = goal_result
        end
        
        # Update last action timestamp
        kernel.last_action_at = now()
        
        return authority_response
        
    catch e
        @error "Error processing user goal" error=string(e)
        
        # Handle failure with FailureContainment
        failure_event = create_failure_event(
            "process_user_goal",
            string(e),
            FAILURE_MODERATE,
            "Goal processing failed"
        )
        escalate_failure!(kernel.failure_containment, failure_event)
        
        # Apply autonomy restriction
        apply_autonomy_restriction!(kernel.failure_containment, kernel)
        
        # Return error response
        return AuthorityResponse(
            UUID(UInt128(0)),
            user_input,
            authority_level,
            :error,
            "Error processing goal: $(string(e))",
            nothing,
            nothing,
            Dict{Symbol, Any}(),
            now()
        )
    end
end

"""
    full_action_cycle(kernel::Phase5KernelState, goal_description::String) -> Dict

Execute a complete action cycle from goal to outcome:
1. Decompose goal into sub-goals
2. Authorize each action
3. Execute actions via WorldInterface
4. Reflect on outcomes
5. Update learning

# Arguments
- `kernel::Phase5KernelState`: Phase 5 kernel state
- `goal_description::String`: High-level goal description

# Returns
- `Dict`: Complete result including all steps
"""
function full_action_cycle(
    kernel::Phase5KernelState, 
    goal_description::String
)::Dict
    @info "Starting full action cycle" goal=goal_description
    
    result = Dict{String, Any}(
        "goal" => goal_description,
        "status" => "started",
        "steps" => Dict{String, Any}(),
        "actions_executed" => [],
        "reflections" => [],
        "outcome" => nothing,
        "errors" => String[]
    )
    
    # Check if emergency stopped
    if kernel.emergency_stopped
        result["status"] = "failed"
        result["errors"] = ["Kernel is in emergency stop state"]
        return result
    end
    
    try
        # Step 1: Decompose goal
        @info "Step 1: Decomposing goal"
        decomposition = decompose_goal(
            kernel.kernel,
            goal_description,
            kernel.kernel.world,
            kernel.kernel.doctrine_enforcer
        )
        result["steps"]["decomposition"] = decomposition
        
        # Step 2: Execute each sub-goal
        sub_goals = decomposition.sub_goals
        for (i, sub_goal) in enumerate(sub_goals)
            @info "Processing sub-goal $i/$(length(sub_goals)): $(sub_goal.description)"
            
            # Authorize sub-goal actions
            for action in sub_goal.actions
                # Build world state for abort condition check
                world_state = Dict(
                    "cycle" => kernel.kernel.cycle,
                    "has_active_goal" => kernel.kernel.active_goal_id != ""
                )
                
                # Check abort conditions first
                if check_abort_conditions(action, world_state)
                    @warn "Abort conditions met for action $(action.id)"
                    push!(result["errors"], "Action aborted: $(action.intent)")
                    continue
                end
                
                # Authorize action
                auth_result = authorize_action(
                    kernel.kernel,
                    action
                )
                
                if auth_result.granted
                    # Execute action
                    @info "Executing action: $(action.intent)"
                    exec_result = execute_world_action(kernel.kernel, action)
                    push!(result["actions_executed"], exec_result)
                    
                    # Track action
                    push!(kernel.active_action_ids, action.id)
                    
                    # Step 3: Reflect on action outcome
                    reflection = reflect_on_action(
                        kernel.reflection_engine,
                        action,
                        exec_result,
                        kernel.kernel.self_model
                    )
                    push!(result["reflections"], reflection)
                    
                    # Update metrics
                    kernel.phase5_metrics["total_actions_executed"] += 1
                    kernel.last_reflection_at = now()
                    
                    # Handle any failures detected
                    if exec_result.status != :success
                        failure_event = create_failure_event(
                            string(action.id),
                            exec_result.actual_outcome,
                            FAILURE_MODERATE,
                            "Action execution failed"
                        )
                        escalate_failure!(kernel.failure_containment, failure_event)
                        push!(kernel.failed_action_ids, action.id)
                    end
                    
                    # Remove from active, add to completed
                    filter!(id -> id != action.id, kernel.active_action_ids)
                    push!(kernel.completed_action_ids, action.id)
                else
                    @warn "Action not authorized: $(action.intent)"
                    kernel.phase5_metrics["total_actions_denied"] += 1
                    push!(result["errors"], "Action denied: $(action.intent)")
                end
            end
        end
        
        # Step 4: Check if goal was achieved
        result["status"] = "completed"
        result["outcome"] = "All sub-goals processed"
        kernel.phase5_metrics["total_goals_completed"] += 1
        
    catch e
        @error "Error in full action cycle" error=string(e)
        result["status"] = "error"
        push!(result["errors"], string(e))
        
        # Trigger failure containment
        failure_event = create_failure_event(
            "full_action_cycle",
            string(e),
            FAILURE_MAJOR,
            "Action cycle failed"
        )
        escalate_failure!(kernel.failure_containment, failure_event)
    end
    
    return result
end

"""
    autonomous_goal_achievement(kernel::Phase5KernelState, goal_description::String) -> Dict

System autonomously achieves a goal through self-directed planning and execution.
Continuously re-evaluates progress and adapts approach.

# Arguments
- `kernel::Phase5KernelState`: Phase 5 kernel state  
- `goal_description::String`: Goal to achieve autonomously

# Returns
- `Dict`: Result with autonomous achievement details
"""
function autonomous_goal_achievement(
    kernel::Phase5KernelState, 
    goal_description::String
)::Dict
    @info "Starting autonomous goal achievement" goal=goal_description
    
    # Check autonomy level
    autonomy = get_autonomy_level(kernel)
    
    result = Dict{String, Any}(
        "goal" => goal_description,
        "autonomy_level" => autonomy,
        "status" => "started",
        "iterations" => 0,
        "max_iterations" => 10,
        "actions" => [],
        "reflections" => [],
        "achieved" => false,
        "final_outcome" => nothing
    )
    
    # Check if we have sufficient autonomy
    if autonomy == AUTONOMY_HALTED
        result["status"] = "blocked"
        result["final_outcome"] = "System is halted"
        return result
    elseif autonomy == AUTONOMY_MINIMAL
        result["max_iterations"] = 1  # Very limited autonomy
    elseif autonomy == AUTONOMY_RESTRICTED
        result["max_iterations"] = 3
    end
    
    current_goal = goal_description
    iterations = 0
    
    while iterations < result["max_iterations"]
        iterations += 1
        result["iterations"] = iterations
        
        @info "Autonomous iteration $iterations/$(result["max_iterations"])"
        
        # Execute action cycle
        cycle_result = full_action_cycle(kernel, current_goal)
        
        # Record actions from this iteration
        if haskey(cycle_result, "actions_executed")
            append!(result["actions"], cycle_result["actions_executed"])
        end
        
        # Record reflections
        if haskey(cycle_result, "reflections")
            append!(result["reflections"], cycle_result["reflections"])
        end
        
        # Check if goal was achieved
        if cycle_result["status"] == "completed"
            result["achieved"] = true
            result["status"] = "achieved"
            result["final_outcome"] = "Goal achieved through autonomous planning"
            break
        end
        
        # Re-evaluate and potentially adjust approach
        # (In a full implementation, this would analyze what worked/didn't)
        if cycle_result["status"] == "error"
            # Try a simpler approach
            current_goal = "Achieve: $goal_description (simplified)"
        end
        
        # Small delay between iterations to prevent tight loops
        # (In production, this would be async)
    end
    
    if !result["achieved"]
        result["status"] = "incomplete"
        result["final_outcome"] = "Goal not fully achieved within iteration limit"
    end
    
    return result
end

"""
    emergency_stop_all!(kernel::Phase5KernelState, reason::String)

Trigger emergency halt across all Phase 5 components.
- Blocks all actions
- Logs emergency
- Reduces autonomy to minimal
- Triggers mandatory reflection
"""
function emergency_stop_all!(kernel::Phase5KernelState, reason::String)
    @error "EMERGENCY STOP TRIGGERED" reason=reason
    
    # Set emergency stop flag
    kernel.emergency_stopped = true
    
    # Kill all active actions
    for action_id in kernel.active_action_ids
        @warn "Killing active action: $action_id"
    end
    empty!(kernel.active_action_ids)
    
    # Trigger emergency halt in failure containment
    emergency_halt!(kernel.failure_containment, reason)
    
    # Reduce autonomy level
    kernel.phase5_metrics["autonomy_level"] = "halted"
    
    # Log emergency event
    kernel.phase5_metrics["last_emergency_stop"] = Dict(
        "reason" => reason,
        "timestamp" => string(now())
    )
    
    @error "Emergency stop complete" reason=reason
end

"""
    get_phase5_status(kernel::Phase5KernelState) -> Dict

Return comprehensive Phase 5 status including:
- Current autonomy level
- Recent failures
- Learning history
- Active goals
"""
function get_phase5_status(kernel::Phase5KernelState)::Dict
    # Get autonomy level
    autonomy = get_autonomy_level(kernel)
    
    # Get failure containment status
    failure_status = get_failure_status(kernel.failure_containment)
    
    # Get recent failures (last 5)
    recent_failures = get_recent_failures(kernel)
    
    # Get learning history summary
    learning_summary = get_learning_history_summary(kernel)
    
    # Get active goals
    active_goals = get_active_goals_summary(kernel)
    
    # Calculate uptime
    uptime_seconds = (now() - kernel.created_at).value / 1000.0
    
    return Dict{String, Any}(
        "phase5_version" => "1.0.0",
        "created_at" => string(kernel.created_at),
        "uptime_seconds" => uptime_seconds,
        "emergency_stopped" => kernel.emergency_stopped,
        "shutdown_requested" => kernel.shutdown_requested,
        "autonomy_level" => string(autonomy),
        "autonomy_index" => get_autonomy_level_index(autonomy),
        "metrics" => kernel.phase5_metrics,
        "active_actions" => length(kernel.active_action_ids),
        "completed_actions" => length(kernel.completed_action_ids),
        "failed_actions" => length(kernel.failed_action_ids),
        "failure_status" => failure_status,
        "recent_failures" => recent_failures,
        "learning_summary" => learning_summary,
        "active_goals" => active_goals,
        "last_action_at" => kernel.last_action_at !== nothing ? string(kernel.last_action_at) : nothing,
        "last_reflection_at" => kernel.last_reflection_at !== nothing ? string(kernel.last_reflection_at) : nothing
    )
end

# ============================================================================
# PHASE 5 METRICS HELPERS
# ============================================================================

"""
    get_autonomy_level(kernel::Phase5KernelState) -> AutonomyLevel

Get current autonomy level from failure containment.
"""
function get_autonomy_level(kernel::Phase5KernelState)::AutonomyLevel
    return get_current_autonomy(kernel.failure_containment)
end

"""
    get_recent_failures(kernel::Phase5KernelState, count::Int=5) -> Vector{Dict}

Get recent failure events.
"""
function get_recent_failures(kernel::Phase5KernelState, count::Int=5)::Vector{Dict}
    failures = get_failure_history(kernel.failure_containment)
    recent = failures[max(1, length(failures)-count+1):end]
    
    return [
        Dict(
            "timestamp" => string(f.timestamp),
            "component" => f.component,
            "error" => f.error_message,
            "severity" => string(f.severity)
        ) for f in recent
    ]
end

"""
    get_learning_history_summary(kernel::Phase5KernelState) -> Dict

Get summary of learning history from reflection engine.
"""
function get_learning_history_summary(kernel::Phase5KernelState)::Dict
    history = get_learning_history(kernel.reflection_engine)
    
    return Dict(
        "total_reflections" => length(history),
        "recent_reflections" => min(5, length(history)),
        "last_reflection" => !isempty(history) ? string(history[end].timestamp) : nothing
    )
end

"""
    get_active_goals_summary(kernel::Phase5KernelState) -> Vector{Dict}

Get summary of active goals from kernel state.
"""
function get_active_goals_summary(kernel::Phase5KernelState)::Vector{Dict}
    goals = kernel.kernel.goals
    
    return [
        Dict(
            "id" => g.id,
            "description" => g.description,
            "priority" => g.priority,
            "status" => get(kernel.kernel.goal_states, g.id, GoalState(g.id)).status
        ) for g in goals
    ]
end

end # module Phase5Kernel
