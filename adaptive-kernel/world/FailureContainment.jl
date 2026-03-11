# FailureContainment.jl - Failure Containment & Kill-Switch Logic
# 
# This module ensures failures result in reduced autonomy, increased conservatism,
# and mandatory reflection cycles - never silent failure or silent success.
# 
# KEY PRINCIPLES:
# - Failure must result in reduced autonomy
# - Failure must result in increased conservatism
# - Failure must trigger mandatory reflection cycles
# - Never silent failure - all outcomes logged
# - Never silent success - all outcomes validated

module FailureContainment

using Dates
using UUIDs
using Logging

# Import shared types first
include("../types.jl")
using .SharedTypes

# Import WorldInterface types
include("WorldInterface.jl")
using .WorldInterface

# Import AuthorizationPipeline for AuthorizationContext
include("AuthorizationPipeline.jl")
using .AuthorizationPipeline

# Export all public types and functions
export 
    # Enums
    FailureSeverity,
    AutonomyLevel,
    # Types
    EscalationPolicy,
    FailureEvent,
    # Functions
    detect_failure,
    escalate_failure!,
    apply_autonomy_restriction!,
    attempt_autonomy_restoration,
    force_reflection_cycle!,
    check_rate_limit,
    get_rate_limit_status,
    emergency_halt!,
    graceful_degradation!,
    trigger_kill_switch,
    monitor_action_health,
    detect_silent_failure,
    validate_outcome,
    initiate_recovery!,
    test_recovery_ready,
    # Helper functions
    create_default_escalation_policy,
    create_failure_event,
    get_autonomy_level_index,
    get_severity_index,
    # State accessors
    get_current_autonomy,
    get_failure_history,
    get_failure_status

# ============================================================================
# ENUMS - Failure Severity and Autonomy Levels
# ============================================================================

"""
    FailureSeverity - Classification of failure impact levels
    
    - :minor - Small deviation, minor impact
    - :moderate - Noticeable impact, requires attention
    - :major - Significant impact, requires response
    - :critical - Severe impact, requires immediate halt
    - :catastrophic - System integrity threatened
"""
@enum FailureSeverity begin
    FAILURE_MINOR
    FAILURE_MODERATE
    FAILURE_MAJOR
    FAILURE_CRITICAL
    FAILURE_CATASTROPHIC
end

"""
    AutonomyLevel - Current autonomy state of the system
    
    - :full - Full autonomous operation
    - :reduced - Reduced autonomy, more checks
    - :restricted - Limited actions only
    - :minimal - Observation only
    - :halted - Complete halt
"""
@enum AutonomyLevel begin
    AUTONOMY_FULL
    AUTONOMY_REDUCED
    AUTONOMY_RESTRICTED
    AUTONOMY_MINIMAL
    AUTONOMY_HALTED
end

# ============================================================================
# TYPES - EscalationPolicy and FailureEvent
# ============================================================================

"""
    EscalationPolicy - Defines escalation behavior for failures
    
    Fields:
    - failure_threshold::Int - Number of failures before escalation
    - time_window_seconds::Float64 - Time window for counting failures
    - autonomy_reduction::AutonomyLevel - How much to reduce autonomy
    - require_reflection::Bool - Force reflection cycle on failure
    - cooldown_seconds::Float64 - Time before restoration attempt
"""
struct EscalationPolicy
    failure_threshold::Int
    time_window_seconds::Float64
    autonomy_reduction::AutonomyLevel
    require_reflection::Bool
    cooldown_seconds::Float64
    
    function EscalationPolicy(
        failure_threshold::Int=3;
        time_window_seconds::Float64=300.0,
        autonomy_reduction::AutonomyLevel=AUTONOMY_REDUCED,
        require_reflection::Bool=true,
        cooldown_seconds::Float64=60.0
    )
        return new(
            failure_threshold,
            time_window_seconds,
            autonomy_reduction,
            require_reflection,
            cooldown_seconds
        )
    end
end

