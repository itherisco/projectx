# cognition/context/WorkingMemory.jl - Multi-turn Context and Working Memory
# Stage 2: Functional Loops - Context retention across multiple turns
#
# This module provides:
# 1. Conversation history buffer for multi-turn context
# 2. Working memory for intermediate results
# 3. Context window optimization
# 4. State persistence between cognitive cycles

module WorkingMemory

using Dates
using UUIDs

export
    # Types
    ConversationMessage,
    ConversationContext,
    WorkingMemoryBuffer,
    ContextWindow,
    
    # Functions
    add_user_message!,
    add_system_message!,
    add_internal_thought!,
    get_conversation_history,
    get_recent_context,
    prune_old_context,
    store_working!,
    retrieve_working,
    clear_working!,
    build_context_vector,
    summarize_context

# ============================================================================
# CONVERSATION CONTEXT
# ============================================================================

"""
    ConversationMessage - Single message in conversation history
"""
struct ConversationMessage
    id::UUID
    role::Symbol  # :user, :system, :assistant, :internal
    content::String
    timestamp::DateTime
    metadata::Dict{Symbol, Any}
    
    function ConversationMessage(
        role::Symbol,
        content::String;
        metadata::Dict{Symbol, Any}=Dict{Symbol, Any}()
    )
        new(uuid4(), role, content, now(), metadata)
    end
end

"""
    ConversationContext - Multi-turn conversation history buffer
    
    Maintains conversation context across multiple cognitive cycles.
    This is the key component for Stage 2 (Functional Loops).
"""
mutable struct ConversationContext
    messages::Vector{ConversationMessage}
    max_history::Int
    current_topic::Union{String, Nothing}
    topic_confidence::Float32
    turn_count::Int
    
    function ConversationContext(;
        max_history::Int=50
    )
        new(
            ConversationMessage[],
            max_history,
            nothing,
            0.0f0,
            0
        )
    end
end

"""
    add_user_message! - Add user message to conversation context
"""
function add_user_message!(ctx::ConversationContext, content::String)
    msg = ConversationMessage(:user, content)
    push!(ctx.messages, msg)
    ctx.turn_count += 1
    
    # Prune if exceeds max
    if length(ctx.messages) > ctx.max_history
        ctx.messages = ctx.messages[end-ctx.max_history+1:end]
    end
    
    return msg
end

"""
    add_system_message! - Add system/assistant response to conversation
"""
function add_system_message!(ctx::ConversationContext, content::String; metadata::Dict{Symbol, Any}=Dict{Symbol, Any}())
    msg = ConversationMessage(:system, content; metadata=metadata)
    push!(ctx.messages, msg)
    
    # Prune if exceeds max
    if length(ctx.messages) > ctx.max_history
        ctx.messages = ctx.messages[end-ctx.max_history+1:end]
    end
    
    return msg
end

"""
    add_internal_thought! - Add internal thought (for self-reflection tracking)
"""
function add_internal_thought!(ctx::ConversationContext, thought::String; metadata::Dict{Symbol, Any}=Dict{Symbol, Any}())
    msg = ConversationMessage(:internal, thought; metadata=metadata)
    push!(ctx.messages, msg)
    return msg
end

"""
    get_conversation_history - Get full conversation history
"""
function get_conversation_history(ctx::ConversationContext)::Vector{ConversationMessage}
    return copy(ctx.messages)
end

"""
    get_recent_context - Get recent N messages for context
"""
function get_recent_context(ctx::ConversationContext, n::Int)::Vector{ConversationMessage}
    if isempty(ctx.messages)
        return ConversationMessage[]
    end
    start_idx = max(1, length(ctx.messages) - n + 1)
    return ctx.messages[start_idx:end]
end

"""
    prune_old_context - Prune old messages based on age or token count
"""
function prune_old_context!(ctx::ConversationContext; keep_recent::Int=20)
    if length(ctx.messages) > keep_recent
        ctx.messages = ctx.messages[end-keep_recent+1:end]
    end
end

"""
    update_topic! - Update current topic detection
"""
function update_topic!(ctx::ConversationContext, topic::String, confidence::Float32)
    ctx.current_topic = topic
    ctx.topic_confidence = confidence
end

# ============================================================================
# WORKING MEMORY BUFFER
# ============================================================================

"""
    WorkingMemoryEntry - Single entry in working memory
"""
struct WorkingMemoryEntry
    key::String
    value::Any
    created_at::DateTime
    access_count::Int
    priority::Float32  # 0-1, higher = more important to retain
    
    function WorkingMemoryEntry(key::String, value::Any; priority::Float32=0.5f0)
        new(key, value, now(), 0, priority)
    end
end

"""
    WorkingMemoryBuffer - Short-term working memory for intermediate results
    
    This provides the "scratchpad" for the cognitive system to store
    intermediate results between cycles.
"""
mutable struct WorkingMemoryBuffer
    entries::Dict{String, WorkingMemoryEntry}
    max_entries::Int
    access_order::Vector{String}  # LRU tracking
    
    function WorkingMemoryBuffer(; max_entries::Int=100)
        new(Dict{String, WorkingMemoryEntry}(), max_entries, String[])
    end
end

"""
    store_working! - Store value in working memory
"""
function store_working!(wm::WorkingMemoryBuffer, key::String, value::Any; priority::Float32=0.5f0)
    entry = WorkingMemoryEntry(key, value; priority=priority)
    wm.entries[key] = entry
    
    # Update access order
    if key in wm.access_order
        filter!(k -> k != key, wm.access_order)
    end
    push!(wm.access_order, key)
    
    # Evict if over capacity (LRU eviction)
    if length(wm.entries) > wm.max_entries
        # Evict lowest priority or least recently used
        evict_lowest_priority!(wm)
    end
    
    return entry
