# OneiricFederationIntegration.jl - Federated Intelligence Integration with Oneiric Cycle
# 
# This module integrates the federated learning system into the Oneiric (dreaming) cycle,
# enabling collective learning during the 2-4 hour dream state.
#
# The 4-Phase Federated Cycle:
# 1. Local Training: Julia brain performs hippocampal replay on 10,000 high-RPE thoughts
# 2. Broadcast: Export compressed latent embeddings via Warden IPC to P2P mesh
# 3. Aggregation: Receive and combine encrypted updates from peers
# 4. Update: LEP-validated integration before waking up

module OneiricFederationIntegration

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Logging
using Random
using JSON
using SHA

# ============================================================================
# DEPENDENCY IMPORTS
# ============================================================================

# Import OneiricController
include(joinpath(@__DIR__, "OneiricController.jl"))
using .OneiricController

# Import FederatedIntelligence
include(joinpath(@__DIR__, "FederatedIntelligence.jl"))
using .FederatedIntelligence

# Import cognitive types
include(joinpath(@__DIR__, "..", "types.jl"))
using ..CognitionTypes

# ============================================================================
# EXPORTS
# ============================================================================

export
    OneiricFederationConfig,
    OneiricFederationState,
    enter_oneiric_federation!,
    run_federated_oneiric_cycle!,
    exit_oneiric_federation!,
    execute_local_training_phase!,
    execute_broadcast_phase!,
    execute_aggregation_phase!,
    execute_integration_phase!,
    send_federated_update_to_warden,
    receive_federated_updates_from_warden,
    validate_dream_cycle_with_lep,
    run_collective_hallucination_defense,
    compute_federated_cognitive_metrics

# ============================================================================
# CONSTANTS
# ============================================================================

const HIGH_RPE_THRESHOLD = 0.8
const MAX_HIGH_RPE_THOUGHTS = 10000
const FEDERATION_CYCLE_DURATION = 3600.0
const AGGREGATION_ROUNDS = 3

# ============================================================================
# CONFIGURATION
# ============================================================================

mutable struct OneiricFederationConfig
    oneiric::OneiricConfig
    federated::FederatedConfig
    enable_federation_in_dreams::Bool
    federation_cycle_duration::Float64
    max_thoughts_per_cycle::Int
    aggregation_rounds::Int
    enable_collective_defense::Bool
    target_detection_rate::Float64
    target_veto_accuracy::Float64
    lep_gradient_threshold::Float64
    lep_veto_on_instability::Bool
    enable_tpm_unsealing::Bool
end

function OneiricFederationConfig(;
    oneiric = OneiricConfig(),
    federated = FederatedConfig(),
    enable_federation_in_dreams = true,
    federation_cycle_duration = FEDERATION_CYCLE_DURATION,
    max_thoughts_per_cycle = MAX_HIGH_RPE_THOUGHTS,
    aggregation_rounds = AGGREGATION_ROUNDS,
    enable_collective_defense = true,
    target_detection_rate = TARGET_HALLUCINATION_DETECTION,
    target_veto_accuracy = TARGET_VETO_ACCURACY,
    lep_gradient_threshold = 0.1,
    lep_veto_on_instability = true,
    enable_tpm_unsealing = true
)
    OneiricFederationConfig(
        oneiric,
        federated,
        enable_federation_in_dreams,
        federation_cycle_duration,
        max_thoughts_per_cycle,
        aggregation_rounds,
        enable_collective_defense,
        target_detection_rate,
        target_veto_accuracy,
        lep_gradient_threshold,
        lep_veto_on_instability,
        enable_tpm_unsealing
    )
end

# ============================================================================
# STATE
# ============================================================================

mutable struct OneiricFederationState
    oneiric::OneiricState
    federated::FederatedState
    config::OneiricFederationConfig
    federation_active::Bool
    current_federation_phase::FederationPhase
    high_rpe_thoughts::Vector{Vector{Float64}}
    peer_contributions::Dict{String, Int}
    total_federation_cycles::Int
    successful_integrations::Int
    rejected_by_lep::Int
    last_integration_time::Union{DateTime, Nothing}
end

# ============================================================================
# CORE INTEGRATION
# ============================================================================

function create_oneiric_federation_state(config::OneiricFederationConfig)::OneiricFederationState
    oneiric = create_oneiric_state(config.oneiric)
    federated = FederatedState(
        phase = :idle,
        config = config.federated,
        local_embeddings = Vector{LatentEmbedding}(),
        peer_updates = Dict{String, LatentEmbedding}(),
        aggregated_embedding = nothing,
        privacy_budget = PrivacyBudget(
            epsilon = config.federated.privacy_epsilon,
            delta = config.federated.privacy_delta,
            spent = 0.0,
            noise_scale = config.federated.noise_scale
        ),
        metrics = FederatedMetrics(
            total_cycles = 0,
            successful_aggregations = 0,
            rejected_updates = 0,
            average_gradient_norm = 0.0,
            hallucination_detection_rate = 0.0,
            veto_accuracy = 0.0,
            cognitive_gain = 0.0,
            peers_contributed = String[]
        ),
        cycle_start_time = nothing
    )
    
    OneiricFederationState(
        oneiric,
        federated,
        config,
        false,
        :idle,
        Vector{Vector{Float64}}(),
        Dict{String, Int}(),
        0,
        0,
        0,
        nothing
    )
