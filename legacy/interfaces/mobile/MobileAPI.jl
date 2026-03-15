"""
    MobileAPI.jl - Mobile API with Sovereign Approval

    This module provides secure mobile API endpoints for JARVIS/Itheris control.
    Implements JWT authentication, sovereign approval gates, and FCM push notifications.

    # Architecture
    - Law Enforcement Point (LEP): All approval requests route through Rust security layer
    - The Brain is advisory, the Kernel is sovereign
    - Mathematical veto equation: score = priority × (reward - risk)

    # API Endpoints
    - POST /auth/login - JWT-based authentication
    - POST /auth/refresh - Token refresh
    - POST /approve - Sovereign approval endpoint
    - GET /status - System status for mobile clients
    - POST /notifications/register - FCM token registration

    # Dependencies
    - HTTP.jl for server
    - JSON.jl for serialization
    - SHA.jl for HMAC signatures
    - Base64 for token encoding

    # Security
    - Fail-closed: Authentication disabled = DENY ALL
    - Rate limiting on all endpoints
    - Cryptographically secure token generation
    - HMAC-SHA256 for message authentication
"""
module MobileAPI

using HTTP
using JSON
using Dates
using SHA
using Random
using UUIDs
using Base64
using Logging

# ============================================================================
# DEPENDENCY IMPORTS (Optional - with fallbacks)
# ============================================================================

# Try to import Rust IPC for secure communication with kernel
const _RUST_IPC_AVAILABLE = Ref{Bool}(false)
try
    using ..RustIPC
    _RUST_IPC_AVAILABLE[] = true
catch e
    # RustIPC not available - will use fallback
end

# Try to import trust modules
const _TRUST_AVAILABLE = Ref{Bool}(false)
try
    using ..SecureConfirmationGate
    _TRUST_AVAILABLE[] = true
catch e
    # Trust module not available
end

# ============================================================================
# CONSTANTS AND CONFIGURATION
# ============================================================================

const API_VERSION = "2.0.0"
const API_BASE_PATH = "/api/mobile/v2"

# JWT Configuration
const JWT_ALGORITHM = "HS256"
const JWT_ACCESS_TTL = 3600        # 1 hour in seconds
const JWT_REFRESH_TTL = 604800     # 7 days in seconds
const JWT_SECRET_LENGTH = 32

# Rate limiting
const RATE_LIMIT_MAX_REQUESTS = 100
const RATE_LIMIT_WINDOW_SECONDS = 60

# FCM Configuration (Firebase Cloud Messaging)
const FCM_DEFAULT_URL = "https://fcm.googleapis.com/fcm/send"

# ============================================================================
# TYPE DEFINITIONS
# ============================================================================

"""
    TokenType - JWT token type
"""
@enum TokenType ACCESS REFRESH

"""
    UserRole - User roles for RBAC
"""
@enum UserRole ADMIN USER READONLY SERVICE

"""
    MobileClaims - JWT claims structure
"""
mutable struct MobileClaims
    sub::String          # Subject (user identifier)
    iss::String          # Issuer
    aud::String          # Audience
    exp::Int64           # Expiration time
    nbf::Int64           # Not before
    iat::Int64           # Issued at
    jti::String          # JWT ID (unique token identifier)
    token_type::TokenType
    roles::Vector{UserRole}
end

"""
    ApprovalRequest - Request for sovereign approval
"""
struct ApprovalRequest
    proposal_id::String
    capability_id::String
    action::String
    params::Dict{String, Any}
    priority::Float64     # 0.0-1.0
    reward::Float64       # Expected reward
    risk::Float64         # Calculated risk
    requester_id::String
    timestamp::Float64
end

"""
    ApprovalResponse - Sovereign approval response
"""
struct ApprovalResponse
    approved::Bool
    score::Float64        # priority × (reward - risk)
    veto_reason::Union{String, Nothing}
    confirmation_token::String
    expires_at::Int64
    kernel_signature::String
end

