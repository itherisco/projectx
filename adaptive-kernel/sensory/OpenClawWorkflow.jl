"""
# OpenClawWorkflow.jl

OpenClaw Workflow Management Framework

This module expands the OpenClaw framework to allow the brain to manage:
- End-to-end development workflows
- Data science workflows  
- Autonomous build and deployment pipelines
- Warden oversight integration for managed workflows

## Integration Points
- Input: Brain.jl decision outputs, OpenClawBridge.jl tool calls
- Output: Workflow execution results, status updates
- Related: Brain.jl, OpenClawBridge.jl, IoTBridge.jl

## Security
- All workflows run in sandboxed environments
- Warden oversight for critical operations
- Audit logging for all workflow executions
- Approval gates for sensitive operations
"""

module OpenClawWorkflow

using UUIDs
using Dates
using JSON
using SHA

# Import existing OpenClaw bridge
include("../jarvis/src/bridge/OpenClawBridge.jl")
using .OpenClawBridge

# Import Warden integration for security oversight
include("../cognition/oneiric/OneiricWardenIntegration.jl")
using .OneiricWardenIntegration

# ============================================================================
# Type Definitions
# ============================================================================

"""
    WorkflowType - Supported workflow categories
"""
@enum WorkflowType begin
    WORKFLOW_DEVELOPMENT    = 1  # Code development workflows
    WORKFLOW_DATASCIENCE   = 2  # Data analysis and ML workflows
    WORKFLOW_DEPLOYMENT    = 3  # Build and deployment pipelines
    WORKFLOW_MAINTENANCE   = 4  # System maintenance tasks
    WORKFLOW_CUSTOM        = 5  # User-defined workflows
end

"""
    WorkflowStatus - Current execution status
"""
@enum WorkflowStatus begin
    STATUS_PENDING      = 1  # Waiting to start
    STATUS_RUNNING      = 2  # Currently executing
    STATUS_WAITING      = 3  # Waiting for approval/dependency
    STATUS_COMPLETED    = 4  # Successfully completed
    STATUS_FAILED       = 5  # Execution failed
    STATUS_CANCELLED    = 6  # Cancelled by user/system
    STATUS_BLOCKED       = 7  # Blocked by dependency
end

"""
    WorkflowStep - Individual step in a workflow

# Fields
- `id::String`: Unique step identifier
- `name::String`: Human-readable step name
- `tool::String`: OpenClaw tool to execute
- `parameters::Dict{String, Any}`: Tool parameters
- `depends_on::Vector{String}`: Step IDs this depends on
- `status::WorkflowStatus`: Current step status
- `result::Union{Dict{String, Any}, Nothing}`: Execution result
- `error::Union{String, Nothing}`: Error message if failed
- `started_at::Union{DateTime, Nothing}`: Start timestamp
- `completed_at::Union{DateTime, Nothing}`: Completion timestamp
"""
mutable struct WorkflowStep
    id::String
    name::String
    tool::String
    parameters::Dict{String, Any}
    depends_on::Vector{String}
    status::WorkflowStatus
    result::Union{Dict{String, Any}, Nothing}
    error::Union{String, Nothing}
    started_at::Union{DateTime, Nothing}
    completed_at::Union{DateTime, Nothing}
    
    function WorkflowStep(name::String, tool::String, parameters::Dict{String, Any}=Dict{String, Any}();
                         depends_on::Vector{String}=String[])
        new(
            string(uuid4())[1:8],
            name,
            tool,
            parameters,
            depends_on,
            STATUS_PENDING,
            nothing,
            nothing,
            nothing,
            nothing
        )
    end
end

