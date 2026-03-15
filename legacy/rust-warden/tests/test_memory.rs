//! Memory management unit tests
//! 
//! Tests for physical memory allocation, EPT table construction,
//! memory region boundaries, and permission flag combinations.

#![cfg(feature = "mock")]

use crate::common::{
    MockEptEntry, EptLevel, EptMemoryType, MockMemoryRegion, MemoryPermissions,
    MemoryRegionType,
};
use core::cell::UnsafeCell;
use core::sync::atomic::{AtomicU64, Ordering};

// ============================================================================
// Physical Memory Allocation Tests
// ============================================================================

/// Test basic memory region creation
#[test]
fn test_memory_region_creation() {
    let region = MockMemoryRegion::new(0x100000, 0x100000); // 1MB region at 1MB
    
    assert_eq!(region.base_address, 0x100000, "Base address should match");
    assert_eq!(region.size, 0x100000, "Size should match");
    assert!(!region.is_allocated, "Region should not be allocated initially");
}

/// Test memory region allocation
#[test]
fn test_memory_region_allocation() {
    let mut region = MockMemoryRegion::new(0x100000, 0x100000);
    
    region.is_allocated = true;
    
    assert!(region.is_allocated, "Region should be allocated");
}

/// Test memory region contains address
#[test]
fn test_memory_region_contains() {
    let region = MockMemoryRegion::new(0x100000, 0x100000);
    
    assert!(region.contains(0x100000), "Should contain base address");
    assert!(region.contains(0x150000), "Should contain middle address");
    assert!(region.contains(0x1FFFFF), "Should contain last byte");
    assert!(!region.contains(0x0FFFFF), "Should not contain address below base");
    assert!(!region.contains(0x200000), "Should not contain address above top");
}

/// Test memory region overlap detection
#[test]
fn test_memory_region_overlap() {
    let region1 = MockMemoryRegion::new(0x100000, 0x100000);
    let region2 = MockMemoryRegion::new(0x150000, 0x100000); // Overlaps
    let region3 = MockMemoryRegion::new(0x200000, 0x100000); // No overlap
    
    assert!(region1.overlaps(&region2), "Regions should overlap");
    assert!(!region1.overlaps(&region3), "Regions should not overlap");
}

/// Test memory region non-overlap with adjacent regions
#[test]
fn test_memory_region_adjacent() {
    let region1 = MockMemoryRegion::new(0x100000, 0x100000);
    let region2 = MockMemoryRegion::new(0x200000, 0x100000); // Adjacent, no overlap
    
    assert!(!region1.overlaps(&region2), "Adjacent regions should not overlap");
}

// ============================================================================
// Memory Permissions Tests
// ============================================================================

/// Test default memory permissions
#[test]
fn test_memory_permissions_default() {
    let perms = MemoryPermissions::default();
    
    assert!(!perms.readable, "Default should not be readable");
    assert!(!perms.writable, "Default should not be writable");
    assert!(!perms.executable, "Default should not be executable");
}

/// Test read-only memory permissions
#[test]
fn test_memory_permissions_readonly() {
    let perms = MemoryPermissions {
        readable: true,
        writable: false,
        executable: false,
    };
    
    assert!(perms.readable, "Should be readable");
    assert!(!perms.writable, "Should not be writable");
    assert!(!perms.executable, "Should not be executable");
}

/// Test read-write memory permissions
#[test]
fn test_memory_permissions_readwrite() {
    let perms = MemoryPermissions {
        readable: true,
        writable: true,
        executable: false,
    };
    
    assert!(perms.readable, "Should be readable");
    assert!(perms.writable, "Should be writable");
    assert!(!perms.executable, "Should not be executable");
}

/// Test read-write-execute permissions
#[test]
fn test_memory_permissions_full() {
    let perms = MemoryPermissions {
        readable: true,
        writable: true,
        executable: true,
    };
    
    assert!(perms.readable, "Should be readable");
    assert!(perms.writable, "Should be writable");
    assert!(perms.executable, "Should be executable");
}

/// Test memory region with permissions
#[test]
fn test_memory_region_with_permissions() {
    let region = MockMemoryRegion::new(0x100000, 0x100000)
        .with_permissions(MemoryPermissions {
            readable: true,
            writable: true,
            executable: false,
        });
    
    assert!(region.permissions.readable);
    assert!(region.permissions.writable);
    assert!(!region.permissions.executable);
}

