#!/usr/bin/env julia
# test_itheris_integration.jl - Integration tests for Itheris.jl Core Brain Functionality
# Tests the Rust-Julia FFI integration by validating the Julia cognitive brain

using Test
using Dates
using UUIDs
using Statistics
using Random
using JSON

# ============================================================================
# TEST CONFIGURATION
# ============================================================================

const TEST_OUTPUT_FILE = joinpath(@__DIR__, "test_results_itheris.json")

# Test results tracking
test_results = Dict{String, Any}(
    "timestamp" => string(now()),
    "tests" => [],
    "summary" => Dict(
        "total" => 0,
        "passed" => 0,
        "failed" => 0,
        "broken" => 0
    )
)

function record_test(name::String, passed::Bool, broken::Bool=false, details::String="")
    push!(test_results["tests"], Dict(
        "name" => name,
        "passed" => passed,
        "broken" => broken,
        "details" => details
    ))
    test_results["summary"]["total"] += 1
    if passed
        test_results["summary"]["passed"] += 1
    elseif broken
        test_results["summary"]["broken"] += 1
    else
        test_results["summary"]["failed"] += 1
    end
end

function save_results()
    open(TEST_OUTPUT_FILE, "w") do f
        JSON.print(f, test_results, 4)
    end
end

# ============================================================================
# LOAD REQUIRED MODULES
# ============================================================================

println("="^70)
println("ITHERIS CORE BRAIN INTEGRATION TESTS")
println("="^70)

# Add project to load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", ".."))

# Include the main brain module
include(joinpath(@__DIR__, "..", "..", "itheris.jl"))
using .ITHERISCore

# ============================================================================
# TEST SUITE 1: BRAIN INITIALIZATION
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 1: BRAIN INITIALIZATION")
println("="^70)

# Test default initialization
println("\n[TEST] Brain initialization with default parameters...")

brain = initialize_brain()

# Verify brain struct is created
@test brain isa BrainCore
record_test("BrainCore instance creation", true, false, "Default brain created successfully")

# Verify default dimensions
@test brain.input_size == 12
record_test("Default input size", brain.input_size == 12, false, "input_size = $(brain.input_size)")

@test brain.hidden_size == 128
record_test("Default hidden size", brain.hidden_size == 128, false, "hidden_size = $(brain.hidden_size)")

# Verify default hyperparameters
@test brain.learning_rate ≈ 0.01f0
record_test("Default learning rate", brain.learning_rate ≈ 0.01f0, false, "learning_rate = $(brain.learning_rate)")

@test brain.gamma ≈ 0.95f0
record_test("Default gamma", brain.gamma ≈ 0.95f0, false, "gamma = $(brain.gamma)")

@test brain.policy_temperature ≈ 1.5f0
record_test("Default policy temperature", brain.policy_temperature ≈ 1.5f0, false, "temperature = $(brain.policy_temperature)")

@test brain.entropy_coeff ≈ 0.01f0
record_test("Default entropy coefficient", brain.entropy_coeff ≈ 0.01f0, false, "entropy_coeff = $(brain.entropy_coeff)")

@test brain.attention_coeff ≈ 0.1f0
record_test("Default attention coefficient", brain.attention_coeff ≈ 0.1f0, false, "attention_coeff = $(brain.attention_coeff)")

# Verify state vectors
@test length(brain.belief_state) == 12
record_test("Belief state size", length(brain.belief_state) == 12, false, "length = $(length(brain.belief_state))")

@test length(brain.context_state) == 128
record_test("Context state size", length(brain.context_state) == 128, false, "length = $(length(brain.context_state))")

@test length(brain.last_hidden) == 128
record_test("Last hidden size", length(brain.last_hidden) == 128, false, "length = $(length(brain.last_hidden))")

# Verify cognitive metrics
@test brain.uncertainty ≈ 0.5f0
record_test("Initial uncertainty", brain.uncertainty ≈ 0.5f0, false, "uncertainty = $(brain.uncertainty)")

