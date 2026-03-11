"""
    ProceduralMemory Module

# Anderson's ACT-R Procedural Memory

This module implements procedural memory - the "how-to" knowledge storage 
for learned skills and behaviors. It is based on cognitive architecture theory,
specifically John Anderson's ACT-R (Adaptive Control of Thought - Rational) model.

## Theoretical Basis

ACT-R's procedural memory represents knowledge of "how" to do things - 
skills and behaviors that have been learned through practice. Key concepts:

- **Production Rules**: Procedural memory stores production rules that encode
  condition-action pairs (IF conditions THEN actions)
- **Strength of Procedures**: Procedures have associated strengths that 
  reflect how well-learned they are
- **Pattern Matching**: When faced with a task, the system matches against
  procedural knowledge to find applicable skills
- **Reinforcement Learning**: Success/failure feedback updates procedure 
  effectiveness through reinforcement
- **Cognitive Load**: More practiced procedures have lower cognitive load

This implementation models:

1. **Effectiveness Tracking**: Success rates and performance history
2. **Usage Patterns**: Times executed, recency of use
3. **Decay Mechanism**: Unused procedures lose effectiveness over time
4. **Capability Organization**: Procedures grouped by capability domain

## Usage

```julia
using .ProceduralMemory

pm = ProceduralMemory()
proc = create_procedure!(pm, "data_analysis", "analyze_csv", 
                         parameters=Dict("delimiter" => ","))

record_execution!(pm, proc.id, success=true, execution_time=1.5)

best = get_best_procedure(pm, "analyze_csv")
```
"""
module ProceduralMemory

export Procedure, ProceduralMemory, create_procedure!, record_execution!,
       get_best_procedure, update_effectiveness!, decay_unused_procedures!,
       get_procedures_by_capability

using Dates, UUIDs, Logging

# ============================================================================
# CORE STRUCTURES
# ============================================================================

"""
    Procedure

A learned skill or behavior stored in procedural memory, representing 
how to accomplish a specific capability.

# Fields
- `id::UUID`: Unique identifier for this procedure
- `name::String`: Human-readable name for the procedure
- `capability_id::String`: The capability this procedure implements
- `success_rate::Float64`: Proportion of successful executions (0.0-1.0)
- `times_executed::Int`: Total number of times this procedure has been run
- `last_used::DateTime`: Timestamp of most recent execution
- `parameters::Dict{String, Any}`: Configuration parameters for execution
- `effectiveness_history::Vector{Dict{String, Any}}`: Rolling history of outcomes
- `created_at::DateTime`: When this procedure was first created
- `avg_execution_time::Float64`: Average time to execute (seconds)

# Cognitive Science Basis

In ACT-R, procedures are analogous to production rules. The success_rate
reflects the "strength" of the production - how reliably it fires in
the given context. The effectiveness_history tracks recent performance
for adaptive selection.

# Example
```julia
proc = Procedure(
    name="csv_analysis",
    capability_id="analyze_data",
    parameters=Dict("delimiter" => ",", "has_header" => true)
)
```
"""
mutable struct Procedure
    id::UUID
    name::String
    capability_id::String
    success_rate::Float64
    times_executed::Int
    last_used::DateTime
    parameters::Dict{String, Any}
    effectiveness_history::Vector{Dict{String, Any}}
    created_at::DateTime
    avg_execution_time::Float64
    
    """
        Procedure(;name, capability_id, parameters=Dict())
    
    Create a new procedure with default values.
    
    # Arguments
    - `name::String`: Human-readable name
    - `capability_id::String`: The capability this procedure implements
    - `parameters::Dict`: Configuration parameters (default: empty Dict)
    """
    function Procedure(;
        name::String,
        capability_id::String,
        parameters::Dict{String, Any}=Dict{String, Any}()
    )
        new(
            uuid4(),
            name,
            capability_id,
            0.5,  # Initial success rate (unknown)
            0,
            now(),
            parameters,
            Dict{String, Any}[],  # Empty history
            now(),
            0.0  # No executions yet
        )
    end
end

