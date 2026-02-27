# cognition/goals/GoalSystem.jl - Autonomous Goal Formation
# Component 3 of JARVIS Neuro-Symbolic Architecture
# Implements curiosity-driven intrinsic reward for autonomous goal hierarchy

module GoalSystem

using UUIDs
using Dates
using Statistics
using LinearAlgebra

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Core types
    GoalStatus,
    Goal,
    GoalGraph,
    
    # Constants
    MIN_ACTIVATION_THRESHOLD,
    MAX_GOALS_ACTIVE,
    
    # Core functions
    generate_goals,
    evaluate_goal,
    should_activate_goal,
    should_abandon_goal,
    abandon_goal!,
    require_kernel_approval,
    compute_intrinsic_reward,
    
    # Goal management
    create_goal!,
    activate_goal!,
    complete_goal!,
    suspend_goal!,
    get_goal_score,
    update_goal_progress!

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    GoalStatus - Enum for goal lifecycle states
"""
@enum GoalStatus begin
    :pending    # Goal created, not yet activated
    :active     # Goal is being pursued
    :completed # Goal successfully achieved
    :abandoned # Goal given up
    :suspended # Goal temporarily paused
end

"""
    Goal - Autonomous goal with curiosity-driven intrinsic reward
"""
mutable struct Goal
    id::UUID
    description::String
    target_state::Vector{Float32}  # Desired end state
    current_state::Vector{Float32}  # Progress tracking
    priority::Float32  # Base priority 0.0-1.0
    intrinsic_reward::Float32  # Curiosity-driven bonus
    status::GoalStatus
    created_at::Float64
    deadline::Union{Float64, Nothing}
    parent_id::Union{UUID, Nothing}  # For hierarchy
    child_ids::Vector{UUID}
    progress::Float32  # 0.0-1.0
    failure_count::Int
    
    function Goal(
        description::String;
        target_state::Vector{Float32}=Float32[],
        current_state::Vector{Float32}=Float32[],
        priority::Float32=0.5f0,
        intrinsic_reward::Float32=0.0f0,
        deadline::Union{Float64, Nothing}=nothing,
        parent_id::Union{UUID, Nothing}=nothing
    )
        new(
            uuid4(),
            description,
            target_state,
            current_state,
            priority,
            intrinsic_reward,
            :pending,
            time(),
            deadline,
            parent_id,
            UUID[],
            0.0f0,
            0
        )
    end
end

"""
    GoalGraph - Manages goal hierarchy and lifecycle
"""
mutable struct GoalGraph
    goals::Dict{UUID, Goal}
    root_goals::Vector{UUID}  # Top-level goals
    active_goals::Vector{UUID}
    completed_goals::Vector{UUID}
    max_active::Int  # Max concurrent goals
    curiosity_weight::Float64  # Intrinsic reward weight
    
    function GoalGraph(; max_active::Int=5, curiosity_weight::Float64=0.3)
        new(
            Dict{UUID, Goal}(),
            UUID[],
            UUID[],
            UUID[],
            max_active,
            curiosity_weight
        )
    end
end

# ============================================================================
# CONSTANTS
# ============================================================================

const MIN_ACTIVATION_THRESHOLD = 0.3
const MAX_GOALS_ACTIVE = 5

# ============================================================================
# GOAL MANAGEMENT FUNCTIONS
# ============================================================================

"""
    create_goal! - Add a new goal to the graph
"""
function create_goal!(
    graph::GoalGraph,
    description::String;
    target_state::Vector{Float32}=Float32[],
    current_state::Vector{Float32}=Float32[],
    priority::Float32=0.5f0,
    deadline::Union{Float64, Nothing}=nothing,
    parent_id::Union{UUID, Nothing}=nothing
)::Goal
    
    goal = Goal(
        description;
        target_state=target_state,
        current_state=current_state,
        priority=priority,
        deadline=deadline,
        parent_id=parent_id
    )
    
    graph.goals[goal.id] = goal
    
    # Handle hierarchy
    if parent_id !== nothing && haskey(graph.goals, parent_id)
        push!(graph.goals[parent_id].child_ids, goal.id)
    else
        push!(graph.root_goals, goal.id)
    end
    
    return goal
end

"""
    activate_goal! - Move goal from pending to active
"""
function activate_goal!(graph::GoalGraph, goal_id::UUID)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    
    if goal.status != :pending
        return false
    end
    
    if length(graph.active_goals) >= graph.max_active
        return false
    end
    
    goal.status = :active
    push!(graph.active_goals, goal_id)
    
    return true
end

"""
    complete_goal! - Mark goal as completed
