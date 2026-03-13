//! ITHERIS Console Build Script
//! 
//! Compiles protobuf definitions using tonic-build.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Build protobuf definitions
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile(
            &["proto/warden.proto"],
            &["proto/"],
        )?;

    println!("cargo:rerun-if-changed=proto/warden.proto");

    Ok(())
}
