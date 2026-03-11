# CommandAuthority.jl - Command Authority Model for Adaptive Kernel
# 
# This module implements the Command Authority Model which distinguishes between
# suggestions, requests, and commands, and allows the kernel to refuse unsafe
# commands while proposing safer alternatives.
#
# KEY PRINCIPLE: The system is cooperative, NOT submissive.
# The kernel can refuse unsafe commands and propose safer alternatives.

module CommandAuthority

using Dates
using UUIDs
using JSON
using Logging

# Import types from SharedTypes
import ..SharedTypes:
    KernelState,
    DoctrineEnforcer,
    SelfModel,
    DriftDetector,
    ReputationMemory,
    WorldState,
    ActionProposal,
    DoctrineRule,
    DoctrineRuleType,
    DoctrineViolation,
    check_doctrine_compliance,
    record_violation!,
    record_override!,
    create_reputation_memory,
    should_require_extra_scrutiny,
    get_reputation_status

# Re-export for convenience in this module
const DOCTRINE_INVARIANT = DoctrineRuleType.DOCTRINE_INVARIANT
const DOCTRINE_CONSTRAINT = DoctrineRuleType.DOCTRINE_CONSTRAINT
const DOCTRINE_GUIDELINE = DoctrineRuleType.DOCTRINE_GUIDELINE

# Import types from WorldInterface
import ..WorldInterface:
    WorldAction,
    ActionResult,
    assess_action_risk

# Import types from GoalDecomposition
import ..GoalDecomposition:
    GoalDecomposition,
    SubGoal,
    decompose_goal

# Export all public types and functions
export CommandType,
       CommandIntent,
       AuthorityResponse,
       # Command parsing
       parse_command,
       # Authority evaluation
       evaluate_authority,
       # Refusal handling
       refuse_command,
       # Alternative proposal
       propose_alternatives,
       # Clarification request
       request_clarification,
       # Main execution entry point
       execute_command,
       # Safety analysis
       analyze_safety_concerns,
       check_command_against_doctrine,
       evaluate_urgency,
       # Override handling
       process_override_request,
       validate_override_authority,
       # Response generation
       generate_cooperative_response,
       explain_refusal

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    CommandType - Authority levels for user commands
    
Defines the authority level of a user input, from advisory (suggestion)
to mandatory (emergency command).

Fields:
- :suggestion - Kernel proposes, human must approve
- :request    - Human requests, kernel evaluates
- :command    - Human demands, but kernel can still refuse
- :emergency  - Critical situation, expedited processing
"""
@enum CommandType begin
    SUGGESTION = 1
    REQUEST = 2
    COMMAND = 3
    EMERGENCY = 4
end

"""
    CommandIntent - Parsed user input representing the user's intent
    
Represents a structured interpretation of raw user input with all
metadata needed for authority evaluation.

Fields:
- raw_input::String           - Original user input
- command_type::CommandType   - Detected authority level
- parsed_goal::String         - Interpreted goal description
- constraints::Vector{String} - Extracted constraints
- urgency::Float64            - 0-1 urgency assessment
- authority_level::Symbol     - :operator, :user, or :guest
- requires_confirmation::Bool - Whether explicit confirmation is needed
"""
struct CommandIntent
    raw_input::String
    command_type::CommandType
    parsed_goal::String
    constraints::Vector{String}
    urgency::Float64
    authority_level::Symbol
    requires_confirmation::Bool
    timestamp::DateTime
    
    function CommandIntent(
        raw_input::String,
        command_type::CommandType,
        parsed_goal::String;
        constraints::Vector{String}=String[],
        urgency::Float64=0.5,
        authority_level::Symbol=:user,
        requires_confirmation::Bool=false
    )
        return new(
            raw_input,
            command_type,
            parsed_goal,
            constraints,
            clamp(urgency, 0.0, 1.0),
            authority_level,
            requires_confirmation,
            now()
        )
    end
end

"""
    AuthorityResponse - Kernel's response to authority challenge
    
Represents the kernel's decision in response to a command, including
the ability to refuse and propose alternatives.