// ============================================================================
// Memory Region Type Tests
// ============================================================================

/// Test RAM region type
#[test]
fn test_memory_region_type_ram() {
    let region = MockMemoryRegion::new(0x100000, 0x100000)
        .with_type(MemoryRegionType::Ram);
    
    assert_eq!(region.region_type, MemoryRegionType::Ram);
}

/// Test MMIO region type
#[test]
fn test_memory_region_type_mmio() {
    let region = MockMemoryRegion::new(0xFED00000, 0x100000)
        .with_type(MemoryRegionType::Mmio);
    
    assert_eq!(region.region_type, MemoryRegionType::Mmio);
}

/// Test reserved region type
#[test]
fn test_memory_region_type_reserved() {
    let region = MockMemoryRegion::new(0xFEE00000, 0x20000)
        .with_type(MemoryRegionType::Reserved);
    
    assert_eq!(region.region_type, MemoryRegionType::Reserved);
}

/// Test unavailable region type
#[test]
fn test_memory_region_type_unavailable() {
    let region = MockMemoryRegion::new(0xFFFF0000, 0x10000)
        .with_type(MemoryRegionType::Unavailable);
    
    assert_eq!(region.region_type, MemoryRegionType::Unavailable);
}

// ============================================================================
// EPT Table Construction Tests
// ============================================================================

/// Test EPT entry creation
#[test]
fn test_ept_entry_creation() {
    let entry = MockEptEntry::new(EptLevel::Pt);
    
    assert!(entry.read_access, "Default should allow read");
    assert!(entry.write_access, "Default should allow write");
    assert!(entry.execute_access, "Default should allow execute");
    assert_eq!(entry.memory_type, EptMemoryType::WriteBack, "Default should be WriteBack");
    assert_eq!(entry.level, EptLevel::Pt);
}

/// Test EPT PML4 entry
#[test]
fn test_ept_pml4_entry() {
    let entry = MockEptEntry::new(EptLevel::Pml4);
    
    assert_eq!(entry.level, EptLevel::Pml4);
    assert!(entry.read_access, "PML4 should allow read");
}

/// Test EPT PDPT entry
#[test]
fn test_ept_pdpt_entry() {
    let entry = MockEptEntry::new(EptLevel::Pdpt);
    
    assert_eq!(entry.level, EptLevel::Pdpt);
    assert!(entry.read_access, "PDPT should allow read");
}

/// Test EPT PD entry
#[test]
fn test_ept_pd_entry() {
    let entry = MockEptEntry::new(EptLevel::Pd);
    
    assert_eq!(entry.level, EptLevel::Pd);
    assert!(entry.read_access, "PD should allow read");
}

/// Test EPT PT entry
#[test]
fn test_ept_pt_entry() {
    let entry = MockEptEntry::new(EptLevel::Pt);
    
    assert_eq!(entry.level, EptLevel::Pt);
    assert!(entry.read_access, "PT should allow read");
}

/// Test EPT entry to bits conversion
#[test]
fn test_ept_entry_to_bits() {
    let entry = MockEptEntry {
        read_access: true,
        write_access: true,
        execute_access: false,
        memory_type: EptMemoryType::WriteBack,
        level: EptLevel::Pt,
        physical_address: 0x100000,
    };
    
    let bits = entry.to_bits();
    
    // Check read bit (bit 0)
    assert!(bits & 1 != 0, "Read bit should be set");
    // Check write bit (bit 1)
    assert!(bits & 2 != 0, "Write bit should be set");
    // Check execute bit (bit 2)
    assert!(bits & 4 == 0, "Execute bit should not be set");
}

/// Test EPT entry with uncacheable memory
#[test]
fn test_ept_entry_uncacheable() {
    let entry = MockEptEntry {
        read_access: true,
        write_access: true,
        execute_access: true,
        memory_type: EptMemoryType::Uncacheable,
        level: EptLevel::Pt,
        physical_address: 0,
    };
    
    let bits = entry.to_bits();
    // Uncacheable = 0, shift left 3 bits
    assert_eq!(bits & 0x18, 0, "Memory type should be uncacheable");
}

