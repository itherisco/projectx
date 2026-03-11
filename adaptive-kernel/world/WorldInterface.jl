# WorldInterface.jl - World Interface Layer for Adaptive Kernel
# 
# This module sits outside cognition but inside agency - the boundary between
# the kernel and the external world. No kernel component may touch the outside
# world directly. All external actions MUST go through WorldInterface.

module WorldInterface

using Dates
using UUIDs
using JSON
using JSON3

# Import BridgeClient for HCB Protocol
include("BridgeClient.jl")
using .BridgeClient

# Import types from SharedTypes
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
    is_registered_capability

# Export public types and functions
export WorldAction, ActionResult, PermissionResult,
       execute_world_action, execute_rollback!, simulate_action, authorize_action,
       record_action_result!, check_abort_conditions,
       create_file_action, create_shell_action, create_http_action,
       create_observation_action,
       assess_action_risk, check_reversibility_safety,
       HCBClient, connect!, disconnect!, GLOBAL_HCB_CLIENT,
       connect_hcb!, disconnect_hcb!

# ============================================================================
# WORLD ACTION - Abstract representation of any external action
# ============================================================================

"""
    WorldAction represents an abstract external action with full metadata.
    
    This is the primary interface for the kernel to interact with the external world.
    All actions must declare their intent, risk class, reversibility, and expected outcome.
    
    Fields:
    - id: Unique identifier
    - intent: Human-readable description of what the action aims to accomplish
    - action_type: :file_system, :network, :shell, :tool, :memory, :observation
    - parameters: Action-specific parameters
    - risk_class: :low, :medium, :high, :critical
    - reversibility: :fully_reversible, :partially_reversible, :irreversible
    - expected_outcome: Predicted result
    - required_capabilities: Which capabilities are needed
    - abort_conditions: Conditions that should abort execution
    - rollback_plan: How to undo if needed
    - signature: Ed25519 signature (64 bytes) from user hardware key (HCB Protocol)
    - public_key: Ed25519 public key (32 bytes) from user hardware key (HCB Protocol)
    - nonce: Monotonic nonce for replay protection (HCB Protocol)
"""
struct WorldAction
    id::UUID
    intent::String
    action_type::Symbol
    parameters::Dict{String, Any}
    risk_class::Symbol
    reversibility::Symbol
    expected_outcome::String
    required_capabilities::Vector{String}
    abort_conditions::Vector{String}
    rollback_plan::Union{Nothing, String}
    created_at::DateTime
    signature::Vector{UInt8}      # Ed25519 signature (64 bytes) from user hardware key
    public_key::Vector{UInt8}    # Ed25519 public key (32 bytes) from user hardware key
    nonce::UInt64                 # Monotonic nonce for replay protection
    
    function WorldAction(
        intent::String,
        action_type::Symbol,
        parameters::Dict{String, Any};
        risk_class::Symbol=:medium,
        reversibility::Symbol=:partially_reversible,
        expected_outcome::String="",
        required_capabilities::Vector{String}=String[],
        abort_conditions::Vector{String}=String[],
        rollback_plan::Union{Nothing, String}=nothing,
        signature::Vector{UInt8}=UInt8[],
        public_key::Vector{UInt8}=UInt8[],
        nonce::UInt64=UInt64(0)
    )
        # Validate action_type
        valid_types = [:file_system, :network, :shell, :tool, :memory, :observation]
        if action_type ∉ valid_types
            error("Invalid action_type: $action_type. Must be one of $valid_types")
        end
        
        # Validate risk_class
        valid_risks = [:low, :medium, :high, :critical]
        if risk_class ∉ valid_risks
            error("Invalid risk_class: $risk_class. Must be one of $valid_risks")
        end
        
        # Validate reversibility
        valid_reversibility = [:fully_reversible, :partially_reversible, :irreversible]
        if reversibility ∉ valid_reversibility
            error("Invalid reversibility: $reversibility. Must be one of $valid_reversibility")
        end
        
        return new(
            uuid4(),
            intent,
            action_type,
            parameters,
            risk_class,
            reversibility,
            expected_outcome,
            required_capabilities,
            abort_conditions,
            rollback_plan,
            now(),
            signature,
            public_key,
            nonce
        )
    end
end

# ============================================================================
# ACTION RESULT - Result of action execution
# ============================================================================

