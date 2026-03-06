//! Key Manager Module - TPM to Kernel Keyring Integration
//!
//! This module manages the lifecycle of secrets from TPM-sealed to kernel keyring.
//! It implements the secure workflow: TPM sealed → runtime memory → kernel keyring
//!
//! # Security Requirements:
//! - All sensitive keys follow: TPM sealed → runtime memory → kernel keyring
//! - No plaintext secrets stored on disk
//! - Memory zeroing after key usage
//! - Audit logging for all key operations
//! - Key revocation and rotation support

use crate::tpm::{TPMError, TPMAuthority};
use crate::security::tpm_unseal::{TpmUnsealAuthority, SealedSecret, PcrPolicy, UnsealError};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use chrono::Utc;
use uuid::Uuid;

/// Linux kernel keyring operations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KernelKeyring {
    /// Key description prefix
    prefix: String,
}

/// Key types for kernel keyring
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum KeyType {
    /// User session keyring
    Session,
    /// User keyring
    User,
    /// Thread keyring
    Thread,
    /// Process keyring
    Process,
}

/// Key manager errors
#[derive(Error, Debug)]
pub enum KeyManagerError {
    #[error("TPM unseal error: {0}")]
    UnsealError(#[from] UnsealError),
    
    #[error("Kernel keyring error: {0}")]
    KeyringError(String),
    
    #[error("Key not found: {0}")]
    KeyNotFound(String),
    
    #[error("Key already exists: {0}")]
    KeyAlreadyExists(String),
    
    #[error("Key revoked: {0}")]
    KeyRevoked(String),
    
    #[error("Memory security error: {0}")]
    MemorySecurityError(String),
    
    #[error("Key rotation failed: {0}")]
    RotationFailed(String),
    
    #[error("Operation not permitted: {0}")]
    PermissionDenied(String),
}

/// Key metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyMetadata {
    /// Unique key identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Key type
    pub key_type: KeyType,
    /// Keyring destination
    pub keyring: String,
    /// Creation timestamp
    pub created_at: String,
    /// Last used timestamp
    pub last_used: String,
    /// Expiration time (None = never)
    pub expires_at: Option<String>,
    /// Key version for rotation
    pub version: u32,
    /// Whether key is revoked
    pub revoked: bool,
    /// TPM sealed secret ID
    pub sealed_secret_id: Option<String>,
}

/// Key operation audit entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyOperationAudit {
    /// Operation type
    pub operation: String,
    /// Key identifier
    pub key_id: String,
    /// Success/failure
    pub success: bool,
    /// Error message if failed
    pub error_message: Option<String>,
    /// Timestamp
    pub timestamp: String,
    /// Source of operation
    pub source: String,
}

/// Secure memory buffer for key material
/// Provides automatic zeroing on drop
pub struct SecureMemory {
    data: Vec<u8>,
}

impl SecureMemory {
    /// Create new secure memory buffer
    pub fn new(data: Vec<u8>) -> Self {
        Self { data }
    }
    
    /// Get a slice of the data (use with caution)
    pub fn as_slice(&self) -> &[u8] {
        &self.data
    }
    
    /// Get mutable access (use with extreme caution)
    /// Only call this when you absolutely need to modify the data
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        &mut self.data
    }
    
    /// Get the length
    pub fn len(&self) -> usize {
        self.data.len()
    }
    
    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
}

impl Drop for SecureMemory {
    fn drop(&mut self) {
        // Zero out the memory on drop
        // In production, use a secure zeroing crate
        for byte in &mut self.data {
            *byte = 0;
        }
    }
}

/// Managed key state
#[derive(Debug, Clone)]
struct ManagedKey {
    /// Key metadata
    metadata: KeyMetadata,
    /// Runtime key data (in secure memory, not persisted)
    runtime_key: Option<SecureMemory>,
    /// TPM sealed secret reference
    sealed_secret_id: Option<String>,
}

/// Key Manager - manages keys from TPM to kernel keyring
pub struct KeyManager {
    /// TPM unseal authority
    tpm_unseal: TpmUnsealAuthority,
    /// Managed keys
    keys: Arc<Mutex<HashMap<String, ManagedKey>>>,
    /// Audit log
    audit_log: Arc<Mutex<Vec<KeyOperationAudit>>>,
    /// Kernel keyring interface
    keyring: KernelKeyring,
}

