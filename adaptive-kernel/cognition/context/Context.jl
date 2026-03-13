# cognition/context/Context.jl - Context module index
# Stage 2: Functional Loops - Multi-turn context maintenance

module Context

# Re-export all from WorkingMemory
include("WorkingMemory.jl")
using .WorkingMemory

export
    # Types
    ConversationMessage,
    ConversationContext,
    WorkingMemoryBuffer,
    WorkingMemoryEntry,
    ContextWindow,
    
    # Functions
    add_user_message!,
    add_system_message!,
    add_internal_thought!,
    get_conversation_history,
    get_recent_context,
    prune_old_context!,
    store_working!,
    retrieve_working,
    has_working_key,
    clear_working!,
    get_working_keys,
    build_context_vector,
    summarize_context,
    update_topic!,
    update_summary!,
    optimize_window,
    build_summary

end  # module Context