/// Test EPT entry with write-through memory
#[test]
fn test_ept_entry_write_through() {
    let entry = MockEptEntry {
        read_access: true,
        write_access: true,
        execute_access: true,
        memory_type: EptMemoryType::WriteThrough,
        level: EptLevel::Pt,
        physical_address: 0,
    };
    
    let bits = entry.to_bits();
    // WriteThrough = 1, shift left 3 bits = 0x08
    assert_eq!(bits & 0x18, 0x08, "Memory type should be write-through");
}

/// Test EPT entry leaf flag
#[test]
fn test_ept_entry_leaf_flag() {
    let entry = MockEptEntry::new(EptLevel::Pt);
    
    let bits = entry.to_bits();
    // Leaf flag is bit 0x40 (bit 6)
    assert!(bits & 0x40 != 0, "PT entry should have leaf flag");
}

/// Test EPT entry non-leaf flag for page directories
#[test]
fn test_ept_entry_non_leaf_flag() {
    let entry = MockEptEntry::new(EptLevel::Pd);
    
    let bits = entry.to_bits();
    // Non-leaf should not have leaf flag
    assert!(bits & 0x40 == 0, "Non-leaf entry should not have leaf flag");
}

// ============================================================================
// EPT Hierarchy Tests
// ============================================================================

/// Test EPT page walk simulation
#[test]
fn test_ept_page_walk() {
    // Simulate a 4KB page mapping
    let virtual_addr: u64 = 0x0000_1000;
    
    // PML4 index (bits 39-47)
    let pml4_idx = ((virtual_addr >> 39) & 0x1FF) as usize;
    // PDPT index (bits 30-38)
    let pdpt_idx = ((virtual_addr >> 30) & 0x1FF) as usize;
    // PD index (bits 21-29)
    let pd_idx = ((virtual_addr >> 21) & 0x1FF) as usize;
    // PT index (bits 12-20)
    let pt_idx = ((virtual_addr >> 12) & 0x1FF) as usize;
    // Page offset
    let offset = virtual_addr & 0xFFF;
    
    assert_eq!(pml4_idx, 0, "PML4 index should be 0");
    assert_eq!(pdpt_idx, 0, "PDPT index should be 0");
    assert_eq!(pd_idx, 0, "PD index should be 0");
    assert_eq!(pt_idx, 0, "PT index should be 0");
    assert_eq!(offset, 0x1000, "Offset should be 0x1000");
}

/// Test EPT page walk for high memory
#[test]
fn test_ept_page_walk_high_memory() {
    let virtual_addr: u64 = 0xFFFF_FFFF;
    
    let pml4_idx = ((virtual_addr >> 39) & 0x1FF) as usize;
    let pdpt_idx = ((virtual_addr >> 30) & 0x1FF) as usize;
    let pd_idx = ((virtual_addr >> 21) & 0x1FF) as usize;
    let pt_idx = ((virtual_addr >> 12) & 0x1FF) as usize;
    let offset = virtual_addr & 0xFFF;
    
    assert_eq!(pml4_idx, 0x1FF, "PML4 index should be max");
    assert_eq!(pdpt_idx, 0x1FF, "PDPT index should be max");
    assert_eq!(pd_idx, 0x1FF, "PD index should be max");
    assert_eq!(pt_idx, 0x1FF, "PT index should be max");
    assert_eq!(offset, 0xFFF, "Offset should be max");
}

/// Test EPT 2MB page mapping
#[test]
fn test_ept_2mb_page_mapping() {
    // 2MB pages don't use PT level
    let virtual_addr: u64 = 0x0000_200000;
    
    let pml4_idx = ((virtual_addr >> 39) & 0x1FF) as usize;
    let pdpt_idx = ((virtual_addr >> 30) & 0x1FF) as usize;
    let pd_idx = ((virtual_addr >> 21) & 0x1FF) as usize;
    let offset = virtual_addr & 0x1FFFFF;
    
    assert_eq!(pml4_idx, 0);
    assert_eq!(pdpt_idx, 0);
    assert_eq!(pd_idx, 1, "PD index should be 1 for 2MB");
    assert_eq!(offset, 0, "Offset should be 0 for 2MB aligned");
}

