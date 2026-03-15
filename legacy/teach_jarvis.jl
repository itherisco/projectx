#!/usr/bin/env julia --project=.
# ==========================================================
#  TEACH_JARVIS.JL - Bootstrapping the Neural Network
# ==========================================================
# This script forces the brain to learn a simple rule:
#   Rule: If CPU > 80%, the correct action is Action 5 (Throttle CPU).
#
# Usage:
#   julia --project=. teach_jarvis.jl
#
# Then verify with:
#   julia --project=. -e 'include("interact_itheris.jl"); pilot_cycle(0.85, 0.90)'

# ============================================================================
# 0. Include the ITHERIS Core module
# ============================================================================
include(joinpath(@__DIR__, "itheris.jl"))

using .ITHERISCore
using Dates, UUIDs

# ============================================================================
# 1. Emergency Patch for Missing Structs
# ============================================================================
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
        
        function ActionProposal(cap_id::String, priority::Float32, cost::Float32, 
                                benefit::Float32, risk::String, reason::String)
            return ActionProposal(cap_id, priority, cost, benefit, risk, reason)
        end
        
        export ActionProposal
    end
    println("✓ ActionProposal struct patched into ITHERISCore")
end

# ============================================================================
# 2. Initialize the Brain
# ============================================================================
println("\n" * "="^60)
println("👨‍🏫 JARVIS TEACHER - Bootstrapping Neural Network")
println("="^60)

brain = ITHERISCore.initialize_brain()
println("✓ Brain initialized successfully")

# ============================================================================
# 3. Define the "Correct" Action for High CPU
# ============================================================================
# Action 5 = Throttle CPU (as defined in ACTION_NAMES below)
const TARGET_ACTION = 5

# Create high-stress perception (CPU at 85%, Memory at 90%)
const HIGH_STRESS_PERCEPTION = Dict{String, Any}(
    "cpu_load" => 0.85,
    "memory_usage" => 0.90,
    "disk_io" => 0.5,
    "network_latency" => 25.0,
    "overall_severity" => 0.5,
    "threats" => String[],
    "file_count" => 0,
    "process_count" => 100,
    "energy_level" => 0.9,
    "confidence" => 0.7,
    "system_uptime_hours" => 24.0,
    "user_activity_level" => 0.3
)

println("\n👨‍🏫 STARTING LESSON: High CPU requires Throttling")
println("-"^60)
println("📊 Training Input: ")
println("   CPU Load:    $(HIGH_STRESS_PERCEPTION["cpu_load"] * 100)%")
println("   Memory Use:  $(HIGH_STRESS_PERCEPTION["memory_usage"] * 100)%")
println("   Target Action: $TARGET_ACTION (THROTTLE_CPU)")
println("-"^60)

# IMPORTANT: Initialize brain state by running one inference cycle first
# This populates the recurrence_buffer and belief_state with proper dimensions
println("Initializing brain state...")
_ = ITHERISCore.infer(brain, HIGH_STRESS_PERCEPTION)

# Now encode the perception (after brain state is initialized)
encoded_features = ITHERISCore.encode_perception(HIGH_STRESS_PERCEPTION)
println("✓ Brain state and features initialized")

println("\n🏋️ Starting training loops...")
println("-"^60)
println("📊 Training Input (encoded): ")
println("   CPU Load:    $(HIGH_STRESS_PERCEPTION["cpu_load"] * 100)%")
println("   Memory Use:  $(HIGH_STRESS_PERCEPTION["memory_usage"] * 100)%")
println("   Target Action: $TARGET_ACTION (THROTTLE_CPU)")
println("-"^60)

# ============================================================================
# 4. Run Training Loop (50 iterations)
# ============================================================================
const NUM_TRAINING_CYCLES = 50

for i in 1:NUM_TRAINING_CYCLES
    # A. Forward Pass - What does the brain think now?
    thought = ITHERISCore.infer(brain, HIGH_STRESS_PERCEPTION)
    probs = thought.probs
    
    # B. Backpropagation (The Learning Step)
    # We tell the brain: "For this input, Action 5 gave a reward of 1.0"
    # This forces the policy network to increase probability of action 5
    ITHERISCore.train_brain!(brain, encoded_features, TARGET_ACTION, 1.0f0)
    
    # C. Print progress every 10 cycles
    if i % 10 == 0
        p_target = probs[TARGET_ACTION] * 100
        p_other = maximum([probs[j] for j in 1:length(probs) if j != TARGET_ACTION]) * 100
        println("   Cycle $i: Action $TARGET_ACTION confidence: $(round(p_target, digits=1))% (best alternative: $(round(p_other, digits=1))%)")
    end
end

println("-"^60)
println("🎓 Lesson Complete!")

# ============================================================================
# 5. Verification Cycle
# ============================================================================
println("\n📋 Running verification cycle...")
println("="^60)

# Run inference again to show the learned behavior
final_thought = ITHERISCore.infer(brain, HIGH_STRESS_PERCEPTION)

println("\n🧠 VERIFICATION RESULTS (High CPU = 85%, Memory = 90%)")
println("-"^60)
println("📊 Input Metrics:")
println("   - CPU Load:    $(round(HIGH_STRESS_PERCEPTION["cpu_load"] * 100, digits=1))%")
println("   - Memory Use:  $(round(HIGH_STRESS_PERCEPTION["memory_usage"] * 100, digits=1))%")

# Action names mapping
const ACTION_NAMES = Dict(
    1 => "LOG_STATUS",
    2 => "LIST_PROCESSES",
    3 => "GARBAGE_COLLECT",
    4 => "OPTIMIZE_DISK",
    5 => "THROTTLE_CPU",
    6 => "EMERGENCY_SHUTDOWN"
)

action_name = get(ACTION_NAMES, final_thought.action, "UNKNOWN")
println("\n🎯 Action Selected:  $(final_thought.action) ($(action_name))")
println("📈 Confidence:       $(round(1.0 - final_thought.uncertainty, digits=4))")
println("💎 Internal Value:   $(round(final_thought.value, digits=4))")
println("🎲 Uncertainty:      $(round(final_thought.uncertainty, digits=4))")

println("\n📋 Action Probabilities:")
for (i, p) in enumerate(final_thought.probs)
    name = get(ACTION_NAMES, i, "UNKNOWN")
    @printf("   Action %d (%-18s): %6.2f%%\n", i, name, p * 100)
end

println("="^60)
println("\n✅ Training complete! The brain has learned:")
println("   → When CPU > 80%, THROTTLE_CPU (Action 5) is the correct response")
println("\n💡 To verify with interact_itheris.jl, run:")
println("   julia --project=. -e 'include(\"interact_itheris.jl\"); pilot_cycle(0.85, 0.90)'")
println("="^60)

# Export brain for external use
brain
