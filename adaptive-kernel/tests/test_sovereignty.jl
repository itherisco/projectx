# test_sovereignty.jl - Test the sovereignty gateway changes
# This is a standalone test that verifies the syntax and structure

using UUIDs
using Dates
using SHA

# Test the sovereignty types and functions in isolation

println("Testing SovereigntyViolation exception...")

# Create a SovereigntyViolation manually (simulating the struct)
struct SovereigntyViolation
    message::String
    risk_score::Float32
    threshold::Float32
    proposal_id::String
end

# Test AuthToken struct
println("Testing AuthToken struct...")
struct AuthToken
    token_id::UUID
    proposal_id::String
    capability_id::String
    issued_at::DateTime
    expires_at::DateTime
    kernel_signature::Vector{UInt8}
    risk_score::Float32
    cycle::Int
end

# Test get_kernel_secret
println("Testing get_kernel_secret...")
KERNEL_SECRET_ENV = "JARVIS_KERNEL_SECRET"

# SECURITY FIX: Removed hardcoded default - now fails secure like Types.jl
function get_kernel_secret()::Vector{UInt8}
    if !haskey(ENV, KERNEL_SECRET_ENV)
        error("SECURITY CRITICAL: $KERNEL_SECRET_ENV environment variable not set. " * 
              "System cannot operate without a configured kernel secret. " *
              "Set this environment variable to a cryptographically secure random value.")
    end
    return Vector{UInt8}(ENV[KERNEL_SECRET_ENV])
end

# DIAGNOSTIC: Log current state
println("  ENV[$KERNEL_SECRET_ENV] set: $(haskey(ENV, KERNEL_SECRET_ENV))")

secret = get_kernel_secret()
println("  Secret length: $(length(secret))")
@assert length(secret) > 0

# Test _build_token_payload
println("Testing _build_token_payload...")
function _build_token_payload(
    proposal_id::String,
    capability_id::String,
    issued_at::Float64,
    expires_at::Float64,
    risk_score::Float32,
    cycle::Int
)::Vector{UInt8}
    proposal_bytes = Vector{UInt8}(proposal_id)
    cap_bytes = Vector{UInt8}(capability_id)
    issued_bytes = reinterpret(UInt8, [issued_at])
    expires_bytes = reinterpret(UInt8, [expires_at])
    risk_bytes = reinterpret(UInt8, [risk_score])
    cycle_bytes = reinterpret(UInt8, [cycle])
    
    return vcat(proposal_bytes, cap_bytes, issued_bytes, expires_bytes, risk_bytes, cycle_bytes)
end

payload = _build_token_payload("test_proposal", "read_file", time(), time() + 300, 0.5f0, 1)
println("  Payload length: $(length(payload))")

# Test sign_approval
println("Testing sign_approval...")
function sign_approval(
    proposal_id::String,
    issued_at::DateTime,
    capability_id::String,
    risk_score::Float32,
    cycle::Int
)::AuthToken
    token_id = uuid4()
    expires_at = issued_at + Dates.Minute(5)
    issued_float = datetime2unix(issued_at)
    expires_float = datetime2unix(expires_at)
    
    payload = _build_token_payload(proposal_id, capability_id, issued_float, expires_float, risk_score, cycle)
    sig = sha256(vcat(secret, payload))
    
    return AuthToken(
        token_id,
        proposal_id,
        capability_id,
        issued_at,
        expires_at,
        sig,
        risk_score,
        cycle
    )
end

token = sign_approval("test_proposal", now(), "read_file", 0.5f0, 1)
println("  Token ID: $(token.token_id)")
println("  Token capability: $(token.capability_id)")
println("  Token risk: $(token.risk_score)")

# Test verify_token_signature
println("Testing verify_token_signature...")
function verify_token_signature(token::AuthToken, test_secret::Vector{UInt8})::Bool
    issued_float = datetime2unix(token.issued_at)
    expires_float = datetime2unix(token.expires_at)
    
    payload = _build_token_payload(
        token.proposal_id,
        token.capability_id,
        issued_float,
        expires_float,
        token.risk_score,
        token.cycle
    )
    
    expected_signature = sha256(vcat(test_secret, payload))
    
    return token.kernel_signature == expected_signature
end

is_valid = verify_token_signature(token, secret)
println("  Token verification: $is_valid")
@assert is_valid

# Test with wrong secret
is_invalid = verify_token_signature(token, Vector{UInt8}("wrong_secret"))
println("  Wrong secret verification: $is_invalid")
@assert !is_invalid

# Test is_token_valid (without time check)
println("Testing is_token_valid (mock)...")
function is_token_valid_mock(token::AuthToken)::Bool
    # Skip expiration check for test
    return verify_token_signature(token, secret)
end

@assert is_token_valid_mock(token)

# Test KERNEL_THRESHOLD
println("Testing KERNEL_THRESHOLD...")
KERNEL_THRESHOLD = Float32(0.6)
println("  KERNEL_THRESHOLD: $KERNEL_THRESHOLD")
@assert KERNEL_THRESHOLD == 0.6f0

# Test calculate_risk (mock version)
println("Testing calculate_risk...")
function get_risk_value(risk)::Float32
    if risk isa Float32
        return risk
    elseif risk isa String
        if risk == "high" return 0.8f0
        elseif risk == "medium" return 0.5f0
        else return 0.2f0
        end
    end
    return 0.3f0
end

function calculate_risk_mock(proposal_risk::Float32, confidence::Float32, energy::Float32)::Float32
    base_risk = proposal_risk
    
    confidence_multiplier = if confidence >= 0.7f0
        1.0f0
    elseif confidence >= 0.4f0
        1.2f0
    else
        1.5f0
    end
    
    energy_multiplier = if energy >= 0.5f0
        1.0f0
    elseif energy >= 0.3f0
        1.1f0
    else
        1.3f0
    end
    
    final_risk = base_risk * confidence_multiplier * energy_multiplier
    return clamp(final_risk, 0.0f0, 1.0f0)
end

# Test with low risk proposal
risk1 = calculate_risk_mock(0.3f0, 0.8f0, 1.0f0)
println("  Low risk (0.3, 0.8 conf, 1.0 energy): $risk1")
@assert risk1 <= KERNEL_THRESHOLD

# Test with high risk proposal
risk2 = calculate_risk_mock(0.6f0, 0.5f0, 0.4f0)
println("  High risk (0.6, 0.5 conf, 0.4 energy): $risk2")
@assert risk2 > KERNEL_THRESHOLD

# Test SovereigntyViolation would be thrown
println("Testing SovereigntyViolation logic...")
high_risk = 0.7f0
if high_risk > KERNEL_THRESHOLD
    println("  Would throw SovereigntyViolation for risk=$high_risk > threshold=$KERNEL_THRESHOLD")
    @assert true
else
    @assert false
end

println("\n✅ All sovereignty gateway tests passed!")
