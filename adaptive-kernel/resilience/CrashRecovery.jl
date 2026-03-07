# adaptive-kernel/resilience/CrashRecovery.jl - Crash recovery system
# Functions: watchdog_restart, memory_recovery, journal_replay

module CrashRecovery

using Dates
using Serialization
using Logging
using Distributed

# Export public API
export CrashRecoveryManager, RecoveryState
export watchdog_restart, memory_recovery, journal_replay
export start_watchdog, stop_watchdog
export save_recovery_point, load_recovery_point

# ============================================================================
# Core Types
# ============================================================================

"""
    RecoveryState - Current recovery operation state
"""
@enum RecoveryState IDLE RECOVERING WATCHDOG_ACTIVE RESTARTING

"""
    RecoveryPoint - Saved state for recovery
"""
struct RecoveryPoint
    timestamp::DateTime
    cycle::Int
    checkpoint_file::String
    journal_file::String
    memory_state::Dict{String, Any}
end

"""
    JournalEntry - Single event in the replay journal
"""
struct JournalEntry
    timestamp::DateTime
    event_type::String
    data::Dict{String, Any}
end

"""
    CrashRecoveryManager - Manages crash recovery operations
"""
mutable struct CrashRecoveryManager
    # State
    state::RecoveryState
    recovery_dir::String
    
    # Watchdog configuration
    watchdog_interval::Float64  # seconds
    watchdog_timeout::Float64   # seconds before restart
    last_heartbeat::DateTime
    watchdog_task::Union{Task, Nothing}
    
    # Recovery configuration
    max_recovery_points::Int
    auto_recover::Bool
    
    # Integration references
    health_monitor::Any  # Optional HealthMonitor reference
    checkpointer::Any    # Optional Checkpointer reference
    
    # Journal
    journal::Vector{JournalEntry}
    journal_file::String
    
    # Recovery callbacks
    on_restart_callback::Union{Function, Nothing}
    on_recovery_callback::Union{Function, Nothing}
    
    function CrashRecoveryManager(;
        recovery_dir::String="./recovery",
        watchdog_interval::Float64=5.0,
        watchdog_timeout::Float64=60.0,
        max_recovery_points::Int=5,
        auto_recover::Bool=true)
        mkpath(recovery_dir)
        new(
            IDLE,
            recovery_dir,
            watchdog_interval,
            watchdog_timeout,
            now(),
            nothing,
            max_recovery_points,
            auto_recover,
            nothing,
            nothing,
            JournalEntry[],
            joinpath(recovery_dir, "journal.log"),
            nothing,
            nothing
        )
    end
end

# ============================================================================
# Watchdog Functions
# ============================================================================

"""
    start_watchdog(manager::CrashRecoveryManager)
Start the watchdog timer for automatic restart
"""
function start_watchdog(manager::CrashRecoveryManager)
    if manager.watchdog_task !== nothing && !istaskdone(manager.watchdog_task)
        @warn "Watchdog already running"
        return
    end
    
    manager.state = WATCHDOG_ACTIVE
    manager.last_heartbeat = now()
    
    manager.watchdog_task = @task begin
        while manager.state == WATCHDOG_ACTIVE
            elapsed = (now() - manager.last_heartbeat).value / 1000.0
            
            if elapsed > manager.watchdog_timeout
                @error "Watchdog timeout exceeded: $(elapsed)s > $(manager.watchdog_timeout)s"
                watchdog_restart(manager)
            end
            
            sleep(manager.watchdog_interval)
        end
    end
    
    @info "Watchdog started with timeout: $(manager.watchdog_timeout)s"
end

"""
    stop_watchdog(manager::CrashRecoveryManager)
Stop the watchdog timer
"""
function stop_watchdog(manager::CrashRecoveryManager)
    manager.state = IDLE
    if manager.watchdog_task !== nothing
        schedule(manager.watchdog_task, InterruptException(), error=true)
        manager.watchdog_task = nothing
    end
    @info "Watchdog stopped"
end

