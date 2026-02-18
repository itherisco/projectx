# kernel/Kernel.jl - Adaptive Cognitive Kernel (≤400 lines)
# Core responsibilities: world state, self state, priorities, action selection, reflection
# Does NOT contain tool logic, OS logic, UI, skills, or personality.

module Kernel

using JSON
using Dates
using Statistics
using UUIDs

# Import shared types
include("../types.jl")
using .SharedTypes

# Import Phase3 types from SharedTypes
using .SharedTypes: ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType,
                     add_intent!, update_alignment!, get_alignment_penalty, GoalState, update_goal_progress!

export KernelState, Goal, GoalState, WorldState, init_kernel, step_once, run_loop, request_action, 
       get_kernel_stats, set_kernel_state!, reflect!, reflect_with_event!, get_reflection_events,
       ensure_goal_state!, get_active_goal_state, add_strategic_intent!,
       run_thought_cycle, ThoughtCycleType

struct WorldState
    timestamp::DateTime
    observations::Dict{String, Any}  # e.g., {"cpu_load" => 0.5, "memory" => 2048}
    facts::Dict{String, String}      # semantic memory (key=>value pairs)
end

# Use shared ActionProposal from SharedTypes

mutable struct KernelState
    cycle::Int
    goals::Vector{Goal}  # Immutable goals
    goal_states::Dict{String, GoalState}  # Mutable goal progress tracking
    world::WorldState
    active_goal_id::String
    episodic_memory::Vector{ReflectionEvent}  # Changed to typed ReflectionEvent
    self_metrics::Dict{String, Float32}  # confidence, energy, focus
    last_action::Union{ActionProposal, Nothing}
    last_reward::Float32
    last_prediction_error::Float32
    
    # IntentVector for strategic inertia (Phase 3)
    intent_vector::IntentVector
    
    # Mutable for runtime updates only—not structural logic
    KernelState(cycle::Int, goals::Vector{Goal}, world::WorldState, active_goal_id::String) =
        new(cycle, goals, 
            Dict(goal.id => GoalState(goal.id) for goal in goals),  # Initialize goal states
            world, active_goal_id, 
            ReflectionEvent[],  # Now uses typed ReflectionEvent
            Dict("confidence" => 0.8f0, "energy" => 1.0f0, "focus" => 0.5f0),
            nothing, 0.0f0, 0.0f0,
            IntentVector()  # Initialize strategic intent vector
        )
end

# ============================================================================
# Initialization
# ============================================================================

"""
    init_kernel(config::Dict)::KernelState
Initialize kernel with goals and initial world state.
Config keys: "goals" (Vector of goal dicts with id, description, priority), "observations" (Dict).
"""
function init_kernel(config::Dict)::KernelState
    @info "Initializing kernel with config keys" keys=keys(config)
    goals = [
        Goal(g["id"], g["description"], Float32(g["priority"]), now())
        for g in get(config, "goals", [Goal("default", "Run system nominal", 0.8f0, now())])
    ]
    observations = get(config, "observations", Dict{String, Any}())
    world = WorldState(now(), observations, Dict{String, String}())
    active_goal = !isempty(goals) ? goals[1].id : "default"
    @info "Kernel initialized" num_goals=length(goals) active_goal=active_goal
    return KernelState(0, goals, world, active_goal)
end

# ============================================================================
# Core Reasoning: Evaluate World & Compute Priorities
# ============================================================================

"""
    evaluate_world(kernel::KernelState)::Vector{Float32}
Compute priority scores for active goals given current world state and self metrics.
Returns normalized [0,1] scores; heuristic: base_priority * confidence * (1 - energy_drain).
"""
function evaluate_world(kernel::KernelState)::Vector{Float32}
    scores = Float32[]
    confidence = get(kernel.self_metrics, "confidence", 0.8f0)
    energy = get(kernel.self_metrics, "energy", 1.0f0)
    
    for goal in kernel.goals
        # Heuristic: base priority weighted by confidence and energy availability
        score = goal.priority * confidence * (0.5f0 + 0.5f0 * energy)
        push!(scores, score)
    end
    # Normalize
    total = sum(scores)
    return total > 0 ? scores ./ total : ones(Float32, length(scores)) ./ length(scores)
end

# ============================================================================
# Core Selection: Choose Next Action via Deterministic Heuristic
# ============================================================================

