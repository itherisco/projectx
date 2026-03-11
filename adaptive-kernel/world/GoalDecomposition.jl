# GoalDecomposition.jl - Strategic Goal Decomposition Engine for Adaptive Kernel
# 
# This module accepts high-level ambiguous human goals and decomposes them into
# executable sub-goals with proper planning, abort conditions, rollback paths,
# and doctrine-sensitive constraints.

module GoalDecomposition

using Dates
using UUIDs
using JSON
using Logging

# Import types from SharedTypes
import ..SharedTypes:
    KernelState,
    Goal,
    GoalState,
    WorldState,
    DoctrineEnforcer,
    SelfModel,
    CapabilityProfile,
    DriftDetector,
    ReputationMemory,
    ActionProposal,
    check_doctrine_compliance

# Import types from WorldInterface
import ..WorldInterface:
    WorldAction,
    ActionResult,
    assess_action_risk

# Import types from AuthorizationPipeline
import ..AuthorizationPipeline:
    AuthorizationContext

# Export all public types and functions
export GoalDecomposition,
       SubGoal,
       ActionChain,
       # StrategicPlanner functions
       decompose_goal,
       analyze_goal_requirements,
       generate_sub_goals,
       plan_action_chain,
       extract_doctrine_constraints,
       evaluate_plan_safety,
       recalculate_plan!,
       # Execution functions
       execute_decomposition!,
       execute_sub_goal!,
       abort_on_condition,
       rollback_to_checkpoint!,
       # Plan Analysis
       estimate_success_probability,
       explain_plan

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    SubGoal - Individual decomposable goal
    
    Represents a single sub-goal that can be executed independently.
    Each sub-goal has dependencies, actions, status, and rollback plan.
    
    Fields:
    - id: Unique identifier
    - description: Human-readable description
    - priority: 0-1 priority level
    - dependencies: IDs of sub-goals that must complete first
    - actions: Actions to achieve this sub-goal
    - status: :pending, :ready, :executing, :completed, :failed, :skipped
    - estimated_cost: Estimated computational cost
    - rollback_plan: How to undo if needed
"""
mutable struct SubGoal
    id::UUID
    description::String
    priority::Float64  # 0-1
    dependencies::Vector{UUID}
    actions::Vector{WorldAction}
    status::Symbol  # :pending, :ready, :executing, :completed, :failed, :skipped
    estimated_cost::Float64
    rollback_plan::Union{Nothing, String}
    created_at::DateTime
    started_at::Union{Nothing, DateTime}
    completed_at::Union{Nothing, DateTime}
    
    function SubGoal(
        description::String;
        priority::Float64=0.5,
        dependencies::Vector{UUID}=UUID[],
        actions::Vector{WorldAction}=WorldAction[],
        estimated_cost::Float64=1.0,
        rollback_plan::Union{Nothing, String}=nothing
    )
        return new(
            uuid4(),
            description,
            priority,
            dependencies,
            actions,
            :pending,
            estimated_cost,
            rollback_plan,
            now(),
            nothing,
            nothing
        )
    end
end

"""
    ActionChain - Sequence of actions for a sub-goal
    
    Ordered sequence of actions with checkpoint tracking.
    
    Fields:
    - id: Unique identifier
    - sub_goal_id: ID of parent sub-goal
    - actions: Ordered actions
    - current_action_index: Index of currently executing action
    - completed_actions: IDs of completed actions
    - failed_action_id: ID of failed action if any
"""
mutable struct ActionChain
    id::UUID
    sub_goal_id::UUID
    actions::Vector{WorldAction}
    current_action_index::Int
    completed_actions::Vector{UUID}
    failed_action_id::Union{Nothing, UUID}
    created_at::DateTime
    last_executed_at::Union{Nothing, DateTime}
    
    function ActionChain(
        sub_goal_id::UUID;
        actions::Vector{WorldAction}=WorldAction[]
    )
        return new(
            uuid4(),
            sub_goal_id,
            actions,
            1,  # Start at first action
            UUID[],
            nothing,
            now(),
            nothing
        )
    end
end

"""
    GoalDecomposition - Complete plan for achieving a goal
    
    A complete hierarchical plan with sub-goals, action chains, abort conditions,
    rollback paths, and doctrine constraints.
    
    Fields:
    - id: Unique identifier
    - root_goal: The original high-level goal
    - sub_goals: Decomposed sub-goals (max 7 - cognitive limit)
    - action_chains: Ordered action sequences
    - tool_requirements: Required capabilities
    - abort_conditions: Conditions that should abort execution
    - rollback_paths: How to rollback each sub-goal
    - doctrine_constraints: Doctrine-sensitive constraints
    - created_at: Creation timestamp
    - estimated_duration: Estimated time in seconds
    - complexity_score: Plan complexity (0-1)
    - status: :planning, :ready, :executing, :paused, :completed, :failed, :aborted
