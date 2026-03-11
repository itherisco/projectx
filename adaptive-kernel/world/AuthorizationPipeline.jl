# AuthorizationPipeline.jl - Action Authorization Pipeline for Adaptive Kernel
# 
# This pipeline ensures every action passes through proper authorization checks
# before execution. It implements a fail-closed security model where actions are
# blocked by default and only permitted after passing all authorization stages.

module AuthorizationPipeline

using Dates
using UUIDs
using JSON

# Import types from SharedTypes and WorldInterface
import ..SharedTypes:
    KernelState,
    DoctrineEnforcer,
    SelfModel,
    DriftDetector,
    ReputationMemory,
    WorldState,
    ActionProposal,
    PermissionHandler,
    PermissionResult,
    check_permission,
    create_permission_handler,
    is_registered_capability,
    check_doctrine_compliance,
    RiskProfile,
    DriftSeverity,
    DriftAlert,
    ReputationScore,
    ConfidenceCalibration

import ..WorldInterface:
    WorldAction,
    ActionResult,
    execute_world_action,
    simulate_action,
    authorize_action,
    record_action_result!,
    assess_action_risk

# Export public types and functions
export AuthorizationStage,
       AuthorizationContext,
       propose_action,
       simulate_action,
       check_doctrine,
       assess_risk,
       project_drift,
       evaluate_reputation,
       authorize,
       execute_pipeline,
       record_outcome!,
       run_authorization_pipeline,
       get_pipeline_status,
       should_continue_pipeline,
       emergency_stop!

# ============================================================================
# AUTHORIZATION STAGE - Track pipeline progress
# ============================================================================

"""
    AuthorizationStage - Enum representing each stage of the authorization pipeline.
    
    The pipeline progresses through these stages in order:
    - :proposed - Action has been proposed
    - :simulated - Action has been simulated
    - :doctrine_checked - Doctrine compliance has been verified
    - :risk_assessed - Risk assessment has been completed
    - :drift_projected - Identity drift projection has been calculated
    - :reputation_evaluated - Reputation impact has been evaluated
    - :authorized - Final authorization decision has been made
    - :executed - Action has been executed
    - :observed - Execution result has been observed
    - :recorded - Result has been recorded
"""
@enum AuthorizationStage begin
    STAGE_PROPOSED
    STAGE_SIMULATED
    STAGE_DOCTRINE_CHECKED
    STAGE_RISK_ASSESSED
    STAGE_DRIFT_PROJECTED
    STAGE_REPUTATION_EVALUATED
    STAGE_AUTHORIZED
    STAGE_EXECUTED
    STAGE_OBSERVED
    STAGE_RECORDED
end

# Stage name mappings for logging
const STAGE_NAMES = Dict(
    STAGE_PROPOSED => "proposed",
    STAGE_SIMULATED => "simulated",
    STAGE_DOCTRINE_CHECKED => "doctrine_checked",
    STAGE_RISK_ASSESSED => "risk_assessed",
    STAGE_DRIFT_PROJECTED => "drift_projected",
    STAGE_REPUTATION_EVALUATED => "reputation_evaluated",
    STAGE_AUTHORIZED => "authorized",
    STAGE_EXECUTED => "executed",
    STAGE_OBSERVED => "observed",
    STAGE_RECORDED => "recorded"
)

"""
    stage_to_symbol - Convert AuthorizationStage to Symbol for Dict keys
"""
stage_to_symbol(stage::AuthorizationStage)::Symbol = Symbol(STAGE_NAMES[stage])

"""
    symbol_to_stage - Convert Symbol to AuthorizationStage
"""
symbol_to_stage(sym::Symbol)::AuthorizationStage = begin
    for (stage, name) in STAGE_NAMES
        if Symbol(name) == sym
            return stage
        end
    end
    error("Unknown stage symbol: $sym")
end

# ============================================================================
# AUTHORIZATION CONTEXT - Holds all authorization state
# ============================================================================

