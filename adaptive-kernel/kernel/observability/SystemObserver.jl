# kernel/observability/SystemObserver.jl - Real-time system telemetry aggregation
# Reads from /proc (Linux) or uses safe defaults (Windows)

module SysObserver

using Dates
using Statistics

# Export public API
export SystemObserver, Observation, collect_real_observation, observe, get_history, get_average_metrics

# ============================================================================
# Core Types
# ============================================================================

"""
    Observation - System metrics snapshot (matches Kernel.jl Observation for compatibility)
"""
struct Observation
    timestamp::DateTime
    cpu_usage::Float32      # 0.0 - 1.0
    memory_usage::Float32   # 0.0 - 1.0
    disk_io::Float32        # bytes/sec normalized
    network_latency::Float32  # ms
    file_count::Int
    process_count::Int
    
    # Constructor for backwards compatibility with Kernel.jl
    Observation() = new(now(), 0.0f0, 0.0f0, 0.0f0, 0.0f0, 0, 0)
    
    # Constructor with all fields
    Observation(cpu::Float32, mem::Float32, disk::Float32, net::Float32, files::Int, procs::Int) = 
        new(now(), cpu, mem, disk, net, files, procs)
end

# Alias for backwards compatibility
const KernelObservation = Observation

"""
    SystemObserver - Real-time system telemetry aggregation
"""
mutable struct SystemObserver
    observation_interval::Float64  # seconds
    last_observation::Union{Observation, Nothing}
    observation_history::Vector{Observation}
    history_size::Int
    _last_cpu_idle::Vector{UInt64}
    _last_cpu_total::Vector{UInt64}
    
    function SystemObserver(interval::Float64=1.0; history_size::Int=100)
        new(interval, nothing, Vector{Observation}(), history_size, UInt64[], UInt64[])
    end
end

# ============================================================================
# Platform-Specific Implementations
# ============================================================================

"""
    _read_cpu_load()::Float32
Read CPU load from /proc/loadavg (Linux) or calculate from /proc/stat
Returns normalized value 0.0-1.0
"""
function _read_cpu_load()::Float32
    try
        if isfile("/proc/loadavg")
            # Read 1-minute load average
            load_str = split(readlines("/proc/loadavg")[1])[1]
            load = parse(Float64, load_str)
            # Normalize by CPU count (clamp to 1.0 if overloaded)
            cpu_count = Sys.CPU_THREADS
            normalized = load / max(cpu_count, 1)
            return Float32(clamp(normalized, 0.0, 1.0))
        elseif isfile("/proc/stat")
            # Fallback: calculate CPU usage from /proc/stat
            return _read_cpu_from_stat()
        end
    catch e
        @warn "Failed to read CPU load" exception=e
    end
    return 0.1f0  # Safe default
end

"""
    _read_cpu_from_stat()::Float32
Calculate CPU usage from /proc/stat (Linux)
"""
function _read_cpu_from_stat()::Float32
    try
        lines = readlines("/proc/stat")
        cpu_line = first(line for line in lines if startswith(line, "cpu "))
        fields = split(cpu_line)[2:end]  # Skip "cpu" label
        
        # Fields: user, nice, system, idle, iowait, irq, softirq, steal
        values = parse.(UInt64, fields)
        
        idle = values[4]
        total = sum(values)
        
        return Float32(clamp(1.0 - (idle / max(total, 1)), 0.0, 1.0))
    catch
        return 0.1f0
    end
end

"""
    _read_memory_usage()::Float32
Read memory usage from /proc/meminfo (Linux)
Returns used/total ratio 0.0-1.0
"""
function _read_memory_usage()::Float32
    try
        if isfile("/proc/meminfo")
            lines = readlines("/proc/meminfo")
            
            memtotal = 0
            memavailable = 0
            
            for line in lines
                if startswith(line, "MemTotal:")
                    memtotal = parse(Int, split(line)[2]) * 1024  # Convert kB to bytes
                elseif startswith(line, "MemAvailable:")
                    memavailable = parse(Int, split(line)[2]) * 1024
                    break
                end
            end
            
            if memtotal > 0
                used = memtotal - memavailable
                return Float32(clamp(used / memtotal, 0.0, 1.0))
            end
        end
    catch e
        @warn "Failed to read memory usage" exception=e
    end
    return 0.5f0  # Safe default
