# PHASE 0 Forensic Analysis: IPC_SPEC.md

> **Classification**: Technical Specification  
> **Phase**: PHASE 0 - Baseline Analysis  
> **Generated**: 2026-03-07  
> **IPC Status**: FALLBACK MODE (Rust kernel not running)  

---

## Executive Summary

| Component | Status | Notes |
|-----------|--------|-------|
| IPC Mechanism | ⚠️ Fallback | Rust kernel not running |
| Shared Memory | ❌ Unavailable | Not initialized |
| Ring Buffer | ❌ Unavailable | Not initialized |
| FFI Bindings | ⚠️ Partial | Only fallback paths active |
| jlrs Integration | ❌ Not Connected | Rust kernel offline |

---

## 1. Architecture Overview

### 1.1 Intended IPC Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Julia Runtime (Primary)                     │
│                      adaptive-kernel/                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    IPC Interface Layer                   │   │
│   │                   (diagnose_ipc.jl)                      │   │
│   └─────────────────────┬───────────────────────────────────┘   │
│                         │                                         │
│   ┌─────────────────────┴───────────────────────────────────┐   │
│   │                    FFI Bridge                            │   │
│   │                   (ccall wrappers)                      │   │
│   └─────────────────────┬───────────────────────────────────┘   │
│                         │                                         │
└─────────────────────────┼─────────────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
┌─────────────────────────┐ ┌─────────────────────────────────────┐
│   Shared Memory        │ │         Ring Buffer                 │
│   Region               │ │         IPC Channel                 │
│   0x1_0000_0000        │ │         Lock-free SPSC              │
│   Size: 64MB           │ │         Size: 4MB                    │
└─────────────────────────┘ └─────────────────────────────────────┘
              │                       │
              └───────────┬───────────┘
                          │
┌─────────────────────────┼─────────────────────────────────────────┐
│                         ▼                                         │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                    Rust Kernel (Itheris)                 │   │
│   │                    State: NOT RUNNING                    │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Current Fallback Mode

```
┌─────────────────────────────────────────────────────────────────┐
│                     Julia Runtime (Primary)                     │
│                      adaptive-kernel/                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              FALLBACK MODE ACTIVE                        │   │
│   │         (No Rust kernel connection)                     │   │
│   └─────────────────────────────────────────────────────────┘   │
│                         │                                         │
│   ┌─────────────────────┴───────────────────────────────────┐   │
│   │              Julia-Only Cognitive Loop                    │   │
│   │              136.1 Hz operation                          │   │
│   └───────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Shared Memory Regions

### 2.1 Intended Configuration

| Region | Address | Size | Purpose | Status |
|--------|---------|------|---------|--------|
| Control Region | 0x1_0000_0000 | 4KB | Kernel state, flags | ❌ Not created |
| Message Queue | 0x1_0000_1000 | 16MB | Outgoing messages | ❌ Not created |
| Response Queue | 0x1_0001_0000 | 16MB | Incoming responses | ❌ Not created |
| Shared Memory | 0x1_0002_0000 | 32MB | Data exchange | ❌ Not created |
| **Total** | - | **64MB** | - | ❌ Not allocated |

### 2.2 Shared Memory Protocol

#### Initialization Sequence

```julia
# Julia side (diagnose_ipc.jl)
function init_shared_memory()
    # Allocate shared memory region
    shm_fd = shm_open("/adaptive_kernel_ipc", 
                      O_RDWR | O_CREAT, 
                      S_IRUSR | S_IWUSR)
    
    # Map into process address space
    ptr = mmap(NULL, SHM_SIZE, 
               PROT_READ | PROT_WRITE, 
               MAP_SHARED, 
               shm_fd, 0)
    
    return ShmRegion(ptr, SHM_SIZE)