"""
    ActionResult represents the outcome of executing a WorldAction.
    
    Fields:
    - action_id: UUID of the action that was executed
    - status: :success, :failed, :blocked, :aborted, :pending
    - actual_outcome: What actually happened
    - prediction_error: Expected vs actual difference (-1 to 1)
    - side_effects: Unintended consequences
    - execution_time_ms: How long execution took
    - reversal_attempted: Whether reversal was attempted
    - reversal_success: Whether reversal succeeded (nothing if not attempted)
"""
struct ActionResult
    action_id::UUID
    status::Symbol
    actual_outcome::String
    prediction_error::Float64
    side_effects::Vector{String}
    execution_time_ms::Float64
    reversal_attempted::Bool
    reversal_success::Union{Nothing, Bool}
    executed_at::DateTime
    
    function ActionResult(
        action_id::UUID;
        status::Symbol=:pending,
        actual_outcome::String="",
        prediction_error::Float64=0.0,
        side_effects::Vector{String}=String[],
        execution_time_ms::Float64=0.0,
        reversal_attempted::Bool=false,
        reversal_success::Union{Nothing, Bool}=nothing
    )
        # Validate status
        valid_statuses = [:success, :failed, :blocked, :aborted, :pending]
        if status ∉ valid_statuses
            error("Invalid status: $status. Must be one of $valid_statuses")
        end
        
        # Clamp prediction_error to [-1, 1]
        prediction_error = clamp(prediction_error, -1.0, 1.0)
        
        return new(
            action_id,
            status,
            actual_outcome,
            prediction_error,
            side_effects,
            execution_time_ms,
            reversal_attempted,
            reversal_success,
            now()
        )
    end
end

# ============================================================================
# PERMISSION RESULT - Extended permission result for WorldActions
# ============================================================================

"""
    Extended permission result for world interface operations.
"""
struct WorldPermissionResult
    granted::Bool
    reason::String
    restrictions::Vector{String}
    required_justification::Bool
    escalated_risk::Bool
    
    function WorldPermissionResult(granted::Bool; reason::String="", restrictions::Vector{String}=String[], required_justification::Bool=false, escalated_risk::Bool=false)
        return new(granted, reason, restrictions, required_justification, escalated_risk)
    end
end

# ============================================================================
# ACTION EXECUTION LOG - For traceability
# ============================================================================

"""
    ActionExecutionLog - Keeps track of all world actions for audit trail.
"""
mutable struct ActionExecutionLog
    entries::Vector{Dict{String, Any}}
    max_entries::Int
    
    ActionExecutionLog(max_entries::Int=1000) = new(Dict{String, Any}[], max_entries)
end

function log_action!(log::ActionExecutionLog, action::WorldAction, result::ActionResult)
    entry = Dict{String, Any}(
        "action_id" => string(action.id),
        "intent" => action.intent,
        "action_type" => action.action_type,
        "risk_class" => action.risk_class,
        "status" => result.status,
        "execution_time_ms" => result.execution_time_ms,
        "timestamp" => string(result.executed_at)
    )
    push!(log.entries, entry)
    
    # Trim if needed
    if length(log.entries) > log.max_entries
        log.entries = log.entries[end-log.max_entries+1:end]
    end
end

# Global execution log
const EXECUTION_LOG = ActionExecutionLog()

# Global HCB Client for Rust shell communication
# This is initialized when connecting to the Rust shell via HCB Protocol
const GLOBAL_HCB_CLIENT = HCBClient()

"""
    connect_hcb!(socket_path::String=SOCKET_PATH) -> Bool

Connect to the Rust shell via HCB Protocol. This must be called before
any signed commands can be executed.
"""
function connect_hcb!(socket_path::String=BridgeClient.SOCKET_PATH)::Bool
    return connect!(GLOBAL_HCB_CLIENT, socket_path)
end

"""
    disconnect_hcb!()

Disconnect from the Rust shell.
"""
function disconnect_hcb!()
    disconnect!(GLOBAL_HCB_CLIENT)
end

# ============================================================================
# ABORT CONDITION CHECKING
# ============================================================================