"""
    select_action(kernel::KernelState, capability_candidates::Vector{Dict{String,Any}})::ActionProposal
Select best action candidate using heuristic: argmax(priority_score - cost * cost_weight).
Deterministic: no randomness, fully traceable for audit.
"""
function select_action(kernel::KernelState, capability_candidates::Vector{Dict{String, Any}})::ActionProposal
    isempty(capability_candidates) && return ActionProposal("none", 0.0f0, 0.0f0, 0.0f0, "low", "No candidates")
    
    priority_scores = evaluate_world(kernel)
    active_idx = findfirst(g -> g.id == kernel.active_goal_id, kernel.goals)
    active_priority = active_idx !== nothing ? priority_scores[active_idx] : 0.5f0
    
    # Get intent alignment penalty (Phase 3)
    intent_penalty = get_alignment_penalty(kernel.intent_vector)
    
    best_score = -Inf
    best_idx = 1
    
    for (i, cap) in enumerate(capability_candidates)
        cost = Float32(get(cap, "cost", 0.1))
        cap_id = get(cap, "id", "unknown")
        risk = get(cap, "risk", "low")
        
        # Heuristic utility: predicted reward - cost penalty; risk modulates confidence
        reward_pred = Float32(1.0 - cost)  # Default: higher reward if lower cost
        risk_penalty = risk == "high" ? 0.3f0 : (risk == "medium" ? 0.1f0 : 0.0f0)
        
        # Apply intent alignment penalty
        score = active_priority * (reward_pred - risk_penalty) - intent_penalty
        
        if score > best_score
            best_score = score
            best_idx = i
        end
    end
    
    chosen = capability_candidates[best_idx]
    return ActionProposal(
        get(chosen, "id", "unknown"),
        Float32(get(chosen, "confidence", 0.7)),
        Float32(get(chosen, "cost", 0.1)),
        best_score,
        get(chosen, "risk", "low"),
        "Selected by priority heuristic (score=$(round(best_score, digits=3)))"
    )
end

# ============================================================================
# Reflection: Episodic Memory & Self-Model Updates (TYPED - Phase 3)
# ============================================================================

"""
    reflect! - Record action outcome and update self-metrics (TYPED VERSION)
    Uses ReflectionEvent struct instead of Dict{String, Any}
"""
function reflect!(kernel::KernelState, action::ActionProposal, result::Dict{String, Any})
    success = get(result, "success", false)
    effect = get(result, "effect", "")
    actual_confidence = Float32(get(result, "actual_confidence", action.confidence))
    energy_cost = Float32(get(result, "energy_cost", action.predicted_cost))
    
    # Compute instantaneous reward: success bonus + effect magnitude
    reward = success ? 0.8f0 : -0.2f0
    
    # Calculate deltas for typed reflection
    old_conf = get(kernel.self_metrics, "confidence", 0.8f0)
    new_conf = 0.9f0 * old_conf + 0.1f0 * actual_confidence
    new_conf = clamp(new_conf, 0.1f0, 1.0f0)
    confidence_delta = new_conf - old_conf
    
    old_energy = get(kernel.self_metrics, "energy", 1.0f0)
    new_energy = old_energy - energy_cost
    new_energy = clamp(new_energy, 0.0f0, 1.0f0)
    energy_delta = new_energy - old_energy
    
    # Create typed ReflectionEvent (no Any type!)
    event = ReflectionEvent(
        kernel.cycle,
        action.capability_id,
        action.confidence,
        action.predicted_cost,
        success,
        reward,
        abs(action.predicted_reward - reward),
        effect;
        confidence_delta = confidence_delta,
        energy_delta = energy_delta
    )
    
    push!(kernel.episodic_memory, event)
    
    # Update self-metrics
    kernel.self_metrics["confidence"] = new_conf
    kernel.self_metrics["energy"] = new_energy
    
    # Track for audit
    kernel.last_reward = reward
    kernel.last_prediction_error = abs(action.predicted_reward - reward)
    
    # Update goal progress based on success
    if haskey(kernel.goal_states, kernel.active_goal_id)
        goal_state = kernel.goal_states[kernel.active_goal_id]
        if success
            new_progress = goal_state.progress + 0.1f0
            update_goal_progress!(goal_state, new_progress)
        else
            # Failed action - may need to reconsider approach
            goal_state.iterations += 1
        end
    end
    
    return event
end

"""
    reflect_with_event! - Directly record a ReflectionEvent
    For cases where event is constructed externally
"""
function reflect_with_event!(kernel::KernelState, event::ReflectionEvent)
    push!(kernel.episodic_memory, event)
    
    # Update self-metrics based on event deltas
    old_conf = get(kernel.self_metrics, "confidence", 0.8f0)
    kernel.self_metrics["confidence"] = clamp(old_conf + event.confidence_delta, 0.1f0, 1.0f0)
    
    old_energy = get(kernel.self_metrics, "energy", 1.0f0)
    kernel.self_metrics["energy"] = clamp(old_energy + event.energy_delta, 0.0f0, 1.0f0)
    
    kernel.last_reward = event.reward
    kernel.last_prediction_error = event.prediction_error
end

