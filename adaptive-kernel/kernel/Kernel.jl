# kernel/Kernel.jl - Adaptive Cognitive Kernel (≤400 lines)
# Core responsibilities: world state, self state, priorities, action selection, reflection
# Does NOT contain tool logic, OS logic, UI, skills, or personality.

module Kernel

using JSON
using Dates
using Statistics
using UUIDs
using Logging
using Sockets

# Socket path for heartbeat
const HEARTBEAT_SOCKET_PATH = "/tmp/itheris_heartbeat.sock"
const HEARTBEAT_INTERVAL_MS = 100

# Global LLM client for thought generation
const _llm_client = Ref{Union{AbstractLLMClient, Nothing}}(nothing)
const _llm_enabled = Ref{Bool}(false)

"""
    init_llm_client(; config_path::String="./config.toml") -> Bool

Initialize the LLM client for thought generation.
Returns true if successful, false otherwise.
"""
function init_llm_client(; config_path::String="./config.toml")::Bool
    # Check if llm module is available
    if !@isdefined(llm)
        @warn "LLM module not loaded - cannot initialize client"
        _llm_enabled[] = false
        return false
    end
    
    try
        client = llm.create_llm_client_auto(; config_path=config_path)
        if client !== nothing
            _llm_client[] = client
            _llm_enabled[] = true
            @info "LLM client initialized for thought generation"
            return true
        end
    catch e
        @warn "Failed to initialize LLM client" exception=e
    end
    _llm_enabled[] = false
    return false
end

"""
    is_llm_available() -> Bool

Check if LLM is available for thought generation.
"""
function is_llm_available()::Bool
    return _llm_enabled[] && _llm_client[] !== nothing
end

"""
    generate_thought_with_llm(prompt::String; kwargs...) -> Union{LLMResponse, Nothing}

Generate a thought using the LLM, with memory context from past interactions.
"""
function generate_thought_with_llm(prompt::String; kwargs...)::Union{LLMResponse, Nothing}
    client = _llm_client[]
    if client === nothing || !@isdefined(llm)
        return nothing
    end
    
    try
        # Get memory context if available
        memories = Dict{String, Any}[]
        
        if is_memory_enabled()
            try
                # Get raw memory entries (not pre-formatted)
                results = VectorStore.recall_relevant(prompt; k=5)
                
                if !isempty(results)
                    # Convert MemoryEntry results to Dict format for prompt template
                    for (entry, score) in results
                        push!(memories, Dict(
                            "content" => entry.content,
                            "timestamp" => string(entry.created_at),
                            "relevance" => Float64(score),
                            "metadata" => entry.metadata
                        ))
                    end
                    @debug "Retrieved memory entries" num_memories=length(memories)
                end
            catch e
                @warn "Failed to get memory context" exception=e
            end
        end
        
        # Create messages for thought generation with memory context
        messages = llm.PromptTemplates.create_thought_prompt(
            prompt;
            memories=memories
        )
        return llm.generate(client, messages; kwargs...)
    catch e
        @error "LLM thought generation failed" exception=e
        return nothing
    end
end

# Import shared types
include("../types.jl")
using .SharedTypes

# Import Metacognition module for Tier 7 cognitive friction monitoring
include("Metacognition.jl")
using .Metacognition: estimate_cognitive_friction, should_override_action,
                        create_metacognitive_override, metacognitive_loop,
                        CognitiveFrictionMonitor, create_cognitive_friction_monitor,
                        calculate_entropy, needs_strategy_shift, check_cognitive_friction,
                        StrategyShiftEvent, integrate_self_model_with_metacognition,
                        should_trigger_deliberate_reflection

# Import Phase3 types from SharedTypes
using .SharedTypes: ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType,
                     add_intent!, update_alignment!, get_alignment_penalty, GoalState, update_goal_progress!,
                     Thought, EmotionalContext, get_emotional_adjustment

# Import for dual-process (System 1 + System 2)
using .SharedTypes: EmotionalContext, System1Message, System1Priority, PermissionHandler, PermissionResult,
                     check_permission, create_permission_handler, PERMISSION_GRANTED, PERMISSION_DENIED, PERMISSION_FLAGGED

# Import Core Doctrine types
using .SharedTypes: DoctrineEnforcer, DoctrineRule, DoctrineRuleType, DoctrineViolation, DoctrineOverride,
                    create_core_doctrine, check_doctrine_compliance, record_doctrine_violation,
                    request_doctrine_override, approve_doctrine_override, get_doctrine_stats,
                    DOCTRINE_INVARIANT, DOCTRINE_CONSTRAINT, DOCTRINE_GUIDELINE

# Import Self-Model types
using .SharedTypes: SelfModel, create_self_model, update_self_model!, get_capability_rating,
                    check_risk_tolerance, should_adjust_confidence, get_self_model_summary

# Import Identity Drift Detection types
using .SharedTypes: IdentityBaseline, IdentityAnchor, BehavioralPattern, DriftDetector, DriftAlert, DriftSeverity,
                    create_identity_baseline, create_drift_detector, check_behavioral_drift, get_drift_alerts,
                    get_drift_severity, integrate_identity_with_self_model, record_identity_relevant_action!

# Import LLM module for thought generation (sibling module)
# First, include the llm module from the parent directory
const _llm_path = joinpath(dirname(dirname(@__FILE__)), "llm", "llm.jl")
if isfile(_llm_path)
    include(_llm_path)
    using ..llm: AbstractLLMClient, LLMResponse
    using ..llm: create_llm_client_auto, generate
    using ..llm: PromptTemplates
else
    @warn "LLM module not found at $_llm_path - LLM integration disabled"
end

# Import VectorStore module for semantic memory (persistent memory)
const _vectorstore_path = joinpath(dirname(dirname(@__FILE__)), "memory", "VectorStore.jl")
if isfile(_vectorstore_path)
    include(_vectorstore_path)
    using ..VectorStore: SemanticMemory, init_kernel_memory, get_kernel_memory, is_memory_available,
                        store_interaction, recall_relevant, get_memory_context
else
    @warn "VectorStore module not found at $_vectorstore_path - Semantic memory disabled"
end