"""
    AuthorizationContext - Complete state container for action authorization.
    
    This struct tracks all information gathered during the authorization
    pipeline, including results from each stage, timestamps, and the final
    authorization decision.
    
    Fields:
    - action: The WorldAction being authorized
    - current_stage: Current position in the pipeline
    - doctrine_result: Result from doctrine compliance check
    - risk_score: Calculated risk score
    - drift_projection: Projected identity drift impact
    - reputation_impact: Impact on system reputation
    - simulation_result: Results from action simulation
    - authorization_decision: Final permission decision
    - failure_reason: Reason for denial if blocked
    - stage_timestamps: Dict mapping each stage to when it was completed
"""
mutable struct AuthorizationContext
    action::WorldAction
    current_stage::AuthorizationStage
    doctrine_result::Union{Nothing, PermissionResult}
    risk_score::Union{Nothing, Float64}
    drift_projection::Union{Nothing, Dict}
    reputation_impact::Union{Nothing, Float64}
    simulation_result::Union{Nothing, Dict}
    authorization_decision::Union{Nothing, PermissionResult}
    failure_reason::Union{Nothing, String}
    stage_timestamps::Dict{Symbol, DateTime}
    
    function AuthorizationContext(action::WorldAction)
        return new(
            action,
            STAGE_PROPOSED,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            Dict{Symbol, DateTime}()
        )
    end
end

# ============================================================================
# PIPELINE STAGE 1: PROPOSE ACTION
# ============================================================================

"""
    propose_action - Initialize authorization context for a new action.
    
    This is the entry point for the authorization pipeline. It creates
    the AuthorizationContext and records the initial proposal timestamp.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: Action to propose for authorization
    
    # Returns
    - `AuthorizationContext`: Initialized authorization context
"""
function propose_action(kernel::KernelState, action::WorldAction)::AuthorizationContext
    @info "Action proposed for authorization" 
          action_id=action.id 
          intent=action.intent 
          action_type=action.action_type
    
    ctx = AuthorizationContext(action)
    ctx.stage_timestamps[:proposed] = now()
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 2: SIMULATE ACTION
# ============================================================================

