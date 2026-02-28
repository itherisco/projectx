using Dates

"""
    HealthMonitor - Component health tracking
"""
@enum HealthStatus HEALTHY DEGRADED UNHEALTHY UNKNOWN

"""
    ComponentHealth - Health status of a single component
"""
struct ComponentHealth
    name::String
    status::HealthStatus
    last_success::DateTime
    last_failure::DateTime
    failure_count::Int
    success_count::Int
    last_check::DateTime
end

mutable struct HealthMonitor
    components::Dict{String, ComponentHealth}
    last_check::DateTime
    
    function HealthMonitor()
        new(Dict{String, ComponentHealth}(), now())
    end
end

"""
    register_component!(monitor::HealthMonitor, name::String)
Register a new component for health monitoring
"""
function register_component!(monitor::HealthMonitor, name::String)
    now_time = now()
    monitor.components[name] = ComponentHealth(
        name=name,
        status=UNKNOWN,
        last_success=now_time,
        last_failure=now_time,
        failure_count=0,
        success_count=0,
        last_check=now_time
    )
    @info "Registered component for health monitoring: $name"
end

"""
    record_success!(monitor::HealthMonitor, component::String)
Record a successful operation for a component
"""
function record_success!(monitor::HealthMonitor, component::String)
    if !haskey(monitor.components, component)
        register_component!(monitor, component)
    end
    
    health = monitor.components[component]
    monitor.components[component] = ComponentHealth(
        name=component,
        status=health.status,
        last_success=now(),
        last_failure=health.last_failure,
        failure_count=health.failure_count,
        success_count=health.success_count + 1,
        last_check=now()
    )
end

"""
    record_failure!(monitor::HealthMonitor, component::String)
Record a failed operation for a component
"""
function record_failure!(monitor::HealthMonitor, component::String)
    if !haskey(monitor.components, component)
        register_component!(monitor, component)
    end
    
    health = monitor.components[component]
    monitor.components[component] = ComponentHealth(
        name=component,
        status=health.status,
        last_success=health.last_success,
        last_failure=now(),
        failure_count=health.failure_count + 1,
        success_count=health.success_count,
        last_check=now()
    )
    
    # Update status based on failure count
    _update_status!(monitor, component)
end

"""
    _update_status! - Update health status based on failure count
"""
function _update_status!(monitor::HealthMonitor, component::String)
    health = monitor.components[component]
    
    # Unhealthy if recent failures
    recent_failure_window = 60  # seconds
    time_since_failure = (now() - health.last_failure).value / 1000
    
    if time_since_failure < recent_failure_window
        if health.failure_count > 3
            new_status = UNHEALTHY
        elseif health.failure_count > 0
            new_status = DEGRADED
        else
            new_status = HEALTHY
        end
    else
        new_status = HEALTHY
    end
    
    monitor.components[component] = ComponentHealth(
        name=health.name,
        status=new_status,
        last_success=health.last_success,
        last_failure=health.last_failure,
        failure_count=health.failure_count,
        success_count=health.success_count,
        last_check=now()
    )
end

"""
    check_health(monitor::HealthMonitor, component::String)::HealthStatus
Get health status of a component
"""
function check_health(monitor::HealthMonitor, component::String)::HealthStatus
    if !haskey(monitor.components, component)
        return UNKNOWN
    end
    
    _update_status!(monitor, component)
    return monitor.components[component].status
end

"""
    get_all_health(monitor::HealthMonitor)::Dict{String, HealthStatus}
Get health status of all components
"""
function get_all_health(monitor::HealthMonitor)::Dict{String, HealthStatus}
    result = Dict{String, HealthStatus}()
    for (name, _) in monitor.components
        result[name] = check_health(monitor, name)
    end
    return result
end

"""
    is_healthy(monitor::HealthMonitor, component::String)::Bool
Check if a component is healthy
"""
function is_healthy(monitor::HealthMonitor, component::String)::Bool
    status = check_health(monitor, component)
    return status == HEALTHY || status == DEGRADED
end

"""
    get_overall_status(monitor::HealthMonitor)::HealthStatus
Get overall system health status
"""
function get_overall_status(monitor::HealthMonitor)::HealthStatus
    if isempty(monitor.components)
        return UNKNOWN
    end
    
    has_unhealthy = false
    has_degraded = false
    
    for (_, status) in get_all_health(monitor)
        if status == UNHEALTHY
            return UNHEALTHY
        elseif status == DEGRADED
            has_degraded = true
        elseif status == UNKNOWN
            # Unknown counts as degraded
            has_degraded = true
        end
    end
    
    return has_degraded ? DEGRADED : HEALTHY
end