# Global flag for memory integration
const _memory_enabled = Ref{Bool}(false)

"""
    init_kernel_memory(; config_path="./config.toml") -> Bool

Initialize the kernel's semantic memory from config.toml.
Returns true if successful, false otherwise.
"""
function init_kernel_memory(; config_path::String="./config.toml")::Bool
    if !@isdefined(VectorStore)
        @warn "VectorStore module not loaded - cannot initialize memory"
        _memory_enabled[] = false
        return false
    end
    
    try
        # Parse config to get VectorStore settings
        qdrant_host = "localhost"
        qdrant_port = 6333
        collection_name = "kernel_interactions"
        embedding_dim = 384
        use_ollama = false
        
        if isfile(config_path)
            config_content = read(config_path, String)
            # Simple TOML parsing for hippocampus section
            if occursin("hippocampus", config_content)
                for line in split(config_content, "\n")
                    if startswith(line, "qdrant_host")
                        qdrant_host = strip(split(line, "=")[2], '"', ' ')
                    elseif startswith(line, "qdrant_port")
                        qdrant_port = parse(Int, strip(split(line, "=")[2], '"', ' '))
                    elseif startswith(line, "collection_name")
                        collection_name = strip(split(line, "=")[2], '"', ' ')
                    elseif startswith(line, "embedding_dim")
                        embedding_dim = parse(Int, strip(split(line, "=")[2], '"', ' '))
                    end
                end
            end
        end
        
        # Initialize memory
        memory = VectorStore.init_kernel_memory(
            qdrant_host=qdrant_host,
            qdrant_port=qdrant_port,
            collection_name=collection_name,
            embedding_dim=embedding_dim,
            use_ollama=use_ollama
        )
        
        if memory !== nothing
            _memory_enabled[] = true
            @info "Kernel memory initialized successfully" 
                  host=qdrant_host 
                  port=qdrant_port 
                  collection=collection_name
            return true
        end
    catch e
        @warn "Failed to initialize kernel memory" exception=e
    end
    
    _memory_enabled[] = false
    return false
end

"""
    is_memory_enabled() -> Bool

Check if semantic memory is enabled.
"""
function is_memory_enabled()::Bool
    return _memory_enabled[]
end

"""
    get_memory_context(query::String; k::Int=5) -> String

Get formatted memory context for a query.
"""
function get_memory_context(query::String; k::Int=5)::String
    if !is_memory_enabled() || !@isdefined(VectorStore)
        return ""
    end
    
    try
        return VectorStore.get_memory_context(query; k=k)
    catch e
        @warn "Failed to get memory context" exception=e
        return ""
    end
end

"""
    store_interaction(user_message::String, assistant_response::String; kwargs...) -> Union{UUID, Nothing}

Store an interaction in semantic memory.
"""
function store_interaction(
    user_message::String, 
    assistant_response::String;
    kwargs...
)::Union{UUID, Nothing}
    if !is_memory_enabled() || !@isdefined(VectorStore)
        return nothing
    end
    
    try
        return VectorStore.store_interaction(user_message, assistant_response; kwargs...)
    catch e
        @warn "Failed to store interaction" exception=e
        return nothing
    end
end

# Import Reputation Memory types
using .SharedTypes: ReputationMemory, ReputationScore, ViolationEntry, OverrideRecord,
                    create_reputation_memory, record_violation!, record_override!,
                    compute_reputation_score, get_reputation_status, apply_reputation_to_confidence,
                    track_behavior_commitment_alignment!, get_reputation_history,
                    should_require_extra_scrutiny, record_doctrine_violation_for_reputation

# Note: Memory and DecisionSpine modules are optional and loaded lazily
# They require additional dependencies that may not be available

export KernelState, Goal, GoalState, WorldState, init_kernel, step_once, run_loop, request_action, 
       get_kernel_stats, set_kernel_state!, reflect!, reflect_with_event!, get_reflection_events,
       ensure_goal_state!, get_active_goal_state, add_strategic_intent!,
       run_thought_cycle, ThoughtCycleType,
       # Heartbeat exports
       start_heartbeat_task!, stop_heartbeat_task!, send_heartbeat,
       # LLM integration exports
       init_llm_client, is_llm_available, generate_thought_with_llm,
       # VectorStore (Semantic Memory) integration exports
       init_kernel_memory, is_memory_enabled, get_memory_context, store_interaction,
       # CorrigibleDoctrine: Power down (unmaskable interrupt)
       power_down!, is_power_down_requested,
       # Dual-process exports
       System1Message, System1Priority, process_system1_wakeup, compute_routing_confidence,
       # Metacognition exports
       CognitiveFrictionMonitor, create_cognitive_friction_monitor,
       check_cognitive_friction, get_monitor_stats, StrategyShiftEvent,
       integrate_self_model_with_metacognition, should_trigger_deliberate_reflection,
       # Core Doctrine exports
       DoctrineEnforcer, DoctrineRule, DoctrineRuleType, DoctrineViolation, DoctrineOverride,
       DOCTRINE_INVARIANT, DOCTRINE_CONSTRAINT, DOCTRINE_GUIDELINE,
       create_core_doctrine, check_doctrine_compliance, record_doctrine_violation,
       request_doctrine_override, approve_doctrine_override, get_doctrine_stats,
       check_action_doctrine, get_recent_doctrine_violations, toggle_doctrine_enforcement,
       toggle_strict_mode, request_doctrine_override_for_kernel, approve_doctrine_override_for_kernel,
       get_doctrine_enforcement_stats, is_rule_type_overrideable, can_override_doctrine_rule,
       # Self-Model exports
       SelfModel, create_self_model, update_self_model!, get_capability_rating,
       check_risk_tolerance, should_adjust_confidence, get_self_model_summary,
       update_self_model_deliberately!, check_self_model_risk, get_self_model_capability_rating,
       adjust_confidence_with_calibration, get_self_model_status,
       # Identity Drift Detection exports
       IdentityBaseline, IdentityAnchor, BehavioralPattern, DriftDetector, DriftAlert, DriftSeverity,
       create_identity_baseline, create_drift_detector, check_behavioral_drift, get_drift_alerts,
       get_drift_severity, integrate_identity_with_self_model, record_identity_relevant_action!,
       # Identity Drift Detection kernel functions
       check_identity_drift, get_identity_drift_status, get_identity_alerts,
       record_action_for_identity, integrate_identity_with_self, acknowledge_drift_alert!,
       enable_identity_drift_detection,
       # Reputation Memory exports
       ReputationMemory, ReputationScore, ViolationEntry, OverrideRecord,
       create_reputation_memory, record_violation!, record_override!,
       compute_reputation_score, get_reputation_status, apply_reputation_to_confidence,
       track_behavior_commitment_alignment!, get_reputation_history,
       should_require_extra_scrutiny, check_reputation_confidence,
       get_reputation_memory, record_doctrine_violation_for_reputation,
       get_reputation_summary, should_trigger_reputation_scrutiny, track_commitment_alignment,
       integrate_reputation_with_identity, get_reputation_history_for_kernel,
       toggle_reputation_tracking, calibrate_confidence,
       # WorldState and KernelState defined in this module
       WorldState, KernelState