@test brain.novelty ≈ 0.3f0
record_test("Initial novelty", brain.novelty ≈ 0.3f0, false, "novelty = $(brain.novelty)")

@test brain.complexity ≈ 0.7f0
record_test("Initial complexity", brain.complexity ≈ 0.7f0, false, "complexity = $(brain.complexity)")

# Verify counters
@test brain.cycle_count == 0
record_test("Initial cycle count", brain.cycle_count == 0, false, "cycle_count = $(brain.cycle_count)")

@test brain.plan_count == 0
record_test("Initial plan count", brain.plan_count == 0, false, "plan_count = $(brain.plan_count)")

# Verify optimizers
@test haskey(brain.optimizers, "main")
record_test("Main optimizer exists", haskey(brain.optimizers, "main"), false)

@test haskey(brain.optimizers, "value")
record_test("Value optimizer exists", haskey(brain.optimizers, "value"), false)

@test haskey(brain.optimizers, "policy")
record_test("Policy optimizer exists", haskey(brain.optimizers, "policy"), false)

println("  ✓ All default parameter tests passed")

# Custom parameters test
println("\n[TEST] Brain initialization with custom parameters...")

brain2 = initialize_brain(
    input_size=8,
    hidden_size=64,
    learning_rate=0.02f0,
    gamma=0.9f0,
    policy_temperature=2.0f0,
    entropy_coeff=0.02f0,
    attention_coeff=0.2f0
)

@test brain2.input_size == 8
record_test("Custom input size", brain2.input_size == 8, false, "input_size = $(brain2.input_size)")

@test brain2.hidden_size == 64
record_test("Custom hidden size", brain2.hidden_size == 64, false, "hidden_size = $(brain2.hidden_size)")

@test brain2.learning_rate ≈ 0.02f0
record_test("Custom learning rate", brain2.learning_rate ≈ 0.02f0, false, "learning_rate = $(brain2.learning_rate)")

@test brain2.gamma ≈ 0.9f0
record_test("Custom gamma", brain2.gamma ≈ 0.9f0, false, "gamma = $(brain2.gamma)")

@test brain2.policy_temperature ≈ 2.0f0
record_test("Custom temperature", brain2.policy_temperature ≈ 2.0f0, false, "temperature = $(brain2.policy_temperature)")

println("  ✓ All custom parameter tests passed")

# ============================================================================
# TEST SUITE 2: PERCEPTION ENCODING
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 2: PERCEPTION ENCODING")
println("="^70)

println("\n[TEST] Encoding standard system perception...")

perception = Dict{String, Any}(
    "cpu_load" => 0.75,
    "memory_usage" => 0.6,
    "disk_io" => 0.3,
    "network_latency" => 50.0,
    "overall_severity" => 0.2,
    "threats" => ["low_risk_1"],
    "file_count" => 5000,
    "process_count" => 200,
    "energy_level" => 0.9,
    "confidence" => 0.7,
    "system_uptime_hours" => 48.0,
    "user_activity_level" => 0.5
)

encoded = encode_perception(perception)

@test length(encoded) == 12
record_test("Encoded dimension", length(encoded) == 12, false, "dimensions = $(length(encoded))")

encoded_mean = mean(encoded)
@test abs(encoded_mean) < 0.1
record_test("Mean centering", abs(encoded_mean) < 0.1, false, "mean = $encoded_mean")

@test all(-3.0f0 .<= encoded .<= 3.0f0)
record_test("Value range", all(-3.0f0 .<= encoded .<= 3.0f0), false, "range = [$(minimum(encoded)), $(maximum(encoded))]")

println("  ✓ Standard perception encoding tests passed")

# Edge cases
println("\n[TEST] Encoding edge case perceptions...")

perception_empty = Dict{String, Any}()
encoded_empty = encode_perception(perception_empty)
@test length(encoded_empty) == 12
record_test("Empty perception", length(encoded_empty) == 12, false)

perception_extreme = Dict{String, Any}(
    "cpu_load" => 100.0,
    "memory_usage" => -10.0,
    "network_latency" => 10000.0,
    "file_count" => 1000000,
    "process_count" => 10000,
    "system_uptime_hours" => 1000.0
)
encoded_extreme = encode_perception(perception_extreme)
@test length(encoded_extreme) == 12
record_test("Extreme values", length(encoded_extreme) == 12, false)

