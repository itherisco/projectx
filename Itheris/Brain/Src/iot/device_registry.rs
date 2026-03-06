//! Device Registry Module
//!
//! Manages IoT device registration, discovery, and health monitoring.
//! Provides async-friendly CRUD operations for device lifecycle management.

use crate::iot_bridge::Device;
use chrono::{DateTime, Local, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::{interval, Duration};

/// Device health status
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unreachable,
    Unknown,
}

/// Device metadata for registry
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceMetadata {
    pub registered_at: DateTime<Utc>,
    pub last_health_check: Option<DateTime<Utc>>,
    pub health_status: HealthStatus,
    pub firmware_version: Option<String>,
    pub tags: Vec<String>,
}

/// Device registry entry with enhanced metadata
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceEntry {
    pub device: Device,
    pub metadata: DeviceMetadata,
}

/// Device discovery event
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceDiscoveryEvent {
    pub device_id: String,
    pub event_type: DiscoveryEventType,
    pub timestamp: DateTime<Utc>,
    pub details: Option<String>,
}

/// Types of discovery events
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum DiscoveryEventType {
    Discovered,
    Registered,
    Updated,
    Unreachable,
    Reconnected,
    Removed,
}

/// Device registry errors
#[derive(Debug, thiserror::Error)]
pub enum DeviceRegistryError {
    #[error("Device not found: {0}")]
    DeviceNotFound(String),
    #[error("Device already exists: {0}")]
    DeviceAlreadyExists(String),
    #[error("Invalid device configuration: {0}")]
    InvalidConfiguration(String),
    #[error("Registry error: {0}")]
    RegistryError(String),
}

/// Health check configuration
#[derive(Clone, Debug)]
pub struct HealthCheckConfig {
    pub interval_secs: u64,
    pub timeout_secs: u64,
    pub max_retries: u32,
}

impl Default for HealthCheckConfig {
    fn default() -> Self {
        Self {
            interval_secs: 30,
            timeout_secs: 5,
            max_retries: 3,
        }
    }
}

/// Device Registry - manages all registered IoT devices
pub struct DeviceRegistry {
    devices: Arc<RwLock<HashMap<String, DeviceEntry>>>,
    health_config: HealthCheckConfig,
}

impl DeviceRegistry {
    /// Create a new device registry
    pub fn new() -> Self {
        Self {
            devices: Arc::new(RwLock::new(HashMap::new())),
            health_config: HealthCheckConfig::default(),
        }
    }

    /// Create with custom health check configuration
    pub fn with_health_config(config: HealthCheckConfig) -> Self {
        Self {
            devices: Arc::new(RwLock::new(HashMap::new())),
            health_config: config,
        }
    }

    /// Register a new device
    pub async fn register_device(&self, device: Device) -> Result<DeviceEntry, DeviceRegistryError> {
        let device_id = device.id.clone();
        
        let mut devices = self.devices.write().await;
        
        if devices.contains_key(&device_id) {
            return Err(DeviceRegistryError::DeviceAlreadyExists(device_id));
        }

        let entry = DeviceEntry {
            device: device.clone(),
            metadata: DeviceMetadata {
                registered_at: Utc::now(),
                last_health_check: None,
                health_status: HealthStatus::Unknown,
                firmware_version: None,
                tags: vec![],
            },
        };

        devices.insert(device_id.clone(), entry.clone());

        println!(
            "[DEVICE_REGISTRY] ✓ Device registered: {} (type: {}, location: {})",
            device_id, device.device_type, device.location
        );

        Ok(entry)
    }

    /// Update an existing device
    pub async fn update_device(&self, device: Device) -> Result<DeviceEntry, DeviceRegistryError> {
        let device_id = device.id.clone();
        
        let mut devices = self.devices.write().await;
        
        if let Some(entry) = devices.get_mut(&device_id) {
            entry.device = device.clone();
            entry.metadata.last_health_check = Some(Utc::now());
            
            println!(
                "[DEVICE_REGISTRY] ✓ Device updated: {}",
                device_id
            );
            
            Ok(entry.clone())
        } else {
            Err(DeviceRegistryError::DeviceNotFound(device_id))
        }
    }

    /// Remove a device from registry
    pub async fn remove_device(&self, device_id: &str) -> Result<(), DeviceRegistryError> {
        let mut devices = self.devices.write().await;
        
        if devices.remove(device_id).is_some() {
            println!(
                "[DEVICE_REGISTRY] ✓ Device removed: {}",
                device_id
            );
            Ok(())
        } else {
            Err(DeviceRegistryError::DeviceNotFound(device_id.to_string()))
        }
    }

    /// Get a device by ID
    pub async fn get_device(&self, device_id: &str) -> Result<DeviceEntry, DeviceRegistryError> {
        let devices = self.devices.read().await;
        
        devices
            .get(device_id)
            .cloned()
            .ok_or_else(|| DeviceRegistryError::DeviceNotFound(device_id.to_string()))
    }

    /// Get all registered devices
    pub async fn get_all_devices(&self) -> Vec<DeviceEntry> {
        let devices = self.devices.read().await;
        devices.values().cloned().collect()
    }

    /// Get devices by type
    pub async fn get_devices_by_type(&self, device_type: &str) -> Vec<DeviceEntry> {
        let devices = self.devices.read().await;
        devices
            .values()
            .filter(|e| e.device.device_type == device_type)
            .cloned()
            .collect()
    }

    /// Get devices by location
    pub async fn get_devices_by_location(&self, location: &str) -> Vec<DeviceEntry> {
        let devices = self.devices.read().await;
        devices
            .values()
            .filter(|e| e.device.location == location)
            .cloned()
            .collect()
    }

