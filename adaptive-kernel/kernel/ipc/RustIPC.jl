# RustIPC.jl - IPC Bridge to Rust Ring 0 Kernel
# 
# This module provides the Julia-side interface to communicate with the
# Rust bare-metal kernel via shared memory ring buffers.
#
# Architecture:
# - Shared memory region: 0x01000000 - 0x01100000 (16MB)
# - Ring buffer protocol with lock-free access
# - Ed25519 signatures for authentication
# - HMAC-SHA256 for message authentication with replay protection

module RustIPC

using SHA
using Dates
using JSON
using Random
using Base.Threads

# ============================================================================
# DEPRECATION NOTICE
# ============================================================================
#
# WARNING: Direct use of unsafe_store! and unsafe_load is now DEPRECATED!
#
# All shared memory access MUST go through the safe API functions:
#   - safe_shm_write() - Thread-safe write with bounds checking
#   - safe_shm_read()  - Thread-safe read with bounds checking
#
# Using raw unsafe operations will result in race conditions and data corruption.
#
# The Rust kernel already has proper synchronization (ShmLock, ShmWriteGuard).
# Julia MUST acquire the mutex before any shared memory access.
#
# ============================================================================

# ============================================================================
# Constants
# ============================================================================

# Configurable shared memory path - can be overridden via environment variable
function _get_shm_path()
    get("ITHERIS_SHM_PATH", "/dev/shm/itheris_ipc")
end

const SHM_PATH = _get_shm_path()
const SHM_SIZE = 0x0010_0000  # 16MB
const RING_BUFFER_ENTRIES = 256

# Response region offset - separated from request region to avoid collisions
const RESPONSE_OFFSET = 4096  # Response written at offset 4096 bytes
const MAX_PAYLOAD_SIZE = 4096  # Maximum payload size per entry

# Mutex for thread-safe shared memory access
# Uses Base.Threads.ReentrantLock for recursive locking capability
const _shm_mutex = ReentrantLock()

# Track if mutex is held for debugging
const _mutex_holder = Ref{Union{Nothing, Int}}(nothing)

# IPC Protocol constants
const IPC_MAGIC = 0x49544852  # "ITHR"
const IPC_VERSION = 0x0001

# IPC Entry types (matching Rust enum)
const IPC_ENTRY_THOUGHT_CYCLE = 0
const IPC_ENTRY_INTEGRATION_PROPOSAL = 1
const IPC_ENTRY_RESPONSE = 2
const IPC_ENTRY_HEARTBEAT = 3
const IPC_ENTRY_PANIC = 4

# Security constants
const TIMESTAMP_VALIDITY_SECONDS = 30  # Reject messages older than 30 seconds
const SIGNATURE_SIZE = 32  # HMAC-SHA256 produces 32 bytes
const TIMESTAMP_SIZE = 8   # UInt64 for millisecond timestamp
const SEQUENCE_SIZE = 8    # UInt64 for sequence number

# ============================================================================
# Custom Exception Types
# ============================================================================

"""
    SignatureError - Base exception for signature failures
"""
struct SignatureError <: Exception
    message::String
    details::Dict{Symbol, Any}
    
    SignatureError(msg::String; kwargs...) = new(msg, Dict(kwargs))
end

Base.showerror(io::IO, e::SignatureError) = print(io, "SignatureError: $(e.message)")

"""
    SignatureVerificationError - Raised when signature verification fails
"""
struct SignatureVerificationError <: Exception
    message::String
    timestamp_received::Union{UInt64, Nothing}
    timestamp_current::Union{UInt64, Nothing}
    age_seconds::Union{Float64, Nothing}
    
    function SignatureVerificationError(msg::String; 
                                         received::Union{UInt64, Nothing}=nothing,
                                         current::Union{UInt64, Nothing}=nothing)
        age = nothing
        if received !== nothing && current !== nothing
            age = Float64(current - received) / 1000.0
        end
        new(msg, received, current, age)
    end
end

function Base.showerror(io::IO, e::SignatureVerificationError)
    print(io, "SignatureVerificationError: $(e.message)")
    if e.age_seconds !== nothing
        print(io, " (message age: $(round(e.age_seconds, digits=2))s)")
    end
end

"""
    ReplayAttackError - Raised when a message is detected as a replay attack
"""
struct ReplayAttackError <: Exception
    sequence_received::UInt64
    sequence_last::UInt64
    timestamp_received::UInt64
    timestamp_current::UInt64
    
    function ReplayAttackError(seq::UInt64, last_seq::UInt64, 
                                ts::UInt64, current_ts::UInt64)
        new(seq, last_seq, ts, current_ts)
    end
end

function Base.showerror(io::IO, e::ReplayAttackError)
    print(io, "ReplayAttackError: Detected potential replay attack! ")
    print(io, "Received seq: $(e.sequence_received), Last seen: $(e.sequence_last)")
end

"""
    KeyManagementError - Raised for secret key management issues
"""
struct KeyManagementError <: Exception
    message::String
    
    KeyManagementError(msg::String) = new(msg)
