"""
    Interfaces Module

Parent module for all JARVIS interface implementations.
Provides unified access to Desktop, Web, Mobile interfaces, and UnifiedBridge.

# Submodules
- `Desktop`: System tray and desktop integration
- `Web`: Web dashboard and control UI
- `Mobile`: Mobile API endpoints
- `UnifiedBridge`: Manager-Worker bridge for cross-language IPC

# Usage
```julia
using Interfaces

# Start web dashboard
Interfaces.Web.serve_dashboard()

# Start mobile API
Interfaces.Mobile.serve_mobile_api()

# Show system tray
Interfaces.Desktop.show_tray_icon()

# Initialize unified bridge
UnifiedBridge.init_bridge()
UnifiedBridge.connect_warden()
```
"""
module Interfaces

# Export interface modules
using .Desktop
using .Web
using .Mobile

# Include UnifiedBridge as a submodule (in same directory)
include("UnifiedBridge.jl")
using .UnifiedBridge

# Re-export public functions for convenience
export Desktop, Web, Mobile, UnifiedBridge

# Module version
const VERSION = "1.0.0"

"""
    start_all_interfaces(;web_port=8080, mobile_port=9090)

Start all available interfaces.
# Arguments
- `web_port::Int`: Port for web dashboard
- `mobile_port::Int`: Port for mobile API
- `init_bridge::Bool`: Whether to initialize the UnifiedBridge
"""
function start_all_interfaces(;web_port=8080, mobile_port=9090, init_bridge::Bool=true)
    interfaces = Dict(
        :timestamp => now()
    )
    
    # Initialize Unified Bridge for cross-language IPC
    if init_bridge
        try
            UnifiedBridge.init_bridge()
            UnifiedBridge.connect_warden()
            interfaces[:bridge] = Dict(:status => "initialized")
        catch e
            interfaces[:bridge] = Dict(:status => "failed", :error => string(e))
        end
    end
    
    # Start desktop interface if available
    try
        interfaces[:desktop] = Desktop.show_tray_icon()
    catch e
        @warn "Could not start desktop interface: $e"
    end
    
    # Start web interface
    try
        interfaces[:web] = Web.serve_dashboard(port=web_port)
    catch e
        @warn "Could not start web interface: $e"
    end
    
    # Start mobile interface
    try
        interfaces[:mobile] = Mobile.serve_mobile_api(port=mobile_port)
    catch e
        @warn "Could not start mobile interface: $e"
    end
    
    @info "Started all JARVIS interfaces"
    return interfaces
end

"""
    get_interface_status()

Get status of all interfaces.
"""
function get_interface_status()
    status = Dict(
        :timestamp => now()
    )
    
    # Get UnifiedBridge status
    try
        status[:bridge] = UnifiedBridge.get_bridge_status()
    catch e
        status[:bridge] = Dict(:status => "unavailable", :error => string(e))
    end
    
    status[:desktop] = Dict(:status => "available")
    status[:web] = Dict(:status => "available")
    status[:mobile] = Dict(:status => "available")
    
    return status
end

# Export additional utility functions
export start_all_interfaces, get_interface_status, VERSION

end # module Interfaces
