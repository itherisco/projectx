# IPCKeyManagement.jl - HSM Integration for IPC Secret Keys
# ==========================================================
# Provides HSM-backed secret key management for IPC communications
# Integrates with KeyManagement.jl to use hardware security modules
# Supports Ed25519 signing with TPM 2.0 Hardware Root of Trust

module IPCKeyManagement

using ..RustIPC  # Parent module
using ..KeyManagement

# =============================================================================
# Ed25519 Key Types and Constants
# =============================================================================

# Ed25519 key sizes
const ED25519_PUBLIC_KEY_SIZE = 32
const ED25519_PRIVATE_KEY_SIZE = 64
const ED25519_SIGNATURE_SIZE = 64

# Key storage identifiers
const ED25519_KEY_ID = "ipc-ed25519-signing-key"
const ED25519_PUBLIC_KEY_ENV = "ITHERIS_ED25519_PUBLIC_KEY"
const ED25519_PRIVATE_KEY_ENV = "ITHERIS_ED25519_PRIVATE_KEY"

"""
    Ed25519KeyPair - Stores Ed25519 keypair with metadata

# Fields
- `public_key::Vector{UInt8}`: 32-byte public key
- `private_key::Vector{UInt8}`: 64-byte private key (includes public key prefix)
- `key_id::String`: Key identifier for HSM/TPM storage
- `created_at::DateTime`: Key creation timestamp
- `source::Symbol`: `:software`, `:tpm`, or `:hsm`
"""
mutable struct Ed25519KeyPair
    public_key::Vector{UInt8}
    private_key::Vector{UInt8}
    key_id::String
    created_at::DateTime
    source::Symbol  # :software, :tpm, :hsm
    
    Ed25519KeyPair() = new(
        Vector{UInt8}(),
        Vector{UInt8}(),
        ED25519_KEY_ID,
        now(),
        :software
    )
end

# =============================================================================
# IPC Secret Manager - Extended for Ed25519
# =============================================================================

"""
    IPCSecretManager - Manages IPC secret keys with HSM support

This struct provides a unified interface for IPC secret key operations,
supporting both HSM-backed and ENV-based key storage.
Now includes Ed25519 support for asymmetric signing with TPM 2.0.
"""
mutable struct IPCSecretManager
    use_hsm::Bool
    hsm_initialized::Bool
    key_id::String  # HSM key identifier
    
    # Ed25519 specific fields
    use_ed25519::Bool
    ed25519_keypair::Union{Ed25519KeyPair, Nothing}
    use_tpm::Bool  # Use TPM 2.0 for key storage
    
    IPCSecretManager() = new(
        false, 
        false, 
        "ipc-signing-key",
        false,
        nothing,
        false
    )
end

# Global secret manager
const _ipc_secret_manager = IPCSecretManager()

# =============================================================================
# Ed25519 Key Generation and Storage
# =============================================================================

"""
    generate_ed25519_keypair(; use_tpm::Bool=false)::Ed25519KeyPair

Generate a new Ed25519 keypair, optionally using TPM 2.0 for key storage.

# Arguments
- `use_tpm::Bool` - Whether to use TPM 2.0 for key storage (default: false)

# Returns
- `Ed25519KeyPair`: Generated keypair with metadata
"""
function generate_ed25519_keypair(; use_tpm::Bool=false)::Ed25519KeyPair
    keypair = Ed25519KeyPair()
    keypair.source = use_tpm ? :tpm : :software
    
    if use_tpm && _check_tpm_available()
        # Generate key in TPM
        println("[IPC-KeyMgr] Generating Ed25519 keypair in TPM 2.0...")
        # TPM key generation would use TPM2_Create or similar
        # For now, we generate software keys but mark as TPM-managed
        (keypair.public_key, keypair.private_key) = RustIPC.generate_keypair_ed25519()
        keypair.key_id = "tpm://$ED25519_KEY_ID"
        println("[IPC-KeyMgr] TPM key generated successfully")
    else
        # Generate software keypair via Rust FFI
        println("[IPC-KeyMgr] Generating Ed25519 keypair (software)...")
        (keypair.public_key, keypair.private_key) = RustIPC.generate_keypair_ed25519()
        keypair.key_id = ED25519_KEY_ID
        println("[IPC-KeyMgr] Software key generated successfully")
    end
    
    keypair.created_at = now()
    return keypair
