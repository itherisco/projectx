//! Intel VT-x Virtual Machine Extensions
//!
//! This module provides the core Intel VT-x virtualization functionality,
//! including VMXON/VMXOFF, VMCS management, and VM entry/exit handling.

use crate::ept::EptManager;
use crate::HypervisorError;

/// VMX Capabilities
#[derive(Debug, Clone, Copy)]
pub struct VmxCapabilities {
    /// VMX allowed settings for control0
    pub ctrl0: u64,
    /// VMX allowed settings for control1
    pub ctrl1: u64,
    /// True MSR controls available
    pub has_true_msrs: bool,
}

/// VMXON region (must be 4KB aligned)
#[repr(C, align(4096))]
pub struct VmxonRegion {
    /// VMX revision identifier
    pub revision: u32,
    /// VMXON region data
    pub data: [u8; 4088],
}

impl VmxonRegion {
    /// Create new VMXON region
    pub fn new(revision: u32) -> Self {
        Self {
            revision,
            data: [0; 4088],
        }
    }
}

/// VMCS region (must be 4KB aligned)
#[repr(C, align(4096))]
pub struct VmcsRegion {
    /// VMCS revision identifier
    pub revision: u32,
    /// VMCS abort indicator
    pub abort: u32,
    /// VMCS data
    pub data: [u8; 4088],
}

impl VmcsRegion {
    /// Create new VMCS region
    pub fn new(revision: u32) -> Self {
        Self {
            revision,
            abort: 0,
            data: [0; 4088],
        }
    }
}

/// VMX control fields
pub mod vmcs_fields {
    /// Pin-based VM-execution controls
    pub const VMCS_CTRL_PIN_BASED: u32 = 0x00004000;
    /// Primary processor-based VM-execution controls
    pub const VMCS_CTRL_PROC_BASED: u32 = 0x00004002;
    /// Exception bitmap
    pub const VMCS_CTRL_EXCEPTION_BITMAP: u32 = 0x00004004;
    /// Page-fault error-code mask
    const VMCS_CTRL_PF_MASK: u32 = 0x00004006;
    /// Page-fault error-code match
    const VMCS_CTRL_PF_MATCH: u32 = 0x00004008;
    /// I/O bitmap A address
    const VMCS_CTRL_IO_A: u32 = 0x0000400C;
    /// I/O bitmap B address
    const VMCS_CTRL_IO_B: u32 = 0x0000400E;
    /// Time-stamp counter offset
    const VMCS_CTRL_TSC_OFFSET: u32 = 0x00004010;
    /// Secondary processor-based controls
    pub const VMCS_CTRL_PROC_BASED2: u32 = 0x0000401E;
    /// EPT pointer
    pub const VMCS_CTRL_EPT_POINTER: u32 = 0x0000401A;
    /// Virtual-processor identifier
    const VMCS_CTRL_VPID: u32 = 0x00004020;

    /// Guest ES selector
    pub const VMCS_GUEST_ES_SELECTOR: u32 = 0x00000800;
    /// Guest CS selector
    pub const VMCS_GUEST_CS_SELECTOR: u32 = 0x00000802;
    /// Guest SS selector
    pub const VMCS_GUEST_SS_SELECTOR: u32 = 0x00000804;
    /// Guest DS selector
    pub const VMCS_GUEST_DS_SELECTOR: u32 = 0x00000806;
    /// Guest FS selector
    pub const VMCS_GUEST_FS_SELECTOR: u32 = 0x00000808;
    /// Guest GS selector
    pub const VMCS_GUEST_GS_SELECTOR: u32 = 0x0000080A;
    /// Guest LDTR selector
    pub const VMCS_GUEST_LDTR_SELECTOR: u32 = 0x0000080C;
    /// Guest TR selector
    pub const VMCS_GUEST_TR_SELECTOR: u32 = 0x0000080E;