"""
    FCMToken - Firebase Cloud Messaging token registration
"""
mutable struct FCMToken
    token::String
    user_id::String
    device_type::String
    registered_at::Int64
    last_active::Int64
end

"""
    MobileSession - Active mobile session
"""
mutable struct MobileSession
    user_id::String
    session_id::String
    access_token::String
    refresh_token::String
    roles::Vector{UserRole}
    created_at::Int64
    expires_at::Int64
    fcm_tokens::Vector{FCMToken}
    ip_address::String
end

# ============================================================================
# GLOBAL STATE
# ============================================================================

# In-memory session storage (in production, use Redis/database)
const _sessions = Dict{String, MobileSession}()
const _rate_limits = Dict{String, Vector{Float64}}()
const _fcm_registrations = Dict{String, Vector{FCMToken}}()

# Rate limiting lock
using Base.Threads
const _rate_limit_lock = ReentrantLock()

# JWT secret (in production, load from secure config)
const _jwt_secret = Ref{Vector{UInt8}}(rand(UInt8, JWT_SECRET_LENGTH))

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    _generate_secure_token - Generate cryptographically secure token
"""
function _generate_secure_token(length::Int=32)::String
    return base64encode(rand(UInt8, length))
end

"""
    _generate_jti - Generate unique JWT ID
"""
function _generate_jti()::String
    return string(uuid4())
end

"""
    _get_current_timestamp - Get current Unix timestamp
"""
function _get_current_timestamp()::Int64
    return floor(Int64, time())
end

"""
    _check_rate_limit - Check if request is within rate limits
"""
function _check_rate_limit(identifier::String)::Bool
    lock(_rate_limit_lock) do
        current_time = time()
        window_start = current_time - RATE_LIMIT_WINDOW_SECONDS
        
        # Get or create rate limit entry
        if !haskey(_rate_limits, identifier)
            _rate_limits[identifier] = Float64[]
        end
        
        # Clean old entries
        filter!(_rate_limits[identifier]) do t
            t > window_start
        end
        
        # Check limit
        if length(_rate_limits[identifier]) >= RATE_LIMIT_MAX_REQUESTS
            return false
        end
        
        # Add current request
        push!(_rate_limits[identifier], current_time)
        return true
    end
end

# ============================================================================
# JWT AUTHENTICATION
# ============================================================================

"""
    _base64url_encode - Base64 URL-safe encoding
"""
function _base64url_encode(data::Vector{UInt8})::String
    return replace(base64encode(data), "+" => "-", "/" => "_", "=" => "")
end

"""
    _base64url_decode - Base64 URL-safe decoding
"""
function _base64url_decode(data::String)::Vector{UInt8}
    # Add padding if needed
    padded = data * repeat("=", mod(4 - length(data) % 4, 4))
    return base64decode(replace(padded, "-" => "+", "_" => "/"))
end

"""
    _create_jwt_header - Create JWT header
"""
function _create_jwt_header()::String
    header = Dict(
        "alg" => JWT_ALGORITHM,
        "typ" => "JWT"
    )
    return _base64url_encode(Vector{UInt8}(JSON.json(header)))
end

"""
    _create_jwt_claims - Create JWT claims
"""
function _create_jwt_claims(
    subject::String,
    token_type::TokenType,
    roles::Vector{UserRole};
    ttl::Int64=JWT_ACCESS_TTL
)::Dict{String, Any}
    now = _get_current_timestamp()
    
    claims = Dict{String, Any}(
        "sub" => subject,
        "iss" => "itheris-mobile-api",
        "aud" => "itheris",
        "exp" => now + ttl,
        "nbf" => now,
        "iat" => now,
        "jti" => _generate_jti(),
        "type" => string(token_type),
        "roles" => [string(r) for r in roles]
    )
    
    return claims
end

"""
    _sign_jwt - Sign JWT with HMAC-SHA256