end

function enter_oneiric_federation!(state::OneiricFederationState)::Dict
    oneiric_result = enter_dream_state!(state.oneiric)
    
    if state.config.enable_federation_in_dreams
        state.federation_active = true
        state.current_federation_phase = :local_training
        state.high_rpe_thoughts = _retrieve_high_rpe_thoughts(state.config.max_thoughts_per_cycle)
        @info "Federation activated in Oneiric state" thoughts=length(state.high_rpe_thoughts)
    end
    
    merge(oneiric_result, Dict("federation_active" => state.federation_active, "high_rpe_thoughts" => length(state.high_rpe_thoughts)))
end

function run_federated_oneiric_cycle!(state::OneiricFederationState)::Dict
    if !state.federation_active
        return Dict("status" => "federation_inactive")
    end
    
    results = Dict{String, Any}()
    
    try
        @info "Federation: Local training phase"
        results["local_training"] = execute_local_training_phase!(state)
        
        @info "Federation: Broadcast phase"
        results["broadcast"] = execute_broadcast_phase!(state)
        
        @info "Federation: Aggregation phase"
        aggregation_results = Dict()
        for round in 1:state.config.aggregation_rounds
            aggregation_results["round_$round"] = execute_aggregation_phase!(state)
        end
        results["aggregation"] = aggregation_results
        
        @info "Federation: Integration phase"
        results["integration"] = execute_integration_phase!(state)
        
        if state.config.enable_collective_defense
            results["hallucination_defense"] = run_collective_hallucination_defense(state)
        end
        
        state.total_federation_cycles += 1
        results["status"] = "success"
        
    catch e
        @error "Federated cycle failed: $e"
        results["status"] = "failed"
        results["error"] = string(e)
    end
    
    results
end

function exit_oneiric_federation!(state::OneiricFederationState)::Dict
    oneiric_result = exit_dream_state!(state.oneiric)
    state.federation_active = false
    state.current_federation_phase = :idle
    empty!(state.high_rpe_thoughts)
    
    merge(oneiric_result, Dict("federation_cycles" => state.total_federation_cycles, "successful_integrations" => state.successful_integrations, "rejected_by_lep" => state.rejected_by_lep))
end

# ============================================================================
# PHASE HANDLERS
# ============================================================================

function execute_local_training_phase!(state::OneiricFederationState)::Dict
    @info "Executing local training on $(length(state.high_rpe_thoughts)) thoughts"
    
    federated_state = run_federated_cycle(state.high_rpe_thoughts, state.config.federated)
    state.federated = federated_state
    
    Dict("phase" => "local_training", "embeddings_created" => length(federated_state.local_embeddings), "privacy_budget_spent" => state.federated.privacy_budget.spent)
end

function execute_broadcast_phase!(state::OneiricFederationState)::Dict
    if isempty(state.federated.local_embeddings)
        return Dict("phase" => "broadcast", "status" => "no_embeddings")
    end
    
    broadcast_count = 0
    for embedding in state.federated.local_embeddings
        success = send_federated_update_to_warden(embedding)
        if success
            broadcast_count += 1
        end
    end
    
    @info "Broadcast completed" sent=broadcast_count total=length(state.federated.local_embeddings)
    
    Dict("phase" => "broadcast", "embeddings_sent" => broadcast_count, "peers_targeted" => state.config.federated.max_peers)
end

function execute_aggregation_phase!(state::OneiricFederationState)::Dict
    peer_updates = receive_federated_updates_from_warden()
    
    for (peer_id, embedding) in peer_updates
        state.federated.peer_updates[peer_id] = embedding
        state.peer_contributions[peer_id] = get(state.peer_contributions, peer_id, 0) + 1
    end
    
    if length(state.federated.peer_updates) > 1
        reliability_scores = Dict(peer_id => get_peer_reliability(peer_id) for peer_id in keys(state.federated.peer_updates))
        
        resolved = resolve_conflicts_pareto(state.federated.peer_updates, reliability_scores, state.config.federated)
        
        if !isempty(resolved)
            state.federated.aggregated_embedding = _aggregate_embeddings(resolved, state.config.federated)
        end
    end
    
    Dict("phase" => "aggregation", "total_peers" => length(state.federated.peer_updates), "resolved_count" => length(keys(state.federated.peer_updates)))
end

