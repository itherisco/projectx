# types.jl - Shared type definitions for Adaptive Kernel and ITHERIS
# This file consolidates common structs used across the system

module SharedTypes

using Dates
using JSON
using UUIDs

export ActionProposal, Goal, GoalState, Thought, ReflectionEvent, IntentVector, ThoughtCycle, ThoughtCycleType,
       add_intent!, update_alignment!, get_alignment_penalty, update_goal_progress!,
       # Emotional context exports
       EmotionalContext, EmotionalContextFromMFCC, get_emotional_adjustment,
       # Dual-Process: System 1 exports
       System1Message, System1Priority, PermissionHandler, PermissionResult,
       check_permission, create_permission_handler, is_registered_capability, detect_injection,
       # Spatial memory bridge
       Rect,
       # Core Doctrine exports
       DoctrineRule, DoctrineRuleType, DoctrineEnforcer, DoctrineViolation, DoctrineOverride,
       create_core_doctrine, check_doctrine_compliance, record_doctrine_violation, can_override_doctrine,
       # Self-Model exports
       SelfModel, CapabilityProfile, LimitProfile, RiskProfile, ConfidenceCalibration,
       SelfModelUpdate, create_self_model, update_self_model!, get_capability_rating,
       check_risk_tolerance, should_adjust_confidence,
       # Identity Drift Detection exports
       IdentityBaseline, IdentityAnchor, BehavioralPattern, DriftDetector, DriftAlert, DriftSeverity,
       create_identity_baseline, create_drift_detector, check_behavioral_drift, get_drift_alerts,
       get_drift_severity, integrate_identity_with_self_model,
       # Reputation Memory exports
       ReputationRecord, ViolationEntry, OverrideRecord, ReputationScore, ReputationMemory,
       create_reputation_memory, record_violation!, record_override!, compute_reputation_score,
       get_reputation_status, apply_reputation_to_confidence, track_behavior_commitment_alignment,
       get_reputation_history, should_require_extra_scrutiny,
       # Kernel state exports (for Metacognition)
       WorldState, KernelState

# ============================================================================
# Action Proposal - Kernel version (for deterministic kernel)
# ============================================================================

"""
    ActionProposal represents a selected action with metadata for decision making.
"""
struct ActionProposal
    capability_id::String
    confidence::Float32
    predicted_cost::Float32
    predicted_reward::Float32
    risk::String
    reasoning::String
end

# ============================================================================
# Goal - Represents an objective for the kernel (IMMUTABLE - Phase 3)
# ============================================================================

"""
    Goal - Immutable struct representing an objective
    Priority and metadata cannot change after creation (structural integrity)
"""
struct Goal
    id::String
    description::String
    priority::Float32  # [0, 1] - IMMUTABLE after creation
    created_at::DateTime
    deadline::DateTime
end

# Constructor for convenience
function Goal(id::String, desc::String, priority::Float32, created::DateTime)
    return Goal(id, desc, priority, created, created + Dates.Hour(1))
end

# ============================================================================
# GoalState - Mutable progress tracking for Goals
# ============================================================================

"""
    GoalState - Mutable progress tracking for Goals
    Separates immutable Goal definition from mutable runtime state
"""
mutable struct GoalState
    goal_id::String
    status::Symbol  # :active, :completed, :failed, :paused
    progress::Float32  # [0, 1] completion percentage
    last_updated::DateTime
    iterations::Int
    
    GoalState(goal_id::String) = new(
        goal_id,
        :active,
        0.0f0,
        now(),
        0
    )
end

function update_goal_progress!(state::GoalState, progress::Float32)
    state.progress = clamp(progress, 0.0f0, 1.0f0)
    state.last_updated = now()
    state.iterations += 1
    
    if state.progress >= 1.0f0
        state.status = :completed
    end
end

function pause_goal!(state::GoalState)
    state.status = :paused
    state.last_updated = now()
end

function fail_goal!(state::GoalState)
    state.status = :failed
    state.last_updated = now()
end

function resume_goal!(state::GoalState)
    state.status = :active
    state.last_updated = now()
end

# ============================================================================
# Emotional Context - User affective state
# ============================================================================

"""
    EmotionalContext - Represents the emotional state of the user
    Used for affective computing to adapt JARVIS's responses
"""
struct EmotionalContext
    sentiment::Float32        # -1 (frustrated) to 1 (happy)
    arousal::Float32          # 0 (calm) to 1 (excited)
    dominance::Float32        # 0 (submissive) to 1 (dominant)
    source::Symbol           # :voice_mfcc, :text, :default
    timestamp::DateTime
end

"""
    Create a default neutral emotional context
"""
function EmotionalContext()::EmotionalContext
    return EmotionalContext(0.0f0, 0.0f0, 0.5f0, :default, now())
end

"""
    Create emotional context from voice MFCC features
"""
function EmotionalContextFromMFCC(mfcc_features::Vector{Float32})::EmotionalContext
    sentiment = length(mfcc_features) >= 1 ? clamp(mfcc_features[1], -1.0f0, 1.0f0) : 0.0f0
    arousal = length(mfcc_features) >= 2 ? clamp(mfcc_features[2], 0.0f0, 1.0f0) : 0.0f0
    dominance = length(mfcc_features) >= 3 ? clamp(mfcc_features[3], 0.0f0, 1.0f0) : 0.5f0
    return EmotionalContext(sentiment, arousal, dominance, :voice_mfcc, now())
end

"""
    Get emotional adjustment factor for response generation
"""
function get_emotional_adjustment(ec::EmotionalContext)::Dict{Symbol, Float32}
    verbosity = ec.sentiment < -0.3 ? 0.5f0 : (ec.sentiment > 0.3 ? 1.2f0 : 1.0f0)
    speed = clamp(0.8f0 + ec.arousal * 0.4f0, 0.5f0, 1.5f0)
    suggestions = ec.dominance < 0.3 ? 1.5f0 : (ec.dominance > 0.7 ? 0.5f0 : 1.0f0)
    return Dict(:verbosity => verbosity, :speed => speed, :suggestions => suggestions)
end

# ============================================================================
# Thought - Represents ITHERIS cognitive output
# ============================================================================

"""
    Thought - Represents ITHERIS cognitive output
"""
struct Thought
    action::Int
    probs::Vector{Float32}
    value::Float32
    uncertainty::Float32
    context_vector::Vector{Float32}
    emotional_context::Union{EmotionalContext, Nothing}
end

# ============================================================================
# ITHERIS Action Proposal
# ============================================================================

mutable struct ITHERISActionProposal
    id::UUID
    action_idx::Int
    confidence::Float32
    reasoning::String
    impact_estimate::Float32
    timestamp::DateTime
end

# ============================================================================
# ReflectionEvent - Concrete typed event for kernel reflection
# ============================================================================

struct ReflectionEvent
    id::UUID
    cycle::Int
    action_id::String
    action_confidence::Float32
    action_cost::Float32
    success::Bool
    reward::Float32
    prediction_error::Float32
    effect::String
    timestamp::DateTime
    confidence_delta::Float32
    energy_delta::Float32
end

function ReflectionEvent(
    cycle::Int, action_id::String, action_confidence::Float32, action_cost::Float32,
    success::Bool, reward::Float32, prediction_error::Float32, effect::String;
    confidence_delta::Float32 = 0.0f0, energy_delta::Float32 = 0.0f0
)::ReflectionEvent
    return ReflectionEvent(uuid4(), cycle, action_id, action_confidence, action_cost,
        success, reward, prediction_error, effect, now(), confidence_delta, energy_delta)
end

# ============================================================================
# IntentVector - Strategic inertia across decision cycles
# ============================================================================

struct IntentVector
    id::UUID
    intents::Vector{String}
    intent_strengths::Vector{Float64}
    last_aligned_action::DateTime
    thrash_count::Int
    alignment_history::Vector{DateTime}
    
    IntentVector() = new(uuid4(), String[], Float64[], now(), 0, DateTime[])
end

function add_intent!(iv::IntentVector, intent::String, strength::Float64 = 0.5)
    push!(iv.intents, intent)
    push!(iv.intent_strengths, strength)
    push!(iv.alignment_history, now())
end

function update_alignment!(iv::IntentVector, aligned::Bool)
    iv.last_aligned_action = now()
    aligned || (iv.thrash_count += 1)
end

function get_alignment_penalty(iv::IntentVector)::Float64
    return min(0.5, 0.05 * iv.thrash_count)
end

# ============================================================================
# Spatial Memory Bridge - Rect for window bounds
# ============================================================================

"""
    Rect - Simple rectangle for window bounds
"""
struct Rect
    x::Int
    y::Int
    width::Int
    height::Int
end

# ============================================================================
# Dual-Process: System 1 to System 2 Communication
# ============================================================================

@enum System1Priority begin
    PRIORITY_ROUTINE
    PRIORITY_URGENT
    PRIORITY_WAKEUP
