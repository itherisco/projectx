//! Panic Translation Layer - FFI Boundary Error Handling
//!
//! This module provides robust error handling at the Rust-Julia FFI boundary.
//! It catches Rust panics and translates them into meaningful Julia exceptions
//! that can be handled by the Julia application.
//!
//! # Design Principles
//! - All FFI entry points use `catch_unwind` to prevent Rust panics from crashing Julia
//! - Panics are converted to structured error types with rich context
//! - Error messages are propagated through the IPC bridge
//! - The system remains stable even when Rust code panics

use std::panic;
use std::sync::atomic::{AtomicBool, Ordering};
use std::ffi::{CString, CStr};
use std::ptr;

/// Global flag indicating whether a panic is currently being handled
static PANIC_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// Maximum length of panic message to capture
const MAX_PANIC_MESSAGE_LEN: usize = 4096;

/// Keyword to exception code mapping for automatic panic message parsing
const PANIC_KEYWORD_MAPPINGS: &[(&str, JuliaExceptionCode)] = &[
    ("memory", JuliaExceptionCode::OutOfMemory),
    ("out of memory", JuliaExceptionCode::OutOfMemory),
    ("oom", JuliaExceptionCode::OutOfMemory),
    ("alloc", JuliaExceptionCode::OutOfMemory),
    ("lock", JuliaExceptionCode::LockError),
    ("mutex", JuliaExceptionCode::LockError),
    ("rwlock", JuliaExceptionCode::LockError),
    ("poisoned", JuliaExceptionCode::LockError),
    ("thread", JuliaExceptionCode::ThreadPanic),
    ("task", JuliaExceptionCode::ThreadPanic),
    ("crypto", JuliaExceptionCode::CryptoError),
    ("encryption", JuliaExceptionCode::CryptoError),
    ("decryption", JuliaExceptionCode::CryptoError),
    ("invalid", JuliaExceptionCode::InvalidArgument),
    ("null", JuliaExceptionCode::InvalidArgument),
    ("not implemented", JuliaExceptionCode::NotImplemented),
    ("unimplemented", JuliaExceptionCode::NotImplemented),
    ("capability", JuliaExceptionCode::CapabilityDenied),
    ("permission", JuliaExceptionCode::CapabilityDenied),
    ("forbidden", JuliaExceptionCode::CapabilityDenied),
    ("ipc", JuliaExceptionCode::IPCError),
    ("channel", JuliaExceptionCode::IPCError),
    ("kernel", JuliaExceptionCode::KernelViolation),
    ("shared memory", JuliaExceptionCode::SharedMemoryError),
    ("shm", JuliaExceptionCode::SharedMemoryError),
    ("buffer full", JuliaExceptionCode::BufferFull),
    ("buffer overflow", JuliaExceptionCode::BufferFull),
    ("buffer empty", JuliaExceptionCode::BufferEmpty),
    ("underflow", JuliaExceptionCode::BufferEmpty),
];

/// Analyze a panic message to infer the appropriate JuliaExceptionCode
/// 
/// This function searches for known keywords in the panic message to
/// determine the most appropriate exception code.
/// 
/// # Arguments
/// * `message` - The panic message to analyze
/// 
/// # Returns
/// The inferred JuliaExceptionCode, or Unknown if no match found
pub fn infer_exception_from_panic(message: &str) -> JuliaExceptionCode {
    let lowercase_msg = message.to_lowercase();
    
    for (keyword, code) in PANIC_KEYWORD_MAPPINGS {
        if lowercase_msg.contains(keyword) {
            return *code;
        }
    }
    
    JuliaExceptionCode::Unknown
}

/// Julia exception codes that can be raised from Rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum JuliaExceptionCode {
    /// Unknown/unhandled panic
    Unknown = 1,
    /// Out of memory
    OutOfMemory = 2,
    /// Invalid argument passed to Rust function
    InvalidArgument = 3,
    /// Rust function not implemented
    NotImplemented = 4,
    /// Rust function returned an error
    RustError = 5,
    /// Thread panicked while executing
    ThreadPanic = 6,
    /// Capability check failed
    CapabilityDenied = 7,
    /// Cryptographic operation failed
    CryptoError = 8,
    /// IPC communication error
    IPCError = 9,
    /// Kernel enforcement violation
    KernelViolation = 10,
    /// Shared memory error
    SharedMemoryError = 11,
    /// Lock/Mutex error
    LockError = 12,
    /// Buffer full
    BufferFull = 13,
    /// Buffer empty
    BufferEmpty = 14,
}

