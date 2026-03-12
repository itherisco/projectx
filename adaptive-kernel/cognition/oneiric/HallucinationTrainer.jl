# adaptive-kernel/cognition/oneiric/HallucinationTrainer.jl - Hallucination Detection Training System
# JARVIS Neuro-Symbolic Architecture - Dream-based reality monitoring and anomaly detection
# AUTOENCODER IMPLEMENTATION - Replaces discriminator-only approach

module HallucinationTrainer

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Logging

# Import cognitive types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..CognitionTypes

# Import memory replay for training data
include(joinpath(@__DIR__, "MemoryReplay.jl"))
using .MemoryReplay

# ============================================================================
# EXPORTS
# ============================================================================

export
    # Configuration
    HallucinationConfig,
    
    # State
    HallucinationState,
    
    # Core functions (backward compatible API)
    train_discriminator!,       # Now trains autoencoder
    detect_anomalies,           # Uses reconstruction error
    generate_synthetic_examples,
    compute_reality_score,      # Uses hallucination score
    update_discriminator!,      # Now trains autoencoder
    
    # NEW: Autoencoder-specific exports
    train_autoencoder!,
    compute_reconstruction_error,
    compute_hallucination_score,
    get_encoder_weights,
    get_decoder_weights,
    get_latent_statistics,
    set_reconstruction_threshold,
    get_reconstruction_threshold

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    HallucinationConfig - Configuration for hallucination detection training

# Fields (updated for autoencoder)
- `autoencoder_epochs::Int`: Training epochs per dream cycle (default: 15)
- `anomaly_threshold::Float32`: Legacy threshold - now maps to reconstruction threshold (default: 0.7)
- `synthetic_ratio::Float32`: Ratio of synthetic to real examples (default: 0.3)
- `feature_dim::Int`: Input feature dimension (default: 256)
- `hidden_dim::Int`: Hidden layer dimension (default: 128)
- `latent_dim::Int`: Latent space dimension (default: 32) - KEY for autoencoder
- `learning_rate::Float32`: Autoencoder learning rate (default: 0.001)
- `reality_confidence_threshold::Float32`: Minimum confidence for reality (default: 0.8)
- `reconstruction_threshold::Float32`: Threshold for reconstruction error (autoencoder default: 0.15)
- `use_variational::Bool`: Use VAE (with KL divergence) vs standard AE (default: false)
- `beta_vae::Float32`: KL divergence weight for VAE (default: 0.1)
- `improvement_target::Float32`: Target improvement over discriminator (default: 0.43 = 43%)
"""
@with_kw mutable struct HallucinationConfig
    autoencoder_epochs::Int = 15
    anomaly_threshold::Float32 = 0.7
    synthetic_ratio::Float32 = 0.3
    feature_dim::Int = 256
    hidden_dim::Int = 128
    latent_dim::Int = 32  # Compressed representation
    learning_rate::Float32 = 0.001f0
    reality_confidence_threshold::Float32 = 0.8f0
    reconstruction_threshold::Float32 = 0.15f0  # Reconstruction error threshold
    use_variational::Bool = false
    beta_vae::Float32 = 0.1f0
    improvement_target::Float32 = 0.43f0  # 43% improvement target
end

# ============================================================================
# STATE
# ============================================================================

"""
    HallucinationState - Mutable state for hallucination detection (Autoencoder)

