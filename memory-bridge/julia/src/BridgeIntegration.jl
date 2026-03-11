# ============================================================================
# BridgeIntegration.jl - Integration of MemoryBridge with ActiveInference
# Phase 3 of ITHERIS Ω - Bridges Rust Wasmtime with Julia Active Inference
# ============================================================================

module BridgeIntegration

using Dates
using LinearAlgebra
using Random
using UUIDs

# Import from MemoryBridge
include("MemoryBridge.jl")
import .MemoryBridge

# Import from ActiveInference if available
const HAS_ACTIVEINFERENCE = try
    include(joinpath(dirname(@__DIR__), "..", "active-inference", "ActiveInference.jl"))
    true
catch
    false
end

if HAS_ACTIVEINFERENCE
    import .ActiveInference as AI
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    CognitiveBridge,
    create_cognitive_bridge,
    run_full_cognitive_loop,
    initialize_bridge

# ============================================================================
# Cognitive Bridge - Full Integration
# ============================================================================

"""
    CognitiveBridge - Full cognitive loop integrating Rust Sentry with Julia Active Inference
"""
mutable struct CognitiveBridge
    memory_bridge::MemoryBridge.MemoryBridgeClient
    hdc_memory::Dict{String, Vector{Float64}}
    generative_model::Union{Nothing, Any}
    free_energy_history::Vector{Float64}
    is_running::Bool
    
    function CognitiveBridge(; base_path::String="/tmp/itheris_shm")
        new(
            MemoryBridge.create_bridge(base_path=base_path),
            Dict{String, Vector{Float64}}(),
            nothing,
            Float64[],
            false
        )
    end
end

"""
    Create a cognitive bridge
"""
function create_cognitive_bridge(; base_path::String="/tmp/itheris_shm")::CognitiveBridge
    CognitiveBridge(base_path=base_path)
end

"""
    Initialize the bridge with a generative model
"""
function initialize_bridge(bridge::CognitiveBridge; state_dim::Int=128, obs_dim::Int=64, action_dim::Int=32)
    # Initialize HDC memory with base concepts
    bridge.hdc_memory["default"] = randn(1000)
    bridge.hdc_memory["observation"] = randn(1000)
    bridge.hdc_memory["action"] = randn(1000)
    bridge.hdc_memory["prediction"] = randn(1000)
    
    # Initialize generative model if ActiveInference is available
    if HAS_ACTIVEINFERENCE
        try
            bridge.generative_model = AI.GenerativeModel(state_dim, obs_dim, action_dim)
            @info "Generative model initialized"
        catch e
            @warn "Failed to initialize generative model: $e"
        end
    end
    
    @info "Cognitive bridge initialized"
end

"""
    Update HDC memory with new concept
"""
function update_hdc_concept!(bridge::CognitiveBridge, concept::String, vector::Vector{Float64})
    bridge.hdc_memory[concept] = vector / norm(vector)
end

"""
    Retrieve concept from HDC memory
"""
function retrieve_hdc_concept(bridge::CognitiveBridge, query::Vector{Float64})::Tuple{String, Float64}
    best_sim = -Inf
    best_concept = "unknown"
    
    for (concept, vector) in bridge.hdc_memory
        sim = dot(query, vector)
        if sim > best_sim
            best_sim = sim
            best_concept = concept
        end
    end
    
    return (best_concept, best_sim)
end

"""
    Bind concepts in HDC space
"""
function hdc_bind(bridge::CognitiveBridge, a::String, b::String)::Vector{Float64}
    vec_a = get(bridge.hdc_memory, a, randn(1000))
    vec_b = get(bridge.hdc_memory, b, randn(1000))
    bound = vec_a .* vec_b
    return bound / norm(bound)
end

"""
    Process observation with Active Inference
"""
function process_with_active_inference(
    bridge::CognitiveBridge,
    obs::MemoryBridge.SensoryObservation
)::MemoryBridge.InferenceResponse
    response = MemoryBridge.InferenceResponse(observation_id=obs.id)
    
    values = obs.values
    
    if length(values) > 0
        # Use generative model if available
        if bridge.generative_model !== nothing && HAS_ACTIVEINFERENCE
            try
                # Convert to Float32 for ActiveInference
                values_f32 = Float32.(values)
                state = rand(Float32, 128)  # Random initial state
                
                # Generate prediction
                predicted = AI.observation(bridge.generative_model, state)
                
                # Compute free energy
                fe_state = AI.compute_free_energy(bridge.generative_model, state, values_f32)
                
                response.prediction_error = Float64(fe_state.prediction_error)
                response.free_energy = Float64(fe_state.total_free_energy)
                response.predicted_values = Float64.(predicted)
                
                # Select policy
                if response.prediction_error > 0.1
                    response.selected_policy = "explore"
                else
                    response.selected_policy = "exploit"
                end
            catch e
                @warn "Active inference failed: $e"
                # Fallback to simple processing
                response = simple_process(obs)
            end
        else
            # Simple fallback processing
            response = simple_process(obs)
        end
        
        # Update HDC memory with observation
        obs_vector = values / norm(values)
        update_hdc_concept!(bridge, "observation_$(obs.id)", obs_vector)
        
        # Bind observation with source
        source_key = string(obs.source)
        bound_key = "bound_$(source_key)_$(obs.id)"
        bound_vector = hdc_bind(bridge, source_key, "observation_$(obs.id)")
        update_hdc_concept!(bridge, bound_key, bound_vector)
        
        # Store HDC bindings in shared memory
        response.updated_hdc_bindings[bound_key] = bound_vector
    end
    
    # Record free energy history
    push!(bridge.free_energy_history, response.free_energy)
    
    return response
