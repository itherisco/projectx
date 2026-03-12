# cognition/SessionManager.jl
# Phase 3: Session Management for Stage 2 (Functional Loops)
#
# This module provides:
# 1. Multi-turn context maintenance across interactions
# 2. Session persistence mechanisms
# 3. Context building across multiple turns
# 4. Memory of previous interactions
#
# This enables the system to evolve from Stage 1 (Foundational) to Stage 2 (Functional Loops)

module SessionManager

using Dates
using UUIDs
using JSON
using Statistics

# ============================================================================
# SESSION TYPES
# ============================================================================

"""
    TurnContext - Context for a single turn in a session

# Fields
- `turn_id::UUID`: Unique identifier for this turn
- `user_input::String`: User's input for this turn
- `system_response::String`: System's response
- `perception_snapshot::Dict`: Perception state at turn time
- `emotional_state::Dict`: Emotional state at turn time
- `actions_taken::Vector{String}`: Actions taken in this turn
- `outcomes::Vector{Bool}`: Outcomes of actions
- `timestamp::DateTime`: When this turn occurred
- `context_vector::Vector{Float32}`: 16D context vector for this turn
"""
mutable struct TurnContext
    turn_id::UUID
    user_input::String
    system_response::String
    perception_snapshot::Dict
    emotional_state::Dict
    actions_taken::Vector{String}
    outcomes::Vector{Bool}
    timestamp::DateTime
    context_vector::Vector{Float32}
    
    function TurnContext(user_input::String)
        new(
            uuid4(),
            user_input,
            "",
            Dict(),
            Dict(),
            String[],
            Bool[],
            now(),
            zeros(Float32, 16)
        )
    end
end

"""
    Session - Main session state for multi-turn interactions

# Fields
- `session_id::UUID`: Unique identifier for this session
- `turns::Vector{TurnContext}`: All turns in this session
- `current_turn::Int`: Current turn number
- `created_at::DateTime`: When session was created
- `last_activity::DateTime`: Last activity timestamp
- `context_summary::Vector{Float32}`: Aggregated context across turns
- `goal_history::Vector{Dict}`: Goals pursued in this session
- `knowledge_updates::Vector{Dict}`: Knowledge learned in this session
- `metadata::Dict`: Additional session metadata
"""
mutable struct Session
    session_id::UUID
    turns::Vector{TurnContext}
    current_turn::Int
    created_at::DateTime
    last_activity::DateTime
    context_summary::Vector{Float32}
    goal_history::Vector{Dict}
    knowledge_updates::Vector{Dict}
    metadata::Dict
    
    function Session()
        new(
            uuid4(),
            TurnContext[],
            0,
            now(),
            now(),
            zeros(Float32, 32),  # 32D context summary
            Dict[],
            Dict[],
            Dict()
        )
    end
end

"""
    SessionManager - Manager for multiple sessions

# Fields
- `active_sessions::Dict{UUID, Session}`: Currently active sessions
- `session_timeout_minutes::Int`: Timeout for inactive sessions
- `max_turns_per_session::Int`: Maximum turns before session reset
- `context_decay::Float32`: How quickly old context decays (0-1)
- `persistence_path::Union{String, Nothing}`: Path for session persistence
"""
mutable struct SessionManager
    active_sessions::Dict{UUID, Session}
    session_timeout_minutes::Int
    max_turns_per_session::Int
    context_decay::Float32
    persistence_path::Union{String, Nothing}
    
    function SessionManager(;timeout_minutes::Int=60, max_turns::Int=50, 
                           context_decay::Float32=0.95f0, persistence_path::Union{String, Nothing}=nothing)
        new(
            Dict{UUID, Session}(),
            timeout_minutes,
            max_turns,
            context_decay,
            persistence_path
        )
    end
end

# ============================================================================
# SESSION MANAGEMENT FUNCTIONS
# ============================================================================

"""
    create_session(manager::SessionManager)::Session

Create a new session and register it with the manager.
"""
function create_session(manager::SessionManager)::Session
    session = Session()
    manager.active_sessions[session.session_id] = session
    return session
end

"""
    get_or_create_session(manager::SessionManager, session_id::UUID)::Session

Get an existing session or create a new one if it doesn't exist.
"""
function get_or_create_session(manager::SessionManager, session_id::UUID)::Session
    if haskey(manager.active_sessions, session_id)
        session = manager.active_sessions[session_id]
        
        # Check for timeout
        inactive_minutes = (now() - session.last_activity).value / 60000
        if inactive_minutes > manager.session_timeout_minutes
            # Session expired, create new one
            delete!(manager.active_sessions, session_id)
            return create_session(manager)
        end
        
        return session
    end
    
    return create_session(manager)
end