perception_test = Dict{String, Any}("cpu_load" => 0.5, "memory_usage" => 0.5)
encoded1 = encode_perception(perception_test)
encoded2 = encode_perception(perception_test)
@test encoded1 ≈ encoded2
record_test("Reproducibility", encoded1 ≈ encoded2, false)

println("  ✓ Edge case perception tests passed")

# ============================================================================
# TEST SUITE 3: INFERENCE
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 3: INFERENCE")
println("="^70)

println("\n[TEST] Running basic inference...")

brain = initialize_brain()

perception = Dict{String, Any}(
    "cpu_load" => 0.5,
    "memory_usage" => 0.5,
    "disk_io" => 0.3,
    "network_latency" => 50.0,
    "overall_severity" => 0.1,
    "threats" => [],
    "file_count" => 1000,
    "process_count" => 100,
    "energy_level" => 0.8,
    "confidence" => 0.7,
    "system_uptime_hours" => 24.0,
    "user_activity_level" => 0.3
)

thought = infer(brain, perception)

@test thought isa Thought
record_test("Thought type", thought isa Thought, false)

@test 1 <= thought.action <= 6
record_test("Action range", 1 <= thought.action <= 6, false, "action = $(thought.action)")

@test length(thought.probs) == 6
record_test("Probability count", length(thought.probs) == 6, false, "count = $(length(thought.probs))")

@test abs(sum(thought.probs) - 1.0f0) < 0.01
record_test("Probability sum", abs(sum(thought.probs) - 1.0f0) < 0.01, false, "sum = $(sum(thought.probs))")

@test all(0 .<= thought.probs .<= 1)
record_test("Probability bounds", all(0 .<= thought.probs .<= 1), false)

@test typeof(thought.value) == Float32
record_test("Value type", typeof(thought.value) == Float32, false)

@test 0 <= thought.uncertainty <= 1
record_test("Uncertainty range", 0 <= thought.uncertainty <= 1, false, "uncertainty = $(thought.uncertainty)")

@test length(thought.context_vector) == 128
record_test("Context vector size", length(thought.context_vector) == 128, false, "length = $(length(thought.context_vector))")

println("  ✓ Basic inference tests passed")

# ============================================================================
# TEST SUITE 4: LEARNING
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 4: LEARNING")
println("="^70)

println("\n[TEST] Running basic learning update...")

brain = initialize_brain()
initial_cycle_count = brain.cycle_count

perception1 = Dict{String, Any}(
    "cpu_load" => 0.5, "memory_usage" => 0.5, "disk_io" => 0.3,
    "network_latency" => 50.0, "overall_severity" => 0.1,
    "threats" => [], "file_count" => 1000, "process_count" => 100,
    "energy_level" => 0.8, "confidence" => 0.7,
    "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
)

thought = infer(brain, perception1)

perception2 = Dict{String, Any}(
    "cpu_load" => 0.4, "memory_usage" => 0.45, "disk_io" => 0.25,
    "network_latency" => 45.0, "overall_severity" => 0.05,
    "threats" => [], "file_count" => 1100, "process_count" => 105,
    "energy_level" => 0.85, "confidence" => 0.75,
    "system_uptime_hours" => 24.5, "user_activity_level" => 0.35
)

reward = 1.0f0
next_value = 0.8f0

learn!(brain, perception1, perception2, thought, reward, next_value)

@test brain.cycle_count == initial_cycle_count + 1
record_test("Cycle count increment", brain.cycle_count == initial_cycle_count + 1, false)

@test length(brain.episodic) >= 1
record_test("Experience stored", length(brain.episodic) >= 1, false, "count = $(length(brain.episodic))")

@test length(brain.reward_trace) >= 1
record_test("Reward trace", length(brain.reward_trace) >= 1, false, "count = $(length(brain.reward_trace))")