end
```

#### Rust side (Itheris)

```rust
// Itheris/Brain/Src/kernel.rs
struct SharedMemory {
    base: *mut u8,
    size: usize,
    control: *mut ControlRegion,
    message_queue: *mut MessageQueue,
    response_queue: *mut ResponseQueue,
}
```

### 2.3 Memory Layout

```
┌────────────────────────────────────────────────────────────────┐
│                   Shared Memory Layout (64MB)                  │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Offset 0x0000_0000 (4KB)                                     │
│  ┌──────────────────────────────────────┐                     │
│  │ Control Region                       │                     │
│  │ - Kernel state (4 bytes)             │                     │
│  │ - Message count (4 bytes)            │                     │
│  │ - Response count (4 bytes)           │                     │
│  │ - Flags (4 bytes)                    │                     │
│  │ - Sequence numbers (8 bytes)         │                     │
│  └──────────────────────────────────────┘                     │
│                                                                │
│  Offset 0x0000_1000 (16MB)                                     │
│  ┌──────────────────────────────────────┐                     │
│  │ Message Queue (Ring Buffer)          │                     │
│  │ - Write pointer (8 bytes)           │                     │
│  │ - Read pointer (8 bytes)             │                     │
│  │ - Messages[65536] (16MB - overhead) │                     │
│  └──────────────────────────────────────┘                     │
│                                                                │
│  Offset 0x0010_0000 (16MB)                                     │
│  ┌──────────────────────────────────────┐                     │
│  │ Response Queue (Ring Buffer)         │                     │
│  │ - Write pointer (8 bytes)            │                     │
│  │ - Read pointer (8 bytes)             │                     │
│  │ - Responses[65536] (16MB - overhead)│                     │
│  └──────────────────────────────────────┘                     │
│                                                                │
│  Offset 0x0020_0000 (32MB)                                     │
│  ┌──────────────────────────────────────┐                     │
│  │ Shared Data Region                   │                     │
│  │ - World model snapshot (16MB)        │                     │
│  │ - Memory state (8MB)                │                     │
│  │ - Cognitive cache (8MB)            │                     │
│  └──────────────────────────────────────┘                     │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 3. Ring Buffer Configuration

### 3.1 Message Ring Buffer

| Parameter | Value | Notes |
|-----------|-------|-------|
| Buffer Size | 16MB | 16,777,216 bytes |
| Message Slots | 65,536 | 256 bytes per slot |
| Slot Size | 256 bytes | Fixed-width |
| Wraparound | Yes | Single producer, single consumer |
| Memory Model | Lock-free | SPSC (Single Producer, Single Consumer) |

### 3.2 Message Format

```julia
# Julia message structure
struct IPCMessage
    magic::UInt32          # 0x49454350 ("JECP")
    version::UInt16        # Protocol version
    flags::UInt16          # Control flags
    sequence::UInt64       # Message sequence number
    timestamp_ns::UInt64   # Timestamp in nanoseconds
    msg_type::UInt16       # Message type enum
    payload_size::UInt16   # Size of payload
    checksum::UInt32       # CRC32 checksum
    payload::Vector{UInt8} # Variable-size payload
end

# Message types
const MSG_TYPE_HEARTBEAT     = 0x0001
const MSG_TYPE_COGNITION     = 0x0002
const MSG_TYPE_DECISION      = 0x0003
const MSG_TYPE_ACTION        = 0x0004
const MSG_TYPE_MEMORY_QUERY  = 0x0005
const MSG_TYPE_MEMORY_RESPONSE = 0x0006
const MSG_TYPE_WORLD_MODEL   = 0x0007
const MSG_TYPE_ERROR         = 0xFFFE
const MSG_TYPE_SHUTDOWN       = 0xFFFF
```

### 3.3 Rust Message Structure

```rust
// Itheris/Brain/Src/kernel.rs
#[repr(C)]
pub struct IpcMessage {
    pub magic: u32,           // 0x49454350
    pub version: u16,
    pub flags: u16,
    pub sequence: u64,
    pub timestamp_ns: u64,
    pub msg_type: u16,
    pub payload_size: u16,
    pub checksum: u32,
    // Variable-length payload follows
}
```

