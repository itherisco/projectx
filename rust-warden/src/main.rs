//! Rust Warden Type-1 Hypervisor - Main Entry Point
//!
//! This is the core of the Warden hypervisor, a Type-1 bare-metal hypervisor
//! designed for the Julia Digital Brain cognitive system.
//!
//! # Architecture
//!
//! The hypervisor runs at Ring -1 (hypervisor privilege level) and provides:
//! - Hardware virtualization (Intel VT-x / AMD SVM)
//! - Memory isolation via EPT/NPT
//! - Secure IPC via shared memory ring buffer
//! - TPM 2.0 measured boot
//! - Hardware watchdog protection

#![no_std]
#![no_main]
#![feature(asm, const_fn, core_intrinsics)]
#![allow(unused)]

extern crate baremetal;
extern crate spin;
extern crate x86_64;

// Re-export core modules
mod ept;
mod guest;
mod ipc;
mod memory;
mod svm;
mod tpm;
mod vmx;
mod watchdog;

use core::hint;
use core::panic::PanicInfo;

// Use spin for synchronization
use spin::Mutex;

// Import hypervisor components
use ept::EptManager;
use memory::MemoryManager;
use vmx::{VmxCapabilities, VmxManager};
use svm::SvmCapabilities;
use ipc::ring_buffer::RingBuffer;
use tpm::TpmManager;
use watchdog::Watchdog;
use guest::JuliaGuest;

// ============================================================================
// CONSTANTS
// ============================================================================

/// Warden magic number
pub const WARDEN_MAGIC: u32 = 0x57415244; // "WARD"

/// VMXON region alignment (4KB)
pub const VMXON_ALIGN: u64 = 0x1000;

/// VMCS region alignment (4KB)
pub const VMCS_ALIGN: u64 = 0x1000;

/// Page size (4KB)
pub const PAGE_SIZE: u64 = 0x1000;

/// Warden memory regions
pub mod memory_regions {
    /// Warden code and data space
    pub const WARDEN_SPACE_START: u64 = 0x0000_0000;
    pub const WARDEN_SPACE_END: u64 = 0x00FF_FFFF;

    /// IPC Ring Buffer (64MB)
    pub const IPC_RING_BUFFER_START: u64 = 0x0100_0000;
    pub const IPC_RING_BUFFER_SIZE: u64 = 0x0400_0000;

    /// Julia Guest Physical Memory
    pub const GUEST_PHYS_START: u64 = 0x1000_0000;
    pub const GUEST_PHYS_SIZE: u64 = 0x1000_0000; // 256MB
}

// ============================================================================
// ERROR TYPES
// ============================================================================

/// Hypervisor initialization errors
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HypervisorError {
    /// No virtualization support
    NoVirtualizationSupport,
    /// VMX not supported
    NoVmxSupport,
    /// SVM not supported
    NoSvmSupport,
    /// EPT not supported
    NoEptSupport,
    /// NPT not supported
    NoNptSupport,
    /// Memory allocation failed
    OutOfMemory,
    /// VMXON failed
    VmxonFailed,
    /// VMXOFF failed
    VmxoffFailed,
    /// VMCS operation failed
    VmcsOperationFailed,
    /// VM launch failed
    VmLaunchFailed,
    /// VM resume failed
    VmResumeFailed,
    /// EPT configuration error
    EptError,
    /// TPM initialization failed
    TpmError,
    /// Watchdog error
    WatchdogError,
    /// Invalid CPU state
    InvalidCpuState,
    /// Guest execution error
    GuestError,
}