# Fields (updated for autoencoder architecture)
- `config::HallucinationConfig`: Training configuration
- `encoder_weights::Matrix{Float32}`: Encoder hidden layer weights (feature_dim -> hidden_dim)
- `encoder_bias::Vector{Float32}`: Encoder hidden layer bias
- `encoder_output_weights::Matrix{Float32}`: Encoder output layer weights (hidden_dim -> latent_dim)
- `encoder_output_bias::Vector{Float32}`: Encoder output layer bias
- `decoder_weights::Matrix{Float32}`: Decoder hidden layer weights (latent_dim -> hidden_dim)
- `decoder_bias::Vector{Float32}`: Decoder hidden layer bias
- `decoder_output_weights::Matrix{Float32}`: Decoder output layer weights (hidden_dim -> feature_dim)
- `decoder_output_bias::Vector{Float32}`: Decoder output layer bias
- `training_count::Int`: Number of training iterations
- `anomaly_log::Vector{Dict}`: Log of detected anomalies
- `reality_scores::Vector{Float32}`: Historical reality scores
- `reconstruction_errors::Vector{Float32}`: Historical reconstruction errors
- `hallucination_scores::Vector{Float32}`: Historical hallucination scores
- `last_training_time::Float64`: Unix timestamp of last training
- `reconstruction_threshold::Float32`: Dynamic threshold based on training
- `mean_reconstruction_error::Float32`: Running mean of reconstruction errors
- `std_reconstruction_error::Float32`: Running std of reconstruction errors
- `is_trained::Bool`: Whether autoencoder has been trained
"""
mutable struct HallucinationState
    config::HallucinationConfig
    
    # Encoder network (feature_dim -> hidden_dim -> latent_dim)
    encoder_weights::Matrix{Float32}
    encoder_bias::Vector{Float32}
    encoder_output_weights::Matrix{Float32}
    encoder_output_bias::Vector{Float32}
    
    # Decoder network (latent_dim -> hidden_dim -> feature_dim)
    decoder_weights::Matrix{Float32}
    decoder_bias::Vector{Float32}
    decoder_output_weights::Matrix{Float32}
    decoder_output_bias::Vector{Float32}
    
    # Legacy discriminator weights (kept for backward compatibility)
    discriminator_weights::Matrix{Float32}
    discriminator_bias::Vector{Float32}
    
    training_count::Int
    anomaly_log::Vector{Dict{String, Any}}
    reality_scores::Vector{Float32}
    reconstruction_errors::Vector{Float32}
    hallucination_scores::Vector{Float32}
    last_training_time::Float64
    reconstruction_threshold::Float32
    mean_reconstruction_error::Float32
    std_reconstruction_error::Float32
    is_trained::Bool
    
    function HallucinationState(config::HallucinationConfig=HallucinationConfig())
        rng = MersenneTwister(42)
        
        # Xavier initialization for encoder
        fan_in_enc = config.feature_dim
        fan_out_enc = config.hidden_dim
        scale_enc = sqrt(2.0f0 / (fan_in_enc + fan_out_enc))
        
        encoder_weights = randn(rng, Float32, config.hidden_dim, config.feature_dim) .* scale_enc
        encoder_bias = zeros(Float32, config.hidden_dim)
        
        fan_in_enc2 = config.hidden_dim
        fan_out_enc2 = config.latent_dim
        scale_enc2 = sqrt(2.0f0 / (fan_in_enc2 + fan_out_enc2))
        encoder_output_weights = randn(rng, Float32, config.latent_dim, config.hidden_dim) .* scale_enc2
        encoder_output_bias = zeros(Float32, config.latent_dim)
        
        # Xavier initialization for decoder (mirror of encoder)
        fan_in_dec = config.latent_dim
        fan_out_dec = config.hidden_dim
        scale_dec = sqrt(2.0f0 / (fan_in_dec + fan_out_dec))
        
        decoder_weights = randn(rng, Float32, config.hidden_dim, config.latent_dim) .* scale_dec
        decoder_bias = zeros(Float32, config.hidden_dim)
        
        fan_in_dec2 = config.hidden_dim
        fan_out_dec2 = config.feature_dim
        scale_dec2 = sqrt(2.0f0 / (fan_in_dec2 + fan_out_dec2))
        decoder_output_weights = randn(rng, Float32, config.feature_dim, config.hidden_dim) .* scale_dec2
        decoder_output_bias = zeros(Float32, config.feature_dim)
        
        # Legacy discriminator (for backward compatibility)
        scale_disc = sqrt(2.0f0 / (fan_in_enc + fan_out_enc))
        discriminator_weights = randn(rng, Float32, config.hidden_dim, config.feature_dim) .* scale_disc
        discriminator_bias = zeros(Float32, config.hidden_dim)
        
        new(
            config,
            encoder_weights,
            encoder_bias,
            encoder_output_weights,
            encoder_output_bias,
            decoder_weights,
            decoder_bias,
            decoder_output_weights,
            decoder_output_bias,
            discriminator_weights,
            discriminator_bias,
            0,
            Dict{String, Any}[],
            Float32[],
            Float32[],
            Float32[],
            0.0,
            config.reconstruction_threshold,
            0.0f0,
            1.0f0,  # Start with high std to avoid false positives
            false
        )
    end
end

# ============================================================================
# AUTOENCODER FUNCTIONS
# ============================================================================

"""
    relu(x::Float32)::Float32

