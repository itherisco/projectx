"""
# MultimodalIntegration.jl

Multimodal Sensory Integration Module

This module integrates vision perception with the existing SensoryProcessing.jl
to create a unified multimodal sensory pipeline that combines visual, auditory,
telemetry, and now vision inputs into the 12D unified perception format.

## Features
- Unified multimodal input handling
- Cross-modal attention and salience computation
- Seamless integration with Brain.jl 12D format
- Vision + telemetry fusion for enhanced environmental awareness

## Integration Points
- Input: VisionPerception.jl, SensoryProcessing.jl
- Output: 12D unified perception for Brain.jl
- Related: IoTBridge.jl, RealityIngestion.jl, Brain.jl

## Applications
- Physical Security (vision + telemetry fusion)
- Autonomous Robotics (spatial awareness)
- Environmental Monitoring (multimodal sensing)
"""

module MultimodalIntegration

using Statistics
using LinearAlgebra
using Dates

# Import existing sensory processing
include("SensoryProcessing.jl")
using .SensoryProcessing

# Import vision perception
include("VisionPerception.jl")
using .VisionPerception

# Import central Attention module for salience-based gating
include("../cognition/attention/Attention.jl")
using .Attention

# ============================================================================
# Type Definitions
# ============================================================================

"""
    MultimodalConfig - Configuration for multimodal integration

# Fields
- `enable_vision::Bool`: Enable vision processing
- `enable_audio::Bool`: Enable audio processing  
- `enable_telemetry::Bool`: Enable system telemetry
- `fusion_strategy::Symbol`: How to combine modalities (:weighted, :attention, :concatenate)
- `vision_weight::Float32`: Weight for vision in fusion [0, 1]
- `audio_weight::Float32`: Weight for audio in fusion [0, 1]
- `telemetry_weight::Float32`: Weight for telemetry in fusion [0, 1]
- `history_size::Int`: Number of past perceptions to keep for novelty detection
"""
mutable struct MultimodalConfig
    enable_vision::Bool
    enable_audio::Bool
    enable_telemetry::Bool
    fusion_strategy::Symbol
    vision_weight::Float32
    audio_weight::Float32
    telemetry_weight::Float32
    history_size::Int
    
    function MultimodalConfig(;
        enable_vision::Bool=true,
        enable_audio::Bool=true,
        enable_telemetry::Bool=true,
        fusion_strategy::Symbol=:attention,
        vision_weight::Float32=0.4f0,
        audio_weight::Float32=0.3f0,
        telemetry_weight::Float32=0.3f0,
        history_size::Int=100
    )
        new(enable_vision, enable_audio, enable_telemetry, fusion_strategy,
            vision_weight, audio_weight, telemetry_weight, history_size)
    end
end

"""
    MultimodalState - Runtime state for multimodal processing

# Fields
- `vision_processor::Union{Dict, Nothing}`: Vision processing pipeline
- `sensory_buffer::Union{SensoryBuffer, Nothing}`: Legacy sensory buffer
- `vision_history::Vector{VisionPerceptionResult}`: Recent vision results
- `fusion_history::Vector{Vector{Float32}}`: Recent fused perceptions
- `last_update::Float64`: Timestamp of last update
- `processing_count::Int64`: Total frames processed
"""
mutable struct MultimodalState
    vision_processor::Union{Dict{String, Any}, Nothing}
    sensory_buffer::Union{SensoryBuffer, Nothing}
    vision_history::Vector{VisionPerceptionResult}
    fusion_history::Vector{Vector{Float32}}
    last_update::Float64
    processing_count::Int64
    
    function MultimodalState(;
        vision_processor::Union{Dict{String, Any}, Nothing}=nothing,
        sensory_buffer::Union{SensoryBuffer, Nothing}=nothing
    )
        new(vision_processor, sensory_buffer, 
            VisionPerceptionResult[], Vector{Float32}[],
            time(), Int64(0))
    end
end