"""
    Workflow - Complete workflow definition

# Fields
- `id::String`: Unique workflow identifier
- `name::String`: Human-readable workflow name
- `type::WorkflowType`: Workflow category
- `description::String`: Workflow description
- `steps::Vector{WorkflowStep}`: Ordered workflow steps
- `status::WorkflowStatus`: Overall workflow status
- `config::OpenClawConfig`: OpenClaw connection config
- `requires_approval::Bool`: Whether human approval required
- `created_at::DateTime`: Creation timestamp
- `started_at::Union{DateTime, Nothing}`: Start timestamp
- `completed_at::Union{DateTime, Nothing}`: Completion timestamp
- `created_by::String`: Creator identifier
"""
mutable struct Workflow
    id::String
    name::String
    type::WorkflowType
    description::String
    steps::Vector{WorkflowStep}
    status::WorkflowStatus
    config::OpenClawConfig
    requires_approval::Bool
    created_at::DateTime
    started_at::Union{DateTime, Nothing}
    completed_at::Union{DateTime, Nothing}
    created_by::String
    
    function Workflow(name::String, type::WorkflowType, description::String,
                     config::OpenClawConfig; created_by::String="system")
        new(
            string(uuid4())[1:8],
            name,
            type,
            description,
            WorkflowStep[],
            STATUS_PENDING,
            config,
            false,
            now(),
            nothing,
            nothing,
            created_by
        )
    end
end

"""
    WorkflowExecution - Runtime execution state

# Fields
- `workflow_id::String`: Associated workflow ID
- `execution_id::String`: Unique execution identifier
- `status::WorkflowStatus`: Current status
- `current_step::Union{Int, Nothing}`: Current step index
- `completed_steps::Vector{String}`: IDs of completed steps
- `failed_steps::Vector{String}`: IDs of failed steps
- `results::Dict{String, Any}`: Aggregated results
- `logs::Vector{String}`: Execution logs
- `started_at::DateTime`: Start timestamp
- `completed_at::Union{DateTime, Nothing}`: Completion timestamp
"""
mutable struct WorkflowExecution
    workflow_id::String
    execution_id::String
    status::WorkflowStatus
    current_step::Union{Int, Nothing}
    completed_steps::Vector{String}
    failed_steps::Vector{String}
    results::Dict{String, Any}
    logs::Vector{String}
    started_at::DateTime
    completed_at::Union{DateTime, Nothing}
    
    function WorkflowExecution(workflow_id::String)
        new(
            workflow_id,
            string(uuid4())[1:8],
            STATUS_PENDING,
            nothing,
            String[],
            String[],
            Dict{String, Any}(),
            String[],
            now(),
            nothing
        )
    end
end

"""
    WorkflowTemplate - Pre-defined workflow templates
"""
struct WorkflowTemplate
    name::String
    type::WorkflowType
    description::String
    steps::Vector{Dict{String, Any}}  # Step definitions
end

# ============================================================================
# LEP (Law Enforcement Point) Veto System
# ============================================================================

"""
    LEPAction - Action proposed by the brain for Warden evaluation

# Fields
- `id::String`: Unique action identifier
- `action_type::Symbol`: Type of action (:git_commit, :curl, :file_write, :shell_exec, etc.)
- `parameters::Dict{String, Any}`: Action parameters
- `priority::Float32`: Priority of the action [0, 1]
- `estimated_reward::Float32`: Expected reward [0, 1]
- `estimated_risk::Float32`: Estimated risk [0, 1]
- `context::Vector{Float32}`: Context features for the Warden
"""
mutable struct LEPAction
    id::String
    action_type::Symbol
    parameters::Dict{String, Any}
    priority::Float32
    estimated_reward::Float32
    estimated_risk::Float32
    context::Vector{Float32}
    
    function LEPAction(action_type::Symbol, parameters::Dict{String, Any}=Dict{String, Any}();
                      priority::Float32=0.5f0, estimated_reward::Float32=0.5f0, 
                      estimated_risk::Float32=0.3f0, context::Vector{Float32}=Float32[])
        new(
            string(uuid4())[1:8],
            action_type,
            parameters,
            priority,
            estimated_reward,
            estimated_risk,
            context
        )
    end
end

