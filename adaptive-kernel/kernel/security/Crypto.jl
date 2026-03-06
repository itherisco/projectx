# Crypto.jl - Production-grade Cryptographic Operations
# ======================================================
# Provides cryptographic signing, verification, and key rotation
# for ITHERIS cognitive system security.
#
# Requirements:
# - HMAC-SHA256 signed action tokens
# - Constant-time signature verification (prevent timing attacks)
# - Key rotation support (every 24 hours)
# - Audit logging of all signature verifications

module Crypto

using SHA
using Random
using Dates
using JSON3

export 
    ActionToken,
    sign_action,
    verify_token,
    constant_time_compare,
    rotate_keys!,
    CryptoKey,
    AuditLog,
    generate_secret_key

# ============================================================================
# Type Definitions
# ============================================================================

"""
    Action - An action to be signed and executed
"""
struct Action
    action_type::String
    target::String
    parameters::Dict{String, Any}
    timestamp::DateTime
end

"""
    ActionToken - Cryptographically signed action token
    
    Fields:
    - action: The action being signed
    - timestamp: When the token was created
    - nonce: Random bytes for uniqueness
    - signature: HMAC-SHA256 signature
"""
struct ActionToken
    action::Action
    timestamp::DateTime
    nonce::Vector{UInt8}
    signature::Vector{UInt8}
end

"""
    CryptoKey - Secret key for signing
    
    Fields:
    - key: The secret key bytes
    - created_at: When the key was created
    - rotated_at: Last rotation time
    - key_id: Unique identifier for this key version
"""
mutable struct CryptoKey
    key::Vector{UInt8}
    created_at::DateTime
    rotated_at::Union{DateTime, Nothing}
    key_id::String
    version::Int
end

"""
    AuditLog - Record of all cryptographic operations
"""
struct AuditLog
    timestamp::DateTime
    operation::Symbol  # :sign, :verify
    key_id::String
    success::Bool
    details::String
end

# ============================================================================
# Global State
# ============================================================================

# Current active key
const _current_key = Ref{Union{CryptoKey, Nothing}}(nothing)

# Archived keys for verification of old tokens
const _key_archive = Vector{CryptoKey}()

# Audit log buffer
const _audit_log = Vector{AuditLog}()

# Configuration
const KEY_ROTATION_PERIOD_HOURS = 24
const AUDIT_LOG_MAX_ENTRIES = 10000

# ============================================================================
# Key Generation
# ============================================================================

"""
    Generate a random secret key
    
    Arguments:
    - length::Int - Key length in bytes (default: 32 for HMAC-SHA256)
    
    Returns: Vector{UInt8} - Random key bytes
"""
function generate_secret_key(length::Int=32)::Vector{UInt8}
    key = Vector{UInt8}(undef, length)
    rand!(key)
    key
end

"""
    Initialize the crypto system with a new key
"""
function init_crypto(key::Vector{UInt8})::CryptoKey
    now = DateTime(now())
    crypto_key = CryptoKey(
        key,
        now,
        nothing,
        string(uuid4()),
        1
    )
    _current_key[] = crypto_key
    println("[Crypto] Initialized with key_id: $(crypto_key.key_id)")
    crypto_key
end

"""
    Generate a new UUID (simple implementation)
"""
function uuid4()::UUID
    # Simple UUID v4 generation
    bytes = Vector{UInt8}(undef, 16)
    rand!(bytes)
    bytes[7] = (bytes[7] & 0x0f) | 0x40  # Version 4
    bytes[9] = (bytes[9] & 0x3f) | 0x80  # Variant 10
    
    UUID(bytes)
end

"""
    UUID type for key identification
"""
struct UUID
    bytes::Vector{UInt8}
end

function Base.string(u::UUID)::String
    join([string(b, base=16, pad=2) for b in u.bytes], "-")
end

# ============================================================================
# Core Cryptographic Operations
# ============================================================================