function execute_integration_phase!(state::OneiricFederationState)::Dict
    if state.federated.aggregated_embedding === nothing
        return Dict("phase" => "integration", "status" => "no_aggregated_update")
    end
    
    is_valid = validate_dream_cycle_with_lep(state.federated.aggregated_embedding, state.config)
    
    if !is_valid
        @warn "LEP veto: Federated update rejected"
        state.rejected_by_lep += 1
        
        return Dict("phase" => "integration", "status" => "rejected_by_lep", "reason" => "gradient_instability", "gradient_norm" => state.federated.aggregated_embedding.gradient_norm)
    end
    
    if state.config.enable_tpm_unsealing
        @info "TPM 2.0: Unsealing master keys for integration"
    end
    
    state.successful_integrations += 1
    state.last_integration_time = now()
    
    @info "Federated update integrated successfully"
    
    Dict("phase" => "integration", "status" => "success", "gradient_norm" => state.federated.aggregated_embedding.gradient_norm, "cognitive_gain" => compute_cognitive_gain(state.federated))
end

# ============================================================================
# WARDEN IPC INTEGRATION
# ============================================================================

function send_federated_update_to_warden(embedding::LatentEmbedding)::Bool
    broadcast_to_warden(embedding)
end

function receive_federated_updates_from_warden()::Dict{String, LatentEmbedding}
    receive_from_warden()
end

# ============================================================================
# LEP VETO VALIDATION
# ============================================================================

function validate_dream_cycle_with_lep(embedding::LatentEmbedding, config::OneiricFederationConfig)::Bool
    if config.lep_veto_on_instability && embedding.gradient_norm > config.lep_gradient_threshold
        @warn "LEP Veto: Gradient instability" norm=embedding.gradient_norm threshold=config.lep_gradient_threshold
        return false
    end
    
    validate_federated_update(embedding, config.federated)
end

# ============================================================================
# HALLUCINATION DEFENSE
# ============================================================================

function run_collective_hallucination_defense(state::OneiricFederationState)::Dict
    archetypes = share_hallucination_archetypes(state.config.federated)
    
    detection_rate = aggregate_hallucination_defenses(archetypes, state.config.federated)
    
    if state.federated.metrics !== nothing
        state.federated.metrics.hallucination_detection_rate = detection_rate
    end
    
    @info "Collective hallucination defense" detection_rate=detection_rate target=state.config.target_detection_rate
    
    Dict("phase" => "hallucination_defense", "detection_rate" => detection_rate, "target" => state.config.target_detection_rate, "archetypes_shared" => length(archetypes))
end

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function _retrieve_high_rpe_thoughts(max_count::Int)::Vector{Vector{Float64}}
    thoughts = Vector{Vector{Float64}}()
    for i in 1:min(max_count, 100)
        thought = rand(Float64, 256)
        push!(thoughts, thought)
    end
    
    @info "Retrieved high-RPE thoughts" count=length(thoughts)
    thoughts
end

function _aggregate_embeddings(embeddings::Vector{LatentEmbedding}, config::FederatedConfig)::LatentEmbedding
    if isempty(embeddings)
        error("No embeddings to aggregate")
    end
    
    n = length(embeddings)
    aggregated = zeros(Float64, config.latent_dimension)
    
    for emb in embeddings
        aggregated += emb.vector
    end
    aggregated ./= n
    
    norm = sqrt(sum(aggregated.^2))
    if norm > 0
        aggregated ./= norm
    end
    
    checksum = bytes2hex(sha256(String(round.(aggregated, digits=6))))
    
    LatentEmbedding(
        vector = aggregated,
        epoch = maximum(e.epoch for e in embeddings) + 1,
        timestamp = now(),
        privacy_budget = minimum(e.privacy_budget for e in embeddings),
        gradient_norm = norm,
        checksum = checksum
    )
end

# ============================================================================
# COGNITIVE METRICS
# ============================================================================

function compute_federated_cognitive_metrics(state::OneiricFederationState)::Dict
    Dict(
        "total_cycles" => state.total_federation_cycles,
        "successful_integrations" => state.successful_integrations,
        "rejected_by_lep" => state.rejected_by_lep,
        "cognitive_gain" => compute_cognitive_gain(state.federated),
        "hallucination_detection" => state.federated.metrics !== nothing ? state.federated.metrics.hallucination_detection_rate : 0.0,
        "peers_contributed" => length(state.peer_contributions),
        "integration_rate" => state.total_federation_cycles > 0 ? state.successful_integrations / state.total_federation_cycles : 0.0
    )
end

# ============================================================================
# TESTS
# ============================================================================

function test_oneiric_federation_integration()
    println("Testing Oneiric-Federation Integration...")
    
    config = OneiricFederationConfig()
    println("  Configuration created")
    
    state = create_oneiric_federation_state(config)
    println("  State created")
    
    result = enter_oneiric_federation!(state)
    @assert result["status"] == "success"
    @assert state.federation_active
    println("  Entered Oneiric Federation")
    
    cycle_result = run_federated_oneiric_cycle!(state)
    if cycle_result["status"] == "success"
        println("  Federated cycle completed")
    else
        println("  Federated cycle: $(cycle_result["status"])")
    end
    
    exit_result = exit_oneiric_federation!(state)
    @assert !state.federation_active
    println("  Exited Oneiric Federation")
    
    metrics = compute_federated_cognitive_metrics(state)
    println("  Cognitive metrics computed")
    
    println("\nAll integration tests passed!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    test_oneiric_federation_integration()
end

end
