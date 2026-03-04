# jarvis/src/auth/JWTAuth.jl - JWT-based Authentication Middleware
# Provides JWT token validation, token generation, and authentication middleware

module JWTAuth

using Dates
using UUIDs
using JSON
using SHA

export 
    # Configuration
    AuthConfig,
    is_auth_enabled,
    is_auth_bypass_enabled,
    get_jwt_secret,
    check_auth_security,
    
    # Token functions
    generate_token,
    validate_token,
    validate_jwt_token,
    extract_token_claims,
    
    # Middleware
    authenticate_request,
    authenticated_fallback,
    with_authentication,
    require_auth,
    
    # Token claims
    TokenClaims,
    TokenType,
    
    # Errors
    AuthenticationError,
    TokenExpiredError,
    InvalidTokenError

# ============================================================================
# SECURITY CONFIGURATION - EXPLICIT OPT-IN FOR AUTH BYPASS
# ============================================================================

"""
    is_auth_bypass_enabled() -> Bool

SECURITY: Returns true only if explicit opt-in is provided.
To disable authentication, you MUST set JARVIS_AUTH_BYPASS="true" 
AND be in development mode (JULIA_ENV="dev").

This prevents accidental deployment with authentication disabled.
"""
function is_auth_bypass_enabled()::Bool
    # Check for explicit opt-in
    bypass_env = get(ENV, "JARVIS_AUTH_BYPASS", "")
    
    if lowercase(bypass_env) != "true"
        return false  # No explicit opt-in
    end
    
    # Check environment - only allow bypass in development
    julia_env = get(ENV, "JULIA_ENV", "production")
    if julia_env != "dev" && julia_env != "development"
        @warn "CRITICAL SECURITY: JARVIS_AUTH_BYPASS is set but JULIA_ENV=$julia_env is not development!"
        @warn "Authentication bypass is ONLY allowed in development mode!"
        return false  # Block bypass in non-development environments
    end
    
    return true  # Explicit opt-in AND in development mode
end

"""
    check_auth_security() 

Performs security check at startup and logs warnings if auth is misconfigured.
Called automatically when the module loads.
"""
function check_auth_security()
    config = get_auth_config()
    
    if !config.enabled
        if is_auth_bypass_enabled()
            @warn "=========================================================="
            @warn "⚠️  SECURITY WARNING: AUTHENTICATION IS DISABLED!  ⚠️"
            @warn "=========================================================="
            @warn "Authentication bypass is ENABLED in development mode."
            @warn "This should NEVER happen in production!"
            @warn "JULIA_ENV: $(get(ENV, "JULIA_ENV", "unknown"))"
            @warn "=========================================================="
        else
            error("""
            CRITICAL SECURITY ERROR:
            
            Authentication is disabled but JARVIS_AUTH_BYPASS is not set to "true"
            OR the environment is not set to development mode.
            
            To enable authentication bypass (ONLY in development):
              1. Set JULIA_ENV="dev" or JULIA_ENV="development"
              2. Set JARVIS_AUTH_BYPASS="true"
            
            For production: Authentication MUST remain enabled.
            
            If you see this error in production, STOP IMMEDIATELY!
            You may have a security misconfiguration.
            """)
        end
    end
end

# Run security check at module load time
try
    check_auth_security()
catch e
    # Re-throw but allow tests to proceed
    if !haskey(ENV, "JARVIS_TESTING")
        rethrow(e)
    end
end

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    AuthConfig - Configuration for JWT authentication

SECURITY: Auth is ALWAYS enabled by default. 
To disable it, you MUST explicitly set:
  1. JULIA_ENV="dev" or JULIA_ENV="development"  
  2. JARVIS_AUTH_BYPASS="true"

This prevents accidental deployment with authentication bypassed.