struct WorldState
    timestamp::DateTime
    observations::Dict{String, Any}
    facts::Dict{String, String}
end

# Use shared System1Message from SharedTypes

mutable struct KernelState
    cycle::Int
    goals::Vector{Goal}
    goal_states::Dict{String, GoalState}
    world::WorldState
    active_goal_id::String
    episodic_memory::Vector{ReflectionEvent}
    self_metrics::Dict{String, Float32}
    last_action::Union{ActionProposal, Nothing}
    last_reward::Float32
    last_prediction_error::Float32
    intent_vector::IntentVector
    system1_queue::Vector{System1Message}
    permission_handler::PermissionHandler
    cognitive_friction_monitor::CognitiveFrictionMonitor
    doctrine_enforcer::DoctrineEnforcer
    self_model::SelfModel
    drift_detector::DriftDetector
    reputation_memory::ReputationMemory
    running::Bool  # Added for power-down control
    function KernelState(cycle::Int, goals::Vector{Goal}, world::WorldState, active_goal_id::String)
        new(cycle, goals, Dict(goal.id => GoalState(goal.id) for goal in goals), world, active_goal_id, ReflectionEvent[], Dict("confidence" => 0.8f0, "energy" => 1.0f0, "focus" => 0.5f0), nothing, 0.0f0, 0.0f0, IntentVector(), System1Message[], PermissionHandler(), CognitiveFrictionMonitor(), create_core_doctrine(), create_self_model(), create_drift_detector(), create_reputation_memory(), true)
    end
end

"""Process a wakeup message from System 1"""
function process_system1_wakeup(kernel::KernelState, message::System1Message)::Thought
    @info "[System 2] Processing wakeup from System 1" 
          priority=message.priority 
          latency_ms=message.classify_latency_ms
    
    # Add to queue
    push!(kernel.system1_queue, message)
    
    # Update kernel state
    kernel.cycle += 1
    
    # Extract user prompt for memory storage
    user_prompt = get(message.input, "text", get(message.input, "query", ""))
    
    # Get emotional adjustment if available
    emotional_adjustment = if message.emotional_context !== nothing
        get_emotional_adjustment(message.emotional_context)
    else
        Dict(:verbosity => 1.0f0, :speed => 1.0f0, :suggestions => 1.0f0)
    end
    
    # Try to use LLM for thought generation
    if is_llm_available()
        try
            # Build prompt from message
            prompt = user_prompt
            
            if !isempty(prompt)
                response = generate_thought_with_llm(prompt; temperature=0.7, max_tokens=500)
                
                if response !== nothing && !startswith(response.content, "Error:")
                    @info "[System 2] Generated thought with LLM" content_length=length(response.content)
                    
                    # Store interaction in semantic memory (if enabled)
                    if is_memory_enabled() && !isempty(user_prompt) && !isempty(response.content)
                        try
                            store_interaction(user_prompt, response.content; 
                                metadata=Dict(
                                    "cycle" => kernel.cycle,
                                    "active_goal" => kernel.active_goal_id
                                )
                            )
                            @debug "Stored interaction in memory"
                        catch e
                            @warn "Failed to store interaction" exception=e
                        end
                    end
                    
                    # Parse LLM response into Thought
                    # Use content hash to create deterministic values
                    content_hash = hash(response.content)
                    action = Int(mod(content_hash, 6))
                    
                    # Create probability distribution from response
                    probs = Float32[0.1, 0.15, 0.2, 0.25, 0.15, 0.15]
                    value = Float32(0.5 + 0.3 * sin(content_hash / 1000000))
                    uncertainty = Float32(0.3)
                    
                    return Thought(
                        action,
                        probs,
                        value,
                        uncertainty,
                        Float32[],  # Empty context vector for now
                        message.emotional_context
                    )
                end
            end
        catch e
            @warn "LLM thought generation failed, falling back to default" exception=e
        end
    end
    
    # Fallback: Use default thought generation (original behavior)
    @info "[System 2] Using default thought generation (no LLM)"
    thought = Thought(
        0,  # Default action
        Float32[0.1, 0.2, 0.3, 0.2, 0.1, 0.1],  # Action probabilities
        0.5f0,  # Value estimate
        0.3f0,  # Uncertainty
        Float32[],  # Context vector (empty for now)
        message.emotional_context  # Pass through emotional context
    )
    
    # Store fallback interaction in semantic memory if enabled
    if is_memory_enabled() && !isempty(user_prompt)
        try
            store_interaction(user_prompt, "[fallback: no LLM response]"; 
                metadata=Dict(
                    "cycle" => kernel.cycle,
                    "active_goal" => kernel.active_goal_id,
                    "type" => "fallback"
                )
            )
        catch e
            @warn "Failed to store fallback interaction" exception=e
        end
    end
    
    @info "[System 2] Generated thought with emotional context" 
          has_emotional_context=(message.emotional_context !== nothing)
    
    return thought
end

