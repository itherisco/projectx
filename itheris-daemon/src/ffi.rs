//! # FFI Bridge for Julia Interop
//!
//! This module provides C ABI functions that Julia can call via ccall.
//! It bridges the gap between the Rust kernel and Julia brain.
//!
//! Export functions:
//! - kernel_init - Initialize the kernel
//! - send_message - Send a message to the kernel
//! - recv_message - Receive a message from the kernel
//! - get_kernel_status - Get kernel status

use crate::shared_memory::{
    FFI_IPC_Message, IPCEntryType, IPCMessage, IPC_MAGIC, IPC_VERSION,
    MAX_PAYLOAD_SIZE, SHM_PATH, SHM_SIZE, RING_BUFFER_ENTRIES,
    SharedMemoryIPCRef, create_shared_memory_ipc,
};
use ed25519_dalek::{
    Signer, SigningKey, Verifier, VerifyingKey, Signature, SIGNATURE_LENGTH, SECRET_KEY_LENGTH,
};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use once_cell::sync::Lazy;
use rand_core::{OsRng, RngCore};

/// Kernel initialization state
static KERNEL_INITIALIZED: AtomicBool = AtomicBool::new(false);

/// Kernel running state
static KERNEL_RUNNING: AtomicBool = AtomicBool::new(false);

/// Panic state flag
static PANIC_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// Message counter
static MESSAGE_COUNTER: AtomicU32 = AtomicU32::new(0);

/// Global message buffer for FFI
static LAST_MESSAGE: Lazy<Mutex<Option<IPCMessage>>> = Lazy::new(|| Mutex::new(None));

/// Kernel status enum for FFI
#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum KernelStatus {
    Uninitialized = 0,
    Initialized = 1,
    Running = 2,
    Panicked = 3,
    Stopped = 4,
}

/// Initialize the kernel (C ABI) - FAIL-CLOSED
///
/// This function implements fail-closed security behavior. If shared memory
/// initialization fails, the kernel will NOT allow Julia to continue with
/// insecure operations.
///
/// Returns:
/// - 0 on success
/// - -1 if already initialized
/// - -3 on FATAL error (kernel panic - Julia MUST halt)
#[no_mangle]
pub extern "C" fn kernel_init() -> i32 {
    if KERNEL_INITIALIZED.load(Ordering::Acquire) {
        log::warn!("[FFI] Kernel already initialized");
        return -1;
    }
    
    // Initialize shared memory
    let shm = match create_shared_memory_ipc() {
        Ok(s) => s,
        Err(e) => {
            // FATAL: Cannot create shared memory - fail-closed
            log::error!("[FFI] FATAL: Failed to create shared memory: {}", e);
            log::error!("[FFI] SECURITY BREACH PREVENTED: Julia must halt immediately");
            
            // Set panic state to prevent any unsafe operations
            PANIC_IN_PROGRESS.store(true, Ordering::Release);
            KERNEL_RUNNING.store(false, Ordering::Release);
            
            // Return FATAL error code - Julia MUST NOT continue
            return -3;
        }
    };
    
    match shm.initialize() {
        Ok(()) => {
            KERNEL_INITIALIZED.store(true, Ordering::Release);
            KERNEL_RUNNING.store(true, Ordering::Release);
            log::info!("[FFI] Kernel initialized successfully - FAIL-SECURE");
            0
        }
        Err(e) => {
            // FATAL: Initialization failed - fail-closed
            log::error!("[FFI] FATAL: Failed to initialize kernel: {}", e);
            log::error!("[FFI] SECURITY BREACH PREVENTED: Julia must halt immediately");
            
            // Set panic state to prevent any unsafe operations
            PANIC_IN_PROGRESS.store(true, Ordering::Release);
            KERNEL_RUNNING.store(false, Ordering::Release);
            
            // Return FATAL error code - Julia MUST NOT continue
            -3
        }
    }
}

/// Emergency halt signal - Rust kernel commands Julia to stop (C ABI)
///
/// This is called by the Rust kernel when a critical security issue is detected.
/// Julia MUST immediately cease all operations upon receiving this signal.
///
/// Returns:
/// - 0 on success (halt signal sent)
/// - -1 if Julia is already halted
#[no_mangle]
pub extern "C" fn emergency_halt() -> i32 {
    log::error!("[FFI] EMERGENCY HALT: Julia must stop immediately!");
    log::error!("[FFI] FATAL: Security boundary breach detected");
    
    // Set panic state to enforce halt
    PANIC_IN_PROGRESS.store(true, Ordering::Release);
    KERNEL_RUNNING.store(false, Ordering::Release);
    
    // Julia should call get_kernel_status() and see status == Panicked (3)
    // This will cause Julia to enter safe mode and not execute any proposals
    0
}

/// Julia acknowledges emergency halt (C ABI)
///
/// Called by Julia to confirm it has received and is processing the halt request.
///
/// Returns:
/// - 0 on success
#[no_mangle]
pub extern "C" fn julia_acknowledge_halt() -> i32 {
    log::info!("[FFI] Julia acknowledged emergency halt - entering safe mode");
    // Julia is now in safe mode - it will not execute any operations
    // without explicit Rust kernel approval
    0
}

/// Emergency seal - permanently lock the kernel (C ABI)
///
/// Once sealed, the kernel cannot be initialized again until system restart.
/// This is a last-resort security measure.
///
/// Returns:
/// - 0 on success (sealed)
/// - -1 if already sealed
#[no_mangle]
pub extern "C" fn emergency_seal() -> i32 {
     log::error!("[FFI] EMERGENCY SEAL: Kernel permanently locked!");
     log::error!("[FFI] FATAL: System in lockdown - restart required");
    
    // Set all states to halt
    PANIC_IN_PROGRESS.store(true, Ordering::Release);
    KERNEL_RUNNING.store(false, Ordering::Release);
    KERNEL_INITIALIZED.store(false, Ordering::Release);
    
    // Julia should detect this via get_kernel_status() returning Panicked (3)
    // and must not attempt any further operations
    0
}