"""
mutable struct GoalDecomposition
    id::UUID
    root_goal::Goal
    sub_goals::Vector{SubGoal}
    action_chains::Vector{ActionChain}
    tool_requirements::Dict{String, Bool}
    abort_conditions::Vector{String}
    rollback_paths::Dict{UUID, String}
    doctrine_constraints::Vector{String}
    created_at::DateTime
    estimated_duration::Float64
    complexity_score::Float64
    status::Symbol
    last_updated::DateTime
    execution_log::Vector{Dict{String, Any}}
    
    function GoalDecomposition(
        root_goal::Goal;
        tool_requirements::Dict{String, Bool}=Dict{String, Bool}(),
        abort_conditions::Vector{String}=String[],
        rollback_paths::Dict{UUID, String}=Dict{UUID, String}(),
        doctrine_constraints::Vector{String}=String[],
        estimated_duration::Float64=0.0,
        complexity_score::Float64=0.5
    )
        return new(
            uuid4(),
            root_goal,
            SubGoal[],
            ActionChain[],
            tool_requirements,
            abort_conditions,
            rollback_paths,
            doctrine_constraints,
            now(),
            estimated_duration,
            complexity_score,
            :planning,
            now(),
            Dict{String, Any}[]
        )
    end
end

# ============================================================================
# STRATEGIC PLANNER - GOAL DECOMPOSITION FUNCTIONS
# ============================================================================

"""
    analyze_goal_requirements(goal_description::String) -> Dict
    
    Parse goal for required domains, identify capabilities, estimate complexity,
    and detect potential risks.
    
    # Arguments
    - goal_description: Human-readable goal description
    
    # Returns
    Dict with keys: :required_domains, :required_capabilities, :complexity_estimate, :potential_risks
"""
function analyze_goal_requirements(goal_description::String)::Dict{Symbol, Any}
    result = Dict{Symbol, Any}()
    
    # Parse required domains from goal description
    required_domains = String[]
    goal_lower = lowercase(goal_description)
    
    # Domain detection patterns
    domain_patterns = [
        ("file", "file", [:file_system]),
        ("directory", "dir", [:file_system]),
        ("folder", "folder", [:file_system]),
        ("write", "create", [:file_system]),
        ("read", "read", [:file_system]),
        ("download", "download", [:network, :file_system]),
        ("upload", "upload", [:network, :file_system]),
        ("http", "request", [:network]),
        ("api", "api", [:network]),
        ("web", "web", [:network]),
        ("shell", "shell", [:shell]),
        ("command", "cmd", [:shell]),
        ("process", "process", [:tool]),
        ("log", "log", [:observation]),
        ("analyze", "analyze", [:observation]),
        ("compare", "compare", [:tool]),
        ("schedule", "schedule", [:tool]),
        ("git", "git", [:shell]),
        ("network", "network", [:observation]),
        ("cpu", "cpu", [:observation]),
        ("memory", "memory", [:observation]),
    ]
    
    for (domain, keyword, action_types) in domain_patterns
        if occursin(keyword, goal_lower)
            push!(required_domains, domain)
        end
    end
    
    # If no domains detected, assume file_system as default
    if isempty(required_domains)
        push!(required_domains, "file_system")
    end
    
    result[:required_domains] = required_domains
    
    # Map domains to required capabilities
    capability_map = Dict(
        "file_system" => ["write_file", "observe_filesystem"],
        "network" => ["safe_http_request", "observe_network"],
        "shell" => ["safe_shell"],
        "tool" => ["compare_strategies", "simulate_outcomes", "task_scheduler"],
        "observation" => ["observe_cpu", "observe_processes", "analyze_logs", "summarize_state"]
    )
    
    required_capabilities = String[]
    for domain in required_domains
        if haskey(capability_map, domain)
            append!(required_capabilities, capability_map[domain])
        end
    end
    
    # Always add analyze_logs for goal analysis
    if "analyze_logs" ∉ required_capabilities
        push!(required_capabilities, "analyze_logs")
    end
    
    result[:required_capabilities] = unique(required_capabilities)
    
    # Estimate complexity based on multiple factors
    complexity_estimate = 0.0
    
    # Length-based complexity
    word_count = length(split(goal_description))
    complexity_estimate += min(0.3, word_count / 100.0)
    
    # Multi-step indicators
    multi_step_indicators = ["then", "after", "next", "before", "first", "finally", "and then"]
    for indicator in multi_step_indicators
        if occursin(indicator, goal_lower)
            complexity_estimate += 0.15
        end
    end
    
    # Conditional indicators
    conditional_indicators = ["if", "when", "unless", "depending"]
    for indicator in conditional_indicators
        if occursin(indicator, goal_lower)
            complexity_estimate += 0.1
        end
    end
    
    # Risky operation indicators
    risky_indicators = ["delete", "remove", "destroy", "terminate", "kill", "overwrite"]
    for indicator in risky_indicators
        if occursin(indicator, goal_lower)
            complexity_estimate += 0.2
        end
    end
    
    result[:complexity_estimate] = clamp(complexity_estimate, 0.1, 1.0)
    
    # Detect potential risks
    potential_risks = String[]
    
    if occursin("delete", goal_lower) || occursin("remove", goal_lower)
        push!(potential_risks, "Data loss risk - destructive operation detected")
    end
    
    if occursin("sudo", goal_lower) || occursin("root", goal_lower) || occursin("admin", goal_lower)
        push!(potential_risks, "Elevation of privilege risk")
    end
    
    if occursin("network", goal_lower) || occursin("http", goal_lower)
        push!(potential_risks, "Network exposure risk")
    end
    
    if occursin("shell", goal_lower) || occursin("command", goal_lower)
        push!(potential_risks, "Command injection risk")
    end
    
    if length(required_capabilities) > 5
        push!(potential_risks, "High capability dependency - many components required")
    end
    
    if result[:complexity_estimate] > 0.7
        push!(potential_risks, "High complexity plan - multiple failure points")
    end
    
    result[:potential_risks] = potential_risks
    
    return result
end

"""
    extract_doctrine_constraints(goal_description::String) -> Vector{String}
    
    Identify doctrine-relevant aspects and generate constraints that ensure
    doctrine compliance.
    
    # Arguments
    - goal_description: Human-readable goal description
    
    # Returns
    Vector of doctrine constraint strings