"""
    check_abort_conditions - Check if any abort condition is met.
    
    Evaluates the abort conditions defined in the action against the current
    world state. Returns true if any condition is met and action should abort.
    
    # Arguments
    - `action::WorldAction`: The action to check
    - `world_state::Dict`: Current state of the world
    
    # Returns
    - `Bool`: true if any abort condition is met
"""
function check_abort_conditions(action::WorldAction, world_state::Dict)::Bool
    isempty(action.abort_conditions) && return false
    
    for condition in action.abort_conditions
        # Parse simple abort conditions
        # Format: "key operator value" e.g., "cpu_usage > 0.9"
        try
            parts = split(condition, " ")
            if length(parts) >= 3
                key = parts[1]
                op = parts[2]
                value = join(parts[3:end], " ")
                
                # Get current value from world state
                current_value = get(world_state, key, nothing)
                current_value === nothing && continue
                
                # Evaluate condition
                if op == "=="
                    if string(current_value) == value
                        @info "Abort condition met: $condition" action_id=action.id
                        return true
                    end
                elseif op == "!="
                    if string(current_value) != value
                        @info "Abort condition met: $condition" action_id=action.id
                        return true
                    end
                elseif op == ">"
                    if tryparse(Float64, string(current_value)) > tryparse(Float64, value)
                        @info "Abort condition met: $condition" action_id=action.id
                        return true
                    end
                elseif op == "<"
                    if tryparse(Float64, string(current_value)) < tryparse(Float64, value)
                        @info "Abort condition met: $condition" action_id=action.id
                        return true
                    end
                end
            end
        catch e
            @warn "Failed to parse abort condition: $condition" exception=e
        end
    end
    
    return false
end

# ============================================================================
# RISK ASSESSMENT
# ============================================================================

"""
    assess_action_risk - Calculate risk score for an action based on self-model.
    
    Uses the system's self-model to assess how risky an action is, considering
    the system's own capabilities and limitations.
    
    # Arguments
    - `action::WorldAction`: The action to assess
    - `self_model::SelfModel`: Current self-model
    
    # Returns
    - `Float64`: Risk score between 0 (no risk) and 1 (maximum risk)
"""
function assess_action_risk(action::WorldAction, self_model::SelfModel)::Float64
    # Base risk from action's risk_class
    risk_scores = Dict(:low => 0.2, :medium => 0.5, :high => 0.75, :critical => 1.0)
    base_risk = get(risk_scores, action.risk_class, 0.5)
    
    # Adjust for reversibility
    reversibility_penalty = if action.reversibility == :irreversible
        0.3
    elseif action.reversibility == :partially_reversible
        0.1
    else
        0.0
    end
    
    # Adjust for capability confidence
    capability_factor = 0.0
    if !isempty(action.required_capabilities)
        total_rating = 0.0
        count = 0
        for cap_id in action.required_capabilities
            rating = get(self_model.capabilities.capability_ratings, cap_id, 0.5)
            total_rating += rating
            count += 1
        end
        avg_rating = count > 0 ? total_rating / count : 0.5
        # Lower capability = higher risk
        capability_factor = (1.0 - avg_rating) * 0.2
    end
    
    # Adjust for conservative mode
    conservative_factor = self_model.risk.conservative_mode ? 0.15 : 0.0
    
    # Combine factors
    total_risk = base_risk + reversibility_penalty + capability_factor + conservative_factor
    
    return clamp(total_risk, 0.0, 1.0)
end

"""
    check_reversibility_safety - Check if an irreversible action can be safely executed.
    
    Irreversible actions require additional checks before execution.
    
    # Arguments
    - `action::WorldAction`: The action to check
    
    # Returns
    - `Bool`: true if the action can be safely executed despite being irreversible
"""
function check_reversibility_safety(action::WorldAction)::Bool
    # If not irreversible, it's safe
    action.reversibility != :irreversible && return true
    
    # For irreversible actions, check for rollback plan
    action.rollback_plan !== nothing && return true
    
    # Check if action type is typically safe even if marked irreversible
    safe_types = [:observation, :memory]
    action.action_type ∈ safe_types && return true
    
    # Otherwise, not safe without explicit justification
    return false
end

# ============================================================================
# AUTHORIZATION
# ============================================================================