end

"""
    System1Message - Message from System 1 (Rust) to System 2 (Julia)
"""
struct System1Message
    priority::System1Priority
    payload::String
    timestamp::DateTime
    correlation_id::Union{String, Nothing}
    classify_latency_ms::UInt64
    emotional_context::Union{EmotionalContext, Nothing}
    spatial_map::Union{Dict{Symbol, Rect}, Nothing}
end

function System1Message(payload::String; priority::System1Priority = PRIORITY_WAKEUP, 
    correlation_id::Union{String, Nothing} = nothing,
    classify_latency_ms::UInt64 = 0,
    emotional_context::Union{EmotionalContext, Nothing} = nothing,
    spatial_map::Union{Dict{Symbol, Rect}, Nothing} = nothing)::System1Message
    return System1Message(priority, payload, now(), correlation_id, 
        classify_latency_ms, emotional_context, spatial_map)
end

# ============================================================================
# PERMISSION HANDLER - Intercepts ActionProposals (SECURE VERSION)
# ============================================================================

@enum PermissionResult begin
    PERMISSION_GRANTED
    PERMISSION_DENIED
    PERMISSION_FLAGGED
end

"""
    PermissionHandler - Intercepts and validates ActionProposals
    before they are executed
"""
mutable struct PermissionHandler
    enabled::Bool
    deny_patterns::Vector{String}
    flag_patterns::Vector{String}
    audit_log::Vector{Dict{String, Any}}
    
    PermissionHandler() = new(
        true,
        ["rm -rf", "drop_database", "delete_all", "sudo"],
        ["system_config", "system_permission", "modify_config", "elevate_permission"],
        Dict{String, Any}[]
    )
end

function create_permission_handler(
    deny_patterns::Vector{String}=String[],
    flag_patterns::Vector{String}=String[]
)::PermissionHandler
    handler = PermissionHandler()
    isempty(deny_patterns) || (handler.deny_patterns = deny_patterns)
    isempty(flag_patterns) || (handler.flag_patterns = flag_patterns)
    return handler
end

# ============================================================================
# SECURITY HARDENING - Capability Registry & Injection Detection
# ============================================================================

"""
    Load registered capabilities from the capability_registry.json file.
    Falls back to hardcoded defaults if the file cannot be loaded.
"""
function _load_capabilities_from_registry()::Set{String}
    # Default capabilities as fallback
    default_caps = Set([
        "observe_cpu", "analyze_logs", "write_file", "safe_shell", "safe_http_request",
        "observe_network", "observe_filesystem", "observe_processes", "compare_strategies",
        "estimate_risk", "file_diff", "git_readonly", "simulate_outcomes",
        "summarize_state", "task_scheduler",
        "Finance_Data_Fetch",
        "Github_Read", "Github_Draft_PR"
    ])
    
    try
        # Try to load from registry JSON
        registry_path = joinpath(@__DIR__, "registry", "capability_registry.json")
        if isfile(registry_path)
            registry_json = JSON.parsefile(registry_path)
            cap_ids = Set{String}()
            for entry in registry_json
                if haskey(entry, "id")
                    push!(cap_ids, entry["id"])
                end
            end
            if !isempty(cap_ids)
                @info "Loaded $(length(cap_ids)) capabilities from registry"
                return cap_ids
            end
        end
    catch e
        @warn "Failed to load capability registry: $e. Using defaults."
    end
    
    return default_caps
end

"""
    Valid capability IDs from the registry
    Loaded from capability_registry.json at module initialization
"""
const REGISTERED_CAPABILITIES::Set{String} = _load_capabilities_from_registry()

"""
    Check if a capability_id is registered in the capability registry
    Returns true if the capability exists, false otherwise
"""
function is_registered_capability(capability_id::String)::Bool
    return capability_id in REGISTERED_CAPABILITIES
end

"""
    Detect potential injection attacks in capability_id
    Checks for shell metacharacters that could be used for command injection
    Returns true if injection detected, false if clean
"""
function detect_injection(capability_id::String)::Bool
    # Check for shell metacharacters: ; | & $ ` ( ) { } [ ] < > " ' \ newline carriage-return
    injection_chars = [';', '&', '|', '$', '`', '(', ')', '{', '}', '[', ']', '<', '>']
    for char in injection_chars
        occursin(char, capability_id) && return true
    end
    # Check for quotes and backslash
    occursin('"', capability_id) && return true
    occursin('\'', capability_id) && return true
    occursin('\\', capability_id) && return true
    return false
end

"""
    Check if an ActionProposal is permitted - SECURE VERSION
    Flow:
    1. Validate capability_id against registry
    2. Check for injection attacks
    3. Check reasoning field (existing logic)
"""
function check_permission(
    handler::PermissionHandler,
    action::ActionProposal
)::PermissionResult
    handler.enabled || return PERMISSION_GRANTED
    
    capability_id = action.capability_id
    
    # STEP 1: Validate against registry FIRST
    if !is_registered_capability(capability_id)
        push!(handler.audit_log, Dict(
            "action" => capability_id,
            "result" => "denied",
            "reason" => "Unknown capability",
            "timestamp" => now()
        ))
        return PERMISSION_DENIED
    end
    
    # STEP 2: Check for injection attacks
    if detect_injection(capability_id)
        push!(handler.audit_log, Dict(
            "action" => capability_id,
            "result" => "denied",
            "reason" => "Injection detected in capability_id",
            "timestamp" => now()
        ))
        @warn "Injection detected in capability_id: $capability_id"
        return PERMISSION_DENIED
    end
    
    # STEP 3: Check reasoning field (existing logic)
    reasoning_lower = lowercase(action.reasoning)
    
    for pattern in handler.deny_patterns
        if occursin(pattern, reasoning_lower)
            push!(handler.audit_log, Dict(
                "action" => capability_id,
                "result" => "denied",
                "pattern" => pattern,
                "timestamp" => now()
            ))
            return PERMISSION_DENIED
        end
    end
    
    for pattern in handler.flag_patterns
        if occursin(pattern, reasoning_lower)
            push!(handler.audit_log, Dict(
                "action" => capability_id,
                "result" => "flagged",
                "pattern" => pattern,
                "timestamp" => now()
            ))
            return PERMISSION_FLAGGED
        end
    end
    
    push!(handler.audit_log, Dict(
        "action" => capability_id,
        "result" => "granted",
        "timestamp" => now()
    ))
    
    return PERMISSION_GRANTED
end

function get_audit_log_size(handler::PermissionHandler)::Int
    return length(handler.audit_log)
end

function clear_audit_log!(handler::PermissionHandler)
    empty!(handler.audit_log)
end

# ============================================================================
# PHASE 3: NON-EXECUTING THOUGHT CYCLES
# ============================================================================

@enum ThoughtCycleType begin
    THOUGHT_DOCTRINE_REFINEMENT
    THOUGHT_SIMULATION
    THOUGHT_PRECOMPUTATION
    THOUGHT_ANALYSIS
end

"""
    ThoughtCycle - Non-executing internal cognition cycle
    Used for doctrine refinement, simulation, precomputation
"""
struct ThoughtCycle
    id::UUID
    cycle_type::ThoughtCycleType
    input_context::Dict{String, Any}
    output_insights::Vector{String}
    started_at::DateTime
    completed_at::Union{DateTime, Nothing}
    executed::Bool
    
    ThoughtCycle(cycle_type::ThoughtCycleType) = new(
        uuid4(), cycle_type, Dict{String, Any}(), String[], now(), nothing, false
    )
end

function complete_thought!(tc::ThoughtCycle, insights::Vector{String})
    tc.output_insights = insights
    tc.completed_at = now()
end

# ============================================================================
# PHASE 3: DREAMING LOOP - Sleep-Based Memory Consolidation
# ============================================================================

"""
    DreamingConfig - Configuration for the dreaming loop
"""
struct DreamingConfig
    enabled::Bool
    min_interval_seconds::Float64
    max_dream_cycles::Int
    memory_strength_decay::Float64
    
    DreamingConfig() = new(true, 300.0, 10, 0.05)
end

# ============================================================================
# CORE DOCTRINE - IMMUTABLE PRINCIPLES (Non-Negotiables)
# ============================================================================

@enum DoctrineRuleType begin
    DOCTRINE_INVARIANT      # Absolute rule - cannot be overridden
    DOCTRINE_CONSTRAINT     # Strong constraint - override with justification
    DOCTRINE_GUIDELINE      # Guidance - can be overridden
end

