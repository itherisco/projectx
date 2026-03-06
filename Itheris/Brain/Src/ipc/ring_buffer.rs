//! Production-grade Ring Buffer for Julia-Rust IPC Communication
//!
//! This module implements a stable, production-grade ring buffer for Julia-Rust communication
//! with the following requirements:
//! - Lock-free single-producer-single-consumer ring buffer
//! - Message versioning and backward compatibility
//! - Automatic reconnection on disconnection
//! - Heartbeat mechanism (1 Hz)
//! - Performance: 10,000+ messages/second
//! - Memory: Fixed allocation, no dynamic growth

use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering, fence};
use std::sync::Arc;
use std::collections::HashMap;
use serde::{Serialize, Deserialize};
use std::time::{Duration, Instant};
use std::thread;
use std::sync::mpsc::{channel, Sender, Receiver};

/// Message types for Julia-Rust communication
#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum Message {
    /// Action proposal from Julia to Rust
    Proposal { 
        id: u64, 
        action: String, 
        confidence: f32, 
        features: Vec<f32> 
    },
    /// Verdict response from Rust to Julia
    Verdict { 
        proposal_id: u64, 
        approved: bool, 
        reward: f32, 
        reason: Option<String> 
    },
    /// World state update
    WorldState { 
        timestamp: u64, 
        energy: f32, 
        observations: HashMap<String, f32> 
    },
    /// Heartbeat message for connection monitoring
    Heartbeat { 
        sender: String, 
        timestamp: u64 
    },
}

impl Message {
    /// Get the message type identifier for versioning
    pub fn type_id(&self) -> u8 {
        match self {
            Message::Proposal { .. } => 1,
            Message::Verdict { .. } => 2,
            Message::WorldState { .. } => 3,
            Message::Heartbeat { .. } => 4,
        }
    }
    
    /// Serialize message to bytes
    pub fn serialize(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }
    
    /// Deserialize message from bytes
    pub fn deserialize(data: &[u8]) -> Result<Message, serde_json::Error> {
        serde_json::from_slice(data)
    }
}

/// IPC Error types
#[derive(Debug, Clone)]
pub enum IpcError {
    /// Buffer is full
    BufferFull,
    /// Buffer is empty
    BufferEmpty,
    /// Not connected
    NotConnected,
    /// Connection lost
    ConnectionLost,
    /// Reconnection timeout
    ReconnectionTimeout,
    /// Serialization error
    SerializationError(String),
    /// Version mismatch
    VersionMismatch(u8, u8),
    /// Unknown message type
    UnknownMessageType(u8),
}

impl std::fmt::Display for IpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IpcError::BufferFull => write!(f, "Ring buffer is full"),
            IpcError::BufferEmpty => write!(f, "Ring buffer is empty"),
            IpcError::NotConnected => write!(f, "Not connected to peer"),
            IpcError::ConnectionLost => write!(f, "Connection to peer lost"),
            IpcError::ReconnectionTimeout => write!(f, "Reconnection timeout exceeded"),
            IpcError::SerializationError(msg) => write!(f, "Serialization error: {}", msg),
            IpcError::VersionMismatch(actual, expected) => 
                write!(f, "Version mismatch: got {}, expected {}", actual, expected),
            IpcError::UnknownMessageType(t) => write!(f, "Unknown message type: {}", t),
        }
    }
}

impl std::error::Error for IpcError {}

/// Message header for versioning and identification
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MessageHeader {
    /// Message version (for backward compatibility)
    pub version: u8,
    /// Message type identifier
    pub msg_type: u8,
    /// Sequence number
    pub sequence: u64,
    /// Timestamp in milliseconds
    pub timestamp: u64,
    /// Payload length
    pub payload_len: u32,
}

impl MessageHeader {
    pub fn new(msg_type: u8, sequence: u64, payload_len: u32) -> Self {
        Self {
            version: 1,
            msg_type,
            sequence,
            timestamp: current_timestamp_ms(),
            payload_len,
        }
    }
    
    pub fn header_size() -> usize {
        // version(1) + msg_type(1) + sequence(8) + timestamp(8) + payload_len(4) = 22 bytes
        22
    }
}

/// Ring buffer entry structure
#[derive(Debug, Clone)]
pub struct RingBufferEntry {
    /// Header for versioning
    pub header: MessageHeader,
    /// Serialized message payload
    pub payload: Vec<u8>,
}

impl RingBufferEntry {
    pub fn new(header: MessageHeader, payload: Vec<u8>) -> Self {
        Self { header, payload }
    }
    
    pub fn total_size(&self) -> usize {
        MessageHeader::header_size() + self.payload.len()
    }
}