"""
    MultimodalPerception - Complete multimodal perception result

# Fields
- `perception_12d::Vector{Float32}`: Fused 12D unified perception
- `modality_perceptions::Dict{Symbol, Vector{Float32}}`: Individual modality 12D vectors
- `modality_saliences::Dict{Symbol, Float32}`: Salience scores per modality
- `fusion_confidence::Float32`: Overall fusion confidence [0, 1]
- `novelty_score::Float32`: Novelty relative to history [0, 1]
- `timestamp::Float64`: Processing timestamp
- `frame_id::Int64`: Vision frame ID (if vision enabled)
- `sources::Vector{Symbol}`: Active data sources
"""
struct MultimodalPerception
    perception_12d::Vector{Float32}
    modality_perceptions::Dict{Symbol, Vector{Float32}}
    modality_saliences::Dict{Symbol, Float32}
    fusion_confidence::Float32
    novelty_score::Float32
    timestamp::Float64
    frame_id::Int64
    sources::Vector{Symbol}
end

# ============================================================================
# Export public API
# ============================================================================

export
    # Types
    MultimodalConfig,
    MultimodalState,
    MultimodalPerception,
    
    # Core functions
    create_multimodal_pipeline,
    process_vision_frame,
    process_audio_input,
    process_telemetry_input,
    fuse_perceptions,
    get_unified_perception,
    
    # Attention gating
    apply_attention_gating,
    compute_modality_salience,
    gate_perception_by_attention,
    
    # Utility
    get_modality_weights,
    compute_crossmodal_attention,
    default_multimodal_config

# ============================================================================
# Core Processing Functions
# ============================================================================

"""
    create_multimodal_pipeline(config::MultimodalConfig)

Create a new multimodal processing pipeline.
Initializes both vision and legacy sensory processing.
"""
function create_multimodal_pipeline(config::MultimodalConfig)
    # Initialize vision processor if enabled
    vision_processor = if config.enable_vision
        vision_config = VisionConfig(
            resolution=(640, 480),
            fps=30.0,
            enable_object_detection=false
        )
        create_vision_processor(vision_config)
    else
        nothing
    end
    
    # Initialize legacy sensory buffer if any modality enabled
    sensory_buffer = if config.enable_audio || config.enable_telemetry
        SensoryBuffer(max_size=config.history_size)
    else
        nothing
    end
    
    state = MultimodalState(
        vision_processor=vision_processor,
        sensory_buffer=sensory_buffer
    )
    
    return state
end

"""
    process_vision_frame(state::MultimodalState, config::MultimodalConfig;
                        data::Union{Matrix{Float32}, Nothing}=nothing,
                        source::Symbol=:camera)::Union{MultimodalPerception, Nothing}

Process a single vision frame and integrate with multimodal pipeline.
"""
function process_vision_frame(state::MultimodalState, config::MultimodalConfig;
                             data::Union{Matrix{Float32}, Nothing}=nothing,
                             source::Symbol=:camera)::Union{MultimodalPerception, Nothing}
    
    if !config.enable_vision || state.vision_processor === nothing
        return nothing
    end
    
    # Process vision frame
    vision_result = process_vision_input(state.vision_processor, source; data=data)
    
    # Store in history
    push!(state.vision_history, vision_result)
    if length(state.vision_history) > config.history_size
        deleteat!(state.vision_history, 1:length(state.vision_history)-config.history_size)
    end
    
    # Get individual modality perception
    modality_perceptions = Dict{Symbol, Vector{Float32}}(
        :vision => vision_result.perception_12d
    )
    modality_saliences = Dict{Symbol, Float32}(
        :vision => vision_result.salience_score
    )
    
    # Create multimodal perception from vision only
    perception = MultimodalPerception(
        vision_result.perception_12d,
        modality_perceptions,
        modality_saliences,
        vision_result.raw_features.confidence,
        vision_result.novelty_score,
        vision_result.timestamp,
        vision_result.frame_id,
        [:vision]
    )
    
    state.processing_count += 1
    state.last_update = time()
    
    return perception
end

