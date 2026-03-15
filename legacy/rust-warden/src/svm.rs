//! AMD SVM (Secure Virtual Machine) Support
//!
//! This module provides the AMD SVM virtualization functionality,
//! including SVM enable/disable, VMCB management, and NPT (Nested Page Tables).

use crate::HypervisorError;

/// SVM Capabilities
#[derive(Debug, Clone, Copy)]
pub struct SvmCapabilities {
    /// SVM revision
    pub revision: u8,
    /// Maximum ASID
    pub max_asid: u16,
    /// Number of physical bits
    pub phys_bits: u8,
    /// NPT supported
    pub npt: bool,
    /// LbrVirt supported
    pub lbr_virt: bool,
    /// VLAT save/restore supported
    pub vls: bool,
    /// Instruction intercept supported
    pub ins_int: bool,
}

/// VMCB (Virtual Machine Control Block) - must be aligned to 4KB
#[repr(C, align(4096))]
pub struct VmcbControlArea {
    /// CR0 read shadow
    pub cr0_read_shadow: u64,
    /// CR4 read shadow
    pub cr4_read_shadow: u64,
    /// CR3 target list 0
    pub cr3_target_0: u64,
    /// CR3 target list 1
    pub cr3_target_1: u64,
    /// CR3 target list 2
    pub cr3_target_2: u64,
    /// CR3 target list 3
    pub cr3_target_3: u64,
    /// ASID
    pub asid: u16,
    /// TLB control
    pub tlb_control: u8,
    /// Reserved
    _reserved1: [u8; 5],
    /// Interrupt shadow
    pub interrupt_shadow: u64,
    /// Exit code
    pub exit_code: u64,
    /// Exit info 1
    pub exit_info_1: u64,
    /// Exit info 2
    pub exit_info_2: u64,
    /// Exit interruption info
    pub exit_int_info: u64,
    /// Exit interruption error code
    pub exit_int_error_code: u64,
    /// Nested page table root
    pub npt_root: u64,
    /// Host IA32_EFER
    pub host_efer: u64,
    /// Host CR0
    pub host_cr0: u64,
    /// Host CR3
    pub host_cr3: u64,
    /// Host CR4
    pub host_cr4: u64,
    /// Host CS selector
    pub host_cs_selector: u16,
    /// Host DS selector
    pub host_ds_selector: u16,
    /// Host ES selector
    pub host_es_selector: u16,
    /// Host FS selector
    pub host_fs_selector: u16,
    /// Host GS selector
    pub host_gs_selector: u16,
    /// Host SS selector
    pub host_ss_selector: u16,
    /// Host TR selector
    pub host_tr_selector: u16,
    /// Reserved
    _reserved2: [u8; 6],
    /// Host FS base
    pub host_fs_base: u64,
    /// Host GS base
    pub host_gs_base: u64,
    /// Host TR base
    pub host_tr_base: u64,
    /// Host GDTR base
    pub host_gdtr_base: u64,
    /// Host IDTR base
    pub host_idtr_base: u64,
    /// Host RSP
    pub host_rsp: u64,
    /// Host RIP
    pub host_rip: u64,
    /// Reserved
    _reserved3: [u8; 96],
    /// IOPM base address
    pub iopm_base: u64,
    /// MSRPM base address
    pub msrpm_base: u64,
    /// TSC offset
    pub tsc_offset: u64,
    /// Guest ES selector
    pub guest_es_selector: u16,
    /// Guest CS selector
    pub guest_cs_selector: u16,
    /// Guest SS selector
    pub guest_ss_selector: u16,
    /// Guest DS selector
    pub guest_ds_selector: u16,
    /// Guest FS selector
    pub guest_fs_selector: u16,
    /// Guest GS selector
    pub guest_gs_selector: u16,
    /// Guest LDTR selector
    pub guest_ldtr_selector: u16,
    /// Guest TR selector
    pub guest_tr_selector: u16,
    /// Reserved
    _reserved4: [u8; 4],
    /// Guest ES limit
    pub guest_es_limit: u32,
    /// Guest CS limit
    pub guest_cs_limit: u32,
    /// Guest SS limit
    pub guest_ss_limit: u32,
    /// Guest DS limit
    pub guest_ds_limit: u32,
    /// Guest FS limit
    pub guest_fs_limit: u32,
    /// Guest GS limit
    pub guest_gs_limit: u32,
    /// Guest LDTR limit
    pub guest_ldtr_limit: u32,
    /// Guest TR limit
    pub guest_tr_limit: u32,
    /// Guest ES access rights
    pub guest_es_attr: u32,
    /// Guest CS access rights
    pub guest_cs_attr: u32,
    /// Guest SS access rights
    pub guest_ss_attr: u32,
    /// Guest DS access rights
    pub guest_ds_attr: u32,
    /// Guest FS access rights
    pub guest_fs_attr: u32,
    /// Guest GS access rights
    pub guest_gs_attr: u32,
    /// Guest LDTR access rights
    pub guest_ldtr_attr: u32,
    /// Guest TR access rights
    pub guest_tr_attr: u32,
    /// Reserved
    _reserved5: [u8; 4],
    /// Guest ES base
    pub guest_es_base: u64,
    /// Guest CS base
    pub guest_cs_base: u64,
    /// Guest SS base
    pub guest_ss_base: u64,
    /// Guest DS base
    pub guest_ds_base: u64,
    /// Guest FS base
    pub guest_fs_base: u64,
    /// Guest GS base
    pub guest_gs_base: u64,
    /// Guest LDTR base
    pub guest_ldtr_base: u64,
    /// Guest TR base
    pub guest_tr_base: u64,
    /// Reserved
    _reserved6: [u8; 8],
    /// Guest CR0
    pub guest_cr0: u64,
    /// Guest CR2
    pub guest_cr2: u64,
    /// Guest CR3
    pub guest_cr3: u64,
    /// Guest CR4
    pub guest_cr4: u64,
    /// Reserved
    _reserved7: [u8; 8],
    /// Guest DR6
    pub guest_dr6: u64,
    /// Guest DR7
    pub guest_dr7: u64,
    /// Guest RIP
    pub guest_rip: u64,
    /// Guest RFLAGS
    pub guest_rflags: u64,
    /// Guest RSP
    pub guest_rsp: u64,
    /// Guest RA
    pub guest_rax: u64,
    /// Guest CR1
    pub guest_cr1: u64,
    /// Guest star
    pub guest_star: u64,
    /// Guest LSTAR
    pub guest_lstar: u64,
    /// Guest CSTAR
    pub guest_cstar: u64,
    /// Guest FMASK
    pub guest_fmask: u64,
    /// Guest Kernel GS base
    pub guest_kernel_gs_base: u64,
    /// Guest GDTR base
    pub guest_gdtr_base: u64,
    /// Guest IDTR base
    pub guest_idtr_base: u64,
    /// Guest TR limit
    pub guest_tr_limit: u32,
    /// Reserved
    _reserved8: [u8; 4],
    /// Guest LDTR base
    pub guest_ldtr_base: u64,
    /// Guest MPU
    pub guest_mp: u8,
    /// Guest XF
    pub guest_xf: u8,
    /// Reserved
    _reserved9: [u8; 6],
    /// Guest FPU
    pub guest_fpu: [u8; 128],
    /// Reserved
    _reserved10: [u8; 8],
    /// XSS (Host)
    pub xss: u64,
    /// Guest FS fix
    pub guest_fs_arc: u64,
    /// Guest GS fix
    pub guest_gs_arc: u64,
    /// Reserved
    _reserved11: [u8; 96],
}

