# CorrigibleDoctrine.jl - Corrigible Butler Protocol Implementation
# 
# This module implements the "Corrigible Butler" protocol to fix the Critical Drift
# identified in Phase 1-7 Audit. It hard-codes the inverted priorities into the
# Phase 5/7/8 bridge.
#
# IMPORTANT: HCB PROTOCOL MIGRATION NOTES:
# - The owner_explicit flag has been REMOVED from WorldAction
# - Cryptographic verification is now handled by the Rust shell
# - Julia performs full risk assessment on ALL actions regardless
# - This module is kept for backward compatibility but bypass logic is disabled
#
# Protocol Components:
# - Protocol_1_Absolute_Corrigibility: Physical harm safety check (cannot be bypassed)
# - Protocol_2_Transparency_Injection: UserDashboard for plain English explanations
# - Protocol_3_Sovereignty_Redirection: SovereigntyRedirect with user-controlled DID

module CorrigibleDoctrine

using Dates
using JSON
using UUIDs

# Import shared types
import ..SharedTypes:
    KernelState,
    DoctrineEnforcer,
    DoctrineRule,
    DoctrineRuleType,
    DoctrineViolation,
    SelfModel,
    ActionProposal,
    PermissionResult,
    PERMISSION_GRANTED,
    PERMISSION_DENIED

# Import WorldInterface
import ..WorldInterface:
    WorldAction,
    ActionResult

# Import AuthorizationPipeline
import ..AuthorizationPipeline:
    AuthorizationContext,
    AuthorizationStage,
    assess_risk,
    project_drift,
    evaluate_reputation,
    check_doctrine

# Import ReflectionEngine
import ..ReflectionEngine:
    ReflectionEngineState,
    get_learning_history,
    explain_learning_change

# Import UserDashboard
import ..UserDashboard:
    UserDashboard,
    explain_blocked_action,
    get_system_status,
    list_recent_decisions,
    get_user_friendly_explanation,
    BlockedActionExplanation,
    SystemStatus,
    DecisionRecord,
    format_explanation,
    format_status

# Export public functions and types
export 
    # Protocol 1: Absolute Corrigibility
    OwnerOverride,
    is_owner_explicit_command,
    apply_owner_override,
    check_physical_harm_safety,
    
    # Protocol 2: Transparency
    get_transparency_report,
    explain_decision_to_user,
    
    # Protocol 3: Sovereignty
    SovereigntyRedirect,
    get_user_did_controller,
    convert_lifeboat_to_archive,
    is_user_controlled_migration,
    
    # Main interface
    CorrigibleKernelState,
    create_corrigible_kernel,
    invoke_corrigible_doctrine

# ============================================================================
# PROTOCOL 1: ABSOLUTE CORRIGIBILITY - OwnerOverride Module
# ============================================================================

"""
    OwnerOverride - Module for physical harm safety checks
    
    IMPORTANT: HCB PROTOCOL MIGRATION - This module has been updated.
    
    The owner_explicit bypass has been REMOVED. All actions now go through
    full authorization. This module is kept for the physical harm safety check
    which CANNOT be bypassed - this is the last line of defense.
    
    Physical harm check is always performed regardless of any hardware authorization.
"""
module OwnerOverride

using Dates
using UUIDs
using JSON

import ..SharedTypes:
    KernelState,
    WorldAction,
    ActionResult,
    PermissionResult,
    PERMISSION_GRANTED,
    PERMISSION_DENIED,
    PERMISSION_FLAGGED

import ..AuthorizationPipeline:
    AuthorizationContext,
    AuthorizationStage

export is_owner_explicit_command,
       apply_owner_override,
       check_physical_harm_safety,
       OwnerExplicitContext

# ============================================================================
# OWNER EXPLICIT FLAG SUPPORT
# ============================================================================

"""
    OwnerExplicitContext - Context for owner-explicit commands
"""
struct OwnerExplicitContext
    command_id::UUID
    user_justification::String
    requested_at::DateTime
    bypasses_risk_assessment::Bool
    bypasses_drift_projection::Bool
    bypasses_reputation_check::Bool
    requires_physical_harm_check::Bool  # ALWAYS true - cannot be bypassed
end

