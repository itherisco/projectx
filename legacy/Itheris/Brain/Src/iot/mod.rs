//! IoT Actuation Bridge Module
//!
//! Provides real MQTT communication and device control for IoT devices.
//! Integrates with the existing iot_bridge.rs stub to provide actual functionality.

pub mod device_registry;
pub mod mqtt_bridge;
pub mod actuation_router;
pub mod telemetry_stream;

// Re-exports for convenience
pub use device_registry::{
    DeviceEntry, DeviceMetadata, DeviceRegistry, DeviceRegistryError, DeviceDiscoveryEvent,
    DiscoveryEventType, HealthCheckConfig, HealthStatus,
};

pub use mqtt_bridge::{
    MqttBridge, MqttConfig, MqttError, MqttMessage, MqttStats, QoSLevel, ConnectionState,
    build_mqtt_config,
};

pub use actuation_router::{
    ActuationRouter, ActuationConfirmation, ActuationError, ActuationRequest,
    ActuationStats, ConfirmationStatus, LatencyMeasurement,
};

pub use telemetry_stream::{
    TelemetryStream, TelemetryConfig, TelemetryError, TelemetryPoint, StreamMetrics,
    ThroughputTestResult,
};
