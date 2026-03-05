# test_key_management.jl - Tests for HSM/Key Management Integration
# =================================================================

# Set up test environment
ENV["ITHERIS_HSM_ENABLED"] = "true"
ENV["ITHERIS_HSM_BACKEND"] = "soft-hsm"
ENV["ITHERIS_HSM_CONFIG"] = JSON3.json(Dict(
    "keystore_path" => joinpath(pwd(), ".test_hsm"),
    "simulation" => true
))

# Include KeyManagement module
push!(LOAD_PATH, joinpath(pwd(), "kernel", "security"))
using KeyManagement

# Test results tracking
test_results = Dict{String, Any}()

function run_tests()
    println("="^60)
    println("HSM/Key Management Integration Tests")
    println("="^60)
    
    # Test 1: SoftHSM Backend Initialization
    test_soft_hsm_init()
    
    # Test 2: Key Creation
    test_key_creation()
    
    # Test 3: Signing and Verification
    test_sign_verify()
    
    # Test 4: Encryption/Decryption
    test_encrypt_decrypt()
    
    # Test 5: Key Rotation
    test_key_rotation()
    
    # Test 6: AWS KMS Backend
    test_aws_kms_backend()
    
    # Test 7: Azure Key Vault Backend
    test_azure_kv_backend()
    
    # Test 8: GCP KMS Backend
    test_gcp_kms_backend()
    
    # Test 9: Migration from ENV
    test_env_migration()
    
    # Test 10: Security Status
    test_security_status()
    
    # Print summary
    print_summary()
end

