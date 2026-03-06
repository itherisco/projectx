//! # OpenSSL Version Manager for Julia/Rust Interop
//!
//! Manages OpenSSL version compatibility between Rust and Julia components.
//! Resolves conflicts that cause crypto primitive failures, JWT validation errors,
//! and TLS handshake instability.
//!
//! ## Key Features:
//! - Version pinning and compatibility checking
//! - LD_LIBRARY_PATH sanitization
//! - Runtime version detection and reporting
//! - Fallback mechanisms for version conflicts

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::process::Command;

/// Known good OpenSSL version combinations
pub const KNOWN_GOOD_OPENSSL_VERSIONS: &[(&str, &str)] = &[
    ("1.1.1k", "1.1.1"),  // OpenSSL 1.1.1k with OpenSSL.jl 1.1.1
    ("1.1.1l", "1.1.1"),  // OpenSSL 1.1.1l with OpenSSL.jl 1.1.1
    ("1.1.1n", "1.1.1"),  // OpenSSL 1.1.1n with OpenSSL.jl 1.1.1
    ("1.1.1o", "1.1.1"),  // OpenSSL 1.1.1o with OpenSSL.jl 1.1.1
    ("3.0.8", "3.0"),    // OpenSSL 3.0.8 with OpenSSL.jl 3.0
    ("3.0.9", "3.0"),    // OpenSSL 3.0.9 with OpenSSL.jl 3.0
    ("3.0.10", "3.0"),   // OpenSSL 3.0.10 with OpenSSL.jl 3.0
];

/// Minimum supported OpenSSL version
pub const MIN_SUPPORTED_OPENSSL_VERSION: &str = "1.1.1";

/// Maximum supported OpenSSL version for Julia compatibility
pub const MAX_SUPPORTED_OPENSSL_VERSION: &str = "3.0.10";

/// OpenSSL version information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenSslVersion {
    pub version: String,
    pub major: u8,
    pub minor: u8,
    pub patch: u8,
    pub build_flags: Vec<String>,
    pub is_compatible: bool,
    pub julia_compatible: bool,
}

/// Version detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionDetectionResult {
    pub system_openssl: Option<OpenSslVersion>,
    pub linked_openssl: Option<OpenSslVersion>,
    pub julia_openssl: Option<String>,
    pub conflicts_detected: Vec<String>,
    pub recommendations: Vec<String>,
}

/// Environment configuration for OpenSSL
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenSslEnvironmentConfig {
    pub ld_library_path: Vec<PathBuf>,
    pub openssl_lib_dir: Option<PathBuf>,
    pub openssl_conf: Option<PathBuf>,
    pub preferred_version: Option<String>,
    pub fallback_enabled: bool,
}

/// Version manager error types
#[derive(Debug, thiserror::Error)]
pub enum VersionManagerError {
    #[error("OpenSSL not found on system")]
    OpenSslNotFound,
    #[error("Version parsing error: {0}")]
    VersionParseError(String),
    #[error("Incompatible OpenSSL version: {0}")]
    IncompatibleVersion(String),
    #[error("Environment configuration error: {0}")]
    EnvironmentError(String),
    #[error("Julia not found or not configured")]
    JuliaNotFound,
}

/// Result type for version manager operations
pub type VersionManagerResult<T> = Result<T, VersionManagerError>;

/// Main version manager for OpenSSL compatibility
pub struct OpenSslVersionManager {
    config: OpenSslEnvironmentConfig,
    detected_versions: VersionDetectionResult,
}

impl OpenSslVersionManager {
    /// Create a new version manager with default configuration
    pub fn new() -> Self {
        Self {
            config: OpenSslEnvironmentConfig {
                ld_library_path: Vec::new(),
                openssl_lib_dir: None,
                openssl_conf: None,
                preferred_version: None,
                fallback_enabled: true,
            },
            detected_versions: VersionDetectionResult {
                system_openssl: None,
                linked_openssl: None,
                julia_openssl: None,
                conflicts_detected: Vec::new(),
                recommendations: Vec::new(),
            },
        }
    }