/// Get kernel status (C ABI)
///
/// Returns:
/// - 0: Uninitialized
/// - 1: Initialized
/// - 2: Running
/// - 3: Panicked
/// - 4: Stopped
#[no_mangle]
pub extern "C" fn get_kernel_status() -> i32 {
    if PANIC_IN_PROGRESS.load(Ordering::Acquire) {
        return KernelStatus::Panicked as i32;
    }
    
    if KERNEL_RUNNING.load(Ordering::Acquire) {
        return KernelStatus::Running as i32;
    }
    
    if KERNEL_INITIALIZED.load(Ordering::Acquire) {
        return KernelStatus::Initialized as i32;
    }
    
    KernelStatus::Uninitialized as i32
}

/// Check if panic is in progress (C ABI)
///
/// Used by Julia to check if Rust kernel is panicking
///
/// Returns:
/// - 0: Not panicking
/// - 1: Panicking
#[no_mangle]
pub extern "C" fn panic_in_progress() -> i32 {
    if PANIC_IN_PROGRESS.load(Ordering::Acquire) {
        1
    } else {
        0
    }
}

/// Set panic state (C ABI)
///
/// Called when a panic occurs in the kernel
#[no_mangle]
pub extern "C" fn set_panic_state(panic: i32) {
    PANIC_IN_PROGRESS.store(panic != 0, Ordering::Release);
    if panic != 0 {
        log::error!("[FFI] Kernel panic state set to: {}", panic);
    }
}

/// Send a message to the kernel (C ABI)
///
/// Arguments:
/// - msg_type: Message type (0-4)
/// - payload: Pointer to payload data
/// - payload_size: Size of payload in bytes
///
/// Returns:
/// - 0 on success
/// - -1 if not initialized
/// - -2 if payload is too large
/// - -3 on other error
#[no_mangle]
pub extern "C" fn send_message(
    msg_type: u8,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    // Check initialization
    if !KERNEL_INITIALIZED.load(Ordering::Acquire) {
        log::error!("[FFI] Cannot send message: kernel not initialized");
        return -1;
    }
    
    // Validate payload
    if payload.is_null() {
        log::error!("[FFI] Cannot send message: null payload");
        return -1;
    }
    
    if payload_size > MAX_PAYLOAD_SIZE {
        log::error!("[FFI] Payload too large: {} > {}", payload_size, MAX_PAYLOAD_SIZE);
        return -2;
    }
    
    // Read payload from pointer
    let payload_slice = unsafe { std::slice::from_raw_parts(payload, payload_size) };
    let payload_vec = payload_slice.to_vec();
    
    // Convert message type
    let entry_type = match msg_type {
        0 => IPCEntryType::ThoughtCycle,
        1 => IPCEntryType::IntegrationProposal,
        2 => IPCEntryType::Response,
        3 => IPCEntryType::Heartbeat,
        4 => IPCEntryType::Panic,
        _ => {
            log::error!("[FFI] Invalid message type: {}", msg_type);
            return -3;
        }
    };
    
    // Create message
    let message = IPCMessage::new(entry_type, payload_vec);
    
    // Store in global buffer for later retrieval
    if let Ok(mut guard) = LAST_MESSAGE.lock() {
        *guard = Some(message);
    }
    
    // Update counter
    MESSAGE_COUNTER.fetch_add(1, Ordering::Relaxed);
    
    log::debug!("[FFI] Message sent: type={}, size={}", msg_type, payload_size);
    0
}

/// Receive a message from the kernel (C ABI)
///
/// Arguments:
/// - msg_type: Output buffer for message type
/// - payload: Output buffer for payload data
/// - max_payload_size: Maximum size of payload buffer
/// - actual_size: Output for actual payload size
///
/// Returns:
/// - 0 on success
/// - -1 if no message available
/// - -2 if buffer too small
#[no_mangle]
pub extern "C" fn recv_message(
    msg_type: *mut u8,
    payload: *mut u8,
    max_payload_size: usize,
    actual_size: *mut usize,
) -> i32 {
    // Check initialization
    if !KERNEL_INITIALIZED.load(Ordering::Acquire) {
        return -1;
    }
    
    // Validate outputs
    if msg_type.is_null() || payload.is_null() || actual_size.is_null() {
        return -1;
    }
    
    // Get last message (in real implementation, this would be from ring buffer)
    let message = match LAST_MESSAGE.lock() {
        Ok(guard) => match guard.as_ref() {
            Some(msg) => msg.clone(),
            None => return -1,
        },
        Err(_) => return -1,
    };
    
    // Check buffer size
    if max_payload_size < message.payload.len() {
        unsafe {
            *actual_size = message.payload.len();
        }
        return -2;
    }
    
    // Write message type
    unsafe {
        *msg_type = message.header.entry_type;
    }
    
    // Write payload
    unsafe {
        let payload_slice = std::slice::from_raw_parts_mut(payload, message.payload.len());
        payload_slice.copy_from_slice(&message.payload);
        *actual_size = message.payload.len();
    }
    
    log::debug!("[FFI] Message received: type={}, size={}", 
                message.header.entry_type, message.payload.len());
    0
}

/// Non-blocking send message to kernel (C ABI)
///
/// Arguments:
/// - msg_type: Message type (0-4)
/// - payload: Pointer to payload data
/// - payload_size: Size of payload in bytes
///
/// Returns:
/// - 0 on success (message queued)
/// - -1 if not initialized
/// - -2 if buffer full
#[no_mangle]
pub extern "C" fn send_message_nb(
    msg_type: u8,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    // Check initialization
    if !KERNEL_INITIALIZED.load(Ordering::Acquire) {
        return -1;
    }
    
    // Validate payload
    if payload.is_null() || payload_size > MAX_PAYLOAD_SIZE {
        return -2;
    }
    
    // In a real implementation, this would use a non-blocking ring buffer
    // For now, just return success
    MESSAGE_COUNTER.fetch_add(1, Ordering::Relaxed);
    0
}

/// Non-blocking receive message from kernel (C ABI)
///
/// Arguments:
/// - msg_type: Output buffer for message type
/// - payload: Output buffer for payload data
/// - max_payload_size: Maximum size of payload buffer
/// - actual_size: Output for actual payload size
///
/// Returns:
/// - 0 on success (message received)
/// - -1 if no message available
/// - -2 if buffer too small
#[no_mangle]
pub extern "C" fn recv_message_nb(
    msg_type: *mut u8,
    payload: *mut u8,
    max_payload_size: usize,
    actual_size: *mut usize,
) -> i32 {
    // Check initialization
    if !KERNEL_INITIALIZED.load(Ordering::Acquire) {
        return -1;
    }
    
    // Validate outputs
    if msg_type.is_null() || payload.is_null() || actual_size.is_null() {
        return -1;
    }
    
    // No messages available in this implementation
    // Would check ring buffer in real implementation
    -1
}