"""
    process_audio_input(state::MultimodalState, config::MultimodalConfig,
                       features::Vector{Float32})::Bool

Process audio features into the sensory buffer.
"""
function process_audio_input(state::MultimodalState, config::MultimodalConfig,
                            features::Vector{Float32})::Bool
    
    if !config.enable_audio || state.sensory_buffer === nothing
        return false
    end
    
    return push_sensory!(state.sensory_buffer, :microphone, Float64.(features))
end

"""
    process_telemetry_input(state::MultimodalState, config::MultimodalConfig,
                           features::Vector{Float32})::Bool

Process telemetry features into the sensory buffer.
"""
function process_telemetry_input(state::MultimodalState, config::MultimodalConfig,
                                features::Vector{Float32})::Bool
    
    if !config.enable_telemetry || state.sensory_buffer === nothing
        return false
    end
    
    return push_sensory!(state.sensory_buffer, :system, Float64.(features))
end

"""
    fuse_perceptions(vision_perception::Union{VisionPerceptionResult, Nothing},
                    sensory_perception::Union{ProcessedSensory, Nothing},
                    config::MultimodalConfig)::Vector{Float32}

Fuse multiple modality perceptions into a single 12D vector.
"""
function fuse_perceptions(vision_perception::Union{VisionPerceptionResult, Nothing},
                         sensory_perception::Union{ProcessedSensory, Nothing},
                         config::MultimodalConfig)::Vector{Float32}
    
    # Collect available perceptions
    perceptions = Vector{Float32}[]
    weights = Float32[]
    
    if vision_perception !== nothing && config.enable_vision
        push!(perceptions, vision_perception.perception_12d)
        push!(weights, config.vision_weight)
    end
    
    if sensory_perception !== nothing
        # Add auditory if available
        if config.enable_audio && !isempty(sensory_perception.raw_streams[:auditory])
            audio_12d = _extract_modality_12d(sensory_perception.raw_streams[:auditory], 5:8)
            push!(perceptions, audio_12d)
            push!(weights, config.audio_weight)
        end
        
        # Add telemetry if available
        if config.enable_telemetry && !isempty(sensory_perception.raw_streams[:telemetry])
            telemetry_12d = _extract_modality_12d(sensory_perception.raw_streams[:telemetry], 9:12)
            push!(perceptions, telemetry_12d)
            push!(weights, config.telemetry_weight)
        end
    end
    
    # If no perceptions available, return zero vector
    if isempty(perceptions)
        return zeros(Float32, 12)
    end
    
    # Normalize weights
    weights = weights ./ sum(weights)
    
    # Fuse based on strategy
    fused = if config.fusion_strategy == :weighted
        _weighted_fusion(perceptions, weights)
    elseif config.fusion_strategy == :attention
        _attention_fusion(perceptions, weights)
    else
        _concatenate_fusion(perceptions)
    end
    
    return fused
end

"""
    _extract_modality_12d(features::Vector{Float32}, range::UnitRange{Int})::Vector{Float32}

Extract a 4D subset and expand to full 12D representation.
"""
function _extract_modality_12d(features::Vector{Float32}, range::UnitRange{Int})::Vector{Float32}
    # Start with zeros
    result = zeros(Float32, 12)
    
    # Resize features to 4D
    features_4d = _resize_to_4d(features)
    
    # Place in appropriate range
    result[range] = features_4d
    
    return result
end

"""
    _resize_to_4d(features::Vector{Float32})::Vector{Float32}

Resize feature vector to exactly 4 dimensions.
"""
function _resize_to_4d(features::Vector{Float32})::Vector{Float32}
    TARGET_DIM = 4
    
    if length(features) == TARGET_DIM
        return features
    elseif isempty(features)
        return zeros(Float32, TARGET_DIM)
    elseif length(features) > TARGET_DIM
        # Pool down to 4D using mean pooling
        chunk_size = length(features) ÷ TARGET_DIM
        pooled = Float32[]
        for i in 1:TARGET_DIM
            start_idx = (i-1) * chunk_size + 1
            end_idx = min(i * chunk_size, length(features))
            push!(pooled, mean(features[start_idx:end_idx]))
        end
        return pooled
    else
        # Pad to 4D
        padded = zeros(Float32, TARGET_DIM)
        padded[1:length(features)] = features
        return padded
    end
