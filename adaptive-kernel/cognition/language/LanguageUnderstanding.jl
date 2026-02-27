# adaptive-kernel/cognition/language/LanguageUnderstanding.jl - Grounded Language Understanding
# Component 8 of JARVIS Neuro-Symbolic Architecture
# Bridges LLM outputs to perception with symbol grounding

module LanguageUnderstanding

using Dates
using UUIDs
using Statistics
using LinearAlgebra
using Random
using JSON
using SHA  # For deterministic embeddings

export
    # Core types
    GroundingContext,
    SymbolBinding,
    
    # Symbol grounding
    ground_symbols,
    resolve_reference,
    
    # Embodied reference resolution
    resolve_embodied_reference,
    
    # Conversational episodic linking
    link_to_episode,
    update_conversation_context!,
    
    # Response contextualization
    contextualize_response,
    
    # Symbol-perception binding
    bind_symbol_to_perception!,
    get_grounded_meaning,
    
    # VectorMemory integration
    store_semantic_embedding,
    retrieve_by_perception

# ============================================================================
# GROUNDING CONTEXT
# ============================================================================

"""
    GroundingContext - Context for symbol grounding operations
    
Maintains the current state needed to ground textual symbols to perceptual
referents and maintain conversational coherence.
"""
mutable struct GroundingContext
    perception_state::Vector{Float32}      # Current 12D perception from SensoryProcessing
    world_model_state::Vector{Float32}     # Internal world model representation
    active_goals::Vector{UUID}             # Current goal IDs from GoalSystem
    episodic_memory::Vector{Dict}          # Recent episodes for context
    emotional_state::Dict{Symbol, Any}      # Current emotions for context
    conversation_history::Vector{Dict}     # Recent utterances
    symbol_bindings::Dict{String, SymbolBinding}  # Learned symbol-perception bindings
    
    function GroundingContext()
        new(
            zeros(Float32, 12),
            zeros(Float32, 12),
            UUID[],
            Dict[],
            Dict{Symbol, Any}(
                :valence => 0.5f0,
                :arousal => 0.5f0,
                :dominance => 0.5f0
            ),
            Dict[],
            Dict{String, SymbolBinding}()
        )
    end
end

# ============================================================================
# SYMBOL-PERCEPTION BINDING
# ============================================================================

"""
    SymbolBinding - Tracks the perceptual grounding of a symbol
    
Maps textual symbols to their corresponding perceptual features,
enabling embodiment-aware language understanding.
"""
struct SymbolBinding
    symbol::String
    perception_features::Vector{Float32}
    confidence::Float32
    created_at::Float64
    access_count::Int
    last_accessed::Float64
end

"""
    bind_symbol_to_perception!(symbol, perception, bindings)

Create or update a symbol-perception binding.
Tracks confidence based on usage frequency.
"""
function bind_symbol_to_perception!(
    symbol::String,
    perception::Vector{Float32},
    bindings::Dict{String, SymbolBinding}
)
    current_time = time()
    
    if haskey(bindings, symbol)
        # Update existing binding with exponential moving average
        existing = bindings[symbol]
        alpha = 0.3f0  # Learning rate
        
        # Update perception features with moving average
        new_features = alpha .* perception .+ (1f0 - alpha) .* existing.perception_features
        
        # Increment access count
        new_access_count = existing.access_count + 1
        
        # Update confidence (can increase with repeated successful bindings)
        new_confidence = min(1.0f0, existing.confidence + 0.05f0)
        
        bindings[symbol] = SymbolBinding(
            symbol,
            new_features,
            new_confidence,
            existing.created_at,
            new_access_count,
            current_time
        )
    else
        # Create new binding
        bindings[symbol] = SymbolBinding(
            symbol,
            perception,
            0.7f0,  # Initial confidence
            current_time,
            1,
            current_time
        )
    end
    
    return bindings[symbol]
end