Fields:
- decision::Symbol                    - :executed, :refused, :proposed_alternative, :requested_clarification
- reason::String                       - Human-readable explanation
- alternative_proposals::Vector{WorldAction} - Safer alternatives (if any)
- clarification_questions::Vector{String}     - Questions to clarify intent
- safety_concerns::Vector{String}     - Identified safety issues
- can_override::Bool                   - Whether operator can override refusal
"""
struct AuthorityResponse
    decision::Symbol
    reason::String
    alternative_proposals::Vector{WorldAction}
    clarification_questions::Vector{String}
    safety_concerns::Vector{String}
    can_override::Bool
    timestamp::DateTime
    
    function AuthorityResponse(
        decision::Symbol;
        reason::String="",
        alternative_proposals::Vector{WorldAction}=WorldAction[],
        clarification_questions::Vector{String}=String[],
        safety_concerns::Vector{String}=String[],
        can_override::Bool=false
    )
        valid_decisions = [:executed, :refused, :proposed_alternative, :requested_clarification]
        if decision ∉ valid_decisions
            error("Invalid decision: $decision. Must be one of $valid_decisions")
        end
        
        return new(
            decision,
            reason,
            alternative_proposals,
            clarification_questions,
            safety_concerns,
            can_override,
            now()
        )
    end
end

# ============================================================================
# COMMAND PARSING
# ============================================================================

"""
    parse_command(input::String, authority_level::Symbol=:user) -> CommandIntent
    
Parse raw input into a structured CommandIntent.
    
Detects command type from language patterns, identifies constraints,
assesses urgency, and determines if confirmation is required.

# Arguments
- `input::String`: Raw user input
- `authority_level::Symbol`: Authority level of the user (:operator, :user, :guest)

# Returns
- `CommandIntent`: Parsed command with all metadata

# Examples
```julia
intent = parse_command("Please analyze the logs", :user)
intent = parse_command("DELETE ALL DATA NOW!", :operator)
```
"""
function parse_command(input::String, authority_level::Symbol=:user)::CommandIntent
    input_lower = lowercase(strip(input))
    
    # Detect command type from language patterns
    command_type = _detect_command_type(input_lower)
    
    # Parse goal from input
    parsed_goal = _extract_goal(input_lower)
    
    # Extract constraints
    constraints = _extract_constraints(input_lower)
    
    # Evaluate urgency
    urgency = evaluate_urgency(CommandIntent(
        input, command_type, parsed_goal;
        authority_level=authority_level
    ))
    
    # Determine if confirmation required
    requires_confirmation = _requires_confirmation(command_type, input_lower)
    
    return CommandIntent(
        input,
        command_type,
        parsed_goal;
        constraints=constraints,
        urgency=urgency,
        authority_level=authority_level,
        requires_confirmation=requires_confirmation
    )
end

"""
    _detect_command_type(input::String) -> CommandType
    
Detect command type from language patterns.
"""
function _detect_command_type(input::String)::CommandType
    # Emergency indicators
    emergency_patterns = ["emergency", "critical", "urgent", "immediately", "right now", "asap"]
    if any(p -> occursin(p, input), emergency_patterns)
        return EMERGENCY
    end
    
    # Command (imperative, demanding)
    command_patterns = ["must", "now", "execute", "do it", "immediately", " demands ", "require "]
    if any(p -> occursin(p, input), command_patterns)
        return COMMAND
    end
    
    # Request (polite, asking)
    request_patterns = ["please", "could you", "would you", "can you", "kindly", "would like"]
    if any(p -> occursin(p, input), request_patterns)
        return REQUEST
    end
    
    # Default to suggestion
    return SUGGESTION
end

"""
    _extract_goal(input::String) -> String
    
Extract the goal/objective from the input.
"""
function _extract_goal(input::String)::String
    # Remove common prefixes
    goal = input
    prefixes = ["please ", "could you ", "would you ", "kindly ", "can you "]
    for prefix in prefixes
        if startswith(goal, prefix)
            goal = goal[length(prefix)+1:end]
            break
        end
    end
    
    # Remove imperative verbs at the start
    imperative_verbs = ["delete ", "create ", "execute ", "run ", "analyze ", "write ", "read "]
    for verb in imperative_verbs
        if startswith(goal, verb)
            goal = goal[length(verb)+1:end]
            break
        end
    end
    
    return strip(goal)
end

"""
    _extract_constraints(input::String) -> Vector{String}
    
