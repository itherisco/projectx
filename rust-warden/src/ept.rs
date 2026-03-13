//! Extended Page Table (EPT) Implementation
//!
//! This module provides the Intel EPT (Extended Page Table) functionality,
//! which provides second-level address translation for memory virtualization.

use crate::HypervisorError;
use crate::memory::{PAGE_SIZE, LARGE_PAGE_SIZE, HUGE_PAGE_SIZE};

/// EPT memory types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EptMemoryType {
    /// Uncacheable (UC)
    Uncacheable = 0,
    /// Write-Combining (WC)
    WriteCombining = 1,
    /// Write-Through (WT)
    WriteThrough = 4,
    /// Write-Protected (WP)
    WriteProtected = 5,
    /// Write-Back (WB)
    WriteBack = 6,
}

impl Default for EptMemoryType {
    fn default() -> Self {
        Self::WriteBack
    }
}

/// EPT permissions
#[derive(Debug, Clone, Copy, Default)]
pub struct EptPermissions {
    /// Read permission
    pub read: bool,
    /// Write permission
    pub write: bool,
    /// Execute permission
    pub execute: bool,
}

impl EptPermissions {
    /// Read-only
    pub const fn read_only() -> Self {
        Self { read: true, write: false, execute: true }
    }

    /// Read-write
    pub const fn read_write() -> Self {
        Self { read: true, write: true, execute: false }
    }

    /// Read-execute
    pub const fn read_execute() -> Self {
        Self { read: true, write: false, execute: true }
    }

    /// No access
    pub const fn none() -> Self {
        Self { read: false, write: false, execute: false }
    }

    /// Full access
    pub const fn full() -> Self {
        Self { read: true, write: true, execute: true }
    }

    /// Convert to EPT entry bits
    fn to_bits(&self) -> u64 {
        let mut bits = 0u64;
        if self.read { bits |= 1 << 0; }
        if self.write { bits |= 1 << 1; }
        if self.execute { bits |= 1 << 2; }
        bits
    }
}

/// EPT Page Directory Pointer Table Entry (1GB page)
#[repr(C)]
pub struct EptPdpe1GB {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bit 3: Ignored
    _ignore1: u8,
    /// Bit 4: Memory type
    memory_type: u8,
    /// Bit 5: Ignore PAT
    ignore_pat: bool,
    /// Bit 6: Page size (1 = 1GB)
    page_size: bool,
    /// Bit 7: Accessed
    accessed: bool,
    /// Bit 8: Dirty
    dirty: bool,
    /// Bits 9-11: User/Supervisor
    _user: u8,
    /// Bits 12-51: Physical address (bits 30-12)
    physical_address: u40,
    /// Bits 52-63: Reserved
    _reserved: u12,
}

#[repr(C)]
struct u40(u64);
#[repr(C)]
struct u12(u64);

impl EptPdpe1GB {
    /// Create new 1GB PDPE
    pub fn new(phys_addr: u64, perms: &EptPermissions, mem_type: EptMemoryType) -> Self {
        Self {
            access: perms.to_bits() as u8,
            _ignore1: 0,
            memory_type: mem_type as u8,
            ignore_pat: false,
            page_size: true,
            accessed: false,
            dirty: false,
            _user: 0,
            physical_address: u40(phys_addr >> 30),
            _reserved: u12(0),
        }
    }
}

/// EPT Page Directory Entry (2MB page)
#[repr(C)]
pub struct EptPde2MB {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bit 3: Ignored
    _ignore1: u8,
    /// Bit 4: Memory type
    memory_type: u8,
    /// Bit 5: Ignore PAT
    ignore_pat: bool,
    /// Bit 6: Page size (1 = 2MB)
    page_size: bool,
    /// Bit 7: Accessed
    accessed: bool,
    /// Bit 8: Dirty
    dirty: bool,
    /// Bit 9: Global
    _global: u8,
    /// Bits 12-20: Available
    available: u16,
    /// Bits 21-51: Physical address (bits 21-12)
    physical_address: u32,
    /// Bits 52-63: Reserved
    _reserved: u32,
}

impl EptPde2MB {
    /// Create new 2MB PDE
    pub fn new(phys_addr: u64, perms: &EptPermissions, mem_type: EptMemoryType) -> Self {
        Self {
            access: perms.to_bits() as u8,
            _ignore1: 0,
            memory_type: mem_type as u8,
            ignore_pat: false,
            page_size: true,
            accessed: false,
            dirty: false,
            _global: 0,
            available: 0,
            physical_address: (phys_addr >> 21) as u32,
            _reserved: 0,
        }
    }
}

