//! IPC Bridge Module - Ring Buffer Protocol for Rust-Julia Communication
//!
//! This module implements the shared memory IPC bridge between the Rust Ring 0 kernel
//! and the Julia Ring 3 runtime. It uses a lock-free ring buffer protocol.
//!
//! # Memory Layout
//! - Shared memory region: 0x01000000 - 0x01100000 (16MB)
//! - Ring buffer: Fixed address for direct hardware access

use bitflags::bitflags;

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
            _ => None,
        }
    }
}

/// Ring buffer for IPC
pub mod ring_buffer {
    use super::*;
    use lockfree::ring_buffer::{RingBuffer, RB};
    
    /// Maximum entries in the ring buffer
    pub const RING_BUFFER_CAPACITY: usize = 256;
    
    /// IPC Ring Buffer
    pub struct IpcRingBuffer {
        /// The underlying lock-free ring buffer
        buffer: RB<IPCEntry>,
    }
    
    impl IpcRingBuffer {
        /// Create a new IPC ring buffer
        pub fn new() -> Self {
            let buffer = RB::new(RING_BUFFER_CAPACITY);
            IpcRingBuffer { buffer }
        }
        
        /// Try to push an entry to the ring buffer
        pub fn push(&self, entry: &IPCEntry) -> bool {
            self.buffer.push(entry).is_ok()
        }
        
        /// Try to pop an entry from the ring buffer
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
    
    impl Default for IpcRingBuffer {
        fn default() -> Self {
            Self::new()
        }
    }
}

/// Shared memory region management
pub mod shm {
    use super::*;
    
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
    }
    
    impl ShmRegion {
        /// Create a new shared memory region
        pub fn new(phys_start: u64, virt_start: u64, size: u64) -> Self {
            ShmRegion {
                phys_start,
                virt_start,
                size,
                mapped: false,
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
}