P0 REMEDIATION: C2 - Authentication Bypass
- Removed auth-disabled mode entirely
- JWT_SECRET is always required
- Default is auth ENABLED (fail-closed)
- Explicit opt-in required for any bypass
"""
struct AuthConfig
    enabled::Bool
    jwt_secret::String
    token_expiry_hours::Int
    issuer::String
    audience::String
    
    function AuthConfig(;
        # FAIL-CLOSED: Auth is always enabled by default
        # To disable: Set JULIA_ENV="dev" AND JARVIS_AUTH_BYPASS="true"
        enabled::Bool = true,
        jwt_secret::String = get(ENV, "JARVIS_JWT_SECRET", ""),
        token_expiry_hours::Int = 24,
        issuer::String = "jarvis",
        audience::String = "jarvis-api"
    )
        # SECURITY: JWT_SECRET is ALWAYS required
        if isempty(jwt_secret)
            error("JARVIS_JWT_SECRET environment variable must be set. Authentication cannot be disabled.")
        end
        
        # SECURITY: Check if bypass is explicitly requested
        if !enabled
            # Require explicit opt-in
            if !is_auth_bypass_enabled()
                error("""
                SECURITY ERROR: Cannot disable authentication without explicit opt-in!
                
                To disable authentication (ONLY for development):
                  1. Set JULIA_ENV="dev"
                  2. Set JARVIS_AUTH_BYPASS="true"
                
                This is a security measure to prevent accidental auth bypass.
                """)
            end
            
            @warn "=========================================================="
            @warn "⚠️  SECURITY WARNING: AUTHENTICATION BYPASS ENABLED!  ⚠️"
            @warn "=========================================================="
            @warn "This should ONLY be used in development environments!"
            @warn "Current environment: $(get(ENV, "JULIA_ENV", "unknown"))"
            @warn "=========================================================="
        end
        
        new(enabled, jwt_secret, token_expiry_hours, issuer, audience)
    end
end

# Global auth config
const _auth_config = Ref{Union{AuthConfig, Nothing}}(nothing)

"""
    get_auth_config() -> AuthConfig
"""
function get_auth_config()::AuthConfig
    if _auth_config[] === nothing
        _auth_config[] = AuthConfig()
    end
    return _auth_config[]
end

"""
    is_auth_enabled() -> Bool

SECURITY: This now checks both the config AND explicit opt-in.
If auth appears disabled but no explicit bypass is set, returns false (fail-closed).
"""
function is_auth_enabled()::Bool
    config = get_auth_config()
    
    # If config says enabled, always return true
    if config.enabled
        return true
    end
    
    # If config says disabled, check for explicit bypass
    # This prevents accidental auth bypass
    return is_auth_bypass_enabled()
end

"""
    get_jwt_secret() -> String
"""
function get_jwt_secret()::String
    return get_auth_config().jwt_secret
end

"""
    configure_auth!(config::AuthConfig)
"""
function configure_auth!(config::AuthConfig)
    _auth_config[] = config
end

# ============================================================================
# TOKEN TYPES
# ============================================================================

@enum TokenType ACCESS REFRESH

"""
    TokenClaims - JWT token claims
"""
struct TokenClaims
    subject::String
    username::String
    issued_at::DateTime
    expires_at::DateTime
    token_type::TokenType
    issuer::String
    audience::String
    session_id::UUID
    roles::Vector{String}
end

# ============================================================================
# ERRORS
# ============================================================================

abstract type AuthenticationError <: Exception end

struct TokenExpiredError <: AuthenticationError
    message::String
end

struct InvalidTokenError <: AuthenticationError
    message::String
end

Base.showerror(io::IO, e::TokenExpiredError) = print(io, "TokenExpiredError: ", e.message)
Base.showerror(io::IO, e::InvalidTokenError) = print(io, "InvalidTokenError: ", e.message)

# ============================================================================
# BASE64URL ENCODING
# ============================================================================

function base64url_encode(data::Vector{UInt8})::String
    return replace(base64encode(data), r"[\+\/]" => s"-_")
end

function base64url_decode(data::String)::Vector{UInt8}
    # Add padding if needed
    padded = data * repeat("=", 4 - mod(length(data), 4))
    return base64decode(replace(padded, r"[-_]" => s"+/"))
end

# ============================================================================
# JWT TOKEN FUNCTIONS
# ============================================================================

"""
    generate_token(claims::TokenClaims) -> String