"""
    ProceduralMemory

The storage system for learned procedures (skills and behaviors).

# Fields
- `procedures::Vector{Procedure}`: All stored procedures
- `capability_index::Dict{String, Vector{UUID}}`: Maps capability_id to procedure IDs
- `max_history::Int`: Maximum effectiveness history entries to keep per procedure
- `decay_rate::Float64`: Rate at which unused procedures lose effectiveness
- `min_effectiveness::Float64`: Floor for effectiveness (default: 0.1)

# Cognitive Science Basis

This implements the "procedural module" from ACT-R theory:
- Storage of production rules (procedures)
- Pattern matching for retrieval
- Reinforcement learning from outcomes
- Decay/forgetting of unused knowledge

# Example
```julia
pm = ProceduralMemory(max_history=20, decay_rate=0.05)
```
"""
mutable struct ProceduralMemory
    procedures::Vector{Procedure}
    capability_index::Dict{String, Vector{UUID}}
    max_history::Int
    decay_rate::Float64
    min_effectiveness::Float64
    
    """
        ProceduralMemory(;max_history=20, decay_rate=0.05, min_effectiveness=0.1)
    
    Create a new procedural memory store.
    
    # Arguments
    - `max_history::Int`: Max effectiveness history per procedure (default: 20)
    - `decay_rate::Float64`: Decay rate for unused procedures (default: 0.05)
    - `min_effectiveness::Float64`: Minimum effectiveness floor (default: 0.1)
    """
    function ProceduralMemory(;
        max_history::Int=20,
        decay_rate::Float64=0.05,
        min_effectiveness::Float64=0.1
    )
        new(
            Procedure[],
            Dict{String, Vector{UUID}}(),
            max_history,
            decay_rate,
            min_effectiveness
        )
    end
end

# ============================================================================
# PROCEDURE CREATION
# ============================================================================

"""
    create_procedure!(pm::ProceduralMemory, name::String, capability_id::String; 
                     parameters::Dict{String, Any}=Dict{String, Any}())::Procedure

Create and store a new procedure in procedural memory.

# Cognitive Mechanism

When a new procedure is created, it represents a newly learned skill or
behavior pattern. Initially, effectiveness is unknown (0.5), and the
procedure enters the capability index for retrieval.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `name::String`: Human-readable name for the procedure
- `capability_id::String`: The capability this procedure implements
- `parameters::Dict`: Configuration parameters (default: empty Dict)

# Returns
- The newly created `Procedure`

# Example
```julia
pm = ProceduralMemory()
proc = create_procedure!(pm, "fast_csv_parser", "analyze_csv", 
                        parameters=Dict("method" => "streaming"))
```
"""
function create_procedure!(pm::ProceduralMemory, name::String, capability_id::String;
                           parameters::Dict{String, Any}=Dict{String, Any}())::Procedure
    proc = Procedure(name=name, capability_id=capability_id, parameters=parameters)
    
    # Add to procedures list
    push!(pm.procedures, proc)
    
    # Add to capability index
    if !haskey(pm.capability_index, capability_id)
        pm.capability_index[capability_id] = UUID[]
    end
    push!(pm.capability_index[capability_id], proc.id)
    
    @debug "Created procedure" name=proc.name capability_id=proc.capability_id id=proc.id
    
    return proc
end

# ============================================================================
# EXECUTION RECORDING
# ============================================================================

"""
    record_execution!(pm::ProceduralMemory, procedure_id::UUID; 
                      success::Bool, execution_time::Float64=0.0,
                      outcome_details::Dict{String, Any}=Dict{String, Any}())::Bool

Record the outcome of a procedure execution and update effectiveness.

# Cognitive Mechanism

This implements the reinforcement learning component of ACT-R procedural
memory. Each execution provides feedback that updates the procedure's
effectiveness. The history maintains a rolling window of recent outcomes
for adaptive selection.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `procedure_id::UUID`: ID of the executed procedure
- `success::Bool`: Whether the execution was successful
- `execution_time::Float64`: Time taken to execute (seconds)
- `outcome_details::Dict`: Additional outcome information

# Returns
- `true` if update was successful, `false` if procedure not found

# Example
```julia
proc = create_procedure!(pm, "analyze", "data_analysis")
record_execution!(pm, proc.id, success=true, execution_time=2.3)
```
"""
function record_execution!(pm::ProceduralMemory, procedure_id::UUID;
                           success::Bool, 
                           execution_time::Float64=0.0,
                           outcome_details::Dict{String, Any}=Dict{String, Any}())::Bool
    
    # Find the procedure
    proc = find_proc(pm, procedure_id)
    if proc === nothing
        @warn "Procedure not found for execution recording" procedure_id=procedure_id
        return false
    end
    
    # Record execution
    proc.times_executed += 1
    proc.last_used = now()
    
    # Update average execution time (exponential moving average)
    if proc.times_executed == 1
        proc.avg_execution_time = execution_time
    else
        proc.avg_execution_time = 0.9 * proc.avg_execution_time + 0.1 * execution_time
    end
    
    # Add to effectiveness history
    outcome = Dict{String, Any}(
        "timestamp" => now(),
        "success" => success,
        "execution_time" => execution_time,
        "details" => outcome_details
    )
    push!(proc.effectiveness_history, outcome)
    
    # Trim history to max size
    if length(proc.effectiveness_history) > pm.max_history
        proc.effectiveness_history = proc.effectiveness_history[end-pm.max_history+1:end]
    end
    
    # Update effectiveness
    update_effectiveness!(proc)
    
    @debug "Recorded execution" procedure=proc.name success=success times_executed=proc.times_executed
    
    return true
