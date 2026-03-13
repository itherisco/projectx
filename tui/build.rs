// Build script for tonic/protobuf compilation
// In production, this would generate code from .proto files

fn main() {
    // In production, use tonic-build to generate code from protobuf definitions:
    // tonic_build::configure()
    //     .build_server(true)
    //     .build_client(true)
    //     .compile(
    //         &["proto/telemetry.proto"],
    //         &["proto/"],
    //     )
    //     .unwrap();
    
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=proto/");
}
