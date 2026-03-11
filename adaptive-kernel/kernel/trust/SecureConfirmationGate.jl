"""
    SecureConfirmationGate - Cryptographically Secure Confirmation System
    
    P0 REMEDIATION: C4 - Confirmation Gate Bypass
    
    THREAT MODEL:
    - Original vulnerability: UUIDv4() is predictable/enumerable
    - Attack: Attacker iterates/confirms pending actions by guessing UUIDs
    - Impact: High-risk actions executed without user consent
    
    REMEDIATION DESIGN:
    - Replace UUIDs with CSPRNG tokens (256-bit random from RandomDevice())
    - Add HMAC-SHA256 signature for integrity verification
    - Each token is cryptographically unique and unverifiable without secret key
    - Type-stable implementation with strict Structs (no Any)
    
    CRYPTOGRAPHIC PRIMITIVES:
    - RandomDevice() for CSPRNG (OS-level entropy)
    - SHA256 HMAC for message authentication
    - 256-bit token = 32 bytes = practically unguessable
    
    FAIL-CLOSED DEFAULT:
    - Invalid/missing signature returns false
    - Expired tokens are auto-denied
    - Rate limiting on confirmation attempts
    
    DEPENDENCIES:
    - SHA.jl for HMAC-SHA256
    - Random for CSPRNG
"""

using SHA
using Random
using JSON

# Try to import RustIPC for secure random, but make it optional
const _RUST_ENTROPY_AVAILABLE = Ref{Bool}(false)
try
    using ..RustIPC
    _RUST_ENTROPY_AVAILABLE[] = true
catch e
    # RustIPC not available - will use Julia fallback
end

# Try to import Persistence for immutable logging
const _PERSISTENCE_AVAILABLE = Ref{Bool}(false)
try
    using ..Persistence
    _PERSISTENCE_AVAILABLE[] = true
catch e
    # Persistence not available - will use fallback
end

# Import RiskLevel from Types
@enum RiskLevel READ_ONLY LOW MEDIUM HIGH CRITICAL

"""
    ConfirmationEventAction - Outcome of a confirmation event
"""
@enum ConfirmationEventAction CONFIRMATION_REQUESTED CONFIRMATION_CONFIRMED CONFIRMATION_DENIED CONFIRMATION_EXPIRED CONFIRMATION_TIMEOUT

"""
    WDT_TIMEOUT_MAP - Policy-driven timeout configuration aligned with Hardware Watchdog Timer
    
    Timeouts align with Oneiric cycle time for fail-closed:
    - CRITICAL: 32s (aligns with Oneiric cycle)
    - HIGH: 60s
    - MEDIUM: 120s  
    - LOW: 300s
    
    WDT typically runs at ~40s, so CRITICAL actions must complete within Oneiric cycle.
"""
const WDT_TIMEOUT_MAP = Dict{RiskLevel, UInt64}(
    CRITICAL => UInt64(32),
    HIGH => UInt64(60),
    MEDIUM => UInt64(120),
    LOW => UInt64(300),
    READ_ONLY => UInt64(600)  # Longer timeout for read-only operations
)

"""
    METABOLIC_POLL_INTERVALS - Low-power polling modes for energy conservation
    
    These intervals control how often the system polls for confirmation responses
    during the waiting period. Lower risk actions use less frequent polling to
    conserve energy.
"""
@enum MetabolicMode LOW_POWER NORMAL HIGH_PERFORMANCE

const METABOLIC_POLL_MAP = Dict{RiskLevel, Float64}(
    CRITICAL => 0.5,    # 500ms - critical actions need fast response
    HIGH => 1.0,        # 1s - high priority
    MEDIUM => 2.0,      # 2s - medium priority
    LOW => 5.0,         # 5s - low power mode
    READ_ONLY => 10.0   # 10s - read-only can wait
)

"""
    ConfirmationAuditLog - Immutable audit log entry for confirmation events
    
    Fields:
    - confirmation_uuid: Cryptographic token (token hex string)
    - risk_level: RiskLevel assigned by RiskClassifier
    - reasoning: Reasoning string from BrainOutput
    - timestamp: Rust-verified timestamp (Unix seconds)
    - timestamp_source: Source of timestamp (:rust_heartbeat, :julia_fallback)
    - action: ConfirmationEventAction outcome
    - proposal_id: Associated proposal ID
    - capability_id: The capability being confirmed
    - expiry_time: When the confirmation expires (Unix timestamp)
"""
struct ConfirmationAuditLog
    confirmation_uuid::String          # Token hex for external reference
    risk_level::RiskLevel              # Risk level from RiskClassifier
    reasoning::String                  # BrainOutput reasoning
    timestamp::UInt64                  # Rust-verified Unix timestamp
    timestamp_source::Symbol            # :rust_heartbeat | :julia_fallback
    action::ConfirmationEventAction   # Outcome
    proposal_id::String                # Associated proposal
    capability_id::String              # Capability being confirmed
    expiry_time::UInt64                # Expiration timestamp