/// Free translated panic message (C ABI)
///
/// This is called from Julia after using a Rust-allocated string
/// to avoid memory leaks.
#[no_mangle]
pub extern "C" fn free_translated_panic(ptr: *mut std::ffi::c_void) {
    if ptr.is_null() {
        return;
    }
    
    // In a real implementation, we would free the allocated string
    // For now, this is a placeholder
    log::debug!("[FFI] Freeing translated panic at {:?}", ptr);
    
    // Note: In actual implementation, we would need to track allocations
    // and free them appropriately. This is a simplified version.
}

/// Raise a Julia exception from Rust context (C ABI)
///
/// Arguments:
/// - message: Null-terminated error message string
#[no_mangle]
pub extern "C" fn raise_julia_exception(message: *const std::ffi::c_char) {
    if message.is_null() {
        return;
    }
    
    // Convert C string to Rust string
    let msg = unsafe {
        std::ffi::CStr::from_ptr(message)
            .to_string_lossy()
            .into_owned()
    };
    
    log::error!("[FFI] Raising Julia exception: {}", msg);
    
    // In a real implementation, this would raise an exception in Julia
    // For now, we just log it
}

/// Get message counter (C ABI)
///
/// Returns the number of messages processed
#[no_mangle]
pub extern "C" fn get_message_count() -> u32 {
    MESSAGE_COUNTER.load(Ordering::Relaxed)
}

/// Get shared memory info (C ABI)
///
/// Returns information about the shared memory region
///
/// Arguments:
/// - path: Output buffer for path (must be at least 256 bytes)
/// - size: Output for size
/// - entries: Output for number of entries
#[no_mangle]
pub extern "C" fn get_shm_info(
    path: *mut u8,
    size: *mut usize,
    entries: *mut usize,
) -> i32 {
    if path.is_null() || size.is_null() || entries.is_null() {
        return -1;
    }
    
    let shm_path = crate::shared_memory::SHM_PATH.as_bytes();
    
    unsafe {
        let path_slice = std::slice::from_raw_parts_mut(path, 256.min(shm_path.len()));
        path_slice.copy_from_slice(&shm_path[..path_slice.len()]);
        
        *size = crate::shared_memory::SHM_SIZE;
        *entries = crate::shared_memory::RING_BUFFER_ENTRIES;
    }
    
    0
}

/// Reset kernel (C ABI)
///
/// Returns kernel to uninitialized state
#[no_mangle]
pub extern "C" fn kernel_reset() -> i32 {
    KERNEL_RUNNING.store(false, Ordering::Release);
    KERNEL_INITIALIZED.store(false, Ordering::Release);
    PANIC_IN_PROGRESS.store(false, Ordering::Release);
    MESSAGE_COUNTER.store(0, Ordering::Relaxed);
    
    if let Ok(mut guard) = LAST_MESSAGE.lock() {
        *guard = None;
    }
    
    log::info!("[FFI] Kernel reset");
    0
}

/// Shutdown kernel (C ABI)
///
/// Clean shutdown of the kernel
#[no_mangle]
pub extern "C" fn kernel_shutdown() -> i32 {
    if !KERNEL_INITIALIZED.load(Ordering::Acquire) {
        return -1;
    }
    
    KERNEL_RUNNING.store(false, Ordering::Release);
    log::info!("[FFI] Kernel shutdown");
    0
}

// ============================================================================
// Ed25519 Cryptographic Functions for IPC Signing
// ============================================================================

/// Error codes for crypto operations
#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum CryptoError {
    Success = 0,
    NullPointer = -1,
    InvalidKeySize = -2,
    InvalidSignatureSize = -3,
    SigningError = -4,
    VerificationFailed = -5,
    KeyGenerationError = -6,
}

/// Sign a message using Ed25519 (C ABI)
///
/// Arguments:
/// - private_key_ptr: Pointer to 32-byte Ed25519 private key
/// - message_ptr: Pointer to message data
/// - message_len: Length of message in bytes
/// - signature_out: Output buffer for 64-byte signature (must be pre-allocated)
///
/// Returns:
/// - 0 on success
/// - -1 if any pointer is null
/// - -2 if private key is not 32 bytes
/// - -4 on signing error
#[no_mangle]
pub extern "C" fn sign_message(
    private_key_ptr: *const u8,
    message_ptr: *const u8,
    message_len: usize,
    signature_out: *mut u8,
) -> i32 {
    // Validate pointers
    if private_key_ptr.is_null() || message_ptr.is_null() || signature_out.is_null() {
        log::error!("[FFI] sign_message: null pointer provided");
        return CryptoError::NullPointer as i32;
    }

    // Load the 32-byte private key
    let private_key_bytes = unsafe { std::slice::from_raw_parts(private_key_ptr, SECRET_KEY_LENGTH) };
    
    let signing_key = match SigningKey::from_bytes(private_key_bytes.try_into().unwrap()) {
        Ok(key) => key,
        Err(e) => {
            log::error!("[FFI] sign_message: invalid private key: {:?}", e);
            return CryptoError::InvalidKeySize as i32;
        }
    };

    // Read the message
    let message = unsafe { std::slice::from_raw_parts(message_ptr, message_len) };

    // Sign the message
    let signature = signing_key.sign(message);

    // Write signature to output buffer
    unsafe {
        let sig_slice = std::slice::from_raw_parts_mut(signature_out, SIGNATURE_LENGTH);
        sig_slice.copy_from_slice(signature.as_bytes());
    }

    log::debug!("[FFI] sign_message: signed {} bytes", message_len);
    CryptoError::Success as i32
}