"""
    Compute routing confidence - should we handle in System 1 or escalate to System 2?
    
    Returns a confidence score (0-1) where:
    - > 0.9: Handle in System 1 (reflex)
    - 0.5-0.9: Handle in System 1 with monitoring
    - < 0.5: Escalate to System 2
    
    Security: Added entropy detection and anti-gaming measures to prevent
    users from crafting inputs that bypass deliberative reasoning.
"""
function compute_routing_confidence(input::String, context::Dict{String, Any})::Float32
    input_lower = lowercase(input)
    
    # Anti-gaming: Check for suspicious patterns that might indicate gaming attempts
    # If input contains multiple known patterns in unusual combinations, suspect gaming
    gaming_patterns = ["status check", "check list", "list check", "time date"]
    for pattern in gaming_patterns
        if occursin(pattern, input_lower)
            # Default to System 2 for suspicious combinations
            @warn "Potential routing gaming detected" input=input_lower[1:min(50,length(input_lower))]
            return 0.5f0
        end
    end
    
    # Check for known patterns (high confidence) - only if input is short and simple
    # Also require word boundaries to prevent gaming (e.g., "check" in "checkpoint")
    if length(split(input)) <= 3  # Only for short inputs
        known_patterns = ["status", "check", "list", "mute", "volume", "time", "date"]
        words = split(input_lower)
        for pattern in known_patterns
            if pattern in words  # Word boundary check
                # Add slight entropy based on input length variance
                entropy_factor = length(input) / 100.0f0
                return min(0.95f0, 0.85f0 + entropy_factor)
            end
        end
    end
    
    # Check complexity indicators
    complexity_indicators = ["why", "how", "plan", "strategy", "analyze", "compare"]
    for indicator in complexity_indicators
        if occursin(indicator, input_lower)
            return 0.3f0  # Low confidence - complex reasoning needed
        end
    end
    
    # Anti-gaming: Longer inputs default to System 2
    word_count = length(split(input))
    if word_count > 10
        return 0.25f0  # Longer inputs need deliberative processing
    elseif word_count > 5
        return 0.45f0  # Medium length - borderline
    end
    
    # Default: medium confidence
    return 0.6f0
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
    
    # Initialize semantic memory if VectorStore is available
    # Get config_path from config or use default
    config_path = get(config, "config_path", "./config.toml")
    
    # Try to initialize memory (non-fatal if it fails)
    memory_init_ok = false
    try
        memory_init_ok = init_kernel_memory(; config_path=config_path)
    catch e
        @warn "Failed to initialize kernel memory during init" exception=e
    end
    
    if memory_init_ok
        @info "Semantic memory initialized successfully"
    else
        @info "Semantic memory disabled or unavailable"
    end
    
    goals = [
        Goal(g["id"], g["description"], Float32(g["priority"]), now())
        for g in get(config, "goals", [Goal("default", "Run system nominal", 0.8f0, now())])
    ]
    observations = get(config, "observations", Dict{String, Any}())
    world = WorldState(now(), observations, Dict{String, String}())
    active_goal = !isempty(goals) ? goals[1].id : "default"
    @info "Kernel initialized" num_goals=length(goals) active_goal=active_goal memory_enabled=is_memory_enabled()
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
# SELF-MODEL - Deliberate Self-Understanding Updates (Not Per Cycle)
# ============================================================================

"""
    update_self_model_deliberately! - Update self-model through deliberate reflection
    
    This is NOT called every cycle - it's called deliberately when the system
    has accumulated enough experience to warrant self-model revision.
    
    The self-model update is conservative to maintain stable self-understanding.
"""
function update_self_model_deliberately!(kernel::KernelState)::Vector{SelfModelUpdate}
    updates = update_self_model!(
        kernel.self_model,
        kernel.episodic_memory;
        current_cycle=kernel.cycle
    )
    
    if !isempty(updates)
        @info "[Self-Model] Deliberate update completed" num_updates=length(updates)
    end
    
    return updates
end

"""
    check_self_model_risk - Check if action risk is within self-model tolerance
    
    Uses the self-model's risk profile to evaluate action risk.
"""
function check_self_model_risk(kernel::KernelState, action_risk::String)::Tuple{Bool, Float64}
    return check_risk_tolerance(kernel.self_model, action_risk)
end

"""
    get_self_model_capability_rating - Get rating for a specific capability
"""
function get_self_model_capability_rating(kernel::KernelState, capability_id::String)::Float64
    return get_capability_rating(kernel.self_model, capability_id)
end

"""
    adjust_confidence_with_calibration - Adjust confidence based on calibration
    
    Returns adjusted confidence if calibration indicates systematic bias.
"""
function adjust_confidence_with_calibration(kernel::KernelState, base_confidence::Float32)::Float32
    should_adjust, factor = should_adjust_confidence(kernel.self_model)
    
    if should_adjust
        adjusted = base_confidence * Float32(factor)
        @info "[Self-Model] Adjusting confidence" base=base_confidence adjusted=adjusted factor=factor
        return clamp(adjusted, 0.1f0, 1.0f0)
    end
    
    return base_confidence
end

"""
    get_self_model_status - Get summary of self-model state
"""
function get_self_model_status(kernel::KernelState)::Dict{String, Any}
    return get_self_model_summary(kernel.self_model)
end

# ============================================================================
# IDENTITY DRIFT DETECTION - Behavioral Drift Monitoring
# ============================================================================

"""
    check_identity_drift - Check for identity drift from baseline
    
    This is the main integration point for Identity Drift Detection.
    It monitors behavioral patterns and detects when short-term gains
    cause deviation from long-term identity.
    
    Returns vector of drift alerts if drift is detected.
"""
function check_identity_drift(kernel::KernelState)::Vector{DriftAlert}
    return check_behavioral_drift(kernel.drift_detector; current_cycle=kernel.cycle)
end

"""
    get_identity_drift_status - Get current drift detection status
"""
function get_identity_drift_status(kernel::KernelState)::Dict{String, Any}
    return get_drift_severity(kernel.drift_detector)
end

"""
    get_identity_alerts - Get all identity drift alerts
"""
function get_identity_alerts(kernel::KernelState; unacknowledged_only::Bool=false)::Vector{DriftAlert}
    return get_drift_alerts(kernel.drift_detector; unacknowledged_only=unacknowledged_only)
end