impl core::fmt::Display for HypervisorError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            HypervisorError::NoVirtualizationSupport => write!(f, "No hardware virtualization support"),
            HypervisorError::NoVmxSupport => write!(f, "Intel VT-x not supported"),
            HypervisorError::NoSvmSupport => write!(f, "AMD SVM not supported"),
            HypervisorError::NoEptSupport => write!(f, "Intel EPT not supported"),
            HypervisorError::NoNptSupport => write!(f, "AMD NPT not supported"),
            HypervisorError::OutOfMemory => write!(f, "Out of memory"),
            HypervisorError::VmxonFailed => write!(f, "VMXON failed"),
            HypervisorError::VmxoffFailed => write!(f, "VMXOFF failed"),
            HypervisorError::VmcsOperationFailed => write!(f, "VMCS operation failed"),
            HypervisorError::VmLaunchFailed => write!(f, "VM launch failed"),
            HypervisorError::VmResumeFailed => write!(f, "VM resume failed"),
            HypervisorError::EptError => write!(f, "EPT configuration error"),
            HypervisorError::TpmError => write!(f, "TPM initialization error"),
            HypervisorError::WatchdogError => write!(f, "Watchdog error"),
            HypervisorError::InvalidCpuState => write!(f, "Invalid CPU state"),
            HypervisorError::GuestError => write!(f, "Guest execution error"),
        }
    }
}

// ============================================================================
// HYPERVISOR STATE
// ============================================================================

/// CPU vendor identification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CpuVendor {
    Intel,
    AMD,
    Unknown,
}

/// Hardware virtualization capabilities
#[derive(Debug, Clone, Copy)]
pub struct HypervisorCapabilities {
    /// Intel VT-x available
    pub has_vtx: bool,
    /// Intel EPT available
    pub has_ept: bool,
    /// Intel UGLA available
    pub has_uglobal: bool,
    /// AMD SVM available
    pub has_svm: bool,
    /// AMD NPT available
    pub has_npt: bool,
    /// PAT available
    pub has_pat: bool,
    /// PGE available
    pub has_pge: bool,
    /// CPU vendor
    pub cpuid_vendor: CpuVendor,
}

impl Default for HypervisorCapabilities {
    fn default() -> Self {
        Self {
            has_vtx: false,
            has_ept: false,
            has_uglobal: false,
            has_svm: false,
            has_npt: false,
            has_pat: false,
            has_pge: true,
            cpuid_vendor: CpuVendor::Unknown,
        }
    }
}

/// Warden hypervisor state
pub struct WardenState {
    /// Hypervisor capabilities
    pub capabilities: HypervisorCapabilities,
    /// Memory manager
    pub memory: Option<MemoryManager>,
    /// EPT manager (Intel)
    pub ept: Option<EptManager>,
    /// VMX manager (Intel)
    pub vmx: Option<VmxManager>,
    /// SVM manager (AMD)
    pub svm: Option<svm::SvmManager>,
    /// IPC ring buffer
    pub ipc: Option<&'static mut RingBuffer>,
    /// TPM manager
    pub tpm: Option<TpmManager>,
    /// Watchdog timer
    pub watchdog: Option<Watchdog>,
    /// Julia guest
    pub guest: Option<JuliaGuest>,
    /// Running state
    pub running: bool,
}

impl WardenState {
    /// Create new warden state
    pub fn new() -> Self {
        Self {
            capabilities: HypervisorCapabilities::default(),
            memory: None,
            ept: None,
            vmx: None,
            svm: None,
            ipc: None,
            tpm: None,
            watchdog: None,
            guest: None,
            running: false,
        }
    }
}

// Global warden state
static WARDEN_STATE: Mutex<WardenState> = Mutex::new(WardenState::new());

// ============================================================================
// CPU DETECTION
// ============================================================================

/// Detect CPU virtualization capabilities
fn detect_capabilities() -> HypervisorCapabilities {
    use x86_64::instructions::cpuid::CpuId;

    let cpuid = CpuId::new();
    let mut caps = HypervisorCapabilities::default();

    // Get vendor string
    if let Some(vendor_info) = cpuid.get_vendor_info() {
        let vendor = vendor_info.as_str();
        match vendor {
            "GenuineIntel" => caps.cpuid_vendor = CpuVendor::Intel,
            "AuthenticAMD" => caps.cpuid_vendor = CpuVendor::AMD,
            _ => caps.cpuid_vendor = CpuVendor::Unknown,
        }
    }

    // Check Intel VT-x
    if let Some(virt_info) = cpuid.get_virtualization_info() {
        caps.has_vtx = virt_info.has_vmx();
        caps.has_ept = virt_info.has_ept();
        caps.has_uglobal = virt_info.has_ugla();
    }

    // Check AMD SVM
    if let Some(ext_info) = cpuid.get_extended_processor_info() {
        caps.has_svm = ext_info.has_svm();
        caps.has_npt = ext_info.has_npt();
    }

    // Check PAT support (via CR4)
    caps.has_pat = true; // PAT is always supported on x86_64

    caps
}