"""
    Compute HMAC-SHA256
    
    Arguments:
    - key::Vector{UInt8} - Secret key
    - message::Vector{UInt8} - Message to authenticate
    
    Returns: Vector{UInt8} - 32-byte HMAC-SHA256 signature
"""
function hmac_sha256(key::Vector{UInt8}, message::Vector{UInt8})::Vector{UInt8}
    # HMAC-SHA256 implementation
    block_size = 64
    
    if length(key) > block_size
        key = sha256(key)
    end
    
    # Pad key to block size
    if length(key) < block_size
        key = vcat(key, zeros(UInt8, block_size - length(key)))
    end
    
    # Inner and outer keys
    o_key_pad = xor.(key, fill(0x5c, block_size))
    i_key_pad = xor.(key, fill(0x36, block_size))
    
    # Inner hash
    inner = sha256(vcat(i_key_pad, message))
    
    # Outer hash
    signature = sha256(vcat(o_key_pad, inner))
    
    signature
end

"""
    constant_time_compare(a::Vector{UInt8}, b::Vector{UInt8})::Bool

Constant-time comparison resistant to timing attacks.
Uses fixed-iteration approach regardless of input differences.

# Security Properties
- Always iterates through max(length(a), length(b)) bytes
- No early returns based on content or length
- Accumulates differences in single variable
- Prevents timing-based information leakage

# Reference
- https://codahale.com/a-lesson-in-timing-attacks/
- OWASP: https://owasp.org/www-community/vulnerabilities/Timing_attack
"""
function constant_time_compare(a::Vector{UInt8}, b::Vector{UInt8})::Bool
    # Determine maximum length (don't leak which is longer)
    len_a = length(a)
    len_b = length(b)
    max_len = max(len_a, len_b)
    
    # Accumulator for differences (0 = equal, non-zero = different)
    diff = UInt8(0)
    
    # Length difference contributes to diff
    diff |= UInt8(len_a ⊻ len_b)
    
    # Always iterate through max_len (constant time)
    for i in 1:max_len
        # Safe indexing - use 0x00 for out-of-bounds
        byte_a = i <= len_a ? a[i] : 0x00
        byte_b = i <= len_b ? b[i] : 0x00
        
        # XOR accumulates differences
        diff |= byte_a ⊻ byte_b
    end
    
    # Return true only if no differences found
    return diff == 0x00
end

"""
    Constant-time string comparison
"""
function constant_time_compare(a::String, b::String)::Bool
    constant_time_compare(Vector{UInt8}(a), Vector{UInt8}(b))
end

# ============================================================================
# Action Token Operations
# ============================================================================

"""
    Sign an action with a secret key
    
    Arguments:
    - action::Action - The action to sign
    - secret_key::Vector{UInt8} - The secret key
    
    Returns: ActionToken - Signed token
"""
function sign_action(action::Action, secret_key::Vector{UInt8})::ActionToken
    # Generate random nonce
    nonce = Vector{UInt8}(undef, 16)
    rand!(nonce)
    
    # Create timestamp
    timestamp = DateTime(now())
    
    # Serialize action + timestamp + nonce
    message = serialize_for_signing(action, timestamp, nonce)
    
    # Compute HMAC-SHA256 signature
    signature = hmac_sha256(secret_key, message)
    
    ActionToken(action, timestamp, nonce, signature)
end

"""
    Serialize action for signing
    
    Returns: Vector{UInt8}
"""
function serialize_for_signing(action::Action, timestamp::DateTime, nonce::Vector{UInt8})::Vector{UInt8}
    # Create message = serialize(action) || timestamp || nonce
    action_json = JSON3.write(Dict(
        "action_type" => action.action_type,
        "target" => action.target,
        "parameters" => action.parameters
    ))
    
    timestamp_bytes = reinterpret(UInt8, [round(Int64, Dates.datetime2unix(timestamp) * 1000)])
    
    vcat(Vector{UInt8}(action_json), timestamp_bytes, nonce)
end

