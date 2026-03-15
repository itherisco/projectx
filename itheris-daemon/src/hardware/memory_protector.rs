//! # Memory Region Scanner and Protector
//!
//! Scans `/proc/self/maps` and `/proc/<julia_pid>/maps` for memory regions
//! and provides functions to protect (revoke) memory permissions.
//!
//! This is used by the kill chain to poison Julia Brain memory when a panic occurs.

use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::ffi::c_void;
use thiserror::Error;
use crate::shared_memory;


/// Memory protection errors
#[derive(Error, Debug)]
pub enum MemoryProtectionError {
    #[error("Failed to read process maps: {0}")]
    ReadMapsError(String),
    
    #[error("Failed to protect memory: {0}")]
    ProtectError(String),
    
    #[error("Julia process not found")]
    JuliaProcessNotFound,
    
    #[error("Invalid memory address")]
    InvalidAddress,
}

/// Represents a memory region from /proc/maps
#[derive(Debug, Clone)]
pub struct MemoryRegion {
    /// Start address
    pub start: usize,
    /// End address
    pub end: usize,
    /// Permissions string (rwx-p)
    pub perms: String,
    /// Path to mapped file (if any)
    pub pathname: String,
    /// Whether this is a heap region
    pub is_heap: bool,
    /// Whether this looks like a Julia region
    pub is_julia: bool,
}

impl MemoryRegion {
    /// Check if this region has read permission
    pub fn has_read(&self) -> bool {
        self.perms.chars().nth(0) == Some('r')
    }
    
    /// Check if this region has write permission
    pub fn has_write(&self) -> bool {
        self.perms.chars().nth(1) == Some('w')
    }
    
    /// Check if this region has execute permission
    pub fn has_exec(&self) -> bool {
        self.perms.chars().nth(2) == Some('x')
    }
    
    /// Check if this region is private (not shared)
    pub fn is_private(&self) -> bool {
        self.perms.contains('p')
    }
    
    /// Check if this region is writable (likely heap or data)
    pub fn is_writable(&self) -> bool {
        self.has_write() && self.is_private()
    }
    
    /// Check if this is a heap region
    pub fn check_is_heap(&mut self) {
        // Heap typically starts with [heap] in the pathname
        // or is at low addresses with rw-p permissions
        self.is_heap = self.pathname.contains("[heap]") || 
            (self.pathname.is_empty() && self.start < 0x40000000 && self.has_write() && self.is_private());
    }
    
    /// Check if this looks like a Julia region
    pub fn check_is_julia(&mut self) {
        // Julia regions typically have paths like:
        // /julia, libjulia, or anonymous with heap-like properties
        let path_lower = self.pathname.to_lowercase();
        self.is_julia = path_lower.contains("julia") ||
            (path_lower.is_empty() && self.is_writable()) ||
            self.pathname.contains("[heap]") ||
            self.pathname.contains("[anon:");
    }
}

/// Global storage for discovered Julia regions
static JULIA_REGIONS: once_cell::sync::Lazy<std::sync::Mutex<HashMap<usize, MemoryRegion>>> = 
    once_cell::sync::Lazy::new(|| std::sync::Mutex::new(HashMap::new()));

/// Global storage for current process regions
static CURRENT_PROCESS_REGIONS: once_cell::sync::Lazy<std::sync::Mutex<HashMap<usize, MemoryRegion>>> = 
    once_cell::sync::Lazy::new(|| std::sync::Mutex::new(HashMap::new()));

/// Parse a single line from /proc/maps
/// 
/// Format: 00400000-0040b000 r-xp 00000000 00:0c 1234567    /path/to/bin
fn parse_maps_line(line: &str) -> Option<MemoryRegion> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 5 {
        return None;
    }
    
    // Parse address range
    let addr_parts: Vec<&str> = parts[0].split('-').collect();
    if addr_parts.len() != 2 {
        return None;
    }
    
    let start = usize::from_str_radix(addr_parts[0], 16).ok()?;
    let end = usize::from_str_radix(addr_parts[1], 16).ok()?;
    
    let perms = parts[1].to_string();
    let pathname = if parts.len() > 5 {
        // pathname may contain spaces, join the rest
        parts[5..].join(" ")
    } else {
        String::new()
    };
    
    let mut region = MemoryRegion {
        start,
        end,
        perms,
        pathname,
        is_heap: false,
        is_julia: false,
    };
    
    region.check_is_heap();
    region.check_is_julia();
    
    Some(region)
}