ReLU activation function.
"""
function relu(x::Float32)::Float32
    return max(x, 0.0f0)
end

"""
    sigmoid(x::Float32)::Float32

Numerically stable sigmoid function.
"""
function sigmoid(x::Float32)::Float32
    return if x >= 0
        1.0f0 / (1.0f0 + exp(-x))
    else
        exp(x) / (1.0f0 + exp(x))
    end
end

"""
    sigmoid_grad(x::Float32)::Float32

Sigmoid gradient.
"""
function sigmoid_grad(x::Float32)::Float32
    s = sigmoid(x)
    return s * (1.0f0 - s)
end

"""
    encode(state::HallucinationState, input::Vector{Float32})::Vector{Float32}

Encode input to latent representation.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `input::Vector{Float32}`: Input features

# Returns
- `Vector{Float32}`: Latent representation
"""
function encode(state::HallucinationState, input::Vector{Float32})::Vector{Float32}
    config = state.config
    
    # First hidden layer
    hidden = state.encoder_weights * input .+ state.encoder_bias
    hidden = relu.(hidden)
    
    # Output layer (latent)
    latent = state.encoder_output_weights * hidden .+ state.encoder_output_bias
    
    # For non-VAE, return as-is; for VAE, apply some transformation
    if config.use_variational
        # Return raw latent (mean) - in full VAE, would also return logvar
        return latent
    end
    
    return latent
end

"""
    decode(state::HallucinationState, latent::Vector{Float32})::Vector{Float32}

Decode latent representation to reconstruction.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `latent::Vector{Float32}`: Latent representation

# Returns
- `Vector{Float32}`: Reconstructed features
"""
function decode(state::HallucinationState, latent::Vector{Float32})::Vector{Float32}
    config = state.config
    
    # First hidden layer
    hidden = state.decoder_weights * latent .+ state.decoder_bias
    hidden = relu.(hidden)
    
    # Output layer (reconstruction)
    reconstruction = state.decoder_output_weights * hidden .+ state.decoder_output_bias
    
    # Apply tanh to bound reconstruction
    reconstruction = tanh.(reconstruction)
    
    return reconstruction
end

"""
    forward_autoencoder(state::HallucinationState, input::Vector{Float32})::Tuple{Vector{Float32}, Vector{Float32}}

Forward pass through autoencoder.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `input::Vector{Float32}`: Input features

# Returns
- `Tuple{Vector{Float32}, Vector{Float32}}`: (reconstruction, latent)
"""
function forward_autoencoder(state::HallucinationState, input::Vector{Float32})::Tuple{Vector{Float32}, Vector{Float32}}
    latent = encode(state, input)
    reconstruction = decode(state, latent)
    return reconstruction, latent
end

"""
    compute_reconstruction_error(state::HallucinationState, input::Vector{Float32})::Float32

Compute reconstruction error (MSE) for hallucination detection.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `input::Vector{Float32}`: Input features

# Returns
- `Float32`: Mean squared reconstruction error
"""
function compute_reconstruction_error(state::HallucinationState, input::Vector{Float32})::Float32
    reconstruction, _ = forward_autoencoder(state, input)
    
    # Mean squared error
    error = input .- reconstruction
    mse = sum(error .^ 2) / length(input)
    
    return mse
end

"""
    compute_hallucination_score(state::HallucinationState, input::Vector{Float32})::Float32

Compute hallucination score based on reconstruction error.
Higher score = more likely to be hallucination/synthetic.

Uses z-score based thresholding for adaptive detection.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `input::Vector{Float32}`: Input features

