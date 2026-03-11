# Security Audit Plan: New Capabilities in ProjectX

**Audit Date:** 2026-02-22  
**Auditor:** Kilo Code (Security Architect)  
**Scope:** 8 New Capabilities  
**Risk Rating:** CRITICAL

---

## Executive Summary

This security audit plan identifies critical vulnerabilities in 8 new capabilities. **Immediate action required before deployment.**

### Critical Findings Summary

| Finding | Severity | Component |
|---------|----------|-----------|
| Ed25519 secret key committed to repository | CRITICAL | Security/Key Management |
| Mock crypto mode accepts ALL signatures | CRITICAL | Ed25519.jl |
| Arbitrary code execution via Inductor | CRITICAL | Inductor.jl |
| Unsafe shell execution in sandbox | CRITICAL | Inductor.jl |
| Weak shared memory permissions | HIGH | Memory-bridge |
| Hardcoded public key in source | HIGH | Capabilities Gate |

---

## 1. Component-by-Component Security Analysis

### 1.1 jarvis_nerves/ - Rust System 1 Reflex Layer

**Location:** `jarvis_nerves/src/`

#### Security Issues

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| JN-001 | commands.rs:47 | OpenApp(String) - no app whitelist | MEDIUM |
| JN-002 | commands.rs:48 | CloseApp(String) - can kill any process | MEDIUM |
| JN-003 | commands.rs:81 | Custom(String) - unbounded command | HIGH |
| JN-004 | main.rs:42 | Hardcoded seed 0xDEADBEEF01234567 | HIGH |

#### Mitigations
- Implement application whitelist for OpenApp/CloseApp
- Remove or sandbox Custom command
- Replace with cryptographically secure seed

---

### 1.2 cognitive-sandbox/ - WASM Runtime

**Location:** `cognitive-sandbox/`

#### Security Issues

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| CS-001 | lib.rs:234 | Wasmtime without explicit sandboxing | MEDIUM |
| CS-002 | lib.rs:282 | host::allocate without limits | MEDIUM |
| CS-003 | lib.rs:166 | IPC lacks authentication | HIGH |
| CS-004 | lib.rs:188 | IPC in-memory, no encryption | MEDIUM |

#### Mitigations
- Configure Wasmtime with memory/CPU limits
- Add message signing to IPC
- Consider TLS for IPC

---

### 1.3 Inductor.jl - Self-Generating Code (MacGyver Loop)

**Location:** `adaptive-kernel/capabilities/Inductor.jl`

#### Security Issues - CRITICAL

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| IN-001 | Inductor.jl:311 | Executes bash directly - NO SANDBOX | CRITICAL |
| IN-002 | Inductor.jl:324 | cargo build in temp dirs - resource exhaustion | CRITICAL |
| IN-003 | Inductor.jl:368 | Registers generated code as capability | CRITICAL |
| IN-004 | Inductor.jl:379 | escape_string but bash -c - injection possible | CRITICAL |
| IN-005 | Inductor.jl:137 | LLM API key in ENV | HIGH |

#### Mitigations - IMMEDIATE ACTION REQUIRED
- Remove direct `bash -c` execution
- Use Firecracker microVM or Linux namespaces
- Require manual approval for capability registration
- Use secrets management service

---

### 1.4 Security/Ed25519 - Key Management

**Location:** `adaptive-kernel/security/`

#### Security Issues - CRITICAL

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| SEC-001 | keys/secret_key.b64 | SECRET KEY IN REPOSITORY | CRITICAL |
| SEC-002 | keys/keypair.txt | Full keypair plaintext | CRITICAL |
| SEC-003 | Ed25519.jl:46 | Mock mode can be enabled | CRITICAL |
| SEC-004 | Ed25519.jl:148 | verify_signature returns TRUE in mock | CRITICAL |
| SEC-005 | Ed25519.jl:127 | Mock sign uses XOR - forgeable | CRITICAL |
| SEC-006 | capabilities_gate.rs:40 | Hardcoded public key | HIGH |

