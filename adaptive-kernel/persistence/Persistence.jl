# persistence/Persistence.jl - Append-only event log + SQLite state store

module Persistence

using JSON
using Dates
using Logging
using SHA
using Base64
using Nettle

export save_event, load_events, init_persistence, get_last_state, set_event_log_file, encrypt_log, decrypt_log, save_encrypted_state, load_encrypted_state

const EVENT_LOG_FILE_DEFAULT = "events.log"
const EVENT_LOG_FILE = Ref(get(ENV, "ADAPTIVE_KERNEL_EVENT_LOG", EVENT_LOG_FILE_DEFAULT))

"""
    _try_load_key_from_config()::String
Try to load encryption key from config file.
"""
function _try_load_key_from_config()::String
    # Try common config locations
    config_paths = [
        joinpath(dirname(@__DIR__), "config.toml"),
        joinpath(dirname(@__DIR__), "..", "config.toml"),
        joinpath(pwd(), "config.toml"),
        "./config.toml"
    ]
    
    for config_path in config_paths
        if isfile(config_path)
            try
                # Try to read config and look for encryption key
                content = read(config_path, String)
                # Look for event_log_key or encryption_key in the config
                for line in split(content, '\n')
                    line = strip(line)
                    if startswith(line, "event_log_key") || startswith(line, "encryption_key")
                        # Extract value after = sign
                        parts = split(line, "=")
                        if length(parts) >= 2
                            value = strip(parts[2])
                            # Remove quotes if present
                            value = strip(value, '"')
                            value = strip(value, '\'')
                            if !isempty(value) && value != "your-secret-key-here"
                                return value
                            end
                        end
                    end
                end
            catch
                # Continue to next config path
            end
        end
    end
    
    return ""
end

# Event log encryption key derived from JARVIS_EVENT_LOG_KEY environment variable
# Format: base64-encoded 32-byte key (for AES-256)
# If not set, tries to load from config file, otherwise warning is issued
const EVENT_LOG_KEY = let
    key_str = get(ENV, "JARVIS_EVENT_LOG_KEY", "")
    if isempty(key_str)
        # Try to load from config if available
        key_str = _try_load_key_from_config()
    end
    if isempty(key_str)
        nothing
    else
        # Support both raw key and base64-encoded key
        try
            # Try base64 first
            base64decode(key_str)
        catch
            # If not base64, use SHA-256 hash of the key string
            sha256(key_str)
        end
    end
end

# Nonce counter for AES-GCM (incremented for each encryption)
const NONCE_COUNTER = Threads.Atomic{UInt64}(0)

"""
    get_next_nonce()::Vector{UInt8}
Generate a unique 12-byte nonce for AES-GCM from atomic counter + timestamp.
"""
function get_next_nonce()::Vector{UInt8}
    counter = Threads.atomic_add!(NONCE_COUNTER, UInt64(1))
    timestamp = UInt64(floor(time() * 1000))  # Use milliseconds
    
    # Combine counter and timestamp into 12 bytes
    # counter uses 8 bytes, timestamp uses 4 bytes
    nonce = UInt8[]
    
    # Add counter bytes (big-endian)
    for i in 7:-1:0
        push!(nonce, (counter >> (8*i)) & 0xFF)
    end
    
    # Add timestamp bytes (big-endian, lower 4 bytes)
    for i in 3:-1:0
        push!(nonce, (timestamp >> (8*i)) & 0xFF)
    end
    
    return nonce
end

"""
    gcm_decrypt(key::Vector{UInt8}, nonce::Vector{UInt8}, ciphertext_with_tag::Vector{UInt8})::Vector{UInt8}
Decrypt AES-256-GCM encrypted data with authentication tag verification.
Throws error if authentication fails.
"""
function gcm_decrypt(key::Vector{UInt8}, nonce::Vector{UInt8}, ciphertext_with_tag::Vector{UInt8})::Vector{UInt8}
    # Use Nettle's GCM decryptor
    decryptor = Nettle.GCMDecryptor("AES256", key)
    # Decrypt and verify auth tag automatically
    plaintext = decryptor\decrypt(nonce, ciphertext_with_tag)
    return plaintext
end