end

"""
    evict_lowest_priority! - Evict lowest priority entry
"""
function evict_lowest_priority!(wm::WorkingMemoryBuffer)
    if isempty(wm.entries)
        return
    end
    
    # Find entry with lowest priority (or oldest if same priority)
    lowest_key = nothing
    lowest_priority = Inf
    oldest_time = DateTime(9999, 12, 31)
    
    for (key, entry) in wm.entries
        if entry.priority < lowest_priority || 
           (entry.priority == lowest_priority && entry.created_at < oldest_time)
            lowest_priority = entry.priority
            oldest_time = entry.created_at
            lowest_key = key
        end
    end
    
    if lowest_key !== nothing
        delete!(wm.entries, lowest_key)
        filter!(k -> k != lowest_key, wm.access_order)
    end
end

"""
    retrieve_working - Retrieve value from working memory
"""
function retrieve_working(wm::WorkingMemoryBuffer, key::String)::Union{Any, Nothing}
    if haskey(wm.entries, key)
        entry = wm.entries[key]
        entry.access_count += 1
        # Move to end of access order (most recently used)
        filter!(k -> k != key, wm.access_order)
        push!(wm.access_order, key)
        return entry.value
    end
    return nothing
end

"""
    has_working_key - Check if key exists in working memory
"""
function has_working_key(wm::WorkingMemoryBuffer, key::String)::Bool
    return haskey(wm.entries, key)
end

"""
    clear_working! - Clear working memory
"""
function clear_working!(wm::WorkingMemoryBuffer)
    empty!(wm.entries)
    empty!(wm.access_order)
end

"""
    get_working_keys - Get all keys in working memory
"""
function get_working_keys(wm::WorkingMemoryBuffer)::Vector{String}
    return collect(keys(wm.entries))
end

# ============================================================================
# CONTEXT WINDOW OPTIMIZATION
# ============================================================================

"""
    ContextWindow - Manages context window size for long conversations
    
    Implements:
    - Sliding window (keep recent)
    - Importance-based pruning
    - Simple summarization
"""
mutable struct ContextWindow
    window_size::Int
    min_importance::Float32
    summary::Union{String, Nothing}
    
    function ContextWindow(; window_size::Int=10, min_importance::Float32=0.3f0)
        new(window_size, min_importance, nothing)
    end
end

"""
    optimize_window - Optimize context window using configured strategy
"""
function optimize_window(
    ctx::ConversationContext,
    wm::ContextWindow
)::Vector{ConversationMessage}
    messages = get_recent_context(ctx, wm.window_size)
    
    # If we have a summary and recent messages, combine them
    if wm.summary !== nothing && length(messages) < wm.window_size
        # Add summary as first "message" if available
        summary_msg = ConversationMessage(:system, "[Summary] " * wm.summary)
        messages = vcat([summary_msg], messages)
    end
    
    return messages
end

"""
    build_summary - Build simple summary of conversation
"""
function build_summary(ctx::ConversationContext)::String
    if isempty(ctx.messages)
        return ""
    end
    
    # Simple summary: first message + last message + turn count
    first = ctx.messages[1].content[1:min(50, length(ctx.messages[1].content))]
    last = ctx.messages[end].content[1:min(50, length(ctx.messages[end].content))]
    
    return "Started with: \"$first...\" | Ended with: \"$last...\" | $ctx.turn_count turns"
end

"""
    update_summary! - Update context window summary
"""
function update_summary!(ctx::ConversationContext, wm::ContextWindow)
    if length(ctx.messages) > wm.window_size
        wm.summary = build_summary(ctx)
    end
end

# ============================================================================
# CONTEXT VECTOR BUILDER
# ============================================================================

"""
    build_context_vector - Build context vector for brain input
    
    Combines:
    - Recent conversation history
    - Current working memory
    - Topic information
"""
function build_context_vector(
    ctx::ConversationContext,
    wm::WorkingMemoryBuffer
)::Vector{Float32}
    # Create a simple context vector
    # Format: [recent_msg_embedding..., working_memory_indicator..., topic_indicator...]
    
    recent = get_recent_context(ctx, 5)
    working_keys = get_working_keys(wm)
    
    # Simple hash-based embedding (in production, use proper embeddings)
    context_parts = String[]
    
    for msg in recent
        push!(context_parts, msg.role == :user ? "U" : "S")
        push!(context_parts, string(hash(msg.content) % 1000))
    end
    
    for key in working_keys
        push!(context_parts, "W:$key")
    end
    
    if ctx.current_topic !== nothing
        push!(context_parts, "T:$(ctx.current_topic)")
    end
    
    # Convert to simple float vector
    hash_sum = sum(parse(Int, split(p, ":")[end]) for p in context_parts if occursin(":", p) && tryparse(Int, split(p, ":")[end]) !== nothing)
    
    return Float32[hash_sum % 1000 / 1000.0, 
                    length(recent) / 50.0,
                    length(working_keys) / 100.0,
                    ctx.topic_confidence]
end

"""
    summarize_context - Get context summary string
"""
function summarize_context(ctx::ConversationContext)::String
    n = length(ctx.messages)
    topic = ctx.current_topic !== nothing ? ctx.current_topic : "unknown"
    return "Context: $n messages, topic: $topic, turns: $(ctx.turn_count)"
end

end  # module WorkingMemory