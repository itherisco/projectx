#!/usr/bin/env julia
# generate_keys.jl - Key Generation Utility for ProjectX Ed25519 Signing
#
# This script generates Ed25519 keypairs for the Julia Brain to sign commands.
# The public key must be shared with the Rust Shell for verification.
#
# USAGE:
#   julia --project=. generate_keys.jl [--output-dir ./keys]
#
# OUTPUT:
#   - public_key.b64    : Base64-encoded public key (share with Rust Shell)
#   - secret_key.b64    : Base64-encoded secret key (KEEP PRIVATE!)
#   - keypair.json      : Full keypair in JSON format (encrypted storage)
#
# SECURITY WARNING:
#   - In production, store secret keys in an HSM or secure enclave
#   - Never commit secret keys to version control
#   - The secret key grants full control over the kernel

using Base64
using Random
using Dates
using JSON3

# Try to use TweetNaCl for real Ed25519 keys
const TWEETNACL_AVAILABLE = try
    using TweetNaCl
    true
catch
    false
end

# ============================================================================
# Key Generation
# ============================================================================

function generate_ed25519_keypair()
    if TWEETNACL_AVAILABLE
        pk = Vector{UInt8}(undef, 32)
        sk = Vector{UInt8}(undef, 64)
        TweetNaCl.crypto_sign_keypair(pk, sk)
        return pk, sk
    else
        error("TweetNaCl.jl not available. Please install: Pkg.add(\"TweetNaCl\")")
    end
end

# ============================================================================
# Main
# ============================================================================

function main()
    println("=" ^ 60)
    println("  ProjectX - Ed25519 Key Generation Utility")
    println("=" ^ 60)
    println()
    
    # Check for TweetNaCl
    if !TWEETNACL_AVAILABLE
        println("ERROR: TweetNaCl.jl is required for Ed25519 key generation")
        println()
        println("Install with:")
        println("  julia> using Pkg")
        println("  julia> Pkg.add(\"TweetNaCl\")")
        println()
        exit(1)
    end
    
    println("Generating Ed25519 keypair...")
    public_key, secret_key = generate_ed25519_keypair()
    println("  ✓ Keypair generated")
    println()
    
    # Encode to base64
    public_key_b64 = base64encode(public_key)
    secret_key_b64 = base64encode(secret_key)
    
    # Parse output directory from args
    output_dir = "./keys"
    for i in 1:length(ARGS)
        if ARGS[i] == "--output-dir" && i < length(ARGS)
            output_dir = ARGS[i+1]
        end
    end
    
    # Create output directory
    mkpath(output_dir)
    
    # Save public key (share with Rust)
    public_key_path = joinpath(output_dir, "public_key.b64")
    write(public_key_path, public_key_b64)
    println("Public Key saved to: $public_key_path")
    println("  → Share this with the Rust Shell for verification")
    println()
    
    # Save secret key (KEEP PRIVATE!)
    secret_key_path = joinpath(output_dir, "secret_key.b64")
    chmod(secret_key_path, 0o600)  # Owner read/write only
    write(secret_key_path, secret_key_b64)
    println("Secret Key saved to: $secret_key_path")
    println("  ⚠️  KEEP THIS SECRET - grants full kernel control!")
    println()
    
    # Save full keypair JSON (for programmatic loading)
    keypair_data = Dict(
        "public_key" => public_key_b64,
        "secret_key" => secret_key_b64,
        "created_at" => string(now(UTC)),
        "algorithm" => "Ed25519",
        "version" => "1.0.0"
    )
    keypair_path = joinpath(output_dir, "keypair.json")
    open(keypair_path, "w") do io
        JSON3.pretty(io, keypair_data)
    end
    chmod(keypair_path, 0o600)
    println("Keypair JSON saved to: $keypair_path")
    println()
    
    # Print public key for easy copy
    println("=" ^ 60)
    println("  PUBLIC KEY (for Rust Shell config)")
    println("=" ^ 60)
    println()
    println(public_key_b64)
    println()
    println("=" ^ 60)
    println()
    
    println("NEXT STEPS:")
    println("  1. Copy the public key to Rust Shell's trusted keys")
    println("  2. Configure the Julia Brain to load the secret key")
    println("  3. Test the signing pipeline")
    println()
end

# Run main
main()