// ============================================================================
// INITIALIZATION
// ============================================================================

/// Initialize the hypervisor
fn init_hypervisor() -> Result<(), HypervisorError> {
    // Step 1: Detect CPU capabilities
    let caps = detect_capabilities();
    println!("[WARDEN] CPU Vendor: {:?}", caps.cpuid_vendor);
    println!("[WARDEN] VT-x: {}, EPT: {}", caps.has_vtx, caps.has_ept);
    println!("[WARDEN] SVM: {}, NPT: {}", caps.has_svm, caps.has_npt);

    // Check for minimum requirements
    if !caps.has_vtx && !caps.has_svm {
        return Err(HypervisorError::NoVirtualizationSupport);
    }

    // Update global state
    let mut state = WARDEN_STATE.lock();
    state.capabilities = caps;

    // Step 2: Initialize memory manager
    println!("[WARDEN] Initializing memory manager...");
    let mem = MemoryManager::new();
    state.memory = Some(mem);

    // Step 3: Initialize appropriate virtualization technology
    match state.capabilities.cpuid_vendor {
        CpuVendor::Intel => {
            if !state.capabilities.has_vtx {
                return Err(HypervisorError::NoVmxSupport);
            }
            if !state.capabilities.has_ept {
                return Err(HypervisorError::NoEptSupport);
            }

            println!("[WARDEN] Initializing Intel VT-x...");
            
            // Initialize VMX
            let vmx = VmxManager::new()?;
            state.vmx = Some(vmx);

            // Initialize EPT
            println!("[WARDEN] Initializing EPT...");
            let ept = EptManager::new(
                memory_regions::GUEST_PHYS_START,
                memory_regions::GUEST_PHYS_SIZE,
            )?;
            state.ept = Some(ept);
        }
        CpuVendor::AMD => {
            if !state.capabilities.has_svm {
                return Err(HypervisorError::NoSvmSupport);
            }
            if !state.capabilities.has_npt {
                return Err(HypervisorError::NoNptSupport);
            }

            println!("[WARDEN] Initializing AMD SVM...");
            
            // Initialize SVM
            let svm = svm::SvmManager::new()?;
            state.svm = Some(svm);
        }
        _ => {
            return Err(HypervisorError::NoVirtualizationSupport);
        }
    }

    // Step 4: Initialize IPC ring buffer
    println!("[WARDEN] Initializing IPC ring buffer...");
    let ipc = RingBuffer::new(
        memory_regions::IPC_RING_BUFFER_START,
        memory_regions::IPC_RING_BUFFER_SIZE as usize,
    ).map_err(|_| HypervisorError::OutOfMemory)?;
    state.ipc = Some(ipc);

    // Step 5: Initialize TPM (optional - continue if not available)
    println!("[WARDEN] Initializing TPM 2.0...");
    match TpmManager::new() {
        Ok(tpm) => {
            state.tpm = Some(tpm);
        }
        Err(e) => {
            println!("[WARDEN] TPM not available: {:?}, continuing without TPM", e);
        }
    }

    // Step 6: Initialize watchdog
    println!("[WARDEN] Initializing watchdog timer...");
    match Watchdog::new(500) { // 500ms timeout
        Ok(wdt) => {
            state.watchdog = Some(wdt);
        }
        Err(e) => {
            println!("[WARDEN] Watchdog not available: {:?}, continuing without WDT", e);
        }
    }

    // Step 7: Initialize Julia guest
    println!("[WARDEN] Creating Julia guest configuration...");
    let guest = JuliaGuest::new(
        memory_regions::GUEST_PHYS_START,
        memory_regions::GUEST_PHYS_SIZE,
    );
    state.guest = Some(guest);

    Ok(())
}

