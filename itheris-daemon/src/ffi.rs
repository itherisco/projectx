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
    self, FFI_IPC_Message, IPCEntryType, IPCMessage, IPC_MAGIC, IPC_VERSION,
    MAX_PAYLOAD_SIZE,
};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use once_cell::sync::Lazy;

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

/// Initialize the kernel (C ABI)
///
/// Returns:
/// - 0 on success
/// - -1 if already initialized
/// - -2 on error
#[no_mangle]
pub extern "C" fn kernel_init() -> i32 {
    if KERNEL_INITIALIZED.load(Ordering::Acquire) {
        log::warn!("[FFI] Kernel already initialized");
        return -1;
    }
    
    // Initialize shared memory
    let shm = shared_memory::create_shared_memory_ipc();
    match shm.initialize() {
        Ok(()) => {
            KERNEL_INITIALIZED.store(true, Ordering::Release);
            KERNEL_RUNNING.store(true, Ordering::Release);
            log::info!("[FFI] Kernel initialized successfully");
            0
        }
        Err(e) => {
            log::error!("[FFI] Failed to initialize kernel: {}", e);
            -2
        }
    }
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
// Additional FFI functions for better Julia integration
// ============================================================================

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
}
