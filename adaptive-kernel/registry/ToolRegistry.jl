"""
    ToolMetadata - Metadata for tool registration
"""
struct ToolMetadata
    id::String
    name::String
    source::Symbol  # :native or :openclaw
    risk_level::Symbol  # :read_only, :low, :medium, :high, :critical
    execution_mode::Symbol  # :julia, :docker, or :sandboxed
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

# ============================================================================
# CODE INTERPRETER CAPABILITY REGISTRATION
# ============================================================================

"""
    register_code_interpreter!(registry::ToolRegistry)
    
Register the code interpreter capability with sandbox execution mode.
This is the primary capability for safe code execution in the adaptive kernel.
"""
function register_code_interpreter!(registry::ToolRegistry)
    metadata = ToolMetadata(
        "capability_code_interpreter",
        "Code Interpreter",
        :native,
        :critical,
        :sandboxed,
        nothing,
        "Isolated code execution via ExecutionSandbox with WDT protection",
        ["code", "language", "timeout", "memory_limit"]
    )
    
    register_native_tool!(registry, metadata, :code_interpreter)
    @info "Registered code interpreter capability with sandbox execution"
end

"""
    initialize_default_capabilities!(registry::ToolRegistry)
    
Initialize all default capabilities for the adaptive kernel.
"""
function initialize_default_capabilities!(registry::ToolRegistry)
    register_code_interpreter!(registry)
end