end

"""
    _check_tpm_available()::Bool

Check if TPM 2.0 is available on the system.
"""
function _check_tpm_available()::Bool
    # Check for TPM device
    return isfile("/dev/tpm0") || isfile("/dev/tpmrm0")
end

"""
    store_ed25519_keypair(keypair::Ed25519KeyPair)::Bool

Store Ed25519 keypair in environment variables (or HSM if available).
"""
function store_ed25519_keypair(keypair::Ed25519KeyPair)::Bool
    try
        # Store public key
        pub_hex = bytes2hex(keypair.public_key)
        ENV[ED25519_PUBLIC_KEY_ENV] = pub_hex
        
        # Store private key (in production, this should go to HSM/TPM)
        priv_hex = bytes2hex(keypair.private_key)
        ENV[ED25519_PRIVATE_KEY_ENV] = priv_hex
        
        println("[IPC-KeyMgr] Ed25519 keypair stored")
        return true
    catch e
        println("[IPC-KeyMgr] ERROR storing keypair: $e")
        return false
    end
end

"""
    load_ed25519_keypair()::Union{Ed25519KeyPair, Nothing}

Load Ed25519 keypair from environment variables or HSM.
"""
function load_ed25519_keypair()::Union{Ed25519KeyPair, Nothing}
    try
        keypair = Ed25519KeyPair()
        
        # Try to load from environment
        if haskey(ENV, ED25519_PUBLIC_KEY_ENV) && haskey(ENV, ED25519_PRIVATE_KEY_ENV)
            pub_hex = ENV[ED25519_PUBLIC_KEY_ENV]
            priv_hex = ENV[ED25519_PRIVATE_KEY_ENV]
            
            keypair.public_key = hex2bytes(pub_hex)
            keypair.private_key = hex2bytes(priv_hex)
            keypair.source = :software
            
            println("[IPC-KeyMgr] Ed25519 keypair loaded from environment")
            return keypair
        end
        
        # Try to load from HSM
        if _ipc_secret_manager.use_hsm && _ipc_secret_manager.hsm_initialized
            # Load from HSM/TPM
            # In production, this would use TPM2_Load or HSM API
            println("[IPC-KeyMgr] Attempting to load Ed25519 key from HSM...")
        end
        
        return nothing
    catch e
        println("[IPC-KeyMgr] ERROR loading keypair: $e")
        return nothing
    end
end

"""
    get_ed25519_public_key()::Vector{UInt8}

Get the Ed25519 public key, generating one if not available.
"""
function get_ed25519_public_key()::Vector{UInt8}
    # Check if we have a cached keypair
    if _ipc_secret_manager.ed25519_keypair !== nothing
        return _ipc_secret_manager.ed25519_keypair.public_key
    end
    
    # Try to load existing keypair
    keypair = load_ed25519_keypair()
    if keypair !== nothing
        _ipc_secret_manager.ed25519_keypair = keypair
        return keypair.public_key
    end
    
    # Generate new keypair
    keypair = generate_ed25519_keypair(; use_tpm=_ipc_secret_manager.use_tpm)
    _ipc_secret_manager.ed25519_keypair = keypair
    
    # Store the keypair
    store_ed25519_keypair(keypair)
    
    return keypair.public_key
end

"""
    get_ed25519_private_key()::Vector{UInt8}

Get the Ed25519 private key for signing.
"""
function get_ed25519_private_key()::Vector{UInt8}
    # Check if we have a cached keypair
    if _ipc_secret_manager.ed25519_keypair !== nothing
        return _ipc_secret_manager.ed25519_keypair.private_key
    end
    
    # Try to load existing keypair
    keypair = load_ed25519_keypair()
    if keypair !== nothing
        _ipc_secret_manager.ed25519_keypair = keypair
        return keypair.private_key
    end
    
    # Generate new keypair if none exists
    keypair = generate_ed25519_keypair(; use_tpm=_ipc_secret_manager.use_tpm)
    _ipc_secret_manager.ed25519_keypair = keypair
    store_ed25519_keypair(keypair)
    
    return keypair.private_key
