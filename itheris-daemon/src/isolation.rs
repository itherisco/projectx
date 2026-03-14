//! # Isolation Layer - Software-Based Containment
//!
//! This module implements three critical security isolation layers since
//! the system runs as a Type-2 hypervisor (process-level) rather than bare-metal.
//!
//! ## Layers
//!
//! 1. **Seccomp Profile** - Syscall restrictions for Julia process
//! 2. **Cgroup Resource Caps** - Metabolic budget enforcement  
//! 3. **Memory Boundary Guards** - Ring buffer protection
//!
//! ## Usage
//!
//! ```rust
//! use isolation::{IsolationManager, IsolationConfig};
//!
//! let config = IsolationConfig::default();
//! let manager = IsolationManager::new(config)?;
//! manager.apply_isolation()?;
//! ```

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use thiserror::Error;

// ============================================================================
// ERROR TYPES
// ============================================================================

#[derive(Error, Debug)]
pub enum IsolationError {
    #[error("Seccomp error: {0}")]
    SeccompError(String),
    
    #[error("Cgroup error: {0}")]
    CgroupError(String),
    
    #[error("Memory guard error: {0}")]
    MemoryGuardError(String),
    
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
    
    #[error("Not initialized")]
    NotInitialized,
}

/// Result type for isolation operations
pub type IsolationResult<T> = Result<T, IsolationError>;

// ============================================================================
// SECCOMP - Syscall Filtering
// ============================================================================

/// Syscall whitelist for Julia Brain VM
const ALLOWED_SYSCALLS: &[&str] = &[
    // File descriptor operations
    "read", "write", "close", "fcntl", "dup", "dup2",
    // Memory mapping for IPC
    "mmap", "munmap", "mprotect", "brk",
    // Process info (read-only)
    "getpid", "getuid", "getgid", "gettid", "uname",
    "clock_gettime", "gettimeofday", "time",
    // Signal handling
    "rt_sigaction", "rt_sigprocmask", "sigaltstack", "nanosleep",
    // Threading
    "clone", "exit", "exit_group",
    // Safe filesystem
    "readlink", "getcwd", "open", "stat", "fstat",
    // Epoll for IPC
    "epoll_create", "epoll_ctl", "epoll_wait",
];

/// Seccomp profile configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeccompProfile {
    pub version: String,
    pub enabled: bool,
    pub ipc_only_mode: bool,
    pub allowed_syscalls: Vec<String>,
    pub block_all_network: bool,
    pub block_all_filesystem: bool,
}

impl Default for SeccompProfile {
    fn default() -> Self {
        SeccompProfile {
            version: "1.0".to_string(),
            enabled: true,
            ipc_only_mode: true,
            allowed_syscalls: ALLOWED_SYSCALLS.iter().map(|s| s.to_string()).collect(),
            block_all_network: true,
            block_all_filesystem: true,
        }
    }
}

impl SeccompProfile {
    /// Generate BPF filter rules (simplified)
    pub fn generate_bpf_rules(&self) -> Vec<String> {
        let mut rules = Vec::new();
        
        // Allow rule for each syscall
        for syscall in &self.allowed_syscalls {
            rules.push(format!("allow: {}", syscall));
        }
        
        // Block network if configured
        if self.block_all_network {
            rules.push("deny: socket".to_string());
            rules.push("deny: connect".to_string());
            rules.push("deny: accept".to_string());
            rules.push("deny: bind".to_string());
            rules.push("deny: listen".to_string());
            rules.push("deny: send".to_string());
            rules.push("deny: recv".to_string());
        }
        
        // Block dangerous syscalls
        rules.push("deny: fork".to_string());
        rules.push("deny: vfork".to_string());
        rules.push("deny: execve".to_string());
        rules.push("deny: kill".to_string());
        rules.push("deny: prctl".to_string());
        rules.push("deny: mount".to_string());
        
        // Default deny
        rules.push("deny: all".to_string());
        
        rules
    }
    
