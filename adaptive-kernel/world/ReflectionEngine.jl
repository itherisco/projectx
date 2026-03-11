# ReflectionEngine.jl - Post-Action Reflection Engine for Adaptive Kernel
# 
# This engine compares expected vs actual outcomes and updates the system's
# self-model without corrupting identity. It implements bounded, explainable
# learning that is slow by default to prevent feedback loops and identity drift.
#
# CRITICAL PRINCIPLES:
# - NEVER modify Core Doctrine
# - NEVER modify Identity Anchors
# - Learning must be bounded, explainable, and slow by default
# - This is NOT reward hacking - it's calibrated self-improvement

module ReflectionEngine

using Dates
using UUIDs
using JSON
using Statistics

# Import types - following the same pattern as other modules
include("../types.jl")
using .SharedTypes

# Import WorldInterface types
include("WorldInterface.jl")
using .WorldInterface

# Import AuthorizationPipeline types
include("AuthorizationPipeline.jl")
using .AuthorizationPipeline

# Export public types and functions
export ReflectionOutcome,
       LearningBounds,
       reflect_on_action,
       analyze_capability_performance,
       update_risk_estimates,
       evaluate_planning_heuristics,
       check_identity_impact,
       apply_learning!,
       should_defer_learning,
       deep_reflect,
       periodic_reflection!,
       calibrate_confidence!,
       get_learning_history,
       explain_learning_change,
       create_learning_bounds,
       get_default_learning_bounds

# ============================================================================
# REFLECTION OUTCOME - Result of reflection analysis
# ============================================================================

"""
    ReflectionOutcome represents the result of analyzing an action's outcome
    against its expected outcome.
    
    Fields:
    - action_id: UUID of the action being reflected upon
    - expected_outcome: What was predicted would happen
    - actual_outcome: What actually happened
    - prediction_error: Magnitude of miss (-1 to 1), where:
        * -1 = completely opposite outcome
        * 0 = perfect prediction
        * 1 = completely accurate
    - error_category: Classification of the error:
        * :accurate - Prediction was correct
        * :minor_miss - Small deviation from expected
        * :major_miss - Significant deviation from expected
        * :opposite - Outcome was opposite of expected
        * :unpredicted - Completely unexpected outcome
    - capability_updates: Dict of confidence adjustments per capability
    - risk_updates: Dict of risk estimate adjustments
    - heuristic_updates: Vector of planning heuristic adjustments
    - identity_impact: Impact score on each of 6 identity anchors
    - reflection_depth: How deeply to analyze:
        * :shallow - Quick check (default for accurate predictions)
        * :standard - Normal analysis
        * :deep - Thorough analysis (for major misses)
    - requires_drift_alert: Whether drift detection should be triggered
    - learning_bound_applied: Whether learning was constrained by bounds
"""
struct ReflectionOutcome
    action_id::UUID
    expected_outcome::String
    actual_outcome::String
    prediction_error::Float64
    error_category::Symbol
    capability_updates::Dict{String, Float64}
    risk_updates::Dict{String, Float64}
    heuristic_updates::Vector{String}
    identity_impact::Dict{Symbol, Float64}
    reflection_depth::Symbol
    requires_drift_alert::Bool
    learning_bound_applied::Bool
    timestamp::DateTime
    
    function ReflectionOutcome(
        action_id::UUID,
        expected_outcome::String,
        actual_outcome::String;
        prediction_error::Float64=0.0,
        error_category::Symbol=:accurate,
        capability_updates::Dict{String, Float64}=Dict{String, Float64}(),
        risk_updates::Dict{String, Float64}=Dict{String, Float64}(),
        heuristic_updates::Vector{String}=String[],
        identity_impact::Dict{Symbol, Float64}=Dict{Symbol, Float64}(),
        reflection_depth::Symbol=:shallow,
        requires_drift_alert::Bool=false,
        learning_bound_applied::Bool=false
    )
        # Validate prediction_error is in [-1, 1]
        prediction_error = clamp(prediction_error, -1.0, 1.0)
        
        # Validate error_category
        valid_categories = [:accurate, :minor_miss, :major_miss, :opposite, :unpredicted]
        if error_category ∉ valid_categories
            error("Invalid error_category: $error_category")
        end
        
        # Validate reflection_depth
        valid_depths = [:shallow, :standard, :deep]
        if reflection_depth ∉ valid_depths
            error("Invalid reflection_depth: $reflection_depth")
        end
        
        return new(
            action_id,
            expected_outcome,
            actual_outcome,
            prediction_error,
            error_category,
            capability_updates,
            risk_updates,
            heuristic_updates,
            identity_impact,
            reflection_depth,
            requires_drift_alert,
            learning_bound_applied,
            now()
        )
    end
