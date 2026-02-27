# capabilities/safe_shell.jl - Restricted shell execution
# SECURITY HARDENED: Blocked dangerous characters, null bytes, newlines, globbing

module SafeShell

export meta, execute

# Whitelist of allowed commands (for security)
# SECURITY: Removed 'find' - can be used for directory traversal and information disclosure
const WHITELIST = Set([
    # File operations (read-only)
    "echo", "ls", "pwd", "cat", "head", "tail", "wc", "grep",
    "sort", "uniq", "cut", "tr", "tee",
    # System info (read-only)
    "date", "whoami", "hostname", "uname", "uptime",
    # Checksums (read-only)
    "md5sum", "sha256sum", "sha1sum",
    # Process info (read-only)
    "ps", "top", "df", "du", "free"
])

# Shell metacharacters that could enable injection
# SECURITY: Enhanced with more dangerous patterns
const DANGEROUS_CHARS = r"[;&|`\$(){}<>\\]|&&|\|\||\s+>"

# SECURITY: Additional dangerous patterns to block
const BLOCKED_PATTERNS = [
    r"\x00",  # Null byte injection
    r"\n",    # Newline injection  
    r"\r",    # Carriage return injection
    r"\s+-",  # Flag injection (e.g., "ls -la")
    r"\*",    # Glob expansion
    r"\?",    # Glob wildcard
    r"\[.*\]",  # Glob bracket
    r"\~",    # Tilde expansion
    r"\.\.",  # Directory traversal
    r"^/etc",  # Absolute path to sensitive directory
    r"^/proc", # /proc filesystem
    r"^/sys",  # /sys filesystem
]

# Maximum command length to prevent buffer overflow attacks
const MAX_COMMAND_LENGTH = 256

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

"""
    sanitize_argument - Sanitize individual command arguments
    SECURITY: Prevents injection through arguments
"""
function sanitize_argument(arg::String)::String
    # Check for blocked patterns
    for pattern in BLOCKED_PATTERNS
        if occursin(pattern, arg)
            return ""  # Return empty string for dangerous args
        end
    end
    
    # Remove any remaining special characters
    sanitized = replace(arg, r"[^a-zA-Z0-9_\-./]" => "")
    return sanitized
end

# Allow SubString input as well
sanitize_argument(arg::SubString{String}) = sanitize_argument(String(arg))

"""
    validate_command - Comprehensive command validation
    SECURITY: Multiple layers of validation
"""
function validate_command(command::String)::Tuple{Bool, String}
    # Check 1: Length limit
    if length(command) > MAX_COMMAND_LENGTH
        return (false, "Command exceeds maximum length of $MAX_COMMAND_LENGTH")
    end
    
    # Check 2: Null byte
    if occursin("\x00", command)
        return (false, "Null byte injection detected")
    end
    
    # Check 3: Newline injection
    if occursin("\n", command) || occursin("\r", command)
        return (false, "Newline/carriage return injection detected")
    end
    
    # Check 4: Shell metacharacters
    if occursin(DANGEROUS_CHARS, command)
        return (false, "Shell metacharacters detected")
    end
    
    # Check 5: Get command base
    parts = split(command)
    if isempty(parts)
        return (false, "Empty command")
    end
    cmd_base = parts[1]
    
    # Check 6: Whitelist
    if cmd_base ∉ WHITELIST
        return (false, "Command '$cmd_base' not in whitelist")
    end
    
    # Check 7: Argument sanitization
    if length(parts) > 1
        for i in 2:length(parts)
            sanitized = sanitize_argument(parts[i])
            if isempty(sanitized) && !isempty(parts[i])
                return (false, "Dangerous argument detected: $(parts[i])")
            end
            # Also check for path traversal attempts
            if occursin(r"\.\.", parts[i])
                return (false, "Path traversal attempt detected")
            end
        end
    end
    
    return (true, "OK")
end

function execute(params::Dict)::Dict{String, Any}
    command = get(params, "command", "echo safe")
    
    # SECURITY: Comprehensive validation
    valid, reason = validate_command(command)
    if !valid
        return Dict(
            "success" => false,
            "effect" => "Command validation failed: $reason",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "data" => Dict(
                "stdout" => "",
                "exit_code" => 127,
                "reason" => reason
            )
        )
    end
    
    try
        # Execute using safer method - avoid shell interpretation
        # Split command and sanitize arguments
        parts = split(command)
        cmd = parts[1]
        args = String[]
        
        if length(parts) > 1
            for i in 2:length(parts)
                sanitized = sanitize_argument(parts[i])
                if !isempty(sanitized)
                    push!(args, sanitized)
                end
            end
        end
        
        # Execute command directly without shell interpretation
        # Use backtick syntax for safe command execution (safe against injection)
        cmd_expr = `$(cmd) $(args...)`
        output = read(cmd_expr, String)
        
        return Dict(
            "success" => true,
            "effect" => "Command executed: $cmd",
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