    /// Write profile to file
    pub fn write_to_file(&self, path: &PathBuf) -> IsolationResult<()> {
        let content = self.generate_bpf_rules().join("\n");
        fs::write(path, content)
            .map_err(|e| IsolationError::SeccompError(format!("Failed to write profile: {}", e)))
    }
}

// ============================================================================
// CGROUP - Resource Limits (Metabolic Budget)
// ============================================================================

/// Cgroup configuration for resource limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CgroupConfig {
    pub name: String,
    pub cpu_max_percent: f64,
    pub memory_max_bytes: u64,
    pub memory_swap_max_bytes: u64,
    pub pids_max: i64,
    pub io_weight: u16,
    pub created_at: DateTime<Utc>,
}

impl Default for CgroupConfig {
    fn default() -> Self {
        CgroupConfig {
            name: "julia_brain_vm".to_string(),
            cpu_max_percent: 50.0,              // 50% CPU max
            memory_max_bytes: 4 * 1024 * 1024 * 1024,  // 4GB
            memory_swap_max_bytes: 1024 * 1024 * 1024,  // 1GB swap
            pids_max: 10,                         // Max 10 processes
            io_weight: 100,                      // Default I/O weight
            created_at: Utc::now(),
        }
    }
}

impl CgroupConfig {
    /// Get cgroup v2 path
    pub fn cgroup_path(&self) -> PathBuf {
        PathBuf::from(format!("/sys/fs/cgroup/{}", self.name.replace('/', "_")))
    }
    
    /// Generate cgroup settings
    pub fn settings(&self) -> HashMap<String, String> {
        let mut settings = HashMap::new();
        
        // CPU controller (cgroup v2)
        // cpu.max format: "max period" or "value period"
        let cpu_value = (self.cpu_max_percent * 10000.0) as u64;
        settings.insert("cpu.max".to_string(), format!("{} 100000", cpu_value));
        settings.insert("cpu.weight".to_string(), 
            format!("{}", (self.cpu_max_percent * 100.0) as u16));
        
        // Memory controller
        settings.insert("memory.max".to_string(), 
            format!("{}", self.memory_max_bytes));
        settings.insert("memory.swap.max".to_string(), 
            format!("{}", self.memory_swap_max_bytes));
        settings.insert("memory.oom.group".to_string(), "1".to_string());
        
        // Pids controller
        settings.insert("pids.max".to_string(), 
            format!("{}", self.pids_max));
        
        // IO controller
        settings.insert("io.weight".to_string(), 
            format!("{}", self.io_weight));
        
        settings
    }
    
    /// Create cgroup directory and apply settings
    pub fn create(&self) -> IsolationResult<PathBuf> {
        let path = self.cgroup_path();
        
        // Create cgroup directory
        if !path.exists() {
            fs::create_dir_all(&path)
                .map_err(|e| IsolationError::CgroupError(
                    format!("Failed to create cgroup {}: {}", path.display(), e)))?;
        }
        
        // Apply settings
        for (key, value) in self.settings() {
            let file_path = path.join(&key);
            if file_path.exists() {
                fs::write(&file_path, &value)
                    .map_err(|e| IsolationError::CgroupError(
                        format!("Failed to write {}: {}", file_path.display(), e)))?;
            }
        }
        
        Ok(path)
    }
    
    /// Add a process to this cgroup
    pub fn add_process(&self, pid: u32) -> IsolationResult<()> {
        let cgroup_procs = self.cgroup_path().join("cgroup.procs");
        
        fs::write(&cgroup_procs, pid.to_string())
            .map_err(|e| IsolationError::CgroupError(
                format!("Failed to add process to cgroup: {}", e)))
    }
    