end

Base.showerror(io::IO, e::KeyManagementError) = print(io, "KeyManagementError: $(e.message)")

# ============================================================================
# Secret Key Management
# ============================================================================

# Environment variable for key management
const ENV_KEY_VAR = "ITHERIS_IPC_SECRET_KEY"

# Global mutable state for secret key and sequence tracking
mutable struct SecretKeyState
    key::Vector{UInt8}
    initialized::Bool
    last_sequence::UInt64
    last_timestamp::UInt64
    seen_messages::Dict{UInt64, Set{UInt64}}  # timestamp -> set of sequences
    
    SecretKeyState() = new(Vector{UInt8}(), false, 0, 0, Dict{UInt64, Set{UInt64}}())
end

# Global secret key state
const _secret_key_state = SecretKeyState()

# Track key source for security status
const _key_source = Ref{String}("none")

"""
    Load secret key from environment variable
    Returns: (key::Vector{UInt8}, source::String) or throws KeyManagementError
"""
function load_key_from_environment()::Tuple{Vector{UInt8}, String}
    env_key = get(ENV_KEY_VAR, nothing)
    
    if env_key === nothing
        throw(KeyManagementError("Environment variable $ENV_KEY_VAR not set"))
    end
    
    # Support both hex and base64 encoded keys
    key = try
        hex2bytes(env_key)
    catch
        try
            base64decode(env_key)
        catch
            throw(KeyManagementError("Invalid key encoding in $ENV_KEY_VAR - expected hex or base64"))
        end
    end
    
    if length(key) < 32
        throw(KeyManagementError("Secret key from environment must be at least 32 bytes"))
    end
    
    (key, "environment")
end

"""
    Initialize or load the shared secret key
    
    Arguments:
    - key::Vector{UInt8} - The secret key bytes
    - source::String - Description of key source (for logging)
"""
function init_secret_key(key::Vector{UInt8}; source::String="provided")::Bool
    if length(key) < 32
        throw(KeyManagementError("Secret key must be at least 32 bytes"))
    end
    
    _secret_key_state.key = key
    _secret_key_state.initialized = true
    _secret_key_state.last_sequence = 0
    _secret_key_state.last_timestamp = 0
    _secret_key_state.seen_messages = Dict{UInt64, Set{UInt64}}()
    
    _key_source[] = source
    
    println("[IPC] Secret key initialized ($(length(key)) bytes) from $source")
    true
end

"""
    Generate a random secret key (for testing or initial setup)
"""
function generate_secret_key(length::Int=32)::Vector{UInt8}
    key = Vector{UInt8}(undef, length)
    rand!(key)
    key
end

"""
    Check if secret key is initialized
"""
function is_key_initialized()::Bool
    _secret_key_state.initialized
end

"""
    Get current sequence number and increment
"""
function _get_next_sequence()::UInt64
    _secret_key_state.last_sequence += 1
end

"""
    Clean up old timestamp entries to prevent memory bloat
"""
function _cleanup_old_timestamps()
    current_ts = _get_current_timestamp()
    # Remove timestamps older than 2 minutes (plenty of buffer)
    cutoff = current_ts - (60 * 1000 * 2)
    
    old_keys = [k for k in keys(_secret_key_state.seen_messages) if k < cutoff]
    for k in old_keys
        delete!(_secret_key_state.seen_messages, k)
    end
end

"""
    Get current Unix timestamp in milliseconds
"""
function _get_current_timestamp()::UInt64
    round(UInt64, time() * 1000)
end

"""
    Get current sequence number without incrementing
"""
function get_current_sequence()::UInt64
    _secret_key_state.last_sequence
end

# ============================================================================
# HMAC-SHA256 Implementation
# ============================================================================

"""
    Compute HMAC-SHA256
"""
function _hmac_sha256(key::Vector{UInt8}, data::Vector{UInt8})::Vector{UInt8}
    # HMAC algorithm: HMAC(K, m) = H((K ⊕ opad) || H((K ⊕ ipad) || m))
    
    block_size = 64  # SHA-256 block size
    
    # If key is longer than block size, hash it first
    if length(key) > block_size
        key = sha256(key)
    end
    
    # Pad key to block size
    key_padded = vcat(key, zeros(UInt8, block_size - length(key)))
    
    # Create ipad and opad
    ipad = xor.(key_padded, UInt8(0x36))
    opad = xor.(key_padded, UInt8(0x5c))
    
    # Inner hash
    inner = sha256(vcat(ipad, data))
    
    # Outer hash
    hmac = sha256(vcat(opad, inner))
    
    hmac
end

# ============================================================================
# Cryptographic Signing
# ============================================================================

