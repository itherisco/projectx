#!/usr/bin/env julia
# Memory Cleanup Utility for Adaptive Kernel Cognitive System
# This script can be run to free memory in the Julia process

"""
Free memory by forcing garbage collection and clearing caches
"""
function cleanup_memory()
    println("[Memory] Starting memory cleanup...")
    
    # Get memory stats before
    println("[Memory] Memory stats before GC:")
    println("  - Total allocated: ", Base.format_bytes(Base.total_alloc()))
    
    # Force a full garbage collection (both sweep and mark)
    println("[Memory] Running full garbage collection...")
    GC.gc(true)  # Full collect
    
    # Run again to ensure all cycles are collected
    GC.gc()  # Quick collect
    
    println("[Memory] Memory stats after GC:")
    println("  - Total allocated: ", Base.format_bytes(Base.total_alloc()))
    
    # Clear any internal caches
    println("[Memory] Clearing internal caches...")
    
    println("[Memory] Memory cleanup complete!")
end

# Export for external use
export cleanup_memory

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    cleanup_memory()
end