end

"""
    _weighted_fusion(perceptions::Vector{Vector{Float32}}, weights::Vector{Float32})::Vector{Float32}

Weighted fusion of multiple perception vectors.
"""
function _weighted_fusion(perceptions::Vector{Vector{Float32}}, weights::Vector{Float32})::Vector{Float32}
    fused = zeros(Float32, 12)
    
    for (perception, weight) in zip(perceptions, weights)
        fused .= fused .+ perception .* weight
    end
    
    return fused
end

"""
    _attention_fusion(perceptions::Vector{Vector{Float32}}, weights::Vector{Float32})::Vector{Float32}

Attention-based fusion with softmax-weighted contributions.
"""
function _attention_fusion(perceptions::Vector{Vector{Float32}}, weights::Vector{Float32})::Vector{Float32}
    # Apply softmax to weights for attention
    attention_weights = softmax(weights)
    
    return _weighted_fusion(perceptions, attention_weights)
end

"""
    _concatenate_fusion(perceptions::Vector{Vector{Float32}})::Vector{Float32}

Concatenation fusion - takes first 4 dimensions from each perception.
"""
function _concatenate_fusion(perceptions::Vector{Vector{Float32}})::Vector{Float32}
    result = Float32[]
    
    for perception in perceptions
        # Take first 4 elements from each
        push!(result, perception[1:4]...)
    end
    
    # Pad or truncate to 12
    if length(result) < 12
        return vcat(result, zeros(Float32, 12 - length(result)))
    else
        return result[1:12]
    end
end

"""
    softmax(x::Vector{Float32})::Vector{Float32}

Compute softmax function for attention weights.
"""
function softmax(x::Vector{Float32})::Vector{Float32}
    x_shifted = x .- maximum(x)
    exp_x = exp.(x_shifted)
    return exp_x ./ sum(exp_x)
end

"""
    get_unified_perception(state::MultimodalState, config::MultimodalConfig;
                          vision_data::Union{Matrix{Float32}, Nothing}=nothing)::MultimodalPerception

Get unified multimodal perception combining all available modalities.
"""
function get_unified_perception(state::MultimodalState, config::MultimodalConfig;
                               vision_data::Union{Matrix{Float32}, Nothing}=nothing)::MultimodalPerception
    
    # Process vision if enabled
    vision_result = if config.enable_vision && state.vision_processor !== nothing
        process_vision_input(state.vision_processor, :camera; data=vision_data)
    else
        nothing
    end
    
    # Get sensory processing result if buffer available
    sensory_result = if state.sensory_buffer !== nothing
        preprocess_input(state.sensory_buffer; attention_gate=true)
    else
        nothing
    end
    
    # Fuse perceptions
    fused_12d = fuse_perceptions(vision_result, sensory_result, config)
    
    # Collect modality information
    modality_perceptions = Dict{Symbol, Vector{Float32}}()
    modality_saliences = Dict{Symbol, Float32}()
    sources = Symbol[]
    
    if vision_result !== nothing && config.enable_vision
        modality_perceptions[:vision] = vision_result.perception_12d
        modality_saliences[:vision] = vision_result.salience_score
        push!(sources, :vision)
    end
    
    if sensory_result !== nothing
        if config.enable_audio
            modality_perceptions[:audio] = _extract_modality_12d(
                get(sensory_result.raw_streams, :auditory, Float32[]), 5:8)
            modality_saliences[:audio] = sensory_result.salience_weights[2]
            push!(sources, :audio)
        end
        if config.enable_telemetry
            modality_perceptions[:telemetry] = _extract_modality_12d(
                get(sensory_result.raw_streams, :telemetry, Float32[]), 9:12)
            modality_saliences[:telemetry] = sensory_result.salience_weights[3]
            push!(sources, :telemetry)
        end
    end
    
    # Compute novelty
    novelty = _compute_fusion_novelty(fused_12d, state.fusion_history)
    
    # Update fusion history
    push!(state.fusion_history, fused_12d)
    if length(state.fusion_history) > config.history_size
        deleteat!(state.fusion_history, 1:length(state.fusion_history)-config.history_size)
    end
    
    state.processing_count += 1
    state.last_update = time()
    
    # Compute fusion confidence
    fusion_confidence = _compute_fusion_confidence(vision_result, sensory_result)
    
    frame_id = vision_result !== nothing ? vision_result.frame_id : Int64(0)
    
    return MultimodalPerception(
        fused_12d,
        modality_perceptions,
        modality_saliences,
        fusion_confidence,
        novelty,
        time(),
        frame_id,
        sources
    )