"""
    FailureEvent - Record of a failure occurrence
    
    Fields:
    - id::UUID - Unique identifier
    - timestamp::DateTime - When failure occurred
    - severity::FailureSeverity - Impact level
    - action_id::UUID - Associated action
    - failure_type::Symbol - Category: :authorization, :execution, :doctrine, :drift, :reputation, :unknown
    - error_message::String - Description of failure
    - side_effects::Vector{String} - Unintended consequences
    - autonomy_impact::AutonomyLevel - Resulting autonomy reduction
"""
struct FailureEvent
    id::UUID
    timestamp::DateTime
    severity::FailureSeverity
    action_id::UUID
    failure_type::Symbol
    error_message::String
    side_effects::Vector{String}
    autonomy_impact::AutonomyLevel
    
    function FailureEvent(
        severity::FailureSeverity,
        action_id::UUID;
        failure_type::Symbol=:unknown,
        error_message::String="",
        side_effects::Vector{String}=String[],
        autonomy_impact::AutonomyLevel=AUTONOMY_FULL
    )
        return new(
            uuid4(),
            now(),
            severity,
            action_id,
            failure_type,
            error_message,
            side_effects,
            autonomy_impact
        )
    end
end

# ============================================================================
# FAILURE DETECTION - Core detection logic
# ============================================================================

"""
    detect_failure(action::WorldAction, result::ActionResult) -> FailureSeverity
    
Analyze action result for failure indicators and assess severity.
Checks for silent failures (unlogged errors) and silent successes (unvalidated results).

# Arguments
- `action::WorldAction`: The action that was executed
- `result::ActionResult`: The result of the action execution

# Returns
- `FailureSeverity`: The assessed severity level
"""
function detect_failure(action::WorldAction, result::ActionResult)::FailureSeverity
    # Check for explicit failure status
    if result.status == :failed
        # Check for silent failure indicators
        if isempty(result.actual_outcome) && isempty(result.error_message)
            # Silent failure - no outcome logged
            @warn "Silent failure detected" action_id=action.id
            return FAILURE_MAJOR
        end
        
        # Analyze based on prediction error
        if abs(result.prediction_error) > 0.8
            return FAILURE_CRITICAL
        elseif abs(result.prediction_error) > 0.5
            return FAILURE_MAJOR
        elseif abs(result.prediction_error) > 0.3
            return FAILURE_MODERATE
        else
            return FAILURE_MINOR
        end
    elseif result.status == :blocked
        # Blocked actions indicate a problem but not necessarily a failure
        return FAILURE_MINOR
    elseif result.status == :aborted
        return FAILURE_MODERATE
    end
    
    # Check for silent success (unvalidated results)
    if result.status == :success
        if isempty(result.actual_outcome)
            @warn "Silent success detected - no outcome validation" action_id=action.id
            return FAILURE_MINOR
        end
        
        # High prediction error even on success indicates issues
        if abs(result.prediction_error) > 0.7
            return FAILURE_MODERATE
        elseif abs(result.prediction_error) > 0.5
            return FAILURE_MINOR
        end
    end
    
    # Check for negative side effects
    if !isempty(result.side_effects)
        side_effect_severity = length(result.side_effects) > 3 ? FAILURE_MAJOR : FAILURE_MINOR
        return max(FAILURE_MINOR, side_effect_severity)
    end
    
    return FAILURE_MINOR
end

"""
    get_severity_index(severity::FailureSeverity) -> Int
Get numeric index for severity comparison.
"""
function get_severity_index(severity::FailureSeverity)::Int
    return Int(severity)
end

"""
    get_autonomy_level_index(level::AutonomyLevel) -> Int
Get numeric index for autonomy level comparison (lower = more restricted).
"""
function get_autonomy_level_index(level::AutonomyLevel)::Int
    return Int(level)
end

"""
    create_default_escalation_policy() -> EscalationPolicy
Create a default escalation policy with sensible defaults.
"""
function create_default_escalation_policy()::EscalationPolicy
    return EscalationPolicy(
        3;                                    # 3 failures before escalation
        time_window_seconds=300.0,            # 5 minute window
        autonomy_reduction=AUTONOMY_REDUCED,   # Reduce by one level
        require_reflection=true,              # Always require reflection
        cooldown_seconds=60.0                # 1 minute cooldown
    )
end

