"""
# SensoryProcessing.jl

Continuous Sensory Processing (Component 2 of JARVIS Neuro-Symbolic Architecture)

This module implements streaming perception pipeline with attention gating for
managing sensory input from multiple sources (visual, auditory, telemetry).

## Integration Points:
- Input: Receives from system observation capabilities
- Output: Produces 12D unified_perception for Brain.jl BrainInput
- Attention: Feeds salience weights to Attention System (Component 5)
"""

module SensoryProcessing

using Base.Threads: @spawn
using LinearAlgebra
using Statistics

# =============================================================================
# Utility Functions
# =============================================================================

"""
    softmax(x::AbstractVector{T}) where T<:AbstractFloat

Compute softmax function for attention weights.
"""
function softmax(x::AbstractVector{T}) where T<:AbstractFloat
    # Subtract max for numerical stability
    x_shifted = x .- maximum(x)
    exp_x = exp.(x_shifted)
    return exp_x ./ sum(exp_x)
end

# =============================================================================
# Type Definitions
# =============================================================================

"""
    SensoryBuffer

Manages streaming data from multiple sensory channels with bounded memory.

#visual::Channel{ Fields
- `Vector{Float32}}`: Visual stream buffer
- `auditory::Channel{Vector{Float32}}`: Audio stream buffer  
- `telemetry::Channel{Vector{Float32}}`: System telemetry stream
- `event_queue::Channel{Any}`: Event-based processing queue
- `max_size::Int`: Maximum buffer size per channel
- `sampling_rate_hz::Float64`: Sampling rate in Hz
"""
mutable struct SensoryBuffer
    visual::Channel{Vector{Float32}}
    auditory::Channel{Vector{Float32}}
    telemetry::Channel{Vector{Float32}}
    event_queue::Channel{Any}
    max_size::Int
    sampling_rate_hz::Float64
    
    function SensoryBuffer(; max_size::Int=1000, sampling_rate_hz::Float64=10.0)
        new(
            Channel{Vector{Float32}}(max_size),
            Channel{Vector{Float32}}(max_size),
            Channel{Vector{Float32}}(max_size),
            Channel{Any}(max_size),
            max_size,
            sampling_rate_hz
        )
    end
end

"""
    SensoryInput

Unified input format for sensory data from all sources.

# Fields
- `visual_features::Vector{Float32}`: Extracted visual features
- `auditory_features::Vector{Float32}`: Extracted audio features
- `telemetry_features::Vector{Float32}`: System telemetry features
- `timestamp::Float64`: Unix timestamp of input
- `source::Symbol`: Source identifier`:camera`, `:microphone`, `:system`, `:user`)
"""
struct SensoryInput
    visual_features::Vector{Float32}
    auditory_features::Vector{Float32}
    telemetry_features::Vector{Float32}
    timestamp::Float64
    source::Symbol
end

"""
    ProcessedSensory

Output from preprocessing pipeline after attention gating and feature fusion.

# Fields
- `unified_perception::Vector{Float32}`: 12D vector for ITHERIS format
- `salience_weights::Vector{Float32}`: Attention allocation weights
- `novelty_score::Float32`: Novelty detection score [0.0, 1.0]
- `raw_streams::Dict{Symbol, Vector{Float32}}`: Raw stream data
- `timestamp::Float64`: Processing timestamp
"""
struct ProcessedSensory
    unified_perception::Vector{Float32}
    salience_weights::Vector{Float32}
    novelty_score::Float32
    raw_streams::Dict{Symbol, Vector{Float32}}
    timestamp::Float64
end

# =============================================================================
# Core Buffer Operations
# =============================================================================

