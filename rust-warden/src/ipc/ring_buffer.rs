//! IPC Ring Buffer Implementation
//!
//! This module provides a lock-free Single-Producer-Single-Consumer (SPSC)
//! ring buffer for communication between the hypervisor and Julia guest.

use core::sync::atomic::{AtomicU64, Ordering};
use core::mem::MaybeUninit;

/// IPC buffer constants
pub mod ipc_consts {
    /// IPC buffer base address
    pub const IPC_BUFFER_BASE: u64 = 0x0100_0000;
    
    /// IPC buffer size (64MB)
    pub const IPC_BUFFER_SIZE: u64 = 0x0400_0000;
    
    /// Control region size
    pub const CONTROL_REGION_SIZE: u64 = 0x1000;
    
    /// Producer info offset
    pub const PRODUCER_INFO_OFFSET: u64 = 0x1000;
    
    /// Consumer info offset
    pub const CONSUMER_INFO_OFFSET: u64 = 0x2000;
    
    /// Message data area offset
    pub const MESSAGE_AREA_OFFSET: u64 = 0x10000;
    
    /// Message magic ("JECP")
    pub const MESSAGE_MAGIC: u32 = 0x4945_4350;
    
    /// Max payload size
    pub const MAX_PAYLOAD_SIZE: usize = 16384;
    
    /// Message header size
    pub const MESSAGE_HEADER_SIZE: usize = 48;
}

/// IPC message types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IpcMessageType {
    /// Heartbeat message
    Heartbeat = 0x0001,
    /// State query
    StateQuery = 0x0002,
    /// Memory request
    MemoryRequest = 0x0003,
    /// Control message
    Control = 0x0004,
    /// Cognitive request
    CognitiveRequest = 0x0010,
    /// Cognitive response
    CognitiveResponse = 0x0011,
    /// World model update
    WorldModelUpdate = 0x0020,
    /// Memory operation
    MemoryOperation = 0x0030,
    /// Unknown
    Unknown = 0xFFFF,
}

impl From<u16> for IpcMessageType {
    fn from(val: u16) -> Self {
        match val {
            0x0001 => IpcMessageType::Heartbeat,
            0x0002 => IpcMessageType::StateQuery,
            0x0003 => IpcMessageType::MemoryRequest,
            0x0004 => IpcMessageType::Control,
            0x0010 => IpcMessageType::CognitiveRequest,
            0x0011 => IpcMessageType::CognitiveResponse,
            0x0020 => IpcMessageType::WorldModelUpdate,
            0x0030 => IpcMessageType::MemoryOperation,
            _ => IpcMessageType::Unknown,
        }
    }
}

/// IPC message header
#[repr(C)]
#[derive(Clone, Copy)]
pub struct IpcMessageHeader {
    /// Magic number (0x49454350)
    pub magic: u32,
    /// Protocol version
    pub version: u16,
    /// Flags
    pub flags: u16,
    /// Sequence number
    pub sequence: u64,
    /// Timestamp (nanoseconds)
    pub timestamp_ns: u64,
    /// Message type
    pub msg_type: u16,
    /// Payload size
    pub payload_size: u16,
    /// Checksum
    pub checksum: u32,
}

impl IpcMessageHeader {
    /// Create new header
    pub fn new(msg_type: IpcMessageType, payload_size: u16, sequence: u64) -> Self {
        Self {
            magic: ipc_consts::MESSAGE_MAGIC,
            version: 1,
            flags: 0,
            sequence,
            timestamp_ns: 0, // Would be set by sender
            msg_type: msg_type as u16,
            payload_size,
            checksum: 0,
        }
    }

    /// Validate header
    pub fn is_valid(&self) -> bool {
        self.magic == ipc_consts::MESSAGE_MAGIC
    }
}

/// IPC message
#[derive(Clone)]
pub struct IpcMessage {
    /// Message header
    pub header: IpcMessageHeader,
    /// Message payload
    pub payload: Vec<u8>,
}

impl IpcMessage {
    /// Create new message
    pub fn new(msg_type: IpcMessageType, payload: Vec<u8>) -> Self {
        Self {
            header: IpcMessageHeader::new(
                msg_type, 
                payload.len() as u16, 
                0,
            ),
            payload,
        }
    }

    /// Get total size
    pub fn total_size(&self) -> usize {
        ipc_consts::MESSAGE_HEADER_SIZE + self.payload.len()
    }
}

/// Control region in IPC buffer
#[repr(C)]
pub struct IpcControlRegion {
    /// Magic
    pub magic: u32,
    /// Version
    pub version: u16,
    /// Flags
    pub flags: u16,
    /// Warden state
    pub warden_state: u32,
    /// Guest state
    pub guest_state: u32,
    /// Message count
    pub message_count: u64,
    /// Error count
    pub error_count: u64,
    /// Sequence counter
    pub sequence_counter: u64,
    /// Reserved
    _reserved: [u8; 4032],
}

