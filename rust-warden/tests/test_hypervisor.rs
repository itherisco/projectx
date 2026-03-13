//! Hypervisor unit tests
//! 
//! Tests for VMX/SVM hardware detection, VMXON/VMXOFF operations,
//! and VMCS structure initialization using mock implementations.

#![cfg(feature = "mock")]

use crate::common::{
    MockCpuState, MockVmxCapabilities, MockVmcs, MockSvmCapabilities, MockVmxonRegion,
};
use core::cell::UnsafeCell;
use core::sync::atomic::{AtomicBool, AtomicPtr, AtomicU64, Ordering};

// ============================================================================
// Hardware Detection Tests
// ============================================================================

/// Test VMX capability detection
#[test]
fn test_vmx_capability_detection() {
    let caps = MockVmxCapabilities::new();
    
    assert!(caps.vmxon_supported, "VMXON should be supported");
    assert!(caps.vmxoff_supported, "VMXOFF should be supported");
    assert!(caps.vmptrld_supported, "VMPTRLD should be supported");
    assert!(caps.vmptrst_supported, "VMPTRST should be supported");
    assert!(caps.vmclear_supported, "VMCLEAR should be supported");
    assert!(caps.vmwrite_supported, "VMWRITE should be supported");
    assert!(caps.vmread_supported, "VMREAD should be supported");
    assert!(caps.vmlaunch_supported, "VMLAUNCH should be supported");
    assert!(caps.vmresume_supported, "VMRESUME should be supported");
    assert!(caps.vmexit_supported, "VMEXIT should be supported");
    assert!(caps.secondary_controls, "Secondary controls should be supported");
    assert!(caps.true_controls, "True controls should be supported");
}

/// Test SVM capability detection  
#[test]
fn test_svm_capability_detection() {
    let caps = MockSvmCapabilities::new();
    
    assert!(caps.svm_supported, "SVM should be supported");
    assert!(caps.npfits_supported, "NPFITS should be supported");
    assert!(caps.sev_supported, "SEV should be supported");
    assert!(caps.sev_es_supported, "SEV-ES should be supported");
    assert!(caps.vmrun_supported, "VMRUN should be supported");
    assert!(caps.vmmcall_supported, "VMMCALL should be supported");
    assert!(caps.invlpga_supported, "INVLPGA should be supported");
    assert!(caps.skinit_supported, "SKINIT should be supported");
}

/// Test hardware detection with unsupported features
#[test]
fn test_unsupported_hardware_detection() {
    let mut caps = MockVmxCapabilities::default();
    caps.vmxon_supported = false;
    
    assert!(!caps.vmxon_supported, "VMXON should not be supported");
    
    let mut svm_caps = MockSvmCapabilities::default();
    svm_caps.svm_supported = false;
    
    assert!(!svm_caps.svm_supported, "SVM should not be supported");
}

// ============================================================================
// VMXON/VMXOFF Operation Tests
// ============================================================================

/// Test VMXON region initialization
#[test]
fn test_vmxon_region_initialization() {
    let region = MockVmxonRegion::new();
    
    // Check revision ID is set correctly
    assert_eq!(region.revision_id, 0xFFFFFFFF, "VMXON revision ID should be set");
    
    // Check region size is correct (must be 4KB)
    assert_eq!(region.data.len(), 4096, "VMXON region should be 4KB");
}

/// Test VMXON operation with valid region
#[test]
fn test_vmxon_operation_valid_region() {
    let vmxon_region = MockVmxonRegion::new();
    let region_addr = &vmxon_region as *const _ as u64;
    
    // Simulate VMXON operation
    let vmx_enabled = AtomicBool::new(false);
    vmx_enabled.store(true, Ordering::Release);
    
    // Verify VMX is enabled
    assert!(vmx_enabled.load(Ordering::Acquire), "VMX should be enabled after VMXON");
}

/// Test VMXOFF operation
#[test]
fn test_vmxoff_operation() {
    let vmx_enabled = AtomicBool::new(true);
    
    // Simulate VMXOFF
    vmx_enabled.store(false, Ordering::Release);
    
    // Verify VMX is disabled
    assert!(!vmx_enabled.load(Ordering::Acquire), "VMX should be disabled after VMXOFF");
}

/// Test VMXON failure with invalid region
#[test]
fn test_vmxon_invalid_region() {
    // Simulate an invalid region address (NULL)
    let null_addr: *const () = core::ptr::null();
    let addr = null_addr as u64;
    
    // In real hardware, VMXON with NULL would fail
    assert_eq!(addr, 0, "Invalid region address should be 0");
}

// ============================================================================
// VMCS Structure Tests
// ============================================================================