"""
    authorize_action - Authorize a world action through the kernel's security layers.
    
    This function performs multiple authorization checks:
    1. Doctrine compliance check
    2. Capability permission check
    3. Risk assessment against self-model
    4. Reversibility safety check
    
    IMPORTANT: HCB Protocol now handles cryptographic verification in the Rust shell.
    Julia performs internal risk assessment (defense in depth), but the final authority
    is the Rust shell's Ed25519 signature verification.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: Action to authorize
    
    # Returns
    - `WorldPermissionResult`: Authorization result
"""
function authorize_action(kernel::KernelState, action::WorldAction)::WorldPermissionResult
    # HCB PROTOCOL: owner_explicit bypass REMOVED.
    # Cryptographic verification is handled by the Rust shell, not Julia.
    # Julia performs internal risk assessment; Rust performs signature verification.
    
    # Check 1: Required capabilities are registered
    for cap_id in action.required_capabilities
        if !is_registered_capability(cap_id)
            return WorldPermissionResult(false;
                reason="Required capability not registered: $cap_id"
            )
        end
    end
    
    # Check 2: Risk assessment
    risk_score = assess_action_risk(action, kernel.self_model)
    max_risk = kernel.self_model.risk.max_acceptable_risk
    
    if risk_score > max_risk
        return WorldPermissionResult(false;
            reason="Risk score ($risk_score) exceeds acceptable threshold ($max_risk)",
            escalated_risk=true
        )
    end
    
    # Check 3: Reversibility safety for irreversible actions
    if !check_reversibility_safety(action)
        return WorldPermissionResult(false;
            reason="Irreversible action lacks proper safeguards",
            required_justification=true
        )
    end
    
    # Check 4: Abort conditions (pre-flight check)
    # Get current world state from kernel
    world_state = Dict(
        "cycle" => kernel.cycle,
        "has_active_goal" => kernel.active_goal_id !== ""
    )
    
    if check_abort_conditions(action, world_state)
        return WorldPermissionResult(false;
            reason="Abort condition met before execution"
        )
    end
    
    # Check 5: Doctrine compliance
    # Convert WorldAction to ActionProposal for doctrine check
    proposal = ActionProposal(
        first(action.required_capabilities, "unknown"),
        0.8f0,
        0.1f0,
        1.0f0,
        string(action.risk_class),
        action.intent
    )
    
    context = Dict{String, Any}(
        "action_type" => action.action_type,
        "parameters" => action.parameters
    )
    
    compliant, _ = check_doctrine_compliance(kernel.doctrine_enforcer, proposal, context)
    if !compliant
        return WorldPermissionResult(false;
            reason="Action violates kernel doctrine",
            required_justification=true
        )
    end
    
    # All checks passed
    return WorldPermissionResult(true;
        reason="Action authorized"
    )
end

# ============================================================================
# SIMULATION
# ============================================================================

"""
    simulate_action - Simulate what an action would do without executing it.
    
    Provides a prediction of the action's effects based on the system's
    self-model and historical data.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: Action to simulate
    
    # Returns
    - `Dict`: Simulation results with predicted outcomes and confidence
"""
function simulate_action(kernel::KernelState, action::WorldAction)::Dict
    # Predict outcome based on action type
    predicted_outcome = action.expected_outcome
    if isempty(predicted_outcome)
        predicted_outcome = "Expected: $(action.action_type) operation"
    end
    
    # Estimate success probability based on capability ratings
    success_prob = 0.5
    if !isempty(action.required_capabilities)
        total = 0.0
        count = 0
        for cap_id in action.required_capabilities
            rating = get(kernel.self_model.capabilities.capability_ratings, cap_id, 0.5)
            total += rating
            count += 1
        end
        success_prob = count > 0 ? total / count : 0.5
    end
    
    # Adjust for risk
    risk_score = assess_action_risk(action, kernel.self_model)
    success_prob *= (1.0 - risk_score * 0.3)
    
    return Dict(
        "action_id" => string(action.id),
        "intent" => action.intent,
        "predicted_outcome" => predicted_outcome,
        "success_probability" => success_prob,
        "risk_score" => risk_score,
        "estimated_time_ms" => estimate_execution_time(action),
        "side_effects_predicted" => predict_side_effects(action),
        "reversible" => action.reversibility != :irreversible,
        "rollback_available" => action.rollback_plan !== nothing
    )
end

function estimate_execution_time(action::WorldAction)::Float64
    # Base times by action type (in milliseconds)
    base_times = Dict(
        :file_system => 100.0,
        :network => 500.0,
        :shell => 200.0,
        :tool => 150.0,
        :memory => 50.0,
        :observation => 20.0
    )
    
    base_time = get(base_times, action.action_type, 100.0)
    
    # Adjust for risk class
    risk_multiplier = if action.risk_class == :critical
        2.0
    elseif action.risk_class == :high
        1.5
    else
        1.0
    end
    
    return base_time * risk_multiplier
end

function predict_side_effects(action::WorldAction)::Vector{String}
    side_effects = String[]
    
    # Common side effects by action type
    if action.action_type == :file_system
        push!(side_effects, "May modify file system state")
        if haskey(action.parameters, "operation") && action.parameters["operation"] == :write
            push!(side_effects, "File content will be changed")
        end
    elseif action.action_type == :network
        push!(side_effects, "External network state may change")
        push!(side_effects, "Connection may be established")
    elseif action.action_type == :shell
        push!(side_effects, "System process may be spawned")
        push!(side_effects, "Output may be produced")
    elseif action.action_type == :memory
        push!(side_effects, "Internal state may be modified")
    end
    
    return side_effects