"""
    get_grounded_meaning(symbol, bindings) -> Union{Vector{Float32}, Nothing}

Retrieve the perceptual features associated with a symbol.
Returns nothing if the symbol has not been grounded.
"""
function get_grounded_meaning(
    symbol::String,
    bindings::Dict{String, SymbolBinding}
)::Union{Vector{Float32}, Nothing}
    
    if haskey(bindings, symbol)
        binding = bindings[symbol]
        # Update last accessed time
        bindings[symbol] = SymbolBinding(
            binding.symbol,
            binding.perception_features,
            binding.confidence,
            binding.created_at,
            binding.access_count,
            time()
        )
        return binding.perception_features
    end
    
    return nothing
end

# ============================================================================
# SYMBOL GROUNDING
# ============================================================================

"""
    ground_symbols(text, context) -> Dict{Symbol, Any}

Map textual symbols to perceptual referents.
Resolves pronouns and references using the grounding context.

Returns a dictionary with:
- :tokens: Vector of tokens
- :grounded_meanings: Dict mapping tokens to perception vectors
- :references: Resolved references with their grounding
- :confidence: Overall grounding confidence
"""
function ground_symbols(
    text::String,
    context::GroundingContext
)::Dict{Symbol, Any}
    
    # Tokenize (simple whitespace tokenization)
    tokens = split(text)
    
    # Initialize result
    result = Dict{Symbol, Any}()
    result[:tokens] = tokens
    result[:grounded_meanings] = Dict{String, Vector{Float32}}()
    result[:references] = Dict{String, Any}()
    result[:confidence] = 0.0f0
    
    grounded_count = 0
    
    for token in tokens
        # Skip common stop words
        token_lower = lowercase(token)
        if token_lower in ["the", "a", "an", "is", "are", "was", "were", "be", "been", "being"]
            continue
        end
        
        # Try to resolve from symbol bindings
        grounded = get_grounded_meaning(token_lower, context.symbol_bindings)
        
        if grounded !== nothing
            result[:grounded_meanings][token_lower] = grounded
            grounded_count += 1
        else
            # Try embodied reference resolution
            grounded = resolve_embodied_reference(token_lower, context.perception_state)
            if grounded !== nothing && !iszero(grounded)
                result[:grounded_meanings][token_lower] = grounded
                # Also create a binding for future use
                bind_symbol_to_perception!(token_lower, grounded, context.symbol_bindings)
                grounded_count += 1
            end
        end
    end
    
    # Calculate confidence based on grounding success
    if length(tokens) > 0
        result[:confidence] = grounded_count / length(tokens)
    end
    
    # Add perception context
    result[:perception_context] = context.perception_state
    result[:world_model_context] = context.world_model_state
    
    return result
end

"""
    resolve_reference(referent, context) -> Union{Vector{Float32}, Nothing}

Find perceptual referent for pronouns and demonstratives like "this", "that", etc.
Searches in perception state and episodic memory.
"""
function resolve_reference(
    referent::String,
    context::GroundingContext
)::Union{Vector{Float32}, Nothing}
    
    referent_lower = lowercase(referent)
    
    # Common demonstratives and pronouns
    demonstratives = ["this", "that", "these", "those", "it", "thisone", "thatone"]
    
    if referent_lower in demonstratives
        # Use most recent perception as the referent
        if !iszero(context.perception_state)
            return context.perception_state
        end
    end
    
    # Try to find in symbol bindings
    if haskey(context.symbol_bindings, referent_lower)
        return context.symbol_bindings[referent_lower].perception_features
    end
    
    # Search in episodic memory for most recent relevant episode
    if !isempty(context.episodic_memory)
        # Return the perception from the most recent episode
        latest_episode = context.episodic_memory[end]
        if haskey(latest_episode, :perception)
            return latest_episode[:perception]
        end
    end
    
    return nothing
end

# ============================================================================
# EMBODIED REFERENCE RESOLUTION
# ============================================================================