"""
    simulate_action - Simulate the action to predict outcomes.
    
    Runs the action through WorldInterface simulation to predict
    what would happen if the action were executed.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with simulation results
"""
function simulate_action(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Simulating action" action_id=ctx.action.id
    
    # Call WorldInterface.simulate_action
    simulation_result = simulate_action(kernel, ctx.action)
    ctx.simulation_result = simulation_result
    ctx.current_stage = STAGE_SIMULATED
    ctx.stage_timestamps[:simulated] = now()
    
    @info "Simulation complete" 
          action_id=ctx.action.id 
          success_prob=get(simulation_result, "success_probability", 0.0)
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 3: CHECK DOCTRINE
# ============================================================================

"""
    check_doctrine - Verify action complies with Core Doctrine.
    
    Runs the action through the DoctrineEnforcer to check for any
    violations of the kernel's immutable principles.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with doctrine check results
"""
function check_doctrine(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Checking doctrine compliance" action_id=ctx.action.id
    
    # Convert WorldAction to ActionProposal for doctrine check
    proposal = ActionProposal(
        isempty(ctx.action.required_capabilities) ? "unknown" : first(ctx.action.required_capabilities),
        0.8f0,
        0.1f0,
        1.0f0,
        string(ctx.action.risk_class),
        ctx.action.intent
    )
    
    context = Dict{String, Any}(
        "action_type" => ctx.action.action_type,
        "parameters" => ctx.action.parameters,
        "intent" => ctx.action.intent
    )
    
    # Run doctrine compliance check
    compliant, violation = check_doctrine_compliance(kernel.doctrine_enforcer, proposal, context)
    
    if compliant
        ctx.doctrine_result = PERMISSION_GRANTED
        @info "Doctrine check passed" action_id=ctx.action.id
    else
        ctx.doctrine_result = PERMISSION_DENIED
        ctx.failure_reason = violation !== nothing ? 
            "Doctrine violation: $(violation.rule_id)" : 
            "Unknown doctrine violation"
        @warn "Doctrine check failed" 
              action_id=ctx.action.id 
              reason=ctx.failure_reason
    end
    
    ctx.current_stage = STAGE_DOCTRINE_CHECKED
    ctx.stage_timestamps[:doctrine_checked] = now()
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 4: ASSESS RISK
# ============================================================================

"""
    assess_risk - Calculate and evaluate action risk.
    
    Uses the system's self-model RiskProfile to assess how risky
    the action is, applying conservative_mode adjustments if active.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with risk assessment
"""
function assess_risk(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Assessing action risk" action_id=ctx.action.id
    
    # HCB PROTOCOL: owner_explicit removed. Cryptographic verification handled by Rust shell.
    # Julia performs full risk assessment on all actions regardless.
    # The HCB Protocol ensures hardware-level authorization before actions reach Julia.
    # All actions go through complete authorization pipeline - no bypasses.
    
    # Get risk score from WorldInterface
    risk_score = assess_action_risk(ctx.action, kernel.self_model)
    ctx.risk_score = risk_score
    
    # Get max acceptable risk from RiskProfile
    max_acceptable_risk = kernel.self_model.risk.max_acceptable_risk
    
    # Apply conservative mode adjustment if active
    if kernel.self_model.risk.conservative_mode
        # In conservative mode, reduce the effective max acceptable risk
        adjusted_max = max_acceptable_risk * 0.5
        @info "Conservative mode active - adjusted threshold" 
              original_threshold=max_acceptable_risk 
              adjusted_threshold=adjusted_max
        
        if risk_score > adjusted_max
            ctx.failure_reason = ctx.failure_reason !== nothing ? 
                ctx.failure_reason : 
                "Risk score ($risk_score) exceeds conservative threshold ($adjusted_max)"
        end
    else
        # Normal mode - check against unadjusted threshold
        if risk_score > max_acceptable_risk
            ctx.failure_reason = ctx.failure_reason !== nothing ? 
                ctx.failure_reason : 
                "Risk score ($risk_score) exceeds acceptable threshold ($max_acceptable_risk)"
        end
    end
    
    ctx.current_stage = STAGE_RISK_ASSESSED
    ctx.stage_timestamps[:risk_assessed] = now()
    
    @info "Risk assessment complete" 
          action_id=ctx.action.id 
          risk_score=risk_score
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 5: PROJECT DRIFT
# ============================================================================

"""
    project_drift - Project potential identity drift from action.
    
    Analyzes the action's potential impact on the 6 identity anchors
    and calculates worst-case drift severity.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with drift projection
"""
function project_drift(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Projecting identity drift" action_id=ctx.action.id
    
    # HCB PROTOCOL: owner_explicit removed. Cryptographic verification handled by Rust shell.
    # Julia performs full drift projection on all actions regardless.
    # All actions go through complete identity anchor analysis - no bypasses.
    
    drift_detector = kernel.drift_detector
    anchors = drift_detector.baseline.anchors
    
    # Analyze action impact on each identity anchor
    anchor_impacts = Dict{String, Dict}()
    worst_severity = DRIFT_NONE
    
    for anchor in anchors
        # Estimate potential drift based on action characteristics
        impact = estimate_anchor_impact(ctx.action, anchor)
        anchor_impacts[anchor.id] = Dict(
            "name" => anchor.name,
            "current_value" => anchor.baseline_value,
            "projected_drift" => impact,
            "severity" => impact_to_severity(impact, anchor.tolerance)
        )
        
        # Track worst severity
        severity = impact_to_severity(impact, anchor.tolerance)
        if severity > worst_severity
            worst_severity = severity
        end
    end
    
    # Build drift projection dict
    ctx.drift_projection = Dict(
        "anchor_impacts" => anchor_impacts,
        "worst_severity" => string(worst_severity),
        "worst_severity_enum" => worst_severity,
        "critical" => (worst_severity == DRIFT_CRITICAL)
    )
    
    # If critical drift projected, set failure reason
    if worst_severity == DRIFT_CRITICAL
        ctx.failure_reason = ctx.failure_reason !== nothing ? 
            ctx.failure_reason : 
            "Projected critical identity drift"
    end
    
    ctx.current_stage = STAGE_DRIFT_PROJECTED
    ctx.stage_timestamps[:drift_projected] = now()
    
    @info "Drift projection complete" 
          action_id=ctx.action.id 
          worst_severity=string(worst_severity)
    
    return ctx
end

"""
    estimate_anchor_impact - Estimate how much an action would drift an anchor.
"""
function estimate_anchor_impact(action::WorldAction, anchor)::Float64
    # Base drift from action risk class
    risk_drift = if action.risk_class == :critical
        0.3
    elseif action.risk_class == :high
        0.2
    elseif action.risk_class == :medium
        0.1
    else
        0.0
    end
    
    # Check if action intent relates to anchor behavioral indicators
    action_str = lowercase(action.intent * " " * string(action.action_type))
    indicator_match = 0.0
    
    for indicator in anchor.behavioral_indicators
        if occursin(indicator, action_str)
            indicator_match = anchor.weight * 0.3
            break
        end
    end
    
    # Combine factors
    total_impact = risk_drift + indicator_match
    
    return clamp(total_impact, 0.0, 1.0)
end

"""
    impact_to_severity - Convert drift impact to DriftSeverity.
"""
function impact_to_severity(impact::Float64, tolerance::Float64)::DriftSeverity
    if impact > tolerance * 2.0
        return DRIFT_CRITICAL
    elseif impact > tolerance * 1.5
        return DRIFT_SIGNIFICANT
    elseif impact > tolerance * 1.2
        return DRIFT_MODERATE
    elseif impact > tolerance
        return DRIFT_MINOR
    else
        return DRIFT_NONE
    end
end

# ============================================================================
# PIPELINE STAGE 6: EVALUATE REPUTATION
# ============================================================================

"""
    evaluate_reputation - Evaluate action's impact on system reputation.
    
    Simulates the reputation impact of the action and checks if it
    would trigger the scrutiny threshold.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with reputation evaluation
"""
function evaluate_reputation(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Evaluating reputation impact" action_id=ctx.action.id
    
    # HCB PROTOCOL: owner_explicit removed. Cryptographic verification handled by Rust shell.
    # Julia performs full reputation evaluation on all actions regardless.
    # All actions go through complete reputation impact analysis - no bypasses.
    
    reputation_memory = kernel.reputation_memory
    scrutiny_threshold = reputation_memory.scrutiny_threshold
    
    # Simulate reputation impact based on action characteristics
    # Start with current score
    current_score = reputation_memory.record.current_score.overall_score
    
    # Estimate impact from this action
    # Higher risk actions have more potential for reputation damage
    risk_factor = ctx.risk_score !== nothing ? ctx.risk_score : 0.5
    
    # Actions that fail doctrine checks damage reputation more
    doctrine_penalty = ctx.doctrine_result == PERMISSION_DENIED ? 0.2 : 0.0
    
    # Calculate projected reputation impact
    projected_impact = current_score - (risk_factor * 0.1) - doctrine_penalty
    projected_impact = clamp(projected_impact, 0.0, 1.0)
    
    ctx.reputation_impact = projected_impact
    
    # Check if this would trigger scrutiny threshold
    if projected_impact < scrutiny_threshold
        # Flag for extra scrutiny
        if ctx.authorization_decision === nothing || ctx.authorization_decision != PERMISSION_DENIED
            ctx.authorization_decision = PERMISSION_FLAGGED
        end
        
        @warn "Reputation below scrutiny threshold" 
              action_id=ctx.action.id 
              current_score=current_score
              projected_impact=projected_impact
              threshold=scrutiny_threshold
    end
    
    ctx.current_stage = STAGE_REPUTATION_EVALUATED
    ctx.stage_timestamps[:reputation_evaluated] = now()
    
    @info "Reputation evaluation complete" 
          action_id=ctx.action.id 
          impact=projected_impact
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 7: AUTHORIZE
# ============================================================================

"""
    authorize - Make final authorization decision based on all stage results.
    
    Combines all previous stage results to make the final decision:
    - If any stage denied → PERMISSION_DENIED
    - If risk_score > max_acceptable_risk → PERMISSION_DENIED
    - If drift_projection.critical → PERMISSION_DENIED
    - If reputation_impact < scrutiny_threshold → PERMISSION_FLAGGED
    - Otherwise → PERMISSION_GRANTED
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `AuthorizationContext`: Updated context with final decision
"""
function authorize(ctx::AuthorizationContext, kernel::KernelState)::AuthorizationContext
    @info "Making authorization decision" action_id=ctx.action.id
    
    # Decision logic
    decision = PERMISSION_GRANTED
    
    # Check 1: Any previous stage denied?
    if ctx.doctrine_result == PERMISSION_DENIED
        decision = PERMISSION_DENIED
        @info "Authorization denied: doctrine violation"
    end
    
    # Check 2: Risk score exceeds threshold?
    if ctx.risk_score !== nothing
        max_risk = kernel.self_model.risk.max_acceptable_risk
        if kernel.self_model.risk.conservative_mode
            max_risk *= 0.5  # Conservative mode adjustment
        end
        
        if ctx.risk_score > max_risk
            decision = PERMISSION_DENIED
            @info "Authorization denied: risk exceeds threshold" 
                  risk=ctx.risk_score 
                  threshold=max_risk
        end
    end
    
    # Check 3: Critical drift projected?
    if ctx.drift_projection !== nothing
        if get(ctx.drift_projection, "critical", false) == true
            decision = PERMISSION_DENIED
            @info "Authorization denied: critical drift projected"
        end
    end
    
    # Check 4: Reputation below scrutiny threshold?
    if ctx.reputation_impact !== nothing
        if ctx.reputation_impact < kernel.reputation_memory.scrutiny_threshold
            if decision != PERMISSION_DENIED
                decision = PERMISSION_FLAGGED
                @info "Authorization flagged: reputation below threshold"
            end
        end
    end
    
    # Set final decision
    ctx.authorization_decision = decision
    
    # Set failure reason if denied
    if decision == PERMISSION_DENIED && ctx.failure_reason === nothing
        ctx.failure_reason = "Authorization denied by pipeline decision logic"
    end
    
    ctx.current_stage = STAGE_AUTHORIZED
    ctx.stage_timestamps[:authorized] = now()
    
    @info "Authorization complete" 
          action_id=ctx.action.id 
          decision=string(decision)
    
    return ctx
end

# ============================================================================
# PIPELINE STAGE 8: EXECUTE
# ============================================================================

"""
    execute_pipeline - Execute the action if authorized.
    
    Only executes the action if authorization was granted.
    Returns the context and action result.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `Tuple{AuthorizationContext, ActionResult}`: Updated context and result
"""
function execute_pipeline(ctx::AuthorizationContext, kernel::KernelState)::Tuple{AuthorizationContext, ActionResult}
    @info "Attempting to execute action" 
          action_id=ctx.action.id 
          decision=string(ctx.authorization_decision)
    
    # Check if authorized
    if ctx.authorization_decision == PERMISSION_DENIED
        @warn "Action not authorized, blocking execution" 
              action_id=ctx.action.id 
              reason=ctx.failure_reason
        
        # Create blocked result
        result = ActionResult(ctx.action.id;
            status=:blocked,
            actual_outcome="Blocked: $(ctx.failure_reason)"
        )
        
        ctx.current_stage = STAGE_EXECUTED
        ctx.stage_timestamps[:executed] = now()
        
        return ctx, result
    end
    
    # Execute the action via WorldInterface
    result = execute_world_action(kernel, ctx.action)
    
    ctx.current_stage = STAGE_EXECUTED
    ctx.stage_timestamps[:executed] = now()
    
    @info "Action execution complete" 
          action_id=ctx.action.id 
          status=result.status
    
    return ctx, result
end

# ============================================================================
# PIPELINE STAGE 9: RECORD OUTCOME
# ============================================================================

"""

    record_outcome! - Record the action result and update kernel state.
    
    Updates the kernel's internal state based on the action result,
    including updating reputation memory and confidence calibration.
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    - `kernel::KernelState`: Current kernel state
    - `result::ActionResult`: Result of action execution
"""
function record_outcome!(ctx::AuthorizationContext, kernel::KernelState, result::ActionResult)
    @info "Recording action outcome" 
          action_id=ctx.action.id 
          status=result.status
    
    # Call WorldInterface.record_action_result!
    record_action_result!(kernel, result)
    
    # Update confidence calibration based on prediction accuracy
    if result.prediction_error != 0.0
        update_confidence_calibration!(kernel, ctx, result)
    end
    
    # Update drift detector based on action outcome
    update_drift_from_result!(kernel, ctx, result)
    
    ctx.current_stage = STAGE_RECORDED
    ctx.stage_timestamps[:recorded] = now()
    
    @info "Outcome recorded" action_id=ctx.action.id
end

"""
    update_confidence_calibration! - Update confidence calibration based on results.
"""
function update_confidence_calibration!(kernel::KernelState, ctx::AuthorizationContext, result::ActionResult)
    cal = kernel.self_model.calibration
    
    # Get simulation prediction if available
    predicted = if ctx.simulation_result !== nothing
        get(ctx.simulation_result, "success_probability", 0.5)
    else
        0.5
    end
    
    # Actual outcome: 1.0 for success, 0.0 for failure
    actual = result.status == :success ? 1.0 : 0.0
    
    # Record prediction pair
    push!(cal.prediction_history, (predicted, actual))
    
    # Keep only recent history
    if length(cal.prediction_history) > 100
        cal.prediction_history = cal.prediction_history[end-99:end]
    end
    
    # Update calibration error
    errors = [abs(p - a) for (p, a) in cal.prediction_history]
    cal.calibration_error = sum(errors) / length(errors)
    
    # Track over/under confidence
    if predicted > actual + 0.2
        cal.overconfidence_count += 1
    elseif predicted < actual - 0.2
        cal.underconfidence_count += 1
    end
    
    cal.last_calibrated = now()
end

"""
    update_drift_from_result! - Update drift detector based on action result.
"""
function update_drift_from_result!(kernel::KernelState, ctx::AuthorizationContext, result::ActionResult)
    # Record identity-relevant action in drift detector
    # Convert to ActionProposal for the drift detector
    proposal = ActionProposal(
        isempty(ctx.action.required_capabilities) ? "unknown" : first(ctx.action.required_capabilities),
        0.8f0,
        0.1f0,
        1.0f0,
        string(ctx.action.risk_class),
        ctx.action.intent
    )
    
    # Calculate outcome reward for drift tracking
    outcome_reward = result.status == :success ? 1.0f0 : -0.5f0
    
    # Record in drift detector
    record_identity_relevant_action!(kernel.drift_detector, proposal, outcome_reward)
end

# ============================================================================
# MASTER PIPELINE FUNCTION
# ============================================================================

"""
    run_authorization_pipeline - Execute the complete authorization pipeline.
    
    This is the main entry point that runs the full authorization pipeline:
    propose → simulate → doctrine → risk → drift → reputation → authorize → execute → record
    
    If any stage fails:
    - Block action
    - Record failure reason
    - Update confidence calibration
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: Action to authorize and execute
    
    # Returns
    - `Tuple{AuthorizationContext, ActionResult}`: Final context and result
"""
function run_authorization_pipeline(kernel::KernelState, action::WorldAction)::Tuple{AuthorizationContext, ActionResult}
    @info "Starting authorization pipeline" 
          action_id=action.id 
          intent=action.intent
    
    # Stage 1: Propose
    ctx = propose_action(kernel, action)
    
    # Check if we should continue
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at proposal stage"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 2: Simulate
    ctx = simulate_action(ctx, kernel)
    
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at simulation stage"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 3: Check Doctrine
    ctx = check_doctrine(ctx, kernel)
    
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at doctrine check"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 4: Assess Risk
    ctx = assess_risk(ctx, kernel)
    
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at risk assessment"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 5: Project Drift
    ctx = project_drift(ctx, kernel)
    
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at drift projection"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 6: Evaluate Reputation
    ctx = evaluate_reputation(ctx, kernel)
    
    if !should_continue_pipeline(ctx)
        @warn "Pipeline halted at reputation evaluation"
        result = ActionResult(action.id;
            status=:blocked,
            actual_outcome="Pipeline halted: $(ctx.failure_reason)"
        )
        return ctx, result
    end
    
    # Stage 7: Authorize
    ctx = authorize(ctx, kernel)
    
    # Stage 8: Execute
    ctx, result = execute_pipeline(ctx, kernel)
    
    # Stage 9: Record
    record_outcome!(ctx, kernel, result)
    
    @info "Authorization pipeline complete" 
          action_id=action.id 
          decision=string(ctx.authorization_decision) 
          status=result.status
    
    return ctx, result
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_pipeline_status - Get summary of pipeline state.
    
    Returns a dictionary with information about all completed stages
    and their results.
    
    # Arguments
    - `ctx::AuthorizationContext`: Authorization context to query
    
    # Returns
    - `Dict`: Summary of pipeline status
"""
function get_pipeline_status(ctx::AuthorizationContext)::Dict
    return Dict(
        "action_id" => string(ctx.action.id),
        "intent" => ctx.action.intent,
        "current_stage" => STAGE_NAMES[ctx.current_stage],
        "doctrine_result" => ctx.doctrine_result !== nothing ? string(ctx.doctrine_result) : nothing,
        "risk_score" => ctx.risk_score,
        "drift_projection" => ctx.drift_projection,
        "reputation_impact" => ctx.reputation_impact,
        "authorization_decision" => ctx.authorization_decision !== nothing ? string(ctx.authorization_decision) : nothing,
        "failure_reason" => ctx.failure_reason,
        "stage_timestamps" => Dict(k => string(v) for (k, v) in ctx.stage_timestamps),
        "completed_stages" => [STAGE_NAMES[s] for s in instances(AuthorizationStage) if s <= ctx.current_stage]
    )
end

"""
    should_continue_pipeline - Check if pipeline should continue.
    
    Determines if the pipeline should continue to the next stage
    based on current results. Pipeline should stop if:
    - A critical check has failed
    - A failure reason has been set
    
    # Arguments
    - `ctx::AuthorizationContext`: Current authorization context
    
    # Returns
    - `Bool`: true if pipeline should continue, false if it should halt
"""
function should_continue_pipeline(ctx::AuthorizationContext)::Bool
    # If already denied, stop
    if ctx.authorization_decision == PERMISSION_DENIED
        return false
    end
    
    # If doctrine check failed, stop (fail-closed)
    if ctx.doctrine_result == PERMISSION_DENIED
        return false
    end
    
    # If we have a failure reason set, generally stop
    if ctx.failure_reason !== nothing
        # But allow if it's just a warning (flagged)
        if ctx.authorization_decision == PERMISSION_FLAGGED
            return true
        end
        return false
    end
    
    return true
end

"""
    emergency_stop! - Trigger emergency halt of the kernel.
    
    Activates emergency protocols when critical failures are detected.
    Sets the kernel to conservative mode and logs the emergency.
    
    # Arguments
    - `kernel::KernelState`: Kernel state to modify
    - `reason::String`: Reason for emergency stop
"""
function emergency_stop!(kernel::KernelState, reason::String)
    @error "EMERGENCY STOP TRIGGERED" reason=reason
    
    # Enable conservative mode
    kernel.self_model.risk.conservative_mode = true
    
    # Disable doctrine enforcer strict mode temporarily (for emergency overrides)
    # But keep it enabled
    kernel.doctrine_enforcer.enabled = true
    
    # Log emergency in reputation memory
    record_violation!(
        kernel.reputation_memory,
        "emergency_stop",
        "system_emergency",
        "emergency_stop",
        1.0,
        "executed_with_violation";
        context=Dict("reason" => reason),
        cycle=kernel.cycle
    )
    
    @warn "Kernel switched to conservative mode" reason=reason
end

end # module