exp = brain.episodic[end]
@test exp.action == thought.action
record_test("Experience action", exp.action == thought.action, false, "action = $(exp.action)")

@test exp.reward == reward
record_test("Experience reward", exp.reward == reward, false, "reward = $(exp.reward)")

println("  ✓ Basic learning tests passed")

# Multiple learning steps
println("\n[TEST] Running multiple learning steps...")

brain = initialize_brain()

for i in 1:5
    perception1 = Dict{String, Any}(
        "cpu_load" => 0.5 + i*0.05, "memory_usage" => 0.5,
        "disk_io" => 0.3, "network_latency" => 50.0 + i*5,
        "overall_severity" => 0.1, "threats" => [],
        "file_count" => 1000 + i*100, "process_count" => 100,
        "energy_level" => 0.8, "confidence" => 0.7,
        "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
    )
    
    thought = infer(brain, perception1)
    
    perception2 = Dict{String, Any}(perception1)
    perception2["cpu_load"] = perception1["cpu_load"] - 0.1
    
    reward = Float32(rand(-1:1))
    learn!(brain, perception1, perception2, thought, reward, 0.5f0)
end

@test length(brain.episodic) >= 5
record_test("Multiple experiences", length(brain.episodic) >= 5, false, "count = $(length(brain.episodic))")

@test length(brain.reward_trace) >= 5
record_test("Reward history", length(brain.reward_trace) >= 5, false, "count = $(length(brain.reward_trace))")

@test brain.cycle_count >= 5
record_test("Cycle count", brain.cycle_count >= 5, false, "cycles = $(brain.cycle_count)")

println("  ✓ Multiple learning steps tests passed")

# ============================================================================
# TEST SUITE 5: DREAMING / WORLD MODEL
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 5: DREAMING / WORLD MODEL")
println("="^70)

println("\n[TEST] Dream with insufficient experiences...")

brain = initialize_brain()

dream_loss = dream!(brain)
@test dream_loss == 0.0f0
record_test("No experiences dream", dream_loss == 0.0f0, false, "loss = $dream_loss")

for i in 1:10
    perception1 = Dict{String, Any}(
        "cpu_load" => 0.5, "memory_usage" => 0.5, "disk_io" => 0.3,
        "network_latency" => 50.0, "overall_severity" => 0.1,
        "threats" => [], "file_count" => 1000, "process_count" => 100,
        "energy_level" => 0.8, "confidence" => 0.7,
        "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
    )
    thought = infer(brain, perception1)
    
    perception2 = Dict{String, Any}(perception1)
    perception2["cpu_load"] = 0.4
    
    learn!(brain, perception1, perception2, thought, 0.5f0, 0.5f0)
end

dream_loss = dream!(brain)
@test dream_loss == 0.0f0
record_test("Insufficient experiences dream", dream_loss == 0.0f0, false, "loss = $dream_loss")

println("  ✓ Insufficient data tests passed")

# Sufficient data
println("\n[TEST] Dream with sufficient experiences...")

brain = initialize_brain()

for i in 1:25
    perception1 = Dict{String, Any}(
        "cpu_load" => 0.5 + 0.02*sin(i), "memory_usage" => 0.5 + 0.01*i,
        "disk_io" => 0.3, "network_latency" => 50.0 + i,
        "overall_severity" => 0.1 + 0.01*i, "threats" => [],
        "file_count" => 1000 + i*50, "process_count" => 100 + i,
        "energy_level" => 0.8 - 0.01*i, "confidence" => 0.7 + 0.01*i,
        "system_uptime_hours" => 24.0 + i*0.1, "user_activity_level" => 0.3
    )
    thought = infer(brain, perception1)
    
    perception2 = Dict{String, Any}(perception1)
    perception2["cpu_load"] = perception1["cpu_load"] - 0.1
    perception2["memory_usage"] = perception1["memory_usage"] - 0.05
    
    reward = if i % 3 == 0 1.0f0 elseif i % 3 == 1 -0.5f0 else 0.0f0 end
    learn!(brain, perception1, perception2, thought, reward, 0.5f0)
end

