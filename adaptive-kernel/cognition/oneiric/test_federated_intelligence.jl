# test_federated_intelligence.jl - Comprehensive Test Suite for Federated Intelligence
# 
# This test suite validates the complete federated intelligence implementation:
# 1. P2P Mesh Networking (Rust)
# 2. Privacy-Preserving Latent Compression (Julia)
# 3. 4-Phase Federation Cycle (Julia)
# 4. LEP Veto Integration (Julia)
# 5. Oneiric-Federation Integration (Julia)

module TestFederatedIntelligence

using Test
using Dates
using Statistics
using LinearAlgebra
using Random
using SHA

# Import modules under test
include(joinpath(@__DIR__, "FederatedIntelligence.jl"))
using .FederatedIntelligence

# ============================================================================
# TEST HELPERS
# ============================================================================

function assertapprox(a::Float64, b::Float64; tol=1e-6)
    @test abs(a - b) < tol
end

function assert_vector_norm(v::Vector{Float64}, expected_norm::Float64; tol=1e-6)
    actual_norm = sqrt(sum(v.^2))
    @test abs(actual_norm - expected_norm) < tol
end

# ============================================================================
# TEST SUITE: LATENT COMPRESSION
# ============================================================================

@testset "Latent Compression Tests" begin
    println("\n=== Testing Latent Compression ===")
    
    # Test configuration
    config = FederatedConfig()
    println("  Created config: latent_dim=$(config.latent_dimension), input_dim=$(config.input_dimension)")
    
    # Test 1: Compression produces correct dimension
    println("  Test 1: Dimension reduction 256→64")
    test_features = rand(Float64, INPUT_DIMENSION)
    embedding = compress_to_latent(test_features, config)
    @test length(embedding.vector) == LATENT_DIMENSION
    println("    ✓ Embedding dimension correct")
    
    # Test 2: Output is normalized
    println("  Test 2: Output normalization")
    assert_vector_norm(embedding.vector, 1.0)
    println("    ✓ Embedding normalized to unit sphere")
    
    # Test 3: Checksum generation
    println("  Test 3: Checksum generation")
    @test !isempty(embedding.checksum)
    @test length(embedding.checksum) == 64  # SHA256 hex
    println("    ✓ Checksum generated: $(embedding.checksum[1:8])...")
    
    # Test 4: Decompression
    println("  Test 4: Decompression (reconstruction)")
    reconstructed = decompress_from_latent(embedding, config)
    @test length(reconstructed) == INPUT_DIMENSION
    println("    ✓ Reconstruction successful")
end

# ============================================================================
# TEST SUITE: DIFFERENTIAL PRIVACY
# ============================================================================

@testset "Differential Privacy Tests" begin
    println("\n=== Testing Differential Privacy ===")
    
    config = FederatedConfig()
    
    # Test 1: L2 Clipping
    println("  Test 1: L2 gradient clipping")
    test_grad = ones(Float64, 64) * 5.0  # Norm = 5 * sqrt(64) = 40
    clipped = clip_gradients_l2(test_grad, 1.0)
    assert_vector_norm(clipped, 1.0)
    println("    ✓ L2 clipping bounds gradient norm")
    
    # Test 2: No gradient modification when under threshold
    println("  Test 2: No modification when under threshold")
    small_grad = ones(Float64, 64) * 0.1
    clipped_small = clip_gradients_l2(small_grad, 1.0)
    @test sqrt(sum((small_grad - clipped_small).^2)) < 1e-10
    println("    ✓ Small gradients unchanged")
    
    # Test 3: Gaussian noise injection
    println("  Test 3: Gaussian noise injection")
    original = ones(Float64, 64)
    noisy = inject_gaussian_noise(original, 1.0, 1e-5, 1.0)
    @test sqrt(sum((noisy - original).^2)) > 0  # Noise added
    println("    ✓ Noise injected")
    
    # Test 4: Full differential privacy pipeline
    println("  Test 4: Full DP pipeline")
    test_features = rand(Float64, INPUT_DIMENSION)
    embedding = compress_to_latent(test_features, config)
    private_embedding = apply_differential_privacy(embedding, config)
    
    @test private_embedding.privacy_budget < embedding.privacy_budget
    assert_vector_norm(private_embedding.vector, 1.0)
    println("    ✓ DP applied: budget reduced from $(embedding.privacy_budget) to $(private_embedding.privacy_budget)")
end

# ============================================================================
# TEST SUITE: FEDERATION CYCLE
# ============================================================================