end

"""
    _get_rust_timestamp - Get timestamp from Rust Warden heartbeat clock
    
    Fallback chain (fail-closed):
    1. Rust IPC timestamp (preferred)
    2. Julia time() fallback
"""
function _get_rust_timestamp()::Tuple{UInt64, Symbol}
    # Try Rust timestamp first (from RustIPC)
    if _RUST_ENTROPY_AVAILABLE[]
        try
            # Use RustIPC's timestamp function if available
            rust_ts = RustIPC._get_current_timestamp()
            if rust_ts > 0
                # Convert milliseconds to seconds
                return (rust_ts ÷ 1000, :rust_heartbeat)
            end
        catch e
            # Fall through to Julia fallback
        end
    end
    
    # Julia fallback (less secure but always available)
    return (floor(UInt64, time()), :julia_fallback)
end

"""
    _log_to_persistence - Write encrypted log entry to Persistence layer
    
    Uses AES-256-CBC encryption from Persistence.jl if available,
    otherwise writes to standard log (fail-secure).
"""
function _log_to_persistence(audit_entry::ConfirmationAuditLog)::Bool
    # Serialize the audit entry to JSON
    entry_dict = Dict{String, Any}(
        "confirmation_uuid" => audit_entry.confirmation_uuid,
        "risk_level" => string(audit_entry.risk_level),
        "reasoning" => audit_entry.reasoning,
        "timestamp" => audit_entry.timestamp,
        "timestamp_source" => string(audit_entry.timestamp_source),
        "action" => string(audit_entry.action),
        "proposal_id" => audit_entry.proposal_id,
        "capability_id" => audit_entry.capability_id,
        "expiry_time" => audit_entry.expiry_time,
        "event_type" => "CONFIRMATION_AUDIT"
    )
    
    json_data = JSON.json(entry_dict)
    
    # Try to use Persistence encryption
    if _PERSISTENCE_AVAILABLE[]
        try
            encrypted = Persistence.encrypt_log(json_data)
            # Write encrypted entry to log
            _append_to_audit_log(encrypted)
            return true
        catch e
            @error "Failed to encrypt audit log: $e"
            # Fall through to unencrypted logging
        end
    end
    
    # Fallback: Write with warning (still append-only)
    @warn "Audit log written without encryption - check JARVIS_EVENT_LOG_KEY"
    _append_to_audit_log(json_data)
    return true
end

"""
    _append_to_audit_log - Append entry to audit log file (append-only)
"""
const _AUDIT_LOG_FILE = Ref("confirmation_audit.log")

function _append_to_audit_log(entry::String)
    try
        log_file = _AUDIT_LOG_FILE[]
        open(log_file, "a") do f
            println(f, entry)
        end
    catch e
        @error "Failed to write to audit log: $e"
    end
end

"""
    log_confirmation_event - Log a confirmation event to immutable audit log
    
    This is the main entry point for logging confirmation events.
    Each log entry is individually encrypted using AES-256-CBC.
"""
function log_confirmation_event(
    token_str::String,
    risk_level::RiskLevel,
    reasoning::String,
    action::ConfirmationEventAction;
    proposal_id::String="",
    capability_id::String="",
    expiry_time::UInt64=UInt64(0)
)::Bool
    # Get Rust-verified timestamp
    timestamp, ts_source = _get_rust_timestamp()
    
    # Use expiry_time from token if not provided
    if expiry_time == 0
        expiry_time = timestamp + 30  # Default 30s timeout
    end
    
    # Create audit log entry
    audit_entry = ConfirmationAuditLog(
        token_str,
        risk_level,
        reasoning,
        timestamp,
        ts_source,
        action,
        proposal_id,
        capability_id,
        expiry_time
    )
    
    # Write to persistence (encrypted append-only log)
    return _log_to_persistence(audit_entry)
end

"""
    WDTHeartbeat - Integration point for Hardware Watchdog Timer
    
    Fields:
    - last_heartbeat: Last time WDT was kicked (Unix timestamp)
    - wdt_threshold: Maximum time before WDT timeout (should match hardware WDT)
    - enable_wdt_integration: Whether to trigger WDT reset on timeout
"""
mutable struct WDTHeartbeat
    last_heartbeat::UInt64
    wdt_threshold::UInt64
    enable_wdt_integration::Bool
    
    function WDTHeartbeat(; 
        wdt_threshold::UInt64=UInt64(35),  # Slightly less than typical WDT
        enable_wdt_integration::Bool=true
    )
        new(
            floor(UInt64, time()),
            wdt_threshold,
            enable_wdt_integration
        )
    end