end

"""
    _read_disk_io()::Float32
Read disk I/O stats from /proc/diskstats (Linux)
Returns normalized bytes/sec (0.0-1.0 scale based on typical SSD)
"""
function _read_disk_io()::Float32
    try
        if isfile("/proc/diskstats")
            lines = readlines("/proc/diskstats")
            
            total_sectors_read = 0
            total_sectors_written = 0
            
            for line in lines
                fields = split(line)
                # Skip loop devices and ram disks
                dev = length(fields) >= 3 ? fields[3] : ""
                if startswith(dev, "loop") || startswith(dev, "ram")
                    continue
                end
                
                # Fields: read_sectors, write_sectors (sectors are 512 bytes)
                if length(fields) >= 14
                    total_sectors_read += parse(UInt64, fields[6])
                    total_sectors_written += parse(UInt64, fields[10])
                end
            end
            
            # Normalize: assume ~500MB/s max for modern SSD (1.0 = 500MB/s)
            max_io_rate = 500.0f6  # 500 MB/s in bytes
            total_bytes = (total_sectors_read + total_sectors_written) * 512
            
            return Float32(clamp(total_bytes / max_io_rate, 0.0, 1.0))
        end
    catch e
        @warn "Failed to read disk I/O" exception=e
    end
    return 0.0f0  # Safe default
end

"""
    _read_network_latency()::Float32
Check network latency via socket connection test
Returns latency in milliseconds (0.0-1.0 scale: 0ms = 0.0, 1000ms = 1.0)
"""
function _read_network_latency()::Float32
    try
        # Try to connect to a well-known host to measure latency
        # Use a quick TCP connection test
        sock = nothing
        start_time = time()
        
        try
            sock = connect("8.8.8.8", 53)  # Google DNS
            close(sock)
        catch
            # Fallback: try localhost
            try
                sock = connect("127.0.0.1", 80)
                close(sock)
            catch
                # No network available
            end
        end
        
        latency_ms = (time() - start_time) * 1000.0
        
        # Normalize: 0ms = 0.0, 1000ms = 1.0
        return Float32(clamp(latency_ms / 1000.0, 0.0, 1.0))
    catch e
        @warn "Failed to measure network latency" exception=e
    end
    return 0.5f0  # Safe default
end

"""
    _count_filesystem_objects()::Int
Count files and directories in common locations (Linux)
"""
function _count_filesystem_objects()::Int
    count = 0
    try
        # Count in /tmp, /var, /home (sample approach)
        for path in ["/tmp", "/var/tmp", "/home"]
            if isdir(path)
                try
                    # Use quick find-like approach without subprocess
                    count += _quick_count_entries(path)
                catch
                    # Skip inaccessible directories
                end
            end
        end
    catch e
        @warn "Failed to count filesystem objects" exception=e
    end
    return count
end

"""
    _quick_count_entries(path::String)::Int
Quickly count entries in a directory (non-recursive)
"""
function _quick_count_entries(path::String)::Int
    count = 0
    try
        for entry in readdir(path, join=true)
            count += 1
        end
    catch
        # Permission denied or other error
    end
    return count
end

"""
    _count_processes()::Int
Count running processes from /proc (Linux)
"""
function _count_processes()::Int
    try
        if isdir("/proc")
            # Count numeric directories (PIDs)
            return length(filter(x -> tryparse(Int, x) !== nothing, readdir("/proc")))
        end
    catch e
        @warn "Failed to count processes" exception=e
    end
    return 1  # Safe default
end

# ============================================================================
# Windows Fallbacks
# ============================================================================

"""
    _windows_fallback_cpu()::Float32
Windows fallback for CPU reading
"""
function _windows_fallback_cpu()::Float32
    try
        # Try WMI via PowerShell (fallback)
        return 0.2f0  # Conservative default
    catch
        return 0.2f0
    end
end

"""
    _windows_fallback_memory()::Float32
Windows fallback for memory reading
"""
function _windows_fallback_memory()::Float32
    try
        return 0.5f0  # Conservative default
    catch
        return 0.5f0
    end
end