/// EPT Page Table Entry (4KB page)
#[repr(C)]
pub struct EptPte4KB {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bit 3: Ignored
    _ignore1: u8,
    /// Bit 4: Memory type
    memory_type: u8,
    /// Bit 5: Ignore PAT
    ignore_pat: bool,
    /// Bit 6: Page size (0 = 4KB)
    page_size: bool,
    /// Bit 7: Accessed
    accessed: bool,
    /// Bit 8: Dirty
    dirty: bool,
    /// Bit 9-11: User/Supervisor
    _user: u8,
    /// Bits 12-19: Available
    available: u8,
    /// Bits 20-51: Physical address (bits 51-12)
    physical_address: u32,
    /// Bits 52-63: Reserved
    _reserved: u32,
}

impl EptPte4KB {
    /// Create new 4KB PTE
    pub fn new(phys_addr: u64, perms: &EptPermissions, mem_type: EptMemoryType) -> Self {
        Self {
            access: perms.to_bits() as u8,
            _ignore1: 0,
            memory_type: mem_type as u8,
            ignore_pat: false,
            page_size: false,
            accessed: false,
            dirty: false,
            _user: 0,
            available: 0,
            physical_address: (phys_addr >> 12) as u32,
            _reserved: 0,
        }
    }
}

/// EPT PML4 Entry
#[repr(C)]
pub struct EptPml4e {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bits 3-5: Ignored
    _ignore: u8,
    /// Bit 6: Ignore PAT
    ignore_pat: bool,
    /// Bit 7: Page size (must be 0 for PML4)
    page_size: bool,
    /// Bit 8-11: Reserved
    _reserved1: u8,
    /// Bits 12-51: Physical address (bits 51-12)
    physical_address: u32,
    /// Bits 52-63: Reserved
    _reserved2: u32,
}

impl EptPml4e {
    /// Create new PML4E
    pub fn new(phys_addr: u64) -> Self {
        Self {
            access: 0x7, // R/W/X
            _ignore: 0,
            ignore_pat: false,
            page_size: false,
            _reserved1: 0,
            physical_address: (phys_addr >> 12) as u32,
            _reserved2: 0,
        }
    }
}

/// EPT Page Directory Pointer Entry (points to PD)
#[repr(C)]
pub struct EptPdpte {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bits 3-5: Ignored
    _ignore: u8,
    /// Bit 6: Ignore PAT
    ignore_pat: bool,
    /// Bit 7: Page size (0 = points to PD)
    page_size: bool,
    /// Bit 8-11: Reserved
    _reserved1: u8,
    /// Bits 12-51: Physical address (bits 51-12)
    physical_address: u32,
    /// Bits 52-63: Reserved
    _reserved2: u32,
}

impl EptPdpte {
    /// Create new PDPTE
    pub fn new(phys_addr: u64) -> Self {
        Self {
            access: 0x7, // R/W/X
            _ignore: 0,
            ignore_pat: false,
            page_size: false,
            _reserved1: 0,
            physical_address: (phys_addr >> 12) as u32,
            _reserved2: 0,
        }
    }
}

/// EPT Page Directory Entry (points to PT)
#[repr(C)]
pub struct EptPde {
    /// Bits 0-2: Access rights
    access: u8,
    /// Bits 3-5: Ignored
    _ignore: u8,
    /// Bit 6: Ignore PAT
    ignore_pat: bool,
    /// Bit 7: Page size (0 = points to PT)
    page_size: bool,
    /// Bit 8-11: Reserved
    _reserved1: u8,
    /// Bits 12-51: Physical address (bits 51-12)
    physical_address: u32,
    /// Bits 52-63: Reserved
    _reserved2: u32,
}

impl EptPde {
    /// Create new PDE
    pub fn new(phys_addr: u64) -> Self {
        Self {
            access: 0x7, // R/W/X
            _ignore: 0,
            ignore_pat: false,
            page_size: false,
            _reserved1: 0,
            physical_address: (phys_addr >> 12) as u32,
            _reserved2: 0,
        }
    }
}

/// EPT Page Table
#[repr(C, align(4096))]
pub struct EptPageTable {
    /// Entries
    entries: [u64; 512],
}

impl EptPageTable {
    /// Create new page table
    pub fn new() -> Self {
        Self { entries: [0; 512] }
    }

