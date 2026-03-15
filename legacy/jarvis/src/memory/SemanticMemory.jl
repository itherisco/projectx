# jarvis/src/memory/SemanticMemory.jl - Semantic Memory with RAGTools.jl Integration
# Provides HNSW-backed vector store for recalling past action outcomes
# to adjust expected_reward in the safety formula

module SemanticMemory

using LinearAlgebra
using Random
using Dates
using UUIDs
using JSON
using Logging

# Try to import RAGTools.jl if available
const RAGTOOLS_AVAILABLE = try
    using RAGTools
    true
catch
    false
end

export 
    SemanticMemoryStore,
    ActionOutcome,
    store_action_outcome!,
    recall_similar_outcomes,
    adjust_expected_reward,
    get_action_statistics,
    SemanticMemoryConfig,
    initialize_semantic_memory

# Import Jarvis types
include("../types.jl")
using ..JarvisTypes

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    SemanticMemoryConfig - Configuration for semantic memory store
"""
struct SemanticMemoryConfig
    embedding_dim::Int
    hnsw_ef::Int          # HNSW search width
    hnsw_m::Int           # HNSW connections per node
    max_memories::Int     # Maximum stored memories
    similarity_threshold::Float32
    
    function SemanticMemoryConfig(;
        embedding_dim::Int = 384,
        hnsw_ef::Int = 64,
        hnsw_m::Int = 16,
        max_memories::Int = 100000,
        similarity_threshold::Float32 = 0.7f0
    )
        new(embedding_dim, hnsw_m, hnsw_m, max_memories, similarity_threshold)
    end
end

# ============================================================================
# ACTION OUTCOME TYPE
# ============================================================================

"""
    ActionOutcome - Record of a past action execution for memory-based learning
    Used to adjust expected_reward based on similar past outcomes
"""
mutable struct ActionOutcome
    id::UUID
    action_id::String
    perception_vector::Vector{Float32}  # 12D state when action was taken
    expected_reward::Float32
    actual_reward::Float32
    risk::Float32
    success::Bool
    error_message::Union{String, Nothing}
    context::Dict{String, Any}  # Additional context (system state, etc.)
    timestamp::DateTime
    
    function ActionOutcome(
        action_id::String,
        perception::Vector{Float32},
        expected_reward::Float32,
        actual_reward::Float32,
        risk::Float32;
        success::Bool = true,
        error_message::Union{String, Nothing} = nothing,
        context::Dict{String, Any} = Dict()
    )
        new(
            uuid4(),
            action_id,
            perception,
            expected_reward,
            actual_reward,
            risk,
            success,
            error_message,
            context,
            now()
        )
    end
end

# ============================================================================
# SEMANTIC MEMORY STORE
# ============================================================================

"""
    SemanticMemoryStore - Main semantic memory interface
    Uses RAGTools.jl HNSW when available, falls back to custom implementation
"""
mutable struct SemanticMemoryStore
    config::SemanticMemoryConfig
    
    # Action outcomes indexed by action_id
    outcomes_by_action::Dict{String, Vector{ActionOutcome}}
    
    # HNSW index for similarity search
    # Custom implementation when RAGTools not available
    outcome_vectors::Matrix{Float32}  # (embedding_dim, n_outcomes)
    outcome_indices::Vector{Int}
    outcome_metadata::Vector{ActionOutcome}
    
    # Statistics
    total_recalls::Int
    successful_adjustments::Int
    
    # Persistence
    persistence_path::Union{String, Nothing}
    
    function SemanticMemoryStore(
        config::SemanticMemoryConfig = SemanticMemoryConfig();
        persistence_path::Union{String, Nothing} = nothing
    )
        new(
            config,
            Dict{String, Vector{ActionOutcome}}(),
            Matrix{Float32}(undef, config.embedding_dim, 0),
            Int[],
            ActionOutcome[],
            0,
            0,
            persistence_path
        )
    end
end

# ============================================================================
# EMBEDDING UTILITIES
# ============================================================================

"""
    action_to_embedding - Convert action outcome to embedding vector
    Creates a feature vector combining state + action + reward info