impl VmcbControlArea {
    /// Create new VMCB control area
    pub fn new() -> Self {
        Self {
            cr0_read_shadow: 0,
            cr4_read_shadow: 0,
            cr3_target_0: 0,
            cr3_target_1: 0,
            cr3_target_2: 0,
            cr3_target_3: 0,
            asid: 0,
            tlb_control: 0,
            _reserved1: [0; 5],
            interrupt_shadow: 0,
            exit_code: 0,
            exit_info_1: 0,
            exit_info_2: 0,
            exit_int_info: 0,
            exit_int_error_code: 0,
            npt_root: 0,
            host_efer: 0,
            host_cr0: 0,
            host_cr3: 0,
            host_cr4: 0,
            host_cs_selector: 0,
            host_ds_selector: 0,
            host_es_selector: 0,
            host_fs_selector: 0,
            host_gs_selector: 0,
            host_ss_selector: 0,
            host_tr_selector: 0,
            _reserved2: [0; 6],
            host_fs_base: 0,
            host_gs_base: 0,
            host_tr_base: 0,
            host_gdtr_base: 0,
            host_idtr_base: 0,
            host_rsp: 0,
            host_rip: 0,
            _reserved3: [0; 96],
            iopm_base: 0,
            msrpm_base: 0,
            tsc_offset: 0,
            guest_es_selector: 0,
            guest_cs_selector: 0,
            guest_ss_selector: 0,
            guest_ds_selector: 0,
            guest_fs_selector: 0,
            guest_gs_selector: 0,
            guest_ldtr_selector: 0,
            guest_tr_selector: 0,
            _reserved4: [0; 4],
            guest_es_limit: 0,
            guest_cs_limit: 0,
            guest_ss_limit: 0,
            guest_ds_limit: 0,
            guest_fs_limit: 0,
            guest_gs_limit: 0,
            guest_ldtr_limit: 0,
            guest_tr_limit: 0,
            guest_es_attr: 0,
            guest_cs_attr: 0,
            guest_ss_attr: 0,
            guest_ds_attr: 0,
            guest_fs_attr: 0,
            guest_gs_attr: 0,
            guest_ldtr_attr: 0,
            guest_tr_attr: 0,
            _reserved5: [0; 4],
            guest_es_base: 0,
            guest_cs_base: 0,
            guest_ss_base: 0,
            guest_ds_base: 0,
            guest_fs_base: 0,
            guest_gs_base: 0,
            guest_ldtr_base: 0,
            guest_tr_base: 0,
            _reserved6: [0; 8],
            guest_cr0: 0,
            guest_cr2: 0,
            guest_cr3: 0,
            guest_cr4: 0,
            _reserved7: [0; 8],
            guest_dr6: 0,
            guest_dr7: 0,
            guest_rip: 0,
            guest_rflags: 0,
            guest_rsp: 0,
            guest_rax: 0,
            guest_cr1: 0,
            guest_star: 0,
            guest_lstar: 0,
            guest_cstar: 0,
            guest_fmask: 0,
            guest_kernel_gs_base: 0,
            guest_gdtr_base: 0,
            guest_idtr_base: 0,
            guest_tr_limit: 0,
            _reserved8: [0; 4],
            guest_ldtr_base: 0,
            guest_mp: 0,
            guest_xf: 0,
            _reserved9: [0; 6],
            guest_fpu: [0; 128],
            _reserved10: [0; 8],
            xss: 0,
            guest_fs_arc: 0,
            guest_gs_arc: 0,
            _reserved11: [0; 96],
        }
    }
}