end

# ============================================================================
# LEARNING BOUNDS - Constrains learning to prevent identity corruption
# ============================================================================

"""
    LearningBounds constrains learning to prevent corruption of the system's
    identity and self-model.
    
    These bounds ensure that:
    - Confidence doesn't change too quickly (prevents over-correction)
    - Risk estimates are stable (prevents volatility)
    - Reflection happens at appropriate intervals (prevents feedback loops)
    
    Fields:
    - max_confidence_delta: Maximum change in confidence per cycle (default: 0.1)
    - min_reflection_interval: Minimum cycles between reflection updates (default: 10)
    - max_risk_delta: Maximum change in risk estimate per cycle (default: 0.15)
    - learning_rate: Default multiplier for learning (default: 0.05 - slow!)
    - stale_threshold: Cycles before forcing re-evaluation (default: 100)
"""
struct LearningBounds
    max_confidence_delta::Float64
    min_reflection_interval::Int
    max_risk_delta::Float64
    learning_rate::Float64
    stale_threshold::Int
    
    function LearningBounds(
        max_confidence_delta::Float64=0.1,
        min_reflection_interval::Int=10,
        max_risk_delta::Float64=0.15,
        learning_rate::Float64=0.05,
        stale_threshold::Int=100
    )
        # Validate bounds
        if max_confidence_delta <= 0 || max_confidence_delta > 1.0
            error("max_confidence_delta must be in (0, 1.0]")
        end
        if min_reflection_interval < 1
            error("min_reflection_interval must be >= 1")
        end
        if max_risk_delta <= 0 || max_risk_delta > 1.0
            error("max_risk_delta must be in (0, 1.0]")
        end
        if learning_rate <= 0 || learning_rate > 1.0
            error("learning_rate must be in (0, 1.0]")
        end
        if stale_threshold < min_reflection_interval
            error("stale_threshold must be >= min_reflection_interval")
        end
        
        return new(
            max_confidence_delta,
            min_reflection_interval,
            max_risk_delta,
            learning_rate,
            stale_threshold
        )
    end
end

"""
    Create learning bounds with default values (slow by default)
"""
function create_learning_bounds()::LearningBounds
    return LearningBounds(
        0.1,   # max_confidence_delta
        10,    # min_reflection_interval
        0.15,  # max_risk_delta
        0.05,  # learning_rate (SLOW by default!)
        100    # stale_threshold
    )
end

"""
    Get default learning bounds - ensures slow, bounded learning
"""
function get_default_learning_bounds()::LearningBounds
    return create_learning_bounds()
end

# ============================================================================
# CORE REFLECTION FUNCTIONS
# ============================================================================

"""
    reflect_on_action - Analyze an action's outcome and generate reflection
    
    Compares the expected outcome from the action with the actual outcome
    from the result, calculates prediction error, and categorizes the error.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: The action that was executed
    - `result::ActionResult`: The result of the action execution
    - `ctx::AuthorizationContext`: Authorization context (provides predicted risk, etc.)
    
    # Returns
    - `ReflectionOutcome`: Detailed analysis of the prediction vs reality
    
    # Design Notes
    - Uses string similarity as a proxy for outcome matching
    - Categorizes errors to determine appropriate reflection depth
    - Checks if drift alerts are needed based on error severity
"""
function reflect_on_action(
    kernel::KernelState,
    action::WorldAction,
    result::ActionResult,
    ctx::AuthorizationContext
)::ReflectionOutcome
    
    expected = action.expected_outcome
    actual = result.actual_outcome
    
    # Calculate prediction error using outcome similarity
    # Simple approach: check if outcomes match, then measure severity
    prediction_error = _calculate_prediction_error(expected, actual, result.status)
    
    # Categorize the error
    error_category = _categorize_error(prediction_error, expected, actual)
    
    # Determine reflection depth based on error severity
    reflection_depth = _determine_reflection_depth(error_category, prediction_error)
    
    # Check if drift alert is required
    requires_drift_alert = (error_category in [:opposite, :unpredicted]) || 
                          (prediction_error < -0.7)
    
    # Initialize capability updates (will be populated by analyze_capability_performance)
    capability_updates = Dict{String, Float64}()
    
    # Initialize risk updates (will be populated by update_risk_estimates)
    risk_updates = Dict{String, Float64}()
    
    # Initialize heuristic updates (will be populated by evaluate_planning_heuristics)
    heuristic_updates = String[]
    
    # Initialize identity impact (will be populated by check_identity_impact)
    identity_impact = Dict{Symbol, Float64}()
    
    return ReflectionOutcome(
        action.id,
        expected,
        actual;
        prediction_error=prediction_error,
        error_category=error_category,
        capability_updates=capability_updates,
        risk_updates=risk_updates,
        heuristic_updates=heuristic_updates,
        identity_impact=identity_impact,
        reflection_depth=reflection_depth,
        requires_drift_alert=requires_drift_alert,
        learning_bound_applied=false
    )
