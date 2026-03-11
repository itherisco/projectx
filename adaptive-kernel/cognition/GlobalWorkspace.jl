# cognition/GlobalWorkspace.jl - Global Workspace Theory Implementation
# Based on Bernard Baars' Global Workspace Theory (GWT)
# The "consciousness" system that allows specialized modules to share information

"""
    GlobalWorkspace Module

# Bernard Baars' Global Workspace Theory (GWT)

This module implements the Global Workspace Theory of consciousness, which 
proposes that consciousness functions like a "theatre" where specialized 
modules can share information through a central workspace.

## Theoretical Basis

Global Workspace Theory proposes:

1. **The Stage**: Unconscious specialized modules process information in parallel,
   each handling specific tasks (vision, language, planning, etc.)

2. **The Spotlight**: Only one piece of information reaches conscious awareness
   at a time - this is the "spotlight" of attention

3. **The Broadcast**: When content enters the spotlight, it's broadcast to ALL
   subsystems, allowing them to respond, collaborate, or compete

4. **Competition**: Multiple modules may compete for the spotlight based on:
   - Importance/urgency (salience)
   - Contextual relevance
   - Recent activation history
   - Strategic value

This architecture allows:
- Flexible, adaptive behavior through module cooperation
- Coherent action selection despite parallel processing
- "Conscious" decision-making through competitive broadcasting
- Integration of diverse information sources into unified experience

## Usage

```julia
using .GlobalWorkspace

gw = create_workspace()
subscribe!(gw, "VisionProcessor"; priority=PRIORITY_NORMAL)
result = broadcast_content(gw, "User typing", "VisionProcessor"; importance=0.6)
conscious = get_conscious_content(gw)
```
"""
module GlobalWorkspace

using Dates
using UUIDs

# ============================================================================
# THEATRE METAPHOR EXPLANATION
# ============================================================================
#
# Global Workspace Theory (GWT) proposes that consciousness functions like a
# "theatre" where:
#
# 1. THE STAGE: Unconscious specialized modules (subsystems) process information
#    in parallel, each handling specific tasks (vision, language, planning, etc.)
#
# 2. THE SPOTLIGHT: Only one piece of information reaches the "stage" at a time -
#    this is conscious awareness. The spotlight can shift rapidly.
#
# 3. THE BROADCAST: When content enters the spotlight, it's broadcast to ALL
#    subsystems, allowing them to respond, collaborate, or compete.
#
# 4. COMPETITION: Multiple modules may compete for the spotlight. The competition
#    is based on:
#    - Importance/urgency (salience)
#    - Contextual relevance
#    - Recent activation history
#    - Strategic value
#
# This architecture allows:
# - Flexible, adaptive behavior through module cooperation
# - Coherent action selection despite parallel processing
# - "Conscious" decision-making through competitive broadcasting
# - Integration of diverse information sources into unified experience
#
# ============================================================================

export
    # Types
    WorkspaceContent,
    GlobalWorkspace,
    Subscriber,
    SubscriberPriority,
    
    # Operations
    subscribe!,
    unsubscribe!,
    broadcast_content,
    compete_for_consciousness,
    get_conscious_content,
    clear_workspace,
    get_broadcast_history,
    create_workspace,
    get_workspace_status,
    add_competing_content!

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    SubscriberPriority

Priority levels for subscribers in the competition for consciousness.
Higher priority subscribers have their content more likely to be broadcast.
"""
@enum SubscriberPriority begin
    PRIORITY_CRITICAL = 3   # Life-threatening, urgent safety concerns
    PRIORITY_HIGH = 2       # Important system needs
    PRIORITY_NORMAL = 1     # Standard processing
    PRIORITY_LOW = 0        # Background processes
end

"""
    Subscriber - A cognitive module that receives broadcasts from the Global Workspace

Represents a specialized processing module (e.g., vision, language, planning)
that can both submit content for broadcasting and receive broadcast content.

