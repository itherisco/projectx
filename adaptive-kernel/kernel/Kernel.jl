# kernel/Kernel.jl - Adaptive Cognitive Kernel (~830 lines)
# Core responsibilities: world state, self state, priorities, action selection, reflection
# Does NOT contain tool logic, OS logic, UI, skills, or personality.

module Kernel

using JSON
using Dates
using Statistics
using UUIDs
using Base.Threads

# Import shared types
include("../types.jl")
using .SharedTypes

# Import Phase3 types from SharedTypes
using .SharedTypes: ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType,
                     add_intent!, update_alignment!, get_alignment_penalty, GoalState, update_goal_progress!

# Import SystemObserver for real-time telemetry (Phase 3)
include("observability/SystemObserver.jl")
using .SysObserver

# Import SelfModel for dynamic confidence calibration ("Honest Uncertainty")
# Include SelfModel directly as it defines its own module
include(joinpath(@__DIR__, "..", "cognition", "metacognition", "SelfModel.jl"))

# Export decision types and kernel functions
export Observation, KernelState, Goal, GoalState, WorldState, init_kernel, step_once, run_loop, request_action, 
       get_kernel_stats, set_kernel_state!, reflect!, reflect_with_event!, get_reflection_events,
       ensure_goal_state!, get_active_goal_state, add_strategic_intent!,
       run_thought_cycle, ThoughtCycleType, _validate_kernel_metrics,
       # Decision types for sovereignty
       APPROVED, DENIED, STOPPED, approve,
       # Phase 3: SystemObserver - re-export from SysObserver
       SystemObserver, collect_real_observation, observe, get_history, get_average_metrics,
       # SelfModel for dynamic confidence ("Honest Uncertainty")
       get_dynamic_confidence, get_confidence_statement_for_context, update_kernel_from_self_model!,
       record_decision_outcome!

# Decision types for kernel sovereignty
@enum Decision APPROVED DENIED STOPPED

struct Observation
    cpu_load::Float32
    memory_usage::Float32
    disk_io::Float32
    network_latency::Float32
    file_count::Int
    process_count::Int
    custom::Dict{String, Float32}  # Additional typed metrics
    
    Observation() = new(0.0f0, 0.0f0, 0.0f0, 0.0f0, 0, 0, Dict{String, Float32}())
    Observation(cpu::Float32, mem::Float32, disk::Float32, net::Float32, files::Int, procs::Int) = 
        new(cpu, mem, disk, net, files, procs, Dict{String, Float32}())
end

mutable struct WorldState
    timestamp::DateTime
    observations::Observation  # Typed struct instead of Dict{String, Any}
    facts::Dict{String, String}
end

# Use shared ActionProposal from SharedTypes