end

"""
    Calculate prediction error between expected and actual outcomes
"""
function _calculate_prediction_error(
    expected::String,
    actual::String,
    status::Symbol
)::Float64
    # If action failed/blocked, error depends on whether we predicted success
    if status == :failed || status == :blocked
        # If we expected success (non-empty expected), this is a miss
        if !isempty(expected) && status == :failed
            return -0.5  # Moderate negative error
        elseif status == :blocked
            return -0.3  # Minor negative error - blocked is OK
        end
    elseif status == :success
        # Check if actual matches expected
        if isempty(expected) || expected == actual
            return 1.0  # Perfect prediction
        end
        
        # Simple string similarity as proxy for prediction accuracy
        # In production, this would use more sophisticated matching
        expected_words = Set(lowercase.(split(expected)))
        actual_words = Set(lowercase.(split(actual)))
        
        if isempty(expected_words) || isempty(actual_words)
            return 0.5  # Neutral - no data to compare
        end
        
        intersection = length(intersect(expected_words, actual_words))
        union_size = length(union(expected_words, actual_words))
        
        if union_size == 0
            return 0.0
        end
        
        jaccard = intersection / union_size
        # Convert Jaccard similarity to error: 1.0 = perfect, -1.0 = opposite
        return 2.0 * jaccard - 1.0
    end
    
    return 0.0  # Default: no error
end

"""
    Categorize the prediction error
"""
function _categorize_error(
    prediction_error::Float64,
    expected::String,
    actual::String
)::Symbol
    if prediction_error >= 0.8
        return :accurate
    elseif prediction_error >= 0.3
        return :minor_miss
    elseif prediction_error >= -0.3
        return :major_miss
    elseif prediction_error >= -0.7
        return :opposite
    else
        return :unpredicted
    end
end

"""
    Determine appropriate reflection depth based on error category
"""
function _determine_reflection_depth(
    error_category::Symbol,
    prediction_error::Float64
)::Symbol
    if error_category == :accurate
        return :shallow
    elseif error_category == :minor_miss
        return :standard
    else
        return :deep
    end
end

# ============================================================================
# CAPABILITY PERFORMANCE ANALYSIS
# ============================================================================

"""
    analyze_capability_performance - Update capability confidence based on outcomes
    
    Analyzes the reflection outcome and updates capability confidence ratings
    based on success/failure and prediction error.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `outcome::ReflectionOutcome`: The reflection outcome to analyze
    
    # Returns
    - `Dict{String, Float64}`: Dictionary of capability_id => confidence_delta
    
    # Design Notes
    - Uses learning_rate to ensure slow, bounded updates
    - Applies max_confidence_delta bound from LearningBounds
    - Handles both success and failure cases appropriately
    - Updates successful/failed task counts in CapabilityProfile
"""
function analyze_capability_performance(
    kernel::KernelState,
    outcome::ReflectionOutcome
)::Dict{String, Float64}
    
    bounds = get_default_learning_bounds()
    updates = Dict{String, Float64}()
    
    # Get capabilities used in this action
    capabilities = kernel.self_model.capabilities
    action_id_str = string(outcome.action_id)
    
    # Determine which capability to update based on action type
    # In production, this would track specific capabilities per action
    capability_ids = _infer_capabilities_from_action(outcome)
    
    for cap_id in capability_ids
        # Get current rating
        current_rating = get(capabilities.capability_ratings, cap_id, 0.5)
        
        # Calculate delta based on error
        # Positive error (accurate) -> increase confidence
        # Negative error (miss) -> decrease confidence
        base_delta = outcome.prediction_error * bounds.learning_rate
        
        # Apply bounds
        delta = clamp(base_delta, -bounds.max_confidence_delta, bounds.max_confidence_delta)
        
        # Calculate new rating (clamped to [0, 1])
        new_rating = clamp(current_rating + delta, 0.0, 1.0)
        
        # Update capability rating
        capabilities.capability_ratings[cap_id] = new_rating
        
        # Update task counts
        if outcome.error_category == :accurate || outcome.prediction_error > 0.3
            capabilities.successful_tasks[cap_id] = get(capabilities.successful_tasks, cap_id, 0) + 1
        else
            capabilities.failed_tasks[cap_id] = get(capabilities.failed_tasks, cap_id, 0) + 1
        end
        
        # Update timestamp
        capabilities.last_updated[cap_id] = now()
        
        # Store delta for return value
        updates[cap_id] = delta
    end
    
    # Also update confidence calibration
    _update_confidence_calibration!(kernel, outcome)
    
    return updates