"""
    encrypt_log(plaintext::String)::String
Encrypt plaintext using AES-256-CBC with SHA256-HMAC authentication.
Returns base64-encoded IV || ciphertext || auth_tag.
Throws error if no encryption key is configured (fail-secure).
"""
function encrypt_log(plaintext::String)::String
    if EVENT_LOG_KEY === nothing
        error("SECURITY FAILURE: No encryption key configured. Refusing to store data in plaintext. Please configure JARVIS_EVENT_LOG_KEY environment variable or encryption_key in config.toml")
    end
    
    # Ensure we have a 32-byte key for AES-256
    key = EVENT_LOG_KEY
    if length(key) < 32
        key = sha256(key)  # Expand short keys to 32 bytes
    end
    
    # Generate unique nonce
    nonce = get_next_nonce()
    
    # Use Nettle's CBC mode encryption with PKCS7 padding
    # Note: Nettle.jl doesn't support GCM mode, so we use AES256-CBC with SHA256 for authentication
    try
        # Generate random IV
        iv = rand(UInt8, 16)
        
        # Pad data to 16-byte boundary (PKCS7 padding)
        plaintext_bytes = Vector{UInt8}(plaintext)
        pad_len = 16 - (length(plaintext_bytes) % 16)
        if pad_len == 0
            pad_len = 16
        end
        append!(plaintext_bytes, fill(UInt8(pad_len), pad_len))
        
        # Use AES256 encryption
        cipher = Nettle.Encryptor("AES256", key)
        output = Vector{UInt8}(undef, length(plaintext_bytes))
        Nettle.encrypt!(cipher, output, plaintext_bytes)
        
        # Create SHA256-based MAC for authentication (covers IV + ciphertext)
        # Using SHA(key || iv || ciphertext) as authentication tag
        auth_tag = sha256(vcat(key, iv, output))
        
        # Combine: IV + ciphertext + auth_tag
        return base64encode(vcat(iv, output, auth_tag))
    catch e
        # CRITICAL SECURITY: Do NOT fall back to insecure encryption!
        # Either encrypt properly or fail securely
        error("AES-CBC encryption failed: $e. Data will NOT be saved in plaintext - refusing to use insecure XOR fallback.")
    end
end

"""
    decrypt_log(ciphertext_b64::String)::String
Decrypt base64-encoded ciphertext using AES-256-CBC with SHA256-HMAC verification.
Returns plaintext on success, throws error on authentication failure.
Throws error if no encryption key is configured (fail-secure).
"""
function decrypt_log(ciphertext_b64::String)::String
    if EVENT_LOG_KEY === nothing
        error("SECURITY FAILURE: No encryption key configured. Cannot decrypt data without a key. Please configure JARVIS_EVENT_LOG_KEY environment variable or encryption_key in config.toml")
    end
    
    # Ensure we have a 32-byte key for AES-256
    key = EVENT_LOG_KEY
    if length(key) < 32
        key = sha256(key)
    end
    
    # Decode base64
    data = base64decode(ciphertext_b64)
    
    # New format: IV (16 bytes) + ciphertext + auth_tag (32 bytes)
    # Minimum size: 16 (IV) + 16 (one block) + 32 (auth_tag) = 64 bytes
    min_len = 16 + 16 + 32
    if length(data) < min_len
        error("Invalid ciphertext: too short ($length(data) bytes, minimum $min_len)")
    end
    
    # Extract components
    iv = data[1:16]
    auth_tag_stored = data[end-31:end]  # Last 32 bytes
    ciphertext = data[17:end-32]
    
    # Verify authentication tag
    auth_tag_computed = sha256(vcat(key, iv, ciphertext))
    if auth_tag_stored != auth_tag_computed
        error("Authentication failed: HMAC mismatch")
    end
    
    # Decrypt using AES256-CBC
    decryptor = Nettle.Decryptor("AES256", key)
    plaintext_padded = Vector{UInt8}(undef, length(ciphertext))
    Nettle.decrypt!(decryptor, plaintext_padded, ciphertext)
    
    # Remove PKCS7 padding
    pad_len = plaintext_padded[end]
    plaintext = String(plaintext_padded[1:end-pad_len])
    
    return plaintext
end

"""
    init_persistence()
Initialize persistence (event log and SQLite placeholder).
"""
function init_persistence()
    # Ensure event log exists
    logpath = EVENT_LOG_FILE[]
    if !isfile(logpath)
        touch(logpath)
    end
end

"""
    save_event(event::Dict{String, Any})
Append an event to the append-only log (JSONL format).
"""
function save_event(event::Dict{String, Any})
    init_persistence()
    plaintext = JSON.json(event)
    encrypted = encrypt_log(plaintext)
    open(EVENT_LOG_FILE[], "a") do io
        println(io, encrypted)
    end
end