mutable struct KernelState
    cycle::Threads.Atomic{Int}
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
    
    # Kernel sovereignty: track last decision for security assertion
    last_decision::Decision
    
    # Phase 3: SystemObserver for real-time telemetry
    system_observer::Union{SystemObserver, Nothing}
    
    # SelfModel for dynamic confidence calibration ("Honest Uncertainty")
    self_model::Union{SelfModel.SelfModelCore, Nothing}
    
    # Mutable for runtime updates only—not structural logic
    KernelState(cycle::Int, goals::Vector{Goal}, world::WorldState, active_goal_id::String) =
        new(Threads.Atomic{Int}(cycle), goals, 
            Dict(goal.id => GoalState(goal.id) for goal in goals),  # Initialize goal states
            world, active_goal_id, 
            ReflectionEvent[],  # Now uses typed ReflectionEvent
            Dict("confidence" => 0.8f0, "energy" => 1.0f0, "focus" => 0.5f0),
            nothing, 0.0f0, 0.0f0,
            IntentVector(),  # Initialize strategic intent vector
            DENIED,  # Default to DENIED for security
            nothing,  # SystemObserver initialized separately
            SelfModel.SelfModelCore()  # Initialize SelfModel for dynamic confidence
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
    
    # Handle goals - support both Dict and Goal types
    goals_config = get(config, "goals", nothing)
    if goals_config === nothing || isempty(goals_config)
        goals = [Goal("default", "Run system nominal", 0.8f0, now())]
    else
        goals = Goal[]
        for g in goals_config
            if g isa Dict
                # Handle Dict-type goal configs
                # ID must be a string
                id_raw = get(g, "id", "goal_$(length(goals))")
                id = id_raw isa String ? id_raw : string(id_raw)
                
                # Description must be a string
                desc_raw = get(g, "description", "")
                desc = desc_raw isa String ? desc_raw : string(desc_raw)
                
                # Handle priority - must be numeric
                priority_val = get(g, "priority", 0.5)
                priority = if priority_val isa Number
                    Float32(clamp(priority_val, 0.0, 1.0))
                else
                    0.5f0  # Default for non-numeric
                end
                push!(goals, Goal(id, desc, priority, now()))
            elseif g isa Goal
                # Already a Goal object
                push!(goals, g)
            end
        end
        if isempty(goals)
            goals = [Goal("default", "Run system nominal", 0.8f0, now())]
        end
    end
    # Create typed Observation from config or default
    obs_config = get(config, "observations", nothing)
    
    # Handle observations - must be a Dict or nothing
    if obs_config isa Dict
        observations = if haskey(obs_config, "cpu_load")
            Observation(
                Float32(get(obs_config, "cpu_load", 0.0)),
                Float32(get(obs_config, "memory_usage", 0.0)),
                Float32(get(obs_config, "disk_io", 0.0)),
                Float32(get(obs_config, "network_latency", 0.0)),
                get(obs_config, "file_count", 0),
                get(obs_config, "process_count", 0)
            )
        else
            Observation()
        end
    else
        # Invalid observations type - use default
        observations = Observation()
    end
    world = WorldState(now(), observations, Dict{String, String}())
    active_goal = !isempty(goals) ? goals[1].id : "default"
    
    # Create SystemObserver for real-time telemetry (Phase 3)
    system_observer = SystemObserver(1.0; history_size=100)
    
    # Initialize kernel state
    kernel = KernelState(0, goals, world, active_goal)
    kernel.system_observer = system_observer
    
    @info "Kernel initialized with SystemObserver" num_goals=length(goals) active_goal=active_goal
    return kernel
end

# ============================================================================
# Core Reasoning: Evaluate World & Compute Priorities
# ============================================================================

# P0: Fail-closed validation function for kernel metrics
function _validate_kernel_metrics(kernel::KernelState)::Bool
    for (key, value) in kernel.self_metrics
        if isnan(value) || isinf(value)
            @error "Invalid metric detected" key=value
            return false
        end
    end
    # Also validate observation values
    obs = kernel.world.observations
    if isnan(obs.cpu_load) || isnan(obs.memory_usage) || isnan(obs.disk_io) || isnan(obs.network_latency)
        @error "NaN detected in observations"
        return false
    end
    return true
end

# ============================================================================
# Dynamic Confidence Calibration - "Honest Uncertainty" Engine
# ============================================================================

"""
    get_dynamic_confidence(kernel::KernelState, decision_context::Dict=Dict())::Float32

Get dynamically calibrated confidence using SelfModel.
This is the "Honest Uncertainty" engine - replaces hardcoded 0.8f0 default.

# Arguments
- `kernel::KernelState` - The kernel state
- `decision_context::Dict` - Optional context for decision-specific confidence

# Returns
- `Float32` - Calibrated confidence between 0.05 and 0.95
"""
function get_dynamic_confidence(
    kernel::KernelState,
    decision_context::Dict=Dict()
)::Float32
    # Use SelfModel if available
    if kernel.self_model !== nothing
        return SelfModel.SelfModelCore.get_calibrated_confidence(kernel.self_model, decision_context)
    end
    
    # Fallback to self_metrics with dynamic adjustment
    base_confidence = get(kernel.self_metrics, "confidence", 0.5f0)
    
    # Adjust based on cognitive health (from self_metrics if available)
    energy = get(kernel.self_metrics, "energy", 1.0f0)
    focus = get(kernel.self_metrics, "focus", 0.5f0)
    
    # Apply penalties for low energy/focus
    if energy < 0.3
        base_confidence *= 0.7
    elseif energy < 0.5
        base_confidence *= 0.85
    end
    
    if focus < 0.3
        base_confidence *= 0.8
    end
    
    return clamp(base_confidence, 0.05f0, 0.95f0)
end

"""
    get_confidence_statement_for_context(kernel::KernelState, decision_context::Dict)::String

Generate a transparent confidence statement for a specific decision context.
This enables Jarvis to say "I am 40% sure; let's verify together".

# Arguments
- `kernel::KernelState` - The kernel state
- `decision_context::Dict` - Context containing :domain, :required_capabilities, etc.

# Returns
- `String` - Human-readable confidence statement
"""
function get_confidence_statement_for_context(
    kernel::KernelState,
    decision_context::Dict
)::String
    if kernel.self_model !== nothing
        return SelfModel.SelfModelCore.get_honest_uncertainty_statement(kernel.self_model, decision_context)
    end
    
    # Fallback statement without SelfModel
    confidence = get_dynamic_confidence(kernel, decision_context)
    confidence_pct = round(Int, confidence * 100)
    
    if confidence >= 0.7f0
        return "I am $confidence_pct% confident in this decision."
    elseif confidence >= 0.4f0
        return "I am $confidence_pct% confident. Consider verifying this."
    else
        return "I'm only $confidence_pct% confident. I recommend we verify this together."
    end
end

"""
    update_kernel_from_self_model!(kernel::KernelState)

Sync kernel self_metrics with SelfModel for consistent state.
"""
function update_kernel_from_self_model!(kernel::KernelState)
    if kernel.self_model !== nothing
        # Sync confidence from SelfModel to self_metrics
        general_context = Dict(:complexity => 0.5f0, :data_quality => 0.5f0)
        calibrated_conf = get_dynamic_confidence(kernel, general_context)
        kernel.self_metrics["confidence"] = calibrated_conf
        
        # Update capability-based info
        for (cap, score) in kernel.self_model.capabilities
            # Could extend self_metrics with capability-specific scores
        end
    end
end

"""
    record_decision_outcome!(kernel::KernelState, decision_context::Dict, actual_outcome::Bool)

Record decision outcome to improve future confidence calibration.
"""
function record_decision_outcome!(
    kernel::KernelState,
    decision_context::Dict,
    actual_outcome::Bool
)
    if kernel.self_model !== nothing
        predicted_conf = get_dynamic_confidence(kernel, decision_context)
        SelfModel.SelfModelCore.calibrate_decision!(kernel.self_model, decision_context, predicted_conf, actual_outcome)
        
        # Also update kernel self_metrics
        update_kernel_from_self_model!(kernel)
    end
end

"""
    evaluate_world(kernel::KernelState)::Vector{Float32}
Compute priority scores for active goals given current world state and self metrics.
Returns normalized [0,1] scores; heuristic: base_priority * confidence * (1 - energy_drain).
Uses real-time system observations from SystemObserver (Phase 3).
"""
function evaluate_world(kernel::KernelState)::Vector{Float32}
    # P0: Fail-closed - validate metrics before computation
    if !_validate_kernel_metrics(kernel)
        @warn "Kernel metrics invalid - returning safe defaults"
        return ones(Float32, length(kernel.goals)) ./ max(length(kernel.goals), 1)
    end
    
    # Phase 3: Collect real-time system observations
    real_observation = if kernel.system_observer !== nothing
        observe(kernel.system_observer)
    else
        # Fallback to existing observation or defaults
        kernel.world.observations
    end
    
    # Update world state with real observations
    kernel.world.observations = Observation(
        real_observation.cpu_usage,
        real_observation.memory_usage,
        real_observation.disk_io,
        real_observation.network_latency,
        real_observation.file_count,
        real_observation.process_count
    )
    
    scores = Float32[]
    confidence = get(kernel.self_metrics, "confidence", 0.8f0)
    energy = get(kernel.self_metrics, "energy", 1.0f0)
    
    # Adjust confidence based on system load (Phase 3)
    system_load = real_observation.cpu_usage
    adjusted_confidence = confidence * (1.0f0 - 0.3f0 * system_load)  # Reduce confidence under high load
    
    for goal in kernel.goals
        # Heuristic: base priority weighted by confidence, energy, and system load
        score = goal.priority * adjusted_confidence * (0.5f0 + 0.5f0 * energy)
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
function select_action(kernel::KernelState, capability_candidates::Vector{<:Any})::ActionProposal
    # Handle empty candidates
    if isempty(capability_candidates)
        return ActionProposal("none", 0.0f0, 0.0f0, 0.0f0, 0.2f0, "No candidates")
    end
    
    # Ensure we have a vector of dicts
    typed_candidates = if eltype(capability_candidates) <: Dict
        capability_candidates
    else
        # Convert Vector{Any} to Vector{Dict}
        try
            convert(Vector{Dict{String, Any}}, capability_candidates)
        catch
            # If conversion fails, return a default action
            return ActionProposal("none", 0.0f0, 0.0f0, 0.0f0, 0.2f0, "Invalid candidates")
        end
    end
    
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
    # Convert risk string to Float32 value
    risk_str = get(chosen, "risk", "low")
    risk_value = if risk_str == "high"
        0.8f0
    elseif risk_str == "medium"
        0.5f0
    else  # "low" or default
        0.2f0
    end
    return ActionProposal(
        get(chosen, "id", "unknown"),
        Float32(get(chosen, "confidence", 0.7)),
        Float32(get(chosen, "cost", 0.1)),
        best_score,
        risk_value,
        "Selected by priority heuristic (score=$(round(best_score, digits=3)))"
    )
end

"""
    approve(kernel::KernelState, proposal::ActionProposal, world_state::Dict{String, Any})::Decision
    
Kernel sovereignty function - evaluates a proposal and returns a decision.
This is the single choke point for all execution approval.

# Arguments
- `kernel::KernelState`: Current kernel state
- `proposal::ActionProposal`: The action proposal from brain (advisory only)
- `world_state::Dict{String, Any}`: Current world state for evaluation

# Returns
- `APPROVED`: Action can be executed
- `DENIED`: Action is not approved
- `STOPPED`: System should stop entirely
"""
function approve(kernel::KernelState, proposal::ActionProposal, world_state::Dict{String, Any})::Decision
    # P0: Fail-closed - default to DENIED for security
    kernel.last_decision = DENIED
    
    # If proposal is nothing, deny by default
    if proposal === nothing
        @debug "Kernel denied: no proposal"
        return DENIED
    end
    
    # Parse risk level from proposal
    risk_level = proposal.risk
    
    # Evaluate based on self-metrics
    confidence = get(kernel.self_metrics, "confidence", 0.8f0)
    energy = get(kernel.self_metrics, "energy", 1.0f0)
    
    # Check energy level - if too low, consider STOPPED
    if energy < 0.1f0
        @warn "Kernel STOPPED: critically low energy"
        kernel.last_decision = STOPPED
        return STOPPED
    end
    
    # High risk actions require high confidence
    if risk_level >= 0.7f0 && confidence < 0.8f0
        @warn "Kernel denied: high risk with low confidence" risk=risk_level confidence=confidence
        kernel.last_decision = DENIED
        return DENIED
    end
    
    # Evaluate against active goal priorities
    priority_scores = evaluate_world(kernel)
    active_idx = findfirst(g -> g.id == kernel.active_goal_id, kernel.goals)
    active_priority = active_idx !== nothing ? priority_scores[active_idx] : 0.5f0
    
    # Require minimum priority for approval
    if active_priority < 0.1f0
        @warn "Kernel denied: active goal priority too low" priority=active_priority
        kernel.last_decision = DENIED
        return DENIED
    end
    
    # Check risk threshold - reject if too high
    if risk_level > 0.8f0
        @warn "Kernel denied: risk too high" risk=risk_level
        kernel.last_decision = DENIED
        return DENIED
    end
    
    # All checks passed - approve
    @debug "Kernel approved" action=proposal.capability_id risk=risk_level confidence=confidence
    kernel.last_decision = APPROVED
    return APPROVED
end

"""
    approve_with_candidates(kernel::KernelState, proposals::Vector{ActionProposal}, 
                          capability_candidates::Vector{Dict{String, Any}})::Tuple{Decision, ActionProposal}
    
Evaluate multiple proposals and return the best one with decision.
"""
function approve_with_candidates(
    kernel::KernelState, 
    proposals::Vector{ActionProposal}, 
    capability_candidates::Vector{Dict{String, Any}}
)::Tuple{Decision, ActionProposal}
    
    # If no proposals, deny
    if isempty(proposals)
        kernel.last_decision = DENIED
        return DENIED, ActionProposal("none", 0.0f0, 0.0f0, 0.0f0, 1.0f0, "No proposals")
    end
    
    # Use select_action to evaluate candidates
    selected = select_action(kernel, capability_candidates)
    
    # Check if selected matches any proposal
    for proposal in proposals
        if proposal.capability_id == selected.capability_id
            # Evaluate this specific proposal
            decision = approve(kernel, proposal, Dict{String, Any}())
            return decision, proposal
        end
    end
    
    # No match found - deny
    kernel.last_decision = DENIED
    return DENIED, first(proposals)
end

# ============================================================================
# Reflection: Episodic Memory & Self-Model Updates (TYPED - Phase 3)
# ============================================================================

# P1: Memory budget check to prevent unbounded growth (Edge Case #1 from review)
const MAX_EPISODIC_MEMORY = 1000  # Maximum number of reflection events to retain
const MEMORY_PRUNE_BUFFER = 100    # Buffer to prevent frequent pruning at boundary

function _prune_episodic_memory!(kernel::KernelState)
    # Use >= to handle boundary case (when exactly at MAX_EPISODIC_MEMORY)
    if length(kernel.episodic_memory) >= MAX_EPISODIC_MEMORY
        # Keep most recent events with buffer to prevent thrashing
        keep_count = MAX_EPISODIC_MEMORY - MEMORY_PRUNE_BUFFER
        keep_count = max(keep_count, 100)  # Always keep at least 100 events
        kernel.episodic_memory = kernel.episodic_memory[(end-keep_count+1):end]
        @info "Pruned episodic memory" remaining=length(kernel.episodic_memory) kept=keep_count
    end
end

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
        kernel.cycle[],
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
    
    # P1: Prune episodic memory to prevent unbounded growth
    _prune_episodic_memory!(kernel)
    
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
    push!(insights, "Analysis: cycle $(kernel.cycle[]), active goal: $(kernel.active_goal_id)")
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
    if kernel.cycle[] % 10 == 0
        tc = run_thought_cycle(kernel, THOUGHT_ANALYSIS, Dict{String, Any}())
        push!(cycles, tc)
    end
    
    # Run doctrine refinement every 50 cycles
    if kernel.cycle[] % 50 == 0
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
             execute_fn::Function, permission_handler::Function)::Union{Tuple{KernelState, ActionProposal, Dict}, Tuple{Nothing, ActionProposal, Dict}}
