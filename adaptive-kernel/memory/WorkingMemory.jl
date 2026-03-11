"""
    WorkingMemory Module

# Baddeley's Working Memory Model

This module implements a computational model of working memory based on
Alan Baddeley's influential multi-component model of short-term memory.

## Theoretical Basis

Baddeley's model proposes working memory consists of multiple subsystems:

- **Phonological Loop**: Stores verbal information
- **Visuospatial Sketchpad**: Stores visual and spatial information  
- **Episodic Buffer**: Integrates information from multiple sources
- **Central Executive**: Controls attention and coordinates subsystems

This implementation models the core characteristics:

1. **Limited Capacity**: Based on Miller's "Magical Number 7±2" (default: 7)
2. **Attention-Based Selection**: Items compete for attentional resources
3. **Decay Over Time**: Information fades without rehearsal/refresh
4. **Active Maintenance**: Recently accessed items receive attention boosts

## Usage

```julia
using .WorkingMemory

wm = WorkingMemory()
push_to_working_memory!(wm, "task_context")
items = get_attended_items(wm)
```
"""
module WorkingMemory

export WorkingMemory, push_to_working_memory!, pop_from_working_memory, 
       decay_working_memory!, clear_working_memory!, get_attended_items,
       calculate_attention_weights

using Dates

# ============================================================================
# CORE STRUCTURES
# ============================================================================

"""
    WorkingMemory

A short-term working memory buffer implementing Baddeley's cognitive architecture.

# Fields
- `buffer::Vector{Any}`: Short-term storage for current context items
- `capacity::Int`: Maximum buffer size (default: 7, based on Miller's 7±2)
- `decay_rate::Float64`: How quickly items fade from memory (default: 0.1)
- `last_update::DateTime`: Timestamp for decay calculations

# Cognitive Science Basis
- **Capacity Limit**: Reflects the limited capacity of attentional resources
- **Decay Mechanism**: Models natural forgetting without rehearsal
- **Attention Tagging**: Items receive attention weights based on recency

# Example
```julia
wm = WorkingMemory(capacity=5, decay_rate=0.15)
push_to_working_memory!(wm, "current_task")
```
"""
mutable struct WorkingMemory{T}
    buffer::Vector{T}
    capacity::Int
    decay_rate::Float64
    last_update::DateTime
    
    """
        WorkingMemory(;capacity=7, decay_rate=0.1)
    
    Create a new working memory buffer.
    
    # Arguments
    - `capacity::Int`: Maximum items in buffer (default: 7, Miller's 7±2)
    - `decay_rate::Float64`: Per-second decay factor (default: 0.1)
    """
    function WorkingMemory(;capacity::Int=7, decay_rate::Float64=0.1)
        new{Any}(Any[], capacity, decay_rate, now())
    end
end

# ============================================================================
# PRIMITIVE OPERATIONS
# ============================================================================

"""
    push_to_working_memory!(wm::WorkingMemory, item)

Add an item to the working memory buffer with attention tagging.

# Cognitive Mechanism
When an item is pushed to working memory, it receives high attention weight.
If buffer exceeds capacity, oldest/least attended item is displaced (not 
instantly forgotten, but loses attention support).

# Arguments
- `wm::WorkingMemory`: The working memory buffer
- `item`: Any item to add to the buffer

# Returns
- The item that was added

# Example
```julia
wm = WorkingMemory()
push_to_working_memory!(wm, "task_goal")
push_to_working_memory!(wm, Dict("type" => "observation", "data" => x))
```
"""
function push_to_working_memory!(wm::WorkingMemory, item)
    # Create attention-tagged item entry
    entry = Dict{String, Any}(
        "content" => item,
        "attention" => 1.0,  # Full attention on new item
        "timestamp" => now(),
        "access_count" => 1
    )
    
    # If at capacity, decay all items and remove weakest
    if length(wm.buffer) >= wm.capacity
        decay_working_memory!(wm)
        
        # Find and remove lowest attention item (use in-place filter!)
        if !isempty(wm.buffer)
            min_attention = minimum(e["attention"] for e in wm.buffer)
            filter!(e -> e["attention"] != min_attention, wm.buffer)
        end
    end
    
    push!(wm.buffer, entry)
    wm.last_update = now()
    
    return item
end

"""
    pop_from_working_memory(wm::WorkingMemory)

Remove and return the most recent item from working memory.

# Cognitive Mechanism
Models retrieval from the "focus of attention" - the most recently 
accessed item is returned while maintaining the buffer structure.

# Arguments
- `wm::WorkingMemory`: The working memory buffer

# Returns
- The most recent item content, or `nothing` if buffer is empty

# Example
```julia
wm = WorkingMemory()
push_to_working_memory!(wm, "item1")
push_to_working_memory!(wm, "item2")
last_item = pop_from_working_memory(wm)  # Returns "item2"
```
"""
function pop_from_working_memory(wm::WorkingMemory)
    if isempty(wm.buffer)
        return nothing
    end
    
    # Get most recent item (highest timestamp)
    most_recent_idx = argmax(e -> e["timestamp"], wm.buffer)
    item = wm.buffer[most_recent_idx]["content"]
    
    # Remove from buffer
    deleteat!(wm.buffer, most_recent_idx)
    wm.last_update = now()
    
    return item