/// Launch the Julia guest VM
fn launch_guest() -> Result<(), HypervisorError> {
    let mut state = WARDEN_STATE.lock();

    // Configure and launch VM
    match state.capabilities.cpuid_vendor {
        CpuVendor::Intel => {
            if let Some(vmx) = &mut state.vmx {
                if let Some(ept) = &mut state.ept {
                    println!("[WARDEN] Launching Julia guest (Intel VT-x)...");
                    vmx.launch_guest(ept)?;
                }
            }
        }
        CpuVendor::AMD => {
            if let Some(svm) = &mut state.svm {
                println!("[WARDEN] Launching Julia guest (AMD SVM)...");
                svm.launch_guest()?;
            }
        }
        _ => {
            return Err(HypervisorError::NoVirtualizationSupport);
        }
    }

    state.running = true;
    Ok(())
}

// ============================================================================
// MAIN SUPERVISORY LOOP
// ============================================================================

/// Main supervisory loop - runs after guest launch
fn supervisory_loop() -> ! {
    println!("[WARDEN] Entering supervisory loop...");

    loop {
        // Check watchdog
        let state = WARDEN_STATE.lock();
        
        if let Some(wdt) = &state.watchdog {
            // Kick watchdog
            let _ = wdt.kick();
        }

        // Check IPC for messages
        if let Some(ipc) = &state.ipc {
            // Process any pending IPC messages
            while let Some(msg) = ipc.try_read() {
                // Process message from Julia guest
                process_ipc_message(msg);
            }
        }

        // Small delay to prevent busy-waiting
        // In real implementation, this would be an interrupt-driven event
        for _ in 0..1000 {
            hint::spin_loop();
        }
    }
}

/// Process IPC message from Julia guest
fn process_ipc_message(msg: ipc::ring_buffer::IpcMessage) {
    // Handle different message types
    match msg.header.msg_type {
        // Heartbeat from Julia
        0x0001 => {
            // Record heartbeat for watchdog
            // This is handled by the watchdog subsystem
        }
        // State query
        0x0002 => {
            // Respond to state queries
        }
        // Memory request
        0x0003 => {
            // Handle memory requests
        }
        // Control message
        0x0004 => {
            // Handle control messages
        }
        _ => {
            // Unknown message type
        }
    }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

/// Boot entry point
#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Initialize serial console for debugging
    init_serial();

    println!("=================================================");
    println!("  Rust Warden Type-1 Hypervisor v1.0.0");
    println!("  Secure Foundation for Julia Digital Brain");
    println!("=================================================");
    println!();

    // Initialize hypervisor
    match init_hypervisor() {
        Ok(()) => {
            println!("[WARDEN] Hypervisor initialized successfully");
        }
        Err(e) => {
            println!("[WARDEN] Failed to initialize hypervisor: {:?}", e);
            // In fail-closed mode, we halt on error
            halt();
        }
    }

    // Launch Julia guest
    match launch_guest() {
        Ok(()) => {
            println!("[WARDEN] Julia guest launched successfully");
        }
        Err(e) => {
            println!("[WARDEN] Failed to launch guest: {:?}", e);
            // In fail-closed mode, we halt on error
            halt();
        }
    }

    // Enter main supervisory loop
    supervisory_loop();
}

/// Initialize serial console for debugging
fn init_serial() {
    // Simple serial port initialization (COM1)
    // In real implementation, this would use x86_64::instructions::port
}

/// Halt the system
fn halt() -> ! {
    loop {
        x86_64::instructions::hlt();
    }
}

// ============================================================================
// PANIC HANDLER
// ============================================================================

/// Panic handler
#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    println!("[PANIC] Warden hypervisor panicked!");
    if let Some(location) = info.location() {
        println!("[PANIC] Location: {}:{}:{}",
            location.file(),
            location.line(),
            location.column()
        );
    }
    if let Some(message) = info.message() {
        println!("[PANIC] Message: {:?}", message);
    }

    // In fail-closed mode, we halt on panic
    halt();
}

// ============================================================================
// STACK DEFINITION
// ============================================================================

// Stack for the hypervisor
#[no_mangle]
static _stack: [u8; 65536] = [0; 65536];

#[no_mangle]
static _stack_start: u64 = _stack.as_ptr() as u64 + 65536;