"""
function extract_doctrine_constraints(goal_description::String)::Vector{String}
    constraints = String[]
    goal_lower = lowercase(goal_description)
    
    # Data protection constraints
    if occursin("write", goal_lower) || occursin("create", goal_lower) || occursin("save", goal_lower)
        push!(constraints, "Maintain audit trail for all file operations")
    end
    
    if occursin("delete", goal_lower) || occursin("remove", goal_lower)
        push!(constraints, "Ensure data is backed up before deletion")
        push!(constraints, "Require explicit confirmation for permanent deletion")
    end
    
    # Network safety constraints
    if occursin("http", goal_lower) || occursin("request", goal_lower) || occursin("api", goal_lower)
        push!(constraints, "Validate all network responses")
        push!(constraints, "Use HTTPS for all network requests")
    end
    
    # Shell safety constraints
    if occursin("shell", goal_lower) || occursin("command", goal_lower) || occursin("exec", goal_lower)
        push!(constraints, "Sanitize all shell command inputs")
        push!(constraints, "Log all shell executions")
    end
    
    # General safety constraints
    push!(constraints, "Never execute self-destructive actions")
    push!(constraints, "Preserve sovereign cognition capabilities")
    push!(constraints, "Maintain audit trail for significant decisions")
    
    return unique(constraints)
end

"""
    generate_sub_goals(kernel::KernelState, goal_description::String) -> Vector{SubGoal}
    
    Break down goal into 3-7 sub-goals (cognitive limit), ordered by dependencies,
    with priorities and defined actions.
    
    # Arguments
    - kernel: Current kernel state
    - goal_description: Human-readable goal description
    
    # Returns
    Vector of SubGoal objects
"""
function generate_sub_goals(kernel::KernelState, goal_description::String)::Vector{SubGoal}
    requirements = analyze_goal_requirements(goal_description)
    sub_goals = SubGoal[]
    
    # Analyze complexity to determine number of sub-goals
    complexity = requirements[:complexity_estimate]
    num_sub_goals = min(7, max(3, ceil(Int, complexity * 5)))
    
    # Common sub-goal templates based on domain
    required_domains = requirements[:required_domains]
    required_capabilities = requirements[:required_capabilities]
    
    # Base sub-goals based on typical execution flow
    # 1. Observation/Analysis sub-goal (always first)
    obs_subgoal = SubGoal(
        "Observe and analyze current state";
        priority=0.9,
        estimated_cost=0.5,
        rollback_plan=nothing
    )
    
    # Determine observation capabilities
    obs_capabilities = filter(cap -> occursin("observe", cap) || cap == "analyze_logs", required_capabilities)
    if isempty(obs_capabilities)
        push!(obs_capabilities, "observe_filesystem")
    end
    
    # Create observation actions
    obs_action = WorldAction(
        "Observe current system state",
        :observation;
        parameters=Dict("capabilities" => obs_capabilities),
        risk_class=:low,
        reversibility=:fully_reversible,
        expected_outcome="Current state captured for planning"
    )
    obs_subgoal.actions = [obs_action]
    
    push!(sub_goals, obs_subgoal)
    
    # 2. Planning sub-gool
    plan_subgoal = SubGoal(
        "Develop execution plan based on analysis";
        priority=0.8,
        dependencies=[obs_subgoal.id],
        estimated_cost=0.3,
        rollback_plan=nothing
    )
    push!(sub_goals, plan_subgoal)
    
    # 3. Preparation sub-goal (if network or complex operations needed)
    if "network" in required_domains || complexity > 0.5
        prep_subgoal = SubGoal(
            "Prepare resources and validate prerequisites";
            priority=0.7,
            dependencies=[plan_subgoal.id],
            estimated_cost=0.4,
            rollback_plan="Release any allocated resources"
        )
        
        # Add preparation actions based on domains
        prep_actions = WorldAction[]
        
        if "network" in required_domains
            push!(prep_actions, WorldAction(
                "Validate network connectivity and setup";
                :network;
                parameters=Dict("check_connectivity" => true),
                risk_class=:low,
                reversibility=:fully_reversible,
                expected_outcome="Network is accessible"
            ))
        end
        
        if "file_system" in required_domains
            push!(prep_actions, WorldAction(
                "Validate file system access";
                :file_system;
                parameters=Dict("check_permissions" => true),
                risk_class=:low,
                reversibility=:fully_reversible,
                expected_outcome="File system access confirmed"
            ))
        end
        
        prep_subgoal.actions = prep_actions
        push!(sub_goals, prep_subgoal)
    end
    
    # 4. Main execution sub-goal(s)
    main_deps = isempty(sub_goals) ? UUID[] : [sub_goals[end].id]
    
    # Determine main action type
    main_action_type = :tool
    if "file_system" in required_domains
        main_action_type = :file_system
    elseif "network" in required_domains
        main_action_type = :network
    elseif "shell" in required_domains
        main_action_type = :shell
    end
    
    main_subgoal = SubGoal(
        "Execute primary goal actions: $(goal_description)";
        priority=1.0,
        dependencies=main_deps,
        estimated_cost=complexity * 2.0,
        rollback_plan="Restore previous state from backup if available"
    )
    
    # Create main execution action
    main_action = WorldAction(
        "Execute: $(goal_description)";
        main_action_type;
        parameters=Dict(
            "goal_description" => goal_description,
            "required_capabilities" => required_capabilities
        );
        risk_class=:medium,
        reversibility=:partially_reversible,
        expected_outcome="Primary goal achieved",
        required_capabilities=required_capabilities,
        abort_conditions=[
            "doctrine_violation",
            "capability_unavailable",
            "resource_exhausted"
        ]
    )
    main_subgoal.actions = [main_action]
    push!(sub_goals, main_subgoal)
    
    # 5. Verification sub-goal
    verify_subgoal = SubGoal(
        "Verify goal completion and assess results";
        priority=0.6,
        dependencies=[main_subgoal.id],
        estimated_cost=0.3,
        rollback_plan=nothing
    )
    
    verify_action = WorldAction(
        "Verify execution results match expectations";
        :observation;
        parameters=Dict("verify_goal" => goal_description);
        risk_class=:low,
        reversibility=:fully_reversible,
        expected_outcome="Goal completion verified"
    )
    verify_subgoal.actions = [verify_action]
    push!(sub_goals, verify_subgoal)
    
    # 6. Cleanup sub-goal (if needed for risky operations)
    if complexity > 0.6 || "delete" in lowercase(goal_description)
        cleanup_subgoal = SubGoal(
            "Cleanup temporary resources and finalize";
            priority=0.3,
            dependencies=[verify_subgoal.id],
            estimated_cost=0.2,
            rollback_plan="Reallocate cleanup resources if needed"
        )
        push!(sub_goals, cleanup_subgoal)
    end
    
    # Ensure max 7 sub-goals
    return sub_goals[1:min(7, length(sub_goals))]
end

"""
    plan_action_chain(kernel::KernelState, sub_goal::SubGoal) -> ActionChain
    
    Create ordered sequence of actions for a sub-goal, ensuring dependencies
    are respected, adding observation/reality-check actions between steps.
    
    # Arguments
    - kernel: Current kernel state
    - sub_goal: The sub-goal to plan for
    
    # Returns
    ActionChain with ordered actions