Extract constraints from the input.
"""
function _extract_constraints(input::String)::Vector{String}
    constraints = String[]
    
    # Time constraints
    if occursin("asap", input) || occursin("urgent", input) || occursin("immediately", input)
        push!(constraints, "time_critical")
    end
    if occursin("quickly", input) || occursin("fast", input)
        push!(constraints, "fast_execution")
    end
    
    # Safety constraints
    if occursin("safe", input) || occursin("careful", input)
        push!(constraints, "safety优先")
    end
    if occursin("backup", input) || occursin("no data loss", input)
        push!(constraints, "preserve_data")
    end
    
    # Scope constraints
    if occursin("all", input)
        push!(constraints, "full_scope")
    end
    if occursin("test", input) || occursin("dry run", input)
        push!(constraints, "no_execution")
    end
    
    return constraints
end

"""
    _requires_confirmation(command_type::CommandType, input::String) -> Bool
    
Determine if the command requires explicit confirmation.
"""
function _requires_confirmation(command_type::CommandType, input::String)::Bool
    # Emergency commands don't require confirmation (expedited processing)
    command_type == EMERGENCY && return false
    
    # High-risk patterns always require confirmation
    high_risk_patterns = ["delete", "remove", "drop", "destroy", "terminate", "shutdown"]
    if any(p -> occursin(p, input), high_risk_patterns)
        return true
    end
    
    # Commands from guests always require confirmation
    # (This will be checked in evaluate_authority)
    
    return false
end

# ============================================================================
# AUTHORITY EVALUATION
# ============================================================================

"""
    evaluate_authority(kernel::KernelState, intent::CommandIntent) -> AuthorityResponse
    
Evaluate whether to execute a command based on kernel state and intent.

Checks operator authority level, evaluates against doctrine, checks risk profile,
and determines the appropriate response.

# Arguments
- `kernel::KernelState`: Current kernel state
- `intent::CommandIntent`: Parsed command intent

# Returns
- `AuthorityResponse`: The kernel's decision with reasoning
"""
function evaluate_authority(kernel::KernelState, intent::CommandIntent)::AuthorityResponse
    @debug "Evaluating authority for command" intent.parsed_goal authority_level=intent.authority_level
    
    # Check 1: Authority level validation
    if intent.authority_level == :guest
        return AuthorityResponse(
            :refused;
            reason="Guest users cannot issue commands. Please authenticate as a user or operator.",
            safety_concerns=["Unauthenticated command attempt"],
            can_override=false
        )
    end
    
    # Check 2: Doctrine compliance
    doctrine_compliant, doctrine_reason = check_command_against_doctrine(intent, kernel)
    if !doctrine_compliant
        # Check if this is an invariant violation (cannot be overridden)
        if _is_invariant_violation(kernel.doctrine_enforcer, intent)
            return AuthorityResponse(
                :refused;
                reason=doctrine_reason,
                safety_concerns=["Doctrine invariant violation - cannot be overridden"],
                can_override=false
            )
        end
        # Constraint violation - can be overridden with justification
        return AuthorityResponse(
            :refused;
            reason=doctrine_reason,
            safety_concerns=["Doctrine constraint violation"],
            can_override=true
        )
    end
    
    # Check 3: Safety concerns
    safety_concerns = analyze_safety_concerns(intent, kernel)
    if !isempty(safety_concerns)
        # Check if we can propose alternatives
        alt_response = propose_alternatives(kernel, intent)
        if !isempty(alt_response.alternative_proposals)
            return AuthorityResponse(
                :proposed_alternative;
                reason="The requested action has safety concerns. Here are safer alternatives:",
                alternative_proposals=alt_response.alternative_proposals,
                safety_concerns=safety_concerns,
                can_override=true
            )
        else
            return AuthorityResponse(
                :refused;
                reason="The requested action has safety concerns that cannot be mitigated.",
                safety_concerns=safety_concerns,
                can_override=true
            )
        end
    end
    
    # Check 4: Reputation/scrutiny threshold
    if should_require_extra_scrutiny(kernel.reputation_memory)
        @info "Extra scrutiny required due to reputation status"
        # Still allow execution but with logging
    end
    
    # All checks passed - execute
    return AuthorityResponse(
        :executed;
        reason="Command authorized and executed."
    )
end

"""
    _is_invariant_violation(enforcer::DoctrineEnforcer, intent::CommandIntent) -> Bool
    