# Fields
- `id::UUID`: Unique identifier for this subscriber
- `name::String`: Human-readable name (e.g., "VisionProcessor", "Planner")
- `priority::SubscriberPriority`: Base priority level
- `current_activation::Float64`: Current activation level (0-1)
- `receive_callback::Union{Function, Nothing}`: Optional callback for receiving broadcasts
- `last_broadcast_time::Union{DateTime, Nothing}`: When this subscriber last won the competition
"""
mutable struct Subscriber
    id::UUID
    name::String
    priority::SubscriberPriority
    current_activation::Float64
    receive_callback::Union{Function, Nothing}
    last_broadcast_time::Union{DateTime, Nothing}
    
    Subscriber(
        name::String;
        priority::SubscriberPriority = PRIORITY_NORMAL,
        receive_callback::Union{Function, Nothing} = nothing
    ) = new(uuid4(), name, priority, 0.0, receive_callback, nothing)
end

"""
    WorkspaceContent - Content being broadcast through the Global Workspace

Represents a piece of information that is competing for or has achieved
conscious awareness (the "spotlight").

# Fields
- `id::UUID`: Unique identifier
- `content::Any`: The actual content (can be any Julia object)
- `source_module::String`: Name of the module that generated this content
- `importance::Float64`: Importance score (0-1) for competition
- `timestamp::DateTime`: When this content was created
- `context::Dict{String, Any}`: Additional context metadata
- `is_conscious::Bool`: Whether this content currently has the spotlight
- `thought_cycle::Union{ThoughtCycle, Nothing}`: Associated ThoughtCycle if any
"""
mutable struct WorkspaceContent
    id::UUID
    content::Any
    source_module::String
    importance::Float64
    timestamp::DateTime
    context::Dict{String, Any}
    is_conscious::Bool
    thought_cycle::Union{Nothing, Any}  # ThoughtCycle type from main types.jl
    
    WorkspaceContent(
        content::Any,
        source_module::String;
        importance::Float64 = 0.5,
        context::Dict = Dict{String, Any}(),
        thought_cycle::Union{Nothing, Any} = nothing
    ) = new(
        uuid4(),
        content,
        source_module,
        clamp(importance, 0.0, 1.0),
        now(),
        context,
        false,
        thought_cycle
    )
end

"""
    GlobalWorkspace - The broadcast mechanism implementing Global Workspace Theory

This is the central "theatre" where content competes for the spotlight of consciousness
and is broadcast to all subscribers.

# Fields
- `id::UUID`: Unique identifier
- `subscribers::Vector{Subscriber}`: Registered cognitive modules
- `content_history::Vector{WorkspaceContent}`: Past broadcasts
- `competing_content::Vector{WorkspaceContent}`: Content currently competing for consciousness
- `current_conscious_content::Union{WorkspaceContent, Nothing}`: The current spotlight content
- `broadcast_count::Int`: Total number of broadcasts
- `competition_threshold::Float64`: Minimum importance to enter competition
- `attention_decay::Float64`: How fast attention shifts (seconds)
- `max_history::Int`: Maximum history to retain
"""
mutable struct GlobalWorkspace
    id::UUID
    subscribers::Vector{Subscriber}
    content_history::Vector{WorkspaceContent}
    competing_content::Vector{WorkspaceContent}
    current_conscious_content::Union{WorkspaceContent, Nothing}
    broadcast_count::Int
    competition_threshold::Float64
    attention_decay::Float64  # seconds before attention can shift
    max_history::Int
    
    GlobalWorkspace(;
        competition_threshold::Float64 = 0.3,
        attention_decay::Float64 = 0.1,
        max_history::Int = 100
    ) = new(
        uuid4(),
        Subscriber[],
        WorkspaceContent[],
        WorkspaceContent[],
        nothing,
        0,
        competition_threshold,
        attention_decay,
        max_history
    )
end

# ============================================================================
# CONSTRUCTOR FUNCTIONS
# ============================================================================

"""
    create_workspace(; kwargs...) -> GlobalWorkspace