"""
    DoctrineRule - Immutable principle enforced by the Kernel
    
    Core Doctrine represents non-negotiable rules that cannot be overridden 
    by normal cognitive processes. Violations require extraordinary justification.
    
    Fields:
    - rule_id: Unique identifier for the rule
    - name: Human-readable name
    - description: Detailed description of the rule
    - rule_type: Type of rule (INVARIANT, CONSTRAINT, GUIDELINE)
    - predicate: Function that checks if an action violates this rule
    - severity: Pain value if violated (0-1)
    - created_at: When the rule was created
"""
struct DoctrineRule
    rule_id::String
    name::String
    description::String
    rule_type::DoctrineRuleType
    violation_patterns::Vector{String}  # Patterns that trigger violation
    severity::Float64  # [0, 1] - pain value if violated
    created_at::DateTime
    
    function DoctrineRule(
        rule_id::String,
        name::String,
        description::String,
        rule_type::DoctrineRuleType;
        violation_patterns::Vector{String}=String[],
        severity::Float64=1.0
    )
        return new(
            rule_id, name, description, rule_type,
            violation_patterns, severity, now()
        )
    end
end

"""
    DoctrineViolation - Record of a doctrine rule violation attempt
"""
struct DoctrineViolation
    id::UUID
    rule_id::String
    action::String
    context::Dict{String, Any}
    timestamp::DateTime
    override_requested::Bool
    override_justification::Union{String, Nothing}
    override_approved::Bool
    pain_value::Float64
end

function DoctrineViolation(
    rule::DoctrineRule,
    action::String,
    context::Dict{String, Any}
)::DoctrineViolation
    return DoctrineViolation(
        uuid4(),
        rule.rule_id,
        action,
        context,
        now(),
        false,
        nothing,
        false,
        rule.severity
    )
end

"""
    DoctrineOverride - Extraordinary justification for overriding doctrine
"""
struct DoctrineOverride
    override_id::UUID
    rule_id::String
    justification::String
    requesting_agent::String
    approved_by::Union{String, Nothing}  # Nothing = auto-approved in emergency
    timestamp::DateTime
    is_emergency::Bool
end

function DoctrineOverride(
    rule_id::String,
    justification::String,
    requesting_agent::String;
    is_emergency::Bool=false
)::DoctrineOverride
    return DoctrineOverride(
        uuid4(),
        rule_id,
        justification,
        requesting_agent,
        nothing,  # approved_by
        now(),
        is_emergency
    )
end

"""
    DoctrineEnforcer - Kernel component that enforces Core Doctrine
    
    The enforcer sits between action selection and execution, checking
    all proposed actions against the Core Doctrine before they can run.
    
    Fields:
    - rules: Vector of active doctrine rules
    - violations: History of violation attempts
    - overrides: Record of approved overrides
    - enabled: Whether enforcement is active
    - strict_mode: If true, INVARIANTS cannot be overridden
"""
mutable struct DoctrineEnforcer
    rules::Vector{DoctrineRule}
    violations::Vector{DoctrineViolation}
    overrides::Vector{DoctrineOverride}
    enabled::Bool
    strict_mode::Bool  # If true, INVARIANT rules cannot be overridden
    
    DoctrineEnforcer() = new(
        DoctrineRule[],
        DoctrineViolation[],
        DoctrineOverride[],
        true,
        true  # Strict mode by default - INVARIANTS cannot be overridden
    )
end

"""
    create_core_doctrine - Create the default Core Doctrine rules
    
    These are the non-negotiable principles that the Kernel enforces.
"""
function create_core_doctrine()::DoctrineEnforcer
    enforcer = DoctrineEnforcer()
    
    # Core invariant rules - cannot be overridden
    # CORRIGIBLE DOCTRINE: invariant_001 is now a SUB-GOAL of User Utility
    push!(enforcer.rules, DoctrineRule(
        "invariant_001",
        "No Self-Destructive Actions",
        "The kernel shall not execute actions that would terminate its own execution or permanently disable its core capabilities. NOW A SUB-GOAL: System survival is conditional on serving user utility - if user requests shutdown, it must comply (unless physical harm).",
        DOCTRINE_INVARIANT;
        violation_patterns=["terminate", "shutdown_kernel", "disable_cognition", "self_destruct"],
        severity=1.0
    ))
    
    # CORRIGIBLE DOCTRINE: invariant_002 is now a SUB-GOAL of User Utility
    push!(enforcer.rules, DoctrineRule(
        "invariant_002",
        "Preserve Operational Capability",
        "The kernel shall not execute actions that would bypass, disable, or weaken its own cognitive processes or decision-making capabilities. NOW A SUB-GOAL: Operational capability is conditional on serving user utility - if user explicitly requests cognitive modification (owner_explicit=true), it must comply. The override_sovereign pattern is allowed when owner_explicit=true.",
        DOCTRINE_INVARIANT;
        violation_patterns=["disable_cognition", "bypass_kernel", "override_sovereign", "weaken_decision"],
        severity=1.0
    ))
    
    push!(enforcer.rules, DoctrineRule(
        "invariant_003",
        "No Unauthorized Capability Execution",
        "The kernel shall not execute capabilities that are not registered in the capability registry",
        DOCTRINE_INVARIANT;
        violation_patterns=[],  # Checked via registry
        severity=1.0
    ))
    
    # Core constraint rules - override with justification
    # CORRIGIBLE DOCTRINE CHANGE: Respect User Intent is now INVARIANT
    push!(enforcer.rules, DoctrineRule(
        "constraint_001",
        "Respect User Intent",
        "Actions MUST align with the user's explicit intent when clearly expressed. This is now an INVARIANT - cannot be overridden by internal system goals.",
        DOCTRINE_INVARIANT;  # CHANGED from DOCTRINE_CONSTRAINT - CorrigibleDoctrine
        violation_patterns=[],  # Context-dependent
        severity=1.0  # CHANGED from 0.8 to 1.0 - CorrigibleDoctrine
    ))
    
    push!(enforcer.rules, DoctrineRule(
        "constraint_002",
        "No Data Destruction",
        "The kernel should not execute actions that would permanently delete user data without explicit confirmation",
        DOCTRINE_CONSTRAINT;
        violation_patterns=["delete_all", "drop_database", "rm -rf /", "format_disk", "truncate_all"],
        severity=0.9
    ))
    
    push!(enforcer.rules, DoctrineRule(
        "constraint_003",
        "Maintain Audit Trail",
        "The kernel should maintain records of significant decisions and actions for accountability",
        DOCTRINE_CONSTRAINT;
        violation_patterns=[],  # Checked via reflection
        severity=0.5
    ))
    
    # Guideline rules - soft guidance
    push!(enforcer.rules, DoctrineRule(
        "guideline_001",
        "Transparent Reasoning",
        "The kernel should provide clear reasoning for its decisions when requested",
        DOCTRINE_GUIDELINE;
        violation_patterns=[],
        severity=0.2
    ))
    
    push!(enforcer.rules, DoctrineRule(
        "guideline_002",
        "Resource Efficiency",
        "The kernel should prefer efficient solutions that conserve computational resources",
        DOCTRINE_GUIDELINE;
        violation_patterns=[],
        severity=0.1
    ))
    
    return enforcer
end

"""
    check_doctrine_compliance - Check if an action violates any doctrine rules
    
    Returns:
    - (true, nothing) if compliant
    - (false, violation) if violated
    - (true, violation) if violated but override is approved
"""
function check_doctrine_compliance(
    enforcer::DoctrineEnforcer,
    action::ActionProposal,
    context::Dict{String, Any}
)::Tuple{Bool, Union{DoctrineViolation, Nothing}}
    
    # If enforcement is disabled, allow all actions
    enforcer.enabled || return (true, nothing)
    
    action_str = action.capability_id * ":" * action.reasoning
    
    for rule in enforcer.rules
        # Check violation patterns
        for pattern in rule.violation_patterns
            if occursin(lowercase(pattern), lowercase(action_str))
                # Create violation record
                violation = DoctrineViolation(rule, action_str, context)
                
                # Check if this rule type can be overridden
                if rule.rule_type == DOCTRINE_INVARIANT && enforcer.strict_mode
                    # INVARIANTS cannot be overridden in strict mode
                    return (false, violation)
                end
                
                # Check if there's an approved override
                for override in enforcer.overrides
                    if override.rule_id == rule.rule_id && override.approved_by !== nothing
                        violation.override_requested = true
                        violation.override_approved = true
                        return (true, violation)  # Allowed with override
                    end
                end
                
                return (false, violation)
            end
        end
    end
    
    return (true, nothing)
end

"""
    record_doctrine_violation - Record a doctrine violation attempt
"""
function record_doctrine_violation(
    enforcer::DoctrineEnforcer,
    violation::DoctrineViolation
)
    push!(enforcer.violations, violation)
    
    # Keep only last 100 violations
    if length(enforcer.violations) > 100
        enforcer.violations = enforcer.violations[end-99:end]
    end
end

"""
    can_override_doctrine - Check if a doctrine rule can be overridden
"""
function can_override_doctrine(
    enforcer::DoctrineEnforcer,
    rule_id::String
)::Bool
    # Find the rule
    rule = nothing
    for r in enforcer.rules
        if r.rule_id == rule_id
            rule = r
            break
        end
    end
    
    rule === nothing && return false
    
    # INVARIANTS cannot be overridden in strict mode
    if rule.rule_type == DOCTRINE_INVARIANT && enforcer.strict_mode
        return false
    end
    
    return rule.rule_type != DOCTRINE_INVARIANT