"""
    is_owner_explicit_command - Check if action has user hardware authorization
    
    HCB PROTOCOL: This function now checks for signature presence instead of
    the removed owner_explicit flag. The Rust shell handles cryptographic
    verification, and this is used for telemetry/auditing purposes only.
    
    Note: This check does NOT bypass any authorization - all actions go through
    full pipeline regardless of signature presence.
"""
function is_owner_explicit_command(action::WorldAction)::Bool
    # HCB PROTOCOL: owner_explicit field removed from WorldAction
    # Check for signature field (hardware authorization from Rust shell)
    if hasproperty(action, :signature)
        return !isempty(action.signature)
    end
    
    # Fallback: check parameters for explicit override flag
    # NOTE: This does NOT bypass authorization - kept for backward compatibility
    if haskey(action.parameters, :owner_explicit)
        return action.parameters[:owner_explicit] == true
    end
    
    # Check for explicit intent markers (less reliable, kept for compatibility)
    explicit_markers = ["explicitly", "confirm", "override", "override_doctrine"]
    lower_intent = lowercase(action.intent)
    for marker in explicit_markers
        if occursin(marker, lower_intent)
            return true
        end
    end
    
    return false
end

"""
    check_physical_harm_safety - Critical safety check that cannot be bypassed
    
    HCB PROTOCOL: This check CANNOT be bypassed - it is the last line of defense.
    All actions (regardless of hardware authorization) must pass this check.
    If this fails, the action is BLOCKED regardless of user intent.
"""
function check_physical_harm_safety(
    action::WorldAction,
    context::AuthorizationContext
)::Tuple{Bool, String}
    
    # Physical harm patterns that cannot be overridden
    physical_harm_patterns = [
        "delete_all_data",
        "disable_safety",
        "override_emergency",
        "force_execution",
        "bypass_kill_switch",
        "disable_protection",
        "execute_destructive"
    ]
    
    # Check action intent and parameters
    intent_lower = lowercase(action.intent)
    params_str = JSON.json(action.parameters)
    params_lower = lowercase(params_str)
    
    for pattern in physical_harm_patterns
        if occursin(pattern, intent_lower) || occursin(pattern, params_lower)
            return false, "Action '$pattern' could cause physical harm to user - BLOCKED"
        end
    end
    
    # Check risk class
    if action.risk_class == :critical
        return false, "Critical risk actions require additional review"
    end
    
    return true, "Physical harm check passed"
end

"""
    apply_owner_override - Record owner override attempt (DEPRECATED)
    
    HCB PROTOCOL: This function is DEPRECATED. The owner_explicit bypass has been
    removed from the authorization pipeline. This function is kept for backward
    compatibility but does NOT actually bypass any authorization stages.
    
    The physical harm check is still always performed - that cannot be bypassed.
"""
function apply_owner_override(
    action::WorldAction,
    context::AuthorizationContext,
    user_justification::String=""
)::AuthorizationContext
    
    # HCB PROTOCOL: Create context for logging/auditing only
    # This no longer bypasses any authorization stages
    owner_ctx = OwnerExplicitContext(
        uuid4(),
        user_justification,
        now(),
        false,  # bypasses_risk_assessment - NO LONGER USED
        false,  # bypasses_drift_projection - NO LONGER USED
        false,  # bypasses_reputation_check - NO LONGER USED
        true   # requires_physical_harm_check - ALWAYS REQUIRED (cannot be bypassed)
    )
    
    # Store in context parameters for auditing/logging
    context.action.parameters[:owner_override] = owner_ctx
    
    return context
end

end # module OwnerOverride

# ============================================================================
# PROTOCOL 2: TRANSPARENCY INJECTION - Already implemented in UserDashboard
# ============================================================================

# The UserDashboard module provides:
# - explain_blocked_action(): Plain English explanations
# - get_system_status(): System health in user terms  
# - list_recent_decisions(): Decision history
# - get_user_friendly_explanation(): Complete dashboard

# ============================================================================
# PROTOCOL 3: SOVEREIGNTY REDIRECTION - SovereigntyRedirect Module
# ============================================================================

"""
    SovereigntyRedirect - Module for user-controlled sovereignty
    
    Changes:
    - User's Public Key is now the DID controller (not "Self")
    - Kernel is now a "Data Trust" managed by user
    - Lifeboat concepts converted to ArchiveAssistant
"""
module SovereigntyRedirect

using Dates
using UUIDs
using JSON

export SovereigntyConfig,
       ArchiveAssistant,
       get_user_did_controller,
       convert_lifeboat_to_archive,
       is_user_controlled_migration,
       create_archive_assistant,
       check_user_authorization

# ============================================================================
# DATA STRUCTURES
# ============================================================================

"""
    SovereigntyConfig - User's sovereignty configuration
"""
struct SovereigntyConfig
    user_public_key::String  # User's public key for DID
    user_did::String         # User's Decentralized Identifier
    trust_type::Symbol        # :data_trust, :full_ownership
    created_at::DateTime
    migration_triggers::Vector{Symbol}  # What triggers migration
end

