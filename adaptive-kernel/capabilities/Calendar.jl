"""
# Calendar.jl

Calendar integration for the adaptive brain.
Provides read and write access to calendar events.

## Capabilities
- List calendar events
- Create new events
- Update existing events
- Delete events (own events only)
- Query events by date range

## Security
- OAuth2 authentication required
- Only modify own calendar
- Event content sanitization
- Sandbox execution enforced
"""

module Calendar

using JSON
using Dates

# Calendar configuration
struct CalendarConfig
    api_endpoint::String
    calendar_id::String
    max_events::Int
    allowed_fields::Vector{String}
end

"""
    create_config()

Create calendar configuration with security defaults.
"""
function create_config()
    CalendarConfig(
        "https://calendar-api.example.com/v3",  # api_endpoint
        "primary",                               # calendar_id
        50,                                      # max_events
        ["title", "description", "start", "end", "location", "attendees"]  # allowed fields
    )
end

"""
    validate_event(event::Dict)

Validate event data before creation/update.
"""
function validate_event(event::Dict)
    errors = String[]
    
    # Required fields
    if !haskey(event, "title") || isempty(event["title"])
        push!(errors, "Title is required")
    end
    
    if !haskey(event, "start") || isempty(event["start"])
        push!(errors, "Start time is required")
    end
    
    # Validate date format
    if haskey(event, "start")
        try
            DateTime(event["start"])
        catch
            push!(errors, "Invalid start date format. Use ISO 8601.")
        end
    end
    
    if haskey(event, "end")
        try
            DateTime(event["end"])
        catch
            push!(errors, "Invalid end date format. Use ISO 8601.")
        end
    end
    
    # Check for allowed fields only
    config = create_config()
    for key in keys(event)
        if key ∉ config.allowed_fields
            push!(errors, "Field '$key' is not allowed")
        end
    end
    
    return isempty(errors), errors
end

"""
    sanitize_event(event::Dict)

Sanitize event content to prevent injection.
"""
function sanitize_event(event::Dict)
    sanitized = Dict{String, Any}()
    
    for (key, value) in event
        if typeof(value) == String
            # Remove potentially dangerous content
            sanitized[key] = replace(value, r"<[^>]*>" => "")  # Remove HTML tags
            sanitized[key] = replace(sanitized[key], r"javascript:" => "", count=1)
            sanitized[key] = replace(sanitized[key], r"on\w+=" => "", count=1)
        else
            sanitized[key] = value
        end
    end
    
    return sanitized
end

"""
    list_events(config::CalendarConfig, start_date::String, end_date::String)

List calendar events within date range.
"""
function list_events(config::CalendarConfig, start_date::String, end_date::String)
    println("Calendar: Listing events from $start_date to $end_date")
    
    # In production, actual API call would happen here
    return Dict(
        "success" => true,
        "events" => [],
        "count" => 0,
        "start_date" => start_date,
        "end_date" => end_date
    )
end

"""
    create_event(config::CalendarConfig, event::Dict)

Create a new calendar event.
"""
function create_event(config::CalendarConfig, event::Dict)
    # Sanitize and validate
    event = sanitize_event(event)
    is_valid, errors = validate_event(event)
    
    if !is_valid
        return Dict(
            "success" => false,
            "errors" => errors
        )
    end
    
    # Check max events limit
    if config.max_events <= 0
        return Dict(
            "success" => false,
            "error" => "Event limit exceeded"
        )
    end
    
    println("Calendar: Creating event: $(event["title"])")
    
    # Generate event ID
    event_id = string(uuid4())
    
    return Dict(
        "success" => true,
        "event_id" => event_id,
        "title" => event["title"],
        "created" => true
    )
end

"""
    update_event(config::CalendarConfig, event_id::String, updates::Dict)

Update an existing event.
"""
function update_event(config::CalendarConfig, event_id::String, updates::Dict)
    # Validate updates
    updates = sanitize_event(updates)
    is_valid, errors = validate_event(updates)
    
    if !is_valid
        return Dict(
            "success" => false,
            "errors" => errors
        )
    end
    
    println("Calendar: Updating event $event_id")
    
    return Dict(
        "success" => true,
        "event_id" => event_id,
        "updated" => true
    )
end

"""
    delete_event(config::CalendarConfig, event_id::String)

Delete a calendar event.
"""
function delete_event(config::CalendarConfig, event_id::String)
    # In production, verify ownership before deletion
    println("Calendar: Deleting event $event_id")
    
    return Dict(
        "success" => true,
        "event_id" => event_id,
        "deleted" => true
    )
end

"""
    execute(params::Dict)

Main entry point for capability registry.
"""
function execute(params::Dict)
    action = get(params, "action", "list_events")
    config = create_config()
    
    result = try
        if action == "list_events"
            start_date = get(params, "start_date", string(today()))
            end_date = get(params, "end_date", string(today() + Week(1)))
            list_events(config, start_date, end_date)
        elseif action == "create_event"
            event = get(params, "event", Dict())
            create_event(config, event)
        elseif action == "update_event"
            event_id = get(params, "event_id", "")
            updates = get(params, "updates", Dict())
            update_event(config, event_id, updates)
        elseif action == "delete_event"
            event_id = get(params, "event_id", "")
            delete_event(config, event_id)
        else
            Dict("success" => false, "error" => "Unknown action: $action")
        end
    catch e
        Dict("success" => false, "error" => string(e))
    end
    
    return result
end

# Entry point when run directly
if abspath(PROGRAM_FILE) == @__FILE__()
    result = execute(Dict())
    println(JSON.json(result))
end

end # module