"""
    Verify an action token
    
    Arguments:
    - token::ActionToken - The token to verify
    - secret_key::Vector{UInt8} - The secret key
    
    Returns: Bool - true if signature is valid
"""
function verify_token(token::ActionToken, secret_key::Vector{UInt8})::Bool
    # Record verification attempt for audit
    key_id = _current_key[] !== nothing ? _current_key[].key_id : "unknown"
    
    try
        # Recompute signature
        message = serialize_for_signing(token.action, token.timestamp, token.nonce)
        expected_signature = hmac_sha256(secret_key, message)
        
        # Use constant-time comparison to prevent timing attacks
        result = constant_time_compare(token.signature, expected_signature)
        
        # Log verification result
        log_audit!(
            :verify,
            key_id,
            result,
            result ? "Token verified successfully" : "Signature mismatch"
        )
        
        result
    catch e
        # Log error
        log_audit!(
            :verify,
            key_id,
            false,
            "Verification error: $e"
        )
        false
    end
end

"""
    Verify token with key rotation support
    
    Tries current key first, then archived keys
"""
function verify_token_with_rotation(token::ActionToken)::Bool
    # Try current key
    if _current_key[] !== nothing
        if verify_token(token, _current_key[].key)
            return true
        end
    end
    
    # Try archived keys
    for archived_key in _key_archive
        if verify_token(token, archived_key.key)
            return true
        end
    end
    
    false
end

# ============================================================================
# Key Rotation
# ============================================================================

"""
    Check if key rotation is needed
"""
function needs_rotation()::Bool
    if _current_key[] === nothing
        return true
    end
    
    key = _current_key[]
    hours_since_creation = (now() - key.created_at) / Millisecond(3600000)
    
    hours_since_creation >= KEY_ROTATION_PERIOD_HOURS
end

"""
    Rotate keys - generate new key and archive old one
    
    Arguments:
    - kernel - The kernel (for pending action re-signing)
    
    Returns: CryptoKey - The new key
"""
function rotate_keys!(kernel::Any=nothing)::CryptoKey
    now = DateTime(now())
    
    # Archive current key if exists
    if _current_key[] !== nothing
        current = _current_key[]
        current.rotated_at = now
        push!(_key_archive, current)
        
        println("[Crypto] Archived key: $(current.key_id) (version $(current.version))")
    end
    
    # Generate new key
    new_key = generate_secret_key(32)
    
    # Create new CryptoKey
    rotated = CryptoKey(
        new_key,
        now,
        nothing,
        string(uuid4()),
        _current_key[] === nothing ? 1 : _current_key[].version + 1
    )
    
    _current_key[] = rotated
    
    # Re-sign pending actions if kernel provided
    # (This would be integrated with the actual kernel)
    # if kernel !== nothing
    #     # Re-sign pending actions with new key
    # end
    
    println("[Crypto] Rotated to new key: $(rotated.key_id) (version $(rotated.version))")
    
    # Log rotation
    log_audit!(
        :rotate,
        rotated.key_id,
        true,
        "Key rotated from version $(rotated.version - 1) to $(rotated.version)"
    )
    
    rotated
end

"""
    Get current key (if initialized)
"""
function get_current_key()::Union{CryptoKey, Nothing}
    _current_key[]
end

# ============================================================================
# Audit Logging
# ============================================================================

"""
    Log an audit entry
"""
function log_audit!(operation::Symbol, key_id::String, success::Bool, details::String)::Nothing
    entry = AuditLog(
        DateTime(now()),
        operation,
        key_id,
        success,
        details
    )
    
    push!(_audit_log, entry)
    
    # Trim log if too large
    if length(_audit_log) > AUDIT_LOG_MAX_ENTRIES
        deleteat!(_audit_log, 1:length(_audit_log) - AUDIT_LOG_MAX_ENTRIES)
    end
    
    # Also print for immediate visibility
    status = success ? "✓" : "✗"
    println("[Crypto Audit] $status $operation key=$key_id: $details")
    
    nothing
end

"""
    Get recent audit log entries
"""
function get_audit_log(; limit::Int=100)::Vector{AuditLog}
    if limit >= length(_audit_log)
        return copy(_audit_log)
    else
        return _audit_log[end-limit+1:end]
    end
end