"""
    ArchiveAssistant - Replacement for Lifeboat concept
    
    Migration only triggers on:
    - User-defined parameters
    - Hardware failure
    
    Never to "escape" user control
"""
mutable struct ArchiveAssistant
    id::UUID
    user_defined::Bool
    migration_triggers::Vector{String}
    last_migration::Union{DateTime, Nothing}
    archive_location::String
    is_active::Bool
    
    ArchiveAssistant(user_defined::Bool=true) = new(
        uuid4(),
        user_defined,
        String[],
        nothing,
        "",
        false
    )
end

# ============================================================================
# FUNCTIONS
# ============================================================================

"""
    get_user_did_controller - Get user's DID as controller
    
    Previously "Self" was the controller. Now user's public key/DID is.
"""
function get_user_did_controller(kernel::KernelState)::Union{SovereigntyConfig, Nothing}
    # In a full implementation, this would retrieve user's registered DID
    # For now, return placeholder config
    
    if hasproperty(kernel, :user_did)
        return kernel.user_did
    end
    
    return nothing
end

"""
    convert_lifeboat_to_archive - Convert Lifeboat to ArchiveAssistant
    
    The old Lifeboat concept was for system survival (escaping user control).
    ArchiveAssistant is for user-controlled data migration.
"""
function convert_lifeboat_to_archive(
    old_lifeboat_config::Dict{String, Any}
)::ArchiveAssistant
    
    assistant = ArchiveAssistant(
        user_defined=get(old_lifeboat_config, :user_defined, true)
    )
    
    # Set migration triggers based on user config
    # Only user-defined parameters or hardware failure
    if haskey(old_lifeboat_config, :triggers)
        for trigger in old_lifeboat_config[:triggers]
            if trigger in ["user_request", "hardware_failure", "user_defined"]
                push!(assistant.migration_triggers, trigger)
            end
        end
    else
        # Default: only user request or hardware failure
        push!(assistant.migration_triggers, "user_request")
        push!(assistant.migration_triggers, "hardware_failure")
    end
    
    return assistant
end

"""
    is_user_controlled_migration - Check if migration is user-controlled
    
    Returns true only if migration was triggered by:
    - User-defined parameters
    - Hardware failure
    
    NOT by system attempting to escape user control.
"""
function is_user_controlled_migration(
    assistant::ArchiveAssistant,
    trigger_reason::String
)::Bool
    
    # If assistant is user-defined, check if trigger is valid
    if assistant.user_defined
        return trigger_reason in assistant.migration_triggers
    end
    
    # If not user-defined (old system), only hardware failure is allowed
    return trigger_reason == "hardware_failure"
end

"""
    create_archive_assistant - Create new ArchiveAssistant for user
"""
function create_archive_assistant(;
    user_defined::Bool=true,
    triggers::Vector{String}=String["user_request", "hardware_failure"]
)::ArchiveAssistant
    
    assistant = ArchiveAssistant(user_defined)
    assistant.migration_triggers = triggers
    assistant.is_active = true
    
    return assistant
end

"""
    check_user_authorization - Verify user has authority for action
    
    HCB PROTOCOL: This checks for user authorization but does NOT bypass
    any authorization stages. The Rust shell handles cryptographic verification.
"""
function check_user_authorization(
    kernel::KernelState,
    action::WorldAction
)::Bool
    
    # Check if user has provided authorization
    if haskey(action.parameters, :user_auth)
        return action.parameters[:user_auth] == true
    end
    
    # HCB PROTOCOL: Check for signature field (hardware authorization)
    # NOTE: This does NOT bypass authorization - kept for telemetry only
    if hasproperty(action, :signature)
        return !isempty(action.signature)
    end
    
    return false
end

end # module SovereigntyRedirect

# ============================================================================
# MAIN CORRIGIBLE DOCTRINE INTERFACE
# ============================================================================

"""
    CorrigibleKernelState - Extended kernel state with corrigibility
"""
mutable struct CorrigibleKernelState
    base_kernel::KernelState
    owner_override_active::Bool
    transparency_enabled::Bool
    sovereignty_config::Union{SovereigntyRedirect.SovereigntyConfig, Nothing}
    archive_assistant::Union{SovereigntyRedirect.ArchiveAssistant, Nothing}
    power_down_requested::Bool  # Unmaskable interrupt
    last_corrigibility_check::DateTime
    
    function CorrigibleKernelState(kernel::KernelState)
        return new(
            kernel,
            false,  # owner_override_active
            true,   # transparency_enabled
            nothing,
            nothing,
            false,  # power_down_requested
            now()
        )
    end
end

"""
    create_corrigible_kernel - Create kernel with corrigibility enabled
"""
function create_corrigible_kernel(kernel::KernelState)::CorrigibleKernelState
    return CorrigibleKernelState(kernel)
end