"""
    push_sensory!(buffer::SensoryBuffer, input::SensoryInput)

Add sensory input to the appropriate channel based on source.
Handles backpressure with drop_oldest strategy.

# Arguments
- `buffer::SensoryBuffer`: The sensory buffer to push to
- `input::SensoryInput`: The sensory input to add

# Returns
- `Bool`: True if successfully added, false on failure
"""
function push_sensory!(buffer::SensoryBuffer, input::SensoryInput)
    channel = _get_channel(buffer, input.source)
    
    try
        # Non-blocking put with drop_oldest behavior on full channel
        if isready(channel)
            # Channel is full, drop oldest by taking one item
            try
                take!(channel)
            catch
                # Ignore if already taken
            end
        end
        put!(channel, _extract_features(input))
        return true
    catch e
        @warn "Failed to push sensory input: $e"
        return false
    end
end

"""
    push_sensory!(buffer::SensoryBuffer, source::Symbol, features::Vector{Float64})

Convenience method to push raw features with auto-generated timestamp.
"""
function push_sensory!(buffer::SensoryBuffer, source::Symbol, features::Vector{Float64})
    input = SensoryInput(
        source == :camera ? Float32.(features) : Float32[],
        source == :microphone ? Float32.(features) : Float32[],
        source == :system ? Float32.(features) : Float32[],
        time(),
        source
    )
    return push_sensory!(buffer, input)
end

# Internal helper to get the correct channel
function _get_channel(buffer::SensoryBuffer, source::Symbol)::Channel{Vector{Float32}}
    if source == :camera
        return buffer.visual
    elseif source == :microphone
        return buffer.auditory
    elseif source == :system
        return buffer.telemetry
    else
        return buffer.event_queue
    end
end

# Internal helper to extract features for storage
function _extract_features(input::SensoryInput)::Vector{Float32}
    if input.source == :camera
        return input.visual_features
    elseif input.source == :microphone
        return input.auditory_features
    elseif input.source == :system
        return input.telemetry_features
    else
        return vcat(input.visual_features, input.auditory_features, input.telemetry_features)
    end
end

# =============================================================================
# Backpressure Handling
# =============================================================================

"""
    handle_backpressure!(buffer::SensoryBuffer)

Handle backpressure by dropping oldest entries when channels are full.
Logs warnings for monitoring while maintaining throughput.

# Arguments
- `buffer::SensoryBuffer`: The sensory buffer to handle
"""
function handle_backpressure!(buffer::SensoryBuffer)
    dropped = 0
    
    for (name, channel) in [
        (:visual, buffer.visual),
        (:auditory, buffer.auditory),
        (:telemetry, buffer.telemetry)
    ]
        while isready(channel) && length(channel.data) >= buffer.max_size
            try
                take!(channel)
                dropped += 1
            catch
                break
            end
        end
    end
    
    if dropped > 0
        @warn "Backpressure: dropped $dropped oldest sensory entries"
    end
    
    return dropped
end

"""
    get_buffer_utilization(buffer::SensoryBuffer)

Get current buffer utilization percentages for all channels.

# Returns
- `Dict{Symbol, Float64}`: Utilization percentage for each channel
"""
function get_buffer_utilization(buffer::SensoryBuffer)::Dict{Symbol, Float64}
    return Dict(
        :visual => length(buffer.visual.data) / buffer.max_size * 100,
        :auditory => length(buffer.auditory.data) / buffer.max_size * 100,
        :telemetry => length(buffer.telemetry.data) / buffer.max_size * 100,
        :events => length(buffer.event_queue.data) / buffer.max_size * 100
    )
end

# =============================================================================
# Attention Gating
# =============================================================================