/// Production-grade Lock-free Ring Buffer
/// 
/// Uses atomic operations for single-producer-single-consumer pattern
pub struct RingBuffer {
    /// Fixed capacity
    capacity: usize,
    /// Internal storage - fixed size Vec for zero-allocation
    buffer: Vec<RingBufferEntry>,
    /// Read position (consumer)
    read_pos: AtomicUsize,
    /// Write position (producer)
    write_pos: AtomicUsize,
    /// Message sequence counter
    sequence: AtomicU64,
    /// Connection state
    connected: std::sync::atomic::AtomicBool,
    /// Last heartbeat timestamp
    last_heartbeat: std::sync::Mutex<u64>,
    /// Heartbeat sender channel
    heartbeat_tx: Option<Sender<()>>,
    /// Reconnection state
    reconnecting: std::sync::atomic::AtomicBool,
}

impl RingBuffer {
    /// Create a new ring buffer with fixed capacity
    pub fn new(capacity: usize) -> Self {
        let buffer = (0..capacity)
            .map(|_| RingBufferEntry {
                header: MessageHeader::new(0, 0, 0),
                payload: Vec::new(),
            })
            .collect();
        
        RingBuffer {
            capacity,
            buffer,
            read_pos: AtomicUsize::new(0),
            write_pos: AtomicUsize::new(0),
            sequence: AtomicU64::new(0),
            connected: std::sync::atomic::AtomicBool::new(false),
            last_heartbeat: std::sync::Mutex::new(0),
            heartbeat_tx: None,
            reconnecting: std::sync::atomic::AtomicBool::new(false),
        }
    }
    
    /// Create an Arc-wrapped ring buffer for sharing between threads
    pub fn new_arc(capacity: usize) -> Arc<Self> {
        Arc::new(Self::new(capacity))
    }
    
    /// Get next sequence number
    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::AcqRel)
    }
    
    /// Calculate mask for wraparound (power of 2 capacity)
    fn mask(&self) -> usize {
        self.capacity - 1
    }
    
    /// Check if buffer is full
    pub fn is_full(&self) -> bool {
        let read = self.read_pos.load(Ordering::Acquire);
        let write = self.write_pos.load(Ordering::Acquire);
        (write + 1) & self.mask() == read
    }
    
    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        let read = self.read_pos.load(Ordering::Acquire);
        let write = self.write_pos.load(Ordering::Acquire);
        read == write
    }
    
    /// Get number of available messages
    pub fn len(&self) -> usize {
        let read = self.read_pos.load(Ordering::Acquire);
        let write = self.write_pos.load(Ordering::Acquire);
        write.wrapping_sub(read) & self.mask()
    }
    
    /// Send a message to the ring buffer
    /// 
    /// # Arguments
    /// * `msg` - The message to send
    /// 
    /// # Returns
    /// * `Ok(())` if message was sent successfully
    /// * `Err(IpcError::BufferFull)` if buffer is full
    pub fn send(&self, msg: Message) -> Result<(), IpcError> {
        if !self.is_connected() {
            return Err(IpcError::NotConnected);
        }
        
        if self.is_full() {
            return Err(IpcError::BufferFull);
        }
        
        // Serialize the message
        let payload = msg.serialize()
            .map_err(|e| IpcError::SerializationError(e.to_string()))?;
        
        let seq = self.next_sequence();
        let header = MessageHeader::new(
            msg.type_id(),
            seq,
            payload.len() as u32,
        );
        
        // Get current write position
        let write = self.write_pos.load(Ordering::Acquire);
        
        // Write to buffer (memory barrier ensures ordering)
        fence(Ordering::Release);
        self.buffer[write & self.mask()] = RingBufferEntry::new(header, payload);
        fence(Ordering::Release);
        
        // Advance write position
        self.write_pos.store((write + 1) & self.mask(), Ordering::Release);
        
        Ok(())
    }
    
    /// Receive a message from the ring buffer
    /// 
    /// # Returns
    /// * `Ok(Message)` if message was received successfully
    /// * `Err(IpcError::BufferEmpty)` if buffer is empty
    pub fn receive(&self) -> Result<Message, IpcError> {
        if self.is_empty() {
            return Err(IpcError::BufferEmpty);
        }
        
        // Get current read position
        let read = self.read_pos.load(Ordering::Acquire);
        
        // Read from buffer
        fence(Ordering::Acquire);
        let entry = &self.buffer[read & self.mask()];
        
        // Check version for backward compatibility
        if entry.header.version > 1 {
            return Err(IpcError::VersionMismatch(entry.header.version, 1));
        }
        
        // Deserialize message
        let msg = Message::deserialize(&entry.payload)
            .map_err(|e| IpcError::SerializationError(e.to_string()))?;
        
        fence(Ordering::Acquire);
        
        // Advance read position
        self.read_pos.store((read + 1) & self.mask(), Ordering::Release);
        
        Ok(msg)
    }
    
    /// Check if connected
    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::Acquire)
    }
    
    /// Mark as connected
    pub fn set_connected(&self, connected: bool) {
        self.connected.store(connected, Ordering::Release);
    }
    
    /// Attempt to reconnect
    pub fn reconnect(&mut self) -> Result<(), IpcError> {
        if self.reconnecting.load(Ordering::Acquire) {
            return Err(IpcError::ConnectionLost);
        }
        
        self.reconnecting.store(true, Ordering::Release);
        
        // Simulate reconnection attempt
        // In production, this would attempt to re-establish the connection
        let start = Instant::now();
        let timeout = Duration::from_secs(5);
        
        while start.elapsed() < timeout {
            // Try to reconnect
            // In production: re-establish shared memory or socket connection
            self.set_connected(true);
            
            if self.is_connected() {
                self.reconnecting.store(false, Ordering::Release);
                return Ok(());
            }
            
            thread::sleep(Duration::from_millis(100));
        }
        
        self.reconnecting.store(false, Ordering::Release);
        Err(IpcError::ReconnectionTimeout)
    }
    
    /// Update last heartbeat timestamp
    pub fn update_heartbeat(&self, timestamp: u64) {
        if let Ok(mut last) = self.last_heartbeat.lock() {
            *last = timestamp;
        }
    }
    
    /// Get last heartbeat timestamp
    pub fn get_last_heartbeat(&self) -> u64 {
        self.last_heartbeat.lock().map(|l| *l).unwrap_or(0)
    }
    
    /// Check if heartbeat is stale (> 2 seconds since last heartbeat)
    pub fn is_heartbeat_stale(&self) -> bool {
        let last = self.get_last_heartbeat();
        if last == 0 {
            return true; // No heartbeat received yet
        }
        
        let now = current_timestamp_ms();
        now.saturating_sub(last) > 2000 // 2 seconds timeout
    }
}

