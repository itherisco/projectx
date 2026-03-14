"""
# test_multimodal_sensory.jl

Integration tests for Multimodal Sensory Expansion

Tests:
1. VisionPerception.jl - Camera integration and feature extraction
2. MultimodalIntegration.jl - Unified multimodal processing
3. 12D perception format integration with Brain.jl

Run with: julia --project=. test_multimodal_sensory.jl
"""

using Test
using Dates

# Add parent to path for imports
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Import modules under test
include("../sensory/VisionPerception.jl")
using .VisionPerception

include("../sensory/MultimodalIntegration.jl")  
using .MultimodalIntegration

# ============================================================================
# Test Configuration
# ============================================================================

const TEST_RESOLUTION = (64, 64)  # Small for fast tests
const TEST_FPS = 10.0

# ============================================================================
# VisionPerception Tests
# ============================================================================

@testset "VisionPerception" begin
    @testset "VisionConfig creation" begin
        config = VisionConfig(
            resolution=TEST_RESOLUTION,
            fps=TEST_FPS,
            enable_object_detection=true
        )
        
        @test config.resolution == TEST_RESOLUTION
        @test config.fps == TEST_FPS
        @test config.enable_object_detection == true
    end
    
    @testset "Vision processor creation" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        @test processor !== nothing
        @test processor[:config] === config
        @test processor[:frame_counter] == 0
    end
    
    @testset "Frame capture" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        frame = capture_frame(processor, :test_camera)
        
        @test frame !== nothing
        @test size(frame.data) == TEST_RESOLUTION
        @test frame.source == :test_camera
        @test frame.frame_id == 1
        @test validate_frame(frame) == true
    end
    
    @testset "Feature extraction" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        frame = capture_frame(processor, :test_camera)
        features = extract_features(frame, config)
        
        @test length(features.spatial_features) == 4
        @test length(features.histogram_features) == 4
        @test length(features.edge_features) == 4
        @test length(features.texture_features) == 4
        @test features.confidence >= 0.0 && features.confidence <= 1.0
    end
    
    @testset "12D perception computation" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        # Process multiple frames for motion features
        for i in 1:3
            frame = capture_frame(processor, :test_camera)
            features = extract_features(frame, config; 
                previous_frame=i > 1 ? processor[:previous_frame] : nothing)
        end
        
        # Get final features
        features = processor[:feature_history][end]
        
        perception_12d = compute_perception_12d(features)
        
        @test length(perception_12d) == 12
        @test all(f -> f isa Float32, perception_12d)
    end
    
    @testset "Complete vision pipeline" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        result = process_vision_input(processor, :test_camera)
        
        @test result !== nothing
        @test length(result.perception_12d) == 12
        @test result.salience_score >= 0.0 && result.salience_score <= 1.0
        @test result.novelty_score >= 0.0 && result.novelty_score <= 1.0
        @test result.frame_id >= 1
    end
    
    @testset "Motion detection" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        # Generate different frames
        data1 = rand(Float32, TEST_RESOLUTION)
        data2 = data1 .+ 0.3f0  # Different enough for motion
        
        frame1 = capture_frame(processor, :test_camera; data=data1)
        frame2 = capture_frame(processor, :test_camera; data=data2)
        
        has_motion = detect_motion(frame1, frame2; threshold=0.1)
        
        @test has_motion == true
        
        # Nearly identical frames should have no motion
        data3 = data1 .+ 0.01f0
        frame3 = capture_frame(processor, :test_camera; data=data3)
        
        no_motion = detect_motion(frame1, frame3; threshold=0.1)
        @test no_motion == false
    end
    
    @testset "Frame validation" begin
        # Valid frame
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        valid_frame = capture_frame(processor, :test_camera)
        @test validate_frame(valid_frame) == true
        
        # Invalid frame with NaN
        invalid_frame = VisionFrame(
            Float32[NaN, 0.0; 0.0, 0.0],
            time(),
            1,
            :test,
            Dict{String, Any}()
        )
        @test validate_frame(invalid_frame) == false
        
        # Invalid frame with out-of-bounds values
        invalid_frame2 = VisionFrame(
            Float32[1.5, 0.0; 0.0, 0.0],  # > 2.0
            time(),
            1,
            :test,
            Dict{String, Any}()
        )
        @test validate_frame(invalid_frame2) == false
    end
    
    @testset "Supported sources" begin
        sources = get_supported_sources()
        @test :webcam in sources
        @test :ip_camera in sources
        @test :file in sources
        @test :virtual in sources
    end
end

# ============================================================================
# MultimodalIntegration Tests
# ============================================================================

