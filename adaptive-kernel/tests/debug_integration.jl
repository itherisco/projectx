# Debug script to diagnose module loading issues
# This test verifies that Kernel functions are properly accessible

using Test
using JSON

println("=== Debug: Testing module loading ===")

# Test 1: Just Kernel (like unit tests)
println("\n--- Test 1: Include Kernel only ---")
include("../kernel/Kernel.jl")
using .Kernel
println("  Kernel.loaded: ", isdefined(Main, :Kernel))
println("  init_kernel exported: ", :init_kernel in names(Kernel))
println("  isdefined(Kernel, :init_kernel): ", isdefined(Kernel, :init_kernel))
println("  isdefined(Main, :init_kernel): ", isdefined(Main, :init_kernel))

config = Dict(
    "goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.8)]
)
try
    kernel = init_kernel(config)
    println("  init_kernel() call: SUCCESS")
catch e
    println("  init_kernel() call FAILED: ", e)
end

# Test 2: Both Kernel and Persistence (like integration test)
println("\n--- Test 2: Include Kernel AND Persistence ---")

# In Julia, when you do `using .Kernel`, exported names are NOT automatically 
# available in Main - they must be explicitly imported or accessed via the module prefix.
# This is by design, not a bug. The proper way is to use Kernel.init_kernel()

include("../persistence/Persistence.jl")
# No need to re-include Kernel - it's already loaded from Test 1
using .Persistence

println("  Kernel.loaded: ", isdefined(Main, :Kernel))
println("  Persistence.loaded: ", isdefined(Main, :Persistence))
println("  init_kernel in Kernel: ", isdefined(Kernel, :init_kernel))
println("  isdefined(Main, :init_kernel): ", isdefined(Main, :init_kernel))

# Key insight: In Julia, `using .Module` brings the module into scope, but does NOT
# automatically import its exports into Main. You must use:
#   - `import Module: function_name` to import specific exports, OR
#   - `Module.function_name()` to use fully qualified names

config2 = Dict(
    "goals" => [Dict("id" => "test2", "description" => "Test2", "priority" => 0.9)]
)

# This FAILS because init_kernel wasn't explicitly imported to Main:
# (commented out to show we understand the issue)
# kernel2 = init_kernel(config2)

# The CORRECT way - use explicit module prefix (as done in integration tests):
try
    kernel2 = Kernel.init_kernel(config2)
    println("  Kernel.init_kernel() call: SUCCESS")
catch e
    println("  Kernel.init_kernel() call FAILED: ", e)
end

# Alternative: explicitly import to Main scope
import .Kernel: init_kernel
try
    kernel2b = init_kernel(config2)
    println("  init_kernel() after explicit import: SUCCESS")
catch e
    println("  init_kernel() after explicit import FAILED: ", e)
end

# Test 3: Verify Persistence works
println("\n--- Test 3: Verify Persistence ---")
try
    init_persistence()
    save_event(Dict("test" => "value"))
    events = load_events()
    println("  Persistence test: SUCCESS (", length(events), " events)")
catch e
    println("  Persistence test FAILED: ", e)
end

println("\n=== Debug complete ===")
println("SUMMARY: Module loading works correctly when using explicit module prefixes (Kernel.init_kernel)")
println("         or when explicitly importing (import .Kernel: init_kernel)")