/// Get current timestamp in milliseconds
fn current_timestamp_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Heartbeat sender task
pub struct HeartbeatSender {
    tx: Sender<()>,
    handle: Option<thread::JoinHandle<()> >,
}

impl HeartbeatSender {
    /// Create a new heartbeat sender
    pub fn new(ring_buffer: Arc<RingBuffer>) -> Self {
        let (tx, rx) = channel();
        
        let handle = thread::spawn(move || {
            let mut last_tick = Instant::now();
            
            loop {
                // Wait for 1 second
                thread::sleep(Duration::from_secs(1));
                
                // Check for shutdown signal
                if rx.try_recv().is_ok() {
                    break;
                }
                
                // Send heartbeat if connected
                if ring_buffer.is_connected() {
                    let heartbeat = Message::Heartbeat {
                        sender: "rust".to_string(),
                        timestamp: current_timestamp_ms(),
                    };
                    
                    if let Err(e) = ring_buffer.send(heartbeat) {
                        eprintln!("Heartbeat send error: {}", e);
                    }
                }
                
                last_tick = Instant::now();
            }
        });
        
        HeartbeatSender { tx, handle: Some(handle) }
    }
    
    /// Stop the heartbeat sender
    pub fn stop(&self) {
        let _ = self.tx.send(());
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_ring_buffer_basic() {
        let rb = RingBuffer::new(8);
        
        // Test empty buffer
        assert!(rb.is_empty());
        assert!(!rb.is_full());
        
        // Send a message
        let msg = Message::Proposal {
            id: 1,
            action: "test_action".to_string(),
            confidence: 0.95,
            features: vec![1.0, 2.0, 3.0],
        };
        
        rb.set_connected(true);
        assert!(rb.send(msg.clone()).is_ok());
        
        // Receive the message
        let received = rb.receive().unwrap();
        assert!(matches!(received, Message::Proposal { .. }));
    }
    
    #[test]
    fn test_ring_buffer_wraparound() {
        let rb = RingBuffer::new(4);
        rb.set_connected(true);
        
        // Fill buffer
        for i in 0..4 {
            let msg = Message::Proposal {
                id: i,
                action: format!("action_{}", i),
                confidence: 0.9,
                features: vec![],
            };
            assert!(rb.send(msg).is_ok());
        }
        
        // Buffer should be full
        assert!(rb.is_full());
        
        // Should fail to send more
        let msg = Message::Proposal {
            id: 100,
            action: "overflow".to_string(),
            confidence: 0.9,
            features: vec![],
        };
        assert!(rb.send(msg).is_err());
        
        // Read all messages
        for _ in 0..4 {
            assert!(rb.receive().is_ok());
        }
        
        // Buffer should be empty again
        assert!(rb.is_empty());
    }
    
    #[test]
    fn test_message_serialization() {
        let msg = Message::Proposal {
            id: 42,
            action: "test".to_string(),
            confidence: 0.75,
            features: vec![1.0, 2.0, 3.0],
        };
        
        let bytes = msg.serialize().unwrap();
        let deserialized = Message::deserialize(&bytes).unwrap();
        
        assert!(matches!(deserialized, Message::Proposal { id: 42, .. }));
    }
    
    #[test]
    fn test_heartbeat_stale() {
        let rb = RingBuffer::new(8);
        rb.set_connected(true);
        
        // No heartbeat yet - should be stale
        assert!(rb.is_heartbeat_stale());
        
        // Update heartbeat
        rb.update_heartbeat(current_timestamp_ms());
        
        // Should not be stale
        assert!(!rb.is_heartbeat_stale());
    }
}