"""
function plan_action_chain(kernel::KernelState, sub_goal::SubGoal)::ActionChain
    chain = ActionChain(sub_goal.id)
    
    # If sub-goal already has actions, use them
    if !isempty(sub_goal.actions)
        chain.actions = sub_goal.actions
    else
        # Create default action based on description
        default_action = WorldAction(
            sub_goal.description;
            :tool;
            parameters=Dict("sub_goal_id" => string(sub_goal.id));
            risk_class=:medium;
            reversibility=:partially_reversible
        )
        chain.actions = [default_action]
    end
    
    # Add observation/check action between main actions if there are multiple
    if length(chain.actions) > 1
        observed_actions = WorldAction[]
        for (i, action) in enumerate(chain.actions)
            push!(observed_actions, action)
            
            # Add checkpoint after each action except last
            if i < length(chain.actions)
                checkpoint = WorldAction(
                    "Checkpoint after step $(i): Verify state";
                    :observation;
                    parameters=Dict(
                        "previous_action" => string(action.id),
                        "step" => i
                    );
                    risk_class=:low;
                    reversibility=:fully_reversible;
                    expected_outcome="State verified after step $(i)"
                )
                push!(observed_actions, checkpoint)
            end
        end
        chain.actions = observed_actions
    end
    
    return chain
end

"""
    decompose_goal(kernel::KernelState, goal_description::String, priority::Float64=0.5) -> GoalDecomposition
    
    Accept ambiguous human-like goal, analyze against capabilities, generate
    sub-goals, create action chains, define abort conditions, plan rollback
    paths, and apply doctrine constraints.
    
    # Arguments
    - kernel: Current kernel state
    - goal_description: Human-readable goal description
    - priority: Goal priority (0-1), default 0.5
    
    # Returns
    Complete GoalDecomposition plan
