# capabilities/safe_shell.jl - Restricted shell execution
# SECURITY HARDENED: Blocked dangerous characters, null bytes, newlines, globbing
# PATH TRAVERSAL FIX: Added canonicalization, whitelist directories, explicit errors
# SHELL INJECTION FIX: Enhanced with comprehensive pattern matching

module SafeShell

export meta, execute

# ============================================================================
# SECURITY CONFIGURATION - FAIL CLOSED
# ============================================================================

# Whitelist of allowed commands (for security)
# SECURITY HARDENED: Principle of Least Privilege - only safe output commands
# REMOVED: cat, head, tail, wc (file-reading commands enable data exfiltration)
# REMOVED: md5sum, sha256sum (could be used to verify exfiltrated data hashes)
const WHITELIST = Set([
    # Safe output-only commands
    "echo",
    # System info (minimal, non-disclosing)
    "date", "hostname"
])

# SECURITY: Allowed base directories for file operations
# PATH TRAVERSAL FIX: Restrict operations to safe directories only
const ALLOWED_DIRS = [
    "/tmp",
    "/var/tmp",
    "/home/user/projectx"  # Project workspace
]

# Shell metacharacters that could enable injection
# SECURITY: Enhanced with more dangerous patterns
const DANGEROUS_CHARS = r"[;&|`\$(){}<>\\]|&&|\|\||\s+>"

# SECURITY: Additional dangerous patterns to block
# SECURITY HARDENED: Extended to cover all sensitive system directories
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
    # Sensitive system directories - BLOCK ALL ACCESS
    r"^/etc",    # System configuration
    r"^/proc",   # Process information
    r"^/sys",    # System kernel info
    r"^/root",   # Root home directory
    r"^/var",    # Variable data (logs, caches, etc)
    r"^/opt",    # Optional/third-party software
    r"^/srv",    # Service data
    r"^/mnt",    # Mount points
    r"^/boot",   # Boot files
    r"^/media",  # Removable media
    r"^/dev",    # Device files
    r"^/run",    # Runtime data
    r"^/lost\+found",  # Filesystem recovery
]

# SECURITY FIX: Shell injection specific patterns
const SHELL_INJECTION_PATTERNS = [
    r"\$\([^)]+\)",           # Command substitution $(...)
    r"`[^`]+`",                 # Backtick command substitution
    r"\|\s*bash",              # Pipe to bash
    r"\|\s*sh",                # Pipe to sh
    r"&&\s+",                  # Command chaining
    r"\|\s*",                  # Pipe commands
    r";#",                      # Comment injection
    r"\s>\s*/tmp",             # Output redirect to tmp
    r"\s>>\s*/tmp",            # Output append to tmp
    r"\s\d?>\s*",             # Any output redirect
    r";\s*rm\s",              # Semicolon + rm
    r";\s*wget\s",            # Semicolon + wget
    r";\s*curl\s",            # Semicolon + curl
    r";\s*nc\s",              # Semicolon + netcat
    r";\s*nmap\s",            # Semicolon + nmap
    r"\|\s*nc\s",             # Pipe + netcat
    r"\|\s*nmap\s",           # Pipe + nmap
    r"\bexec\s",              # exec command
    r"\beval\s",              # eval command
    r"\bsource\s",            # source command
    r"\.\s*/",                # Execute from path
]

# Maximum command length to prevent buffer overflow attacks
const MAX_COMMAND_LENGTH = 256

# SHELL INJECTION FIX: Validate input is purely alphanumeric
function validate_no_injection(command::String)::Tuple{Bool, String}
    # Check for command substitution
    for pattern in SHELL_INJECTION_PATTERNS
        if occursin(pattern, command)
            return (false, "Shell injection pattern detected: $(pattern)")
        end
    end
    
    # Check for dangerous characters
    if occursin(DANGEROUS_CHARS, command)
        return (false, "Shell metacharacters detected")
    end
    
    # Ensure command only contains safe characters
    if !occursin(r"^[a-zA-Z0-9_\-\s]+$", command)
        return (false, "Command contains invalid characters")
    end
    
    return (true, "OK")
end

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
    
    PATH TRAVERSAL FIX: Returns (success, sanitized_value, error_message) tuple
    instead of throwing exceptions. This ensures proper error handling.
"""
function sanitize_argument(arg::String)::Tuple{Bool, String, String}
    # Check for blocked patterns - return error instead of throwing
    for pattern in BLOCKED_PATTERNS
        if occursin(pattern, arg)
            # PATH TRAVERSAL FIX: Return explicit error instead of throwing
            return (false, "", "SECURITY: Blocked dangerous pattern detected: $(pattern)")
        end
    end
    
    # SHELL INJECTION FIX: Additional validation for arguments
    valid, error_msg = validate_no_injection(arg)
    if !valid
        return (false, "", "SECURITY: $error_msg")
    end
    
    # Remove any remaining special characters
    sanitized = replace(arg, r"[^a-zA-Z0-9_\-./]" => "")
    return (true, sanitized, "")
end

# Allow SubString input as well
sanitize_argument(arg::SubString{String}) = sanitize_argument(String(arg))

"""
    validate_command - Comprehensive command validation
    SECURITY: Multiple layers of validation
    
    PATH TRAVERSAL FIX: Now handles tuple return from sanitize_argument
    and adds path canonicalization check.