/// Structure representing a translated panic for FFI
#[derive(Debug, Clone)]
#[repr(C)]
pub struct TranslatedPanic {
    /// Exception code (matches Julia exception codes)
    pub exception_code: u32,
    /// Human-readable message (null-terminated C string)
    pub message: [u8; 256],
    /// Location where panic occurred (file)
    pub file: [u8; 128],
    /// Location where panic occurred (line number)
    pub line: u32,
    /// Location where panic occurred (column)
    pub column: u32,
    /// Whether this is a genuine panic vs. synthetic error
    pub is_panic: u8,
}

impl TranslatedPanic {
    /// Create a new translated panic from a panic info
    /// 
    /// Automatically infers the exception code from the panic message
    /// using keyword matching.
    pub fn from_panic_info(info: &panic::PanicInfo) -> Self {
        let message = if let Some(s) = info.message() {
            let msg = format!("{:?}", s);
            Self::truncate_to_array(msg.as_bytes(), MAX_PANIC_MESSAGE_LEN)
        } else {
            [0u8; 256]
        };

        let (file, line, column) = if let Some(loc) = info.location() {
            let file_bytes = Self::truncate_to_array(loc.file().as_bytes(), 127);
            (
                file_bytes,
                loc.line() as u32,
                loc.column() as u32,
            )
        } else {
            ([0u8; 128], 0, 0)
        };

        // Infer exception code from panic message
        let msg_str = if let Some(s) = info.message() {
            format!("{:?}", s)
        } else {
            String::new()
        };
        let inferred_code = infer_exception_from_panic(&msg_str);

        TranslatedPanic {
            exception_code: inferred_code as u32,
            message,
            file,
            line,
            column,
            is_panic: 1,
        }
    }

    /// Create a synthetic (non-panic) error
    pub fn from_error_code(code: JuliaExceptionCode, message: &str) -> Self {
        let msg_bytes = Self::truncate_to_array(message.as_bytes(), 255);
        
        TranslatedPanic {
            exception_code: code as u32,
            message: msg_bytes,
            file: [0u8; 128],
            line: 0,
            column: 0,
            is_panic: 0,
        }
    }

    /// Truncate bytes to fit a fixed-size array, null-terminate
    fn truncate_to_array(bytes: &[u8], max_len: usize) -> [u8; 256] {
        let mut arr = [0u8; 256];
        let copy_len = bytes.len().min(max_len);
        arr[..copy_len].copy_from_slice(&bytes[..copy_len]);
        arr
    }

    /// Get the message as a Rust String
    pub fn get_message(&self) -> String {
        let len = self.message.iter().position(|&b| b == 0).unwrap_or(256);
        String::from_utf8_lossy(&self.message[..len]).to_string()
    }

    /// Get the file as a Rust String
    pub fn get_file(&self) -> String {
        let len = self.file.iter().position(|&b| b == 0).unwrap_or(128);
        String::from_utf8_lossy(&self.file[..len]).to_string()
    }
}

/// FFI-safe result type for panic-wrapped operations
#[derive(Debug, Clone)]
#[repr(C)]
pub struct FFIResult {
    /// 0 for success, non-zero for error
    pub success: i32,
    /// Error code (if success is non-zero)
    pub error_code: u32,
    /// Pointer to translated panic (must be freed by caller)
    pub error_ptr: *const TranslatedPanic,
}

impl FFIResult {
    /// Create a success result
    pub fn success() -> Self {
        FFIResult {
            success: 0,
            error_code: 0,
            error_ptr: ptr::null(),
        }
    }

    /// Create an error result from a translated panic
    pub fn from_panic(panic: TranslatedPanic) -> Self {
        FFIResult {
            success: -1,
            error_code: panic.exception_code,
            error_ptr: Box::into_raw(Box::new(panic)),
        }
    }

    /// Create an error result from an error code and message
    pub fn from_error(code: JuliaExceptionCode, message: &str) -> Self {
        let panic = TranslatedPanic::from_error_code(code, message);
        Self::from_panic(panic)
    }
}