    /// Get devices by status
    pub async fn get_devices_by_status(&self, status: &str) -> Vec<DeviceEntry> {
        let devices = self.devices.read().await;
        devices
            .values()
            .filter(|e| e.device.status == status)
            .cloned()
            .collect()
    }

    /// Update device status
    pub async fn update_device_status(
        &self,
        device_id: &str,
        status: String,
    ) -> Result<(), DeviceRegistryError> {
        let mut devices = self.devices.write().await;
        
        if let Some(entry) = devices.get_mut(device_id) {
            entry.device.status = status;
            entry.metadata.last_health_check = Some(Utc::now());
            Ok(())
        } else {
            Err(DeviceRegistryError::DeviceNotFound(device_id.to_string()))
        }
    }

    /// Update device state
    pub async fn update_device_state(
        &self,
        device_id: &str,
        key: String,
        value: serde_json::Value,
    ) -> Result<(), DeviceRegistryError> {
        let mut devices = self.devices.write().await;
        
        if let Some(entry) = devices.get_mut(device_id) {
            entry.device.state.insert(key, value);
            entry.device.last_seen = Local::now().to_rfc3339();
            Ok(())
        } else {
            Err(DeviceRegistryError::DeviceNotFound(device_id.to_string()))
        }
    }

    /// Update health status for a device
    pub async fn update_health_status(
        &self,
        device_id: &str,
        status: HealthStatus,
    ) -> Result<(), DeviceRegistryError> {
        let mut devices = self.devices.write().await;
        
        if let Some(entry) = devices.get_mut(device_id) {
            entry.metadata.health_status = status;
            entry.metadata.last_health_check = Some(Utc::now());
            Ok(())
        } else {
            Err(DeviceRegistryError::DeviceNotFound(device_id.to_string()))
        }
    }

    /// Get device count
    pub async fn device_count(&self) -> usize {
        let devices = self.devices.read().await;
        devices.len()
    }

    /// Check if device exists
    pub async fn device_exists(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices.contains_key(device_id)
    }

    /// Get devices needing health check
    pub async fn get_devices_needing_health_check(&self) -> Vec<String> {
        let devices = self.devices.read().await;
        let now = Utc::now();
        
        devices
            .iter()
            .filter(|(_, entry)| {
                match entry.metadata.last_health_check {
                    Some(last_check) => {
                        (now - last_check).num_seconds() > self.health_config.interval_secs as i64
                    }
                    None => true,
                }
            })
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Generate discovery event
    pub async fn generate_discovery_event(
        &self,
        device_id: &str,
        event_type: DiscoveryEventType,
    ) -> Option<DeviceDiscoveryEvent> {
        let devices = self.devices.read().await;
        
        if devices.contains_key(device_id) {
            Some(DeviceDiscoveryEvent {
                device_id: device_id.to_string(),
                event_type,
                timestamp: Utc::now(),
                details: None,
            })
        } else {
            None
        }
    }

    /// Start health monitoring background task
    pub async fn start_health_monitoring(&self) {
        let devices = Arc::clone(&self.devices);
        let config = self.health_config.clone();
        
        tokio::spawn(async move {
            let mut check_interval = interval(Duration::from_secs(config.interval_secs));
            
            loop {
                check_interval.tick().await;
                
                let device_ids: Vec<String> = {
                    let devices = devices.read().await;
                    let now = Utc::now();
                    
                    devices
                        .iter()
                        .filter(|(_, entry)| {
                            match entry.metadata.last_health_check {
                                Some(last_check) => {
                                    (now - last_check).num_seconds() > config.interval_secs as i64
                                }
                                None => true,
                            }
                        })
                        .map(|(id, _)| id.clone())
                        .collect()
                };
                
                for device_id in device_ids {
                    println!(
                        "[DEVICE_REGISTRY] Health check triggered for: {}",
                        device_id
                    );
                    // In production, this would ping the device
                    // For now, we just mark it as checked
                    let mut devices = devices.write().await;
                    if let Some(entry) = devices.get_mut(&device_id) {
                        entry.metadata.last_health_check = Some(Utc::now());
                        // Set to healthy if reachable
                        if entry.metadata.health_status != HealthStatus::Unreachable {
                            entry.metadata.health_status = HealthStatus::Healthy;
                        }
                    }
                }
            }
        });
    }
}

impl Default for DeviceRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_device_registration() {
        let registry = DeviceRegistry::new();
        
        let device = Device {
            id: "test-device-001".to_string(),
            device_type: "sensor".to_string(),
            location: "lab-1".to_string(),
            status: "online".to_string(),
            last_seen: Local::now().to_rfc3339(),
            capabilities: vec!["read".to_string()],
            state: serde_json::json!({}),
        };
        
        let result = registry.register_device(device).await;
        assert!(result.is_ok());
        
        let count = registry.device_count().await;
        assert_eq!(count, 1);
    }

    #[tokio::test]
    async fn test_device_not_found() {
        let registry = DeviceRegistry::new();
        
        let result = registry.get_device("nonexistent").await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_duplicate_registration() {
        let registry = DeviceRegistry::new();
        
        let device = Device {
            id: "test-device-002".to_string(),
            device_type: "actuator".to_string(),
            location: "lab-2".to_string(),
            status: "online".to_string(),
            last_seen: Local::now().to_rfc3339(),
            capabilities: vec!["write".to_string()],
            state: serde_json::json!({}),
        };
        
        let _ = registry.register_device(device.clone()).await;
        let result = registry.register_device(device).await;
        
        assert!(result.is_err());
    }
}