/// SVM Exit codes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SvmExit {
    /// Exit due to exception
    Exception(u8),
    /// Exit due to interrupt
    Interrupt,
    /// Nested page fault
    Npf,
    /// Task switch
    TaskSwitch,
    /// CPUID
    Cpuid,
    /// HLT
    Hlt,
    /// INVD
    Invd,
    /// VMCALL
    Vmcall,
    /// VMRUN
    Vmrun,
    /// VMMCALL
    Vmmcall,
    /// IRET
    Iret,
    /// RDTSC
    Rdtsc,
    /// RDPMC
    Rdpmc,
    /// PUSHF/POPF
    PushfPopf,
    /// CPUID
    Cpuid2,
    /// RDRAND
    Rdrand,
    /// RDSEED
    Rdseed,
    /// Unknown
    Unknown,
}

impl From<u64> for SvmExit {
    fn from(code: u64) -> Self {
        match code {
            0x00..=0x0F => SvmExit::Exception(code as u8),
            0x10 => SvmExit::Interrupt,
            0x40 => SvmExit::Npf,
            0x41 => SvmExit::TaskSwitch,
            0x42 => SvmExit::Cpuid,
            0x44 => SvmExit::Hlt,
            0x45 => SvmExit::Invd,
            0x46 => SvmExit::Vmcall,
            0x47 => SvmExit::Vmrunning,
            0x48 => SvmExit::Vmmcall,
            0x4C => SvmExit::Iret,
            0x4D => SvmExit::Rdtsc,
            0x4E => SvmExit::Rdpmc,
            0x52 => SvmExit::PushfPopf,
            0x53 => SvmExit::Cpuid2,
            0x57 => SvmExit::Rdrand,
            0x59 => SvmExit::Rdseed,
            _ => SvmExit::Unknown,
        }
    }
}

/// SVM Manager - handles AMD SVM operations
pub struct SvmManager {
    /// VMCB physical address
    vmcb_phys: u64,
    /// NPT root physical address
    npt_root_phys: u64,
    /// SVM capabilities
    capabilities: SvmCapabilities,
    /// Whether SVM is active
    active: bool,
    /// Current ASID
    asid: u16,
}

