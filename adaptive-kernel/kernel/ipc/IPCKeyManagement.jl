# IPCKeyManagement.jl - HSM Integration for IPC Secret Keys
# ==========================================================
# Provides HSM-backed secret key management for IPC communications
# Integrates with KeyManagement.jl to use hardware security modules

module IPCKeyManagement

using ..RustIPC  # Parent module
using ..KeyManagement

# =============================================================================
# HSM Integration for IPC
# =============================================================================

"""
    IPCSecretManager - Manages IPC secret keys with HSM support

This struct provides a unified interface for IPC secret key operations,
supporting both HSM-backed and ENV-based key storage.
"""
mutable struct IPCSecretManager
    use_hsm::Bool
    hsm_initialized::Bool
    key_id::String  # HSM key identifier
    
    IPCSecretManager() = new(false, false, "ipc-signing-key")
end

# Global secret manager
const _ipc_secret_manager = IPCSecretManager()

"""
    init_ipc_key_manager(; use_hsm::Bool=true, key_id::String="ipc-signing-key")::Bool

Initialize the IPC key manager with optional HSM support.

# Arguments
- `use_hsm::Bool` - Whether to use HSM for key management (default: true)
- `key_id::String` - The key identifier to use in HSM (default: "ipc-signing-key")

# Returns
- `Bool`: true if initialization successful
"""
function init_ipc_key_manager(; use_hsm::Bool=true, key_id::String="ipc-signing-key")::Bool
    _ipc_secret_manager.key_id = key_id
    
    if use_hsm && KeyManagement.is_hsm_initialized()
        _ipc_secret_manager.use_hsm = true
        _ipc_secret_manager.hsm_initialized = true
        println("[IPC-KeyMgr] Using HSM for IPC secret keys")
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
    
    # Fall back to ENV-based keys
    _ipc_secret_manager.use_hsm = false
    _ipc_secret_manager.hsm_initialized = false
    
    if haskey(ENV, RustIPC.ENV_KEY_VAR)
        println("[IPC-KeyMgr] Using ENV for IPC secret keys (HSM unavailable)")
        return true
    else
        println("[IPC-KeyMgr] WARNING: No secret key source available!")
        return false
    end
end

"""
    get_ipc_secret_key()::Vector{UInt8}

Get the IPC secret key, preferring HSM when available.
"""
function get_ipc_secret_key()::Vector{UInt8}
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
    
    return KeyManagement.hsm_create_key(
        _ipc_secret_manager.key_id;
        key_type=KeyManagement.SYMMETRIC,
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
        :key_id => _ipc_secret_manager.key_id
    )
    
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

# =============================================================================
# Integration with RustIPC signing
# =============================================================================

"""
    sign_message_with_hsm(data::Vector{UInt8})::Vector{UInt8}

Sign a message using HSM if available, otherwise use standard RustIPC signing.
This function provides backward compatibility while enabling HSM when available.
"""
function sign_message_with_hsm(data::Vector{UInt8})::Vector{UInt8}
    if is_using_hsm()
        return hsm_sign_ipc(data)
    else
        # Use standard RustIPC signing
        return RustIPC.sign_message(data, get_ipc_secret_key())
    end
end

"""
    verify_message_with_hsm(data::Vector{UInt8}, signature::Vector{UInt8})::Bool

Verify a message signature using HSM if available.
"""
function verify_message_with_hsm(data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    if is_using_hsm()
        return hsm_verify_ipc(data, signature)
    else
        return RustIPC.verify_signature(data, signature, get_ipc_secret_key())[1]
    end
end

# =============================================================================
# Export public API
# =============================================================================

export
    IPCSecretManager,
    init_ipc_key_manager,
    get_ipc_secret_key,
    hsm_sign_ipc,
    hsm_verify_ipc,
    create_ipc_hsm_key,
    rotate_ipc_key,
    get_ipc_key_status,
    is_using_hsm,
    sign_message_with_hsm,
    verify_message_with_hsm

end # module