"""
    get_reflection_events - Get all reflection events (typed, no Any)
"""
function get_reflection_events(kernel::KernelState)::Vector{ReflectionEvent}
    return kernel.episodic_memory
end

# ============================================================================
# Goal State Management (Phase 3)
# ============================================================================

"""
    ensure_goal_state! - Ensure GoalState exists for a goal
"""
function ensure_goal_state!(kernel::KernelState, goal_id::String)
    if !haskey(kernel.goal_states, goal_id)
        kernel.goal_states[goal_id] = GoalState(goal_id)
    end
end

"""
    get_active_goal_state - Get mutable state for active goal
"""
function get_active_goal_state(kernel::KernelState)::Union{GoalState, Nothing}
    return get(kernel.goal_states, kernel.active_goal_id, nothing)
end

# ============================================================================
# Strategic Intent Management (Phase 3)
# ============================================================================

"""
    add_strategic_intent! - Add a long-term strategic intent
    Only updated via Kernel-approved commitments
"""
function add_strategic_intent!(kernel::KernelState, intent::String, strength::Float64 = 0.5)
    add_intent!(kernel.intent_vector, intent, strength)
end

"""
    update_intent_alignment! - Update whether action aligned with strategic intent
"""
function update_intent_alignment!(kernel::KernelState, aligned::Bool)
    update_alignment!(kernel.intent_vector, aligned)
end

"""
    get_intent_penalty - Get penalty for intent thrashing
"""
function get_intent_penalty(kernel::KernelState)::Float64
    return get_alignment_penalty(kernel.intent_vector)
end

# ============================================================================
# SELF-INITIATED THOUGHT CYCLES (Phase 3 - Non-Executing)
# ============================================================================

"""
    run_thought_cycle - Run internal cognition cycle WITHOUT executing actions
    Can refine doctrine, simulate futures, or precompute strategies
    CRITICAL: This does NOT execute any actions - it's for internal processing only
"""
function run_thought_cycle(
    kernel::KernelState,
    cycle_type::ThoughtCycleType,
    context::Dict{String, Any}
)::ThoughtCycle
    
    # Create new thought cycle
    tc = ThoughtCycle(cycle_type)
    tc.input_context = context
    
    # Perform thought based on type
    insights = Vector{String}()
    
    if cycle_type == THOUGHT_DOCTRINE_REFINEMENT
        insights = refine_doctrine(kernel, context)
    elseif cycle_type == THOUGHT_SIMULATION
        insights = simulate_outcomes(kernel, context)
    elseif cycle_type == THOUGHT_PRECOMPUTATION
        insights = precompute_strategies(kernel, context)
    elseif cycle_type == THOUGHT_ANALYSIS
        insights = analyze_state(kernel, context)
    end
    
    # Complete thought - executed remains FALSE
    complete_thought!(tc, insights)
    
    # Verify no execution occurred (security check)
    @assert tc.executed == false "Thought cycle must not execute actions!"
    
    return tc
end

"""
    refine_doctrine - Internal doctrine refinement (non-executing)
"""
function refine_doctrine(
    kernel::KernelState,
    context::Dict{String, Any}
)::Vector{String}
    insights = String[]
    
    # Analyze recent reflection events for patterns
    recent_events = kernel.episodic_memory[max(1, end-10):end]
    
    # Look for recurring prediction errors
    if !isempty(recent_events)
        mean_error = mean(e.prediction_error for e in recent_events)
        if mean_error > 0.3
            push!(insights, "High prediction error detected: consider revising confidence calibration")
        end
    end
    
    # Check for intent thrashing
    if kernel.intent_vector.thrash_count > 5
        push!(insights, "Intent thrashing detected: consider stabilizing strategic direction")
    end
    
    return insights
end

"""
    simulate_outcomes - Simulate future outcomes (non-executing)
"""
function simulate_outcomes(
    kernel::KernelState,
    context::Dict{String, Any}
)::Vector{String}
    insights = String[]
    
    # Simple simulation: what if we continued current trajectory?
    push!(insights, "Simulation: continuing current strategy would maintain momentum")
    
    # Check energy levels
    energy = get(kernel.self_metrics, "energy", 1.0f0)
    if energy < 0.3
        push!(insights, "Simulation: low energy suggests pausing major initiatives")
    end
    
    return insights
end

"""
    precompute_strategies - Precompute strategy options (non-executing)
"""
function precompute_strategies(
    kernel::KernelState,
    context::Dict{String, Any}
)::Vector{String}
    insights = String[]
    
    # Precompute based on current state
    confidence = get(kernel.self_metrics, "confidence", 0.8f0)
    
    if confidence > 0.7
        push!(insights, "Precomputed: high confidence allows aggressive strategy")
    else
        push!(insights, "Precomputed: low confidence suggests conservative approach")
    end
    
    return insights