impl IpcControlRegion {
    /// Create new control region
    pub fn new() -> Self {
        Self {
            magic: ipc_consts::MESSAGE_MAGIC,
            version: 1,
            flags: 0,
            warden_state: 0,
            guest_state: 0,
            message_count: 0,
            error_count: 0,
            sequence_counter: 0,
            _reserved: [0; 4032],
        }
    }
}

impl Default for IpcControlRegion {
    fn default() -> Self {
        Self::new()
    }
}

/// Producer/Consumer info
#[repr(C)]
pub struct IpcQueueInfo {
    /// Write position
    pub write_pos: AtomicU64,
    /// Read position
    pub read_pos: AtomicU64,
    /// High watermark
    pub watermark_high: u64,
    /// Low watermark
    pub watermark_low: u64,
    /// Reserved
    _reserved: [u8; 4088],
}

impl IpcQueueInfo {
    /// Create new queue info
    pub fn new() -> Self {
        Self {
            write_pos: AtomicU64::new(0),
            read_pos: AtomicU64::new(0),
            watermark_high: 0,
            watermark_low: 0,
            _reserved: [0; 4088],
        }
    }
}

impl Default for IpcQueueInfo {
    fn default() -> Self {
        Self::new()
    }
}

/// IPC Errors
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IpcError {
    /// Buffer full
    BufferFull,
    /// Buffer empty
    BufferEmpty,
    /// Invalid message
    InvalidMessage,
    /// Out of memory
    OutOfMemory,
    /// Not initialized
    NotInitialized,
}

/// IPC Ring Buffer - Lock-free SPSC implementation
pub struct RingBuffer {
    /// Base address
    base: u64,
    /// Capacity (power of 2)
    capacity: usize,
    /// Mask for wraparound
    mask: usize,
    /// Write position
    write_pos: &'static AtomicU64,
    /// Read position
    read_pos: &'static AtomicU64,
    /// Control region
    control: &'static mut IpcControlRegion,
    /// Message area start
    message_area: u64,
    /// Sequence counter
    sequence: AtomicU64,
}

impl RingBuffer {
    /// Create new ring buffer at specified address
    pub fn new(phys_addr: u64, size: usize) -> Result<&'static mut Self, IpcError> {
        // Round up to power of 2
        let capacity = size.next_power_of_two();
        let mask = capacity - 1;

        if capacity < 4096 {
            return Err(IpcError::OutOfMemory);
        }

        // Create control region
        let control = Box::leak(Box::new(IpcControlRegion::new()));
        
        // Create queue info
        let queue_info = Box::leak(Box::new(IpcQueueInfo::new()));
        
        // For now, use a static buffer
        // In reality, this would be mapped to physical memory
        let write_pos = Box::leak(Box::new(AtomicU64::new(0)));
        let read_pos = Box::leak(Box::new(AtomicU64::new(0)));

        let ring = Box::leak(Box::new(Self {
            base: phys_addr,
            capacity,
            mask,
            write_pos,
            read_pos,
            control,
            message_area: phys_addr + ipc_consts::MESSAGE_AREA_OFFSET,
            sequence: AtomicU64::new(0),
        }));

        println!("[IPC] Ring buffer created at 0x{:x}, capacity: {} bytes", 
            phys_addr, capacity);

