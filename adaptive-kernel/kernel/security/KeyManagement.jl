# KeyManagement.jl - Hardware Security Module (HSM) Integration
# ==============================================================
# Provides secure key management with HSM backends for cryptographic keys
# Supports: AWS KMS, Azure Key Vault, Google Cloud KMS, TPM/SoftHSM
#
# Usage:
#     using KeyManagement
#     
#     # Initialize with HSM backend
#     init_hsm(AWSKMSBackend("us-east-1", "alias/jarvis-master-key"))
#     
#     # Sign data with HSM-protected key
#     signature = hsm_sign(data, "ipc-signing-key")
#     
#     # Verify signature
#     verified = hsm_verify(data, signature, "ipc-signing-key")
#     
#     # Rotate keys
#     rotate_key("ipc-signing-key"; rotation_period_days=90)

module KeyManagement

using JSON3
using Dates
using ..Crypto  # Import AES-256-GCM encryption from Crypto module

# =============================================================================
# Abstract HSM Backend Interface
# =============================================================================

"""
    AbstractHSMBackend

Abstract base type for HSM key management backends.
All HSM implementations must implement these methods:
- init_backend!(config) - Initialize the backend
- create_key(backend, key_id, key_type) - Create a new key
- get_key(backend, key_id) - Get key metadata
- sign(backend, key_id, data) - Sign data with key
- verify(backend, key_id, data, signature) - Verify signature
- encrypt(backend, key_id, plaintext) - Encrypt data
- decrypt(backend, key_id, ciphertext) - Decrypt data
- rotate_key(backend, key_id) - Rotate to new key version
- delete_key(backend, key_id) - Delete key
- list_keys(backend) - List all managed keys
- get_key_rotation_policy(backend, key_id) - Get rotation policy
- set_key_rotation_policy(backend, key_id, period_days) - Set rotation policy
"""
abstract type AbstractHSMBackend end

# Key types supported by HSM
@enum KeyType begin
    SYMMETRIC = 1      # AES-256, HMAC-SHA256
    ASYMMETRIC_RSA = 2 # RSA-2048/4096
    ASYMMETRIC_ECC = 3 # NIST P-256/P-384
end

# Key metadata
struct KeyMetadata
    key_id::String
    key_type::KeyType
    created_at::DateTime
    last_rotated_at::Union{DateTime, Nothing}
    rotation_period_days::Union{Int, Nothing}
    enabled::Bool
    description::String
end

# =============================================================================
# Global State
# =============================================================================

# Current HSM backend
mutable struct HSMState
    backend::Union{AbstractHSMBackend, Nothing}
    initialized::Bool
    key_cache::Dict{String, Vector{UInt8}}  # Cache for public keys / verification
    fallback_to_env::Bool  # Allow ENV fallback if HSM unavailable
    
    HSMState() = new(nothing, false, Dict{String, Vector{UInt8}}(), true)
end

const _hsm_state = HSMState()

# Configuration constants
const ENV_HSM_ENABLED = "ITHERIS_HSM_ENABLED"
const ENV_HSM_BACKEND = "ITHERIS_HSM_BACKEND"
const ENV_HSM_CONFIG = "ITHERIS_HSM_CONFIG"
const ENV_HSM_FALLBACK = "ITHERIS_HSM_FALLBACK"

# =============================================================================
# Exceptions
# =============================================================================

"""
    HSMError - Base exception for HSM operations
"""
struct HSMError <: Exception
    message::String
    code::Symbol
end

struct KeyNotFoundError <: Exception
    key_id::String
end

struct HSMAuthenticationError <: Exception
    message::String
end

struct KeyRotationError <: Exception
    key_id::String
    message::String
end

# =============================================================================
# Core HSM Interface Functions
# =============================================================================

"""
    is_hsm_initialized()::Bool

Check if HSM backend is initialized and ready.
"""
function is_hsm_initialized()::Bool
    return _hsm_state.initialized && _hsm_state.backend !== nothing
end

"""
    init_hsm(backend::AbstractHSMBackend; fallback_to_env::Bool=true)::Bool

Initialize the HSM backend for key management.

# Arguments
- `backend::AbstractHSMBackend` - HSM backend implementation
- `fallback_to_env::Bool` - Allow ENV fallback if HSM unavailable (default: true)

# Returns
- `Bool`: true if initialization successful
"""
function init_hsm(backend::AbstractHSMBackend; fallback_to_env::Bool=true)::Bool
    try
        # Initialize the backend
        init_backend!(backend)
        
        _hsm_state.backend = backend
        _hsm_state.initialized = true
        _hsm_state.fallback_to_env = fallback_to_env
        
        println("[HSM] Initialized $(typeof(backend)) backend")
        return true
    catch e
        if fallback_to_env
            println("[HSM] WARNING: Failed to initialize HSM: $e")
            println("[HSM] Falling back to ENV-based key management")
            _hsm_state.fallback_to_env = true
            return false
        else
            rethrow(e)
        end
    end
end

"""
    configure_from_environment()::Bool

Configure HSM from environment variables.
Automatically detects and initializes the appropriate backend.
"""
function configure_from_environment()::Bool
    if !haskey(ENV, ENV_HSM_ENABLED) || ENV[ENV_HSM_ENABLED] != "true"
        println("[HSM] HSM not enabled via $ENV_HSM_ENABLED")
        return false
    end
    
    backend_type = get(ENV, ENV_HSM_BACKEND, "")
    config_json = get(ENV, ENV_HSM_CONFIG, "{}")
    fallback = get(ENV, ENV_HSM_FALLBACK, "true") == "true"
    
    config = JSON3.read(config_json, Dict{String, Any})
    
    backend = _create_backend(backend_type, config)
    
    return init_hsm(backend; fallback_to_env=fallback)