// ============================================================================
// Memory Boundary Tests
// ============================================================================

/// Test 32-bit address space boundary
#[test]
fn test_memory_boundary_4gb() {
    let region = MockMemoryRegion::new(0x100000000, 0x10000000);
    
    assert!(region.contains(0x100000000), "Should contain 4GB boundary");
    assert!(region.contains(0x100100000), "Should contain above 4GB");
}

/// Test maximum physical address
#[test]
fn test_memory_max_physical() {
    let max_phys: u64 = 0xFFFF_FFFF_FFFF; // 48-bit physical address max
    
    let region = MockMemoryRegion::new(max_phys - 0x1000, 0x1000);
    
    assert!(region.contains(max_phys - 1), "Should contain last byte");
}

/// Test 1GB boundary
#[test]
fn test_memory_boundary_1gb() {
    let region = MockMemoryRegion::new(0x40000000, 0x10000000);
    
    assert!(region.contains(0x40000000), "Should contain 1GB boundary");
    assert!(region.contains(0x4FFFFFFF), "Should contain end of region");
}

/// Test 2MB boundary (typical huge page)
#[test]
fn test_memory_boundary_2mb() {
    let region = MockMemoryRegion::new(0x200000, 0x100000);
    
    assert!(region.contains(0x200000), "Should contain 2MB boundary");
    assert!(region.contains(0x3FFFFF), "Should contain 2MB + 2MB - 1");
}

// ============================================================================
// Memory Allocation Simulation
// ============================================================================

/// Test memory allocation tracking
#[test]
fn test_memory_allocation_tracking() {
    let mut region = MockMemoryRegion::new(0x100000, 0x100000);
    
    assert!(!region.is_allocated, "Should not be allocated initially");
    
    region.is_allocated = true;
    
    assert!(region.is_allocated, "Should be allocated after allocation");
    
    region.is_allocated = false;
    
    assert!(!region.is_allocated, "Should not be allocated after deallocation");
}

/// Test allocation alignment
#[test]
fn test_allocation_alignment() {
    // Test that all alignments are power of 2
    let alignments = [0x1000, 0x2000, 0x10000, 0x100000, 0x1000000];
    
    for &align in &alignments {
        assert!(align.is_power_of_two(), "Alignment {} should be power of 2", align);
    }
}

/// Test page size constants
#[test]
fn test_page_sizes() {
    const PAGE_4KB: u64 = 0x1000;
    const PAGE_2MB: u64 = 0x200000;
    const PAGE_1GB: u64 = 0x40000000;
    
    assert_eq!(PAGE_4KB, 4096, "4KB page size");
    assert_eq!(PAGE_2MB, 2097152, "2MB page size");
    assert_eq!(PAGE_1GB, 1073741824, "1GB page size");
    
    // Verify relationships
    assert_eq!(PAGE_2MB / PAGE_4KB, 512, "2MB = 512 * 4KB");
    assert_eq!(PAGE_1GB / PAGE_2MB, 512, "1GB = 512 * 2MB");
}

// ============================================================================
// Edge Cases
// ============================================================================

/// Test zero-sized memory region
#[test]
fn test_zero_sized_region() {
    let region = MockMemoryRegion::new(0x100000, 0);
    
    assert_eq!(region.size, 0, "Size should be 0");
    assert!(!region.contains(0x100000), "Should not contain any address");
}

/// Test region at address 0
#[test]
fn test_region_at_zero() {
    let region = MockMemoryRegion::new(0, 0x1000);
    
    assert_eq!(region.base_address, 0, "Base should be 0");
    assert!(region.contains(0), "Should contain address 0");
    assert!(region.contains(0xFFF), "Should contain address 0xFFF");
}

/// Test region with max size
#[test]
fn test_max_size_region() {
    let max_size: u64 = 0xFFFF_FFFF_FFFF;
    let region = MockMemoryRegion::new(0, max_size);
    
    assert_eq!(region.size, max_size, "Size should be max");
    assert!(region.contains(max_size - 1), "Should contain max address");
}

// ============================================================================
// Memory Type Combinations
// ============================================================================