"""
    add_turn!(session::Session, user_input::String)::TurnContext

Add a new turn to the session with user input.
"""
function add_turn!(session::Session, user_input::String)::TurnContext
    session.current_turn += 1
    turn = TurnContext(user_input)
    push!(session.turns, turn)
    session.last_activity = now()
    
    # Check if we've exceeded max turns
    if session.current_turn > session.max_turns_per_session
        # Start a new session context but keep history
        consolidate_session_context!(session)
    end
    
    return turn
end

"""
    update_turn!(session::Session, turn::TurnContext; 
                 system_response=nothing, perception=nothing, 
                 emotional=nothing, actions=nothing, outcomes=nothing)

Update a turn with response and results.
"""
function update_turn!(session::Session, turn::TurnContext;
                     system_response::Union{String, Nothing}=nothing,
                     perception::Union{Dict, Nothing}=nothing,
                     emotional::Union{Dict, Nothing}=nothing,
                     actions::Union{Vector{String}, Nothing}=nothing,
                     outcomes::Union{Vector{Bool}, Nothing}=nothing)
    
    if system_response !== nothing
        turn.system_response = system_response
    end
    
    if perception !== nothing
        turn.perception_snapshot = perception
    end
    
    if emotional !== nothing
        turn.emotional_state = emotional
    end
    
    if actions !== nothing
        turn.actions_taken = actions
    end
    
    if outcomes !== nothing
        turn.outcomes = outcomes
    end
    
    # Update context vector
    turn.context_vector = build_turn_context_vector(turn)
    
    # Update session context summary
    update_session_context!(session)
    
    session.last_activity = now()
end

"""
    build_turn_context_vector(turn::TurnContext)::Vector{Float32}

Build a 16D context vector for a single turn.
"""
function build_turn_context_vector(turn::TurnContext)::Vector{Float32}
    vec = zeros(Float32, 16)
    
    # Input length (normalized)
    vec[1] = clamp(length(turn.user_input) / 500.0, 0.0f0, 1.0f0)
    
    # Has response
    vec[2] = !isempty(turn.system_response) ? 1.0f0 : 0.0f0
    
    # Actions taken count
    vec[3] = clamp(length(turn.actions_taken) / 10.0, 0.0f0, 1.0f0)
    
    # Success rate
    if !isempty(turn.outcomes)
        vec[4] = mean(Float32.(turn.outcomes))
    else
        vec[4] = 0.5f0
    end
    
    # Emotional valence (-1 to 1 -> 0 to 1)
    if haskey(turn.emotional_state, "valence")
        vec[5] = (turn.emotional_state["valence"] + 1.0f0) / 2.0f0
    else
        vec[5] = 0.5f0
    end
    
    # Emotional arousal (0 to 1)
    if haskey(turn.emotional_state, "arousal")
        vec[6] = turn.emotional_state["arousal"]
    else
        vec[6] = 0.0f0
    end
    
    # Turn number (normalized)
    vec[7] = clamp(turn.turn_id.value % 1000 / 1000.0, 0.0f0, 1.0f0)
    
    # Recency (time since turn)
    age_seconds = (now() - turn.timestamp).value / 1000
    vec[8] = clamp(exp(-age_seconds / 3600.0), 0.0f0, 1.0f0)  # Decay over 1 hour
    
    # Fill remaining with zeros (could be extended)
    vec[9:16] .= 0.0f0
    
    return vec
end

"""
    update_session_context!(session::Session)

Update the aggregated context summary for the session.
"""
function update_session_context!(session::Session)
    if isempty(session.turns)
        return
    end
    
    # Get recent turns (last 10)
    recent_turns = session.turns[max(1, end-9):end]
    
    # Average context vectors with recency weighting
    total_weight = 0.0f0
    weighted_sum = zeros(Float32, 32)
    
    for (i, turn) in enumerate(reverse(recent_turns))
        weight = Float32(i)  # More recent = higher weight
        
        # Expand 16D turn vector to 32D
        weighted_sum[1:16] += turn.context_vector * weight
        weighted_sum[17:32] += turn.context_vector * weight * 0.5f0
        
        total_weight += weight * 1.5f0
    end
    
    # Apply decay to old context
    session.context_summary = session.context_summary * session.context_decay
    
    # Add new weighted context
    if total_weight > 0
        session.context_summary += weighted_sum / total_weight
    end
    
    # Normalize
    session.context_summary = session.context_summary / (norm(session.context_summary) + 1e-6f0)
end

"""
    consolidate_session_context!(session::Session)

Consolidate session context when max turns exceeded.
Creates a summary of the session so far.
"""
function consolidate_session_context!(session::Session)
    # Keep last 20 turns, create summary
    if length(session.turns) > 20
        # Record goal history and knowledge updates
        for turn in session.turns[1:end-20]
            if !isempty(turn.actions_taken)
                push!(session.goal_history, Dict(
                    "turn" => turn.turn_id,
                    "actions" => turn.actions_taken,
                    "outcomes" => turn.outcomes,
                    "timestamp" => turn.timestamp
                ))
            end
        end
        
        # Delete old turns
        session.turns = session.turns[end-19:end]
    end
    
    # Reset current turn counter but keep context
    session.current_turn = length(session.turns)
