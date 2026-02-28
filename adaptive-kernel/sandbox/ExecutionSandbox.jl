"""
    ExecutionSandbox - Isolated tool execution environment
"""
abstract type SandboxMode end
struct DockerSandbox <: SandboxMode end
struct ProcessSandbox <: SandboxMode end
struct LocalSandbox <: SandboxMode end

"""
    ExecutionResult - Result of sandboxed tool execution
"""
struct ExecutionResult
    success::Bool
    output::Any
    error::Union{String, Nothing}
    execution_time::Float64  # seconds
    sandbox_mode::Symbol
end

"""
    SandboxConfig - Configuration for sandbox execution
"""
mutable struct SandboxConfig
    timeout::Int  # seconds
    memory_limit_mb::Int
    cpu_limit::Float64  # 0.0 - 1.0 (percentage of CPU)
    network_allowed::Bool
    filesystem_allowed::Bool
    
    function SandboxConfig(;timeout::Int=30, memory_limit_mb::Int=512, 
                          cpu_limit::Float64=0.5, network_allowed::Bool=true,
                          filesystem_allowed::Bool=true)
        new(timeout, memory_limit_mb, cpu_limit, network_allowed, filesystem_allowed)
    end
end

"""
    execute_in_sandbox(tool_id::String, params::Dict, mode::SandboxMode, 
                      registry::ToolRegistry, config::SandboxConfig)::ExecutionResult
Execute a tool in the specified sandbox mode
"""
function execute_in_sandbox(
    tool_id::String,
    params::Dict,
    mode::LocalSandbox,
    registry::ToolRegistry,
    config::SandboxConfig
)::ExecutionResult
    start_time = time()
    
    # Validate tool exists
    metadata = get_tool_metadata(registry, tool_id)
    if metadata === nothing
        return ExecutionResult(
            success=false,
            output=nothing,
            error="Tool not found: $tool_id",
            execution_time=time() - start_time,
            sandbox_mode=:local
        )
    end
    
    # Execute based on source
    if metadata.source == :native
        return _execute_native(tool_id, params, config, start_time)
    elseif metadata.source == :openclaw
        return _execute_openclaw(tool_id, params, registry, config, start_time)
    end
    
    return ExecutionResult(
        success=false,
        output=nothing,
        error="Unknown tool source: $(metadata.source)",
        execution_time=time() - start_time,
        sandbox_mode=:local
    )
end

"""
    _execute_native - Execute a native Julia capability
"""
function _execute_native(tool_id::String, params::Dict, config::SandboxConfig, start_time::Float64)::ExecutionResult
    # Get capability from registry
    # In practice, would look up and call the actual function
    # For now, return placeholder
    
    return ExecutionResult(
        success=true,
        output=Dict("result" => "Executed $tool_id", "params" => params),
        error=nothing,
        execution_time=time() - start_time,
        sandbox_mode=:local
    )
end

"""
    _execute_openclaw - Execute via OpenClaw API
"""
function _execute_openclaw(tool_id::String, params::Dict, registry::ToolRegistry, 
                          config::SandboxConfig, start_time::Float64)::ExecutionResult
    # Would make HTTP call to OpenClaw endpoint
    # For now, return placeholder
    
    return ExecutionResult(
        success=true,
        output=Dict("result" => "OpenClaw execution for $tool_id", "params" => params),
        error=nothing,
        execution_time=time() - start_time,
        sandbox_mode=:docker
    )
end

"""
    validate_params(metadata::ToolMetadata, params::Dict)::Bool
Validate parameters against tool metadata
"""
function validate_params(metadata::ToolMetadata, params::Dict)::Bool
    for param in metadata.parameters
        if !haskey(params, param)
            @warn "Missing required parameter: $param for tool $(metadata.name)"
            return false
        end
    end
    return true
end