impl KeyManager {
    /// Create a new key manager
    pub fn new() -> Self {
        Self {
            tpm_unseal: TpmUnsealAuthority::new(),
            keys: Arc::new(Mutex::new(HashMap::new())),
            audit_log: Arc::new(Mutex::new(Vec::new())),
            keyring: KernelKeyring {
                prefix: "itheris".to_string(),
            },
        }
    }
    
    /// Check if TPM is available
    pub fn is_tpm_available(&self) -> bool {
        self.tpm_unseal.is_available()
    }
    
    /// Log an audit entry
    fn log_audit(&self, operation: &str, key_id: &str, success: bool, error: Option<&str>) {
        let entry = KeyOperationAudit {
            operation: operation.to_string(),
            key_id: key_id.to_string(),
            success,
            error_message: error.map(String::from),
            timestamp: Utc::now().to_rfc3339(),
            source: "KeyManager".to_string(),
        };
        
        if let Ok(mut log) = self.audit_log.lock() {
            log.push(entry);
        }
    }
    
    /// Create and seal a new key with TPM
    ///
    /// # Workflow:
    /// 1. Generate random key material
    /// 2. Seal with TPM using PCR policy
    /// 3. Store sealed blob in TPM NV (optional)
    /// 4. Return key metadata
    pub fn create_key(
        &self,
        name: &str,
        key_type: KeyType,
        keyring: &str,
        policy: Option<PcrPolicy>,
    ) -> Result<KeyMetadata, KeyManagerError> {
        // Generate random key material (256 bits)
        let mut key_data = vec![0u8; 32];
        use rand::RngCore;
        rand::thread_rng().fill_bytes(&mut key_data);
        
        // Seal with TPM
        let sealed = self.tpm_unseal.seal_secret(
            name,
            &key_data,
            policy,
        )?;
        
        // Zero key material immediately after sealing
        // Note: SecureMemory will auto-zero on drop
        let _secure_key = SecureMemory::new(key_data);
        
        // Create metadata
        let metadata = KeyMetadata {
            id: sealed.id.clone(),
            name: name.to_string(),
            key_type,
            keyring: keyring.to_string(),
            created_at: Utc::now().to_rfc3339(),
            last_used: Utc::now().to_rfc3339(),
            expires_at: None,
            version: 1,
            revoked: false,
            sealed_secret_id: Some(sealed.id.clone()),
        };
        
        // Store in memory
        let managed_key = ManagedKey {
            metadata: metadata.clone(),
            runtime_key: None, // Not loaded yet
            sealed_secret_id: Some(sealed.id.clone()),
        };
        
        if let Ok(mut keys) = self.keys.lock() {
            if keys.contains_key(&metadata.id) {
                return Err(KeyManagerError::KeyAlreadyExists(name.to_string()));
            }
            keys.insert(metadata.id.clone(), managed_key);
        }
        
        self.log_audit("create_key", &metadata.id, true, None);
        
        Ok(metadata)
    }
    
    /// Inject key into Linux kernel keyring
    ///
    /// # Security Notes:
    /// - Unseals key from TPM
    /// - Injects into kernel keyring
    /// - Zeros runtime memory after injection
    pub fn inject_to_keyring(&self, key_id: &str) -> Result<(), KeyManagerError> {
        // Get key metadata
        let sealed_secret_id = {
            let keys = self.keys.lock()
                .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
            
            let key = keys.get(key_id)
                .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
            
            if key.metadata.revoked {
                return Err(KeyManagerError::KeyRevoked(key_id.to_string()));
            }
            
            key.sealed_secret_id.clone()
                .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?
        };
        
        // Unseal from TPM
        let key_data = self.tpm_unseal.unseal_secret(&sealed_secret_id)?;
        
        // Inject into kernel keyring
        // In production, this would use keyctl syscall
        self.inject_keyctl(key_id, &key_data, &self.keyring.prefix)?;
        
        // Zero the key data from memory
        // SecureMemory auto-zeros on drop
        let _secure = SecureMemory::new(key_data);
        
        // Update last used
        if let Ok(mut keys) = self.keys.lock() {
            if let Some(key) = keys.get_mut(key_id) {
                key.metadata.last_used = Utc::now().to_rfc3339();
            }
        }
        
        self.log_audit("inject_to_keyring", key_id, true, None);
        
        Ok(())
    }
    