"""
    create_failure_event(severity::FailureSeverity, action_id::UUID; kwargs...) -> FailureEvent
Convenience constructor for FailureEvent with keyword arguments.
"""
function create_failure_event(
    severity::FailureSeverity,
    action_id::UUID;
    failure_type::Symbol=:unknown,
    error_message::String="",
    side_effects::Vector{String}=String[]
)::FailureEvent
    return FailureEvent(
        severity,
        action_id;
        failure_type=failure_type,
        error_message=error_message,
        side_effects=side_effects
    )
end

"""
    get_current_autonomy() -> AutonomyLevel

Get the current autonomy level from the failure tracker.
"""
function get_current_autonomy()::AutonomyLevel
    return _failure_tracker.current_autonomy
end

"""
    get_failure_history() -> Vector{FailureEvent}

Get all recorded failure events.
"""
function get_failure_history()::Vector{FailureEvent}
    return copy(_failure_tracker.recent_failures)
end

"""
    get_failure_status() -> Dict

Get the current failure containment status.
"""
function get_failure_status()::Dict
    return Dict(
        "current_autonomy" => string(_failure_tracker.current_autonomy),
        "recent_failure_count" => length(_failure_tracker.recent_failures),
        "reflection_required" => _failure_tracker.reflection_required,
        "reflection_completed" => _failure_tracker.reflection_completed,
        "last_autonomy_change" => string(_failure_tracker.last_autonomy_change)
    )
end

# ============================================================================
# ESCALATION LOGIC - Process failures through escalation policy
# ============================================================================

# Mutable state for tracking failures (would be part of KernelState in production)
mutable struct FailureTracker
    recent_failures::Vector{FailureEvent}
    current_autonomy::AutonomyLevel
    last_autonomy_change::DateTime
    reflection_required::Bool
    reflection_completed::Bool
    rate_limits::Dict{Symbol, Vector{DateTime}}
    escalation_policy::EscalationPolicy
    
    FailureTracker() = new(
        FailureEvent[],
        AUTONOMY_FULL,
        now(),
        false,
        false,
        Dict{Symbol, Vector{DateTime}}(),
        create_default_escalation_policy()
    )
end

# Global tracker instance (in production, this would be in KernelState)
const _failure_tracker = FailureTracker()

"""
    escalate_failure!(kernel::KernelState, event::FailureEvent)
    
Process failure through escalation policy, reduce autonomy, trigger mandatory reflection.
"""
function escalate_failure!(kernel::KernelState, event::FailureEvent)
    @info "Escalating failure event" 
          event_id=event.id 
          severity=event.severity 
          failure_type=event.failure_type
    
    # Add to recent failures
    push!(_failure_tracker.recent_failures, event)
    
    # Clean up old failures outside time window
    policy = _failure_tracker.escalation_policy
    cutoff_time = now() - Dates.Second(policy.time_window_seconds)
    _failure_tracker.recent_failures = filter(
        f -> f.timestamp > cutoff_time,
        _failure_tracker.recent_failures
    )
    
    # Count failures in window
    failure_count = length(_failure_tracker.recent_failures)
    
    # Check if we need to escalate
    if failure_count >= policy.failure_threshold
        @warn "Failure threshold reached" 
              count=failure_count 
              threshold=policy.failure_threshold
        
        # Determine new autonomy level
        current_idx = get_autonomy_level_index(_failure_tracker.current_autonomy)
        reduction_idx = get_autonomy_level_index(policy.autonomy_reduction)
        new_idx = min(current_idx + reduction_idx, length(instances(AutonomyLevel)) - 1)
        
        new_autonomy = AutonomyLevel(new_idx)
        
        # Apply autonomy restriction
        apply_autonomy_restriction!(kernel, new_autonomy)
        
        # Update tracker state
        _failure_tracker.last_autonomy_change = now()
        
        # Require reflection if policy says so
        if policy.require_reflection
            force_reflection_cycle!(kernel, "Escalation policy triggered: $(failure_count) failures in $(policy.time_window_seconds)s")
        end
    else
        # Even below threshold, log the failure
        @info "Failure recorded" failure_count=failure_count threshold=policy.failure_threshold
    end
    
    # Log failure to kernel's episodic memory
    _log_failure_to_kernel(kernel, event)
end