"""
    WardenDecision - Decision from the Warden on an action

# Fields
- `action_id::String`: Associated action ID
- `approved::Bool`: Whether the action is approved
- `score::Float32`: LEP score = priority × (reward - risk)
- `veto_reason::Union{String, Nothing}`: Reason for veto if rejected
- `conditions::Vector{String}`: Conditions for approval (if any)
- `timestamp::DateTime`: Decision timestamp
"""
struct WardenDecision
    action_id::String
    approved::Bool
    score::Float32
    veto_reason::Union{String, Nothing}
    conditions::Vector{String}
    timestamp::DateTime
    
    function WardenDecision(action_id::String, approved::Bool, score::Float32;
                          veto_reason::Union{String, Nothing}=nothing,
                          conditions::Vector{String}=String[])
        new(action_id, approved, score, veto_reason, conditions, now())
    end
end

# High-risk action types that require Warden approval
const HIGH_RISK_ACTIONS = Set{Symbol}([:git_commit, :shell_exec, :curl, :file_write, :database_write, :deploy])

"""
    compute_lep_score(action::LEPAction)::Float32

Compute the LEP (Law Enforcement Point) score for an action.
LEP Score Equation: score = priority × (reward - risk)

Higher scores indicate more favorable actions.
Negative scores indicate the action should be rejected.
"""
function compute_lep_score(action::LEPAction)::Float32
    # LEP Score = priority × (reward - risk)
    reward_minus_risk = action.estimated_reward - action.estimated_risk
    score = action.priority * reward_minus_risk
    
    return score
end

"""
    evaluate_action_for_warden(action::LEPAction)::WardenDecision

Evaluate an action through the Warden system using LEP veto equation.
Returns a WardenDecision with approval status and score.

# LEP Veto Criteria:
- If score < 0: VETO (negative expected value)
- If risk > 0.8: VETO (too risky)
- If action_type in HIGH_RISK_ACTIONS and score < 0.3: VETO (high-risk actions need high score)
- Otherwise: APPROVE with optional conditions
"""
function evaluate_action_for_warden(action::LEPAction)::WardenDecision
    score = compute_lep_score(action)
    
    # Determine approval based on LEP criteria
    approved = true
    veto_reason = nothing
    conditions = String[]
    
    # Check 1: Negative score - always veto
    if score < 0.0
        approved = false
        veto_reason = "LEP score is negative ($(score)), action has negative expected value"
    
    # Check 2: Extremely high risk - always veto
    elseif action.estimated_risk > 0.8
        approved = false
        veto_reason = "Risk too high ($(action.estimated_risk)) - exceeds safety threshold"
    
    # Check 3: High-risk actions need higher scores
    elseif action.action_type in HIGH_RISK_ACTIONS && score < 0.3
        approved = false
        veto_reason = "High-risk action requires LEP score >= 0.3, got $(score)"
    
    # Check 4: Medium risk actions get conditions
    elseif action.estimated_risk > 0.5
        push!(conditions, "Monitor execution closely")
        push!(conditions, "Log all output")
    end
    
    return WardenDecision(action.id, approved, score; veto_reason=veto_reason, conditions=conditions)
end

"""
    submit_to_warden(action::LEPAction)::WardenDecision

Submit an action to the Warden for evaluation.
This is the main entry point for Warden oversight of workflow actions.

Every action in OpenClaw pipelines (git commit, curl, shell exec, etc.)
must pass through this function before execution.
"""
function submit_to_warden(action::LEPAction)::WardenDecision
    # Log the submission
    log_warden_submission(action)
    
    # Evaluate through Warden
    decision = evaluate_action_for_warden(action)
    
    # Log the decision
    log_warden_decision(decision)
    
    return decision
end

"""
    log_warden_submission(action::LEPAction)

Log Warden submission for audit trail.
"""
function log_warden_submission(action::LEPAction)
    # In production, this would write to secure audit log
    # For now, we log to execution logs
    println("[WARDEN] Submitted action: $(action.action_type) (ID: $(action.id))")
    println("  Priority: $(action.priority), Reward: $(action.estimated_reward), Risk: $(action.estimated_risk)")
end

"""
    log_warden_decision(decision::WardenDecision)

Log Warden decision for audit trail.
"""
function log_warden_decision(decision::WardenDecision)
    status = decision.approved ? "APPROVED" : "VETOED"
    println("[WARDEN] Decision: $(status) for action $(decision.action_id)")
    println("  Score: $(decision.score)")
    if decision.veto_reason !== nothing
        println("  Reason: $(decision.veto_reason)")
    end
    if !isempty(decision.conditions)
        println("  Conditions: $(join(decision.conditions, ", "))")
    end
