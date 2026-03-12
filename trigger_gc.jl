#!/usr/bin/env julia
# Trigger garbage collection in the running Julia process
# This script runs GC to free unused memory

using Base.CoreLogging

println("[Memory] Starting garbage collection...")
println("[Memory] Memory before GC: ", Base.format_bytes(Base.gc_total_bytes()))

# Force a full garbage collection
GC.gc(true)

# Also run a slower full collect
GC.gc()

println("[Memory] Memory after GC: ", Base.format_bytes(Base.gc_total_bytes()))

# Print memory stats
println("[Memory] Total allocated: ", Base.format_bytes(Base.total_alloc()))