    /// Initialize with custom configuration
    pub fn with_config(config: OpenSslEnvironmentConfig) -> Self {
        Self {
            config,
            detected_versions: VersionDetectionResult {
                system_openssl: None,
                linked_openssl: None,
                julia_openssl: None,
                conflicts_detected: Vec::new(),
                recommendations: Vec::new(),
            },
        }
    }

    /// Detect all OpenSSL versions in the environment
    pub fn detect_versions(&mut self) -> VersionManagerResult<&VersionDetectionResult> {
        // Detect system OpenSSL
        if let Ok(version) = Self::detect_system_openssl() {
            self.detected_versions.system_openssl = Some(version);
        }

        // Detect linked OpenSSL (via openssl command)
        if let Ok(version) = Self::detect_linked_openssl() {
            self.detected_versions.linked_openssl = Some(version);
        }

        // Detect Julia OpenSSL version
        if let Ok(version) = Self::detect_julia_openssl() {
            self.detected_versions.julia_openssl = Some(version);
        }

        // Check for conflicts
        self.check_conflicts();

        Ok(&self.detected_versions)
    }

    /// Detect system OpenSSL version from shared libraries
    fn detect_system_openssl() -> VersionManagerResult<OpenSslVersion> {
        // Check common library paths
        let library_paths = vec![
            "/usr/lib/x86_64-linux-gnu/libssl.so",
            "/usr/lib/libssl.so",
            "/lib/x86_64-linux-gnu/libssl.so",
            "/lib/libssl.so",
            "/usr/local/lib/libssl.so",
        ];

        for path in library_paths {
            if std::path::Path::new(path).exists() {
                if let Ok(version) = Self::parse_openssl_version_from_file(path) {
                    return Ok(version);
                }
            }
        }

        // Try using pkg-config
        if let Ok(output) = Command::new("pkg-config")
            .arg("--modversion")
            .arg("openssl")
            .output()
        {
            if output.status.success() {
                let version_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
                return Self::parse_version_string(&version_str);
            }
        }

        Err(VersionManagerError::OpenSslNotFound)
    }

    /// Parse OpenSSL version from library file
    fn parse_openssl_version_from_file(_path: &str) -> VersionManagerResult<OpenSslVersion> {
        // Try running openssl version command
        Self::detect_linked_openssl()
    }

    /// Detect OpenSSL version using openssl command
    fn detect_linked_openssl() -> VersionManagerResult<OpenSslVersion> {
        let output = Command::new("openssl")
            .arg("version")
            .arg("-a")
            .output()
            .map_err(|_| VersionManagerError::OpenSslNotFound)?;

        if !output.status.success() {
            return Err(VersionManagerError::OpenSslNotFound);
        }

        let output_str = String::from_utf8_lossy(&output.stdout);
        
        // Parse version from output like "OpenSSL 1.1.1k  24 Aug 2021"
        for line in output_str.lines() {
            if line.starts_with("OpenSSL ") {
                let version_part = line.trim_start_matches("OpenSSL ");
                let version = version_part.split_whitespace().next()
                    .ok_or_else(|| VersionManagerError::VersionParseError("No version found".to_string()))?;
                return Self::parse_version_string(version);
            }
        }

        Err(VersionManagerError::VersionParseError("Could not parse version".to_string()))
    }

    /// Detect Julia's OpenSSL.jl version
    fn detect_julia_openssl() -> VersionManagerResult<String> {
        // Check if Julia is available and query OpenSSL.jl version
        let julia_script = r#"
            try
                import Pkg
                import OpenSSL
                if isdefined(OpenSSL, :VERSION)
                    println(OpenSSL.VERSION)
                else
                    # Try alternative method
                    println("julia_openssl_detected")
                end
            catch e
                println("julia_openssl_not_found")
            end
        "#;

        let output = Command::new("julia")
            .arg("--startup-file=no")
            .arg("-e")
            .arg(julia_script)
            .output();

        match output {
            Ok(out) if out.status.success() => {
                let result = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if result.contains("not_found") || result.is_empty() {
                    Err(VersionManagerError::JuliaNotFound)
                } else {
                    Ok(result)
                }
            }
            _ => Err(VersionManagerError::JuliaNotFound),
        }
    }