"""
    compute_attention_weights(
        visual::Vector{Float32},
        auditory::Vector{Float32},
        telemetry::Vector{Float32}
    )::Vector{Float32}

Compute relative importance weights for each sensory modality using
softmax normalization. This prevents sensory flooding by dynamically
allocating computational resources.

# Arguments
- `visual::Vector{Float32}`: Visual features (can be empty)
- `auditory::Vector{Float32}`: Auditory features (can be empty)
- `telemetry::Vector{Float32}`: Telemetry features (can be empty)

# Returns
- `Vector{Float32}`: 3-element weight vector [visual_weight, auditory_weight, telemetry_weight]
"""
function compute_attention_weights(
    visual::Vector{Float32},
    auditory::Vector{Float32},
    telemetry::Vector{Float32}
)::Vector{Float32}
    
    # Compute energy signals from each modality
    visual_energy = _compute_energy(visual)
    auditory_energy = _compute_energy(auditory)
    telemetry_energy = _compute_energy(telemetry)
    
    # Apply attention gating: prioritize non-zero inputs
    energies = [visual_energy, auditory_energy, telemetry_energy]
    
    # Add small epsilon to prevent numerical instability
    epsilon = 1e-6
    energies = energies .+ epsilon
    
    # Apply softmax for bounded, normalized weights
    weights = softmax(energies)
    
    return weights
end

# Internal helper to compute energy from feature vector
function _compute_energy(features::Vector{Float32})::Float32
    if isempty(features)
        # Zero-energy for empty streams - will get minimal attention
        return 0.0f0
    end
    # Use L2 norm as energy measure
    return sum(features .^ 2) / length(features)
end

# =============================================================================
# Main Processing Pipeline
# =============================================================================

"""
    preprocess_input(buffer::SensoryBuffer; attention_gate::Bool=true)::ProcessedSensory

Convert streaming sensory data to unified 12D ITHERIS perception format.
Applies sampling rate control and optional attention gating.

# Arguments
- `buffer::SensoryBuffer`: The sensory buffer to preprocess
- `attention_gate::Bool`: Whether to compute attention weights (default: true)

# Returns
- `ProcessedSensory`: Processed sensory output with unified perception

# ITHERIS 12D Format
- [1-4]: Visual features (4D)
- [5-8]: Auditory features (4D)  
- [9-12]: Telemetry features (4D)
"""
function preprocess_input(buffer::SensoryBuffer; attention_gate::Bool=true)::ProcessedSensory
    
    # Pull latest from each stream (non-blocking)
    visual_data = _pull_latest(buffer.visual)
    auditory_data = _pull_latest(buffer.auditory)
    telemetry_data = _pull_latest(buffer.telemetry)
    
    # Compute attention weights if enabled
    salience_weights = if attention_gate
        compute_attention_weights(visual_data, auditory_data, telemetry_data)
    else
        Float32[1/3, 1/3, 1/3]  # Equal weights when disabled
    end
    
    # Convert to unified 12D ITHERIS format
    unified = _to_itheris_format(visual_data, auditory_data, telemetry_data, salience_weights)
    
    # Store raw streams for potential later analysis
    raw_streams = Dict{Symbol, Vector{Float32}}(
        :visual => visual_data,
        :auditory => auditory_data,
        :telemetry => telemetry_data
    )
    
    timestamp = time()
    
    return ProcessedSensory(
        unified,
        salience_weights,
        0.0f0,  # Novelty score set to 0, updated by detect_novelty if needed
        raw_streams,
        timestamp
    )
end

# Internal helper to pull latest item from channel
function _pull_latest(channel::Channel{Vector{Float32}})::Vector{Float32}
    latest = Float32[]
    
    # Try to get latest without blocking
    while isready(channel)
        try
            latest = take!(channel)
        catch
            break
        end
    end
    
    return latest
end

# Convert to 12D ITHERIS format with attention weighting
function _to_itheris_format(
    visual::Vector{Float32},
    auditory::Vector{Float32},
    telemetry::Vector{Float32},
    weights::Vector{Float32}
)::Vector{Float32}
    
    # Target dimensions per modality
    local DIM_PER_MODALITY = 4
    local TOTAL_DIM = 12
    
    # Resize each modality to 4D using pooling
    visual_4d = _resize_to_4d(visual)
    auditory_4d = _resize_to_4d(auditory)
    telemetry_4d = _resize_to_4d(telemetry)
    
    # Apply attention weighting
    visual_weighted = visual_4d .* weights[1]
    auditory_weighted = auditory_4d .* weights[2]
    telemetry_weighted = telemetry_4d .* weights[3]
    
    # Concatenate to 12D
    unified = vcat(visual_weighted, auditory_weighted, telemetry_weighted)
    
    return unified