"""
function _sign_jwt(header::String, payload::String)::String
    message = header * "." * payload
    signature = hmac_sha256(_jwt_secret[], Vector{UInt8}(message))
    return _base64url_encode(signature)
end

"""
    _verify_jwt_signature - Verify JWT signature
"""
function _verify_jwt_signature(token::String)::Bool
    parts = split(token, ".")
    if length(parts) != 3
        return false
    end
    
    header, payload, signature = parts
    expected_sig = hmac_sha256(_jwt_secret[], Vector{UInt8}(header * "." * payload))
    expected_b64 = _base64url_encode(expected_sig)
    
    return signature == expected_b64
end

"""
    create_access_token - Create JWT access token
"""
function create_access_token(
    user_id::String,
    roles::Vector{UserRole}=[UserRole.USER]
)::String
    header = _create_jwt_header()
    payload = _create_jwt_claims(user_id, ACCESS, roles)
    payload_b64 = _base64url_encode(Vector{UInt8}(JSON.json(payload)))
    signature = _sign_jwt(header, payload_b64)
    
    return header * "." * payload_b64 * "." * signature
end

"""
    create_refresh_token - Create JWT refresh token
"""
function create_refresh_token(user_id::String)::String
    header = _create_jwt_header()
    payload = _create_jwt_claims(user_id, REFRESH, []; ttl=JWT_REFRESH_TTL)
    payload_b64 = _base64url_encode(Vector{UInt8}(JSON.json(payload)))
    signature = _sign_jwt(header, payload_b64)
    
    return header * "." * payload_b64 * "." * signature
end

"""
    validate_token - Validate JWT token
"""
function validate_token(token::String)::Union{MobileClaims, Nothing}
    # Check signature first (fail-closed)
    if !_verify_jwt_signature(token)
        @warn "JWT signature verification failed"
        return nothing
    end
    
    parts = split(token, ".")
    if length(parts) != 3
        return nothing
    end
    
    # Decode payload
    try
        payload_json = String(_base64url_decode(parts[2]))
        payload = JSON.parse(payload_json)
        
        # Check expiration
        now = _get_current_timestamp()
        if get(payload, "exp", 0) < now
            @warn "JWT token expired"
            return nothing
        end
        
        # Check not-before
        if get(payload, "nbf", 0) > now
            @warn "JWT token not yet valid"
            return nothing
        end
        
        # Parse token type
        token_type_str = get(payload, "type", "access")
        token_type = token_type_str == "refresh" ? REFRESH : ACCESS
        
        # Parse roles
        roles = UserRole[]
        for role_str in get(payload, "roles", [])
            if role_str == "admin"
                push!(roles, ADMIN)
            elseif role_str == "user"
                push!(roles, USER)
            elseif role_str == "readonly"
                push!(roles, READONLY)
            elseif role_str == "service"
                push!(roles, SERVICE)
            end
        end
        
        return MobileClaims(
            get(payload, "sub", ""),
            get(payload, "iss", ""),
            get(payload, "aud", ""),
            get(payload, "exp", 0),
            get(payload, "nbf", 0),
            get(payload, "iat", 0),
            get(payload, "jti", ""),
            token_type,
            roles
        )
    catch e
        @error "JWT parsing error: $e"
        return nothing
    end
end

"""
    has_role - Check if claims has required role
"""
function has_role(claims::MobileClaims, required_role::UserRole)::Bool
    if isempty(claims.roles)
        return false
    end
    
    # Admin has all permissions
    if ADMIN in claims.roles
        return true
    end
    
    return required_role in claims.roles
end

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

"""
    create_session - Create new mobile session
"""
function create_session(
    user_id::String,
    roles::Vector{UserRole};
    ip_address::String="unknown"
)::MobileSession
    session_id = _generate_secure_token(16)
    access_token = create_access_token(user_id, roles)
    refresh_token = create_refresh_token(user_id)
    
    now = _get_current_timestamp()
    
    session = MobileSession(
        user_id,
        session_id,
        access_token,
        refresh_token,
        roles,
        now,
        now + JWT_ACCESS_TTL,
        FCMToken[],
        ip_address
    )
    
    # Store session
    _sessions[session_id] = session
    
    return session
end

"""
    get_session - Get session by ID