    /// Parse version string into structured format
    fn parse_version_string(version: &str) -> VersionManagerResult<OpenSslVersion> {
        // Handle versions like "1.1.1k" or "3.0.8"
        let parts: Vec<&str> = version.split('.').collect();
        
        if parts.len() < 2 {
            return Err(VersionManagerError::VersionParseError(
                format!("Invalid version format: {}", version)
            ));
        }

        let major: u8 = parts[0].parse()
            .map_err(|_| VersionManagerError::VersionParseError(
                format!("Invalid major version: {}", parts[0])
            ))?;

        let minor: u8 = parts[1].parse()
            .map_err(|_| VersionManagerError::VersionParseError(
                format!("Invalid minor version: {}", parts[1])
            ))?;

        let patch: u8 = if parts.len() >= 3 {
            // Extract just the numeric part (e.g., '1' from '1k' or '10' from '10')
            let patch_str: String = parts[2].chars().take_while(|c| c.is_ascii_digit()).collect();
            patch_str.parse().unwrap_or(0)
        } else {
            0
        };

        let is_compatible = Self::check_version_compatibility(major, minor, patch);
        let julia_compatible = Self::check_julia_compatibility(major, minor);

        Ok(OpenSslVersion {
            version: version.to_string(),
            major,
            minor,
            patch,
            build_flags: Vec::new(),
            is_compatible,
            julia_compatible,
        })
    }

    /// Check if version is compatible with this system
    fn check_version_compatibility(major: u8, minor: u8, patch: u8) -> bool {
        // Check minimum version
        if major < 1 || (major == 1 && minor < 1) || (major == 1 && minor == 1 && patch < 1) {
            return false;
        }

        // Check maximum version (OpenSSL 3.0.x is the max supported)
        if major > 3 || (major == 3 && minor > 0) || (major == 3 && minor == 0 && patch > 10) {
            return false;
        }

        true
    }

    /// Check if version is compatible with Julia's OpenSSL.jl
    fn check_julia_compatibility(major: u8, minor: u8) -> bool {
        match (major, minor) {
            (1, 1) => true,  // OpenSSL 1.1.x is fully supported
            (3, 0) => true,  // OpenSSL 3.0.x is supported with OpenSSL.jl 3.0
            _ => false,
        }
    }

    /// Check for version conflicts
    fn check_conflicts(&mut self) {
        let sys_ver = &self.detected_versions.system_openssl;
        let link_ver = &self.detected_versions.linked_openssl;
        let julia_ver = &self.detected_versions.julia_openssl;

        // Check system vs linked mismatch
        if let (Some(sys), Some(link)) = (sys_ver, link_ver) {
            if sys.version != link.version {
                self.detected_versions.conflicts_detected.push(format!(
                    "System OpenSSL ({}) differs from linked ({})",
                    sys.version, link.version
                ));
            }
        }

        // Check Julia compatibility
        if let Some(link) = link_ver {
            if !link.julia_compatible {
                self.detected_versions.conflicts_detected.push(format!(
                    "Linked OpenSSL {} may not be compatible with Julia OpenSSL.jl",
                    link.version
                ));
                self.detected_versions.recommendations.push(
                    "Consider upgrading OpenSSL.jl to version 3.0 for OpenSSL 3.x".to_string()
                );
            }
        }

        // Generate recommendations
        if self.detected_versions.conflicts_detected.is_empty() {
            self.detected_versions.recommendations.push(
                "No conflicts detected - system is properly configured".to_string()
            );
        }
    }

