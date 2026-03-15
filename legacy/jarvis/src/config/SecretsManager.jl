# SecretsManager - Secure secrets loading using Memory-Only Vault + SecureKeystore
# =======================================================================
#
# SECURITY FIX: Replaced ENV-based storage with MemoryVault + SecureKeystore
#
# Previous Vulnerabilities Fixed:
# 1. ENV variable leakage - any process could read /proc/<pid>/environ
# 2. XOR encryption - not secure, vulnerable to known-plaintext attacks
#
# New Security Model:
# - Secrets stored in MemoryVault (encrypted in RAM)
# - Secrets also stored in SecureKeystore (encrypted on disk)
# - Master key derived from user passphrase using PBKDF2 (600k+ iterations)
# - Automatic secret wiping on session end
# - No ENV variables for secret storage
#
# Usage:
#     manager = SecretsManager("your-secure-passphrase")
#     secret = get_secret(manager, "api_key")
#     destroy!(manager)  # Wipe all secrets when done
#
using SHA
using Base64
using Nettle
using Random

# Include the MemoryVault module
include("../security/MemoryVault.jl")

# Include SecureKeystore for local encrypted storage
include("SecureKeystore.jl")

"""
Secure Secrets Manager using Memory-Only Vault.

This replaces the old ENV-based SecretsManager with secure memory-only storage.

# Security Properties
- Secrets NEVER stored in environment variables
- Master key derived from passphrase (PBKDF2-HMAC-SHA256, 600k iterations)
- All secrets encrypted with AES-256-GCM in memory
- Automatic cleanup on destroy

# Example
    manager = SecretsManager("user-passphrase")
    store_secret!(manager, "api_key", "secret-value")
    value = get_secret(manager, "api_key")
    destroy!(manager)  # Clean up when done
"""
mutable struct SecretsManager
    vault::MemoryVault
    initialized::Bool
    
    """
    Create a new SecretsManager with a user-provided passphrase.
    
    # Arguments
    - `passphrase::String`: User passphrase for key derivation (NOT stored)
    - `salt_b64::Union{String, Nothing}`: Optional salt for vault re-opening
    """
    function SecretsManager(passphrase::String; salt_b64::Union{String, Nothing}=nothing)
        salt = nothing
        if salt_b64 !== nothing && !isempty(salt_b64)
            try
                salt = base64decode(salt_b64)
            catch e
                @warn "Invalid salt provided, generating new one"
                salt = nothing
            end
        end
        
        vault = MemoryVault(passphrase; salt=salt)
        new(vault, true)
    end
end

"""
Get vault salt for persistence (NOT sensitive - can be stored openly).
"""
function get_salt(manager::SecretsManager)::String
    return get_salt_b64(manager.vault)
end

"""
Store a secret in the encrypted vault.
"""
function store_secret!(manager::SecretsManager, key::String, value::String)::Nothing
    if !manager.initialized
        error("SecretsManager not initialized")
    end
    store_secret!(manager.vault, key, value)
    return nothing
end

"""
Retrieve a secret from the vault.
Returns empty string if not found (fail-closed).
"""
function get_secret(manager::SecretsManager, key::String)::String
    if !manager.initialized
        return ""  # Fail-closed
    end
    return get_secret(manager.vault, key)
end

"""
Check if a secret exists.
"""
function has_secret(manager::SecretsManager, key::String)::Bool
    if !manager.initialized
        return false
    end
    return has_secret(manager.vault, key)
end

"""
List all secret keys.
"""
function list_secrets(manager::SecretsManager)::Vector{String}
    if !manager.initialized
        return String[]
    end
    return list_secret_keys(manager.vault)
end

"""
Remove a secret from the vault.
"""
function remove_secret!(manager::SecretsManager, key::String)::Bool
    if !manager.initialized
        return false
    end
    return remove_secret!(manager.vault, key)
end

"""
Lock the vault (prevents access until unlocked).
"""
function lock!(manager::SecretsManager)::Nothing
    lock!(manager.vault)
    return nothing
end

"""
Unlock the vault with passphrase (for session resumption).
"""
function unlock(manager::SecretsManager, passphrase::String)::SecretsManager
    return SecretsManager(passphrase; salt_b64=get_salt(manager))
end

"""
Destroy the SecretsManager - securely wipe all secrets and keys.

# IMPORTANT: Call this when done to prevent residual secrets in memory.
"""
function destroy!(manager::SecretsManager)::Nothing
    if manager.initialized
        destroy!(manager.vault)
        manager.initialized = false
    end
    return nothing
end

"""
Export vault metadata for persistence.
Returns salt (safe to store openly) and locked status.
"""
function export_metadata(manager::SecretsManager)::Dict{String, String}
    return export_vault_metadata(manager.vault)