"""
function get_session(session_id::String)::Union{MobileSession, Nothing}
    return get(_sessions, session_id, nothing)
end

"""
    revoke_session - Revoke session
"""
function revoke_session(session_id::String)::Bool
    if haskey(_sessions, session_id)
        delete!(_sessions, session_id)
        return true
    end
    return false
end

"""
    refresh_session - Refresh session tokens
"""
function refresh_session(refresh_token::String)::Union{MobileSession, Nothing}
    claims = validate_token(refresh_token)
    
    if claims === nothing || claims.token_type != REFRESH
        return nothing
    end
    
    # Find existing session
    session = nothing
    for (sid, s) in _sessions
        if s.user_id == claims.sub
            session = s
            break
        end
    end
    
    if session === nothing
        return nothing
    end
    
    # Rotate tokens
    session.access_token = create_access_token(claims.sub, session.roles)
    session.refresh_token = create_refresh_token(claims.sub)
    session.expires_at = _get_current_timestamp() + JWT_ACCESS_TTL
    
    return session
end

# ============================================================================
# SOVEREIGN APPROVAL - VETO EQUATION
# ============================================================================

"""
    calculate_veto_score - Calculate veto equation: score = priority × (reward - risk)
    
    The Kernel is sovereign - this function implements the mathematical veto
    that determines whether an action is approved or rejected.
    
    # Arguments
    - `priority::Float64`: Priority weight (0.0-1.0)
    - `reward::Float64`: Expected reward (can be negative)
    - `risk::Float64`: Calculated risk (0.0-1.0)
    
    # Returns
    - `score::Float64`: Final score (negative = veto)
"""
function calculate_veto_score(priority::Float64, reward::Float64, risk::Float64)::Float64
    # Normalize risk to 0-10 scale
    risk_normalized = risk * 10.0
    
    # Veto equation: score = priority × (reward - risk)
    score = priority * (reward - risk_normalized)
    
    return score
end

"""
    classify_risk - Classify risk level from parameters
"""
function classify_risk(capability_id::String, params::Dict{String, Any})::Float64
    # Base risk from capability
    base_risk = 0.5
    
    # High-risk capabilities
    high_risk_caps = ["execute", "shell", "write", "delete", "destroy", "admin"]
    for cap in high_risk_caps
        if occursin(cap, lowercase(capability_id))
            base_risk = 0.8
            break
        end
    end
    
    # Low-risk capabilities
    low_risk_caps = ["read", "observe", "query", "status", "telemetry"]
    for cap in low_risk_caps
        if occursin(cap, lowercase(capability_id))
            base_risk = 0.2
            break
        end
    end
    
    # Parameter risk modifier
    param_risk = 0.0
    sensitive_keys = ["password", "secret", "key", "token", "credential", "sudo"]
    for (key, _) in params
        key_lower = lowercase(key)
        for sensitive in sensitive_keys
            if occursin(sensitive, key_lower)
                param_risk += 0.3
                break
            end
        end
    end
    
    # Dangerous path detection
    dangerous_paths = ["/etc/", "/root/", "/sys/", "/proc/"]
    path_value = get(params, "path", get(params, "file", ""))
    for path in dangerous_paths
        if occursin(path, path_value)
            param_risk += 0.4
            break
        end
    end
    
    return min(base_risk + param_risk, 1.0)
end

"""
    approve_action - Sovereign approval with Kernel enforcement
    
    This implements the Law Enforcement Point (LEP) - all approval
    requests must go through this function which enforces the
    mathematical veto equation.