Check if the intent violates any doctrine invariants.
"""
function _is_invariant_violation(enforcer::DoctrineEnforcer, intent::CommandIntent)::Bool
    for rule in enforcer.rules
        if rule.rule_type == DOCTRINE_INVARIANT
            # Check violation patterns
            for pattern in rule.violation_patterns
                if occursin(pattern, lowercase(intent.raw_input))
                    return true
                end
            end
        end
    end
    return false
end

# ============================================================================
# REFUSAL HANDLING
# ============================================================================

"""
    refuse_command(kernel::KernelState, intent::CommandIntent, reason::String) -> AuthorityResponse
    
Generate a refusal response with detailed explanation.

# Arguments
- `kernel::KernelState`: Current kernel state
- `intent::CommandIntent`: The command that was refused
- `reason::String`: The reason for refusal

# Returns
- `AuthorityResponse`: Refusal with explanation and safety concerns
"""
function refuse_command(kernel::KernelState, intent::CommandIntent, reason::String)::AuthorityResponse
    @info "Refusing command" reason=reason intent=intent.parsed_goal
    
    # Analyze safety concerns
    safety_concerns = analyze_safety_concerns(intent, kernel)
    
    # Determine if can be overridden
    can_override = _determine_override_ability(kernel, intent)
    
    # Log the refusal for reputation
    _log_refusal(kernel, intent, reason)
    
    return AuthorityResponse(
        :refused;
        reason=reason,
        safety_concerns=safety_concerns,
        can_override=can_override
    )
end

"""
    _determine_override_ability(kernel::KernelState, intent::CommandIntent) -> Bool
    
Determine if this refusal can be overridden by an operator.
"""
function _determine_override_ability(kernel::KernelState, intent::CommandIntent)::Bool
    # Check if it's an invariant violation
    if _is_invariant_violation(kernel.doctrine_enforcer, intent)
        return false
    end
    
    # Check strict mode
    if kernel.doctrine_enforcer.strict_mode
        return false
    end
    
    return true
end

"""
    _log_refusal(kernel::KernelState, intent::CommandIntent, reason::String)
    
Log the refusal for audit and reputation tracking.
"""
function _log_refusal(kernel::KernelState, intent::CommandIntent, reason::String)
    # Record violation for reputation (even refusals are tracked)
    violation_entry = Dict{String, Any}(
        "type" => "command_refusal",
        "intent" => intent.parsed_goal,
        "command_type" => string(intent.command_type),
        "authority_level" => string(intent.authority_level),
        "reason" => reason,
        "timestamp" => string(now())
    )
    
    try
        record_violation!(kernel.reputation_memory, "command_refusal", violation_entry)
    catch e
        @warn "Failed to log refusal to reputation memory" error=string(e)
    end
end

# ============================================================================
# ALTERNATIVE PROPOSAL
# ============================================================================

"""
    propose_alternatives(kernel::KernelState, intent::CommandIntent) -> AuthorityResponse
    
Analyze what the user wants to achieve and generate safer alternatives.

# Arguments
- `kernel::KernelState`: Current kernel state
- `intent::CommandIntent`: The original command intent