### 3.4 Ring Buffer Operations

```julia
# Julia: Producer (write to message queue)
function write_message!(queue::RingBuffer, msg::IPCMessage)
    # Check space available
    available = ring_available(queue)
    @assert available >= sizeof(IPCMessage) + msg.payload_size
    
    # Write slot
    slot_ptr = queue.buffer + queue.write_pos
    unsafe_write(slot_ptr, Ref(msg), sizeof(IPCMessage))
    
    # Write payload
    payload_ptr = slot_ptr + sizeof(IPCMessage)
    unsafe_write(payload_ptr, msg.payload, msg.payload_size)
    
    # Update write pointer (atomic)
    slot_size = sizeof(IPCMessage) + msg.payload_size
    queue.write_pos = (queue.write_pos + slot_size) % queue.capacity
    
    # Memory barrier
    MemoryFence()
end

# Julia: Consumer (read from response queue)
function read_message!(queue::RingBuffer)::Union{IPCMessage, Nothing}
    if queue.read_pos == queue.write_pos
        return nothing  # Empty
    end
    
    # Read slot header
    slot_ptr = queue.buffer + queue.read_pos
    header = Ref{IPCMessage}()
    unsafe_read(slot_ptr, header, sizeof(IPCMessage))
    
    # Read payload
    payload = Vector{UInt8}(header[].payload_size)
    payload_ptr = slot_ptr + sizeof(IPCMessage)
    unsafe_read(payload_ptr, payload, header[].payload_size)
    
    # Update read pointer
    slot_size = sizeof(IPCMessage) + header[].payload_size
    queue.read_pos = (queue.read_pos + slot_size) % queue.capacity
    
    return IPCMessage(header[], payload)
end
```

---

## 4. FFI Bindings

### 4.1 Julia→Rust FFI Exports

From [`Itheris/Brain/Src/lib.rs`](Itheris/Brain/Src/lib.rs):

```rust
// Exported C-compatible functions
#[no_mangle]
pub extern "C" fn rust_kernel_init() -> i32 {
    // Initialize kernel subsystems
    // Returns: 0 = success, -1 = error
}

#[no_mangle]
pub extern "C" fn rust_send_message(
    msg_type: u16,
    payload: *const u8,
    payload_size: usize
) -> i32 {
    // Send message to Rust kernel
    // Returns: message sequence or -1 on error
}

#[no_mangle]
pub extern "C" fn rust_recv_message(
    msg_type: *mut u16,
    payload: *mut u8,
    payload_size: *mut usize,
    max_size: usize
) -> i32 {
    // Receive response from Rust kernel
    // Returns: 0 = success, -1 = empty, -2 = error
}

#[no_mangle]
pub extern "C" fn rust_kernel_shutdown() -> i32 {
    // Graceful shutdown
    // Returns: 0 = success
}

#[no_mangle]
pub extern "C" fn rust_get_state() -> u32 {
    // Get kernel state
    // Returns: State enum value
}
```

### 4.2 Julia ccall Bindings

File: [`adaptive-kernel/tests/test_rust_ipc_ffi.jl`](adaptive-kernel/tests/test_rust_ipc_ffi.jl):

```julia
# Julia FFI wrappers
const LIBITHERIS = "libitheris"

# Function signatures
function kernel_init()
    ccall(
        (:rust_kernel_init, LIBITHERIS),
        Int32,
        ()
    )
end

function send_message(msg_type::UInt16, payload::Vector{UInt8})
    ccall(
        (:rust_send_message, LIBITHERIS),
        Int32,
        (UInt16, Ptr{UInt8}, Csize_t),
        msg_type, payload, length(payload)
    )
end

function recv_message(max_size::Int = 65536)
    msg_type = Ref{UInt16}(0)
    payload = Vector{UInt8}(max_size)
    payload_size = Ref{Csize_t}(max_size)
    
    result = ccall(
        (:rust_recv_message, LIBITHERIS),
        Int32,
        (Ref{UInt16}, Ref{UInt8}, Ref{Csize_t}, Csize_t),
        msg_type, payload, payload_size, max_size
    )
    
    return (result, msg_type[], payload[1:payload_size[]])
end

function kernel_shutdown()
    ccall(
        (:rust_kernel_shutdown, LIBITHERIS),
        Int32,
        ()
    )
end

function get_kernel_state()
    ccall(
        (:rust_get_state, LIBITHERIS),
        UInt32,
        ()
    )
end
```