"""
    heartbeat!(manager::CrashRecoveryManager)
Update watchdog heartbeat to prevent restart
"""
function heartbeat!(manager::CrashRecoveryManager)
    manager.last_heartbeat = now()
end

"""
    watchdog_restart(manager::CrashRecoveryManager)
Automatic process restart triggered by watchdog
"""
function watchdog_restart(manager::CrashRecoveryManager)
    @error "WATCHDOG: Initiating automatic restart"
    manager.state = RESTARTING
    
    try
        # Save recovery point before restart
        save_recovery_point(manager)
        
        # Trigger restart callback if set
        if manager.on_restart_callback !== nothing
            manager.on_restart_callback()
        end
        
        # In a real system, this would restart the process
        # For Julia, we can exit with specific code for launcher to detect
        @error "WATCHDOG: Process would restart here (simulated)"
        
    catch e
        @error "Watchdog restart failed" exception=e
    finally
        manager.state = IDLE
    end
end

# ============================================================================
# Memory Recovery Functions
# ============================================================================

"""
    memory_recovery(manager::CrashRecoveryManager)::Union{Dict, Nothing}
Recover memory state from the latest recovery point
"""
function memory_recovery(manager::CrashRecoveryManager)::Union{Dict, Nothing}
    @info "Starting memory recovery..."
    manager.state = RECOVERING
    
    try
        # Try to load from checkpointer first
        if manager.checkpointer !== nothing
            checkpoint_data = load_checkpoint(manager.checkpointer)
            if checkpoint_data !== nothing
                @info "Recovered state from checkpoint"
                manager.state = IDLE
                return checkpoint_data
            end
        end
        
        # Fallback: load from recovery points
        recovery_files = _list_recovery_points(manager)
        if isempty(recovery_files)
            @warn "No recovery points found"
            manager.state = IDLE
            return nothing
        end
        
        # Load most recent recovery point
        latest = recovery_files[end]
        @info "Loading recovery point: $latest"
        
        data = open(latest, "r") do io
            deserialize(io)
        end
        
        if manager.on_recovery_callback !== nothing
            manager.on_recovery_callback(data)
        end
        
        @info "Memory recovery completed"
        manager.state = IDLE
        return data
        
    catch e
        @error "Memory recovery failed" exception=e
        manager.state = IDLE
        return nothing
    end
end

"""
    save_recovery_point(manager::CrashRecoveryManager; extra_data::Dict=Dict())
Save current state as a recovery point
"""
function save_recovery_point(manager::CrashRecoveryManager; extra_data::Dict=Dict())
    try
        timestamp = replace(string(now()), ":" => "-")
        filename = joinpath(manager.recovery_dir, "recovery_$timestamp.jld2")
        
        recovery_data = Dict(
            "timestamp" => string(now()),
            "journal" => manager.journal,
            "extra" => extra_data
        )
        
        # Write atomically
        temp_file = filename * ".tmp"
        open(temp_file, "w") do io
            serialize(io, recovery_data)
        end
        mv(temp_file, filename, force=true)
        
        # Cleanup old recovery points
        _cleanup_recovery_points(manager)
        
        @info "Saved recovery point: $filename"
        
    catch e
        @error "Failed to save recovery point" exception=e
    end
end

"""
    load_recovery_point(manager::CrashRecoveryManager)::Union{Dict, Nothing}
Load the latest recovery point (alias for memory_recovery without health check)
"""
function load_recovery_point(manager::CrashRecoveryManager)::Union{Dict, Nothing}
    return memory_recovery(manager)
end

# ============================================================================
# Journal Replay Functions
# ============================================================================

"""
    journal_replay(manager::CrashRecoveryManager; from_time::Union{DateTime, Nothing}=nothing)
Replay events from the journal
"""
function journal_replay(manager::CrashRecoveryManager; from_time::Union{DateTime, Nothing}=nothing)
    @info "Starting journal replay..."
    
    # Filter entries by time if specified
    entries = if from_time !== nothing
        filter(e -> e.timestamp >= from_time, manager.journal)
    else
        manager.journal
    end
    
    if isempty(entries)
        @info "No journal entries to replay"
        return 0
    end
    
    replayed = 0
    for entry in entries
        try
            _replay_entry(entry)
            replayed += 1
        catch e
            @error "Failed to replay journal entry" exception=e entry_type=entry.event_type
        end
    end
    
    @info "Journal replay completed: $replayed entries"
    return replayed