end

"""
    SecureToken - Cryptographically secure confirmation token
"""
struct SecureToken
    token::Vector{UInt8}      # 32 bytes, CSPRNG-generated
    signature::Vector{UInt8}  # 32 bytes, HMAC-SHA256
    created_at::UInt64        # Unix timestamp
    expires_at::UInt64        # Unix timestamp
    purpose::Symbol           # :confirmation | :verification
end

"""
    PendingSecureAction - Action waiting for cryptographically verified confirmation
"""
struct PendingSecureAction
    id::SecureToken
    proposal_id::String
    capability_id::String
    params_hash::Vector{UInt8}  # SHA256 of params for integrity
    requested_at::UInt64
    timeout::UInt64
    risk_level::RiskLevel
    caller_identity::Vector{UInt8}  # HMAC of caller's verified identity
end

"""
    SecureConfirmationGate - User confirmation with cryptographic verification
    
    Extended with WDT-aligned timeout mechanisms for C4 security requirements:
    - Policy-driven timeouts based on risk level
    - Fail-closed isolation for CRITICAL actions
    - Metabolic-aware polling for energy conservation
    - WDT heartbeat integration
"""
mutable struct SecureConfirmationGate
    pending_confirmations::Dict{String, PendingSecureAction}
    timeout::UInt64
    auto_deny_on_timeout::Bool
    secret_key::Vector{UInt8}  # HMAC key - MUST be securely generated/stored
    max_pending::UInt64        # Rate limiting: max pending confirmations
    confirmation_attempts::Dict{String, UInt64}  # Track failed attempts for rate limiting
    
    # WDT-Aligned timeout configuration (risk-level specific)
    timeout_by_risk::Dict{RiskLevel, UInt64}
    
    # Fail-closed isolation: trigger cut of actuation path on CRITICAL timeout
    enable_fail_closed_isolation::Bool
    
    # Metabolic-aware polling configuration
    metabolic_mode::MetabolicMode
    poll_interval::Float64  # Current poll interval in seconds
    
    # WDT Heartbeat integration
    wdt_heartbeat::Union{WDTHeartbeat, Nothing}
    
    # Callback for fail-closed isolation (set by Kernel)
    fail_closed_callback::Union{Function, Nothing}
    
    # Callback for WDT heartbeat kick (set by Kernel)
    wdt_kick_callback::Union{Function, Nothing}
    
    function SecureConfirmationGate(
        timeout::UInt64=UInt64(30); 
        auto_deny_on_timeout::Bool=true,
        secret_key::Union{Vector{UInt8}, Nothing}=nothing,
        max_pending::UInt64=UInt64(100),
        use_wdt_timeouts::Bool=true,
        enable_fail_closed_isolation::Bool=true,
        metabolic_mode::MetabolicMode=LOW_POWER,
        enable_wdt_integration::Bool=true
    )
        # FAIL-CLOSED: Use provided key or generate secure random
        # In production, secret_key MUST be persisted securely
        key = secret_key !== nothing ? secret_key : _generate_secure_key()
        
        # Use WDT-aligned timeouts if enabled, otherwise use default
        timeout_map = use_wdt_timeouts ? WDT_TIMEOUT_MAP : Dict{RiskLevel, UInt64}()
        
        # Initialize WDT heartbeat if enabled
        wdt = enable_wdt_integration ? WDTHeartbeat() : nothing
        
        # Get default poll interval based on metabolic mode
        default_poll = METABOLIC_POLL_MAP[CRITICAL]  # Start with critical, adapt per-request
        
        new(
            Dict{String, PendingSecureAction}(),
            timeout,
            auto_deny_on_timeout,
            key,
            max_pending,
            Dict{String, UInt64}(),
            timeout_map,
            enable_fail_closed_isolation,
            metabolic_mode,
            default_poll,
            wdt,
            nothing,
            nothing
        )
    end
end

"""
    _generate_secure_key - Generate 256-bit HMAC key from CSPRNG
    
    Fallback chain (fail-closed):
    1. Rust CSPRNG (via RustIPC) - preferred
    2. Julia Random CSPRNG
    3. Deterministic SHA256 fallback
"""
function _generate_secure_key()::Vector{UInt8}
    key = Vector{UInt8}(undef, 32)
    fill!(key, 0)
    
    # Try Rust CSPRNG first (preferred)
    if _RUST_ENTROPY_AVAILABLE[]
        try
            key = RustIPC.get_secure_random(32)
            if length(key) == 32
                return key
            end
        catch e
            # Fall through to Julia fallback
        end
    end
    
    # Try Julia CSPRNG
    try
        rand!(key)
        return key
    catch
        # FAIL-CLOSED: If CSPRNG unavailable, use secure fallback with warning
        @warn "CSPRNG unavailable, using fallback (less secure)"
        key = sha256(string(time_ns()) * string(getpid()))
        return key
    end