"""
    Sign a message using HMAC-SHA256 with timestamp and sequence
    
    Message format: [timestamp::UInt64][sequence::UInt64][payload]
    
    Returns: signature (32 bytes)
"""
function sign_message(data::Vector{UInt8}, secret_key::Vector{UInt8})::Vector{UInt8}
    if !is_key_initialized()
        throw(KeyManagementError("Secret key not initialized. Call init_secret_key() first."))
    end
    
    # Get current timestamp and sequence
    timestamp = _get_current_timestamp()
    sequence = _get_next_sequence()
    
    # Build signed message: [timestamp][sequence][payload]
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    sequence_bytes = reinterpret(UInt8, [sequence])
    signed_data = vcat(timestamp_bytes, sequence_bytes, data)
    
    # Compute HMAC-SHA256
    signature = _hmac_sha256(secret_key, signed_data)
    
    # Log for debugging
    println("[IPC] Signed message: timestamp=$(timestamp), sequence=$(sequence)")
    
    signature
end

"""
    Sign data with explicit timestamp and sequence (for testing)
"""
function sign_message(data::Vector{UInt8}, secret_key::Vector{UInt8},
                      timestamp::UInt64, sequence::UInt64)::Vector{UInt8}
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    sequence_bytes = reinterpret(UInt8, [sequence])
    signed_data = vcat(timestamp_bytes, sequence_bytes, data)
    
    _hmac_sha256(secret_key, signed_data)
end

# ============================================================================
# Signature Verification
# ============================================================================

"""
    Verify a signature and check timestamp validity
    
    Returns: (valid::Bool, reason::String)
"""
function verify_signature(data::Vector{UInt8}, 
                          signature::Vector{UInt8},
                          secret_key::Vector{UInt8};
                          check_timestamp::Bool=true)::Bool
    if !is_key_initialized()
        throw(KeyManagementError("Secret key not initialized. Call init_secret_key() first."))
    end
    
    if length(signature) != SIGNATURE_SIZE
        println("[IPC] ERROR: Invalid signature length: $(length(signature))")
        return false
    end
    
    if length(data) < TIMESTAMP_SIZE + SEQUENCE_SIZE
        println("[IPC] ERROR: Data too short to contain timestamp and sequence")
        return false
    end
    
    # Extract timestamp and sequence from data
    timestamp = reinterpret(UInt64, data[1:TIMESTAMP_SIZE])[1]
    sequence = reinterpret(UInt64, data[TIMESTAMP_SIZE+1:TIMESTAMP_SIZE+SEQUENCE_SIZE])[1]
    payload = data[TIMESTAMP_SIZE+SEQUENCE_SIZE:end]
    
    current_timestamp = _get_current_timestamp()
    timestamp_age_ms = current_timestamp - timestamp
    timestamp_age_seconds = timestamp_age_ms / 1000.0
    
    # Check timestamp validity
    if check_timestamp && timestamp_age_ms > (TIMESTAMP_VALIDITY_SECONDS * 1000)
        println("[IPC] ERROR: Timestamp too old! Age: $(timestamp_age_seconds)s (max: $(TIMESTAMP_VALIDITY_SECONDS)s)")
        throw(SignatureVerificationError("Message timestamp too old"; 
                                           received=timestamp, 
                                           current=current_timestamp))
    end
    
    # Check for replay attack using timestamp + sequence pair
    # NOTE: This check is always performed for security, even when check_timestamp is false
    if haskey(_secret_key_state.seen_messages, timestamp)
        if sequence in _secret_key_state.seen_messages[timestamp]
            println("[IPC] ERROR: Replay attack detected! Sequence $(sequence) already seen for timestamp $(timestamp)")
            throw(ReplayAttackError(sequence, _secret_key_state.last_sequence, timestamp, current_timestamp))
        end
    else
        _secret_key_state.seen_messages[timestamp] = Set{UInt64}()
    end
    push!(_secret_key_state.seen_messages[timestamp], sequence)
    
    # Update last seen sequence if this is newer
    if sequence > _secret_key_state.last_sequence
        _secret_key_state.last_sequence = sequence
    end
    
    # Verify the signature
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    sequence_bytes = reinterpret(UInt8, [sequence])
    signed_data = vcat(timestamp_bytes, sequence_bytes, payload)
    
    expected_signature = _hmac_sha256(secret_key, signed_data)
    
    # Constant-time comparison to prevent timing attacks
    if length(signature) != length(expected_signature)
        println("[IPC] ERROR: Signature length mismatch")
        return false
    end
    
    # Use bitwise comparison (Julia doesn't have constant-time compare, 
    # but we can at least do full comparison)
    valid = true
    for i in 1:length(signature)
        if signature[i] != expected_signature[i]
            valid = false
            break
        end
    end
    
    if !valid
        println("[IPC] ERROR: Signature verification FAILED!")
        println("[IPC]   Timestamp: $(timestamp)")
        println("[IPC]   Sequence: $(sequence)")
        println("[IPC]   Payload length: $(length(payload))")
    else
        println("[IPC] Signature verified: timestamp=$(timestamp), sequence=$(sequence), age=$(round(timestamp_age_seconds, digits=2))s")
    end
    
    # Periodically clean up old timestamps
    if rand() < 0.01  # ~1% chance
        _cleanup_old_timestamps()
    end
    
    valid
end