    /// Guest ES limit
    const VMCS_GUEST_ES_LIMIT: u32 = 0x00000810;
    /// Guest CS limit
    const VMCS_GUEST_CS_LIMIT: u32 = 0x00000812;
    /// Guest SS limit
    const VMCS_GUEST_SS_LIMIT: u32 = 0x00000814;
    /// Guest DS limit
    const VMCS_GUEST_DS_LIMIT: u32 = 0x00000816;
    /// Guest FS limit
    const VMCS_GUEST_FS_LIMIT: u32 = 0x00000818;
    /// Guest GS limit
    const VMCS_GUEST_GS_LIMIT: u32 = 0x0000081A;
    /// Guest LDTR limit
    const VMCS_GUEST_LDTR_LIMIT: u32 = 0x0000081C;
    /// Guest TR limit
    const VMCS_GUEST_TR_LIMIT: u32 = 0x0000081E;

    /// Guest ES access rights
    const VMCS_GUEST_ES_ACCESS: u32 = 0x00000814;
    /// Guest CS access rights
    const VMCS_GUEST_CS_ACCESS: u32 = 0x00000816;

    /// Guest GDTR base
    pub const VMCS_GUEST_GDTR_BASE: u32 = 0x00000820;
    /// Guest IDTR base
    pub const VMCS_GUEST_IDTR_BASE: u32 = 0x00000822;
    /// Guest TR base
    pub const VMCS_GUEST_TR_BASE: u32 = 0x00000824;
    /// Guest LDTR base
    const VMCS_GUEST_LDTR_BASE: u32 = 0x00000826;
    /// Guest GS base
    const VMCS_GUEST_GS_BASE: u32 = 0x00000828;
    /// Guest FS base
    const VMCS_GUEST_FS_BASE: u32 = 0x0000082C;
    /// Guest CS base
    const VMCS_GUEST_CS_BASE: u32 = 0x00000832;
    /// Guest SS base
    const VMCS_GUEST_SS_BASE: u32 = 0x00000834;
    /// Guest DS base
    const VMCS_GUEST_DS_BASE: u32 = 0x00000836;
    /// Guest ES base
    const VMCS_GUEST_ES_BASE: u32 = 0x00000838;

    /// Guest CR0
    pub const VMCS_GUEST_CR0: u32 = 0x00006800;
    /// Guest CR3
    pub const VMCS_GUEST_CR3: u32 = 0x00006802;
    /// Guest CR4
    pub const VMCS_GUEST_CR4: u32 = 0x00006804;
    /// Guest DR7
    const VMCS_GUEST_DR7: u32 = 0x0000680A;
    /// Guest RSP
    pub const VMCS_GUEST_RSP: u32 = 0x0000681C;
    /// Guest RIP
    pub const VMCS_GUEST_RIP: u32 = 0x0000681E;
    /// Guest RFLAGS
    pub const VMCS_GUEST_RFLAGS: u32 = 0x00006820;

    /// Guest pending debug exceptions
    const VMCS_GUEST_PENDING_DBG: u32 = 0x00006828;
    /// Guest IA32_SYSENTER_ESP
    const VMCS_GUEST_SYSENTER_ESP: u32 = 0x00006824;
    /// Guest IA32_SYSENTER_EIP
    const VMCS_GUEST_SYSENTER_EIP: u32 = 0x00006826;

    /// Host ES selector
    pub const VMCS_HOST_ES_SELECTOR: u32 = 0x00000C00;
    /// Host CS selector
    pub const VMCS_HOST_CS_SELECTOR: u32 = 0x00000C02;
    /// Host SS selector
    pub const VMCS_HOST_SS_SELECTOR: u32 = 0x00000C04;
    /// Host DS selector
    pub const VMCS_HOST_DS_SELECTOR: u32 = 0x00000C06;
    /// Host FS selector
    pub const VMCS_HOST_FS_SELECTOR: u32 = 0x00000C08;
    /// Host GS selector
    pub const VMCS_HOST_GS_SELECTOR: u32 = 0x00000C0A;
    /// Host TR selector
    pub const VMCS_HOST_TR_SELECTOR: u32 = 0x00000C0C;

    /// Host CR0
    pub const VMCS_HOST_CR0: u32 = 0x00006C00;
    /// Host CR3
    pub const VMCS_HOST_CR3: u32 = 0x00006C02;
    /// Host CR4
    pub const VMCS_HOST_CR4: u32 = 0x00006C04;
    /// Host RSP
    pub const VMCS_HOST_RSP: u32 = 0x00006C14;
    /// Host RIP
    pub const VMCS_HOST_RIP: u32 = 0x00006C16;

