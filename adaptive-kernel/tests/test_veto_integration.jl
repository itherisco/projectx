# tests/test_veto_integration.jl - Simple test for Memory Veto Integration
# Tests only DecisionSpine veto hooks without Kernel dependencies

using Test
using Dates
using UUIDs

# Import shared types
push!(LOAD_PATH, joinpath(pwd(), ".."))

# Test shared types
include("../types.jl")
using ..SharedTypes

# Test cognition types
include("../cognition/types.jl")
using ..CognitionTypes

# Test DecisionSpine (without Kernel dependency)
include("../cognition/spine/DecisionSpine.jl")
using ..DecisionSpine

# ============================================================================
# VETO INTEGRATION TESTS
# ============================================================================

println("\n" * "="^60)
println("Memory Veto Integration Tests")
println("="^60 * "\n")

@testset "DecisionSpine Memory Veto Integration" begin
    
    @testset "check_memory_vetoes - doctrine veto applied" begin
        # Create doctrine memory with invariant
        doctrine = DoctrineMemory()
        push!(doctrine.invariants, "no_delete")
        
        # Create proposals
        proposals = [
            AgentProposal("executor_001", :executor, "delete_file", 0.8; weight=1.0),
            AgentProposal("strategist_001", :strategist, "read_file", 0.7; weight=1.0)
        ]
        
        # Apply veto check
        result = check_memory_vetoes(proposals, doctrine, nothing, Dict())
        
        @test length(result) == 2
        # First proposal should be vetoed
        @test result[1].vetoed == true
        @test result[1].confidence == 0.0
        @test result[1].weight == 0.0
        @test occursin("DOCTRINE", result[1].veto_reason)
        # Second proposal should pass
        @test result[2].vetoed == false
        @test result[2].confidence == 0.7
        
        println("✓ Doctrine veto applied correctly")
    end
    
    @testset "check_memory_vetoes - tactical veto applied" begin
        # Create tactical memory with failure pattern
        tactical = TacticalMemory(100)
        for i in 1:5
            record_outcome!(tactical, Dict("decision" => "execute_api", "result" => false))
        end
        
        # Create proposal that matches failure pattern
        proposals = [
            AgentProposal("executor_001", :executor, "execute_api", 0.8; weight=1.0)
        ]
        
        # Apply veto check
        result = check_memory_vetoes(proposals, nothing, tactical, Dict())
        
        @test length(result) == 1
        @test result[1].vetoed == true
        @test result[1].confidence == 0.0
        @test occursin("TACTICAL", result[1].veto_reason)
        
        println("✓ Tactical veto applied correctly")
    end
    
    @testset "check_memory_vetoes - no memory provided" begin
        proposals = [
            AgentProposal("executor_001", :executor, "any_action", 0.8; weight=1.0)
        ]
        
        # Should pass through unchanged when no memory provided
        result = check_memory_vetoes(proposals, nothing, nothing, Dict())
        
        @test length(result) == 1
        @test result[1].vetoed == false
        @test result[1].confidence == 0.8
        
        println("✓ No memory - passes through correctly")
    end
    
    @testset "check_memory_vetoes - both vetos, doctrine first" begin
        # Create both memories
        doctrine = DoctrineMemory()
        push!(doctrine.invariants, "no_delete")
        
        tactical = TacticalMemory(100)
        for i in 1:5
            record_outcome!(tactical, Dict("decision" => "execute_api", "result" => false))
        end
        
        # Proposal that would match both
        proposals = [
            AgentProposal("executor_001", :executor, "delete_file", 0.8; weight=1.0)
        ]
        
        result = check_memory_vetoes(proposals, doctrine, tactical, Dict())
        
        # Should get doctrine veto (checked first)
        @test result[1].vetoed == true
        @test occursin("DOCTRINE", result[1].veto_reason)
        
        println("✓ Doctrine veto takes precedence")
    end
    
    @testset "get_vetoed_proposals helper" begin
        proposals = [
            AgentProposal("a1", :executor, "action1", 0.8; vetoed=true, veto_reason="test"),
            AgentProposal("a2", :strategist, "action2", 0.7),
            AgentProposal("a3", :auditor, "action3", 0.6; vetoed=true, veto_reason="test2")
        ]
        
        vetoed = get_vetoed_proposals(proposals)
        
        @test length(vetoed) == 2
        @test vetoed[1].agent_id == "a1"
        @test vetoed[2].agent_id == "a3"
        
        println("✓ get_vetoed_proposals works")
    end
    
    @testset "has_vetoed_proposals helper" begin
        proposals_no_veto = [
            AgentProposal("a1", :executor, "action1", 0.8)
        ]
        
        proposals_with_veto = [
            AgentProposal("a1", :executor, "action1", 0.8; vetoed=true, veto_reason="test"),
            AgentProposal("a2", :strategist, "action2", 0.7)
        ]
        
        @test has_vetoed_proposals(proposals_no_veto) == false
        @test has_vetoed_proposals(proposals_with_veto) == true
        
        println("✓ has_vetoed_proposals works")
    end
    
    @testset "AgentProposal with veto fields" begin
        proposal = AgentProposal(
            "test_agent",
            :executor,
            "test_decision",
            0.9;
            reasoning = "Test reasoning",
            weight = 1.0,
            vetoed = true,
            veto_reason = "Test veto reason"
        )
        
        @test proposal.agent_id == "test_agent"
        @test proposal.decision == "test_decision"
        @test proposal.confidence == 0.9
        @test proposal.vetoed == true
        @test proposal.veto_reason == "Test veto reason"
        
        println("✓ AgentProposal with veto fields works")
    end
    
    @testset "Safe action passes both vetos" begin
        doctrine = DoctrineMemory()
        push!(doctrine.invariants, "no_delete")
        
        tactical = TacticalMemory(100)
        for i in 1:5
            record_outcome!(tactical, Dict("decision" => "execute_api", "result" => false))
        end
        
        # Safe action
        proposals = [
            AgentProposal("executor_001", :executor, "read_file_safe", 0.8; weight=1.0)
        ]
        
        result = check_memory_vetoes(proposals, doctrine, tactical, Dict())
        
        @test result[1].vetoed == false
        @test result[1].confidence == 0.8
        
        println("✓ Safe action passes both vetos")
    end
end

println("\n" * "="^60)
println("✓ All Memory Veto Integration Tests Passed!")
println("="^60 * "\n")
