//! Memory Management Module
//!
//! This module provides physical memory management for the hypervisor,
//! including vmalloc-style allocation and memory region definitions.

use crate::HypervisorError;

/// Page size (4KB)
pub const PAGE_SIZE: u64 = 0x1000;

/// Large page size (2MB)
pub const LARGE_PAGE_SIZE: u64 = 0x200000;

/// Huge page size (1GB)
pub const HUGE_PAGE_SIZE: u64 = 0x40000000;

/// Memory region types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryRegionType {
    /// Warden hypervisor memory (Ring -1)
    WardenSpace,
    /// Julia guest physical memory
    GuestPhysical,
    /// Shared memory region (IPC)
    Shared,
    /// Memory-mapped I/O regions
    MMIO,
    /// Reserved memory
    Reserved,
    /// Available memory
    Available,
}

/// Memory region descriptor
#[derive(Debug, Clone, Copy)]
pub struct MemoryRegion {
    /// Start address (physical)
    pub start: u64,
    /// Size in bytes
    pub size: u64,
    /// Region type
    pub region_type: MemoryRegionType,
}

impl MemoryRegion {
    /// Create a new memory region
    pub const fn new(start: u64, size: u64, region_type: MemoryRegionType) -> Self {
        Self { start, size, region_type }
    }

    /// Check if an address is within this region
    pub fn contains(&self, addr: u64) -> bool {
        addr >= self.start && addr < self.start + self.size
    }

    /// Get end address (exclusive)
    pub fn end(&self) -> u64 {
        self.start + self.size
    }

    /// Check if this region overlaps with another
    pub fn overlaps(&self, other: &MemoryRegion) -> bool {
        self.start < other.end() && other.start < self.end()
    }
}

/// Warden memory map - predefined regions
pub mod warden_memory_map {
    use super::*;

    /// Warden code region
    pub const WARDEN_CODE: MemoryRegion = MemoryRegion::new(
        0x0001_0000,
        0x0003_0000, // 192KB
        MemoryRegionType::WardenSpace,
    );

    /// Warden data region
    pub const WARDEN_DATA: MemoryRegion = MemoryRegion::new(
        0x0004_0000,
        0x0001_0000, // 64KB
        MemoryRegionType::WardenSpace,
    );

    /// VMXON region
    pub const VMXON: MemoryRegion = MemoryRegion::new(
        0x0010_0000,
        0x1000, // 4KB
        MemoryRegionType::WardenSpace,
    );

    /// VMCS region
    pub const VMCS: MemoryRegion = MemoryRegion::new(
        0x0010_1000,
        0x1000, // 4KB per CPU
        MemoryRegionType::WardenSpace,
    );

    /// EPT page tables region
    pub const EPT_TABLES: MemoryRegion = MemoryRegion::new(
        0x0020_0000,
        0x0100_0000, // 16MB for EPT
        MemoryRegionType::WardenSpace,
    );

    /// IPC Ring Buffer
    pub const IPC_BUFFER: MemoryRegion = MemoryRegion::new(
        0x0100_0000,
        0x0400_0000, // 64MB
        MemoryRegionType::Shared,
    );

    /// Julia Guest Physical Memory
    pub const GUEST_PHYSICAL: MemoryRegion = MemoryRegion::new(
        0x1000_0000,
        0x1000_0000, // 256MB
        MemoryRegionType::GuestPhysical,
    );

    /// All Warden regions
    pub const WARDEN_REGIONS: &[MemoryRegion] = &[
        WARDEN_CODE,
        WARDEN_DATA,
        VMXON,
        VMCS,
        EPT_TABLES,
    ];

    /// All predefined regions
    pub const ALL_REGIONS: &[MemoryRegion] = &[
        WARDEN_CODE,
        WARDEN_DATA,
        VMXON,
        VMCS,
        EPT_TABLES,
        IPC_BUFFER,
        GUEST_PHYSICAL,
    ];
}

/// Memory manager for the hypervisor
pub struct MemoryManager {
    /// Total available memory
    total_memory: u64,
    /// Used memory
    used_memory: u64,
    /// Reserved regions
    reserved_regions: &'static [MemoryRegion],
}