/// Trait for types that can be safely translated across FFI
pub trait FFISafe {
    /// Convert to FFI-safe representation
    fn to_ffi(&self) -> FFIResult;
}

// ============================================================================
// FFISafe Implementations for Common Rust Error Types
// ============================================================================

impl FFISafe for std::io::Error {
    /// Convert std::io::Error to FFI result
    /// 
    /// Maps IO errors to appropriate Julia exception codes:
    /// - NotFound -> InvalidArgument
    /// - PermissionDenied -> CapabilityDenied
    /// - OutOfMemory -> OutOfMemory (if applicable)
    /// - Other -> RustError
    fn to_ffi(&self) -> FFIResult {
        let code = match self.kind() {
            std::io::ErrorKind::NotFound => JuliaExceptionCode::InvalidArgument,
            std::io::ErrorKind::PermissionDenied => JuliaExceptionCode::CapabilityDenied,
            std::io::ErrorKind::OutOfMemory => JuliaExceptionCode::OutOfMemory,
            std::io::ErrorKind::AddrInUse | std::io::ErrorKind::AddrNotAvailable => {
                JuliaExceptionCode::LockError
            }
            std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => {
                JuliaExceptionCode::BufferEmpty
            }
            _ => JuliaExceptionCode::RustError,
        };
        
        FFIResult::from_error(code, &self.to_string())
    }
}

impl FFISafe for String {
    /// Convert String to FFI result
    /// 
    /// Analyzes the string content to infer the appropriate exception code
    /// using keyword matching, then wraps it in an FFI result.
    fn to_ffi(&self) -> FFIResult {
        let code = infer_exception_from_panic(self);
        FFIResult::from_error(code, self)
    }
}

impl FFISafe for &'static str {
    /// Convert static string slice to FFI result
    /// 
    /// Analyzes the string content to infer the appropriate exception code
    /// using keyword matching, then wraps it in an FFI result.
    fn to_ffi(&self) -> FFIResult {
        let code = infer_exception_from_panic(self);
        FFIResult::from_error(code, self)
    }
}

/// Extension trait for convenient FFI conversion
pub trait IntoFFIResult {
    /// Convert to FFI result
    fn into_ffi(self) -> FFIResult;
}

impl IntoFFIResult for std::io::Error {
    fn into_ffi(self) -> FFIResult {
        FFISafe::to_ffi(&self)
    }
}

impl IntoFFIResult for String {
    fn into_ffi(self) -> FFIResult {
        FFISafe::to_ffi(&self)
    }
}

impl IntoFFIResult for &str {
    fn into_ffi(self) -> FFIResult {
        FFISafe::to_ffi(&self)
    }
}

/// Execute a closure with panic catching, returning a FFI result
/// 
/// # Safety
/// This function is designed to be called from FFI boundaries. The closure
/// should not contain any unsafe code that could cause undefined behavior.
#[no_mangle]
pub unsafe extern "C" fn catch_panic<F, T>(func: F) -> FFIResult
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
{
    // Prevent recursive panics from causing infinite loops
    if PANIC_IN_PROGRESS.load(Ordering::SeqCst) {
        return FFIResult::from_error(
            JuliaExceptionCode::ThreadPanic,
            "Recursive panic detected during panic handling",
        );
    }

    PANIC_IN_PROGRESS.store(true, Ordering::SeqCst);

    let result = panic::catch_unwind(panic::AssertUnwindSafe(func));

    PANIC_IN_PROGRESS.store(false, Ordering::SeqCst);

    match result {
        Ok(_ok) => FFIResult::success(),
        Err(panic_info) => {
            let translated = TranslatedPanic::from_panic_info(&panic_info);
            println!(
                "[PANIC_TRANSLATION] Caught panic: {} at {}:{}:{}",
                translated.get_message(),
                translated.get_file(),
                translated.line,
                translated.column
            );
            FFIResult::from_panic(translated)
        }
    }
}