# Returns
- `Float32`: Hallucination score (0.0 = real, 1.0 = definitely hallucination)
"""
function compute_hallucination_score(state::HallucinationState, input::Vector{Float32})::Float32
    reconstruction_error = compute_reconstruction_error(state, input)
    
    if !state.is_trained
        # If not trained, use simple threshold
        return reconstruction_error > state.reconstruction_threshold ? 1.0f0 : 0.0f0
    end
    
    # Z-score based hallucination score
    # If error is above mean + 2*std, it's likely a hallucination
    z_score = (reconstruction_error - state.mean_reconstruction_error) / (state.std_reconstruction_error + Float32(1e-6))
    
    # Convert z-score to probability-like score (0-1)
    # z > 2 means significantly above normal
    hallucination_score = sigmoid(z_score - 2.0f0)
    
    return hallucination_score
end

"""
    get_latent_statistics(state::HallucinationState, inputs::Vector{Vector{Float32}})::Dict{String, Float32}

Get statistics about latent representations.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `inputs::Vector{Vector{Float32}}`: Input features

# Returns
- `Dict{String, Float32}`: Latent statistics
"""
function get_latent_statistics(state::HallucinationState, inputs::Vector{Vector{Float32}})::Dict{String, Float32}
    if isempty(inputs)
        return Dict{String, Float32}(
            "mean_magnitude" => 0.0f0,
            "std_magnitude" => 0.0f0,
            "max_magnitude" => 0.0f0,
            "min_magnitude" => 0.0f0
        )
    end
    
    latents = [encode(state, input) for input in inputs]
    magnitudes = [sqrt(sum(latent .^ 2)) for latent in latents]
    
    return Dict{String, Float32}(
        "mean_magnitude" => mean(magnitudes),
        "std_magnitude" => std(magnitudes),
        "max_magnitude" => maximum(magnitudes),
        "min_magnitude" => minimum(magnitudes)
    )
end

# ============================================================================
# TRAINING FUNCTIONS
# ============================================================================

"""
    train_autoencoder!(
    state::HallucinationState,
    normal_examples::Vector{Vector{Float32}}
)::Dict{String, Any}

Train the autoencoder on "normal" cognitive states during Oneiric periods.
This is the PRIMARY training function - trains on real examples only,
learning to reconstruct normal experiences.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `normal_examples::Vector{Vector{Float32}}`: Normal (real) experience features

