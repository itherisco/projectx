//! Build script for Rust Warden Hypervisor
//! Configures no_std build for bare metal x86_64

use std::env;
use std::fs;
use std::path::Path;

/// Generate linker script path
fn get_linker_script() -> &'static str {
    // Use target.json for cross-compilation
    "linker_script.ld"
}

fn main() {
    // Tell Cargo to rerun this script if the linker script changes
    println!("cargo:rerun-if-changed=linker_script.ld");
    println!("cargo:rerun-if-changed=build.rs");

    // Set target for bare metal x86_64
    println!("cargo:rustc-target=x86_64-unknown-none");

    // Enable specific CPU features for virtualization
    println!("cargo:rustc-cfg=feature=\"vmx\"");
    println!("cargo:rustc-cfg=feature=\"svm\"");
    println!("cargo:rustc-cfg=feature=\"ept\"");
    println!("cargo:rustc-cfg=feature=\"npt\");

    // Linker configuration
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_arch == "x86_64" {
        // For bare metal, we don't link against std or any system libraries
        println!("cargo:rustc-link-arg=--script={}", get_linker_script());
    }

    // Create target directory if needed
    let out_dir = env::var("OUT_DIR").unwrap();
    let target_dir = Path::new(&out_dir);
    fs::create_dir_all(target_dir).ok();

    println!("cargo:warning=Rust Warden Hypervisor - Building for x86_64-unknown-none");
    println!("cargo:warning=Features: VMX, SVM, EPT, NPT");
}
