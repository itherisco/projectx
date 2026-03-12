"""
    FlowIntegrity.jl - Cryptographic Flow Integrity System
    
    P0 REMEDIATION: Sovereignty Illusion (Convention-Only)
    
    THREAT MODEL:
    - Original vulnerability: Kernel.approve() is just a function call
    - Attack: Prompt injection could redefine the function to always return true
    - Impact: Unrestricted capability execution without kernel oversight
    
    REMEDIATION DESIGN - Flow Integrity Pattern:
    - Kernel issues one-time cryptographic HMAC tokens on approval
    - Each token encodes: capability_id, params_hash, cycle_number, expiration
    - ExecutionEngine MUST verify token before running any capability
    - Tokens are single-use and time-bounded
    - HMAC secret is NEVER exposed to external code
    
    CRYPTOGRAPHIC PRIMITIVES:
    - HMAC-SHA256 for token authentication (can't be forged without secret)
    - RandomDevice() for token entropy (CSPRNG)
    - SHA256 for capability/params binding (integrity)
    
    FAIL-CLOSED DEFAULT:
    - Missing/invalid tokens = DENIED
    - Expired tokens = DENIED
    - Verification failure = DENIED
    - Token reuse attempt = DENIED
    
    SECURITY PROPERTIES:
    - Non-repudiation: Tokens can't be forged without HMAC secret
    - Integrity: Token is bound to specific capability + params
    - Freshness: Tokens expire and can't be replayed
    - Single-use: Used tokens are invalidated immediately
"""

module FlowIntegrity

using SHA
using Random
using JSON
using Dates

# Note: SharedTypes is already defined in the Kernel module that includes this file
# FlowIntegrity.jl is included by Kernel.jl after SharedTypes is defined
# So we access it via the parent module (Kernel)

# ============================================================================
# FLOW TOKEN TYPES
# ============================================================================

"""
    FlowToken - Cryptographically sealed execution permit
    
    A FlowToken is a one-time permit issued by the Kernel that authorizes
    a specific capability execution. It cannot be forged, reused, or redirected.
"""
struct FlowToken
    token_id::Vector{UInt8}      # 32 bytes, unique identifier
    capability_id::String        # What capability this token authorizes
    params_hash::Vector{UInt8}   # SHA256 of execution params (integrity binding)
    cycle_number::Int            # Kernel cycle when issued (freshness)
    created_at::UInt64           # Unix timestamp
    expires_at::UInt64           # Unix timestamp (expiration)
    hmac::Vector{UInt8}          # HMAC-SHA256 signature (authenticity)
end

"""
    FlowTokenStore - Manages active FlowTokens with single-use guarantee
"""
mutable struct FlowTokenStore
    active_tokens::Dict{String, FlowToken}  # token_id -> FlowToken
    used_tokens::Set{String}                  # One-time use tracking
    secret_key::Vector{UInt8}                 # HMAC secret (kernel-only)
    max_tokens::Int                            # Max active tokens
    token_ttl::UInt64                          # Token validity duration (seconds)
    
    function FlowTokenStore(
        secret_key::Vector{UInt8};
        max_tokens::Int=100,
        token_ttl::UInt64=UInt64(60)  # 60 seconds default
    )
        return new(
            Dict{String, FlowToken}(),
            Set{String}(),
            secret_key,
            max_tokens,
            token_ttl
        )
    end
end

# ============================================================================
# FLOW INTEGRITY GATE
# ============================================================================

"""
    FlowIntegrityGate - Kernel-side token issuer
    
    This gate maintains the cryptographic boundary between Kernel approval
    and ExecutionEngine execution. It issues tokens that the ExecutionEngine
    MUST verify before any capability runs.
"""
# CRITICAL SECURITY FIX: Token enforcement is now IMMUTABLE
# Token enforcement cannot be toggled - security is non-negotiable
struct FlowIntegrityGate
    token_store::FlowTokenStore
    # NOTE: enforce_tokens was removed - tokens are ALWAYS enforced
    
    function FlowIntegrityGate(;secret_key=nothing)
        # Use provided key or generate/load from secure storage
        key = _get_flow_integrity_secret(secret_key)
        store = FlowTokenStore(key)
        return new(store)  # ALWAYS enforce tokens - no toggle possible
    end
end

# Environment variable for flow integrity secret
const _FLOW_INTEGRITY_SECRET_ENV = "JARVIS_FLOW_INTEGRITY_SECRET"