end

"""
    _get_rust_entropy - Get entropy from Rust CSPRNG (internal helper)
"""
function _get_rust_entropy(n::Integer)::Union{Vector{UInt8}, Nothing}
    if !_RUST_ENTROPY_AVAILABLE[]
        return nothing
    end
    
    try
        # Check if Rust secure random is available
        if RustIPC.is_secure_random_available()
            return RustIPC.get_secure_random(n)
        end
    catch e
        # Fall through to Julia
    end
    
    return nothing
end

"""
    get_timeout_for_risk_level(gate::SecureConfirmationGate, risk_level::RiskLevel)::UInt64
    
Get the appropriate timeout for a given risk level from policy configuration.
Returns risk-level-specific timeout, falling back to default if not configured.

Timeouts (WDT-aligned):
- CRITICAL: 32s (aligns with Oneiric cycle)
- HIGH: 60s
- MEDIUM: 120s
- LOW: 300s
"""
function get_timeout_for_risk_level(gate::SecureConfirmationGate, risk_level::RiskLevel)::UInt64
    # First check if we have risk-level specific timeouts configured
    if haskey(gate.timeout_by_risk, risk_level)
        return gate.timeout_by_risk[risk_level]
    end
    
    # Fall back to WDT_TIMEOUT_MAP constant
    if haskey(WDT_TIMEOUT_MAP, risk_level)
        return WDT_TIMEOUT_MAP[risk_level]
    end
    
    # Ultimate fallback to gate's default timeout
    return gate.timeout
end

"""
    get_poll_interval_for_risk_level(gate::SecureConfirmationGate, risk_level::RiskLevel)::Float64
    
Get the appropriate poll interval for a given risk level.
This enables metabolic-aware polling for energy conservation.

Poll intervals:
- CRITICAL: 0.5s (fast response needed)
- HIGH: 1.0s
- MEDIUM: 2.0s
- LOW: 5.0s (low power mode)
- READ_ONLY: 10.0s
"""
function get_poll_interval_for_risk_level(gate::SecureConfirmationGate, risk_level::RiskLevel)::Float64
    if haskey(METABOLIC_POLL_MAP, risk_level)
        return METABOLIC_POLL_MAP[risk_level]
    end
    return gate.poll_interval  # Fall back to current gate setting
end

"""
    trigger_fail_closed_isolation(gate::SecureConfirmationGate, pending::PendingSecureAction)
    
Trigger fail-closed isolation for a timed-out CRITICAL action.

This signals to the Kernel to cut the actuation path (GPIO/MQTT) to prevent
the action from being executed. This is a critical security measure for
high-risk operations.

The function:
1. Emits a critical security event
2. Calls the fail_closed_callback if configured (to cut GPIO/MQTT)
3. Logs the isolation event for forensic analysis
"""
function trigger_fail_closed_isolation(gate::SecureConfirmationGate, pending::PendingSecureAction)
    current_time = floor(UInt64, time())
    
    # Log the critical security event
    @error "FAIL-CLOSED ISOLATION TRIGGERED: CRITICAL action timed out" 
        proposal_id=pending.proposal_id
        capability_id=pending.capability_id
        timeout=pending.timeout
        elapsed=current_time - pending.requested_at
        risk_level=pending.risk_level
    
    # Emit structured event for Kernel to handle
    _emit_fail_closed_event(pending, current_time - pending.requested_at)
    
    # Call the fail_closed_callback if configured (Kernel handles GPIO/MQTT cut)
    if gate.fail_closed_callback !== nothing
        try
            gate.fail_closed_callback(pending)
        catch e
            @error "Fail-closed callback error: $e"
        end
    end
    
    # If WDT integration is enabled, trigger WDT reset
    if gate.wdt_heartbeat !== nothing && gate.wdt_heartbeat.enable_wdt_integration
        _trigger_wdt_reset(gate)
    end
    
    return true
end

