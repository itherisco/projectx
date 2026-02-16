# kernel/Kernel.jl - Adaptive Cognitive Kernel (≤400 lines)
# Core responsibilities: world state, self state, priorities, action selection, reflection
# Does NOT contain tool logic, OS logic, UI, skills, or personality.

module Kernel

using JSON
using Dates
import Statistics: mean

export KernelState, Goal, WorldState, init_kernel, step_once, run_loop, request_action, 
       get_kernel_stats, set_kernel_state!

# ============================================================================
# Data Structures (immutable-by-design: struct fields are not changed after init)
# ============================================================================

struct Goal
    id::String
    description::String
    priority::Float32  # [0, 1]
    created_at::DateTime
end

struct WorldState
    timestamp::DateTime
    observations::Dict{String, Any}  # e.g., {"cpu_load" => 0.5, "memory" => 2048}
    facts::Dict{String, String}      # semantic memory (key=>value pairs)
end

struct ActionProposal
    capability_id::String
    confidence::Float32  # [0, 1]
    predicted_cost::Float32  # [0, 1]
    predicted_reward::Float32  # relative utility
    risk::String  # "low", "medium", "high"
    reasoning::String
end

mutable struct KernelState
    cycle::Int
    goals::Vector{Goal}
    world::WorldState
    active_goal_id::String
    episodic_memory::Vector{Dict{String, Any}}  # Each entry: {timestamp, cycle, action_id, result, reward, prediction_error}
    self_metrics::Dict{String, Float32}  # confidence, energy, focus
    last_action::Union{ActionProposal, Nothing}
    last_reward::Float32
    last_prediction_error::Float32
    
    # Mutable for runtime updates only—not structural logic
    KernelState(cycle::Int, goals::Vector{Goal}, world::WorldState, active_goal_id::String) =
        new(cycle, goals, world, active_goal_id, [], 
            Dict("confidence" => 0.8f0, "energy" => 1.0f0, "focus" => 0.5f0),
            nothing, 0.0f0, 0.0f0)
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
    goals = [
        Goal(g["id"], g["description"], Float32(g["priority"]), now())
        for g in get(config, "goals", [Goal("default", "Run system nominal", 0.8f0, now())])
    ]
    observations = get(config, "observations", Dict{String, Any}())
    world = WorldState(now(), observations, Dict{String, String}())
    active_goal = !isempty(goals) ? goals[1].id : "default"
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
    
    best_score = -Inf
    best_idx = 1
    
    for (i, cap) in enumerate(capability_candidates)
        cost = Float32(get(cap, "cost", 0.1))
        cap_id = get(cap, "id", "unknown")
        risk = get(cap, "risk", "low")
        
        # Heuristic utility: predicted reward - cost penalty; risk modulates confidence
        reward_pred = Float32(1.0 - cost)  # Default: higher reward if lower cost
        risk_penalty = risk == "high" ? 0.3f0 : (risk == "medium" ? 0.1f0 : 0.0f0)
        score = active_priority * (reward_pred - risk_penalty)
        
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
# Reflection: Episodic Memory & Self-Model Updates
# ============================================================================

"""
    reflect!(kernel::KernelState, action::ActionProposal, result::Dict{String,Any})
Record action outcome and update self-metrics (confidence, energy).
"""
function reflect!(kernel::KernelState, action::ActionProposal, result::Dict{String, Any})
    success = get(result, "success", false)
    effect = get(result, "effect", "")
    actual_confidence = Float32(get(result, "actual_confidence", action.confidence))
    energy_cost = Float32(get(result, "energy_cost", action.predicted_cost))
    
    # Compute instantaneous reward: success bonus + effect magnitude
    reward = success ? 0.8f0 : -0.2f0
    
    # Record in episodic memory
    entry = Dict(
        "timestamp" => now(),
        "cycle" => kernel.cycle,
        "action_id" => action.capability_id,
        "result" => success,
        "reward" => reward,
        "prediction_error" => abs(action.predicted_reward - reward),
        "effect" => effect
    )
    push!(kernel.episodic_memory, entry)
    
    # Update self-metrics
    old_conf = get(kernel.self_metrics, "confidence", 0.8f0)
    new_conf = 0.9f0 * old_conf + 0.1f0 * actual_confidence
    kernel.self_metrics["confidence"] = clamp(new_conf, 0.1f0, 1.0f0)
    
    old_energy = get(kernel.self_metrics, "energy", 1.0f0)
    new_energy = old_energy - energy_cost
    kernel.self_metrics["energy"] = clamp(new_energy, 0.0f0, 1.0f0)
    
    # Track for audit
    kernel.last_reward = reward
    kernel.last_prediction_error = entry["prediction_error"]
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
            mean([get(e, "reward", 0.0) for e in kernel.episodic_memory]) : 0.0,
        "last_action" => kernel.last_action !== nothing ? kernel.last_action.capability_id : "none",
        "last_reward" => kernel.last_reward
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