#### Mitigations - IMMEDIATE ACTION REQUIRED
1. Rotate all keys immediately
2. Remove secret_key.b64 from repository
3. Use HSM/TPM key storage
4. Remove mock mode from production
5. Implement key rotation mechanism

---

### 1.5 CommandAuthority.jl - Command Authority Model

**Location:** `adaptive-kernel/world/CommandAuthority.jl`

#### Security Issues

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| CA-001 | CommandAuthority.jl:116 | Authority defaults to :user | MEDIUM |
| CA-002 | CommandAuthority.jl:162 | can_override set by Julia | HIGH |
| CA-003 | Not impl | Phase 8 alignment missing | HIGH |

---

### 1.6 AuthorizationPipeline.jl

**Location:** `adaptive-kernel/world/AuthorizationPipeline.jl`

#### Security Issues

| ID | Description | Severity |
|----|-------------|----------|
| AP-001 | Pipeline starts at proposed - no pre-auth | MEDIUM |
| AP-003 | owner_explicit set by Julia - can bypass | CRITICAL |

---

### 1.7 memory-bridge/ - Julia-Rust Memory Bridge

**Location:** `memory-bridge/`

#### Security Issues

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| MB-001 | lib.rs:146 | o666 permissions - world readable | CRITICAL |
| MB-002 | lib.rs:198 | No data size validation | HIGH |
| MB-003 | lib.rs:123 | Magic only - no crypto | MEDIUM |

#### Mitigations
- Set o600 permissions on shared memory
- Add HMAC authentication
- Add bounds checking

---

### 1.8 itheris_shell/ - Shell with Capabilities Gate

**Location:** `itheris_shell/`

#### Security Issues

| ID | Location | Description | Severity |
|----|----------|-------------|----------|
| IS-001 | capabilities_gate.rs:40 | Hardcoded key | HIGH |
| IS-002 | bridge.rs | JSON without schema validation | MEDIUM |

---

## 2. Input Validation Gaps

| Component | Input | Validation | Gap |
|-----------|-------|-----------|-----|
| ReflexCommand | String | None | Arbitrary strings |
| OpenApp | String | None | Any app name |
| CloseApp | String | None | Any process |
| Custom | String | None | Unbounded execution |

---

## 3. Risk Assessment Matrix

```
                    │ Likelihood │ Impact │ Risk
───────────────────┼────────────┼────────┼────────
Key Compromise     │    HIGH    │  HIGH  │ CRITICAL
Code Injection     │    HIGH    │  HIGH  │ CRITICAL
Signature Bypass   │   MEDIUM   │  HIGH  │ CRITICAL
IPC Interception   │    HIGH    │ MEDIUM │   HIGH
```

---

## 4. Recommended Mitigations

### Priority 1 (Critical - Before Deployment)

1. **Rotate all cryptographic keys immediately**
   - Remove secret_key.b64 from repo
   - Implement HSM/TPM storage
   - Add key rotation

2. **Disable/sandbox Inductor code execution**
   - Remove direct bash -c execution
   - Use Firecracker or namespaces
   - Manual approval for capability registration

3. **Fix memory-bridge permissions**
   - Change o666 to o600
   - Add HMAC authentication

### Priority 2 (Within 2 Weeks)

4. Remove mock crypto from production
5. Implement command validation in jarvis_nerves
6. Add WASM resource limits
7. Verify owner_explicit in Rust shell

---

## 5. Testing Recommendations

| Test | Description | Expected |
|------|-------------|----------|
| T-001 | Arbitrary shell via Inductor | BLOCKED |
| T-002 | Expired signature | BLOCKED |
| T-003 | Unauthorized shared memory access | BLOCKED |
| T-004 | Crafted IPC message | BLOCKED |
| T-005 | owner_explicit bypass | BLOCKED |

---

## 6. Conclusion

**Multiple critical vulnerabilities require immediate action:**

1. **Cryptographic key compromise** - Keys in repo, mock signatures
2. **Arbitrary code execution** - Inductor without sandbox
3. **IPC security** - Unauthenticated, unencrypted

**Recommendation: DO NOT DEPLOY** until Priority 1 mitigations are implemented.

---

*Document Version: 1.0*  
*Last Updated: 2026-02-22*