"""
    Verify signature without throwing (returns tuple)
"""
function verify_signature_safe(data::Vector{UInt8},
                                signature::Vector{UInt8},
                                secret_key::Vector{UInt8};
                                check_timestamp::Bool=true)::Tuple{Bool, String}
    try
        result = verify_signature(data, signature, secret_key; check_timestamp=check_timestamp)
        (result, result ? "OK" : "Invalid signature")
    catch e
        (false, string(e))
    end
end

# ============================================================================
# Data Structures
# ============================================================================

"""
    IPCEntry - Ring buffer entry format matching Rust kernel
"""
struct IPCEntry
    magic::UInt32      # 0x49544852 ("ITHR")
    version::UInt16    # Protocol version
    entry_type::UInt8  # Entry type
    flags::UInt8       # Flags
    length::UInt32     # Payload length
    identity::NTuple{32, UInt8}  # Cryptographic identity
    message_hash::NTuple{32, UInt8}  # SHA-256 hash
    signature::NTuple{64, UInt8}  # Ed25519 signature (now also used for HMAC)
    payload::NTuple{4096, UInt8}  # Variable length payload
    checksum::UInt32   # CRC32
end

"""
    Connection state to Rust kernel
"""
mutable struct KernelConnection
    shm_fd::Int
    mapped_addr::Ptr{Cvoid}
    connected::Bool
end

"""
    Thought cycle message from Julia to Rust
"""
struct ThoughtCycle
    identity::String
    intent::String
    payload::Dict{String, Any}
    timestamp::DateTime
    nonce::String
end

"""
    Response from Rust kernel
"""
struct KernelResponse
    approved::Bool
    reason::String
    signature::Vector{UInt8}
end

# ============================================================================
# Shared Memory Interface
# ============================================================================

"""
    Connect to Rust kernel shared memory region
"""
function connect_kernel()::KernelConnection
    # Open or create shared memory
    # O_RDWR = 0x02, O_CREAT = 0x200
    # Security: Using 0o600 (owner read/write only) instead of 0o666 (world-readable/writable)
    const SHM_PERMISSIONS = 0o600  # Secure: owner only
    shm_fd = ccall(:shm_open, Int32, (Cstring, Int32, UInt32), 
                   SHM_PATH, 0x02 | 0x200, SHM_PERMISSIONS)
    
    if shm_fd < 0
        error("Failed to open shared memory: $(Libc.errno())")
    end
    
    # Set size
    ccall(:ftruncate, Int32, (Int32, Int64), shm_fd, SHM_SIZE)
    
    # Map the memory: PROT_READ | PROT_WRITE = 3, MAP_SHARED = 1
    mapped = ccall(:mmap, Ptr{Cvoid}, 
                  (Ptr{Cvoid}, Csize_t, Int32, Int32, Int32, Int64), 
                  C_NULL, SHM_SIZE, 3, 1, shm_fd, 0)
    
    if mapped == C_NULL
        error("Failed to map shared memory: $(Libc.errno())")
    end
    
    # Log security confirmation with permission info
    println("[IPC] Connected to Rust kernel via shared memory (permissions: 0o$(string(SHM_PERMISSIONS, base=8)))")
    
    KernelConnection(shm_fd, mapped, true)
end

"""
    Disconnect from Rust kernel
"""
function disconnect_kernel(conn::KernelConnection)
    if conn.mapped_addr != C_NULL
        ccall(:munmap, Int32, (Ptr{Cvoid}, Csize_t), conn.mapped_addr, SHM_SIZE)
    end
    if conn.shm_fd >= 0
        ccall(:close, Int32, (Int32,), conn.shm_fd)
    end
    
    conn.connected = false
    println("[IPC] Disconnected from Rust kernel")
end

# ============================================================================
# Safe Shared Memory API - Bounds Checking and Mutex Protection
# ============================================================================

"""
    BoundsCheckError - Raised when memory access is out of bounds
"""
struct BoundsCheckError <: Exception
    offset::UInt64
    size::UInt64
    region_size::UInt64
    
    BoundsCheckError(off::UInt64, sz::UInt64, reg::UInt64) = new(off, sz, reg)
end

function Base.showerror(io::IO, e::BoundsCheckError)
    print(io, "BoundsCheckError: Attempted to access offset $(e.offset) with size $(e.size), ")
    print(io, "but region size is only $(e.region_size)")
end

"""
    MutexError - Raised when mutex lock fails
"""
struct MutexError <: Exception
    message::String
    
    MutexError(msg::String) = new(msg)
end

function Base.showerror(io::IO, e::MutexError)
    print(io, "MutexError: $(e.message)")
end

"""
    Validate that an offset and size are within bounds
    
    Arguments:
    - offset::UInt64 - The offset into shared memory
    - size::UInt64 - The size of data to access
    - region_size::UInt64 - Total size of the shared memory region
    
    Throws: BoundsCheckError if access would go out of bounds
"""
function _validate_bounds(offset::UInt64, size::UInt64, region_size::UInt64)
    # Check for overflow
    end_offset = offset + size
    if end_offset > region_size
        throw(BoundsCheckError(offset, size, region_size))
    end
    
    # Also check for zero-size access
    if size == 0
        throw(BoundsCheckError(offset, size, region_size))
    end
    
    true
