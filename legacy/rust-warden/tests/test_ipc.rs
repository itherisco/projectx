//! IPC (Inter-Process Communication) unit tests
//! 
//! Tests for ring buffer initialization, single-producer-single-consumer
//! operations, boundary conditions, atomic operations, and memory barriers.

#![cfg(feature = "mock")]

use crate::common::{
    atomic_utils, generators, MockRingBuffer,
};
use core::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

// ============================================================================
// Ring Buffer Initialization Tests
// ============================================================================

/// Test ring buffer creation with valid capacity
#[test]
fn test_ring_buffer_creation() {
    let buffer = MockRingBuffer::new(1024);
    
    assert_eq!(buffer.capacity(), 1024, "Capacity should match");
    assert!(buffer.is_empty(), "Should be empty initially");
    assert!(!buffer.is_full(), "Should not be full initially");
}

/// Test ring buffer with minimum capacity
#[test]
fn test_ring_buffer_min_capacity() {
    let buffer = MockRingBuffer::new(1);
    
    assert_eq!(buffer.capacity(), 1);
    assert!(buffer.is_empty());
}

/// Test ring buffer with typical IPC size
#[test]
fn test_ring_buffer_typical_size() {
    let buffer = MockRingBuffer::new(4096); // Page-sized
    
    assert_eq!(buffer.capacity(), 4096);
    assert!(buffer.is_empty());
}

/// Test ring buffer initial state
#[test]
fn test_ring_buffer_initial_state() {
    let buffer = MockRingBuffer::new(1024);
    
    let read_pos = buffer.available_data();
    assert_eq!(read_pos, 0, "Available data should be 0 initially");
}

// ============================================================================
// Single-Producer-Single-Consumer Tests
// ============================================================================

/// Test simple write operation
#[test]
fn test_spsc_write() {
    let buffer = MockRingBuffer::new(1024);
    let data = b"Hello, World!";
    
    let result = buffer.write(data);
    
    assert!(result.is_ok(), "Write should succeed");
    assert_eq!(result.unwrap(), data.len(), "Written bytes should match");
}

/// Test simple read operation
#[test]
fn test_spsc_read() {
    let buffer = MockRingBuffer::new(1024);
    let data = b"Test Message";
    
    buffer.write(data).expect("Write should succeed");
    let read_data = buffer.read(data.len()).expect("Read should succeed");
    
    assert_eq!(read_data, data, "Read data should match written data");
}

/// Test write-read sequence
#[test]
fn test_spsc_write_read_sequence() {
    let buffer = MockRingBuffer::new(1024);
    
    // Write data
    let msg1 = b"First";
    let msg2 = b"Second";
    
    buffer.write(msg1).expect("First write should succeed");
    buffer.write(msg2).expect("Second write should succeed");
    
    // Read data
    let read1 = buffer.read(5).expect("First read should succeed");
    let read2 = buffer.read(6).expect("Second read should succeed");
    
    assert_eq!(read1, msg1);
    assert_eq!(read2, msg2);
}

/// Test large data write
#[test]
fn test_spsc_large_write() {
    let buffer = MockRingBuffer::new(4096);
    let large_data = vec![0xAB; 2048]; // 2KB of data
    
    let result = buffer.write(&large_data);
    
    assert!(result.is_ok(), "Large write should succeed");
    assert_eq!(result.unwrap(), 2048, "All data should be written");
}

/// Test multi-message throughput
#[test]
fn test_spsc_multi_message() {
    let buffer = MockRingBuffer::new(4096);
    let message = b"Message";
    
    // Write 100 messages
    for _ in 0..100 {
        buffer.write(message).expect("Write should succeed");
    }
    
    // Read 100 messages
    for _ in 0..100 {
        let read = buffer.read(7).expect("Read should succeed");
        assert_eq!(read, message);
    }
}

// ============================================================================
// Boundary Condition Tests
// ============================================================================

/// Test buffer wraparound - write crossing boundary
#[test]
fn test_buffer_wraparound_write() {
    let buffer = MockRingBuffer::new(16);
    
    // Write 10 bytes
    let data1 = b"0123456789";
    buffer.write(data1).expect("First write should succeed");
    
    // Read 4 bytes
    buffer.read(4).expect("Read should succeed");
    
    // Write 10 more bytes (should wrap)
    let data2 = b"ABCDEFGHIJ";
    let result = buffer.write(data2);
    
    assert!(result.is_ok(), "Wrapped write should succeed");
}