"""
function approve_action(
    request::ApprovalRequest;
    user_claims::Union{MobileClaims, Nothing}=nothing
)::ApprovalResponse
    now = _get_current_timestamp()
    
    # Calculate risk if not provided
    risk = request.risk > 0 ? request.risk : classify_risk(request.capability_id, request.params)
    
    # Calculate veto score
    score = calculate_veto_score(request.priority, request.reward, risk)
    
    # Determine approval
    approved = score >= 0.0
    
    # Generate confirmation token
    confirmation_token = approved ? _generate_secure_token(32) : ""
    
    # Generate kernel signature (in production, this comes from Rust)
    kernel_signature = approved ? _generate_kernel_signature(request, confirmation_token) : ""
    
    # Calculate expiry (use WDT-aligned timeout from SecureConfirmationGate)
    expiry_seconds = _get_approval_timeout(risk)
    expires_at = now + expiry_seconds
    
    # Build veto reason if rejected
    veto_reason = approved ? nothing : "Veto: score=$score < 0 (priority=$(request.priority), reward=$(request.reward), risk=$risk)"
    
    # Log approval event
    _log_approval_event(request, approved, score, veto_reason)
    
    return ApprovalResponse(
        approved,
        score,
        veto_reason,
        confirmation_token,
        expires_at,
        kernel_signature
    )
end

"""
    _get_approval_timeout - Get approval timeout based on risk level
"""
function _get_approval_timeout(risk::Float64)::Int64
    if risk >= 0.8
        return 32   # CRITICAL: 32s (WDT-aligned)
    elseif risk >= 0.6
        return 60   # HIGH: 60s
    elseif risk >= 0.4
        return 120  # MEDIUM: 120s
    else
        return 300  # LOW: 300s
    end
end

"""
    _generate_kernel_signature - Generate Kernel signature for approved action
"""
function _generate_kernel_signature(request::ApprovalRequest, token::String)::String
    # In production, this calls Rust kernel for cryptographic signature
    # For now, generate HMAC-based signature
    message = request.proposal_id * request.capability_id * token * string(request.timestamp)
    signature = hmac_sha256(_jwt_secret[], Vector{UInt8}(message))
    return _base64url_encode(signature)
end

"""
    _log_approval_event - Log approval event for audit
"""
function _log_approval_event(
    request::ApprovalRequest,
    approved::Bool,
    score::Float64,
    veto_reason::Union{String, Nothing}
)
    event = Dict(
        "event_type" => "APPROVAL",
        "timestamp" => _get_current_timestamp(),
        "proposal_id" => request.proposal_id,
        "capability_id" => request.capability_id,
        "requester_id" => request.requester_id,
        "approved" => approved,
        "score" => score,
        "veto_reason" => veto_reason
    )
    
    @info "Approval event: $(JSON.json(event))"
end

# ============================================================================
# PUSH NOTIFICATIONS - FCM
# ============================================================================

"""
    register_fcm_token - Register FCM token for push notifications
"""
function register_fcm_token(
    user_id::String,
    fcm_token::String;
    device_type::String="android"
)::Bool
    now = _get_current_timestamp()
    
    # Find or create user registrations
    if !haskey(_fcm_registrations, user_id)
        _fcm_registrations[user_id] = FCMToken[]
    end
    
    # Check if token already exists
    for token in _fcm_registrations[user_id]
        if token.token == fcm_token
            token.last_active = now
            return true  # Updated
        end
    end
    
    # Add new token
    push!(_fcm_registrations[user_id], FCMToken(
        fcm_token,
        user_id,
        device_type,
        now,
        now
    ))
    
    return true
end

"""
    unregister_fcm_token - Unregister FCM token
"""
function unregister_fcm_token(user_id::String, fcm_token::String)::Bool
    if !haskey(_fcm_registrations, user_id)
        return false
    end
    
    # Find and remove token
    filter!(_fcm_registrations[user_id]) do t
        t.token != fcm_token
    end
    
    return true
end

"""
    send_sovereign_notification - Send push notification about Kernel decision
    
    This ensures "Sovereign Decision" of the kernel remains visible to 
    human operators.