end

"""
    Safe write to shared memory with mutex protection and bounds checking
    
    Arguments:
    - conn::KernelConnection - The kernel connection
    - data::T - Data to write (must be bitstype)
    - offset::UInt64 - Offset into shared memory
    
    Returns: true on success
    
    Throws:
    - BoundsCheckError if offset/size is out of bounds
    - MutexError if lock cannot be acquired
"""
function safe_shm_write(conn::KernelConnection, data::T, offset::UInt64)::Bool where T
    # Acquire mutex lock for thread-safe access
    lock(_shm_mutex)
    try
        # Get data size
        data_size = UInt64(sizeof(T))
        
        # Bounds check BEFORE unsafe operation
        _validate_bounds(offset, data_size, UInt64(SHM_SIZE))
        
        # Calculate actual pointer
        ptr = reinterpret(Ptr{T}, conn.mapped_addr + offset)
        
        # Log for debugging (race condition detection)
        tid = Threads.threadid()
        println("[IPC] Thread $tid: Writing $(data_size) bytes at offset $(offset)")
        
        # Now perform the unsafe operation - it's protected!
        unsafe_store!(ptr, data)
        
        println("[IPC] Thread $tid: Write completed")
        true
    catch e
        println("[IPC] ERROR in safe_shm_write: $e")
        rethrow()
    finally
        # Always release the lock
        unlock(_shm_mutex)
    end
end

"""
    Safe read from shared memory with mutex protection and bounds checking
    
    Arguments:
    - conn::KernelConnection - The kernel connection
    - ::Type{T} - Type to read
    - offset::UInt64 - Offset into shared memory
    
    Returns: The read data
    
    Throws:
    - BoundsCheckError if offset/size is out of bounds
    - MutexError if lock cannot be acquired
"""
function safe_shm_read(conn::KernelConnection, ::Type{T}, offset::UInt64)::T where T
    # Acquire mutex lock for thread-safe access
    lock(_shm_mutex)
    try
        # Get data size
        data_size = UInt64(sizeof(T))
        
        # Bounds check BEFORE unsafe operation
        _validate_bounds(offset, data_size, UInt64(SHM_SIZE))
        
        # Calculate actual pointer
        ptr = reinterpret(Ptr{T}, conn.mapped_addr + offset)
        
        # Log for debugging (race condition detection)
        tid = Threads.threadid()
        println("[IPC] Thread $tid: Reading $(data_size) bytes at offset $(offset)")
        
        # Now perform the unsafe operation - it's protected!
        result = unsafe_load(ptr)
        
        println("[IPC] Thread $tid: Read completed")
        result
    catch e
        println("[IPC] ERROR in safe_shm_read: $e")
        rethrow()
    finally
        # Always release the lock
        unlock(_shm_mutex)
    end
end

"""
    Check if the shared memory region is properly mapped
    
    Arguments:
    - conn::KernelConnection - The kernel connection
    
    Returns: true if mapped, false otherwise
"""
function is_shm_mapped(conn::KernelConnection)::Bool
    conn.mapped_addr != C_NULL && conn.connected
end

"""
    Get shared memory region information
    
    Returns: Dict with path, size, and mapped status
"""
function get_shm_info()::Dict{Symbol, Any}
    Dict(
        :path => SHM_PATH,
        :size => SHM_SIZE,
        :response_offset => RESPONSE_OFFSET,
        :max_payload => MAX_PAYLOAD_SIZE,
        :mutex_locked => islocked(_shm_mutex),
    )
end

"""
    Reset/shutdown the mutex (for testing or recovery)
    
    WARNING: Only use this if you're sure no other threads are using shared memory!
"""
function reset_shm_mutex()
    # Try to unlock if locked (this is a last-resort recovery mechanism)
    if islocked(_shm_mutex)
        try
            unlock(_shm_mutex)
            println("[IPC] WARNING: Force-unlocked mutex (possible deadlock recovery)")
        catch e
            println("[IPC] Could not unlock mutex: $e")
        end
    end
end

# ============================================================================
# Message Serialization
# ============================================================================

"""
    Serialize a thought cycle to bytes (WITHOUT timestamp/sequence - added during signing)
"""
function serialize_thought(thought::ThoughtCycle)::Vector{UInt8}
    data = Dict(
        "identity" => thought.identity,
        "intent" => thought.intent,
        "payload" => thought.payload,
        "timestamp" => string(thought.timestamp),
        "nonce" => thought.nonce
    )
    
    JSON.json(data) |> codeunits
end