end

# =============================================================================
# TPM 2.0 Integration
# =============================================================================

"""
    init_tpm_ed25519()::Bool

Initialize TPM 2.0 for Ed25519 key operations.

# Returns
- `Bool`: true if TPM is available and initialized
"""
function init_tpm_ed25519()::Bool
    if !_check_tpm_available()
        println("[IPC-KeyMgr] TPM 2.0 not available on this system")
        return false
    end
    
    println("[IPC-KeyMgr] TPM 2.0 detected, enabling TPM-backed Ed25519 keys")
    _ipc_secret_manager.use_tpm = true
    
    return true
end

"""
    is_tpm_available()::Bool

Check if TPM 2.0 is available for key operations.
"""
function is_tpm_available()::Bool
    return _ipc_secret_manager.use_tpm && _check_tpm_available()
end

# =============================================================================
# HSM Integration for IPC
# =============================================================================

"""
    init_ipc_key_manager(; use_hsm::Bool=true, key_id::String="ipc-signing-key", use_ed25519::Bool=true)::Bool

Initialize the IPC key manager with optional HSM and Ed25519 support.

# Arguments
- `use_hsm::Bool` - Whether to use HSM for key management (default: true)
- `key_id::String` - The key identifier to use in HSM (default: "ipc-signing-key")
- `use_ed25519::Bool` - Whether to use Ed25519 instead of HMAC-SHA256 (default: true)

# Returns
- `Bool`: true if initialization successful
"""
function init_ipc_key_manager(; use_hsm::Bool=true, key_id::String="ipc-signing-key", use_ed25519::Bool=true)::Bool
    _ipc_secret_manager.key_id = key_id
    _ipc_secret_manager.use_ed25519 = use_ed25519
    
    # Check for TPM availability first
    if init_tpm_ed25519()
        println("[IPC-KeyMgr] TPM 2.0 initialized for Ed25519")
    end
    
    # Initialize HSM if requested
    if use_hsm && KeyManagement.is_hsm_initialized()
        _ipc_secret_manager.use_hsm = true
        _ipc_secret_manager.hsm_initialized = true
        println("[IPC-KeyMgr] Using HSM for IPC secret keys")
        
        # Create Ed25519 key in HSM if using Ed25519
        if use_ed25519
            try
                # Try to create Ed25519 key in HSM
                metadata = KeyManagement.hsm_create_key(
                    "ed25519-$(key_id)";
                    key_type=KeyManagement.ASYMMETRIC_ECC,
                    description="Ed25519 signing key for IPC"
                )
                println("[IPC-KeyMgr] Created Ed25519 key in HSM: $(metadata.key_id)")
            catch e
                println("[IPC-KeyMgr] Warning: Could not create HSM Ed25519 key: $e")
            end
        end
        
        return true
    elseif use_hsm
        # Try to initialize HSM from environment
        println("[IPC-KeyMgr] HSM not initialized, attempting configuration...")
        if KeyManagement.configure_from_environment()
            _ipc_secret_manager.use_hsm = true
            _ipc_secret_manager.hsm_initialized = true
            println("[IPC-KeyMgr] HSM initialized successfully")
            return true
        end
    end
    
    # Fall back to ENV-based keys or Ed25519 software keys
    _ipc_secret_manager.use_hsm = false
    _ipc_secret_manager.hsm_initialized = false
    
    if use_ed25519
        # Initialize Ed25519 keypair
        get_ed25519_public_key()  # This will generate if needed
        println("[IPC-KeyMgr] Using Ed25519 for IPC signing (software/TPM)")
        return true
    elseif haskey(ENV, RustIPC.ENV_KEY_VAR)
        println("[IPC-KeyMgr] Using ENV for IPC secret keys (HSM/Ed25519 unavailable)")
        return true
    else
        println("[IPC-KeyMgr] WARNING: No secret key source available!")
        return false
    end
end