/// Execute a closure with panic catching, returning a raw pointer result
/// 
/// This variant is useful when the closure returns a pointer that needs
/// to be preserved even if a panic occurs.
/// 
/// # Safety
/// The returned pointer is only valid if success is 0.
#[no_mangle]
pub unsafe extern "C" fn catch_panic_ptr<F, T>(func: F) -> (FFIResult, *mut T)
where
    F: FnOnce() -> *mut T + Send + 'static,
    T: Send + 'static,
{
    if PANIC_IN_PROGRESS.load(Ordering::SeqCst) {
        return (
            FFIResult::from_error(
                JuliaExceptionCode::ThreadPanic,
                "Recursive panic detected during panic handling",
            ),
            ptr::null_mut(),
        );
    }

    PANIC_IN_PROGRESS.store(true, Ordering::SeqCst);

    let result = panic::catch_unwind(panic::AssertUnwindSafe(func));

    PANIC_IN_PROGRESS.store(false, Ordering::SeqCst);

    match result {
        Ok(ptr) => (FFIResult::success(), ptr),
        Err(panic_info) => {
            let translated = TranslatedPanic::from_panic_info(&panic_info);
            println!(
                "[PANIC_TRANSLATION] Caught panic in ptr function: {} at {}:{}:{}",
                translated.get_message(),
                translated.get_file(),
                translated.line,
                translated.column
            );
            (FFIResult::from_panic(translated), ptr::null_mut())
        }
    }
}

/// Free a translated panic that was returned from FFI
/// 
/// # Safety
/// The pointer must have been allocated by this module and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn free_translated_panic(ptr: *mut TranslatedPanic) {
    if !ptr.is_null() {
        Box::from_raw(ptr);
    }
}

/// Check if a panic is currently being handled
#[no_mangle]
pub extern "C" fn panic_in_progress() -> bool {
    PANIC_IN_PROGRESS.load(Ordering::SeqCst)
}

/// Raise a Julia exception from Rust
/// 
/// This function can be called to raise a Julia exception that will be
/// caught by the Julia error handling system.
/// 
/// # Safety
/// This should only be called from the Rust FFI layer.
#[no_mangle]
pub unsafe extern "C" fn raise_julia_exception(
    code: u32,
    message: *const libc::c_char,
) -> FFIResult {
    // Use CStr::from_ptr to read the message without taking ownership
    // This prevents memory leaks when the pointer is owned by Julia
    let msg = if !message.is_null() {
        CStr::from_ptr(message)
            .to_string_lossy()
            .into_owned()
    } else {
        "Unknown error".to_string()
    };

    let exception = match code {
        1 => JuliaExceptionCode::Unknown,
        2 => JuliaExceptionCode::OutOfMemory,
        3 => JuliaExceptionCode::InvalidArgument,
        4 => JuliaExceptionCode::NotImplemented,
        5 => JuliaExceptionCode::RustError,
        6 => JuliaExceptionCode::ThreadPanic,
        7 => JuliaExceptionCode::CapabilityDenied,
        8 => JuliaExceptionCode::CryptoError,
        9 => JuliaExceptionCode::IPCError,
        10 => JuliaExceptionCode::KernelViolation,
        11 => JuliaExceptionCode::SharedMemoryError,
        12 => JuliaExceptionCode::LockError,
        13 => JuliaExceptionCode::BufferFull,
        14 => JuliaExceptionCode::BufferEmpty,
        _ => JuliaExceptionCode::Unknown,
    };

    println!("[PANIC_TRANSLATION] Raising Julia exception: {} - {}", code, msg);
    
    FFIResult::from_error(exception, &msg)
}

/// Set up global panic hook that integrates with this translation layer
pub fn install_panic_hook() {
    let old_hook = panic::take_hook();
    
    panic::set_hook(Box::new(move |panic_info| {
        // Check if we're already handling a panic
        if PANIC_IN_PROGRESS.load(Ordering::SeqCst) {
            // Can't do much here, just halt
            eprintln!("[PANIC_TRANSLATION] Double panic during handling - halting");
            loop {
                std::thread::sleep(std::time::Duration::from_secs(1));
            }
        }

        PANIC_IN_PROGRESS.store(true, Ordering::SeqCst);
        
        // Log the panic with detailed information
        if let Some(location) = panic_info.location() {
            eprintln!(
                "[PANIC_TRANSLATION] PANIC at {}:{}:{}",
                location.file(),
                location.line(),
                location.column()
            );
        }
        
        if let Some(message) = panic_info.message() {
            eprintln!("[PANIC_TRANSLATION] Message: {:?}", message);
        }
        
        // Call the old hook for any additional handling
        old_hook(panic_info);
        
        PANIC_IN_PROGRESS.store(false, Ordering::SeqCst);
    }));
    
    println!("[PANIC_TRANSLATION] Global panic hook installed");
}