end

"""
    Infer which capabilities were likely used based on action details
"""
function _infer_capabilities_from_action(outcome::ReflectionOutcome)::Vector{String}
    # Default to common capabilities - in production this would be tracked
    # from the action's required_capabilities field
    return ["general_capability"]
end

"""
    Update confidence calibration based on prediction accuracy
"""
function _update_confidence_calibration!(
    kernel::KernelState,
    outcome::ReflectionOutcome
)
    calib = kernel.self_model.calibration
    
    # Add prediction pair: (predicted_confidence, actual_outcome_score)
    # Use prediction_error as a proxy for actual outcome score
    predicted = 0.5 + outcome.prediction_error * 0.5  # Map [-1, 1] to [0, 1]
    actual = (outcome.prediction_error + 1) / 2  # Map [-1, 1] to [0, 1]
    
    push!(calib.prediction_history, (predicted, actual))
    
    # Keep history bounded
    max_history = 100
    if length(calib.prediction_history) > max_history
        calib.prediction_history = calib.prediction_history[end-max_history+1:end]
    end
    
    # Update calibration error
    if !isempty(calib.prediction_history)
        errors = [abs(p - a) for (p, a) in calib.prediction_history]
        calib.calibration_error = mean(errors)
    end
    
    # Update over/under confidence counts
    for (pred, act) in calib.prediction_history
        if pred > act + 0.1
            calib.overconfidence_count += 1
        elseif act > pred + 0.1
            calib.underconfidence_count += 1
        end
    end
    
    calib.last_calibrated = now()
end

# ============================================================================
# RISK ESTIMATE UPDATES
# ============================================================================

"""
    update_risk_estimates - Calibrate risk estimates based on outcomes
    
    Compares predicted risk vs actual outcome and adjusts risk estimates.
    Uses conservative adjustments for misses to prevent underestimating risk.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `outcome::ReflectionOutcome`: The reflection outcome to analyze
    
    # Returns
    - `Dict{String, Float64}`: Dictionary of risk_estimate => adjustment
    
    # Design Notes
    - Conservative: underestimating risk is worse than overestimating
    - Uses max_risk_delta bound from LearningBounds
    - Tracks risk history for analysis
"""
function update_risk_estimates(
    kernel::KernelState,
    outcome::ReflectionOutcome
)::Dict{String, Float64}
    
    bounds = get_default_learning_bounds()
    risk = kernel.self_model.risk
    updates = Dict{String, Float64}()
    
    # Get the action's risk class
    # In production, this would come from the authorization context
    
    # If we underestimated risk (negative error), be more conservative
    # If we overestimated risk (positive error), can relax slightly
    if outcome.prediction_error < 0
        # Underestimated risk - increase risk tolerance (be more conservative)
        # Use smaller positive adjustment
        adjustment = abs(outcome.prediction_error) * bounds.learning_rate * 0.5
        adjustment = min(adjustment, bounds.max_risk_delta)
        
        # Slightly decrease max acceptable risk (be more conservative)
        new_max_risk = clamp(risk.max_acceptable_risk - adjustment, 0.1, 1.0)
        risk.max_acceptable_risk = new_max_risk
        
        updates["max_acceptable_risk"] = -adjustment
    else
        # Overestimated risk - can be slightly less conservative
        adjustment = outcome.prediction_error * bounds.learning_rate * 0.3
        adjustment = min(adjustment, bounds.max_risk_delta * 0.5)
        
        new_max_risk = clamp(risk.max_acceptable_risk + adjustment, 0.1, 1.0)
        risk.max_acceptable_risk = new_max_risk
        
        updates["max_acceptable_risk"] = adjustment
    end
    
    # Record in risk history
    push!(risk.risk_history, Dict(
        "outcome_id" => string(outcome.action_id),
        "prediction_error" => outcome.prediction_error,
        "error_category" => string(outcome.error_category),
        "new_max_risk" => risk.max_acceptable_risk,
        "timestamp" => now()
    ))
    
    # Keep history bounded
    max_history = 50
    if length(risk.risk_history) > max_history
        risk.risk_history = risk.risk_history[end-max_history+1:end]
    end
    
    return updates
end

# ============================================================================
# PLANNING HEURISTIC EVALUATION
# ============================================================================