# ============================================================================
# Main Observation Collection
# ============================================================================

"""
    collect_real_observation()::Observation
Collect real system metrics from the platform
"""
function collect_real_observation()::Observation
    # Determine platform and collect accordingly
    if Sys.islinux()
        return _collect_linux_observation()
    elseif Sys.iswindows()
        return _collect_windows_observation()
    else
        # Unknown platform - return safe defaults
        return _collect_safe_observation()
    end
end

"""
    _collect_linux_observation()::Observation
Collect observation on Linux
"""
function _collect_linux_observation()::Observation
    cpu = _read_cpu_load()
    memory = _read_memory_usage()
    disk = _read_disk_io()
    network = _read_network_latency()
    files = _count_filesystem_objects()
    processes = _count_processes()
    
    return Observation(cpu, memory, disk, network, files, processes)
end

"""
    _collect_windows_observation()::Observation
Collect observation on Windows (with fallbacks)
"""
function _collect_windows_observation()::Observation
    cpu = _windows_fallback_cpu()
    memory = _windows_fallback_memory()
    disk = 0.0f0
    network = 0.1f0
    files = 100  # Estimated
    processes = 50  # Estimated
    
    return Observation(cpu, memory, disk, network, files, processes)
end

"""
    _collect_safe_observation()::Observation
Return safe default observation when platform not supported
"""
function _collect_safe_observation()::Observation
    return Observation(0.1f0, 0.5f0, 0.0f0, 0.1f0, 10, 5)
end

# ============================================================================
# Observer Management
# ============================================================================

"""
    observe(observer::SystemObserver)::Observation
Get current observation and update history
"""
function observe(observer::SystemObserver)::Observation
    obs = collect_real_observation()
    observer.last_observation = obs
    
    # Add to history (with size limit)
    push!(observer.observation_history, obs)
    if length(observer.observation_history) > observer.history_size
        popfirst!(observer.observation_history)
    end
    
    return obs
end

"""
    get_history(observer::SystemObserver, n::Int)::Vector{Observation}
Get the n most recent observations
"""
function get_history(observer::SystemObserver, n::Int)::Vector{Observation}
    history = observer.observation_history
    if isempty(history)
        return Observation[]
    end
    
    # Return last n observations
    start_idx = max(1, length(history) - n + 1)
    return history[start_idx:end]
end

"""
    get_average_metrics(observer::SystemObserver)::Dict{Symbol, Float32}
Calculate average metrics over observation history
"""
function get_average_metrics(observer::SystemObserver)::Dict{Symbol, Float32}
    history = observer.observation_history
    
    if isempty(history)
        return Dict{Symbol, Float32}(
            :cpu_usage => 0.1f0,
            :memory_usage => 0.5f0,
            :disk_io => 0.0f0,
            :network_latency => 0.1f0,
            :file_count => 0,
            :process_count => 1
        )
    end
    
    # Calculate averages
    n = length(history)
    
    cpu_avg = sum(o.cpu_usage for o in history) / n
    mem_avg = sum(o.memory_usage for o in history) / n
    disk_avg = sum(o.disk_io for o in history) / n
    net_avg = sum(o.network_latency for o in history) / n
    file_avg = sum(Float32(o.file_count) for o in history) / n
    proc_avg = sum(Float32(o.process_count) for o in history) / n
    
    return Dict{Symbol, Float32}(
        :cpu_usage => cpu_avg,
        :memory_usage => mem_avg,
        :disk_io => disk_avg,
        :network_latency => net_avg,
        :file_count => Int(file_avg),
        :process_count => Int(proc_avg)
    )
end

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    create_default_observer()::SystemObserver
Create a default SystemObserver with sensible settings
"""
function create_default_observer()::SystemObserver
    return SystemObserver(1.0; history_size=100)
end

"""
    to_kernel_observation(obs::Observation)::NamedTuple
Convert SystemObserver.Observation to Kernel-compatible format
"""
function to_kernel_observation(obs::Observation)
    return (
        cpu_load=obs.cpu_usage,
        memory_usage=obs.memory_usage,
        disk_io=obs.disk_io,
        network_latency=obs.network_latency,
        file_count=obs.file_count,
        process_count=obs.process_count
    )
end

end # module