end

# ============================================================================
# EFFECTIVENESS UPDATES
# ============================================================================

"""
    update_effectiveness!(proc::Procedure)

Update a procedure's effectiveness based on its effectiveness history.

# Cognitive Mechanism

In ACT-R, the strength of a production rule increases with successful
use and decreases with failures. This function calculates the current
success rate from the recent history, weighting more recent outcomes
more heavily to capture current performance trends.

# Arguments
- `proc::Procedure`: The procedure to update

# Example
```julia
proc = Procedure(name="test", capability_id="test_cap")
record_execution!(pm, proc.id, success=true)
update_effectiveness!(proc)
```
"""
function update_effectiveness!(proc::Procedure)
    history = proc.effectiveness_history
    
    if isempty(history)
        return  # Keep default effectiveness
    end
    
    # Calculate weighted success rate (recent executions weighted more)
    total_weight = 0.0
    weighted_success = 0.0
    
    for (i, outcome) in enumerate(history)
        # Weight: more recent = higher weight (linear increase)
        weight = Float64(i)
        total_weight += weight
        
        if get(outcome, "success", false)
            weighted_success += weight
        end
    end
    
    if total_weight > 0
        proc.success_rate = weighted_success / total_weight
    end
    
    # Clamp to valid range
    proc.success_rate = clamp(proc.success_rate, 0.0, 1.0)
end

"""
    update_effectiveness!(pm::ProceduralMemory, procedure_id::UUID)::Bool

Update effectiveness for a specific procedure in memory.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `procedure_id::UUID`: ID of the procedure to update

# Returns
- `true` if update was successful, `false` if procedure not found
"""
function update_effectiveness!(pm::ProceduralMemory, procedure_id::UUID)::Bool
    proc = find_proc(pm, procedure_id)
    if proc === nothing
        return false
    end
    update_effectiveness!(proc)
    return true
end

# ============================================================================
# PROCEDURE RETRIEVAL
# ============================================================================

"""
    get_best_procedure(pm::ProceduralMemory, capability_id::String;
                       min_effectiveness::Float64=0.0)::Union{Procedure, Nothing}

Get the most effective procedure for a given capability.

# Cognitive Mechanism

This implements the production matching and selection in ACT-R. When
faced with a task requiring a capability, the system retrieves the
most effective known procedure. Higher effectiveness (success rate)
indicates a stronger production rule that should be preferred.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `capability_id::String`: The capability needed
- `min_effectiveness::Float64`: Minimum effectiveness threshold (default: 0.0)

# Returns
- The most effective `Procedure` for the capability, or `nothing` if none found

# Example
```julia
best = get_best_procedure(pm, "data_analysis")
if best !== nothing
    execute_procedure(best)
end
```
"""
function get_best_procedure(pm::ProceduralMemory, capability_id::String;
                            min_effectiveness::Float64=0.0)::Union{Procedure, Nothing}
    
    # Get procedure IDs for this capability
    proc_ids = get(pm.capability_index, capability_id, UUID[])
    
    if isempty(proc_ids)
        return nothing
    end
    
    # Find the best procedure
    best_proc = nothing
    best_effectiveness = -1.0
    
    for proc_id in proc_ids
        proc = find_proc(pm, proc_id)
        if proc !== nothing && proc.success_rate >= min_effectiveness
            if proc.success_rate > best_effectiveness
                best_effectiveness = proc.success_rate
                best_proc = proc
            end
        end
    end
    
    return best_proc
end

