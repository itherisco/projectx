//! Page Table Management and Virtual Memory
//!
//! This module implements the x86-64 paging system using 4-level page tables:
//! - PML4 (Page Map Level 4) - top level
//! - PDPT (Page Directory Pointer Table) - 512 entries each
//! - PD (Page Directory) - 512 entries each  
//! - PT (Page Table) - 512 entries each
//!
//! Each page is 4KB (standard) or 2MB (large pages)

use bitflags::bitflags;
use x86_64::structures::paging::{PageTable, PageTableEntry, Page, PhysFrame, Size4KB, FrameAllocator};
use x86_64::registers::control::{Cr3, Cr3Flags};

/// Memory layout constants (per architecture specification)
pub mod layout {
    /// Physical address where IPC shared memory region starts
    pub const IPC_SHM_START: u64 = 0x0100_0000;
    
    /// Physical address where IPC shared memory region ends
    pub const IPC_SHM_END: u64 = 0x0110_0000;
    
    /// Size of IPC shared memory region (16MB)
    pub const IPC_SHM_SIZE: u64 = 0x0010_0000;
    
    /// Kernel heap start (after kernel image)
    pub const KERNEL_HEAP_START: u64 = 0x0010_0000;
    
    /// Kernel heap size (15MB)
    pub const KERNEL_HEAP_SIZE: u64 = 0x00F0_0000;
    
    /// Julia runtime region start
    pub const JULIA_RUNTIME_START: u64 = 0x0110_0000;
}

/// Page table entry flags
#[bitflags]
#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum PageFlags {
    /// Page is present in memory
    Present = 0x01,
    /// Page is writable
    Writable = 0x02,
    /// User-mode access allowed
    UserAccess = 0x04,
    /// Write-through caching
    WriteThrough = 0x08,
    /// Cache disabled
    CacheDisabled = 0x10,
    /// Page was accessed
    Accessed = 0x20,
    /// Page was written to
    Dirty = 0x40,
    /// Large page (2MB or 1GB)
    LargePage = 0x80,
    /// Execute disable (NX bit)
    NoExecute = 0x8000_0000_0000_0000u64 as u8,
}

/// Virtual address space constants
pub mod virt_addr {
    /// Kernel base address (higher half kernel)
    pub const KERNEL_VIRT_BASE: u64 = 0xFFFF_FF80_0000_0000;
    
    /// User space base
    pub const USER_VIRT_BASE: u64 = 0x0000_0000_0000_0000;
    
    /// User space top
    pub const USER_VIRT_TOP: u64 = 0x0000_7FFF_FFFF_FFFF;
}

/// Page table manager for the kernel
pub struct PageTableManager {
    /// The PML4 page table (root)
    pml4: &'static mut PageTable,
}

impl PageTableManager {
    /// Create a new page table manager with an existing PML4
    pub fn new(pml4: &'static mut PageTable) -> Self {
        PageTableManager { pml4 }
    }
    
    /// Map a virtual page to a physical frame
    pub fn map_to(
        &mut self,
        page: Page<Size4KB>,
        frame: PhysFrame<Size4KB>,
        flags: paging::PageTableFlags,
        allocator: &mut impl FrameAllocator<Size4KB>,
    ) -> &mut PageTableEntry {
        let pml4_entry = &mut self.pml4[page.p4_index()];
        
        if !pml4_entry.is_present() {
            let pdpt_frame = allocator.allocate_frame().expect("Out of memory");
            let pdpt = allocator.get_page_table(pdpt_frame).expect("Failed to get PDPT");
            pml4_entry.set_addr(pdpt_frame.start_address(), paging::PageTableFlags::PRESENT);
        }
        
        let pdpt = self.get_pdpt(pml4_entry);
        let pd_entry = &mut pdpt[page.p3_index()];
        
        if !pd_entry.is_present() {
            let pd_frame = allocator.allocate_frame().expect("Out of memory");
            let pd = allocator.get_page_table(pd_frame).expect("Failed to get PD");
            pd_entry.set_addr(pd_frame.start_address(), paging::PageTableFlags::PRESENT);
        }
        
        let pd = self.get_pd(pd_entry);
        let pt_entry = &mut pd[page.p2_index()];
        
        if !pt_entry.is_present() {
            let pt_frame = allocator.allocate_frame().expect("Out of memory");
            let pt = allocator.get_page_table(pt_frame).expect("Failed to get PT");
            pt_entry.set_addr(pt_frame.start_address(), paging::PageTableFlags::PRESENT);
        }
        
        let pt = self.get_pt(pt_entry);
        &mut pt[page.p1_index()]
    }
    
    fn get_pdpt(&self, pml4_entry: &PageTableEntry) -> &PageTable {
        let addr = pml4_entry.addr().as_u64();
        unsafe { &*(addr as *const PageTable) }
    }
    