/// Test all EPT memory types
#[test]
fn test_ept_memory_types_all() {
    let types = [
        EptMemoryType::Uncacheable,
        EptMemoryType::WriteCombining,
        EptMemoryType::WriteThrough,
        EptMemoryType::WriteProtected,
        EptMemoryType::WriteBack,
    ];
    
    for memory_type in types {
        let entry = MockEptEntry {
            read_access: true,
            write_access: true,
            execute_access: true,
            memory_type,
            level: EptLevel::Pt,
            physical_address: 0,
        };
        
        let bits = entry.to_bits();
        assert!(bits != 0, "Entry should have non-zero bits for type {:?}", memory_type);
    }
}

/// Test permission flag combinations
#[test]
fn test_permission_combinations() {
    let test_cases = [
        (false, false, false),
        (true, false, false),
        (false, true, false),
        (false, false, true),
        (true, true, false),
        (true, false, true),
        (false, true, true),
        (true, true, true),
    ];
    
    for (read, write, exec) in test_cases {
        let entry = MockEptEntry {
            read_access: read,
            write_access: write,
            execute_access: exec,
            memory_type: EptMemoryType::WriteBack,
            level: EptLevel::Pt,
            physical_address: 0,
        };
        
        let bits = entry.to_bits();
        
        assert_eq!((bits & 1) != 0, read, "Read bit should match");
        assert_eq!((bits & 2) != 0, write, "Write bit should match");
        assert_eq!((bits & 4) != 0, exec, "Execute bit should match");
    }
}

// ============================================================================
// Physical Memory Layout Tests
// ============================================================================

/// Test typical system memory layout
#[test]
fn test_system_memory_layout() {
    // Create typical memory layout
    let regions = [
        MockMemoryRegion::new(0x0, 0xA0000).with_type(MemoryRegionType::Reserved),         // IVT/BIOS
        MockMemoryRegion::new(0xA0000, 0x10000).with_type(MemoryRegionType::Mmio),          // VGA MMIO
        MockMemoryRegion::new(0x100000, 0x7E900000).with_type(MemoryRegionType::Ram),       // Main RAM
        MockMemoryRegion::new(0xFEC00000, 0x1000000).with_type(MemoryRegionType::Mmio),    // APIC
        MockMemoryRegion::new(0xFEE00000, 0x100000).with_type(MemoryRegionType::Reserved), // APIC
    ];
    
    // Verify layout
    assert_eq!(regions[0].base_address, 0x0);
    assert_eq!(regions[0].region_type, MemoryRegionType::Reserved);
    
    assert_eq!(regions[1].base_address, 0xA0000);
    assert_eq!(regions[1].region_type, MemoryRegionType::Mmio);
    
    assert_eq!(regions[2].base_address, 0x100000);
    assert_eq!(regions[2].region_type, MemoryRegionType::Ram);
    
    assert_eq!(regions[4].base_address, 0xFEE00000);
    assert_eq!(regions[4].region_type, MemoryRegionType::Reserved);
}

/// Test RAM region for guest VM
#[test]
fn test_guest_memory_region() {
    let guest_mem = MockMemoryRegion::new(0x100000, 0x10000000) // 256 MB at 1MB
        .with_permissions(MemoryPermissions {
            readable: true,
            writable: true,
            executable: true,
        })
        .with_type(MemoryRegionType::Ram);
    
    assert!(guest_mem.contains(0x100000));
    assert!(guest_mem.contains(0x10FFFFFF));
    assert!(guest_mem.permissions.readable);
    assert!(guest_mem.permissions.writable);
    assert!(guest_mem.permissions.executable);
    assert_eq!(guest_mem.region_type, MemoryRegionType::Ram);
}

// ============================================================================
// Performance Characteristics Tests
// ============================================================================

/// Test EPT entry bit patterns
#[test]
fn test_ept_entry_bit_patterns() {
    // Create entry with specific physical address
    let entry = MockEptEntry {
        read_access: true,
        write_access: true,
        execute_access: true,
        memory_type: EptMemoryType::WriteBack,
        level: EptLevel::Pt,
        physical_address: 0x100000, // 1MB physical
    };
    
    let bits = entry.to_bits();
    
    // Physical address bits should be in positions [12:47]
    let addr_bits = (bits >> 12) & 0xFFFFFFFFFFF;
    assert_eq!(addr_bits, 0x100, "Physical address should be encoded");
}