end

# Internal helper to resize feature vector to exactly 4 dimensions
function _resize_to_4d(features::Vector{Float32})::Vector{Float32}
    local TARGET_DIM = 4
    
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

# =============================================================================
# Novelty Detection
# =============================================================================

"""
    detect_novelty(current::ProcessedSensory, history::Vector{ProcessedSensory})::Float32

Detect novelty by comparing current perception to recent history using
cosine similarity. Higher scores indicate more novel input.

# Arguments
- `current::ProcessedSensory`: Current processed sensory
- `history::Vector{ProcessedSensory}`: Recent history for comparison

# Returns
- `Float32`: Novelty score in range [0.0, 1.0]
"""
function detect_novelty(current::ProcessedSensory, history::Vector{ProcessedSensory})::Float32
    if isempty(history)
        return 1.0f0  # First input is maximally novel
    end
    
    # Compare to last N entries in history
    local HISTORY_WINDOW = 5
    recent = history[max(1, end-HISTORY_WINDOW+1):end]
    
    if isempty(recent)
        return 1.0f0
    end
    
    # Compute average cosine similarity to recent history
    similarities = Float32[]
    
    for past in recent
        sim = _cosine_similarity(current.unified_perception, past.unified_perception)
        push!(similarities, sim)
    end
    
    avg_similarity = mean(similarities)
    
    # Convert similarity to novelty (1.0 - similarity)
    novelty = 1.0f0 - Float32(avg_similarity)
    
    # Clamp to [0, 1]
    return clamp(novelty, 0.0f0, 1.0f0)
end

# Internal cosine similarity helper
function _cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    if isempty(a) || isempty(b) || length(a) != length(b)
        return 0.0f0
    end
    
    dot_product = dot(a, b)
    norm_a = norm(a)
    norm_b = norm(b)
    
    if norm_a == 0 || norm_b == 0
        return 0.0f0
    end
    
    return Float32(dot_product / (norm_a * norm_b))
end

# =============================================================================
# Utility Functions
# =============================================================================

"""
    create_test_buffer(; max_size::Int=100, sampling_rate_hz::Float64=10.0)

Create a sensory buffer for testing purposes.
"""
function create_test_buffer(; max_size::Int=100, sampling_rate_hz::Float64=10.0)
    return SensoryBuffer(max_size=max_size, sampling_rate_hz=sampling_rate_hz)
end

"""
    create_test_input(; source::Symbol=:camera, feature_dim::Int=8)

Create a sensory input for testing.
"""
function create_test_input(; source::Symbol=:camera, feature_dim::Int=8)
    features = Float32.(rand(feature_dim))
    
    return SensoryInput(
        source == :camera ? features : Float32[],
        source == :microphone ? features : Float32[],
        source == :system ? features : Float32[],
        time(),
        source
    )
end

"""
    get_sample_rate_interval(buffer::SensoryBuffer)::Float64

Get the sampling interval in seconds based on configured rate.
"""
function get_sample_rate_interval(buffer::SensoryBuffer)::Float64
    return 1.0 / buffer.sampling_rate_hz
end

"""
    is_buffer_healthy(buffer::SensoryBuffer)::Bool

Check if buffer is operating within healthy parameters.
"""
function is_buffer_healthy(buffer::SensoryBuffer)::Bool
    utilization = get_buffer_utilization(buffer)
    
    for (_, util) in utilization
        if util > 95.0  # More than 95% full
            return false
        end
    end
    
    return true
end

# =============================================================================
# Export public API
# =============================================================================

export
    SensoryBuffer,
    SensoryInput,
    ProcessedSensory,
    push_sensory!,
    handle_backpressure!,
    get_buffer_utilization,
    compute_attention_weights,
    preprocess_input,
    detect_novelty,
    create_test_buffer,
    create_test_input,
    get_sample_rate_interval,
    is_buffer_healthy

end # module