impl SvmManager {
    /// Create and initialize SVM manager
    pub fn new() -> Result<Self, HypervisorError> {
        // Get SVM capabilities
        let capabilities = Self::get_capabilities();
        
        if !capabilities.npt {
            return Err(HypervisorError::NoNptSupport);
        }
        
        // Allocate VMCB (must be 4KB aligned)
        let vmcb_phys = Self::allocate_vmcb()?;
        
        // Allocate NPT root
        let npt_root_phys = Self::allocate_npt_root()?;
        
        // Enable SVM
        Self::enable_svm()?;
        
        // Initialize SVM
        Self::svm_init(vmcb_phys)?;
        
        println!("[SVM] SVM enabled successfully");
        
        Ok(Self {
            vmcb_phys,
            npt_root_phys,
            capabilities,
            active: true,
            asid: 1,
        })
    }

    /// Get SVM capabilities from CPUID
    fn get_capabilities() -> SvmCapabilities {
        use x86_64::instructions::cpuid::CpuId;
        
        let cpuid = CpuId::new();
        
        if let Some(info) = cpuid.get_extended_processor_info() {
            SvmCapabilities {
                revision: 1, // SVM revision 1
                max_asid: 0, // Will be read from MSR
                phys_bits: 0,
                npt: info.has_npt(),
                lbr_virt: info.has_lbr(),
                vls: info.has_svm_vls(),
                ins_int: info.has_svm_ins_outs(),
            }
        } else {
            SvmCapabilities {
                revision: 1,
                max_asid: 0,
                phys_bits: 0,
                npt: false,
                lbr_virt: false,
                vls: false,
                ins_int: false,
            }
        }
    }

    /// Read SVM-related MSRs
    fn read_svm_msr() -> (u64, u64) {
        use x86_64::registers::model_specific::Msr;
        
        // SVM Features MSR (C001_0115h)
        let vm_hv = Msr::new(0xC001_0115)
            .map(|m| m.read())
            .unwrap_or(0);
        
        // Maximum ASID MSR (C001_0118h)
        let max_asid = Msr::new(0xC001_0118)
            .map(|m| m.read())
            .unwrap_or(0);
        
        (vm_hv, max_asid)
    }

    /// Allocate VMCB
    fn allocate_vmcb() -> Result<u64, HypervisorError> {
        let vmcb = Box::leak(Box::new(VmcbControlArea::new()));
        let addr = vmcb as *const _ as u64;
        
        assert!(addr % 4096 == 0, "VMCB must be 4KB aligned");
        
        Ok(addr)
    }

    /// Allocate NPT root (PML4 equivalent)
    fn allocate_npt_root() -> Result<u64, HypervisorError> {
        // In real implementation, this would allocate and initialize NPT tables
        // For now, use a static allocation
        let mut npt = [0u64; 512];
        
        let npt_ptr = Box::leak(Box::new(npt));
        let addr = npt_ptr as *const _ as u64;
        
        assert!(addr % 4096 == 0, "NPT root must be 4KB aligned");
        
        Ok(addr)
    }

    /// Enable SVM via CR4
    fn enable_svm() -> Result<(), HypervisorError> {
        use x86_64::registers::control::Cr4;
        
        let mut cr4 = Cr4::read();
        cr4.enable_svm();
        Cr4::write(cr4);
        
        Ok(())
    }

    /// Initialize SVM with VMCB
    fn svm_init(vmcb_phys: u64) -> Result<(), HypervisorError> {
        use x86_64::registers::model_specific::Msr;
        
        // Write VMCB physical address to SVM MSR
        let msr = Msr::new(0xC001_0116)
            .map_err(|_| HypervisorError::SvmInitFailed)?;
        
        msr.write(vmcb_phys);
        
        Ok(())
    }

    /// Start SVM (VMGEXIT)
    fn svm_start() -> Result<(), HypervisorError> {
        unsafe {
            llvm_asm!("vmgexit"
                     : 
                     : 
                     : "memory", "cc"
                     : "volatile");
        }
        
        Ok(())
    }

