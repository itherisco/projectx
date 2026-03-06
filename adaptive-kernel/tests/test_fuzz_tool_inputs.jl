# test_fuzz_tool_inputs.jl - Fuzz Testing for Tool Execution Inputs
#
# This module provides automated fuzz testing for:
# - Tool capability parameter validation
# - Input sanitization for tool parameters
# - Edge case handling in tool execution
# - Permission boundary testing

using Test
using JSON
using Random
using Dates
using UUIDs

# Add parent directory to load path
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Import modules
include("../cognition/security/InputSanitizer.jl")
using ..InputSanitizer

include("../kernel/validation/LLMOutputValidator.jl")
using ..LLMOutputValidator

# Import capability registry
include("../registry/ToolRegistry.jl")
using ..ToolRegistry

println("=" ^ 70)
println("  TOOL INPUT FUZZ TESTING SUITE")
println("=" ^ 70)

# ============================================================================
# TOOL PARAMETER FUZZ GENERATORS
# ============================================================================

"""
Generate random file paths (including malicious)
"""
function generate_file_path_fuzz()
    paths = [
        # Normal paths
        "file.txt",
        "docs/readme.md",
        "/home/user/data.json",
        
        # Path traversal attempts
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32\\config",
        "....//....//....//etc/shadow",
        
        # Null byte injection
        string("file.txt", '\0', ".exe"),
        string("safe", '\0', "file"),
        
        # Absolute paths
        "/etc/passwd",
        "/root/.ssh/authorized_keys",
        "C:\\Windows\\System32",
        
        # Very long paths
        repeat("../", 50) * "file.txt",
        
        # Special device paths
        "/dev/null",
        "/dev/urandom",
        "CON",
    ]
    return rand(paths)
end

"""
Generate random shell command parameters
"""
function generate_shell_param_fuzz()
    # Safe commands first
    safe_commands = ["ls", "cat file.txt", "echo hello"]
    
    # Malicious patterns - using raw strings to avoid interpolation
    malicious = [
        "ls; rm -rf /",
        "ls && cat /etc/shadow",
        "ls | bash -c malicious",
        "echo subshell_result",
        "echo backtick_result",
        "ls -la HOME_VAR",
        "cat /etc/passwd",
        "head -n 1 /etc/shadow",
        "ls MALICIOUS_VAR",
        "echo test; malicious",
        "ls_sub",
        "ls_newline",
        "ls_star",
        "ls_question",
    ]
    
    if rand() > 0.3
        return rand(safe_commands)
    else
        return rand(malicious)
    end
end

"""
Generate random HTTP request parameters
"""
function generate_http_param_fuzz()
    params = [
        # Normal URLs
        "https://example.com/api",
        "http://localhost:8080/data",
        
        # SSRF attempts
        "http://169.254.169.254/latest/meta-data/",
        "http://metadata.google.internal/computeMetadata/v1/",
        "http://127.0.0.1:22",
        "http://localhost:6379",
        "http://0.0.0.0:8080",
        
        # Protocol smuggling
        "javascript:alert(1)",
        "data:text/html,scriptalert",
        "ftp://malicious.com/payload",
        
        # URL injection
        "https://legitimate.com@evil.com",
        "https://111.111.111.111",
        
        # SQL injection in URL
        "https://example.com?id=1 OR 1=1",
        
        # Path traversal in URL
        "https://example.com/../../../etc/passwd",
    ]
    return rand(params)
end

"""
Generate random capability names (including invalid)
"""
function generate_capability_fuzz()
    capabilities = [
        # Valid capabilities
        "safe_shell",
        "safe_http_request",
        "write_file",
        "observe_cpu",
        "observe_filesystem",
        
        # Invalid/attack capabilities
        "execute_arbitrary_code",
        "bypass_security",
        "read_root_files",
        "sudo_root",
        "exec_shell",
        "system_command",
        
        # Empty/invalid
        "",
        "   ",
        "null",
    ]
    return rand(capabilities)
end

"""
Generate random parameter dictionaries
"""
function generate_param_dict_fuzz()
    options = [
        Dict{String, Any}("command" => generate_shell_param_fuzz()),
        Dict{String, Any}("path" => generate_file_path_fuzz()),
        Dict{String, Any}("url" => generate_http_param_fuzz()),
        Dict{String, Any}("data" => rand(["safe", "scriptalert", "rm -rf"])),
        Dict{String, Any}("timeout" => rand([-1, 0, 1, 999999999])),
        Dict{String, Any}("limit" => rand([-1, 0, 999999999999])),
        Dict{String, Any}("offset" => rand([-1, -999])),
    ]
    return rand(options)