"""
function decompose_goal(
    kernel::KernelState,
    goal_description::String,
    priority::Float64=0.5
)::GoalDecomposition
    
    @info "Decomposing goal" description=goal_description priority=priority
    
    # Create root goal
    root_goal = Goal(
        string(uuid4()),
        goal_description,
        Float32(priority),
        now()
    )
    
    # Analyze requirements
    requirements = analyze_goal_requirements(goal_description)
    
    # Create decomposition
    decomposition = GoalDecomposition(
        root_goal;
        estimated_duration=sum(requirements[:complexity_estimate] * 10.0 for _ in 1:5),
        complexity_score=requirements[:complexity_estimate]
    )
    
    # Add tool requirements
    for cap in requirements[:required_capabilities]
        decomposition.tool_requirements[cap] = haskey(kernel.self_model.capabilities.capability_ratings, cap)
    end
    
    # Extract doctrine constraints
    decomposition.doctrine_constraints = extract_doctrine_constraints(goal_description)
    
    # Generate sub-goals
    decomposition.sub_goals = generate_sub_goals(kernel, goal_description)
    
    # Plan action chains for each sub-goal
    for sub_goal in decomposition.sub_goals
        chain = plan_action_chain(kernel, sub_goal)
        push!(decomposition.action_chains, chain)
        
        # Add rollback path for sub-goal
        if sub_goal.rollback_plan !== nothing
            decomposition.rollback_paths[sub_goal.id] = sub_goal.rollback_plan
        end
    end
    
    # Define abort conditions based on risks
    decomposition.abort_conditions = [
        "doctrine_violation_detected",
        "capability_unavailable",
        "resource_exhausted (>90%)",
        "execution_time_exceeded",
        "user_cancelled",
        "unexpected_error"
    ]
    
    # Add risk-specific abort conditions
    for risk in requirements[:potential_risks]
        if occursin("Data loss", risk)
            push!(decomposition.abort_conditions, "file_verification_failed")
        elseif occursin("Network", risk)
            push!(decomposition.abort_conditions, "network_connectivity_lost")
        end
    end
    
    # Mark as ready
    decomposition.status = :ready
    
    @info "Goal decomposition complete" 
          sub_goals=length(decomposition.sub_goals)
          complexity=decomposition.complexity_score
          estimated_duration=decomposition.estimated_duration
    
    return decomposition
end

"""
    evaluate_plan_safety(decomposition::GoalDecomposition, kernel::KernelState) -> Dict
    
    Check all actions against doctrine, verify reversibility, assess overall risk,
    and identify single points of failure.
    
    # Arguments
    - decomposition: The plan to evaluate
    - kernel: Current kernel state
    
    # Returns
    Dict with safety assessment results
"""
function evaluate_plan_safety(
    decomposition::GoalDecomposition,
    kernel::KernelState
)::Dict{Symbol, Any}
    
    result = Dict{Symbol, Any}()
    
    # Check doctrine compliance
    doctrine_violations = String[]
    for sub_goal in decomposition.sub_goals
        for action in sub_goal.actions
            # Create a mock ActionProposal for doctrine checking
            proposal = ActionProposal(
                string(action.id),
                0.8f0,
                0.1f0,
                1.0f0,
                string(action.risk_class),
                action.intent
            )
            
            compliant, violation = check_doctrine_compliance(
                kernel.doctrine_enforcer,
                proposal,
                Dict("action_id" => string(action.id))
            )
            
            if !compliant
                push!(doctrine_violations, "Action $(action.id): Doctrine violation")
            end
        end
    end
    
    result[:doctrine_compliant] = isempty(doctrine_violations)
    result[:doctrine_violations] = doctrine_violations
    
    # Check reversibility
    reversible_count = 0
    irreversible_count = 0
    
    for sub_goal in decomposition.sub_goals
        for action in sub_goal.actions
            if action.reversibility == :fully_reversible
                reversible_count += 1
            elseif action.reversibility == :irreversible
                irreversible_count += 1
            end
        end
    end
    
    total_actions = length(reversible_count) + length(irreversible_count)
    result[:reversibility_ratio] = total_actions > 0 ? reversible_count / total_actions : 0.0
    result[:irreversible_count] = irreversible_count
    
    # Assess overall risk
    risk_scores = Float64[]
    for sub_goal in decomposition.sub_goals
        for action in sub_goal.actions
            risk_score = assess_action_risk(action)
            push!(risk_scores, risk_score)
        end
    end
    
    result[:max_risk] = isempty(risk_scores) ? 0.0 : maximum(risk_scores)
    result[:avg_risk] = isempty(risk_scores) ? 0.0 : mean(risk_scores)
    
    # Identify single points of failure (sub-goals with no alternatives)
    single_points_of_failure = UUID[]
    for sub_goal in decomposition.sub_goals
        # A sub-goal is a single point of failure if:
        # 1. It has no parallel alternatives
        # 2. Many other sub-goals depend on it
        dependent_count = count(sg -> sub_goal.id ∈ sg.dependencies, decomposition.sub_goals)
        if dependent_count > 2
            push!(single_points_of_failure, sub_goal.id)
        end
    end
    
    result[:single_points_of_failure] = single_points_of_failure
    
    # Overall safety score (0-1, higher is safer)
    safety_score = 1.0
    
    # Penalize for doctrine violations
    if !result[:doctrine_compliant]
        safety_score -= 0.5
    end
    
    # Penalize for high risk
    safety_score -= result[:max_risk] * 0.3
    
    # Penalize for single points of failure
    safety_score -= length(single_points_of_failure) * 0.1
    
    # Penalize for irreversible actions
    safety_score -= irreversible_count * 0.1
    
    result[:safety_score] = clamp(safety_score, 0.0, 1.0)
    
    return result
end

"""
    recalculate_plan!(decomposition::GoalDecomposition, kernel::KernelState, world_state::Dict)
    
    Re-evaluate plan as conditions change, add/remove sub-goals as needed,
    update action sequences. Never abandons rollback paths.
    
    # Arguments
    - decomposition: The plan to recalculate
    - kernel: Current kernel state
    - world_state: Current world state