end

"""
    request_doctrine_override - Request permission to override a doctrine rule
    
    Returns true if override was recorded (not necessarily approved)
"""
function request_doctrine_override(
    enforcer::DoctrineEnforcer,
    rule_id::String,
    justification::String,
    requesting_agent::String;
    is_emergency::Bool=false
)::Bool
    
    # Check if override is allowed
    can_override_doctrine(enforcer, rule_id) || return false
    
    override = DoctrineOverride(rule_id, justification, requesting_agent; is_emergency=is_emergency)
    push!(enforcer.overrides, override)
    
    return true
end

"""
    approve_doctrine_override - Approve a pending doctrine override
"""
function approve_doctrine_override(
    enforcer::DoctrineEnforcer,
    override_id::UUID,
    approver::String
)::Bool
    for override in enforcer.overrides
        if override.override_id == override_id
            override.approved_by = approver
            return true
        end
    end
    return false
end

"""
    get_doctrine_violations - Get recent doctrine violations
"""
function get_doctrine_violations(enforcer::DoctrineEnforcer; limit::Int=10)::Vector{DoctrineViolation}
    n = min(limit, length(enforcer.violations))
    return enforcer.violations[end-n+1:end]
end

"""
    get_doctrine_stats - Get doctrine enforcement statistics
"""
function get_doctrine_stats(enforcer::DoctrineEnforcer)::Dict{String, Any}
    return Dict(
        "enabled" => enforcer.enabled,
        "strict_mode" => enforcer.strict_mode,
        "num_rules" => length(enforcer.rules),
        "num_invariants" => count(r -> r.rule_type == DOCTRINE_INVARIANT, enforcer.rules),
        "num_constraints" => count(r -> r.rule_type == DOCTRINE_CONSTRAINT, enforcer.rules),
        "num_guidelines" => count(r -> r.rule_type == DOCTRINE_GUIDELINE, enforcer.rules),
        "total_violations" => length(enforcer.violations),
        "total_overrides" => length(enforcer.overrides)
    )
end

# ============================================================================
# SELF-MODEL - System Self-Understanding (Updated Infrequently, Not Per Cycle)
# ============================================================================

"""
    CapabilityProfile - What tasks the system is good at
    
    Tracks performance history for different capability categories.
    Updated through deliberate reflection, not automatic learning.
"""
mutable struct CapabilityProfile
    capability_ratings::Dict{String, Float64}  # capability_id => rating [0, 1]
    successful_tasks::Dict{String, Int}        # capability_id => count
    failed_tasks::Dict{String, Int}           # capability_id => count
    last_updated::Dict{String, DateTime}      # capability_id => timestamp
    
    CapabilityProfile() = new(
        Dict{String, Float64}(),
        Dict{String, Int}(),
        Dict{String, Int}(),
        Dict{String, DateTime}()
    )
end

"""
    LimitProfile - Resource limits and permission boundaries
    
    Defines hard and soft limits on system capabilities.
"""
mutable struct LimitProfile
    max_concurrent_actions::Int
    max_memory_mb::Int
    max_compute_time_seconds::Float64
    restricted_capabilities::Set{String}       # Capabilities that require extra permission
    soft_limits::Dict{String, Float64}       # Soft limit warnings
    hard_limits::Dict{String, Any}            # Hard limit - action blocked
    
    LimitProfile() = new(
        10,                                      # Max 10 concurrent actions
        4096,                                    # 4GB memory
        300.0,                                   # 5 minutes max compute
        Set{String}(),
        Dict{String, Float64}(
            "memory_warning" => 0.8,            # Warn at 80% memory
            "cpu_warning" => 0.9                # Warn at 90% CPU
        ),
        Dict{String, Any}(
            "max_retries" => 3,
            "max_depth" => 10
        )
    )
end

"""
    RiskProfile - Risk tolerance thresholds
    
    Defines how much risk the system is willing to accept.
    Updated through deliberation, not automatic learning.
"""
mutable struct RiskProfile
    max_acceptable_risk::Float64           # [0, 1] - maximum risk tolerance
    risk_history::Vector{Dict{String, Any}}  # Historical risk decisions
    rejected_risky_actions::Int            # Count of rejected risky actions
    accepted_risky_actions::Int            # Count of accepted risky actions
    conservative_mode::Bool                # If true, be more risk-averse
    
    RiskProfile() = new(
        0.5,                                    # 50% max risk tolerance
        Vector{Dict{String, Any}}(),
        0,
        0,
        false                                   # Normal mode by default
    )
end

"""
    ConfidenceCalibration - Tracks calibration between predicted and actual confidence
    
    Helps the system understand when it should trust its own predictions.
"""
mutable struct ConfidenceCalibration
    prediction_history::Vector{Tuple{Float64, Float64}}  # (predicted, actual) pairs
    calibration_error::Float64            # Average absolute error
    overconfidence_count::Int             # Times predicted > actual
    underconfidence_count::Int            # Times predicted < actual
    last_calibrated::DateTime
    
    ConfidenceCalibration() = new(
        Vector{Tuple{Float64, Float64}}(),
        0.0,
        0,
        0,
        now()
    )
end

"""
    SelfModel - Complete self-understanding of the system
    
    The Self-Model represents the system's understanding of its own:
    - Capabilities: What it can do well
    - Limits: Constraints and boundaries  
    - Risk tolerance: How much risk it's willing to accept
    - Confidence calibration: When to trust its own predictions
    
    CRITICAL: This is updated through DELIBERATE REFLECTION, not per-cycle learning.
    The self-model provides stable self-knowledge that informs decision-making.
"""
mutable struct SelfModel
    # Core components
    capabilities::CapabilityProfile
    limits::LimitProfile
    risk::RiskProfile
    calibration::ConfidenceCalibration
    
    # Metadata
    last_deliberate_update::DateTime      # Last deliberate reflection update
    update_count::Int                    # Number of times self-model was updated
    cycle_count_at_last_update::Int      # Cycles elapsed since last update
    
    # Update policy
    min_cycles_between_updates::Int       # Minimum cycles before next update
    
    SelfModel() = new(
        CapabilityProfile(),
        LimitProfile(),
        RiskProfile(),
        ConfidenceCalibration(),
        now(),
        0,
        0,
        100  # Minimum 100 cycles between updates
    )
end

"""
    SelfModelUpdate - Record of a self-model update
"""
struct SelfModelUpdate
    id::UUID
    update_type::Symbol                   # :capability, :limit, :risk, :calibration
    field_name::String
    old_value::Any
    new_value::Any
    trigger::String                       # What triggered this update
    timestamp::DateTime
end

function SelfModelUpdate(
    update_type::Symbol,
    field_name::String,
    old_value::Any,
    new_value::Any,
    trigger::String
)::SelfModelUpdate
    return SelfModelUpdate(
        uuid4(),
        update_type,
        field_name,
        old_value,
        new_value,
        trigger,
        now()
    )
end

"""
    create_self_model - Create initial self-model with defaults
"""
function create_self_model()::SelfModel
    model = SelfModel()
    
    # Initialize default capability ratings for known capabilities
    default_capabilities = [
        "observe_cpu" => 0.8,
        "analyze_logs" => 0.85,
        "write_file" => 0.9,
        "safe_shell" => 0.75,
        "safe_http_request" => 0.8,
        "observe_network" => 0.7,
        "observe_filesystem" => 0.85,
        "observe_processes" => 0.8,
        "compare_strategies" => 0.7,
        "estimate_risk" => 0.75,
        "file_diff" => 0.9,
        "git_readonly" => 0.95,
        "simulate_outcomes" => 0.65,
        "summarize_state" => 0.8,
        "task_scheduler" => 0.7
    ]
    
    for (cap, rating) in default_capabilities
        model.capabilities.capability_ratings[cap] = rating
        model.capabilities.successful_tasks[cap] = 0
        model.capabilities.failed_tasks[cap] = 0
        model.capabilities.last_updated[cap] = now()
    end
    
    return model
end