end

"""
    _compute_fusion_novelty(current::Vector{Float32}, 
                           history::Vector{Vector{Float32}})::Float32

Compute novelty of current fused perception vs history.
"""
function _compute_fusion_novelty(current::Vector{Float32}, 
                                history::Vector{Vector{Float32}})::Float32
    if isempty(history)
        return 0.5f0
    end
    
    similarities = Float32[]
    for past in history[max(1, end-10):end]
        sim = _cosine_similarity(current, past)
        push!(similarities, sim)
    end
    
    avg_sim = mean(similarities)
    return clamp(1.0f0 - avg_sim, 0.0f0, 1.0f0)
end

"""
    _cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
"""
function _cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    if length(a) != length(b)
        return 0.0f0
    end
    
    dot_prod = sum(a .* b)
    norm_a = sqrt(sum(a .^ 2))
    norm_b = sqrt(sum(b .^ 2))
    
    if norm_a == 0 || norm_b == 0
        return 0.0f0
    end
    
    return clamp(dot_prod / (norm_a * norm_b), 0.0f0, 1.0f0)
end

"""
    _compute_fusion_confidence(vision_result::Union{VisionPerceptionResult, Nothing},
                               sensory_result::Union{ProcessedSensory, Nothing})::Float32

Compute overall confidence in fused perception.
"""
function _compute_fusion_confidence(vision_result::Union{VisionPerceptionResult, Nothing},
                                    sensory_result::Union{ProcessedSensory, Nothing})::Float32
    
    confidences = Float32[]
    
    if vision_result !== nothing
        push!(confidences, vision_result.raw_features.confidence)
    end
    
    if sensory_result !== nothing
        # Average salience as proxy for confidence
        push!(confidences, mean(sensory_result.salience_weights))
    end
    
    if isempty(confidences)
        return 0.0f0
    end
    
    return mean(confidences)
end

"""
    get_modality_weights(config::MultimodalConfig)::Dict{Symbol, Float32}

Get current modality weights.
"""
function get_modality_weights(config::MultimodalConfig)::Dict{Symbol, Float32}
    return Dict(
        :vision => config.vision_weight,
        :audio => config.audio_weight,
        :telemetry => config.telemetry_weight
    )
end

"""
    compute_crossmodal_attention(perceptions::Dict{Symbol, Vector{Float32}})::Dict{Symbol, Float32}

Compute cross-modal attention weights based on feature entropy.
"""
function compute_crossmodal_attention(perceptions::Dict{Symbol, Vector{Float32}})::Dict{Symbol, Float32}
    entropies = Float32[]
    modalities = Symbol[]
    
    for (modality, perception) in perceptions
        # Compute entropy as measure of information content
        entropy = _compute_entropy(perception)
        push!(entropies, entropy)
        push!(modalities, modality)
    end
    
    # Apply softmax for attention weights
    if isempty(entropies)
        return Dict{Symbol, Float32}()
    end
    
    attention = softmax(entropies)
    
    result = Dict{Symbol, Float32}()
    for (modality, weight) in zip(modalities, attention)
        result[modality] = weight
    end
    
    return result
end

