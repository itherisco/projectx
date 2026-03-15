//! IPC Bridge Module - Ring Buffer Protocol for Rust-Julia Communication
//!
//! This module implements the shared memory IPC bridge between the Rust Ring 0 kernel
//! and the Julia Ring 3 runtime. It uses a lock-free ring buffer protocol with
//! mutex protection for thread-safe access.
//!
//! # Memory Layout
//! - Shared memory region: 0x01000000 - 0x01100000 (16MB)
//! - Ring buffer: Fixed address for direct hardware access
//!
//! # Concurrency
//! All IPC operations are protected by mutexes to prevent race conditions
//! between the Rust kernel and Julia runtime threads.

use bitflags::bitflags;
use std::sync::{Mutex, RwLock, Arc, Semaphore};
use std::sync::atomic::AtomicBool;
use crate::panic_translation::{TranslatedPanic, JuliaExceptionCode};

/// IPC entry magic number ("ITHR")
pub const IPC_MAGIC: u32 = 0x49_54_48_52;

/// IPC protocol version
pub const IPC_VERSION: u16 = 1;

/// IPC entry types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum IPCEntryType {
    /// Thought cycle from Julia to Rust
    ThoughtCycle = 0,
    /// Integration action proposal (verified)
    IntegrationActionProposal = 1,
    /// Response from Rust to Julia
    Response = 2,
    /// Heartbeat/health check
    Heartbeat = 3,
    /// Panic/exception from Rust to Julia
    PanicTranslation = 4,
}

/// IPC entry flags
#[bitflags]
#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum IPCFlags {
    /// Entry has been processed
    Processed = 0x01,
    /// Entry is valid (signature verified)
    Valid = 0x02,
    /// Entry is a response
    IsResponse = 0x04,
}

/// IPC entry - the fundamental unit of communication
/// Size: 4 + 2 + 1 + 1 + 4 + 32 + 32 + 64 + 4096 + 4 = 4240 bytes
#[derive(Debug, Clone)]
#[repr(C, packed)]
pub struct IPCEntry {
    /// Magic number (0x49544852)
    pub magic: u32,
    /// Protocol version
    pub version: u16,
    /// Entry type
    pub entry_type: u8,
    /// Flags
    pub flags: u8,
    /// Payload length
    pub length: u32,
    /// Cryptographic identity (32 bytes)
    pub identity: [u8; 32],
    /// SHA-256 hash of payload (32 bytes)
    pub message_hash: [u8; 32],
    /// Ed25519 signature (64 bytes)
    pub signature: [u8; 64],
    /// Variable length payload (up to 4096 bytes)
    pub payload: [u8; 4096],
    /// CRC32 checksum
    pub checksum: u32,
}

impl IPCEntry {
    /// Create a new IPC entry
    pub fn new(entry_type: IPCEntryType) -> Self {
        IPCEntry {
            magic: IPC_MAGIC,
            version: IPC_VERSION,
            entry_type: entry_type as u8,
            flags: 0,
            length: 0,
            identity: [0; 32],
            message_hash: [0; 32],
            signature: [0; 64],
            payload: [0; 4096],
            checksum: 0,
        }
    }
    
    /// Validate the entry header
    pub fn is_valid(&self) -> bool {
        self.magic == IPC_MAGIC && self.version == IPC_VERSION
    }
    
    /// Check if entry has been processed
    pub fn is_processed(&self) -> bool {
        self.flags & IPCFlags::Processed.bits() != 0
    }
    
    /// Mark entry as processed
    pub fn set_processed(&mut self) {
        self.flags |= IPCFlags::Processed.bits();
    }
    
    /// Get the entry type
    pub fn get_entry_type(&self) -> Option<IPCEntryType> {
        match self.entry_type {
            0 => Some(IPCEntryType::ThoughtCycle),
            1 => Some(IPCEntryType::IntegrationActionProposal),
            2 => Some(IPCEntryType::Response),
            3 => Some(IPCEntryType::Heartbeat),
            4 => Some(IPCEntryType::PanicTranslation),
            _ => None,
        }
    }
    
