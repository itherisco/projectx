//! Memory Management Module
//!
//! This module provides physical memory management for the bare-metal kernel.
//! It includes a buddy system allocator and memory layout definitions.
//!
//! # Memory Layout (per architecture spec)
//! ```text
//! 0x00000000 - 0x0000FFFF    | Boot ROM / Bootstrap
//! 0x00010000 - 0x00100000    | Rust Kernel Text & Data
//! 0x00100000 - 0x01000000    | Kernel Heap / Slab Allocator
//! 0x01000000 - 0x01100000    | IPC Shared Memory Region
//! 0x01100000 - 0x10000000    | Julia Runtime Region
//! 0x10000000+                | User Applications / Page Tables
//! ```

#[cfg(feature = "bare-metal")]
use buddy_system_allocator::LockedHeap;

/// Memory layout constants
pub mod layout {
    /// Physical address where kernel image is loaded
    pub const KERNEL_PHYS_START: u64 = 0x0010_0000;
    
    /// Kernel image size (estimate)
    pub const KERNEL_SIZE: u64 = 0x0010_0000; // 16MB
    
    /// Kernel heap start
    pub const HEAP_START: u64 = 0x0020_0000;
    
    /// Kernel heap size
    pub const HEAP_SIZE: u64 = 0x00E0_0000; // 224MB
    
    /// IPC shared memory region start
    pub const IPC_SHM_START: u64 = 0x0100_0000;
    
    /// IPC shared memory region size (16MB)
    pub const IPC_SHM_SIZE: u64 = 0x0010_0000;
    
    /// Julia runtime region start
    pub const JULIA_RUNTIME_START: u64 = 0x0110_0000;
    
    /// Page size (4KB)
    pub const PAGE_SIZE: u64 = 0x1000;
    
    /// Number of pages in kernel heap
    pub const HEAP_PAGES: usize = (HEAP_SIZE / PAGE_SIZE) as usize;
}

/// Physical memory frame
#[derive(Debug, Clone, Copy)]
pub struct PhysFrame {
    pub start: u64,
    pub size: u64,
}

impl PhysFrame {
    /// Check if this frame contains the given address
    pub fn contains(&self, addr: u64) -> bool {
        addr >= self.start && addr < self.start + self.size
    }
    
    /// Get the end address (exclusive)
    pub fn end(&self) -> u64 {
        self.start + self.size
    }
}

/// E820 memory map entry type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryType {
    Usable = 1,
    Reserved = 2,
    ACPIReclaimable = 3,
    NVS = 4,
    BadRAM = 5,
}

/// E820 memory map entry
#[derive(Debug, Clone, Copy)]
pub struct E820Entry {
    pub addr: u64,
    pub size: u64,
    pub mem_type: MemoryType,
}

/// Physical memory manager
pub struct PhysicalMemoryManager {
    /// Total usable memory in bytes
    pub total_memory: u64,
    /// Memory map entries
    pub memory_map: &'static [E820Entry],
}

impl PhysicalMemoryManager {
    /// Initialize the memory manager with the E820 map
    pub fn new(memory_map: &'static [E820Entry]) -> Self {
        let total: u64 = memory_map
            .iter()
            .filter(|e| e.mem_type == MemoryType::Usable)
            .map(|e| e.size)
            .sum();
        
        println!("[MEMORY] Total usable memory: {} MB", total / (1024 * 1024));
        
        PhysicalMemoryManager {
            total_memory: total,
            memory_map: memory_map,
        }
    }
    
    /// Get usable memory regions
    pub fn usable_regions(&self) -> impl Iterator<Item = &E820Entry> {
        self.memory_map.iter().filter(|e| e.mem_type == MemoryType::Usable)
    }
    
    /// Allocate a physical frame
    pub fn allocate_frame(&mut self, size: u64) -> Option<PhysFrame> {
        for entry in self.memory_map.iter() {
            if entry.mem_type == MemoryType::Usable && entry.size >= size {
                let frame = PhysFrame {
                    start: entry.addr,
                    size,
                };
                return Some(frame);
            }
        }
        None
    }
}

/// Kernel heap allocator type
#[cfg(feature = "bare-metal")]
pub type KernelHeap = LockedHeap<32>;

/// Initialize the kernel heap
#[cfg(feature = "bare-metal")]
pub fn init_heap() -> KernelHeap {
    let mut heap = LockedHeap::<32>::empty();
    unsafe {
        heap.init(layout::HEAP_START as *mut u8, layout::HEAP_SIZE as usize);
    }
    println!("[MEMORY] Kernel heap initialized at 0x{:x} ({} MB)", 
        layout::HEAP_START, layout::HEAP_SIZE / (1024 * 1024));
    heap
}

/// Memory information
#[derive(Debug)]
pub struct MemoryInfo {
    pub total: u64,
    pub used: u64,
    pub free: u64,
    pub kernel_heap_size: u64,
}

impl MemoryInfo {
    /// Get human-readable total memory
    pub fn total_mb(&self) -> u64 {
        self.total / (1024 * 1024)
    }
    
    /// Get human-readable used memory
    pub fn used_mb(&self) -> u64 {
        self.used / (1024 * 1024)
    }
    
    /// Get human-readable free memory
    pub fn free_mb(&self) -> u64 {
        self.free / (1024 * 1024)
    }
}

/// Virtual address space utilities
pub mod virt {
    /// Convert physical address to virtual
    pub fn phys_to_virt(phys: u64) -> u64 {
        phys + 0xFFFF_FF80_0000_0000
    }
    
    /// Convert virtual address to physical
    pub fn virt_to_phys(virt: u64) -> Option<u64> {
        // Only works for identity-mapped regions
        if virt >= 0xFFFF_FF80_0000_0000 {
            Some(virt - 0xFFFF_FF80_0000_0000)
        } else {
            None
        }
    }
    
    /// Check if address is in userspace
    pub fn is_user_address(addr: u64) -> bool {
        addr < 0x0000_8000_0000_0000
    }
    
    /// Check if address is in kernel space
    pub fn is_kernel_address(addr: u64) -> bool {
        !is_user_address(addr)
    }
}

/// Page table utilities
pub mod page {
    use super::layout::PAGE_SIZE;
    
    /// Align address down to page boundary
    pub fn align_down(addr: u64) -> u64 {
        addr & !(PAGE_SIZE - 1)
    }
    
    /// Align address up to page boundary
    pub fn align_up(addr: u64) -> u64 {
        (addr + PAGE_SIZE - 1) & !(PAGE_SIZE - 1)
    }
    
    /// Calculate number of pages needed for size
    pub fn pages_needed(size: u64) -> usize {
        ((size + PAGE_SIZE - 1) / PAGE_SIZE) as usize
    }
}