Create a new Global Workspace with optional configuration.

# Arguments
- `competition_threshold::Float64`: Minimum importance to enter competition (default: 0.3)
- `attention_decay::Float64`: Seconds before attention can shift (default: 0.1)
- `max_history::Int`: Maximum broadcast history to retain (default: 100)

# Example
```julia
gw = create_workspace(attention_decay=0.5, max_history=50)
```
"""
function create_workspace(;
    competition_threshold::Float64 = 0.3,
    attention_decay::Float64 = 0.1,
    max_history::Int = 100
)::GlobalWorkspace
    return GlobalWorkspace(
        competition_threshold = competition_threshold,
        attention_decay = attention_decay,
        max_history = max_history
    )
end

# ============================================================================
# SUBSCRIBER MANAGEMENT
# ============================================================================

"""
    subscribe!(gw::GlobalWorkspace, name::String; priority, callback) -> Subscriber

Register a cognitive module to receive broadcasts from the Global Workspace.

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace
- `name::String`: Name of the subscribing module
- `priority::SubscriberPriority`: Priority level (default: PRIORITY_NORMAL)
- `callback::Union{Function, Nothing}`: Optional callback when content is received

# Returns
- `Subscriber`: The created subscriber

# Example
```julia
# Simple subscription
vision_sub = subscribe!(gw, "VisionProcessor")

# With priority and callback
planner_sub = subscribe!(gw, "Planner"; priority=PRIORITY_HIGH, callback=handle_broadcast)
```
"""
function subscribe!(
    gw::GlobalWorkspace,
    name::String;
    priority::SubscriberPriority = PRIORITY_NORMAL,
    callback::Union{Function, Nothing} = nothing
)::Subscriber
    # Check if subscriber with same name already exists
    for sub in gw.subscribers
        if sub.name == name
            sub.priority = priority
            sub.receive_callback = callback
            return sub
        end
    end
    
    subscriber = Subscriber(name; priority = priority, receive_callback = callback)
    push!(gw.subscribers, subscriber)
    return subscriber
end

"""
    unsubscribe!(gw::GlobalWorkspace, name::String) -> Bool

Remove a subscriber from the Global Workspace.

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace
- `name::String`: Name of the subscriber to remove

# Returns
- `Bool`: Whether the subscriber was found and removed

# Example
```julia
unsubscribe!(gw, "VisionProcessor")
```
"""
function unsubscribe!(gw::GlobalWorkspace, name::String)::Bool
    for (i, sub) in enumerate(gw.subscribers)
        if sub.name == name
            deleteat!(gw.subscribers, i)
            return true
        end
    end
    return false
end

"""
    unsubscribe!(gw::GlobalWorkspace, subscriber::Subscriber) -> Bool

Remove a subscriber by reference.
"""
function unsubscribe!(gw::GlobalWorkspace, subscriber::Subscriber)::Bool
    return unsubscribe!(gw, subscriber.name)
end

# ============================================================================
# COMPETITION AND BROADCAST
# ============================================================================

"""
    add_competing_content!(gw::GlobalWorkspace, content::WorkspaceContent) -> Bool

Add content to the competition pool for consciousness.

This is typically called by subsystems that have processed information
and want to compete for the spotlight of attention.
"""
function add_competing_content!(gw::GlobalWorkspace, content::WorkspaceContent)::Bool
    if content.importance >= gw.competition_threshold
        push!(gw.competing_content, content)
        return true
    end
    return false
end

"""
    compete_for_consciousness(gw::GlobalWorkspace) -> Union{WorkspaceContent, Nothing}

The competition process where modules vie for the spotlight of consciousness.

Competition is based on:
1. Content importance score
2. Subscriber priority level  
3. Current activation of the source module
4. Recency (recent broadcasts have advantage)

The winner becomes the "conscious" content and is broadcast to all subscribers.

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace

# Returns
- `Union{WorkspaceContent, Nothing}`: The winning content or nothing if no valid competitors
"""
function compete_for_consciousness(gw::GlobalWorkspace)::Union{WorkspaceContent, Nothing}
    if isempty(gw.competing_content)
        return nothing
    end
    
    # Check if enough time has passed since last attention shift
    if gw.current_conscious_content !== nothing
        last_time = gw.current_conscious_content.timestamp
        elapsed = (now() - last_time).value / 1000.0  # Convert to seconds
        if elapsed < gw.attention_decay
            return gw.current_conscious_content
        end
    end
    
    # Calculate competition scores
    scores = Float64[]
    for content in gw.competing_content
        # Find subscriber
        subscriber_score = 0.5  # Default
        for sub in gw.subscribers
            if sub.name == content.source_module
                subscriber_score = 0.5 + (Int(sub.priority) / 6.0)  # Priority adds to score
                break
            end
        end
        
        # Combined score: importance weighted by subscriber priority
        final_score = content.importance * subscriber_score
        push!(scores, final_score)
    end
    
    # Find winner (highest score)
    if isempty(scores)
        return nothing
    end
    
    winner_idx = argmax(scores)
    winner_content = gw.competing_content[winner_idx]
    
    # Mark as conscious
    winner_content.is_conscious = true
    
    # Update source subscriber's last broadcast time
    for sub in gw.subscribers
        if sub.name == winner_content.source_module
            sub.last_broadcast_time = now()
            break
        end
    end
    
    # Clear from competing content
    deleteat!(gw.competing_content, winner_idx)
    
    # Set as current conscious content
    gw.current_conscious_content = winner_content
    gw.broadcast_count += 1
    
    return winner_content
end

"""
    broadcast(gw::GlobalWorkspace, content::Any, source_module::String; importance, context, thought_cycle) -> Union{WorkspaceContent, Nothing}

Send content to all subscribers through the Global Workspace.

This is the main entry point for content to enter the "theatre".
The content enters the competition and if it wins, gets broadcast to all subscribers.

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace
- `content::Any`: The content to broadcast
- `source_module::String`: Name of the source module
- `importance::Float64`: Importance score (0-1), default 0.5
- `context::Dict{String, Any}`: Additional context, default empty
- `thought_cycle::Union{Nothing, Any}`: Associated ThoughtCycle if any

# Returns
- `Union{WorkspaceContent, Nothing}`: The broadcast content if it won competition

# Example
```julia
# Simple broadcast
result = broadcast(gw, "Planning to execute action X", "Planner")

# High importance broadcast (emergency)
result = broadcast(gw, "CRITICAL: Safety boundary violated!", "SafetyMonitor"; importance=0.95)
```
"""
function broadcast_content(
    gw::GlobalWorkspace,
    content::Any,
    source_module::String;
    importance::Float64 = 0.5,
    context::Dict = Dict{String, Any}(),
    thought_cycle::Union{Nothing, Any} = nothing
)::Union{WorkspaceContent, Nothing}
    
    # Create workspace content
    workspace_content = WorkspaceContent(
        content,
        source_module;
        importance = importance,
        context = context,
        thought_cycle = thought_cycle
    )
    
    # Add to competition
    add_competing_content!(gw, workspace_content)
    
    # Run competition
    winner = compete_for_consciousness(gw)
    
    if winner !== nothing && winner.id == workspace_content.id
        # This content won - broadcast to all subscribers
        _deliver_to_subscribers(gw, winner)
        
        # Add to history
        push!(gw.content_history, winner)
        
        # Trim history if needed
        if length(gw.content_history) > gw.max_history
            gw.content_history = gw.content_history[end-gw.max_history+1:end]
        end
        
        return winner
    end
    
    return nothing
end

"""
    _deliver_to_subscribers(gw::GlobalWorkspace, content::WorkspaceContent)