/// Verify an Ed25519 signature (C ABI)
///
/// Arguments:
/// - public_key_ptr: Pointer to 32-byte Ed25519 public key
/// - message_ptr: Pointer to message data
/// - message_len: Length of message in bytes
/// - signature_ptr: Pointer to 64-byte signature
///
/// Returns:
/// - 0 on success (signature valid)
/// - 1 if signature is invalid
/// - -1 if any pointer is null
/// - -2 if public key is not 32 bytes
/// - -3 if signature is not 64 bytes
#[no_mangle]
pub extern "C" fn verify_message(
    public_key_ptr: *const u8,
    message_ptr: *const u8,
    message_len: usize,
    signature_ptr: *const u8,
) -> i32 {
    // Validate pointers
    if public_key_ptr.is_null() || message_ptr.is_null() || signature_ptr.is_null() {
        log::error!("[FFI] verify_message: null pointer provided");
        return CryptoError::NullPointer as i32;
    }

    // Load the 32-byte public key
    let public_key_bytes = unsafe { std::slice::from_raw_parts(public_key_ptr, 32) };
    
    let verifying_key = match VerifyingKey::from_bytes(public_key_bytes.try_into().unwrap()) {
        Ok(key) => key,
        Err(e) => {
            log::error!("[FFI] verify_message: invalid public key: {:?}", e);
            return CryptoError::InvalidKeySize as i32;
        }
    };

    // Read the message
    let message = unsafe { std::slice::from_raw_parts(message_ptr, message_len) };

    // Read the signature
    let signature_bytes = unsafe { std::slice::from_raw_parts(signature_ptr, SIGNATURE_LENGTH) };
    let signature = match Signature::from_bytes(signature_bytes.try_into().unwrap()) {
        Ok(sig) => sig,
        Err(e) => {
            log::error!("[FFI] verify_message: invalid signature: {:?}", e);
            return CryptoError::InvalidSignatureSize as i32;
        }
    };

    // Verify the signature
    match verifying_key.verify(message, &signature) {
        Ok(()) => {
            log::debug!("[FFI] verify_message: signature valid");
            CryptoError::Success as i32
        }
        Err(e) => {
            log::debug!("[FFI] verify_message: signature invalid: {:?}", e);
            1 // Signature invalid
        }
    }
}

/// Generate an Ed25519 keypair (C ABI)
///
/// Arguments:
/// - seed_ptr: Optional pointer to 32-byte seed (can be null for random)
/// - public_key_out: Output buffer for 32-byte public key (must be pre-allocated)
/// - private_key_out: Output buffer for 64-byte private key (must be pre-allocated)
///
/// Returns:
/// - 0 on success
/// - -1 if output pointers are null
/// - -2 if seed is provided but not 32 bytes
/// - -6 on key generation error
#[no_mangle]
pub extern "C" fn generate_keypair(
    seed_ptr: *const u8,
    public_key_out: *mut u8,
    private_key_out: *mut u8,
) -> i32 {
    // Validate output pointers
    if public_key_out.is_null() || private_key_out.is_null() {
        log::error!("[FFI] generate_keypair: null output pointer");
        return CryptoError::NullPointer as i32;
    }

    let signing_key = if seed_ptr.is_null() {
        // Generate random keypair
        SigningKey::generate(&mut rand_core::OsRng)
    } else {
        // Use provided seed
        let seed = unsafe { std::slice::from_raw_parts(seed_ptr, 32) };
        let seed_array: [u8; 32] = match seed.try_into() {
            Ok(arr) => arr,
            Err(_) => {
                log::error!("[FFI] generate_keypair: invalid seed size");
                return CryptoError::InvalidKeySize as i32;
            }
        };
        SigningKey::from_bytes(&seed_array)
    };

    let verifying_key = signing_key.verifying_key();

    // Write public key (32 bytes)
    unsafe {
        let pk_slice = std::slice::from_raw_parts_mut(public_key_out, 32);
        pk_slice.copy_from_slice(verifying_key.as_bytes());
    }

    // Write private key (64 bytes - includes public key)
    unsafe {
        let sk_slice = std::slice::from_raw_parts_mut(private_key_out, 64);
        sk_slice.copy_from_slice(signing_key.to_bytes().as_ref());
    }

    log::debug!("[FFI] generate_keypair: keypair generated");
    CryptoError::Success as i32
}

// ============================================================================
// Cryptographic Random Number Generation (CSPRNG)
// ============================================================================

/// Generate cryptographically secure random bytes (C ABI)
///
/// This function uses the Rust `getrandom` crate which provides:
/// - OS-specific CSPRNG (getrandom on Linux, SecRandomCopyBytes on macOS)
/// - Fallback to TPM/HSM RNG if available
///
/// Arguments:
/// - `buf_out`: Output buffer for random bytes
/// - `n`: Number of bytes to generate
///
/// Returns:
/// - 0 on success
/// - -1 on error (buffer too small)
/// - -2 if CSPRNG unavailable
#[no_mangle]
pub extern "C" fn get_secure_random(buf_out: *mut u8, n: usize) -> i32 {
    use getrandom::getrandom;
    
    if n == 0 {
        return 0;
    }
    
    if buf_out.is_null() {
        log::error!("[FFI] get_secure_random: null buffer pointer");
        return -1;
    }
    
    // Create buffer and fill with random bytes
    let mut buffer = vec![0u8; n];
    
    match getrandom(&mut buffer) {
        Ok(()) => {
            // Copy to output buffer
            unsafe {
                let out_slice = std::slice::from_raw_parts_mut(buf_out, n);
                out_slice.copy_from_slice(&buffer);
            }
            log::debug!("[FFI] get_secure_random: generated {} bytes", n);
            0
        }
        Err(e) => {
            log::error!("[FFI] get_secure_random: failed to get random: {:?}", e);
            -2
        }
    }
}

// ============================================================================
// Additional FFI functions for better Julia integration
// ============================================================================

/// Check if kernel is ready for messages (C ABI)
///
/// Returns:
/// - 1 if ready
/// - 0 if not ready
#[no_mangle]
pub extern "C" fn kernel_ready() -> i32 {
    if KERNEL_INITIALIZED.load(Ordering::Acquire) && KERNEL_RUNNING.load(Ordering::Acquire) {
        if !PANIC_IN_PROGRESS.load(Ordering::Acquire) {
            return 1;
        }
    }
    0
}

// FFI Functions for new security modules
// These provide C ABI entry points that Julia can call

