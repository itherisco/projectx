#!/usr/bin/env julia
# run_diagnostic.jl - Comprehensive system execution with detailed logging

using Dates
using JSON
using Statistics

println("=" ^ 80)
println("COMPREHENSIVE SYSTEM EXECUTION WITH DETAILED LOGGING")
println("Started: ", now())
println("=" ^ 80)

# Include modules
include("kernel/Kernel.jl")
include("persistence/Persistence.jl")

using .Kernel
using .Persistence

# Import persistence functions explicitly
import .Persistence: init_persistence, save_event, load_events

println("\n[PHASE 1] Environment Setup")
println("-" ^ 40)

# Initialize persistence layer
init_persistence()
println("✓ Persistence layer initialized")

# Clean previous events
rm("events.log", force=true)
println("✓ Previous event log cleared")

# Set up performance tracking
const PERF_START = time()

println("\n[PHASE 2] Kernel Initialization")
println("-" ^ 40)

# Initialize kernel with test configuration
config = Dict(
    "goals" => [
        Dict("id" => "system_monitoring", "description" => "Continuous system health monitoring", "priority" => 0.95),
        Dict("id" => "resource_optimization", "description" => "Optimize resource allocation", "priority" => 0.85),
        Dict("id" => "security_monitoring", "description" => "Monitor for security threats", "priority" => 0.90)
    ],
    "observations" => Dict(
        "cpu_load" => 0.45,
        "memory_usage" => 0.55,
        "disk_io" => 120,
        "network_latency" => 25.0
    )
)

ks = Kernel.init_kernel(config)
println("✓ Kernel initialized")
println("  - Initial cycle: ", ks.cycle[])
println("  - Goals loaded: ", length(ks.goals))

# Log kernel initialization event
save_event(Dict(
    "timestamp" => string(now()),
    "event_type" => "kernel_init",
    "cycle" => 0,
    "goals_count" => length(ks.goals),
    "initial_confidence" => ks.self_metrics["confidence"],
    "initial_energy" => ks.self_metrics["energy"]
))

println("\n[PHASE 3] 50-Cycle Execution with Comprehensive Logging")
println("-" ^ 40)

# Define capability candidates
candidates = [
    Dict("id" => "observe_cpu", "name" => "CPU Observation", "cost" => 0.02, "risk" => "low", "confidence" => 0.92),
    Dict("id" => "observe_filesystem", "name" => "Filesystem Observation", "cost" => 0.03, "risk" => "low", "confidence" => 0.88),
    Dict("id" => "analyze_logs", "name" => "Log Analysis", "cost" => 0.05, "risk" => "low", "confidence" => 0.85),
    Dict("id" => "estimate_risk", "name" => "Risk Estimation", "cost" => 0.04, "risk" => "low", "confidence" => 0.80),
    Dict("id" => "safe_shell", "name" => "Safe Shell Execution", "cost" => 0.08, "risk" => "medium", "confidence" => 0.75)
]

# Execution function with timing
function timed_execute(cap_id)
    exec_start = time()
    
    result = if occursin("cpu", cap_id)
        Dict("success" => true, "effect" => "CPU observed: 45%", "actual_confidence" => 0.92f0, "energy_cost" => 0.02f0)
    elseif occursin("filesystem", cap_id)
        Dict("success" => true, "effect" => "Filesystem observed: 1500 files", "actual_confidence" => 0.88f0, "energy_cost" => 0.03f0)
    elseif occursin("analyze", cap_id)
        Dict("success" => true, "effect" => "Logs analyzed: 500 entries", "actual_confidence" => 0.85f0, "energy_cost" => 0.05f0)
    elseif occursin("risk", cap_id)
        Dict("success" => true, "effect" => "Risk estimated: low", "actual_confidence" => 0.80f0, "energy_cost" => 0.04f0)
    elseif occursin("shell", cap_id)
        Dict("success" => true, "effect" => "Shell command executed", "actual_confidence" => 0.75f0, "energy_cost" => 0.08f0)
    else
        Dict("success" => false, "effect" => "Unknown capability", "actual_confidence" => 0.0f0, "energy_cost" => 0.0f0)
    end
    
    exec_time = time() - exec_start
    result["execution_time_ms"] = exec_time * 1000
    return result
end

# Permission function
permission_fn = (risk) -> risk != "high"

# Verify function for FlowIntegrity
verify_fn = (cap_id, token) -> Dict("success" => true, "verified" => true)

# Run 50 cycles
action_log = []
cycle_times = Float64[]

