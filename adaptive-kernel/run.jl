"""
# ITHERIS Adaptive Kernel - Main Entry Point (Simplified)

This file starts the ITHERIS daemon in minimal mode without loading
all cognition modules to avoid module conflicts.

Usage:
- julia run.jl                    # Run daemon only (minimal mode)
"""

# Core dependencies
using Pkg
using Dates

# Activate project environment
Pkg.activate(@__DIR__)

# Include only minimal required modules
include("types.jl")  # Must be first - defines SharedTypes

"""
Main entry point for the ITHERIS daemon (minimal mode).
"""
function main()
    println("=" ^ 60)
    println("🧠 ITHERIS Adaptive Kernel - Starting (Minimal Mode)")
    println("=" ^ 60)
    println("Timestamp: $(now())")
    println("Mode: MINIMAL (core only)")
    println("=" ^ 60)
    
    # Main daemon loop - keep running
    println("\n[Daemon] Entering main loop...")
    println("[Daemon] Press Ctrl+C to stop\n")
    
    try
        while true
            # Heartbeat every 30 seconds
            println("[Daemon] Heartbeat - running")
            sleep(30)
        end
    catch e
        if e isa InterruptException
            println("\n[Daemon] Shutting down...")
        else
            println("[Daemon] Error: $e")
        end
    end
    
    println("[Daemon] Shutdown complete")
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

export main