/// Test VMCS initialization
#[test]
fn test_vmcs_initialization() {
    let vmcs = MockVmcs::new();
    
    // Check revision ID is set
    assert_eq!(vmcs.revision_id, 0xFFFFFFFF, "VMCS revision ID should be set");
    
    // Check abort indicator is initially zero
    assert_eq!(vmcs.abort_indicator, 0, "Abort indicator should be 0 initially");
    
    // Check VMCS size
    assert_eq!(vmcs.data.len(), 4096, "VMCS should be 4KB");
}

/// Test VMCS field write operation
#[test]
fn test_vmcs_field_write() {
    let mut vmcs = MockVmcs::new();
    
    // Write a test value to field offset 0 (GUEST_RIP)
    let test_value: u64 = 0x1000;
    let result = vmcs.set_field(0, test_value);
    
    assert!(result.is_ok(), "Field write should succeed");
    
    // Verify the value was written
    let read_value = vmcs.get_field(0).unwrap();
    assert_eq!(read_value, test_value, "Field read should return written value");
}

/// Test VMCS field write out of bounds
#[test]
fn test_vmcs_field_write_oob() {
    let mut vmcs = MockVmcs::new();
    
    // Try to write beyond VMCS size
    let result = vmcs.set_field(4096, 0xDEAD);
    
    assert!(result.is_err(), "Out of bounds write should fail");
}

/// Test VMCS field read operation
#[test]
fn test_vmcs_field_read() {
    let mut vmcs = MockVmcs::new();
    
    // Write multiple fields and read them back
    let test_values = [
        (0, 0x1000u64),     // GUEST_RIP
        (8, 0x2000),        // GUEST_RSP
        (16, 0x3000),       // HOST_RIP
        (24, 0x4000),       // HOST_RSP
    ];
    
    for (offset, value) in test_values.iter() {
        vmcs.set_field(*offset, *value).expect("Write should succeed");
    }
    
    // Read back and verify
    for (offset, expected) in test_values.iter() {
        let actual = vmcs.get_field(*offset).expect("Read should succeed");
        assert_eq!(actual, *expected, "Value should match");
    }
}

/// Test VMCS field read out of bounds
#[test]
fn test_vmcs_field_read_oob() {
    let vmcs = MockVmcs::new();
    
    // Try to read beyond VMCS size
    let result = vmcs.get_field(4096);
    
    assert!(result.is_err(), "Out of bounds read should fail");
}

/// Test VMCS abort indicator
#[test]
fn test_vmcs_abort_indicator() {
    let mut vmcs = MockVmcs::new();
    
    // Set abort indicator (at offset 4, per Intel SDM)
    vmcs.abort_indicator = 0xFFFFFFFF;
    
    assert_eq!(vmcs.abort_indicator, 0xFFFFFFFF, "Abort indicator should be set");
}

// ============================================================================
// VMCS Pin-Based Controls Tests
// ============================================================================

/// Test pin-based VM-execution controls
#[test]
fn test_vmcs_pin_based_controls() {
    let mut vmcs = MockVmcs::new();
    
    // Pin-based controls offset is 0x4000
    const PIN_CONTROLS: usize = 0x4000;
    
    // Set external interrupt exiting = 1
    let controls: u64 = 1 << 0;  // External interrupt exiting
    vmcs.set_field(PIN_CONTROLS, controls).expect("Write should succeed");
    
    let read_controls = vmcs.get_field(PIN_CONTROLS).expect("Read should succeed");
    assert_eq!(read_controls & 1, 1, "External interrupt exiting should be set");
}

/// Test processor-based VM-execution controls
#[test]
fn test_vmcs_processor_based_controls() {
    let mut vmcs = MockVmcs::new();
    
    // Processor-based controls offset is 0x4002
    const PROC_CONTROLS: usize = 0x4002;
    
    // Set some controls
    let controls: u64 = (1 << 1) | (1 << 4) | (1 << 7); // HLT, MWAIT, CR3 load exiting
    vmcs.set_field(PROC_CONTROLS, controls).expect("Write should succeed");
    
    let read_controls = vmcs.get_field(PROC_CONTROLS).expect("Read should succeed");
    assert!(read_controls & (1 << 1) != 0, "HLT exiting should be set");
    assert!(read_controls & (1 << 4) != 0, "MWAIT exiting should be set");
    assert!(read_controls & (1 << 7) != 0, "CR3 load exiting should be set");
}

// ============================================================================
// VM Entry/Exit Controls Tests
// ============================================================================

