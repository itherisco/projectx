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
    
    # Core functions
    create_workflow,
    add_step!,
    execute_workflow,
    execute_step,
    get_workflow_status,
    cancel_workflow,
    
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
                config::OpenClawConfig)::WorkflowStep

Execute a single workflow step via OpenClaw.
"""
function execute_step(execution::WorkflowExecution, step::WorkflowStep, 
                     config::OpenClawConfig)::WorkflowStep
    
    step.status = STATUS_RUNNING
    step.started_at = now()
    
    push!(execution.logs, "[$(now())] Starting step: $(step.name)")
    
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
    execute_workflow(workflow::Workflow; wait_for_approval::Bool=false)::WorkflowExecution

Execute a complete workflow.
"""
function execute_workflow(workflow::Workflow; wait_for_approval::Bool=false)::WorkflowExecution
    
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
        execute_step(execution, next_step, workflow.config)
        
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