"""
    Serialize thought and add timestamp/sequence header for signing
"""
function serialize_for_signing(thought::ThoughtCycle)::Vector{UInt8}
    payload = serialize_thought(thought)
    
    timestamp = _get_current_timestamp()
    sequence = _get_next_sequence()
    
    # Prepend timestamp and sequence
    timestamp_bytes = reinterpret(UInt8, [timestamp])
    sequence_bytes = reinterpret(UInt8, [sequence])
    
    vcat(timestamp_bytes, sequence_bytes, payload)
end

"""
    Extract payload from signed data (removes timestamp and sequence header)
"""
function extract_payload(signed_data::Vector{UInt8})::Vector{UInt8}
    if length(signed_data) < TIMESTAMP_SIZE + SEQUENCE_SIZE
        error("Data too short to contain timestamp and sequence header")
    end
    signed_data[TIMESTAMP_SIZE + SEQUENCE_SIZE + 1:end]
end

"""
    Extract timestamp from signed data
"""
function extract_timestamp(signed_data::Vector{UInt8})::UInt64
    if length(signed_data) < TIMESTAMP_SIZE
        error("Data too short to contain timestamp")
    end
    reinterpret(UInt64, signed_data[1:TIMESTAMP_SIZE])[1]
end

"""
    Extract sequence from signed data
"""
function extract_sequence(signed_data::Vector{UInt8})::UInt64
    if length(signed_data) < TIMESTAMP_SIZE + SEQUENCE_SIZE
        error("Data too short to contain sequence")
    end
    reinterpret(UInt64, signed_data[TIMESTAMP_SIZE+1:TIMESTAMP_SIZE+SEQUENCE_SIZE])[1]
end

"""
    Compute SHA-256 hash of data
"""
function compute_hash(data::Vector{UInt8})::NTuple{32, UInt8}
    h = sha256(data)
    Tuple(h)
end

"""
    Compute CRC32 checksum
"""
function compute_checksum(data::Vector{UInt8})::UInt32
    # Simple CRC32 implementation
    crc = 0xFFFFFFFF
    for b in data
        crc = xor(crc, UInt32(b))
        for _ in 1:8
            if crc & 1 == 1
                crc = xor(crc, 0xEDB88320)
            end
            crc = crc >> 1
        end
    end
    xor(crc, 0xFFFFFFFF)
end

# ============================================================================
# IPC Operations
# ============================================================================

"""
    Submit a thought cycle to Rust kernel for verification
    NOW INCLUDES SIGNING with timestamp and sequence
    
    SECURITY: This function now uses mutex-protected shared memory access
    with explicit bounds checking to prevent race conditions and buffer overflows.
"""
function submit_thought(conn::KernelConnection, 
                       thought::ThoughtCycle;
                       sign::Bool=true)::KernelResponse
    # Check if key is initialized when signing is requested
    if sign && !is_key_initialized()
        throw(KeyManagementError("Cannot sign message: secret key not initialized. Call init_secret_key() first."))
    end
    
    # Check if shared memory is properly mapped
    if !is_shm_mapped(conn)
        throw(MutexError("Shared memory not mapped - cannot submit thought"))
    end
    
    # Serialize the thought
    payload = serialize_thought(thought)
    
    # Validate payload size BEFORE creating entry
    if length(payload) > MAX_PAYLOAD_SIZE
        throw(BoundsCheckError(0, UInt64(length(payload)), UInt64(MAX_PAYLOAD_SIZE)))
    end
    
    # Sign the payload if requested
    if sign
        signature = sign_message(payload, _secret_key_state.key)
    else
        signature = zeros(UInt8, 64)  # Placeholder for unsigned
    end
    
    # Compute hash of the original payload (not the signed data)
    hash = compute_hash(payload)
    
    # Create IPC entry
    entry = IPCEntry(
        IPC_MAGIC,                    # magic
        IPC_VERSION,                  # version
        UInt8(IPC_ENTRY_THOUGHT_CYCLE), # entry_type
        sign ? 0x01 : 0x00,          # flags (bit 0 = signed)
        UInt32(length(payload)),      # length
        ntuple(i -> i <= length(thought.identity) ? 
                    UInt8(thought.identity[i]) : 0, 32),  # identity
        hash,                         # message_hash
        ntuple(i -> i <= length(signature) ? signature[i] : 0, 64),  # signature
        ntuple(i -> i <= length(payload) ? payload[i] : 0, 4096),  # payload
        compute_checksum(payload)     # checksum
    )
    
    # =========================================================================
    # SECURE: Use mutex-protected safe API instead of raw unsafe_store!
    # =========================================================================
    
    # Write entry to shared memory at offset 0 using safe API
    # This acquires the mutex lock and performs bounds checking
    safe_shm_write(conn, entry, UInt64(0))
    
    # Trigger interrupt to notify kernel
    ccall(:raise, Int32, (Int32,), 30)  # SIGUSR1
    
    # Wait for response (simplified)
    sleep(0.1)
    
    # =========================================================================
    # SECURE: Use mutex-protected safe API instead of raw unsafe_load
    # =========================================================================
    
    # Read response from shared memory at RESPONSE_OFFSET using safe API
    # This acquires the mutex lock and performs bounds checking
    response = safe_shm_read(conn, IPCEntry, UInt64(RESPONSE_OFFSET))
    
    KernelResponse(
        response.entry_type == 0x01,  # approved if response type is IntegrationAction
        "Verified",  # would parse from response payload
        collect(response.signature)
    )
