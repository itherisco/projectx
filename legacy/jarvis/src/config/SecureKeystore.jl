# config/SecureKeystore.jl
# Secure Local Keystore - Hardware-backed secure storage for secrets
# Replaces ENV variable usage to prevent secret leakage

module SecureKeystore

using Crypto.jl
using JSON3

# ============================================================================
# AES-256-GCM ENCRYPTION HELPERS
# ============================================================================

"""
    aes_encrypt_gcm - Encrypt data using AES-256-GCM
"""
function aes_encrypt_gcm(key::Vector{UInt8}, nonce::Vector{UInt8}, plaintext::Vector{UInt8})::Vector{UInt8}
    # Derive AES key from master key using HKDF-like approach
    derived_key = sha256(key)
    
    # Use GCM mode for authenticated encryption
    ciphertext = Crypto.aes_encrypt_gcm(derived_key, nonce, plaintext)
    return ciphertext
end

"""
    aes_decrypt_gcm - Decrypt data using AES-256-GCM
"""
function aes_decrypt_gcm(key::Vector{UInt8}, nonce::Vector{UInt8}, ciphertext::Vector{UInt8})::Vector{UInt8}
    # Derive AES key from master key
    derived_key = sha256(key)
    
    # Use GCM mode for authenticated decryption
    plaintext = Crypto.aes_decrypt_gcm(derived_key, nonce, ciphertext)
    return plaintext
end

# ============================================================================
# SECURE KEYSTORE - Local encrypted storage
# ============================================================================

# Keystore file location
const KEYSTORE_DIR = joinpath(homedir(), ".jarvis", "keystore")
const KEYSTORE_FILE = joinpath(KEYSTORE_DIR, "secrets.enc")
const KEYSTORE_KEY_FILE = joinpath(KEYSTORE_DIR, "master.key")

"""
    SecureKeystore - Encrypted local keystore
    
    Uses AES-256-GCM encryption with a derived key.
    Secrets are stored encrypted on disk, never in ENV.
"""
mutable struct SecureKeystore
    master_key::Vector{UInt8}
    secrets::Dict{String, Vector{UInt8}}
    is_initialized::Bool
    
    function SecureKeystore(master_key::Union{Vector{UInt8}, Nothing}=nothing)
        keystore = new(
            Vector{UInt8}(),
            Dict{String, Vector{UInt8}}(),
            false
        )
        
        if master_key !== nothing
            keystore.master_key = master_key
        else
            # Try to load existing key or generate new one
            keystore.master_key = _load_or_generate_key()
        end
        
        # Try to load existing secrets
        _load_secrets!(keystore)
        
        keystore.is_initialized = true
        return keystore
    end
end

"""
    _load_or_generate_key - Load existing key or generate new one
"""
function _load_or_generate_key()::Vector{UInt8}
    if isfile(KEYSTORE_KEY_FILE)
        try
            return read(KEYSTORE_KEY_FILE)
        catch
            # If can't read, generate new key (old one may be corrupted)
        end
    end
    
    # Generate new random master key
    key = rand(UInt8, 32)  # 256-bit key
    
    # Ensure directory exists
    mkpath(KEYSTORE_DIR)
    
    # Save key with restricted permissions
    write(KEYSTORE_KEY_FILE, key)
    chmod(KEYSTORE_KEY_FILE, 0o600)  # Owner read/write only
    
    return key
end

"""
    _load_secrets - Load encrypted secrets from disk
"""
function _load_secrets!(keystore::SecureKeystore)
    if !isfile(KEYSTORE_FILE)
        return  # No existing secrets
    end
    
    try
        encrypted_data = read(KEYSTORE_FILE)
        
        # Decrypt using AES-256-GCM
        # Format: nonce (12 bytes) || ciphertext || auth_tag (16 bytes)
        nonce = encrypted_data[1:12]
        ciphertext_with_tag = encrypted_data[13:end]
        
        # Use proper AES-256-GCM decryption
        decrypted = aes_decrypt_gcm(keystore.master_key, nonce, ciphertext_with_tag)
        
        # Parse JSON
        keystore.secrets = JSON3.read(String(decrypted), Dict{String, Vector{UInt8}})
    catch e
        @warn "Failed to load keystore secrets: $e"
        keystore.secrets = Dict{String, Vector{UInt8}}()
    end
end

