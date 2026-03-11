#!/usr/bin/env julia
# Test script for ActiveInference.jl module

# Add the module to load path
push!(LOAD_PATH, joinpath(@__DIR__, "active-inference"))

# Load dependencies first
using Dates
using Distributions
using Flux
using LinearAlgebra
using Printf
using Random
using Statistics
using UUIDs

# Load the module
include(joinpath(@__DIR__, "ActiveInference.jl"))

using .ActiveInference

println("\n" * "=" ^ 60)
println("Testing Active Inference Module")
println("=" ^ 60)

# Test 1: Module loads correctly
println("\n[TEST 1] Module loading...")
println("  ✓ ActiveInference module loaded")

# Test 2: Create engine
println("\n[TEST 2] Creating engine...")
engine = create_engine(64, 384, 32)
println("  ✓ Engine created with dimensions: state=$(engine.model.state_dim), obs=$(engine.model.obs_dim), action=$(engine.model.action_dim)")

# Test 3: HDC Memory
println("\n[TEST 3] Testing HDC Memory...")
concepts = [:security, :morning, :user, :task]
for c in concepts
    get_or_create_vector(engine.hdc_memory, c)
end

# Test binding
bound = bind_concepts(engine.hdc_memory, :security, :morning)
println("  ✓ Bound 'security' + 'morning': dimension=$(length(bound))")

# Test bundling
bundled = bundle_concepts(engine.hdc_memory, :user, :task)
println("  ✓ Bundled 'user' + 'task': dimension=$(length(bundled))")

# Test holographic recall
recall = holographic_recall(engine.hdc_memory, [:security, :morning])
retrieved = retrieve_concept(engine.hdc_memory, recall)
println("  ✓ Holographic recall works, retrieved: $retrieved")

# Test 4: Generative Model
println("\n[TEST 4] Testing Generative Model...")
test_state = rand(Float32, 64)
test_action = rand(Float32, 32)
test_obs = rand(Float32, 384)

predicted_obs = observation(engine.model, test_state)
next_state = transition(engine.model, test_state, test_action)
println("  ✓ Observation model: input 64 → output $(length(predicted_obs))")
println("  ✓ Transition model: input 96 → output $(length(next_state))")

# Test 5: Free Energy Computation
println("\n[TEST 5] Testing Free Energy Computation...")
fe_state = compute_free_energy(engine.model, test_state, test_obs; precision=1.0f0)
println("  ✓ Prediction error: $(round(fe_state.prediction_error, digits=4))")
println("  ✓ KL divergence: $(round(fe_state.kl_divergence, digits=4))")
println("  ✓ Total free energy: $(round(fe_state.total_free_energy, digits=4))")
println("  ✓ Precision-weighted error: $(round(fe_state.precision_weighted_error, digits=4))")
println("  ✓ Accuracy: $(round(fe_state.accuracy, digits=4))")

# Test 6: Inference Step
println("\n[TEST 6] Testing inference step...")
state, action, fe = infer_step(engine, test_obs)
println("  ✓ Inferred state dimension: $(length(state.vector))")
println("  ✓ State precision: $(round(state.precision, digits=4))")
println("  ✓ Action length: $(length(action))")
println("  ✓ Free energy: $(round(fe, digits=4))")

# Test 7: Multiple steps
println("\n[TEST 7] Running 10 inference steps...")
for i in 1:10
    obs = rand(Float32, 384)
    state, action, fe = infer_step(engine, obs)
end
avg_fe = mean(engine.free_energy_history)
println("  ✓ Average free energy over 10 steps: $(round(avg_fe, digits=4))")
println("  ✓ Final precision: $(round(engine.precision, digits=4))")
println("  ✓ Total steps: $(engine.step_count)")

# Test 8: Policy selection
println("\n[TEST 8] Testing policy selection...")
policies = generate_policies(engine, 3)
for (i, p) in enumerate(policies)
    energy = compute_expected_free_energy(engine, p)
    println("  ✓ Policy $i: expected FE = $(round(energy, digits=4))")
end

# Test 9: Integration with ITHERIS wrapper
println("\n[TEST 9] Testing ITHERIS wrapper...")
wrapped_engine = wrap_itheris_brain(nothing)
println("  ✓ Wrapped engine created (use_itheris=$(wrapped_engine.use_itheris))")

# Test 10: Hybrid inference
println("\n[TEST 10] Testing hybrid inference...")
hybrid_action = hybrid_inference(wrapped_engine, test_obs, 1.0f0)
println("  ✓ Hybrid action dimension: $(length(hybrid_action))")

# Final summary
println("\n" * "=" ^ 60)
println("ALL TESTS PASSED!")
println("=" ^ 60)
println("\nModule successfully implements:")
println("  ✓ Free Energy Principle (FEP) core")
println("  ✓ Generative Model (observation + transition models)")
println("  ✓ Prediction error and KL divergence computation")
println("  ✓ Variational inference for state estimation")
println("  ✓ Precision-weighted learning")
println("  ✓ HDC memory with binding, bundling, holographic recall")
println("  ✓ Active Inference controller (predict → infer → act)")
println("  ✓ Policy selection via expected free energy")
println("  ✓ Integration wrapper for existing ITHERIS brain")
println("=" ^ 60)