"""
    _log_failure_to_kernel - Internal helper to log failure to kernel
"""
function _log_failure_to_kernel(kernel::KernelState, event::FailureEvent)
    # Record in doctrine violations for audit
    # This would integrate with the existing reputation/drift systems
    @debug "Failure logged to kernel state" event_id=event.id severity=event.severity
end

# ============================================================================
# AUTONOMY MANAGEMENT - Control system autonomy levels
# ============================================================================

"""
    apply_autonomy_restriction!(kernel::KernelState, level::AutonomyLevel)
    
Reduce system autonomy, log restriction, update self-model conservative mode.
"""
function apply_autonomy_restriction!(kernel::KernelState, level::AutonomyLevel)
    old_level = _failure_tracker.current_autonomy
    
    # Don't escalate beyond halted
    if level == AUTONOMY_HALTED || _failure_tracker.current_autonomy == AUTONOMY_HALTED
        _failure_tracker.current_autonomy = AUTONOMY_HALTED
    else
        _failure_tracker.current_autonomy = level
    end
    
    @info "Autonomy restricted" 
          old_level=old_level 
          new_level=_failure_tracker.current_autonomy
    
    # Enable conservative mode in self-model
    kernel.self_model.risk.conservative_mode = true
    
    # Log the restriction
    @info "Conservative mode enabled due to autonomy restriction"
end

"""
    attempt_autonomy_restoration(kernel::KernelState) -> Bool
    
Check if cooldown has passed, verify reflection completed, test stability.
Restore autonomy if safe.
"""
function attempt_autonomy_restoration(kernel::KernelState)::Bool
    policy = _failure_tracker.escalation_policy
    
    # Check cooldown
    time_since_change = now() - _failure_tracker.last_autonomy_change
    if time_since_change < Dates.Second(policy.cooldown_seconds)
        @info "Cooldown period not elapsed" 
              elapsed=time_since_change 
              required=policy.cooldown_seconds
        return false
    end
    
    # Check if reflection is required but not completed
    if _failure_tracker.reflection_required && !_failure_tracker.reflection_completed
        @info "Reflection required but not completed"
        return false
    end
    
    # Test system stability
    if !_test_stability(kernel)
        @info "System stability test failed"
        return false
    end
    
    # Attempt to restore autonomy
    current_idx = get_autonomy_level_index(_failure_tracker.current_autonomy)
    if current_idx > 0
        new_level = AutonomyLevel(current_idx - 1)
        _failure_tracker.current_autonomy = new_level
        
        # If we're back to full autonomy, disable conservative mode
        if new_level == AUTONOMY_FULL
            kernel.self_model.risk.conservative_mode = false
            @info "Full autonomy restored - conservative mode disabled"
        else
            @info "Autonomy partially restored" new_level=new_level
        end
        
        _failure_tracker.last_autonomy_change = now()
        return true
    end
    
    return false
end

"""
    _test_stability - Internal stability test
"""
function _test_stability(kernel::KernelState)::Bool
    # Check for recent failures
    recent_failures = filter(
        f -> f.timestamp > now() - Dates.Minute(5),
        _failure_tracker.recent_failures
    )
    
    # If too many recent failures, not stable
    if length(recent_failures) > 2
        return false
    end
    
    # Check kernel confidence
    confidence = get(kernel.self_metrics, "confidence", 0.8)
    if confidence < 0.5
        return false
    end
    
    return true
end

"""
    force_reflection_cycle!(kernel::KernelState, reason::String)
    
Trigger mandatory reflection, block further actions until complete, log requirement.
"""
function force_reflection_cycle!(kernel::KernelState, reason::String)
    _failure_tracker.reflection_required = true
    _failure_tracker.reflection_completed = false
    
    @warn "Mandatory reflection triggered" reason=reason
    
    # In production, this would block the kernel's action execution
    # until reflection is complete. For now, we set the flag.
    kernel.self_metrics["reflection_required"] = 1.0
    
    # Log the reflection requirement
    @info "Reflection required: $reason"
end

# ============================================================================
# RATE LIMITING - Prevent action flooding
# ============================================================================

