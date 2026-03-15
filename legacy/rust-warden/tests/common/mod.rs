//! Common mock structures for Rust Warden testing
//! 
//! This module provides mock implementations for hardware-specific operations
//! that cannot be executed in a hosted testing environment.

use core::cell::UnsafeCell;
use core::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

/// Mock VMX capability flags
#[derive(Debug, Clone, Copy, Default)]
pub struct MockVmxCapabilities {
    pub vmxon_supported: bool,
    pub vmxoff_supported: bool,
    pub vmptrld_supported: bool,
    pub vmptrst_supported: bool,
    pub vmclear_supported: bool,
    pub vmwrite_supported: bool,
    pub vmread_supported: bool,
    pub vmlaunch_supported: bool,
    pub vmresume_supported: bool,
    pub vmexit_supported: bool,
    pub secondary_controls: bool,
    pub true_controls: bool,
}

impl MockVmxCapabilities {
    pub fn new() -> Self {
        Self {
            vmxon_supported: true,
            vmxoff_supported: true,
            vmptrld_supported: true,
            vmptrst_supported: true,
            vmclear_supported: true,
            vmwrite_supported: true,
            vmread_supported: true,
            vmlaunch_supported: true,
            vmresume_supported: true,
            vmexit_supported: true,
            secondary_controls: true,
            true_controls: true,
        }
    }
}

/// Mock SVM capability flags
#[derive(Debug, Clone, Copy, Default)]
pub struct MockSvmCapabilities {
    pub svm_supported: bool,
    pub npfits_supported: bool,
    pub sev_supported: bool,
    pub sev_es_supported: bool,
    pub vmrun_supported: bool,
    pub vmmcall_supported: bool,
    pub invlpga_supported: bool,
    pub skinit_supported: bool,
}

impl MockSvmCapabilities {
    pub fn new() -> Self {
        Self {
            svm_supported: true,
            npfits_supported: true,
            sev_supported: true,
            sev_es_supported: true,
            vmrun_supported: true,
            vmmcall_supported: true,
            invlpga_supported: true,
            skinit_supported: true,
        }
    }
}

/// Mock VMCS (Virtual Machine Control Structure) data
#[derive(Debug, Clone, Default)]
pub struct MockVmcs {
    pub revision_id: u32,
    pub abort_indicator: u32,
    pub data: [u8; 4096],
}

impl MockVmcs {
    pub fn new() -> Self {
        Self {
            revision_id: 0xFFFFFFFF, // VMCS revision ID
            abort_indicator: 0,
            data: [0u8; 4096],
        }
    }

    pub fn set_field(&mut self, offset: usize, value: u64) -> Result<(), &'static str> {
        if offset + 8 > self.data.len() {
            return Err("Offset out of bounds");
        }
        self.data[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        Ok(())
    }

    pub fn get_field(&self, offset: usize) -> Result<u64, &'static str> {
        if offset + 8 > self.data.len() {
            return Err("Offset out of bounds");
        }
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&self.data[offset..offset + 8]);
        Ok(u64::from_le_bytes(bytes))
    }
}

/// Mock VMXON region
#[derive(Debug, Clone, Default)]
pub struct MockVmxonRegion {
    pub revision_id: u32,
    pub data: [u8; 4096],
}

impl MockVmxonRegion {
    pub fn new() -> Self {
        Self {
            revision_id: 0xFFFFFFFF,
            data: [0u8; 4096],
        }
    }
}

/// Mock TPM response
#[derive(Debug, Clone, Default)]
pub struct MockTpmResponse {
    pub header: [u8; 10],
    pub payload: Vec<u8>,
    pub size: usize,
}

impl MockTpmResponse {
    pub fn new() -> Self {
        Self {
            header: [0; 10],
            payload: Vec::new(),
            size: 0,
        }
    }

    pub fn success() -> Self {
        let mut resp = Self::new();
        // TPM_ST_SUCCESS = 0x00
        resp.header[0] = 0x00;
        // Response size (will be set later)
        resp.header[2] = 0x00;
        resp.header[3] = 0x00;
        resp
    }

    pub fn with_payload(mut self, payload: &[u8]) -> Self {
        self.payload = payload.to_vec();
        self.size = 10 + payload.len();
        // Set size in header (big-endian)
        self.header[2] = ((self.size >> 8) & 0xFF) as u8;
        self.header[3] = (self.size & 0xFF) as u8;
        self
    }
}

/// Mock PCR (Platform Configuration Register) value
#[derive(Debug, Clone, Default)]
pub struct MockPcrValue {
    pub index: u8,
    pub value: [u8; 32],
    pub bank: u8,
}