    /// Host FS base
    const VMCS_HOST_FS_BASE: u32 = 0x00006C06;
    /// Host GS base
    const VMCS_HOST_GS_BASE: u32 = 0x00006C0C;
    /// Host TR base
    const VMCS_HOST_TR_BASE: u32 = 0x00006C10;
    /// Host GDTR base
    const VMCS_HOST_GDTR_BASE: u32 = 0x00006C08;
    /// Host IDTR base
    const VMCS_HOST_IDTR_BASE: u32 = 0x00006C0E;
    /// Host IA32_SYSENTER_ESP
    const VMCS_HOST_SYSENTER_ESP: u32 = 0x00006C18;
    /// Host IA32_SYSENTER_EIP
    const VMCS_HOST_SYSENTER_EIP: u32 = 0x00006C1A;

    /// VM exit controls
    pub const VMCS_CTRL_VMEXIT_CTRL: u32 = 0x0000400C;
    /// VM entry controls
    pub const VMCS_CTRL_VMENTRY_CTRL: u32 = 0x00004002;
    /// VM exit MSR store address
    const VMCS_CTRL_VMEXIT_MSR_STORE: u32 = 0x00004006;
    /// VM exit MSR load address
    const VMCS_CTRL_VMEXIT_MSR_LOAD: u32 = 0x00004008;
    /// VM entry MSR load address
    const VMCS_CTRL_VMENTRY_MSR_LOAD: u32 = 0x0000400A;

    /// VM exit reason
    pub const VMCS_EXIT_REASON: u32 = 0x00004402;
    /// VM exit qualification
    pub const VMCS_EXIT_QUALIFICATION: u32 = 0x00004400;
    /// Guest linear address
    pub const VMCS_GUEST_LINEAR_ADDR: u32 = 0x0000440A;
    /// Guest physical address
    pub const VMCS_GUEST_PHYSICAL_ADDR: u32 = 0x0000440C;
}

/// VM exit reasons
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExitReason {
    ExceptionOrNmi = 0,
    ExternalInterrupt = 1,
    TripleFault = 2,
    InitSignal = 3,
    StartupIpi = 4,
    IoSmi = 7,
    OtherSmi = 8,
    InterruptWindow = 9,
    NmiWindow = 10,
    TaskSwitch = 12,
    CpuId = 13,
    Hlt = 12,
    Invd = 13,
    Vmcall = 14,
    Vmclear = 15,
    Vmlaunch = 16,
    Vmptrld = 17,
    Vmptrst = 18,
    Vmread = 19,
    Vmwrite = 20,
    Vmxoff = 21,
    Vmxon = 22,
    CrAccess = 28,
    DrAccess = 29,
    IoInstruction = 30,
    MsrRead = 31,
    MsrWrite = 32,
    InvalidGuestState = 33,
    MsrLoadingError = 34,
    /// EPT Violation (must read from VMCS)
    EptViolation,
    /// EPT Misconfiguration
    EptMisconfig,
    /// Unknown exit
    Unknown,
}

impl From<u32> for ExitReason {
    fn from(code: u32) -> Self {
        match code {
            0 => ExitReason::ExceptionOrNmi,
            1 => ExitReason::ExternalInterrupt,
            2 => ExitReason::TripleFault,
            3 => ExitReason::InitSignal,
            4 => ExitReason::StartupIpi,
            7 => ExitReason::IoSmi,
            8 => ExitReason::OtherSmi,
            9 => ExitReason::InterruptWindow,
            10 => ExitReason::NmiWindow,
            12 => ExitReason::TaskSwitch,
            13 => ExitReason::CpuId,
            14 => ExitReason::Vmcall,
            15 => ExitReason::Vmclear,
            16 => ExitReason::Vmlaunch,
            17 => ExitReason::Vmptrld,
            18 => ExitReason::Vmptrst,
            19 => ExitReason::Vmread,
            20 => ExitReason::Vmwrite,
            21 => ExitReason::Vmxoff,
            22 => ExitReason::Vmxon,
            28 => ExitReason::CrAccess,
            29 => ExitReason::DrAccess,
            30 => ExitReason::IoInstruction,
            31 => ExitReason::MsrRead,
            32 => ExitReason::MsrWrite,
            33 => ExitReason::InvalidGuestState,
            34 => ExitReason::MsrLoadingError,
            48 => ExitReason::EptViolation,
            49 => ExitReason::EptMisconfig,
            _ => ExitReason::Unknown,
        }
    }
}

