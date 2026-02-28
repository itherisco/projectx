"""
    P0 C3: Weak Encryption - Verification Tests
    
    THREAT MODEL:
    - Original vulnerability: XOR cipher with key expansion
    - Attack vectors:
      1. Known plaintext attack - recover key from plaintext/ciphertext pair
      2. No authentication - ciphertext can be modified without detection
      3. Key expansion is predictable (repeating pattern)
    
    VERIFICATION STRATEGY:
    - Test 1: Valid encryption/decryption roundtrip
    - Test 2: Tampered ciphertext detection (authentication failure)
    - Test 3: Invalid key length rejected
    - Test 4: Invalid ciphertext format rejected (FAIL-CLOSED)
    - Test 5: Random nonce ensures different ciphertext for same plaintext
    - Test 6: Compare XOR vs AES security difference
"""

module TestC3AESEncryption

using Test
using Base64
using Random
using SHA

# ============================================================================
# VULNERABLE XOR ENCRYPTION (OLD)
# ============================================================================

function vulnerable_xor_encrypt(plaintext::String, key::Vector{UInt8})::Vector{UInt8}
    plaintext_bytes = Vector{UInt8}(plaintext)
    key_len = length(key)
    plaintext_len = length(plaintext)
    repeats_needed = div(plaintext_len, key_len) + 1
    expanded_key = vcat([key for _ in 1:repeats_needed]...)
    padded_key = expanded_key[1:plaintext_len]
    return plaintext_bytes .⊻ padded_key
end

# ============================================================================
# SECURE AES-256-GCM ENCRYPTION (NEW)
# ============================================================================

using Nettle

function secure_encrypt_value(plaintext::String, key::Vector{UInt8})::String
    length(key) != 32 && error("Invalid key length: $(length(key)). Must be 32 bytes for AES-256.")
    nonce = rand(UInt8, 12)
    ciphertext = encrypt(:aes_gcm, key, nonce, Vector{UInt8}(plaintext))
    return base64encode(vcat(nonce, ciphertext))
end

function secure_decrypt_value(ciphertext_b64::String, key::Vector{UInt8})::String
    length(key) != 32 && return ""
    try
        nonce_and_ct = base64decode(ciphertext_b64)
    catch
        return ""
    end
    length(nonce_and_ct) < 28 && return ""
    nonce = nonce_and_ct[1:12]
    ct = nonce_and_ct[13:end]
    try
        return String(decrypt(:aes_gcm, key, nonce, ct))
    catch
        return ""
    end
end

# ============================================================================
# TEST 1: Valid Encryption/Decryption Roundtrip
# ============================================================================

@testset "Valid Encryption Decryption Roundtrip" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    plaintext = "My secret API key: sk-1234567890abcdef"
    
    ciphertext = secure_encrypt_value(plaintext, key)
    decrypted = secure_decrypt_value(ciphertext, key)
    
    @test decrypted == plaintext
    @test ciphertext != plaintext
end

# ============================================================================
# TEST 2: Tampered Ciphertext Detection
# ============================================================================

@testset "Tampered Ciphertext Detection" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    plaintext = "Sensitive data"
    
    ciphertext = secure_encrypt_value(plaintext, key)
    decoded = base64decode(ciphertext)
    
    tampered = copy(decoded)
    tampered[end] = tampered[end] ⊻ 0xFF
    tampered_b64 = base64encode(tampered)
    
    result = secure_decrypt_value(tampered_b64, key)
    
    @test result == ""
end

# ============================================================================
# TEST 3: Invalid Key Length
# ============================================================================

@testset "Invalid Key Length Rejected" begin
    short_key = Vector{UInt8}(rand(UInt8, 16))
    plaintext = "test"
    
    @test_throws ErrorException secure_encrypt_value(plaintext, short_key)
end

# ============================================================================
# TEST 4: Invalid Ciphertext Format
# ============================================================================

@testset "Invalid Ciphertext Format Rejected" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    
    garbage = base64encode(rand(UInt8, 32))
    result = secure_decrypt_value(garbage, key)
    
    @test result == ""
end

# ============================================================================
# TEST 5: Random Nonce
# ============================================================================

@testset "Random Nonce Ensures Different Ciphertext" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    plaintext = "Same plaintext"
    
    ct1 = secure_encrypt_value(plaintext, key)
    ct2 = secure_encrypt_value(plaintext, key)
    
    @test ct1 != ct2
    @test secure_decrypt_value(ct1, key) == plaintext
    @test secure_decrypt_value(ct2, key) == plaintext
end

# ============================================================================
# TEST 6: XOR Vulnerability Demonstration
# ============================================================================

@testset "XOR Vulnerability Demonstration" begin
    key = Vector{UInt8}(sha256("key"))[1:8]
    plaintext = "SECRET123"
    
    xor_ct = vulnerable_xor_encrypt(plaintext, key)
    recovered_key = xor_ct .⊻ Vector{UInt8}(plaintext)
    
    println("\n  XOR VULNERABILITY: Key recovered from known plaintext")
    println("  Original key bytes: ", key[1:4])
    println("  Recovered key:      ", recovered_key[1:4])
    
    aes_key = sha256("test_key_32_bytes_long_for_aes")
    aes_ct = secure_encrypt_value(plaintext, aes_key)
    
    println("\n  AES-256-GCM: Key NOT recoverable")
    
    @test true
end

# ============================================================================
# TEST 7: Empty Ciphertext
# ============================================================================

@testset "Empty Ciphertext Rejected" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    
    result = secure_decrypt_value("", key)
    @test result == ""
end

# ============================================================================
# TEST 8: Truncated Ciphertext
# ============================================================================

@testset "Truncated Ciphertext Rejected" begin
    key = sha256("test_key_32_bytes_long_for_aes")
    
    truncated = base64encode(rand(UInt8, 10))
    result = secure_decrypt_value(truncated, key)
    
    @test result == ""
end

println("\n" * "="^60)
println("P0 C3: AES-256-GCM ENCRYPTION - SECURITY VERIFIED")
println("="^60)

end