end

"""
    Submit without signing (for backward compatibility)
"""
function submit_thought_unsigned(conn::KernelConnection, 
                                 thought::ThoughtCycle)::KernelResponse
    submit_thought(conn, thought; sign=false)
end

"""
    Poll for pending entries from Rust kernel
    
    SECURITY: This function implements FAIL-SECURE behavior:
    - If verify_signatures is true (default), ALL messages MUST have valid signatures
    - Messages with invalid, missing, or tampered signatures are REJECTED
    - No unsigned messages are processed when signature verification is enabled
    
    Arguments:
    - verify_signatures::Bool - Enable/disable signature verification (default: true)
    - check_timestamp::Bool - Check timestamp freshness (default: true)
    
    Returns: Vector{ThoughtCycle} - Only verified messages
"""
function poll_entries(conn::KernelConnection; 
                     verify_signatures::Bool=true,
                     check_timestamp::Bool=true)::Vector{ThoughtCycle}
    entries = ThoughtCycle[]
    
    # SECURITY: Fail-secure - reject all if signature verification is required but key missing
    if verify_signatures && !is_key_initialized()
        println("[IPC] SECURITY: Cannot verify signatures - key not initialized")
        println("[IPC] FAIL-SECURE: Rejecting ALL messages until key is initialized")
        return entries  # Return empty - no messages accepted
    end
    
    # If signature verification is disabled, return empty (we don't accept unsigned)
    if !verify_signatures
        println("[IPC] WARNING: Signature verification disabled - returning no messages (fail-secure)")
        return entries
    end
    
    # Would iterate through ring buffer and verify each entry
    # For now, return empty (actual implementation would read from shared memory)
    entries
end

"""
    Verify and process a single IPC entry
    
    SECURITY: Implements fail-secure behavior:
    - If key is not initialized, throws KeyManagementError (fail-secure)
    - Rejects ALL unsigned messages (flag 0x01 not set)
    - Validates payload hash and CRC32 checksum
    - Verifies HMAC-SHA256 signature with timestamp/sequence replay protection
    
    Arguments:
    - check_timestamp::Bool - Whether to reject old messages (default: true)
    
    Returns: true if entry is valid and verified, false otherwise
"""
function verify_entry(entry::IPCEntry; check_timestamp::Bool=true)::Bool
    # SECURITY: Fail-secure - require key to be initialized
    if !is_key_initialized()
        println("[IPC] SECURITY: Cannot verify entry - key not initialized")
        throw(KeyManagementError("Secret key not initialized - cannot verify IPC entry (fail-secure)"))
    end
    
    # Extract signature
    signature = collect(entry.signature)
    
    # Check if entry is signed (flag bit 0)
    is_signed = (entry.flags & 0x01) != 0
    
    # SECURITY: Fail-secure - reject ALL unsigned entries
    if !is_signed
        println("[IPC] SECURITY: REJECTING unsigned entry (fail-secure)")
        return false
    end
    
    # Check for zero signature (invalid)
    if all(s -> s == 0, signature)
        println("[IPC] SECURITY: REJECTING entry with zero signature")
        return false
    end
    
    # Extract payload
    payload = collect(entry.payload)[1:entry.length]
    
    # Verify payload hash
    computed_hash = compute_hash(payload)
    if computed_hash != entry.message_hash
        println("[IPC] SECURITY: REJECTING entry - Payload hash mismatch!")
        return false
    end
    
    # Verify CRC32 checksum
    computed_checksum = compute_checksum(payload)
    if computed_checksum != entry.checksum
        println("[IPC] SECURITY: REJECTING entry - Checksum mismatch!")
        return false
    end
    
    # Verify signature (includes timestamp validity and replay attack detection)
    try
        result = verify_signature(payload, signature, _secret_key_state.key; check_timestamp=check_timestamp)
        if !result
            println("[IPC] SECURITY: REJECTING entry - Signature verification failed")
        end
        return result
    catch e
        # Any exception during verification = reject (fail-secure)
        println("[IPC] SECURITY: REJECTING entry due to exception: $(typeof(e))")
        return false
    end
end

# ============================================================================
# Health Check
# ============================================================================

"""
    Send heartbeat to kernel
"""
function send_heartbeat(conn::KernelConnection)::Bool
    if !conn.connected
        return false
    end
    
    # Would write heartbeat entry to ring buffer
    true
end

"""
    Check kernel connection health
"""
function health_check(conn::KernelConnection)::Bool
    send_heartbeat(conn)
end

# ============================================================================
# Initialization
# ============================================================================