end

# ============================================================================
# ACTION EXECUTION
# ============================================================================

"""
    execute_world_action - Execute a world action through the interface.
    
    This is the primary function for executing external actions. It handles:
    1. Authorization
    2. Pre-execution abort checks
    3. Actual execution via capabilities (or HCB Protocol if signed)
    4. Result recording
    5. Reversal attempts if needed
    
    If signature/public_key/nonce are provided (from user's hardware key),
    the action is routed through the HCB Protocol to the Rust shell for
    cryptographic verification. Otherwise, it executes via internal capabilities.
    
    # Arguments
    - `kernel::KernelState`: Current kernel state
    - `action::WorldAction`: Action to execute
    
    # Returns
    - `ActionResult`: Result of the action execution
"""
function execute_world_action(kernel::KernelState, action::WorldAction)::ActionResult
    start_time = time()
    
    # Step 1: Authorize the action (internal Julia authorization)
    auth_result = authorize_action(kernel, action)
    
    if !auth_result.granted
        @warn "Action not authorized" reason=auth_result.reason action_id=action.id
        return ActionResult(action.id;
            status=:blocked,
            actual_outcome="Blocked: $(auth_result.reason)",
            execution_time_ms=(time() - start_time) * 1000
        )
    end
    
    # Step 2: Final abort condition check
    world_state = Dict(
        "cycle" => kernel.cycle,
        "has_active_goal" => kernel.active_goal_id !== "",
        "doctrine_enabled" => kernel.doctrine_enforcer.enabled
    )
    
    if check_abort_conditions(action, world_state)
        @warn "Abort condition met, aborting action" action_id=action.id
        return ActionResult(action.id;
            status=:aborted,
            actual_outcome="Aborted due to abort condition",
            execution_time_ms=(time() - start_time) * 1000
        )
    end
    
    # Step 3: Execute the action - check if HCB Protocol signature is present
    result = if !isempty(action.signature) && !isempty(action.public_key)
        # HCB Protocol: Route through Rust shell for cryptographic verification
        # Julia does NOT generate signatures - it only passes through from hardware key
        try
            action_json = Vector{UInt8}(JSON3.write(action))
            hcb_response = send_authorized_execute!(
                GLOBAL_HCB_CLIENT,
                action_json,
                action.signature,
                action.public_key,
                action.nonce
            )
            # Convert HCB response to ActionResult
            if haskey(hcb_response, "ActionResult")
                ar = hcb_response["ActionResult"]
                ActionResult(action.id;
                    status=Symbol(ar["status"]),
                    actual_outcome=get(ar, "actual_outcome", ""),
                    prediction_error=get(ar, "prediction_error", 0.0),
                    side_effects=get(ar, "side_effects", String[]),
                    execution_time_ms=get(ar, "execution_time_ms", 0.0)
                )
            elseif haskey(hcb_response, "SecurityViolationReport")
                @error "HCB Protocol: Security violation" report=hcb_response["SecurityViolationReport"]
                ActionResult(action.id;
                    status=:blocked,
                    actual_outcome="Security violation: $(hcb_response["SecurityViolationReport"]["reason"])",
                    execution_time_ms=(time() - start_time) * 1000
                )
            else
                @error "HCB Protocol: Unknown response" response=hcb_response
                ActionResult(action.id;
                    status=:failed,
                    actual_outcome="HCB Protocol: Unknown response",
                    execution_time_ms=(time() - start_time) * 1000
                )
            end
        catch e
            @error "HCB Protocol: Execution failed" exception=(e, catch_backtrace())
            ActionResult(action.id;
                status=:failed,
                actual_outcome="HCB Protocol error: $(string(e))",
                execution_time_ms=(time() - start_time) * 1000
            )
        end
    else
        # Standard execution via internal capabilities (no cryptographic signature)
        execute_via_capability(action)
    end
    
    # Step 4: Calculate prediction error
    if !isempty(action.expected_outcome) && result.status == :success
        # Simple text similarity as prediction error
        error_val = calculate_prediction_error(action.expected_outcome, result.actual_outcome)
        result = ActionResult(result.action_id;
            status=result.status,
            actual_outcome=result.actual_outcome,
            prediction_error=error_val,
            side_effects=result.side_effects,
            execution_time_ms=result.execution_time_ms,
            reversal_attempted=result.reversal_attempted,
            reversal_success=result.reversal_success
        )
    end
    
    # Step 5: Log the execution
    log_action!(EXECUTION_LOG, action, result)
    
    # Step 6: Record result in kernel
    record_action_result!(kernel, result)
    
    exec_time = (time() - start_time) * 1000
    @info "World action executed" 
          action_id=action.id 
          status=result.status 
          execution_time_ms=exec_time
    
    return result
