# tests/test_flow_integrity.jl - Integration tests for Flow Integrity Pattern
# Tests the cryptographic sovereignty system that prevents prompt injection
# from bypassing Kernel.approve() through function redefinition.

using Test
using Dates
using JSON

include("../kernel/Kernel.jl")
using .Kernel
using .Kernel.FlowIntegrity

const TEST_SECRET = Vector{UInt8}("test-flow-integrity-secret-key")

@testset "Flow Integrity Pattern Tests" begin
    
    @testset "Token Generation" begin
        gate = FlowIntegrityGate(secret_key=TEST_SECRET)
        capability_id = "safe_execute"
        params = Dict("command" => "echo test", "timeout" => 30)
        cycle_number = 1
        
        token = issue_flow_token(gate, capability_id, params, cycle_number)
        
        @test token !== nothing
        @test token.capability_id == capability_id
        @test token.cycle_number == cycle_number
        @test length(token.token_id) == 32
        @test length(token.hmac) == 32
        
        # Test serialization
        serialized = serialize_token(token)
        @test haskey(serialized, "token_id")
        @test haskey(serialized, "hmac")
    end
    
    @testset "Token Verification - Valid" begin
        gate = FlowIntegrityGate(secret_key=TEST_SECRET)
        capability_id = "safe_shell"
        params = Dict("command" => "ls -la")
        cycle_number = 42
        
        token = issue_flow_token(gate, capability_id, params, cycle_number)
        serialized = serialize_token(token)
        
        is_valid, reason = verify_flow_token_from_dict(gate, serialized, capability_id, params)
        
        @test is_valid == true
        @test reason == "TOKEN_VALID"
    end
    
    @testset "Token Verification - Tampered HMAC" begin
        gate = FlowIntegrityGate(secret_key=TEST_SECRET)
        capability_id = "write_file"
        params = Dict("path" => "/tmp/test.txt", "content" => "test")
        
        token = issue_flow_token(gate, capability_id, params, 1)
        serialized = serialize_token(token)
        
        # Tamper with the HMAC
        serialized["hmac"] = "0000000000000000000000000000000000000000000000000000000000000000"
        
        is_valid, reason = verify_flow_token_from_dict(gate, serialized, capability_id, params)
        
        @test is_valid == false
        @test reason == "INVALID_HMAC"
    end
    
    @testset "Token Verification - Capability Mismatch (Anti-Redirect)" begin
        gate = FlowIntegrityGate(secret_key=TEST_SECRET)
        capability_id = "safe_read"
        params = Dict("file" => "/etc/passwd")
        
        token = issue_flow_token(gate, capability_id, params, 1)
        serialized = serialize_token(token)
        
        # Try to use token for different capability
        wrong_capability = "safe_shell"
        is_valid, reason = verify_flow_token_from_dict(gate, serialized, wrong_capability, params)
        
        @test is_valid == false
        @test reason == "CAPABILITY_MISMATCH"
    end
    
    @testset "Token Single-Use Enforcement" begin
        gate = FlowIntegrityGate(secret_key=TEST_SECRET)
        capability_id = "observe_cpu"
        params = Dict()
        
        token = issue_flow_token(gate, capability_id, params, 1)
        serialized = serialize_token(token)
        
        # First use should succeed
        is_valid_1, reason_1 = verify_flow_token_from_dict(gate, serialized, capability_id, params)
        @test is_valid_1 == true
        
        # Second use should fail
        is_valid_2, reason_2 = verify_flow_token_from_dict(gate, serialized, capability_id, params)
        @test is_valid_2 == false
        @test reason_2 == "TOKEN_ALREADY_USED"
    end
    
    @testset "Secret Environment Variable" begin
        ENV["JARVIS_FLOW_INTEGRITY_SECRET"] = "env-test-secret-key"
        
        try
            gate = FlowIntegrityGate()
            token = issue_flow_token(gate, "test", Dict(), 1)
            serialized = serialize_token(token)
            
            is_valid, _ = verify_flow_token_from_dict(gate, serialized, "test", Dict())
            @test is_valid == true
        finally
            delete!(ENV, "JARVIS_FLOW_INTEGRITY_SECRET")
        end
    end
    
    @testset "flow_secret_is_set()" begin
        # Initially false
        initial = flow_secret_is_set()
        
        ENV["JARVIS_FLOW_INTEGRITY_SECRET"] = "test-secret"
        try
            @test flow_secret_is_set() == true
        finally
            delete!(ENV, "JARVIS_FLOW_INTEGRITY_SECRET")
        end
    end
    
end

println("All Flow Integrity tests completed!")