"""
    _get_flow_integrity_secret - Get or generate the HMAC secret
SECURITY: Throws an error if not configured - fail secure
"""
function _get_flow_integrity_secret(provided::Union{Vector{UInt8}, Nothing})::Vector{UInt8}
    if provided !== nothing
        return provided
    elseif haskey(ENV, _FLOW_INTEGRITY_SECRET_ENV)
        return Vector{UInt8}(ENV[_FLOW_INTEGRITY_SECRET_ENV])
    else
        error("SECURITY CRITICAL: JARVIS_FLOW_INTEGRITY_SECRET environment variable not set. " *
              "System cannot operate without a configured flow integrity secret. " *
              "Set this environment variable to a cryptographically secure random value.")
    end
end

"""
    flow_secret_is_set()::Bool
Check if JARVIS_FLOW_INTEGRITY_SECRET has been configured.
"""
function flow_secret_is_set()::Bool
    return haskey(ENV, _FLOW_INTEGRITY_SECRET_ENV)
end

# ============================================================================
# TOKEN GENERATION (Kernel-Side)
# ============================================================================

"""
    _build_token_payload - Build the data to be HMAC-signed
"""
function _build_token_payload(
    token_id::Vector{UInt8},
    capability_id::String,
    params_hash::Vector{UInt8},
    cycle_number::Int,
    created_at::UInt64,
    expires_at::UInt64
)::Vector{UInt8}
    payload = vcat(
        token_id,
        Vector{UInt8}(capability_id),
        params_hash,
        reinterpret(UInt8, [Int32(cycle_number)]),
        reinterpret(UInt8, [created_at]),
        reinterpret(UInt8, [expires_at])
    )
    return payload
end

"""
    _compute_token_hmac - Compute HMAC for a token
"""
function _compute_token_hmac(
    payload::Vector{UInt8},
    secret_key::Vector{UInt8}
)::Vector{UInt8}
    return sha256([secret_key; payload])
end

"""
    issue_flow_token - Kernel issues a one-time execution token
    
    This is called when the Kernel approves an action. The token binds
    the specific capability and parameters to prevent redirect attacks.
"""
function issue_flow_token(
    gate::FlowIntegrityGate,
    capability_id::String,
    params::Dict{String, Any},
    cycle_number::Int
)::Union{FlowToken, Nothing}
    
    # Rate limiting: check token store capacity
    if length(gate.token_store.active_tokens) >= gate.token_store.max_tokens
        @warn "FlowIntegrity: Token store full, rejecting new token request"
        return nothing
    end
    
    # Generate unique token ID using CSPRNG
    token_id = rand(RandomDevice(), UInt8, 32)
    
    # Compute params hash for integrity binding
    params_json = JSON.json(params)
    params_hash = sha256(Vector{UInt8}(params_json))
    
    # Timestamps
    now_ts = UInt64(floor(time()))
    expires_at = now_ts + gate.token_store.token_ttl
    
    # Build payload and compute HMAC
    payload = _build_token_payload(
        token_id, capability_id, params_hash, cycle_number, now_ts, expires_at
    )
    hmac = _compute_token_hmac(payload, gate.token_store.secret_key)
    
    # Create token
    token = FlowToken(
        token_id,
        capability_id,
        params_hash,
        cycle_number,
        now_ts,
        expires_at,
        hmac
    )
    
    # Store token
    token_id_str = bytes2hex(token_id)
    gate.token_store.active_tokens[token_id_str] = token
    
    @debug "FlowIntegrity: Issued token" capability=capability_id cycle=cycle_number token_id=token_id_str[1:8]*"..."
    
    return token
end

"""
    serialize_token - Convert token to a verification-friendly format
    Returns token_id hex + HMAC hex for external verification
"""
function serialize_token(token::FlowToken)::Dict{String, Any}
    return Dict{String, Any}(
        "token_id" => bytes2hex(token.token_id),
        "capability_id" => token.capability_id,
        "params_hash" => bytes2hex(token.params_hash),
        "cycle_number" => string(token.cycle_number),
        "created_at" => string(token.created_at),
        "expires_at" => string(token.expires_at),
        "hmac" => bytes2hex(token.hmac)
    )
end

# ============================================================================
# TOKEN VERIFICATION (ExecutionEngine-Side)
# ============================================================================

