#!/usr/bin/env julia
# harness/run.jl - Main event loop orchestrator

using JSON
using Dates
using Statistics

include("../kernel/Kernel.jl")
include("../persistence/Persistence.jl")

using .Kernel
using .Persistence

# Global registry (no UNSAFE_MODE - kernel sovereignty cannot be bypassed)

"""
    load_registry(registry_file::String)
Load capability metadata from JSON registry.
"""
function load_registry(registry_file::String)
    if !isfile(registry_file)
        @warn "Registry file not found: $registry_file"
        return
    end
    
    registry_data = JSON.parsefile(registry_file)
    for cap in registry_data
        CAPABILITY_REGISTRY[cap["id"]] = cap
    end
    @info "Loaded $(length(CAPABILITY_REGISTRY)) capabilities"
end

"""
    default_permission_handler(risk::String)::Bool
Default permission handler: allow "low" risk, deny "high" and "medium".
Can be overridden with --unsafe flag.
"""
function default_permission_handler(risk::String)::Bool
    # Security: Never bypass sovereignty - always use proper risk assessment
    # This function provides a default implementation but the Kernel
    # performs its own risk assessment independently
    
    return risk == "low"  # Only allow low-risk by default
end

"""
    execute_capability(cap_id::String, params::Dict{String,Any}=Dict())::Dict{String,Any}
Execute a capability by loading and invoking it.
"""
function execute_capability(cap_id::String, params::Dict{String, Any}=Dict())::Dict{String, Any}
    cap_meta = get(CAPABILITY_REGISTRY, cap_id, nothing)
    
    if cap_meta === nothing
        return Dict(
            "success" => false,
            "effect" => "Capability not found: $cap_id",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0
        )
    end
    
    # Load capability module dynamically
    cap_file = "capabilities/$cap_id.jl"
    
    try
        if !isfile(cap_file)
            return Dict(
                "success" => false,
                "effect" => "Capability file not found: $cap_file",
                "actual_confidence" => 0.0,
                "energy_cost" => 0.0
            )
        end
        
        # Include and execute
        include(cap_file)
        
        # Get the module name (capitalized and cleaned)
        module_name = titlecase(replace(cap_id, "_" => " ")) |> s -> replace(s, " " => "")
        
        # Dynamically retrieve and call the module
        mod = getfield(Main, Symbol(module_name))
        return mod.execute(params)
        
    catch e
        return Dict(
            "success" => false,
            "effect" => "Execution error: $(string(e))",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0
        )
    end
end

"""
    make_capability_candidates()::Vector{Dict{String,Any}}
Return list of available capabilities (metadata only).
"""
function make_capability_candidates()::Vector{Dict{String, Any}}
    return collect(values(CAPABILITY_REGISTRY))
end

"""
    run_harness(cycles::Int=20; unsafe::Bool=false, registry_path::String="registry/capability_registry.json")
Main entry point: initialize kernel, load capabilities, run event loop.
"""
function run_harness(cycles::Int=20; registry_path::String="registry/capability_registry.json")
    # SECURITY: No unsafe parameter - kernel sovereignty cannot be bypassed
    # All actions must go through proper Kernel approval
    
    @info "=== Adaptive Kernel Harness ===" cycles
    
    # Initialize persistence
    init_persistence()
    
    # Load registry
    load_registry(registry_path)
    
    # Initialize kernel
    kernel_config = Dict(
        "goals" => [
            Dict("id" => "nominal_operation", "description" => "Maintain system nominal operation", "priority" => 0.9),
            Dict("id" => "observe", "description" => "Continuous observation of system state", "priority" => 0.8)
        ],
        "observations" => Dict(
            "cpu_load" => 0.5,
            "memory_usage" => 4096,
            "disk_io" => 100
        )
    )
    
    kernel = init_kernel(kernel_config)
    
    @info "Kernel initialized" cycle=kernel.cycle[]
    
    # Event loop
    for i in 1:cycles
        candidates = make_capability_candidates()
        
        # Wrapper for execute_capability
        exec_wrapper = (cap_id) -> execute_capability(cap_id)
        
        # Step once
        kernel, action, result = Kernel.step_once(
            kernel,
            candidates,
            exec_wrapper,
            default_permission_handler
        )
        
        # Log event
        event = Dict(
            "timestamp" => string(now()),
            "cycle" => kernel.cycle[],
            "type" => "action_executed",
            "action_id" => action.capability_id,
            "success" => get(result, "success", false),
            "risk" => action.risk,
            "confidence" => action.confidence,
            "predicted_reward" => action.predicted_reward
        )
        save_event(event)
        
        # Periodic summary
        if i % 5 == 0 || i == cycles
            stats = Kernel.get_kernel_stats(kernel)
            @info "Cycle $i summary" stats
        end
    end
    
    # Flush final state
    final_stats = Kernel.get_kernel_stats(kernel)
    save_kernel_state(final_stats)
    
    @info "Event loop complete" cycles=kernel.cycle[] final_confidence=final_stats["confidence"] final_energy=final_stats["energy"]
    
    return kernel
end

# ============================================================================
# CLI Entry Point
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    # Parse command-line args
    cycles = 20
    unsafe = false
    registry_path = "registry/capability_registry.json"
    
    args = ARGS
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--cycles"
            i += 1
            cycles = parse(Int, args[i])
        elseif arg == "--unsafe"
            unsafe = true
        elseif arg == "--registry"
            i += 1
            registry_path = args[i]
        end
        i += 1
    end
    
    run_harness(cycles; registry_path=registry_path)
end