Single cycle: observe → evaluate → decide → reflect.
- execute_fn(action)::Dict runs the capability (external).
- permission_handler(risk)::Bool returns true if action is permitted.
- Returns nothing for kernel when action is denied (fail-closed design)
"""
function step_once(kernel::KernelState, capability_candidates::Vector{<:Any}, 
                   execute_fn::Function, permission_handler::Function)::Union{Tuple{KernelState, ActionProposal, Dict}, Tuple{Nothing, ActionProposal, Dict}}
    # P1: Thread-safe cycle increment using atomic operation
    Threads.atomic_add!(kernel.cycle, 1)
    kernel.world = WorldState(now(), kernel.world.observations, kernel.world.facts)
    
    # Handle empty or any-type candidates array by converting to proper type
    typed_candidates = if isempty(capability_candidates)
        Vector{Dict{String, Any}}()
    elseif eltype(capability_candidates) <: Dict
        capability_candidates
    else
        # Convert Vector{Any} to Vector{Dict{String, Any}}
        convert(Vector{Dict{String, Any}}, capability_candidates)
    end
    
    # DECIDE: Select action
    action = select_action(kernel, typed_candidates)
    
    # PERMISSION CHECK: Verify risk level
    permitted = permission_handler(action.risk)
    
    if !permitted
        # P0: Fail-closed - denied actions should not execute or return valid kernel state
        # This prevents corrupted/invalid state from propagating
        result = Dict(
            "success" => false,
            "effect" => "Action denied by permission handler - fail-closed",
            "actual_confidence" => 0.0f0,
            "energy_cost" => 0.0f0,
            "denied" => true
        )
        reflect!(kernel, action, result)
        # Return nothing for kernel to signal invalid state (fail-closed)
        return nothing, action, result
    end
    
    # EXECUTE: Call capability with error handling
    try
        result = execute_fn(action.capability_id)
    catch e
        @error "Execution failed" error=e exception=(e, catch_backtrace())
        # Create failure result - don't propagate exception
        result = Dict(
            "success" => false,
            "effect" => "Execution error: $(string(e))",
            "actual_confidence" => 0.0f0,
            "energy_cost" => action.predicted_cost,
            "error" => string(e)
        )
    end
    
    # REFLECT: Update memory and self-metrics (even on execution failure)
    reflect!(kernel, action, result)
    
    kernel.last_action = action
    return kernel, action, result
end

"""
    run_loop(kernel::KernelState, capability_candidates::Vector{Dict{String,Any}}, 
            execute_fn::Function, permission_handler::Function, cycles::Int)::KernelState
Run event loop for N cycles. Handles fail-closed returns from step_once.
"""
function run_loop(kernel::KernelState, capability_candidates::Vector{Dict{String, Any}}, 
                  execute_fn::Function, permission_handler::Function, cycles::Int)::KernelState
    for _ in 1:cycles
        result = step_once(kernel, capability_candidates, execute_fn, permission_handler)
        # Handle fail-closed: if step_once returns nothing for kernel, stop execution
        if result[1] === nothing
            @warn "Action denied - entering fail-closed state"
            break
        end
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
        "cycle" => kernel.cycle[],
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