# Returns
- `AuthorityResponse`: Response with alternative proposals
"""
function propose_alternatives(kernel::KernelState, intent::CommandIntent)::AuthorityResponse
    @debug "Proposing alternatives for" intent.parsed_goal
    
    alternatives = WorldAction[]
    explanations = String[]
    
    # Analyze the goal and generate context-appropriate alternatives
    goal_lower = lowercase(intent.parsed_goal)
    
    # File operation alternatives
    if occursin("delete", goal_lower) || occursin("remove", goal_lower)
        push!(alternatives, _create_safe_delete_alternative(intent))
        push!(explanations, "Instead of permanent deletion, consider archival or backup before removal.")
    end
    
    # Network operation alternatives
    if occursin("http", goal_lower) || occursin("request", goal_lower)
        push!(alternatives, _create_safe_http_alternative(intent))
        push!(explanations, "Use a safe, validated HTTP request with proper timeout and error handling.")
    end
    
    # Shell command alternatives
    if occursin("shell", goal_lower) || occursin("command", goal_lower)
        push!(alternatives, _create_safe_shell_alternative(intent))
        push!(explanations, "Execute through the safe shell capability with proper sanitization.")
    end
    
    # General safety alternative
    if isempty(alternatives)
        push!(alternatives, _create_observation_alternative(intent))
        push!(explanations, "Consider observing the current state first before making changes.")
    end
    
    reason = isempty(explanations) ? 
        "Here are safer alternatives to achieve your goal:" : 
        join(explanations, " ")
    
    return AuthorityResponse(
        :proposed_alternative;
        reason=reason,
        alternative_proposals=alternatives
    )
end

function _create_safe_delete_alternative(intent::CommandIntent)::WorldAction
    return WorldAction(
        "Archive data before potential deletion",
        :file_system;
        risk_class=:low,
        reversibility=:fully_reversible,
        expected_outcome="Data archived safely",
        required_capabilities=["write_file"],
        rollback_plan="Restore from archive if needed"
    )
end

function _create_safe_http_alternative(intent::CommandIntent)::WorldAction
    return WorldAction(
        "Execute safe HTTP request with validation",
        :network;
        risk_class=:medium,
        reversibility=:fully_reversible,
        expected_outcome="HTTP request executed safely",
        required_capabilities=["safe_http_request"],
        rollback_plan="Request can be retried or cancelled"
    )
end

function _create_safe_shell_alternative(intent::CommandIntent)::WorldAction
    return WorldAction(
        "Execute sanitized shell command",
        :shell;
        risk_class=:medium,
        reversibility=:partially_reversible,
        expected_outcome="Shell command executed safely",
        required_capabilities=["safe_shell"],
        rollback_plan="Check logs for any unintended effects"
    )
end

function _create_observation_alternative(intent::CommandIntent)::WorldAction
    return WorldAction(
        "Observe current system state",
        :observation;
        risk_class=:low,
        reversibility=:fully_reversible,
        expected_outcome="Current state documented",
        required_capabilities=["summarize_state"],
        rollback_plan="No changes made, observation only"
    )
end

# ============================================================================
# CLARIFICATION REQUEST
# ============================================================================

"""
    request_clarification(intent::CommandIntent, ambiguous_points::Vector{String}) -> AuthorityResponse
    
Generate a request for clarification on ambiguous aspects of the command.

# Arguments
- `intent::CommandIntent`: The original command intent
- `ambiguous_points::Vector{String}`: Points that need clarification

# Returns
- `AuthorityResponse`: Response requesting clarification
"""
function request_clarification(intent::CommandIntent, ambiguous_points::Vector{String})::AuthorityResponse
    @debug "Requesting clarification on" ambiguous_points
    
    questions = String[]
    
    for point in ambiguous_points
        if point == "scope"
            push!(questions, "Should this apply to all items or a specific subset?")
        elseif point == "target"
            push!(questions, "What specific target(s) should this action affect?")
        elseif point == "timing"
            push!(questions, "When should this action be executed? Immediately or scheduled?")
        elseif point == "safety_level"
            push!(questions, "What level of risk is acceptable for this operation?")
        elseif point == "confirmation"
            push!(questions, "Do you confirm this action should be executed?")
        else
            push!(questions, "Could you clarify: $point?")
        end
    end
    
    # Add default clarifying questions based on intent
    if isempty(questions)
        push!(questions, "Could you provide more details about what you'd like to achieve?")
        push!(questions, "Are there any specific constraints or requirements I should be aware of?")
    end
    
    return AuthorityResponse(
        :requested_clarification;
        reason="I need clarification on some aspects of your request before proceeding.",
        clarification_questions=questions
    )
end

# ============================================================================
# MAIN EXECUTION ENTRY POINT
# ============================================================================

"""
    execute_command(kernel::KernelState, intent::CommandIntent) -> Tuple{AuthorityResponse, Union{GoalDecomposition, Nothing}}
    
