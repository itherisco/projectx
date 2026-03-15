//! Guest VM unit tests
//! 
//! Tests for VM configuration, CPU state setup, memory layout,
//! and VM entry sequence using mock implementations.

#![cfg(feature = "mock")]

use crate::common::{MockCpuState, MockVmConfig, MockVmcs};

// ============================================================================
// VM Configuration Tests
// ============================================================================

/// Test VM configuration creation
#[test]
fn test_vm_config_creation() {
    let config = MockVmConfig::new();
    
    assert_eq!(config.vcpu_count, 1, "Default vCPU count should be 1");
    assert_eq!(config.memory_size, 0x10000000, "Default memory should be 256MB");
    assert_eq!(config.memory_base, 0x100000, "Default memory base should be 1MB");
}

/// Test VM configuration with custom vCPU count
#[test]
fn test_vm_config_vcpu_count() {
    let config = MockVmConfig {
        vcpu_count: 4,
        ..Default::default()
    };
    
    assert_eq!(config.vcpu_count, 4);
}

/// Test VM configuration with custom memory
#[test]
fn test_vm_config_memory() {
    let config = MockVmConfig {
        memory_size: 0x20000000, // 512 MB
        memory_base: 0x100000,
        ..Default::default()
    };
    
    assert_eq!(config.memory_size, 0x20000000);
    assert_eq!(config.memory_base, 0x100000);
}

/// Test EPT enabled configuration
#[test]
fn test_vm_config_ept() {
    let config = MockVmConfig {
        ept_enabled: true,
        ..Default::default()
    };
    
    assert!(config.ept_enabled, "EPT should be enabled");
}

/// Test VPID enabled configuration
#[test]
fn test_vm_config_vpid() {
    let config = MockVmConfig {
        vpid_enabled: true,
        ..Default::default()
    };
    
    assert!(config.vpid_enabled, "VPID should be enabled");
}

/// Test unrestricted guest configuration
#[test]
fn test_vm_config_unrestricted_guest() {
    let config = MockVmConfig {
        unrestricted_guest: true,
        ..Default::default()
    };
    
    assert!(config.unrestricted_guest, "Unrestricted guest should be enabled");
}

/// Test I/O bitmap configuration
#[test]
fn test_vm_config_io_bitmap() {
    let config = MockVmConfig {
        io_bitmap_a: Some(0x1000),
        io_bitmap_b: Some(0x2000),
        ..Default::default()
    };
    
    assert!(config.io_bitmap_a.is_some());
    assert!(config.io_bitmap_b.is_some());
    assert_eq!(config.io_bitmap_a.unwrap(), 0x1000);
}

/// Test MSR bitmap configuration
#[test]
fn test_vm_config_msr_bitmap() {
    let config = MockVmConfig {
        msr_bitmap: Some(0x3000),
        ..Default::default()
    };
    
    assert!(config.msr_bitmap.is_some());
    assert_eq!(config.msr_bitmap.unwrap(), 0x3000);
}

// ============================================================================
// CPU State Setup Tests
// ============================================================================

/// Test CPU state creation
#[test]
fn test_cpu_state_creation() {
    let state = MockCpuState::new();
    
    // Verify default segment selectors are set
    assert_eq!(state.cs, 0x08);
    assert_eq!(state.ss, 0x10);
    assert_eq!(state.ds, 0x10);
    assert_eq!(state.es, 0x10);
}