impl MockPcrValue {
    pub fn new(index: u8) -> Self {
        Self {
            index,
            value: [0u8; 32],
            bank: 0,
        }
    }

    pub fn with_value(mut self, value: [u8; 32]) -> Self {
        self.value = value;
        self
    }
}

/// Mock memory region for testing
#[derive(Debug, Clone)]
pub struct MockMemoryRegion {
    pub base_address: u64,
    pub size: u64,
    pub is_allocated: bool,
    pub permissions: MemoryPermissions,
    pub region_type: MemoryRegionType,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct MemoryPermissions {
    pub readable: bool,
    pub writable: bool,
    pub executable: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryRegionType {
    Ram,
    Mmio,
    Reserved,
    Unavailable,
}

impl Default for MemoryRegionType {
    fn default() -> Self {
        Self::Ram
    }
}

impl MockMemoryRegion {
    pub fn new(base: u64, size: u64) -> Self {
        Self {
            base_address: base,
            size,
            is_allocated: false,
            permissions: MemoryPermissions::default(),
            region_type: MemoryRegionType::default(),
        }
    }

    pub fn with_permissions(mut self, perms: MemoryPermissions) -> Self {
        self.permissions = perms;
        self
    }

    pub fn with_type(mut self, region_type: MemoryRegionType) -> Self {
        self.region_type = region_type;
        self
    }

    pub fn contains(&self, addr: u64) -> bool {
        addr >= self.base_address && addr < self.base_address + self.size
    }

    pub fn overlaps(&self, other: &MockMemoryRegion) -> bool {
        !(self.base_address + self.size <= other.base_address ||
          other.base_address + other.size <= self.base_address)
    }
}

/// Mock EPT (Extended Page Table) entry
#[derive(Debug, Clone, Default)]
pub struct MockEptEntry {
    pub read_access: bool,
    pub write_access: bool,
    pub execute_access: bool,
    pub memory_type: EptMemoryType,
    pub level: EptLevel,
    pub physical_address: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EptMemoryType {
    #[default]
    Uncacheable,
    WriteCombining,
    WriteThrough,
    WriteProtected,
    WriteBack,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EptLevel {
    #[default]
    Pml4,
    Pdpt,
    Pd,
    Pt,
}

impl MockEptEntry {
    pub fn new(level: EptLevel) -> Self {
        Self {
            read_access: true,
            write_access: true,
            execute_access: true,
            memory_type: EptMemoryType::WriteBack,
            level,
            physical_address: 0,
        }
    }

    pub fn to_bits(&self) -> u64 {
        let mut bits: u64 = 0;
        if self.read_access { bits |= 1; }
        if self.write_access { bits |= 2; }
        if self.execute_access { bits |= 4; }
        bits |= (self.memory_type as u64) << 3;
        bits |= (self.physical_address & 0xFFFF_FFC0_0000) >> 12;
        if matches!(self.level, EptLevel::Pt) {
            bits |= 0x40; // Leaf entry
        }
        bits
    }
}

/// Mock ring buffer for IPC testing
#[derive(Debug)]
pub struct MockRingBuffer {
    buffer: UnsafeCell<Vec<u8>>,
    capacity: usize,
    read_pos: AtomicUsize,
    write_pos: AtomicUsize,
    is_full: AtomicBool,
}

impl MockRingBuffer {
    pub fn new(capacity: usize) -> Self {
        Self {
            buffer: UnsafeCell::new(Vec::with_capacity(capacity)),
            capacity,
            read_pos: AtomicUsize::new(0),
            write_pos: AtomicUsize::new(0),
            is_full: AtomicBool::new(false),
        }
    }

    pub fn write(&self, data: &[u8]) -> Result<usize, &'static str> {
        let buffer = unsafe { &mut *self.buffer.get() };
        
        if data.len() > self.capacity {
            return Err("Data too large for buffer");
        }

        // Simple single-producer implementation
        let write_pos = self.write_pos.load(Ordering::Acquire);
        let available = self.available_space(write_pos);
        
        if data.len() > available {
            return Err("Not enough space in buffer");
        }

        // Ensure buffer has enough capacity
        while buffer.len() < self.capacity {
            buffer.push(0);
        }

        // Copy data
        for (i, &byte) in data.iter().enumerate() {
            buffer[(write_pos + i) % self.capacity] = byte;
        }

        let new_write_pos = (write_pos + data.len()) % self.capacity;
        self.write_pos.store(new_write_pos, Ordering::Release);
        
        if new_write_pos == self.read_pos.load(Ordering::Acquire) {
            self.is_full.store(true, Ordering::Release);
        }

        Ok(data.len())
    }

    pub fn read(&self, size: usize) -> Result<Vec<u8>, &'static str> {
        let read_pos = self.read_pos.load(Ordering::Acquire);
        let write_pos = self.write_pos.load(Ordering::Acquire);
        
        let available = if write_pos >= read_pos {
            write_pos - read_pos
        } else {
            self.capacity - read_pos + write_pos
        };

        if size > available {
            return Err("Not enough data in buffer");
        }

        let buffer = unsafe { &mut *self.buffer.get() };
        let mut result = Vec::with_capacity(size);
        
        for i in 0..size {
            result.push(buffer[(read_pos + i) % self.capacity]);
        }

        let new_read_pos = (read_pos + size) % self.capacity;
        self.read_pos.store(new_read_pos, Ordering::Release);
        self.is_full.store(false, Ordering::Release);

        Ok(result)
    }

    fn available_space(&self, write_pos: usize) -> usize {
        let read_pos = self.read_pos.load(Ordering::Acquire);
        if self.is_full.load(Ordering::Acquire) {
            0
        } else if write_pos >= read_pos {
            self.capacity - (write_pos - read_pos) - 1
        } else {
            read_pos - write_pos - 1
        }
    }

    pub fn available_data(&self) -> usize {
        let read_pos = self.read_pos.load(Ordering::Acquire);
        let write_pos = self.write_pos.load(Ordering::Acquire);
        
        if write_pos >= read_pos {
            write_pos - read_pos
        } else {
            self.capacity - read_pos + write_pos
        }
    }

    pub fn is_empty(&self) -> bool {
        self.read_pos.load(Ordering::Acquire) == self.write_pos.load(Ordering::Acquire) &&
            !self.is_full.load(Ordering::Acquire)
    }

    pub fn is_full(&self) -> bool {
        self.is_full.load(Ordering::Acquire)
    }

    pub fn capacity(&self) -> usize {
        self.capacity
    }

    pub fn clear(&self) {
        self.read_pos.store(0, Ordering::Release);
        self.write_pos.store(0, Ordering::Release);
        self.is_full.store(false, Ordering::Release);
    }
}

/// Mock Watchdog Timer
#[derive(Debug)]
pub struct MockWatchdogTimer {
    timeout_ms: u64,
    last_kick: AtomicU64,
    is_active: AtomicBool,
    is_locked: AtomicBool,
    failure_count: AtomicU64,
}

impl MockWatchdogTimer {
    pub fn new(timeout_ms: u64) -> Self {
        Self {
            timeout_ms,
            last_kick: AtomicU64::new(0),
            is_active: AtomicBool::new(false),
            is_locked: AtomicBool::new(false),
            failure_count: AtomicU64::new(0),
        }
    }

    pub fn start(&self) -> Result<(), &'static str> {
        if self.is_locked.load(Ordering::Acquire) {
            return Err("Watchdog is locked");
        }
        self.is_active.store(true, Ordering::Release);
        self.last_kick.store(0, Ordering::Release); // Current time = 0 for mock
        Ok(())
    }

    pub fn stop(&self) -> Result<(), &'static str> {
        self.is_active.store(false, Ordering::Release);
        Ok(())
    }