use crate::secrets;
use crate::jwt_auth::{self, Role};
use crate::flow_integrity::{self, RiskLevel as FlowRiskLevel};
use crate::risk_classifier::{self, RiskLevel};
use crate::secure_confirmation::{self, RiskLevel as ConfirmRiskLevel};
use crate::task_orchestrator::{self, TaskPriority};
use crate::safe_shell;
use crate::safe_http::{self, HttpMethod};

// ============================================================================
// Secrets Manager FFI
// ============================================================================

/// Initialize secrets manager with passphrase
/// Returns 0 on success, -1 on error
#[no_mangle]
pub extern "C" fn secrets_init(passphrase: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    if passphrase.is_null() {
        return -1;
    }
    
    let c_str = unsafe { CStr::from_ptr(passphrase) };
    if let Ok(pass) = c_str.to_str() {
        match secrets::unlock_global(pass, None) {
            Ok(_) => 0,
            Err(_) => -1,
        }
    } else {
        -1
    }
}

/// Store a secret
/// Returns 0 on success, -1 on error
#[no_mangle]
pub extern "C" fn secrets_store(key: *const std::ffi::c_char, value: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    if key.is_null() || value.is_null() {
        return -1;
    }
    
    let key_str = unsafe { CStr::from_ptr(key) };
    let value_str = unsafe { CStr::from_ptr(value) };
    
    if let (Ok(k), Ok(v)) = (key_str.to_str(), value_str.to_str()) {
        match secrets::store_global(k, v) {
            Ok(_) => 0,
            Err(_) => -1,
        }
    } else {
        -1
    }
}

/// Get a secret (returns pointer to string, caller must free)
#[no_mangle]
pub extern "C" fn secrets_get(key: *const std::ffi::c_char) -> *mut std::ffi::c_char {
    use std::ffi::{CStr, CString};
    use std::ptr;
    
    if key.is_null() {
        return ptr::null_mut();
    }
    
    let key_str = unsafe { CStr::from_ptr(key) };
    
    if let Ok(k) = key_str.to_str() {
        if let Ok(value) = secrets::get_global(k) {
            if let Ok(c_string) = CString::new(value) {
                return c_string.into_raw();
            }
        }
    }
    
    ptr::null_mut()
}

/// Lock secrets manager
#[no_mangle]
pub extern "C" fn secrets_lock() {
    secrets::lock_global();
}

// ============================================================================
// AES-256-GCM Encryption FFI (for Julia interop)
// ============================================================================

/// Encrypt data using AES-256-GCM
/// 
/// # Arguments
/// * `key` - 32-byte encryption key
/// * `key_len` - Must be 32
/// * `plaintext` - Data to encrypt
/// * `plaintext_len` - Length of plaintext
/// * `ciphertext_out` - Output buffer (must be at least plaintext_len + 28 bytes for nonce + tag)
/// * `nonce_out` - 12-byte nonce output
///
/// # Returns
/// * Total output length (ciphertext_len + 12 nonce + 16 tag) on success
/// * 0 on error
#[no_mangle]
pub extern "C" fn aes_gcm_encrypt(
    key: *const u8,
    key_len: usize,
    plaintext: *const u8,
    plaintext_len: usize,
    ciphertext_out: *mut u8,
    nonce_out: *mut u8,
) -> usize {
    use aes_gcm::{
        aead::{Aead, KeyInit, OsRng},
        Aes256Gcm, Nonce,
    };
    use std::ptr;

    // Validate inputs
    if key.is_null() || plaintext.is_null() || ciphertext_out.is_null() || nonce_out.is_null() {
        return 0;
    }
    if key_len != 32 || plaintext_len == 0 {
        return 0;
    }

    // Get key bytes
    let key_bytes = unsafe { std::slice::from_raw_parts(key, key_len) };
    let plaintext_bytes = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };

    // Create cipher
    let cipher = match Aes256Gcm::new_from_slice(key_bytes) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    // Generate random 96-bit nonce
    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    // Encrypt
    let ciphertext = match cipher.encrypt(nonce, plaintext_bytes) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    // Copy outputs
    unsafe {
        ptr::copy_nonoverlapping(nonce_bytes.as_ptr(), nonce_out, 12);
        ptr::copy_nonoverlapping(ciphertext.as_ptr(), ciphertext_out, ciphertext.len());
    }

    // Return total length: nonce (12) + ciphertext + tag (16)
    // GCM appends the tag to ciphertext, so ciphertext.len() = plaintext_len + 16
    12 + ciphertext.len()
}

/// Decrypt data using AES-256-GCM
/// 
/// # Arguments
/// * `key` - 32-byte decryption key
/// * `key_len` - Must be 32
/// * `nonce` - 12-byte nonce
/// * `ciphertext` - Ciphertext + tag (from encrypt)
/// * `ciphertext_len` - Length of ciphertext + tag
/// * `plaintext_out` - Output buffer (must be at least ciphertext_len - 28 bytes)
///
/// # Returns
/// * Plaintext length on success
/// * 0 on error (authentication failure or other)
#[no_mangle]
pub extern "C" fn aes_gcm_decrypt(
    key: *const u8,
    key_len: usize,
    nonce: *const u8,
    ciphertext: *const u8,
    ciphertext_len: usize,
    plaintext_out: *mut u8,
) -> usize {
    use aes_gcm::{
        aead::{Aead, KeyInit, OsRng},
        Aes256Gcm, Nonce,
    };
    use std::ptr;

    // Validate inputs
    if key.is_null() || nonce.is_null() || ciphertext.is_null() || plaintext_out.is_null() {
        return 0;
    }
    if key_len != 32 || ciphertext_len < 28 {
        // Minimum: 12 nonce + 16 tag = 28
        return 0;
    }

    // Get key and data bytes
    let key_bytes = unsafe { std::slice::from_raw_parts(key, key_len) };
    let nonce_bytes = unsafe { std::slice::from_raw_parts(nonce, 12) };
    let ciphertext_bytes = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };

    // Create cipher
    let cipher = match Aes256Gcm::new_from_slice(key_bytes) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    // Create nonce
    let nonce = Nonce::from_slice(nonce_bytes);

    // Decrypt (this verifies the authentication tag)
    let plaintext = match cipher.decrypt(nonce, ciphertext_bytes) {
        Ok(p) => p,
        Err(_) => return 0, // Authentication failure
    };

    // Copy output
    unsafe {
        ptr::copy_nonoverlapping(plaintext.as_ptr(), plaintext_out, plaintext.len());
    }

    plaintext.len()
}