end

"""
    Simple fallback processing
"""
function simple_process(obs::MemoryBridge.SensoryResponse)::MemoryBridge.InferenceResponse
    response = MemoryBridge.InferenceResponse(observation_id=obs.id)
    
    values = obs.values
    if length(values) > 0
        # Simple prediction: next value = current value + small noise
        predicted = values .+ randn(length(values)) .* 0.1
        response.predicted_values = predicted
        
        # Compute prediction error
        response.prediction_error = sum((values .- predicted).^2) / length(values)
        
        # Simple free energy approximation
        response.free_energy = response.prediction_error
        
        # Policy selection based on error
        if response.prediction_error > 0.5
            response.selected_policy = "explore"
        else
            response.selected_policy = "exploit"
        end
    end
    
    return response
end

"""
    Run the full cognitive loop once
"""
function run_full_cognitive_loop(bridge::CognitiveBridge; timeout_ms::Int=5000)::Union{MemoryBridge.InferenceResponse, Nothing}
    # Wait for observation from Rust
    obs = MemoryBridge.wait_for_observation(bridge.memory_bridge, timeout_ms=timeout_ms)
    
    if obs === nothing
        @warn "Timeout waiting for observation"
        return nothing
    end
    
    @info "Received observation: $(obs.id) from $(obs.source)"
    @info "  Values: $(length(obs.values))"
    
    # Process with Active Inference
    response = process_with_active_inference(bridge, obs)
    
    # Write response back to shared memory
    success = MemoryBridge.write_inference_response(bridge.memory_bridge, response)
    
    if success
        @info "Response written to shared memory"
        @info "  Prediction error: $(round(response.prediction_error, digits=4))"
        @info "  Free energy: $(round(response.free_energy, digits=4))"
        @info "  Policy: $(response.selected_policy)"
    else
        @warn "Failed to write response"
    end
    
    return response
end

"""
    Run continuous cognitive loop
"""
function run_continuous(bridge::CognitiveBridge; duration_s::Float64=60.0)
    bridge.is_running = true
    start_time = time()
    cycle_count = 0
    
    @info "Starting continuous cognitive loop for $duration_s seconds..."
    
    while bridge.is_running && (time() - start_time) < duration_s
        cycle_count += 1
        
        result = run_full_cognitive_loop(bridge, timeout_ms=5000)
        
        if result !== nothing
            @info "Cycle $cycle_count complete"
        else
            @warn "Cycle $cycle_count timed out"
        end
        
        sleep(0.1)  # Small delay between cycles
    end
    
    @info "Continuous loop ended after $cycle_count cycles"
end

"""
    Stop the continuous loop
"""
function stop_continuous(bridge::CognitiveBridge)
    bridge.is_running = false
end

# ============================================================================
# Demo
# ============================================================================

"""
    Run a demo of the cognitive bridge
"""
function demo(; iterations::Int=5)
    println("=== Cognitive Bridge Demo ===")
    
    # Create and initialize bridge
    bridge = create_cognitive_bridge()
    initialize_bridge(bridge)
    
    println("Bridge initialized")
    println("Running $iterations demo cycles...\n")
    
    # Simulate observations and process
    for i in 1:iterations
        # Create mock observation
        obs = MemoryBridge.SensoryObservation(
            source=:sentry,
            data_type=:float32,
            values=rand(10) .* 100,
            metadata=Dict("demo" => "true", "iteration" => string(i))
        )
        
        println("Cycle $i:")
        println("  Observation: $(obs.values[1:3])...")
        
        # Process
        response = process_with_active_inference(bridge, obs)
        
        println("  Prediction error: $(round(response.prediction_error, digits=4))")
        println("  Free energy: $(round(response.free_energy, digits=4))")
        println("  Policy: $(response.selected_policy)")
        println("  HDC bindings: $(length(response.updated_hdc_bindings))")
        println()
    end
    
    println("Demo complete!")
    println("Free energy history: $(bridge.free_energy_history)")
end

end  # module