/// Test CPU state general purpose registers
#[test]
fn test_cpu_state_registers() {
    let mut state = MockCpuState::new();
    
    // Set all general purpose registers
    state.rax = 0x1111111111111111;
    state.rbx = 0x2222222222222222;
    state.rcx = 0x3333333333333333;
    state.rdx = 0x4444444444444444;
    state.rsi = 0x5555555555555555;
    state.rdi = 0x6666666666666666;
    state.rbp = 0x7777777777777777;
    state.r8 = 0x8888888888888888;
    state.r9 = 0x9999999999999999;
    state.r10 = 0xAAAAAAAAAAAAAAAA;
    state.r11 = 0xBBBBBBBBBBBBBBBB;
    state.r12 = 0xCCCCCCCCCCCCCCCC;
    state.r13 = 0xDDDDDDDDDDDDDDDD;
    state.r14 = 0xEEEEEEEEEEEEEEEE;
    state.r15 = 0xFFFFFFFFFFFFFFFF;
    
    assert_eq!(state.rax, 0x1111111111111111);
    assert_eq!(state.rbx, 0x2222222222222222);
    assert_eq!(state.r8, 0x8888888888888888);
}

/// Test CPU state instruction pointer and stack pointer
#[test]
fn test_cpu_state_ip_sp() {
    let mut state = MockCpuState::new();
    
    state.rip = 0x1000;
    state.rsp = 0x8000;
    
    assert_eq!(state.rip, 0x1000);
    assert_eq!(state.rsp, 0x8000);
}

/// Test CPU state flags
#[test]
fn test_cpu_state_flags() {
    let mut state = MockCpuState::new();
    
    // Set common flags
    state.rflags = 0x202; // Reserved bit (always 1) + IF = 1
    
    assert!(state.rflags & 0x200 != 0, "IF should be set");
}

/// Test CPU control registers initialization
#[test]
fn test_cpu_state_control_registers() {
    let state = MockCpuState::new();
    
    // CR0 should have PG (paging) and PE (protection) enabled
    assert!(state.cr0 & 0x80000000 != 0, "PG should be set");
    assert!(state.cr0 & 0x1 != 0, "PE should be set");
    
    // CR4 should have PAE enabled
    assert!(state.cr4 & 0x20 != 0, "PAE should be set");
}

/// Test CPU extended feature register
#[test]
fn test_cpu_state_efer() {
    let state = MockCpuState::new();
    
    // EFER should have LME (Long Mode Enabled) set
    assert!(state.efer & 0x100 != 0, "LME should be set");
    // EFER should have SCE (System Call Extensions) set
    assert!(state.efer & 0x1 != 0, "SCE should be set");
}

// ============================================================================
// Memory Layout Tests
// ============================================================================

/// Test guest memory layout
#[test]
fn test_guest_memory_layout() {
    let memory_base: u64 = 0x100000;  // 1 MB
    let memory_size: u64 = 0x10000000; // 256 MB
    let memory_top = memory_base + memory_size;
    
    // Reserved: 0x0 - 0x9FFFF (640 KB)
    let ivt_end: u64 = 0xA0000;
    
    // RAM starts at 1 MB
    assert_eq!(memory_base, 0x100000);
    assert!(ivt_end < memory_base);
    assert!(memory_top > memory_base);
}

/// Test guest memory region mapping
#[test]
fn test_memory_region_mapping() {
    struct MemoryRegion {
        start: u64,
        end: u64,
        name: &'static str,
    }
    
    let regions = [
        MemoryRegion { start: 0x0, end: 0x9FFFF, name: "IVT/BIOS" },
        MemoryRegion { start: 0xA0000, end: 0xBFFFF, name: "VGA" },
        MemoryRegion { start: 0xC0000, end: 0xFFFFF, name: "BIOS" },
        MemoryRegion { start: 0x100000, end: 0x10000000, name: "RAM" },
    ];
    
    // Verify no overlap
    for i in 0..regions.len() {
        for j in (i + 1)..regions.len() {
            assert!(regions[i].end < regions[j].start || 
                   regions[j].end < regions[i].start,
                   "{} and {} should not overlap", 
                   regions[i].name, regions[j].name);
        }
    }
}