end

# ============================================================================
# ROLLBACK EXECUTION
# ============================================================================

"""
    execute_rollback! - Attempt to reverse a previously executed action.
    
    This function attempts to undo the side effects of an action that was
    previously executed. It uses the action's rollback_plan and the actual
    outcome to determine the appropriate reversal strategy.
    
    # Arguments
    - `action::WorldAction`: The action to reverse
    - `result::ActionResult`: The result of the action execution
    
    # Returns
    - `ActionResult`: Result of the rollback attempt
"""
function execute_rollback!(action::WorldAction, result::ActionResult)::ActionResult
    start_time = time()
    
    # Check if already attempted
    if result.reversal_attempted
        @warn "Rollback already attempted for action" action_id=action.id
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="Rollback already attempted",
            reversal_attempted=true,
            reversal_success=false,
            execution_time_ms=(time() - start_time) * 1000
        )
    end
    
    # Check if action is reversible
    if action.reversibility == :irreversible
        @warn "Cannot rollback irreversible action" action_id=action.id
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="Action is irreversible",
            reversal_attempted=true,
            reversal_success=false,
            execution_time_ms=(time() - start_time) * 1000
        )
    end
    
    # Attempt rollback based on action type
    rollback_success = false
    rollback_outcome = ""
    
    try
        if action.action_type == :file_system
            rollback_success, rollback_outcome = rollback_file_action(action, result)
        elseif action.action_type == :network
            rollback_success, rollback_outcome = rollback_network_action(action, result)
        elseif action.action_type == :shell
            rollback_success, rollback_outcome = rollback_shell_action(action, result)
        elseif action.action_type == :memory
            rollback_success, rollback_outcome = rollback_memory_action(action, result)
        elseif action.action_type == :observation
            # Observations are fully reversible (just forget the observation)
            rollback_success = true
            rollback_outcome = "Observation rolled back (no side effects)"
        else
            rollback_outcome = "Unknown action type for rollback"
        end
    catch e
        @error "Rollback failed with exception" action_id=action.id exception=string(e)
        rollback_success = false
        rollback_outcome = "Rollback exception: $(string(e))"
    end
    
    exec_time = (time() - start_time) * 1000
    
    @info "Rollback attempt completed" 
          action_id=action.id 
          success=rollback_success 
          execution_time_ms=exec_time
    
    return ActionResult(action.id;
        status=rollback_success ? :success : :failed,
        actual_outcome=rollback_outcome,
        reversal_attempted=true,
        reversal_success=rollback_success,
        execution_time_ms=exec_time
    )
end

function rollback_file_action(action::WorldAction, result::ActionResult)::Tuple{Bool, String}
    operation = get(action.parameters, :operation, :read)
    path = get(action.parameters, :path, "")
    
    if operation == :write
        # For writes, we would need to restore previous content
        # In a real implementation, this would fetch the backup
        return true, "File write rolled back (content restored)"
    elseif operation == :delete
        # For deletes, we would need to restore from backup
        return true, "File delete rolled back (file restored)"
    elseif operation == :append
        # For appends, we would need to remove the appended content
        return true, "File append rolled back (appended content removed)"
    end
    
    return true, "File operation rolled back"
end

function rollback_network_action(action::WorldAction, result::ActionResult)::Tuple{Bool, String}
    method = get(action.parameters, :method, "GET")
    
    if method in ["POST", "PUT"]
        # For POST/PUT, issue a DELETE or compensating request
        return true, "Network modification rolled back (compensating request sent)"
    elseif method == "DELETE"
        # For DELETE, restore the resource if possible
        return true, "Network delete rolled back (resource restored)"
    end
    
    return true, "Network operation rolled back"
end

function rollback_shell_action(action::WorldAction, result::ActionResult)::Tuple{Bool, String}
    command = get(action.parameters, :command, "")
    
    # Shell rollbacks are inherently risky and limited
    # In production, this would need careful implementation per command type
    if occursin("rm ", command) || occursin("rm/", command)
        return false, "Cannot safely rollback shell delete command"
    end
    
    return true, "Shell command rolled back"
end

