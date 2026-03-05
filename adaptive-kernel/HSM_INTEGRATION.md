# HSM Integration Guide

## Overview

The Itheris system now supports Hardware Security Module (HSM) integration for secure secret key management. This replaces the previous reliance on environment variables for storing cryptographic keys.

## Supported Backends

1. **AWS KMS** - Amazon Web Services Key Management Service
2. **Azure Key Vault** - Microsoft Azure Key Vault
3. **Google Cloud KMS** - Google Cloud Platform Key Management Service
4. **SoftHSM/TPM** - Software-based HSM simulation (for development/testing)

## Quick Start

### 1. Enable HSM

Set the following environment variables:

```bash
# Enable HSM
export ITHERIS_HSM_ENABLED=true

# Choose backend: aws-kms, azure-keyvault, gcp-kms, or soft-hsm
export ITHERIS_HSM_BACKEND=soft-hsm

# Backend-specific configuration (JSON)
export ITHERIS_HSM_CONFIG='{"keystore_path": "/home/user/.itheris/hsm", "simulation": true}'
```

### 2. Initialize in Julia Code

```julia
using KeyManagement

# Option A: Initialize with SoftHSM (development)
backend = SoftHSMBackend(;
    keystore_path="/home/user/.itheris/hsm",
    simulation=true
)
init_hsm(backend)

# Option B: Initialize with AWS KMS
backend = AWSKMSBackend(;region="us-east-1")
init_hsm(backend)

# Option C: Configure from environment variables
configure_from_environment()
```

### 3. Use HSM for Key Operations

```julia
# Create a key
metadata = hsm_create_key("my-signing-key"; key_type=SYMMETRIC)

# Sign data
data = Vector{UInt8}("Hello, World!")
signature = hsm_sign(data, "my-signing-key")

# Verify signature
verified = hsm_verify(data, signature, "my-signing-key")

# Encrypt
ciphertext = hsm_encrypt(plaintext, "my-encryption-key")

# Decrypt
decrypted = hsm_decrypt(ciphertext, "my-encryption-key")
```

### 4. Key Rotation

```julia
# Set rotation policy (e.g., rotate every 90 days)
hsm_set_rotation_policy("my-signing-key", 90)

# Manually rotate
hsm_rotate_key("my-signing-key")

# Check which keys need rotation
keys_due = check_key_rotation()

# Rotate all due keys
rotate_due_keys()
```

## Cloud Provider Configuration

### AWS KMS

```bash
export ITHERIS_HSM_BACKEND=aws-kms
export ITHERIS_HSM_CONFIG='{"region": "us-east-1", "key_arn": "arn:aws:kms:us-east-1:123456789012:key/xxx"}'
# Optionally set AWS credentials via environment
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
```

### Azure Key Vault

```bash
export ITHERIS_HSM_BACKEND=azure-keyvault
export ITHERIS_HSM_CONFIG='{"vault_name": "my-vault", "tenant_id": "xxx", "client_id": "xxx", "client_secret": "xxx"}'
```

### Google Cloud KMS

```bash
export ITHERIS_HSM_BACKEND=gcp-kms
export ITHERIS_HSM_CONFIG='{"project_id": "my-project", "location": "us-central1", "key_ring": "jarvis"}'
# GCP credentials via gcloud SDK or environment
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

## Migration from Environment Variables

To migrate existing secrets from environment variables to HSM:

```julia
# Set environment variables before migration
ENV["ITHERIS_IPC_SECRET_KEY"] = "your-hex-key"
ENV["JARVIS_KERNEL_SECRET"] = "your-hex-key"

# Run migration
backend = SoftHSMBackend(;keystore_path="/path/to/hsm", simulation=true)
migrated_count = migrate_env_to_hsm(backend)
println("Migrated $migrated_count secrets")
```

## IPC Integration

For IPC signing with HSM support:

```julia
using IPCKeyManagement

# Initialize IPC with HSM
init_ipc_key_manager(; use_hsm=true, key_id="ipc-signing-key")

# Use HSM-signed messages
signature = sign_message_with_hsm(data)
verified = verify_message_with_hsm(data, signature)
```

## Security Considerations

1. **Key Separation**: Use separate keys for different purposes (signing, encryption)
2. **Rotation Policy**: Set appropriate rotation periods (recommended: 30-90 days)
3. **Access Control**: Restrict key access to only necessary components
4. **Audit Logging**: Enable logging for all key operations
5. **Backup**: Maintain secure backups of key material (encrypted)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
├─────────────────────────────────────────────────────────┤
│  KeyManagement.jl - HSM Abstraction                    │
│  ┌─────────────────────────────────────────────────────┐│
│  │  AWS KMS  │ Azure KV │ GCP KMS │ SoftHSM/TPM      ││
│  └─────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────┤
│  IPCKeyManagement.jl - IPC-specific key management    │
├─────────────────────────────────────────────────────────┤
│  RustIPC.jl - Original ENV-based key management        │
│  (Falls back if HSM unavailable)                      │
└─────────────────────────────────────────────────────────┘
```

## Troubleshooting

### HSM Not Initialized

If you see "HSM not initialized", check:
1. Environment variables are set correctly
2. Backend credentials are valid
3. Network connectivity (for cloud KMS)

### Fallback Behavior

By default, the system falls back to ENV-based keys if HSM is unavailable. To disable this:

```julia
init_hsm(backend; fallback_to_env=false)
```

### Key Not Found

Ensure the key exists before use:
```julia
keys = hsm_list_keys()
if !("my-key" in [k.key_id for k in keys])
    hsm_create_key("my-key")
end
```