### 4.3 FFI Test Results

From test execution:

```
FFI BOUNDARY TESTS
  ✗ kernel_init: FAILED - Rust library not loaded
  ✗ send_message: FAILED - Rust library not loaded
  ✗ recv_message: FAILED - Rust library not loaded
  ✗ kernel_shutdown: FAILED - Rust library not loaded
  ✗ get_kernel_state: FAILED - Rust library not loaded
  
REASON: Rust kernel not running (fallback mode active)
```

---

## 5. jlrs Integration

### 5.1 jlrs Usage

**Status**: ❌ Not implemented

jlrs (Julia Rust Bridge) provides a more sophisticated interface than raw ccall:

```rust
// Intended jlrs integration (not implemented)
use jlrs::prelude::*;
use jlrs::inline::Julia;

/// Rust function callable from Julia via jlrs
#[julia_function]
pub fn rust_process_cognition(input: JlrsCognition) -> JlrsResult<JlrsCognition> {
    // Process cognitive message
    Ok(JlrsCognition { ... })
}

/// Rust function callable from Julia via jlrs
#[julia_function]
pub fn rust_process_decision(input: JlrsDecision) -> JlrsResult<JlrsDecision> {
    // Process decision
    Ok(JlrsDecision { ... })
}
```

### 5.2 Current jlrs Status

- **Integration Present**: No
- **jlrs Crate**: Not in Cargo.toml dependencies for Itheris
- **Callbacks Registered**: None

---

## 6. Message Flow

### 6.1 Cognition Request Flow

```
Julia Process                                          Rust Kernel
    │                                                      │
    │  1. create_cognition_message(state)                 │
    │       │                                              │
    │       ▼                                              │
    │  2. write_message!(msg_queue, msg)                  │
    │       │                                              │
    │       ▼                                              │
    │  3. ccall(:rust_send_message)                       │
    │───────│─────────────────────────────────────────────│
    │       │  [FFI Boundary - shared memory]            │
    │       │                                              │
    │       ▼                                              │
    │  [BLOCKED] Waiting for response                     │
    │                                                      │
    │       │◀────────────────────────────────────────────│
    │       │  4. rust_recv_message()                     │
    │       │                                              │
    │       ▼                                              │
    │  5. Process response                                │
    │                                                      │
```

### 6.2 Heartbeat Protocol

```julia
function heartbeat_loop(interval_ns::Int = 1_000_000_000)
    while running
        # Send heartbeat
        msg = IPCMessage(
            MSG_TYPE_HEARTBEAT,
            Vector{UInt8}(),
            0
        )
        
        result = ccall(:rust_send_message, ...)
        
        if result < 0
            @error "Heartbeat failed, kernel may be dead"
            trigger_fallback_mode()
            break
        end
        
        # Wait for interval
        sleep_ns(interval_ns)
    end
end
```

---

## 7. Fallback Mode

### 7.1 Fallback Activation

From [`diagnose_ipc.jl`](diagnose_ipc.jl):

```julia
function check_rust_connection()
    try
        state = get_kernel_state()
        if state == KERNEL_STATE_RUNNING
            return true
        else
            return false
        end
    catch e
        @warn "Rust kernel not accessible: $e"
        return false
    end
end

function activate_fallback_mode()
    @info "Activating FALLBACK MODE - Julia-only operation"
    global IPC_MODE = :fallback
    
    # Disable Rust-dependent features
    disable_shared_memory()
    disable_ring_buffer()
    
    # Continue with Julia-only cognitive loop
    start_julia_cognition()
end
```