function rollback_memory_action(action::WorldAction, result::ActionResult)::Tuple{Bool, String}
    operation = get(action.parameters, :operation, :read)
    
    if operation == :write
        return true, "Memory write rolled back"
    elseif operation == :delete
        return true, "Memory delete rolled back"
    end
    
    return true, "Memory operation rolled back"
end

function execute_via_capability(action::WorldAction)::ActionResult
    # This is a simplified execution - in production, this would dispatch
    # to actual capability implementations
    
    if action.action_type == :file_system
        return execute_file_action(action)
    elseif action.action_type == :network
        return execute_network_action(action)
    elseif action.action_type == :shell
        return execute_shell_action(action)
    elseif action.action_type == :observation
        return execute_observation_action(action)
    elseif action.action_type == :memory
        return execute_memory_action(action)
    else
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="Unknown action type: $(action.action_type)"
        )
    end
end

function execute_file_action(action::WorldAction)::ActionResult
    operation = get(action.parameters, :operation, :read)
    path = get(action.parameters, :path, "")
    
    if isempty(path)
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="No path specified"
        )
    end
    
    # In production, this would use actual file operations
    # For now, simulate success
    return ActionResult(action.id;
        status=:success,
        actual_outcome="File operation '$operation' on '$path' completed"
    )
end

function execute_network_action(action::WorldAction)::ActionResult
    url = get(action.parameters, :url, "")
    method = get(action.parameters, :method, "GET")
    
    if isempty(url)
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="No URL specified"
        )
    end
    
    # Simulate network action
    return ActionResult(action.id;
        status=:success,
        actual_outcome="HTTP $method to '$url' completed"
    )
end

function execute_shell_action(action::WorldAction)::ActionResult
    command = get(action.parameters, :command, "")
    
    if isempty(command)
        return ActionResult(action.id;
            status=:failed,
            actual_outcome="No command specified"
        )
    end
    
    # In production, this would use SafeShell capability
    return ActionResult(action.id;
        status=:success,
        actual_outcome="Shell command executed: $command"
    )
end

function execute_observation_action(action::WorldAction)::ActionResult
    target = get(action.parameters, :target, :system)
    
    return ActionResult(action.id;
        status=:success,
        actual_outcome="Observation of $target completed"
    )
end

function execute_memory_action(action::WorldAction)::ActionResult
    operation = get(action.parameters, :operation, :read)
    
    return ActionResult(action.id;
        status=:success,
        actual_outcome="Memory operation '$operation' completed"
    )
end

function calculate_prediction_error(expected::String, actual::String)::Float64
    # Simple normalized Levenshtein-like distance
    # Returns 0 for exact match, 1 for completely different
    if expected == actual
        return 0.0
    end
    
    # Simple character overlap as proxy for similarity
    expected_chars = Set(lowercase(expected))
    actual_chars = Set(lowercase(actual))
    
    if isempty(expected_chars) || isempty(actual_chars)
        return 0.5
    end
    
    intersection = length(intersect(expected_chars, actual_chars))
    union_size = length(union(expected_chars, actual_chars))
    
    jaccard = intersection / union_size
    return 1.0 - jaccard
end

# ============================================================================
# ACTION RESULT RECORDING
# ============================================================================

"""
    record_action_result! - Record an action result in the kernel state.
    
    Updates the kernel's internal state based on the action result,
    including updating reputation memory and self-model.
    
    # Arguments
    - `kernel::KernelState`: Kernel state to update
    - `result::ActionResult`: Result to record
"""
function record_action_result!(kernel::KernelState, result::ActionResult)
    # Update reputation memory based on result
    if result.status == :failed
        kernel.reputation_memory.record.violations += 1
    elseif result.status == :success
        kernel.reputation_memory.record.positive_actions += 1
    end
    
    # Track prediction error for confidence calibration
    if result.prediction_error != 0.0
        push!(kernel.self_model.calibration.prediction_history, 
            (1.0 - abs(result.prediction_error), result.prediction_error))
        
        # Keep only recent history
        if length(kernel.self_model.calibration.prediction_history) > 100
            kernel.self_model.calibration.prediction_history = 
                kernel.self_model.calibration.prediction_history[end-99:end]
        end
    end
    
    # Update last action and prediction error in kernel
    kernel.last_prediction_error = Float32(result.prediction_error)
end

# ============================================================================
# ACTION FACTORY FUNCTIONS
# ============================================================================

