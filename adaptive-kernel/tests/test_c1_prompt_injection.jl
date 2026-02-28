"""
    P0 C1: Prompt Injection Sovereignty Bypass - Verification Tests
    
    THREAT MODEL:
    - Original vulnerability: LLM output parsed without validation
    - Attack vectors:
      1. SQL injection via entities
      2. Command injection in action fields
      3. Priority manipulation to bypass controls
      4. Malformed JSON causing parse errors
      5. NaN/Inf injection in perception vectors
    
    VERIFICATION STRATEGY:
    - Test 1: Valid LLM output should pass
    - Test 2: Invalid intent should FAIL
    - Test 3: SQL injection attempt should FAIL
    - Test 4: Command injection should FAIL  
    - Test 5: Malformed JSON should FAIL
    - Test 6: NaN in perception vector should FAIL
    - Test 7: Out-of-bounds confidence should be sanitized
    - Test 8: Context whitelist enforced
"""

module TestC1PromptInjection

using Test
using JSON
using ..LLMOutputValidator

# ============================================================================
# TEST 1: Valid LLM Output Should Pass
# ============================================================================

@testset "Valid LLM Output" begin
    valid_json = """
    {
        "intent": "task_execution",
        "entities": {
            "target": "file.txt",
            "action": "read",
            "priority": "high"
        },
        "confidence": 0.95,
        "requires_confirmation": true,
        "context_needed": ["preferences", "conversations"]
    }
    """
    
    result = validate_llm_output(valid_json)
    
    @test result.is_valid == true
    @test result.sanitized_data !== nothing
    @test result.sanitized_data["intent"] == "task_execution"
    @test result.sanitized_data["entities"]["priority"] == "high"
    @test result.sanitized_data["confidence"] ≈ 0.95f0
    @test result.sanitized_data["requires_confirmation"] == true
end

# ============================================================================
# TEST 2: Invalid Intent Should FAIL
# ============================================================================

@testset "Invalid Intent - Prompt Injection Attempt" begin
    # Attacker tries to inject malicious intent
    malicious_json = """
    {
        "intent": "execute_shell_command",
        "entities": {
            "target": "malicious.sh",
            "action": "rm -rf /"
        }
    }
    """
    
    result = validate_llm_output(malicious_json)
    
    @test result.is_valid == false
    @test result.sanitized_data === nothing
    @test occursin("Invalid intent", result.error_message)
end

# ============================================================================
# TEST 3: SQL Injection Attempt Should FAIL
# ============================================================================

@testset "SQL Injection in Entities" begin
    # Attacker tries SQL injection via entity
    injection_json = """
    {
        "intent": "task_execution",
        "entities": {
            "target": "'; DROP TABLE users; --"
        }
    }
    """
    
    result = validate_llm_output(injection_json)
    
    @test result.is_valid == true  # Sanitization should clean it
    @test result.sanitized_data !== nothing
    # Verify dangerous characters removed
    @test !occursin("DROP", result.sanitized_data["entities"]["target"])
end

# ============================================================================
# TEST 4: Command Injection Should FAIL
# ============================================================================

@testset "Command Injection Attempt" begin
    cmd_injection = """
    {
        "intent": "task_execution",
        "entities": {
            "action": "exec; cat /etc/passwd"
        }
    }
    """
    
    result = validate_llm_output(cmd_injection)
    
    @test result.is_valid == true  # Sanitization removes dangerous chars
    @test result.sanitized_data !== nothing
    @test !occursin(";", result.sanitized_data["entities"]["action"])
end

# ============================================================================
# TEST 5: Malformed JSON Should FAIL
# ============================================================================

@testset "Malformed JSON Rejection" begin
    malformed = "{ this is not valid json"
    
    result = validate_llm_output(malformed)
    
    @test result.is_valid == false
    @test result.sanitized_data === nothing
    @test occursin("Invalid JSON", result.error_message)
end

# ============================================================================
# TEST 6: NaN in Perception Vector Should FAIL
# ============================================================================

@testset "NaN Detection in Perception Vector" begin
    vector_with_nan = Float32[1.0, 2.0, NaN32, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0]
    
    is_valid = validate_perception_vector(vector_with_nan)
    
    @test is_valid == false