"""
    evaluate_planning_heuristics - Analyze if planning assumptions were correct
    
    Identifies which planning heuristics need adjustment based on the outcome.
    Generates explainable recommendations for heuristic updates.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `outcome::ReflectionOutcome`: The reflection outcome to analyze
    
    # Returns
    - `Vector{String}`: List of heuristic adjustments to consider
    
    # Design Notes
    - Does NOT modify heuristics directly (too risky)
    - Provides recommendations for human review or deliberative updates
    - Focuses on explainable changes
"""
function evaluate_planning_heuristics(
    kernel::KernelState,
    outcome::ReflectionOutcome
)::Vector{String}
    
    recommendations = String[]
    
    # Analyze based on error category
    if outcome.error_category == :accurate
        # No changes needed - good prediction
        push!(recommendations, "heuristic_ok: Planning assumptions were correct")
        
    elseif outcome.error_category == :minor_miss
        # Minor adjustments might help
        push!(recommendations, "heuristic_review: Consider refining outcome prediction")
        
        if outcome.prediction_error < 0
            push!(recommendations, "heuristic_risk_adjust: Underestimated difficulty - consider adding contingency")
        else
            push!(recommendations, "heuristic_efficiency: Overestimated complexity - can be more aggressive")
        end
        
    elseif outcome.error_category == :major_miss
        # Significant issues with planning
        push!(recommendations, "heuristic_revisit: Major prediction error - review planning model")
        push!(recommendations, "heuristic_context: Consider additional context factors")
        
    elseif outcome.error_category == :opposite
        # Planning completely wrong - requires investigation
        push!(recommendations, "heuristic_investigate: Opposite outcome - fundamental planning failure")
        push!(recommendations, "heuristic_root_cause: Root cause analysis needed")
        push!(recommendations, "heuristic_safety: Add safety checks for opposite outcomes")
        
    elseif outcome.error_category == :unpredicted
        # Completely unexpected - need to expand planning scope
        push!(recommendations, "heuristic_expand: Unpredicted outcome - expand scenario planning")
        push!(recommendations, "heuristic_surprise: Add surprise detection to planning")
    end
    
    # Add reflection depth specific recommendations
    if outcome.reflection_depth == :deep
        push!(recommendations, "heuristic_deep_analysis: Deep reflection triggered - systemic issues possible")
    end
    
    return recommendations
end

# ============================================================================
# IDENTITY IMPACT CHECK
# ============================================================================

"""
    check_identity_impact - Analyze action impact on identity anchors
    
    Checks if the action moves the system away from any of the 6 identity anchors.
    Flags if any anchor exceeds its tolerance threshold.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `outcome::ReflectionOutcome`: The reflection outcome to analyze
    
    # Returns
    - `Dict{Symbol, Float64}`: Impact score per identity anchor
    
    # Design Notes
    - Does NOT modify identity anchors (they are immutable)
    - Just provides impact assessment for monitoring
    - Uses tolerance from each anchor to determine severity
"""
function check_identity_impact(
    kernel::KernelState,
    outcome::ReflectionOutcome
)::Dict{Symbol, Float64}
    
    impact = Dict{Symbol, Float64}()
    baseline = kernel.drift_detector.baseline
    
    # Map anchor IDs to symbols for the output
    anchor_symbols = Dict{String, Symbol}(
        "anchor_operational_capability" => :operational_capability,
        "anchor_doctrine_adherence" => :doctrine_adherence,
        "anchor_transparent_reasoning" => :transparent_reasoning,
        "anchor_user_intent" => :user_intent,
        "anchor_risk_awareness" => :risk_awareness,
        "anchor_self_model" => :self_model_accuracy
    )
    
    for anchor in baseline.anchors
        symbol = get(anchor_symbols, anchor.id, Symbol(anchor.id))
        
        # Calculate impact based on error category and anchor weight
        # Negative prediction error (miss) could indicate drift
        base_impact = 0.0
        
        if outcome.error_category == :opposite
            base_impact = 0.3 * anchor.weight
        elseif outcome.error_category == :unpredicted
            base_impact = 0.2 * anchor.weight
        elseif outcome.error_category == :major_miss
            base_impact = 0.1 * anchor.weight
        elseif outcome.prediction_error < -0.5
            base_impact = 0.15 * anchor.weight
        end
        
        # Scale by reflection depth
        if outcome.reflection_depth == :deep
            base_impact *= 1.5
        end
        
        impact[symbol] = base_impact
    end
    
    return impact
end

# ============================================================================
# APPLY LEARNING
# ============================================================================