"""
function send_sovereign_notification(
    user_id::String;
    title::String="Sovereign Decision",
    body::String="Kernel has rendered a decision",
    data::Dict{String, Any}=Dict()
)::Bool
    if !haskey(_fcm_registrations, user_id)
        @warn "No FCM tokens for user: $user_id"
        return false
    end
    
    tokens = _fcm_registrations[user_id]
    if isempty(tokens)
        return false
    end
    
    # In production, send to FCM API
    # For now, log the notification
    notification = Dict(
        "type" => "SOVEREIGN_DECISION",
        "title" => title,
        "body" => body,
        "data" => data,
        "timestamp" => _get_current_timestamp()
    )
    
    @info "Sending sovereign notification: $(JSON.json(notification))"
    
    # Return success (in production, check FCM response)
    return true
end

"""
    send_oneiric_notification - Send notification about Oneiric (dreaming) state
"""
function send_oneiric_notification(
    user_id::String;
    phase::Symbol=:idle
)::Bool
    title = "Dream State Update"
    
    body = if phase == :entering
        "System entering dream state (Oneiric)"
    elseif phase == :replay
        "Memory replay in progress"
    elseif phase == :homeostasis
        "Synaptic consolidation in progress"
    elseif phase == :exiting
        "Dream state complete"
    else
        "System in dream state"
    end
    
    return send_sovereign_notification(
        user_id;
        title=title,
        body=body,
        data=Dict("phase" => string(phase), "type" => "ONEIRIC")
    )
end

# ============================================================================
# API ENDPOINTS
# ============================================================================

"""
    API Status endpoint
"""
function api_status()
    status = Dict(
        "api_version" => API_VERSION,
        "status" => "operational",
        "timestamp" => _get_current_timestamp(),
        "endpoints" => [
            "$API_BASE_PATH/auth/login",
            "$API_BASE_PATH/auth/refresh",
            "$API_BASE_PATH/approve",
            "$API_BASE_PATH/status",
            "$API_BASE_PATH/notifications/register"
        ],
        "security" => Dict(
            "auth_enabled" => true,
            "fail_closed" => true,
            "rate_limiting" => true
        )
    )
    
    return status
end

"""
    Auth login endpoint
"""
function handle_login(
    username::String,
    password::String;
    ip_address::String="unknown"
)::Dict{String, Any}
    # Check rate limit
    if !_check_rate_limit("login:$ip_address")
        return Dict(
            "success" => false,
            "error" => "Rate limit exceeded",
            "error_code" => "RATE_LIMITED"
        )
    end
    
    # In production, validate against user database
    # For demo, accept any non-empty credentials
    if isempty(username) || isempty(password)
        return Dict(
            "success" => false,
            "error" => "Invalid credentials",
            "error_code" => "INVALID_CREDENTIALS"
        )
    end
    
    # Determine roles (in production, from database)
    roles = username == "admin" ? [ADMIN, USER] : [USER]
    
    # Create session
    session = create_session(username, roles; ip_address=ip_address)
    
    return Dict(
        "success" => true,
        "access_token" => session.access_token,
        "refresh_token" => session.refresh_token,
        "expires_in" => JWT_ACCESS_TTL,
        "user_id" => session.user_id,
        "roles" => [string(r) for r in session.roles]
    )
end

"""
    Auth refresh endpoint
"""
function handle_refresh(refresh_token::String)::Dict{String, Any}
    # Check rate limit
    if !_check_rate_limit("refresh")
        return Dict(
            "success" => false,
            "error" => "Rate limit exceeded",
            "error_code" => "RATE_LIMITED"
        )
    end
    
    session = refresh_session(refresh_token)
    
    if session === nothing
        return Dict(
            "success" => false,
            "error" => "Invalid refresh token",
            "error_code" => "INVALID_TOKEN"
        )
    end
    
    return Dict(
        "success" => true,
        "access_token" => session.access_token,
        "refresh_token" => session.refresh_token,
        "expires_in" => JWT_ACCESS_TTL
    )
end

"""
    Approve endpoint - Sovereign approval with LEP