end

"""
    create_lep_action_from_step(step::WorkflowStep)::LEPAction

Convert a workflow step to an LEPAction for Warden evaluation.
Infers priority, reward, and risk from step characteristics.
"""
function create_lep_action_from_step(step::WorkflowStep)::LEPAction
    # Infer action type from tool
    action_type = Symbol(step.tool)
    
    # Estimate parameters based on action type
    priority = _estimate_priority(action_type, step.parameters)
    reward = _estimate_reward(action_type)
    risk = _estimate_risk(action_type, step.parameters)
    
    return LEPAction(action_type, step.parameters; priority=priority, estimated_reward=reward, estimated_risk=risk)
end

function _estimate_priority(action_type::Symbol, parameters::Dict{String, Any})::Float32
    # Higher priority for deployment and maintenance
    if action_type == :deploy
        return 0.9f0
    elseif action_type == :shell
        return 0.7f0
    else
        return 0.5f0
    end
end

function _estimate_reward(action_type::Symbol)::Float32
    # Reward based on action value
    if action_type == :deploy
        return 0.9f0  # High value deployment
    elseif action_type == :shell
        return 0.6f0
    else
        return 0.5f0
    end
end

function _estimate_risk(action_type::Symbol, parameters::Dict{String, Any})::Float32
    # Base risk by action type
    base_risk = if action_type == :deploy
        0.7f0  # Deployments are risky
    elseif action_type == :shell
        0.5f0
    elseif action_type == :http
        0.3f0
    else
        0.2f0
    end
    
    # Check for dangerous commands in shell
    if action_type == :shell
        cmd = get(parameters, "command", "")
        if occursin("rm -rf", cmd) || occursin("sudo", cmd)
            base_risk = 0.9f0  # Very dangerous
        elseif occursin("curl", cmd) || occursin("wget", cmd)
            base_risk = 0.6f0  # Network operations
        end
    end
    
    return base_risk
end

# ============================================================================
# Export public API
# ============================================================================

export
    # Types
    WorkflowType,
    WorkflowStatus,
    WorkflowStep,
    Workflow,
    WorkflowExecution,
    WorkflowTemplate,
    LEPAction,
    WardenDecision,
    
    # Core functions
    create_workflow,
    add_step!,
    execute_workflow,
    execute_step,
    get_workflow_status,
    cancel_workflow,
    
    # LEP Veto functions
    compute_lep_score,
    evaluate_action_for_warden,
    submit_to_warden,
    
    # Templates
    get_development_template,
    get_datascience_template,
    get_deployment_template,
    
    # Utility
    validate_workflow,
    estimate_execution_time,
    get_workflow_history

# ============================================================================
# Workflow Templates
# ============================================================================

"""
    get_development_template(config::OpenClawConfig)::WorkflowTemplate

Get pre-defined development workflow template.
"""
function get_development_template(config::OpenClawConfig)::WorkflowTemplate
    steps = [
        Dict{String, Any}(
            "name" => "Lint Code",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "julia --depwarn=yes --check-bounds=yes ."),
            "depends_on" => []
        ),
        Dict{String, Any}(
            "name" => "Run Tests", 
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "julia test/runtests.jl"),
            "depends_on" => ["Lint Code"]
        ),
        Dict{String, Any}(
            "name" => "Build Documentation",
            "tool" => "shell", 
            "parameters" => Dict{String, Any}("command" => "julia docs/make.jl"),
            "depends_on" => ["Run Tests"]
        )
    ]
    
    return WorkflowTemplate(
        "Development Pipeline",
        WORKFLOW_DEVELOPMENT,
        "Code lint, test, and documentation build workflow",
        steps
    )
end