"""

"""
    canonicalize_path - Resolve path to canonical form
    PATH TRAVERSAL FIX: Resolves symlinks and .. components to prevent bypass attacks
"""
function canonicalize_path(path::String)::Tuple{Bool, String, String}
    # Skip empty paths
    if isempty(path)
        return (true, "", "")
    end
    
    # Skip if path doesn't exist (will be caught by command execution)
    # But check for ALL suspicious patterns first
    # SECURITY FIX: Extended to cover all sensitive system directories
    if occursin(r"^/etc|^/proc|^/sys|^/root|^/var|^/opt|^/srv|^/mnt|^/boot|^/media|^/dev|^/run", path)
        return (false, "", "Access to sensitive system directory denied")
    end
    
    # Try to canonicalize if file exists - handle edge cases safely
    if isfile(path) || isdir(path)
        try
            canonical = realpath(path)
            # Check if canonical path is within allowed directories
            allowed = false
            for allowed_dir in ALLOWED_DIRS
                # Skip if allowed_dir doesn't exist
                if isdir(allowed_dir) && startswith(canonical, allowed_dir)
                    allowed = true
                    break
                end
            end
            if !allowed
                return (false, "", "Path resolved to non-allowed directory: $canonical")
            end
            return (true, canonical, "")
        catch e
            return (false, "", "Failed to canonicalize path: $(string(e))")
        end
    end
    
    # For non-existent paths, validate the path components safely
    # SECURITY FIX: Block ALL paths outside allowed directories, no warnings
    if startswith(path, "/")
        # Absolute path - check if it starts with any allowed directory
        for allowed_dir in ALLOWED_DIRS
            # Only check existing allowed directories
            if isdir(allowed_dir) && startswith(path, allowed_dir)
                return (true, path, "")
            end
        end
        # Not in allowed directory - BLOCK it (no warning, block directly)
        return (false, "", "Path not in allowed directories: $path")
    end
    
    return (true, path, "")
end

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
    
    # SHELL INJECTION FIX: Enhanced shell metacharacter check
    # Check 4: Shell metacharacters AND injection patterns
    if occursin(DANGEROUS_CHARS, command)
        return (false, "Shell metacharacters detected")
    end
    
    # Check 4b: Shell injection patterns (comprehensive)
    valid, error_msg = validate_no_injection(command)
    if !valid
        return (false, error_msg)
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
    
    # Check 7: Argument sanitization with path traversal detection
    # PATH TRAVERSAL FIX: Now handles tuple return and canonicalizes paths
    if length(parts) > 1
        for i in 2:length(parts)
            # Use new tuple return from sanitize_argument
            success, sanitized, error_msg = sanitize_argument(parts[i])
            
            if !success
                return (false, error_msg)
            end
            
            if isempty(sanitized) && !isempty(parts[i])
                return (false, "Dangerous argument detected: $(parts[i])")
            end
            
            # PATH TRAVERSAL FIX: Also canonicalize and check the path
            if !isempty(sanitized) && (startswith(sanitized, "/") || occursin("/", sanitized))
                canon_success, canonical_path, canon_error = canonicalize_path(sanitized)
                if !canon_success
                    return (false, "Path validation failed: $canon_error")
                end
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
        # PATH TRAVERSAL FIX: Explicit error message instead of empty string
        return Dict(
            "success" => false,
            "effect" => "Command validation failed: $reason",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "data" => Dict(
                "stdout" => "ERROR: $reason",  # FIX: Explicit error in stdout
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
                # PATH TRAVERSAL FIX: Handle tuple return from sanitize_argument
                success, sanitized, error_msg = sanitize_argument(parts[i])
                if success && !isempty(sanitized)
                    push!(args, sanitized)
                elseif !success
                    # Security error during execution - should not happen if validation passed
                    return Dict(
                        "success" => false,
                        "effect" => "Security validation failed: $error_msg",
                        "actual_confidence" => 0.0,
                        "energy_cost" => 0.0,
                        "data" => Dict(
                            "stdout" => "ERROR: $error_msg",  # FIX: Explicit error
                            "exit_code" => 127,
                            "reason" => error_msg
                        )
                    )
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
        # PATH TRAVERSAL FIX: Explicit error message instead of empty string
        error_detail = string(e)
        return Dict(
            "success" => false,
            "effect" => "Execution failed: $error_detail",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "data" => Dict(
                "stdout" => "ERROR: $error_detail",  # FIX: Explicit error in stdout
                "exit_code" => 1,
                "reason" => error_detail
            )
        )
    end
end

end  # module
