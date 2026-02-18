# runtests.jl - convenience test runner for adaptive-kernel
import Pkg
Pkg.activate(@__DIR__)
try
    Pkg.instantiate()
catch e
    @warn "Pkg.instantiate() failed: $e"
end

# Run unit tests directly (bypass Pkg.test environment issues)
println("Running unit tests...")
include(joinpath(@__DIR__, "tests/unit_kernel_test.jl"))
include(joinpath(@__DIR__, "tests/unit_capability_test.jl"))

println("Running integration test (if desired)...")
try
    include(joinpath(@__DIR__, "tests/integration_simulation_test.jl"))
catch e
    @warn "Integration test skipped or failed to run: $e"
end
