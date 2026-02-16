# tests/unit_capability_test.jl - Test capability interface

using Test

@testset "Capability Interface Tests" begin
    
    @testset "observe_cpu capability" begin
        include("../capabilities/observe_cpu.jl")
        using .ObserveCPU
        
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
    
    @testset "analyze_logs capability" begin
        include("../capabilities/analyze_logs.jl")
        using .AnalyzeLogs
        
        meta = AnalyzeLogs.meta()
        @test meta["id"] == "analyze_logs"
        @test meta["risk"] == "low"
        
        result = AnalyzeLogs.execute(Dict("file_path" => "events.log"))
        @test haskey(result, "success")
        @test haskey(result, "effect")
        @test haskey(result["data"], "lines")
    end
    
    @testset "write_file capability" begin
        include("../capabilities/write_file.jl")
        using .WriteFile
        
        meta = WriteFile.meta()
        @test meta["id"] == "write_file"
        @test meta["risk"] == "medium"
        @test meta["reversible"] == false
        
        result = WriteFile.execute(Dict("content" => "Test content"))
        @test result["success"] == true
        @test haskey(result["data"], "file_path")
        @test occursin("sandbox", result["data"]["file_path"])
    end
    
    @testset "safe_shell capability whitelist" begin
        include("../capabilities/safe_shell.jl")
        using .SafeShell
        
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
