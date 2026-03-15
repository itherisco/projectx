//! Global Descriptor Table (GDT) Implementation
//!
//! The GDT defines memory segments and their access privileges.
//! In x86-64 protected mode, we need:
//! - Kernel Code Segment (Ring 0)
//! - Kernel Data Segment (Ring 0)
//! - User Code Segment (Ring 3)
//! - User Data Segment (Ring 3)
//! - Task State Segment (TSS) for hardware task switching

use bitflags::bitflags;
use x86_64::structures::gdt::{Descriptor, DescriptorFlags, GlobalDescriptorTable as X86GDT, SegmentSelector};
use x86_64::instructions::tables::{load_tss, DescriptorTablePointer};
use x86_64::PrivilegeLevel;

/// GDT Entry indices
#[derive(Debug, Clone, Copy)]
#[repr(u16)]
pub enum GdtIndex {
    Null = 0,       // Null descriptor (required)
    KernelCode = 1, // Kernel code segment
    KernelData = 2, // Kernel data segment
    UserCode = 3,   // User code segment (Ring 3)
    UserData = 4,   // User data segment (Ring 3)
    Tss = 5,        // Task State Segment
}

/// Access byte flags for GDT entries
#[bitflags]
#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum GdtAccess {
    Accessed = 0x01,
    ReadWrite = 0x02,
    DirectionConforming = 0x04,
    Executable = 0x08,
    UserSegment = 0x10,
    DplRing0 = 0x00,
    DplRing1 = 0x20,
    DplRing2 = 0x40,
    DplRing3 = 0x60,
    Present = 0x80,
}

/// Granularity flags for GDT entries
#[bitflags]
#[repr(u8)]
#[derive(Clone, Copy, Debug)]
pub enum GdtGranularity {
    Available = 0x10,
    LongMode = 0x20,
    Size32 = 0x40,
    PageGranularity = 0x80,
}

/// Task State Segment for hardware context switching
#[repr(align(16), C)]
pub struct TaskStateSegment {
    reserved: u32,
    pub rsp0: u64,
    pub rsp1: u64,
    pub rsp2: u64,
    reserved2: u64,
    pub ist1: u64,
    pub ist2: u64,
    pub ist3: u64,
    pub ist4: u64,
    pub ist5: u64,
    pub ist6: u64,
    pub ist7: u64,
    reserved3: u16,
    pub iopb: u16,
}

impl TaskStateSegment {
    /// Create a new TSS with default values
    pub fn new() -> Self {
        TaskStateSegment {
            reserved: 0,
            rsp0: 0,
            rsp1: 0,
            rsp2: 0,
            reserved2: 0,
            ist1: 0,
            ist2: 0,
            ist3: 0,
            ist4: 0,
            ist5: 0,
            ist6: 0,
            ist7: 0,
            reserved3: 0,
            iopb: 0,
        }
    }
    
    /// Set the kernel stack pointer for Ring 0
    pub fn set_kernel_stack(&mut self, stack_ptr: u64) {
        self.rsp0 = stack_ptr;
    }
}

/// The Global Descriptor Table structure
pub struct Gdt {
    /// The underlying x86_64 GDT
    gdt: X86GDT,
    /// TSS for task switching
    tss: TaskStateSegment,
    /// Kernel code segment selector
    pub kernel_code: SegmentSelector,
    /// Kernel data segment selector
    pub kernel_data: SegmentSelector,
    /// User code segment selector
    pub user_code: SegmentSelector,
    /// User data segment selector
    pub user_data: SegmentSelector,
    /// TSS segment selector
    pub tss_selector: SegmentSelector,
}

impl Gdt {
    /// Create and initialize a new GDT
    pub fn new() -> Self {
        let mut gdt = X86GDT::new();
        let mut tss = TaskStateSegment::new();
        
        // Kernel code segment (Ring 0, 64-bit)
        let kernel_code = gdt.add_entry(Descriptor::kernel_segment(
            DescriptorFlags::PRESENT
                | DescriptorFlags::PRIVILEGE_RING_0
                | DescriptorFlags::EXECUTABLE
                | DescriptorFlags::LONG_MODE,
        ));
        
        // Kernel data segment (Ring 0)
        let kernel_data = gdt.add_entry(Descriptor::kernel_segment(
            DescriptorFlags::PRESENT
                | DescriptorFlags::PRIVILEGE_RING_0
                | DescriptorFlags::READ_WRITE,
        ));
        
        // User code segment (Ring 3, 64-bit)
        let user_code = gdt.add_entry(Descriptor::user_segment(
            DescriptorFlags::PRESENT
                | DescriptorFlags::PRIVILEGE_RING_3
                | DescriptorFlags::EXECUTABLE
                | DescriptorFlags::LONG_MODE,
        ));
        
        // User data segment (Ring 3)
        let user_data = gdt.add_entry(Descriptor::user_segment(
            DescriptorFlags::PRESENT
                | DescriptorFlags::PRIVILEGE_RING_3
                | DescriptorFlags::READ_WRITE,
        ));
        
        // TSS segment
        let tss_selector = gdt.add_entry(Descriptor::tss_segment(&tss));
        
        Gdt {
            gdt,
            tss,
            kernel_code,
            kernel_data,
            user_code,
            user_data,
            tss_selector,
        }
    }
    
    /// Load the GDT into the CPU
    pub fn load(&'static self) {
        // Set up the TSS with a valid kernel stack
        self.tss.set_kernel_stack(0xFFFF_FFFF_FFFF_F000);
        
        // Load the GDT
        let gdtr = DescriptorTablePointer::new(&self.gdt);
        unsafe {
            x86_64::instructions::tables::lgdt(&gdtr);
            
            // Load the CS (code segment) with kernel code selector
            x86_64::instructions::segments::load_ss(self.kernel_data);
            x86_64::instructions::segments::load_ds(self.kernel_data);
            x86_64::instructions::segments::load_es(self.kernel_data);
            x86_64::instructions::segments::load_fs(self.kernel_data);
            x86_64::instructions::segments::load_gs(self.kernel_data);
            
            // Load the TSS
            load_tss(self.tss_selector);
        }
        
        println!("[GDT] Loaded successfully");
    }
    
    /// Get the TSS for modification
    pub fn tss_mut(&mut self) -> &mut TaskStateSegment {
        &mut self.tss
    }
}

/// Initialize the GDT
pub fn init() {
    let gdt = Gdt::new();
    gdt.load();
    println!("[GDT] Global Descriptor Table initialized");
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_gdt_creation() {
        let gdt = Gdt::new();
        // Verify selectors are valid
        assert!(gdt.kernel_code.0 > 0);
        assert!(gdt.kernel_data.0 > 0);
        assert!(gdt.user_code.0 > 0);
        assert!(gdt.user_data.0 > 0);
        assert!(gdt.tss_selector.0 > 0);
    }
    
    #[test]
    fn test_tss_creation() {
        let tss = TaskStateSegment::new();
        // Verify TSS is properly aligned
        let addr = &tss as *const TaskStateSegment as usize;
        assert_eq!(addr % 16, 0, "TSS must be 16-byte aligned");
    }
}