// ============================================================================
// Integration with IPC System
// ============================================================================

/// Error codes for IPC-based panic translation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IPCPanicError {
    /// The ring buffer is full
    BufferFull,
    /// Failed to serialize panic data
    SerializationFailed,
    /// Invalid IPC entry
    InvalidEntry,
}

/// Convert a translated panic to IPC entry for transmission to Julia
/// 
/// This allows panic information to be sent through the existing IPC bridge.
/// 
/// Note: This module is available in both bare-metal and user-space modes.
/// In bare-metal mode, it uses the full IPC implementation.
/// In user-space mode, it provides a simplified fallback that writes to stderr
/// and returns a basic response structure.
#[cfg(feature = "bare-metal")]
pub mod ipc_translation {
    use super::*;
    use crate::ipc::{IPCEntry, IPCEntryType, IPCFlags};
    
    /// Convert a TranslatedPanic to an IPC entry for Julia
    pub fn panic_to_ipc_entry(panic: &TranslatedPanic) -> IPCEntry {
        let mut entry = IPCEntry::new(IPCEntryType::Response);
        
        // Serialize panic data to JSON payload
        let panic_json = serde_json::json!({
            "type": "panic_translation",
            "exception_code": panic.exception_code,
            "message": panic.get_message(),
            "file": panic.get_file(),
            "line": panic.line,
            "column": panic.column,
            "is_panic": panic.is_panic != 0,
        });
        
        let json_str = panic_json.to_string();
        let bytes = json_str.as_bytes();
        
        // Copy to payload (truncate if necessary)
        let copy_len = bytes.len().min(4096);
        entry.payload[..copy_len].copy_from_slice(&bytes[..copy_len]);
        entry.length = copy_len as u32;
        
        // Mark as valid response
        entry.flags = IPCFlags::Valid.bits() | IPCFlags::IsResponse.bits();
        
        entry
    }
}

/// User-space fallback IPC translation (when bare-metal feature is not enabled)
/// 
/// This provides a simplified implementation for non-bare-metal environments.
/// It writes panic information to stderr and returns a simple status code.
#[cfg(not(feature = "bare-metal"))]
pub mod ipc_translation {
    use super::*;
    use std::io::Write;
    
    /// Simplified IPC entry structure for user-space mode
    #[derive(Debug, Clone)]
    pub struct UserSpaceIPCEntry {
        /// Whether the entry is valid
        pub valid: bool,
        /// Exception code from the panic
        pub exception_code: u32,
        /// Error message
        pub message: String,
    }
    
    impl Default for UserSpaceIPCEntry {
        fn default() -> Self {
            UserSpaceIPCEntry {
                valid: false,
                exception_code: 0,
                message: String::new(),
            }
        }
    }
    
    /// Convert a TranslatedPanic to a user-space IPC entry for Julia
    /// 
    /// In user-space mode, this writes the panic information to stderr
    /// and returns a simplified entry structure.
    pub fn panic_to_ipc_entry(panic: &TranslatedPanic) -> UserSpaceIPCEntry {
        // Write to stderr for visibility
        eprintln!(
            "[PANIC_TRANSLATION] IPC Fallback: Exception {} - {} at {}:{}",
            panic.exception_code,
            panic.get_message(),
            panic.get_file(),
            panic.line
        );
        
        UserSpaceIPCEntry {
            valid: true,
            exception_code: panic.exception_code,
            message: panic.get_message(),
        }
    }
    
    /// Send panic notification via user-space IPC fallback
    /// 
    /// This function provides a simple mechanism to notify Julia of panics
    /// without requiring the bare-metal IPC infrastructure.
    pub fn send_panic_notification(panic: &TranslatedPanic) -> Result<(), IPCPanicError> {
        let entry = panic_to_ipc_entry(panic);
        
        if entry.valid {
            // In a real implementation, this could use pipes, Unix sockets,
            // or other user-space IPC mechanisms
            Ok(())
        } else {
            Err(IPCPanicError::InvalidEntry)
        }
    }
}