        Ok(ring)
    }

    /// Try to write a message
    pub fn try_write(&self, msg: &IpcMessage) -> Result<(), IpcError> {
        let total_size = msg.total_size();
        
        // Get current positions
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Acquire);
        
        // Calculate available space
        let available = if write >= read {
            self.capacity - (write - read) as usize
        } else {
            (read - write) as usize
        };
        
        // Check if we have enough space
        if available < total_size {
            return Err(IpcError::BufferFull);
        }
        
        // Calculate offset in buffer
        let offset = (write as usize) & self.mask;
        
        // Check for wraparound
        let wrap_needed = offset + total_size > self.capacity;
        
        if wrap_needed {
            // Message would wrap - for simplicity, fail
            // In real implementation, would handle split writes
            return Err(IpcError::BufferFull);
        }
        
        // Get message sequence
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);
        
        // Create header
        let mut header = msg.header;
        header.sequence = seq;
        header.timestamp_ns = self.get_timestamp_ns();
        
        // Write header
        let header_ptr = (self.message_area + offset as u64) as *mut IpcMessageHeader;
        unsafe {
            *header_ptr = header;
        }
        
        // Write payload
        if !msg.payload.is_empty() {
            let payload_ptr = (self.message_area + offset as u64 + ipc_consts::MESSAGE_HEADER_SIZE as u64) 
                as *mut u8;
            unsafe {
                core::ptr::copy_nonoverlapping(
                    msg.payload.as_ptr(),
                    payload_ptr,
                    msg.payload.len(),
                );
            }
        }
        
        // Memory barrier before publishing
        core::sync::atomic::fence(Ordering::Release);
        
        // Update write position
        self.write_pos.store(write + total_size as u64, Ordering::Release);
        
        // Update control region
        self.control.message_count += 1;
        
        Ok(())
    }

    /// Try to read a message
    pub fn try_read(&self) -> Option<IpcMessage> {
        // Get current positions
        let read = self.read_pos.load(Ordering::Acquire);
        let write = self.write_pos.load(Ordering::Acquire);
        
        // Check if buffer is empty
        if write == read {
            return None;
        }
        
        let offset = (read as usize) & self.mask;
        
        // Read header
        let header_ptr = (self.message_area + offset as u64) as *const IpcMessageHeader;
        let header = unsafe { *header_ptr };
        
        // Validate header
        if !header.is_valid() {
            self.control.error_count += 1;
            return None;
        }
        
        // Read payload
        let payload_size = header.payload_size as usize;
        let mut payload = Vec::with_capacity(payload_size);
        
        if payload_size > 0 {
            let payload_ptr = (self.message_area + offset as u64 + ipc_consts::MESSAGE_HEADER_SIZE as u64) 
                as *const u8;
            unsafe {
                payload.set_len(payload_size);
                core::ptr::copy_nonoverlapping(
                    payload_ptr,
                    payload.as_mut_ptr(),
                    payload_size,
                );
            }
        }
        
        let total_size = ipc_consts::MESSAGE_HEADER_SIZE + payload_size;
        
        // Memory barrier before advancing
        core::sync::atomic::fence(Ordering::Release);
        
        // Advance read position
        self.read_pos.store(read + total_size as u64, Ordering::Release);
        
        Some(IpcMessage { header, payload })
    }

    /// Get available space
    pub fn available_space(&self) -> usize {
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Acquire);
        
        if write >= read {
            self.capacity - (write - read) as usize
        } else {
            (read - write) as usize
        }
    }

    /// Get used space
    pub fn used_space(&self) -> usize {
        let write = self.write_pos.load(Ordering::Acquire);
        let read = self.read_pos.load(Ordering::Acquire);
        
        if write >= read {
            (write - read) as usize
        } else {
            self.capacity - (read - write) as usize
        }
    }

    /// Get message count
    pub fn message_count(&self) -> u64 {
        self.control.message_count
    }

    /// Get timestamp in nanoseconds
    fn get_timestamp_ns(&self) -> u64 {
        // Simplified - would use proper timing in real implementation
        0
    }
}

/// Warden to Julia IPC handle
pub struct WardenIpc {
    /// Ring buffer reference
    ring: &'static RingBuffer,
}

impl WardenIpc {
    /// Create new Warden IPC handle
    pub fn new(ring: &'static RingBuffer) -> Self {
        Self { ring }
    }

    /// Send heartbeat to Julia
    pub fn send_heartbeat(&self) -> Result<(), IpcError> {
        let msg = IpcMessage::new(IpcMessageType::Heartbeat, Vec::new());
        self.ring.try_write(&msg)
    }

    /// Send state query to Julia
    pub fn send_state_query(&self) -> Result<(), IpcError> {
        let msg = IpcMessage::new(IpcMessageType::StateQuery, Vec::new());
        self.ring.try_write(&msg)
    }

    /// Send cognitive request
    pub fn send_cognitive_request(&self, data: Vec<u8>) -> Result<(), IpcError> {
        let msg = IpcMessage::new(IpcMessageType::CognitiveRequest, data);
        self.ring.try_write(&msg)
    }

    /// Receive message from Julia
    pub fn receive(&self) -> Option<IpcMessage> {
        self.ring.try_read()
    }

    /// Get IPC statistics
    pub fn stats(&self) -> IpcStats {
        IpcStats {
            capacity: self.ring.capacity,
            used: self.ring.used_space(),
            available: self.ring.available_space(),
            messages: self.ring.message_count(),
        }
    }
}

/// IPC statistics
#[derive(Debug, Clone, Copy)]
pub struct IpcStats {
    /// Total capacity
    pub capacity: usize,
    /// Used space
    pub used: usize,
    /// Available space
    pub available: usize,
    /// Message count
    pub messages: u64,
}

impl IpcStats {
    /// Usage percentage
    pub fn usage_percent(&self) -> f64 {
        (self.used as f64 / self.capacity as f64) * 100.0
    }
}