    /// Create an IPC entry from a translated panic
    pub fn from_panic(panic: &TranslatedPanic) -> Self {
        let mut entry = IPCEntry::new(IPCEntryType::PanicTranslation);
        
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

/// Ring buffer for IPC
pub mod ring_buffer {
    use super::*;
    use lockfree::ring_buffer::{RingBuffer, RB};
    use std::sync::{Mutex, RwLock};
    
    /// Maximum entries in the ring buffer
    pub const RING_BUFFER_CAPACITY: usize = 256;
    
    /// IPC Ring Buffer - DEPRECATED: Use SyncIpcRingBuffer instead
    /// 
    /// This is kept for backward compatibility but should not be used directly
    /// in multi-threaded contexts.
    #[deprecated(since = "5.0.0", note = "Use SyncIpcRingBuffer for thread-safe access")]
    pub struct IpcRingBuffer {
        /// The underlying lock-free ring buffer
        buffer: RB<IPCEntry>,
    }
    
    #[allow(deprecated)]
    impl IpcRingBuffer {
        /// Create a new IPC ring buffer
        #[deprecated(since = "5.0.0", note = "Use SyncIpcRingBuffer::new() instead")]
        pub fn new() -> Self {
            let buffer = RB::new(RING_BUFFER_CAPACITY);
            IpcRingBuffer { buffer }
        }
        
        /// Try to push an entry to the ring buffer
        #[deprecated(since = "5.0.0", note = "Use SyncIpcRingBuffer::push() instead")]
        pub fn push(&self, entry: &IPCEntry) -> bool {
            self.buffer.push(entry).is_ok()
        }
        
        /// Try to pop an entry from the ring buffer
        #[deprecated(since = "5.0.0", note = "Use SyncIpcRingBuffer::pop() instead")]
        pub fn pop(&self) -> Option<IPCEntry> {
            self.buffer.pop()
        }
        
        /// Check if buffer is full
        pub fn is_full(&self) -> bool {
            self.buffer.is_full()
        }
        
        /// Check if buffer is empty
        pub fn is_empty(&self) -> bool {
            self.buffer.is_empty()
        }
        
        /// Get the number of available entries
        pub fn len(&self) -> usize {
            self.buffer.len()
        }
    }
    
    #[allow(deprecated)]
    impl Default for IpcRingBuffer {
        fn default() -> Self {
            Self::new()
        }
    }
}

/// Shared memory region management
pub mod shm {
    use std::sync::{Semaphore, atomic::AtomicBool};
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
    use crate::panic_translation::JuliaExceptionCode;
    
    /// Shared memory errors
    #[derive(Debug)]
    pub enum ShmError {
        /// Failed to acquire lock
        LockFailed,
        /// Region not mapped
        NotMapped,
        /// Invalid address
        InvalidAddress,
        /// Memory allocation failed
        OutOfMemory,
    }
    
    impl std::fmt::Display for ShmError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                ShmError::LockFailed => write!(f, "Failed to acquire shared memory lock"),
                ShmError::NotMapped => write!(f, "Shared memory region not mapped"),
                ShmError::InvalidAddress => write!(f, "Invalid memory address"),
                ShmError::OutOfMemory => write!(f, "Out of memory"),
            }
        }
    }
    
    impl std::error::Error for ShmError {}
    
    /// Result type for shared memory operations
    pub type ShmResult<T> = Result<T, ShmError>;
    
    /// Shared memory region addresses (physical)
    pub mod phys {
        /// IPC shared memory start
        pub const IPC_START: u64 = 0x0100_0000;
        
        /// IPC shared memory size (16MB)
        pub const IPC_SIZE: u64 = 0x0010_0000;
        
        /// IPC shared memory end (exclusive)
        pub const IPC_END: u64 = IPC_START + IPC_SIZE;
    }
    
    /// Shared memory region addresses (virtual - for identity mapping)
    pub mod virt {
        /// IPC shared memory start (identity mapped)
        pub const IPC_START: u64 = 0x0100_0000;
        
        /// IPC shared memory size
        pub const IPC_SIZE: u64 = 0x0010_0000;
    }
    
    /// Shared memory synchronization primitives
    /// 
    /// These provide atomic operations and semaphores for coordinating
    /// access to shared memory between Rust and Julia.
    pub mod sync {
        use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
        use std::sync::Semaphore;
        
        /// Maximum number of concurrent readers
        pub const MAX_READERS: usize = 16;
        
        /// Shared memory lock state
        pub struct ShmLock {
            /// Atomic flag indicating if write lock is held
            write_locked: AtomicBool,
            /// Reader count
            reader_count: AtomicUsize,
            /// Semaphore for limiting concurrent readers
            reader_sem: Semaphore,
        }
        
        impl ShmLock {
            /// Create a new shared memory lock
            pub fn new() -> Self {
                ShmLock {
                    write_locked: AtomicBool::new(false),
                    reader_count: AtomicUsize::new(0),
                    reader_sem: Semaphore::new(MAX_READERS),
                }
            }
            
            /// Try to acquire a write lock
            /// 
            /// Returns true if the lock was acquired, false if already locked
            pub fn try_write_lock(&self) -> bool {
                // Try to set write_locked from false to true
                self.write_locked.compare_and_swap(false, true, Ordering::Acquire)
                    == false
            }
            
            /// Acquire a write lock (blocks until available)
            pub fn write_lock(&self) -> ShmWriteGuard {
                while !self.try_write_lock() {
                    std::thread::sleep(std::time::Duration::from_micros(100));
                }
                ShmWriteGuard { lock: self }
            }
            
            /// Try to acquire a read lock
            /// 
            /// Returns Some(guard) if successful, None if too many readers
            pub fn try_read_lock(&self) -> Option<ShmReadGuard> {
                // Check if write lock is held
                if self.write_locked.load(Ordering::Acquire) {
                    return None;
                }
                
                // Try to acquire reader permit
                match self.reader_sem.try_acquire() {
                    Ok(_permit) => {
                        self.reader_count.fetch_add(1, Ordering::AcqRel);
                        Some(ShmReadGuard { lock: self })
                    }
                    Err(_) => None,
                }
            }
            
            /// Check if write lock is held
            pub fn is_write_locked(&self) -> bool {
                self.write_locked.load(Ordering::Acquire)
            }
            
            /// Get current reader count
            pub fn reader_count(&self) -> usize {
                self.reader_count.load(Ordering::Acquire)
            }
        }
        
        impl Default for ShmLock {
            fn default() -> Self {
                Self::new()
            }
        }
        
        /// Guard for read access
        pub struct ShmReadGuard<'a> {
            lock: &'a ShmLock,
        }
        
        impl<'a> Drop for ShmReadGuard<'a> {
            fn drop(&mut self) {
                self.lock.reader_count.fetch_sub(1, Ordering::AcqRel);
                // Note: Semaphore permit is automatically released
            }
        }
        
        /// Guard for write access
        pub struct ShmWriteGuard<'a> {
            lock: &'a ShmLock,
        }
        
        impl<'a> Drop for ShmWriteGuard<'a> {
            fn drop(&mut self) {
                self.lock.write_locked.store(false, Ordering::Release);
            }
        }
        
        /// Atomic shared memory counter for sequence numbers
        pub struct ShmSequence {
            sequence: AtomicU64,
        }
        
        impl ShmSequence {
            pub fn new() -> Self {
                ShmSequence {
                    sequence: AtomicU64::new(0),
                }
            }
            
            /// Get next sequence number
            pub fn next(&self) -> u64 {
                self.sequence.fetch_add(1, Ordering::AcqRel)
            }
            
            /// Get current sequence number
            pub fn current(&self) -> u64 {
                self.sequence.load(Ordering::Acquire)
            }
        }
        
        impl Default for ShmSequence {
            fn default() -> Self {
                Self::new()
            }
        }
    }
    
    /// Shared memory region descriptor
    #[derive(Debug)]
    pub struct ShmRegion {
        /// Physical start address
        pub phys_start: u64,
        /// Virtual start address
        pub virt_start: u64,
        /// Size in bytes
        pub size: u64,
        /// Whether the region is mapped
        pub mapped: bool,
        /// Synchronization primitives for this region
        sync: Option<sync::ShmLock>,
        /// Sequence number for this region
        sequence: sync::ShmSequence,
    }
    
    impl ShmRegion {
        /// Create a new shared memory region
        pub fn new(phys_start: u64, virt_start: u64, size: u64) -> Self {
            ShmRegion {
                phys_start,
                virt_start,
                size,
                mapped: false,
                sync: Some(sync::ShmLock::new()),
                sequence: sync::ShmSequence::new(),
            }
        }
        
        /// Get the IPC shared memory region
        pub fn ipc_region() -> Self {
            ShmRegion::new(
                phys::IPC_START,
                virt::IPC_START,
                phys::IPC_SIZE,
            )
        }
        
        /// Mark as mapped
        pub fn set_mapped(&mut self) {
            self.mapped = true;
        }
        
        /// Get the synchronization lock for this region
        pub fn lock(&self) -> Option<&sync::ShmLock> {
            self.sync.as_ref()
        }
        
        /// Get next sequence number for this region
        pub fn next_sequence(&self) -> u64 {
            self.sequence.next()
        }
        
        /// Acquire write lock for this region
        #[allow(dead_code)]
        pub fn write_lock(&self) -> Option<sync::ShmWriteGuard> {
            self.sync.as_ref().map(|l| l.write_lock())
        }
        
        /// Try to acquire read lock for this region
        #[allow(dead_code)]
        pub fn try_read_lock(&self) -> Option<sync::ShmReadGuard> {
            self.sync.as_ref().and_then(|l| l.try_read_lock())
        }
    }
}