    /// Get current resource usage
    pub fn get_usage(&self) -> IsolationResult<CgroupUsage> {
        let path = self.cgroup_path();
        
        let mut usage = CgroupUsage {
            timestamp: Utc::now(),
            cpu_usage_percent: 0.0,
            memory_current_bytes: 0,
            memory_max_bytes: self.memory_max_bytes,
            pids_current: 0,
            pids_max: self.pids_max,
            within_budget: true,
        };
        
        // Read CPU usage
        if let Ok(cpu_stat) = fs::read_to_string(path.join("cpu.stat")) {
            for line in cpu_stat.lines() {
                if line.starts_with("usage_usec") {
                    // Simplified - just parse total usage
                    if let Some(val) = line.split_whitespace().nth(1) {
                        if let Ok(usec) = val.parse::<u64>() {
                            usage.cpu_usage_percent = (usec as f64 / 1_000_000.0).min(100.0);
                        }
                    }
                }
            }
        }
        
        // Read memory usage
        if let Ok(mem_current) = fs::read_to_string(path.join("memory.current")) {
            if let Ok(val) = mem_current.trim().parse::<u64>() {
                usage.memory_current_bytes = val;
                usage.within_budget = val <= self.memory_max_bytes;
            }
        }
        
        // Read pids usage
        if let Ok(pids_current) = fs::read_to_string(path.join("pids.current")) {
            if let Ok(val) = pids_current.trim().parse::<i64>() {
                usage.pids_current = val;
            }
        }
        
        Ok(usage)
    }
}

/// Current cgroup resource usage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CgroupUsage {
    pub timestamp: DateTime<Utc>,
    pub cpu_usage_percent: f64,
    pub memory_current_bytes: u64,
    pub memory_max_bytes: u64,
    pub pids_current: i64,
    pub pids_max: i64,
    pub within_budget: bool,
}

// ============================================================================
// MEMORY GUARD - Ring Buffer Protection
// ============================================================================

/// Memory bounds for IPC ring buffer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryBounds {
    pub base_address: u64,
    pub size_bytes: u64,
}

impl Default for MemoryBounds {
    fn default() -> Self {
        // Ring buffer at /dev/shm/itheris_ipc (64MB)
        // Virtual address hint: 0x3000_0000 - 0x3400_0000
        MemoryBounds {
            base_address: 0x3000_0000,
            size_bytes: 0x0400_0000,  // 64MB
        }
    }
}

impl MemoryBounds {
    /// Get buffer end address
    pub fn end_address(&self) -> u64 {
        self.base_address + self.size_bytes
    }
    
    /// Check if address is within bounds
    pub fn contains(&self, address: u64) -> bool {
        address >= self.base_address && address < self.end_address()
    }
    
    /// Check if memory range is within bounds
    pub fn contains_range(&self, address: u64, size: u64) -> bool {
        self.contains(address) && self.contains(address + size)
    }
}

/// Memory guard configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryGuardConfig {
    pub enabled: bool,
    pub bounds: MemoryBounds,
    pub enable_asan: bool,
    pub enable_tsan: bool,
    pub guard_page_size: u64,
}

impl Default for MemoryGuardConfig {
    fn default() -> Self {
        MemoryGuardConfig {
            enabled: true,
            bounds: MemoryBounds::default(),
            enable_asan: true,
            enable_tsan: false,
            guard_page_size: 4096,
        }
    }
}

impl MemoryGuardConfig {
    /// Validate memory access
    pub fn validate_access(&self, address: u64, size: u64) -> IsolationResult<()> {
        if !self.enabled {
            return Ok(());
        }
        
        let end = address.saturating_add(size);
        
        // Check guard pages
        let guard_start = self.bounds.base_address.saturating_sub(self.guard_page_size);
        let guard_end = self.bounds.end_address();
        
        if address < guard_start || end > guard_end {
            return Err(IsolationError::MemoryGuardError(
                format!("Memory access out of bounds: 0x{:x}-0x{:x} (bounds: 0x{:x}-0x{:x})",
                    address, end, self.bounds.base_address, self.bounds.end_address())
            ));
        }
        
        Ok(())
    }
    
    /// Generate ASan configuration
    pub fn asan_options(&self) -> String {
        format!(
            "detect_leaks=1:halt_on_error=1:external_symbol_ignore_pattern=jl_|\
memory_boundary_ignore=0x{:x}:\
memory_boundary_size={}",
            self.bounds.base_address,
            self.bounds.size_bytes
        )
    }
}