    /// Get entry
    pub fn get_entry(&self, index: usize) -> u64 {
        self.entries[index]
    }

    /// Set entry
    pub fn set_entry(&mut self, index: usize, value: u64) {
        self.entries[index] = value;
    }
}

impl Default for EptPageTable {
    fn default() -> Self {
        Self::new()
    }
}

/// EPT PML4 Table
pub type EptPml4 = EptPageTable;

/// EPT PDPT
pub type EptPdpt = EptPageTable;

/// EPT PD
pub type EptPd = EptPageTable;

/// EPT PT
pub type EptPt = EptPageTable;

/// EPT Violation information
#[derive(Debug, Clone, Copy)]
pub struct EptViolation {
    /// Read violation
    pub read: bool,
    /// Write violation
    pub write: bool,
    /// Execute violation
    pub execute: bool,
    /// Guest linear address
    pub guest_linear: u64,
    /// Guest physical address
    pub guest_physical: u64,
    /// Caused by fetch (instruction fetch)
    pub fetch: bool,
}

impl EptViolation {
    /// Create from exit qualification
    pub fn from_qualification(qual: u64, linear: u64, physical: u64) -> Self {
        Self {
            read: (qual & 0x1) != 0,
            write: (qual & 0x2) != 0,
            execute: (qual & 0x4) != 0,
            guest_linear: linear,
            guest_physical: physical,
            fetch: (qual & 0x8) != 0,
        }
    }
}

/// EPT Manager - manages EPT tables for a guest
pub struct EptManager {
    /// Guest physical base address
    guest_phys_base: u64,
    /// Guest physical size
    guest_phys_size: u64,
    /// PML4 physical address
    pml4_phys: u64,
    /// PML4 virtual address
    pml4: &'static mut EptPml4,
    /// Memory type
    memory_type: EptMemoryType,
    /// Allocated pages count
    allocated_pages: usize,
}

impl EptManager {
    /// Create new EPT manager
    pub fn new(guest_phys_base: u64, guest_phys_size: u64) -> Result<Self, HypervisorError> {
        // Calculate required pages
        let pages_needed = Self::calculate_pages_needed(guest_phys_size);
        
        // Allocate EPT pages
        let pml4 = Box::leak(Box::new(EptPml4::new()));
        let pml4_phys = pml4 as *const _ as u64;
        
        // Ensure alignment
        assert!(pml4_phys % 4096 == 0, "PML4 must be 4KB aligned");
        
        println!("[EPT] Guest physical: 0x{:x} - 0x{:x}", 
            guest_phys_base, 
            guest_phys_base + guest_phys_size);
        println!("[EPT] EPT root: 0x{:x}", pml4_phys);
        
        let mut ept = Self {
            guest_phys_base,
            guest_phys_size,
            pml4_phys,
            pml4,
            memory_type: EptMemoryType::WriteBack,
            allocated_pages: 1, // PML4
        };
        
        // Map guest physical memory
        ept.map_guest_memory()?;
        
        Ok(ept)
    }

    /// Calculate required EPT pages
    fn calculate_pages_needed(guest_size: u64) -> usize {
        // PML4: 1 page (covers 512GB)
        let pdpt_pages = ((guest_size + 0x3F_FFFF) >> 30).max(1) as usize;
        let pd_pages = ((guest_size + 0x1F_FFFF) >> 21).max(1) as usize;
        let pt_pages = ((guest_size + 0xFFF) >> 12).max(1) as usize;
        
        1 + pdpt_pages + pd_pages + pt_pages
    }

    /// Map guest physical memory
    pub fn map_guest_memory(&mut self) -> Result<(), HypervisorError> {
        let mut current_gpa = self.guest_phys_base;
        let end_gpa = self.guest_phys_base + self.guest_phys_size;
        
        while current_gpa < end_gpa {
            let remaining = end_gpa - current_gpa;
            
            // Try to use 1GB pages first
            if remaining >= HUGE_PAGE_SIZE && current_gpa % HUGE_PAGE_SIZE == 0 {
                self.map_1gb_page(current_gpa)?;
                current_gpa += HUGE_PAGE_SIZE;
            }
            // Try 2MB pages
            else if remaining >= LARGE_PAGE_SIZE && current_gpa % LARGE_PAGE_SIZE == 0 {
                self.map_2mb_page(current_gpa)?;
                current_gpa += LARGE_PAGE_SIZE;
            }
            // Use 4KB pages
            else {
                self.map_4kb_page(current_gpa)?;
                current_gpa += PAGE_SIZE;
            }
        }
        
        println!("[EPT] Mapped {} pages", self.allocated_pages);
        
        Ok(())
    }