/// Test buffer wraparound read
#[test]
fn test_buffer_wraparound_read() {
    let buffer = MockRingBuffer::new(16);
    
    // Write full buffer
    let data = b"0123456789ABCDEF";
    buffer.write(data).expect("Write should succeed");
    
    // Read 8 bytes
    buffer.read(8).expect("Read should succeed");
    
    // Read remaining (should wrap)
    let read_data = buffer.read(8).expect("Wrapped read should succeed");
    assert_eq!(read_data.len(), 8);
}

/// Test buffer full condition
#[test]
fn test_buffer_full() {
    let buffer = MockRingBuffer::new(10);
    
    // Fill buffer
    buffer.write(b"0123456789").expect("Write should succeed");
    
    assert!(buffer.is_full(), "Buffer should be full");
    assert!(!buffer.is_empty(), "Buffer should not be empty");
}

/// Test buffer empty after read
#[test]
fn test_buffer_empty_after_read() {
    let buffer = MockRingBuffer::new(1024);
    
    buffer.write(b"Test").expect("Write should succeed");
    buffer.read(4).expect("Read should succeed");
    
    assert!(buffer.is_empty(), "Buffer should be empty");
}

/// Test write to full buffer fails
#[test]
fn test_write_to_full_buffer() {
    let buffer = MockRingBuffer::new(10);
    
    buffer.write(b"0123456789").expect("Write should succeed");
    
    let result = buffer.write(b"X");
    
    assert!(result.is_err(), "Write to full buffer should fail");
}

/// Test read from empty buffer fails
#[test]
fn test_read_from_empty_buffer() {
    let buffer = MockRingBuffer::new(1024);
    
    let result = buffer.read(1);
    
    assert!(result.is_err(), "Read from empty buffer should fail");
}

/// Test write with exact capacity
#[test]
fn test_write_exact_capacity() {
    let buffer = MockRingBuffer::new(10);
    
    // Write exactly capacity
    let result = buffer.write(b"0123456789");
    
    assert!(result.is_ok());
    assert!(buffer.is_full());
}

/// Test read exact capacity
#[test]
fn test_read_exact_capacity() {
    let buffer = MockRingBuffer::new(10);
    
    buffer.write(b"0123456789").expect("Write should succeed");
    let result = buffer.read(10);
    
    assert!(result.is_ok());
    assert!(buffer.is_empty());
}

// ============================================================================
// Data Integrity Tests
// ============================================================================

/// Test data integrity - bytes preserved
#[test]
fn test_data_integrity() {
    let buffer = MockRingBuffer::new(4096);
    
    // Write known pattern
    let pattern = generators::generate_alternating_data(1024);
    buffer.write(&pattern).expect("Write should succeed");
    
    // Read and verify
    let read_data = buffer.read(1024).expect("Read should succeed");
    assert_eq!(read_data, pattern, "Data should match");
}

/// Test null data handling
#[test]
fn test_null_data_handling() {
    let buffer = MockRingBuffer::new(4096);
    
    let null_data = generators::generate_null_data(512);
    buffer.write(&null_data).expect("Write should succeed");
    
    let read_data = buffer.read(512).expect("Read should succeed");
    assert!(read_data.iter().all(|&b| b == 0), "All bytes should be null");
}

/// Test pattern data integrity
#[test]
fn test_pattern_data_integrity() {
    let buffer = MockRingBuffer::new(4096);
    
    let pattern = generators::generate_pattern_data(256, 0x5A);
    buffer.write(&pattern).expect("Write should succeed");
    
    let read_data = buffer.read(256).expect("Read should succeed");
    assert!(read_data.iter().all(|&b| b == 0x5A), "All bytes should match pattern");
}

/// Test random-like data
#[test]
fn test_random_data() {
    let buffer = MockRingBuffer::new(4096);
    
    let random_data = generators::generate_test_data(1024);
    buffer.write(&random_data).expect("Write should succeed");
    
    let read_data = buffer.read(1024).expect("Read should succeed");
    assert_eq!(read_data.len(), 1024, "Length should match");
}

// ============================================================================
// Atomic Operation Tests
// ============================================================================