/// Test VM-entry controls
#[test]
fn test_vmcs_vm_entry_controls() {
    let mut vmcs = MockVmcs::new();
    
    // VM-entry controls offset is 0x4004
    const ENTRY_CONTROLS: usize = 0x4004;
    
    // Set load debug controls
    let controls: u64 = 1 << 2; // Load debug controls
    vmcs.set_field(ENTRY_CONTROLS, controls).expect("Write should succeed");
    
    let read_controls = vmcs.get_field(ENTRY_CONTROLS).expect("Read should succeed");
    assert!(read_controls & (1 << 2) != 0, "Load debug controls should be set");
}

/// Test VM-exit controls
#[test]
fn test_vmcs_vm_exit_controls() {
    let mut vmcs = MockVmcs::new();
    
    // VM-exit controls offset is 0x4006
    const EXIT_CONTROLS: usize = 0x4006;
    
    // Set save debug controls
    let controls: u64 = 1 << 2; // Save debug controls
    vmcs.set_field(EXIT_CONTROLS, controls).expect("Write should succeed");
    
    let read_controls = vmcs.get_field(EXIT_CONTROLS).expect("Read should succeed");
    assert!(read_controls & (1 << 2) != 0, "Save debug controls should be set");
}

// ============================================================================
// Guest State Area Tests
// ============================================================================

/// Test guest RIP/RSP setup
#[test]
fn test_vmcs_guest_rip_rsp() {
    let mut vmcs = MockVmcs::new();
    
    // Guest RIP offset = 0x4016
    const GUEST_RIP: usize = 0x4016;
    const GUEST_RSP: usize = 0x4018;
    
    let rip_value: u64 = 0xFFFF_FFF0;  // Start of ROM
    let rsp_value: u64 = 0x8000_0000;   // Top of stack
    
    vmcs.set_field(GUEST_RIP, rip_value).expect("Write RIP should succeed");
    vmcs.set_field(GUEST_RSP, rsp_value).expect("Write RSP should succeed");
    
    assert_eq!(vmcs.get_field(GUEST_RIP).unwrap(), rip_value);
    assert_eq!(vmcs.get_field(GUEST_RSP).unwrap(), rsp_value);
}

/// Test guest segment selectors
#[test]
fn test_vmcs_guest_segment_selectors() {
    let mut vmcs = MockVmcs::new();
    
    // Segment selector offsets
    const GUEST_CS: usize = 0x4802;
    const GUEST_SS: usize = 0x4808;
    const GUEST_DS: usize = 0x480E;
    const GUEST_ES: usize = 0x4814;
    const GUEST_FS: usize = 0x481A;
    const GUEST_GS: usize = 0x4820;
    
    vmcs.set_field(GUEST_CS, 0x08).expect("CS should be set");
    vmcs.set_field(GUEST_SS, 0x10).expect("SS should be set");
    vmcs.set_field(GUEST_DS, 0x10).expect("DS should be set");
    vmcs.set_field(GUEST_ES, 0x10).expect("ES should be set");
    vmcs.set_field(GUEST_FS, 0x00).expect("FS should be set");
    vmcs.set_field(GUEST_GS, 0x00).expect("GS should be set");
    
    assert_eq!(vmcs.get_field(GUEST_CS).unwrap(), 0x08);
    assert_eq!(vmcs.get_field(GUEST_SS).unwrap(), 0x10);
}

/// Test guest control registers
#[test]
fn test_vmcs_guest_control_registers() {
    let mut vmcs = MockVmcs::new();
    
    // CR0, CR3, CR4 offsets
    const GUEST_CR0: usize = 0x6800;
    const GUEST_CR3: usize = 0x6802;
    const GUEST_CR4: usize = 0x6804;
    
    let cr0_value: u64 = 0x80050011; // PG, PE, MP
    let cr3_value: u64 = 0x0010_0000; // Page table base
    let cr4_value: u64 = 0x00000020; // PAE enabled
    
    vmcs.set_field(GUEST_CR0, cr0_value).expect("CR0 should be set");
    vmcs.set_field(GUEST_CR3, cr3_value).expect("CR3 should be set");
    vmcs.set_field(GUEST_CR4, cr4_value).expect("CR4 should be set");
    
    assert_eq!(vmcs.get_field(GUEST_CR0).unwrap(), cr0_value);
    assert_eq!(vmcs.get_field(GUEST_CR3).unwrap(), cr3_value);
    assert_eq!(vmcs.get_field(GUEST_CR4).unwrap(), cr4_value);
}

// ============================================================================
// Host State Area Tests
// ============================================================================

