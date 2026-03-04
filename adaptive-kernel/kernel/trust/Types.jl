"""
    TrustTypes - Core types for the Trust module
"""
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL
@enum TrustLevel TRUST_NONE TRUST_RESTRICTED TRUST_LIMITED TRUST_STANDARD TRUST_FULL

# SHA import for HMAC verification
using SHA

"""
    SecureTrustLevel - HMAC-verified trust level wrapper

Provides cryptographic integrity protection for trust state to prevent
manipulation attacks (CWE-639: Authorization Bypass Through User-Controlled Key).
"""
struct SecureTrustLevel
    level::TrustLevel
    hmac::Vector{UInt8}
    timestamp::Float64
end

# Environment variable for trust secret
const _TRUST_SECRET_ENV = "JARVIS_TRUST_SECRET"

"""
    get_trust_secret()::Vector{UInt8}
Get the HMAC secret key for trust verification.
SECURITY: Throws an error if not configured - fail secure
"""
function get_trust_secret()::Vector{UInt8}
    if !haskey(ENV, _TRUST_SECRET_ENV)
        error("SECURITY CRITICAL: JARVIS_TRUST_SECRET environment variable not set. " *
              "System cannot operate without a configured trust secret. " *
              "Set this environment variable to a cryptographically secure random value.")
    end
    return Vector{UInt8}(ENV[_TRUST_SECRET_ENV])
end

"""
    trust_secret_is_set()::Bool
Check if JARVIS_TRUST_SECRET environment variable has been set.
"""
function trust_secret_is_set()::Bool
    return haskey(ENV, _TRUST_SECRET_ENV)
end

"""
    _build_payload(level::TrustLevel, timestamp::Float64)::Vector{UInt8}
Build the payload for HMAC computation.
"""
function _build_payload(level::TrustLevel, timestamp::Float64)::Vector{UInt8}
    level_byte = UInt8(Int(level))
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    return vcat(level_byte, timestamp_bytes)
end

"""
    SecureTrustLevel(level::TrustLevel, secret_key::Vector{UInt8})
Create a new secure trust level with HMAC verification.
"""
function SecureTrustLevel(level::TrustLevel, secret_key::Vector{UInt8})
    timestamp = time()
    payload = _build_payload(level, timestamp)
    hmac = sha256(secret_key * payload)
    return SecureTrustLevel(level, hmac, timestamp)
end

"""
    verify_trust(secure::SecureTrustLevel, secret_key::Vector{UInt8})::Bool
Verify the HMAC of a secure trust level.
"""
function verify_trust(secure::SecureTrustLevel, secret_key::Vector{UInt8})::Bool
    payload = _build_payload(secure.level, secure.timestamp)
    expected_hmac = sha256(secret_key * payload)
    return secure.hmac == expected_hmac
end

"""
    verify_trust(secure::SecureTrustLevel)::Bool
Verify using the default trust secret.
"""
function verify_trust(secure::SecureTrustLevel)::Bool
    return verify_trust(secure, get_trust_secret())
end

"""
    create_secure_trust(level::TrustLevel)::SecureTrustLevel
Create a new secure trust level using the default secret.
"""
function create_secure_trust(level::TrustLevel)::SecureTrustLevel
    return SecureTrustLevel(level, get_trust_secret())
end

"""
    Base.get(secure::SecureTrustLevel)::TrustLevel
Extract the underlying trust level (does NOT verify - caller must verify first!).
"""
function Base.get(secure::SecureTrustLevel)::TrustLevel
    return secure.level
end