/// VMX Manager - handles Intel VT-x operations
pub struct VmxManager {
    /// VMXON region physical address
    vmxon_phys: u64,
    /// VMCS region physical address
    vmcs_phys: u64,
    /// VMX revision ID
    revision: u32,
    /// VMX capabilities
    capabilities: VmxCapabilities,
    /// Whether VMX is active
    active: bool,
}

impl VmxManager {
    /// Create and initialize VMX manager
    pub fn new() -> Result<Self, HypervisorError> {
        // Get VMX capabilities
        let capabilities = Self::get_capabilities();
        
        // Get revision ID
        let revision = Self::get_revision();
        
        // Allocate VMXON region (must be aligned to 4KB)
        let vmxon_phys = Self::allocate_vmxon_region(revision)?;
        
        // Allocate VMCS region
        let vmcs_phys = Self::allocate_vmcs_region(revision)?;
        
        // Enable VMX
        Self::enable_vmx()?;
        
        // Execute VMXON
        Self::vmxon(vmxon_phys)?;
        
        println!("[VMX] VMX enabled successfully");
        
        Ok(Self {
            vmxon_phys,
            vmcs_phys,
            revision,
            capabilities,
            active: true,
        })
    }

    /// Get VMX capabilities from CPUID
    fn get_capabilities() -> VmxCapabilities {
        use x86_64::instructions::cpuid::CpuId;
        
        let cpuid = CpuId::new();
        let mut caps = VmxCapabilities {
            ctrl0: 0,
            ctrl1: 0,
            has_true_msrs: false,
        };
        
        if let Some(info) = cpuid.get_vmx_info() {
            caps.ctrl0 = info.get_allowed0() as u64;
            caps.ctrl1 = info.get_allowed1() as u64;
        }
        
        caps
    }

    /// Get VMX revision ID from IA32_VMX_BASIC MSR
    fn get_revision() -> u32 {
        use x86_64::registers::model_specific::Msr;
        
        let msr = Msr::new(0x480).unwrap_or_else(|_| {
            // Fallback - use standard revision
            Msr::new(0x480).expect("Failed to read VMX revision")
        });
        
        (msr.read() & 0xFFFFFFFF) as u32
    }

    /// Allocate VMXON region
    fn allocate_vmxon_region(revision: u32) -> Result<u64, HypervisorError> {
        // In a real implementation, this would allocate from physical memory
        // For now, use a static aligned region
        let mut region = VmxonRegion::new(revision);
        region.revision = revision;
        
        let addr = &region as *const _ as u64;
        
        // Ensure alignment
        assert!(addr % 4096 == 0, "VMXON region must be 4KB aligned");
        
        Ok(addr)
    }

    /// Allocate VMCS region
    fn allocate_vmcs_region(revision: u32) -> Result<u64, HypervisorError> {
        let mut region = VmcsRegion::new(revision);
        region.revision = revision;
        
        let addr = &region as *const _ as u64;
        
        assert!(addr % 4096 == 0, "VMCS region must be 4KB aligned");
        
        Ok(addr)
    }

    /// Enable VMX via IA32_FEATURE_CONTROL MSR
    fn enable_vmx() -> Result<(), HypervisorError> {
        use x86_64::registers::control::Cr4;
        use x86_64::registers::model_specific::Msr;
        
        // Enable VMX in CR4
        let mut cr4 = Cr4::read();
        cr4.enable_vmx();
        Cr4::write(cr4);
        
        // Enable VMX in IA32_FEATURE_CONTROL
        let msr = Msr::new(0x3A).map_err(|_| HypervisorError::VmxonFailed)?;
        let val = msr.read();
        msr.write(val | 0x5); // Enable VMX outside SMX
        
        Ok(())
    }