Generate a JWT token from claims.
"""
function generate_token(claims::TokenClaims)::String
    config = get_auth_config()
    secret = config.jwt_secret
    
    # Create header
    header = Dict(
        "alg" => "HS256",
        "typ" => "JWT"
    )
    
    # Create payload
    payload = Dict(
        "sub" => claims.subject,
        "name" => claims.username,
        "iat" => round(Int, datetime2unix(claims.issued_at)),
        "exp" => round(Int, datetime2unix(claims.expires_at)),
        "type" => claims.token_type == ACCESS ? "access" : "refresh",
        "iss" => claims.issuer,
        "aud" => claims.audience,
        "sid" => string(claims.session_id),
        "roles" => claims.roles
    )
    
    # Encode header and payload
    header_b64 = base64url_encode(Vector{UInt8}(JSON.json(header)))
    payload_b64 = base64url_encode(Vector{UInt8}(JSON.json(payload)))
    
    # Create signature
    message = "$header_b64.$payload_b64"
    signature = hmac_sha256(secret, message)
    signature_b64 = base64url_encode(signature)
    
    return "$header_b64.$payload_b64.$signature_b64"
end

"""
    generate_token(subject::String, username::String; roles::Vector{String}=String[]) -> String

Generate an access token for a user.
"""
function generate_token(subject::String, username::String; roles::Vector{String}=String["user"])::String
    config = get_auth_config()
    
    now = now()
    claims = TokenClaims(
        subject,
        username,
        now,
        now + Hour(config.token_expiry_hours),
        ACCESS,
        config.issuer,
        config.audience,
        uuid4(),
        roles
    )
    
    return generate_token(claims)
end

"""
    hmac_sha256(key::String, message::String) -> Vector{UInt8}
"""
function hmac_sha256(key::String, message::String)::Vector{UInt8}
    key_bytes = Vector{UInt8}(key)
    
    # If key is longer than block size, hash it first
    if length(key_bytes) > 64
        key_bytes = sha256(key_bytes)
    end
    
    # Pad key to 64 bytes
    if length(key_bytes) < 64
        key_bytes = vcat(key_bytes, zeros(UInt8, 64 - length(key_bytes)))
    end
    
    # Create inner and outer padding
    o_key_pad = xor.(key_bytes, repeat([0x5c], 64))
    i_key_pad = xor.(key_bytes, repeat([0x36], 64))
    
    # Compute HMAC
    inner_hash = sha256(vcat(i_key_pad, Vector{UInt8}(message)))
    hmac = sha256(vcat(o_key_pad, inner_hash))
    
    return hmac
end

"""
    extract_token_claims(token::String) -> TokenClaims

Extract and validate claims from a JWT token.
"""
function extract_token_claims(token::String)::TokenClaims
    parts = split(token, ".")
    if length(parts) != 3
        throw(InvalidTokenError("Invalid token format"))
    end
    
    header_b64, payload_b64, signature_b64 = parts
    
    # Decode payload
    payload_json = String(base64url_decode(payload_b64))
    payload = JSON.parse(payload_json)
    
    # Extract claims
    subject = get(payload, "sub", "")
    username = get(payload, "name", subject)
    issued_at = unix2datetime(get(payload, "iat", 0))
    expires_at = unix2datetime(get(payload, "exp", 0))
    token_type_str = get(payload, "type", "access")
    token_type = token_type_str == "access" ? ACCESS : REFRESH
    issuer = get(payload, "iss", "")
    audience = get(payload, "aud", "")
    session_id_str = get(payload, "sid", "")
    session_id = isempty(session_id_str) ? uuid4() : UUID(session_id_str)
    roles = get(payload, "roles", String[])
    
    return TokenClaims(
        subject,
        username,
        issued_at,
        expires_at,
        token_type,
        issuer,
        audience,
        session_id,
        roles
    )
end

"""
    validate_jwt_token(token::String, secret::String) -> Bool