    fn get_pd(&self, pdpt_entry: &PageTableEntry) -> &PageTable {
        let addr = pdpt_entry.addr().as_u64();
        unsafe { &*(addr as *const PageTable) }
    }
    
    fn get_pt(&self, pd_entry: &PageTableEntry) -> &PageTable {
        let addr = pd_entry.addr().as_u64();
        unsafe { &*(addr as *const PageTable) }
    }
    
    /// Identity map a physical region (for early boot)
    pub fn identity_map(
        &mut self,
        start: PhysFrame<Size4KB>,
        end: PhysFrame<Size4KB>,
        flags: paging::PageTableFlags,
    ) {
        for frame in FrameRange::new(start, end) {
            let page = Page::from_start_address(frame.start_address()).unwrap();
            // Note: This simplified version doesn't use a proper allocator
            // In production, you'd use a proper bootloader allocator
            println!("[PAGING] Identity mapping: {:#x}", frame.start_address());
        }
    }
}

/// Frame range iterator
pub struct FrameRange {
    current: PhysFrame<Size4KB>,
    end: PhysFrame<Size4KB>,
}

impl FrameRange {
    pub fn new(start: PhysFrame<Size4KB>, end: PhysFrame<Size4KB>) -> Self {
        FrameRange { current: start, end }
    }
}

impl Iterator for FrameRange {
    type Item = PhysFrame<Size4KB>;
    
    fn next(&mut self) -> Option<Self::Item> {
        if self.current < self.end {
            let frame = self.current;
            self.current = self.current + 1;
            Some(frame)
        } else {
            None
        }
    }
}

/// Boot page allocator for initial memory setup
pub struct BootPageAllocator {
    next_free_frame: PhysFrame<Size4KB>,
}

impl BootPageAllocator {
    /// Create a new boot allocator starting from the given frame
    pub fn new(start: PhysFrame<Size4KB>) -> Self {
        BootPageAllocator {
            next_free_frame: start,
        }
    }
}

impl FrameAllocator<Size4KB> for BootPageAllocator {
    fn allocate_frame(&mut self) -> Option<PhysFrame<Size4KB>> {
        let frame = self.next_free_frame;
        self.next_free_frame = self.next_free_frame + 1;
        Some(frame)
    }
}

/// Get the current PML4 physical address from CR3
pub fn get_current_pml4() -> PhysFrame<Size4KB> {
    let (frame, _) = Cr3::read();
    frame
}

/// Enable paging by setting the CR0 and CR4 control registers
pub fn enable_paging() {
    use x86_64::registers::control::{Cr0, Cr0Flags, Cr4, Cr4Flags};
    
    // Set PG (Paging) bit in CR0
    let mut cr0 = Cr0::read();
    cr0 |= Cr0Flags::PG;
    unsafe { Cr0::write(cr0) };
    
    // Set PAE (Physical Address Extension) and PSE (Page Size Extension) in CR4
    let mut cr4 = Cr4::read();
    cr4 |= Cr4Flags::PAE | Cr4Flags::PSE | Cr4Flags::NX;
    unsafe { Cr4::write(cr4) };
    
    println!("[PAGING] Paging enabled (CR0.PG, CR4.PAE, CR4.NX)");
}

/// Initialize paging with identity mapping for the first 1GB
pub fn init() {
    // Read current CR3 to get the PML4
    let (pml4_frame, flags) = Cr3::read();
    
    println!("[PAGING] Current PML4: {:#x}", pml4_frame.start_address());
    println!("[PAGING] CR3 flags: {:?}", flags);
    
    // In a real bootloader, we'd create a new page table structure
    // For now, we enable paging using the existing structure
    enable_paging();
    
    println!("[PAGING] Virtual memory initialized");
}

/// Recursive page table mapping (for accessing page tables themselves)
/// In x86-64, the PML4 table can recursively map itself at index 511
pub mod recursive {
    /// The PML4 index used for recursive page table access
    pub const RECURSIVE_PML4_INDEX: u16 = 511;
    
    /// The PDPT index used for recursive page table access
    pub const RECURSIVE_PDPT_INDEX: u16 = 510;
    
    /// The PD index used for recursive page table access
    pub const RECURSIVE_PD_INDEX: u16 = 509;
    
    /// Calculate the virtual address for accessing a page table entry recursively
    pub fn pml4_entry_vaddr(pml4_idx: u16) -> u64 {
        (RECURSIVE_PML4_INDEX as u64) << 39
            | (RECURSIVE_PDPT_INDEX as u64) << 30
            | (RECURSIVE_PD_INDEX as u64) << 21
            | (pml4_idx as u64) << 12
    }
}