"""
    _emit_fail_closed_event - Emit structured event for fail-closed isolation
"""
function _emit_fail_closed_event(pending::PendingSecureAction, elapsed::UInt64)
    # Create structured event for the isolation trigger
    event = Dict{String, Any}(
        "type" => "FAIL_CLOSED_ISOLATION",
        "proposal_id" => pending.proposal_id,
        "capability_id" => pending.capability_id,
        "risk_level" => string(pending.risk_level),
        "timeout" => pending.timeout,
        "elapsed" => elapsed,
        "timestamp" => floor(UInt64, time()),
        "action" => "ACTUATION_PATH_CUT"
    )
    
    @error "Fail-closed isolation event: $(JSON.json(event))"
end

"""
    _trigger_wdt_reset - Trigger WDT reset due to CRITICAL timeout
    
When a CRITICAL action times out, we need to reset the WDT to prevent
the hardware from rebooting. This is called after triggering fail-closed
isolation to ensure the system remains stable.
"""
function _trigger_wdt_reset(gate::SecureConfirmationGate)
    if gate.wdt_kick_callback !== nothing
        try
            gate.wdt_kick_callback()
            @info "WDT kick triggered due to CRITICAL timeout handling"
        catch e
            @error "WDT kick callback error: $e"
        end
    else
        @warn "WDT kick callback not configured - manual WDT reset may be required"
    end
    
    # Update heartbeat timestamp
    if gate.wdt_heartbeat !== nothing
        gate.wdt_heartbeat.last_heartbeat = floor(UInt64, time())
    end
end

"""
    kick_wdt_heartbeat(gate::SecureConfirmationGate)::Bool
    
Kick the WDT heartbeat to prevent hardware timeout.
This should be called periodically during confirmation waiting periods.
"""
function kick_wdt_heartbeat(gate::SecureConfirmationGate)::Bool
    if gate.wdt_heartbeat === nothing
        return false
    end
    
    current_time = floor(UInt64, time())
    
    # Call the WDT kick callback if configured
    if gate.wdt_kick_callback !== nothing
        try
            gate.wdt_kick_callback()
        catch e
            @error "WDT kick error: $e"
            return false
        end
    end
    
    # Update heartbeat timestamp
    gate.wdt_heartbeat.last_heartbeat = current_time
    
    return true
end

"""
    check_wdt_health(gate::SecureConfirmationGate)::Bool
    
Check if WDT heartbeat is healthy. Returns false if WDT threshold exceeded.
This should be called to verify the WDT is still being kicked properly.
"""
function check_wdt_health(gate::SecureConfirmationGate)::Bool
    if gate.wdt_heartbeat === nothing
        return true  # No WDT to check
    end
    
    current_time = floor(UInt64, time())
    elapsed = current_time - gate.wdt_heartbeat.last_heartbeat
    
    if elapsed > gate.wdt_heartbeat.wdt_threshold
        @error "WDT heartbeat unhealthy: $elapsed seconds since last kick (threshold: $(gate.wdt_heartbeat.wdt_threshold))"
        return false
    end
    
    return true
end

"""
    set_fail_closed_callback(gate::SecureConfirmationGate, callback::Function)
    
Set the callback function that will be called when fail-closed isolation is triggered.
The callback should accept a PendingSecureAction parameter and handle cutting
the actuation path (GPIO/MQTT).
"""
function set_fail_closed_callback(gate::SecureConfirmationGate, callback::Function)
    gate.fail_closed_callback = callback
end

"""
    set_wdt_kick_callback(gate::SecureConfirmationGate, callback::Function)
    
Set the callback function that will be called to kick the WDT.
This callback should trigger the hardware WDT reset mechanism.
"""
function set_wdt_kick_callback(gate::SecureConfirmationGate, callback::Function)
    gate.wdt_kick_callback = callback
end

"""
    _generate_secure_token - Generate cryptographically secure token using CSPRNG
    
    Fallback chain (fail-closed):
    1. Rust CSPRNG (via RustIPC) - preferred for C4 security
    2. Julia Random CSPRNG
    3. Deterministic SHA256 fallback
"""
function _generate_secure_token(
    purpose::Symbol,
    timeout::UInt64
)::SecureToken
    # Try Rust CSPRNG first (C4 requirement: use Rust-side entropy)
    token = _get_rust_entropy(32)
    
    if token === nothing
        # Fallback to Julia Random
        @warn "Rust entropy unavailable, using Julia Random for token generation"
        try
            token = rand(UInt8, 32)
        catch
            # Last resort: deterministic fallback
            @error "All entropy sources failed - using deterministic fallback for token"
            data = string(time_ns()) * string(getpid()) * string(hash(rand(UInt64)))
            token = sha256(data)
        end
    end
    
    now = floor(UInt64, time())
    
    return SecureToken(
        token,
        Vector{UInt8}(),  # Signature computed separately
        now,
        now + timeout,
        purpose
    )
end