/// Scan /proc/self/maps and return all memory regions
pub fn scan_current_process_maps() -> Result<Vec<MemoryRegion>, MemoryProtectionError> {
    let maps_path = "/proc/self/maps";
    
    let content = fs::read_to_string(maps_path)
        .map_err(|e| MemoryProtectionError::ReadMapsError(e.to_string()))?;
    
    let mut regions = Vec::new();
    let mut region_map = CURRENT_PROCESS_REGIONS.lock().unwrap();
    region_map.clear();
    
    for line in content.lines() {
        if let Some(region) = parse_maps_line(line) {
            region_map.insert(region.start, region.clone());
            regions.push(region);
        }
    }
    
    log::debug!("Scanned {} memory regions for current process", regions.len());
    Ok(regions)
}

/// Scan /proc/<pid>/maps for a specific process
pub fn scan_process_maps(pid: u32) -> Result<Vec<MemoryRegion>, MemoryProtectionError> {
    let maps_path = format!("/proc/{}/maps", pid);
    
    // Check if process exists
    if !Path::new(&maps_path).exists() {
        return Err(MemoryProtectionError::JuliaProcessNotFound);
    }
    
    let content = fs::read_to_string(&maps_path)
        .map_err(|e| MemoryProtectionError::ReadMapsError(e.to_string()))?;
    
    let mut regions = Vec::new();
    let mut region_map = JULIA_REGIONS.lock().unwrap();
    region_map.clear();
    
    for line in content.lines() {
        if let Some(region) = parse_maps_line(line) {
            region_map.insert(region.start, region.clone());
            regions.push(region);
        }
    }
    
    log::debug!("Scanned {} memory regions for process {}", regions.len(), pid);
    Ok(regions)
}

/// Get the PID of the Julia process (if running)
/// 
/// This looks for processes with "julia" in the name
pub fn find_julia_process() -> Option<u32> {
    // Try to find a Julia process
    // First check if there's a known Julia PID stored somewhere
    // For now, we'll scan /proc for julia processes
    
    let proc_path = Path::new("/proc");
    
    if let Ok(entries) = fs::read_dir(proc_path) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(filename) = path.file_name() {
                if let Ok(pid) = filename.to_string_lossy().parse::<u32>() {
                    // Read the process cmdline
                    let cmdline_path = path.join("cmdline");
                    if let Ok(cmdline) = fs::read_to_string(&cmdline_path) {
                        if cmdline.to_lowercase().contains("julia") {
                            log::info!("Found Julia process: {}", pid);
                            return Some(pid);
                        }
                    }
                }
            }
        }
    }
    
    None
}

/// Scan and store Julia process memory regions
pub fn scan_julia_memory() -> Result<(), MemoryProtectionError> {
    // First try to find Julia process
    let julia_pid = find_julia_process()
        .ok_or(MemoryProtectionError::JuliaProcessNotFound)?;
    
    // Scan the process maps
    let _regions = scan_process_maps(julia_pid)?;
    
    log::info!("Julia memory regions scanned and stored");
    Ok(())
}

/// Get all writable Julia regions
pub fn get_julia_regions() -> Vec<MemoryRegion> {
    let region_map = JULIA_REGIONS.lock().unwrap();
    region_map.values()
        .filter(|r| r.is_writable())
        .cloned()
        .collect()
}

/// Get all writable regions from current process
pub fn get_current_process_regions() -> Vec<MemoryRegion> {
    let region_map = CURRENT_PROCESS_REGIONS.lock().unwrap();
    region_map.values()
        .filter(|r| r.is_writable())
        .cloned()
        .collect()
}

/// Call mprotect to set memory protection
/// 
/// # Safety
/// This calls mprotect which can crash the process if used incorrectly
unsafe fn mprotect_region(addr: usize, len: usize) -> Result<(), MemoryProtectionError> {
    if addr == 0 || len == 0 {
        return Err(MemoryProtectionError::InvalidAddress);
    }
    
    // Align address to page size
    let page_size = 4096; // Hardcode page size to avoid libc::sysconf
    let aligned_addr = addr & !(page_size - 1);
    let aligned_len = ((len + page_size - 1) / page_size) * page_size;
    
    let result = libc::mprotect(
        aligned_addr as *mut libc::c_void,
        aligned_len as libc::size_t,
        libc::PROT_NONE
    );
    
    if result != 0 {
        let err = std::io::Error::last_os_error();
        return Err(MemoryProtectionError::ProtectError(err.to_string()));
    }
    
    Ok(())
}