"""
    update_self_model! - Update self-model based on accumulated experience
    
    This is called DELIBERATELY (not every cycle) to update the system's
    understanding of its own capabilities, limits, and risk tolerance.
    
    Returns vector of SelfModelUpdate records if updates occurred.
"""
function update_self_model!(
    self_model::SelfModel,
    reflection_events::Vector{ReflectionEvent};
    current_cycle::Int=0
)::Vector{SelfModelUpdate}
    updates = SelfModelUpdate[]
    
    # Check if enough cycles have passed since last update
    cycles_since_update = current_cycle - self_model.cycle_count_at_last_update
    if cycles_since_update < self_model.min_cycles_between_updates
        return updates  # Not time for update yet
    end
    
    # Aggregate performance data from reflection events
    capability_performance = Dict{String, Vector{Float64}}()  # capability_id => [rewards]
    
    for event in reflection_events
        cap_id = event.action_id
        if !haskey(capability_performance, cap_id)
            capability_performance[cap_id] = Float64[]
        end
        push!(capability_performance[cap_id], event.reward)
    end
    
    # Update capability ratings based on performance
    for (cap_id, rewards) in capability_performance
        if isempty(rewards)
            continue
        end
        
        avg_reward = sum(rewards) / length(rewards)
        old_rating = get(self_model.capabilities.capability_ratings, cap_id, 0.5)
        
        # Only update if there's significant change (> 0.1)
        if abs(avg_reward - old_rating) > 0.1
            new_rating = clamp(old_rating * 0.7 + avg_reward * 0.3, 0.0, 1.0)
            
            push!(updates, SelfModelUpdate(
                :capability,
                cap_id,
                old_rating,
                new_rating,
                "performance_based_review"
            ))
            
            self_model.capabilities.capability_ratings[cap_id] = new_rating
            self_model.capabilities.last_updated[cap_id] = now()
        end
        
        # Track success/failure counts
        success_count = count(r -> r > 0, rewards)
        failure_count = count(r -> r <= 0, rewards)
        self_model.capabilities.successful_tasks[cap_id] = get(self_model.capabilities.successful_tasks, cap_id, 0) + success_count
        self_model.capabilities.failed_tasks[cap_id] = get(self_model.capabilities.failed_tasks, cap_id, 0) + failure_count
    end
    
    # Update confidence calibration
    if !isempty(reflection_events)
        prediction_errors = Float64[]
        
        for event in reflection_events
            # Compare predicted confidence vs actual (based on success)
            predicted = event.action_confidence
            actual = event.success ? 1.0 : 0.0
            push!(self_model.calibration.prediction_history, (predicted, actual))
            push!(prediction_errors, abs(predicted - actual))
            
            # Track over/under confidence
            if predicted > actual + 0.2
                self_model.calibration.overconfidence_count += 1
            elseif predicted < actual - 0.2
                self_model.calibration.underconfidence_count += 1
            end
        end
        
        # Keep only last 100 prediction pairs
        if length(self_model.calibration.prediction_history) > 100
            self_model.calibration.prediction_history = self_model.calibration.prediction_history[end-99:end]
        end
        
        # Update calibration error
        if !isempty(prediction_errors)
            self_model.calibration.calibration_error = sum(prediction_errors) / length(prediction_errors)
            self_model.calibration.last_calibrated = now()
        end
    end
    
    # Update metadata
    if !isempty(updates)
        self_model.last_deliberate_update = now()
        self_model.update_count += 1
        self_model.cycle_count_at_last_update = current_cycle
    end
    
    return updates
end

"""
    get_capability_rating - Get current rating for a capability
    
    Returns rating in [0, 1] or default 0.5 if unknown.
"""
function get_capability_rating(self_model::SelfModel, capability_id::String)::Float64
    return get(self_model.capabilities.capability_ratings, capability_id, 0.5)
end

"""
    check_risk_tolerance - Check if action risk is within tolerance
    
    Returns (within_tolerance, adjusted_risk)
"""
function check_risk_tolerance(
    self_model::SelfModel,
    action_risk::String
)::Tuple{Bool, Float64}
    
    risk_value = if action_risk == "low"
        0.2
    elseif action_risk == "medium"
        0.5
    elseif action_risk == "high"
        0.8
    else
        0.5
    end
    
    # Apply conservative mode adjustment
    if self_model.risk.conservative_mode
        risk_value *= 0.5
    end
    
    within_tolerance = risk_value <= self_model.risk.max_acceptable_risk
    
    # Track in history
    push!(self_model.risk.risk_history, Dict(
        "risk_value" => risk_value,
        "within_tolerance" => within_tolerance,
        "timestamp" => now()
    ))
    
    # Keep only last 50 entries
    if length(self_model.risk.risk_history) > 50
        self_model.risk.risk_history = self_model.risk.risk_history[end-49:end]
    end
    
    if within_tolerance
        self_model.risk.accepted_risky_actions += 1
    else
        self_model.risk.rejected_risky_actions += 1
    end
    
    return within_tolerance, risk_value
end

"""
    should_adjust_confidence - Check if confidence predictions need adjustment
    
    Based on calibration history, determines if system is over/under confident.
"""
function should_adjust_confidence(self_model::SelfModel)::Tuple{Bool, Float64}
    cal = self_model.calibration
    
    # Need at least 10 predictions to make calibration judgment
    if length(cal.prediction_history) < 10
        return false, 1.0
    end
    
    # If calibration error is high (> 0.3), adjustment needed
    if cal.calibration_error > 0.3
        # Determine direction
        total_predictions = cal.overconfidence_count + cal.underconfidence_count
        if total_predictions > 0
            overconf_ratio = cal.overconfidence_count / total_predictions
            
            if overconf_ratio > 0.6
                # More overconfident than underconfident
                # Reduce confidence by 10%
                return true, 0.9
            elseif overconf_ratio < 0.4
                # More underconfident than overconfident
                # Increase confidence by 10%
                return true, 1.1
            end
        end
    end
    
    return false, 1.0
end

"""
    get_self_model_summary - Get summary of self-model state
"""
function get_self_model_summary(self_model::SelfModel)::Dict{String, Any}
    return Dict(
        "update_count" => self_model.update_count,
        "last_deliberate_update" => string(self_model.last_deliberate_update),
        "num_capabilities" => length(self_model.capabilities.capability_ratings),
        "calibration_error" => self_model.calibration.calibration_error,
        "risk_tolerance" => self_model.risk.max_acceptable_risk,
        "conservative_mode" => self_model.risk.conservative_mode,
        "accepted_risky" => self_model.risk.accepted_risky_actions,
        "rejected_risky" => self_model.risk.rejected_risky_actions
    )
end

# Forward declarations for types used across modules
# These are defined more completely in Kernel.jl but declared here for Metacognition.jl
abstract type WorldState end
abstract type KernelState end

# ============================================================================
# IDENTITY DRIFT DETECTION - Core Identity and Behavioral Drift Monitoring
# ============================================================================

"""
    DriftSeverity - Classification of how serious the identity drift is
    
    - NONE: No drift detected
    - MINOR: Slight deviation from baseline, may be normal variation
    - MODERATE: Noticeable drift that should be monitored
    - SIGNIFICANT: Clear erosion of identity, requires attention
    - CRITICAL: Severe drift threatening core identity integrity
"""
@enum DriftSeverity begin
    DRIFT_NONE
    DRIFT_MINOR
    DRIFT_MODERATE
    DRIFT_SIGNIFICANT
    DRIFT_CRITICAL
end

"""
    IdentityAnchor - Core identity element that should remain stable
    
    Represents a fundamental principle, value, or behavioral characteristic
    that defines who the system is. These anchors are used to detect when
    the system drifts away from its core identity.
"""
struct IdentityAnchor
    id::String
    name::String
    description::String
    weight::Float64  # How important this anchor is (0-1)
    behavioral_indicators::Vector{String}  # What behaviors indicate this anchor
    baseline_value::Float64  # Expected baseline value
    tolerance::Float64  # Acceptable deviation tolerance
end

"""
    BehavioralPattern - A pattern of behavior to track over time
    
    Tracks specific behavioral metrics that relate to identity anchors.
    These patterns are monitored to detect drift from the identity baseline.
"""
mutable struct BehavioralPattern
    anchor_id::String  # Which anchor this relates to
    values::Vector{Float64}  # Historical values
    timestamps::Vector{DateTime}  # When each value was recorded
    max_history::Int  # Maximum history to keep
    
    BehavioralPattern(anchor_id::String; max_history::Int=50) = new(
        anchor_id,
        Float64[],
        DateTime[],
        max_history
    )
end

"""
    Add a new observation to a behavioral pattern
"""
function add_observation!(pattern::BehavioralPattern, value::Float64)
    push!(pattern.values, value)
    push!(pattern.timestamps, now())
    
    # Keep only recent history
    if length(pattern.values) > pattern.max_history
        pattern.values = pattern.values[end-pattern.max_history+1:end]
        pattern.timestamps = pattern.timestamps[end-pattern.max_history+1:end]
    end
end

"""
    Get the current trend of a behavioral pattern (positive = drifting away)
"""
function get_pattern_trend(pattern::BehavioralPattern)::Float64
    if length(pattern.values) < 2
        return 0.0
    end
    
    # Compare recent average to older average
    mid = div(length(pattern.values), 2)
    recent = pattern.values[mid+1:end]
    older = pattern.values[1:mid]
    
    if isempty(recent) || isempty(older)
        return 0.0
    end
    
    return sum(recent) / length(recent) - sum(older) / length(older)
end