"""
    resolve_embodied_reference(phrase, perception) -> Vector{Float32}

Map spatial and referential language to perception.
Examples:
- "the file" → relevant file features in perception
- "the process" → relevant process features
- "that one" → recently attended perception

Returns a grounded perception vector or zeros if no match found.
"""
function resolve_embodied_reference(
    phrase::String,
    perception::Vector{Float32}
)::Vector{Float32}
    
    # Ensure perception is proper length (12D expected)
    if length(perception) != 12
        perception = resize_perception(perception, 12)
    end
    
    phrase_lower = lowercase(phrase)
    
    # Define semantic categories and their typical perception indices
    # Perception vector: [file_score, process_score, network_score, 
    #                     cpu_load, memory_load, disk_io,
    #                     attention_weight_1, attention_weight_2, attention_weight_3,
    #                     recency_1, recency_2, recency_3]
    
    file_indicators = ["file", "document", "folder", "text", "code", "data"]
    process_indicators = ["process", "task", "job", "action", "operation"]
    network_indicators = ["network", "connection", "request", "server", "api"]
    
    # Score the phrase against each category
    file_score = sum(indicator -> contains(phrase_lower, indicator), file_indicators)
    process_score = sum(indicator -> contains(phrase_lower, indicator), process_indicators)
    network_score = sum(indicator -> contains(phrase_lower, indicator), network_indicators)
    
    # Create weighted perception output
    result = zeros(Float32, 12)
    
    if file_score > 0
        result[1] = min(1.0f0, Float32(file_score))
    end
    if process_score > 0
        result[2] = min(1.0f0, Float32(process_score))
    end
    if network_score > 0
        result[3] = min(1.0f0, Float32(network_score))
    end
    
    # Copy relevant perception features based on category
    if file_score >= process_score && file_score >= network_score
        # Focus on file-related perception
        result[7:9] = perception[7:9]  # Attention weights
    elseif process_score >= network_score
        # Focus on process-related perception
        result[4:6] = perception[4:6]  # System loads
    else
        # Focus on network-related perception
        result[3] = max(result[3], perception[3])
    end
    
    # Add recency information
    result[10:12] = perception[10:12]
    
    return result
end

"""
    resize_perception(perception, target_dim) -> Vector{Float32}

Resize perception vector to target dimension.
"""
function resize_perception(
    perception::Vector{Float32},
    target_dim::Int
)::Vector{Float32}
    
    current_dim = length(perception)
    
    if current_dim == target_dim
        return perception
    elseif current_dim < target_dim
        # Pad with zeros
        result = zeros(Float32, target_dim)
        result[1:current_dim] = perception
        return result
    else
        # Truncate
        return perception[1:target_dim]
    end
end

# ============================================================================
# CONVERSATIONAL EPISODIC LINKING
# ============================================================================

"""
    link_to_episode(text, context) -> Union{UUID, Nothing}

Link current utterance to relevant episode in memory.
Uses semantic similarity to find the most relevant past episode.

Returns episode UUID if found, nothing otherwise.
"""
function link_to_episode(
    text::String,
    context::GroundingContext
)::Union{UUID, Nothing}
    
    if isempty(context.episodic_memory)
        return nothing
    end
    
    # Generate embedding for current text (simplified - would use actual embedding)
    current_embedding = generate_simple_embedding(text)
    
    best_match = nothing
    best_similarity = 0.0f0
    
    for episode in context.episodic_memory
        if haskey(episode, :embedding)
            similarity = cosine_similarity(current_embedding, episode[:embedding])
            
            if similarity > best_similarity
                best_similarity = similarity
                best_match = episode
            end
        end
    end
    
    # Only return if similarity is above threshold
    if best_similarity > 0.5f0 && best_match !== nothing
        return get(best_match, :episode_id, nothing)
    end
    
    return nothing
end