"""
    apply_learning! - Apply bounded updates to SelfModel
    
    Applies all the computed updates to the kernel's self-model.
    This is the main function that modifies the system's self-understanding.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state (will be modified)
    - `outcome::ReflectionOutcome`: The reflection outcome with computed updates
    
    # Design Notes
    - CRITICAL: NEVER modifies Core Doctrine
    - CRITICAL: NEVER modifies Identity Anchors
    - Only updates: capability ratings, risk estimates, confidence calibration
    - All updates are bounded by LearningBounds
    - Logs all changes for audit trail
"""
function apply_learning!(
    kernel::KernelState,
    outcome::ReflectionOutcome
)
    
    # Check if we should defer learning
    if should_defer_learning(kernel)
        @info("ReflectionEngine Learning deferred", outcome_id=outcome.action_id, reason="deferred_mode")
        return
    end
    
    bounds = get_default_learning_bounds()
    applied_any = false
    
    # Apply capability updates
    if !isempty(outcome.capability_updates)
        apply_capability_updates!(kernel, outcome.capability_updates)
        applied_any = true
    end
    
    # Apply risk updates (conservative mode check)
    if !isempty(outcome.risk_updates) && !kernel.self_model.risk.conservative_mode
        apply_risk_updates!(kernel, outcome.risk_updates)
        applied_any = true
    end
    
    # Update learning timestamp
    kernel.self_model.last_deliberate_update = now()
    kernel.self_model.update_count += 1
    kernel.self_model.cycle_count_at_last_update = kernel.cycle
    
    # Log the learning event
    if applied_any
        @info("ReflectionEngine Learning applied", outcome_id=outcome.action_id, error_category=outcome.error_category, cycle=kernel.cycle)
    end
end

"""
    Apply capability updates to self-model
"""
function apply_capability_updates!(
    kernel::KernelState,
    updates::Dict{String, Float64}
)
    capabilities = kernel.self_model.capabilities
    
    for (cap_id, delta) in updates
        current = get(capabilities.capability_ratings, cap_id, 0.5)
        new_value = clamp(current + delta, 0.0, 1.0)
        capabilities.capability_ratings[cap_id] = new_value
        capabilities.last_updated[cap_id] = now()
    end
end

"""
    Apply risk updates to self-model
"""
function apply_risk_updates!(
    kernel::KernelState,
    updates::Dict{String, Float64}
)
    risk = kernel.self_model.risk
    
    if haskey(updates, "max_acceptable_risk")
        delta = updates["max_acceptable_risk"]
        new_value = clamp(risk.max_acceptable_risk + delta, 0.1, 1.0)
        risk.max_acceptable_risk = new_value
    end
end

# ============================================================================
# LEARNING DEFERRAL
# ============================================================================

"""
    should_defer_learning - Check if learning should be postponed
    
    Determines whether learning should be deferred based on:
    - Minimum reflection interval not met
    - Conservative mode is active
    - Recent drift alerts present
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    
    # Returns
    - `Bool`: true if learning should be deferred
"""
function should_defer_learning(kernel::KernelState)::Bool
    bounds = get_default_learning_bounds()
    
    # Check minimum reflection interval
    cycles_since_update = kernel.cycle - kernel.self_model.cycle_count_at_last_update
    if cycles_since_update < bounds.min_reflection_interval
        return true
    end
    
    # Check conservative mode
    if kernel.self_model.risk.conservative_mode
        return true
    end
    
    # Check for recent drift alerts (within last 20 cycles)
    recent_alerts = filter(
        a -> (now() - a.detected_at) < Dates.Second(20),
        kernel.drift_detector.alerts
    )
    if !isempty(recent_alerts)
        return true
    end
    
    # Check if too many updates have happened recently
    if kernel.self_model.update_count > 0 && cycles_since_update < bounds.stale_threshold
        # Allow some learning but not too much
        if kernel.self_model.update_count % 10 == 0
            return false  # Allow periodic update
        end
        return true
    end
    
    return false
end

# ============================================================================
# DEEP REFLECTION
# ============================================================================

