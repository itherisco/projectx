"""
    ToolMetadata - Metadata for tool registration
"""
struct ToolMetadata
    id::String
    name::String
    source::Symbol  # :native or :openclaw
    risk_level::Symbol  # :read_only, :low, :medium, :high, :critical
    execution_mode::Symbol  # :julia or :docker
    endpoint::Union{String, Nothing}
    description::String
    parameters::Vector{String}  # parameter names
end

"""
    ToolRegistry - Central registry for all executable tools
Binds OpenClaw tools + native capabilities
"""
mutable struct ToolRegistry
    openclaw_endpoint::String
    native_capabilities::Dict{String, Any}  # capability_name => Capability
    tool_metadata::Dict{String, ToolMetadata}
    
    function ToolRegistry(endpoint::String="http://localhost:3000")
        new(endpoint, Dict{String, Any}(), Dict{String, ToolMetadata}())
    end
end

"""
    register_native_tool!(registry::ToolRegistry, metadata::ToolMetadata, capability::Any)
Register a native Julia capability
"""
function register_native_tool!(registry::ToolRegistry, metadata::ToolMetadata, capability::Any)
    registry.native_capabilities[metadata.name] = capability
    registry.tool_metadata[metadata.id] = metadata
    @info "Registered native tool: $(metadata.name)"
end

"""
    register_openclaw_tool!(registry::ToolRegistry, metadata::ToolMetadata)
Register an OpenClaw tool (remote execution)
"""
function register_openclaw_tool!(registry::ToolRegistry, metadata::ToolMetadata)
    registry.tool_metadata[metadata.id] = metadata
    @info "Registered OpenClaw tool: $(metadata.name)"
end

"""
    get_tool_metadata(registry::ToolRegistry, tool_id::String)::Union{ToolMetadata, Nothing}
Get metadata for a tool
"""
function get_tool_metadata(registry::ToolRegistry, tool_id::String)::Union{ToolMetadata, Nothing}
    return get(registry.tool_metadata, tool_id, nothing)
end

"""
    list_tools(registry::ToolRegistry; source::Union{Symbol, Nothing}=nothing)::Vector{ToolMetadata}
List all registered tools, optionally filtered by source
"""
function list_tools(registry::ToolRegistry; source::Union{Symbol, Nothing}=nothing)::Vector{ToolMetadata}
    if source === nothing
        return collect(values(registry.tool_metadata))
    end
    return filter(t -> t.source == source, collect(values(registry.tool_metadata)))
end

"""
    is_tool_available(registry::ToolRegistry, tool_id::String)::Bool
Check if a tool is registered and available
"""
function is_tool_available(registry::ToolRegistry, tool_id::String)::Bool
    return haskey(registry.tool_metadata, tool_id)
end