"""
function complete_goal!(graph::GoalGraph, goal_id::UUID)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    goal.status = :completed
    goal.progress = 1.0f0
    
    # Remove from active
    filter!(id -> id != goal_id, graph.active_goals)
    
    # Add to completed
    push!(graph.completed_goals, goal_id)
    
    return true
end

"""
    suspend_goal! - Temporarily pause an active goal
"""
function suspend_goal!(graph::GoalGraph, goal_id::UUID)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    
    if goal.status != :active
        return false
    end
    
    goal.status = :suspended
    filter!(id -> id != goal_id, graph.active_goals)
    
    return true
end

"""
    update_goal_progress! - Update goal progress
"""
function update_goal_progress!(
    graph::GoalGraph,
    goal_id::UUID,
    new_progress::Float32
)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    goal.progress = clamp(new_progress, 0.0f0, 1.0f0)
    
    # Update current state based on progress
    if !isempty(goal.target_state) && !isempty(goal.current_state)
        goal.current_state = goal.current_state .+ 
            (goal.target_state .- goal.current_state) .* new_progress
    end
    
    return true
end

# ============================================================================
# GOAL EVALUATION
# ============================================================================

"""
    get_goal_score - Calculate goal score for activation decision
"""
function get_goal_score(
    goal::Goal,
    curiosity_weight::Float64
)::Float32
    # Weighted score formula from requirements
    score = goal.progress * 0.3f0 + 
            goal.priority * 0.3f0 + 
            goal.intrinsic_reward * Float32(curiosity_weight)
    
    return clamp(score, 0.0f0, 1.0f0)
end

"""
    evaluate_goal - Compute weighted score for goal with risk and kernel approval
"""
function evaluate_goal(
    goal::Goal,
    world_state::Vector{Float32},
    risk_score::Float64,
    kernel_approval::Bool;
    curiosity_weight::Float64=0.3
)::Float32
    
    # Compute weighted score
    score = get_goal_score(goal, curiosity_weight)
    
    # If risk is too high, reduce score
    if risk_score > 0.7
        score = score - Float32(risk_score * 0.5)
    end
    
    # If kernel didn't approve, zero the score
    if !kernel_approval
        score = 0.0f0
    end
    
    return clamp(score, 0.0f0, 1.0f0)
end

# ============================================================================
# GOAL ACTIVATION
# ============================================================================

"""
    should_activate_goal - Determine if goal should be activated
"""
function should_activate_goal(
    goal::Goal,
    available_slots::Int;
    curiosity_weight::Float64=0.3
)::Bool
    
    # Must be pending status
    if goal.status != :pending
        return false
    end
    
    # Must have score >= threshold
    score = get_goal_score(goal, curiosity_weight)
    if score < MIN_ACTIVATION_THRESHOLD
        return false
    end
    
    # Must have available slots
    if available_slots <= 0
        return false
    end
    
    # Must not exceed max active
    if available_slots > MAX_GOALS_ACTIVE
        return false
    end
    
    return true
end

# ============================================================================
# GOAL ABANDONMENT
# ============================================================================

"""
    should_abandon_goal - Determine if goal should be abandoned
"""
function should_abandon_goal(goal::Goal)::Bool
    
    # Abandon if failure count >= 3
    if goal.failure_count >= 3
        return true
    end
    
    # Abandon if deadline passed and not completed
    if goal.deadline !== nothing && time() > goal.deadline && goal.status != :completed
        return true
    end
    
    # Abandon if progress < 0.1 after significant time (created more than 1 hour ago)
    if time() - goal.created_at > 3600.0 && goal.progress < 0.1f0
        return true
    end
    
    return false
end

"""
    abandon_goal! - Mark goal as abandoned and clean up
"""
function abandon_goal!(graph::GoalGraph, goal_id::UUID)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    
    # Set status to abandoned
    goal.status = :abandoned
    
    # Remove from active goals if present
    filter!(id -> id != goal_id, graph.active_goals)
    
    # Log for audit (in production, this would go to a proper logging system)
    println("[GOAL_AUDIT] Abandoned goal: $(goal.id) - $(goal.description)")
    println("  - Failure count: $(goal.failure_count)")
    println("  - Progress: $(goal.progress)")
    println("  - Time alive: $(time() - goal.created_at)s")
    
    return true
end

"""
    increment_failure! - Increment failure count for a goal
"""
function increment_failure!(graph::GoalGraph, goal_id::UUID)::Bool
    if !haskey(graph.goals, goal_id)
        return false
    end
    
    goal = graph.goals[goal_id]
    goal.failure_count += 1
    
    # Check if should abandon
    if should_abandon_goal(goal)
        abandon_goal!(graph, goal_id)
    end
    
    return true
end

# ============================================================================
# KERNEL APPROVAL INTEGRATION
# ============================================================================

"""
    require_kernel_approval - Get kernel approval for goal activation