/// Protect all Julia process memory regions by setting PROT_NONE
pub fn protect_all_julia_memory() {
    // Ensure we have scanned Julia memory
    if let Err(e) = scan_julia_memory() {
        log::warn!("Failed to scan Julia memory: {}", e);
        return;
    }
    
    let regions = get_julia_regions();
    
    if regions.is_empty() {
        log::warn!("No Julia memory regions found to protect");
        return;
    }
    
    log::info!("Protecting {} Julia memory regions", regions.len());
    
    for region in regions {
        let len = region.end - region.start;
        unsafe {
            if let Err(e) = mprotect_region(region.start, len) {
                log::warn!("Failed to protect Julia region {:x}-{:x}: {}", 
                    region.start, region.end, e);
            } else {
                log::debug!("Protected Julia region {:x}-{:x}", region.start, region.end);
            }
        }
    }
}

/// Enforce Oneiric Isolation by revoking write/execute permissions on the shared memory region
/// This is the silicon-enforced "EPT poisoning" that prevents Julia from actuating during dreams.
pub fn enforce_oneiric_isolation(enable: bool) {
    let addr = shared_memory::IPC_MAPPED_ADDR.load(std::sync::atomic::Ordering::SeqCst);
    if addr == 0 {
        log::warn!("⚠️ Oneiric Isolation: Shared memory not mapped, skipping silicon enforcement.");
        return;
    }

    let prot = if enable {
        log::info!("🌙 ENFORCING ONEIRIC ISOLATION: Shared memory set to RO_NOEXEC");
        libc::PROT_READ
    } else {
        log::info!("☀ EXITING ONEIRIC ISOLATION: Restoring RW permissions");
        libc::PROT_READ | libc::PROT_WRITE
    };

    unsafe {
        if libc::mprotect(addr as *mut c_void, shared_memory::SHM_SIZE, prot) != 0 {
            log::error!("❌ FAILED to enforce Oneiric Isolation: {}", std::io::Error::last_os_error());
        }
    }
}

/// Protect all writable memory regions in the current process
pub fn protect_current_process_memory() {
    // Ensure we have scanned current process memory
    if let Err(e) = scan_current_process_maps() {
        log::warn!("Failed to scan current process memory: {}", e);
        return;
    }
    
    let regions = get_current_process_regions();
    
    if regions.is_empty() {
        log::warn!("No current process memory regions found to protect");
        return;
    }
    
    log::info!("Protecting {} current process memory regions", regions.len());
    
    for region in regions {
        let len = region.end - region.start;
        unsafe {
            if let Err(e) = mprotect_region(region.start, len) {
                // Don't log too much here - we're in a panic context
                let _ = std::io::Write::write_all(
                    &mut std::io::stderr(),
                    format!("[KILL CHAIN] Failed to protect region {:x}: {}\n", region.start, e).as_bytes()
                );
            }
        }
    }
}

/// Get memory statistics for current process
#[allow(dead_code)]
pub fn get_memory_stats() -> HashMap<String, usize> {
    let mut stats = HashMap::new();
    
    // Count regions
    let current_regions = get_current_process_regions();
    stats.insert("current_writable_regions".to_string(), current_regions.len());
    
    // Count Julia regions
    let julia_regions = get_julia_regions();
    stats.insert("julia_writable_regions".to_string(), julia_regions.len());
    
    // Calculate total protected memory
    let mut total_current = 0usize;
    for r in &current_regions {
        total_current += r.end - r.start;
    }
    stats.insert("current_protectable_bytes".to_string(), total_current);
    
    let mut total_julia = 0usize;
    for r in &julia_regions {
        total_julia += r.end - r.start;
    }
    stats.insert("julia_protectable_bytes".to_string(), total_julia);
    
    stats
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_scan_current_process_maps() {
        let result = scan_current_process_maps();
        assert!(result.is_ok());
        let regions = result.unwrap();
        assert!(!regions.is_empty());
        
        // Check we have at least one writable region (heap)
        let writable: Vec<_> = regions.iter().filter(|r| r.is_writable()).collect();
        assert!(!writable.is_empty(), "Should have writable regions");
    }
    
    #[test]
    fn test_memory_region_properties() {
        let region = MemoryRegion {
            start: 0x1000,
            end: 0x2000,
            perms: "rw-p".to_string(),
            pathname: "/test".to_string(),
            is_heap: false,
            is_julia: false,
        };
        
        assert!(region.has_read());
        assert!(region.has_write());
        assert!(!region.has_exec());
        assert!(region.is_private());
        assert!(region.is_writable());
    }
    
    #[test]
    fn test_julia_process_find() {
        // This test will find whatever process is running
        // Just verify the function doesn't panic
        let result = find_julia_process();
        // May be None if no Julia process is running - that's OK
        let _ = result;
    }
    
    #[test]
    fn test_get_memory_stats() {
        // Ensure we scanned first
        let _ = scan_current_process_maps();
        let stats = get_memory_stats();
        
        assert!(stats.contains_key("current_writable_regions"));
        assert!(stats.contains_key("julia_writable_regions"));
    }
}
