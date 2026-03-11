# cognition/Attention.jl - Attention Module for Cognitive System
# Based on Michael Posner's Attention Model and Bottleneck Theory
# Implements the cognitive control system that determines processing priority

module Attention

using Dates
using UUIDs

# ============================================================================
# THEORETICAL BASIS: POSNER'S ATTENTION MODEL
# ============================================================================
#
# Michael Posner's model of attention identifies three distinct but interacting
# components:
#
# 1. **ALERTING** (Vigilance/Phasic Alertness)
#    - Maintaining a vigilant, receptive state
#    - Readiness to process incoming information
#    - "Wakefulness" or general arousal
#    - Implemented via: alerting_level, alertness_decay
#
# 2. **ORIENTING** (Selective Attention)
#    - Selecting information from a specific sensory channel
#    - The "spotlight" metaphor - focusing on specific input
#    - Filtering out irrelevant stimuli
#    - Implemented via: current_focus, attention_allocation
#
# 3. **EXECUTIVE CONTROL** (Conflict Resolution)
#    - Monitoring and resolving conflicts between competing stimuli
#    - Top-down goal-directed attention
#    - Override of automatic responses
#    - Implemented via: attention_budget, filter, priority_inheritance
#
# BOTTLENECK THEORY:
# - Attention acts as a bottleneck preventing information overload
# - Limited processing capacity must be allocated wisely
# - Competition between stimuli for access to limited resources
# - Can be divided (divided attention) or focused (focused attention)
#
# COGNITIVE INTEGRATION:
# - Works with WorkingMemory for short-term information storage
# - Works with GlobalWorkspace for conscious broadcasting
# - Priority inheritance from goals and emotional states
#
# ============================================================================

export
    # Types
    AttentionalPriority,
    AttentionSource,
    AttentionItem,
    AttentionSystem,
    AttentionalControl,
    
    # Operations
    allocate_attention!,
    shift_attention!,
    divide_attention,
    suppress_distraction!,
    get_current_focus,
    calculate_attentional_demand,
    release_attention!,
    create_attention_system,
    add_attention_demand!,
    remove_attention_demand!,
    get_attention_status,
    update_alertness!,
    apply_attentional_filter

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    AttentionalPriority

Priority levels for attentional allocation, from most urgent to least.
Based on survival value and goal relevance.
"""
@enum AttentionalPriority begin
    PRIORITY_CRITICAL = 4   # Survival/emergency - immediate processing required
    PRIORITY_HIGH = 3       # High importance - goal relevant
    PRIORITY_NORMAL = 2     # Standard processing - default priority
    PRIORITY_LOW = 1        # Background - can be delayed
    PRIORITY_IGNORED = 0    # Filtered out - receives no attention
end

"""
    AttentionSource

The source of attentional demand, determining where the demand originates.
This affects how the attention system weighs competing stimuli.
"""
@enum AttentionSource begin
    SOURCE_EXTERNAL = 1     # External stimuli (sensory input)
    SOURCE_INTERNAL = 2    # Internal processes (thoughts, memories)
    SOURCE_GOAL = 3         # Goal-directed (task-relevant)
    SOURCE_EMOTION = 4      # Emotional salience (fear, joy, etc.)
    SOURCE_SELF = 5         # Self-generated (imagination, planning)
end

"""
    AttentionItem

An item competing for attentional resources in the cognitive system.