"""
function require_kernel_approval(
    goal::Goal,
    kernel_approve_func::Function
)::Bool
    
    # Prepare goal summary for kernel
    goal_summary = Dict(
        "goal_id" => string(goal.id),
        "description" => goal.description,
        "priority" => goal.priority,
        "intrinsic_reward" => goal.intrinsic_reward,
        "target_state_dim" => length(goal.target_state),
        "has_deadline" => goal.deadline !== nothing,
        "parent_id" => goal.parent_id !== nothing ? string(goal.parent_id) : nothing
    )
    
    # Call kernel approval function
    approved = try
        kernel_approve_func(goal_summary)
    catch e
        println("[GOAL_KERNEL] Error calling kernel approval: $e")
        false
    end
    
    # Log approval/denial
    if approved
        println("[GOAL_KERNEL] Approved goal: $(goal.id) - $(goal.description)")
    else
        println("[GOAL_KERNEL] Denied goal: $(goal.id) - $(goal.description)")
    end
    
    return approved
end

# ============================================================================
# INTRINSIC REWARD (CURIOSITY) CALCULATION
# ============================================================================

"""
    compute_intrinsic_reward - Calculate curiosity-driven intrinsic reward
"""
function compute_intrinsic_reward(
    goal::Goal,
    visited_states::Vector{Vector{Float32}},
    world_state::Vector{Float32};
    novelty_weight::Float64=0.6,
    information_gain_weight::Float64=0.4
)::Float32
    
    # If no visited states, return moderate intrinsic reward
    if isempty(visited_states)
        return 0.5f0
    end
    
    # Compute novelty: inverse distance to nearest visited state
    novelty_score = 0.0f0
    
    if !isempty(goal.target_state)
        # Calculate distances to all visited states
        distances = Float32[]
        for visited in visited_states
            if length(visited) == length(goal.target_state)
                dist = norm(goal.target_state .- visited)
                push!(distances, dist)
            end
        end
        
        if !isempty(distances)
            min_dist = minimum(distances)
            # Novelty is higher for more distant states
            # Normalize to 0-1 range (assuming max distance of 10)
            novelty_score = clamp(min_dist / 10.0f0, 0.0f0, 1.0f0)
        else
            novelty_score = 0.5f0  # Default if no comparable states
        end
    else
        novelty_score = 0.5f0
    end
    
    # Compute information gain estimate
    # Higher if target state is different from current world state
    information_gain = 0.0f0
    
    if !isempty(goal.target_state) && !isempty(world_state)
        if length(goal.target_state) == length(world_state)
            dist_to_current = norm(goal.target_state .- world_state)
            information_gain = clamp(dist_to_current / 10.0f0, 0.0f0, 1.0f0)
        end
    end
    
    # Combine scores with weights
    intrinsic = novelty_score * Float32(novelty_weight) + 
                information_gain * Float32(information_gain_weight)
    
    return clamp(intrinsic, 0.0f0, 1.0f0)
end

# ============================================================================
# GOAL GENERATION WITH CURIOSITY
# ============================================================================

"""
    generate_goals - Create new goals based on world state and user constraints
"""
function generate_goals(
    graph::GoalGraph,
    world_state::Vector{Float32},
    user_constraints::Vector{String};
    visited_states::Vector{Vector{Float32}}=Vector{Float32}[],
    max_new::Int=3
)::Vector{Goal}
    
    new_goals = Goal[]
    
    # Analyze world state for opportunities
    opportunities = analyze_world_state(world_state)
    
    # Check user constraints for alignment
    aligned_goals = align_with_constraints(opportunities, user_constraints)
    
    # Generate curiosity-driven novel goals
    for i in 1:min(max_new, length(aligned_goals))
        goal_desc = aligned_goals[i]
        
        # Create target state based on goal type
        target_state = generate_target_state(goal_desc, world_state)
        
        # Create the goal
        goal = create_goal!(
            graph,
            goal_desc;
            target_state=target_state,
            current_state=deepcopy(world_state),
            priority=0.5f0
        )
        
        # Compute intrinsic reward based on curiosity
        goal.intrinsic_reward = compute_intrinsic_reward(
            goal, visited_states, world_state
        )
        
        push!(new_goals, goal)
    end
    
    return new_goals
end

"""
    analyze_world_state - Identify opportunities in the world state