    /// Setup VMCB for guest
    pub fn setup_vmcb(&mut self, guest_phys: u64, guest_size: u64) -> Result<(), HypervisorError> {
        // Get VMCB address
        let vmcb_ptr = self.vmcb_phys as *mut VmcbControlArea;
        
        // Safety: we own this memory
        let vmcb = unsafe { &mut *vmcb_ptr };
        
        // Setup NPT root
        vmcb.npt_root = self.npt_root_phys | 0x7; // Read, Write, Present
        
        // Setup ASID
        vmcb.asid = self.asid;
        
        // Guest CR0: Enable protected mode, disable paging
        vmcb.guest_cr0 = 0x21; // PE + WP
        
        // Guest CR3: Point to guest page tables (if any)
        vmcb.guest_cr3 = 0;
        
        // Guest CR4: Enable PAE
        vmcb.guest_cr4 = 0x200;
        
        // Guest selectors
        vmcb.guest_cs_selector = 0x8;
        vmcb.guest_cs_base = 0;
        vmcb.guest_cs_limit = 0xFFFF;
        vmcb.guest_cs_attr = 0x9B; // Present, Executable, Readable, Accessed
        
        vmcb.guest_ds_selector = 0x10;
        vmcb.guest_ds_base = 0;
        vmcb.guest_ds_limit = 0xFFFF;
        vmcb.guest_ds_attr = 0x93; // Present, Writable, Accessed
        
        vmcb.guest_ss_selector = 0x10;
        vmcb.guest_ss_base = 0;
        vmcb.guest_ss_limit = 0xFFFF;
        vmcb.guest_ss_attr = 0x93;
        
        vmcb.guest_es_selector = 0x10;
        vmcb.guest_es_base = 0;
        vmcb.guest_es_limit = 0xFFFF;
        vmcb.guest_es_attr = 0x93;
        
        vmcb.guest_fs_selector = 0;
        vmcb.guest_gs_selector = 0;
        vmcb.guest_ldtr_selector = 0;
        vmcb.guest_tr_selector = 0x28;
        
        // Guest GDTR/IDTR
        vmcb.guest_gdtr_base = 0;
        vmcb.guest_gdtr_limit = 0;
        vmcb.guest_idtr_base = 0;
        vmcb.guest_idtr_limit = 0;
        
        // Guest RIP (start at 0x100000 - typical boot address)
        vmcb.guest_rip = 0x100000;
        
        // Guest RSP (stack at top of memory)
        vmcb.guest_rsp = guest_phys + guest_size - 16;
        
        // Guest RFLAGS
        vmcb.guest_rflags = 0x2;
        
        // Guest RAX (initial accumulator)
        vmcb.guest_rax = 0;
        
        // Setup host state
        vmcb.host_cr0 = x86_64::registers::control::Cr0::read().bits();
        vmcb.host_cr3 = 0; // Should be hypervisor's CR3
        vmcb.host_cr4 = x86_64::registers::control::Cr4::read().bits();
        
        // Host selectors
        vmcb.host_cs_selector = 0x8;
        vmcb.host_ds_selector = 0x10;
        vmcb.host_es_selector = 0x10;
        vmcb.host_ss_selector = 0x10;
        
        // EFER
        vmcb.host_efer = 0x1000; // Long mode enabled
        
        println!("[SVM] VMCB configured successfully");
        
        Ok(())
    }

    /// Launch the guest VM
    pub fn launch_guest(&mut self) -> Result<(), HypervisorError> {
        // Setup VMCB (would require guest physical memory info)
        // For now, just setup basic config
        self.setup_vmcb(0x10000000, 0x10000000)?;
        
        // Run the guest
        self.run_guest()
    }

    /// Run the guest VM (VMRUN)
    fn run_guest(&self) -> Result<(), HypervisorError> {
        // Set up VMCB address for VMRUN
        let vmcb_phys = self.vmcb_phys;
        
        unsafe {
            // VMRUN instruction
            llvm_asm!("vmrun $0"
                     : 
                     : "r" (vmcb_phys)
                     : "memory", "rax", "rcx", "rdx", "rsi", "rdi"
                     : "volatile");
        }
        
        // If we return from VMRUN, a VM exit occurred
        // Check exit code
        let vmcb = unsafe { &*(self.vmcb_phys as *const VmcbControlArea) };
        
        println!("[SVM] VM exit: code={}", vmcb.exit_code);
        
        Err(HypervisorError::GuestError)
    }

    /// Handle VM exit
    pub fn handle_exit(&self) -> SvmExit {
        let vmcb = unsafe { &*(self.vmcb_phys as *const VmcbControlArea) };
        
        SvmExit::from(vmcb.exit_code)
    }

    /// Disable SVM
    pub fn disable(&mut self) -> Result<(), HypervisorError> {
        if !self.active {
            return Ok(());
        }
        
        use x86_64::registers::control::Cr4;
        
        let mut cr4 = Cr4::read();
        cr4.disable_svm();
        Cr4::write(cr4);
        
        self.active = false;
        
        Ok(())
    }
}

impl Drop for SvmManager {
    fn drop(&mut self) {
        if self.active {
            let _ = self.disable();
        }
    }
}

// Import Vmrunning from the match
fn vmrunning() -> SvmExit { SvmExit::Vmrun }