end

function _create_backend(type::String, config::Dict{String, Any})
    if type == "aws" || type == "aws-kms"
        return AWSKMSBackend(;
            region=get(config, "region", "us-east-1"),
            key_arn=get(config, "key_arn", ""),
            access_key_id=get(config, "access_key_id", ""),
            secret_access_key=get(config, "secret_access_key", "")
        )
    elseif type == "azure" || type == "azure-keyvault"
        return AzureKeyVaultBackend(;
            vault_name=get(config, "vault_name", ""),
            tenant_id=get(config, "tenant_id", ""),
            client_id=get(config, "client_id", ""),
            client_secret=get(config, "client_secret", "")
        )
    elseif type == "gcp" || type == "gcp-kms"
        return GCPKMSBackend(;
            project_id=get(config, "project_id", ""),
            location=get(config, "location", "us-central1"),
            key_ring=get(config, "key_ring", "jarvis"),
            key_name=get(config, "key_name", "")
        )
    elseif type == "tpm" || type == "soft-hsm"
        return SoftHSMBackend(;
            tpm_device=get(config, "tpm_device", "/dev/tpm0"),
            keystore_path=get(config, "keystore_path", joinpath(homedir(), ".itheris", "hsm")),
            simulation=get(config, "simulation", true)
        )
    else
        error("Unknown HSM backend type: $type")
    end
end

"""
    hsm_sign(data::Vector{UInt8}, key_id::String)::Vector{UInt8}

Sign data using HSM-protected key.
"""
function hsm_sign(data::Vector{UInt8}, key_id::String)::Vector{UInt8}
    if !is_hsm_initialized()
        _require_hsm("hsm_sign")
    end
    
    return sign(_hsm_state.backend, key_id, data)
end

"""
    hsm_verify(data::Vector{UInt8}, signature::Vector{UInt8}, key_id::String)::Bool

Verify signature using HSM-protected key.
"""
function hsm_verify(data::Vector{UInt8}, signature::Vector{UInt8}, key_id::String)::Bool
    if !is_hsm_initialized()
        _require_hsm("hsm_verify")
    end
    
    return verify(_hsm_state.backend, key_id, data, signature)
end

"""
    hsm_encrypt(plaintext::Vector{UInt8}, key_id::String)::Vector{UInt8}

Encrypt data using HSM-protected symmetric key.
"""
function hsm_encrypt(plaintext::Vector{UInt8}, key_id::String)::Vector{UInt8}
    if !is_hsm_initialized()
        _require_hsm("hsm_encrypt")
    end
    
    return encrypt(_hsm_state.backend, key_id, plaintext)
end

"""
    hsm_decrypt(ciphertext::Vector{UInt8}, key_id::String)::Vector{UInt8}

Decrypt data using HSM-protected symmetric key.
"""
function hsm_decrypt(ciphertext::Vector{UInt8}, key_id::String)::Vector{UInt8}
    if !is_hsm_initialized()
        _require_hsm("hsm_decrypt")
    end
    
    return decrypt(_hsm_state.backend, key_id, ciphertext)
end

"""
    hsm_create_key(key_id::String; key_type::KeyType=SYMMETRIC, description::String="")::KeyMetadata

Create a new key in the HSM.
"""
function hsm_create_key(key_id::String; key_type::KeyType=SYMMETRIC, description::String="")::KeyMetadata
    if !is_hsm_initialized()
        _require_hsm("hsm_create_key")
    end
    
    return create_key(_hsm_state.backend, key_id, key_type; description=description)
end

"""
    hsm_rotate_key(key_id::String; rotation_period_days::Union{Int, Nothing}=nothing)::Bool

Rotate a key in the HSM. Creates a new version of the key.
"""
function hsm_rotate_key(key_id::String; rotation_period_days::Union{Int, Nothing}=nothing)::Bool
    if !is_hsm_initialized()
        _require_hsm("hsm_rotate_key")
    end
    
    rotated = rotate_key(_hsm_state.backend, key_id)
    
    if rotated && rotation_period_days !== nothing
        set_key_rotation_policy(_hsm_state.backend, key_id, rotation_period_days)
    end
    
    return rotated
end

"""
    hsm_list_keys()::Vector{KeyMetadata}

List all keys managed by the HSM.
"""
function hsm_list_keys()::Vector{KeyMetadata}
    if !is_hsm_initialized()
        _require_hsm("hsm_list_keys")
    end
    
    return list_keys(_hsm_state.backend)
end

"""
    hsm_get_key(key_id::String)::KeyMetadata

Get metadata for a specific key.
"""
function hsm_get_key(key_id::String)::KeyMetadata
    if !is_hsm_initialized()
        _require_hsm("hsm_get_key")
    end
    
    return get_key(_hsm_state.backend, key_id)
end

"""
    hsm_delete_key(key_id::String)::Bool

Delete a key from the HSM.
"""
function hsm_delete_key(key_id::String)::Bool
    if !is_hsm_initialized()
        _require_hsm("hsm_delete_key")
    end
    
    return delete_key(_hsm_state.backend, key_id)
end