end

"""
    decay_working_memory!(wm::WorkingMemory)

Apply decay to attention weights of items in working memory.

# Cognitive Mechanism
Models the natural decay of information from working memory when not 
actively maintained through rehearsal. Items that aren't accessed 
or reinforced gradually lose attention support.

The decay is time-based: items that haven't been accessed for longer
periods lose attention faster.

# Arguments
- `wm::WorkingMemory`: The working memory buffer to decay

# Example
```julia
wm = WorkingMemory(decay_rate=0.2)
push_to_working_memory!(wm, "item1")
sleep(1)  # Simulate time passing
decay_working_memory!(wm)
```
"""
function decay_working_memory!(wm::WorkingMemory)
    current_time = now()
    elapsed_seconds = (current_time - wm.last_update).value / 1000.0
    
    for entry in wm.buffer
        # Calculate time since last access
        time_since_access = (current_time - entry["timestamp"]).value / 1000.0
        
        # Exponential decay based on time and decay rate
        decay_factor = exp(-wm.decay_rate * elapsed_seconds * 0.1)
        entry["attention"] = entry["attention"] * decay_factor
    end
    
    # Remove items that have fallen below attention threshold
    attention_threshold = 0.05
    wm.buffer = filter(e -> e["attention"] > attention_threshold, wm.buffer)
    
    wm.last_update = current_time
end

"""
    clear_working_memory!(wm::WorkingMemory)

Reset the working memory buffer to empty state.

# Cognitive Mechanism
Models a "clean slate" - perhaps after task completion or cognitive
reset. This is analogous to clearing the focus of attention.

# Arguments
- `wm::WorkingMemory`: The working memory buffer to clear

# Example
```julia
wm = WorkingMemory()
push_to_working_memory!(wm, "temporary_data")
clear_working_memory!(wm)  # Buffer is now empty
```
"""
function clear_working_memory!(wm::WorkingMemory)
    empty!(wm.buffer)
    wm.last_update = now()
end

# ============================================================================
# ATTENTION AND RETRIEVAL
# ============================================================================

"""
    get_attended_items(wm::WorkingMemory; threshold::Float64=0.3)

Return items with attention weight above threshold.

# Cognitive Mechanism
Models selective attention from working memory. Only items above the
attention threshold are "in the focus of attention" and available
for conscious processing.

# Arguments
- `wm::WorkingMemory`: The working memory buffer
- `threshold::Float64`: Minimum attention weight (default: 0.3)

# Returns
- Vector of items above attention threshold

# Example
```julia
wm = WorkingMemory()
push_to_working_memory!(wm, "important_task")
push_to_working_memory!(wm, "background_noise")
attended = get_attended_items(wm, threshold=0.5)
```
"""
function get_attended_items(wm::WorkingMemory; threshold::Float64=0.3)
    # Apply decay before retrieving
    decay_working_memory!(wm)
    
    # Filter items above threshold
    attended = [entry["content"] for entry in wm.buffer if entry["attention"] >= threshold]
    
    return attended
end

"""
    calculate_attention_weights(wm::WorkingMemory)

Compute salience scores for all items in working memory.

# Cognitive Mechanism
Calculates attention weights based on two factors:
1. **Recency**: More recently accessed items have higher weights
2. **Access Frequency**: Frequently accessed items are reinforced

The attention weight determines which items are available for 
conscious processing - the "spotlight" of attention.

# Arguments
- `wm::WorkingMemory`: The working memory buffer

# Returns
- Vector of tuples (item, attention_weight)

# Example
```julia
wm = WorkingMemory()
push_to_working_memory!(wm, "task1")
push_to_working_memory!(wm, "task2")
weights = calculate_attention_weights(wm)
```
"""
function calculate_attention_weights(wm::WorkingMemory)
    current_time = now()
    weights = []
    
    for entry in wm.buffer
        content = entry["content"]
        attention = entry["attention"]
        
        # Time-based recency component (within last minute)
        seconds_since = (current_time - entry["timestamp"]).value / 1000.0
        recency = exp(-seconds_since / 60.0)  # Decay over 60 seconds
        
        # Access count reinforcement
        access_boost = log(1 + entry["access_count"])
        
        # Combined salience score
        salience = attention * (0.7 * recency + 0.3 * access_boost)
        
        push!(weights, (content=content, attention=attention, salience=salience))
    end
    
    # Sort by salience (highest first)
    sort!(weights, by = x -> x.salience, rev = true)
    
    return weights
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    Base.length(wm::WorkingMemory)

Return the number of items in working memory.
"""
Base.length(wm::WorkingMemory) = length(wm.buffer)

"""
    Base.isempty(wm::WorkingMemory)

Check if working memory is empty.
"""
Base.isempty(wm::WorkingMemory) = isempty(wm.buffer)

"""
    capacity_remaining(wm::WorkingMemory)

Return remaining capacity in working memory buffer.
"""
function capacity_remaining(wm::WorkingMemory)
    return max(0, wm.capacity - length(wm.buffer))
end

end # module