end

"""
    get_context_for_reasoning(session::Session; max_turns::Int=10)::Dict

Get the context from recent turns to use in reasoning.
This is the main function for Stage 2 multi-turn context maintenance.
"""
function get_context_for_reasoning(session::Session; max_turns::Int=10)::Dict
    recent_turns = session.turns[max(1, end-max_turns+1):end]
    
    # Build conversation history
    conversation = []
    for turn in recent_turns
        push!(conversation, Dict(
            "role" => "user",
            "content" => turn.user_input,
            "timestamp" => turn.timestamp
        ))
        if !isempty(turn.system_response)
            push!(conversation, Dict(
                "role" => "system",
                "content" => turn.system_response,
                "timestamp" => turn.timestamp
            ))
        end
    end
    
    # Extract key information
    all_actions = String[]
    all_outcomes = Bool[]
    for turn in recent_turns
        append!(all_actions, turn.actions_taken)
        append!(all_outcomes, turn.outcomes)
    end
    
    return Dict(
        "session_id" => session.session_id,
        "current_turn" => session.current_turn,
        "conversation" => conversation,
        "context_summary" => session.context_summary,
        "recent_actions" => all_actions,
        "recent_outcomes" => all_outcomes,
        "goal_history" => session.goal_history,
        "knowledge_updates" => session.knowledge_updates,
        "success_rate" => isempty(all_outcomes) ? 0.5 : mean(Float32.(all_outcomes))
    )
end

"""
    persist_session(session::Session, path::String)

Persist session to disk for recovery.
"""
function persist_session(session::Session, path::String)
    # Convert to JSON-serializable format
    data = Dict(
        "session_id" => string(session.session_id),
        "current_turn" => session.current_turn,
        "created_at" => string(session.created_at),
        "last_activity" => string(session.last_activity),
        "context_summary" => collect(session.context_summary),
        "goal_history" => session.goal_history,
        "knowledge_updates" => session.knowledge_updates,
        "metadata" => session.metadata,
        "turn_count" => length(session.turns)
    )
    
    # Write to file
    open(path, "w") do f
        JSON.print(f, data)
    end
end

"""
    load_session(path::String)::Session

Load session from disk.
"""
function load_session(path::String)::Session
    data = JSON.parsefile(path)
    
    session = Session()
    session.session_id = UUID(data["session_id"])
    session.current_turn = data["current_turn"]
    session.created_at = DateTime(data["created_at"])
    session.last_activity = DateTime(data["last_activity"])
    session.context_summary = Vector{Float32}(data["context_summary"])
    session.goal_history = data["goal_history"]
    session.knowledge_updates = data["knowledge_updates"]
    session.metadata = data["metadata"]
    
    return session
end

"""
    cleanup_expired_sessions!(manager::SessionManager)

Remove expired sessions from the manager.
"""
function cleanup_expired_sessions!(manager::SessionManager)
    current_time = now()
    expired_ids = UUID[]
    
    for (id, session) in manager.active_sessions
        inactive_minutes = (current_time - session.last_activity).value / 60000
        if inactive_minutes > manager.session_timeout_minutes
            # Persist before deleting
            if manager.persistence_path !== nothing
                path = joinpath(manager.persistence_path, "session_$id.json")
                persist_session(session, path)
            end
            push!(expired_ids, id)
        end
    end
    
    for id in expired_ids
        delete!(manager.active_sessions, id)
    end
    
    return Dict(
        "cleaned" => length(expired_ids),
        "remaining" => length(manager.active_sessions)
    )
end

# ============================================================================
# CONTEXT BUILDING FOR STAGE 2
# ============================================================================

"""
    build_multi_turn_context(user_input::String, session::Session, 
                           perception::Dict, emotional::Dict)::Dict

Build comprehensive context from multiple turns for reasoning.
This is the primary interface for Stage 2 context maintenance.
"""
function build_multi_turn_context(user_input::String, session::Session, 
                                  perception::Dict, emotional::Dict)::Dict
    # Add new turn
    turn = add_turn!(session, user_input)
    
    # Get reasoning context from session
    reasoning_context = get_context_for_reasoning(session)
    
    # Return combined context
    return Dict(
        "turn_id" => turn.turn_id,
        "current_input" => user_input,
        "session_context" => reasoning_context,
        "current_perception" => perception,
        "current_emotional" => emotional,
        "context_vector" => session.context_summary
    )
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    TurnContext,
    Session,
    SessionManager,
    create_session,
    get_or_create_session,
    add_turn!,
    update_turn!,
    get_context_for_reasoning,
    persist_session,
    load_session,
    cleanup_expired_sessions!,
    build_multi_turn_context

end # module