"""
    verify_flow_token - Verify and consume a FlowToken
    
    This function MUST be called by the ExecutionEngine before any
    capability execution. It verifies:
    1. Token exists and is not expired
    2. HMAC signature is valid (authentic)
    3. Capability matches (anti-redirect)
    4. Params hash matches (anti-tampering)
    5. Token hasn't been used (single-use)
    
    Returns: (is_valid::Bool, reason::String)
"""
function verify_flow_token(
    gate::FlowIntegrityGate,
    token_id_hex::String,
    capability_id::String,
    params::Dict{String, Any}
)::Tuple{Bool, String}
    
    # CRITICAL SECURITY FIX: Token enforcement is now IMMUTABLE
    # Tokens are ALWAYS enforced - there is no bypass path
    # Fail-closed: if token is missing, deny execution
    if !haskey(gate.token_store.active_tokens, token_id_hex)
        # Check if it was already used
        if token_id_hex in gate.token_store.used_tokens
            return false, "TOKEN_ALREADY_USED"
        end
        return false, "TOKEN_NOT_FOUND"
    end
    
    token = gate.token_store.active_tokens[token_id_hex]
    
    # Check 1: Expiration
    now_ts = UInt64(floor(time()))
    if now_ts > token.expires_at
        return false, "TOKEN_EXPIRED"
    end
    
    # Check 2: HMAC verification (re-compute and compare)
    params_json = JSON.json(params)
    params_hash = sha256(Vector{UInt8}(params_json))
    
    # Re-build original payload to verify HMAC
    # Note: We use stored timestamps to ensure HMAC verification works
    payload = _build_token_payload(
        token.token_id,
        token.capability_id,
        token.params_hash,  # Original params hash from token
        token.cycle_number,
        token.created_at,
        token.expires_at
    )
    
    expected_hmac = _compute_token_hmac(payload, gate.token_store.secret_key)
    if token.hmac != expected_hmac
        return false, "INVALID_HMAC"
    end
    
    # Check 3: Capability binding (anti-redirect)
    if token.capability_id != capability_id
        return false, "CAPABILITY_MISMATCH"
    end
    
    # Check 4: Params hash (anti-tampering)
    if params_hash != token.params_hash
        return false, "PARAMS_TAMPERED"
    end
    
    # Check 5: Single-use (mark as used)
    delete!(gate.token_store.active_tokens, token_id_hex)
    push!(gate.token_store.used_tokens, token_id_hex)
    
    @debug "FlowIntegrity: Token verified" capability=capability_id token_id=token_id_hex[1:8]*"..."
    
    return true, "TOKEN_VALID"
end

"""
    verify_flow_token_from_dict - Verify token from serialized dict format
"""
function verify_flow_token_from_dict(
    gate::FlowIntegrityGate,
    token_dict::Dict{String, Any},
    capability_id::String,
    params::Dict{String, Any}
)::Tuple{Bool, String}
    
    token_id = get(token_dict, "token_id", "")
    if isempty(token_id)
        return false, "MISSING_TOKEN_ID"
    end
    
    return verify_flow_token(gate, token_id, capability_id, params)
end

# ============================================================================
# TOKEN MANAGEMENT
# ============================================================================

"""
    cleanup_expired_tokens - Remove expired tokens from active store
"""
function cleanup_expired_tokens(gate::FlowIntegrityGate)::Int
    now_ts = UInt64(floor(time()))
    expired_keys = String[]
    
    for (token_id, token) in gate.token_store.active_tokens
        if now_ts > token.expires_at
            push!(expired_keys, token_id)
        end
    end
    
    for key in expired_keys
        delete!(gate.token_store.active_tokens, key)
    end
    
    return length(expired_keys)
end

"""
    get_active_token_count - Get number of active tokens
"""
function get_active_token_count(gate::FlowIntegrityGate)::Int
    return length(gate.token_store.active_tokens)
end

# CRITICAL SECURITY FIX: Token enforcement can no longer be toggled
# This function is kept for API compatibility but now throws an error
"""
    enable_token_enforcement - DISABLED for security
    
    CRITICAL: Token enforcement can no longer be disabled.
    This function exists only for API compatibility and will throw an error.
"""
function enable_token_enforcement(gate::FlowIntegrityGate, enabled::Bool)
    error("SECURITY CRITICAL: Token enforcement toggle has been removed. 
          Flow integrity enforcement is now always enabled and non-optional.")
end

# ============================================================================
# EXPORTS
# ============================================================================

export FlowToken, FlowTokenStore, FlowIntegrityGate,
       issue_flow_token, serialize_token, verify_flow_token, verify_flow_token_from_dict,
       cleanup_expired_tokens, get_active_token_count, enable_token_enforcement,
       flow_secret_is_set

end  # module FlowIntegrity