    /// Enter VMX operation (VMXON)
    fn vmxon(phys_addr: u64) -> Result<(), HypervisorError> {
        unsafe {
            // Use inline assembly for VMXON
            llvm_asm!("vmxon $0" 
                     : 
                     : "m" (*(phys_addr as *const u8))
                     : "memory", "cc"
                     : "intel");
        }
        
        Ok(())
    }

    /// Exit VMX operation (VMXOFF)
    pub fn vmxoff(&mut self) -> Result<(), HypervisorError> {
        if !self.active {
            return Ok(());
        }
        
        unsafe {
            llvm_asm!("vmxoff" 
                     : 
                     : 
                     : "memory", "cc"
                     : "intel");
        }
        
        self.active = false;
        Ok(())
    }

    /// Load VMCS pointer (VMPTRLD)
    fn vmptrld(phys_addr: u64) -> Result<(), HypervisorError> {
        unsafe {
            llvm_asm!("vmptrld $0" 
                     : 
                     : "m" (*(phys_addr as *const u8))
                     : "memory"
                     : "intel");
        }
        
        Ok(())
    }

    /// Store VMCS pointer (VMPTRST)
    fn vmptrst() -> Result<u64, HypervisorError> {
        let mut addr: u64 = 0;
        
        unsafe {
            llvm_asm!("vmptrst $0" 
                     : "=m" (addr)
                     : 
                     : "memory"
                     : "intel");
        }
        
        Ok(addr)
    }

    /// Read from VMCS field
    pub fn vmread(field: u32) -> Result<u64, HypervisorError> {
        let mut value: u64 = 0;
        
        let result = unsafe {
            llvm_asm!("vmread $2, $1" 
                     : "=r" (value)
                     : "r" (field as u64), "m" (value)
                     : "memory"
                     : "intel")
        };
        
        if result.is_err() {
            return Err(HypervisorError::VmcsOperationFailed);
        }
        
        Ok(value)
    }

    /// Write to VMCS field
    pub fn vmwrite(field: u32, value: u64) -> Result<(), HypervisorError> {
        unsafe {
            llvm_asm!("vmwrite $1, $2" 
                     : 
                     : "r" (field as u64), "r" (value)
                     : "memory"
                     : "intel")
        }
        
        Ok(())
    }

    /// Setup VMCS for guest
    pub fn setup_vmcs(&self, ept: &EptManager) -> Result<(), HypervisorError> {
        // Load VMCS
        self.vmptrld(self.vmcs_phys)?;
        
        // ========== PIN-BASED CONTROLS ==========
        // External interrupt exiting
        let pin_ctrl: u32 = 0x16; // NMI exiting + external interrupt exiting
        self.vmwrite(vmcs_fields::VMCS_CTRL_PIN_BASED, pin_ctrl as u64)?;
        
        // ========== PROCESSOR-BASED CONTROLS ==========
        // Enable EPT, enable RDTSCP, enable invvpid
        let proc_ctrl: u32 = 0x8080_6042 | (1 << 31); // Secondary controls
        self.vmwrite(vmcs_fields::VMCS_CTRL_PROC_BASED, proc_ctrl as u64)?;
        
        // Secondary processor-based controls
        let proc_ctrl2: u32 = 0x2 |  // Enable EPT
                              0x40 | // Enable RDTSCP
                              0x80 | // Enable INVVPID
                              0x1000; // Enable unrestricted guest
        self.vmwrite(vmcs_fields::VMCS_CTRL_PROC_BASED2, proc_ctrl2 as u64)?;
        
        // ========== EPT POINTER ==========
        let eptp = ept.get_eptp();
        self.vmwrite(vmcs_fields::VMCS_CTRL_EPT_POINTER, eptp)?;
        
        // ========== VM EXIT CONTROLS ==========
        let vmexit_ctrl: u32 = 0xD0000; // Save debug controls, IA32e mode guest, save perf global ctrl
        self.vmwrite(vmcs_fields::VMCS_CTRL_VMEXIT_CTRL, vmexit_ctrl as u64)?;
        
        // ========== VM ENTRY CONTROLS ==========
        let vmentry_ctrl: u32 = 0x8000 | 0x10000 | 0x20000; // IA32e mode guest, load debug controls
        self.vmwrite(vmcs_fields::VMCS_CTRL_VMENTRY_CTRL, vmentry_ctrl as u64)?;
        
        // ========== GUEST STATE ==========
        // CR0: Enable protected mode, disable paging initially
        self.vmwrite(vmcs_fields::VMCS_GUEST_CR0, 0x20)?;
        
        // CR3: No paging initially
        self.vmwrite(vmcs_fields::VMCS_GUEST_CR3, 0)?;
        
        // CR4: Enable PAE for EPT
        self.vmwrite(vmcs_fields::VMCS_GUEST_CR4, 0x200)?;
        
        // RFLAGS
        self.vmwrite(vmcs_fields::VMCS_GUEST_RFLAGS, 0x2)?;
        
        // Selectors and bases
        self.vmwrite(vmcs_fields::VMCS_GUEST_CS_SELECTOR, 0x8)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_CS_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_CS_LIMIT, 0xFFFF)?;
        
