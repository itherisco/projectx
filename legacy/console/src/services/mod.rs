//! ITHERIS Console Services
//! 
//! Service layer for gRPC communication and other external services.

pub mod grpc;

#[cfg(feature = "grpc-web")]
pub mod grpc_web;