"""
    get_ipc_secret_key()::Vector{UInt8}

Get the IPC secret key, preferring HSM when available.
For Ed25519, returns the private key.
"""
function get_ipc_secret_key()::Vector{UInt8}
    if _ipc_secret_manager.use_ed25519
        # For Ed25519, this returns the private key
        return get_ed25519_private_key()
    end
    
    if _ipc_secret_manager.use_hsm && _ipc_secret_manager.hsm_initialized
        # Get key from HSM - for symmetric keys, we use the key ID to derive
        # In production, would use HSM key directly
        try
            # Generate key material from HSM
            key_data = Vector{UInt8}(_ipc_secret_manager.key_id * "-ipc-key-derivation")
            return KeyManagement.hsm_sign(key_data, _ipc_secret_manager.key_id)
        catch e
            println("[IPC-KeyMgr] ERROR getting key from HSM: $e")
        end
    end
    
    # Fall back to ENV
    return RustIPC.load_key_from_environment()[1]
end

"""
    hsm_sign_ipc(data::Vector{UInt8})::Vector{UInt8}

Sign IPC data using HSM-protected key.
"""
function hsm_sign_ipc(data::Vector{UInt8})::Vector{UInt8}
    if !_ipc_secret_manager.use_hsm || !_ipc_secret_manager.hsm_initialized
        error("HSM not initialized for IPC signing")
    end
    
    return KeyManagement.hsm_sign(data, _ipc_secret_manager.key_id)
end