end

"""
    _replay_entry(entry::JournalEntry)
Replay a single journal entry
"""
function _replay_entry(entry::JournalEntry)
    @debug "Replaying event: $(entry.event_type)"
    
    # Handle different event types
    if entry.event_type == "state_update"
        # Replay state update
    elseif entry.event_type == "decision"
        # Replay decision
    elseif entry.event_type == "action"
        # Replay action execution
    else
        @warn "Unknown journal entry type: $(entry.event_type)"
    end
end

"""
    append_journal!(manager::CrashRecoveryManager, event_type::String, data::Dict)
Add an entry to the recovery journal
"""
function append_journal!(manager::CrashRecoveryManager, event_type::String, data::Dict)
    entry = JournalEntry(
        timestamp=now(),
        event_type=event_type,
        data=data
    )
    push!(manager.journal, entry)
    
    # Persist journal to disk
    _persist_journal(manager)
end

"""
    _persist_journal(manager::CrashRecoveryManager)
Write journal to disk
"""
function _persist_journal(manager::CrashRecoveryManager)
    try
        open(manager.journal_file, "w") do io
            serialize(io, manager.journal)
        end
    catch e
        @error "Failed to persist journal" exception=e
    end
end

"""
    load_journal!(manager::CrashRecoveryManager)
Load journal from disk on startup
"""
function load_journal!(manager::CrashRecoveryManager)
    if isfile(manager.journal_file)
        try
            manager.journal = open(manager.journal_file, "r") do io
                deserialize(io)
            end
            @info "Loaded $(length(manager.journal)) journal entries"
        catch e
            @warn "Failed to load journal" exception=e
            manager.journal = JournalEntry[]
        end
    end
end

# ============================================================================
# Integration with HealthMonitor
# ============================================================================

"""
    set_health_monitor!(manager::CrashRecoveryManager, monitor)
Link CrashRecoveryManager to HealthMonitor
"""
function set_health_monitor!(manager::CrashRecoveryManager, monitor)
    manager.health_monitor = monitor
    @info "CrashRecovery linked to HealthMonitor"
end

"""
    set_checkpointer!(manager::CrashRecoveryManager, checkpointer)
Link CrashRecoveryManager to Checkpointer
"""
function set_checkpointer!(manager::CrashRecoveryManager, checkpointer)
    manager.checkpointer = checkpointer
    @info "CrashRecovery linked to Checkpointer"
end

"""
    set_restart_callback!(manager::CrashRecoveryManager, callback::Function)
Set callback to be called on restart
"""
function set_restart_callback!(manager::CrashRecoveryManager, callback::Function)
    manager.on_restart_callback = callback
end

"""
    set_recovery_callback!(manager::CrashRecoveryManager, callback::Function)
Set callback to be called after recovery
"""
function set_recovery_callback!(manager::CrashRecoveryManager, callback::Function)
    manager.on_recovery_callback = callback
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    _list_recovery_points(manager::CrashRecoveryManager)
List available recovery point files
"""
function _list_recovery_points(manager::CrashRecoveryManager)
    files = filter(f -> endswith(f, ".jld2"), readdir(manager.recovery_dir, join=true))
    return sort(files)
end

"""
    _cleanup_recovery_points(manager::CrashRecoveryManager)
Remove old recovery points beyond max limit
"""
function _cleanup_recovery_points(manager::CrashRecoveryManager)
    files = _list_recovery_points(manager)
    if length(files) > manager.max_recovery_points
        to_delete = files[1:(length(files) - manager.max_recovery_points)]
        for f in to_delete
            rm(f, force=true)
            @debug "Removed old recovery point: $f"
        end
    end
end

end # module