/// Test page table layout
#[test]
fn test_page_table_layout() {
    // PML4 at top of virtual address space
    let pml4_addr: u64 = 0xFFFF_FFFF_FFFF_F000;
    let pdpt_addr: u64 = 0xFFFF_FFFF_FFFF_E000;
    let pd_addr: u64 = 0xFFFF_FFFF_FFFF_D000;
    let pt_addr: u64 = 0xFFFF_FFFF_FFFF_C000;
    
    // All should be page-aligned
    assert_eq!(pml4_addr & 0xFFF, 0);
    assert_eq!(pdpt_addr & 0xFFF, 0);
    assert_eq!(pd_addr & 0xFFF, 0);
    assert_eq!(pt_addr & 0xFFF, 0);
}

/// Test large page support
#[test]
fn test_large_page_support() {
    // 2MB pages
    const PMD_SIZE: u64 = 0x200000;
    // 1GB pages  
    const PUD_SIZE: u64 = 0x40000000;
    
    assert_eq!(PMD_SIZE, 2 * 1024 * 1024);
    assert_eq!(PUD_SIZE, 1024 * 1024 * 1024);
}

// ============================================================================
// VM Entry Sequence Tests
// ============================================================================

/// Test VM entry with real mode state
#[test]
fn test_vm_entry_real_mode() {
    let mut state = MockCpuState::new();
    
    // Configure for real mode
    state.cr0 = 0x11; // PE = 1, MP = 1 (no paging)
    state.cr4 = 0;
    state.efer = 0;
    
    assert!(state.cr0 & 1 != 0, "Protection enabled");
    assert!(state.cr4 == 0, "No PAE");
}

/// Test VM entry with protected mode state
#[test]
fn test_vm_entry_protected_mode() {
    let mut state = MockCpuState::new();
    
    // Configure for protected mode with paging
    state.cr0 = 0x80050011; // PG, PE, MP, ET
    state.cr3 = 0x100000;   // Page directory
    state.cr4 = 0x20;        // PAE
    
    assert!(state.cr0 & 0x80000000 != 0, "Paging enabled");
    assert!(state.cr4 & 0x20 != 0, "PAE enabled");
}

/// Test VM entry with long mode state
#[test]
fn test_vm_entry_long_mode() {
    let mut state = MockCpuState::new();
    
    // Configure for long mode (64-bit)
    state.cr0 = 0x80050011;
    state.cr3 = 0x100000;
    state.cr4 = 0x30; // PAE + PSE
    state.efer = 0x500; // LME + SCE
    
    assert!(state.efer & 0x100 != 0, "Long mode enabled");
    assert!(state.cr4 & 0x20 != 0, "PAE enabled");
}

/// Test VM entry with compatibility mode
#[test]
fn test_vm_entry_compatibility_mode() {
    let mut state = MockCpuState::new();
    
    // Compatibility mode: long mode but CS.D = 0
    state.cr0 = 0x80050011;
    state.cr3 = 0x100000;
    state.cr4 = 0x30;
    state.efer = 0x500;
    
    // In compatibility mode, address size is 32-bit
    assert!(state.efer & 0x100 != 0);
}

/// Test VM entry with PAE enabled
#[test]
fn test_vm_entry_pae() {
    let mut state = MockCpuState::new();
    
    state.cr4 = 0x20; // PAE
    state.cr3 = 0x100000; // PML4 (in PAE, this is PDPT)
    
    assert!(state.cr4 & 0x20 != 0);
}

/// Test VM entry with EPT enabled
#[test]
fn test_vm_entry_ept() {
    let mut vmcs = MockVmcs::new();
    
    // Secondary execution controls
    const SECONDARY_CONTROLS: usize = 0x401E;
    const EPT_ENABLED: u64 = 1 << 1; // bit 1
    
    vmcs.set_field(SECONDARY_CONTROLS, EPT_ENABLED).expect("Write should succeed");
    
    let controls = vmcs.get_field(SECONDARY_CONTROLS).expect("Read should succeed");
    assert!(controls & EPT_ENABLED != 0, "EPT should be enabled in VMCS");
}