@testset "MultimodalIntegration" begin
    @testset "MultimodalConfig creation" begin
        config = MultimodalConfig(
            enable_vision=true,
            enable_audio=false,
            enable_telemetry=true,
            fusion_strategy=:attention
        )
        
        @test config.enable_vision == true
        @test config.enable_audio == false
        @test config.enable_telemetry == true
        @test config.fusion_strategy == :attention
    end
    
    @testset "Pipeline creation" begin
        config = MultimodalConfig(enable_vision=true)
        state = create_multimodal_pipeline(config)
        
        @test state !== nothing
        @test state.vision_processor !== nothing
        @test state.processing_count == 0
    end
    
    @testset "Vision-only multimodal perception" begin
        config = MultimodalConfig(
            enable_vision=true,
            enable_audio=false,
            enable_telemetry=false,
            vision_weight=1.0f0
        )
        
        state = create_multimodal_pipeline(config)
        
        result = process_vision_frame(state, config)
        
        @test result !== nothing
        @test length(result.perception_12d) == 12
        @test :vision in result.sources
    end
    
    @testset "Audio input processing" begin
        config = MultimodalConfig(
            enable_vision=false,
            enable_audio=true,
            enable_telemetry=false
        )
        
        state = create_multimodal_pipeline(config)
        
        # Simulate audio features
        audio_features = rand(Float32, 128)
        success = process_audio_input(state, config, audio_features)
        
        @test success == true
    end
    
    @testset "Telemetry input processing" begin
        config = MultimodalConfig(
            enable_vision=false,
            enable_audio=false,
            enable_telemetry=true
        )
        
        state = create_multimodal_pipeline(config)
        
        # Simulate telemetry features
        telemetry_features = rand(Float32, 64)
        success = process_telemetry_input(state, config, telemetry_features)
        
        @test success == true
    end
    
    @testset "Unified perception generation" begin
        config = MultimodalConfig(
            enable_vision=true,
            enable_audio=true,
            enable_telemetry=true
        )
        
        state = create_multimodal_pipeline(config)
        
        # Add some audio and telemetry
        process_audio_input(state, config, rand(Float32, 64))
        process_telemetry_input(state, config, rand(Float32, 64))
        
        # Get unified perception
        result = get_unified_perception(state, config)
        
        @test result !== nothing
        @test length(result.perception_12d) == 12
        @test length(result.sources) >= 1
    end
    
    @testset "Fusion strategies" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        vision_result = process_vision_input(processor, :test)
        
        # Test weighted fusion
        result_12d = fuse_perceptions(vision_result, nothing, MultimodalConfig(
            enable_vision=true, fusion_strategy=:weighted))
        @test length(result_12d) == 12
        
        # Test attention fusion
        result_12d = fuse_perceptions(vision_result, nothing, MultimodalConfig(
            enable_vision=true, fusion_strategy=:attention))
        @test length(result_12d) == 12
        
        # Test concatenate fusion
        result_12d = fuse_perceptions(vision_result, nothing, MultimodalConfig(
            enable_vision=true, fusion_strategy=:concatenate))
        @test length(result_12d) == 12
    end
    
    @testset "Cross-modal attention" begin
        perceptions = Dict{Symbol, Vector{Float32}}(
            :vision => rand(Float32, 12),
            :audio => rand(Float32, 12),
            :telemetry => rand(Float32, 12)
        )
        
        attention = compute_crossmodal_attention(perceptions)
        
        @test :vision in keys(attention)
        @test :audio in keys(attention)
        @test :telemetry in keys(attention)
        
        # Attention weights should sum to approximately 1
        total = sum(values(attention))
        @test abs(total - 1.0f0) < 0.1
    end
    
    @testset "Modality weights" begin
        config = MultimodalConfig(
            vision_weight=0.5f0,
            audio_weight=0.3f0,
            telemetry_weight=0.2f0
        )
        
        weights = get_modality_weights(config)
        
        @test weights[:vision] == 0.5f0
        @test weights[:audio] == 0.3f0
        @test weights[:telemetry] == 0.2f0
    end
end

# ============================================================================
# Integration Tests
# ============================================================================

@testset "Integration: Vision to Brain 12D Format" begin
    @testset "12D format compatibility" begin
        # Create vision processor
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        # Process frame
        result = process_vision_input(processor, :camera)
        
        # Verify 12D format matches Brain.jl expectations
        perception_12d = result.perception_12d
        
        @test length(perception_12d) == 12  # Required by BrainInput
        
        # Verify all values are valid floats
        @test all(f -> !isnan(f) && !isinf(f), perception_12d)
        
        # Verify reasonable range (after normalization)
        @test all(f -> f >= -10.0f0 && f <= 10.0f0, perception_12d)
    end
    
    @testset "Multimodal to Brain Input" begin
        # Create full multimodal pipeline
        config = MultimodalConfig(
            enable_vision=true,
            enable_audio=true,
            enable_telemetry=true
        )
        
        state = create_multimodal_pipeline(config)
        
        # Add various inputs
        process_audio_input(state, config, rand(Float32, 64))
        process_telemetry_input(state, config, rand(Float32, 64))
        
        # Get unified perception (Brain-ready)
        result = get_unified_perception(state, config)
        
        # This 12D vector can be directly used as BrainInput.perception_vector
        brain_input = result.perception_12d
        
        @test length(brain_input) == 12
        @test eltype(brain_input) == Float32
    end
end

# ============================================================================
# Performance Tests
# ============================================================================

@testset "Performance" begin
    @testset "Vision processing throughput" begin
        config = VisionConfig(resolution=TEST_RESOLUTION)
        processor = create_vision_processor(config)
        
        # Time processing of multiple frames
        n_frames = 100
        start_time = time()
        
        for i in 1:n_frames
            process_vision_input(processor, :test)
        end
        
        elapsed = time() - start_time
        fps_processed = n_frames / elapsed
        
        @info "Vision processing: $(round(fps_processed, digits=1)) FPS"
        
        # Should process at least 10 FPS
        @test fps_processed > 10
    end
end

# ============================================================================
# Test Summary
# ============================================================================

println("\n" * "="^60)
println("MULTIMODAL SENSORY EXPANSION - TEST SUMMARY")
println("="^60)
println("All tests completed. See output above for details.")
println("="^60)