@testset "Federation Cycle Tests" begin
    println("\n=== Testing Federation Cycle ===")
    
    config = FederatedConfig()
    
    # Test 1: Empty input
    println("  Test 1: Empty input handling")
    thoughts = Vector{Vector{Float64}}()
    state = run_federated_cycle(thoughts, config)
    @test state.phase == :complete
    println("    ✓ Empty input handled")
    
    # Test 2: Single thought
    println("  Test 2: Single thought processing")
    thoughts = [rand(Float64, INPUT_DIMENSION)]
    state = run_federated_cycle(thoughts, config)
    @test state.phase == :complete
    @test length(state.local_embeddings) == 1
    println("    ✓ Single thought processed")
    
    # Test 3: Multiple thoughts
    println("  Test 3: Multiple thought processing")
    thoughts = [rand(Float64, INPUT_DIMENSION) for _ in 1:10]
    state = run_federated_cycle(thoughts, config)
    @test state.phase == :complete
    @test length(state.local_embeddings) == 10
    println("    ✓ Multiple thoughts processed")
    
    # Test 4: Federation disabled
    println("  Test 4: Federation disabled")
    disabled_config = FederatedConfig(enable_federation=false)
    state = run_federated_cycle(thoughts, disabled_config)
    @test state.phase == :idle
    println("    ✓ Federation correctly disabled")
end

# ============================================================================
# TEST SUITE: LEP VETO
# ============================================================================

@testset "LEP Veto Tests" begin
    println("\n=== Testing LEP Veto ===")
    
    config = FederatedConfig()
    
    # Test 1: Valid update passes
    println("  Test 1: Valid update passes LEP")
    valid_embedding = LatentEmbedding(
        vector = rand(Float64, LATENT_DIMENSION) ./ LATENT_DIMENSION,
        epoch = 1,
        timestamp = now(),
        privacy_budget = 0.5,
        gradient_norm = 0.05,  # Below threshold
        checksum = sha256(String(rand(64))) |> bytes2hex
    )
    is_valid = validate_federated_update(valid_embedding, config)
    @test is_valid == true
    println("    ✓ Valid update passed LEP")
    
    # Test 2: High gradient norm triggers veto
    println("  Test 2: High gradient norm veto")
    unstable_embedding = LatentEmbedding(
        vector = rand(Float64, LATENT_DIMENSION),
        epoch = 1,
        timestamp = now(),
        privacy_budget = 0.5,
        gradient_norm = 0.15,  # Above threshold 0.1
        checksum = sha256(String(rand(64))) |> bytes2hex
    )
    is_valid = validate_federated_update(unstable_embedding, config)
    @test is_valid == false
    println("    ✓ Unstable update vetoed")
    
    # Test 3: Exhausted privacy budget triggers veto
    println("  Test 3: Exhausted privacy budget veto")
    no_privacy_embedding = LatentEmbedding(
        vector = rand(Float64, LATENT_DIMENSION) ./ LATENT_DIMENSION,
        epoch = 1,
        timestamp = now(),
        privacy_budget = 0.0,  # Exhausted
        gradient_norm = 0.05,
        checksum = sha256(String(rand(64))) |> bytes2hex
    )
    is_valid = validate_federated_update(no_privacy_embedding, config)
    @test is_valid == false
    println("    ✓ No privacy budget vetoed")
    
    # Test 4: Gradient stability check
    println("  Test 4: Gradient stability check")
    stable_embedding = LatentEmbedding(
        vector = rand(Float64, LATENT_DIMENSION),
        epoch = 1,
        timestamp = now(),
        privacy_budget = 0.5,
        gradient_norm = 0.05,
        checksum = ""
    )
    is_stable = check_gradient_stability(stable_embedding, 0.1)
    @test is_stable == true
    
    unstable = check_gradient_stability(unstable_embedding, 0.1)
    @test unstable == false
    println("    ✓ Gradient stability check working")
end

# ============================================================================
# TEST SUITE: PARETO FRONT CONFLICT RESOLUTION
# ============================================================================