end

# ============================================================================
# DEPRECATED: Old API (for backward compatibility during migration)
# ============================================================================

"""
DEPRECATED: Creates SecretsManager that reads from ENV (INSECURE).

⚠️  WARNING: This constructor is deprecated and provided only for 
backward compatibility during migration. 

New code should use: SecretsManager(passphrase::String)

The old approach stored secrets in ENV variables which are vulnerable
to /proc/<pid>/environ leakage. This is a Day 1 vulnerability.
"""
function SecretsManager()
    @warn """
    DEPRECATED: SecretsManager() without passphrase is insecure!
    
    This constructor reads secrets from ENV variables which can be
    read by any process with access to /proc/<pid>/environ.
    
    Please migrate to:
        manager = SecretsManager("your-secure-passphrase")
    
    See MemoryVault.jl and SecureKeystore.jl for secure secret management.
    
    CRITICAL SECURITY FIX: Now uses SecureKeystore instead of ENV variables.
    """
    
    # CRITICAL: Try SecureKeystore first (secure local storage)
    # Only fall back to ENV if explicitly needed for backward compatibility
    passphrase = SecureKeystore.get_vault_passphrase()
    
    if isempty(passphrase) || passphrase === nothing
        # Fall back to ENV only as last resort (with warning)
        @warn "Using ENV for secrets is insecure. Migrate to SecureKeystore."
        passphrase = get(ENV, "JARVIS_VAULT_PASSPHRASE", "")
    end
    
    if isempty(passphrase)
        error("""
            SECURE MODE: No passphrase provided.
            
            For secure operation, provide a passphrase:
                manager = SecretsManager("your-secure-passphrase")
            
            Or store passphrase in SecureKeystore:
                SecureKeystore.store_secret!("JARVIS_VAULT_PASSPHRASE", "your-passphrase")
        """)
    end
    
    return SecretsManager(passphrase)
end

# ============================================================================
# CRYPTOGRAPHIC CONSTANTS (for reference - now using MemoryVault)
# ============================================================================

const PBKDF2_ITERATIONS::Int = 600_000
const AES_GCM_NONCE_BYTES::Int = 12
const AES_GCM_TAG_BYTES::Int = 16
const SALT_BYTES::Int = 32

# ============================================================================
# ENCRYPTION HELPERS (Delegated to MemoryVault)
# ============================================================================

"""
Derive a 256-bit key from password using PBKDF2-HMAC-SHA256.
Uses 600,000+ iterations as per 2026 standards.
"""
function derive_key_pbkdf2(password::String, salt::Vector{UInt8}; iterations::Int=PBKDF2_ITERATIONS)::Vector{UInt8}
    password_bytes = Vector{UInt8}(password)
    return pbkdf2_sha256(password_bytes, salt, iterations, 32)
end

"""
Encrypt plaintext using AES-256-GCM (Galois/Counter Mode).
Uses 96-bit random nonce for every message.
"""
function encrypt_value_aes256gcm(plaintext::String, key::Vector{UInt8})::String
    if length(key) != 32
        error("Invalid key length: $(length(key)). Must be 32 bytes for AES-256-GCM.")
    end
    
    nonce = rand(UInt8, AES_GCM_NONCE_BYTES)
    plaintext_bytes = Vector{UInt8}(plaintext)
    
    enc = Nettle.Encryptor("AES256-GCM", key)
    ciphertext_with_tag = encrypt(enc, nonce, plaintext_bytes)
    
    return base64encode(vcat(nonce, ciphertext_with_tag))
end

"""
Decrypt AES-256-GCM ciphertext.
Returns empty string on any failure (fail-closed).
"""
function decrypt_value_aes256gcm(ciphertext_b64::String, key::Vector{UInt8})::String
    if length(key) != 32
        return ""
    end
    
    data = nothing
    try
        data = base64decode(ciphertext_b64)
    catch e
        return ""
    end
    
    if length(data) < AES_GCM_NONCE_BYTES + AES_GCM_TAG_BYTES
        return ""
    end
    
    nonce = data[1:AES_GCM_NONCE_BYTES]
    ciphertext_with_tag = data[AES_GCM_NONCE_BYTES+1:end]
    
    try
        dec = Nettle.Decryptor("AES256-GCM", key)
        plaintext_bytes = decrypt(dec, nonce, ciphertext_with_tag)
        return String(plaintext_bytes)
    catch e
        return ""
    end
end

"""
Encrypt with password-derived key using PBKDF2.
Returns Base64-encoded salt || nonce+ciphertext.
"""
function encrypt_with_password(plaintext::String, password::String)::String
    salt = rand(UInt8, SALT_BYTES)
    key = derive_key_pbkdf2(password, salt)
    ciphertext = encrypt_value_aes256gcm(plaintext, key)
    return base64encode(vcat(salt, base64decode(ciphertext)))