"""
    update_conversation_context!(context, utterance, is_user)

Update context with new utterance and track conversation history.
"""
function update_conversation_context!(
    context::GroundingContext,
    utterance::String,
    is_user::Bool
)
    current_time = time()
    
    # Create utterance record
    utterance_record = Dict{Any, Any}(
        :text => utterance,
        :is_user => is_user,
        :timestamp => current_time,
        :embedding => generate_simple_embedding(utterance)
    )
    
    # Add to conversation history
    push!(context.conversation_history, utterance_record)
    
    # Keep only recent history (last 20 utterances)
    if length(context.conversation_history) > 20
        context.conversation_history = context.conversation_history[end-19:end]
    end
    
    # Extract and store new symbol groundings
    grounding_result = ground_symbols(utterance, context)
    
    for (token, perception) in grounding_result[:grounded_meanings]
        bind_symbol_to_perception!(token, perception, context.symbol_bindings)
    end
end

# ============================================================================
# CONTEXTUALIZE RESPONSE
# ============================================================================

"""
    contextualize_response(llm_output, context; grounding_required=true) -> String

Post-process LLM output for perceptual grounding.
Ensures references are resolved and adds perceptual context when needed.

This bridges the gap between abstract language generation and grounded understanding.
"""
function contextualize_response(
    llm_output::String,
    context::GroundingContext;
    grounding_required::Bool=true
)::String
    
    result = llm_output
    
    # Check for unresolved references
    tokens = split(llm_output)
    
    # Identify demonstratives and pronouns that might need resolution
    demonstratives = ["this", "that", "it", "these", "those"]
    unresolved_refs = []
    
    for token in tokens
        token_lower = lowercase(rstrip(token, ',', '.', '!', '?'))
        if token_lower in demonstratives
            # Check if we can resolve it
            grounding = resolve_reference(token_lower, context)
            if grounding !== nothing
                # We have grounding - the reference is resolved
                # Could add implicit confirmation
            else
                push!(unresolved_refs, token_lower)
            end
        end
    end
    
    # If grounding is required and we have unresolved references,
    # add a grounding prefix
    if grounding_required && !isempty(unresolved_refs)
        # Add perception context to help resolve ambiguity
        perception_summary = summarize_perception(context.perception_state)
        
        # Prepend grounding context (optional - can be disabled for more natural output)
        # result = "[Context: $perception_summary] $result"
    end
    
    # Update conversation context with the response
    update_conversation_context!(result, context, false)
    
    return result
end

"""
    summarize_perception(perception) -> String

Create a human-readable summary of perception state.
"""
function summarize_perception(perception::Vector{Float32})::String
    if length(perception) < 12
        perception = resize_perception(perception, 12)
    end
    
    # Extract key features
    file_activity = perception[1]
    process_activity = perception[2]
    network_activity = perception[3]
    
    summaries = String[]
    
    if file_activity > 0.5
        push!(summaries, "file activity")
    end
    if process_activity > 0.5
        push!(summaries, "process activity")
    end
    if network_activity > 0.5
        push!(summaries, "network activity")
    end
    
    if isempty(summaries)
        return "general monitoring"
    else
        return join(summaries, ", ")
    end
end

# ============================================================================
# VECTOR MEMORY INTEGRATION
# ============================================================================

"""
    store_semantic_embedding(text, perception, memory)

Store text with grounded perception in memory.
Enables retrieval by perception similarity.

memory should implement:
- store!(entry)
- search(query_vector, k)
"""
function store_semantic_embedding(
    text::String,
    perception::Vector{Float32},
    memory::Any  # VectorMemory.VectorStore
)
    # Ensure perception is proper dimension
    if length(perception) != 12
        perception = resize_perception(perception, 12)
    end
    
    # Generate semantic embedding (combines text hash with perception)
    embedding = generate_grounded_embedding(text, perception)
    
    # Create memory entry
    entry = Dict{Any, Any}(
        :text => text,
        :embedding => embedding,
        :perception => perception,
        :timestamp => time()
    )
    
    # Store in memory if the interface supports it
    if applicable(store!, memory, entry)
        store!(memory, entry)
    end
    
    return entry
end