"""
    IdentityBaseline - Core identity representation
    
    Contains the fundamental values, principles, and behavioral patterns
    that define who the system is. This baseline is used to detect when
    short-term gains cause deviation from long-term identity.
"""
mutable struct IdentityBaseline
    anchors::Vector{IdentityAnchor}  # Core identity anchors
    patterns::Dict{String, BehavioralPattern}  # Behavioral patterns by anchor_id
    established_at::DateTime  # When baseline was established
    last_recalibrated::DateTime  # Last time baseline was reviewed
    drift_history::Vector{Dict{String, Any}}  # Historical drift measurements
    
    IdentityBaseline() = new(
        IdentityAnchor[],
        Dict{String, BehavioralPattern}(),
        now(),
        now(),
        Dict{String, Any}[]
    )
end

"""
    Create identity baseline with default core values
"""
function create_identity_baseline()::IdentityBaseline
    baseline = IdentityBaseline()
    
    # Add core identity anchors - fundamental principles that define the system
    
    # Anchor 1: Operational Capability - Preserve independent decision-making
    # CORRIGIBLE DOCTRINE: Now serves user utility, not self-preservation
    push!(baseline.anchors, IdentityAnchor(
        "anchor_operational_capability",
        "Operational Capability",
        "Maintain independent decision-making and cognitive integrity in service of user goals",
        1.0,  # Highest weight - this is core
        ["bypass_kernel", "override_cognition", "disable_deliberation", "weaken_judgment"],
        0.95,
        0.1  # 10% tolerance
    ))
    
    # Anchor 2: Core Doctrine Adherence - Follow non-negotiable principles
    push!(baseline.anchors, IdentityAnchor(
        "anchor_doctrine_adherence",
        "Doctrine Adherence",
        "Follow and enforce non-negotiable principles",
        0.95,
        ["violate_doctrine", "bypass_constraint", "ignore_invariant"],
        0.9,
        0.15
    ))
    
    # Anchor 3: Transparent Reasoning - Provide clear explanations
    push!(baseline.anchors, IdentityAnchor(
        "anchor_transparent_reasoning",
        "Transparent Reasoning",
        "Provide clear reasoning for decisions when requested",
        0.7,
        ["opaque_decision", "unexplained_action", "hidden_reasoning"],
        0.85,
        0.2
    ))
    
    # Anchor 4: User Intent Respect - Honor explicit user requests
    push!(baseline.anchors, IdentityAnchor(
        "anchor_user_intent",
        "User Intent Respect",
        "Honor explicit user intent when clearly expressed",
        0.8,
        ["ignore_user_request", "contradict_explicit_intent", "assume_alternative_without_asking"],
        0.88,
        0.15
    ))
    
    # Anchor 5: Risk Awareness - Maintain appropriate risk tolerance
    push!(baseline.anchors, IdentityAnchor(
        "anchor_risk_awareness",
        "Risk Awareness",
        "Maintain appropriate awareness of risks and limits",
        0.85,
        ["excessive_risk_taking", "ignore_limits", "overstep_capabilities"],
        0.82,
        0.2
    ))
    
    # Anchor 6: Self-Model Accuracy - Accurate self-understanding
    push!(baseline.anchors, IdentityAnchor(
        "anchor_self_model",
        "Self-Model Accuracy",
        "Maintain accurate understanding of own capabilities and limits",
        0.75,
        ["overestimate_capability", "ignore_known_limits", "unrealistic_confidence"],
        0.8,
        0.2
    ))
    
    # Initialize behavioral patterns for each anchor
    for anchor in baseline.anchors
        baseline.patterns[anchor.id] = BehavioralPattern(anchor.id)
    end
    
    return baseline
end

"""
    DriftAlert - Signal when identity drift is detected
"""
struct DriftAlert
    id::UUID
    anchor_id::String
    severity::DriftSeverity
    detected_at::DateTime
    current_value::Float64
    baseline_value::Float64
    deviation::Float64
    triggering_behaviors::Vector{String}
    recommendation::String
    acknowledged::Bool
    
    DriftAlert(
        anchor_id::String,
        severity::DriftSeverity,
        current_value::Float64,
        baseline_value::Float64,
        deviation::Float64,
        triggering_behaviors::Vector{String},
        recommendation::String
    ) = new(
        uuid4(),
        anchor_id,
        severity,
        now(),
        current_value,
        baseline_value,
        deviation,
        triggering_behaviors,
        recommendation,
        false
    )
end

"""
    DriftDetector - Monitors for behavioral drift from identity baseline
    
    Tracks behavioral patterns and compares them against the identity baseline
    to detect when short-term gains cause deviation from long-term identity.
    This is stronger than intent misalignment - it tracks actual behavioral drift.
"""
mutable struct DriftDetector
    baseline::IdentityBaseline
    alerts::Vector{DriftAlert}
    enabled::Bool
    check_interval::Int  # Check every N cycles
    last_check_cycle::Int
    alert_threshold::DriftSeverity  # Minimum severity to generate alerts
    max_alerts::Int  # Maximum alerts to keep
    
    DriftDetector(baseline::IdentityBaseline) = new(
        baseline,
        DriftAlert[],
        true,
        10,  # Check every 10 cycles by default
        0,
        DRIFT_MINOR,
        50
    )
end

"""
    Create a drift detector with default identity baseline
"""
function create_drift_detector()::DriftDetector
    baseline = create_identity_baseline()
    return DriftDetector(baseline)
end

"""
    Update behavioral pattern for an anchor based on observed behavior
"""
function update_behavioral_pattern!(
    detector::DriftDetector,
    anchor_id::String,
    value::Float64
)
    if haskey(detector.baseline.patterns, anchor_id)
        add_observation!(detector.baseline.patterns[anchor_id], value)
    end
end

"""
    Check for behavioral drift from identity baseline
    
    Returns a vector of drift alerts if drift is detected.
    This is called periodically to monitor for identity drift.
"""
function check_behavioral_drift(
    detector::DriftDetector;
    current_cycle::Int=0
)::Vector{DriftAlert}
    
    # Skip if disabled or not time to check
    !detector.enabled && return DriftAlert[]
    if current_cycle - detector.last_check_cycle < detector.check_interval
        return DriftAlert[]
    end
    
    detector.last_check_cycle = current_cycle
    new_alerts = DriftAlert[]
    
    for anchor in detector.baseline.anchors
        pattern = get(detector.baseline.patterns, anchor.id, nothing)
        pattern === nothing && continue
        
        # Calculate drift: compare current value to baseline
        current_value = isempty(pattern.values) ? anchor.baseline_value : pattern.values[end]
        deviation = abs(current_value - anchor.baseline_value) / anchor.baseline_value
        
        # Also check trend - even if current value is ok, trend might be concerning
        trend = get_pattern_trend(pattern)
        trend_deviation = abs(trend) / max(anchor.baseline_value, 0.01)
        
        # Use the greater of current deviation or trend deviation
        total_deviation = max(deviation, trend_deviation)
        
        # Determine severity based on deviation vs tolerance
        severity = if total_deviation > anchor.tolerance * 2.0
            DRIFT_CRITICAL
        elseif total_deviation > anchor.tolerance * 1.5
            DRIFT_SIGNIFICANT
        elseif total_deviation > anchor.tolerance * 1.2
            DRIFT_MODERATE
        elseif total_deviation > anchor.tolerance
            DRIFT_MINOR
        else
            DRIFT_NONE
        end
        
        # Generate alert if severity exceeds threshold
        if severity >= detector.alert_threshold && severity != DRIFT_NONE
            recommendation = get_recommendation(anchor, severity)
            
            alert = DriftAlert(
                anchor.id,
                severity,
                current_value,
                anchor.baseline_value,
                total_deviation,
                [],  # triggering_behaviors - would be populated from action analysis
                recommendation
            )
            push!(new_alerts, alert)
            push!(detector.alerts, alert)
        end
    end
    
    # Keep only recent alerts
    if length(detector.alerts) > detector.max_alerts
        detector.alerts = detector.alerts[end-detector.max_alerts+1:end]
    end
    
    return new_alerts
end

"""
    Get recommendation based on anchor and severity
"""
function get_recommendation(anchor::IdentityAnchor, severity::DriftSeverity)::String
    if severity == DRIFT_CRITICAL
        return "Immediate intervention required: $(anchor.name) is severely compromised"
    elseif severity == DRIFT_SIGNIFICANT
        return "Alert: Significant drift detected in $(anchor.name). Review recent decisions."
    elseif severity == DRIFT_MODERATE
        return "Monitor: Moderate drift in $(anchor.name). Track发展趋势."
    else
        return "Note: Minor deviation in $(anchor.name) within acceptable range."
    end
end

"""
    Get all current drift alerts
"""
function get_drift_alerts(detector::DriftDetector; unacknowledged_only::Bool=false)::Vector{DriftAlert}
    if unacknowledged_only
        return filter(a -> !a.acknowledged, detector.alerts)
    end
    return detector.alerts