    pub fn kick(&self) -> Result<(), &'static str> {
        if !self.is_active.load(Ordering::Acquire) {
            return Err("Watchdog not active");
        }
        self.last_kick.store(0, Ordering::Release); // Reset to current mock time
        Ok(())
    }

    pub fn lock(&self) {
        self.is_locked.store(true, Ordering::Release);
    }

    pub fn check_timeout(&self, current_time_ms: u64) -> bool {
        if !self.is_active.load(Ordering::Acquire) {
            return false;
        }
        
        let elapsed = current_time_ms - self.last_kick.load(Ordering::Acquire);
        if elapsed > self.timeout_ms {
            self.failure_count.fetch_add(1, Ordering::AcqRel);
            return true;
        }
        false
    }

    pub fn get_failure_count(&self) -> u64 {
        self.failure_count.load(Ordering::Acquire)
    }

    pub fn is_running(&self) -> bool {
        self.is_active.load(Ordering::Acquire)
    }

    pub fn is_locked(&self) -> bool {
        self.is_locked.load(Ordering::Acquire)
    }

    pub fn timeout_ms(&self) -> u64 {
        self.timeout_ms
    }
}

/// Mock CPU state for guest VM
#[derive(Debug, Clone, Default)]
pub struct MockCpuState {
    pub rax: u64,
    pub rbx: u64,
    pub rcx: u64,
    pub rdx: u64,
    pub rsi: u64,
    pub rdi: u64,
    pub rbp: u64,
    pub r8: u64,
    pub r9: u64,
    pub r10: u64,
    pub r11: u64,
    pub r12: u64,
    pub r13: u64,
    pub r14: u64,
    pub r15: u64,
    pub rip: u64,
    pub rsp: u64,
    pub rflags: u64,
    pub cs: u16,
    pub ss: u16,
    pub ds: u16,
    pub es: u16,
    pub fs: u16,
    pub gs: u16,
    pub cr0: u64,
    pub cr2: u64,
    pub cr3: u64,
    pub cr4: u64,
    pub efer: u64,
}

