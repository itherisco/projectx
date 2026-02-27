# test_integration.jl - Integration tests for brain-kernel-jarvis communication
# Tests the Integration types and conversion functions

using Test
using Dates
using UUIDs
using Logging

# Suppress info logs during tests
Logging.disable_logging(Logging.Info)

# Import modules
include("../types.jl")
using .SharedTypes

# Import Integration conversions
include("../integration/Conversions.jl")
using .Integration

@testset "Integration Types Tests" begin
    println("\n=== Testing Integration Types ===")
    
    # Test IntegrationActionProposal creation
    proposal = IntegrationActionProposal(
        "observe_cpu",
        0.9f0,
        0.1f0,
        0.8f0,
        0.2f0;
        reasoning = "CPU usage monitoring",
        impact = 0.7f0
    )
    
    @test proposal isa IntegrationActionProposal
    @test proposal.capability_id == "observe_cpu"
    @test proposal.confidence == 0.9f0
    @test proposal.risk == 0.2f0
    @test proposal.id isa UUID
    @test proposal.timestamp isa DateTime
    
    println("  + IntegrationActionProposal created successfully")
    
    # Test IntegrationWorldState creation
    world_state = IntegrationWorldState(
        system_metrics = Dict{String, Float32}(
            "cpu_load" => 0.7f0,
            "memory_usage" => 0.5f0
        ),
        severity = 0.3f0,
        threat_count = 0,
        trust_level = 80,
        observations = Dict{String, Any}("test" => "value"),
        facts = Dict{String, String}("fact1" => "value1"),
        cycle = 1,
        last_action_id = "action_123"
    )
    
    @test world_state isa IntegrationWorldState
    @test world_state.system_metrics["cpu_load"] == 0.7f0
    @test world_state.trust_level == 80
    @test world_state.cycle == 1
    
    println("  + IntegrationWorldState created successfully")
end

@testset "SharedTypes to Integration Conversion Tests" begin
    println("\n=== Testing SharedTypes -> Integration Conversion ===")
    
    # Create a SharedTypes.ActionProposal (with risk as String)
    shared_proposal = SharedTypes.ActionProposal(
        "safe_shell",
        0.7f0,
        0.2f0,
        0.6f0,
        "low",  # Risk as String!
        "Shell command looks safe"
    )
    
    # Convert to Integration format
    integration_proposal = Integration.convert_shared_proposal_to_integration(shared_proposal)
    
    @test integration_proposal isa IntegrationActionProposal
    @test integration_proposal.capability_id == "safe_shell"
    @test integration_proposal.risk == 0.1f0  # "low" -> 0.1 (below 0.2 threshold)
    
    # Test with "high" risk
    shared_proposal_high = SharedTypes.ActionProposal(
        "dangerous_action",
        0.5f0,
        0.8f0,
        0.9f0,
        "high",
        "Risky action"
    )
    
    integration_high = Integration.convert_shared_proposal_to_integration(shared_proposal_high)
    @test integration_high.risk == 0.8f0  # "high" -> 0.8
    
    # Test with "medium" risk
    shared_proposal_med = SharedTypes.ActionProposal(
        "medium_action",
        0.6f0,
        0.4f0,
        0.5f0,
        "medium",
        "Moderate risk"
    )
    
    integration_med = Integration.convert_shared_proposal_to_integration(shared_proposal_med)
    @test integration_med.risk == 0.35f0  # "medium" -> 0.35 (consistent with thresholds)
    
    println("  + SharedTypes -> Integration conversion works correctly")
end

@testset "Integration to SharedTypes Conversion Tests" begin
    println("\n=== Testing Integration -> SharedTypes Conversion ===")
    
    # Create IntegrationActionProposal
    integration_proposal = IntegrationActionProposal(
        "test_action",
        0.8f0,
        0.15f0,
        0.7f0,
        0.25f0;
        reasoning = "Test reasoning"
    )
    
    # Convert back to SharedTypes
    shared_proposal = Integration.convert_from_integration(integration_proposal)
    
    @test shared_proposal isa SharedTypes.ActionProposal
    @test shared_proposal.capability_id == "test_action"
    @test shared_proposal.confidence == 0.8f0
    @test shared_proposal.risk == "medium"  # 0.25 -> "medium" (0.2 <= 0.25 < 0.5)
    
    # Test with high risk
    integration_high_risk = IntegrationActionProposal(
        "high_risk_action",
        0.9f0,
        0.9f0,
        1.0f0,
        0.85f0
    )
    
    shared_high = Integration.convert_from_integration(integration_high_risk)
    @test shared_high.risk == "high"  # 0.85 -> "high"
    
    # Test with medium risk (0.35 to stay under high threshold)
    integration_med_risk = IntegrationActionProposal(
        "med_risk_action",
        0.7f0,
        0.35f0,
        0.6f0,
        0.35f0
    )
    
    shared_med = Integration.convert_from_integration(integration_med_risk)
    @test shared_med.risk == "medium"  # 0.35 -> "medium" (0.2 <= 0.35 < 0.5)
    
    println("  + Integration -> SharedTypes conversion works correctly")
