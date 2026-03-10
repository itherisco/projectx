"""
    ExecutionSandbox - Isolated tool execution environment
"""

module ExecutionSandbox

# Re-export sandbox types for external use
# The actual implementation is in the parent module

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

# Stub functions - actual implementation would use ToolRegistry
function execute_in_sandbox(tool_id::String, params::Dict, mode::SandboxMode, registry::Any, config::SandboxConfig)::ExecutionResult
    return ExecutionResult(
        success=true,
        output=Dict("result" => "Executed $tool_id", "params" => params),
        error=nothing,
        execution_time=0.0,
        sandbox_mode=:local
    )
end

function validate_params(metadata::Any, params::Dict)::Bool
    return true
end

end # module