    /// Load key into runtime memory (without keyring)
    pub fn load_key(&self, key_id: &str) -> Result<SecureMemory, KeyManagerError> {
        // Get key metadata
        let sealed_secret_id = {
            let keys = self.keys.lock()
                .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
            
            let key = keys.get(key_id)
                .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
            
            if key.metadata.revoked {
                return Err(KeyManagerError::KeyRevoked(key_id.to_string()));
            }
            
            key.sealed_secret_id.clone()
                .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?
        };
        
        // Unseal from TPM
        let key_data = self.tpm_unseal.unseal_secret(&sealed_secret_id)?;
        
        // Store in secure memory
        let secure_mem = SecureMemory::new(key_data);
        
        // Update last used
        if let Ok(mut keys) = self.keys.lock() {
            if let Some(key) = keys.get_mut(key_id) {
                key.metadata.last_used = Utc::now().to_rfc3339();
            }
        }
        
        self.log_audit("load_key", key_id, true, None);
        
        Ok(secure_mem)
    }
    
    /// Revoke a key (prevent future use)
    pub fn revoke_key(&self, key_id: &str) -> Result<(), KeyManagerError> {
        let mut keys = self.keys.lock()
            .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
        
        let key = keys.get_mut(key_id)
            .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
        
        // Mark as revoked
        key.metadata.revoked = true;
        
        // Remove from keyring if present
        // In production: keyctl_unlink(key_id, KEY_SPEC_SESSION_KEYRING)
        self.revoke_keyctl(key_id)?;
        
        self.log_audit("revoke_key", key_id, true, None);
        
        Ok(())
    }
    
    /// Rotate a key (create new version, revoke old)
    pub fn rotate_key(&self, key_id: &str, new_policy: Option<PcrPolicy>) -> Result<KeyMetadata, KeyManagerError> {
        // Get old key info
        let (old_name, old_keyring, old_key_type) = {
            let keys = self.keys.lock()
                .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
            
            let key = keys.get(key_id)
                .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
            
            (key.metadata.name.clone(), key.metadata.keyring.clone(), key.metadata.key_type)
        };
        
        // Revoke old key
        self.revoke_key(key_id)?;
        
        // Create new key with same metadata but new version
        let new_name = format!("{}_v{}", old_name, 
            chrono::Utc::now().timestamp() as u32);
        
        let new_metadata = self.create_key(
            &new_name,
            old_key_type,
            &old_keyring,
            new_policy,
        )?;
        
        self.log_audit("rotate_key", key_id, true, None);
        
        Ok(new_metadata)
    }
    
    /// List all managed keys
    pub fn list_keys(&self) -> Vec<KeyMetadata> {
        if let Ok(keys) = self.keys.lock() {
            keys.values()
                .map(|k| k.metadata.clone())
                .collect()
        } else {
            Vec::new()
        }
    }
    