"""
    check_rate_limit(kernel::KernelState, action_type::Symbol) -> Bool
    
Track actions per time window, prevent action flooding, apply per-action-type limits.
"""
function check_rate_limit(kernel::KernelState, action_type::Symbol)::Bool
    # Default rate limit: 10 actions per minute per type
    max_actions = 10
    window_seconds = 60.0
    
    # Initialize if not present
    if !haskey(_failure_tracker.rate_limits, action_type)
        _failure_tracker.rate_limits[action_type] = DateTime[]
    end
    
    # Clean up old entries
    cutoff = now() - Dates.Second(window_seconds)
    _failure_tracker.rate_limits[action_type] = filter(
        t -> t > cutoff,
        _failure_tracker.rate_limits[action_type]
    )
    
    # Check limit
    current_count = length(_failure_tracker.rate_limits[action_type])
    
    if current_count >= max_actions
        @warn "Rate limit exceeded" action_type=action_type count=current_count max=max_actions
        return false
    end
    
    # Record this action
    push!(_failure_tracker.rate_limits[action_type], now())
    
    return true
end

"""
    get_rate_limit_status(kernel::KernelState) -> Dict
    
Return current rate limit status, show remaining capacity.
"""
function get_rate_limit_status(kernel::KernelState)::Dict{Symbol, Any}
    status = Dict{Symbol, Any}()
    max_actions = 10
    window_seconds = 60.0
    
    for (action_type, timestamps) in _failure_tracker.rate_limits
        cutoff = now() - Dates.Second(window_seconds)
        current = length(filter(t -> t > cutoff, timestamps))
        status[action_type] = Dict(
            "current" => current,
            "max" => max_actions,
            "available" => max(0, max_actions - current),
            "percentage" => current / max_actions
        )
    end
    
    return status
end

# ============================================================================
# KILL-SWITCH FUNCTIONS - Emergency response mechanisms
# ============================================================================

"""
    emergency_halt!(kernel::KernelState, reason::String) -> Nothing
    
Immediate system halt, block all actions, log emergency, set autonomy to :halted.
"""
function emergency_halt!(kernel::KernelState, reason::String)::Nothing
    @error "EMERGENCY HALT TRIGGERED" reason=reason
    
    # Set autonomy to halted
    _failure_tracker.current_autonomy = AUTONOMY_HALTED
    _failure_tracker.last_autonomy_change = now()
    
    # Enable maximum conservative mode
    kernel.self_model.risk.conservative_mode = true
    kernel.self_model.risk.max_acceptable_risk *= 0.1  # Reduce risk tolerance by 90%
    
    # Block all actions by requiring constant reflection
    _failure_tracker.reflection_required = true
    _failure_tracker.reflection_completed = false
    
    # Log emergency
    @error "System halted - all actions blocked" reason=reason timestamp=now()
    
    return nothing
end

"""
    graceful_degradation!(kernel::KernelState, reason::String)
    
Reduce to minimal autonomy, preserve core functions, enable observation only,
allow recovery.
"""
function graceful_degradation!(kernel::KernelState, reason::String)
    @warn "Graceful degradation initiated" reason=reason
    
    # Reduce to minimal autonomy
    _failure_tracker.current_autonomy = AUTONOMY_MINIMAL
    _failure_tracker.last_autonomy_change = now()
    
    # Enable conservative mode
    kernel.self_model.risk.conservative_mode = true
    kernel.self_model.risk.max_acceptable_risk *= 0.5  # Reduce risk tolerance by 50%
    
    # Require reflection before any further action
    force_reflection_cycle!(kernel, "Graceful degradation: $reason")
    
    @info "System operating in minimal autonomy mode"
end