    /// Map 1GB page
    fn map_1gb_page(&mut self, gpa: u64) -> Result<(), HypervisorError> {
        // Allocate host memory for this page
        // In real implementation, this would allocate physical memory
        let hpa = gpa; // Identity mapping for now
        
        // Get PML4 index
        let pml4_idx = ((gpa >> 39) & 0x1FF) as usize;
        
        // Allocate PDPT if needed
        let pdpt = self.get_or_create_pdpt(pml4_idx)?;
        
        // Create 1GB PDE
        let pde = EptPdpe1GB::new(hpa, &EptPermissions::full(), self.memory_type);
        
        // Write to PDPT
        let pdpt_mut = unsafe { &mut *(pdpt as *mut EptPageTable) };
        pdpt_mut.set_entry(((gpa >> 30) & 0x1FF) as usize, pde as u64 | 0x7);
        
        Ok(())
    }

    /// Map 2MB page
    fn map_2mb_page(&mut self, gpa: u64) -> Result<(), HypervisorError> {
        let hpa = gpa; // Identity mapping
        
        // Get PML4 index
        let pml4_idx = ((gpa >> 39) & 0x1FF) as usize;
        
        // Get PDPT
        let pdpt = self.get_or_create_pdpt(pml4_idx)?;
        let pdpt_mut = unsafe { &mut *(pdpt as *mut EptPageTable) };
        
        // Allocate PD if needed
        let pd = self.get_or_create_pd(pml4_idx, ((gpa >> 30) & 0x1FF) as usize)?;
        
        // Create 2MB PDE
        let pde = EptPde2MB::new(hpa, &EptPermissions::full(), self.memory_type);
        
        // Write to PD
        let pd_mut = unsafe { &mut *(pd as *mut EptPageTable) };
        pd_mut.set_entry(((gpa >> 21) & 0x1FF) as usize, pde as u64 | 0x7);
        
        Ok(())
    }

    /// Map 4KB page
    fn map_4kb_page(&mut self, gpa: u64) -> Result<(), HypervisorError> {
        let hpa = gpa; // Identity mapping
        
        // Get indices
        let pml4_idx = ((gpa >> 39) & 0x1FF) as usize;
        let pdpt_idx = ((gpa >> 30) & 0x1FF) as usize;
        let pd_idx = ((gpa >> 21) & 0x1FF) as usize;
        
        // Get/create tables
        let pdpt = self.get_or_create_pdpt(pml4_idx)?;
        let pd = self.get_or_create_pd(pml4_idx, pdpt_idx)?;
        let pt = self.get_or_create_pt(pml4_idx, pdpt_idx, pd_idx)?;
        
        // Create PTE
        let pte = EptPte4KB::new(hpa, &EptPermissions::full(), self.memory_type);
        
        // Write to PT
        let pt_mut = unsafe { &mut *(pt as *mut EptPageTable) };
        pt_mut.set_entry(((gpa >> 12) & 0x1FF) as usize, pte as u64 | 0x7);
        
        self.allocated_pages += 1;
        
        Ok(())
    }

    /// Get or create PDPT
    fn get_or_create_pdpt(&mut self, pml4_idx: usize) -> Result<u64, HypervisorError> {
        let entry = self.pml4.get_entry(pml4_idx);
        
        if entry != 0 {
            return Ok((entry & 0xFFFF_FFC0_000) as u64);
        }
        
        // Allocate new PDPT
        let pdpt = Box::leak(Box::new(EptPdpt::new()));
        let phys = pdpt as *const _ as u64;
        
        // Write PML4E
        self.pml4.set_entry(pml4_idx, (phys & 0xFFFF_FFC0_000) as u64 | 0x7);
        
        self.allocated_pages += 1;
        
        Ok(phys)
    }

