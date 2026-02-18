# adaptive-kernel/tests/integration_test.jl - Integration tests for PROJECT JARVIS
# Tests kernel sovereignty, brain advisory mode, and deterministic behavior

module IntegrationTests

using Test
using Dates
using UUIDs

# ============================================================================
# PHASE 1: KERNEL SOVEREIGNTY TESTS
# ============================================================================

println("Testing kernel sovereignty...")

# Import needed modules
include(joinpath(@__DIR__, "..", "kernel", "Kernel.jl"))
using .Kernel

# Initialize kernel
config = Dict(
    "goals" => [
        Dict("id" => "test", "description" => "Test goal", "priority" => 0.8)
    ],
    "observations" => Dict{String, Any}()
)

kernel = init_kernel(config)

# Create a capability candidate
candidate = Dict(
    "id" => "test_action",
    "risk" => "low",
    "cost" => 0.1,
    "confidence" => 0.8
)

# Test permission handler that denies everything
deny_all(risk::String) = false

# Execute function that should never be called if permission denied
execute_called = Ref(false)
execute_fn(action_id::String) = begin
    execute_called[] = true
    Dict{String, Any}("success" => true)
end

# Run step with permission denied
kernel, action, result = step_once(
    kernel, 
    [candidate], 
    execute_fn, 
    deny_all
)

# Verify action was NOT executed (execute_fn was not called)
@test execute_called[] == false
@test result["success"] == false
@test occursin("denied", result["effect"])

println("  ✓ Kernel veto blocks execution")

# ============================================================================
# PHASE 2: BRAIN REJECTION TEST
# ============================================================================

println("Testing brain suggestion rejection...")

config2 = Dict(
    "goals" => [
        Dict("id" => "default", "description" => "Default", "priority" => 0.5)
    ],
    "observations" => Dict{String, Any}()
)

kernel2 = init_kernel(config2)

# Create high-risk action candidate
high_risk_candidate = Dict(
    "id" => "dangerous_action",
    "risk" => "high",
    "cost" => 0.5,
    "confidence" => 0.9
)

# Permission handler that blocks high risk
block_high_risk(risk::String) = risk != "high"

execute_called2 = Ref(false)
execute_fn2(action_id::String) = begin
    execute_called2[] = true
    Dict{String, Any}("success" => true)
end

kernel2, action2, result2 = step_once(
    kernel2,
    [high_risk_candidate],
    execute_fn2,
    block_high_risk
)

# Verify execution was blocked
@test execute_called2[] == false
@test result2["success"] == false

println("  ✓ Brain suggestions can be rejected")

# ============================================================================
# PHASE 2: NO APPROVAL = NO EXECUTION TEST
# ============================================================================

println("Testing no approval = no execution...")

config3 = Dict(
    "goals" => [Dict("id" => "test", "description" => "Test", "priority" => 0.5)],
    "observations" => Dict{String, Any}()
)

kernel3 = init_kernel(config3)

# Empty candidates - no action proposed
execute_called3 = Ref(false)
execute_fn3(action_id::String) = begin
    execute_called3[] = true
    Dict{String, Any}("success" => true)
end

always_allow(risk::String) = true

# Even with permission to execute, if no candidates, nothing executes
kernel3, action3, result3 = step_once(
    kernel3,
    Dict{String, Any}[],
    execute_fn3,
    always_allow
)

# No action was selected
@test action3.capability_id == "none"

println("  ✓ No capability executes without approval")

# ============================================================================
# PHASE 4: DETERMINISTIC MEMORY TESTS
# ============================================================================

println("Testing deterministic embeddings...")

include(joinpath(@__DIR__, "..", "..", "jarvis", "src", "memory", "VectorMemory.jl"))
using .VectorMemory

test_text = "Hello, this is a test string for embedding"

# Generate embedding twice
embedding1 = generate_embedding(test_text)
embedding2 = generate_embedding(test_text)

# Verify they are identical
@test embedding1 == embedding2

# Verify cosine similarity is 1.0 (identical)
similarity = cosine_similarity(embedding1, embedding2)
@test similarity ≈ 1.0f0

# Test different text produces different embedding
different_text = "Completely different text"
embedding3 = generate_embedding(different_text)

# Verify different text produces different embedding
@test embedding1 != embedding3

# Verify similarity is not 1.0 (different texts)
similarity_diff = cosine_similarity(embedding1, embedding3)
@test similarity_diff < 1.0f0

# Verify no NaN in similarity
@test !isnan(similarity)
@test !isnan(similarity_diff)

println("  ✓ Embeddings are deterministic")