"""
    get_datascience_template(config::OpenClawConfig)::WorkflowTemplate

Get pre-defined data science workflow template.
"""
function get_datascience_template(config::OpenClawConfig)::WorkflowTemplate
    steps = [
        Dict{String, Any}(
            "name" => "Load Data",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "python load_data.py"),
            "depends_on" => []
        ),
        Dict{String, Any}(
            "name" => "Preprocess",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "python preprocess.py"),
            "depends_on" => ["Load Data"]
        ),
        Dict{String, Any}(
            "name" => "Train Model",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "python train.py"),
            "depends_on" => ["Preprocess"]
        ),
        Dict{String, Any}(
            "name" => "Evaluate",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "python evaluate.py"),
            "depends_on" => ["Train Model"]
        )
    ]
    
    return WorkflowTemplate(
        "Data Science Pipeline",
        WORKFLOW_DATASCIENCE,
        "Data loading, preprocessing, model training, and evaluation workflow",
        steps
    )
end

"""
    get_deployment_template(config::OpenClawConfig)::WorkflowTemplate

Get pre-defined deployment workflow template.
"""
function get_deployment_template(config::OpenClawConfig)::WorkflowTemplate
    steps = [
        Dict{String, Any}(
            "name" => "Build",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "make build"),
            "depends_on" => []
        ),
        Dict{String, Any}(
            "name" => "Security Scan",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "make security-scan"),
            "depends_on" => ["Build"]
        ),
        Dict{String, Any}(
            "name" => "Deploy to Staging",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "make deploy-staging"),
            "depends_on" => ["Security Scan"]
        ),
        Dict{String, Any}(
            "name" => "Integration Tests",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "make test-integration"),
            "depends_on" => ["Deploy to Staging"]
        ),
        Dict{String, Any}(
            "name" => "Deploy to Production",
            "tool" => "shell",
            "parameters" => Dict{String, Any}("command" => "make deploy-prod"),
            "depends_on" => ["Integration Tests"]
        )
    ]
    
    return WorkflowTemplate(
        "Deployment Pipeline",
        WORKFLOW_DEPLOYMENT,
        "Build, test, and deploy workflow with staging and production",
        steps
    )
end

# ============================================================================
# Core Workflow Functions
# ============================================================================

"""
    create_workflow(name::String, type::WorkflowType, description::String,
                   config::OpenClawConfig; created_by::String="system")::Workflow

Create a new workflow with the given configuration.
"""
function create_workflow(name::String, type::WorkflowType, description::String,
                        config::OpenClawConfig; created_by::String="system")::Workflow
    return Workflow(name, type, description, config; created_by=created_by)
end

"""
    add_step!(workflow::Workflow, name::String, tool::String, 
             parameters::Dict{String, Any}=Dict{String, Any}();
             depends_on::Vector{String}=String[])::WorkflowStep

Add a step to the workflow.
"""
function add_step!(workflow::Workflow, name::String, tool::String, 
                 parameters::Dict{String, Any}=Dict{String, Any}();
                 depends_on::Vector{String}=String[])::WorkflowStep
    
    step = WorkflowStep(name, tool, parameters; depends_on=depends_on)
    push!(workflow.steps, step)
    
    return step
end

"""
    validate_workflow(workflow::Workflow)::Tuple{Bool, String}

Validate workflow for correctness and safety.
"""
function validate_workflow(workflow::Workflow)::Tuple{Bool, String}
    # Check for empty workflow
    if isempty(workflow.steps)
        return false, "Workflow has no steps"
    end
    
    # Build dependency graph
    step_ids = Set{String}()
    dependencies = Dict{String, Set{String}}()
    
    for step in workflow.steps
        if step.id in step_ids
            return false, "Duplicate step ID: $(step.id)"
        end
        push!(step_ids, step.id)
        dependencies[step.id] = Set(step.depends_on)
    end
    
    # Check for circular dependencies
    for step in workflow.steps
        if _has_circular_dependency(step.id, dependencies, Set{String}())
            return false, "Circular dependency detected involving step: $(step.id)"
        end
    end
    
    # Validate tool names
    valid_tools = ["shell", "http", "file", "database", "docker", "k8s", "custom"]
    for step in workflow.steps
        if step.tool ∉ valid_tools
            return false, "Invalid tool: $(step.tool)"
        end
    end
    
    return true, "Workflow is valid"
end