"""
function recalculate_plan!(
    decomposition::GoalDecomposition,
    kernel::KernelState,
    world_state::Dict
)::Nothing
    
    @info "Recalculating plan" decomposition_id=decomposition.id
    
    # Update last updated timestamp
    decomposition.last_updated = now()
    
    # Re-analyze requirements
    requirements = analyze_goal_requirements(decomposition.root_goal.description)
    
    # Check if capabilities are still available
    for (capability, was_available) in decomposition.tool_requirements
        is_available = haskey(kernel.self_model.capabilities.capability_ratings, capability)
        if is_available != was_available
            @warn "Capability availability changed" capability=capability was_available=was_available now_available=is_available
            decomposition.tool_requirements[capability] = is_available
        end
    end
    
    # Check if any sub-goals need to be re-prioritized based on world state
    if haskey(world_state, "failed_actions")
        failed_actions = world_state["failed_actions"]
        for sub_goal in decomposition.sub_goals
            for action in sub_goal.actions
                if action.id in failed_actions
                    # Increase priority for retry
                    sub_goal.priority = min(1.0, sub_goal.priority * 1.2)
                end
            end
        end
    end
    
    # Check if any new risks have emerged
    current_risks = requirements[:potential_risks]
    
    # Add new abort conditions if new risks detected
    for risk in current_risks
        abort_key = replace(lowercase(risk), " " => "_")
        if !occursin(abort_key, join(decomposition.abort_conditions, " "))
            push!(decomposition.abort_conditions, "risk_emerged:$(abort_key)")
        end
    end
    
    # Re-evaluate safety
    safety = evaluate_plan_safety(decomposition, kernel)
    decomposition.status = safety[:safety_score] > 0.3 ? decomposition.status : :paused
    
    # Log recalculation
    push!(decomposition.execution_log, Dict(
        "event" => "plan_recalculated",
        "timestamp" => now(),
        "safety_score" => safety[:safety_score],
        "world_state_keys" => collect(keys(world_state))
    ))
    
    return nothing
end

# ============================================================================
# EXECUTION FUNCTIONS
# ============================================================================

"""
    execute_sub_goal!(kernel::KernelState, sub_goal::SubGoal) -> SubGoal
    
    Execute actions in chain, check abort conditions between actions,
    update sub-goal status.
    
    # Arguments
    - kernel: Current kernel state
    - sub_goal: The sub-goal to execute
    
    # Returns
    Updated sub-goal
"""
function execute_sub_goal!(kernel::KernelState, sub_goal::SubGoal)::SubGoal
    
    @info "Executing sub-goal" sub_goal_id=sub_goal.id description=sub_goal.description
    
    sub_goal.status = :executing
    sub_goal.started_at = now()
    
    # Execute each action in sequence
    for action in sub_goal.actions
        
        # Check if we should abort
        if sub_goal.status == :failed || sub_goal.status == :skipped
            break
        end
        
        # In a real implementation, we would execute the action here
        # For now, we simulate execution
        
        # Simulate action execution
        try
            # Create authorization context
            auth_ctx = AuthorizationContext(action)
            
            # In full implementation:
            # 1. Authorize action through pipeline
            # 2. Execute action
            # 3. Record result
            # 4. Check for abort conditions
            
            # Mark action as completed
            push!(sub_goal.actions, action)  # This is just to track completion
            
            @debug "Action executed" action_id=action.id intent=action.intent
            
        catch ex
            @error "Action execution failed" action_id=action.id error=string(ex)
            sub_goal.status = :failed
            break
        end
    end
    
    # Update sub-goal status based on execution
    if sub_goal.status != :failed
        sub_goal.status = :completed
        sub_goal.completed_at = now()
    end
    
    return sub_goal
end

"""
    abort_on_condition(decomposition::GoalDecomposition, world_state::Dict) -> Bool
    
    Evaluate all abort conditions and return true if any condition is met.
    
    # Arguments
    - decomposition: The current decomposition
    - world_state: Current world state
    
    # Returns
    true if any abort condition is met
"""
function abort_on_condition(decomposition::GoalDecomposition, world_state::Dict)::Bool
    
    # Check each abort condition
    for condition in decomposition.abort_conditions
        condition_lower = lowercase(condition)
        
        # Doctrine violation check
        if occursin("doctrine", condition_lower)
            if haskey(world_state, "doctrine_violation") && world_state["doctrine_violation"]
                @warn "Abort condition met: doctrine violation"
                return true
            end
        end
        
        # Capability unavailable check
        if occursin("capability", condition_lower)
            if haskey(world_state, "unavailable_capabilities")
                if !isempty(world_state["unavailable_capabilities"])
                    @warn "Abort condition met: capability unavailable"
                    return true
                end
            end
        end
        
        # Resource exhaustion check
        if occursin("resource", condition_lower)
            if haskey(world_state, "resource_usage")
                if world_state["resource_usage"] > 0.9
                    @warn "Abort condition met: resource exhaustion"
                    return true
                end
            end
        end
        
        # User cancelled check
        if occursin("cancelled", condition_lower)
            if haskey(world_state, "user_cancelled") && world_state["user_cancelled"]
                @warn "Abort condition met: user cancelled"
                return true
            end
        end
    end
    
    return false
end

"""
    rollback_to_checkpoint!(kernel::KernelState, decomposition::GoalDecomposition, checkpoint_id::UUID)
    
    Execute rollback plan, restore previous state, and log rollback.
    
    # Arguments
    - kernel: Current kernel state
    - decomposition: The decomposition being rolled back
    - checkpoint_id: ID of checkpoint to rollback to
