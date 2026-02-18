# persistence/Persistence.jl - Append-only event log + SQLite state store

module Persistence

using JSON
using Dates
using Logging

export save_event, load_events, init_persistence, get_last_state, set_event_log_file

const EVENT_LOG_FILE_DEFAULT = "events.log"
const EVENT_LOG_FILE = Ref(get(ENV, "ADAPTIVE_KERNEL_EVENT_LOG", EVENT_LOG_FILE_DEFAULT))

"""
    init_persistence()
Initialize persistence (event log and SQLite placeholder).
"""
function init_persistence()
    # Ensure event log exists
    logpath = EVENT_LOG_FILE[]
    if !isfile(logpath)
        touch(logpath)
    end
end

"""
    save_event(event::Dict{String, Any})
Append an event to the append-only log (JSONL format).
"""
function save_event(event::Dict{String, Any})
    init_persistence()
    open(EVENT_LOG_FILE[], "a") do io
        println(io, JSON.json(event))
    end
end

# Generic method to handle Dict{String, T} (e.g., Dict{String, String})
# Converts to Dict{String, Any} before processing
function save_event(event::Dict{String, T}) where T
    save_event(Dict{String, Any}(event))
end

"""
    load_events()::Vector{Dict{String, Any}}
Load all events from the event log.
"""
function load_events()::Vector{Dict{String, Any}}
    events = Dict{String, Any}[]
    logpath = EVENT_LOG_FILE[]

    if !isfile(logpath)
        return events
    end

    for line in readlines(logpath)
        if !isempty(strip(line))
            try
                push!(events, JSON.parse(line))
            catch e
                @warn "Skipped malformed JSON line: $(e)"
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

"""
    set_event_log_file(path::String)

Set the event log file path for persistence (useful for tests).
"""
function set_event_log_file(path::String)
    EVENT_LOG_FILE[] = path
    init_persistence()
end

end  # module