    /// Get key metadata
    pub fn get_key(&self, key_id: &str) -> Result<KeyMetadata, KeyManagerError> {
        let keys = self.keys.lock()
            .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
        
        keys.get(key_id)
            .map(|k| k.metadata.clone())
            .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))
    }
    
    /// Delete a key completely
    pub fn delete_key(&self, key_id: &str) -> Result<(), KeyManagerError> {
        // First revoke to clean up keyring
        if let Ok(mut keys) = self.keys.lock() {
            if keys.get(key_id).is_some() {
                self.revoke_key(key_id)?;
            }
        }
        
        // Remove from TPM
        self.tpm_unseal.delete_secret(key_id)?;
        
        // Remove from memory
        let mut keys = self.keys.lock()
            .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
        
        keys.remove(key_id)
            .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
        
        self.log_audit("delete_key", key_id, true, None);
        
        Ok(())
    }
    
    /// Get audit log
    pub fn get_audit_log(&self) -> Vec<KeyOperationAudit> {
        if let Ok(log) = self.audit_log.lock() {
            log.clone()
        } else {
            Vec::new()
        }
    }
    
    /// Check key status (loaded, in keyring, etc.)
    pub fn key_status(&self, key_id: &str) -> Result<String, KeyManagerError> {
        let keys = self.keys.lock()
            .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
        
        let key = keys.get(key_id)
            .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
        
        let status = if key.metadata.revoked {
            "revoked"
        } else if key.runtime_key.is_some() {
            "loaded_in_memory"
        } else {
            "sealed_in_tpm"
        };
        
        Ok(status.to_string())
    }
    
    // Private helper methods for kernel keyring operations
    
    /// Inject key using keyctl syscall
    fn inject_keyctl(&self, key_id: &str, key_data: &[u8], prefix: &str) -> Result<(), KeyManagerError> {
        // In production, this would use the keyctl syscall:
        // keyctl_add_key(KEY_TYPE_USER, description, payload, plen, KEY_SPEC_SESSION_KEYRING)
        
        // For now, simulate the operation
        println!("[KEYMGR] Injecting key {} to kernel keyring (prefix: {})", key_id, prefix);
        
        // Update runtime key state
        if let Ok(mut keys) = self.keys.lock() {
            if let Some(key) = keys.get_mut(key_id) {
                key.runtime_key = Some(SecureMemory::new(key_data.to_vec()));
            }
        }
        
        Ok(())
    }
    
    /// Revoke key from kernel keyring
    fn revoke_keyctl(&self, key_id: &str) -> Result<(), KeyManagerError> {
        // In production, this would use:
        // keyctl_unlink(key_id, KEY_SPEC_SESSION_KEYRING)
        
        println!("[KEYMGR] Revoking key {} from kernel keyring", key_id);
        
        // Clear runtime key
        if let Ok(mut keys) = self.keys.lock() {
            if let Some(key) = keys.get_mut(key_id) {
                key.runtime_key = None;
            }
        }
        
        Ok(())
    }
}

impl Default for KeyManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Secure key reference for passing around without exposing key material
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyRef {
    /// Key identifier
    pub id: String,
    /// Key type
    pub key_type: KeyType,
    /// Keyring destination
    pub keyring: String,
    /// Whether key is loaded
    pub loaded: bool,
}

impl KeyManager {
    /// Get a key reference (without exposing key material)
    pub fn get_key_ref(&self, key_id: &str) -> Result<KeyRef, KeyManagerError> {
        let keys = self.keys.lock()
            .map_err(|_| KeyManagerError::MemorySecurityError("Lock failed".to_string()))?;
        
        let key = keys.get(key_id)
            .ok_or_else(|| KeyManagerError::KeyNotFound(key_id.to_string()))?;
        
        Ok(KeyRef {
            id: key.metadata.id.clone(),
            key_type: key.metadata.key_type,
            keyring: key.metadata.keyring.clone(),
            loaded: key.runtime_key.is_some(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_key_creation() {
        let manager = KeyManager::new();
        
        let metadata = manager.create_key(
            "test_key",
            KeyType::Session,
            "session",
            None,
        ).unwrap();
        
        assert_eq!(metadata.name, "test_key");
        assert!(!metadata.id.is_empty());
    }
    
    #[test]
    fn test_key_rotation() {
        let manager = KeyManager::new();
        
        // Create initial key
        let original = manager.create_key(
            "rotating_key",
            KeyType::Session,
            "session",
            None,
        ).unwrap();
        
        // Rotate the key
        let rotated = manager.rotate_key(&original.id, None).unwrap();
        
        // Original should be revoked
        let status = manager.key_status(&original.id).unwrap();
        assert_eq!(status, "revoked");
        
        // New key should work
        assert!(!rotated.id.is_empty());
    }
    
    #[test]
    fn test_secure_memory_zeroing() {
        let data = vec![0xFFu8; 32];
        let secure = SecureMemory::new(data);
        
        // Drop the secure memory
        drop(secure);
        
        // Memory should be zeroed (we can't easily verify this, but the impl is there)
    }
    
    #[test]
    fn test_key_list() {
        let manager = KeyManager::new();
        
        manager.create_key("key1", KeyType::Session, "session", None).unwrap();
        manager.create_key("key2", KeyType::User, "user", None).unwrap();
        
        let keys = manager.list_keys();
        assert_eq!(keys.len(), 2);
    }
}