end

@testset "Risk String Parsing Tests" begin
    println("\n=== Testing Risk String Parsing ===")
    
    # Test various risk string formats
    @test Integration.parse_risk_string("high") == 0.8f0
    @test Integration.parse_risk_string("HIGH") == 0.8f0
    @test Integration.parse_risk_string("h") == 0.8f0
    
    @test Integration.parse_risk_string("medium") == 0.35f0
    @test Integration.parse_risk_string("MEDIUM") == 0.35f0
    @test Integration.parse_risk_string("m") == 0.35f0
    
    @test Integration.parse_risk_string("low") == 0.1f0
    @test Integration.parse_risk_string("LOW") == 0.1f0
    @test Integration.parse_risk_string("l") == 0.1f0
    
    # Test numeric strings
    @test Integration.parse_risk_string("0.75") == 0.75f0
    @test Integration.parse_risk_string("0.3") == 0.3f0
    
    # Test unknown values (should default)
    @test Integration.parse_risk_string("unknown") == 0.3f0
    
    println("  + Risk string parsing works correctly")
end

@testset "Float to Risk String Tests" begin
    println("\n=== Testing Float -> Risk String Conversion ===")
    
    # High risk: >= 0.5
    @test Integration.float_to_risk_string(0.9f0) == "high"
    @test Integration.float_to_risk_string(0.8f0) == "high"
    @test Integration.float_to_risk_string(0.5f0) == "high"
    
    # Medium risk: >= 0.2 and < 0.5
    @test Integration.float_to_risk_string(0.49f0) == "medium"
    @test Integration.float_to_risk_string(0.35f0) == "medium"
    @test Integration.float_to_risk_string(0.2f0) == "medium"
    
    # Low risk: < 0.2
    @test Integration.float_to_risk_string(0.19f0) == "low"
    @test Integration.float_to_risk_string(0.1f0) == "low"
    @test Integration.float_to_risk_string(0.0f0) == "low"
    
    println("  + Float -> Risk String conversion works correctly")
end

@testset "Safe Conversion Tests" begin
    println("\n=== Testing Safe Conversions with Error Handling ===")
    
    # Test safe conversion with valid SharedTypes proposal
    valid_proposal = SharedTypes.ActionProposal(
        "test",
        0.8f0,
        0.1f0,
        0.5f0,
        "low",
        "test reasoning"
    )
    
    result = Integration.safe_convert_to_integration(valid_proposal)
    @test result !== nothing
    @test result isa IntegrationActionProposal
    
    # Test safe conversion with nothing
    result_nothing = Integration.safe_convert_to_integration(nothing)
    @test result_nothing === nothing
    
    # Test safe reverse conversion
    integration_proposal = IntegrationActionProposal(
        "test",
        0.8f0,
        0.1f0,
        0.5f0,
        0.2f0;
        reasoning = "test"
    )
    
    result_reverse = Integration.safe_convert_from_integration(integration_proposal)
    @test result_reverse !== nothing
    @test result_reverse isa SharedTypes.ActionProposal
    
    println("  + Safe conversions with error handling work correctly")
end

# ============================================================================
# Round-trip Tests
# ============================================================================

@testset "Round-trip Conversion Tests" begin
    println("\n=== Testing Round-trip Conversions ===")
    
    # Test: SharedTypes -> Integration -> SharedTypes
    original = SharedTypes.ActionProposal(
        "round_trip",
        0.95f0,
        0.05f0,
        0.9f0,
        "low",
        "Testing round-trip conversion"
    )
    
    # Forward
    integrated = Integration.convert_shared_proposal_to_integration(original)
    
    # Reverse
    round_tripped = Integration.convert_from_integration(integrated)
    
    # Verify key fields survived
    @test round_tripped.capability_id == original.capability_id
    @test round_tripped.confidence == original.confidence
    @test round_tripped.predicted_cost == original.predicted_cost
    @test round_tripped.predicted_reward == original.predicted_reward
    
    println("  + Round-trip conversion preserves key data")
end

println("\n" * "="^60)
println("  ALL INTEGRATION TESTS PASSED")
println("="^60 * "\n")
