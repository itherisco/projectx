//! Security Module - TPM 2.0 Secret Sealing and Key Management
//!
//! This module provides hardware root of trust functionality using TPM 2.0:
//! - TPM secret sealing with PCR policy binding
//! - Runtime secret management
//! - Linux kernel keyring integration
//!
//! # Security Requirements:
//! - Secrets never touch disk in plaintext
//! - TPM sealed → runtime memory → kernel keyring workflow
//! - Memory zeroing after key usage
//! - Audit logging for all key operations

pub mod tpm_unseal;
pub mod key_manager;

pub use tpm_unseal::*;
pub use key_manager::*;