# Fields
- `id::UUID`: Unique identifier
- `content::Any`: The actual content/item competing for attention
- `source::AttentionSource`: Origin of this attentional demand
- `priority::AttentionalPriority`: Current priority level
- `salience::Float64`: Computed salience score [0, 1]
- `created_at::DateTime`: When this item entered competition
- `last_accessed::DateTime`: Last time this item was attended
- `attention_weight::Float64`: Current attention allocation [0, 1]
- `is_focused::Bool`: Whether this item currently has focus
- `competing::Bool`: Whether item is actively competing
- `tags::Vector{String}: Metadata tags for filtering
"""
mutable struct AttentionItem
    id::UUID
    content::Any
    source::AttentionSource
    priority::AttentionalPriority
    salience::Float64
    created_at::DateTime
    last_accessed::DateTime
    attention_weight::Float64
    is_focused::Bool
    competing::Bool
    tags::Vector{String}
    
    function AttentionItem(
        content::Any;
        source::AttentionSource = SOURCE_INTERNAL,
        priority::AttentionalPriority = PRIORITY_NORMAL,
        salience::Float64 = 0.5,
        tags::Vector{String} = String[]
    )
        new(
            UUIDs.uuid4(),
            content,
            source,
            priority,
            salience,
            now(),
            now(),
            0.0,
            false,
            true,
            tags
        )
    end
end

"""
    AttentionSystem

The central attentional control system implementing Posner's model.

This struct manages the allocation of limited attentional resources,
implementing the three components of Posner's model:
- Alerting: Maintaining vigilance/alertness state
- Orienting: Directing the "spotlight" of attention
- Executive: Resolving conflicts between competing demands

# Fields
- `current_focus::Union{AttentionItem, Nothing}`: Currently focused item
- `attention_budget::Float64`: Total available attention [0, 1]
- `allocated_budget::Float64`: Currently allocated attention
- `demands::Vector{AttentionItem}`: All competing demands
- `filter::Vector{String}`: Tags to filter out
- `alerting_level::Float64`: Current alertness [0, 1]
- `orienting_speed::Float64`: How fast focus can shift [0, 1]
- `executive_capacity::Float64`: Conflict resolution capacity [0, 1]
- `last_update::DateTime`: Last update timestamp
- `focus_history::Vector{UUID}`: Recent focus targets
- `attention_cost::Float64`: Accumulated attention cost
"""
mutable struct AttentionSystem
    current_focus::Union{AttentionItem, Nothing}
    attention_budget::Float64
    allocated_budget::Float64
    demands::Vector{AttentionItem}
    filter::Vector{String}
    alerting_level::Float64
    orienting_speed::Float64
    executive_capacity::Float64
    last_update::DateTime
    focus_history::Vector{UUID}
    attention_cost::Float64
    
    function AttentionSystem(;
        attention_budget::Float64 = 1.0,
        alerting_level::Float64 = 0.8,
        orienting_speed::Float64 = 0.9,
        executive_capacity::Float64 = 0.9
    )
        new(
            nothing,
            attention_budget,
            0.0,
            AttentionItem[],
            String[],
            alerting_level,
            orienting_speed,
            executive_capacity,
            now(),
            UUID[],
            0.0
        )
    end
end

# ============================================================================
# CORE OPERATIONS
# ============================================================================

"""
    create_attention_system(;kwargs...)

Create a new attention system with default or custom parameters.

# Arguments (all keyword)
- `attention_budget::Float64 = 1.0`: Total attention capacity
- `alerting_level::Float64 = 0.8`: Initial alertness
- `orienting_speed::Float64 = 0.9`: Speed of attentional shifts
- `executive_capacity::Float64 = 0.9`: Conflict resolution capacity

# Example
```julia
system = create_attention_system(alerting_level=0.9)
```
"""
function create_attention_system(;
    attention_budget::Float64 = 1.0,
    alerting_level::Float64 = 0.8,
    orienting_speed::Float64 = 0.9,
    executive_capacity::Float64 = 0.9
)::AttentionSystem
    return AttentionSystem(
        attention_budget=attention_budget,
        alerting_level=alerting_level,
        orienting_speed=orienting_speed,
        executive_capacity=executive_capacity
    )
end

"""
    allocate_attention!(system::AttentionSystem, item::AttentionItem)

Allocate attention resources to an item.

This implements the **orienting** component of Posner's model - 
selecting which information receives processing priority.

# Cognitive Mechanism
When attention is allocated to an item:
1. Item's attention_weight increases based on salience and priority
2. Item competes with other demands for the focus spotlight
3. Total allocated budget is updated
4. If no focus exists, item may become focused

# Arguments
- `system::AttentionSystem`: The attention system
- `item::AttentionItem`: The item to allocate attention to

# Returns
- The allocated attention weight

# Example
```julia
item = AttentionItem("urgent_task", source=SOURCE_GOAL, priority=PRIORITY_HIGH, salience=0.9)
weight = allocate_attention!(system, item)
```
"""
function allocate_attention!(system::AttentionSystem, item::AttentionItem)::Float64
    # Update last accessed time
    item.last_accessed = now()
    
    # Calculate attention allocation based on multiple factors
    priority_weight = Float64(Int(item.priority)) / 4.0  # Normalize to [0, 1]
    salience_weight = item.salience
    
    # Source weighting - goal-directed attention gets boost
    source_weight = item.source == SOURCE_GOAL ? 1.2 : 1.0
    
    # Calculate final allocation
    raw_allocation = priority_weight * salience_weight * source_weight * system.alerting_level
    
    # Apply executive capacity constraint
    executive_factor = system.executive_capacity
    allocation = min(raw_allocation * executive_factor, system.attention_budget - system.allocated_budget)
    
    # Update item
    item.attention_weight = allocation
    
    # Add to demands if not already there
    if !any(d.id == item.id for d in system.demands)
        push!(system.demands, item)
    end
    
    # Update allocated budget
    system.allocated_budget += allocation
    system.last_update = now()
    
    # If this is the only high-priority item and no focus, make it focused
    if system.current_focus === nothing && allocation > 0.3
        item.is_focused = true
        system.current_focus = item
    end
    
    return allocation
end

"""
    shift_attention!(system::AttentionSystem, new_item::AttentionItem; kwargs...)

Shift the focus of attention to a new item.

This implements the **orienting** component - the "spotlight" moving
to a new location/target.

# Cognitive Mechanism
Attentional shifts are not instantaneous - they take time based on:
1. The orienting_speed of the system
2. Similarity between old and new targets
3. Cognitive load during transition

# Arguments
- `system::AttentionSystem`: The attention system
- `new_item::AttentionItem`: The new item to focus on
- `cost::Float64 = 0.1`: Cognitive cost of shifting

# Returns
- The shift cost incurred

# Example
```julia
new_task = AttentionItem("new_urgent_task", priority=PRIORITY_CRITICAL)
cost = shift_attention!(system, new_task)
```
"""
function shift_attention!(system::AttentionSystem, new_item::AttentionItem; cost::Float64 = 0.1)::Float64
    old_item = system.current_focus
    
    # Calculate shift cost based on orienting speed
    shift_difficulty = 1.0 - system.orienting_speed
    
    if old_item !== nothing
        # Old item loses focus
        old_item.is_focused = false
        old_item.attention_weight *= 0.5  # Decay when losing focus
        
        # Add to history
        push!(system.focus_history, old_item.id)
        if length(system.focus_history) > 10
            popfirst!(system.focus_history)
        end
    end
    
    # Allocate attention to new item
    allocate_attention!(system, new_item)
    
    # Set as new focus
    new_item.is_focused = true
    system.current_focus = new_item
    
    # Calculate actual cost (higher if difficult to shift)
    actual_cost = cost * shift_difficulty
    system.attention_cost += actual_cost
    
    # Decay alertness after shift (mental effort)
    system.alerting_level = max(0.3, system.alerting_level - 0.05)
    
    return actual_cost
end

"""
    divide_attention(system::AttentionSystem, items::Vector{AttentionItem})

Split attention across multiple items (divided attention).

This models the limited capacity of attention - can process multiple
items but with reduced efficiency per item.

# Cognitive Mechanism
Divided attention is less efficient than focused attention:
- Each additional item receives less attention weight
- Total allocation cannot exceed attention_budget
- Executive capacity constrains how many items can be attended

# Arguments
- `system::AttentionSystem`: The attention system
- `items::Vector{AttentionItem}`: Items to divide attention among

# Returns
- Vector of attention weights for each item

# Example
```julia
items = [AttentionItem("task1"), AttentionItem("task2")]
weights = divide_attention(system, items)
```
"""
function divide_attention(system::AttentionSystem, items::Vector{AttentionItem})::Vector{Float64}
    n_items = length(items)
    
    if n_items == 0
        return Float64[]
    end
    
    if n_items == 1
        return [allocate_attention!(system, items[1])]
    end
    
    # Calculate available budget
    available = system.attention_budget - system.allocated_budget
    
    # Executive capacity limits divided attention
    max_divisible = min(n_items, Int(ceil(system.executive_capacity * 5)))
    
    # Efficiency decay for each additional item
    efficiency_factor = 1.0 / sqrt(n_items)
    
    # Allocate proportionally based on priority
    weights = Float64[]
    for item in items[1:max_divisible]
        # Calculate base allocation
        priority_weight = Float64(Int(item.priority)) / 4.0
        raw_allocation = available * priority_weight * efficiency_factor * system.alerting_level
        
        # Ensure minimum for each attended item
        allocation = max(0.1, min(raw_allocation, available / max_divisible))
        
        item.attention_weight = allocation
        item.is_focused = false  # Not fully focused when divided
        
        if !any(d.id == item.id for d in system.demands)
            push!(system.demands, item)
        end
        
        push!(weights, allocation)
        system.allocated_budget += allocation
    end
    
    # For items beyond capacity, set to zero
    for i in (max_divisible+1):n_items
        items[i].attention_weight = 0.0
        items[i].is_focused = false
        push!(weights, 0.0)
    end
    
    system.last_update = now()
    system.current_focus = nothing  # No single focus when divided
    
    return weights
end

"""
    suppress_distraction!(system::AttentionSystem, distraction::AttentionItem)

Filter out irrelevant stimuli from attentional competition.

This implements selective attention - the ability to ignore distractions
and focus on task-relevant information.

# Cognitive Mechanism
Suppression involves:
1. Adding distraction to filter list (bottom-up suppression)
2. Reducing its attention weight to zero
3. Potentially increasing priority of relevant items

# Arguments
- `system::AttentionSystem`: The attention system
- `distraction::AttentionItem`: The item to suppress

# Example
```julia
noise = AttentionItem("background_noise", priority=PRIORITY_LOW, tags=["distraction"])
suppress_distraction!(system, noise)
```
"""
function suppress_distraction!(system::AttentionSystem, distraction::AttentionItem)
    # Add tags to filter
    for tag in distraction.tags
        if tag ∉ system.filter
            push!(system.filter, tag)
        end
    end
    
    # Mark as not competing
    distraction.competing = false
    distraction.attention_weight = 0.0
    distraction.priority = PRIORITY_IGNORED
    
    # Remove from demands
    filter!(d -> d.id != distraction.id, system.demands)
    
    # If this was focused, shift attention
    if system.current_focus !== nothing && system.current_focus.id == distraction.id
        # Try to find another high-priority item
        remaining = filter(d -> d.competing && d.priority >= PRIORITY_NORMAL, system.demands)
        if !isempty(remaining)
            # Shift to highest priority
            next_item = first(sort(remaining, by = x -> Int(x.priority), rev = true))
            shift_attention!(system, next_item, cost=0.05)
        else
            system.current_focus = nothing
        end
    end
    
    system.last_update = now()
end

"""
    get_current_focus(system::AttentionSystem)

Get the currently focused item in attention.

# Arguments
- `system::AttentionSystem`: The attention system

# Returns
- The focused item, or nothing if attention is divided or no focus
"""
function get_current_focus(system::AttentionSystem)::Union{AttentionItem, Nothing}
    return system.current_focus
end

"""
    calculate_attentional_demand(system::AttentionSystem)

Calculate total attentional demand from all competing items.

This sums up the attention requirements of all items currently
competing for attentional resources.

# Cognitive Mechanism
Demand calculation considers:
1. Individual item salience and priority
2. Source of demand (goal-directed > emotion > internal > external)
3. Current alertness level affects perceived demand

# Arguments
- `system::AttentionSystem`: The attention system

# Returns
- Total demand as Float64 [0, ∞), where 1.0 = full capacity

# Example
```julia
demand = calculate_attentional_demand(system)
if demand > system.attention_budget
    println("Attention overload - need to suppress some demands")