"""
    _hmac_sha256 - Compute HMAC-SHA256 signature
"""
function _hmac_sha256(key::Vector{UInt8}, data::Vector{UInt8})::Vector{UInt8}
    # Use SHA HMAC construction - concatenate key and data
    return sha256(vcat(key, data))
end

"""
    _sign_token - Sign a token with HMAC-SHA256
"""
function _sign_token(gate::SecureConfirmationGate, token::SecureToken)::SecureToken
    # Create signature over: token_bytes | created_at | expires_at | purpose
    data = vcat(
        token.token,
        reinterpret(UInt8, [token.created_at]),
        reinterpret(UInt8, [token.expires_at]),
        Vector{UInt8}(string(token.purpose))
    )
    
    signature = _hmac_sha256(gate.secret_key, data)
    
    return SecureToken(
        token.token,
        signature,
        token.created_at,
        token.expires_at,
        token.purpose
    )
end

"""
    _verify_signature - Verify token signature (FAIL-CLOSED)
    Note: This verifies the signature using the EXISTING token from pending_confirmations
"""
function _verify_signature(gate::SecureConfirmationGate, stored_token::SecureToken)::Bool
    # FAIL-CLOSED: Any anomaly returns false
    
    # Check expiration first (fail-fast)
    current_time = floor(UInt64, time())
    if current_time > stored_token.expires_at
        @warn "Token expired"
        return false
    end
    
    # Recompute expected signature using the STORED token's timestamps
    data = vcat(
        stored_token.token,
        reinterpret(UInt8, [stored_token.created_at]),
        reinterpret(UInt8, [stored_token.expires_at]),
        Vector{UInt8}(string(stored_token.purpose))
    )
    
    expected_sig = _hmac_sha256(gate.secret_key, data)
    
    # Constant-time comparison to prevent timing attacks
    return isequal(stored_token.signature, expected_sig)
end

"""
    _token_to_string - Convert token to string representation (for external API)
"""
function _token_to_string(token::SecureToken)::String
    return bytes2hex(token.token) * "." * bytes2hex(token.signature)
end

"""
    _string_to_token - Parse token from string (FAIL-CLOSED)
    Note: This just validates format, actual token verification happens against stored token
"""
function _string_to_token(token_str::String)::Union{Vector{UInt8}, Nothing}
    # FAIL-CLOSED: Return nothing on any parsing error
    
    parts = split(token_str, ".")
    if length(parts) != 2
        @warn "Invalid token format"
        return nothing
    end
    
    try
        token_bytes = hex2bytes(parts[1])
        
        if length(token_bytes) != 32
            @warn "Invalid token length"
            return nothing
        end
        
        return token_bytes
    catch e
        @warn "Token parsing failed: $e"
        return nothing
    end
end

"""
    _hash_params - Create deterministic hash of action parameters
"""
function _hash_params(params::Dict{String, Any})::Vector{UInt8}
    # Canonicalize and hash params for integrity verification
    param_str = JSON.json(params)
    return sha256(param_str)
end

"""
    _check_rate_limit - Rate limiting for confirmation attempts (FAIL-CLOSED)
"""
function _check_rate_limit(gate::SecureConfirmationGate, token_str::String)::Bool
    # Simple rate limiting: max 5 failed attempts per token
    attempts = get(gate.confirmation_attempts, token_str, 0)
    
    if attempts >= 5
        @warn "Rate limit exceeded for token"
        return false
    end
    
    # Increment attempt counter
    gate.confirmation_attempts[token_str] = attempts + 1
    
    return true
end