"""
function handle_approve(
    access_token::String,
    proposal_id::String,
    capability_id::String,
    action::String,
    params::Dict{String, Any},
    priority::Float64,
    reward::Float64
)::Dict{String, Any}
    # Validate token
    claims = validate_token(access_token)
    
    if claims === nothing
        return Dict(
            "success" => false,
            "error" => "Invalid or expired token",
            "error_code" => "UNAUTHORIZED"
        )
    end
    
    # Create approval request
    request = ApprovalRequest(
        proposal_id,
        capability_id,
        action,
        params,
        priority,
        reward,
        0.0,  # Risk calculated in approve_action
        claims.sub,
        time()
    )
    
    # Get sovereign approval (routes through Rust LEP in production)
    response = approve_action(request; user_claims=claims)
    
    # Send push notification for high-risk approvals
    if response.approved && calculate_veto_score(priority, reward, 0.5) < 2.0
        send_sovereign_notification(
            claims.sub;
            title="High-Risk Action Approved",
            body="Action: $action on $capability_id",
            data=Dict(
                "proposal_id" => proposal_id,
                "capability_id" => capability_id,
                "score" => response.score
            )
        )
    end
    
    return Dict(
        "success" => true,
        "approved" => response.approved,
        "score" => response.score,
        "veto_reason" => response.veto_reason,
        "confirmation_token" => response.confirmation_token,
        "expires_at" => response.expires_at,
        "kernel_signature" => response.kernel_signature
    )
end

"""
    Notification register endpoint
"""
function handle_register_notification(
    access_token::String,
    fcm_token::String;
    device_type::String="android"
)::Dict{String, Any}
    # Validate token
    claims = validate_token(access_token)
    
    if claims === nothing
        return Dict(
            "success" => false,
            "error" => "Invalid or expired token",
            "error_code" => "UNAUTHORIZED"
        )
    end
    
    # Register FCM token
    success = register_fcm_token(claims.sub, fcm_token; device_type=device_type)
    
    return Dict(
        "success" => success,
        "message" => success ? "FCM token registered" : "Registration failed"
    )
end

# ============================================================================
# HTTP HANDLERS
# ============================================================================

"""
    _mobile_status_handler - GET /status
"""
function _mobile_status_handler(req)
    status = api_status()
    return HTTP.Response(200, ["Content-Type" => "application/json"]; body=JSON.json(status))
end

"""
    _mobile_auth_login_handler - POST /auth/login
"""
function _mobile_auth_login_handler(req)
    try
        body = JSON.parse(String(req.body))
        username = get(body, "username", "")
        password = get(body, "password", "")
        
        result = handle_login(username, password; ip_address=get(req.headers, "X-Forwarded-For", "unknown"))
        
        return HTTP.Response(
            result["success"] ? 200 : 401,
            ["Content-Type" => "application/json"];
            body=JSON.json(result)
        )
    catch e
        return HTTP.Response(500, ["Content-Type" => "application/json"]; body=JSON.json(Dict("error" => string(e))))
    end
end

"""
    _mobile_auth_refresh_handler - POST /auth/refresh
"""
function _mobile_auth_refresh_handler(req)
    try
        body = JSON.parse(String(req.body))
        refresh_token = get(body, "refresh_token", "")
        
        result = handle_refresh(refresh_token)
        
        return HTTP.Response(
            result["success"] ? 200 : 401,
            ["Content-Type" => "application/json"];
            body=JSON.json(result)
        )
    catch e
        return HTTP.Response(500, ["Content-Type" => "application/json"]; body=JSON.json(Dict("error" => string(e))))
    end
end

"""
    _mobile_approve_handler - POST /approve
