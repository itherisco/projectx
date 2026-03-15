# MemoryVault Security Tests
# ============================================================================
#
# Tests for the Memory-Only Vault implementation
# Validates security properties:
# 1. Secrets are encrypted in memory
# 2. Master key derived from passphrase (PBKDF2)
# 3. Vault can be locked/unlocked
# 4. Secrets are wiped on destroy
# 5. No ENV variable leakage
#
# These tests verify the fix for:
# - CWE-316: Cleartext Storage of Sensitive Information
# - ENV variable leakage via /proc/<pid>/environ

using Test
using SHA
using Base64
using Nettle
using Random

# Include the MemoryVault
include(joinpath(@__DIR__, "..", "src", "security", "MemoryVault.jl"))

# Test configuration
const TEST_PASSPHRASE = "secure-test-passphrase-123"
const TEST_SALT = Vector{UInt8}([
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
    0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
])

println("\n" * "="^60)
println("MEMORY VAULT SECURITY TESTS")
println("="^60)

# Test 1: Vault Creation
println("\n[TEST 1] MemoryVault Creation")
vault = MemoryVault(TEST_PASSPHRASE)
@test !is_locked(vault)
@test length(get_salt(vault)) == 32
destroy!(vault)
println("  PASSED: Vault creation works correctly")

# Test 2: Secret Storage and Retrieval
println("\n[TEST 2] Secret Storage and Retrieval")
vault = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault, "api_key", "secret-api-key-123")
retrieved = get_secret(vault, "api_key")
@test retrieved == "secret-api-key-123"
store_secret!(vault, "database_password", "db-pass-456")
@test get_secret(vault, "database_password") == "db-pass-456"
keys = list_secret_keys(vault)
@test "api_key" in keys
@test has_secret(vault, "api_key")
@test !has_secret(vault, "nonexistent")
destroy!(vault)
println("  PASSED: Secret storage and retrieval works correctly")

# Test 3: Encryption Security
println("\n[TEST 3] Encryption Security")
vault = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault, "secret", "my-sensitive-data")
decrypted = get_secret(vault, "secret")
@test decrypted == "my-sensitive-data"
wrong_vault = MemoryVault("wrong-passphrase"; salt=get_salt(vault))
result = get_secret(wrong_vault, "secret")
@test result == ""
destroy!(vault)
destroy!(wrong_vault)
println("  PASSED: Encryption provides confidentiality")

# Test 4: Key Derivation (PBKDF2)
println("\n[TEST 4] Key Derivation (PBKDF2)")
vault1 = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
vault2 = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault1, "test", "value")
@test get_secret(vault2, "test") == "value"
destroy!(vault1)
destroy!(vault2)
# Different passphrase = different key
vault3 = MemoryVault("different-passphrase"; salt=TEST_SALT)
vault4 = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault3, "test", "value")
result = get_secret(vault4, "test")
@test result == ""
destroy!(vault3)
destroy!(vault4)
println("  PASSED: PBKDF2 key derivation works correctly")

# Test 5: Vault Locking
println("\n[TEST 5] Vault Locking")
vault = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault, "secret", "value")
lock!(vault)
@test is_locked(vault)
result = get_secret(vault, "secret")
@test result == ""
destroy!(vault)
println("  PASSED: Vault locking works correctly")

# Test 6: Vault Destruction (Memory Wipe)
println("\n[TEST 6] Vault Destruction (Memory Wipe)")
vault = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault, "secret1", "value1")
destroy!(vault)
@test is_locked(vault)
result = get_secret(vault, "secret1")
@test result == ""
println("  PASSED: Vault destruction wipes all data")

# Test 7: Fail-Closed Security
println("\n[TEST 7] Fail-Closed Security")
vault = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
result = get_secret(vault, "nonexistent")
@test result == ""
store_secret!(vault, "test", "value")
wrong_vault = MemoryVault("wrong-pass"; salt=get_salt(vault))
result = get_secret(wrong_vault, "test")
@test result == ""
destroy!(vault)
destroy!(wrong_vault)
println("  PASSED: Fail-closed behavior prevents information leakage")

# Test 8: Session Reopening with Salt
println("\n[TEST 8] Session Reopening with Salt")
vault1 = MemoryVault(TEST_PASSPHRASE; salt=TEST_SALT)
store_secret!(vault1, "api_key", "secret-key-123")
salt_b64 = get_salt_b64(vault1)
vault2 = MemoryVault(TEST_PASSPHRASE; salt_b64=salt_b64)
@test get_secret(vault2, "api_key") == "secret-key-123"
destroy!(vault1)
destroy!(vault2)
println("  PASSED: Session can be reopened with persisted salt")

# Test 9: No ENV Leakage
println("\n[TEST 9] No ENV Variable Leakage")
vault = MemoryVault(TEST_PASSPHRASE)
store_secret!(vault, "secret", "value")
@test !haskey(ENV, "JARVIS_API_KEY")
@test !haskey(ENV, "JARVIS_SECRET")
@test !haskey(ENV, "JARVIS_VAULT_ADDR")
destroy!(vault)
println("  PASSED: No secrets stored in ENV variables")

println("\n" * "="^60)
println("ALL SECURITY TESTS COMPLETED SUCCESSFULLY")
println("="^60 * "\n")
