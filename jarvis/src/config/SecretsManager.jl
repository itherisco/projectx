# SecretsManager - Secure secrets loading from Vault or ENV
using SHA
using Base64
using Nettle
using Random

mutable struct SecretsManager
    vault_addr::Union{String, Nothing}
    vault_token::Union{String, Nothing}
    cache::Dict{String, String}
    
    function SecretsManager()
        vault_addr = get(ENV, "JARVIS_VAULT_ADDR", nothing)
        vault_token = get(ENV, "JARVIS_VAULT_TOKEN", nothing)
        new(vault_addr, vault_token, Dict{String, String}())
    end
end

"""
SecureSecretsManager - Encrypted secrets cache using AES-256-GCM encryption

This struct provides encrypted in-memory caching of secrets to prevent
CWE-316: Cleartext Storage of Sensitive Information vulnerabilities.
Encryption key is derived from JARVIS_SECRETS_KEY environment variable.

Usage:
    Set JARVIS_SECRETS_KEY environment variable before use.
    manager = SecureSecretsManager()
    secret = get_secret(manager, "api_key")
"""
mutable struct SecureSecretsManager
    cache::Dict{String, String}  # Encrypted strings (base64 encoded)
    key::Vector{UInt8}  # 32-byte key derived from JARVIS_SECRETS_KEY
    
    function SecureSecretsManager()
        key_str = get(ENV, "JARVIS_SECRETS_KEY", "")
        if isempty(key_str)
            error("JARVIS_SECRETS_KEY environment variable must be set for encrypted secrets cache")
        end
        # Use SHA-256 to derive a 32-byte key from the secret
        key = sha256(key_str)
        new(Dict{String, String}(), key)
    end
end

# ============================================================================
# CRYPTOGRAPHIC CONSTANTS - 2026 Security Standard
# ============================================================================

const PBKDF2_ITERATIONS::Int = 600_000
const AES_GCM_NONCE_BYTES::Int = 12
const AES_GCM_TAG_BYTES::Int = 16
const SALT_BYTES::Int = 32

# ============================================================================
# AES-256-GCM ENCRYPTION - 2026 Security Standard
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
# LEGACY AES-256-CBC + HMAC-SHA256 (for backward compatibility)
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
# SECRET RETRIEVAL
# ============================================================================

"""
Load secret from Vault or fall back to ENV.
"""
function get_secret(manager::SecretsManager, key::String)::String
    haskey(manager.cache, key) && return manager.cache[key]
    
    if manager.vault_addr !== nothing && manager.vault_token !== nothing
        secret = _load_from_vault(manager, key)
        if secret !== nothing
            manager.cache[key] = secret
            return secret
        end
    end
    
    env_key = "JARVIS_$(uppercase(key))"
    secret = get(ENV, env_key, "")
    
    if isempty(secret)
        @warn "Secret $key not found in Vault or ENV (key: $env_key)"
        return ""
    end
    
    manager.cache[key] = secret
    return secret
end

"""
Load secret with encrypted caching from Vault or ENV.
"""
function get_secret(manager::SecureSecretsManager, key::String)::String
    if haskey(manager.cache, key)
        encrypted_value = manager.cache[key]
        return decrypt_value_aes256gcm(encrypted_value, manager.key)
    end
    
    vault_addr = get(ENV, "JARVIS_VAULT_ADDR", nothing)
    vault_token = get(ENV, "JARVIS_VAULT_TOKEN", nothing)
    
    if vault_addr !== nothing && vault_token !== nothing
        encrypted_value = _load_from_vault_encrypted(manager, key)
        if !isempty(encrypted_value)
            manager.cache[key] = encrypted_value
            return decrypt_value_aes256gcm(encrypted_value, manager.key)
        end
    end
    
    env_key = "JARVIS_$(uppercase(key))"
    secret = get(ENV, env_key, "")
    
    if isempty(secret)
        return ""
    end
    
    encrypted_value = encrypt_value_aes256gcm(secret, manager.key)
    manager.cache[key] = encrypted_value
    return secret
end

"""
Store secret in encrypted cache.
"""
function set_secret(manager::SecureSecretsManager, key::String, value::String)::Nothing
    encrypted_value = encrypt_value_aes256gcm(value, manager.key)
    manager.cache[key] = encrypted_value
    return nothing
end

# ============================================================================
# VAULT INTEGRATION (Placeholder)
# ============================================================================

function _load_from_vault(manager::SecretsManager, key::String)::Union{String, Nothing}
    return nothing
end

function _load_from_vault_encrypted(manager::SecureSecretsManager, key::String)::String
    return ""
end