Internal function to deliver broadcast content to all subscribers.
"""
function _deliver_to_subscribers(gw::GlobalWorkspace, content::WorkspaceContent)
    for subscriber in gw.subscribers
        if subscriber.receive_callback !== nothing
            try
                subscriber.receive_callback(content)
            catch e
                # Silently handle callback errors
            end
        end
    end
end

# ============================================================================
# QUERY FUNCTIONS
# ============================================================================

"""
    get_conscious_content(gw::GlobalWorkspace) -> Union{WorkspaceContent, Nothing}

Get the current conscious content (the spotlight).

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace

# Returns
- `Union{WorkspaceContent, Nothing}`: The current conscious content or nothing
"""
function get_conscious_content(gw::GlobalWorkspace)::Union{WorkspaceContent, Nothing}
    return gw.current_conscious_content
end

"""
    get_broadcast_history(gw::GlobalWorkspace; limit::Int = 10) -> Vector{WorkspaceContent}

Get past broadcasts from the workspace history.

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace
- `limit::Int`: Maximum number of entries to return (default: 10)

# Returns
- `Vector{WorkspaceContent}`: Recent broadcast history (most recent last)
"""
function get_broadcast_history(gw::GlobalWorkspace; limit::Int = 10)::Vector{WorkspaceContent}
    n = min(limit, length(gw.content_history))
    return gw.content_history[end-n+1:end]
end

"""
    clear_workspace(gw::GlobalWorkspace; clear_history::Bool = false)

Clear the workspace - reset conscious content and optionally history.

This effectively "clears the stage" - useful for:
- Starting fresh processing cycles
- Recovering from errors
- Resetting attention

# Arguments
- `gw::GlobalWorkspace`: The Global Workspace
- `clear_history::Bool`: Whether to also clear broadcast history (default: false)
"""
function clear_workspace(gw::GlobalWorkspace; clear_history::Bool = false)
    gw.current_conscious_content = nothing
    empty!(gw.competing_content)
    
    if clear_history
        empty!(gw.content_history)
    end
end

"""
    get_workspace_status(gw::GlobalWorkspace) -> Dict{String, Any}

Get the current status of the workspace for debugging/monitoring.
"""
function get_workspace_status(gw::GlobalWorkspace)::Dict{String, Any}
    return Dict{String, Any}(
        "subscriber_count" => length(gw.subscribers),
        "competing_content_count" => length(gw.competing_content),
        "broadcast_count" => gw.broadcast_count,
        "history_size" => length(gw.content_history),
        "has_conscious_content" => gw.current_conscious_content !== nothing,
        "conscious_source" => gw.current_conscious_content !== nothing ? 
            gw.current_conscious_content.source_module : nothing,
        "competition_threshold" => gw.competition_threshold,
        "attention_decay" => gw.attention_decay
    )
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    Base.show(io::IO, sub::Subscriber)
"""
function Base.show(io::IO, sub::Subscriber)
    print(io, "Subscriber(\"$(sub.name)\"; priority=$(sub.priority), activation=$(sub.current_activation))")
end

"""
    Base.show(io::IO, content::WorkspaceContent)
"""
function Base.show(io::IO, content::WorkspaceContent)
    status = content.is_conscious ? "CONSCIOUS" : "unconscious"
    print(io, "WorkspaceContent(\"$(content.source_module)\"; importance=$(content.importance), $status)")
end

"""
    Base.show(io::IO, gw::GlobalWorkspace)
"""
function Base.show(io::IO, gw::GlobalWorkspace)
    conscious = gw.current_conscious_content !== nothing ? 
        gw.current_conscious_content.source_module : "none"
    print(io, "GlobalWorkspace(subscribers=$(length(gw.subscribers)), broadcasts=$(gw.broadcast_count), conscious=$conscious)")
end

# Alias for broadcast_content (avoids conflict with Base.Broadcast)
const broadcast = broadcast_content

end # module GlobalWorkspace
