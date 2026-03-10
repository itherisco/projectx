"""
# Goal Planner Module

Converts goals into execution plans using Hierarchical Task Network (HTN) decomposition.

Each plan step contains:
- action: String (what to do)
- required_capability: Symbol (which capability is needed)
- expected_result: String (what we expect to happen)
- risk_level: Symbol (:low, :medium, :high)
"""

module Planner

using Dates
using UUIDs

# Import Goal types
include("goal_generator.jl")
using .GoalGenerator

# Plan step structure
struct PlanStep
    action::String
    required_capability::Symbol
    expected_result::String
    risk_level::Symbol
    params::Dict{String, Any}
end

# Execution plan
struct Plan
    id::UUID
    goal_id::UUID
    goal_name::Symbol
    steps::Vector{PlanStep}
    created_at::DateTime
    estimated_duration::Float64  # seconds
end

# Goal to capability mapping (HTN domain)
const GOAL_DECOMPOSITION = Dict{Symbol, Vector{PlanStep}}(
    :run_self_diagnostic => [
        PlanStep("check_system_logs", :read_logs, "Identify any errors in logs", :low, Dict()),
        PlanStep("verify_processes", :check_processes, "Confirm all critical processes running", :low, Dict()),
        PlanStep("check_memory_usage", :observe_memory, "Report memory usage", :low, Dict()),
    ],
    :optimize_runtime => [
        PlanStep("analyze_system_metrics", :observe_cpu, "Identify CPU bottlenecks", :low, Dict()),
        PlanStep("identify_bottlenecks", :analyze_logs, "Find performance issues", :low, Dict()),
        PlanStep("adjust_parameters", :configure_system, "Apply optimizations", :medium, Dict()),
    ],
    :compress_memory => [
        PlanStep("analyze_memory", :observe_memory, "Identify memory-heavy objects", :low, Dict()),
        PlanStep("gc_collect", :trigger_gc, "Run garbage collection", :medium, Dict()),
        PlanStep("verify_improvement", :observe_memory, "Confirm memory freed", :low, Dict()),
    ],
    :cleanup_logs => [
        PlanStep("analyze_log_size", :read_logs, "Check log file sizes", :low, Dict()),
        PlanStep("archive_old_logs", :write_file, "Archive logs older than 7 days", :medium, Dict()),
        PlanStep("delete_archived", :delete_files, "Remove archived logs", :high, Dict()),
    ],
    :verify_security => [
        PlanStep("check_open_ports", :observe_network, "Verify expected ports only", :low, Dict()),
        PlanStep("verify_capabilities", :check_permissions, "Confirm capability whitelist", :low, Dict()),
        PlanStep("audit_recent_actions", :read_logs, "Check for suspicious activity", :medium, Dict()),
    ],
    :index_new_knowledge => [
        PlanStep("scan_knowledge_base", :read_files, "Find new documents", :low, Dict()),
        PlanStep("update_index", :index_documents, "Add to search index", :medium, Dict()),
    ],
    :update_embeddings => [
        PlanStep("export_data", :read_files, "Get current embeddings", :low, Dict()),
        PlanStep("recompute_embeddings", :compute_embeddings, "Generate new vectors", :high, Dict()),
        PlanStep("update_store", :write_file, "Save updated embeddings", :medium, Dict()),
    ],
    :check_disk_space => [
        PlanStep("scan_filesystems", :observe_filesystem, "Check disk usage", :low, Dict()),
        PlanStep("identify_large_files", :read_files, "Find space consumers", :low, Dict()),
    ],
    :backup_state => [
        PlanStep("serialize_state", :read_files, "Capture current state", :medium, Dict()),
        PlanStep("write_backup", :write_file, "Write to backup location", :medium, Dict()),
    ],
)

"""
Create an execution plan for a goal.
Returns empty plan if goal type is not supported.
"""
function create_plan(goal::Goal)::Plan
    steps = get(GOAL_DECOMPOSITION, goal.name, PlanStep[])
    
    plan = Plan(
        uuid4(),
        goal.id,
        goal.name,
        steps,
        now(),
        length(steps) * 10.0  # Estimate 10 seconds per step
    )
    
    return plan
end

"""
Get a human-readable plan summary.
"""
function summarize(plan::Plan)::String
    step_names = [step.action for step in plan.steps]
    return "Plan $(plan.id) for $(plan.goal_name): $(join(step_names, " → "))"
end

"""
Validate that a plan has all required steps.
"""
function validate(plan::Plan)::Bool
    return !isempty(plan.steps)
end

"""
Estimate total execution time for a plan.
"""
function estimate_duration(plan::Plan)::Float64
    total = 0.0
    for step in plan.steps
        # Base time + risk factor
        base_time = 5.0  # 5 seconds base
        risk_factor = step.risk_level == :high ? 2.0 : step.risk_level == :medium ? 1.5 : 1.0
        total += base_time * risk_factor
    end
    return total
end

end # module