/// IPC error types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IPCError {
    /// Buffer is full
    BufferFull,
    /// Buffer is empty
    BufferEmpty,
    /// Invalid entry
    InvalidEntry,
    /// Signature verification failed
    SignatureInvalid,
    /// Checksum mismatch
    ChecksumMismatch,
    /// Unknown entry type
    UnknownEntryType,
    /// Mutex lock error
    LockError,
    /// Poisoned lock (thread panicked while holding lock)
    PoisonedLock,
}

impl std::fmt::Display for IPCError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IPCError::BufferFull => write!(f, "IPC buffer is full"),
            IPCError::BufferEmpty => write!(f, "IPC buffer is empty"),
            IPCError::InvalidEntry => write!(f, "Invalid IPC entry"),
            IPCError::SignatureInvalid => write!(f, "Signature verification failed"),
            IPCError::ChecksumMismatch => write!(f, "Checksum mismatch"),
            IPCError::UnknownEntryType => write!(f, "Unknown IPC entry type"),
            IPCError::LockError => write!(f, "Failed to acquire IPC lock"),
            IPCError::PoisonedLock => write!(f, "IPC lock poisoned (thread panicked)"),
        }
    }
}

impl std::error::Error for IPCError {}

/// Thread-safe result type for IPC operations
pub type IPCResult<T> = Result<T, IPCError>;