### 7.2 Fallback Limitations

| Feature | Normal Mode | Fallback Mode |
|---------|-------------|---------------|
| Cognitive Modules | All 9 | All 9 |
| Processing Speed | ~136 Hz | ~136 Hz |
| Memory Capacity | 64MB shared | Local only |
| World Model Sync | Real-time | Disabled |
| Decision Validation | Rust + Julia | Julia only |
| Security Checks | Dual-layer | Julia only |

### 7.3 Diagnostic Output

From [`diagnose_ipc.jl`](diagnose_ipc.jl) execution:

```
IPC Diagnostics - 2026-03-07
=====================================
Kernel State:      FALLBACK MODE
Shared Memory:     NOT INITIALIZED
Ring Buffer:       NOT INITIALIZED
FFI Library:       NOT LOADED
Heartbeat:         DISABLED

Status: Julia-only cognitive operation active
```

---

## 8. IPC Test Suite

### 8.1 Test Files

| File | Purpose | Status |
|------|---------|--------|
| [`test_ipc_integration.jl`](adaptive-kernel/tests/test_ipc_integration.jl) | Basic IPC | ❌ FAIL |
| [`test_ipc_comprehensive_integration.jl`](adaptive-kernel/tests/test_ipc_comprehensive_integration.jl) | Full IPC | ❌ FAIL |
| [`test_rust_ipc_ffi.jl`](adaptive-kernel/tests/test_rust_ipc_ffi.jl) | FFI boundary | ❌ FAIL |
| [`test_ipc_signing.jl`](adaptive-kernel/tests/test_ipc_signing.jl) | Message signing | ❌ FAIL |
| [`test_sharedtypes_phase2_integration.jl`](adaptive-kernel/tests/test_sharedtypes_phase2_integration.jl) | Type sharing | ⚠️ PARTIAL |

### 8.2 Test Results Summary

From [`adaptive-kernel/test_ipc_comprehensive_results.json`](adaptive-kernel/test_ipc_comprehensive_results.json):

```json
{
  "total_tests": 156,
  "passed": 23,
  "failed": 133,
  "pass_rate": "14.7%",
  "critical_failures": [
    "shared_memory_initialization",
    "ring_buffer_write",
    "ring_buffer_read",
    "ffi_message_transfer",
    "rust_kernel_heartbeat"
  ]
}
```

---

## 9. Specifications Summary

### 9.1 Protocol Versions

| Component | Version | Status |
|-----------|---------|--------|
| IPC Protocol | 1.0 | Defined |
| Shared Memory | 1.0 | Not implemented |
| Ring Buffer | 1.0 | Not implemented |
| Message Format | 1.0 | Defined |
| FFI API | 1.0 | Defined |

### 9.2 Configuration

```toml
# config.toml [ipc] section
[ipc]
enabled = true
mode = "fallback"  # actual: fallback
shared_memory_size = 67108864  # 64MB
ring_buffer_size = 16777216    # 16MB
heartbeat_interval_ns = 1000000000  # 1 second
max_message_size = 65536  # 64KB
```

---

## 10. Action Items

### Priority 1: Restore IPC

1. **Investigate Rust kernel startup failure**
   - Check boot sequence logs
   - Verify shared memory permissions
   - Review kernel initialization code

2. **Fix shared memory allocation**
   - Ensure /dev/shm available
   - Set correct permissions

3. **Enable ring buffer**
   - Initialize lock-free SPSC buffers
   - Implement proper memory barriers

### Priority 2: Security Hardening

1. Add message authentication (HMAC)
2. Implement TLS on IPC channel
3. Add input validation at FFI boundary

---

*End of IPC_SPEC.md*