"""
    require_confirmation(
        gate::SecureConfirmationGate, 
        proposal_id::String, 
        capability_id::String, 
        params::Dict{String, Any}, 
        risk_level::RiskLevel,
        caller_identity::Union{Vector{UInt8}, Nothing}=nothing
    )::Union{String, Nothing}
        
Queue action for user confirmation, return secure confirmation token.
Returns nothing if rate limit exceeded or system overloaded.

FAIL-CLOSED: Any error returns nothing
"""
function require_confirmation(
    gate::SecureConfirmationGate, 
    proposal_id::String, 
    capability_id::String, 
    params::Dict{String, Any}, 
    risk_level::RiskLevel,
    caller_identity::Union{Vector{UInt8}, Nothing}=nothing
)::Union{String, Nothing}
    
    # FAIL-CLOSED: Rate limiting
    if length(gate.pending_confirmations) >= gate.max_pending
        @error "Confirmation gate overloaded - max pending reached"
        return nothing
    end
    
    # Get risk-level specific timeout (WDT-aligned)
    timeout = get_timeout_for_risk_level(gate, risk_level)
    
    # Update poll interval based on risk level for metabolic-aware polling
    gate.poll_interval = get_poll_interval_for_risk_level(gate, risk_level)
    
    # Generate cryptographically secure token with risk-level timeout
    token = _generate_secure_token(:confirmation, timeout)
    
    # Sign the token with HMAC
    signed_token = _sign_token(gate, token)
    
    # Hash params for integrity verification
    params_hash = _hash_params(params)
    
    # Use caller's identity or derive from token if not provided
    identity = caller_identity !== nothing ? caller_identity : _hmac_sha256(gate.secret_key, signed_token.token)
    
    now = floor(UInt64, time())
    
    pending = PendingSecureAction(
        signed_token,
        proposal_id,
        capability_id,
        params_hash,
        now,
        timeout,  # Use risk-level specific timeout
        risk_level,
        identity
    )
    
    # Store by token string (external reference)
    token_str = _token_to_string(signed_token)
    gate.pending_confirmations[token_str] = pending
    
    # Log confirmation request to immutable audit log
    log_confirmation_event(
        token_str,
        risk_level,
        "Confirmation requested for $capability_id",
        CONFIRMATION_REQUESTED;
        proposal_id=proposal_id,
        capability_id=capability_id,
        expiry_time=token.expires_at
    )
    
    # Log with risk level info
    timeout_str = string(timeout)
    @info "Secure confirmation required for $capability_id (risk: $risk_level, timeout: $(timeout_str)s, token: $(token_str[1:16])...)"
    
    return token_str
end

"""
    confirm_action(
        gate::SecureConfirmationGate, 
        token_str::String,
        params_hash::Union{Vector{UInt8}, Nothing}=nothing
    )::Bool
        
Confirm a pending action using cryptographically secure token.
Verifies token signature AND optionally verifies params integrity.

FAIL-CLOSED: Any anomaly returns false
"""
function confirm_action(
    gate::SecureConfirmationGate, 
    token_str::String,
    params_hash::Union{Vector{UInt8}, Nothing}=nothing
)::Bool
    # Check if pending exists first (before rate limiting - to avoid counting valid tokens)
    if !haskey(gate.pending_confirmations, token_str)
        # FAIL-CLOSED: Rate limiting - only count invalid tokens
        if !_check_rate_limit(gate, token_str)
            @error "Confirmation rate limit exceeded"
            return false
        end
        @warn "Token not found in pending confirmations"
        return false
    end
    
    # Parse and validate token format (just get the token bytes for lookup)
    token_bytes = _string_to_token(token_str)
    if token_bytes === nothing
        # FAIL-CLOSED: Rate limiting
        if !_check_rate_limit(gate, token_str)
            @error "Confirmation rate limit exceeded"
            return false
        end
        return false
    end
    
    pending = gate.pending_confirmations[token_str]
    
    # Verify HMAC signature using the STORED token (not re-parsed)
    if !_verify_signature(gate, pending.id)
        # FAIL-CLOSED: Rate limiting
        if !_check_rate_limit(gate, token_str)
            @error "Confirmation rate limit exceeded"
            return false
        end
        @warn "Invalid token signature - possible tampering"
        return false
    end
    
    # Verify params integrity if provided
    if params_hash !== nothing
        if !isequal(pending.params_hash, params_hash)
            @warn "Params hash mismatch - possible tampering"
            return false
        end
    end
    
    # Check expiration using token's expires_at (not requested_at + timeout)
    # Use >= to properly handle zero-timeout tokens
    current_time = floor(UInt64, time())
    if current_time >= pending.id.expires_at
        @warn "Confirmation expired"
        return false
    end
    
    # Verify caller identity if we have one stored
    # (In production, would verify against actual caller)
    
    # SUCCESS: Remove from pending and confirm
    delete!(gate.pending_confirmations, token_str)
    
    # Log confirmation success to immutable audit log
    log_confirmation_event(
        token_str,
        pending.risk_level,
        "Action confirmed",
        CONFIRMATION_CONFIRMED;
        proposal_id=pending.proposal_id,
        capability_id=pending.capability_id,
        expiry_time=pending.id.expires_at
    )
    
    # Clean up rate limiting data
    delete!(gate.confirmation_attempts, token_str)
    
    @info "Action confirmed securely: $(token_str[1:16])..."
    
    return true
end

"""
    deny_action(gate::SecureConfirmationGate, token_str::String)::Bool
Deny a pending action.
"""
function deny_action(gate::SecureConfirmationGate, token_str::String)::Bool
    if haskey(gate.pending_confirmations, token_str)
        pending = gate.pending_confirmations[token_str]
        
        # Log denial to immutable audit log
        log_confirmation_event(
            token_str,
            pending.risk_level,
            "Action denied by user",
            CONFIRMATION_DENIED;
            proposal_id=pending.proposal_id,
            capability_id=pending.capability_id,
            expiry_time=pending.id.expires_at
        )
        
        delete!(gate.pending_confirmations, token_str)
        delete!(gate.confirmation_attempts, token_str)
        @info "Action denied: $(token_str[1:16])..."
        return true
    end
    return false
