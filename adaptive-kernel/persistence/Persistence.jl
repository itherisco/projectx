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
    timestamp = time() % UInt64(1e9)  # Use lower 9 digits of timestamp
    
    # Combine counter and timestamp into 12 bytes
    nonce = Vector{UInt8}(12)
    nonce[1:8] = reinterpret(UInt8, [counter])
    nonce[9:12] = reinterpret(UInt8, [timestamp])
    
    return nonce
end

"""
    encrypt_log(plaintext::String)::String
Encrypt plaintext using AES-256-GCM with a unique nonce per encryption.
Returns base64-encoded nonce || ciphertext || auth_tag.
If no key is configured, returns plaintext unchanged.
"""
function encrypt_log(plaintext::String)::String
    if EVENT_LOG_KEY === nothing
        @warn "No encryption key configured - storing plaintext"
        return plaintext
    end
    
    # Ensure we have a 32-byte key for AES-256
    key = EVENT_LOG_KEY
    if length(key) < 32
        key = sha256(key)  # Expand short keys to 32 bytes
    end
    
    # Generate unique nonce
    nonce = get_next_nonce()
    
    # Encrypt using AES-256-GCM (Nettle's gcm_encrypt returns nonce || ciphertext || tag)
    ciphertext = gcm_encrypt("AES256", key, nonce, Vector{UInt8}(plaintext))
    
    # Prepend nonce to ciphertext for storage
    return base64encode(nonce * ciphertext)
end

"""
    decrypt_log(ciphertext_b64::String)::String
Decrypt base64-encoded ciphertext using AES-256-GCM.
Returns plaintext on success, throws error on authentication failure.
If no key is configured, returns ciphertext unchanged (for backwards compatibility).
"""
function decrypt_log(ciphertext_b64::String)::String
    if EVENT_LOG_KEY === nothing
        # No key configured - check if it's actually plaintext (JSON)
        # If it looks like plaintext JSON, return as-is for backwards compatibility
        try
            JSON.parse(ciphertext_b64)
            return ciphertext_b64  # It's valid JSON, treat as plaintext
        catch
            error("Cannot decrypt: no key configured and data is not plaintext JSON")
        end
    end
    
    # Ensure we have a 32-byte key for AES-256
    key = EVENT_LOG_KEY
    if length(key) < 32
        key = sha256(key)
    end
    
    # Decode base64
    data = base64decode(ciphertext_b64)
    
    # Extract nonce (12 bytes) and ciphertext+tag
    if length(data) < 12 + 16  # nonce + minimum tag size
        error("Invalid ciphertext: too short")
    end
    
    nonce = data[1:12]
    ciphertext_with_tag = data[13:end]
    
    # Decrypt using AES-256-GCM (auth tag verified automatically)
    plaintext = gcm_decrypt("AES256", key, nonce, ciphertext_with_tag)
    
    return String(plaintext)
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
Uses AES-256-GCM encryption with unique nonces.
"""
function save_encrypted_state(state::Dict{String, Any})
    if EVENT_LOG_KEY === nothing
        @warn "No encryption key configured - cannot save encrypted state"
        return false
    end
    
    # Serialize state to JSON
    plaintext = JSON.json(state)
    
    # Encrypt using AES-256-GCM
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
        @warn "No encryption key configured - cannot load encrypted state"
        return nothing
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