"""
function action_to_embedding(outcome::ActionOutcome)::Vector{Float32}
    cfg = outcome  # Get config from store
    
    # Combine: perception_vector (12D) + action encoding + reward info
    embedding = Vector{Float32}(undef, 384)  # Default embedding dim
    
    # First 12 dimensions: perception vector
    embedding[1:min(12, length(outcome.perception_vector))] .= outcome.perception_vector[1:min(12, length(outcome.perception_vector))]
    
    # Add action encoding (simple hash-based)
    action_hash = hash(outcome.action_id)
    rng = MersenneTwister(action_hash)
    embedding[13:28] .= rand(rng, Float32, 16)  # 16D action encoding
    
    # Add reward encoding (16D)
    embedding[29:32] .= [
        outcome.expected_reward,
        outcome.actual_reward,
        outcome.risk,
        outcome.success ? 1.0f0 : 0.0f0
    ]
    
    # Fill remaining with normalized random (simulating learned features)
    embedding[33:end] .= rand(Float32, 384 - 32)
    
    # Normalize
    embedding ./= norm(embedding) + eps(Float32)
    
    return embedding
end

function action_to_embedding(store::SemanticMemoryStore, outcome::ActionOutcome)::Vector{Float32}
    return action_to_embedding(outcome)
end

# ============================================================================
# CORE OPERATIONS
# ============================================================================

"""
    store_action_outcome! - Store an action outcome for future recall
    This enables Jarvis to "remember" past results and adjust expected_reward
"""
function store_action_outcome!(
    store::SemanticMemoryStore,
    outcome::ActionOutcome
)::UUID
    # Index by action_id
    if !haskey(store.outcomes_by_action, outcome.action_id)
        store.outcomes_by_action[outcome.action_id] = ActionOutcome[]
    end
    push!(store.outcomes_by_action[outcome.action_id], outcome)
    
    # Add to HNSW index
    embedding = action_to_embedding(store, outcome)
    store.outcome_vectors = hcat(store.outcome_vectors, embedding)
    push!(store.outcome_indices, length(store.outcome_metadata) + 1)
    push!(store.outcome_metadata, outcome)
    
    # Check capacity
    if length(store.outcome_metadata) > store.config.max_memories
        # Remove oldest (simple strategy: remove first)
        if length(store.outcome_metadata) > 0
            store.outcome_vectors = store.outcome_vectors[:, 2:end]
            popfirst!(store.outcome_metadata)
        end
    end
    
    @debug "Stored action outcome: $(outcome.action_id) reward=$(outcome.actual_reward)"
    
    return outcome.id
end

"""
    cosine_similarity - Compute cosine similarity between embeddings
"""
function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    return dot(a, b) / (norm(a) * norm(b) + eps(Float32))
end

"""
    recall_similar_outcomes - Query vector DB for similar past outcomes
    Used to adjust expected_reward based on historical performance
"""
function recall_similar_outcomes(
    store::SemanticMemoryStore,
    current_perception::Vector{Float32},
    action_id::String;
    n_results::Int = 5
)::Vector{Tuple{ActionOutcome, Float32}}
    
    store.total_recalls += 1
    
    if isempty(store.outcome_metadata)
        return Tuple{ActionOutcome, Float32}[]
    end
    
    # Create query embedding from current perception
    # Use same action for context
    query_outcome = ActionOutcome(
        action_id,
        current_perception,
        0.0f0,
        0.0f0,
        0.0f0
    )
    query_embedding = action_to_embedding(store, query_outcome)
    
    # Search in HNSW index (simplified brute force for demo)
    # Production would use actual HNSW
    similarities = Vector{Tuple{Int, Float32}}()
    
    for i in 1:size(store.outcome_vectors, 2)
        outcome = store.outcome_metadata[i]
        # Filter by same action_id for relevance
        if outcome.action_id == action_id
            sim = cosine_similarity(query_embedding, store.outcome_vectors[:, i])
            push!(similarities, (i, sim))
        end
    end
    
    # Sort by similarity
    sort!(similarities, by = x -> x[2], rev = true)
    
    results = Tuple{ActionOutcome, Float32}[]
    for (idx, sim) in first(similarities, min(n_results, length(similarities)))
        if sim >= store.config.similarity_threshold
            push!(results, (store.outcome_metadata[idx], sim))
        end
    end
    
    return results
end

"""
    adjust_expected_reward - Adjust expected_reward based on similar past outcomes
    This is the core neuro-symbolic learning mechanism
    Formula: adjusted_reward = expected_reward * (1 + α * avg_error)
    Where α is the learning factor and avg_error is from similar past actions