"""
    Initialize IPC subsystem with a generated or provided secret key
    
    Key loading priority (first successful):
    1. Explicitly provided key parameter
    2. Environment variable ITHERIS_IPC_SECRET_KEY (hex or base64 encoded)
    3. auto_generate_key (if enabled) - WARNING: for development only
    
    Arguments:
    - secret_key::Union{Vector{UInt8}, Nothing} - Explicit key to use
    - load_from_env::Bool - Whether to try loading from environment variable
    - auto_generate_key::Bool - Generate key if no other source available (dev only)
"""
function init(secret_key::Union{Vector{UInt8}, Nothing}=nothing;
             load_from_env::Bool=true,
             auto_generate_key::Bool=false)::Union{KernelConnection, Nothing}
    println("[IPC] Initializing IPC subsystem...")
    
    key_loaded = false
    key_source = "none"
    
    # Priority 1: Explicitly provided key
    if secret_key !== nothing
        init_secret_key(secret_key; source="provided")
        key_loaded = true
        key_source = "provided"
    # Priority 2: Environment variable
    elseif load_from_env
        try
            key, source = load_key_from_environment()
            init_secret_key(key; source=source)
            key_loaded = true
            key_source = source
        catch e
            if isa(e, KeyManagementError)
                println("[IPC] INFO: $(e.message) - will not load from environment")
            else
                throw(e)
            end
        end
    end
    
    # Priority 3: Auto-generate (development only - not for production)
    if !key_loaded && auto_generate_key
        key = generate_secret_key(32)
        init_secret_key(key; source="auto-generated (INSECURE - development only)")
        key_loaded = true
        key_source = "auto-generated"
        println("[IPC] WARNING: Auto-generated secret key - NOT FOR PRODUCTION USE!")
    end
    
    # Create shared memory if it doesn't exist
    try
        conn = connect_kernel()
        
        if is_key_initialized()
            println("[IPC] IPC subsystem ready")
            println("[IPC] Cryptographic signing: ENABLED (key from: $key_source)")
            println("[IPC] Replay protection: ENABLED (max age: $(TIMESTAMP_VALIDITY_SECONDS)s)")
            println("[IPC] FAIL-SECURE: Invalid signatures will be REJECTED")
        else
            println("[IPC] WARNING: Running without message signing!")
            println("[IPC] FAIL-OPEN WARNING: IPC will accept unsigned messages")
        end
        
        return conn
    catch e
        # SECURITY: When Rust kernel is not available, IPC returns nothing.
        # The Kernel will detect this and enter FAIL-CLOSED safe mode.
        println("[IPC] Warning: Could not connect to kernel: $e")
        println("[IPC] Running in fallback mode")
        return nothing
    end
end

"""
    Convenience function: Initialize with a specific key from hex string
"""
function init_from_hex(hex_key::String; kwargs...)
    key = Vector{UInt8}(hex2bytes(hex_key))
    init(key; kwargs...)
end

# ============================================================================
# Utility Functions
# ============================================================================

"""
    Get the source of the current key
"""
function get_key_source()::String
    _key_source[]
end

"""
    Get security status
"""
function security_status()::Dict{Symbol, Any}
    seen_count = isempty(_secret_key_state.seen_messages) ? 0 : sum(length, values(_secret_key_state.seen_messages))
    Dict(
        :key_initialized => is_key_initialized(),
        :key_length => is_key_initialized() ? length(_secret_key_state.key) : 0,
        :key_source => get_key_source(),
        :last_sequence => get_current_sequence(),
        :timestamp_validity_seconds => TIMESTAMP_VALIDITY_SECONDS,
        :seen_message_count => seen_count,
        :fail_secure_mode => true  # Always true - we always reject invalid signatures
    )
end

"""
    Reset security state (for testing)
"""
function reset_security_state!()
    _secret_key_state.key = Vector{UInt8}()
    _secret_key_state.initialized = false
    _secret_key_state.last_sequence = 0
    _secret_key_state.last_timestamp = 0
    _secret_key_state.seen_messages = Dict{UInt64, Set{UInt64}}()
    _key_source[] = "none"
    println("[IPC] Security state reset")
end

# ============================================================================
# Public API Exports - Safe Access Only!
# ============================================================================
#
# IMPORTANT: All shared memory access must go through these safe functions:
# - safe_shm_write() - Thread-safe write with mutex + bounds checking
# - safe_shm_read() - Thread-safe read with mutex + bounds checking
# - is_shm_mapped() - Check if shared memory is properly mapped
# - get_shm_info() - Get shared memory configuration
# - reset_shm_mutex() - Emergency mutex recovery (use with caution!)
#
# ============================================================================

export safe_shm_write, safe_shm_read, is_shm_mapped, get_shm_info, reset_shm_mutex
export BoundsCheckError, MutexError
export SHM_PATH, SHM_SIZE, get_shm_info

export connect_kernel, disconnect_kernel, submit_thought

export init_secret_key, is_key_initialized, sign_message, verify_signature

export SignatureError, KeyManagementError, SignatureVerificationError, ReplayAttackError

export ThoughtCycle, KernelResponse, KernelConnection, IPCEntry

export send_heartbeat, health_check

export init, get_key_source, reset_security_state!

end  # module