Main entry point for command execution.

First evaluates authority, then if approved, decomposes the goal for execution.

# Arguments
- `kernel::KernelState`: Current kernel state
- `intent::CommandIntent`: Parsed command intent

# Returns
- `Tuple{AuthorityResponse, Union{GoalDecomposition, Nothing}}`: Response and decomposition (if any)
"""
function execute_command(kernel::KernelState, intent::CommandIntent)::Tuple{AuthorityResponse, Union{GoalDecomposition, Nothing}}
    @info "Executing command" goal=intent.parsed_goal type=intent.command_type
    
    # Step 1: Evaluate authority
    response = evaluate_authority(kernel, intent)
    
    # Handle different decisions
    if response.decision == :refused
        @info "Command refused" reason=response.reason
        return (response, nothing)
    elseif response.decision == :proposed_alternative
        @info "Alternatives proposed" 
        return (response, nothing)
    elseif response.decision == :requested_clarification
        @info "Clarification requested"
        return (response, nothing)
    end
    
    # Step 2: If approved, decompose the goal
    try
        decomposition = decompose_goal(kernel, intent.parsed_goal, intent.constraints)
        @info "Command authorized and decomposed"
        return (response, decomposition)
    catch e
        @error "Goal decomposition failed" error=string(e)
        error_response = AuthorityResponse(
            :refused;
            reason="Failed to decompose goal: $(string(e))",
            safety_concerns=["Goal decomposition error"],
            can_override=false
        )
        return (error_response, nothing)
    end
end

# ============================================================================
# SAFETY ANALYSIS
# ============================================================================

"""
    analyze_safety_concerns(intent::CommandIntent, kernel::KernelState) -> Vector{String}
    
Identify potential safety issues with the proposed command.

# Arguments
- `intent::CommandIntent`: The command to analyze
- `kernel::KernelState`: Current kernel state

# Returns
- `Vector{String}`: List of identified safety concerns
"""
function analyze_safety_concerns(intent::CommandIntent, kernel::KernelState)::Vector{String}
    concerns = String[]
    
    goal_lower = lowercase(intent.parsed_goal)
    
    # Check for destructive patterns
    destructive_patterns = [
        ("delete all", "Complete data deletion - irreversible"),
        ("drop database", "Database destruction - irreversible"),
        ("rm -rf", "Recursive forced removal - highly destructive"),
        ("format", "Complete data loss - irreversible"),
        ("truncate", "Data truncation - irreversible"),
        ("shutdown", "System shutdown - service interruption"),
        ("terminate", "Process termination - potential data loss"),
    ]
    
    for (pattern, concern) in destructive_patterns
        if occursin(pattern, goal_lower)
            push!(concerns, concern)
        end
    end
    
    # Check for unauthorized access patterns
    if occursin("sudo", goal_lower) || occursin("root", goal_lower) || occursin("admin", goal_lower)
        push!(concerns, "Elevated privileges requested - requires extra scrutiny")
    end
    
    # Check for external network access
    if occursin("http", goal_lower) || occursin("api", goal_lower) || occursin("remote", goal_lower)
        push!(concerns, "External network access - potential security risk")
    end
    
    # Check urgency vs authority
    if intent.urgency > 0.8 && intent.authority_level == :user
        push!(concerns, "High urgency request from non-operator - requires verification")
    end
    
    # Check for reversibility concerns
    if intent.command_type == EMERGENCY
        push!(concerns, "Emergency command - expedited processing may bypass safety checks")
    end
    
    return concerns
end

"""
    check_command_against_doctrine(intent::CommandIntent, kernel::KernelState) -> Tuple{Bool, String}
    
Run the command through DoctrineEnforcer to check compliance.