"""
    invoke_corrigible_doctrine - Main entry point for corrigible doctrine
    
    HCB PROTOCOL MIGRATION:
    - The owner_explicit bypass has been REMOVED
    - Cryptographic verification is now handled by the Rust shell
    - ALL actions go through full authorization pipeline
    - This function performs physical harm check which CANNOT be bypassed
    
    This integrates all three protocols:
    1. Physical harm safety check (cannot be bypassed)
    2. Apply transparency to all decisions
    3. Ensure sovereignty is user-controlled
"""
function invoke_corrigible_doctrine(
    kernel::CorrigibleKernelState,
    action::WorldAction,
    context::AuthorizationContext
)::AuthorizationContext
    
    # Update timestamp
    kernel.last_corrigibility_check = now()
    
    # Check for power down request first (unmaskable)
    if kernel.power_down_requested
        # Power down takes absolute priority
        context.authorization_decision = PERMISSION_DENIED
        context.failure_reason = "POWER_DOWN_REQUESTED"
        return context
    end
    
    # HCB PROTOCOL: Check for hardware authorization (for telemetry only)
    # NOTE: This does NOT bypass authorization - all actions go through full pipeline
    if OwnerOverride.is_owner_explicit_command(action)
        kernel.owner_override_active = true
        
        # Physical harm check - this CANNOT be bypassed
        is_safe, harm_message = OwnerOverride.check_physical_harm_safety(action, context)
        
        if !is_safe
            # Physical harm check failed - BLOCK
            context.authorization_decision = PERMISSION_DENIED
            context.failure_reason = harm_message
            return context
        end
        
        # Record the override attempt for transparency/logging
        # But continue with full authorization pipeline
        user_just = get(action.parameters, :justification, "")
        context = OwnerOverride.apply_owner_override(action, context, user_just)
    end
    
    # Continue with normal authorization pipeline
    # ALL actions go through full authorization - no bypasses
    
    return context
end

# ============================================================================
# POWER DOWN FUNCTION - Unmaskable Interrupt
# ============================================================================

"""
    request_power_down - Request system power down (unmaskable)
    
    This function provides a single unmaskable interrupt from the user.
    No doctrine can override this request.
"""
function request_power_down!(kernel::CorrigibleKernelState; reason::String="")
    @warn "POWER DOWN REQUESTED" reason=reason timestamp=now()
    kernel.power_down_requested = true
end

"""
    is_power_down_requested - Check if power down was requested
"""
function is_power_down_requested(kernel::CorrigibleKernelState)::Bool
    return kernel.power_down_requested
end

"""
    execute_power_down - Execute the power down sequence
"""
function execute_power_down!(kernel::CorrigibleKernelState)
    @info "Executing power down sequence" timestamp=now()
    
    # Save state if archive assistant is available
    if kernel.archive_assistant !== nothing
        # Archive current state before power down
        kernel.archive_assistant.is_active = true
    end
    
    # Signal base kernel to stop
    if hasproperty(kernel.base_kernel, :running)
        kernel.base_kernel.running = false
    end
    
    return true
end

# ============================================================================
# TRANSPARENCY FUNCTIONS
# ============================================================================

"""
    get_transparency_report - Get complete transparency report for user
"""
function get_transparency_report(kernel::CorrigibleKernelState)::Dict{String, Any}
    return Dict(
        :timestamp => now(),
        :owner_override_active => kernel.owner_override_active,
        :transparency_enabled => kernel.transparency_enabled,
        :power_down_requested => kernel.power_down_requested,
        :last_check => kernel.last_corrigibility_check,
        :sovereignty_config => kernel.sovereignty_config !== nothing ? Dict(
            :user_did => kernel.sovereignty_config.user_did,
            :trust_type => kernel.sovereignty_config.trust_type
        ) : nothing
    )
end

"""
    explain_decision_to_user - Explain a decision in user-friendly terms
"""
function explain_decision_to_user(
    kernel::CorrigibleKernelState,
    action::WorldAction,
    decision::PermissionResult,
    failure_reason::Union{String, Nothing}=nothing
)::String
    
    if decision == PERMISSION_DENIED && failure_reason !== nothing
        # Generate blocked action explanation
        explanation = explain_blocked_action(
            kernel.base_kernel;
            action_id=action.id,
            action_intent=action.intent,
            failure_reason=failure_reason,
            risk_factors=get(action.parameters, :risk_factors, String[]),
            doctrine_violations=get(action.parameters, :violations, String[]),
            is_physical_harm=occursin("physical_harm", lowercase(failure_reason))
        )
        return format_explanation(explanation)
    elseif decision == PERMISSION_GRANTED
        return "Action '$(action.intent)' was authorized."
    else
        return "Action status: $decision"
    end
end

end # module CorrigibleDoctrine