/// Synchronized IPC Ring Buffer with mutex protection
/// 
/// This wrapper provides thread-safe access to the underlying lock-free
/// ring buffer, preventing race conditions between Rust and Julia threads.
pub struct SyncIpcRingBuffer {
    /// The underlying lock-free ring buffer
    inner: RB<IPCEntry>,
    /// Mutex for exclusive access
    write_mutex: Mutex<()>,
    /// Read lock for multiple readers
    read_mutex: RwLock<()>,
}

impl SyncIpcRingBuffer {
    /// Create a new synchronized IPC ring buffer
    pub fn new(capacity: usize) -> Self {
        let buffer = RB::new(capacity);
        SyncIpcRingBuffer {
            inner: buffer,
            write_mutex: Mutex::new(()),
            read_mutex: RwLock::new(()),
        }
    }
    
    /// Push an entry to the ring buffer with mutex protection
    /// 
    /// Returns an error if the buffer is full or if the lock cannot be acquired
    pub fn push(&self, entry: &IPCEntry) -> IPCResult<bool> {
        let _write_guard = self.write_mutex.lock()
            .map_err(|_| IPCError::PoisonedLock)?;
        Ok(self.inner.push(entry).is_ok())
    }
    
    /// Pop an entry from the ring buffer with mutex protection
    /// 
    /// Returns an error if the buffer is empty or if the lock cannot be acquired
    pub fn pop(&self) -> IPCResult<Option<IPCEntry>> {
        let _read_guard = self.read_mutex.read()
            .map_err(|_| IPCError::PoisonedLock)?;
        Ok(self.inner.pop())
    }
    
    /// Try to pop without blocking
    pub fn try_pop(&self) -> IPCResult<Option<IPCEntry>> {
        // Try to acquire read lock without blocking
        let read_guard = match self.read_mutex.try_read() {
            Ok(guard) => guard,
            Err(_) => return Ok(None), // Could not acquire lock, not an error
        };
        let _ = read_guard; // Keep guard alive
        Ok(self.inner.pop())
    }
    
    /// Check if buffer is full
    pub fn is_full(&self) -> bool {
        self.inner.is_full()
    }
    
    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }
    
    /// Get the number of entries in the buffer
    pub fn len(&self) -> usize {
        self.inner.len()
    }
    
    /// Get the capacity of the buffer
    pub fn capacity(&self) -> usize {
        self.inner.capacity()
    }
}

impl Default for SyncIpcRingBuffer {
    fn default() -> Self {
        Self::new(RING_BUFFER_CAPACITY)
    }
}

/// Shared ownership wrapper for synchronized IPC buffer
pub type SharedSyncBuffer = Arc<SyncIpcRingBuffer>;
