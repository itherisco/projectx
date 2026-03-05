#!/usr/bin/env julia
# diagnose_ipc.jl - Diagnose IPC module issues

using Pkg

# Check if JSON package is available
println("=== Checking Julia Packages ===")
try
    using JSON
    println("✓ JSON package available")
    println("  JSON.json = $(typeof(JSON.json))")
catch e
    println("✗ JSON package NOT available: $e")
end

# Check SHA package
try
    using SHA
    println("✓ SHA package available")
catch e
    println("✗ SHA package NOT available: $e")
end

# Include the RustIPC module directly
println("\n=== Loading RustIPC Module ===")
try
    include("adaptive-kernel/kernel/ipc/RustIPC.jl")
    println("✓ RustIPC module included")
    
    # Now import it
    using .RustIPC
    println("✓ RustIPC module loaded successfully")
    
    println("✓ RustIPC module loaded")
    println("\n=== Checking Exported Functions ===")
    
    # Check if sign_message exists and what methods are available
    println("\nChecking sign_message...")
    if isdefined(RustIPC, :sign_message)
        println("  ✓ sign_message is defined")
        println("  Methods: $(methods(RustIPC.sign_message))")
    else
        println("  ✗ sign_message is NOT defined")
    end
    
    # Check for the 4-argument version specifically
    println("\nChecking for 4-argument sign_message...")
    try
        result = RustIPC.sign_message(UInt8[], UInt8[], UInt64(0), UInt64(0))
        println("  ✓ 4-argument sign_message works: $(typeof(result))")
    catch e
        println("  ✗ 4-argument sign_message fails: $e")
    end
    
    # Check verify_signature
    println("\nChecking verify_signature...")
    if isdefined(RustIPC, :verify_signature)
        println("  ✓ verify_signature is defined")
    else
        println("  ✗ verify_signature is NOT defined")
    end
    
    # Check key management
    println("\nChecking key management...")
    if isdefined(RustIPC, :init_secret_key)
        println("  ✓ init_secret_key is defined")
    else
        println("  ✗ init_secret_key is NOT defined")
    end
    
    if isdefined(RustIPC, :is_key_initialized)
        println("  ✓ is_key_initialized is defined")
    else
        println("  ✗ is_key_initialized is NOT defined")
    end
    
    # Check JSON-related functions
    println("\nChecking serialize functions...")
    if isdefined(RustIPC, :serialize_thought)
        println("  ✓ serialize_thought is defined")
    else
        println("  ✗ serialize_thought is NOT defined")
    end
    
    # Check if shared memory is available
    println("\n=== Checking Shared Memory ===")
    shm_path = "/dev/shm/itheris_ipc"
    if ispath(shm_path)
        println("  ✓ Shared memory path exists: $shm_path")
        try
            stat_info = stat(shm_path)
            println("    Size: $(stat_info.size) bytes")
        catch e
            println("    Error getting stat: $e")
        end
    else
        println("  ✗ Shared memory path NOT found: $shm_path")
        println("    (This is expected if Rust kernel is not running)")
    end
    
catch e
    println("✗ Failed to load RustIPC module: $e")
    println("\nFull stack trace:")
    for (exc, bt) in Base.catch_stack()
        showerror(stdout, exc, bt)
        println()
    end
end

println("\n=== Diagnosis Complete ===")