    /// Get or create PD
    fn get_or_create_pd(&mut self, pml4_idx: usize, pdpt_idx: usize) -> Result<u64, HypervisorError> {
        let pdpt_phys = (self.pml4.get_entry(pml4_idx) & 0xFFFF_FFC0_000) as u64;
        let pdpt = unsafe { &*(pdpt_phys as *const EptPageTable) };
        
        let entry = pdpt.get_entry(pdpt_idx);
        
        if entry != 0 {
            return Ok((entry & 0xFFFF_FFC0_000) as u64);
        }
        
        // Allocate new PD
        let pd = Box::leak(Box::new(EptPd::new()));
        let phys = pd as *const _ as u64;
        
        // Write PDPTE
        let pdpt_mut = unsafe { &mut *(pdpt_phys as *mut EptPageTable) };
        pdpt_mut.set_entry(pdpt_idx, (phys & 0xFFFF_FFC0_000) as u64 | 0x7);
        
        self.allocated_pages += 1;
        
        Ok(phys)
    }

    /// Get or create PT
    fn get_or_create_pt(&mut self, pml4_idx: usize, pdpt_idx: usize, pd_idx: usize) -> Result<u64, HypervisorError> {
        let pdpt_phys = (self.pml4.get_entry(pml4_idx) & 0xFFFF_FFC0_000) as u64;
        let pdpt = unsafe { &*(pdpt_phys as *const EptPageTable) };
        
        let pd_phys = (pdpt.get_entry(pdpt_idx) & 0xFFFF_FFC0_000) as u64;
        let pd = unsafe { &*(pd_phys as *const EptPageTable) };
        
        let entry = pd.get_entry(pd_idx);
        
        if entry != 0 {
            return Ok((entry & 0xFFFF_FFC0_000) as u64);
        }
        
        // Allocate new PT
        let pt = Box::leak(Box::new(EptPt::new()));
        let phys = pt as *const _ as u64;
        
        // Write PDE
        let pd_mut = unsafe { &mut *(pd_phys as *mut EptPageTable) };
        pd_mut.set_entry(pd_idx, (phys & 0xFFFF_FFC0_000) as u64 | 0x7);
        
        self.allocated_pages += 1;
        
        Ok(phys)
    }

    /// Get EPTP (EPT Pointer) for VMCS
    pub fn get_eptp(&self) -> u64 {
        // EPTP format:
        // Bits 0-2: Memory type (0 = UC, 6 = WB)
        // Bits 3-5: Reserved
        // Bits 6-7: Page walk length (0 = 4, meaning 4 walks)
        // Bit 8: Accessed and dirty flags enabled
        // Bits 9-11: Reserved
        // Bits 12-51: PML4 physical address (bits 51-12)
        // Bits 52-63: Reserved
        
        let mem_type = match self.memory_type {
            EptMemoryType::Uncacheable => 0u64,
            EptMemoryType::WriteBack => 6u64,
            _ => 0u64,
        };
        
        mem_type | (4 << 6) | ((self.pml4_phys >> 12) << 12)
    }

    /// Map shared memory region
    pub fn map_shared_memory(&mut self, guest_addr: u64, host_addr: u64, size: u64) 
        -> Result<(), HypervisorError> 
    {
        let mut current = guest_addr;
        let end = guest_addr + size;
        
        while current < end {
            self.map_4kb_page_with_host(current, host_addr + (current - guest_addr))?;
            current += PAGE_SIZE;
        }
        
        Ok(())
    }

    /// Map 4KB page with specific host address
    fn map_4kb_page_with_host(&mut self, gpa: u64, hpa: u64) -> Result<(), HypervisorError> {
        // Get indices
        let pml4_idx = ((gpa >> 39) & 0x1FF) as usize;
        let pdpt_idx = ((gpa >> 30) & 0x1FF) as usize;
        let pd_idx = ((gpa >> 21) & 0x1FF) as usize;
        
        // Get/create tables
        let pdpt = self.get_or_create_pdpt(pml4_idx)?;
        let pd = self.get_or_create_pd(pml4_idx, pdpt_idx)?;
        let pt = self.get_or_create_pt(pml4_idx, pdpt_idx, pd_idx)?;
        
        // Create PTE with read-write for shared memory
        let perms = EptPermissions { read: true, write: true, execute: false };
        let pte = EptPte4KB::new(hpa, &perms, self.memory_type);
        
        // Write to PT
        let pt_mut = unsafe { &mut *(pt as *mut EptPageTable) };
        pt_mut.set_entry(((gpa >> 12) & 0x1FF) as usize, pte as u64 | 0x7);
        
        Ok(())
    }

    /// Get number of allocated pages
    pub fn allocated_pages(&self) -> usize {
        self.allocated_pages
    }
}

impl Drop for EptManager {
    fn drop(&mut self) {
        // In a real implementation, we would free the allocated EPT pages
        // For now, they're leaked as static allocations
    }
}