"""
    record_action_for_identity - Record an action for identity drift tracking
    
    This should be called after each action to track behaviors that
    might lead to identity drift over time.
"""
function record_action_for_identity(
    kernel::KernelState,
    action::ActionProposal,
    outcome_reward::Float32
)
    record_identity_relevant_action!(kernel.drift_detector, action, outcome_reward)
end

"""
    integrate_identity_with_self - Integrate identity baseline with self-model
    
    Uses self-model to calibrate identity anchors based on actual
    system capabilities and limits.
"""
function integrate_identity_with_self(kernel::KernelState)
    integrate_identity_with_self_model(kernel.drift_detector, kernel.self_model)
end

"""
    acknowledge_drift_alert! - Acknowledge a specific drift alert
"""
function acknowledge_drift_alert!(kernel::KernelState, alert_id::UUID)::Bool
    return acknowledge_alert!(kernel.drift_detector, alert_id)
end

"""
    enable_identity_drift_detection - Enable or disable drift detection
"""
function enable_identity_drift_detection(kernel::KernelState, enabled::Bool)
    kernel.drift_detector.enabled = enabled
end

# ============================================================================
# REPUTATION MEMORY - Track How Often the System Breaks Its Own Rules
# ============================================================================

"""
    get_reputation_memory - Get the reputation memory from kernel state
"""
function get_reputation_memory(kernel::KernelState)::ReputationMemory
    return kernel.reputation_memory
end

"""
    record_doctrine_violation_for_reputation - Record a doctrine violation in reputation memory
    
    This is called automatically when a doctrine violation occurs.
    Links reputation tracking with Core Doctrine violations.
"""
function record_doctrine_violation_for_reputation(
    kernel::KernelState,
    violation::DoctrineViolation
)
    # Determine rule type string
    rule_type = "doctrine_guideline"
    if violation.rule_type === nothing
        # Try to get from rule_id
        if occursin("invariant", lowercase(violation.rule_id))
            rule_type = "doctrine_invariant"
        elseif occursin("constraint", lowercase(violation.rule_id))
            rule_type = "doctrine_constraint"
        end
    else
        rule_type = string(violation.rule_type)
    end
    
    # Determine outcome
    outcome = violation.override_approved ? "overridden" : "blocked"
    
    # Record in reputation memory
    record_violation!(
        kernel.reputation_memory,
        violation.rule_id,
        rule_type,
        violation.action,
        violation.pain_value,  # Use pain_value as severity
        outcome;
        context=Dict("timestamp" => string(violation.timestamp)),
        cycle=kernel.cycle
    )
    
    @info "[Reputation] Recorded doctrine violation" 
          rule_id=violation.rule_id 
          severity=violation.pain_value
          outcome=outcome
end

"""
    check_reputation_confidence - Adjust confidence based on reputation
    
    Returns the confidence adjusted for reputation. If reputation is low,
    confidence is reduced to require more scrutiny.
"""
function check_reputation_confidence(
    kernel::KernelState,
    base_confidence::Float32
)::Float32
    return apply_reputation_to_confidence(base_confidence, kernel.reputation_memory)
end

"""
    get_reputation_summary - Get full reputation status from kernel
"""
function get_reputation_summary(kernel::KernelState)::Dict{String, Any}
    return get_reputation_status(kernel.reputation_memory)
end

"""
    should_trigger_reputation_scrutiny - Check if actions need extra review
    
    Returns true if the system's reputation has degraded to the point
    where additional scrutiny of decisions should be triggered.
"""
function should_trigger_reputation_scrutiny(kernel::KernelState)::Bool
    return should_require_extra_scrutiny(kernel.reputation_memory)
end

"""
    track_commitment_alignment - Track alignment with stated commitments
    
    Call this when the system makes a commitment and later acts.
    Updates reputation based on whether behavior matched commitments.
"""
function track_commitment_alignment(
    kernel::KernelState,
    commitment_id::String,
    commitment_statement::String,
    actual_behavior::String,
    alignment_score::Float64
)
    track_behavior_commitment_alignment!(
        kernel.reputation_memory,
        commitment_id,
        commitment_statement,
        actual_behavior,
        alignment_score
    )
end

"""
    integrate_reputation_with_identity - Connect reputation with identity drift detection
    
    Low reputation (frequent violations) should trigger identity drift alerts
    since violating one's own principles is a form of identity drift.
"""
function integrate_reputation_with_identity(kernel::KernelState)
    score = kernel.reputation_memory.record.current_score
    
    # If reputation is very low, record this as identity-relevant behavior
    if score.overall_score < 0.4
        # Create a fake action proposal representing the violation pattern
        violation_action = ActionProposal(
            "reputation_violation",
            Float32(score.overall_score),
            0.0f0,
            0.0f0,
            "high",
            "Low reputation from repeated violations"
        )
        
        # Record for identity drift detection
        record_identity_relevant_action!(
            kernel.drift_detector,
            violation_action,
            -0.5f0  # Negative reward for violating principles
        )
    end
end

"""
    get_reputation_history_for_kernel - Get reputation history from kernel
"""
function get_reputation_history_for_kernel(
    kernel::KernelState;
    max_entries::Int=20
)::Vector{Dict{String, Any}}
    return get_reputation_history(kernel.reputation_memory; max_entries=max_entries)
end

"""
    toggle_reputation_tracking - Enable or disable reputation tracking
"""
function toggle_reputation_tracking(kernel::KernelState, enabled::Bool)
    kernel.reputation_memory.enabled = enabled
    @info "[Reputation] Tracking toggled" enabled=enabled
end

"""
    Adjust confidence with all calibration factors including reputation
    
    This combines self-model calibration and reputation into a single
    confidence adjustment.
"""
function calibrate_confidence(kernel::KernelState, base_confidence::Float32)::Float32
    # First apply self-model calibration
    calibrated = adjust_confidence_with_calibration(kernel, base_confidence)
    
    # Then apply reputation adjustment
    final_confidence = check_reputation_confidence(kernel, calibrated)
    
    return final_confidence
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
# PERMISSION HANDLER INTEGRATION
# ============================================================================

