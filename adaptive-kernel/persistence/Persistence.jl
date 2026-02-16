# persistence/Persistence.jl - Append-only event log + SQLite state store

module Persistence

using JSON
using Dates

export save_event, load_events, init_persistence, get_last_state

const EVENT_LOG_FILE = "events.log"

"""
    init_persistence()
Initialize persistence (event log and SQLite placeholder).
"""
function init_persistence()
    # Ensure event log exists
    if !isfile(EVENT_LOG_FILE)
        touch(EVENT_LOG_FILE)
    end
end

"""
    save_event(event::Dict{String, Any})
Append an event to the append-only log (JSONL format).
"""
function save_event(event::Dict{String, Any})
    init_persistence()
    open(EVENT_LOG_FILE, "a") do io
        println(io, JSON.json(event))
    end
end

"""
    load_events()::Vector{Dict{String, Any}}
Load all events from the event log.
"""
function load_events()::Vector{Dict{String, Any}}
    events = Dict{String, Any}[]
    
    if !isfile(EVENT_LOG_FILE)
        return events
    end
    
    for line in readlines(EVENT_LOG_FILE)
        if !isempty(strip(line))
            try
                push!(events, JSON.parse(line))
            catch
                # Skip malformed lines
            end
        end
    end
    
    return events
end

"""
    get_last_state()::Dict{String, Any}
Return the last recorded kernel state from the log.
"""
function get_last_state()::Dict{String, Any}
    events = load_events()
    
    for event in reverse(events)
        if get(event, "type", "") == "state_dump"
            return get(event, "data", Dict())
        end
    end
    
    return Dict()
end

"""
    save_kernel_state(kernel_stats::Dict{String, Any})
Record kernel state snapshot.
"""
function save_kernel_state(kernel_stats::Dict{String, Any})
    event = Dict(
        "timestamp" => string(now()),
        "type" => "state_dump",
        "data" => kernel_stats
    )
    save_event(event)
end

end  # module