for cycle in 1:50
    cycle_start = time()
    
    ks, action, result = Kernel.step_once(ks, candidates, timed_execute, permission_fn; verify_fn=verify_fn)
    
    cycle_time = time() - cycle_start
    push!(cycle_times, cycle_time)
    
    event = Dict(
        "timestamp" => string(now()),
        "cycle" => ks.cycle[],
        "event_type" => "action_executed",
        "action_id" => action.capability_id,
        "action_risk" => action.risk,
        "action_confidence" => action.confidence,
        "action_predicted_reward" => action.predicted_reward,
        "execution_success" => get(result, "success", false),
        "execution_effect" => get(result, "effect", ""),
        "execution_time_ms" => get(result, "execution_time_ms", 0.0),
        "energy_cost" => get(result, "energy_cost", 0.0),
        "cycle_time_ms" => cycle_time * 1000
    )
    
    push!(action_log, event)
    save_event(event)
    
    if cycle % 10 == 0
        stats = Kernel.get_kernel_stats(ks)
        println("  Cycle $cycle: action=$(action.capability_id), success=$(result["success"]), time=$(round(cycle_time*1000, digits=1))ms")
        println("    Confidence: $(round(stats["confidence"], digits=3)), Energy: $(round(stats["energy"], digits=3))")
    end
end

println("\n[PHASE 4] Performance Metrics Analysis")
println("-" ^ 40)

# Calculate metrics
total_time = time() - PERF_START
avg_cycle_time = mean(cycle_times) * 1000
min_cycle_time = minimum(cycle_times) * 1000
max_cycle_time = maximum(cycle_times) * 1000
std_cycle_time = std(cycle_times) * 1000

success_count = count(e -> get(e, "execution_success", false), action_log)
failure_count = length(action_log) - success_count
success_rate = success_count / length(action_log) * 100

# Risk distribution
risk_counts = Dict("low" => 0, "medium" => 0, "high" => 0)
for event in action_log
    risk = get(event, "action_risk", "unknown")
    risk_counts[risk] = get(risk_counts, risk, 0) + 1
end

avg_confidence = mean(e -> get(e, "action_confidence", 0.0), action_log)
avg_execution_time = mean(e -> get(e, "execution_time_ms", 0.0), action_log)

println("Execution Summary:")
println("  Total runtime: ", round(total_time, digits=2), " seconds")
println("  Total cycles: ", length(cycle_times))
println("  Success rate: ", round(success_rate, digits=1), " percent ($success_count/$failure_count)")
println("")
println("Timing Metrics:")
println("  Average cycle time: ", round(avg_cycle_time, digits=2), " ms")
println("  Min cycle time: ", round(min_cycle_time, digits=2), " ms")
println("  Max cycle time: ", round(max_cycle_time, digits=2), " ms")
println("  Std deviation: ", round(std_cycle_time, digits=2), " ms")
println("")
println("Action Distribution:")
println("  Low risk: ", get(risk_counts, "low", 0))
println("  Medium risk: ", get(risk_counts, "medium", 0))
println("  High risk: ", get(risk_counts, "high", 0))
println("")
println("Quality Metrics:")
println("  Average confidence: ", round(avg_confidence, digits=3))
println("  Average execution time: ", round(avg_execution_time, digits=2), " ms")

# Save final kernel state
final_stats = Kernel.get_kernel_stats(ks)
save_kernel_state(final_stats)

# Log final state
save_event(Dict(
    "timestamp" => string(now()),
    "event_type" => "execution_complete",
    "cycle" => ks.cycle[],
    "total_time_seconds" => total_time,
    "success_rate" => success_rate,
    "avg_cycle_time_ms" => avg_cycle_time,
    "final_confidence" => final_stats["confidence"],
    "final_energy" => final_stats["energy"]
))

println("\n[PHASE 5] Event Log Verification")
println("-" ^ 40)

# Load and verify events
events = load_events()
println("Total events logged: ", length(events))

# Sample of recent events
println("\nLast 5 events:")
for event in events[max(1,end-4):end]
    println("  [$(event["cycle"])] $(event["event_type"]): $(get(event, "action_id", "N/A"))")
end

# Save diagnostic report
diagnostic_report = Dict(
    "execution_summary" => Dict(
        "total_runtime_seconds" => total_time,
        "total_cycles" => length(cycle_times),
        "success_rate_percent" => success_rate,
        "success_count" => success_count,
        "failure_count" => failure_count
    ),
    "timing_metrics" => Dict(
        "avg_cycle_time_ms" => avg_cycle_time,
        "min_cycle_time_ms" => min_cycle_time,
        "max_cycle_time_ms" => max_cycle_time,
        "std_deviation_ms" => std_cycle_time
    ),
    "action_distribution" => risk_counts,
    "quality_metrics" => Dict(
        "avg_confidence" => avg_confidence,
        "avg_execution_time_ms" => avg_execution_time
    ),
    "final_kernel_state" => final_stats
)

open("diagnostic_report.json", "w") do f
    JSON.print(f, diagnostic_report, 2)
end

println("\nDiagnostic report saved to: diagnostic_report.json")

println("\n" * "=" ^ 80)
println("EXECUTION COMPLETE")
println("Completed: ", now())
println("=" ^ 80)