end

"""
    analyze_state - Analyze current kernel state (non-executing)
"""
function analyze_state(
    kernel::KernelState,
    context::Dict{String, Any}
)::Vector{String}
    insights = String[]
    
    # Basic state analysis
    push!(insights, "Analysis: cycle $(kernel.cycle), active goal: $(kernel.active_goal_id)")
    push!(insights, "Analysis: confidence=$(get(kernel.self_metrics, "confidence", 0.0)), energy=$(get(kernel.self_metrics, "energy", 0.0))")
    
    return insights
end

"""
    run_periodic_thought_cycles - Run thought cycles at regular intervals
    This is called internally, does NOT execute actions
"""
function run_periodic_thought_cycles(kernel::KernelState)::Vector{ThoughtCycle}
    cycles = ThoughtCycle[]
    
    # Run analysis every 10 cycles
    if kernel.cycle % 10 == 0
        tc = run_thought_cycle(kernel, THOUGHT_ANALYSIS, Dict{String, Any}())
        push!(cycles, tc)
    end
    
    # Run doctrine refinement every 50 cycles
    if kernel.cycle % 50 == 0
        tc = run_thought_cycle(kernel, THOUGHT_DOCTRINE_REFINEMENT, Dict{String, Any}())
        push!(cycles, tc)
    end
    
    return cycles
end

# ============================================================================
# Main Event Loop Primitive
# ============================================================================

"""
    step_once(kernel::KernelState, capability_candidates::Vector{Dict{String,Any}}, 
             execute_fn::Function, permission_handler::Function)::Tuple{KernelState, ActionProposal, Dict}
Single cycle: observe → evaluate → decide → reflect.
- execute_fn(action)::Dict runs the capability (external).
- permission_handler(risk)::Bool returns true if action is permitted.
"""
function step_once(kernel::KernelState, capability_candidates::Vector{Dict{String, Any}}, 
                   execute_fn::Function, permission_handler::Function)::Tuple{KernelState, ActionProposal, Dict}
    kernel.cycle += 1
    kernel.world = WorldState(now(), kernel.world.observations, kernel.world.facts)
    
    # DECIDE: Select action
    action = select_action(kernel, capability_candidates)
    
    # PERMISSION CHECK: Verify risk level
    permitted = permission_handler(action.risk)
    
    if !permitted
        result = Dict(
            "success" => false,
            "effect" => "Action denied by permission handler",
            "actual_confidence" => 0.0f0,
            "energy_cost" => 0.0f0
        )
        reflect!(kernel, action, result)
        return kernel, action, result
    end
    
    # EXECUTE: Call capability
    result = execute_fn(action.capability_id)
    
    # REFLECT: Update memory and self-metrics
    reflect!(kernel, action, result)
    
    kernel.last_action = action
    return kernel, action, result
end

"""
    run_loop(kernel::KernelState, capability_candidates::Vector{Dict{String,Any}}, 
            execute_fn::Function, permission_handler::Function, cycles::Int)::KernelState
Run event loop for N cycles.
"""
function run_loop(kernel::KernelState, capability_candidates::Vector{Dict{String, Any}}, 
                  execute_fn::Function, permission_handler::Function, cycles::Int)::KernelState
    for _ in 1:cycles
        step_once(kernel, capability_candidates, execute_fn, permission_handler)
    end
    return kernel
end

# ============================================================================
# Public Introspection API
# ============================================================================

"""
    get_kernel_stats(kernel::KernelState)::Dict{String, Any}
Return summary stats for monitoring/debugging.
"""
function get_kernel_stats(kernel::KernelState)::Dict{String, Any}
    return Dict(
        "cycle" => kernel.cycle,
        "active_goal" => kernel.active_goal_id,
        "confidence" => get(kernel.self_metrics, "confidence", 0.8f0),
        "energy" => get(kernel.self_metrics, "energy", 1.0f0),
        "episodic_memory_size" => length(kernel.episodic_memory),
        "mean_reward" => !isempty(kernel.episodic_memory) ? 
            mean([e.reward for e in kernel.episodic_memory]) : 0.0,
        "last_action" => kernel.last_action !== nothing ? kernel.last_action.capability_id : "none",
        "last_reward" => kernel.last_reward,
        "intent_thrash_count" => kernel.intent_vector.thrash_count,
        "num_strategic_intents" => length(kernel.intent_vector.intents)
    )
end

"""
    set_kernel_state!(kernel::KernelState, observations::Dict{String,Any})
Update world observations (e.g., from perception capability).
"""
function set_kernel_state!(kernel::KernelState, observations::Dict{String, Any})
    kernel.world = WorldState(now(), observations, kernel.world.facts)
end

end  # module Kernel