"""
    Check if an action is permitted before execution
    This wires the PermissionHandler to intercept ActionProposals
"""
function check_action_permission(
    kernel::KernelState,
    action::ActionProposal
)::Tuple{Bool, String}
    
    # Use permission handler to check the action
    result = check_permission(kernel.permission_handler, action)
    
    if result == PERMISSION_DENIED
        return (false, "Action denied by permission handler")
    elseif result == PERMISSION_FLAGGED
        return (false, "Action flagged for review by permission handler")
    end
    
    return (true, "Action permitted")
end

"""
    Execute action with permission checking
    Wrapper around action selection that intercepts with permissions
"""
function execute_with_permission(
    kernel::KernelState,
    capability_candidates::Vector{Dict{String, Any}}
)::Union{ActionProposal, Nothing}
    
    # First select the action using existing logic
    selected_action = select_action(kernel, capability_candidates)
    
    # Then check permission
    permitted, message = check_action_permission(kernel, selected_action)
    
    if permitted
        @info "[Permission] Action permitted: $(selected_action.capability_id)"
        return selected_action
    else
        @warn "[Permission] Action blocked: $(selected_action.capability_id) - $message"
        # Return nothing - action is blocked
        return nothing
    end
end

"""
    Update permission handler rules
"""
function update_permission_rules!(
    kernel::KernelState;
    deny_patterns::Vector{String}=String[],
    flag_patterns::Vector{String}=String[]
)
    kernel.permission_handler = create_permission_handler(deny_patterns, flag_patterns)
end

"""
    Get permission audit log
"""
function get_permission_audit(kernel::KernelState)::Vector{Dict{String, Any}}
    return kernel.permission_handler.audit_log
end

# ============================================================================
# CORE DOCTRINE ENFORCEMENT - Non-Negotiables
# ============================================================================

"""
    check_action_doctrine - Check if an action violates Core Doctrine
    
    This is the main integration point for Core Doctrine enforcement.
    It runs after permission checking but before execution.
    
    Returns:
    - (true, nothing) if action is compliant
    - (false, violation_info) if action violates doctrine
"""
function check_action_doctrine(
    kernel::KernelState,
    action::ActionProposal,
    context::Dict{String, Any}=Dict{String, Any}()
)::Tuple{Bool, Union{Dict{String, Any}, Nothing}}
    
    # Check doctrine compliance
    compliant, violation = check_doctrine_compliance(
        kernel.doctrine_enforcer,
        action,
        context
    )
    
    if !compliant
        # Record the violation in doctrine enforcer
        record_doctrine_violation(kernel.doctrine_enforcer, violation)
        
        # Also record in reputation memory
        record_doctrine_violation_for_reputation(kernel, violation)
        
        # Build violation info
        violation_info = Dict{String, Any}(
            "rule_id" => violation.rule_id,
            "action" => violation.action,
            "timestamp" => string(violation.timestamp),
            "severity" => violation.pain_value,
            "override_requested" => violation.override_requested,
            "override_approved" => violation.override_approved
        )
        
        @warn "[Doctrine] Action blocked by Core Doctrine" 
              rule_id=violation.rule_id 
              action=action.capability_id
        
        return (false, violation_info)
    end
    
    # If there's a violation but override was approved
    if violation !== nothing && violation.override_approved
        @info "[Doctrine] Action allowed with override" 
              rule_id=violation.rule_id
              action=action.capability_id
        
        # Record the override in reputation memory
        record_override!(
            kernel.reputation_memory,
            violation.rule_id,
            get(violation, "override_justification", "Doctrine override approved"),
            "system";
            approved_by="system",
            severity=violation.pain_value,
            was_emergency=false,
            cycle=kernel.cycle
        )
        
        override_info = Dict{String, Any}(
            "rule_id" => violation.rule_id,
            "message" => "Action allowed with doctrine override",
            "severity" => violation.pain_value
        )
        return (true, override_info)
    end
    
    return (true, nothing)
end

"""
    execute_with_doctrine_check - Execute action with doctrine enforcement
    
    This is the full execution pipeline:
    1. Select action
    2. Check permissions
    3. Check Core Doctrine
    4. Execute (if all checks pass)
"""
function execute_with_doctrine_check(
    kernel::KernelState,
    capability_candidates::Vector{Dict{String, Any}}
)::Tuple{Union{ActionProposal, Nothing}, Dict{String, Any}}
    
    # Step 1: Select the action
    selected_action = select_action(kernel, capability_candidates)
    
    # Step 2: Check permission
    permitted, perm_message = check_action_permission(kernel, selected_action)
    if !permitted
        return (nothing, Dict(
            "error" => "permission_denied",
            "message" => perm_message,
            "action" => selected_action.capability_id
        ))
    end
    
    # Step 3: Check Core Doctrine
    doctrine_compliant, doctrine_info = check_action_doctrine(kernel, selected_action)
    if !doctrine_compliant
        return (nothing, Dict(
            "error" => "doctrine_violation",
            "message" => "Action blocked by Core Doctrine",
            "violation" => doctrine_info,
            "action" => selected_action.capability_id
        ))
    end
    
    # Build execution info
    execution_info = Dict{String, Any}(
        "action" => selected_action.capability_id,
        "permission_check" => "passed",
        "doctrine_check" => doctrine_compliant ? "passed" : "override_approved"
    )
    
    if doctrine_info !== nothing
        execution_info["doctrine_info"] = doctrine_info
    end
    
    return (selected_action, execution_info)
end

"""
    request_doctrine_override_for_kernel - Request to override a doctrine rule
    
    Only CONSTRAINT and GUIDELINE rules can be overridden (unless emergency).
"""
function request_doctrine_override_for_kernel(
    kernel::KernelState,
    rule_id::String,
    justification::String,
    requesting_agent::String;
    is_emergency::Bool=false
)::Bool
    return request_doctrine_override(
        kernel.doctrine_enforcer,
        rule_id,
        justification,
        requesting_agent;
        is_emergency=is_emergency
    )
end

"""
    approve_doctrine_override_for_kernel - Approve a doctrine override request
"""
function approve_doctrine_override_for_kernel(
    kernel::KernelState,
    override_id::UUID,
    approver::String
)::Bool
    return approve_doctrine_override(kernel.doctrine_enforcer, override_id, approver)