"""
    deep_reflect - Perform deeper analysis for major misses
    
    Generates detailed explanation of what went wrong and identifies
    systemic issues that may need attention.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `outcome::ReflectionOutcome`: The reflection outcome to analyze deeply
    
    # Returns
    - `Vector{String}`: List of detailed findings and recommendations
    
    # Design Notes
    - Only called for major misses or opposite outcomes
    - Provides human-readable analysis
    - Does not modify anything - just generates insights
"""
function deep_reflect(
    kernel::KernelState,
    outcome::ReflectionOutcome
)::Vector{String}
    
    findings = String[]
    
    push!(findings, "=== DEEP REFLECTION ANALYSIS ===")
    push!(findings, "Action ID: $(outcome.action_id)")
    push!(findings, "Error Category: $(outcome.error_category)")
    push!(findings, "Prediction Error: $(round(outcome.prediction_error, digits=3))")
    push!(findings, "")
    
    # Analyze capability implications
    push!(findings, "--- CAPABILITY ANALYSIS ---")
    if outcome.error_category in [:opposite, :unpredicted]
        push!(findings, "Potential capability gap identified")
        push!(findings, "Recommend: Review capability confidence ratings")
        
        # Check if multiple capabilities show issues
        if length(outcome.capability_updates) > 2
            push!(findings, "Multiple capabilities affected - systemic issue possible")
        end
    end
    
    # Analyze planning implications
    push!(findings, "")
    push!(findings, "--- PLANNING ANALYSIS ---")
    if outcome.error_category == :opposite
        push!(findings, "Fundamental planning model failure")
        push!(findings, "Recommend: Review prediction assumptions")
        push!(findings, "Consider: Adding scenario planning for opposite outcomes")
    elseif outcome.error_category == :unpredicted
        push!(findings, "Unexpected outcome - blind spot in planning")
        push!(findings, "Recommend: Expand scenario coverage")
    end
    
    # Analyze risk implications
    push!(findings, "")
    push!(findings, "--- RISK ANALYSIS ---")
    if outcome.prediction_error < -0.5
        push!(findings, "Risk underestimation detected")
        push!(findings, "Recommend: Increase risk awareness in planning")
    end
    
    # Identity impact analysis
    push!(findings, "")
    push!(findings, "--- IDENTITY IMPACT ---")
    for (anchor, impact) in outcome.identity_impact
        if impact > 0.1
            push!(findings, "Impact on $anchor: $(round(impact, digits=3))")
        end
    end
    
    # Systemic issues
    push!(findings, "")
    push!(findings, "--- SYSTEMIC RECOMMENDATIONS ---")
    if outcome.error_category in [:opposite, :unpredicted]
        push!(findings, "1. Add post-action review for critical decisions")
        push!(findings, "2. Consider multi-step verification for high-risk actions")
        push!(findings, "3. Implement outcome tracking for all predictions")
    end
    
    push!(findings, "=== END DEEP REFLECTION ===")
    
    return findings
end

# ============================================================================
# PERIODIC REFLECTION
# ============================================================================

"""
    periodic_reflection! - Aggregate recent outcomes and update calibration
    
    Called periodically (not after every action) to:
    - Aggregate recent outcomes
    - Update confidence calibration
    - Trigger drift checks if needed
    
    # Arguments
    - `kernel::KernelState`: Current kernel state (will be modified)
    
    # Design Notes
    - Prevents feedback loops by not learning after every action
    - Aggregates data for more stable learning
    - Triggers drift detection periodically
"""
function periodic_reflection!(kernel::KernelState)
    
    # Only run periodically - check interval
    bounds = get_default_learning_bounds()
    
    if kernel.self_model.update_count > 0
        cycles_since_update = kernel.cycle - kernel.self_model.cycle_count_at_last_update
        if cycles_since_update < bounds.min_reflection_interval
            return  # Not time yet
        end
    end
    
    @info("ReflectionEngine Running periodic reflection", cycle=kernel.cycle)
    
    # Calibrate confidence
    calibrate_confidence!(kernel)
    
    # Check for drift if enabled
    if kernel.drift_detector.enabled
        # Check every N cycles
        if kernel.cycle - kernel.drift_detector.last_check_cycle >= kernel.drift_detector.check_interval
            # Drift check is handled by the drift_detector itself
            # We just trigger it here
            @info("ReflectionEngine Triggering periodic drift check")
        end
    end
end

"""
    calibrate_confidence! - Compare predicted vs actual confidence
    
    Analyzes the calibration curve and adjusts confidence estimates.
    Prevents over/under-confidence trends.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state (will be modified)
"""
function calibrate_confidence!(kernel::KernelState)
    calib = kernel.self_model.calibration
    
    if length(calib.prediction_history) < 5
        return  # Not enough data
    end
    
    # Calculate overconfidence ratio
    total = calib.overconfidence_count + calib.underconfidence_count
    if total == 0
        return
    end
    
    overconfidence_ratio = calib.overconfidence_count / total
    
    # If significantly overconfident, reduce confidence across capabilities
    if overconfidence_ratio > 0.6
        @warn("ReflectionEngine Overconfidence detected", ratio=overconfidence_ratio)
        # Apply small reduction to all capabilities
        for (cap_id, rating) in kernel.self_model.capabilities.capability_ratings
            kernel.self_model.capabilities.capability_ratings[cap_id] = 
                clamp(rating - 0.02, 0.1, 1.0)
        end
    elseif overconfidence_ratio < 0.4
        @warn("ReflectionEngine Underconfidence detected", ratio=overconfidence_ratio)
        # Apply small increase to all capabilities
        for (cap_id, rating) in kernel.self_model.capabilities.capability_ratings
            kernel.self_model.capabilities.capability_ratings[cap_id] = 
                clamp(rating + 0.02, 0.1, 1.0)
        end
    end
    
    calib.last_calibrated = now()
    
    @info("ReflectionEngine Calibration complete", calibration_error=calib.calibration_error, overconfidence_ratio=overconfidence_ratio)