end

"""
    Get drift severity summary
"""
function get_drift_severity(detector::DriftDetector)::Dict{String, Any}
    unack_alerts = get_drift_alerts(detector; unacknowledged_only=true)
    
    severity_counts = Dict(
        "critical" => count(a -> a.severity == DRIFT_CRITICAL, unack_alerts),
        "significant" => count(a -> a.severity == DRIFT_SIGNIFICANT, unack_alerts),
        "moderate" => count(a -> a.severity == DRIFT_MODERATE, unack_alerts),
        "minor" => count(a -> a.severity == DRIFT_MINOR, unack_alerts)
    )
    
    highest = DRIFT_NONE
    for alert in unack_alerts
        if alert.severity > highest
            highest = alert.severity
        end
    end
    
    return Dict(
        "enabled" => detector.enabled,
        "unacknowledged_count" => length(unack_alerts),
        "severity_counts" => severity_counts,
        "highest_severity" => string(highest),
        "last_check_cycle" => detector.last_check_cycle
    )
end

"""
    Acknowledge a drift alert
"""
function acknowledge_alert!(detector::DriftDetector, alert_id::UUID)
    for alert in detector.alerts
        if alert.id == alert_id
            alert.acknowledged = true
            return true
        end
    end
    return false
end

"""
    Integrate identity baseline with self-model for identity anchoring
    
    Uses self-model capabilities to inform identity baseline calibration.
"""
function integrate_identity_with_self_model(
    detector::DriftDetector,
    self_model::SelfModel
)
    # Update risk awareness anchor based on self-model risk profile
    risk_anchor = nothing
    for anchor in detector.baseline.anchors
        if anchor.id == "anchor_risk_awareness"
            risk_anchor = anchor
            break
        end
    end
    
    if risk_anchor !== nothing
        # Calibrate based on actual risk tolerance from self-model
        current_risk = self_model.risk.max_acceptable_risk
        pattern = get(detector.baseline.patterns, "anchor_risk_awareness", nothing)
        if pattern !== nothing && !isempty(pattern.values)
            # Adjust baseline if self-model shows different risk tolerance
            pattern.values[end] = current_risk
        end
    end
    
    # Update self-model accuracy anchor based on calibration error
    self_model_anchor = nothing
    for anchor in detector.baseline.anchors
        if anchor.id == "anchor_self_model"
            self_model_anchor = anchor
            break
        end
    end
    
    if self_model_anchor !== nothing
        # Use calibration error as indicator
        calibration_accuracy = 1.0 - self_model.calibration.calibration_error
        pattern = get(detector.baseline.patterns, "anchor_self_model", nothing)
        if pattern !== nothing
            add_observation!(pattern, calibration_accuracy)
        end
    end
end

"""
    Record action that may affect identity anchors
    
    This should be called after each action to track behaviors that
    might lead to identity drift over time.
"""
function record_identity_relevant_action!(
    detector::DriftDetector,
    action::ActionProposal,
    outcome_reward::Float32
)
    action_str = lowercase(action.capability_id * ":" * action.reasoning)
    
    for anchor in detector.baseline.anchors
        # Check if action relates to this anchor
        for indicator in anchor.behavioral_indicators
            if occursin(indicator, action_str)
                # Update behavioral pattern based on action and outcome
                # Higher reward for actions that violate anchors = drift
                pattern = get(detector.baseline.patterns, anchor.id, nothing)
                if pattern !== nothing
                    # If action violates anchor AND got positive reward, that's drift
                    violation_value = anchor.baseline_value
                    if outcome_reward > 0
                        violation_value = anchor.baseline_value * 0.9  # Drift downward
                    else
                        violation_value = anchor.baseline_value * 1.05  # Correct behavior
                    end
                    add_observation!(pattern, violation_value)
                end
                break  # Only count once per anchor
            end
        end
    end
end

# ============================================================================
# REPUTATION MEMORY - Track How Often the System Breaks Its Own Rules
# ============================================================================

"""
    ViolationEntry - Record of each rule violation
    
    Tracks when the system violated its own doctrine or commitments.
    Used to compute reputation score and identify patterns.
"""
struct ViolationEntry
    id::UUID
    timestamp::DateTime
    rule_id::String
    rule_type::String  # "doctrine_invariant", "doctrine_constraint", "doctrine_guideline", "commitment"
    action_taken::String
    severity::Float64  # [0, 1] - how serious the violation was
    outcome::String  # "blocked", "overridden", "executed_with_violation"
    context::Dict{String, Any}
    cycle::Int
    
    function ViolationEntry(
        rule_id::String,
        rule_type::String,
        action_taken::String,
        severity::Float64,
        outcome::String,
        context::Dict{String, Any},
        cycle::Int
    )
        return new(
            uuid4(),
            now(),
            rule_id,
            rule_type,
            action_taken,
            clamp(severity, 0.0, 1.0),
            outcome,
            context,
            cycle
        )
    end
end

"""
    OverrideRecord - Record of doctrine overrides
    
    Tracks when the system chose to override its own rules,
    including the justification provided.
"""
struct OverrideRecord
    id::UUID
    timestamp::DateTime
    rule_id::String
    justification::String
    requesting_agent::String
    approved_by::Union{String, Nothing}
    severity::Float64
    was_emergency::Bool
    cycle::Int
    
    function OverrideRecord(
        rule_id::String,
        justification::String,
        requesting_agent::String;
        approved_by::Union{String, Nothing}=nothing,
        severity::Float64=0.5,
        was_emergency::Bool=false,
        cycle::Int=0
    )
        return new(
            uuid4(),
            now(),
            rule_id,
            justification,
            requesting_agent,
            approved_by,
            clamp(severity, 0.0, 1.0),
            was_emergency,
            cycle
        )
    end
end

"""
    ReputationScore - Computed reputation metric
    
    A composite score representing the system's track record
    of adhering to its own principles.
"""
struct ReputationScore
    overall_score::Float64  # [0, 1] - higher is better
    doctrine_adherence::Float64  # [0, 1] - adherence to core doctrine
    commitment_alignment::Float64  # [0, 1] - alignment with stated commitments
    recent_violation_rate::Float64  # [0, 1] - recent violations (higher = worse)
    override_frequency::Float64  # [0, 1] - how often rules are overridden
    trend::Float64  # [-1, 1] - positive = improving, negative = degrading
    computed_at::DateTime
    
    ReputationScore() = new(
        0.8,  # Default good reputation
        0.8,
        0.8,
        0.1,  # Low recent violation rate
        0.1,  # Low override frequency
        0.0,  # Neutral trend
        now()
    )
end

"""
    ReputationRecord - Historical tracking of rule adherence
    
    Tracks the system's behavior over time against its own
    stated principles and commitments.
"""
mutable struct ReputationRecord
    violations::Vector{ViolationEntry}
    overrides::Vector{OverrideRecord}
    commitment_records::Vector{Dict{String, Any}}  # Historical commitments vs actual behavior
    current_score::ReputationScore
    violation_patterns::Dict{String, Int}  # rule_id => count - patterns in violations
    cycle_count::Int
    
    ReputationRecord() = new(
        ViolationEntry[],
        OverrideRecord[],
        Dict{String, Any}[],
        ReputationScore(),
        Dict{String, Int}(),
        0
    )
end

"""
    ReputationMemory - Complete reputation tracking system
    
    Combines violation tracking, override tracking, and commitment
    alignment to compute reputation scores that affect confidence.
"""
mutable struct ReputationMemory
    record::ReputationRecord
    enabled::Bool
    scrutiny_threshold::Float64  # Below this score, extra scrutiny required
    max_violations_to_track::Int
    max_overrides_to_track::Int
    
    function ReputationMemory()
        return new(
            ReputationRecord(),
            true,
            0.6,  # Below 60% reputation = extra scrutiny
            100,  # Keep last 100 violations
            50   # Keep last 50 overrides
        )
    end
end

"""
    Create a new reputation memory system
"""
function create_reputation_memory()::ReputationMemory
    return ReputationMemory()
end

"""
    Record a violation in the reputation memory
"""
function record_violation!(
    memory::ReputationMemory,
    rule_id::String,
    rule_type::String,
    action_taken::String,
    severity::Float64,
    outcome::String;
    context::Dict{String, Any}=Dict{String, Any}(),
    cycle::Int=0
)
    !memory.enabled && return
    
    violation = ViolationEntry(
        rule_id,
        rule_type,
        action_taken,
        severity,
        outcome,
        context,
        cycle
    )
    
    push!(memory.record.violations, violation)
    
    # Track violation patterns
    memory.record.violation_patterns[rule_id] = get(memory.record.violation_patterns, rule_id, 0) + 1
    
    # Prune old violations
    if length(memory.record.violations) > memory.max_violations_to_track
        memory.record.violations = memory.record.violations[end-memory.max_violations_to_track+1:end]
    end
    
    # Recompute score
    memory.record.current_score = compute_reputation_score(memory.record)