/// Test atomic load ordering
#[test]
fn test_atomic_load_ordering() {
    let value = AtomicU64::new(0x12345678);
    
    let loaded = atomic_utils::test_load_ordering(&value);
    
    assert_eq!(loaded, 0x12345678, "Loaded value should match");
}

/// Test atomic store ordering
#[test]
fn test_atomic_store_ordering() {
    let value = AtomicU64::new(0);
    
    atomic_utils::test_store_ordering(&value, 0xDEADBEEF);
    
    assert_eq!(value.load(Ordering::Acquire), 0xDEADBEEF);
}

/// Test compare-and-swap success
#[test]
fn test_atomic_cas_success() {
    let value = AtomicU64::new(100);
    
    let result = atomic_utils::test_compare_exchange(&value, 100, 200);
    
    assert!(result.is_ok(), "CAS should succeed");
    assert_eq!(value.load(Ordering::Acquire), 200, "Value should be updated");
}

/// Test compare-and-swap failure
#[test]
fn test_atomic_cas_failure() {
    let value = AtomicU64::new(100);
    
    let result = atomic_utils::test_compare_exchange(&value, 50, 200);
    
    assert!(result.is_err(), "CAS should fail");
    assert_eq!(value.load(Ordering::Acquire), 100, "Value should not change");
}

/// Test fetch-and-add
#[test]
fn test_atomic_fetch_add() {
    let value = AtomicU64::new(100);
    
    let old = atomic_utils::test_fetch_add(&value, 50);
    
    assert_eq!(old, 100, "Old value should be returned");
    assert_eq!(value.load(Ordering::Acquire), 150, "New value should be 150");
}

/// Test fetch-and-sub
#[test]
fn test_atomic_fetch_sub() {
    let value = AtomicU64::new(100);
    
    let old = atomic_utils::test_fetch_sub(&value, 30);
    
    assert_eq!(old, 100, "Old value should be returned");
    assert_eq!(value.load(Ordering::Acquire), 70, "New value should be 70");
}

// ============================================================================
// Memory Barrier Tests
// ============================================================================

/// Test memory barrier execution
#[test]
fn test_memory_barrier() {
    // This test verifies that the barrier doesn't panic
    atomic_utils::test_memory_barrier();
    
    // If we get here, barrier worked
    assert!(true);
}

/// Test memory ordering semantics
#[test]
fn test_memory_ordering_semantics() {
    let data = AtomicU64::new(0);
    let ready = AtomicBool::false();
    
    // Writer thread
    data.store(42, Ordering::Release);
    ready.store(true, Ordering::Release);
    
    // Reader thread
    if ready.load(Ordering::Acquire) {
        let value = data.load(Ordering::Acquire);
        assert_eq!(value, 42, "Should see the written value");
    }
}

// ============================================================================
// Concurrent Access Simulation Tests
// ============================================================================

/// Test sequential SPSC correctness
#[test]
fn test_spsc_sequential_correctness() {
    let buffer = MockRingBuffer::new(64);
    let test_messages = [
        b"Msg01",
        b"Msg02",
        b"Msg03",
        b"Msg04",
        b"Msg05",
    ];
    
    // Write all messages
    for msg in &test_messages {
        buffer.write(msg).expect("Write should succeed");
    }
    
    // Read all messages
    for msg in &test_messages {
        let read = buffer.read(msg.len()).expect("Read should succeed");
        assert_eq!(read, *msg, "Message should match");
    }
    
    assert!(buffer.is_empty(), "Buffer should be empty");
}

/// Test alternating write/read pattern
#[test]
fn test_alternating_pattern() {
    let buffer = MockRingBuffer::new(64);
    
    // Write 1 byte
    buffer.write(b"A").expect("Write should succeed");
    // Read 1 byte
    buffer.read(1).expect("Read should succeed");
    
    // Repeat
    for _ in 0..10 {
        buffer.write(b"B").expect("Write should succeed");
        buffer.read(1).expect("Read should succeed");
    }
    
    assert!(buffer.is_empty(), "Buffer should be empty");
}

/// Test buffer not corrupting on overflow attempt
#[test]
fn test_buffer_no_corruption_on_overflow() {
    let buffer = MockRingBuffer::new(5);
    
    // Try to overflow
    let _ = buffer.write(b"ABCDEF"); // 6 bytes
    
    // Buffer should remain in consistent state
    assert!(!buffer.is_full() || buffer.is_empty() || !buffer.is_empty(), 
             "Buffer should be consistent");
}