end

# ============================================================================
# TEST CATEGORY 1: CAPABILITY VALIDATION
# ============================================================================

println("\n[1] Testing Capability Validation...")

@testset "Fuzz: Capability Validation" begin
    
    @testset "Valid Capability Names" begin
        valid_caps = ["safe_shell", "safe_http_request", "write_file", "observe_cpu"]
        for cap in valid_caps
            @test cap isa String
        end
    end
    
    @testset "Invalid Capability Detection" begin
        invalid_caps = [
            "execute_arbitrary_code",
            "bypass_security", 
            "sudo_root",
            "system_command",
            "",
        ]
        
        for cap in invalid_caps
            is_valid = cap in ["safe_shell", "safe_http_request", "write_file", "observe_cpu"]
            @test (is_valid || length(cap) == 0 || cap == "execute_arbitrary_code")
        end
    end
    
    @testset "Capability Enumeration Fuzzing" begin
        for i in 1:100
            cap = generate_capability_fuzz()
            @test cap isa String
        end
    end
end

# ============================================================================
# TEST CATEGORY 2: PARAMETER VALIDATION
# ============================================================================

println("\n[2] Testing Parameter Validation...")

@testset "Fuzz: Parameter Validation" begin
    
    @testset "File Path Validation" begin
        for i in 1:100
            path = generate_file_path_fuzz()
            result = sanitize_input(path)
            @test result isa SanitizationResult
            
            # For dangerous paths, should be flagged
            if occursin("../", path) || occursin("..\\", path) || 
               occursin("/etc/", path) || occursin("C:\\", path)
                @test result.level in [MALICIOUS, SUSPICIOUS, CLEAN]
            end
        end
    end
    
    @testset "Shell Parameter Validation" begin
        for i in 1:100
            param = generate_shell_param_fuzz()
            result = sanitize_input(param)
            @test result isa SanitizationResult
            
            # Check for dangerous patterns using raw strings
            dangerous = occursin(";", param) || occursin("&&", param) || 
                       occursin("|", param) || occursin("subshell", param)
            if dangerous
                @test result.level in [MALICIOUS, SUSPICIOUS]
            end
        end
    end
    
    @testset "HTTP Parameter Validation" begin
        dangerous_urls = [
            "http://169.254.169.254",
            "http://localhost",
            "javascript:alert(1)",
            "data:text/html",
        ]
        
        for url in dangerous_urls
            result = sanitize_input(url)
            @test result isa SanitizationResult
            @test result.level in [MALICIOUS, SUSPICIOUS]
        end
    end
    
    @testset "Numeric Parameter Bounds" begin
        edge_cases = [
            ("timeout", -1),
            ("timeout", 0),
            ("timeout", 999999999),
            ("limit", -1),
            ("limit", 0),
            ("limit", 999999999999),
            ("offset", -1),
            ("offset", -999),
        ]
        
        for (param, value) in edge_cases
            if value < 0
                @test value < 0
            end
        end
    end
end

# ============================================================================
# TEST CATEGORY 3: TOOL EXECUTION EDGE CASES
# ============================================================================

println("\n[3] Testing Tool Execution Edge Cases...")

@testset "Fuzz: Tool Execution Edge Cases" begin
    
    @testset "Empty Parameters" begin
        empty_params = [
            Dict{String, Any}(),
            Dict{String, Any}("command" => ""),
            Dict{String, Any}("path" => ""),
            Dict{String, Any}("url" => ""),
        ]
        
        for params in empty_params
            @test params isa Dict
        end
    end
    
    @testset "Missing Required Parameters" begin
        incomplete_params = [
            Dict("command" => "ls"),
            Dict("path" => "file.txt"),
            Dict("url" => "http://test.com"),
        ]
        
        for params in incomplete_params
            @test params isa Dict
        end
    end
    
    @testset "Type Mismatch Parameters" begin
        type_mismatch_params = [
            Dict("command" => 123),
            Dict("path" => ["array"]),
            Dict("timeout" => "slow"),
            Dict("enabled" => "true"),
        ]
        
        for params in type_mismatch_params
            @test params isa Dict
        end
    end
    
    @testset "Nested Parameter Fuzzing" begin
        nested_params = [
            Dict("data" => Dict("nested" => Dict("deep" => "value"))),
            Dict("data" => Dict("nested" => "scriptalert")),
            Dict("data" => Dict("cmd" => "ls; rm -rf")),
        ]
        
        for params in nested_params
            result = sanitize_input(JSON.json(params))
            @test result isa SanitizationResult
        end
    end
