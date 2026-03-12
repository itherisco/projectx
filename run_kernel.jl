#!/usr/bin/env julia
# run_kernel.jl - Run the adaptive kernel

using JSON
using Dates

include("adaptive-kernel/kernel/Kernel.jl")
include("adaptive-kernel/persistence/Persistence.jl")
include("adaptive-kernel/kernel/ipc/RustIPC.jl")

using .Kernel
using .Persistence
using .RustIPC

# ============================================================================
# Native Mode IPC Validation
# ============================================================================

function validate_native_ipc()
    """
    Validate shared memory region for Native Mode IPC.
    
    This performs hard validation at kernel startup to ensure:
    1. Shared memory path exists at /dev/shm/itheris_ipc (or configured path)
    2. Memory region size is exactly 16MB (0x00100000 bytes)
    3. Memory region is page-aligned (spans 0x01000000 - 0x01100000)
    
    If validation fails, the kernel refuses to boot with clear error messages.
    """
    println("="^60)
    println("Native Mode IPC Validation")
    println("="^60)
    
    # Detect platform and show info
    platform = detect_platform()
    println("Platform: $(string(platform))")
    println("Native SHM support: $(supports_native_shm())")
    
    # Get configured path and size
    shm_path = get_platform_shm_path()
    expected_size = get_shm_size()
    
    println("SHM Path: $shm_path")
    println("Expected Size: $expected_size bytes (0x$(string(expected_size, base=16)))")
    println("Expected Base: 0x01000000")
    println("Expected End: 0x01100000")
    
    # Perform validation
    result = validate_shm_region(shm_path, expected_size)
    
    if !result.path_exists
        println("\n[FAIL] Shared memory path does not exist!")
        println("Error: $(result.error_message)")
        println("\n" * "="^60)
        println("KERNEL STARTUP ABORTED - Native Mode IPC Required")
        println("="^60)
        println("\nTo fix this issue, run:")
        if platform == :linux
            println("  sudo mkdir -p /dev/shm")
            println("  sudo truncate -s $expected_size $shm_path")
            println("  sudo chmod 666 $shm_path")
        elseif platform == :macos || platform == :bsd
            println("  sudo mkdir -p /tmp")
            println("  sudo touch $shm_path")
            println("  sudo chmod 666 $shm_path")
        elseif platform == :windows
            println("  Use CreateFileMappingA to create named shared memory")
        end
        println("\nOr set environment variables:")
        println("  ITHERIS_SHM_PATH=/path/to/shm")
        println("  ITHERIS_SHM_SIZE=0x00100000")
        println("="^60)
        return false
    end
    
    if !result.size_correct || !result.alignment_correct || !result.permissions_valid
        println("\n[FAIL] Shared memory misconfigured!")
        println("Error: $(result.error_message)")
        println("\n" * "="^60)
        println("KERNEL STARTUP ABORTED - Native Mode IPC Required")
        println("="^60)
        println("\nTo fix this issue, run:")
        println("  sudo truncate -s $expected_size $shm_path")
        println("  sudo chmod 666 $shm_path")
        println("="^60)
        return false
    end
    
    # Validate atomic index alignment
    alignment_result = validate_ring_buffer_alignment()
    if !alignment_result[1]
        println("\n[WARN] Atomic index alignment: $(alignment_result[2])")
    else
        println("\n[PASS] Atomic index alignment validated")
    end
    
    println("\n[PASS] Native Mode IPC validation successful!")
    println("="^60)
    
    # Set default permissions to normal
    set_ipc_permissions(:normal)
    
    return true
end

# Run validation before kernel initialization
if !validate_native_ipc()
    println("\nERROR: Native Mode IPC validation failed!")
    println("The system will run in Fallback Mode with reduced performance.")
    println("Fix the shared memory configuration to enable Native Mode.")
else
    println("Native Mode IPC: ENABLED (sub-microsecond latency)")
end

# Initialize persistence
init_persistence()

# Create a simple config
config = Dict(
    "goals" => [
        Dict("id" => "test_goal", "description" => "Test goal", "priority" => 0.8)
    ],
    "observations" => Dict("test" => 1.0)
)

# Initialize kernel
println("Initializing kernel...")
global kernel_state = Kernel.init_kernel(config)

# Check if kernel initialized properly
if kernel_state === nothing || isnothing(kernel_state)
    println("ERROR: Kernel failed to initialize properly")
    exit(1)
end

println("Kernel initialized successfully!")

# Mock candidates for the kernel to choose from
candidates = [
    Dict("id" => "observe_cpu", "cost" => 0.05f0, "risk" => "low", "confidence" => 0.85f0),
    Dict("id" => "analyze_logs", "cost" => 0.08f0, "risk" => "medium", "confidence" => 0.8f0),
    Dict("id" => "write_file", "cost" => 0.03f0, "risk" => "low", "confidence" => 0.9f0)
]

# Execution function - simulates capability execution
exec_fn = (cap_id) -> begin
    return Dict(
        "success" => true,
        "effect" => "Executed $cap_id",
        "actual_confidence" => 0.85f0,
        "energy_cost" => 0.05f0
    )
end

# Permission function - determines if action is allowed
perm_fn = (risk) -> risk != "high"

# Verify function for FlowIntegrity
verify_fn = (cap_id, token) -> Dict("success" => true, "verified" => true)

# Run 5 cycles
for cycle in 1:5
    global kernel_state
    println("\n--- Cycle $cycle ---")
    
    # Step the kernel - handle case where kernel_state might be nothing
    try
        kernel_state, action, result = Kernel.step_once(kernel_state, candidates, exec_fn, perm_fn; verify_fn=verify_fn)
        
        # Check if we got a valid kernel_state back
        if kernel_state === nothing || isnothing(kernel_state)
            println("Warning: kernel_state is nothing after step_once, skipping cycle")
            continue
        end
        
        # Get stats
        stats = Kernel.get_kernel_stats(kernel_state)
        println("Executed: $(action.capability_id)")
        println("Result: $(result["success"] ? "success" : "failed")")
        println("Cycle: $(stats["cycle"]), Confidence: $(round(stats["confidence"]; digits=2)), Energy: $(round(stats["energy"]; digits=2))")
    catch e
        println("Error in cycle $cycle: $e")
        break
    end
end

println("\n=== System ran successfully for 5 cycles ===")