function test_soft_hsm_init()
    println("\n[Test 1] SoftHSM Backend Initialization")
    try
        # Clean up any existing test keystore
        test_path = joinpath(pwd(), ".test_hsm")
        if isdir(test_path)
            rm(test_path; recursive=true)
        end
        
        # Create and initialize SoftHSM backend
        backend = SoftHSMBackend(;
            keystore_path=test_path,
            simulation=true
        )
        
        result = init_hsm(backend; fallback_to_env=false)
        
        @test result == true
        @test is_hsm_initialized() == true
        
        # Check security status
        status = security_status()
        @test status[:hsm_initialized] == true
        @test status[:backend_type] == "SoftHSMBackend"
        
        test_results["soft_hsm_init"] = Dict("status" => "PASS", "result" => "Initialized successfully")
        println("  ✓ PASSED")
    catch e
        test_results["soft_hsm_init"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_key_creation()
    println("\n[Test 2] Key Creation")
    try
        # Create symmetric key
        metadata1 = hsm_create_key("test-symmetric-key"; 
            key_type=SYMMETRIC, 
            description="Test symmetric key")
        
        @test metadata1.key_id == "test-symmetric-key"
        @test metadata1.key_type == SYMMETRIC
        @test metadata1.enabled == true
        
        # Create another key
        metadata2 = hsm_create_key("test-asymmetric-key";
            key_type=ASYMMETRIC_RSA,
            description="Test asymmetric key")
        
        @test metadata2.key_id == "test-asymmetric-key"
        @test metadata2.key_type == ASYMMETRIC_RSA
        
        # List keys
        keys = hsm_list_keys()
        @test length(keys) >= 2
        
        # Get specific key
        retrieved = hsm_get_key("test-symmetric-key")
        @test retrieved.key_id == "test-symmetric-key"
        
        test_results["key_creation"] = Dict("status" => "PASS", "result" => "Created 2 keys")
        println("  ✓ PASSED")
    catch e
        test_results["key_creation"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_sign_verify()
    println("\n[Test 3] Signing and Verification")
    try
        test_data = Vector{UInt8}("Hello, HSM World!")
        
        # Sign the data
        signature = hsm_sign(test_data, "test-symmetric-key")
        
        @test length(signature) > 0
        @test signature isa Vector{UInt8}
        
        # Verify with correct signature
        valid = hsm_verify(test_data, signature, "test-symmetric-key")
        @test valid == true
        
        # Verify with wrong data (should fail)
        wrong_data = Vector{UInt8}("Different message!")
        invalid = hsm_verify(wrong_data, signature, "test-symmetric-key")
        @test invalid == false
        
        # Verify with wrong signature (should fail)
        wrong_sig = rand(UInt8, length(signature))
        invalid2 = hsm_verify(test_data, wrong_sig, "test-symmetric-key")
        @test invalid2 == false
        
        test_results["sign_verify"] = Dict("status" => "PASS", "result" => "Sign/verify works correctly")
        println("  ✓ PASSED")
    catch e
        test_results["sign_verify"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_encrypt_decrypt()
    println("\n[Test 4] Encryption/Decryption")
    try
        plaintext = Vector{UInt8}("Sensitive data for encryption")
        
        # Encrypt
        ciphertext = hsm_encrypt(plaintext, "test-symmetric-key")
        
        @test ciphertext != plaintext
        @test length(ciphertext) == length(plaintext)
        
        # Decrypt
        decrypted = hsm_decrypt(ciphertext, "test-symmetric-key")
        
        @test decrypted == plaintext
        @test String(decrypted) == "Sensitive data for encryption"
        
        # Test with different key (should produce different result)
        # First create another key
        hsm_create_key("test-encryption-key"; key_type=SYMMETRIC)
        
        ciphertext2 = hsm_encrypt(plaintext, "test-encryption-key")
        decrypted2 = hsm_decrypt(ciphertext2, "test-encryption-key")
        
        @test decrypted2 == plaintext
        
        test_results["encrypt_decrypt"] = Dict("status" => "PASS", "result" => "Encrypt/decrypt works correctly")
        println("  ✓ PASSED")
    catch e
        test_results["encrypt_decrypt"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_key_rotation()
    println("\n[Test 5] Key Rotation")
    try
        # First create a key without rotation policy
        hsm_create_key("test-rotation-key"; key_type=SYMMETRIC)
        
        # Sign with original key
        test_data = Vector{UInt8}("Data before rotation")
        sig_before = hsm_sign(test_data, "test-rotation-key")
        
        # Get current metadata
        meta_before = hsm_get_key("test-rotation-key")
        
        # Set rotation policy
        result = hsm_set_rotation_policy("test-rotation-key", 30)
        @test result == true
        
        # Verify policy
        policy = hsm_get_rotation_policy("test-rotation-key")
        @test policy == 30
        
        # Perform rotation
        rotated = hsm_rotate_key("test-rotation-key")
        @test rotated == true
        
        # Get new metadata
        meta_after = hsm_get_key("test-rotation-key")
        @test meta_after.last_rotated_at !== nothing
        
        # Note: In production, old key material should be preserved for decryption
        # of old messages, but new messages should use new key
        
        test_results["key_rotation"] = Dict("status" => "PASS", "result" => "Key rotation works")
        println("  ✓ PASSED")
    catch e
        test_results["key_rotation"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_aws_kms_backend()
    println("\n[Test 6] AWS KMS Backend")
    try
        # Shutdown current HSM
        shutdown_hsm()
        
        # Create AWS KMS backend
        backend = AWSKMSBackend(;region="us-west-2")
        
        # Initialize without fallback
        result = init_hsm(backend; fallback_to_env=false)
        
        @test result == true
        @test is_hsm_initialized() == true
        
        # Create key
        metadata = hsm_create_key("aws-test-key"; key_type=SYMMETRIC)
        @test metadata.key_id == "aws-test-key"
        
        # Sign
        test_data = Vector{UInt8}("AWS KMS Test")
        sig = hsm_sign(test_data, "aws-test-key")
        
        # Verify
        @test hsm_verify(test_data, sig, "aws-test-key") == true
        
        # List keys
        keys = hsm_list_keys()
        @test length(keys) >= 1
        
        # Cleanup
        shutdown_hsm()
        
        test_results["aws_kms"] = Dict("status" => "PASS", "result" => "AWS KMS backend works")
        println("  ✓ PASSED")
    catch e
        test_results["aws_kms"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_azure_kv_backend()
    println("\n[Test 7] Azure Key Vault Backend")
    try
        # Create Azure backend
        backend = AzureKeyVaultBackend(;
            vault_name="test-vault",
            tenant_id="test-tenant",
            client_id="test-client",
            client_secret="test-secret"
        )
        
        # Initialize with fallback
        result = init_hsm(backend; fallback_to_env=false)
        
        @test result == true
        @test is_hsm_initialized() == true
        
        # Create key
        metadata = hsm_create_key("azure-test-key"; key_type=SYMMETRIC)
        @test metadata.key_id == "azure-test-key"
        
        # Test sign/verify
        test_data = Vector{UInt8}("Azure KV Test")
        sig = hsm_sign(test_data, "azure-test-key")
        @test hsm_verify(test_data, sig, "azure-test-key") == true
        
        # Cleanup
        shutdown_hsm()
        
        test_results["azure_kv"] = Dict("status" => "PASS", "result" => "Azure Key Vault works")
        println("  ✓ PASSED")
    catch e
        test_results["azure_kv"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_gcp_kms_backend()
    println("\n[Test 8] GCP KMS Backend")
    try
        # Create GCP backend
        backend = GCPKMSBackend(;
            project_id="test-project",
            location="us-central1",
            key_ring="test-ring"
        )
        
        # Initialize with fallback
        result = init_hsm(backend; fallback_to_env=false)
        
        @test result == true
        @test is_hsm_initialized() == true
        
        # Create key
        metadata = hsm_create_key("gcp-test-key"; key_type=SYMMETRIC)
        @test metadata.key_id == "gcp-test-key"
        
        # Test encryption/decryption
        plaintext = Vector{UInt8}("GCP KMS Test")
        ciphertext = hsm_encrypt(plaintext, "gcp-test-key")
        decrypted = hsm_decrypt(ciphertext, "gcp-test-key")
        
        @test decrypted == plaintext
        
        # Cleanup
        shutdown_hsm()
        
        test_results["gcp_kms"] = Dict("status" => "PASS", "result" => "GCP KMS works")
        println("  ✓ PASSED")
    catch e
        test_results["gcp_kms"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_env_migration()
    println("\n[Test 9] ENV to HSM Migration")
    try
        # Set up test ENV variables
        test_secrets = Dict(
            "ITHERIS_IPC_SECRET_KEY" => bytes2hex(rand(UInt8, 32)),
            "JARVIS_KERNEL_SECRET" => bytes2hex(rand(UInt8, 32))
        )
        
        for (k, v) in test_secrets
            ENV[k] = v
        end
        
        # Reinitialize SoftHSM
        test_path = joinpath(pwd(), ".test_hsm")
        if isdir(test_path)
            rm(test_path; recursive=true)
        end
        
        backend = SoftHSMBackend(;
            keystore_path=test_path,
            simulation=true
        )
        
        init_hsm(backend; fallback_to_env=true)
        
        # Note: Full migration would import from ENV
        # This test verifies the system can work with fallback
        
        @test is_hsm_initialized() == true
        
        # Cleanup ENV
        for k in keys(test_secrets)
            delete!(ENV, k)
        end
        
        test_results["env_migration"] = Dict("status" => "PASS", "result" => "Migration path available")
        println("  ✓ PASSED")
    catch e
        test_results["env_migration"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function test_security_status()
    println("\n[Test 10] Security Status")
    try
        # Reinitialize for clean state
        test_path = joinpath(pwd(), ".test_hsm")
        if isdir(test_path)
            rm(test_path; recursive=true)
        end
        
        backend = SoftHSMBackend(;keystore_path=test_path, simulation=true)
        init_hsm(backend; fallback_to_env=false)
        
        # Create test keys
        hsm_create_key("status-test-1"; key_type=SYMMETRIC)
        hsm_create_key("status-test-2"; key_type=SYMMETRIC)
        
        # Set rotation policy on one key
        hsm_set_rotation_policy("status-test-1", 90)
        
        # Get status
        status = security_status()
        
        @test status[:hsm_initialized] == true
        @test status[:backend_type] == "SoftHSMBackend"
        @test status[:keys_managed] >= 2
        @test status[:keys_with_rotation] >= 1
        @test status[:fallback_to_env] == false
        
        # Cleanup
        shutdown_hsm()
        
        # Check shutdown status
        status_after = security_status()
        @test status_after[:hsm_initialized] == false
        
        test_results["security_status"] = Dict("status" => "PASS", "result" => "Security status works")
        println("  ✓ PASSED")
    catch e
        test_results["security_status"] = Dict("status" => "FAIL", "error" => string(e))
        println("  ✗ FAILED: $e")
    end
end

function print_summary()
    println("\n" * "="^60)
    println("Test Summary")
    println("="^60)
    
    passed = 0
    failed = 0
    
    for (name, result) in test_results
        status = result["status"]
        if status == "PASS"
            println("  ✓ $name")
            passed += 1
        else
            println("  ✗ $name: $(result["error"])")
            failed += 1
        end
    end
    
    println("\nTotal: $passed passed, $failed failed")
    
    # Clean up test directory
    test_path = joinpath(pwd(), ".test_hsm")
    if isdir(test_path)
        rm(test_path; recursive=true)
    end
    
    return failed == 0
end

# Run tests
println("Starting HSM Integration Tests...\n")
run_tests()
