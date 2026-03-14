//! Build script for generating gRPC code from proto files

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Only run proto generation if the proto file exists and protoc is available
    let proto_path = std::path::Path::new("../proto/warden.proto");
    let has_protoc = std::process::Command::new("protoc")
        .arg("--version")
        .output()
        .is_ok();
    
    if proto_path.exists() && has_protoc {
        tonic_build::configure()
            .out_dir("src/")
            .compile_protos(
                &["../proto/warden.proto"],
                &["../proto/"],
            )?;
        println!("cargo:rerun-if-changed=../proto/warden.proto");
    } else {
        if !proto_path.exists() {
            println!("cargo:warning=Proto file not found at {:?}, skipping code generation", proto_path);
        }
        if !has_protoc {
            println!("cargo:warning=protoc not found, skipping gRPC code generation. Pre-generated code in src/ will be used if available.");
        }
    }
    
    Ok(())
}