dream_loss = dream!(brain)

@test dream_loss >= 0.0f0
record_test("Dream loss value", dream_loss >= 0.0f0, false, "loss = $dream_loss")

@test length(brain.episodic) > 0
record_test("Post-dream experiences", length(brain.episodic) > 0, false, "count = $(length(brain.episodic))")

println("  ✓ Sufficient data dream tests passed")

# ============================================================================
# TEST SUITE 6: COGNITIVE METRICS
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 6: COGNITIVE METRICS")
println("="^70)

println("\n[TEST] Getting stats from empty brain...")

brain = initialize_brain()
stats = get_stats(brain)

@test stats isa Dict
record_test("Stats type", stats isa Dict, false)

@test haskey(stats, "avg_reward")
record_test("Has avg_reward", haskey(stats, "avg_reward"), false)

@test haskey(stats, "experience_count")
record_test("Has experience_count", haskey(stats, "experience_count"), false)

@test haskey(stats, "total_cycles")
record_test("Has total_cycles", haskey(stats, "total_cycles"), false)

@test haskey(stats, "learning_rate")
record_test("Has learning_rate", haskey(stats, "learning_rate"), false)

@test haskey(stats, "uncertainty")
record_test("Has uncertainty", haskey(stats, "uncertainty"), false)

@test haskey(stats, "novelty")
record_test("Has novelty", haskey(stats, "novelty"), false)

@test haskey(stats, "complexity")
record_test("Has complexity", haskey(stats, "complexity"), false)

@test haskey(stats, "plan_count")
record_test("Has plan_count", haskey(stats, "plan_count"), false)

@test stats["avg_reward"] == 0.0
record_test("Empty avg_reward", stats["avg_reward"] == 0.0, false)

@test stats["experience_count"] == 0
record_test("Empty experience_count", stats["experience_count"] == 0, false)

@test stats["total_cycles"] == 0
record_test("Empty total_cycles", stats["total_cycles"] == 0, false)

println("  ✓ Empty brain stats tests passed")

# Active brain
println("\n[TEST] Getting stats from active brain...")

brain = initialize_brain()

for i in 1:15
    perception1 = Dict{String, Any}(
        "cpu_load" => 0.5 + 0.02*sin(i), "memory_usage" => 0.5,
        "disk_io" => 0.3, "network_latency" => 50.0,
        "overall_severity" => 0.1, "threats" => [],
        "file_count" => 1000, "process_count" => 100,
        "energy_level" => 0.8, "confidence" => 0.7,
        "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
    )
    thought = infer(brain, perception1)
    
    perception2 = Dict{String, Any}(perception1)
    perception2["cpu_load"] = 0.4
    
    reward = Float32(i % 3 == 0 ? 1.0 : (i % 3 == 1 ? -0.5 : 0.0))
    learn!(brain, perception1, perception2, thought, reward, 0.5f0)
end

stats = get_stats(brain)

@test stats["experience_count"] >= 15
record_test("Active experience_count", stats["experience_count"] >= 15, false, "count = $(stats["experience_count"])")

@test stats["total_cycles"] >= 15
record_test("Active total_cycles", stats["total_cycles"] >= 15, false, "cycles = $(stats["total_cycles"])")

@test stats["avg_reward"] != 0.0
record_test("Active avg_reward", stats["avg_reward"] != 0.0, false, "reward = $(stats["avg_reward"])")

@test haskey(stats, "recent_avg_reward")
record_test("Has recent_avg_reward", haskey(stats, "recent_avg_reward"), false)

@test haskey(stats, "policy_temperature")
record_test("Has policy_temperature", haskey(stats, "policy_temperature"), false)

@test haskey(stats, "belief_state_norm")
record_test("Has belief_state_norm", haskey(stats, "belief_state_norm"), false)

@test haskey(stats, "attention_entropy")
record_test("Has attention_entropy", haskey(stats, "attention_entropy"), false)

println("  ✓ Active brain stats tests passed")

# ============================================================================
# TEST SUITE 7: PLANNING
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 7: PLANNING")
println("="^70)