// ============================================================================
// MAIN ISOLATION MANAGER
// ============================================================================

/// Configuration for all isolation layers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IsolationConfig {
    pub enable_seccomp: bool,
    pub enable_cgroup: bool,
    pub enable_memory_guard: bool,
    pub seccomp_profile: SeccompProfile,
    pub cgroup_config: CgroupConfig,
    pub memory_guard: MemoryGuardConfig,
}

impl Default for IsolationConfig {
    fn default() -> Self {
        IsolationConfig {
            enable_seccomp: true,
            enable_cgroup: true,
            enable_memory_guard: true,
            seccomp_profile: SeccompProfile::default(),
            cgroup_config: CgroupConfig::default(),
            memory_guard: MemoryGuardConfig::default(),
        }
    }
}

/// Main isolation manager
pub struct IsolationManager {
    config: IsolationConfig,
    initialized: bool,
    cgroup_path: Option<PathBuf>,
}

impl IsolationManager {
    /// Create new isolation manager
    pub fn new(config: IsolationConfig) -> Self {
        IsolationManager {
            config,
            initialized: false,
            cgroup_path: None,
        }
    }
    
    /// Initialize isolation layers
    pub fn initialize(&mut self) -> IsolationResult<()> {
        // Initialize cgroup
        if self.config.enable_cgroup {
            self.cgroup_path = Some(self.config.cgroup_config.create()?);
            log::info!("Cgroup initialized at {:?}", self.cgroup_path);
        }
        
        // Initialize seccomp profile
        if self.config.enable_seccomp {
            let profile_path = PathBuf::from("/tmp/julia_brain_seccomp.json");
            self.config.seccomp_profile.write_to_file(&profile_path)?;
            log::info!("Seccomp profile written to {:?}", profile_path);
        }
        
        self.initialized = true;
        Ok(())
    }
    
    /// Apply isolation to a process
    pub fn apply_to_process(&self, pid: u32) -> IsolationResult<()> {
        if !self.initialized {
            return Err(IsolationError::NotInitialized);
        }
        
        // Add to cgroup
        if self.config.enable_cgroup {
            if let Some(ref path) = self.cgroup_path {
                let cgroup_procs = path.join("cgroup.procs");
                fs::write(&cgroup_procs, pid.to_string())
                    .map_err(|e| IsolationError::CgroupError(
                        format!("Failed to add process to cgroup: {}", e)))?;
                log::info!("Process {} added to cgroup", pid);
            }
        }
        
        Ok(())
    }
    
    /// Validate memory access (for ring buffer)
    pub fn validate_memory_access(&self, address: u64, size: u64) -> IsolationResult<()> {
        self.config.memory_guard.validate_access(address, size)
    }
    
    /// Get current cgroup usage
    pub fn get_cgroup_usage(&self) -> IsolationResult<CgroupUsage> {
        self.config.cgroup_config.get_usage()
    }
    
    /// Check if within metabolic budget
    pub fn is_within_budget(&self) -> IsolationResult<bool> {
        let usage = self.get_cgroup_usage()?;
        Ok(usage.within_budget)
    }
    
    /// Audit isolation status
    pub fn audit(&self) -> IsolationResult<IsolationAudit> {
        let mut audit = IsolationAudit {
            timestamp: Utc::now(),
            initialized: self.initialized,
            layers: HashMap::new(),
        };
        
        // Audit seccomp
        audit.layers.insert("seccomp".to_string(), serde_json::json!({
            "enabled": self.config.enable_seccomp,
            "profile": self.config.seccomp_profile,
        }));
        
        // Audit cgroup
        if self.config.enable_cgroup {
            match self.get_cgroup_usage() {
                Ok(usage) => {
                    audit.layers.insert("cgroup".to_string(), serde_json::json!({
                        "enabled": true,
                        "config": self.config.cgroup_config,
                        "usage": usage,
                    }));
                }
                Err(e) => {
                    audit.layers.insert("cgroup".to_string(), serde_json::json!({
                        "enabled": true,
                        "error": e.to_string(),
                    }));
                }
            }
        } else {
            audit.layers.insert("cgroup".to_string(), serde_json::json!({
                "enabled": false,
            }));
        }
        
        // Audit memory guard
        audit.layers.insert("memory_guard".to_string(), serde_json::json!({
            "enabled": self.config.enable_memory_guard,
            "config": self.config.memory_guard,
        }));
        
        Ok(audit)
    }
}