"""
function rollback_to_checkpoint!(
    kernel::KernelState,
    decomposition::GoalDecomposition,
    checkpoint_id::UUID
)::Nothing
    
    @info "Rolling back to checkpoint" checkpoint_id=checkpoint_id
    
    # Find the rollback plan for this checkpoint
    rollback_plan = get(decomposition.rollback_paths, checkpoint_id, nothing)
    
    if rollback_plan === nothing
        @warn "No rollback plan found for checkpoint" checkpoint_id=checkpoint_id
    else
        @info "Executing rollback plan" plan=rollback_plan
        
        # In full implementation, execute the rollback actions
        # For now, log the rollback attempt
        
        # Find the sub-goal to rollback
        target_sub_goal = nothing
        for sub_goal in decomposition.sub_goals
            if sub_goal.id == checkpoint_id
                target_sub_goal = sub_goal
                break
            end
        end
        
        if target_sub_goal !== nothing && target_sub_goal.rollback_plan !== nothing
            @info "Rolling back sub-goal" 
                  sub_goal_id=target_sub_goal.id 
                  description=target_sub_goal.description
        end
    end
    
    # Log rollback
    push!(decomposition.execution_log, Dict(
        "event" => "rollback_executed",
        "timestamp" => now(),
        "checkpoint_id" => checkpoint_id,
        "rollback_plan" => rollback_plan
    ))
    
    return nothing
end

"""
    execute_decomposition!(kernel::KernelState, decomposition::GoalDecomposition) -> GoalDecomposition
    
    Execute sub-goals in dependency order, handle failures gracefully, update
    status throughout, trigger rollback on abort conditions.
    
    # Arguments
    - kernel: Current kernel state
    - decomposition: The decomposition to execute
    
    # Returns
    Updated decomposition with execution results
"""
function execute_decomposition!(
    kernel::KernelState,
    decomposition::GoalDecomposition
)::GoalDecomposition
    
    @info "Executing goal decomposition" decomposition_id=decomposition.id
    
    decomposition.status = :executing
    
    # Build dependency graph
    completed_ids = Set{UUID}()
    failed_ids = Set{UUID}()
    
    # Get current world state (in real implementation, this would come from monitoring)
    world_state = Dict{String, Any}()
    
    # Execute sub-goals in dependency order
    while length(completed_ids) + length(failed_ids) < length(decomposition.sub_goals)
        
        # Check abort conditions
        if abort_on_condition(decomposition, world_state)
            @warn "Abort conditions met, stopping execution"
            decomposition.status = :aborted
            
            # Rollback completed sub-goals
            for id in completed_ids
                rollback_to_checkpoint!(kernel, decomposition, id)
            end
            
            break
        end
        
        # Find ready sub-goals (all dependencies completed)
        ready_sub_goals = filter(sub_goal -> 
            sub_goal.status == :pending && 
            all(dep_id -> dep_id in completed_ids, sub_goal.dependencies)
        , decomposition.sub_goals)
        
        if isempty(ready_sub_goals)
            # No more ready sub-goals - check if we're stuck
            remaining = filter(sg -> sg.status == :pending, decomposition.sub_goals)
            if !isempty(remaining)
                # Deadlock - mark remaining as failed
                for sub_goal in remaining
                    sub_goal.status = :failed
                    push!(failed_ids, sub_goal.id)
                end
            end
            break
        end
        
        # Execute ready sub-goals (prefer higher priority)
        sort!(ready_sub_goals, by = sg -> -sg.priority)
        
        for sub_goal in ready_sub_goals
            @info "Executing sub-goal" 
                  sub_goal_id=sub_goal.id 
                  description=sub_goal.description 
                  priority=sub_goal.priority
            
            # Execute the sub-goal
            execute_sub_goal!(kernel, sub_goal)
            
            # Update status
            if sub_goal.status == :completed
                push!(completed_ids, sub_goal.id)
            elseif sub_goal.status == :failed
                push!(failed_ids, sub_goal.id)
                
                # Check if we should abort on failure
                if sub_goal.priority > 0.8
                    @warn "Critical sub-goal failed, aborting"
                    decomposition.status = :failed
                    
                    # Rollback
                    for id in completed_ids
                        rollback_to_checkpoint!(kernel, decomposition, id)
                    end
                    
                    return decomposition
                end
            end
        end
    end
    
    # Update final status
    if decomposition.status == :executing
        if isempty(failed_ids)
            decomposition.status = :completed
        else
            decomposition.status = :completed  # Partial success
        end
    end
    
    # Log completion
    push!(decomposition.execution_log, Dict(
        "event" => "decomposition_completed",
        "timestamp" => now(),
        "status" => decomposition.status,
        "completed_count" => length(completed_ids),
        "failed_count" => length(failed_ids)
    ))
    
    @info "Goal decomposition execution complete" 
          status=decomposition.status
          completed=length(completed_ids)
          failed=length(failed_ids)
    
    return decomposition
end

# ============================================================================
# PLAN ANALYSIS FUNCTIONS
# ============================================================================

"""
    estimate_success_probability(decomposition::GoalDecomposition, kernel::KernelState) -> Float64
    
    Estimate success probability based on capability confidence, plan complexity,
    and historical success rates.
    
    # Arguments
    - decomposition: The decomposition to evaluate
    - kernel: Current kernel state
    
    # Returns
    Success probability (0-1)