println("\n[TEST] Basic planning functionality...")

brain = initialize_brain()

perception = Dict{String, Any}(
    "cpu_load" => 0.5, "memory_usage" => 0.5, "disk_io" => 0.3,
    "network_latency" => 50.0, "overall_severity" => 0.1,
    "threats" => [], "file_count" => 1000, "process_count" => 100,
    "energy_level" => 0.8, "confidence" => 0.7,
    "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
)

planned_result = plan(brain, perception, horizon=5)

@test planned_result isa Plan
record_test("Plan type", planned_result isa Plan, false)

@test length(planned_result.actions) == 5
record_test("Plan horizon", length(planned_result.actions) == 5, false, "actions = $(length(planned_result.actions))")

@test all(1 .<= planned_result.actions .<= 6)
record_test("Action validity", all(1 .<= planned_result.actions .<= 6), false)

@test length(planned_result.expected_rewards) == 5
record_test("Expected rewards count", length(planned_result.expected_rewards) == 5, false)

@test 0 <= planned_result.confidence <= 1
record_test("Confidence range", 0 <= planned_result.confidence <= 1, false, "confidence = $(planned_result.confidence)")

@test brain.plan_count >= 1
record_test("Plan count", brain.plan_count >= 1, false, "count = $(brain.plan_count)")

println("  ✓ Basic planning tests passed")

# Plan evaluation
println("\n[TEST] Plan evaluation...")

planned2 = plan(brain, perception, horizon=3)
evaluation = evaluate_plan(brain, planned2)

@test evaluation isa Float32
record_test("Evaluation type", evaluation isa Float32, false)

empty_plan = Plan(uuid4(), [], [], 1.0f0, now(), now())
empty_eval = evaluate_plan(brain, empty_plan)
@test empty_eval == 0.0f0
record_test("Empty plan evaluation", empty_eval == 0.0f0, false)

println("  ✓ Plan evaluation tests passed")

# ============================================================================
# TEST SUITE 8: FALLBACK MODE (No Rust)
# ============================================================================

println("\n" * "="^70)
println("TEST SUITE 8: FALLBACK MODE")
println("="^70)

println("\n[TEST] Verifying Julia brain works without Rust...")

brain = initialize_brain()

for i in 1:10
    perception = Dict{String, Any}(
        "cpu_load" => 0.5, "memory_usage" => 0.5, "disk_io" => 0.3,
        "network_latency" => 50.0, "overall_severity" => 0.1,
        "threats" => [], "file_count" => 1000, "process_count" => 100,
        "energy_level" => 0.8, "confidence" => 0.7,
        "system_uptime_hours" => 24.0, "user_activity_level" => 0.3
    )
    
    thought = infer(brain, perception)
    
    perception2 = Dict{String, Any}(perception)
    perception2["cpu_load"] = 0.4
    learn!(brain, perception, perception2, thought, 1.0f0, 0.5f0)
end

@test brain.cycle_count >= 10
record_test("Fallback cycles", brain.cycle_count >= 10, false, "cycles = $(brain.cycle_count)")

@test length(brain.episodic) >= 10
record_test("Fallback experiences", length(brain.episodic) >= 10, false, "count = $(length(brain.episodic))")

stats = get_stats(brain)
@test stats["total_cycles"] >= 10
record_test("Fallback stats", stats["total_cycles"] >= 10, false)

println("  ✓ Fallback mode tests passed")

# ============================================================================
# RUN ALL TESTS AND SAVE RESULTS
# ============================================================================

println("\n" * "="^70)
println("TEST EXECUTION COMPLETE")
println("="^70)

# Save results to JSON
save_results()

# Print summary
println("\n" * "="^70)
println("TEST SUMMARY")
println("="^70)
println("Total tests: $(test_results["summary"]["total"])")
println("Passed:      $(test_results["summary"]["passed"])")
println("Failed:      $(test_results["summary"]["failed"])")
println("Broken:      $(test_results["summary"]["broken"])")
println("="^70)

# Print JSON output location
println("\nResults saved to: $TEST_OUTPUT_FILE")