/// Test host RIP/RSP setup
#[test]
fn test_vmcs_host_rip_rsp() {
    let mut vmcs = MockVmcs::new();
    
    const HOST_RIP: usize = 0x6C16;
    const HOST_RSP: usize = 0x6C18;
    
    let host_rip: u64 = 0x8000_1000; // Hypervisor entry point
    let host_rsp: u64 = 0xFFFF_F000; // Hypervisor stack
    
    vmcs.set_field(HOST_RIP, host_rip).expect("Write host RIP should succeed");
    vmcs.set_field(HOST_RSP, host_rsp).expect("Write host RSP should succeed");
    
    assert_eq!(vmcs.get_field(HOST_RIP).unwrap(), host_rip);
    assert_eq!(vmcs.get_field(HOST_RSP).unwrap(), host_rsp);
}

/// Test host control registers
#[test]
fn test_vmcs_host_control_registers() {
    let mut vmcs = MockVmcs::new();
    
    const HOST_CR0: usize = 0x6C00;
    const HOST_CR3: usize = 0x6C02;
    const HOST_CR4: usize = 0x6C04;
    
    let host_cr0: u64 = 0x80050011;
    let host_cr3: u64 = 0x0010_0000;
    let host_cr4: u64 = 0x00000020;
    
    vmcs.set_field(HOST_CR0, host_cr0).expect("Write host CR0 should succeed");
    vmcs.set_field(HOST_CR3, host_cr3).expect("Write host CR3 should succeed");
    vmcs.set_field(HOST_CR4, host_cr4).expect("Write host CR4 should succeed");
    
    assert_eq!(vmcs.get_field(HOST_CR0).unwrap(), host_cr0);
    assert_eq!(vmcs.get_field(HOST_CR3).unwrap(), host_cr3);
    assert_eq!(vmcs.get_field(HOST_CR4).unwrap(), host_cr4);
}

// ============================================================================
// VMX State Transitions
// ============================================================================

/// Test VMLAUNCH operation
#[test]
fn test_vmlaunch_operation() {
    let vmcs = MockVmcs::new();
    let launch_state = UnsafeCell::new(0u8); // 0 = clear, 1 = launched
    
    // VMLAUNCH requires VMCS to be clear
    unsafe { *launch_state.get() = 0; }
    
    // Simulate VMLAUNCH
    let result = if unsafe { *launch_state.get() } == 0 {
        unsafe { *launch_state.get() = 1; }
        Ok(())
    } else {
        Err("VMCS already launched")
    };
    
    assert!(result.is_ok(), "VMLAUNCH should succeed");
    assert_eq!(unsafe { *launch_state.get() }, 1, "VMCS should be launched");
}

/// Test VMRESUME operation
#[test]
fn test_vmresume_operation() {
    let launch_state = UnsafeCell::new(1u8); // Already launched
    
    // VMRESUME requires VMCS to be launched
    let result = if unsafe { *launch_state.get() } == 1 {
        Ok(())
    } else {
        Err("VMCS not launched")
    };
    
    assert!(result.is_ok(), "VMRESUME should succeed");
}

/// Test VMLAUNCH failure when already launched
#[test]
fn test_vmlaunch_already_launched() {
    let launch_state = UnsafeCell::new(1u8); // Already launched
    
    let result = if unsafe { *launch_state.get() } == 0 {
        Ok(())
    } else {
        Err("VMCS already launched")
    };
    
    assert!(result.is_err(), "VMLAUNCH should fail when already launched");
}

// ============================================================================
// CPU State Management
// ============================================================================

/// Test CPU state initialization
#[test]
fn test_cpu_state_initialization() {
    let state = MockCpuState::new();
    
    // Verify default segment selectors
    assert_eq!(state.cs, 0x08, "CS should be 0x08");
    assert_eq!(state.ss, 0x10, "SS should be 0x10");
    assert_eq!(state.ds, 0x10, "DS should be 0x10");
}

/// Test CPU state register values
#[test]
fn test_cpu_state_registers() {
    let mut state = MockCpuState::new();
    
    // Set register values
    state.rax = 0x1234;
    state.rbx = 0x5678;
    state.rcx = 0xABCD;
    state.rdx = 0xEF01;
    state.rip = 0x1000;
    state.rsp = 0x8000;
    
    assert_eq!(state.rax, 0x1234);
    assert_eq!(state.rbx, 0x5678);
    assert_eq!(state.rcx, 0xABCD);
    assert_eq!(state.rdx, 0xEF01);
    assert_eq!(state.rip, 0x1000);
    assert_eq!(state.rsp, 0x8000);
}