end
```
"""
function calculate_attentional_demand(system::AttentionSystem)::Float64
    total_demand = 0.0
    
    for item in system.demands
        if item.competing && item.priority > PRIORITY_IGNORED
            # Calculate demand for this item
            priority_factor = Float64(Int(item.priority))
            source_factor = item.source == SOURCE_GOAL ? 1.5 : 
                           item.source == SOURCE_EMOTION ? 1.3 : 1.0
            
            demand = item.salience * priority_factor * source_factor
            total_demand += demand
        end
    end
    
    # Adjust for alertness
    total_demand /= system.alerting_level
    
    return total_demand
end

"""
    release_attention!(system::AttentionSystem, item::AttentionItem)

Release attention from an item, freeing up attentional resources.

# Cognitive Mechanism
When attention is released:
1. Item's attention weight goes to zero
2. Item no longer competes for focus
3. Allocated budget is reduced
4. If was focused, new focus must be selected

# Arguments
- `system::AttentionSystem`: The attention system
- `item::AttentionItem`: The item to release

# Example
```julia
completed_task = AttentionItem("finished_task")
release_attention!(system, completed_task)
```
"""
function release_attention!(system::AttentionSystem, item::AttentionItem)
    # Reduce allocated budget
    system.allocated_budget = max(0.0, system.allocated_budget - item.attention_weight)
    
    # Reset item
    item.attention_weight = 0.0
    item.is_focused = false
    item.competing = false
    
    # Remove from demands
    filter!(d -> d.id != item.id, system.demands)
    
    # If this was focused, select new focus
    if system.current_focus !== nothing && system.current_focus.id == item.id
        # Find highest priority remaining item
        remaining = filter(d -> d.competing && d.priority >= PRIORITY_NORMAL, system.demands)
        
        if !isempty(remaining)
            next_item = first(sort(remaining, by = x -> Int(x.priority), rev = true))
            shift_attention!(system, next_item, cost=0.05)
        else
            system.current_focus = nothing
        end
    end
    
    # Recover some alertness
    system.alerting_level = min(1.0, system.alerting_level + 0.02)
    
    system.last_update = now()
end

# ============================================================================
# ADDITIONAL OPERATIONS
# ============================================================================

"""
    add_attention_demand!(system::AttentionSystem, item::AttentionItem)

Add a new item to compete for attention.

This is a convenience function that creates and allocates attention
in one step if there's capacity.

# Arguments
- `system::AttentionSystem`: The attention system
- `item::AttentionItem`: The item to add

# Returns
- Whether the item was successfully added
"""
function add_attention_demand!(system::AttentionSystem, item::AttentionItem)::Bool
    # Check if filtered
    for tag in item.tags
        if tag ∈ system.filter
            return false
        end
    end
    
    # Check capacity
    demand = item.salience * Float64(Int(item.priority))
    if system.allocated_budget + demand > system.attention_budget
        # Try to suppress lower priority items
        suppress_lower_priority!(system, item)
    end
    
    # Add to demands
    push!(system.demands, item)
    
    # Auto-allocate if we have budget
    if system.current_focus === nothing
        allocate_attention!(system, item)
    end
    
    return true
end

"""
    remove_attention_demand!(system::AttentionSystem, item_id::UUID)

Remove an item from attention competition by ID.

# Arguments
- `system::AttentionSystem`: The attention system
- `item_id::UUID`: The ID of the item to remove

# Returns
- Whether item was found and removed
"""
function remove_attention_demand!(system::AttentionSystem, item_id::UUID)::Bool
    for item in system.demands
        if item.id == item_id
            release_attention!(system, item)
            return true
        end
    end
    return false
end

"""
    get_attention_status(system::AttentionSystem)

Get a summary of the current attention system state.

# Arguments
- `system::AttentionSystem`: The attention system

# Returns
- Dict with status information
"""
function get_attention_status(system::AttentionSystem)::Dict{String, Any}
    demand = calculate_attentional_demand(system)
    overload = demand > system.attention_budget
    
    return Dict{String, Any}(
        "has_focus" => system.current_focus !== nothing,
        "focus_content" => system.current_focus !== nothing ? system.current_focus.content : nothing,
        "demand" => demand,
        "capacity" => system.attention_budget,
        "allocated" => system.allocated_budget,
        "available" => system.attention_budget - system.allocated_budget,
        "alerting_level" => system.alerting_level,
        "orienting_speed" => system.orienting_speed,
        "executive_capacity" => system.executive_capacity,
        "competing_items" => length(filter(d -> d.competing, system.demands)),
        "overload" => overload,
        "filter_count" => length(system.filter)
    )
end

"""
    update_alertness!(system::AttentionSystem, change::Float64)

Update the alerting level of the attention system.

Positive changes increase alertness (vigilance), negative changes
decrease it (drowsiness, distraction).

# Arguments
- `system::AttentionSystem`: The attention system
- `change::Float64`: Change amount [-1, 1]
"""
function update_alertness!(system::AttentionSystem, change::Float64)
    system.alerting_level = clamp(system.alerting_level + change, 0.1, 1.0)
    system.last_update = now()
end

"""
    apply_attentional_filter(system::AttentionSystem, tags::Vector{String})

Apply a filter to suppress items with certain tags.

# Arguments
- `system::AttentionSystem`: The attention system
- `tags::Vector{String}`: Tags to filter out
"""
function apply_attentional_filter(system::AttentionSystem, tags::Vector{String})
    for tag in tags
        if tag ∉ system.filter
            push!(system.filter, tag)
        end
    end
    
    # Suppress all matching items
    for item in system.demands
        if any(tag ∈ system.filter for tag in item.tags)
            suppress_distraction!(system, item)
        end
    end
end

# ============================================================================
# INTERNAL HELPER FUNCTIONS
# ============================================================================

"""
    suppress_lower_priority!(system::AttentionSystem, new_item::AttentionItem)

Suppress lower priority items to make room for a new item.
"""
function suppress_lower_priority!(system::AttentionSystem, new_item::AttentionItem)
    # Sort demands by priority
    sorted = sort(system.demands, by = x -> Int(x.priority))
    
    # Remove lowest priority items until we have room
    for item in sorted
        if system.allocated_budget + (new_item.salience * Float64(Int(new_item.priority))) <= system.attention_budget
            break
        end
        
        if item.priority < new_item.priority && item.id != new_item.id
            suppress_distraction!(system, item)
        end
    end
end

end # module Attention