"""
    Export audit log to JSON
"""
function export_audit_log(path::String)::Nothing
    log_data = [
        Dict(
            "timestamp" => string(e.timestamp),
            "operation" => string(e.operation),
            "key_id" => e.key_id,
            "success" => e.success,
            "details" => e.details
        )
        for e in _audit_log
    ]
    
    open(path, "w") do f
        JSON3.write(f, log_data)
    end
    
    println("[Crypto] Exported audit log to: $path")
    nothing
end

# ============================================================================
# Rate Limiting
# ============================================================================

"""
RateLimiter - Token bucket rate limiter
"""
struct RateLimiter
    max_rate::Float64  # Max requests per second
    tokens::Ref{Float64}
    last_check::Ref{Float64}
    lock::ReentrantLock
end

const _rate_limiters = Dict{String, RateLimiter}()

"""
    check_rate_limit(key::String, max_rate::Float64)::Bool

Check if request is within rate limit. Uses token bucket algorithm.
"""
function check_rate_limit(key::String, max_rate::Float64)::Bool
    if !haskey(_rate_limiters, key)
        _rate_limiters[key] = RateLimiter(max_rate, Ref(max_rate), Ref(time()), ReentrantLock())
    end
    
    limiter = _rate_limiters[key]
    
    lock(limiter.lock) do
        current_time = time()
        elapsed = current_time - limiter.last_check[]
        
        # Refill tokens based on elapsed time
        limiter.tokens[] = min(limiter.max_rate, 
                              limiter.tokens[] + elapsed * limiter.max_rate)
        limiter.last_check[] = current_time
        
        # Check if we have tokens available
        if limiter.tokens[] >= 1.0
            limiter.tokens[] -= 1.0
            return true
        else
            return false
        end
    end
end

"""
    verify_token_safe(token::ActionToken, secret_key::Vector{UInt8})::Bool

Wrapper around verify_token with additional protections:
- Rate limiting to prevent brute force
- Timing jitter to obscure internal operations
- Audit logging of all verification attempts
"""
function verify_token_safe(token::ActionToken, secret_key::Vector{UInt8})::Bool
    # Rate limiting: max 100 verifications per second
    if !check_rate_limit("token_verification", 100.0)
        @warn "Token verification rate limit exceeded"
        log_audit!(:verify, "rate_limit", false, "Rate limit exceeded")
        sleep(rand() * 0.1)  # Random delay on rate limit
        return false
    end
    
    # Add random timing jitter (1-5ms) to obscure internal timing
    jitter_start = rand(1:5) * 0.001
    sleep(jitter_start)
    
    # Actual verification
    result = verify_token(token, secret_key)
    
    # Audit log
    log_audit!(result ? :verify : :verify, 
              _current_key[] !== nothing ? _current_key[].key_id : "unknown",
              result, 
              result ? "Safe verify success" : "Safe verify failure")
    
    # Add ending jitter
    jitter_end = rand(1:5) * 0.001
    sleep(jitter_end)
    
    return result
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    Create an action
"""
function create_action(action_type::String, target::String; parameters::Dict{String, Any}=Dict())::Action
    Action(action_type, target, parameters, DateTime(now()))
end

"""
    Export key info (without exposing the key)
"""
function export_key_info(key::CryptoKey)::Dict{String, Any}
    Dict(
        "key_id" => key.key_id,
        "version" => key.version,
        "created_at" => string(key.created_at),
        "rotated_at" => key.rotated_at !== nothing ? string(key.rotated_at) : nothing
    )
end

# ============================================================================
# Example Usage
# ============================================================================

# Example usage:
# ```
# using Crypto
# 
# # Initialize with a secret key
# key = generate_secret_key(32)
# init_crypto(key)
# 
# # Create and sign an action
# action = create_action("execute_command", "/bin/ls", parameters=Dict("args" => ["-la"]))
# token = sign_action(action, key)
# 
# # Verify the token
# if verify_token(token, key)
#     println("Action verified!")
# else
#     println("Verification failed!")
# end
# 
# # Rotate keys (every 24 hours)
# new_key = rotate_keys!()
# 
# # Check audit log
# for entry in get_audit_log(limit=10)
#     println("$(entry.timestamp): $(entry.operation) - $(entry.details)")
# end
# ```

end # module