/// Helper function to translate a panic and optionally send via IPC
/// 
/// This is the main entry point for panic translation that works in both
/// bare-metal and user-space modes.
#[cfg(not(feature = "bare-metal"))]
pub fn translate_panic_with_ipc(info: &panic::PanicInfo) -> TranslatedPanic {
    let mut translated = TranslatedPanic::from_panic_info(info);
    
    // Infer exception code from panic message
    let msg = translated.get_message();
    translated.exception_code = infer_exception_from_panic(&msg) as u32;
    
    // Attempt to send via IPC (will use fallback in non-bare-metal mode)
    let _ = ipc_translation::send_panic_notification(&translated);
    
    translated
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_translated_panic_from_panic_info() {
        // This test would require triggering an actual panic, 
        // which we don't want to do in unit tests.
        // Instead, we test the error code variant.
        let panic = TranslatedPanic::from_error_code(
            JuliaExceptionCode::InvalidArgument,
            "Test error message",
        );
        
        assert_eq!(panic.exception_code, JuliaExceptionCode::InvalidArgument as u32);
        assert_eq!(panic.get_message(), "Test error message");
        assert_eq!(panic.is_panic, 0);
    }

    #[test]
    fn test_ffi_result_success() {
        let result = FFIResult::success();
        assert_eq!(result.success, 0);
        assert!(result.error_ptr.is_null());
    }

    #[test]
    fn test_ffi_result_from_error() {
        let result = FFIResult::from_error(
            JuliaExceptionCode::RustError,
            "Test error",
        );
        assert_eq!(result.success, -1);
        assert_eq!(result.error_code, JuliaExceptionCode::RustError as u32);
        assert!(!result.error_ptr.is_null());
    }

    #[test]
    fn test_panic_in_progress_flag() {
        assert!(!panic_in_progress());
    }

    #[test]
    fn test_all_exception_codes() {
        // Test all exception codes can be created
        let codes = vec![
            (JuliaExceptionCode::Unknown, "Unknown error"),
            (JuliaExceptionCode::OutOfMemory, "Out of memory"),
            (JuliaExceptionCode::InvalidArgument, "Invalid argument"),
            (JuliaExceptionCode::NotImplemented, "Not implemented"),
            (JuliaExceptionCode::RustError, "Rust error"),
            (JuliaExceptionCode::ThreadPanic, "Thread panic"),
            (JuliaExceptionCode::CapabilityDenied, "Capability denied"),
            (JuliaExceptionCode::CryptoError, "Crypto error"),
            (JuliaExceptionCode::IPCError, "IPC error"),
            (JuliaExceptionCode::KernelViolation, "Kernel violation"),
            (JuliaExceptionCode::SharedMemoryError, "Shared memory error"),
            (JuliaExceptionCode::LockError, "Lock error"),
            (JuliaExceptionCode::BufferFull, "Buffer full"),
            (JuliaExceptionCode::BufferEmpty, "Buffer empty"),
        ];
        
        for (code, msg) in codes {
            let result = FFIResult::from_error(code, msg);
            assert_eq!(result.success, -1);
            assert_eq!(result.error_code, code as u32);
            assert!(!result.error_ptr.is_null());
        }
    }

    #[test]
    fn test_translated_panic_message_truncation() {
        // Test that long messages are truncated properly
        let long_message = "x".repeat(512);
        let panic = TranslatedPanic::from_error_code(
            JuliaExceptionCode::RustError,
            &long_message,
        );
        
        // The message should be truncated to fit in the array
        let retrieved = panic.get_message();
        assert!(retrieved.len() <= 256);
    }

    #[test]
    fn test_translated_panic_file_handling() {
        // Test file handling in panic translation
        let panic = TranslatedPanic::from_error_code(
            JuliaExceptionCode::InvalidArgument,
            "Test error",
        );
        
        let file = panic.get_file();
        assert!(file.is_empty()); // Should be empty for synthetic errors
    }

    #[test]
    fn test_catch_panic_successful_closure() {
        // Test catch_panic with a successful closure
        let result = catch_panic(|| {
            42
        });
        
        assert_eq!(result.success, 0);
        assert_eq!(result.error_code, 0);
        assert!(result.error_ptr.is_null());
    }

    #[test]
    fn test_catch_panic_panicking_closure() {
        // Test catch_panic with a panicking closure
        let result = catch_panic(|| {
            panic!("Test panic message");
        });
        
        assert_eq!(result.success, -1);
        assert_eq!(result.error_code, JuliaExceptionCode::Unknown as u32);
        assert!(!result.error_ptr.is_null());
    }

    #[test]
    fn test_raise_julia_exception_all_codes() {
        // Test raise_julia_exception with all valid codes
        for code in 1..=14u32 {
            let msg = CString::new("Test exception").unwrap();
            let result = unsafe { raise_julia_exception(code, msg.as_ptr()) };
            
            assert_eq!(result.success, -1);
            // The error code should match (or fallback to Unknown for invalid codes)
            assert!(result.error_code > 0);
        }
    }

    #[test]
    fn test_panic_translation_thread_safety() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;
        
        let panic_flag = Arc::new(AtomicBool::new(false));
        let flag_clone = panic_flag.clone();
        
        // Set panic hook that checks the flag
        std::panic::set_hook(Box::new(move |_| {
            flag_clone.store(true, Ordering::SeqCst);
        }));
        
        // Execute a panic
        let _ = catch_panic(|| {
            panic!("Test panic");
        });
        
        // Verify panic was caught
        assert!(panic_flag.load(Ordering::SeqCst));
    }

    // ============================================================================
    // Tests for new features: panic message parsing
    // ============================================================================

    #[test]
    fn test_infer_exception_from_panic_memory_keywords() {
        // Test memory-related keywords
        assert_eq!(
            infer_exception_from_panic("out of memory during allocation"),
            JuliaExceptionCode::OutOfMemory
        );
        assert_eq!(
            infer_exception_from_panic("memory allocation failed"),
            JuliaExceptionCode::OutOfMemory
        );
    }

    #[test]
    fn test_infer_exception_from_panic_lock_keywords() {
        // Test lock-related keywords
        assert_eq!(
            infer_exception_from_panic("lock is poisoned"),
            JuliaExceptionCode::LockError
        );
    }

    #[test]
    fn test_infer_exception_from_panic_thread_keywords() {
        // Test thread-related keywords
        assert_eq!(
            infer_exception_from_panic("thread panicked"),
            JuliaExceptionCode::ThreadPanic
        );
    }

    #[test]
    fn test_infer_exception_from_panic_unknown() {
        // Test unknown message returns Unknown code
        assert_eq!(
            infer_exception_from_panic("some random error"),
            JuliaExceptionCode::Unknown
        );
    }

    // ============================================================================
    // Tests for FFISafe implementations
    // ============================================================================

    #[test]
    fn test_ffi_safe_io_error_not_found() {
        use std::io::ErrorKind;
        let err = std::io::Error::new(ErrorKind::NotFound, "file not found");
        let result = err.to_ffi();
        assert_eq!(result.error_code, JuliaExceptionCode::InvalidArgument as u32);
    }

    #[test]
    fn test_ffi_safe_string() {
        let msg = String::from("out of memory error");
        let result = msg.to_ffi();
        assert_eq!(result.error_code, JuliaExceptionCode::OutOfMemory as u32);
    }

    #[test]
    fn test_ffi_safe_static_str() {
        let msg: &str = "lock mutex poisoned";
        let result = msg.to_ffi();
        assert_eq!(result.error_code, JuliaExceptionCode::LockError as u32);
    }

    // ============================================================================
    // Backward compatibility tests
    // ============================================================================

    #[test]
    fn test_backward_compatible_error_codes() {
        // Ensure all original exception codes still work
        let codes = vec![
            JuliaExceptionCode::Unknown,
            JuliaExceptionCode::OutOfMemory,
            JuliaExceptionCode::InvalidArgument,
            JuliaExceptionCode::NotImplemented,
            JuliaExceptionCode::RustError,
            JuliaExceptionCode::ThreadPanic,
            JuliaExceptionCode::CapabilityDenied,
            JuliaExceptionCode::CryptoError,
            JuliaExceptionCode::IPCError,
            JuliaExceptionCode::KernelViolation,
            JuliaExceptionCode::SharedMemoryError,
            JuliaExceptionCode::LockError,
            JuliaExceptionCode::BufferFull,
            JuliaExceptionCode::BufferEmpty,
        ];
        for code in codes {
            let result = FFIResult::from_error(code, "Test");
            assert_eq!(result.error_code, code as u32);
        }
    }

}