        self.vmwrite(vmcs_fields::VMCS_GUEST_DS_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_DS_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_DS_LIMIT, 0xFFFF)?;
        
        self.vmwrite(vmcs_fields::VMCS_GUEST_SS_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_SS_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_SS_LIMIT, 0xFFFF)?;
        
        self.vmwrite(vmcs_fields::VMCS_GUEST_ES_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_ES_BASE, 0x0)?;
        
        self.vmwrite(vmcs_fields::VMCS_GUEST_FS_SELECTOR, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_GS_SELECTOR, 0x0)?;
        
        // Task register
        self.vmwrite(vmcs_fields::VMCS_GUEST_TR_SELECTOR, 0x28)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_TR_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_TR_LIMIT, 0xFFFF)?;
        
        // LDTR
        self.vmwrite(vmcs_fields::VMCS_GUEST_LDTR_SELECTOR, 0x0)?;
        
        // GDTR and IDTR
        self.vmwrite(vmcs_fields::VMCS_GUEST_GDTR_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_GDTR_BASE, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_GUEST_IDTR_BASE, 0x0)?;
        
        // ========== HOST STATE ==========
        // Selectors
        self.vmwrite(vmcs_fields::VMCS_HOST_CS_SELECTOR, 0x8)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_DS_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_SS_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_ES_SELECTOR, 0x10)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_FS_SELECTOR, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_GS_SELECTOR, 0x0)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_TR_SELECTOR, 0x28)?;
        
        // CR0, CR3, CR4
        self.vmwrite(vmcs_fields::VMCS_HOST_CR0, 0x20)?;
        self.vmwrite(vmcs_fields::VMCS_HOST_CR3, 0x0)?;
        
        let mut cr4 = x86_64::registers::control::Cr4::read();
        cr4.enable_vmx();
        self.vmwrite(vmcs_fields::VMCS_HOST_CR4, cr4.bits())?;
        
        println!("[VMX] VMCS configured successfully");
        
        Ok(())
    }

    /// Launch the guest VM
    pub fn launch_guest(&mut self, ept: &EptManager) -> Result<(), HypervisorError> {
        // Setup VMCS
        self.setup_vmcs(ept)?;
        
        // Launch VM
        unsafe {
            llvm_asm!("vmlaunch" 
                     : 
                     : 
                     : "memory", "cc"
                     : "intel");
        }
        
        // If we get here, VM launch failed
        Err(HypervisorError::VmLaunchFailed)
    }

    /// Resume the guest VM
    pub fn resume_guest() -> Result<(), HypervisorError> {
        unsafe {
            llvm_asm!("vmresume" 
                     : 
                     : 
                     : "memory", "cc"
                     : "intel");
        }
        
        Err(HypervisorError::VmResumeFailed)
    }

    /// Handle VM exit
    pub fn handle_exit(&self) -> ExitReason {
        let reason = self.vmread(vmcs_fields::VMCS_EXIT_REASON)
            .unwrap_or(0) as u32;
        
        ExitReason::from(reason)
    }
}

// Make VmxManager usable
impl Drop for VmxManager {
    fn drop(&mut self) {
        if self.active {
            let _ = self.vmxoff();
        }
    }
}