"""
    _has_circular_dependency(step_id::String, 
                            dependencies::Dict{String, Set{String}},
                            visited::Set{String})::Bool

Check for circular dependencies using DFS.
"""
function _has_circular_dependency(step_id::String, 
                                  dependencies::Dict{String, Set{String}},
                                  visited::Set{String})::Bool
    
    if step_id in visited
        return true
    end
    
    push!(visited, step_id)
    
    for dep in get(dependencies, step_id, Set{String}())
        if _has_circular_dependency(dep, dependencies, copy(visited))
            return true
        end
    end
    
    return false
end

"""
    execute_step(execution::WorkflowExecution, step::WorkflowStep, 
                config::OpenClawConfig; enable_warden::Bool=true)::WorkflowStep

Execute a single workflow step via OpenClaw with Warden oversight.
All actions are evaluated by the Warden before execution.
"""
function execute_step(execution::WorkflowExecution, step::WorkflowStep, 
                     config::OpenClawConfig; enable_warden::Bool=true)::WorkflowStep
    
    step.status = STATUS_RUNNING
    step.started_at = now()
    
    push!(execution.logs, "[$(now())] Starting step: $(step.name)")
    
    # Warden oversight: evaluate action before execution
    if enable_warden
        # Create LEP action from step
        lep_action = create_lep_action_from_step(step)
        
        # Submit to Warden for evaluation
        decision = submit_to_warden(lep_action)
        
        # Check if approved
        if !decision.approved
            step.status = STATUS_FAILED
            step.error = "Warden veto: $(decision.veto_reason)"
            step.completed_at = now()
            
            push!(execution.logs, "[$(now())] WARDEN VETO for step: $(step.name)")
            push!(execution.logs, "[$(now())] Reason: $(decision.veto_reason)")
            push!(execution.failed_steps, step.id)
            
            return step
        end
        
        # Log any conditions
        if !isempty(decision.conditions)
            push!(execution.logs, "[$(now())] Warden conditions: $(join(decision.conditions, ", "))")
        end
    end
    
    try
        # Execute via OpenClaw
        result = call_tool(config, step.tool, step.parameters)
        
        step.result = result
        step.status = STATUS_COMPLETED
        step.completed_at = now()
        
        push!(execution.logs, "[$(now())] Completed step: $(step.name)")
        push!(execution.completed_steps, step.id)
        
    catch e
        step.error = string(e)
        step.status = STATUS_FAILED
        step.completed_at = now()
        
        push!(execution.logs, "[$(now())] FAILED step: $(step.name) - $e")
        push!(execution.failed_steps, step.id)
    end
    
    return step
end

"""
    execute_workflow(workflow::Workflow; wait_for_approval::Bool=false, enable_warden::Bool=true)::WorkflowExecution

Execute a complete workflow with optional Warden oversight.
All actions are evaluated by the Warden before execution if enable_warden=true.
"""
function execute_workflow(workflow::Workflow; wait_for_approval::Bool=false, enable_warden::Bool=true)::WorkflowExecution
    
    # Validate first
    valid, msg = validate_workflow(workflow)
    if !valid
        error("Invalid workflow: $msg")
    end
    
    # Create execution context
    execution = WorkflowExecution(workflow.id)
    execution.status = STATUS_RUNNING
    execution.started_at = now()
    
    workflow.status = STATUS_RUNNING
    workflow.started_at = now()
    
    # Check approval requirement
    if workflow.requires_approval && wait_for_approval
        execution.status = STATUS_WAITING
        workflow.status = STATUS_WAITING
        push!(execution.logs, "[$(now())] Waiting for approval...")
        return execution
    end
    
    # Build step lookup
    step_lookup = Dict{String, WorkflowStep}()
    for step in workflow.steps
        step_lookup[step.id] = step
    end
    
    # Execute steps in order
    completed = Set{String}()
    
    while length(completed) < length(workflow.steps)
        # Find next executable step
        next_step = nothing
        for step in workflow.steps
            if step.id in completed
                continue
            end
            
            # Check if all dependencies satisfied
            deps_satisfied = true
            for dep in step.depends_on
                if dep ∉ completed
                    deps_satisfied = false
                    break
                end
            end
            
            if deps_satisfied
                next_step = step
                break
            end
        end
        
        if next_step === nothing
            # No executable steps - either blocked or complete
            remaining = setdiff(Set([s.id for s in workflow.steps]), completed)
            if isempty(remaining)
                break  # All done
            else
                execution.status = STATUS_BLOCKED
                workflow.status = STATUS_BLOCKED
                push!(execution.logs, "[$(now())] Workflow blocked - cannot proceed")
                break
            end
        end
        
        # Execute the step
        execute_step(execution, next_step, workflow.config; enable_warden=enable_warden)
        
        # Update completion tracking
        if next_step.status == STATUS_COMPLETED
            push!(completed, next_step.id)
            execution.current_step = findfirst(s -> s.id == next_step.id, workflow.steps)
        elseif next_step.status == STATUS_FAILED
            # Stop on failure
            execution.status = STATUS_FAILED
            workflow.status = STATUS_FAILED
            push!(execution.logs, "[$(now())] Workflow failed at step: $(next_step.name)")
            break
        end
    end
    
    # Finalize execution
    if execution.status == STATUS_RUNNING
        execution.status = STATUS_COMPLETED
        workflow.status = STATUS_COMPLETED
    end
    
    execution.completed_at = now()
    workflow.completed_at = now()
    
    return execution