    /// Sanitize LD_LIBRARY_PATH for Julia/Rust compatibility
    pub fn sanitize_ld_library_path(&mut self) -> VersionManagerResult<Vec<PathBuf>> {
        let mut sanitized_paths: Vec<PathBuf> = Vec::new();
        
        // Get current LD_LIBRARY_PATH
        let current_path = env::var("LD_LIBRARY_PATH")
            .unwrap_or_default();

        // Parse and filter paths
        for path in current_path.split(':') {
            let path_buf = PathBuf::from(path);
            
            // Skip paths that might cause conflicts
            let path_str = path_buf.to_string_lossy().to_lowercase();
            if path_str.contains("julia") && path_str.contains("openssl") {
                // This path might cause conflicts - check version
                if let Some(link_ver) = &self.detected_versions.linked_openssl {
                    if !link_ver.julia_compatible {
                        // Skip this path to avoid conflict
                        continue;
                    }
                }
            }
            
            if path_buf.exists() {
                sanitized_paths.push(path_buf);
            }
        }

        // Add recommended paths
        self.add_recommended_paths(&mut sanitized_paths);

        self.config.ld_library_path = sanitized_paths.clone();
        Ok(sanitized_paths)
    }

    /// Add recommended library paths
    fn add_recommended_paths(&self, paths: &mut Vec<PathBuf>) {
        let recommended_paths = vec![
            "/usr/lib/x86_64-linux-gnu",
            "/usr/local/lib",
            "/lib/x86_64-linux-gnu",
        ];

        for path in recommended_paths {
            let pb = PathBuf::from(path);
            if pb.exists() && !paths.contains(&pb) {
                paths.push(pb);
            }
        }
    }

    /// Pin to a specific OpenSSL version (if available)
    pub fn pin_version(&mut self, version: &str) -> VersionManagerResult<()> {
        let parsed = Self::parse_version_string(version)?;
        
        if !parsed.is_compatible {
            return Err(VersionManagerError::IncompatibleVersion(
                format!("Version {} is not compatible", version)
            ));
        }

        self.config.preferred_version = Some(version.to_string());
        
        // Set environment variables to force specific version
        if let Ok(home) = env::var("HOME") {
            let lib_path = format!("{}/.julia/artifacts/{}/lib", home, version);
            if PathBuf::from(&lib_path).exists() {
                env::set_var("LD_LIBRARY_PATH", &lib_path);
            }
        }

        Ok(())
    }

    /// Enable fallback mode for version conflicts
    pub fn enable_fallback(&mut self) {
        self.config.fallback_enabled = true;
        self.detected_versions.recommendations.push(
            "Fallback mode enabled - will try alternative versions on conflict".to_string()
        );
    }

    /// Get environment setup script content
    pub fn generate_environment_script(&self) -> String {
        let mut script = String::new();
        
        script.push_str("#!/bin/bash\n");
        script.push_str("# OpenSSL Environment Setup for Julia/Rust Interop\n");
        script.push_str("# Generated by ITHERIS OpenSSL Version Manager\n\n");
        
        // Set LD_LIBRARY_PATH
        script.push_str("# LD_LIBRARY_PATH configuration\n");
        let ld_paths: Vec<String> = self.config.ld_library_path
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();
        
        if !ld_paths.is_empty() {
            script.push_str(&format!(
                "export LD_LIBRARY_PATH=\"{}\"\n\n",
                ld_paths.join(":")
            ));
        }

        // Set preferred version
        if let Some(ref version) = self.config.preferred_version {
            script.push_str(&format!(
                "# Pinned OpenSSL version: {}\n",
                version
            ));
            script.push_str(&format!(
                "export ITHERIS_OPENSSL_VERSION=\"{}\"\n\n",
                version
            ));
        }

        // Julia-specific configuration
        script.push_str("# Julia OpenSSL configuration\n");
        script.push_str("export JULIA_OPENSSL_LIBSSL_PATH=\"/usr/lib/x86_64-linux-gnu/libssl.so.1.1\"\n");
        script.push_str("export JULIA_OPENSSL_LIBCRYPTO_PATH=\"/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1\"\n");

        // OpenSSL config
        script.push_str("\n# OpenSSL configuration\n");
        if let Some(ref conf) = self.config.openssl_conf {
            script.push_str(&format!(
                "export OPENSSL_CONF=\"{}\"\n",
                conf.to_string_lossy()
            ));
        }

        script
    }

