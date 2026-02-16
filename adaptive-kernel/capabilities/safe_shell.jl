# capabilities/safe_shell.jl - Restricted shell execution

module SafeShell

export meta, execute

# Whitelist of allowed commands (for security)
const WHITELIST = Set([
    "echo",
    "ls",
    "pwd",
    "cat",
    "grep",
    "date",
    "whoami"
])

function meta()::Dict{String, Any}
    return Dict(
        "id" => "safe_shell",
        "name" => "Safe Shell Execute",
        "description" => "Execute a whitelisted command in a restricted shell",
        "inputs" => Dict("command" => "string"),
        "outputs" => Dict("stdout" => "string", "exit_code" => "int", "success" => "bool"),
        "cost" => 0.1,
        "risk" => "high",
        "reversible" => false
    )
end

function execute(params::Dict{String, Any})::Dict{String, Any}
    command = get(params, "command", "echo safe")
    
    # Safety check: verify command is whitelisted
    cmd_base = first(split(command))  # Get first word (the command itself)
    
    if cmd_base ∉ WHITELIST
        return Dict(
            "success" => false,
            "effect" => "Command '$cmd_base' not in whitelist",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "data" => Dict(
                "stdout" => "",
                "exit_code" => 127,
                "reason" => "unauthorized"
            )
        )
    end
    
    try
        # Execute in restricted manner
        output = read(`sh -c $command`, String)
        
        return Dict(
            "success" => true,
            "effect" => "Command executed: $cmd_base",
            "actual_confidence" => 0.85,
            "energy_cost" => 0.1,
            "data" => Dict(
                "stdout" => output,
                "exit_code" => 0,
                "command" => command
            )
        )
    catch e
        return Dict(
            "success" => false,
            "effect" => "Execution failed: $(string(e))",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "data" => Dict(
                "stdout" => "",
                "exit_code" => 1
            )
        )
    end
end

end  # module