"""
    retrieve_by_perception(perception, memory; top_k=5) -> Vector{Dict}

Retrieve semantically similar memories by perception similarity.
Returns top_k most similar entries.
"""
function retrieve_by_perception(
    perception::Vector{Float32},
    memory::Any;
    top_k::Int=5
)::Vector{Dict}
    
    # Ensure perception is proper dimension
    if length(perception) != 12
        perception = resize_perception(perception, 12)
    end
    
    # Use perception as query vector
    results = []
    
    # If memory supports search, use it
    if applicable(search, memory, perception, top_k)
        results = search(memory, perception, top_k)
    else
        # Fallback: return empty results
        results = Dict[]
    end
    
    return results
end

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

"""
    generate_simple_embedding(text) -> Vector{Float32}

Generate a simple deterministic embedding for text.
In production, this would use a proper embedding model.
"""
function generate_simple_embedding(text::String)::Vector{Float32}
    # Use SHA hash for deterministic embedding
    hash_bytes = sha256(text)
    
    # Convert to Float32 vector
    embedding = Float32[]
    for i in 1:min(12, length(hash_bytes))
        push!(embedding, Float32(hash_bytes[i]) / 255.0f0)
    end
    
    # Pad to 12 dimensions
    while length(embedding) < 12
        push!(embedding, 0.0f0)
    end
    
    return embedding[1:12]
end

"""
    generate_grounded_embedding(text, perception) -> Vector{Float32}

Generate embedding that combines text semantics with perception grounding.
"""
function generate_grounded_embedding(
    text::String,
    perception::Vector{Float32}
)::Vector{Float32}
    
    # Get text embedding
    text_embedding = generate_simple_embedding(text)
    
    # Combine with perception (weighted average)
    alpha = 0.6f0  # Weight for text vs perception
    
    combined = alpha .* text_embedding .+ (1f0 - alpha) .* perception
    
    # Normalize
    norm = sqrt(sum(combined .^ 2))
    if norm > 0
        combined = combined ./ norm
    end
    
    return combined
end

"""
    cosine_similarity(a, b) -> Float32

Compute cosine similarity between two vectors.
"""
function cosine_similarity(a::Vector{Float32}, b::Vector{Float32})::Float32
    if length(a) != length(b)
        # Resize to match
        min_len = min(length(a), length(b))
        a = a[1:min_len]
        b = b[1:min_len]
    end
    
    dot_product = sum(a .* b)
    norm_a = sqrt(sum(a .^ 2))
    norm_b = sqrt(sum(b .^ 2))
    
    if norm_a == 0 || norm_b == 0
        return 0.0f0
    end
    
    return dot_product / (norm_a * norm_b)
end

# ============================================================================
# INTEGRATION HELPERS
# ============================================================================

"""
    create_grounding_context(
        perception::Vector{Float32},
        world_model::Vector{Float32},
        goals::Vector{UUID},
        emotions::Dict{Symbol, Any}
    ) -> GroundingContext

Create a GroundingContext from individual components.
"""
function create_grounding_context(
    perception::Vector{Float32},
    world_model::Vector{Float32},
    goals::Vector{UUID},
    emotions::Dict{Symbol, Any}
)::GroundingContext
    
    context = GroundingContext()
    context.perception_state = perception
    context.world_model_state = world_model
    context.active_goals = goals
    context.emotional_state = emotions
    
    return context
end

"""
    extract_perception_features(context) -> Vector{Float32}

Extract the current perception state from grounding context.
"""
function extract_perception_features(context::GroundingContext)::Vector{Float32}
    return context.perception_state
end

"""
    get_conversation_summary(context; recent_count=5) -> String

Get a summary of recent conversation for debugging/logging.
"""
function get_conversation_summary(
    context::GroundingContext;
    recent_count::Int=5
)::String
    
    if isempty(context.conversation_history)
        return "No conversation history"
    end
    
    recent = context.conversation_history[max(1, end-recent_count+1):end]
    
    lines = String[]
    for utterance in recent
        speaker = utterance[:is_user] ? "User" : "JARVIS"
        text = utterance[:text]
        push!(lines, "$speaker: $(text[1:min(50, length(text))])")
    end
    
    return join(lines, "\n")
end

end # module LanguageUnderstanding