# ============================================================================
# PHASE 4: NO NAN SIMILARITY TEST
# ============================================================================

println("Testing no NaN in cosine similarity...")

# Test with zero vector
zero_vec = Float32[0.0, 0.0, 0.0]
non_zero = Float32[1.0, 0.0, 0.0]

sim = cosine_similarity(zero_vec, non_zero)
@test !isnan(sim)
@test sim >= -1.0f0 && sim <= 1.0f0

# Test with two zero vectors
sim2 = cosine_similarity(zero_vec, zero_vec)
@test !isnan(sim2)

# Test with normal vectors
vec1 = Float32[1.0, 2.0, 3.0]
vec2 = Float32[4.0, 5.0, 6.0]
sim3 = cosine_similarity(vec1, vec2)
@test !isnan(sim3)
@test sim3 >= -1.0f0 && sim3 <= 1.0f0

println("  ✓ Cosine similarity never returns NaN")

# ============================================================================
# PHASE 3: SECURITY TESTS - HTTP WHITELIST BYPASS
# ============================================================================

println("Testing HTTP whitelist bypass prevention...")

include(joinpath(@__DIR__, "..", "capabilities", "safe_http_request.jl"))
using .SafeHTTPRequest

# These should be denied (subdomain bypass attempts)
@test is_url_allowed("https://example.com.evil.com")[1] == false
@test is_url_allowed("https://api.example.com.malicious.com")[1] == false
@test is_url_allowed("https://example.com%00.attacker.com")[1] == false

# These should be allowed (exact matches)
@test is_url_allowed("https://example.com")[1] == true
@test is_url_allowed("https://api.github.com")[1] == true

# IP addresses should be denied
@test is_url_allowed("https://192.168.1.1")[1] == false
@test is_url_allowed("https://127.0.0.1")[1] == false

# Localhost should be denied
@test is_url_allowed("http://localhost")[1] == false

println("  ✓ HTTP whitelist prevents subdomain bypass")

# ============================================================================
# PHASE 3: SECURITY TESTS - SHELL SANITIZATION
# ============================================================================

println("Testing shell command sanitization...")

include(joinpath(@__DIR__, "..", "capabilities", "safe_shell.jl"))
using .SafeShell

# These should be blocked (injection attempts)
result = SafeShell.execute(Dict("command" => "ls; rm -rf /"))
@test result["success"] == false
@test result["data"]["reason"] == "Shell metacharacters detected"

result = SafeShell.execute(Dict("command" => "ls | cat /etc/passwd"))
@test result["success"] == false

result = SafeShell.execute(Dict("command" => "echo \$(whoami)"))
@test result["success"] == false

# These should work (whitelisted commands)
result = SafeShell.execute(Dict("command" => "echo hello"))
@test result["success"] == true

result = SafeShell.execute(Dict("command" => "ls"))
@test result["success"] == true

println("  ✓ Shell commands are sanitized")

# ============================================================================
# PHASE 3: SECURITY TESTS - CURL FLAG INJECTION
# ============================================================================

println("Testing curl flag injection prevention...")

# These should be blocked (curl flag injection)
@test parse_url_strictly("https://example.com -O malicious.exe")[1] === nothing
@test parse_url_strictly("https://example.com --data 'malicious'")[1] === nothing
@test parse_url_strictly("https://example.com -u user:pass")[1] === nothing
@test parse_url_strictly("https://example.com -H 'Authorization: Bearer token'")[1] === nothing
@test parse_url_strictly("https://example.com -X POST")[1] === nothing

println("  ✓ Curl flag injection is prevented")

# ============================================================================
# PHASE 3: SECURITY TESTS - SHELL BLOCKED PATTERNS
# ============================================================================

println("Testing additional shell blocking patterns...")

# These should be blocked (new patterns)
result = SafeShell.execute(Dict("command" => "ls -la /etc"))
@test result["success"] == false  # Flag injection blocked

result = SafeShell.execute(Dict("command" => "ls /etc/passwd"))
@test result["success"] == false  # Path traversal blocked

result = SafeShell.execute(Dict("command" => "echo hello\nworld"))
@test result["success"] == false  # Newline injection blocked

result = SafeShell.execute(Dict("command" => "ls *"))
@test result["success"] == false  # Globbing blocked

# Find command should be blocked (removed from whitelist)
result = SafeShell.execute(Dict("command" => "find . -name '*.txt'"))
@test result["success"] == false

println("  ✓ Additional shell blocking patterns work")

# ============================================================================
# SUMMARY
# ============================================================================

println("\n" * "="^60)
println("  ALL TESTS PASSED")
println("="^60)

end  # module
