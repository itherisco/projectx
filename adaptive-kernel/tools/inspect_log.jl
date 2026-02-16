#!/usr/bin/env julia
# tools/inspect_log.jl - Summarize events.log and compute metrics

using JSON
using Statistics
using Dates

"""
    inspect_log(log_file::String="events.log")
Analyze and summarize the event log.
"""
function inspect_log(log_file::String="events.log")
    if !isfile(log_file)
        println("Error: $log_file not found")
        return
    end
    
    events = []
    for line in readlines(log_file)
        if !isempty(strip(line))
            try
                push!(events, JSON.parse(line))
            catch
            end
        end
    end
    
    if isempty(events)
        println("No events in log")
        return
    end
    
    println("\n=== Event Log Summary ===")
    println("Total events: $(length(events))")
    
    # Categorize by type
    action_events = filter(e -> get(e, "type", "") == "action_executed", events)
    state_events = filter(e -> get(e, "type", "") == "state_dump", events)
    
    println("Action events: $(length(action_events))")
    println("State snapshots: $(length(state_events))")
    
    # Success rate
    if !isempty(action_events)
        successes = sum(get(e, "success", false) for e in action_events)
        success_rate = successes / length(action_events)
        println("Success rate: $(round(100 * success_rate, digits=1))%")
    end
    
    # Risk breakdown
    if !isempty(action_events)
        low_risk = sum(get(e, "risk", "") == "low" for e in action_events)
        med_risk = sum(get(e, "risk", "") == "medium" for e in action_events)
        high_risk = sum(get(e, "risk", "") == "high" for e in action_events)
        
        println("\nRisk Distribution:")
        println("  Low:    $low_risk")
        println("  Medium: $med_risk")
        println("  High:   $high_risk")
    end
    
    # Final state
    if !isempty(state_events)
        last_state = state_events[end]["data"]
        println("\nFinal Kernel State:")
        println("  Cycle: $(get(last_state, "cycle", "?"))")
        println("  Confidence: $(round(get(last_state, "confidence", 0), digits=3))")
        println("  Energy: $(round(get(last_state, "energy", 0), digits=3))")
        println("  Memory Size: $(get(last_state, "episodic_memory_size", 0))")
    end
    
    println("\n✓ Log inspection complete\n")
end

if abspath(PROGRAM_FILE) == @__FILE__
    log_file = get(ARGS, 1, "events.log")
    inspect_log(log_file)
end