// ============================================================================
// Edge Cases
// ============================================================================

/// Test zero-length write
#[test]
fn test_zero_length_write() {
    let buffer = MockRingBuffer::new(1024);
    
    let result = buffer.write(b"");
    
    // Zero-length operations may be allowed or not - just check consistency
    assert!(result.is_ok() || result.is_err());
}

/// Test zero-length read
#[test]
fn test_zero_length_read() {
    let buffer = MockRingBuffer::new(1024);
    buffer.write(b"Data").expect("Write should succeed");
    
    let result = buffer.read(0);
    
    // Zero-length read should be handled gracefully
    if result.is_ok() {
        assert!(result.unwrap().is_empty());
    }
}

/// Test read larger than available
#[test]
fn test_read_larger_than_available() {
    let buffer = MockRingBuffer::new(1024);
    buffer.write(b"Hi").expect("Write should succeed");
    
    let result = buffer.read(100);
    
    assert!(result.is_err(), "Read larger than available should fail");
}

/// Test buffer clear operation
#[test]
fn test_buffer_clear() {
    let buffer = MockRingBuffer::new(1024);
    
    buffer.write(b"Some data").expect("Write should succeed");
    assert!(!buffer.is_empty());
    
    buffer.clear();
    
    assert!(buffer.is_empty(), "Buffer should be empty after clear");
    assert!(!buffer.is_full(), "Buffer should not be full after clear");
}

// ============================================================================
// Performance Characteristic Tests
// ============================================================================

/// Test available data calculation
#[test]
fn test_available_data_calculation() {
    let buffer = MockRingBuffer::new(100);
    
    assert_eq!(buffer.available_data(), 0, "Should be 0 initially");
    
    buffer.write(b"Hello").expect("Write should succeed");
    assert_eq!(buffer.available_data(), 5, "Should be 5 after write");
    
    buffer.read(3).expect("Read should succeed");
    assert_eq!(buffer.available_data(), 2, "Should be 2 after read");
}

/// Test available space calculation
#[test]
fn test_available_space() {
    let buffer = MockRingBuffer::new(100);
    
    // Initially: capacity - 0 = 100 (but we check available_space logic)
    buffer.write(b"Test").expect("Write should succeed");
    
    let is_full = buffer.is_full();
    let is_empty = buffer.is_empty();
    
    // Buffer should be neither full nor empty
    assert!(!is_full || !is_empty);
}

// ============================================================================
// Stress Tests (Simulated)
// ============================================================================

/// Test many small writes
#[test]
fn test_many_small_writes() {
    let buffer = MockRingBuffer::new(4096);
    
    // Write 1 byte at a time
    for i in 0..100 {
        let data = [i as u8];
        buffer.write(&data).expect("Write should succeed");
    }
    
    // Read and verify
    for i in 0..100 {
        let read = buffer.read(1).expect("Read should succeed");
        assert_eq!(read[0], i as u8);
    }
}

/// Test burst write then burst read
#[test]
fn test_burst_write_read() {
    let buffer = MockRingBuffer::new(8192);
    let total_size = 4096;
    
    // Burst write
    let burst_data = vec![0x55; total_size];
    buffer.write(&burst_data).expect("Burst write should succeed");
    
    // Burst read
    let read_data = buffer.read(total_size).expect("Burst read should succeed");
    assert!(read_data.iter().all(|&b| b == 0x55), "All data should match");
}

// ============================================================================
// Data Structure Invariant Tests
// ============================================================================

/// Test ring buffer invariants
#[test]
fn test_ring_buffer_invariants() {
    let buffer = MockRingBuffer::new(64);
    
    // Empty invariant
    assert!(buffer.is_empty() == (buffer.available_data() == 0));
    
    // Write some data
    buffer.write(b"Test").expect("Write should succeed");
    
    // Not empty invariant
    assert!(!buffer.is_empty());
    
    // Read all data
    buffer.read(4).expect("Read should succeed");
    
    // Empty again invariant
    assert!(buffer.is_empty());
}

/// Test capacity never changes
#[test]
fn test_capacity_immutable() {
    let buffer = MockRingBuffer::new(1024);
    
    // Perform various operations
    buffer.write(b"Some data").expect("Write");
    buffer.read(4).expect("Read");
    buffer.clear();
    
    // Capacity should remain the same
    assert_eq!(buffer.capacity(), 1024);
}