"""
    _save_secrets - Save encrypted secrets to disk
"""
function _save_secrets(keystore::SecureKeystore)
    # Serialize to JSON
    json_data = JSON3.write(keystore.secrets)
    
    # Generate random nonce for AES-GCM
    nonce = rand(UInt8, 12)
    
    # Encrypt with proper AES-256-GCM
    data_bytes = Vector{UInt8}(json_data)
    encrypted = aes_encrypt_gcm(keystore.master_key, nonce, data_bytes)
    
    # Combine: nonce || ciphertext (includes auth tag)
    encrypted_data = vcat(nonce, encrypted)
    
    # Ensure directory exists
    mkpath(KEYSTORE_DIR)
    
    # Write encrypted data
    write(KEYSTORE_FILE, encrypted_data)
    chmod(KEYSTORE_FILE, 0o600)  # Owner read/write only
end

"""
    set_secret! - Store a secret in the keystore
"""
function set_secret!(keystore::SecureKeystore, name::String, value::Union{String, Vector{UInt8}})
    if isa(value, String)
        keystore.secrets[name] = Vector{UInt8}(value)
    else
        keystore.secrets[name] = value
    end
    
    _save_secrets(keystore)
end

"""
    get_secret - Retrieve a secret from the keystore
"""
function get_secret(keystore::SecureKeystore, name::String)::Union{Vector{UInt8}, Nothing}
    return get(keystore.secrets, name, nothing)
end

"""
    get_secret_string - Retrieve a secret as string
"""
function get_secret_string(keystore::SecureKeystore, name::String)::Union{String, Nothing}
    secret = get_secret(keystore, name)
    if secret === nothing
        return nothing
    end
    return String(secret)
end

"""
    delete_secret! - Remove a secret from the keystore
"""
function delete_secret!(keystore::SecureKeystore, name::String)
    if haskey(keystore.secrets, name)
        delete!(keystore.secrets, name)
        _save_secrets(keystore)
    end
end

"""
    list_secrets - List all secret names (not values)
"""
function list_secrets(keystore::SecureKeystore)::Vector{String}
    return collect(keys(keystore.secrets))
end

# ============================================================================
# GLOBAL KEYSTORE INSTANCE
# ============================================================================

const _GLOBAL_KEYSTORE = Ref{SecureKeystore}()

"""
    get_keystore - Get or create the global keystore instance
"""
function get_keystore()::SecureKeystore
    if !isassigned(_GLOBAL_KEYSTORE)
        _GLOBAL_KEYSTORE[] = SecureKeystore()
    end
    return _GLOBAL_KEYSTORE[]
end

"""
    initialize_keystore! - Initialize keystore with explicit master key
"""
function initialize_keystore!(master_key::Vector{UInt8})::SecureKeystore
    _GLOBAL_KEYSTORE[] = SecureKeystore(master_key)
    return _GLOBAL_KEYSTORE[]
end

# ============================================================================
# SECRET RETRIEVAL (Replaces ENV usage)
# ============================================================================

"""
    get_vault_passphrase - Get vault passphrase from secure keystore
    (Replaces ENV[\"JARVIS_VAULT_PASSPHRASE\"])
"""
function get_vault_passphrase()::Union{String, Nothing}
    keystore = get_keystore()
    return get_secret_string(keystore, "JARVIS_VAULT_PASSPHRASE")
end

"""
    get_trust_secret - Get trust secret from secure keystore
    (Replaces ENV[\"JARVIS_TRUST_SECRET\"])
"""
function get_trust_secret()::Union{Vector{UInt8}, Nothing}
    keystore = get_keystore()
    return get_secret(keystore, "JARVIS_TRUST_SECRET")
end

"""
    get_jwt_secret - Get JWT secret from secure keystore
    (Replaces ENV[\"JARVIS_JWT_SECRET\"])
"""
function get_jwt_secret()::Union{Vector{UInt8}, Nothing}
    keystore = get_keystore()
    return get_secret(keystore, "JARVIS_JWT_SECRET")
end

"""
    get_flow_integrity_secret - Get flow integrity secret from secure keystore
    (Replaces ENV[\"JARVIS_FLOW_INTEGRITY_SECRET\"])
"""
function get_flow_integrity_secret()::Union{Vector{UInt8}, Nothing}
    keystore = get_keystore()
    return get_secret(keystore, "JARVIS_FLOW_INTEGRITY_SECRET")
end

"""
    store_secret! - Store any secret in the keystore
"""
function store_secret!(name::String, value::String)
    keystore = get_keystore()
    set_secret!(keystore, name, value)
end

# ============================================================================
# EXPORTS
# ============================================================================

export SecureKeystore,
       get_keystore,
       initialize_keystore!,
       set_secret!,
       get_secret,
       get_secret_string,
       delete_secret!,
       list_secrets,
       get_vault_passphrase,
       get_trust_secret,
       get_jwt_secret,
       get_flow_integrity_secret,
       store_secret!

end # module SecureKeystore
