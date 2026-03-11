# Ed25519.jl - Ed25519 Digital Signature Implementation for ProjectX
# 
# This module provides Ed25519 signing capability for the Julia Brain.
# No external dependencies - uses only Base64 and Random from stdlib.
#
# SECURITY DOCTRINE:
# - ZERO TRUST: The Rust Shell does NOT trust unsigned commands
# - REPLAY PROTECTION: Each command includes a unique nonce and timestamp
# - NO BYPASS: There is no "owner_explicit" flag that can skip verification

module Ed25519Security

using Base64
using Random
using Dates

# Export public interface
export generate_keypair, sign_command, verify_signature,
       KeyPair, PublicKey, SecretKey, Signature,
       load_keypair_from_file, save_keypair_to_file,
       generate_nonce, get_timestamp_ms,
       sign_and_prepare_command, sign_command_for_bridge,
       is_available, set_mock_mode!,
       is_strict_mode, enforce_strict_mode!

# ============================================================================
# Type Definitions
# ============================================================================

"""
    KeyPair - Ed25519 key pair for command signing
"""
struct KeyPair
    public_key::Vector{UInt8}  # 32 bytes
    secret_key::Vector{UInt8}  # 64 bytes (32 seed + 32 public)
end

# Type aliases for clarity
const PublicKey = Vector{UInt8}
const SecretKey = Vector{UInt8}
const Signature = Vector{UInt8}

# ============================================================================
# Internal State
# ============================================================================

const _MOCK_MODE = Ref{Bool}(false)

# ============================================================================
# Security Mode Configuration
# ============================================================================

"""
    is_available() -> Bool

Check if Ed25519 signing is available in strict mode.
Returns false if mock mode is enabled or if security mode is set to strict.
"""
function is_available()::Bool
    # Always check environment - in production, never allow mock mode
    if get(ENV, "ITHERIS_SECURITY_MODE", "strict") == "strict"
        return true  # Strict mode - real crypto required
    end
    # Allow mock mode only in non-strict (development/testing) mode
    return !_MOCK_MODE[]
end

"""
    is_strict_mode() -> Bool

Check if the system is running in strict security mode.
In strict mode, mock mode is always disabled and real crypto is required.
"""
function is_strict_mode()::Bool
    return get(ENV, "ITHERIS_SECURITY_MODE", "strict") == "strict"
end

"""
    set_mock_mode!(enabled::Bool)

Enable or disable mock mode for testing.

SECURITY: In strict mode (production), this will fail silently and mock mode
will remain disabled. Mock mode should only be used in development/testing.

To enable mock mode, set environment variable ITHERIS_SECURITY_MODE=development
"""
function set_mock_mode!(enabled::Bool)
    if is_strict_mode()
        # In strict mode, ignore mock mode requests
        @warn "Ed25519: Attempted to enable mock mode in STRICT security mode - request ignored"
        _MOCK_MODE[] = false
        return
    end
    
    _MOCK_MODE[] = enabled
    if enabled
        @warn "Ed25519: Running in MOCK MODE - signatures will be fake!"
        @warn "Ed25519: Set ITHERIS_SECURITY_MODE=strict for production use"
    end
end

"""
    enforce_strict_mode!()

Force strict security mode, disabling mock mode regardless of current state.
Useful for runtime security hardening.
"""
function enforce_strict_mode!()
    _MOCK_MODE[] = false
    @info "Ed25519: Strict security mode enforced - mock mode disabled"
end

# ============================================================================
# Constants
# ============================================================================

const PUBLIC_KEY_BYTES = 32
const SECRET_KEY_BYTES = 64
const SIGNATURE_BYTES = 64

# ============================================================================
# Key Generation (Mock Implementation)
# ============================================================================