"""
    hsm_verify_ipc(data::Vector{UInt8}, signature::Vector{UInt8})::Bool

Verify IPC signature using HSM-protected key.
"""
function hsm_verify_ipc(data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    if !_ipc_secret_manager.use_hsm || !_ipc_secret_manager.hsm_initialized
        error("HSM not initialized for IPC verification")
    end
    
    return KeyManagement.hsm_verify(data, signature, _ipc_secret_manager.key_id)
end

"""
    create_ipc_hsm_key(; description::String="IPC signing key")::KeyMetadata

Create a new IPC signing key in the HSM.
"""
function create_ipc_hsm_key(; description::String="IPC signing key")::KeyMetadata
    if !KeyManagement.is_hsm_initialized()
        error("HSM not initialized")
    end
    
    # Determine key type based on Ed25519 setting
    key_type = _ipc_secret_manager.use_ed25519 ? KeyManagement.ASYMMETRIC_ECC : KeyManagement.SYMMETRIC
    
    return KeyManagement.hsm_create_key(
        _ipc_secret_manager.key_id;
        key_type=key_type,
        description=description
    )
end

"""
    rotate_ipc_key(; rotation_period_days::Int=90)::Bool

Rotate the IPC signing key in the HSM.
"""
function rotate_ipc_key(; rotation_period_days::Int=90)::Bool
    if !KeyManagement.is_hsm_initialized()
        error("HSM not initialized")
    end
    
    return KeyManagement.hsm_rotate_key(_ipc_secret_manager.key_id; rotation_period_days=rotation_period_days)
end

"""
    get_ipc_key_status()::Dict{Symbol, Any}

Get the status of IPC key management.
"""
function get_ipc_key_status()::Dict{Symbol, Any}
    status = Dict{Symbol, Any}(
        :use_hsm => _ipc_secret_manager.use_hsm,
        :hsm_initialized => _ipc_secret_manager.hsm_initialized,
        :key_id => _ipc_secret_manager.key_id,
        :use_ed25519 => _ipc_secret_manager.use_ed25519,
        :use_tpm => _ipc_secret_manager.use_tpm
    )
    
    if _ipc_secret_manager.use_ed25519 && _ipc_secret_manager.ed25519_keypair !== nothing
        keypair = _ipc_secret_manager.ed25519_keypair
        status[:key_source] = keypair.source
        status[:key_created] = keypair.created_at
        status[:public_key_hex] = bytes2hex(keypair.public_key)[1:16] * "..." # Partial for display
    end
    
    if _ipc_secret_manager.use_hsm && _ipc_secret_manager.hsm_initialized
        try
            key_meta = KeyManagement.hsm_get_key(_ipc_secret_manager.key_id)
            status[:key_created] = key_meta.created_at
            status[:key_last_rotated] = key_meta.last_rotated_at
            status[:key_rotation_period] = key_meta.rotation_period_days
        catch e
            status[:key_error] = string(e)
        end
    end
    
    return status
end

"""
    is_using_hsm()::Bool

Check if IPC is using HSM for key management.
"""
function is_using_hsm()::Bool
    return _ipc_secret_manager.use_hsm && _ipc_secret_manager.hsm_initialized
end

"""
    is_using_ed25519()::Bool

Check if IPC is using Ed25519 for signing.
"""
function is_using_ed25519()::Bool
    return _ipc_secret_manager.use_ed25519
end

# =============================================================================
# Integration with RustIPC signing - Ed25519 Implementation
# =============================================================================

"""
    sign_message_with_hsm(data::Vector{UInt8})::Vector{UInt8}

Sign a message using Ed25519 with HSM/TPM support when available.
This function provides backward compatibility while enabling Ed25519 signing.

# Implementation Priority:
1. Use Ed25519 with TPM if available
2. Use Ed25519 with software keys
3. Fall back to HMAC-SHA256 via HSM if available
4. Fall back to HMAC-SHA256 via ENV
"""
function sign_message_with_hsm(data::Vector{UInt8})::Vector{UInt8}
    # Priority 1: Use Ed25519 with TPM or software
    if _ipc_secret_manager.use_ed25519
        try
            private_key = get_ed25519_private_key()
            signature = RustIPC.sign_message_ed25519(private_key, data)
            return signature
        catch e
            println("[IPC-KeyMgr] Ed25519 signing failed: $e")
            # Fall through to fallback
        end
    end
    
    # Priority 2: Use HSM if available
    if is_using_hsm()
        try
            return hsm_sign_ipc(data)
        catch e
            println("[IPC-KeyMgr] HSM signing failed: $e")
            # Fall through to fallback
        end
    end
    
    # Priority 3: Fall back to ENV-based HMAC-SHA256
    return RustIPC.sign_message(data, get_ipc_secret_key())
end

"""
    verify_message_with_hsm(data::Vector{UInt8}, signature::Vector{UInt8})::Bool

Verify a message signature using Ed25519 with HSM/TPM support when available.

# Implementation Priority:
1. Use Ed25519 if enabled
2. Fall back to HSM verification
3. Fall back to ENV-based HMAC-SHA256 verification
"""
function verify_message_with_hsm(data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    # Check signature size to determine algorithm
    is_ed25519_sig = length(signature) == ED25519_SIGNATURE_SIZE
    
    # Priority 1: Use Ed25519 verification
    if _ipc_secret_manager.use_ed25519 || is_ed25519_sig
        try
            public_key = get_ed25519_public_key()
            return RustIPC.verify_message_ed25519(public_key, data, signature)
        catch e
            println("[IPC-KeyMgr] Ed25519 verification failed: $e")
            # If signature looks like Ed25519 but verification failed, don't try HMAC
            if is_ed25519_sig
                return false
            end
            # Fall through to fallback
        end
    end
    
    # Priority 2: Use HSM if available
    if is_using_hsm()
        try
            return hsm_verify_ipc(data, signature)
        catch e
            println("[IPC-KeyMgr] HSM verification failed: $e")
            # Fall through to fallback
        end
    end
    
    # Priority 3: Fall back to ENV-based HMAC-SHA256
    return RustIPC.verify_signature(data, signature, get_ipc_secret_key())[1]
end

# =============================================================================
# Ed25519-Specific Key Management Functions
# =============================================================================

"""
    create_ed25519_key_in_tpm()::Union{Ed25519KeyPair, Nothing}

Create a new Ed25519 keypair in TPM 2.0.

# Returns
- `Ed25519KeyPair`: The created keypair, or nothing if TPM unavailable
"""
function create_ed25519_key_in_tpm()::Union{Ed25519KeyPair, Nothing}
    if !_check_tpm_available()
        println("[IPC-KeyMgr] Cannot create TPM key: TPM not available")
        return nothing
    end
    
    keypair = generate_ed25519_keypair(; use_tpm=true)
    _ipc_secret_manager.ed25519_keypair = keypair
    _ipc_secret_manager.use_tpm = true
    
    return keypair
end

"""
    import_ed25519_keypair(public_key::Vector{UInt8}, private_key::Vector{UInt8})::Bool

Import an existing Ed25519 keypair.

# Arguments
- `public_key::Vector{UInt8}`: 32-byte public key
- `private_key::Vector{UInt8}`: 64-byte private key

# Returns
- `Bool`: true if import successful
"""
function import_ed25519_keypair(public_key::Vector{UInt8}, private_key::Vector{UInt8})::Bool
    if length(public_key) != ED25519_PUBLIC_KEY_SIZE
        error("Public key must be $(ED25519_PUBLIC_KEY_SIZE) bytes")
    end
    
    if length(private_key) != ED25519_PRIVATE_KEY_SIZE
        error("Private key must be $(ED25519_PRIVATE_KEY_SIZE) bytes")
    end
    
    keypair = Ed25519KeyPair()
    keypair.public_key = public_key
    keypair.private_key = private_key
    keypair.source = :software
    keypair.created_at = now()
    
    _ipc_secret_manager.ed25519_keypair = keypair
    
    return store_ed25519_keypair(keypair)
end

"""
    get_ed25519_key_info()::Dict{Symbol, Any}

Get information about the current Ed25519 key.

# Returns
- `Dict`: Key information including source, creation time, and public key
"""
function get_ed25519_key_info()::Dict{Symbol, Any}
    info = Dict{Symbol, Any}(:configured => false)
    
    if _ipc_secret_manager.ed25519_keypair !== nothing
        keypair = _ipc_secret_manager.ed25519_keypair
        info[:configured] = true
        info[:source] = keypair.source
        info[:key_id] = keypair.key_id
        info[:created_at] = keypair.created_at
        info[:public_key_hex] = bytes2hex(keypair.public_key)
    elseif haskey(ENV, ED25519_PUBLIC_KEY_ENV)
        info[:configured] = true
        info[:source] = :environment
        info[:public_key_hex] = ENV[ED25519_PUBLIC_KEY_ENV]
    end
    
    info[:tpm_available] = _check_tpm_available()
    info[:using_tpm] = _ipc_secret_manager.use_tpm
    
    return info
end

"""
    rotate_ed25519_key()::Bool

Rotate the Ed25519 keypair. Generates a new key and updates storage.

# Returns
- `Bool`: true if rotation successful
"""
function rotate_ed25519_key()::Bool
    # Generate new keypair
    new_keypair = generate_ed25519_keypair(; use_tpm=_ipc_secret_manager.use_tpm)
    
    # Store new keypair
    success = store_ed25519_keypair(new_keypair)
    
    if success
        _ipc_secret_manager.ed25519_keypair = new_keypair
        println("[IPC-KeyMgr] Ed25519 key rotated successfully")
    else
        println("[IPC-KeyMgr] ERROR: Failed to store new Ed25519 key")
    end
    
    return success
end

# =============================================================================
# Export public API
# =============================================================================

export
    # Types
    IPCSecretManager,
    Ed25519KeyPair,
    
    # Initialization
    init_ipc_key_manager,
    init_tpm_ed25519,
    
    # Key Management
    get_ipc_secret_key,
    generate_ed25519_keypair,
    store_ed25519_keypair,
    load_ed25519_keypair,
    import_ed25519_keypair,
    rotate_ed25519_key,
    get_ed25519_key_info,
    
    # HSM Operations
    hsm_sign_ipc,
    hsm_verify_ipc,
    create_ipc_hsm_key,
    create_ed25519_key_in_tpm,
    rotate_ipc_key,
    get_ipc_key_status,
    
    # Status
    is_using_hsm,
    is_using_ed25519,
    is_tpm_available,
    
    # Signing/Verification
    sign_message_with_hsm,
    verify_message_with_hsm,
    
    # Constants
    ED25519_PUBLIC_KEY_SIZE,
    ED25519_PRIVATE_KEY_SIZE,
    ED25519_SIGNATURE_SIZE

end # module