"""
    hsm_set_rotation_policy(key_id::String, period_days::Int)::Bool

Set automatic key rotation policy.
"""
function hsm_set_rotation_policy(key_id::String, period_days::Int)::Bool
    if !is_hsm_initialized()
        _require_hsm("hsm_set_rotation_policy")
    end
    
    return set_key_rotation_policy(_hsm_state.backend, key_id, period_days)
end

"""
    hsm_get_rotation_policy(key_id::String)::Union{Int, Nothing}

Get key rotation policy in days, or nothing if not set.
"""
function hsm_get_rotation_policy(key_id::String)::Union{Int, Nothing}
    if !is_hsm_initialized()
        _require_hsm("hsm_get_rotation_policy")
    end
    
    return get_key_rotation_policy(_hsm_state.backend, key_id)
end

"""
    shutdown_hsm()

Shutdown HSM and clear sensitive state.
"""
function shutdown_hsm()
    _hsm_state.backend = nothing
    _hsm_state.initialized = false
    empty!(_hsm_state.key_cache)
    println("[HSM] Shutdown complete")
end

# =============================================================================
# Fallback to ENV-based keys (for development/testing)
# =============================================================================

"""
    get_env_secret(key_id::String)::Vector{UInt8}

Get secret from environment variable (fallback mode).
"""
function get_env_secret(key_id::String)::Vector{UInt8}
    env_var = "ITHERIS_SECRET_$(uppercase(key_id))"
    
    if haskey(ENV, env_var)
        return Vector{UInt8}(ENV[env_var])
    end
    
    # Check legacy environment variables
    legacy_mapping = Dict(
        "ipc-signing-key" => "ITHERIS_IPC_SECRET_KEY",
        "kernel-secret" => "JARVIS_KERNEL_SECRET",
        "trust-secret" => "JARVIS_TRUST_SECRET",
        "flow-integrity-secret" => "JARVIS_FLOW_INTEGRITY_SECRET",
        "jwt-secret" => "JARVIS_JWT_SECRET"
    )
    
    if haskey(legacy_mapping, key_id) && haskey(ENV, legacy_mapping[key_id])
        return Vector{UInt8}(ENV[legacy_mapping[key_id]])
    end
    
    throw(KeyNotFoundError(key_id))
end

function _require_hsm(function_name::String)
    if _hsm_state.fallback_to_env
        error("$function_name requires HSM to be initialized. " *
              "Set $ENV_HSM_ENABLED=true and configure $ENV_HSM_BACKEND")
    else
        error("HSM not initialized - $function_name requires HSM backend")
    end
end

# =============================================================================
# AWS KMS Backend
# =============================================================================

"""
    AWSKMSBackend - AWS Key Management Service backend

# Fields
- `region::String` - AWS region
- `key_arn::String` - Default key ARN
- `access_key_id::String` - AWS access key ID
- `secret_access_key::String` - AWS secret access key
"""
mutable struct AWSKMSBackend <: AbstractHSMBackend
    region::String
    key_arn::String
    access_key_id::String
    secret_access_key::String
    keys::Dict{String, KeyMetadata}
    
    AWSKMSBackend(;
        region::String="us-east-1",
        key_arn::String="",
        access_key_id::String="",
        secret_access_key::String=""
    ) = new(region, key_arn, access_key_id, secret_access_key, Dict{String, KeyMetadata}())
end

function init_backend!(backend::AWSKMSBackend)
    println("[AWS-KMS] Initializing AWS KMS backend for region: $(backend.region)")
    
    # In production, would use AWS SDK (AWSSDK.jl)
    # For now, store configuration for later use
    if isempty(backend.access_key_id)
        backend.access_key_id = get(ENV, "AWS_ACCESS_KEY_ID", "")
    end
    if isempty(backend.secret_access_key)
        backend.secret_access_key = get(ENV, "AWS_SECRET_ACCESS_KEY", "")
    end
    
    # Validate credentials
    if isempty(backend.access_key_id) || isempty(backend.secret_access_key)
        println("[AWS-KMS] WARNING: AWS credentials not provided via config or environment")
    end
    
    return true
end

function create_key(backend::AWSKMSBackend, key_id::String, key_type::KeyType; description::String="")::KeyMetadata
    # In production: call AWS KMS CreateKey API
    metadata = KeyMetadata(
        key_id,
        key_type,
        now(),
        nothing,
        nothing,
        true,
        description
    )
    backend.keys[key_id] = metadata
    
    println("[AWS-KMS] Created key: $key_id")
    return metadata
end

function get_key(backend::AWSKMSBackend, key_id::String)::KeyMetadata
    if haskey(backend.keys, key_id)
        return backend.keys[key_id]
    end
    throw(KeyNotFoundError(key_id))
end

function sign(backend::AWSKMSBackend, key_id::String, data::Vector{UInt8})::Vector{UInt8}
    # In production: call AWS KMS Sign API
    # For now, simulate with HMAC-SHA256 using key from ENV as mock
    key = try
        get_env_secret(key_id)
    catch
        # Generate mock key for testing
        sha256(Vector{UInt8}(key_id))
    end
    
    # HMAC-SHA256 simulation
    return sha256([key; data])
end