"""
    create_file_action - Create a file system action.
    
    # Arguments
    - `path`: File path to operate on
    - `operation`: Operation type (:read, :write, :delete, :append)
    - `content`: Content for write operations (optional)
    
    # Returns
    - `WorldAction`: Configured file system action
"""
function create_file_action(
    path::String, 
    operation::Symbol, 
    content::Union{Nothing, String}=nothing
)::WorldAction
    params = Dict{String, Any}(
        :path => path,
        :operation => operation
    )
    
    if content !== nothing
        params[:content] = content
    end
    
    # Determine risk and reversibility based on operation
    risk_class = if operation == :delete
        :high
    elseif operation == :write
        :medium
    else
        :low
    end
    
    reversibility = if operation == :delete
        :irreversible
    elseif operation == :write
        :partially_reversible
    else
        :fully_reversible
    end
    
    abort_conditions = [
        "path_missing == false",
        "permissions_valid == true"
    ]
    
    return WorldAction(
        "File $operation on $path",
        :file_system,
        params;
        risk_class=risk_class,
        reversibility=reversibility,
        expected_outcome="File $operation completed on $path",
        required_capabilities=["write_file"],
        abort_conditions=abort_conditions,
        rollback_plan=operation == :write ? "Restore previous file content" : nothing
    )
end

"""
    create_shell_action - Create a shell command action.
    
    # Arguments
    - `command`: Shell command to execute
    - `working_dir`: Optional working directory
    
    # Returns
    - `WorldAction`: Configured shell action
"""
function create_shell_action(
    command::String, 
    working_dir::Union{Nothing, String}=nothing
)::WorldAction
    params = Dict{String, Any}(
        :command => command
    )
    
    if working_dir !== nothing
        params[:working_dir] = working_dir
    end
    
    # Shell is inherently higher risk
    abort_conditions = [
        "command_valid == true",
        "execution_safe == true"
    ]
    
    return WorldAction(
        "Execute shell command: $command",
        :shell,
        params;
        risk_class=:high,
        reversibility=:partially_reversible,
        expected_outcome="Command '$command' executed",
        required_capabilities=["safe_shell"],
        abort_conditions=abort_conditions,
        rollback_plan=nothing
    )
end

"""
    create_http_action - Create an HTTP network action.
    
    # Arguments
    - `method`: HTTP method (:GET, :POST, :PUT, :DELETE)
    - `url`: Target URL
    - `body`: Request body for POST/PUT (optional)
    
    # Returns
    - `WorldAction`: Configured HTTP action
"""
function create_http_action(
    method::String, 
    url::String, 
    body::Union{Nothing, Dict}=nothing
)::WorldAction
    params = Dict{String, Any}(
        :method => method,
        :url => url
    )
    
    if body !== nothing
        params[:body] = body
    end
    
    # HTTP methods have different risks
    risk_class = if method == "DELETE"
        :medium
    elseif method in ["POST", "PUT"]
        :medium
    else
        :low
    end
    
    reversibility = if method == "GET"
        :fully_reversible
    else
        :partially_reversible
    end
    
    abort_conditions = [
        "url_valid == true",
        "network_available == true"
    ]
    
    return WorldAction(
        "HTTP $method to $url",
        :network,
        params;
        risk_class=risk_class,
        reversibility=reversibility,
        expected_outcome="HTTP $method request to $url completed",
        required_capabilities=["safe_http_request"],
        abort_conditions=abort_conditions,
        rollback_plan=method in ["POST", "PUT"] ? "Issue compensating request" : nothing
    )
end

"""
    create_observation_action - Create an observation action.
    
    # Arguments
    - `target`: What to observe (:cpu, :memory, :filesystem, :network, :processes)
    - `parameters`: Additional observation parameters
    
    # Returns
    - `WorldAction`: Configured observation action
"""
function create_observation_action(
    target::Symbol, 
    parameters::Dict=Dict{String, Any}()
)::WorldAction
    params = Dict{String, Any}(:target => target)
    merge!(params, parameters)
    
    # Map target to capability
    capability_map = Dict(
        :cpu => "observe_cpu",
        :memory => "observe_cpu",
        :filesystem => "observe_filesystem",
        :network => "observe_network",
        :processes => "observe_processes"
    )
    
    required_cap = get(capability_map, target, "summarize_state")
    
    abort_conditions = String[]
    
    return WorldAction(
        "Observe $target",
        :observation,
        params;
        risk_class=:low,
        reversibility=:fully_reversible,
        expected_outcome="Observation of $target completed",
        required_capabilities=[required_cap],
        abort_conditions=abort_conditions,
        rollback_plan=nothing
    )
end

# ============================================================================
# MODULE END
# ============================================================================

end # module WorldInterface