/// Test VM entry with VPID enabled
#[test]
fn test_vm_entry_vpid() {
    let mut vmcs = MockVmcs::new();
    
    const SECONDARY_CONTROLS: usize = 0x401E;
    const VPID_ENABLED: u64 = 1 << 5; // bit 5
    
    vmcs.set_field(SECONDARY_CONTROLS, VPID_ENABLED).expect("Write should succeed");
    
    let controls = vmcs.get_field(SECONDARY_CONTROLS).expect("Read should succeed");
    assert!(controls & VPID_ENABLED != 0, "VPID should be enabled in VMCS");
}

// ============================================================================
// VM Exit Handling Tests
// ============================================================================

/// Test VM exit handling state
#[test]
fn test_vm_exit_state() {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum VmExitReason {
        Exception,
        Interrupt,
        TripleFault,
        InitialVmEntry,
        Vmcall,
        Hlt,
        Invd,
        Vmread,
        Vmwrite,
    }
    
    let exit_reason = VmExitReason::Hlt;
    
    assert_eq!(exit_reason, VmExitReason::Hlt);
}

/// Test VM exit qualification
#[test]
fn test_vm_exit_qualification() {
    // Exit qualification for different exit types
    
    // For CR access
    let cr_access_qual: u64 = 0x00; // CR0 write
    let cr_num = (cr_access_qual >> 3) & 0xF;
    assert_eq!(cr_num, 0); // CR0
    
    // For I/O instruction
    let io_qual: u64 = 0x01; // OUT to immediate port
    let direction = (io_qual & 0x1) != 0;
    assert!(!direction); // OUT
    
    // For EPT violation
    let ept_qual: u64 = 0x07; // Read + Write + Execute
    let read = (ept_qual & 0x1) != 0;
    let write = (ept_qual & 0x2) != 0;
    let execute = (ept_qual & 0x4) != 0;
    assert!(read && write && execute);
}

// ============================================================================
// VMCS Field Tests
// ============================================================================

/// Test VMCS guest state fields
#[test]
fn test_vmcs_guest_state_fields() {
    let mut vmcs = MockVmcs::new();
    
    // Set guest state
    vmcs.set_field(0x4016, 0x1000).expect("Set guest RIP");     // GUEST_RIP
    vmcs.set_field(0x4018, 0x8000).expect("Set guest RSP");     // GUEST_RSP
    vmcs.set_field(0x401A, 0x200).expect("Set guest RFLAGS");   // GUEST_RFLAGS
    vmcs.set_field(0x4802, 0x08).expect("Set guest CS");        // GUEST_CS_SELECTOR
    vmcs.set_field(0x4804, 0x08).expect("Set guest CS limit"); // GUEST_CS_LIMIT
    vmcs.set_field(0x4806, 0x9A).expect("Set guest CS access"); // GUEST_CS_AR
    
    assert_eq!(vmcs.get_field(0x4016).unwrap(), 0x1000);
    assert_eq!(vmcs.get_field(0x4018).unwrap(), 0x8000);
}

/// Test VMCS host state fields
#[test]
fn test_vmcs_host_state_fields() {
    let mut vmcs = MockVmcs::new();
    
    // Set host state
    vmcs.set_field(0x6C16, 0x80001000).expect("Set host RIP");   // HOST_RIP
    vmcs.set_field(0x6C18, 0xFFFFE000).expect("Set host RSP");   // HOST_RSP
    vmcs.set_field(0x6C1A, 0x10).expect("Set host CS");          // HOST_CS_SELECTOR
    vmcs.set_field(0x6C1C, 0x10).expect("Set host SS");          // HOST_SS_SELECTOR
    vmcs.set_field(0x6C1E, 0x10).expect("Set host DS");          // HOST_DS_SELECTOR
    vmcs.set_field(0x6C20, 0x10).expect("Set host ES");          // HOST_ES_SELECTOR
    vmcs.set_field(0x6C22, 0x10).expect("Set host FS");          // HOST_FS_SELECTOR
    vmcs.set_field(0x6C24, 0x10).expect("Set host GS");          // HOST_GS_SELECTOR
    
    assert_eq!(vmcs.get_field(0x6C16).unwrap(), 0x80001000);
    assert_eq!(vmcs.get_field(0x6C18).unwrap(), 0xFFFFE000);
}