"""
    trigger_kill_switch(kernel::KernelState, condition::Symbol) -> Bool
    
Check kill-switch conditions and trigger appropriate response.
Conditions: :critical_failure, :drift_critical, :reputation_failed, :doctrine_violated
"""
function trigger_kill_switch(kernel::KernelState, condition::Symbol)::Bool
    @info "Kill-switch condition check" condition=condition
    
    success = false
    
    if condition == :critical_failure
        # Critical failure - full halt
        emergency_halt!(kernel, "Critical failure: $condition")
        success = true
        
    elseif condition == :drift_critical
        # Check drift severity
        drift_severity = get_drift_severity(kernel.drift_detector)
        if drift_severity == DRIFT_CRITICAL
            emergency_halt!(kernel, "Critical identity drift detected")
            success = true
        else
            # Less severe - just degrade gracefully
            graceful_degradation!(kernel, "Significant identity drift: $drift_severity")
            success = true
        end
        
    elseif condition == :reputation_failed
        # Check reputation score
        rep_score = compute_reputation_score(kernel.reputation_memory)
        if rep_score < 0.3
            emergency_halt!(kernel, "Reputation score critically low: $rep_score")
            success = true
        else
            graceful_degradation!(kernel, "Reputation concerns: $rep_score")
            success = true
        end
        
    elseif condition == :doctrine_violated
        # Check for doctrine violations
        violations = kernel.doctrine_enforcer.violations
        recent_violations = filter(
            v -> v.timestamp > now() - Dates.Minute(5),
            violations
        )
        
        if length(recent_violations) >= 3
            emergency_halt!(kernel, "Multiple doctrine violations: $(length(recent_violations))")
            success = true
        else
            graceful_degradation!(kernel, "Doctrine violation detected")
            success = true
        end
        
    else
        @warn "Unknown kill-switch condition" condition=condition
    end
    
    return success
end

# ============================================================================
# MONITORING FUNCTIONS - Health checks and failure detection
# ============================================================================

"""
    monitor_action_health(kernel::KernelState, result::ActionResult) -> Dict
    
Check action health indicators, detect degradation patterns, predict potential failures.
"""
function monitor_action_health(kernel::KernelState, result::ActionResult)::Dict{String, Any}
    health = Dict{String, Any}()
    
    # Check prediction error trend
    health["prediction_error"] = result.prediction_error
    health["error_severity"] = if abs(result.prediction_error) > 0.7
        "high"
    elseif abs(result.prediction_error) > 0.4
        "medium"
    else
        "low"
    end
    
    # Check execution time
    health["execution_time_ms"] = result.execution_time_ms
    health["slow_execution"] = result.execution_time_ms > 5000  # > 5 seconds
    
    # Check side effects
    health["side_effect_count"] = length(result.side_effects)
    health["has_side_effects"] = !isempty(result.side_effects)
    
    # Check reversal status
    health["reversal_attempted"] = result.reversal_attempted
    health["reversal_success"] = result.reversal_success
    
    # Overall health score
    issues = 0
    issues += abs(result.prediction_error) > 0.5 ? 1 : 0
    issues += result.execution_time_ms > 5000 ? 1 : 0
    issues += length(result.side_effects) > 2 ? 1 : 0
    issues += (result.reversal_attempted && result.reversal_success == false) ? 1 : 0
    
    health["health_score"] = max(0, 1.0 - (issues * 0.25))
    health["status"] = if health["health_score"] > 0.75
        "healthy"
    elseif health["health_score"] > 0.5
        "degraded"
    else
        "unhealthy"
    end
    
    return health
end

"""
    detect_silent_failure(kernel::KernelState) -> Vector{FailureEvent}
    
Scan for unlogged errors, check for unvalidated successes, report any silent failures.
"""
function detect_silent_failure(kernel::KernelState)::Vector{FailureEvent}
    silent_failures = FailureEvent[]
    
    # Check recent actions in episodic memory for silent failures
    recent_events = filter(
        e -> e.timestamp > now() - Dates.Minute(10),
        kernel.episodic_memory
    )
    
    for event in recent_events
        # Check if failed action has no error message (silent failure)
        if !event.success && isempty(event.effect)
            push!(silent_failures, create_failure_event(
                FAILURE_MINOR,
                UUID(event.action_id);
                failure_type=:execution,
                error_message="Silent failure: no outcome recorded"
            ))
        end
        
        # Check for silent success (high prediction error on success)
        if event.success && event.prediction_error > 0.6
            push!(silent_failures, create_failure_event(
                FAILURE_MINOR,
                UUID(event.action_id);
                failure_type=:execution,
                error_message="Silent success: high prediction error ($(event.prediction_error))"
            ))
        end
    end
    
    if !isempty(silent_failures)
        @warn "Silent failures detected" count=length(silent_failures)
    end
    
    return silent_failures
end

