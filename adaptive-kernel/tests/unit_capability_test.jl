# tests/unit_capability_test.jl - Test capability interface

using Test

@testset "Capability Interface Tests" begin
    
    @testset "observe_cpu capability" begin
        include("../capabilities/observe_cpu.jl")
        
        meta = ObserveCPU.meta()
        @test meta["id"] == "observe_cpu"
        @test meta["risk"] == "low"
        @test meta["reversible"] == true
        
        result = ObserveCPU.execute(Dict())
        @test result["success"] == true
        @test haskey(result, "effect")
        @test haskey(result, "actual_confidence")
        @test haskey(result, "energy_cost")
        @test haskey(result, "data")
        @test haskey(result["data"], "cpu_load")
    end
    
    @testset "safe_shell capability whitelist" begin
        include("../capabilities/safe_shell.jl")
        
        meta = SafeShell.meta()
        @test meta["id"] == "safe_shell"
        @test meta["risk"] == "high"
        
        # Test allowed command
        result = SafeShell.execute(Dict("command" => "echo hello"))
        @test result["success"] == true
        
        # Test disallowed command
        result = SafeShell.execute(Dict("command" => "rm -rf /"))
        @test result["success"] == false
        @test !isempty(result["effect"])
    end
    
end

println("✓ All capability tests passed!")