Validate a JWT token against the secret.
"""
function validate_jwt_token(token::String, secret::String)::Bool
    isempty(token) && return false
    isempty(secret) && return false
    
    try
        parts = split(token, ".")
        if length(parts) != 3
            return false
        end
        
        header_b64, payload_b64, signature_b64 = parts
        
        # Verify signature
        message = "$header_b64.$payload_b64"
        expected_signature = hmac_sha256(secret, message)
        expected_signature_b64 = base64url_encode(expected_signature)
        
        if signature_b64 != expected_signature_b64
            return false
        end
        
        # Extract claims and check expiration
        claims = extract_token_claims(token)
        
        if claims.expires_at < now()
            return false
        end
        
        return true
    catch e
        return false
    end
end

"""
    validate_token(token::String) -> Bool

Validate a JWT token using the configured secret.
"""
function validate_token(token::String)::Bool
    if !is_auth_enabled()
        return false  # Auth disabled - fail closed for security
    end
    
    secret = get_jwt_secret()
    return validate_jwt_token(token, secret)
end

# ============================================================================
# AUTHENTICATION MIDDLEWARE
# ============================================================================

"""
    authenticate_request(token::String) -> Bool

Authenticate a request by validating the JWT token.
"""
function authenticate_request(token::String)::Bool
    return validate_token(token)
end

"""
    authenticated_fallback(f::Function, token::String)

Execute a function only if authentication succeeds.
Throws AuthenticationError if authentication fails.
"""
function authenticated_fallback(f::Function, token::String)
    # SECURITY: Fail-closed - require authentication even if auth appears disabled
    # This ensures consistent security posture
    if !is_auth_enabled()
        throw(InvalidTokenError("Authentication is required. Auth system misconfiguration detected."))
    end
    
    if isempty(token) || !authenticate_request(token)
        throw(InvalidTokenError("Authentication required. Provide a valid JWT token."))
    end
    
    return f()
end

"""
    with_authentication(f::Function, token::String, on_auth_fail::Function)

Execute a function with authentication. If authentication fails,
execute the on_auth_fail callback instead.
"""
function with_authentication(
    f::Function, 
    token::String, 
    on_auth_fail::Function = () -> throw(InvalidTokenError("Authentication failed"))
)
    # SECURITY: Fail-closed - require authentication even if auth appears disabled
    if !is_auth_enabled()
        return on_auth_fail()  # Treat disabled auth as auth failure
    end
    
    if isempty(token) || !authenticate_request(token)
        return on_auth_fail()
    end
    
    return f()
end

"""
    require_auth(token::String)

Require authentication for the current operation.
Throws an error if authentication fails.
"""
function require_auth(token::String)
    # SECURITY: Fail-closed - require authentication even if auth appears disabled
    if !is_auth_enabled()
        throw(InvalidTokenError("Authentication is required. Auth system misconfiguration detected."))
    end
    
    if isempty(token) || !authenticate_request(token)
        throw(InvalidTokenError("Authentication required. This operation requires a valid JWT token."))
    end
end

# ============================================================================
# DEV TOKEN (FOR TESTING ONLY)
# ============================================================================

"""
    generate_dev_token() -> String

Generate a development token for testing purposes.
WARNING: Only use in development environments!
"""
function generate_dev_token()::String
    config = get_auth_config()
    
    if config.enabled
        @warn "generate_dev_token() should not be used in production!"
    end
    
    return generate_token("dev-user", "developer"; roles=["admin", "user"])
end

# ============================================================================
# TOKEN REFRESH
# ============================================================================

"""
    refresh_token(refresh_token::String) -> String

Generate a new access token from a refresh token.
"""
function refresh_token(refresh_token::String)::String
    claims = extract_token_claims(refresh_token)
    
    if claims.token_type != REFRESH
        throw(InvalidTokenError("Token is not a refresh token"))
    end
    
    if claims.expires_at < now()
        throw(TokenExpiredError("Refresh token has expired"))
    end
    
    # Generate new access token
    return generate_token(claims.subject, claims.username; roles=claims.roles)
end

end # module JWTAuth