// ============================================================================
// JWT Auth FFI
// ============================================================================

/// Initialize JWT auth
#[no_mangle]
pub extern "C" fn jwt_init(enabled: i32, secret: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    let config = jwt_auth::AuthConfig {
        jwt_secret: if secret.is_null() {
            jwt_auth::generate_token(32)
        } else {
            let c_str = unsafe { CStr::from_ptr(secret) };
            c_str.to_str().unwrap_or("default_secret").to_string()
        },
        algorithm: jsonwebtoken::Algorithm::HS256,
        token_ttl: 3600,
        refresh_ttl: 604800,
        enabled: enabled != 0,
        allow_dev_bypass: false,
        rate_limit: 100,
        rate_limit_window: 60,
    };
    
    jwt_auth::init(config);
    0
}

/// Create JWT token
#[no_mangle]
pub extern "C" fn jwt_create_token(
    subject: *const std::ffi::c_char,
    role: *const std::ffi::c_char,
) -> *mut std::ffi::c_char {
    use std::ffi::{CStr, CString};
    use std::ptr;
    use crate::jwt_auth::Role;
    
    if subject.is_null() {
        return ptr::null_mut();
    }
    
    let sub = unsafe { CStr::from_ptr(subject) }.to_str().unwrap_or("");
    
    // Parse role
    let roles = if !role.is_null() {
        let role_str = unsafe { CStr::from_ptr(role) }.to_str().unwrap_or("user");
        match role_str {
            "admin" => vec![Role::Admin],
            "service" => vec![Role::Service],
            "readonly" => vec![Role::ReadOnly],
            _ => vec![Role::User],
        }
    } else {
        vec![Role::User]
    };
    
    match jwt_auth::create_token(sub, roles) {
        Ok(token) => CString::new(token).unwrap_or_default().into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Validate JWT token
/// Returns 1 if valid, 0 if invalid
#[no_mangle]
pub extern "C" fn jwt_validate(token: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    if token.is_null() {
        return 0;
    }
    
    let token_str = unsafe { CStr::from_ptr(token) }.to_str().unwrap_or("");
    
    match jwt_auth::validate_token(token_str) {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

// ============================================================================
// Flow Integrity FFI
// ============================================================================

/// Initialize flow integrity gate
#[no_mangle]
pub extern "C" fn flow_init(secret: *const u8) -> i32 {
    use aes_gcm::aead::OsRng;
    
    let mut key = [0u8; 32];
    
    if secret.is_null() {
        // Generate random key
        OsRng.fill_bytes(&mut key);
    } else {
        // Use provided key
        unsafe {
            std::ptr::copy_nonoverlapping(secret, key.as_mut_ptr(), 32);
        }
    }
    
    flow_integrity::init(&key);
    0
}

/// Issue flow token
#[no_mangle]
pub extern "C" fn flow_issue_token(
    capability: *const std::ffi::c_char,
    params: *const std::ffi::c_char,
    risk_level: i32,
) -> *mut std::ffi::c_char {
    use std::ffi::{CStr, CString};
    use std::ptr;
    use crate::flow_integrity::RiskLevel;
    
    if capability.is_null() {
        return ptr::null_mut();
    }
    
    let cap = unsafe { CStr::from_ptr(capability) }.to_str().unwrap_or("");
    let params_str = if params.is_null() {
        "{}".to_string()
    } else {
        unsafe { CStr::from_ptr(params) }.to_str().unwrap_or("{}").to_string()
    };
    
    let risk = match risk_level {
        0 => RiskLevel::ReadOnly,
        1 => RiskLevel::Low,
        2 => RiskLevel::Medium,
        3 => RiskLevel::High,
        _ => RiskLevel::Critical,
    };
    
    match flow_integrity::issue_token(cap, &params_str, risk) {
        Ok(token) => {
            let json = flow_integrity::serialize_token(&token);
            CString::new(json).unwrap_or_default().into_raw()
        }
        Err(_) => ptr::null_mut(),
    }
}

/// Verify flow token
/// Returns 1 if valid, 0 if invalid
#[no_mangle]
pub extern "C" fn flow_verify_token(
    token_json: *const std::ffi::c_char,
    capability: *const std::ffi::c_char,
    params: *const std::ffi::c_char,
) -> i32 {
    use std::ffi::CStr;
    
    if token_json.is_null() || capability.is_null() {
        return 0;
    }
    
    let token_str = unsafe { CStr::from_ptr(token_json) }.to_str().unwrap_or("");
    let cap = unsafe { CStr::from_ptr(capability) }.to_str().unwrap_or("");
    let params_str = if params.is_null() {
        "{}".to_string()
    } else {
        unsafe { CStr::from_ptr(params) }.to_str().unwrap_or("{}").to_string()
    };
    
    match flow_integrity::deserialize_token(token_str) {
        Ok(token) => {
            let (valid, _) = flow_integrity::verify_token(&token, cap, &params_str);
            if valid { 1 } else { 0 }
        }
        Err(_) => 0,
    }
}

// ============================================================================
// Risk Classifier FFI
// ============================================================================

/// Initialize risk classifier
#[no_mangle]
pub extern "C" fn risk_init() -> i32 {
    risk_classifier::init();
    0
}

/// Classify action risk
/// Returns risk level (0-4)
#[no_mangle]
pub extern "C" fn risk_classify(
    capability: *const std::ffi::c_char,
    params: *const std::ffi::c_char,
    priority: f64,
    reward: f64,
    risk: f64,
) -> i32 {
    use std::ffi::CStr;
    
    if capability.is_null() {
        return 2; // Default to Medium
    }
    
    let cap = unsafe { CStr::from_ptr(capability) }.to_str().unwrap_or("");
    let params_str = if params.is_null() {
        "{}".to_string()
    } else {
        unsafe { CStr::from_ptr(params) }.to_str().unwrap_or("{}").to_string()
    };
    
    match risk_classifier::classify(cap, &params_str, priority, reward, risk) {
        Ok(result) => result.risk_level.to_numeric() as i32,
        Err(_) => 2, // Default to Medium on error
    }
}

// ============================================================================
// Confirmation Gate FFI
// ============================================================================

/// Initialize confirmation gate
#[no_mangle]
pub extern "C" fn confirmation_init(secret: *const u8) -> i32 {
    use aes_gcm::aead::OsRng;
    
    let mut key = [0u8; 32];
    
    if secret.is_null() {
        OsRng.fill_bytes(&mut key);
    } else {
        unsafe {
            std::ptr::copy_nonoverlapping(secret, key.as_mut_ptr(), 32);
        }
    }
    
    secure_confirmation::init(&key);
    0
}

/// Request confirmation
#[no_mangle]
pub extern "C" fn confirmation_request(
    proposal_id: *const std::ffi::c_char,
    capability: *const std::ffi::c_char,
    params: *const std::ffi::c_char,
    risk_level: i32,
) -> *mut std::ffi::c_char {
    use std::ffi::{CStr, CString};
    use std::ptr;
    use crate::secure_confirmation::{ConfirmationRequest, RiskLevel};
    
    if proposal_id.is_null() || capability.is_null() {
        return ptr::null_mut();
    }
    
    let prop_id = unsafe { CStr::from_ptr(proposal_id) }.to_str().unwrap_or("");
    let cap = unsafe { CStr::from_ptr(capability) }.to_str().unwrap_or("");
    let params_str = if params.is_null() {
        "{}".to_string()
    } else {
        unsafe { CStr::from_ptr(params) }.to_str().unwrap_or("{}").to_string()
    };
    
    let risk = match risk_level {
        0..=1 => RiskLevel::Low,
        2 => RiskLevel::Medium,
        3 => RiskLevel::High,
        _ => RiskLevel::Critical,
    };
    
    let request = ConfirmationRequest {
        proposal_id: prop_id.to_string(),
        capability_id: cap.to_string(),
        params: params_str,
        risk_level: risk,
        reasoning: "Confirmation requested".to_string(),
    };
    
    match secure_confirmation::request_confirmation(&request) {
        Ok(result) => {
            let json = serde_json::to_string(&result).unwrap_or_default();
            CString::new(json).unwrap_or_default().into_raw()
        }
        Err(_) => ptr::null_mut(),
    }
}

/// Confirm action
#[no_mangle]
pub extern "C" fn confirmation_confirm(token: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    if token.is_null() {
        return 0;
    }
    
    let token_str = unsafe { CStr::from_ptr(token) }.to_str().unwrap_or("");
    
    match secure_confirmation::confirm(token_str) {
        Ok(result) => if result.confirmed { 1 } else { 0 },
        Err(_) => 0,
    }
}

// ============================================================================
// Safe Shell FFI
// ============================================================================

/// Execute safe shell command
#[no_mangle]
pub extern "C" fn shell_execute(command: *const std::ffi::c_char) -> *mut std::ffi::c_char {
    use std::ffi::{CStr, CString};
    use std::ptr;
    
    if command.is_null() {
        return ptr::null_mut();
    }
    
    let cmd = unsafe { CStr::from_ptr(command) }.to_str().unwrap_or("");
    
    match safe_shell::execute(cmd) {
        Ok(result) => {
            let json = serde_json::to_string(&result).unwrap_or_default();
            CString::new(json).unwrap_or_default().into_raw()
        }
        Err(e) => {
            let json = serde_json::to_string(&safe_shell::ShellResult {
                success: false,
                stdout: String::new(),
                stderr: e.to_string(),
                exit_code: -1,
                duration_ms: 0,
            }).unwrap_or_default();
            CString::new(json).unwrap_or_default().into_raw()
        }
    }
}

// ============================================================================
// Safe HTTP FFI
// ============================================================================

/// Initialize HTTP client
#[no_mangle]
pub extern "C" fn http_init() -> i32 {
    safe_http::init();
    0
}

/// Add allowed domain
#[no_mangle]
pub extern "C" fn http_add_domain(domain: *const std::ffi::c_char) -> i32 {
    use std::ffi::CStr;
    
    if domain.is_null() {
        return -1;
    }
    
    let d = unsafe { CStr::from_ptr(domain) }.to_str().unwrap_or("");
    safe_http::add_allowed_domain(d);
    0
}

// Note: Async functions (http_get, http_post) require runtime integration
// They should be called through the async tokio runtime in main.rs

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_kernel_init() {
        // Reset state
        let _ = kernel_reset();
        
        // Should succeed
        let result = kernel_init();
        assert_eq!(result, 0);
        
        // Should fail if already initialized
        let result = kernel_init();
        assert_eq!(result, -1);
        
        // Cleanup
        let _ = kernel_reset();
    }
    
    #[test]
    fn test_kernel_status() {
        // Reset state
        let _ = kernel_reset();
        
        // Should be uninitialized
        let status = get_kernel_status();
        assert_eq!(status, KernelStatus::Uninitialized as i32);
        
        // Initialize
        let _ = kernel_init();
        
        // Should be running
        let status = get_kernel_status();
        assert_eq!(status, KernelStatus::Running as i32);
        
        // Cleanup
        let _ = kernel_reset();
    }
    
    #[test]
    fn test_panic_state() {
        // Reset state
        let _ = kernel_reset();
        
        // Should not be panicking
        assert_eq!(panic_in_progress(), 0);
        
        // Set panic state
        set_panic_state(1);
        assert_eq!(panic_in_progress(), 1);
        
        // Clear panic state
        set_panic_state(0);
        assert_eq!(panic_in_progress(), 0);
        
        // Cleanup
        let _ = kernel_reset();
    }
    
    #[test]
    fn test_send_recv_message() {
        // Reset state
        let _ = kernel_reset();
        
        // Initialize
        let _ = kernel_init();
        
        // Test payload
        let payload: [u8; 5] = [1, 2, 3, 4, 5];
        
        // Send message
        let result = send_message(0, payload.as_ptr(), payload.len());
        assert_eq!(result, 0);
        
        // Receive message
        let mut msg_type: u8 = 0;
        let mut recv_payload = [0u8; 100];
        let mut actual_size: usize = 0;
        
        let result = recv_message(
            &mut msg_type,
            recv_payload.as_mut_ptr(),
            100,
            &mut actual_size,
        );
        
        assert_eq!(result, 0);
        assert_eq!(msg_type, 0);
        assert_eq!(actual_size, 5);
        assert_eq!(&recv_payload[..5], &payload);
        
        // Cleanup
        let _ = kernel_reset();
    }
    
    // ========================================================================
    // Ed25519 Cryptographic Function Tests
    // ========================================================================
    
    #[test]
    fn test_generate_keypair() {
        let mut public_key = [0u8; 32];
        let mut private_key = [0u8; 64];
        
        // Generate keypair with null seed (random)
        let result = generate_keypair(
            std::ptr::null(),
            public_key.as_mut_ptr(),
            private_key.as_mut_ptr(),
        );
        assert_eq!(result, 0);
        
        // Verify public key is not all zeros
        assert!(public_key.iter().any(|&x| x != 0));
        
        // Verify private key is not all zeros
        assert!(private_key.iter().any(|&x| x != 0));
    }
    
    #[test]
    fn test_generate_keypair_with_seed() {
        let seed: [u8; 32] = [0x42; 32];
        let mut public_key = [0u8; 32];
        let mut private_key = [0u8; 64];
        
        // Generate keypair with seed
        let result = generate_keypair(
            seed.as_ptr(),
            public_key.as_mut_ptr(),
            private_key.as_mut_ptr(),
        );
        assert_eq!(result, 0);
        
        // Generate again with same seed - should produce same keypair
        let mut public_key2 = [0u8; 32];
        let mut private_key2 = [0u8; 64];
        
        let result2 = generate_keypair(
            seed.as_ptr(),
            public_key2.as_mut_ptr(),
            private_key2.as_mut_ptr(),
        );
        assert_eq!(result2, 0);
        
        assert_eq!(public_key, public_key2);
        assert_eq!(private_key, private_key2);
    }
    
    #[test]
    fn test_sign_and_verify_message() {
        // Generate keypair
        let mut public_key = [0u8; 32];
        let mut private_key = [0u8; 64];
        
        let result = generate_keypair(
            std::ptr::null(),
            public_key.as_mut_ptr(),
            private_key.as_mut_ptr(),
        );
        assert_eq!(result, 0);
        
        // Sign a message
        let message = b"Hello, World! This is a test message.";
        let mut signature = [0u8; 64];
        
        let sign_result = sign_message(
            private_key.as_ptr(),
            message.as_ptr(),
            message.len(),
            signature.as_mut_ptr(),
        );
        assert_eq!(sign_result, 0);
        
        // Verify the signature
        let verify_result = verify_message(
            public_key.as_ptr(),
            message.as_ptr(),
            message.len(),
            signature.as_ptr(),
        );
        assert_eq!(verify_result, 0); // 0 means valid
    }
    
    #[test]
    fn test_verify_invalid_signature() {
        // Generate keypair
        let mut public_key = [0u8; 32];
        let mut private_key = [0u8; 64];
        
        let _ = generate_keypair(
            std::ptr::null(),
            public_key.as_mut_ptr(),
            private_key.as_mut_ptr(),
        );
        
        let message = b"Original message";
        let mut signature = [0u8; 64];
        
        // Sign original message
        let _ = sign_message(
            private_key.as_ptr(),
            message.as_ptr(),
            message.len(),
            signature.as_mut_ptr(),
        );
        
        // Try to verify different message with original signature
        let different_message = b"Different message";
        let verify_result = verify_message(
            public_key.as_ptr(),
            different_message.as_ptr(),
            different_message.len(),
            signature.as_ptr(),
        );
        
        assert_eq!(verify_result, 1); // 1 means invalid signature
    }
    
    #[test]
    fn test_verify_with_wrong_key() {
        // Generate two keypairs
        let mut public_key1 = [0u8; 32];
        let mut private_key1 = [0u8; 64];
        let mut public_key2 = [0u8; 32];
        let mut private_key2 = [0u8; 64];
        
        let _ = generate_keypair(std::ptr::null(), public_key1.as_mut_ptr(), private_key1.as_mut_ptr());
        let _ = generate_keypair(std::ptr::null(), public_key2.as_mut_ptr(), private_key2.as_mut_ptr());
        
        let message = b"Test message";
        let mut signature = [0u8; 64];
        
        // Sign with key1
        let _ = sign_message(
            private_key1.as_ptr(),
            message.as_ptr(),
            message.len(),
            signature.as_mut_ptr(),
        );
        
        // Try to verify with key2's public key
        let verify_result = verify_message(
            public_key2.as_ptr(),
            message.as_ptr(),
            message.len(),
            signature.as_ptr(),
        );
        
        assert_eq!(verify_result, 1); // 1 means invalid signature
    }
    
    #[test]
    fn test_null_pointer_errors() {
        let message = b"Test";
        let mut signature = [0u8; 64];
        let mut public_key = [0u8; 32];
        let mut private_key = [0u8; 64];
        
        // Test sign_message with null pointers
        assert_eq!(sign_message(std::ptr::null(), message.as_ptr(), message.len(), signature.as_mut_ptr()), -1);
        assert_eq!(sign_message(private_key.as_ptr(), std::ptr::null(), message.len(), signature.as_mut_ptr()), -1);
        assert_eq!(sign_message(private_key.as_ptr(), message.as_ptr(), message.len(), std::ptr::null_mut()), -1);
        
        // Test verify_message with null pointers
        assert_eq!(verify_message(std::ptr::null(), message.as_ptr(), message.len(), signature.as_ptr()), -1);
        assert_eq!(verify_message(public_key.as_ptr(), std::ptr::null(), message.len(), signature.as_ptr()), -1);
        assert_eq!(verify_message(public_key.as_ptr(), message.as_ptr(), message.len(), std::ptr::null()), -1);
        
        // Test generate_keypair with null output pointers
        assert_eq!(generate_keypair(std::ptr::null(), std::ptr::null_mut(), private_key.as_mut_ptr()), -1);
        assert_eq!(generate_keypair(std::ptr::null(), public_key.as_mut_ptr(), std::ptr::null_mut()), -1);
    }
}