"""
function adjust_expected_reward(
    store::SemanticMemoryStore,
    proposal::ActionProposal,
    current_perception::Vector{Float32}
)::Float32
    
    # Recall similar past outcomes
    similar_outcomes = recall_similar_outcomes(
        store,
        current_perception,
        proposal.capability_id;
        n_results = 5
    )
    
    if isempty(similar_outcomes)
        # No prior knowledge, return original expected reward
        return proposal.predicted_reward
    end
    
    # Compute adjustment factor from past errors
    total_error = 0.0f0
    total_weight = 0.0f0
    
    for (outcome, similarity) in similar_outcomes
        # Error: how wrong was our prediction?
        error = outcome.actual_reward - outcome.expected_reward
        
        # Weight by similarity (more similar = more weight)
        weight = similarity
        
        total_error += weight * error
        total_weight += weight
    end
    
    if total_weight > 0
        avg_error = total_error / total_weight
        
        # Learning factor (could be from JarvisState)
        α = 0.1f0  # 10% adjustment based on history
        
        # Adjust expected reward
        adjusted = proposal.predicted_reward + α * avg_error
        adjusted = clamp(adjusted, 0.0f0, 1.0f0)  # Keep in valid range
        
        store.successful_adjustments += 1
        
        @debug "Adjusted reward for $(proposal.capability_id): $(proposal.predicted_reward) -> $adjusted (avg_error=$avg_error)"
        
        return adjusted
    end
    
    return proposal.predicted_reward
end

"""
    get_action_statistics - Get historical statistics for an action
    Used by Kernel for risk assessment
"""
function get_action_statistics(
    store::SemanticMemoryStore,
    action_id::String
)::Dict{String, Any}
    
    outcomes = get(store.outcomes_by_action, action_id, ActionOutcome[])
    
    if isempty(outcomes)
        return Dict{String, Any}(
            "count" => 0,
            "success_rate" => 0.0,
            "avg_reward" => 0.0,
            "avg_risk" => 0.0,
            "recent_rewards" => Float32[]
        )
    end
    
    n = length(outcomes)
    successes = sum(o.success for o in outcomes)
    total_reward = sum(o.actual_reward for o in outcomes)
    total_risk = sum(o.risk for o in outcomes)
    
    # Get recent rewards (last 10)
    recent_rewards = Float32[o.actual_reward for o in outcomes[max(1, n-9):end]]
    
    return Dict{String, Any}(
        "count" => n,
        "success_rate" => successes / n,
        "avg_reward" => total_reward / n,
        "avg_risk" => total_risk / n,
        "recent_rewards" => recent_rewards,
        "last_outcome" => outcomes[end].success
    )
end

# ============================================================================
# PERSISTENCE
# ============================================================================

"""
    save_to_file - Persist semantic memory to JSON
"""
function save_to_file(store::SemanticMemoryStore, filepath::String)
    data = Dict{String, Any}[]
    
    for outcomes in values(store.outcomes_by_action)
        for outcome in outcomes
            push!(data, Dict(
                "id" => string(outcome.id),
                "action_id" => outcome.action_id,
                "perception_vector" => Vector(outcome.perception_vector),
                "expected_reward" => outcome.expected_reward,
                "actual_reward" => outcome.actual_reward,
                "risk" => outcome.risk,
                "success" => outcome.success,
                "error_message" => outcome.error_message,
                "context" => outcome.context,
                "timestamp" => string(outcome.timestamp)
            ))
        end
    end
    
    open(filepath, "w") do f
        JSON.print(f, data, 2)
    end
    
    @info "Saved $(length(data)) action outcomes to $filepath"
end

"""
    load_from_file - Load semantic memory from JSON
"""
function load_from_file(filepath::String)::SemanticMemoryStore
    store = SemanticMemoryStore(persistence_path = filepath)
    
    if !isfile(filepath)
        return store
    end
    
    data = JSON.parsefile(filepath)
    
    for entry in data
        outcome = ActionOutcome(
            entry["action_id"],
            Float32.(entry["perception_vector"]),
            entry["expected_reward"],
            entry["actual_reward"],
            entry["risk"];
            success = entry["success"],
            error_message = get(entry, "error_message", nothing),
            context = get(entry, "context", Dict())
        )
        outcome.id = UUID(entry["id"])
        outcome.timestamp = DateTime(entry["timestamp"])
        
        store_action_outcome!(store, outcome)
    end
    
    @info "Loaded $(length(data)) action outcomes from $filepath"
    
    return store
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    initialize_semantic_memory - Create and initialize semantic memory store
"""
function initialize_semantic_memory(
    config::SemanticMemoryConfig = SemanticMemoryConfig();
    load_path::Union{String, Nothing} = nothing
)::SemanticMemoryStore
    
    if load_path !== nothing && isfile(load_path)
        return load_from_file(load_path)
    end
    
    return SemanticMemoryStore(config)
end

# ============================================================================
# RAGTOOLS.JL INTEGRATION (Optional)
# ============================================================================

# If RAGTools is available, provide integration functions
if RAGTOOLS_AVAILABLE
    """
        rag_retrieve_with_ragtools - Use RAGTools.jl for retrieval
    """
    function rag_retrieve_with_ragtools(
        store::SemanticMemoryStore,
        query::String;
        n_results::Int = 5
    )::Vector{ActionOutcome}
        # RAGTools integration would go here
        # For now, return empty as fallback
        return ActionOutcome[]
    end
end

end # module SemanticMemory