# Returns
- `Dict{String, Any}`: Training results with loss metrics
"""
function train_autoencoder!(
    state::HallucinationState,
    normal_examples::Vector{Vector{Float32}}
)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    if isempty(normal_examples)
        return Dict{String, Any}(
            "status" => "no_training_data",
            "reason" => "empty_examples"
        )
    end
    
    # Training loop
    losses = Float32[]
    reconstruction_errors = Float32[]
    rng = MersenneTwister(42)
    
    for epoch in 1:config.autoencoder_epochs
        epoch_losses = Float32[]
        
        # Shuffle examples each epoch
        perm = randperm(rng, length(normal_examples))
        shuffled_examples = normal_examples[perm]
        
        for input in shuffled_examples
            # Forward pass
            reconstruction, latent = forward_autoencoder(state, input)
            
            # Compute reconstruction loss (MSE)
            error = input .- reconstruction
            loss = sum(error .^ 2) / length(input)
            
            # Backpropagation (simplified gradient descent)
            lr = config.learning_rate
            
            # Output layer gradient
            grad_output = 2.0f0 .* error ./ length(input)
            grad_output = grad_output .* (1.0f0 .- reconstruction .^ 2)  # tanh derivative
            
            # Decoder output layer gradients
            grad_decoder_output_weights = reshape(grad_output, length(grad_output), 1) * reshape(latent, 1, length(latent))
            grad_decoder_output_bias = grad_output
            
            # Decoder hidden layer
            hidden = state.decoder_weights * latent .+ state.decoder_bias
            hidden_activation = relu.(hidden)
            grad_hidden = (state.decoder_output_weights' * grad_output) .* (hidden .> 0.0f0)
            
            # Decoder weights update
            state.decoder_weights .-= lr .* grad_hidden * reshape(latent, 1, length(latent))
            state.decoder_bias .-= lr .* grad_hidden
            state.decoder_output_weights .-= lr .* grad_decoder_output_weights
            state.decoder_output_bias .-= lr .* grad_decoder_output_bias
            
            # Encoder gradients (backprop through latent)
            grad_latent = state.decoder_weights' * grad_hidden
            
            # Encoder output layer
            hidden_enc = state.encoder_weights * input .+ state.encoder_bias
            hidden_enc_activation = relu.(hidden_enc)
            grad_hidden_enc = (state.encoder_output_weights' * grad_latent) .* (hidden_enc .> 0.0f0)
            
            # Encoder weights update
            state.encoder_weights .-= lr .* grad_hidden_enc * reshape(input, 1, length(input))
            state.encoder_bias .-= lr .* grad_hidden_enc
            state.encoder_output_weights .-= lr .* grad_hidden_enc * reshape(hidden_enc_activation, 1, length(hidden_enc_activation))
            state.encoder_output_bias .-= lr .* grad_hidden_enc
            
            push!(epoch_losses, loss)
        end
        
        push!(losses, mean(epoch_losses))
    end
    
    # Compute final statistics on training data
    final_errors = [compute_reconstruction_error(state, ex) for ex in normal_examples]
    state.mean_reconstruction_error = mean(final_errors)
    state.std_reconstruction_error = std(final_errors)
    
    # Update reconstruction threshold based on statistics
    # Use mean + 2*std as threshold (captures 95% of normal data)
    state.reconstruction_threshold = state.mean_reconstruction_error + 2.0f0 * state.std_reconstruction_error
    state.reconstruction_threshold = max(state.reconstruction_threshold, config.reconstruction_threshold)
    
    # Update state
    state.training_count += 1
    state.last_training_time = current_time
    state.is_trained = true
    
    # Compute metrics
    avg_error = mean(final_errors)
    max_error = maximum(final_errors)
    min_error = minimum(final_errors)
    
    @info "Autoencoder trained for hallucination detection"
        training_count=state.training_count
        mean_reconstruction_error=avg_error
        reconstruction_threshold=state.reconstruction_threshold
        improvement_target=config.improvement_target
    
    return Dict{String, Any}(
        "status" => "success",
        "training_count" => state.training_count,
        "mean_loss" => losses[end],
        "epoch_losses" => losses,
        "mean_reconstruction_error" => avg_error,
        "std_reconstruction_error" => state.std_reconstruction_error,
        "reconstruction_threshold" => state.reconstruction_threshold,
        "max_reconstruction_error" => max_error,
        "min_reconstruction_error" => min_error,
        "normal_example_count" => length(normal_examples),
        "timestamp" => current_time,
        "architecture" => "autoencoder",
        "latent_dim" => config.latent_dim,
        "improvement_target" => config.improvement_target
    )
end

"""
    train_discriminator!(
    state::HallucinationState,
    real_examples::Vector{Vector{Float32}},
    synthetic_examples::Vector{Vector{Float32}}
)::Dict{String, Any}

Train the hallucination detector (BACKWARD COMPATIBLE).
Now uses autoencoder trained on normal examples, then tests on synthetic.