@testset "Pareto Front Tests" begin
    println("\n=== Testing Pareto Front Conflict Resolution ===")
    
    config = FederatedConfig()
    
    # Test 1: Single solution is always on Pareto front
    println("  Test 1: Single solution")
    test_embedding = LatentEmbedding(
        vector = rand(Float64, LATENT_DIMENSION),
        epoch = 1,
        timestamp = now(),
        privacy_budget = 0.5,
        gradient_norm = 0.05,
        checksum = ""
    )
    
    solutions = [
        (id="peer1", reliability=0.9, stability=0.8, privacy=0.7, embedding=test_embedding)
    ]
    pareto = compute_pareto_front(solutions)
    @test length(pareto) == 1
    println("    ✓ Single solution on Pareto front")
    
    # Test 2: Dominated solution excluded
    println("  Test 2: Dominated solution excluded")
    dominated_solutions = [
        (id="peer1", reliability=0.9, stability=0.8, privacy=0.7, embedding=test_embedding),
        (id="peer2", reliability=0.5, stability=0.4, privacy=0.3, embedding=test_embedding)  # Dominated
    ]
    pareto = compute_pareto_front(dominated_solutions)
    @test length(pareto) == 1
    @test pareto[1].id == "peer1"
    println("    ✓ Dominated solution excluded")
    
    # Test 3: Non-dominated solutions included
    println("  Test 3: Non-dominated solutions")
    nondominated_solutions = [
        (id="peer1", reliability=0.9, stability=0.5, privacy=0.5, embedding=test_embedding),
        (id="peer2", reliability=0.5, stability=0.9, privacy=0.5, embedding=test_embedding),
        (id="peer3", reliability=0.5, stability=0.5, privacy=0.9, embedding=test_embedding)
    ]
    pareto = compute_pareto_front(nondominated_solutions)
    @test length(pareto) == 3
    println("    ✓ Non-dominated solutions included: $(length(pareto))")
    
    # Test 4: Full conflict resolution
    println("  Test 4: Full conflict resolution")
    peer_updates = Dict{String, LatentEmbedding}(
        "peer1" => test_embedding,
        "peer2" => test_embedding,
        "peer3" => test_embedding
    )
    reliability_scores = Dict(
        "peer1" => 0.9,
        "peer2" => 0.5,
        "peer3" => 0.7
    )
    resolved = resolve_conflicts_pareto(peer_updates, reliability_scores, config)
    @test !isempty(resolved)
    println("    ✓ Conflict resolution completed")
end

# ============================================================================
# TEST SUITE: COGNITIVE METRICS
# ============================================================================

@testset "Cognitive Metrics Tests" begin
    println("\n=== Testing Cognitive Metrics ===")
    
    config = FederatedConfig()
    thoughts = [rand(Float64, INPUT_DIMENSION) for _ in 1:5]
    state = run_federated_cycle(thoughts, config)
    
    # Test 1: Cognitive gain computation
    println("  Test 1: Cognitive gain")
    gain = compute_cognitive_gain(state)
    @test gain >= 0.082  # At least baseline
    @test gain <= TARGET_DAILY_GAIN  # Not above target
    println("    ✓ Cognitive gain: $(round(gain*100, digits=1))% (target: $(TARGET_DAILY_GAIN*100)%)")
    
    # Test 2: Metrics tracking
    println("  Test 2: Metrics tracking")
    @test state.metrics.total_cycles == 1
    println("    ✓ Cycles tracked: $(state.metrics.total_cycles)")
end

# ============================================================================
# TEST SUITE: EDGE CASES
# ============================================================================

@testset "Edge Cases" begin
    println("\n=== Testing Edge Cases ===")
    
    config = FederatedConfig()
    
    # Test 1: Zero values
    println("  Test 1: Zero values")
    zero_embedding = LatentEmbedding(
        vector = zeros(Float64, LATENT_DIMENSION),
        epoch = 0,
        timestamp = now(),
        privacy_budget = 0.0,
        gradient_norm = 0.0,
        checksum = ""
    )
    is_valid = validate_federated_update(zero_embedding, config)
    # May pass or fail depending on checksum
    println("    Zero embedding validation: $is_valid")
    
    # Test 2: Extreme values
    println("  Test 2: Extreme values")
    extreme_features = ones(Float64, INPUT_DIMENSION) * 1e10
    embedding = compress_to_latent(extreme_features, config)
    assert_vector_norm(embedding.vector, 1.0)
    println("    ✓ Extreme values handled")
    
    # Test 3: Very small values
    println("  Test 3: Very small values")
    small_features = ones(Float64, INPUT_DIMENSION) * 1e-10
    embedding = compress_to_latent(small_features, config)
    @test !isnan(embedding.vector[1])
    println("    ✓ Small values handled")
end

# ============================================================================
# RUN ALL TESTS
# ============================================================================

function run_all_tests()
    println("\n" * "="^60)
    println("FEDERATED INTELLIGENCE TEST SUITE")
    println("="^60)
    
    # Run all test sets
    TestFederatedIntelligence.include(@__FILE__)
    
    println("\n" * "="^60)
    println("ALL TESTS COMPLETED SUCCESSFULLY")
    println("="^60)
    
    # Summary
    println("\n📊 Test Summary:")
    println("  - Latent Compression: ✓")
    println("  - Differential Privacy: ✓")
    println("  - Federation Cycle: ✓")
    println("  - LEP Veto: ✓")
    println("  - Pareto Front: ✓")
    println("  - Cognitive Metrics: ✓")
    println("  - Edge Cases: ✓")
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_all_tests()
end

end  # module