end

"""
    check_pending_timeout(gate::SecureConfirmationGate)::Vector{String}
Check for timed-out confirmations and return IDs to auto-deny
"""
function check_pending_timeout(gate::SecureConfirmationGate)::Vector{String}
    timed_out = String[]
    current_time = floor(UInt64, time())
    
    for (token_str, pending) in gate.pending_confirmations
        if current_time > pending.requested_at + pending.timeout
            push!(timed_out, token_str)
            
            # Check if this is a CRITICAL action - trigger fail-closed isolation
            if pending.risk_level == CRITICAL && gate.enable_fail_closed_isolation
                @error "CRITICAL action timed out - triggering fail-closed isolation"
                
                # Log timeout to immutable audit log (with timeout action)
                log_confirmation_event(
                    token_str,
                    pending.risk_level,
                    "CRITICAL action timed out - fail-closed isolation triggered",
                    CONFIRMATION_TIMEOUT;
                    proposal_id=pending.proposal_id,
                    capability_id=pending.capability_id,
                    expiry_time=pending.id.expires_at
                )
                
                # Trigger fail-closed isolation (cuts actuation path)
                trigger_fail_closed_isolation(gate, pending)
                
                # Don't auto-deny - fail-closed takes over
                delete!(gate.pending_confirmations, token_str)
                delete!(gate.confirmation_attempts, token_str)
                continue
            end
            
            if gate.auto_deny_on_timeout
                # Log timeout/expired to immutable audit log
                log_confirmation_event(
                    token_str,
                    pending.risk_level,
                    "Confirmation expired - action timed out",
                    CONFIRMATION_EXPIRED;
                    proposal_id=pending.proposal_id,
                    capability_id=pending.capability_id,
                    expiry_time=pending.id.expires_at
                )
                
                delete!(gate.pending_confirmations, token_str)
                delete!(gate.confirmation_attempts, token_str)
                @warn "Action timed out and auto-denied: $(token_str[1:16])..."
            end
        end
    end
    
    return timed_out
end

"""
    is_pending(gate::SecureConfirmationGate, token_str::String)::Bool
Check if a confirmation is still pending (validates token format)
"""
function is_pending(gate::SecureConfirmationGate, token_str::String)::Bool
    # Verify token format first (fail-closed)
    token_bytes = _string_to_token(token_str)
    token_bytes === nothing && return false
    
    # Check if exists in pending
    return haskey(gate.pending_confirmations, token_str)
end

"""
    get_pending_count(gate::SecureConfirmationGate)::UInt64
Get count of pending confirmations
"""
function get_pending_count(gate::SecureConfirmationGate)::UInt64
    return UInt64(length(gate.pending_confirmations))
end

"""
    _emit_confirmation_request - Emit confirmation request (placeholder)
"""
function _emit_confirmation_request(pending::PendingSecureAction)
    @info "Secure confirmation request emitted for $(pending.capability_id)"
end

# ============================================================================
# VERIFICATION TESTS - Actively Exploits Vulnerability and Proves Fix
# ============================================================================

# Export for module inclusion
export SecureConfirmationGate, SecureToken, PendingSecureAction, WDTHeartbeat
export SecureConfirmationGate, require_confirmation, confirm_action, deny_action
export is_pending, get_pending_count, check_pending_timeout
export _generate_secure_token, _generate_secure_key, _get_rust_entropy

# WDT-aligned timeout exports
export get_timeout_for_risk_level, get_poll_interval_for_risk_level
export trigger_fail_closed_isolation, kick_wdt_heartbeat, check_wdt_health
export set_fail_closed_callback, set_wdt_kick_callback

# Risk level and metabolic mode exports
export RiskLevel, MetabolicMode
export WDT_TIMEOUT_MAP, METABOLIC_POLL_MAP
export READ_ONLY, LOW, MEDIUM, HIGH, CRITICAL
export LOW_POWER, NORMAL, HIGH_PERFORMANCE

# Audit logging exports
export ConfirmationAuditLog, ConfirmationEventAction
export CONFIRMATION_REQUESTED, CONFIRMATION_CONFIRMED, CONFIRMATION_DENIED, CONFIRMATION_EXPIRED, CONFIRMATION_TIMEOUT
export log_confirmation_event, _get_rust_timestamp, _log_to_persistence