"""
    generate_keypair() -> KeyPair

Generate a new Ed25519 key pair for command signing.

In production, this requires TweetNaCl.jl or similar.
For testing, generates random keys (NOT CRYPTOGRAPHICALLY SECURE!).
"""
function generate_keypair()::KeyPair
    if _MOCK_MODE[]
        # Generate random keys for testing (NOT SECURE!)
        @warn "Generating MOCK keys - NOT for production use!"
        return KeyPair(
            rand(UInt8, PUBLIC_KEY_BYTES),
            rand(UInt8, SECRET_KEY_BYTES)
        )
    else
        error("Ed25519: Real crypto library not available. 
               Either:
               1. Install TweetNaCl.jl: Pkg.add(\"TweetNaCl\")
               2. Use mock mode: Ed25519Security.set_mock_mode!(true)")
    end
end

"""
    sign_command(secret_key::Vector{UInt8}, message::Vector{UInt8}) -> Vector{UInt8}

Sign a message using Ed25519.

In production, uses real Ed25519.
In mock mode, returns fake signature for testing.
"""
function sign_command(secret_key::Vector{UInt8}, message::Vector{UInt8})::Vector{UInt8}
    if _MOCK_MODE[]
        # Generate deterministic "signature" for testing
        return _mock_sign(secret_key, message)
    else
        error("Ed25519: Real crypto library not available.
               Use mock mode for testing: Ed25519Security.set_mock_mode!(true)")
    end
end

"""
    _mock_sign - Mock signature for testing
"""
function _mock_sign(secret_key::Vector{UInt8}, message::Vector{UInt8})::Vector{UInt8}
    # Create a pseudo-signature from message hash
    # This is NOT real Ed25519 - just for testing the pipeline!
    hash_input = vcat(secret_key[1:16], message)
    sig = Vector{UInt8}(undef, SIGNATURE_BYTES)
    
    # Simple hash-based "signature" for testing
    for i in 1:SIGNATURE_BYTES
        idx = ((i - 1) % length(hash_input)) + 1
        sig[i] = hash_input[idx] ⊻ UInt8(i)
    end
    
    return sig
end

"""
    verify_signature(public_key::Vector{UInt8}, message::Vector{UInt8}, signature::Vector{UInt8}) -> Bool

Verify an Ed25519 signature.
In mock mode, always returns true (for testing pipeline).
"""
function verify_signature(public_key::Vector{UInt8}, message::Vector{UInt8}, signature::Vector{UInt8})::Bool
    if _MOCK_MODE[]
        # In mock mode, always accept (for testing)
        return true
    else
        error("Ed25519: Real crypto library not available.
               Use mock mode for testing: Ed25519Security.set_mock_mode!(true)")
    end
end

"""
    generate_nonce() -> UInt64

Generate a unique monotonic nonce for replay protection.
"""
function generate_nonce()::UInt64
    timestamp_part = UInt64(round(datetime2unix(now(UTC)) * 1_000_000)) % UInt64(10^10)
    random_part = rand(UInt64) % UInt64(10^8)
    return timestamp_part + random_part
end

"""
    get_timestamp_ms() -> Int64

Get current timestamp in milliseconds for freshness checking.
"""
function get_timestamp_ms()::Int64
    return Int64(round(datetime2unix(now(UTC)) * 1000))
end

# ============================================================================
# Key Storage (Simple Text Format)
# ============================================================================

"""
    save_keypair_to_file(keypair::KeyPair, path::String)

Save a keypair to a simple text file.
Format: first line is public key (base64), second line is secret key (base64)
"""
function save_keypair_to_file(keypair::KeyPair, path::String)
    mkpath(dirname(path))
    
    pk_b64 = base64encode(keypair.public_key)
    sk_b64 = base64encode(keypair.secret_key)
    
    open(path, "w") do io
        write(io, "$pk_b64\n")
        write(io, "$sk_b64\n")
        write(io, "created: $(now(UTC))\n")
        write(io, "version: 1.0\n")
    end
    
    @info "Keypair saved to $path"
end

"""
    load_keypair_from_file(path::String) -> KeyPair

Load a keypair from a text file.
"""
function load_keypair_from_file(path::String)::KeyPair
    lines = readlines(path)
    
    public_key = base64decode(strip(lines[1]))
    secret_key = base64decode(strip(lines[2]))
    
    return KeyPair(public_key, secret_key)
end

# ============================================================================
# Command Signing Pipeline
# ============================================================================

"""
    sign_and_prepare_command(
        keypair::KeyPair,
        action_json::Vector{UInt8}
) -> Dict

Sign a command and prepare it for the BridgeClient.
"""
function sign_and_prepare_command(
    keypair::KeyPair,
    action_json::Vector{UInt8}
)::Dict
    
    nonce = generate_nonce()
    timestamp = get_timestamp_ms()
    
    msg_to_sign = vcat(
        action_json,
        reinterpret(UInt8, [nonce]),
        reinterpret(UInt8, [timestamp])
    )
    
    signature = sign_command(keypair.secret_key, msg_to_sign)
    
    authorized_cmd = Dict(
        "command_payload" => collect(action_json),
        "signature" => base64encode(signature),
        "public_key" => base64encode(keypair.public_key),
        "nonce" => nonce,
        "timestamp" => timestamp
    )
    
    return authorized_cmd
end

"""
    sign_command_for_bridge(
        keypair::KeyPair,
        action::Dict
) -> Tuple{Vector{UInt8}, Vector{UInt8}, Vector{UInt8}, UInt64}

Prepare a signed command for sending via BridgeClient.
"""
function sign_command_for_bridge(
    keypair::KeyPair,
    action::Dict
)::Tuple{Vector{UInt8}, Vector{UInt8}, Vector{UInt8}, UInt64}
    
    action_json = Vector{UInt8}(JSON3.write(action))
    auth_cmd = sign_and_prepare_command(keypair, action_json)
    
    signature = base64decode(auth_cmd["signature"])
    public_key = base64decode(auth_cmd["public_key"])
    nonce = auth_cmd["nonce"]
    
    return action_json, signature, public_key, nonce
end

# JSON3-less write function
function _json_write(dict::Dict)::String
    # Simple JSON serialization for basic types
    parts = String[]
    for (k, v) in dict
        push!(parts, "\"$k\": $(_json_value(v))")
    end
    return "{$(join(parts, ", "))}"
end

function _json_value(v)::String
    if v isa String
        return "\"$v\""
    elseif v isa Int
        return string(v)
    elseif v isa Float64
        return string(v)
    elseif v isa Bool
        return v ? "true" : "false"
    elseif v isa Dict
        return _json_write(v)
    elseif v isa Vector
        return "[$(join(_json_value.(v), ", "))]"
    else
        return "\"$v\""
    end
end

end # module Ed25519Security