"""
    get_procedures_by_capability(pm::ProceduralMemory, capability_id::String;
                                  min_effectiveness::Float64=0.0)::Vector{Procedure}

Get all procedures for a given capability, optionally filtered by effectiveness.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `capability_id::String`: The capability to filter by
- `min_effectiveness::Float64`: Minimum effectiveness threshold

# Returns
- Vector of matching `Procedure` objects

# Example
```julia
all_procedures = get_procedures_by_capability(pm, "web_request")
```
"""
function get_procedures_by_capability(pm::ProceduralMemory, capability_id::String;
                                       min_effectiveness::Float64=0.0)::Vector{Procedure}
    
    proc_ids = get(pm.capability_index, capability_id, UUID[])
    results = Procedure[]
    
    for proc_id in proc_ids
        proc = find_proc(pm, proc_id)
        if proc !== nothing && proc.success_rate >= min_effectiveness
            push!(results, proc)
        end
    end
    
    return results
end

# ============================================================================
# DECAY MECHANISM
# ============================================================================

"""
    decay_unused_procedures!(pm::ProceduralMemory; 
                             unused_threshold_days::Int=30,
                             force::Bool=false)

Reduce effectiveness of procedures that haven't been used recently.

# Cognitive Mechanism

In ACT-R, procedural knowledge that is not used frequently becomes
weaker over time - this models the "use it or lose it" principle of
skill retention. Unused procedures decay toward the minimum effectiveness
level, reflecting the cognitive cost of reactivating rarely-used skills.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `unused_threshold_days::Int`: Days of non-use before decay starts (default: 30)
- `force::Bool`: If true, apply decay to all unused regardless of threshold

# Example
```julia
# Apply decay to procedures not used in the last month
decay_unused_procedures!(pm, unused_threshold_days=30)
```
"""
function decay_unused_procedures!(pm::ProceduralMemory; 
                                   unused_threshold_days::Int=30,
                                   force::Bool=false)
    
    current_time = now()
    threshold = Hour(unused_threshold_days * 24)
    
    for proc in pm.procedures
        elapsed = current_time - proc.last_used
        
        # Check if unused beyond threshold
        if force || elapsed > threshold
            # Calculate decay factor based on how long unused
            days_unused = elapsed.value / (1000 * 60 * 60 * 24)
            decay_factor = exp(-pm.decay_rate * days_unused)
            
            # Apply decay to success rate
            proc.success_rate = pm.min_effectiveness + 
                (proc.success_rate - pm.min_effectiveness) * decay_factor
            
            @debug "Decayed procedure" procedure=proc.name 
                   days_unused=round(days_unused, digits=2) 
                   new_success_rate=round(proc.success_rate, digits=3)
        end
    end
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    find_proc(pm::ProceduralMemory, procedure_id::UUID)::Union{Procedure, Nothing}

Find a procedure by its ID.

# Arguments
- `pm::ProceduralMemory`: The procedural memory store
- `procedure_id::UUID`: The procedure ID to find

# Returns
- The `Procedure` if found, `nothing` otherwise
"""
function find_proc(pm::ProceduralMemory, procedure_id::UUID)::Union{Procedure, Nothing}
    for proc in pm.procedures
        if proc.id == procedure_id
            return proc
        end
    end
    return nothing
end

"""
    Base.length(pm::ProceduralMemory)

Return the number of procedures in memory.
"""
Base.length(pm::ProceduralMemory) = length(pm.procedures)

"""
    Base.isempty(pm::ProceduralMemory)

Check if procedural memory is empty.
"""
Base.isempty(pm::ProceduralMemory) = isempty(pm.procedures)

"""
    get_procedure_count(pm::ProceduralMemory, capability_id::String)

Get the number of procedures for a capability.
"""
function get_procedure_count(pm::ProceduralMemory, capability_id::String)::Int
    return length(get(pm.capability_index, capability_id, UUID[]))
end

"""
    get_statistics(pm::ProceduralMemory)::Dict{String, Any}

Get overall procedural memory statistics.
"""
function get_statistics(pm::ProceduralMemory)::Dict{String, Any}
    total_executions = sum(p.times_executed for p in pm.procedures)
    avg_success = isempty(pm.procedures) ? 0.0 : 
        sum(p.success_rate for p in pm.procedures) / length(pm.procedures)
    
    return Dict{String, Any}(
        "total_procedures" => length(pm.procedures),
        "total_executions" => total_executions,
        "average_success_rate" => avg_success,
        "capabilities_covered" => length(pm.capability_index),
        "decay_rate" => pm.decay_rate,
        "max_history" => pm.max_history
    )
end

end # module