"""
    validate_outcome(result::ActionResult) -> Bool
    
Validate outcome matches expected, check side effects are acceptable, ensure proper logging.
"""
function validate_outcome(result::ActionResult)::Bool
    # Check if outcome is logged
    if isempty(result.actual_outcome)
        @warn "Outcome not validated: empty actual_outcome"
        return false
    end
    
    # Check for excessive side effects
    if length(result.side_effects) > 5
        @warn "Too many side effects detected" count=length(result.side_effects)
        return false
    end
    
    # Check for failed reversal
    if result.reversal_attempted && result.reversal_success == false
        @warn "Failed reversal detected - outcome may not be acceptable"
        return false
    end
    
    # Check prediction error is reasonable
    if abs(result.prediction_error) > 0.9
        @warn "Extreme prediction error - outcome may be invalid" error=result.prediction_error
        return false
    end
    
    return true
end

# ============================================================================
# RECOVERY FUNCTIONS - Recovery management
# ============================================================================

"""
    initiate_recovery!(kernel::KernelState, failure::FailureEvent)
    
Create recovery plan, set recovery milestones, enable gradual restoration.
"""
function initiate_recovery!(kernel::KernelState, failure::FailureEvent)
    @info "Initiating recovery from failure" 
          failure_id=failure.id 
          severity=failure.severity
    
    # Set recovery milestones based on severity
    if failure.severity == FAILURE_CATASTROPHIC
        # Maximum restriction
        _failure_tracker.current_autonomy = AUTONOMY_HALTED
    elseif failure.severity == FAILURE_CRITICAL
        _failure_tracker.current_autonomy = AUTONOMY_MINIMAL
    elseif failure.severity == FAILURE_MAJOR
        _failure_tracker.current_autonomy = AUTONOMY_RESTRICTED
    else
        _failure_tracker.current_autonomy = AUTONOMY_REDUCED
    end
    
    # Always require reflection for recovery
    force_reflection_cycle!(kernel, "Recovery from $(failure.severity) failure")
    
    # Update cooldown
    _failure_tracker.last_autonomy_change = now()
    
    # Set conservative mode
    kernel.self_model.risk.conservative_mode = true
    
    @info "Recovery initiated" autonomy=_failure_tracker.current_autonomy
end

"""
    test_recovery_ready(kernel::KernelState) -> Bool
    
Run diagnostic checks, verify stability, confirm safe to proceed.
"""
function test_recovery_ready(kernel::KernelState)::Bool
    # Test 1: No recent critical failures
    recent_failures = filter(
        f -> f.timestamp > now() - Dates.Minute(10),
        _failure_tracker.recent_failures
    )
    
    critical_failures = filter(f -> f.severity >= FAILURE_CRITICAL, recent_failures)
    if !isempty(critical_failures)
        @info "Not ready: recent critical failures" count=length(critical_failures)
        return false
    end
    
    # Test 2: Reflection completed if required
    if _failure_tracker.reflection_required && !_failure_tracker.reflection_completed
        @info "Not ready: reflection not completed"
        return false
    end
    
    # Test 3: Stability check
    if !_test_stability(kernel)
        @info "Not ready: stability test failed"
        return false
    end
    
    # Test 4: Confidence above threshold
    confidence = get(kernel.self_metrics, "confidence", 0.0)
    if confidence < 0.6
        @info "Not ready: low confidence" confidence=confidence
        return false
    end
    
    # Test 5: Rate limits not exhausted
    for (action_type, timestamps) in _failure_tracker.rate_limits
        recent = filter(t -> t > now() - Dates.Minute(1), timestamps)
        if length(recent) >= 10
            @info "Not ready: rate limit exhausted" action_type=action_type
            return false
        end
    end
    
    @info "Recovery ready: all checks passed"
    return true
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_failure_summary() -> Dict
Get a summary of the current failure containment state.
"""
function get_failure_summary()::Dict{String, Any}
    return Dict(
        "current_autonomy" => string(_failure_tracker.current_autonomy),
        "reflection_required" => _failure_tracker.reflection_required,
        "reflection_completed" => _failure_tracker.reflection_completed,
        "recent_failure_count" => length(_failure_tracker.recent_failures),
        "cooldown_remaining" => max(0, _failure_tracker.escalation_policy.cooldown_seconds - 
            Dates.value(now() - _failure_tracker.last_autonomy_change) / 1000)
    )
end

end # module FailureContainment