"""
    _compute_entropy(features::Vector{Float32})::Float32

Compute entropy of feature distribution.
"""
function _compute_entropy(features::Vector{Float32})::Float32
    if isempty(features)
        return 0.0f0
    end
    
    # Simple entropy approximation using variance
    variance = var(features)
    return clamp(variance * 10, 0.0f0, 1.0f0)
end

# ============================================================================
# Attention-Based Gating (using Attention.jl)
# ============================================================================

"""
    compute_modality_salience(modality::Symbol, features::Vector{Float32})::Float32

Compute salience for a specific modality using the central Attention system.
This ensures unified salience computation across all sensory modalities.
"""
function compute_modality_salience(modality::Symbol, features::Vector{Float32})::Float32
    # Create stimulus for attention system
    source = modality_to_source(modality)
    
    stimulus = Stimulus(
        modality,
        features,
        source,
        time(),
        mean(features)
    )
    
    # Compute salience using central Attention
    attention_state = AttentionState(max_focus=5)
    
    try
        return compute_salience(stimulus, attention_state.context)
    catch
        # Fallback to local computation
        return _compute_local_salience(features)
    end
end

"""
    modality_to_source(modality::Symbol)::Symbol

Map modality symbol to Attention source symbol.
"""
function modality_to_source(modality::Symbol)::Symbol
    return get(Dict(
        :vision => :visual,
        :audio => :auditory,
        :telemetry => :telemetry,
        :memory => :memory,
        :goal => :goal
    ), modality, :unknown)
end

"""
    _compute_local_salience(features::Vector{Float32})::Float32

Fallback local salience computation.
"""
function _compute_local_salience(features::Vector{Float32})::Float32
    if isempty(features)
        return 0.0f0
    end
    
    # Variance-based salience
    variance = var(features)
    intensity = mean(abs.(features))
    
    return clamp(variance * 5 + intensity * 0.5, 0.0f0, 1.0f0)
end

"""
    apply_attention_gating(perceptions::Dict{Symbol, Vector{Float32}},
                          saliences::Dict{Symbol, Float32},
                          threshold::Float32=0.3f0)::Dict{Symbol, Vector{Float32}}

Apply attention gating to perceptions. Low-salience modalities are gated out
(their features are zeroed) to prevent sensory bypass.
"""
function apply_attention_gating(perceptions::Dict{Symbol, Vector{Float32}},
                               saliences::Dict{Symbol, Float32},
                               threshold::Float32=0.3f0)::Dict{Symbol, Vector{Float32}}
    
    gated = Dict{Symbol, Vector{Float32}}()
    
    for (modality, features) in perceptions
        salience = get(saliences, modality, 0.0f0)
        
        if salience >= threshold
            # Apply gating: keep features but mark as gated by scaling
            gated[modality] = features
        else
            # Gate out: zero the features
            gated[modality] = zeros(Float32, length(features))
        end
    end
    
    return gated
end

"""
    gate_perception_by_attention(modality_perceptions::Dict{Symbol, Vector{Float32}};
                                  context::Vector{Float32}=Float32[])::Tuple{Dict{Symbol, Vector{Float32}}, Dict{Symbol, Float32}}

Apply attention-based gating to all modality perceptions.
Returns gated perceptions and computed saliences.
"""
function gate_perception_by_attention(modality_perceptions::Dict{Symbol, Vector{Float32}};
                                     context::Vector{Float32}=Float32[])::Tuple{Dict{Symbol, Vector{Float32}}, Dict{Symbol, Float32}}
    
    # Compute saliences for each modality
    saliences = Dict{Symbol, Float32}()
    for (modality, features) in modality_perceptions
        saliences[modality] = compute_modality_salience(modality, features)
    end
    
    # Apply attention gating
    gated = apply_attention_gating(modality_perceptions, saliences)
    
    return gated, saliences
end

"""
    default_multimodal_config()::MultimodalConfig

Get default multimodal configuration.
"""
function default_multimodal_config()::MultimodalConfig
    return MultimodalConfig()
end

# ============================================================================
# End of Module
# ============================================================================

end # module MultimodalIntegration