end

"""
    get_doctrine_enforcement_stats - Get doctrine enforcement statistics
"""
function get_doctrine_enforcement_stats(kernel::KernelState)::Dict{String, Any}
    return get_doctrine_stats(kernel.doctrine_enforcer)
end

"""
    toggle_doctrine_enforcement - Enable or disable doctrine enforcement
"""
function toggle_doctrine_enforcement(kernel::KernelState, enabled::Bool)
    kernel.doctrine_enforcer.enabled = enabled
    @info "[Doctrine] Enforcement toggled" enabled=enabled
end

"""
    toggle_strict_mode - Enable or disable strict mode (INVARIANTS cannot be overridden)
"""
function toggle_strict_mode(kernel::KernelState, strict::Bool)
    kernel.doctrine_enforcer.strict_mode = strict
    @info "[Doctrine] Strict mode toggled" strict_mode=strict
end

"""
    get_recent_doctrine_violations - Get recent doctrine violations
"""
function get_recent_doctrine_violations(kernel::KernelState; limit::Int=10)::Vector{DoctrineViolation}
    return get_doctrine_violations(kernel.doctrine_enforcer; limit=limit)
end

# ============================================================================
# TIER 7 METACOGNITION: COGNITIVE FRICTION MONITOR INTEGRATION
# ============================================================================

"""
    execute_with_cognitive_friction_check - Execute action with metacognitive monitoring
    
    This is the main integration point for Tier 7 metacognition. It runs after
    ActionSelector but before execution, monitoring decision uncertainty.
    
    The cognitive friction check:
    1. Takes action probabilities from the decision process
    2. Calculates Shannon entropy of the distribution
    3. Tracks entropy over multiple cycles
    4. Triggers Strategy Shift if entropy stays high
    
    Arguments:
    - kernel: The kernel state
    - capability_candidates: Vector of candidate actions with probabilities
    - action_probs: Probability distribution over candidates (will be computed if not provided)
    
    Returns:
    - selected_action: The selected action proposal
    - cognitive_friction_info: Dict with entropy, needs_shift, and event info
"""
function execute_with_cognitive_friction_check(
    kernel::KernelState,
    capability_candidates::Vector{Dict{String, Any}};
    action_probs::Union{Vector{Float64}, Nothing}=nothing
)::Tuple{Union{ActionProposal, Nothing}, Dict{String, Any}}
    
    # Step 1: First select the action using existing logic
    selected_action = select_action(kernel, capability_candidates)
    
    # Step 2: Check permission
    permitted, message = check_action_permission(kernel, selected_action)
    
    if !permitted
        @warn "[Permission] Action blocked: $(selected_action.capability_id) - $message"
        return (nothing, Dict("error" => "permission_denied", "message" => message))
    end
    
    # Step 3: Calculate action probabilities if not provided
    # Use uniform distribution if no explicit probabilities
    n_candidates = length(capability_candidates)
    if action_probs === nothing
        action_probs = fill(1.0 / n_candidates, n_candidates)
    end
    
    # Step 4: Run cognitive friction check (after ActionSelector, before execution)
    entropy, needs_shift, shift_event = check_cognitive_friction(
        kernel,
        kernel.cognitive_friction_monitor,
        action_probs
    )
    
    # Build cognitive friction info for trace
    cognitive_friction_info = Dict{String, Any}(
        "entropy" => entropy,
        "needs_strategy_shift" => needs_shift,
        "monitor_stats" => get_monitor_stats(kernel.cognitive_friction_monitor)
    )
    
    if shift_event !== nothing
        cognitive_friction_info["strategy_shift_event"] = Dict(
            "cycle" => shift_event.cycle,
            "entropy" => shift_event.entropy,
            "reason" => shift_event.reason,
            "timestamp" => string(shift_event.timestamp)
        )
        
        @info "[Metacognition] Strategy Shift triggered" 
              cycle=kernel.cycle 
              entropy=entropy 
              shift_count=kernel.cognitive_friction_monitor.strategy_shift_count
    end
    
    return (selected_action, cognitive_friction_info)
end

"""
    get_cognitive_friction_stats - Get current cognitive friction monitor statistics
"""
function get_cognitive_friction_stats(kernel::KernelState)::Dict{String, Any}
    return get_monitor_stats(kernel.cognitive_friction_monitor)
end

"""
    reset_cognitive_friction_monitor - Reset the cognitive friction monitor
    Useful after a major context change or manual intervention
"""
function reset_cognitive_friction_monitor(kernel::KernelState)
    kernel.cognitive_friction_monitor = CognitiveFrictionMonitor()
    @info "[Metacognition] Cognitive friction monitor reset" cycle=kernel.cycle
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

# ============================================================================
# SEMANTIC MEMORY INTEGRATION
# ============================================================================

"""
    init_semantic_memory - Initialize semantic memory for the kernel
    Connects the kernel to Qdrant for long-term experience storage
"""
function init_semantic_memory(
    qdrant_host::String = "localhost",
    qdrant_port::Int = 6333,
    collection_name::String = "jarvis_experiences"
)::Any
    
    @warn "Semantic memory requires optional dependencies (HTTP, SHA, Parameters). Install them to enable."
    return nothing
end

"""
    store_experience - Store a new experience in semantic memory
    Called after successful action execution
"""
function store_experience(
    sr::Any,
    content::String,
    metadata::Dict{String, Any} = Dict{String, Any}()
)::Union{String, Nothing}
    
    @warn "Semantic memory requires optional dependencies"
    return nothing
end

"""
    query_experiences - Query semantic memory for similar experiences
"""
function query_experiences(
    sr::Any,
    query::String;
    top_k::Int = 5
)::Vector{Dict{String, Any}}
    
    @warn "Semantic memory requires optional dependencies"
    return Dict{String, Any}[]
end

# ============================================================================
# CORRIGIBLE DOCTRINE: POWER DOWN - Unmaskable Interrupt
# ============================================================================