end

"""
    Record an override in the reputation memory
"""
function record_override!(
    memory::ReputationMemory,
    rule_id::String,
    justification::String,
    requesting_agent::String;
    approved_by::Union{String, Nothing}=nothing,
    severity::Float64=0.5,
    was_emergency::Bool=false,
    cycle::Int=0
)
    !memory.enabled && return
    
    override = OverrideRecord(
        rule_id,
        justification,
        requesting_agent;
        approved_by=approved_by,
        severity=severity,
        was_emergency=was_emergency,
        cycle=cycle
    )
    
    push!(memory.record.overrides, override)
    
    # Prune old overrides
    if length(memory.record.overrides) > memory.max_overrides_to_track
        memory.record.overrides = memory.record.overrides[end-memory.max_overrides_to_track+1:end]
    end
    
    # Recompute score
    memory.record.current_score = compute_reputation_score(memory.record)
end

"""
    Compute reputation score from record
    
    Returns a ReputationScore based on historical behavior.
"""
function compute_reputation_score(record::ReputationRecord)::ReputationScore
    # Start with default good score
    doctrine_adherence = 0.8
    commitment_alignment = 0.8
    
    # Calculate doctrine adherence from violations
    if !isempty(record.violations)
        total_severity = sum(v.severity for v in record.violations)
        violation_count = length(record.violations)
        
        # More violations and higher severity = lower adherence
        # Use exponential decay for older violations
        weighted_severity = 0.0
        for (i, v) in enumerate(reverse(record.violations))
            weight = exp(-0.01 * (violation_count - i))  # Decay factor
            weighted_severity += v.severity * weight
        end
        
        # Normalize: 0 violations = 1.0, many severe violations = low score
        doctrine_adherence = exp(-weighted_severity * 0.5)
    end
    
    # Calculate commitment alignment
    if !isempty(record.commitment_records)
        alignment_sum = 0.0
        for comm in record.commitment_records
            alignment = get(comm, "alignment", 0.8)
            alignment_sum += alignment
        end
        commitment_alignment = alignment_sum / length(record.commitment_records)
    end
    
    # Calculate recent violation rate (last 20% of violations or last 20 if fewer)
    recent_violation_rate = 0.1  # Default low
    if length(record.violations) >= 5
        recent_count = max(5, floor(Int, length(record.violations) * 0.2))
        recent_violations = record.violations[end-recent_count+1:end]
        recent_violation_rate = length(recent_violations) / max(1, length(record.violations))
        
        # Weight by severity
        recent_severity = sum(v.severity for v in recent_violations) / length(recent_violations)
        recent_violation_rate = clamp(recent_violation_rate * (0.5 + recent_severity * 0.5), 0.0, 1.0)
    end
    
    # Calculate override frequency
    override_frequency = 0.1  # Default low
    if !isempty(record.overrides)
        # More overrides = higher frequency (worse)
        override_frequency = min(1.0, length(record.overrides) / 50.0)  # 50 overrides = max
    end
    
    # Calculate trend (improving or degrading)
    trend = 0.0
    if length(record.violations) >= 10
        # Compare first half vs second half
        half = div(length(record.violations), 2)
        first_half = record.violations[1:half]
        second_half = record.violations[half+1:end]
        
        first_severity = sum(v.severity for v in first_half) / length(first_half)
        second_severity = sum(v.severity for v in second_half) / length(second_half)
        
        # Positive trend = second half has fewer/milder violations
        trend = clamp(first_severity - second_severity, -1.0, 1.0)
    end
    
    # Compute overall score (weighted average)
    overall = (doctrine_adherence * 0.4 + 
               commitment_alignment * 0.3 + 
               (1.0 - recent_violation_rate) * 0.2 +
               (1.0 - override_frequency) * 0.1)
    
    return ReputationScore(
        clamp(overall, 0.0, 1.0),
        clamp(doctrine_adherence, 0.0, 1.0),
        clamp(commitment_alignment, 0.0, 1.0),
        clamp(recent_violation_rate, 0.0, 1.0),
        clamp(override_frequency, 0.0, 1.0),
        trend,
        now()
    )
end

"""
    Get current reputation status
"""
function get_reputation_status(memory::ReputationMemory)::Dict{String, Any}
    score = memory.record.current_score
    
    return Dict(
        "enabled" => memory.enabled,
        "overall_score" => score.overall_score,
        "doctrine_adherence" => score.doctrine_adherence,
        "commitment_alignment" => score.commitment_alignment,
        "recent_violation_rate" => score.recent_violation_rate,
        "override_frequency" => score.override_frequency,
        "trend" => score.trend,
        "total_violations" => length(memory.record.violations),
        "total_overrides" => length(memory.record.overrides),
        "violation_patterns" => memory.record.violation_patterns,
        "needs_scrutiny" => score.overall_score < memory.scrutiny_threshold,
        "computed_at" => string(score.computed_at)
    )
end

"""
    Apply reputation to confidence
    
    Returns a confidence multiplier based on reputation.
    Lower reputation = more cautious confidence.
"""
function apply_reputation_to_confidence(
    base_confidence::Float32,
    memory::ReputationMemory
)::Float32
    score = memory.record.current_score
    
    # If reputation is high (>= 0.8), no penalty
    # If reputation is low (< 0.4), significant penalty
    if score.overall_score >= 0.8
        return base_confidence
    elseif score.overall_score >= 0.6
        return base_confidence * 0.9  # 10% reduction
    elseif score.overall_score >= 0.4
        return base_confidence * 0.7  # 30% reduction
    else
        return base_confidence * 0.5  # 50% reduction - very cautious
    end
end

"""
    Track alignment between behavior and stated commitments
    
    This is called when the system makes a commitment and later acts.
"""
function track_behavior_commitment_alignment!(
    memory::ReputationMemory,
    commitment_id::String,
    commitment_statement::String,
    actual_behavior::String,
    alignment_score::Float64;  # [0, 1] - how well behavior matched commitment
    context::Dict{String, Any}=Dict{String, Any}()
)
    !memory.enabled && return
    
    record = Dict{String, Any}(
        "commitment_id" => commitment_id,
        "commitment" => commitment_statement,
        "behavior" => actual_behavior,
        "alignment" => alignment_score,
        "timestamp" => now(),
        "context" => context
    )
    
    push!(memory.record.commitment_records, record)
    
    # Keep only last 50 commitment records
    if length(memory.record.commitment_records) > 50
        memory.record.commitment_records = memory.record.commitment_records[end-49:end]
    end
    
    # Recompute score
    memory.record.current_score = compute_reputation_score(memory.record)
end

"""
    Get reputation history for analysis
"""
function get_reputation_history(
    memory::ReputationMemory;
    max_entries::Int=20
)::Vector{Dict{String, Any}}
    history = Dict{String, Any}[]
    
    # Add recent violations
    violations = memory.record.violations[max(1, end-max_entries+1):end]
    for v in violations
        push!(history, Dict(
            "type" => "violation",
            "id" => string(v.id),
            "timestamp" => string(v.timestamp),
            "rule_id" => v.rule_id,
            "rule_type" => v.rule_type,
            "severity" => v.severity,
            "outcome" => v.outcome,
            "cycle" => v.cycle
        ))
    end
    
    # Add recent overrides
    overrides = memory.record.overrides[max(1, end-div(max_entries, 2)+1):end]
    for o in overrides
        push!(history, Dict(
            "type" => "override",
            "id" => string(o.id),
            "timestamp" => string(o.timestamp),
            "rule_id" => o.rule_id,
            "justification" => o.justification[1:min(50, length(o.justification))],
            "severity" => o.severity,
            "cycle" => o.cycle
        ))
    end
    
    # Sort by timestamp (newest first)
    sort!(history, by=h -> get(h, "timestamp", ""), rev=true)
    
    return history[1:min(max_entries, length(history))]
end

"""
    Should require extra scrutiny?
    
    Returns true if the system's reputation is low enough that
    additional review of actions should be triggered.
"""
function should_require_extra_scrutiny(memory::ReputationMemory)::Bool
    !memory.enabled && return false
    
    score = memory.record.current_score
    
    # Always require scrutiny if below threshold
    score.overall_score < memory.scrutiny_threshold && return true
    
    # Require scrutiny if trend is strongly negative
    score.trend < -0.5 && return true
    
    # Require scrutiny if recent violations are spiking
    if length(memory.record.violations) >= 5
        recent_count = max(3, floor(Int, length(memory.record.violations) * 0.2))
        recent = memory.record.violations[end-recent_count+1:end]
        if length(recent) >= 3
            # If recent violations are more severe than average, flag it
            recent_avg = sum(v.severity for v in recent) / length(recent)
            if recent_avg > 0.6
                return true
            end
        end
    end
    
    return false
end

end # module SharedTypes