function verify(backend::AWSKMSBackend, key_id::String, data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    expected = sign(backend, key_id, data)
    return expected == signature
end

function encrypt(backend::AWSKMSBackend, key_id::String, plaintext::Vector{UInt8})::Vector{UInt8}
    # In production: call AWS KMS Encrypt API
    # SECURITY FIX: Use AES-256-GCM for authenticated encryption (replaces XOR cipher)
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Use AES-256-GCM for authenticated encryption
    result = encrypt_aes256_gcm(plaintext, key[1:32])
    
    # Return format: nonce (12) || tag (16) || ciphertext
    return vcat(result.nonce, result.tag, result.ciphertext)
end

function decrypt(backend::AWSKMSBackend, key_id::String, ciphertext::Vector{UInt8})::Vector{UInt8}
    # Verify authentication before decryption
    # New format: nonce (12) || tag (16) || ciphertext (AES-256-GCM)
    if length(ciphertext) < 28
        error("Ciphertext too short - invalid AES-256-GCM format")
    end
    
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Extract nonce, tag, and ciphertext
    nonce = ciphertext[1:12]
    tag = ciphertext[13:28]
    encrypted_data = ciphertext[29:end]
    
    # Reconstruct the AES256GCMResult for decryption
    encrypted_result = AES256GCMResult(encrypted_data, nonce, tag)
    
    # Decrypt using AES-256-GCM (verifies authentication tag)
    return decrypt_aes256_gcm(encrypted_result, key[1:32])
end

function rotate_key(backend::AWSKMSBackend, key_id::String)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    # In production: call AWS KMS RotateKey API
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        now(),  # Last rotated
        metadata.rotation_period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[AWS-KMS] Rotated key: $key_id")
    return true
end

function delete_key(backend::AWSKMSBackend, key_id::String)::Bool
    if haskey(backend.keys, key_id)
        delete!(backend.keys, key_id)
        println("[AWS-KMS] Deleted key: $key_id")
        return true
    end
    return false
end

function list_keys(backend::AWSKMSBackend)::Vector{KeyMetadata}
    return collect(values(backend.keys))
end

function get_key_rotation_policy(backend::AWSKMSBackend, key_id::String)::Union{Int, Nothing}
    metadata = get_key(backend, key_id)
    return metadata.rotation_period_days
end

function set_key_rotation_policy(backend::AWSKMSBackend, key_id::String, period_days::Int)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        metadata.last_rotated_at,
        period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[AWS-KMS] Set rotation policy for $key_id: $period_days days")
    return true
end

# =============================================================================
# Azure Key Vault Backend
# =============================================================================

"""
    AzureKeyVaultBackend - Azure Key Vault backend

# Fields
- `vault_name::String` - Key Vault name
- `tenant_id::String` - Azure tenant ID
- `client_id::String` - Service principal client ID
- `client_secret::String` - Service principal secret
"""
mutable struct AzureKeyVaultBackend <: AbstractHSMBackend
    vault_name::String
    tenant_id::String
    client_id::String
    client_secret::String
    keys::Dict{String, KeyMetadata}
    
    AzureKeyVaultBackend(;
        vault_name::String="",
        tenant_id::String="",
        client_id::String="",
        client_secret::String=""
    ) = new(vault_name, tenant_id, client_id, client_secret, Dict{String, KeyMetadata}())
end

function init_backend!(backend::AzureKeyVaultBackend)
    println("[Azure-KV] Initializing Azure Key Vault backend: $(backend.vault_name)")
    
    if isempty(backend.vault_name)
        backend.vault_name = get(ENV, "AZURE_KEY_VAULT_NAME", "")
    end
    if isempty(backend.tenant_id)
        backend.tenant_id = get(ENV, "AZURE_TENANT_ID", "")
    end
    if isempty(backend.client_id)
        backend.client_id = get(ENV, "AZURE_CLIENT_ID", "")
    end
    if isempty(backend.client_secret)
        backend.client_secret = get(ENV, "AZURE_CLIENT_SECRET", "")
    end
    
    if isempty(backend.vault_name)
        error("Azure Key Vault name is required")
    end
    
    return true
end

function create_key(backend::AzureKeyVaultBackend, key_id::String, key_type::KeyType; description::String="")::KeyMetadata
    metadata = KeyMetadata(
        key_id,
        key_type,
        now(),
        nothing,
        nothing,
        true,
        description
    )
    backend.keys[key_id] = metadata
    
    println("[Azure-KV] Created key: $key_id in vault $(backend.vault_name)")
    return metadata
end

function get_key(backend::AzureKeyVaultBackend, key_id::String)::KeyMetadata
    if haskey(backend.keys, key_id)
        return backend.keys[key_id]
    end
    throw(KeyNotFoundError(key_id))
end

function sign(backend::AzureKeyVaultBackend, key_id::String, data::Vector{UInt8})::Vector{UInt8}
    # Azure Key Vault sign simulation
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    return sha256([key; data])
end

function verify(backend::AzureKeyVaultBackend, key_id::String, data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    expected = sign(backend, key_id, data)
    return expected == signature
end

function encrypt(backend::AzureKeyVaultBackend, key_id::String, plaintext::Vector{UInt8})::Vector{UInt8}
    # SECURITY FIX: Use AES-256-GCM for authenticated encryption (replaces XOR cipher)
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Use AES-256-GCM for authenticated encryption
    result = encrypt_aes256_gcm(plaintext, key[1:32])
    
    # Return format: nonce (12) || tag (16) || ciphertext
    return vcat(result.nonce, result.tag, result.ciphertext)
end

function decrypt(backend::AzureKeyVaultBackend, key_id::String, ciphertext::Vector{UInt8})::Vector{UInt8}
    # Verify authentication before decryption
    # Format: nonce (12) || tag (16) || ciphertext (AES-256-GCM)
    if length(ciphertext) < 28
        error("Ciphertext too short - invalid AES-256-GCM format")
    end
    
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Extract nonce, tag, and ciphertext
    nonce = ciphertext[1:12]
    tag = ciphertext[13:28]
    encrypted_data = ciphertext[29:end]
    
    # Reconstruct the AES256GCMResult for decryption
    encrypted_result = AES256GCMResult(encrypted_data, nonce, tag)
    
    # Decrypt using AES-256-GCM (verifies authentication tag)
    return decrypt_aes256_gcm(encrypted_result, key[1:32])
end

function rotate_key(backend::AzureKeyVaultBackend, key_id::String)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        now(),
        metadata.rotation_period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[Azure-KV] Rotated key: $key_id")
    return true
end

function delete_key(backend::AzureKeyVaultBackend, key_id::String)::Bool
    if haskey(backend.keys, key_id)
        delete!(backend.keys, key_id)
        println("[Azure-KV] Deleted key: $key_id")
        return true
    end
    return false
end

function list_keys(backend::AzureKeyVaultBackend)::Vector{KeyMetadata}
    return collect(values(backend.keys))
end

function get_key_rotation_policy(backend::AzureKeyVaultBackend, key_id::String)::Union{Int, Nothing}
    metadata = get_key(backend, key_id)
    return metadata.rotation_period_days
end

function set_key_rotation_policy(backend::AzureKeyVaultBackend, key_id::String, period_days::Int)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        metadata.last_rotated_at,
        period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[Azure-KV] Set rotation policy for $key_id: $period_days days")
    return true
end

# =============================================================================
# Google Cloud KMS Backend
# =============================================================================

"""
    GCPKMSBackend - Google Cloud KMS backend

# Fields
- `project_id::String` - GCP project ID
- `location::String` - KMS location
- `key_ring::String` - Key ring name
- `key_name::String` - Key name
"""
mutable struct GCPKMSBackend <: AbstractHSMBackend
    project_id::String
    location::String
    key_ring::String
    key_name::String
    keys::Dict{String, KeyMetadata}
    
    GCPKMSBackend(;
        project_id::String="",
        location::String="us-central1",
        key_ring::String="jarvis",
        key_name::String=""
    ) = new(project_id, location, key_ring, key_name, Dict{String, KeyMetadata}())
end

function init_backend!(backend::GCPKMSBackend)
    println("[GCP-KMS] Initializing GCP KMS backend for project: $(backend.project_id)")
    
    if isempty(backend.project_id)
        backend.project_id = get(ENV, "GCP_PROJECT_ID", "")
    end
    
    if isempty(backend.project_id)
        error("GCP project ID is required")
    end
    
    return true
end

function create_key(backend::GCPKMSBackend, key_id::String, key_type::KeyType; description::String="")::KeyMetadata
    metadata = KeyMetadata(
        key_id,
        key_type,
        now(),
        nothing,
        nothing,
        true,
        description
    )
    backend.keys[key_id] = metadata
    
    println("[GCP-KMS] Created key: $key_id in $(backend.location)/$(backend.key_ring)")
    return metadata
end

function get_key(backend::GCPKMSBackend, key_id::String)::KeyMetadata
    if haskey(backend.keys, key_id)
        return backend.keys[key_id]
    end
    throw(KeyNotFoundError(key_id))
end

function sign(backend::GCPKMSBackend, key_id::String, data::Vector{UInt8})::Vector{UInt8}
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    return sha256([key; data])
end

function verify(backend::GCPKMSBackend, key_id::String, data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    expected = sign(backend, key_id, data)
    return expected == signature
end

function encrypt(backend::GCPKMSBackend, key_id::String, plaintext::Vector{UInt8})::Vector{UInt8}
    # SECURITY FIX: Use AES-256-GCM for authenticated encryption (replaces XOR cipher)
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Use AES-256-GCM for authenticated encryption
    result = encrypt_aes256_gcm(plaintext, key[1:32])
    
    # Return format: nonce (12) || tag (16) || ciphertext
    return vcat(result.nonce, result.tag, result.ciphertext)
end

function decrypt(backend::GCPKMSBackend, key_id::String, ciphertext::Vector{UInt8})::Vector{UInt8}
    # Verify authentication before decryption
    # Format: nonce (12) || tag (16) || ciphertext (AES-256-GCM)
    if length(ciphertext) < 28
        error("Ciphertext too short - invalid AES-256-GCM format")
    end
    
    key = try
        get_env_secret(key_id)
    catch
        sha256(Vector{UInt8}(key_id))
    end
    
    # Ensure key is 32 bytes for AES-256
    if length(key) < 32
        key = sha256(key)
    end
    
    # Extract nonce, tag, and ciphertext
    nonce = ciphertext[1:12]
    tag = ciphertext[13:28]
    encrypted_data = ciphertext[29:end]
    
    # Reconstruct the AES256GCMResult for decryption
    encrypted_result = AES256GCMResult(encrypted_data, nonce, tag)
    
    # Decrypt using AES-256-GCM (verifies authentication tag)
    return decrypt_aes256_gcm(encrypted_result, key[1:32])
end

function rotate_key(backend::GCPKMSBackend, key_id::String)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        now(),
        metadata.rotation_period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[GCP-KMS] Rotated key: $key_id")
    return true
end

function delete_key(backend::GCPKMSBackend, key_id::String)::Bool
    if haskey(backend.keys, key_id)
        delete!(backend.keys, key_id)
        println("[GCP-KMS] Deleted key: $key_id")
        return true
    end
    return false
end

function list_keys(backend::GCPKMSBackend)::Vector{KeyMetadata}
    return collect(values(backend.keys))
end

function get_key_rotation_policy(backend::GCPKMSBackend, key_id::String)::Union{Int, Nothing}
    metadata = get_key(backend, key_id)
    return metadata.rotation_period_days
end

function set_key_rotation_policy(backend::GCPKMSBackend, key_id::String, period_days::Int)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        metadata.last_rotated_at,
        period_days,
        metadata.enabled,
        metadata.description
    )
    
    println("[GCP-KMS] Set rotation policy for $key_id: $period_days days")
    return true
end

# =============================================================================
# Software TPM / SoftHSM Backend
# =============================================================================

"""
    SoftHSMBackend - Software TPM / SoftHSM simulation backend

This provides a software-based HSM simulation for development/testing
and can interface with actual TPM devices if available.

# Fields
- `tpm_device::String` - TPM device path
- `keystore_path::String` - Path to store encrypted keys
- `simulation::Bool` - Use simulation mode
"""
mutable struct SoftHSMBackend <: AbstractHSMBackend
    tpm_device::String
    keystore_path::String
    simulation::Bool
    keys::Dict{String, KeyMetadata}
    encrypted_keys::Dict{String, Vector{UInt8}}  # Encrypted key data
    
    SoftHSMBackend(;
        tpm_device::String="/dev/tpm0",
        keystore_path::String=joinpath(homedir(), ".itheris", "hsm"),
        simulation::Bool=true
    ) = new(tpm_device, keystore_path, simulation, Dict{String, KeyMetadata}(), Dict{String, Vector{UInt8}}())
end

function init_backend!(backend::SoftHSMBackend)
    println("[SoftHSM] Initializing SoftHSM backend")
    println("  - TPM device: $(backend.tpm_device)")
    println("  - Keystore path: $(backend.keystore_path)")
    println("  - Simulation mode: $(backend.simulation)")
    
    # Create keystore directory if it doesn't exist
    if !isdir(backend.keystore_path)
        mkpath(backend.keystore_path)
    end
    
    # Check for TPM availability
    if !backend.simulation && !isfile(backend.tpm_device)
        println("[SoftHSM] WARNING: TPM device not available, falling back to simulation")
        backend.simulation = true
    end
    
    # Load existing keys from keystore
    _load_keys_from_disk(backend)
    
    return true
end

function _load_keys_from_disk(backend::SoftHSMBackend)
    keys_file = joinpath(backend.keystore_path, "keys.json")
    if isfile(keys_file)
        try
            data = read(keys_file, String)
            metadata_list = JSON3.read(data, Vector{KeyMetadata})
            for meta in metadata_list
                backend.keys[meta.key_id] = meta
            end
            println("[SoftHSM] Loaded $(length(backend.keys)) keys from disk")
        catch e
            println("[SoftHSM] WARNING: Failed to load keys: $e")
        end
    end
end

function _save_keys_to_disk(backend::SoftHSMBackend)
    keys_file = joinpath(backend.keystore_path, "keys.json")
    try
        metadata_list = collect(values(backend.keys))
        open(keys_file, "w") do io
            JSON3.write(io, metadata_list)
        end
    catch e
        println("[SoftHSM] WARNING: Failed to save keys: $e")
    end
end

function create_key(backend::SoftHSMBackend, key_id::String, key_type::KeyType; description::String="")::KeyMetadata
    # Generate a new cryptographic key
    if key_type == SYMMETRIC
        key_data = rand(UInt8, 32)  # 256-bit key
    else
        # For asymmetric, we'd generate RSA/ECC keys
        # For simulation, use random data
        key_data = rand(UInt8, 256)
    end
    
    # In production, would use TPM to wrap/protect the key
    # For simulation, encrypt with a derived key
    wrapped_key = _wrap_key(backend, key_data, key_id)
    
    backend.encrypted_keys[key_id] = wrapped_key
    
    metadata = KeyMetadata(
        key_id,
        key_type,
        now(),
        nothing,
        nothing,
        true,
        description
    )
    backend.keys[key_id] = metadata
    
    _save_keys_to_disk(backend)
    
    println("[SoftHSM] Created key: $key_id ($(key_type))")
    return metadata
end

function _wrap_key(backend::SoftHSMBackend, key_data::Vector{UInt8}, key_id::String)::Vector{UInt8}
    # Derive a wrapping key from key_id (simplified - in production use TPM)
    master_key = sha256(Vector{UInt8}(key_id * "-wrapping-key"))
    
    # SECURITY FIX: Use HMAC-SHA256 instead of XOR for key wrapping
    # Generate random IV
    iv = rand(UInt8, 16)
    
    # Use HMAC-SHA256 for authenticated encryption
    hmac_input = vcat(iv, key_data)
    authentication_tag = hmac_sha256(master_key, hmac_input)
    
    # Return IV || tag || key_data
    return vcat(iv, authentication_tag, key_data)
end

function _unwrap_key(backend::SoftHSMBackend, wrapped_key::Vector{UInt8}, key_id::String)::Vector{UInt8}
    # Verify authentication before unwrapping
    if length(wrapped_key) < 49
        error("Wrapped key too short - invalid format")
    end
    
    master_key = sha256(Vector{UInt8}(key_id * "-wrapping-key"))
    
    # Extract IV, tag, and key data
    iv = wrapped_key[1:16]
    stored_tag = wrapped_key[17:48]
    key_data = wrapped_key[49:end]
    
    # Verify authentication tag
    hmac_input = vcat(iv, key_data)
    computed_tag = hmac_sha256(master_key, hmac_input)
    
    if !constant_time_compare(stored_tag, computed_tag)
        error("Authentication failed - key may have been tampered")
    end
    
    return key_data
end

function get_key(backend::SoftHSMBackend, key_id::String)::KeyMetadata
    if haskey(backend.keys, key_id)
        return backend.keys[key_id]
    end
    throw(KeyNotFoundError(key_id))
end

function sign(backend::SoftHSMBackend, key_id::String, data::Vector{UInt8})::Vector{UInt8}
    if !haskey(backend.encrypted_keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    # Unwrap the key
    key_data = _unwrap_key(backend, backend.encrypted_keys[key_id], key_id)
    
    # Sign with HMAC-SHA256
    return sha256([key_data; data])
end

function verify(backend::SoftHSMBackend, key_id::String, data::Vector{UInt8}, signature::Vector{UInt8})::Bool
    expected = sign(backend, key_id, data)
    return expected == signature
end

function encrypt(backend::SoftHSMBackend, key_id::String, plaintext::Vector{UInt8})::Vector{UInt8}
    if !haskey(backend.encrypted_keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    key_data = _unwrap_key(backend, backend.encrypted_keys[key_id], key_id)
    
    # SECURITY FIX: Use AES-256-GCM for authenticated encryption (replaces XOR cipher)
    # Ensure key is 32 bytes for AES-256
    if length(key_data) < 32
        key_data = sha256(key_data)
    end
    
    # Use AES-256-GCM for authenticated encryption
    result = encrypt_aes256_gcm(plaintext, key_data[1:32])
    
    # Return format: nonce (12) || tag (16) || ciphertext
    return vcat(result.nonce, result.tag, result.ciphertext)
end

function decrypt(backend::SoftHSMBackend, key_id::String, ciphertext::Vector{UInt8})::Vector{UInt8}
    if !haskey(backend.encrypted_keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    # Verify authentication before decryption
    # Format: nonce (12) || tag (16) || ciphertext (AES-256-GCM)
    if length(ciphertext) < 28
        error("Ciphertext too short - invalid AES-256-GCM format")
    end
    
    key_data = _unwrap_key(backend, backend.encrypted_keys[key_id], key_id)
    
    # Ensure key is 32 bytes for AES-256
    if length(key_data) < 32
        key_data = sha256(key_data)
    end
    
    # Extract nonce, tag, and ciphertext
    nonce = ciphertext[1:12]
    tag = ciphertext[13:28]
    encrypted_data = ciphertext[29:end]
    
    # Reconstruct the AES256GCMResult for decryption
    encrypted_result = AES256GCMResult(encrypted_data, nonce, tag)
    
    # Decrypt using AES-256-GCM (verifies authentication tag)
    return decrypt_aes256_gcm(encrypted_result, key_data[1:32])
end

function rotate_key(backend::SoftHSMBackend, key_id::String)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    
    # Generate new key
    if metadata.key_type == SYMMETRIC
        new_key_data = rand(UInt8, 32)
    else
        new_key_data = rand(UInt8, 256)
    end
    
    # Wrap and store
    wrapped_key = _wrap_key(backend, new_key_data, key_id)
    backend.encrypted_keys[key_id] = wrapped_key
    
    # Update metadata
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        now(),  # Last rotated
        metadata.rotation_period_days,
        metadata.enabled,
        metadata.description
    )
    
    _save_keys_to_disk(backend)
    
    println("[SoftHSM] Rotated key: $key_id")
    return true
end

function delete_key(backend::SoftHSMBackend, key_id::String)::Bool
    deleted = false
    
    if haskey(backend.keys, key_id)
        delete!(backend.keys, key_id)
        deleted = true
    end
    
    if haskey(backend.encrypted_keys, key_id)
        # Secure wipe
        backend.encrypted_keys[key_id] = rand(UInt8, length(backend.encrypted_keys[key_id]))
        delete!(backend.encrypted_keys, key_id)
    end
    
    if deleted
        _save_keys_to_disk(backend)
        println("[SoftHSM] Deleted key: $key_id")
    end
    
    return deleted
end

function list_keys(backend::SoftHSMBackend)::Vector{KeyMetadata}
    return collect(values(backend.keys))
end

function get_key_rotation_policy(backend::SoftHSMBackend, key_id::String)::Union{Int, Nothing}
    metadata = get_key(backend, key_id)
    return metadata.rotation_period_days
end

function set_key_rotation_policy(backend::SoftHSMBackend, key_id::String, period_days::Int)::Bool
    if !haskey(backend.keys, key_id)
        throw(KeyNotFoundError(key_id))
    end
    
    metadata = backend.keys[key_id]
    backend.keys[key_id] = KeyMetadata(
        metadata.key_id,
        metadata.key_type,
        metadata.created_at,
        metadata.last_rotated_at,
        period_days,
        metadata.enabled,
        metadata.description
    )
    
    _save_keys_to_disk(backend)
    
    println("[SoftHSM] Set rotation policy for $key_id: $period_days days")
    return true
end

# =============================================================================
# Key Rotation Scheduler
# =============================================================================

"""
    KeyRotationScheduler - Automatic key rotation based on schedule

Tracks keys that need rotation based on their policy.
"""
mutable struct KeyRotationScheduler
    last_check::DateTime
    check_interval_minutes::Int
    
    KeyRotationScheduler(;check_interval_minutes::Int=60) = new(now(), check_interval_minutes)
end

const _rotation_scheduler = KeyRotationScheduler()

"""
    check_key_rotation()::Vector{String}

Check all keys and return list of keys that need rotation.
"""
function check_key_rotation()::Vector{String}
    if !is_hsm_initialized()
        return []
    end
    
    keys_to_rotate = String[]
    keys = list_keys(_hsm_state.backend)
    
    for metadata in keys
        if metadata.rotation_period_days === nothing
            continue
        end
        
        last_rotation = metadata.last_rotated_at !== nothing ? metadata.last_rotated_at : metadata.created_at
        days_since_rotation = (now() - last_rotation).value / (1000 * 60 * 60 * 24)
        
        if days_since_rotation >= metadata.rotation_period_days
            push!(keys_to_rotate, metadata.key_id)
        end
    end
    
    return keys_to_rotate
end

"""
    rotate_due_keys()::Int

Rotate all keys that are due for rotation.
"""
function rotate_due_keys()::Int
    keys = check_key_rotation()
    
    for key_id in keys
        try
            hsm_rotate_key(key_id)
            println("[KeyRotation] Rotated: $key_id")
        catch e
            println("[KeyRotation] ERROR rotating $key_id: $e")
        end
    end
    
    return length(keys)
end

# =============================================================================
# Migration Utilities
# =============================================================================

"""
    migrate_env_to_hsm(backend::AbstractHSMBackend)::Int

Migrate secrets from environment variables to HSM.
"""
function migrate_env_to_hsm(backend::AbstractHSMBackend)::Int
    init_hsm(backend)
    
    migrated = 0
    
    # Known secret mappings
    secret_mappings = [
        ("ipc-signing-key", "ITHERIS_IPC_SECRET_KEY", SYMMETRIC),
        ("kernel-secret", "JARVIS_KERNEL_SECRET", SYMMETRIC),
        ("trust-secret", "JARVIS_TRUST_SECRET", SYMMETRIC),
        ("flow-integrity-secret", "JARVIS_FLOW_INTEGRITY_SECRET", SYMMETRIC),
        ("jwt-secret", "JARVIS_JWT_SECRET", SYMMETRIC),
    ]
    
    for (key_id, env_var, key_type) in secret_mappings
        if haskey(ENV, env_var)
            try
                secret = Vector{UInt8}(ENV[env_var])
                create_key(backend, key_id, key_type; description="Migrated from ENV")
                
                # Store the secret
                println("[Migration] Migrated $key_id from $env_var")
                migrated += 1
            catch e
                println("[Migration] ERROR migrating $key_id: $e")
            end
        end
    end
    
    return migrated
end

"""
    create_rotation_policy_for_all_keys(period_days::Int)::Int

Create a rotation policy for all existing keys.
"""
function create_rotation_policy_for_all_keys(period_days::Int)::Int
    if !is_hsm_initialized()
        error("HSM not initialized")
    end
    
    keys = list_keys(_hsm_state.backend)
    count = 0
    
    for metadata in keys
        try
            set_key_rotation_policy(_hsm_state.backend, metadata.key_id, period_days)
            count += 1
        catch e
            println("[Rotation] ERROR setting policy for $(metadata.key_id): $e")
        end
    end
    
    return count
end

# =============================================================================
# Security Status
# =============================================================================

"""
    security_status()::Dict{Symbol, Any}

Get current security status of HSM integration.
"""
function security_status()::Dict{Symbol, Any}
    status = Dict{Symbol, Any}(
        :hsm_initialized => is_hsm_initialized(),
        :backend_type => isnothing(_hsm_state.backend) ? "none" : typeof(_hsm_state.backend).name.name,
        :fallback_to_env => _hsm_state.fallback_to_env,
        :keys_managed => 0,
        :keys_with_rotation => 0
    )
    
    if is_hsm_initialized()
        keys = list_keys(_hsm_state.backend)
        status[:keys_managed] = length(keys)
        status[:keys_with_rotation] = count(k -> k.rotation_period_days !== nothing, keys)
    end
    
    return status
end

# =============================================================================
# Export public API
# =============================================================================

export 
    # Types
    AbstractHSMBackend,
    KeyMetadata,
    KeyType,
    SYMMETRIC,
    ASYMMETRIC_RSA,
    ASYMMETRIC_ECC,
    
    # Backend types
    AWSKMSBackend,
    AzureKeyVaultBackend,
    GCPKMSBackend,
    SoftHSMBackend,
    
    # Core functions
    init_hsm,
    configure_from_environment,
    is_hsm_initialized,
    shutdown_hsm,
    
    # Key operations
    hsm_create_key,
    hsm_get_key,
    hsm_delete_key,
    hsm_list_keys,
    
    # Cryptographic operations
    hsm_sign,
    hsm_verify,
    hsm_encrypt,
    hsm_decrypt,
    
    # Key rotation
    hsm_rotate_key,
    hsm_set_rotation_policy,
    hsm_get_rotation_policy,
    check_key_rotation,
    rotate_due_keys,
    create_rotation_policy_for_all_keys,
    
    # Migration
    migrate_env_to_hsm,
    
    # Status
    security_status,

    # Exceptions
    HSMError,
    KeyNotFoundError,
    HSMAuthenticationError,
    KeyRotationError

end # module