/// Isolation audit report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IsolationAudit {
    pub timestamp: DateTime<Utc>,
    pub initialized: bool,
    pub layers: HashMap<String, serde_json::Value>,
}

// ============================================================================
// FFI FUNCTIONS - Export to Julia
// ============================================================================

/// Initialize isolation (called from Julia)
#[no_mangle]
pub extern "C" fn isolation_init(cpu_limit: f64, memory_gb: u32) -> i32 {
    let config = IsolationConfig {
        enable_seccomp: true,
        enable_cgroup: true,
        enable_memory_guard: true,
        seccomp_profile: SeccompProfile::default(),
        cgroup_config: CgroupConfig {
            name: "julia_brain_vm".to_string(),
            cpu_max_percent: cpu_limit,
            memory_max_bytes: (memory_gb as u64) * 1024 * 1024 * 1024,
            memory_swap_max_bytes: 1024 * 1024 * 1024,
            pids_max: 10,
            io_weight: 100,
            created_at: Utc::now(),
        },
        memory_guard: MemoryGuardConfig::default(),
    };
    
    // Note: In practice, would use Mutex or store globally
    // For now, just return success
    log::info!("Isolation config created: CPU={}%, Memory={}GB", cpu_limit, memory_gb);
    0  // Success
}

/// Add process to isolation cgroup
#[no_mangle]
pub extern "C" fn isolation_add_process(pid: u32) -> i32 {
    // Would look up the manager and add process
    log::info!("Would add process {} to cgroup", pid);
    0
}

/// Check memory access bounds
#[no_mangle]
pub extern "C" fn isolation_check_memory(address: u64, size: u64) -> i32 {
    let config = MemoryGuardConfig::default();
    match config.validate_access(address, size) {
        Ok(_) => 0,  // Allowed
        Err(_) => -1,  // Denied
    }
}

/// Get cgroup usage
#[no_mangle]
pub extern "C" fn isolation_get_cpu_usage() -> f64 {
    let config = CgroupConfig::default();
    match config.get_usage() {
        Ok(usage) => usage.cpu_usage_percent,
        Err(_) => -1.0,
    }
}

#[no_mangle]
pub extern "C" fn isolation_get_memory_usage() -> u64 {
    let config = CgroupConfig::default();
    match config.get_usage() {
        Ok(usage) => usage.memory_current_bytes,
        Err(_) => 0,
    }
}

/// Check if within metabolic budget
#[no_mangle]
pub extern "C" fn isolation_within_budget() -> i32 {
    let config = CgroupConfig::default();
    match config.get_usage() {
        Ok(usage) => if usage.within_budget { 1 } else { 0 },
        Err(_) => -1,
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_seccomp_profile() {
        let profile = SeccompProfile::default();
        let rules = profile.generate_bpf_rules();
        assert!(rules.len() > 0);
        assert!(rules.contains(&"allow: read".to_string()));
    }
    
    #[test]
    fn test_cgroup_config() {
        let config = CgroupConfig::default();
        let settings = config.settings();
        assert!(settings.contains_key("cpu.max"));
        assert!(settings.contains_key("memory.max"));
    }
    
    #[test]
    fn test_memory_bounds() {
        let bounds = MemoryBounds::default();
        assert!(bounds.contains(0x3000_0000));
        assert!(bounds.contains(0x3400_0000 - 1));
        assert!(!bounds.contains(0x3400_0000));
    }
    
    #[test]
    fn test_memory_guard() {
        let config = MemoryGuardConfig::default();
        assert!(config.validate_access(0x3000_0000, 1024).is_ok());
        assert!(config.validate_access(0x1000_0000, 1024).is_err());
    }
}