impl MemoryManager {
    /// Create a new memory manager
    pub fn new() -> Self {
        // In a real implementation, we would detect available memory
        // from the firmware/BIOS memory map
        let total = 0x10_0000_000; // 4GB assumed for bare metal
        let used = warden_memory_map::ALL_REGIONS
            .iter()
            .map(|r| r.size)
            .sum();

        println!("[MEM] Total memory: {} MB", total / (1024 * 1024));
        println!("[MEM] Reserved: {} MB", used / (1024 * 1024));
        println!("[MEM] Available: {} MB", (total - used) / (1024 * 1024));

        Self {
            total_memory: total,
            used_memory: used,
            reserved_regions: warden_memory_map::WARDEN_REGIONS,
        }
    }

    /// Allocate a page-aligned memory region
    pub fn allocate_pages(&mut self, count: usize) -> Result<u64, HypervisorError> {
        let size = count * PAGE_SIZE as usize;

        if self.used_memory + size as u64 > self.total_memory {
            return Err(HypervisorError::OutOfMemory);
        }

        // In a real implementation, this would use a proper allocator
        // For now, use a simple bump allocator
        let base = 0x0011_0000 + self.used_memory;
        self.used_memory += size as u64;

        Ok(base)
    }

    /// Allocate aligned pages
    pub fn allocate_aligned_pages(&mut self, count: usize, align: u64) -> Result<u64, HypervisorError> {
        let size = (count * PAGE_SIZE as usize) as u64;

        if self.used_memory + size > self.total_memory {
            return Err(HypervisorError::OutOfMemory);
        }

        // Calculate aligned address
        let base = (0x0011_0000 + self.used_memory + align - 1) & !(align - 1);
        self.used_memory = base - 0x0011_0000 + size;

        Ok(base)
    }

    /// Allocate VMXON region (must be 4KB aligned)
    pub fn allocate_vmxon(&mut self) -> Result<u64, HypervisorError> {
        self.allocate_aligned_pages(1, 4096)
    }

    /// Allocate VMCS region (must be 4KB aligned)
    pub fn allocate_vmcs(&mut self) -> Result<u64, HypervisorError> {
        self.allocate_aligned_pages(1, 4096)
    }

    /// Allocate EPT pages
    pub fn allocate_ept_pages(&mut self, count: usize) -> Result<u64, HypervisorError> {
        self.allocate_aligned_pages(count, 4096)
    }

    /// Get memory info
    pub fn info(&self) -> MemoryInfo {
        MemoryInfo {
            total: self.total_memory,
            used: self.used_memory,
            available: self.total_memory - self.used_memory,
        }
    }

    /// Check if an address is in a reserved region
    pub fn is_reserved(&self, addr: u64) -> bool {
        self.reserved_regions.iter().any(|r| r.contains(addr))
    }
}

/// Memory information
#[derive(Debug, Clone, Copy)]
pub struct MemoryInfo {
    /// Total memory
    pub total: u64,
    /// Used memory
    pub used: u64,
    /// Available memory
    pub available: u64,
}

impl MemoryInfo {
    /// Get total in MB
    pub fn total_mb(&self) -> u64 {
        self.total / (1024 * 1024)
    }

    /// Get used in MB
    pub fn used_mb(&self) -> u64 {
        self.used / (1024 * 1024)
    }

    /// Get available in MB
    pub fn available_mb(&self) -> u64 {
        self.available / (1024 * 1024)
    }
}

/// Convert virtual address to physical address
/// In a real hypervisor, this requires tracking the page tables
pub fn virt_to_phys(virt: u64) -> u64 {
    // Simplified: assume identity mapping for now
    // In reality, this would walk the hypervisor's page tables
    virt
}

/// Convert physical address to virtual address
pub fn phys_to_virt(phys: u64) -> u64 {
    // Simplified: assume identity mapping for now
    phys
}

/// Zero a memory region
pub fn zero_memory(addr: u64, size: usize) {
    let ptr = addr as *mut u8;
    unsafe {
        core::ptr::write_bytes(ptr, 0, size);
    }
}

/// Copy memory region
pub fn copy_memory(dest: u64, src: u64, size: usize) {
    let dest_ptr = dest as *mut u8;
    let src_ptr = src as *const u8;
    unsafe {
        core::ptr::copy_nonoverlapping(src_ptr, dest_ptr, size);
    }
}