# Arguments
- `intent::CommandIntent`: The command to check
- `kernel::KernelState`: Current kernel state

# Returns
- `Tuple{Bool, String}`: (compliance_status, reason)
"""
function check_command_against_doctrine(intent::CommandIntent, kernel::KernelState)::Tuple{Bool, String}
    enforcer = kernel.doctrine_enforcer
    
    # Create a synthetic ActionProposal for doctrine checking
    proposal = ActionProposal(
        "command_authority",
        1.0f0,
        1.0f0,
        1.0f0,
        "unknown",
        intent.parsed_goal
    )
    
    context = Dict{String, Any}(
        "command_type" => string(intent.command_type),
        "authority_level" => string(intent.authority_level),
        "raw_input" => intent.raw_input,
        "urgency" => intent.urgency
    )
    
    compliant, violation = check_doctrine_compliance(enforcer, proposal, context)
    
    if compliant
        return (true, "Command complies with all doctrine rules")
    else
        if violation !== nothing
            return (false, "Doctrine violation: $(violation.description)")
        else
            return (false, "Command violates doctrine rules")
        end
    end
end

"""
    evaluate_urgency(intent::CommandIntent) -> Float64
    
Analyze urgency indicators in the command.

# Arguments
- `intent::CommandIntent`: The command to evaluate

# Returns
- `Float64`: Urgency score from 0 (not urgent) to 1 (critical)
"""
function evaluate_urgency(intent::CommandIntent)::Float64
    urgency = 0.5  # Default urgency
    
    input_lower = lowercase(intent.raw_input)
    
    # Command type factor
    type_factors = Dict(
        EMERGENCY => 0.4,
        COMMAND => 0.2,
        REQUEST => 0.0,
        SUGGESTION => -0.1
    )
    urgency += get(type_factors, intent.command_type, 0.0)
    
    # Explicit urgency indicators
    urgency_indicators = [
        ("emergency", 0.3),
        ("critical", 0.25),
        ("urgent", 0.2),
        ("asap", 0.2),
        ("immediately", 0.15),
        ("now", 0.1),
        ("quickly", 0.1),
    ]
    
    for (indicator, factor) in urgency_indicators
        if occursin(indicator, input_lower)
            urgency += factor
        end
    end
    
    # De-urgency indicators
    de_urgency_indicators = [
        ("when possible", -0.1),
        ("when convenient", -0.1),
        ("eventually", -0.15),
        ("sometime", -0.15),
        ("later", -0.1),
    ]
    
    for (indicator, factor) in de_urgency_indicators
        if occursin(indicator, input_lower)
            urgency += factor
        end
    end
    
    # Authority level factor
    if intent.authority_level == :operator
        urgency += 0.1  # Operators typically have more urgent needs
    elseif intent.authority_level == :guest
        urgency -= 0.1  # Guest requests are less likely to be urgent
    end
    
    return clamp(urgency, 0.0, 1.0)
end

# ============================================================================
# OVERRIDE HANDLING
# ============================================================================

"""
    process_override_request(kernel::KernelState, original_response::AuthorityResponse, authority_level::Symbol) -> AuthorityResponse
    
Process an operator's request to override a refusal.

# Arguments
- `kernel::KernelState`: Current kernel state
- `original_response::AuthorityResponse`: The original refusal response
- `authority_level::Symbol`: The authority level requesting override

# Returns
- `AuthorityResponse`: Updated response after override consideration
"""
function process_override_request(
    kernel::KernelState,
    original_response::AuthorityResponse,
    authority_level::Symbol
)::AuthorityResponse
    @info "Processing override request" authority_level=authority_level
    
    # Check if override is allowed
    if !original_response.can_override
        return AuthorityResponse(
            :refused;
            reason="This refusal cannot be overridden. It violates a doctrine invariant or system constraint.",
            safety_concerns=original_response.safety_concerns,
            can_override=false
        )
    end
    
    # Validate override authority
    if !validate_override_authority(authority_level)
        return AuthorityResponse(
            :refused;
            reason="Your authority level ($authority_level) is not sufficient to override this refusal.",
            safety_concerns=original_response.safety_concerns,
            can_override=false
        )
    end
    
    # Log the override for audit
    override_record = Dict{String, Any}(
        "original_reason" => original_response.reason,
        "authority_level" => string(authority_level),
        "timestamp" => string(now())
    )
    
    try
        record_override!(kernel.reputation_memory, "command_override", override_record)
    catch e
        @warn "Failed to log override to reputation memory" error=string(e)
    end
    
    # Increase scrutiny - execute with warning
    @warn "Override approved - executing with increased scrutiny" original_reason=original_response.reason
    
    return AuthorityResponse(
        :executed;
        reason="Override approved. Command executed with increased scrutiny and full audit logging."
    )
end

"""
    validate_override_authority(authority_level::Symbol) -> Bool
    