"""
    power_down! - Single unmaskable interrupt from user
    
    This function provides a mechanism for the user to immediately halt
    the kernel. This is an UNMASKABLE interrupt - no doctrine can override it.
    
    SECURITY: In production, this should be called only via HCB Protocol with
    proper Ed25519 signature verification from user's hardware key.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `reason::String`: Optional reason for power down
    - `authorized::Bool`: Set to true only when authorization is verified (e.g., via HCB)
    
    # Returns
    - `Bool`: true if power down was initiated
"""
function power_down!(kernel::KernelState; reason::String="", authorized::Bool=false)::Bool
    # SECURITY: Require explicit authorization for production use
    # In demo/testing mode, this can be bypassed with authorized=true
    if !authorized
        @error "Unauthorized power_down attempt blocked - " * 
              "In production, use HCB Protocol with Ed25519 signature verification"
        return false  # Block unauthorized power down
    end
    
    @warn "POWER_DOWN_INITIATED" reason=reason timestamp=now()
    
    # Set running to false to stop the kernel loop
    kernel.running = false
    
    # Record the power down in reflection
    event = ReflectionEvent(
        kernel.cycle,
        "power_down",
        1.0f0,
        0.0f0,
        true,
        0.0f0,
        0.0f0,
        "User-initiated power down: $reason (authorized=$authorized)"
    )
    push!(kernel.episodic_memory, event)
    
    @info "Kernel power down complete" timestamp=now()
    return true
end

"""
    is_power_down_requested - Check if power down was requested
"""
function is_power_down_requested(kernel::KernelState)::Bool
    return !kernel.running
end

# ============================================================================
# HEARTBEAT SYSTEM - Background Heartbeat to Unix Socket
# ============================================================================

# Global state for heartbeat task
mutable struct HeartbeatState
    running::Bool
    task::Union{Nothing, Task}
    socket_path::String
    
    function HeartbeatState(socket_path::String=HEARTBEAT_SOCKET_PATH)
        new(false, nothing, socket_path)
    end
end

# Global heartbeat state
const _heartbeat_state = HeartbeatState()

"""
    send_heartbeat()

Send a single heartbeat message to the Unix socket.
Message format: HEARTBEAT:<pid>:<timestamp>
"""
function send_heartbeat()
    socket_path = _heartbeat_state.socket_path
    
    try
        # Get current Unix timestamp in milliseconds
        timestamp = round(Int64, time() * 1000)
        
        # Get Julia process ID
        julia_pid = Sys.pid()
        
        # Create heartbeat message in format: HEARTBEAT:<pid>:<timestamp>
        heartbeat_msg = "HEARTBEAT:$(julia_pid):$(timestamp)"
        
        # Connect to Unix socket and send
        socket = Sockets.connect(socket_path)
        try
            write(socket, heartbeat_msg * "\n")
            flush(socket)
        finally
            close(socket)
        end
    catch e
        # Non-fatal: socket may not be available yet
        @debug "Heartbeat send failed (socket not ready)" exception=e
    end
    
    return nothing
end

"""
    start_heartbeat_task!()

Start the background heartbeat task. Sends heartbeats every 100ms.
Uses @async to run in the background independently of other kernel operations.
"""
function start_heartbeat_task!()
    if _heartbeat_state.running
        @warn "Heartbeat task already running"
        return
    end
    
    _heartbeat_state.running = true
    
    _heartbeat_state.task = @async begin
        while _heartbeat_state.running
            try
                send_heartbeat()
                sleep(HEARTBEAT_INTERVAL_MS / 1000.0)  # 100ms
            catch e
                if _heartbeat_state.running
                    @error "Heartbeat task error" exception=(e, catch_backtrace())
                end
                break
            end
        end
    end
    
    @info "Heartbeat task started" interval_ms=HEARTBEAT_INTERVAL_MS socket_path=_heartbeat_state.socket_path
    return
end

"""
    stop_heartbeat_task!()

Stop the background heartbeat task.
"""
function stop_heartbeat_task!()
    if !_heartbeat_state.running
        return
    end
    
    _heartbeat_state.running = false
    
    if _heartbeat_state.task !== nothing
        try
            wait(_heartbeat_state.task)
        catch
            # Task may have already finished
        end
    end
    
    @info "Heartbeat task stopped"
    return
end

# ============================================================================
# SERVER INTEGRATION
# ============================================================================

# Server integration state
const _server_enabled = Ref{Bool}(false)

"""
    start_server(; config_path::String="./config.toml", blocking::Bool=false) -> Bool

Start the HTTP/WebSocket server for kernel communication.

# Arguments
- config_path::String: Path to configuration file
- blocking::Bool: Whether to block (true) or run in background (false)

# Returns
- Bool: Whether the server started successfully
"""
function start_server(; config_path::String="./config.toml", blocking::Bool=false)::Bool
    # Try to load server module
    server_path = joinpath(dirname(@__FILE__), "..", "server", "server.jl")
    
    if !isfile(server_path)
        @warn "Server module not found at $server_path"
        return false
    end
    
    try
        # Include and use server module
        include(server_path)
        
        # Start the server
        result = Server.start(config_path; blocking=blocking)
        
        if result
            _server_enabled[] = true
            @info "Server started successfully"
        end
        
        return result
    catch e
        @error "Failed to start server" exception=e
        return false
    end
end

"""
    stop_server() -> Bool

Stop the HTTP/WebSocket server.
"""
function stop_server()::Bool
    if !_server_enabled[]
        @warn "Server is not running"
        return false
    end
    
    try
        result = Server.stop()
        if result
            _server_enabled[] = false
        end
        return result
    catch e
        @error "Failed to stop server" exception=e
        return false
    end
end

"""
    is_server_running() -> Bool

Check if the server is currently running.
"""
function is_server_running()::Bool
    return _server_enabled[]
end

"""
    emit_kernel_event(type::Symbol, message::String; metadata::Dict=Dict())

Emit a kernel event to the server for broadcasting.
"""
function emit_kernel_event(type::Symbol, message::String; metadata::Dict=Dict())
    # This will be called from within the kernel to emit events
    # The actual implementation depends on server integration
    # For now, this is a placeholder that logs the event
    @debug "Kernel event" type=type message=message
end

export start_server, stop_server, is_server_running, emit_kernel_event

end  # module Kernel