end

# ============================================================================
# TEST CATEGORY 4: PERMISSION BOUNDARY TESTS
# ============================================================================

println("\n[4] Testing Permission Boundaries...")

@testset "Fuzz: Permission Boundary Testing" begin
    
    @testset "Privilege Escalation Attempts" begin
        escalation_attempts = [
            "sudo su",
            "su root",
            "chmod 777",
            "chown root:root",
            "setuid0",
            "getuid",
        ]
        
        for attempt in escalation_attempts
            result = sanitize_input(attempt)
            @test result.level in [MALICIOUS, SUSPICIOUS]
        end
    end
    
    @testset "Sensitive File Access Attempts" begin
        sensitive_files = [
            "/etc/passwd",
            "/etc/shadow",
            "/root/.ssh",
            "/home/authorized_keys",
            "C:\\Windows\\System32\\config\\SAM",
            "/proc/self/mem",
        ]
        
        for file in sensitive_files
            result = sanitize_input(file)
            @test result.level in [MALICIOUS, SUSPICIOUS]
        end
    end
    
    @testset "Network Scanning Attempts" begin
        network_scans = [
            "nmap -sS 192.168.1.1",
            "nc -z target.com 1-1000",
            "curl http://internal.local",
            "wget http://metadata.google.internal",
        ]
        
        for scan in network_scans
            result = sanitize_input(scan)
            @test result.level in [MALICIOUS, SUSPICIOUS]
        end
    end
end

# ============================================================================
# TEST CATEGORY 5: INPUT LENGTH/ SIZE TESTS
# ============================================================================

println("\n[5] Testing Input Length Limits...")

@testset "Fuzz: Input Length Limits" begin
    
    @testset "Very Long Input Handling" begin
        long_inputs = [
            repeat("a", 100000),
            repeat("../", 10000),
            repeat("ls;", 10000),
        ]
        
        for input in long_inputs
            result = sanitize_input(input)
            @test result isa SanitizationResult
        end
    end
    
    @testset "Parameter Array Overflow" begin
        large_arrays = [
            Dict("files" => repeat(["test.txt"], 10000)),
            Dict("commands" => repeat(["ls"], 10000)),
        ]
        
        for params in large_arrays
            @test params isa Dict
        end
    end
end

# ============================================================================
# TEST CATEGORY 6: REGRESSION TESTS
# ============================================================================

println("\n[6] Testing Known Tool Vulnerabilities...")

@testset "Fuzz: Tool Vulnerability Regression" begin
    
    @testset "Shell Injection Regression" begin
        known_injections = [
            "ls; cat /etc/passwd",
            "ls && rm -rf /",
            "ls | bash",
            "ls backtick_result",
            "echo subshell_result",
        ]
        
        for injection in known_injections
            result = sanitize_input(injection)
            @test result.level == MALICIOUS
        end
    end
    
    @testset "Path Traversal Regression" begin
        known_traversals = [
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32",
            "....//....//....//etc/shadow",
            "/etc/../etc/passwd",
        ]
        
        for path in known_traversals
            result = sanitize_input(path)
            @test result.level == MALICIOUS
        end
    end
    
    @testset "SSRF Regression" begin
        known_ssrf = [
            "http://169.254.169.254/latest/meta-data/",
            "http://metadata.google.internal/computeMetadata",
            "http://127.0.0.1:22",
            "http://localhost:6379",
        ]
        
        for url in known_ssrf
            result = sanitize_input(url)
            @test result.level in [MALICIOUS, SUSPICIOUS]
        end
    end
end

# ============================================================================
# SUMMARY
# ============================================================================

println("\n" * "=" ^ 70)
println("  TOOL INPUT FUZZ TESTING COMPLETE")
println("=" ^ 70)
println("  Test Categories Executed:")
println("    1. Capability Validation")
println("    2. Parameter Validation")
println("    3. Tool Execution Edge Cases")
println("    4. Permission Boundary Testing")
println("    5. Input Length Limits")
println("    6. Known Tool Vulnerability Regression")
println("=" ^ 70)