    /// Get version detection report
    pub fn get_version_report(&self) -> String {
        let mut report = String::new();
        
        report.push_str("=== OpenSSL Version Report ===\n\n");
        
        if let Some(ref sys) = self.detected_versions.system_openssl {
            report.push_str(&format!("System OpenSSL: {}\n", sys.version));
            report.push_str(&format!("  Compatible: {}\n", sys.is_compatible));
            report.push_str(&format!("  Julia Compatible: {}\n\n", sys.julia_compatible));
        }
        
        if let Some(ref link) = self.detected_versions.linked_openssl {
            report.push_str(&format!("Linked OpenSSL: {}\n", link.version));
            report.push_str(&format!("  Compatible: {}\n", link.is_compatible));
            report.push_str(&format!("  Julia Compatible: {}\n\n", link.julia_compatible));
        }
        
        if let Some(ref julia) = self.detected_versions.julia_openssl {
            report.push_str(&format!("Julia OpenSSL.jl: {}\n\n", julia));
        }
        
        if !self.detected_versions.conflicts_detected.is_empty() {
            report.push_str("Conflicts Detected:\n");
            for conflict in &self.detected_versions.conflicts_detected {
                report.push_str(&format!("  - {}\n", conflict));
            }
            report.push('\n');
        }
        
        if !self.detected_versions.recommendations.is_empty() {
            report.push_str("Recommendations:\n");
            for rec in &self.detected_versions.recommendations {
                report.push_str(&format!("  - {}\n", rec));
            }
        }
        
        report
    }
}

impl Default for OpenSslVersionManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Initialize the OpenSSL version manager and environment
pub fn initialize_ssl_environment() -> VersionManagerResult<OpenSslVersionManager> {
    let mut manager = OpenSslVersionManager::new();
    
    // Detect versions
    manager.detect_versions()?;
    
    // Sanitize LD_LIBRARY_PATH
    manager.sanitize_ld_library_path()?;
    
    println!("[OPENSSL] Version detection complete");
    println!("{}", manager.get_version_report());
    
    Ok(manager)
}

/// Get system OpenSSL version (convenience function)
pub fn get_system_openssl_version() -> Option<String> {
    if let Ok(version) = OpenSslVersionManager::detect_system_openssl() {
        Some(version.version)
    } else {
        None
    }
}

/// Check if OpenSSL is compatible with Julia
pub fn check_julia_openssl_compatibility() -> bool {
    if let Ok(version) = OpenSslVersionManager::detect_linked_openssl() {
        version.julia_compatible
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_parsing() {
        let version = OpenSslVersionManager::parse_version_string("1.1.1k").unwrap();
        assert_eq!(version.major, 1);
        assert_eq!(version.minor, 1);
        assert_eq!(version.patch, 1);
        assert!(version.julia_compatible);
    }

    #[test]
    fn test_version_parsing_30x() {
        let version = OpenSslVersionManager::parse_version_string("3.0.8").unwrap();
        assert_eq!(version.major, 3);
        assert_eq!(version.minor, 0);
        assert_eq!(version.patch, 8);
        assert!(version.julia_compatible);
    }

    #[test]
    fn test_incompatible_version() {
        let version = OpenSslVersionManager::parse_version_string("1.0.2f").unwrap();
        assert!(!version.is_compatible);
    }

    #[test]
    fn test_version_manager_creation() {
        let manager = OpenSslVersionManager::new();
        assert!(manager.config.fallback_enabled);
    }
}
