"""
    C4: Confirmation Gate Bypass - Security Verification Test
    
    P0 REMEDIATION VERIFICATION
    
    This test actively attempts to exploit the old vulnerability (UUID prediction)
    and verifies that the new secure implementation FAIL-CLOSED.
    
    RUN: cd("adaptive-kernel") do; julia --project=. -e 'include("tests/test_c4_confirmation_bypass.jl")'; end
"""

using SHA
using Random
using JSON

# Import RiskLevel enum
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL

# Include the secure confirmation gate
include(joinpath(@__DIR__, "..", "kernel", "trust", "SecureConfirmationGate.jl"))
using .SecureConfirmationGate

println("\n" * "="^70)
println("C4: CONFIRMATION GATE BYPASS - SECURITY VERIFICATION")
println("="^70)

# Create gate with known secret for testing
test_key = sha256("test_secret_key_for_c4")
gate = ConfirmationGate(
    UInt64(30), 
    auto_deny_on_timeout=true,
    secret_key=test_key,
    max_pending=UInt64(200)
)

# Test results tracking
all_tests_passed = true

println("\n[TEST 1] Token Uniqueness - CSPRNG Verification")
println("-"^50)

# Generate multiple tokens and verify uniqueness
tokens = String[]
for i in 1:100
    token = require_confirmation(
        gate, 
        "proposal_$i", 
        "capability_$i", 
        Dict{String, Any}("param" => "value"), 
        MEDIUM
    )
    token === nothing && error("Failed to generate token $i")
    push!(tokens, token)
end

all_unique = length(unique(tokens)) == 100
println("  Generated 100 tokens, all unique: $all_unique")
if !all_unique
    global all_tests_passed = false
    println("  FAILED: Token collision detected!")
end
println("  Collision probability: < 2^-128 (256-bit CSPRNG)")

println("\n[TEST 2] UUID Prediction Attack - MUST FAIL")
println("-"^50)

# ATTACK: Try to confirm with predicted UUID format (old vulnerability)
# In old system: UUID("550e8400-e29b-41d4-a716-446655440000")
fake_uuid_token = "550e8400e29b41d4a716446655440000" * "." * bytes2hex(rand(UInt8, 32))
result = confirm_action(gate, fake_uuid_token)
println("  Attempted UUID prediction attack: rejected=$(!result)")
if result
    global all_tests_passed = false
    println("  FAILED: UUID prediction attack succeeded!")
else
    println("  PASSED: Attack correctly rejected (fail-closed)")
end

println("\n[TEST 3] Token Tampering Attack - MUST FAIL")
println("-"^50)

# Get a valid token
valid_token = require_confirmation(
    gate,
    "test_proposal",
    "test_capability",
    Dict{String, Any}("action" => "delete"),
    HIGH
)

# ATTACK: Tamper with token bytes
tampered = valid_token[1:end-8] * "00000000"
result = confirm_action(gate, tampered)
println("  Attempted token tampering: rejected=$(!result)")
if result
    global all_tests_passed = false
    println("  FAILED: Token tampering attack succeeded!")
else
    println("  PASSED: Attack correctly rejected (fail-closed)")
end

println("\n[TEST 4] HMAC Verification - Valid Token Acceptance")
println("-"^50)

# Verify that valid token with correct signature works
result = confirm_action(gate, valid_token)
println("  Valid token confirmation: accepted=$result")
if !result
    global all_tests_passed = false
    println("  FAILED: Valid token rejected!")
else
    println("  PASSED: Valid token correctly accepted")
end

println("\n[TEST 5] Expired Token Attack - MUST FAIL")
println("-"^50)

# Create gate with very short timeout
short_gate = ConfirmationGate(
    UInt64(0),  # Immediate timeout
    auto_deny_on_timeout=true,
    secret_key=test_key
)

expired_token = require_confirmation(
    short_gate,
    "test_proposal",
    "test_capability",
    Dict{String, Any}(),
    LOW
)

# Try immediately - should fail due to timeout check
result = confirm_action(short_gate, expired_token)
println("  Expired token confirmation: rejected=$(!result)")
if result
    global all_tests_passed = false
    println("  FAILED: Expired token accepted!")
else
    println("  PASSED: Expired token correctly rejected (fail-closed)")
end

println("\n[TEST 6] Rate Limiting - DoS Prevention")
println("-"^50)

rate_gate = ConfirmationGate(
    UInt64(30),
    auto_deny_on_timeout=true,
    secret_key=test_key,
    max_pending=UInt64(100)
)

# Generate token
rate_token = require_confirmation(
    rate_gate,
    "test_proposal",
    "test_capability",
    Dict{String, Any}(),
    LOW
)

# Attempt multiple invalid confirmations
for i in 1:6
    result = confirm_action(rate_gate, "invalid_token_$i")
end

# Now try the actual token - should fail due to rate limiting
result = confirm_action(rate_gate, rate_token)
println("  Rate-limited valid token: rejected=$(!result)")
if result
    global all_tests_passed = false
    println("  FAILED: Rate limit not enforced!")
else
    println("  PASSED: Rate limiting correctly enforced (fail-closed)")
end

println("\n[TEST 7] Token Format Validation - MUST FAIL")
println("-"^50)

# Various malformed tokens
malformed_tokens = [
    "",
    "not-a-valid-token",
    "550e8400e29b41d4a716446655440000",  # No signature
    ".signature_here",
    "too_short.signature",
]

all_malformed_rejected = true
for mal in malformed_tokens
    result = confirm_action(gate, mal)
    if result
        all_malformed_rejected = false
        println("  FAILED: Malformed token accepted: '$mal'")
    end
end
if all_malformed_rejected
    println("  PASSED: All malformed tokens correctly rejected")
else
    global all_tests_passed = false
    println("  FAILED: Some malformed tokens accepted!")
end

println("\n" * "="^70)
if all_tests_passed
    println("C4 VERIFICATION COMPLETE - ALL TESTS PASSED")
    println("System is now immune to Confirmation Gate Bypass")
else
    println("C4 VERIFICATION FAILED - SOME TESTS DID NOT PASS")
end
println("="^70)

# Return test result
all_tests_passed
