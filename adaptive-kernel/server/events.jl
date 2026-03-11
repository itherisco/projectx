# events.jl - Event broadcasting system for real-time kernel communication
# Provides event types, subscriber pattern, filtering, and history buffer

module ServerEvents

using JSON
using Dates
using UUIDs
using Base.Threads

# ============================================================================
# Event Types
# ============================================================================

"""
    EventType - Categories of events emitted by the kernel
"""
@enum EventType begin
    EVENT_THOUGHT      # Internal kernel thought/processing
    EVENT_ACTION       # Action being executed
    EVENT_GOAL         # Goal-related event
    EVENT_ERROR        # Error or exception
    EVENT_STATUS       # Kernel status change
    EVENT_MESSAGE      # Chat message
    EVENT_CAPABILITY   # Capability-related event
    EVENT_SYSTEM       # System-level event
end

"""
    ServerEvent - Structured event for broadcasting to clients
"""
mutable struct ServerEvent
    id::String
    type::EventType
    timestamp::DateTime
    payload::Dict{String, Any}
    source::String
end

"""
    Create a new ServerEvent
"""
function create_event(
    type::EventType;
    payload::Dict{String, Any}=Dict{String, Any}(),
    source::String="kernel"
)::ServerEvent
    return ServerEvent(
        string(uuid4()),
        type,
        now(Dates.UTC),
        payload,
        source
    )
end

"""
    Serialize event to JSON string
"""
function to_json(event::ServerEvent)::String
    return JSON.json(Dict(
        "id" => event.id,
        "type" => string(event.type),
        "timestamp" => Dates.format(event.timestamp, Dates.ISODateTimeFormat),
        "payload" => event.payload,
        "source" => event.source
    ))
end

"""
    Deserialize JSON string to ServerEvent
"""
function from_json(json_str::String)::ServerEvent
    data = JSON.parse(json_str)
    return ServerEvent(
        data["id"],
        EventType(Symbol(data["type"])),
        DateTime(data["timestamp"], Dates.ISODateTimeFormat),
        data["payload"],
        data["source"]
    )
end

# ============================================================================
# Subscriber Pattern
# ============================================================================

"""
    EventSubscriber - Callback function for receiving events
"""
const EventSubscriber = Function  # Function that takes ServerEvent as argument

"""
    SubscriberEntry - Internal subscriber storage
"""
mutable struct SubscriberEntry
    id::String
    callback::EventSubscriber
    filter::Union{Set{EventType}, Nothing}  # Nothing = all events
    active::Bool
end

# Global state
const _subscribers = Vector{SubscriberEntry}()
const _subscribers_lock = ReentrantLock()

"""
    Subscribe to events
    
    # Arguments
    - callback::EventSubscriber: Function to call with events
    - filter::Union{Set{EventType}, Nothing}: Event types to receive (nothing = all)
    
    # Returns
    - String: Subscriber ID for unsubscribing
"""
function subscribe(
    callback::EventSubscriber;
    filter::Union{Set{EventType}, Nothing}=nothing
)::String
    lock(_subscribers_lock) do
        sub_id = string(uuid4())
        push!(_subscribers, SubscriberEntry(sub_id, callback, filter, true))
        return sub_id
    end
end

"""
    Unsubscribe from events
"""
function unsubscribe(subscriber_id::String)::Bool
    lock(_subscribers_lock) do
        for sub in _subscribers
            if sub.id == subscriber_id
                sub.active = false
                return true
            end
        end
        return false
    end
end

"""
    Broadcast event to all active subscribers
"""
function broadcast(event::ServerEvent)::Int
    count = 0
    lock(_subscribers_lock) do
        for sub in _subscribers
            if sub.active
                # Check filter
                if sub.filter !== nothing && event.type ∉ sub.filter
                    continue
                end
                try
                    sub.callback(event)
                    count += 1
                catch e
                    @error "Subscriber callback failed" exception=e subscriber=sub.id
                end
            end
        end
    end
    return count
end

# ============================================================================
# Event History Buffer
# ============================================================================

const DEFAULT_HISTORY_SIZE = 1000

mutable struct EventHistory
    events::Vector{ServerEvent}
    max_size::Int
    lock::ReentrantLock
end

"""
    Create a new event history buffer
"""
function create_history(max_size::Int=DEFAULT_HISTORY_SIZE)::EventHistory
    return EventHistory(
        ServerEvent[],
        max_size,
        ReentrantLock()
    )
end

const _global_history = create_history()

"""
    Add event to history buffer
"""
function add_to_history!(event::ServerEvent)::Nothing
    lock(_global_history.lock) do
        push!(_global_history.events, event)
        # Trim if over max size
        if length(_global_history.events) > _global_history.max_size
            _global_history.events = _global_history.events[end-_global_history.max_size+1:end]
        end
    end
    return nothing
end

"""
    Get recent events from history
"""
function get_history(n::Int=100; event_type::Union{EventType, Nothing}=nothing)::Vector{ServerEvent}
    lock(_global_history.lock) do
        events = _global_history.events
        if event_type !== nothing
            events = filter(e -> e.type == event_type, events)
        end
        return events[max(1, end-n+1):end]
    end
end

"""
    Clear event history
"""
function clear_history()::Nothing
    lock(_global_history.lock) do
        empty!(_global_history.events)
    end
    return nothing
end

# ============================================================================
# Convenience Broadcast Functions
# ============================================================================

"""
    Emit a thought event
"""
function emit_thought(thought::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("thought" => thought), metadata)
    event = create_event(EVENT_THOUGHT; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit an action event
"""
function emit_action(action::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("action" => action), metadata)
    event = create_event(EVENT_ACTION; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit a goal event
"""
function emit_goal(goal_id::String, status::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("goal_id" => goal_id, "status" => status), metadata)
    event = create_event(EVENT_GOAL; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit an error event
"""
function emit_error(error_message::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("error" => error_message), metadata)
    event = create_event(EVENT_ERROR; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit a status event
"""
function emit_status(status::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("status" => status), metadata)
    event = create_event(EVENT_STATUS; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit a message event (for chat)
"""
function emit_message(message::String, direction::String="outgoing"; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("message" => message, "direction" => direction), metadata)
    event = create_event(EVENT_MESSAGE; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

"""
    Emit a capability event
"""
function emit_capability(capability_id::String, action::String; metadata::Dict{String, Any}=Dict{String, Any}())::ServerEvent
    payload = merge!(Dict("capability_id" => capability_id, "action" => action), metadata)
    event = create_event(EVENT_CAPABILITY; payload=payload)
    add_to_history!(event)
    broadcast(event)
    return event
end

# ============================================================================
# Exports
# ============================================================================

export 
    # Types
    EventType,
    ServerEvent,
    # Creation
    create_event,
    to_json,
    from_json,
    # Subscriber management
    subscribe,
    unsubscribe,
    broadcast,
    # History
    EventHistory,
    create_history,
    add_to_history!,
    get_history,
    clear_history,
    # Convenience emitters
    emit_thought,
    emit_action,
    emit_goal,
    emit_error,
    emit_status,
    emit_message,
    emit_capability

end # module