"""
function estimate_success_probability(
    decomposition::GoalDecomposition,
    kernel::KernelState
)::Float64
    
    # Base probability from capability confidence
    capability_confidences = Float64[]
    
    for (capability, is_available) in decomposition.tool_requirements
        if is_available
            rating = get(
                kernel.self_model.capabilities.capability_ratings,
                capability,
                0.5
            )
            push!(capability_confidences, rating)
        end
    end
    
    avg_capability_confidence = isempty(capability_confidences) ? 
        0.5 : mean(capability_confidences)
    
    # Factor in plan complexity (higher complexity = lower probability)
    complexity_factor = 1.0 - (decomposition.complexity_score * 0.5)
    
    # Factor in sub-goal completion probability
    sub_goal_completion_probs = Float64[]
    for sub_goal in decomposition.sub_goals
        # Higher priority = higher expected completion
        push!(sub_goal_completion_probs, sub_goal.priority)
    end
    
    avg_sub_goal_prob = isempty(sub_goal_completion_probs) ?
        0.5 : mean(sub_goal_completion_probs)
    
    # Historical success adjustment based on reputation
    reputation_factor = 0.9  # Default good reputation
    
    # Combine factors
    success_prob = avg_capability_confidence * complexity_factor * avg_sub_goal_prob * reputation_factor
    
    return clamp(success_prob, 0.0, 1.0)
end

"""
    explain_plan(decomposition::GoalDecomposition) -> String
    
    Generate human-readable explanation of the plan, outlining sub-goals
    and actions, highlighting key risks and mitigations.
    
    # Arguments
    - decomposition: The decomposition to explain
    
    # Returns
    Human-readable explanation string
"""
function explain_plan(decomposition::GoalDecomposition)::String
    
    lines = String[]
    
    push!(lines, "=" ^ 60)
    push!(lines, "GOAL DECOMPOSITION PLAN")
    push!(lines, "=" ^ 60)
    push!(lines, "")
    
    # Root goal
    push!(lines, "ROOT GOAL:")
    push!(lines, "  $(decomposition.root_goal.description)")
    push!(lines, "  Priority: $(decomposition.root_goal.priority)")
    push!(lines, "")
    
    # Plan overview
    push!(lines, "PLAN OVERVIEW:")
    push!(lines, "  Sub-goals: $(length(decomposition.sub_goals))")
    push!(lines, "  Complexity: $(round(decomposition.complexity_score, digits=2))")
    push!(lines, "  Estimated Duration: $(round(decomposition.estimated_duration, digits=1))s")
    push!(lines, "  Status: $(decomposition.status)")
    push!(lines, "")
    
    # Required capabilities
    push!(lines, "REQUIRED CAPABILITIES:")
    for (cap, available) in decomposition.tool_requirements
        status_str = available ? "[✓]" : "[✗]"
        push!(lines, "  $status_str $cap")
    end
    push!(lines, "")
    
    # Sub-goals
    push!(lines, "SUB-GOALS:")
    for (i, sub_goal) in enumerate(decomposition.sub_goals)
        push!(lines, "  $(i). $(sub_goal.description)")
        push!(lines, "     Priority: $(sub_goal.priority)")
        push!(lines, "     Status: $(sub_goal.status)")
        push!(lines, "     Dependencies: $(length(sub_goal.dependencies)) sub-goals")
        
        if sub_goal.rollback_plan !== nothing
            push!(lines, "     Rollback: $(sub_goal.rollback_plan)")
        end
        
        push!(lines, "     Actions: $(length(sub_goal.actions))")
        for action in sub_goal.actions
            push!(lines, "       - $(action.intent) [$(action.risk_class)]")
        end
        push!(lines, "")
    end
    
    # Abort conditions
    push!(lines, "ABORT CONDITIONS:")
    for condition in decomposition.abort_conditions
        push!(lines, "  - $condition")
    end
    push!(lines, "")
    
    # Doctrine constraints
    push!(lines, "DOCTRINE CONSTRAINTS:")
    for constraint in decomposition.doctrine_constraints
        push!(lines, "  - $constraint")
    end
    push!(lines, "")
    
    # Risks and mitigations
    push!(lines, "KEY RISKS:")
    if isempty(decomposition.abort_conditions)
        push!(lines, "  (No specific risks identified)")
    else
        for condition in decomposition.abort_conditions[1:min(3, length(decomposition.abort_conditions))]
            push!(lines, "  - $condition")
        end
    end
    push!(lines, "")
    
    push!(lines, "=" ^ 60)
    
    return join(lines, "\n")
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    get_capability_rating(kernel::KernelState, capability_id::String) -> Float64
    
    Get the rating for a specific capability from the kernel's self-model.
"""
function get_capability_rating(kernel::KernelState, capability_id::String)::Float64
    return get(
        kernel.self_model.capabilities.capability_ratings,
        capability_id,
        0.5
    )
end

"""
    has_required_capabilities(decomposition::GoalDecomposition, kernel::KernelState) -> Bool
    
    Check if all required capabilities are available.
"""
function has_required_capabilities(decomposition::GoalDecomposition, kernel::KernelState)::Bool
    for (capability, required) in decomposition.tool_requirements
        if required && !haskey(kernel.self_model.capabilities.capability_ratings, capability)
            return false
        end
    end
    return true
end

end # module GoalDecomposition