end

"""
    get_workflow_status(execution::WorkflowExecution)::Dict{String, Any}

Get current workflow execution status.
"""
function get_workflow_status(execution::WorkflowExecution)::Dict{String, Any}
    return Dict{String, Any}(
        "execution_id" => execution.execution_id,
        "status" => string(execution.status),
        "completed_steps" => length(execution.completed_steps),
        "failed_steps" => length(execution.failed_steps),
        "current_step" => execution.current_step,
        "started_at" => string(execution.started_at),
        "completed_at" => execution.completed_at !== nothing ? string(execution.completed_at) : nothing,
        "duration_seconds" => execution.completed_at !== nothing ? 
            (execution.completed_at - execution.started_at).value / 1000 : nothing
    )
end

"""
    cancel_workflow(execution::WorkflowExecution)::Bool

Cancel a running workflow execution.
"""
function cancel_workflow(execution::WorkflowExecution)::Bool
    if execution.status == STATUS_RUNNING || execution.status == STATUS_WAITING
        execution.status = STATUS_CANCELLED
        execution.completed_at = now()
        push!(execution.logs, "[$(now())] Workflow cancelled by user/system")
        return true
    end
    return false
end

"""
    estimate_execution_time(workflow::Workflow)::Float64

Estimate workflow execution time in seconds.
"""
function estimate_execution_time(workflow::Workflow)::Float64
    # Rough estimate: 10 seconds per step + 5 seconds per dependency
    base_time = length(workflow.steps) * 10.0
    
    # Add dependency overhead
    dep_count = sum(length(step.depends_on) for step in workflow.steps)
    dep_time = dep_count * 5.0
    
    return base_time + dep_time
end

# ============================================================================
# Workflow History (In-Memory)
# ============================================================================

const WORKFLOW_HISTORY = Vector{WorkflowExecution}()
const WORKFLOW_HISTORY_LOCK = ReentrantLock()

"""
    get_workflow_history(workflow_id::Union{String, Nothing}=nothing;
                        limit::Int=10)::Vector{WorkflowExecution}

Get workflow execution history.
"""
function get_workflow_history(workflow_id::Union{String, Nothing}=nothing;
                             limit::Int=10)::Vector{WorkflowExecution}
    lock(WORKFLOW_HISTORY_LOCK)
    try
        if workflow_id === nothing
            return WORKFLOW_HISTORY[max(1, end-limit+1):end]
        else
            filtered = filter(e -> e.workflow_id == workflow_id, WORKFLOW_HISTORY)
            return filtered[max(1, end-limit+1):end]
        end
    finally
        unlock(WORKFLOW_HISTORY_LOCK)
    end
end

# ============================================================================
# End of Module
# ============================================================================

end # module OpenClawWorkflow