impl MockCpuState {
    pub fn new() -> Self {
        let mut state = Self::default();
        // Set default values for valid CPU state
        state.cs = 0x08;
        state.ss = 0x10;
        state.ds = 0x10;
        state.es = 0x10;
        state.fs = 0;
        state.gs = 0;
        state.cr0 = 0x80050011; // PG, PE, MP
        state.cr4 = 0x20; // PAE
        state.efer = 0x500; // LME, SCE
        state.rflags = 2; // Reserved bit set
        state
    }
}

/// Mock VM configuration
#[derive(Debug, Clone, Default)]
pub struct MockVmConfig {
    pub vcpu_count: u32,
    pub memory_size: u64,
    pub memory_base: u64,
    pub ept_enabled: bool,
    pub vpid_enabled: bool,
    pub unrestricted_guest: bool,
    pub io_bitmap_a: Option<u64>,
    pub io_bitmap_b: Option<u64>,
    pub msr_bitmap: Option<u64>,
}

impl MockVmConfig {
    pub fn new() -> Self {
        Self {
            vcpu_count: 1,
            memory_size: 0x10000000, // 256 MB
            memory_base: 0x100000,   // 1 MB
            ept_enabled: true,
            vpid_enabled: true,
            unrestricted_guest: true,
            io_bitmap_a: None,
            io_bitmap_b: None,
            msr_bitmap: None,
        }
    }
}

/// Atomic operation testing utilities
pub mod atomic_utils {
    use core::sync::atomic::{AtomicU64, Ordering};
    
    /// Test that atomic load acquires proper ordering
    pub fn test_load_ordering(value: &AtomicU64) -> u64 {
        value.load(Ordering::Acquire)
    }
    
    /// Test that atomic store releases proper ordering
    pub fn test_store_ordering(value: &AtomicU64, new_val: u64) {
        value.store(new_val, Ordering::Release);
    }
    
    /// Test compare-and-swap operation
    pub fn test_compare_exchange(value: &AtomicU64, expected: u64, new_val: u64) -> Result<u64, u64> {
        value.compare_exchange(expected, new_val, Ordering::Acquire, Ordering::Relaxed)
    }
    
    /// Test fetch-and-add operation
    pub fn test_fetch_add(value: &AtomicU64, addend: u64) -> u64 {
        value.fetch_add(addend, Ordering::AcqRel)
    }
    
    /// Test fetch-and-sub operation
    pub fn test_fetch_sub(value: &AtomicU64, subend: u64) -> u64 {
        value.fetch_sub(subend, Ordering::AcqRel)
    }
    
    /// Memory barrier for testing
    pub fn test_memory_barrier() {
        core::sync::atomic::fence(Ordering::SeqCst);
    }
}

/// Test data generators
pub mod generators {
    use core::iter;
    
    /// Generate random-looking test data
    pub fn generate_test_data(size: usize) -> Vec<u8> {
        iter::repeat_with(|| {
            static COUNTER: core::sync::atomic::AtomicU8 = core::sync::atomic::AtomicU8::new(0);
            COUNTER.fetch_add(1, core::sync::atomic::Ordering::Relaxed)
        })
        .take(size)
        .collect()
    }
    
    /// Generate null-filled test data
    pub fn generate_null_data(size: usize) -> Vec<u8> {
        vec![0u8; size]
    }
    
    /// Generate pattern-filled test data
    pub fn generate_pattern_data(size: usize, pattern: u8) -> Vec<u8> {
        vec![pattern; size]
    }
    
    /// Generate alternating pattern test data
    pub fn generate_alternating_data(size: usize) -> Vec<u8> {
        (0..size)
            .map(|i| if i % 2 == 0 { 0xAA } else { 0x55 })
            .collect()
    }
}