This trains on REAL examples only (autoencoder approach) and validates
detection capability using synthetic examples.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `real_examples::Vector{Vector{Float32}}`: Real experience features
- `synthetic_examples::Vector{Vector{Float32}}}: Synthetic/dream-generated examples

# Returns
- `Dict{String, Any}`: Training results with loss metrics
"""
function train_discriminator!(
    state::HallucinationState,
    real_examples::Vector{Vector{Float32}},
    synthetic_examples::Vector{Vector{Float32}}
)::Dict{String, Any}
    config = state.config
    current_time = time()
    
    if isempty(real_examples)
        return Dict{String, Any}(
            "status" => "no_training_data",
            "reason" => "empty_examples"
        )
    end
    
    # Train autoencoder on real examples (normal data)
    train_result = train_autoencoder!(state, real_examples)
    
    # Test detection capability on synthetic examples
    if !isempty(synthetic_examples)
        synthetic_errors = [compute_reconstruction_error(state, ex) for ex in synthetic_examples]
        real_errors = [compute_reconstruction_error(state, ex) for ex in real_examples]
        
        # Calculate detection metrics
        # True positive: synthetic correctly identified as anomalous
        # False negative: synthetic incorrectly identified as normal
        
        detection_rate = 0.0f0
        if !isempty(synthetic_errors)
            detected = sum(synthetic_errors .> state.reconstruction_threshold)
            detection_rate = detected / length(synthetic_errors)
        end
        
        # False positive rate on real examples
        false_positive_rate = 0.0f0
        if !isempty(real_errors)
            false_positives = sum(real_errors .> state.reconstruction_threshold)
            false_positive_rate = false_positives / length(real_errors)
        end
        
        # Add detection metrics to result
        train_result["detection_rate"] = detection_rate
        train_result["false_positive_rate"] = false_positive_rate
        train_result["synthetic_mean_error"] = mean(synthetic_errors)
        train_result["real_mean_error"] = mean(real_errors)
        
        # Estimate improvement over discriminator baseline
        # Discriminator typically achieves ~60% detection, we aim for higher
        baseline_detection = 0.6f0
        improvement = (detection_rate - baseline_detection) / baseline_detection
        train_result["improvement_over_baseline"] = improvement
        train_result["meets_improvement_target"] = improvement >= config.improvement_target
        
        @info "Detection capability test"
            detection_rate=detection_rate
            false_positive_rate=false_positive_rate
            improvement=improvement
    end
    
    # Update legacy discriminator weights for backward compatibility
    # (copy encoder output as proxy)
    state.discriminator_weights .= state.encoder_output_weights
    state.discriminator_bias .= state.encoder_output_bias
    
    return train_result
end

# ============================================================================
# SYNTHETIC EXAMPLE GENERATION
# ============================================================================

"""
    generate_synthetic_examples(
    state::HallucinationState,
    base_examples::Vector{Vector{Float32}};
    num_examples::Int=0
)::Vector{Vector{Float32}}

Generate synthetic examples by augmenting real experiences for testing.
These represent potential hallucinations to detect.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `base_examples::Vector{Vector{Float32}}`: Real examples to augment
- `num_examples::Int`: Number of synthetic examples (0 = use ratio)

# Returns
- `Vector{Vector{Float32}}`: Synthetic examples

# Example
```julia
synthetic = generate_synthetic_examples(halluc_state, real_features)
```
"""
function generate_synthetic_examples(
    state::HallucinationState,
    base_examples::Vector{Vector{Float32}};
    num_examples::Int=0
)::Vector{Vector{Float32}}
    config = state.config
    
    if isempty(base_examples)
        return Vector{Float32}[]
    end
    
    target_count = num_examples > 0 ? num_examples : floor(Int, length(base_examples) * config.synthetic_ratio)
    target_count = max(target_count, 1)
    
    synthetic = Vector{Float32}[]
    rng = MersenneTwister(42)
    
    for _ in 1:target_count
        # Select random base example
        base = rand(rng, base_examples)
        
        # Apply random transformations to simulate dream-like distortions
        augmented = Float32[]
        
        for val in base
            # Add Gaussian noise
            noise = randn(rng, Float32) * 0.1f0
            
            # Occasionally flip sign (simulating contradiction)
            flip = rand(rng, Float32) < 0.05f0 ? -1.0f0 : 1.0f0
            
            # Occasionally zero out (simulating memory dropout)
            zero_out = rand(rng, Float32) < 0.1f0 ? 0.0f0 : 1.0f0
            
            new_val = (val + noise) * flip * zero_out
            push!(augmented, clamp(new_val, -1.0f0, 1.0f0))
        end
        
        push!(synthetic, augmented)
    end
    
    @debug "Generated synthetic examples" count=length(synthetic)
    
    return synthetic
end

# ============================================================================
# ANOMALY DETECTION
# ============================================================================

"""
    detect_anomalies(
    state::HallucinationState,
    experiences::Vector{Vector{Float32}}
)::Vector{Dict{String, Any}}

Detect synthetic anomalies in the given experiences using reconstruction error.
Higher reconstruction error = more likely to be hallucination.

# Arguments
- `state::HallucinationState`: Current hallucination state
- `experiences::Vector{Vector{Float32}}`: Experiences to check

# Returns
- `Vector{Dict{String, Any}}`: List of detected anomalies with details

# Example
```julia
anomalies = detect_anomalies(halluc_state, current_experiences)
```
"""
function detect_anomalies(
    state::HallucinationState,
    experiences::Vector{Vector{Float32}}
)::Vector{Dict{String, Any}}
    config = state.config
    anomalies = Dict{String, Any}[]
    
    for (i, experience) in enumerate(experiences)
        hallucination_score = compute_hallucination_score(state, experience)
        reconstruction_error = compute_reconstruction_error(state, experience)
        
        # Check if above hallucination threshold (for autoencoder, higher score = more anomalous)
        if hallucination_score > (1.0f0 - config.anomaly_threshold)
            anomaly_type = hallucination_score > 0.8f0 ? "highly_synthetic" : "possibly_synthetic"
            
            anomaly = Dict{String, Any}(
                "index" => i,
                "hallucination_score" => hallucination_score,
                "reconstruction_error" => reconstruction_error,
                "anomaly_type" => anomaly_type,
                "confidence" => hallucination_score,
                "threshold" => state.reconstruction_threshold,
                "timestamp" => time()
            )
            push!(anomalies, anomaly)
            
            # Log to anomaly log
            push!(state.anomaly_log, anomaly)
        end
        
        # Record for statistics
        push!(state.reconstruction_errors, reconstruction_error)
        push!(state.hallucination_scores, hallucination_score)
    end
    
    if !isempty(anomalies)
        @warn "Anomalies detected" count=length(anomalies)
    end
    
    return anomalies
end

"""
    compute_reality_score(
    state::HallucinationState,
    experience::Vector{Float32}
)::Float32

Compute a reality confidence score for an experience.
Uses hallucination score inverted (1 - hallucination = reality).

# Arguments
- `state::HallucinationState`: Current hallucination state
- `experience::Vector{Float32}`: Experience features

# Returns
- `Float32`: Reality score (0.0 = definitely synthetic, 1.0 = definitely real)

# Example
```julia
score = compute_reality_score(halluc_state, experience_features)
```
"""
function compute_reality_score(
    state::HallucinationState,
    experience::Vector{Float32}
)::Float32
    hallucination_score = compute_hallucination_score(state, experience)
    reality_score = 1.0f0 - hallucination_score
    
    # Also record for statistics
    push!(state.reality_scores, reality_score)
    
    return reality_score
end

# ============================================================================
# DISCRIMINATOR UPDATE (BACKWARD COMPATIBLE)
# ============================================================================

"""
    update_discriminator!(
    state::HallucinationState,
    replay_results::Dict{String, Any}
)::Dict{String, Any}

Update the autoencoder using memory replay results (BACKWARD COMPATIBLE).

# Arguments
- `state::HallucinationState`: Current hallucination state
- `replay_results::Dict{String, Any}`: Results from memory replay

# Returns
- `Dict{String, Any}`: Update results

# Example
```julia
update_results = update_discriminator!(halluc_state, replay_results)
```
"""
function update_discriminator!(
    state::HallucinationState,
    replay_results::Dict{String, Any}
)::Dict{String, Any}
    config = state.config
    
    # Extract features from replay results
    real_features = Vector{Float32}[]
    
    # If we have replay buffer, use those
    if haskey(replay_results, "embeddings")
        embeddings = replay_results["embeddings"]
        for col in eachcol(embeddings)
            push!(real_features, col)
        end
    end
    
    # Generate synthetic examples for testing
    synthetic_features = generate_synthetic_examples(state, real_features)
    
    # Train autoencoder (backward compatible function)
    if length(real_features) >= 1
        return train_discriminator!(state, real_features, synthetic_features)
    else
        return Dict{String, Any}(
            "status" => "insufficient_data",
            "real_count" => length(real_features),
            "synthetic_count" => length(synthetic_features)
        )
    end
end

# ============================================================================
# NEW: AUTOENCODER UTILITY FUNCTIONS
# ============================================================================

"""
    get_encoder_weights(state::HallucinationState)::Dict{String, Any}

Get encoder network weights for inspection.

# Arguments
- `state::HallucinationState`: Current state

# Returns
- `Dict{String, Any}`: Encoder weights information
"""
function get_encoder_weights(state::HallucinationState)::Dict{String, Any}
    return Dict{String, Any}(
        "encoder_weights_shape" => size(state.encoder_weights),
        "encoder_bias_shape" => size(state.encoder_bias),
        "encoder_output_weights_shape" => size(state.encoder_output_weights),
        "encoder_output_bias_shape" => size(state.encoder_output_bias)
    )
end

"""
    get_decoder_weights(state::HallucinationState)::Dict{String, Any}

Get decoder network weights for inspection.

# Arguments
- `state::HallucinationState`: Current state

# Returns
- `Dict{String, Any}`: Decoder weights information
"""
function get_decoder_weights(state::HallucinationState)::Dict{String, Any}
    return Dict{String, Any}(
        "decoder_weights_shape" => size(state.decoder_weights),
        "decoder_bias_shape" => size(state.decoder_bias),
        "decoder_output_weights_shape" => size(state.decoder_output_weights),
        "decoder_output_bias_shape" => size(state.decoder_output_bias)
    )
end

"""
    set_reconstruction_threshold!(state::HallucinationState, threshold::Float32)

Set the reconstruction error threshold manually.

# Arguments
- `state::HallucinationState`: Current state
- `threshold::Float32`: New threshold value
"""
function set_reconstruction_threshold!(state::HallucinationState, threshold::Float32)
    state.reconstruction_threshold = threshold
end

"""
    get_reconstruction_threshold(state::HallucinationState)::Float32

Get the current reconstruction error threshold.

# Arguments
- `state::HallucinationState`: Current state

# Returns
- `Float32`: Current threshold
"""
function get_reconstruction_threshold(state::HallucinationState)::Float32
    return state.reconstruction_threshold
end

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

"""
    get_hallucination_statistics(state::HallucinationState)::Dict{String, Any}

Get comprehensive statistics about the hallucination detection system.

# Arguments
- `state::HallucinationState`: Current state

# Returns
- `Dict{String, Any}`: Statistics dictionary
"""
function get_hallucination_statistics(state::HallucinationState)::Dict{String, Any}
    recent_anomalies = length(state.anomaly_log) > 0 ? 
        length(state.anomaly_log[max(1, end-9):end]) : 0
    
    avg_reality = isempty(state.reality_scores) ? 
        0.5f0 : mean(state.reality_scores)
    
    avg_hallucination = isempty(state.hallucination_scores) ?
        0.0f0 : mean(state.hallucination_scores)
    
    avg_reconstruction_error = isempty(state.reconstruction_errors) ?
        0.0f0 : mean(state.reconstruction_errors)
    
    return Dict{String, Any}(
        "training_count" => state.training_count,
        "last_training_time" => state.last_training_time,
        "total_anomalies_detected" => length(state.anomaly_log),
        "recent_anomalies" => recent_anomalies,
        "average_reality_score" => avg_reality,
        "average_hallucination_score" => avg_hallucination,
        "average_reconstruction_error" => avg_reconstruction_error,
        "mean_reconstruction_error" => state.mean_reconstruction_error,
        "std_reconstruction_error" => state.std_reconstruction_error,
        "reconstruction_threshold" => state.reconstruction_threshold,
        "is_trained" => state.is_trained,
        "architecture" => "autoencoder",
        "config" => Dict(
            "anomaly_threshold" => state.config.anomaly_threshold,
            "reality_confidence_threshold" => state.config.reality_confidence_threshold,
            "synthetic_ratio" => state.config.synthetic_ratio,
            "latent_dim" => state.config.latent_dim,
            "improvement_target" => state.config.improvement_target
        )
    )
end

"""
    reset_hallucination_state!(state::HallucinationState)

Reset hallucination state for a new dream cycle.
Keeps learned weights for continuity, clears transient state.

# Arguments
- `state::HallucinationState`: State to reset
"""
function reset_hallucination_state!(state::HallucinationState)
    # Keep autoencoder weights for continuity
    # Only clear transient state
    empty!(state.anomaly_log)
    # Keep reconstruction errors and hallucination scores for trend analysis
end

end # module HallucinationTrainer