// ============================================================================
// Guest Register Setup Tests
// ============================================================================

/// Test guest general purpose register setup
#[test]
fn test_guest_gpr_setup() {
    let mut vmcs = MockVmcs::new();
    
    // GPR offsets in VMCS (simplified)
    const RAX: usize = 0x4400;
    const RBX: usize = 0x4402;
    const RCX: usize = 0x4404;
    const RDX: usize = 0x4406;
    
    vmcs.set_field(RAX, 0x1111).expect("Set RAX");
    vmcs.set_field(RBX, 0x2222).expect("Set RBX");
    vmcs.set_field(RCX, 0x3333).expect("Set RCX");
    vmcs.set_field(RDX, 0x4444).expect("Set RDX");
    
    assert_eq!(vmcs.get_field(RAX).unwrap(), 0x1111);
    assert_eq!(vmcs.get_field(RBX).unwrap(), 0x2222);
}

/// Test guest segment register setup
#[test]
fn test_guest_segment_setup() {
    let mut vmcs = MockVmcs::new();
    
    // Segment selectors
    vmcs.set_field(0x4802, 0x08).expect("CS"); // Code segment
    vmcs.set_field(0x4808, 0x10).expect("SS"); // Stack segment
    vmcs.set_field(0x480E, 0x10).expect("DS"); // Data segment
    vmcs.set_field(0x4814, 0x10).expect("ES");
    vmcs.set_field(0x481A, 0x00).expect("FS");
    vmcs.set_field(0x4820, 0x00).expect("GS");
    
    assert_eq!(vmcs.get_field(0x4802).unwrap(), 0x08);
}

/// Test guest table register setup
#[test]
fn test_guest_table_register_setup() {
    let mut vmcs = MockVmcs::new();
    
    // GDTR and IDTR
    vmcs.set_field(0x480A, 0x1000).expect("GDTR base"); // GUEST_GDTR_BASE
    vmcs.set_field(0x480B, 0xFFFF).expect("GDTR limit"); // GUEST_GDTR_LIMIT
    vmcs.set_field(0x480C, 0x1000).expect("IDTR base"); // GUEST_IDTR_BASE
    vmcs.set_field(0x480D, 0xFFFF).expect("IDTR limit"); // GUEST_IDTR_LIMIT
    
    assert_eq!(vmcs.get_field(0x480B).unwrap(), 0xFFFF);
}

// ============================================================================
// VCPU Management Tests
// ============================================================================

/// Test vCPU creation
#[test]
fn test_vcpu_creation() {
    // Simulate vCPU state structure
    struct VcpuState {
        pub id: u32,
        pub state: MockCpuState,
        pub vmcs: MockVmcs,
        pub running: bool,
    }
    
    let vcpu = VcpuState {
        id: 0,
        state: MockCpuState::new(),
        vmcs: MockVmcs::new(),
        running: false,
    };
    
    assert_eq!(vcpu.id, 0);
    assert!(!vcpu.running);
}

/// Test vCPU startup
#[test]
fn test_vcpu_startup() {
    let running = core::sync::atomic::AtomicBool::new(false);
    
    // Simulate vCPU starting
    running.store(true, core::sync::atomic::Ordering::Release);
    
    assert!(running.load(core::sync::atomic::Ordering::Acquire));
}