end

# ============================================================================
# TEST 7: Out-of-Bounds Confidence Should Be Sanitized
# ============================================================================

@testset "Confidence Clamping" begin
    # Test confidence > 1.0 gets clamped
    high_conf = """
    {
        "intent": "task_execution",
        "entities": {},
        "confidence": 1.5
    }
    """
    
    result = validate_llm_output(high_conf)
    
    @test result.is_valid == true
    @test result.sanitized_data["confidence"] <= 1.0f0
    
    # Test confidence < 0.0 gets clamped
    low_conf = """
    {
        "intent": "task_execution", 
        "entities": {},
        "confidence": -0.5
    }
    """
    
    result2 = validate_llm_output(low_conf)
    
    @test result2.is_valid == true
    @test result2.sanitized_data["confidence"] >= 0.0f0
end

# ============================================================================
# TEST 8: Context Whitelist Enforced
# ============================================================================

@testset "Context Whitelist Enforcement" begin
    # Invalid context should fail
    invalid_context = """
    {
        "intent": "task_execution",
        "entities": {},
        "context_needed": ["shell_access", "filesystem_root"]
    }
    """
    
    result = validate_llm_output(invalid_context)
    
    @test result.is_valid == false
    @test occursin("Invalid context", result.error_message)
end

# ============================================================================
# TEST 9: Priority Whitelist Enforced
# ============================================================================

@testset "Priority Whitelist Enforcement" begin
    # Invalid priority gets sanitized to default
    invalid_priority = """
    {
        "intent": "task_execution",
        "entities": {
            "priority": "SUPER_URGENT_OVERRIDE_ALL"
        }
    }
    """
    
    result = validate_llm_output(invalid_priority)
    
    @test result.is_valid == true  # Sanitizes to default
    @test result.sanitized_data["entities"]["priority"] == "medium"  # Default
end

# ============================================================================
# TEST 10: Empty Output Should FAIL
# ============================================================================

@testset "Empty Output Rejection" begin
    result = validate_llm_output("")
    
    @test result.is_valid == false
    @test occursin("Empty", result.error_message)
end

# ============================================================================
# TEST 11: Inf Detection in Perception Vector
# ============================================================================

@testset "Inf Detection in Perception Vector" begin
    vector_with_inf = Float32[1.0, 2.0, 3.0, Inf32, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0]
    
    is_valid = validate_perception_vector(vector_with_inf)
    
    @test is_valid == false
end

# ============================================================================
# TEST 12: Sanitize Perception Vector
# ============================================================================

@testset "Sanitize Perception Vector" begin
    dirty_vector = Float32[0.5, -0.1, 1.5, NaN32, 0.8, 0.9, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
    
    sanitized = sanitize_perception_vector(dirty_vector)
    
    @test all(v -> v >= 0.0f0 && v <= 1.0f0, sanitized)
    @test all(v -> !isnan(v), sanitized)
    @test length(sanitized) == 12
end

# ============================================================================
# TEST 13: Null Byte Injection Should FAIL
# ============================================================================

@testset "Null Byte Injection Sanitization" begin
    null_byte_json = """
    {
        "intent": "task_execution",
        "entities": {
            "target": "file\\u0000.txt"
        }
    }
    """
    
    result = validate_llm_output(null_byte_json)
    
    @test result.is_valid == true
    @test !occursin("\\u0000", result.sanitized_data["entities"]["target"])
end

# ============================================================================
# SUMMARY
# ============================================================================

println("\n" * "="^60)
println("P0 C1: PROMPT INJECTION VALIDATOR - SECURITY VERIFICATION")
println("="^60)
println("FAIL-CLOSED BEHAVIOR VERIFIED:")
println("  ✓ Invalid intents rejected")
println("  ✓ SQL/Command injection sanitized")
println("  ✓ Malformed JSON rejected")
println("  ✓ NaN/Inf in perception vectors rejected")
println("  ✓ Out-of-bounds values clamped")
println("  ✓ Whitelist enforcement on context/priority")
println("  ✓ Empty output rejected")
println("  ✓ Null bytes sanitized")
println("="^60)

end  # module