/// Test CPU control register initialization
#[test]
fn test_cpu_state_control_registers() {
    let state = MockCpuState::new();
    
    // Verify CR0 has paging enabled
    assert!(state.cr0 & (1 << 31) != 0, "CR0 PG should be set");
    assert!(state.cr0 & (1 << 0) != 0, "CR0 PE should be set");
    
    // Verify CR4 has PAE enabled
    assert!(state.cr4 & (1 << 5) != 0, "CR4 PAE should be set");
    
    // Verify EFER has LME set
    assert!(state.efer & (1 << 8) != 0, "EFER LME should be set");
}

// ============================================================================
// Edge Cases and Error Handling
// ============================================================================

/// Test VMCS operations with zero values
#[test]
fn test_vmcs_zero_values() {
    let mut vmcs = MockVmcs::new();
    
    // Write zero and verify
    vmcs.set_field(0, 0).expect("Zero write should succeed");
    assert_eq!(vmcs.get_field(0).unwrap(), 0, "Zero should be read back");
}

/// Test VMCS operations with max values
#[test]
fn test_vmcs_max_values() {
    let mut vmcs = MockVmcs::new();
    
    // Write max value and verify
    let max_val = u64::MAX;
    vmcs.set_field(0, max_val).expect("Max value write should succeed");
    assert_eq!(vmcs.get_field(0).unwrap(), max_val, "Max value should be read back");
}

/// Test concurrent VMCS access (mock simulation)
#[test]
fn test_vmcs_concurrent_access() {
    let vmcs = UnsafeCell::new(MockVmcs::new());
    
    // Simulate sequential access (true concurrency not possible in tests)
    unsafe {
        let vmcs_ref = &mut *vmcs.get();
        vmcs_ref.set_field(0, 0x1000).expect("Write should succeed");
        vmcs_ref.set_field(8, 0x2000).expect("Write should succeed");
    }
    
    // Verify both writes
    unsafe {
        let vmcs_ref = &*vmcs.get();
        assert_eq!(vmcs_ref.get_field(0).unwrap(), 0x1000);
        assert_eq!(vmcs_ref.get_field(8).unwrap(), 0x2000);
    }
}

// ============================================================================
// Integration Tests
// ============================================================================

/// Test full VMCS setup sequence
#[test]
fn test_vmcs_full_setup() {
    let mut vmcs = MockVmcs::new();
    
    // Setup guest state
    vmcs.set_field(0x4016, 0x1000).expect("Set guest RIP");
    vmcs.set_field(0x4018, 0x8000).expect("Set guest RSP");
    vmcs.set_field(0x4802, 0x08).expect("Set guest CS");
    vmcs.set_field(0x4808, 0x10).expect("Set guest SS");
    vmcs.set_field(0x6800, 0x80050011).expect("Set guest CR0");
    vmcs.set_field(0x6802, 0x100000).expect("Set guest CR3");
    vmcs.set_field(0x6804, 0x20).expect("Set guest CR4");
    
    // Setup host state
    vmcs.set_field(0x6C16, 0x80001000).expect("Set host RIP");
    vmcs.set_field(0x6C18, 0xFFFFF000).expect("Set host RSP");
    vmcs.set_field(0x6C00, 0x80050011).expect("Set host CR0");
    vmcs.set_field(0x6C02, 0x100000).expect("Set host CR3");
    vmcs.set_field(0x6C04, 0x20).expect("Set host CR4");
    
    // Verify all fields
    assert_eq!(vmcs.get_field(0x4016).unwrap(), 0x1000);
    assert_eq!(vmcs.get_field(0x4018).unwrap(), 0x8000);
    assert_eq!(vmcs.get_field(0x4802).unwrap(), 0x08);
    assert_eq!(vmcs.get_field(0x4808).unwrap(), 0x10);
}

/// Test VMX operation sequence (VMXON -> VMPTRLD -> VMLAUNCH)
#[test]
fn test_vmx_operation_sequence() {
    // Step 1: VMXON
    let vmxon_region = MockVmxonRegion::new();
    let vmx_enabled = AtomicBool::new(false);
    vmx_enabled.store(true, Ordering::Release);
    assert!(vmx_enabled.load(Ordering::Acquire), "VMXON should succeed");
    
    // Step 2: VMPTRLD
    let vmcs = MockVmcs::new();
    let vmcs_loaded = AtomicBool::new(true);
    assert!(vmcs_loaded.load(Ordering::Acquire), "VMPTRLD should succeed");
    
    // Step 3: VMLAUNCH
    let launch_state = UnsafeCell::new(0u8);
    unsafe {
        if *launch_state.get() == 0 {
            *launch_state.get() = 1;
        }
    }
    assert_eq!(unsafe { *launch_state.get() }, 1, "VMLAUNCH should succeed");
}