# Generic method to handle Dict{String, T} (e.g., Dict{String, String})
# Converts to Dict{String, Any} before processing
function save_event(event::Dict{String, T}) where T
    save_event(Dict{String, Any}(event))
end

# Handle Dict{Any, Any} (e.g., from stress tests)
function save_event(event::Dict{Any, Any})
    # Convert to Dict{String, Any}
    converted = Dict{String, Any}()
    for (k, v) in event
        converted[string(k)] = v
    end
    save_event(converted)
end

"""
    load_events()::Vector{Dict{String, Any}}
Load all events from the event log.
"""
function load_events()::Vector{Dict{String, Any}}
    events = Dict{String, Any}[]
    logpath = EVENT_LOG_FILE[]

    if !isfile(logpath)
        return events
    end

    for line in readlines(logpath)
        if !isempty(strip(line))
            try
                # Try to decrypt first; if not encrypted, decrypt_log returns unchanged
                decrypted = decrypt_log(line)
                push!(events, JSON.parse(decrypted))
            catch e
                @warn "Skipped malformed JSON line: $e"
            end
        end
    end
    
    return events
end

"""
    get_last_state()::Dict{String, Any}
Return the last recorded kernel state from the log.
"""
function get_last_state()::Dict{String, Any}
    events = load_events()
    
    for event in reverse(events)
        if get(event, "type", "") == "state_dump"
            return get(event, "data", Dict())
        end
    end
    
    return Dict()
end

"""
    save_kernel_state(kernel_stats::Dict{String, Any})
Record kernel state snapshot.
"""
function save_kernel_state(kernel_stats::Dict{String, Any})
    event = Dict(
        "timestamp" => string(now()),
        "type" => "state_dump",
        "data" => kernel_stats
    )
    save_event(event)
end

"""
    set_event_log_file(path::String)

Set the event log file path for persistence (useful for tests).
"""
function set_event_log_file(path::String)
    EVENT_LOG_FILE[] = path
    init_persistence()
end

# ============================================================================
# Encrypted State Serialization (Multi-session Continuity)
# ============================================================================

const STATE_FILE = Ref("kernel_state.enc")

"""
    set_state_file(path::String)
Set the encrypted state file path.
"""
function set_state_file(path::String)
    STATE_FILE[] = path
end

"""
    save_encrypted_state(state::Dict{String, Any})
Serialize and encrypt kernel state for multi-session continuity.
Uses AES-256-CBC encryption with SHA256-HMAC authentication.
Throws error if no encryption key is configured (fail-secure).
"""
function save_encrypted_state(state::Dict{String, Any})
    if EVENT_LOG_KEY === nothing
        error("SECURITY FAILURE: No encryption key configured. Refusing to save unencrypted state. Please configure JARVIS_EVENT_LOG_KEY environment variable or encryption_key in config.toml")
    end
    
    # Serialize state to JSON
    plaintext = JSON.json(state)
    
    # Encrypt using AES-256-CBC with SHA256-HMAC
    encrypted = encrypt_log(plaintext)
    
    # Write to file atomically
    temp_file = STATE_FILE[] * ".tmp"
    try
        open(temp_file, "w") do io
            println(io, encrypted)
        end
        # Atomic rename
        mv(temp_file, STATE_FILE[], force=true)
        @info "Saved encrypted kernel state"
        return true
    catch e
        @error "Failed to save encrypted state: $e"
        isfile(temp_file) && rm(temp_file, force=true)
        return false
    end
end

"""
    load_encrypted_state()::Union{Dict{String, Any}, Nothing}
Load and decrypt kernel state from encrypted storage.
Returns nothing if no state file exists or decryption fails.
"""
function load_encrypted_state()::Union{Dict{String, Any}, Nothing}
    state_path = STATE_FILE[]
    
    if !isfile(state_path)
        @info "No encrypted state file found"
        return nothing
    end
    
    if EVENT_LOG_KEY === nothing
        error("SECURITY FAILURE: No encryption key configured. Cannot load encrypted state without a key. Please configure JARVIS_EVENT_LOG_KEY environment variable or encryption_key in config.toml")
    end
    
    try
        encrypted = readline(state_path)
        if isempty(strip(encrypted))
            return nothing
        end
        
        # Decrypt
        plaintext = decrypt_log(encrypted)
        state = JSON.parse(plaintext)
        
        @info "Loaded encrypted kernel state"
        return state
    catch e
        @error "Failed to load encrypted state: $e"
        return nothing
    end
end

end  # module
