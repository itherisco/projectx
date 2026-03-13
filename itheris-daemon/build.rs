//! Build script for generating gRPC code from proto files

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Only run proto generation if the proto file exists
    let proto_path = std::path::Path::new("../proto/warden.proto");
    
    if proto_path.exists() {
        tonic_build::configure()
            .out_dir("src/")
            .compile_protos(
                &["../proto/warden.proto"],
                &["../proto/"],
            )?;
        println!("cargo:rerun-if-changed=../proto/warden.proto");
    } else {
        println!("cargo:warning=Proto file not found at {:?}, skipping code generation", proto_path);
    }
    
    Ok(())
}