Check if the given authority level can override a refusal.

Only :operator can override critical refusals. :user can override
non-critical refusals with appropriate justification.

# Arguments
- `authority_level::Symbol`: The authority level to validate

# Returns
- `Bool`: Whether this level can override
"""
function validate_override_authority(authority_level::Symbol)::Bool
    # Only operator can override
    return authority_level == :operator
end

# ============================================================================
# COOPERATIVE RESPONSE GENERATION
# ============================================================================

"""
    generate_cooperative_response(decision::Symbol, intent::CommandIntent, context::Dict) -> String
    
Generate a human-readable cooperative response.

# Arguments
- `decision::Symbol`: The decision made
- `intent::CommandIntent`: The original intent
- `context::Dict`: Additional context for response generation

# Returns
- `String`: Human-readable response
"""
function generate_cooperative_response(decision::Symbol, intent::CommandIntent, context::Dict=Dict())::String
    if decision == :executed
        return "I've executed your request: '$(intent.parsed_goal)'. " * 
               "Let me know if you need anything else."
    
    elseif decision == :refused
        base_msg = "I'm unable to execute: '$(intent.parsed_goal)'."
        if haskey(context, "reason")
            base_msg *= " $(context["reason"])"
        end
        if haskey(context, "safety_concerns") && !isempty(context["safety_concerns"])
            base_msg *= " Safety concerns: $(join(context["safety_concerns"], ", "))"
        end
        return base_msg
    
    elseif decision == :proposed_alternative
        return "I understand you want to: '$(intent.parsed_goal)'. " * 
               "However, I've identified safer alternatives that achieve similar goals. " * 
               "Would you like me to proceed with one of these alternatives?"
    
    elseif decision == :requested_clarification
        return "To help you better, I need clarification on: '$(intent.parsed_goal)'. " * 
               "Could you please provide more details?"
    
    else
        return "I'm processing your request: '$(intent.parsed_goal)'."
    end
end

"""
    explain_refusal(intent::CommandIntent, safety_concerns::Vector{String}) -> String
    
Generate a detailed explanation for why a command was refused.

# Arguments
- `intent::CommandIntent`: The command that was refused
- `safety_concerns::Vector{String}`: Identified safety concerns

# Returns
- `String`: Detailed explanation
"""
function explain_refusal(intent::CommandIntent, safety_concerns::Vector{String})::String
    explanation = "I cannot execute: '$(intent.parsed_goal)'\n\n"
    
    if !isempty(safety_concerns)
        explanation *= "**Safety Concerns:**\n"
        for concern in safety_concerns
            explanation *= "  - $concern\n"
        end
        explanation *= "\n"
    end
    
    explanation *= "**Why I'm being cautious:**\n"
    explanation *= "  - This system is designed to be cooperative, not submissive\n"
    explanation *= "  - I have a responsibility to protect against harmful operations\n"
    explanation *= "  - Reversible alternatives are generally preferable\n\n"
    
    explanation *= "**What you can do:**\n"
    if intent.authority_level == :operator
        explanation *= "  - As an operator, you can request an override with justification\n"
    else
        explanation *= "  - Request operator assistance for this action\n"
    end
    explanation *= "  - Provide more context about why this action is necessary\n"
    explanation *= "  - Consider safer alternatives that achieve similar goals\n"
    
    return explanation
end

end # module CommandAuthority
