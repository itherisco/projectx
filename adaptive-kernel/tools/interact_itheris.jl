#!/usr/bin/env julia --project=.
# interact_itheris.jl - ITHERIS-Jarvis Command Center
# This script provides a clean interface to interact with the Brain

# ============================================================================
# 0. Include the ITHERIS Core module
# ============================================================================
include(joinpath(@__DIR__, "itheris.jl"))

using .ITHERISCore
using Dates, UUIDs

# ============================================================================
# 1. Action Names Mapping
# ============================================================================
const ACTION_NAMES = Dict(
    1 => "LOG_STATUS",
    2 => "LIST_PROCESSES",
    3 => "GARBAGE_COLLECT",
    4 => "OPTIMIZE_DISK",
    5 => "THROTTLE_CPU",
    6 => "EMERGENCY_SHUTDOWN"
)

# ============================================================================
# 2. Emergency Patch for Missing Structs
# ============================================================================
# If ActionProposal isn't defined in ITHERISCore yet, define it here for the session
# This struct is required by tests and provides action selection metadata
if !isdefined(ITHERISCore, :ActionProposal)
    @eval ITHERISCore begin
        mutable struct ActionProposal
            capability_id::String
            priority_score::Float32
            estimated_cost::Float32
            expected_benefit::Float32
            risk_level::String
            reasoning::String
        end
        
        # Constructor for convenience
        function ActionProposal(cap_id::String, priority::Float32, cost::Float32, 
                                benefit::Float32, risk::String, reason::String)
            return ActionProposal(cap_id, priority, cost, benefit, risk, reason)
        end
        
        export ActionProposal
    end
    println("✓ ActionProposal struct patched into ITHERISCore")
end

# ============================================================================
# 3. Initialize the System
# ============================================================================
println("Initializing ITHERIS-Jarvis Core...")
brain = ITHERISCore.initialize_brain()
println("✓ Brain initialized successfully")
println("  - Network layers: $(length(brain.layers))")
println("  - Input size: $(brain.input_size)")
println("  - Hidden size: $(brain.hidden_size)")

# ============================================================================
# 4. Interaction Function - The Pilot's Seat
# ============================================================================
"""
    pilot_cycle(cpu_load::Float64, mem_usage::Float64)

Execute a cognitive cycle with simulated system metrics.

# Arguments
- `cpu_load`: CPU load fraction (0.0 to 1.0)
- `mem_usage`: Memory usage fraction (0.0 to 1.0)

# Returns
- `Thought`: The result containing action, probabilities, value, and uncertainty
"""
function pilot_cycle(cpu_load::Float64, mem_usage::Float64)
    # Validate inputs
    cpu_load = clamp(cpu_load, 0.0, 1.0)
    mem_usage = clamp(mem_usage, 0.0, 1.0)
    
    # Construct simulated perception (matches encode_perception expected keys)
    perception = Dict{String, Any}(
        "cpu_load" => cpu_load,
        "memory_usage" => mem_usage,
        "disk_io" => 0.3,
        "network_latency" => 25.0,
        "overall_severity" => 0.0,
        "threats" => String[],
        "file_count" => 0,
        "process_count" => 100,
        "energy_level" => 0.9,
        "confidence" => 0.7,
        "system_uptime_hours" => 24.0,
        "user_activity_level" => 0.3
    )
    
    # Execute Cognitive Cycle via the Brain's inference
    thought = ITHERISCore.infer(brain, perception)
    
    # Display results
    println("\n" * "="^50)
    println("🧠 COGNITIVE CYCLE RESULTS")
    println("="^50)
    println("📊 Input Metrics:")
    println("   - CPU Load:    $(round(cpu_load * 100, digits=1))%")
    println("   - Memory Use:  $(round(mem_usage * 100, digits=1))%")
    action_name = get(ACTION_NAMES, thought.action, "UNKNOWN")
    println("\n🎯 Action Selected:  $(thought.action) ($(action_name))")
    println("📈 Confidence:       $(round(1.0 - thought.uncertainty, digits=4))")
    println("💎 Internal Value:   $(round(thought.value, digits=4))")
    println("🎲 Uncertainty:      $(round(thought.uncertainty, digits=4))")
    println("\n📋 Action Probabilities:")
    for (i, p) in enumerate(thought.probs)
        if p > 0.01
            name = get(ACTION_NAMES, i, "UNKNOWN")
            @printf("   Action %d (%-18s): %6.2f%%\n", i, name, p * 100)
        end
    end
    println("="^50)
    
    return thought
end

# ============================================================================
# 5. Convenience Functions for Exploration
# ============================================================================
"""
    get_brain_stats() -> Dict

Get current statistics about the brain's internal state.
"""
function get_brain_stats()
    return ITHERISCore.get_stats(brain)
end

"""
    run_dream_cycle()

Trigger a dreaming cycle for offline consolidation using Experience Replay.
"""
function run_dream_cycle()
    println("\n🌙 Initiating dream cycle for memory consolidation...")
    ITHERISCore.run_dream_cycle(brain)
    println("✓ Dream cycle complete")
end

# ============================================================================
# 6. Welcome Message
# ============================================================================
println("\n" * "="^60)
println("🚀 ITHERIS-JARVIS COMMAND CENTER READY")
println("="^60)
println("\nAvailable commands:")
println("  • pilot_cycle(cpu, mem)  - Run a cognitive cycle")
println("  • get_brain_stats()       - View brain internal state")
println("  • run_dream_cycle()       - Trigger memory consolidation")
println("\nExample usage:")
println("  julia> pilot_cycle(0.9, 0.8)  # High stress scenario")
println("  julia> pilot_cycle(0.3, 0.4)  # Low stress scenario")
println("="^60)