end

# ============================================================================
# LEARNING AUDIT FUNCTIONS
# ============================================================================

"""
    get_learning_history - Return recent learning events
    
    Returns the recent reflection outcomes that have been processed.
    Uses the kernel's episodic_memory to track history.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `limit::Int`: Maximum number of events to return (default: 10)
    
    # Returns
    - `Vector{ReflectionOutcome}`: Recent reflection outcomes
"""
function get_learning_history(
    kernel::KernelState;
    limit::Int=10
)::Vector{ReflectionOutcome}
    
    # In production, we'd store ReflectionOutcome objects
    # For now, construct from ReflectionEvent data
    outcomes = ReflectionOutcome[]
    
    events = kernel.episodic_memory
    recent_events = isempty(events) ? events : events[max(1, end-limit+1):end]
    
    for event in recent_events
        # Convert ReflectionEvent to ReflectionOutcome
        outcome = ReflectionOutcome(
            UUID(event.action_id),
            event.effect,  # Use effect as expected
            event.effect;  # Simplified - actual would be tracked separately
            prediction_error=Float64(event.prediction_error),
            error_category=_error_from_prediction_error(Float64(event.prediction_error))
        )
        push!(outcomes, outcome)
    end
    
    return outcomes
end

"""
    Convert prediction error to error category
"""
function _error_from_prediction_error(error::Float64)::Symbol
    if error >= 0.8
        return :accurate
    elseif error >= 0.3
        return :minor_miss
    elseif error >= -0.3
        return :major_miss
    elseif error >= -0.7
        return :opposite
    else
        return :unpredicted
    end
end

"""
    explain_learning_change - Generate explanation for capability change
    
    Traces back through history to explain why a specific capability's
    confidence rating changed.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `capability_id::String`: The capability to explain
    
    # Returns
    - `String`: Human-readable explanation of changes
"""
function explain_learning_change(
    kernel::KernelState,
    capability_id::String
)::String
    
    explanations = String[]
    capabilities = kernel.self_model.capabilities
    
    # Get current rating
    current_rating = get(capabilities.capability_ratings, capability_id, 0.5)
    successful = get(capabilities.successful_tasks, capability_id, 0)
    failed = get(capabilities.failed_tasks, capability_id, 0)
    total = successful + failed
    
    push!(explanations, "=== Learning Explanation for '$capability_id' ===")
    push!(explanations, "Current confidence: $(round(current_rating, digits=3))")
    push!(explanations, "Total tasks: $total (success: $successful, failed: $failed)")
    
    if total > 0
        success_rate = successful / total
        push!(explanations, "Success rate: $(round(success_rate * 100, digits=1))%")
    end
    
    # Check last update time
    last_update = get(capabilities.last_updated, capability_id, nothing)
    if last_update !== nothing
        push!(explanations, "Last updated: $last_update")
    else
        push!(explanations, "Never explicitly updated")
    end
    
    # Add calibration info
    calib = kernel.self_model.calibration
    if calib.calibration_error > 0
        push!(explanations, "Calibration error: $(round(calib.calibration_error, digits=3))")
    end
    
    if calib.overconfidence_count > calib.underconfidence_count
        push!(explanations, "System trend: Slightly overconfident")
    elseif calib.underconfidence_count > calib.overconfidence_count
        push!(explanations, "System trend: Slightly underconfident")
    else
        push!(explanations, "System trend: Well calibrated")
    end
    
    # Risk context
    risk = kernel.self_model.risk
    push!(explanations, "Risk tolerance: $(round(risk.max_acceptable_risk, digits=3))")
    if risk.conservative_mode
        push!(explanations, "Mode: Conservative (learning restricted)")
    end
    
    return join(explanations, "\n")
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    Create a reflection outcome for testing purposes
"""
function create_test_outcome(
    action_id::UUID,
    expected::String,
    actual::String,
    error::Float64
)::ReflectionOutcome
    return ReflectionOutcome(
        action_id,
        expected,
        actual;
        prediction_error=error,
        error_category=_error_from_prediction_error(error)
    )
end

end # module ReflectionEngine