"""
function analyze_world_state(
    world_state::Vector{Float32}
)::Vector{String}
    
    opportunities = String[]
    
    # Analyze based on state dimensions and values
    if isempty(world_state)
        push!(opportunities, "Explore new state space")
        push!(opportunities, "Establish baseline understanding")
        return opportunities
    end
    
    # Detect areas for improvement
    for (i, value) in enumerate(world_state)
        if value < 0.3
            push!(opportunities, "Improve dimension $i from $(value)")
        elseif value > 0.8
            push!(opportunities, "Leverage strength in dimension $i")
        end
    end
    
    # Add general exploration goals
    if length(opportunities) < 3
        push!(opportunities, "Discover new optimization paths")
        push!(opportunities, "Reduce uncertainty in state estimation")
    end
    
    return opportunities
end

"""
    align_with_constraints - Filter opportunities based on user constraints
"""
function align_with_constraints(
    opportunities::Vector{String},
    constraints::Vector{String}
)::Vector{String}
    
    # If no constraints, return all opportunities
    if isempty(constraints)
        return opportunities
    end
    
    # Filter opportunities that don't violate constraints
    aligned = String[]
    
    for opp in opportunities
        # Simple constraint checking (in production, more sophisticated)
        violates = false
        for constraint in constraints
            if occursin(lowercase(constraint), lowercase(opp)) || 
               occursin("avoid", lowercase(constraint))
                violates = true
                break
            end
        end
        
        if !violates
            push!(aligned, opp)
        end
    end
    
    # If all filtered out, return original
    return isempty(aligned) ? opportunities : aligned
end

"""
    generate_target_state - Create target state vector for a goal
"""
function generate_target_state(
    goal_description::String,
    current_world_state::Vector{Float32}
)::Vector{Float32}
    
    # Initialize target as current state
    target = deepcopy(current_world_state)
    
    # Modify target based on goal description
    if occursin("improve", lowercase(goal_description))
        # Increase values in dimensions that can be improved
        for i in eachindex(target)
            target[i] = min(target[i] + 0.2f0, 1.0f0)
        end
    elseif occursin("explore", lowercase(goal_description))
        # Set target to explore new area
        target = rand(Float32, length(target))
    elseif occursin("reduce", lowercase(goal_description))
        # Reduce certain dimensions
        for i in eachindex(target)
            target[i] = max(target[i] - 0.1f0, 0.0f0)
        end
    elseif occursin("leverage", lowercase(goal_description))
        # Maximize strengths
        for i in eachindex(target)
            if target[i] > 0.5
                target[i] = min(target[i] + 0.1f0, 1.0f0)
            end
        end
    else
        # Default: small improvement across all dimensions
        target = target .+ 0.1f0
    end
    
    return clamp.(target, 0.0f0, 1.0f0)
end

# ============================================================================
# GOAL GRAPH UTILITIES
# ============================================================================

"""
    get_active_goals - Get all currently active goals
"""
function get_active_goals(graph::GoalGraph)::Vector{Goal}
    return [graph.goals[id] for id in graph.active_goals if haskey(graph.goals, id)]
end

"""
    get_pending_goals - Get all pending goals
"""
function get_pending_goals(graph::GoalGraph)::Vector{Goal}
    pending = Goal[]
    for (id, goal) in graph.goals
        if goal.status == :pending
            push!(pending, goal)
        end
    end
    return pending
end

"""
    get_child_goals - Get all child goals of a parent
"""
function get_child_goals(graph::GoalGraph, parent_id::UUID)::Vector{Goal}
    if !haskey(graph.goals, parent_id)
        return Goal[]
    end
    
    parent = graph.goals[parent_id]
    return [graph.goals[child_id] for child_id in parent.child_ids 
            if haskey(graph.goals, child_id)]
end

"""
    get_root_goals - Get all top-level goals
"""
function get_root_goals(graph::GoalGraph)::Vector{Goal}
    return [graph.goals[id] for id in graph.root_goals if haskey(graph.goals, id)]
end

"""
    print_goal_summary - Print summary of goal graph state
"""
function print_goal_summary(graph::GoalGraph)
    println("=== Goal Graph Summary ===")
    println("Total goals: $(length(graph.goals))")
    println("Root goals: $(length(graph.root_goals))")
    println("Active goals: $(length(graph.active_goals))")
    println("Completed goals: $(length(graph.completed_goals))")
    println("Max active: $(graph.max_active)")
    println("Curiosity weight: $(graph.curiosity_weight)")
    println()
    
    println("Active Goals:")
    for goal in get_active_goals(graph)
        println("  - $(goal.description)")
        println("    Priority: $(goal.priority), Progress: $(goal.progress)")
        println("    Intrinsic reward: $(goal.intrinsic_reward)")
    end
end

end # module GoalSystem
