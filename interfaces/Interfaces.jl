"""
    Interfaces Module

Parent module for all JARVIS interface implementations.
Provides unified access to Desktop, Web, and Mobile interfaces.

# Submodules
- `Desktop`: System tray and desktop integration
- `Web`: Web dashboard and control UI
- `Mobile`: Mobile API endpoints

# Usage
```julia
using Interfaces

# Start web dashboard
Interfaces.Web.serve_dashboard()

# Start mobile API
Interfaces.Mobile.serve_mobile_api()

# Show system tray
Interfaces.Desktop.show_tray_icon()
```
"""
module Interfaces

# Export interface modules
using .Desktop
using .Web
using .Mobile

# Re-export public functions for convenience
export Desktop, Web, Mobile

# Module version
const VERSION = "1.0.0"

"""
    start_all_interfaces(;web_port=8080, mobile_port=9090)

Start all available interfaces.
# Arguments
- `web_port::Int`: Port for web dashboard
- `mobile_port::Int`: Port for mobile API
"""
function start_all_interfaces(;web_port=8080, mobile_port=9090)
    interfaces = Dict(
        :desktop => Desktop.show_tray_icon(),
        :web => Web.serve_dashboard(port=web_port),
        :mobile => Mobile.serve_mobile_api(port=mobile_port),
        :timestamp => now()
    )
    
    @info "Started all JARVIS interfaces"
    return interfaces
end

"""
    get_interface_status()

Get status of all interfaces.
"""
function get_interface_status()
    return Dict(
        :desktop => Dict(:status => "available"),
        :web => Dict(:status => "available"),
        :mobile => Dict(:status => "available"),
        :timestamp => now()
    )
end

# Export additional utility functions
export start_all_interfaces, get_interface_status, VERSION

end # module Interfaces