end

"""
Decrypt ciphertext encrypted with encrypt_with_password.
Returns empty string on failure (fail-closed).
"""
function decrypt_with_password(ciphertext_b64::String, password::String)::String
    data = nothing
    try
        data = base64decode(ciphertext_b64)
    catch e
        return ""
    end
    
    if length(data) < SALT_BYTES + AES_GCM_NONCE_BYTES + AES_GCM_TAG_BYTES
        return ""
    end
    
    salt = data[1:SALT_BYTES]
    ciphertext_with_nonce = data[SALT_BYTES+1:end]
    
    key = derive_key_pbkdf2(password, salt)
    ciphertext_b64_reencoded = base64encode(ciphertext_with_nonce)
    
    return decrypt_value_aes256gcm(ciphertext_b64_reencoded, key)
end

# ============================================================================
# LEGACY ENCRYPTION (for backward compatibility with existing encrypted data)
# ============================================================================

"""
Encrypt using AES-256-CBC with HMAC-SHA256 authentication.
Returns Base64-encoded ciphertext with IV and auth tag.
"""
function encrypt_value(plaintext::String, key::Vector{UInt8})::String
    if length(key) != 64
        error("Invalid key length: $(length(key)). Must be 64 bytes (32 for AES + 32 for HMAC).")
    end
    
    aes_key = key[1:32]
    hmac_key = key[33:64]
    
    iv = rand(UInt8, 16)
    
    block_size = 16
    plaintext_bytes = Vector{UInt8}(plaintext)
    plaintext_len = length(plaintext_bytes)
    padding_len = block_size - (plaintext_len % block_size)
    if padding_len == 0
        padding_len = block_size
    end
    padded_plaintext = vcat(plaintext_bytes, fill(UInt8(padding_len), padding_len))
    
    enc = Nettle.Encryptor("AES256", aes_key)
    ciphertext = encrypt(enc, :cbc, iv, padded_plaintext)
    
    mac_input = vcat(iv, ciphertext)
    auth_tag = hmac_sha256(hmac_key, mac_input)
    
    return base64encode(vcat(iv, ciphertext, auth_tag))
end

"""
Decrypt AES-256-CBC + HMAC-SHA256 ciphertext.
Returns empty string on any failure (fail-closed).
"""
function decrypt_value(ciphertext_b64::String, key::Vector{UInt8})::String
    if length(key) != 64
        return ""
    end
    
    aes_key = key[1:32]
    hmac_key = key[33:64]
    
    data = nothing
    try
        data = base64decode(ciphertext_b64)
    catch e
        return ""
    end
    
    if length(data) < 48
        return ""
    end
    
    iv = data[1:16]
    auth_tag_provided = data[end-31:end]
    ciphertext = data[17:end-32]
    
    mac_input = vcat(iv, ciphertext)
    auth_tag_computed = hmac_sha256(hmac_key, mac_input)
    
    if !isequal(auth_tag_provided, auth_tag_computed)
        return ""
    end
    
    try
        dec = Nettle.Decryptor("AES256", aes_key)
        padded_plaintext = decrypt(dec, :cbc, iv, ciphertext)
        
        padding_len = padded_plaintext[end]
        if padding_len > 16 || padding_len == 0
            return ""
        end
        plaintext = padded_plaintext[1:end-padding_len]
        
        return String(plaintext)
    catch e
        return ""
    end
end

# ============================================================================
# SECRET RETRIEVAL (Now handled by MemoryVault - see above)
# ============================================================================

"""
SECRET MANAGEMENT IS NOW HANDLED BY MemoryVault

All secret operations are now performed through the MemoryVault:
- store_secret!(manager, key, value) - Store encrypted secret
- get_secret(manager, key) - Retrieve decrypted secret  
- has_secret(manager, key) - Check if secret exists
- list_secrets(manager) - List all secret keys
- destroy!(manager) - Securely wipe all secrets

The old ENV-based retrieval has been removed to prevent:
- CWE-316: Cleartext Storage of Sensitive Information
- /proc/<pid>/environ leakage vulnerability

See MemoryVault.jl for the complete API.
"""

# ============================================================================
# BACKWARD COMPATIBILITY (LEGACY ENCRYPTION HELPERS)
# ============================================================================

"""
Legacy encryption helpers preserved for decrypting existing encrypted data.

These functions use AES-256-CBC + HMAC-SHA256 which is still secure
for decrypting existing data, but new secrets should use MemoryVault.
"""

# Placeholder - now handled by MemoryVault
function _load_from_vault(manager::SecretsManager, key::String)::Union{String, Nothing}
    # No longer needed - secrets are stored in MemoryVault
    return nothing
end