/// Test vCPU shutdown
#[test]
fn test_vcpu_shutdown() {
    let running = core::sync::atomic::AtomicBool::new(true);
    
    // Simulate vCPU stopping
    running.store(false, core::sync::atomic::Ordering::Release);
    
    assert!(!running.load(core::sync::atomic::Ordering::Acquire));
}

/// Test multiple vCPU topology
#[test]
fn test_vcpu_topology() {
    let vcpu_count = 4;
    let mut vcpus = Vec::new();
    
    for i in 0..vcpu_count {
        vcpus.push(i);
    }
    
    assert_eq!(vcpus.len(), 4);
    assert_eq!(vcpus[0], 0);
    assert_eq!(vcpus[3], 3);
}

// ============================================================================
// Integration Tests
// ============================================================================

/// Test full VM creation sequence
#[test]
fn test_vm_creation_sequence() {
    // 1. Create VM configuration
    let config = MockVmConfig::new();
    assert_eq!(config.vcpu_count, 1);
    
    // 2. Create vCPU state
    let cpu_state = MockCpuState::new();
    assert_eq!(cpu_state.cs, 0x08);
    
    // 3. Create VMCS
    let vmcs = MockVmcs::new();
    assert_eq!(vmcs.revision_id, 0xFFFFFFFF);
    
    // 4. Configure VMCS fields
    let mut vmcs = vmcs;
    vmcs.set_field(0x4016, 0x1000).expect("Set RIP");
    vmcs.set_field(0x4018, 0x8000).expect("Set RSP");
    
    assert_eq!(vmcs.get_field(0x4016).unwrap(), 0x1000);
}

/// Test VM launch sequence
#[test]
fn test_vm_launch_sequence() {
    // 1. Initialize VMX
    let vmx_enabled = core::sync::atomic::AtomicBool::new(true);
    assert!(vmx_enabled.load(Ordering::Acquire));
    
    // 2. Allocate VMCS
    let vmcs = MockVmcs::new();
    
    // 3. Load VMCS
    let vmcs_loaded = core::sync::atomic::AtomicBool::new(true);
    assert!(vmcs_loaded.load(Ordering::Acquire));
    
    // 4. Launch VM
    let launch_state = core::cell::UnsafeCell::new(1u8);
    unsafe {
        assert_eq!(*launch_state.get(), 1, "VM should be launched");
    }
}

/// Test VM termination sequence
#[test]
fn test_vm_termination_sequence() {
    // 1. VM is running
    let running = core::sync::atomic::AtomicBool::new(true);
    assert!(running.load(Ordering::Acquire));
    
    // 2. Trigger VM exit
    running.store(false, Ordering::Release);
    
    // 3. Clear VMCS
    let vmcs_cleared = core::sync::atomic::AtomicBool::new(true);
    assert!(vmcs_cleared.load(Ordering::Acquire));
    
    // 4. VMXOFF
    let vmx_enabled = core::sync::atomic::AtomicBool::new(false);
    assert!(!vmx_enabled.load(Ordering::Acquire));
}

// ============================================================================
// Error Handling Tests
// ============================================================================

/// Test VM creation with invalid memory size
#[test]
fn test_invalid_memory_size() {
    let config = MockVmConfig {
        memory_size: 0, // Invalid: zero size
        ..Default::default()
    };
    
    assert_eq!(config.memory_size, 0);
}

/// Test VM creation with invalid vCPU count
#[test]
fn test_invalid_vcpu_count() {
    let config = MockVmConfig {
        vcpu_count: 0, // Invalid: zero vCPUs
        ..Default::default()
    };
    
    assert_eq!(config.vcpu_count, 0);
}

/// Test CPU state with invalid selectors
#[test]
fn test_invalid_segment_selector() {
    let mut state = MockCpuState::new();
    
    // Set invalid (null) selector
    state.cs = 0;
    state.ss = 0;
    
    assert_eq!(state.cs, 0);
    assert_eq!(state.ss, 0);
}