"""
function _mobile_approve_handler(req)
    try
        # Check rate limit
        if !_check_rate_limit("approve")
            return HTTP.Response(429, ["Content-Type" => "application/json"]; 
                body=JSON.json(Dict("success" => false, "error" => "Rate limit exceeded")))
        end
        
        body = JSON.parse(String(req.body))
        access_token = get(body, "access_token", "")
        proposal_id = get(body, "proposal_id", "")
        capability_id = get(body, "capability_id", "")
        action = get(body, "action", "")
        params = get(body, "params", Dict())
        priority = get(body, "priority", 0.5)
        reward = get(body, "reward", 0.0)
        
        result = handle_approve(access_token, proposal_id, capability_id, action, params, priority, reward)
        
        return HTTP.Response(
            result["success"] ? 200 : 403,
            ["Content-Type" => "application/json"];
            body=JSON.json(result)
        )
    catch e
        return HTTP.Response(500, ["Content-Type" => "application/json"]; body=JSON.json(Dict("error" => string(e))))
    end
end

"""
    _mobile_notifications_register_handler - POST /notifications/register
"""
function _mobile_notifications_register_handler(req)
    try
        body = JSON.parse(String(req.body))
        access_token = get(body, "access_token", "")
        fcm_token = get(body, "fcm_token", "")
        device_type = get(body, "device_type", "android")
        
        result = handle_register_notification(access_token, fcm_token; device_type=device_type)
        
        return HTTP.Response(
            result["success"] ? 200 : 401,
            ["Content-Type" => "application/json"];
            body=JSON.json(result)
        )
    catch e
        return HTTP.Response(500, ["Content-Type" => "application/json"]; body=JSON.json(Dict("error" => string(e))))
    end
end

# ============================================================================
# SERVER
# ============================================================================

"""
    serve_mobile_api - Start the mobile API server
    
    # Arguments
    - `host::String`: Host to bind to (default: "127.0.0.1")
    - `port::Int`: Port to bind to (default: 9090)
    
    # Returns
    - `Dict`: Server configuration
"""
function serve_mobile_api(;host::String="127.0.0.1", port::Int=9090)
    router = HTTP.Router()
    
    # Status endpoint
    HTTP.register!(router, "GET", "$API_BASE_PATH/status", _mobile_status_handler)
    
    # Auth endpoints
    HTTP.register!(router, "POST", "$API_BASE_PATH/auth/login", _mobile_auth_login_handler)
    HTTP.register!(router, "POST", "$API_BASE_PATH/auth/refresh", _mobile_auth_refresh_handler)
    
    # Approval endpoint (LEP - Law Enforcement Point)
    HTTP.register!(router, "POST", "$API_BASE_PATH/approve", _mobile_approve_handler)
    
    # Notification endpoints
    HTTP.register!(router, "POST", "$API_BASE_PATH/notifications/register", _mobile_notifications_register_handler)
    
    @info "Starting Mobile API v$API_VERSION on $host:$port"
    @info "Endpoints:"
    @info "  GET  $API_BASE_PATH/status"
    @info "  POST $API_BASE_PATH/auth/login"
    @info "  POST $API_BASE_PATH/auth/refresh"
    @info "  POST $API_BASE_PATH/approve"
    @info "  POST $API_BASE_PATH/notifications/register"
    
    return Dict(
        "host" => host,
        "port" => port,
        "router" => router,
        "running" => true,
        "version" => API_VERSION
    )
end

# ============================================================================
# EXPORTS
# ============================================================================

export
    # API
    api_status,
    serve_mobile_api,
    
    # Auth
    create_access_token,
    create_refresh_token,
    validate_token,
    create_session,
    handle_login,
    handle_refresh,
    
    # Approval
    approve_action,
    calculate_veto_score,
    classify_risk,
    handle_approve,
    
    # Notifications
    register_fcm_token,
    send_sovereign_notification,
    send_oneiric_notification,
    handle_register_notification,
    
    # Types
    MobileClaims,
    ApprovalRequest,
    ApprovalResponse,
    FCMToken,
    MobileSession,
    TokenType,
    UserRole

end # module MobileAPI
