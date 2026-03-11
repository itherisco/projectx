// ============================================================================
// Memory Bridge - Rust Side
// Phase 3 of ITHERIS Ω - Shared Memory Bridge between Rust and Julia
// Uses memory-mapped files for cross-process communication
// ============================================================================

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use uuid::Uuid;

// ============================================================================
// Data Structures for Shared Memory
// ============================================================================

/// Source of sensory data
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SensorySource {
    Sentry,
    Librarian,
    Action,
}

impl SensorySource {
    pub fn as_str(&self) -> &'static str {
        match self {
            SensorySource::Sentry => "sentry",
            SensorySource::Librarian => "librarian",
            SensorySource::Action => "action",
        }
    }
}

/// Type of data in the observation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DataType {
    Float32,
    Float64,
    Int32,
    Int64,
    String,
    Bool,
    Binary,
}

/// Sensory observation written by Rust (Sentry)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensoryObservation {
    pub id: Uuid,
    pub timestamp: i64,  // Unix timestamp in milliseconds
    pub source: SensorySource,
    pub data_type: DataType,
    pub values: Vec<f64>,  // Raw values as f64 for JSON compatibility
    pub metadata: HashMap<String, String>,
}

/// Prediction response from Julia (Active Inference)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceResponse {
    pub id: Uuid,
    pub observation_id: Uuid,
    pub timestamp: i64,
    pub prediction_error: f64,
    pub predicted_values: Vec<f64>,
    pub updated_hdc_bindings: HashMap<String, Vec<f64>>,
    pub selected_policy: Option<String>,
    pub free_energy: f64,
}

/// HDC vector binding for conceptual associations
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HdcBinding {
    pub concept_a: String,
    pub concept_b: String,
    pub vector: Vec<f64>,
    pub timestamp: i64,
}

// ============================================================================
// Shared Memory Protocol
// ============================================================================

/// Shared memory region names
pub const OBSERVATIONS_SHM: &str = "itheris_observations";
pub const INFERENCE_SHM: &str = "itheris_inference";
pub const HDC_SHM: &str = "itheris_hdc";
pub const LOCK_SHM: &str = "itheris_locks";

/// Magic numbers for validation
const SHM_MAGIC: u32 = 0x49544852;  // "ITHR"
const VERSION: u32 = 1;

/// Shared memory header for validation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShmHeader {
    pub magic: u32,
    pub version: u32,
    pub data_size: u32,
    pub flags: u32,
    pub last_write_timestamp: i64,
    pub write_count: u64,
}

impl ShmHeader {
    pub fn new(data_size: u32) -> Self {
        Self {
            magic: SHM_MAGIC,
            version: VERSION,
            data_size,
            flags: 0,
            last_write_timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64,
            write_count: 0,
        }
    }

    pub fn is_valid(&self) -> bool {
        self.magic == SHM_MAGIC && self.version == VERSION
    }
}

// ============================================================================
// Memory-Mapped File Implementation
// ============================================================================

/// File-backed shared memory region
pub struct SharedMemoryRegion {
    pub name: String,
    pub path: PathBuf,
    pub file: File,
    pub size: usize,
    pub header: ShmHeader,
}

impl SharedMemoryRegion {
    /// Create a new shared memory region
    pub fn new(name: &str, size: usize, base_path: &PathBuf) -> Result<Self, std::io::Error> {
        let path = base_path.join(format!("{}.shm", name));
        
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)?;

        // Initialize with zeros
        let header_size = std::mem::size_of::<ShmHeader>();
        let total_size = header_size + size;
        
        file.set_len(total_size as u64)?;
        
        let header = ShmHeader::new(size as u32);
        
        Ok(Self {
            name: name.to_string(),
            path,
            file,
            size,
            header,
        })
    }

    /// Open existing shared memory region
    pub fn open(name: &str, base_path: &PathBuf) -> Result<Self, std::io::Error> {
        let path = base_path.join(format!("{}.shm", name));
        
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)?;
        
        let metadata = file.metadata()?;
        let size = (metadata.len() as usize) - std::mem::size_of::<ShmHeader>();
        
        // Read header
        let mut header = ShmHeader::new(0);
        let mut header_bytes = vec![0u8; std::mem::size_of::<ShmHeader>()];
        file.read_exact(&mut header_bytes)?;
        // Simple deserialization (in production use bincode or similar)
        
        Ok(Self {
            name: name.to_string(),
            path,
            file,
            size,
            header,
        })
    }

    /// Write data to shared memory
    pub fn write(&mut self, data: &[u8]) -> Result<(), std::io::Error> {
        if data.len() > self.size {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Other,
                "Data too large for shared memory region"
            ));
        }

        // Write header first
        self.header.data_size = data.len() as u32;
        self.header.last_write_timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;
        self.header.write_count += 1;

        let header_bytes = self.serialize_header();
        self.file.write_all(&header_bytes)?;

        // Write data at offset
        use std::io::Seek;
        self.file.seek(std::io::SeekFrom::Start(std::mem::size_of::<ShmHeader>() as u64))?;
        self.file.write_all(data)?;
        self.file.flush()?;

        Ok(())
    }

    /// Read data from shared memory
    pub fn read(&self) -> Result<Vec<u8>, std::io::Error> {
        use std::io::Seek;
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&self.path)?;

        // Skip header
        file.seek(std::io::SeekFrom::Start(std::mem::size_of::<ShmHeader>() as u64))?;
        
        let mut data = vec![0u8; self.size];
        file.read_exact(&mut data)?;
        
        Ok(data)
    }

    fn serialize_header(&self) -> Vec<u8> {
        // Simple serialization (in production use bincode)
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&self.header.magic.to_le_bytes());
        bytes.extend_from_slice(&self.header.version.to_le_bytes());
        bytes.extend_from_slice(&self.header.data_size.to_le_bytes());
        bytes.extend_from_slice(&self.header.flags.to_le_bytes());
        bytes.extend_from_slice(&self.header.last_write_timestamp.to_le_bytes());
        bytes.extend_from_slice(&self.header.write_count.to_le_bytes());
        bytes
    }
}

// ============================================================================
// Observation Buffer (Ring Buffer for High-Frequency Data)
// ============================================================================

/// Ring buffer for observations to handle high-frequency updates
pub struct ObservationBuffer {
    pub observations: Vec<Option<SensoryObservation>>,
    pub head: usize,
    pub tail: usize,
    pub capacity: usize,
    pub is_full: bool,
}

impl ObservationBuffer {
    pub fn new(capacity: usize) -> Self {
        Self {
            observations: vec![None; capacity],
            head: 0,
            tail: 0,
            capacity,
            is_full: false,
        }
    }

    pub fn push(&mut self, obs: SensoryObservation) {
        if self.is_full {
            self.tail = (self.tail + 1) % self.capacity;
        }
        self.observations[self.head] = Some(obs);
        self.head = (self.head + 1) % self.capacity;
        if self.head == self.tail {
            self.is_full = true;
        }
    }

    pub fn pop(&mut self) -> Option<SensoryObservation> {
        if self.is_empty() {
            return None;
        }
        let result = self.observations[self.tail].take();
        self.tail = (self.tail + 1) % self.capacity;
        self.is_full = false;
        result
    }

    pub fn is_empty(&self) -> bool {
        !self.is_full && self.head == self.tail
    }

    pub fn len(&self) -> usize {
        if self.is_full {
            return self.capacity;
        }
        if self.head >= self.tail {
            return self.head - self.tail;
        }
        self.capacity - self.tail + self.head
    }
}

// ============================================================================
// Memory Bridge Core
// ============================================================================

/// Thread-safe memory bridge for Rust ↔ Julia communication
pub struct MemoryBridge {
    base_path: PathBuf,
    observations: RwLock<ObservationBuffer>,
    pending_responses: RwLock<HashMap<Uuid, InferenceResponse>>,
    new_data_available: AtomicBool,
    last_observation_id: AtomicU64,
}

impl MemoryBridge {
    /// Create a new memory bridge
    pub fn new(base_path: PathBuf) -> Result<Self, std::io::Error> {
        // Create directory if it doesn't exist
        std::fs::create_dir_all(&base_path)?;

        Ok(Self {
            base_path,
            observations: RwLock::new(ObservationBuffer::new(100)),
            pending_responses: RwLock::new(HashMap::new()),
            new_data_available: AtomicBool::new(false),
            last_observation_id: AtomicU64::new(0),
        })
    }

    /// Write a sensory observation to shared memory (for Sentry)
    pub fn write_observation(&self, source: SensorySource, data_type: DataType, values: Vec<f64>, metadata: HashMap<String, String>) -> Uuid {
        let id = Uuid::new_v4();
        let obs = SensoryObservation {
            id,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64,
            source,
            data_type,
            values,
            metadata,
        };

        // Add to buffer
        self.observations.write().unwrap().push(obs.clone());
        
        // Write to file-based shared memory
        if let Ok(mut region) = SharedMemoryRegion::new(OBSERVATIONS_SHM, 1024 * 1024, &self.base_path) {
            if let Ok(json) = serde_json::to_vec(&obs) {
                let _ = region.write(&json);
            }
        }

        // Signal that new data is available
        self.new_data_available.store(true, Ordering::SeqCst);
        
        // Increment observation counter
        self.last_observation_id.fetch_add(1, Ordering::SeqCst);

        id
    }

    /// Write anomaly detection from Sentry
    pub fn write_anomaly(&self, values: Vec<f64>, severity: &str) -> Uuid {
        let mut metadata = HashMap::new();
        metadata.insert("severity".to_string(), severity.to_string());
        metadata.insert("type".to_string(), "anomaly".to_string());
        
        self.write_observation(SensorySource::Sentry, DataType::Float32, values, metadata)
    }

    /// Write regular observation from Sentry
    pub fn write_sensory(&self, values: Vec<f64>) -> Uuid {
        self.write_observation(SensorySource::Sentry, DataType::Float32, values, HashMap::new())
    }

    /// Read inference response from Julia (if available)
    pub fn read_inference_response(&self, observation_id: Uuid) -> Option<InferenceResponse> {
        self.pending_responses.write().unwrap().remove(&observation_id)
    }

    /// Store inference response from Julia
    pub fn store_inference_response(&self, response: InferenceResponse) {
        self.pending_responses.write().unwrap().insert(response.observation_id, response);
    }

    /// Check if new data is available
    pub fn has_new_data(&self) -> bool {
        self.new_data_available.load(Ordering::SeqCst)
    }

    /// Mark data as processed
    pub fn mark_processed(&self) {
        self.new_data_available.store(false, Ordering::SeqCst);
    }

    /// Get latest observation
    pub fn get_latest_observation(&self) -> Option<SensoryObservation> {
        let buffer = self.observations.read().unwrap();
        if buffer.is_empty() {
            return None;
        }
        let idx = if buffer.is_full {
            (buffer.head + buffer.capacity - 1) % buffer.capacity
        } else {
            buffer.head
        };
        buffer.observations[idx].clone()
    }

    /// Get observation count
    pub fn get_observation_count(&self) -> u64 {
        self.last_observation_id.load(Ordering::SeqCst)
    }

    /// Write HDC binding to shared memory
    pub fn write_hdc_binding(&self, concept_a: &str, concept_b: &str, vector: Vec<f64>) -> Result<(), std::io::Error> {
        let binding = HdcBinding {
            concept_a: concept_a.to_string(),
            concept_b: concept_b.to_string(),
            vector,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64,
        };

        let mut region = SharedMemoryRegion::new(HDC_SHM, 1024 * 1024, &self.base_path)?;
        let json = serde_json::to_vec(&binding)?;
        region.write(&json)?;

        Ok(())
    }
}

// ============================================================================
// Synchronization Primitives
// ============================================================================

/// File-based lock for cross-process synchronization
pub struct FileLock {
    path: PathBuf,
}

impl FileLock {
    pub fn new(name: &str, base_path: &PathBuf) -> Result<Self, std::io::Error> {
        let path = base_path.join(format!("{}.lock", name));
        Ok(Self { path })
    }

    pub fn acquire(&self) -> Result<(), std::io::Error> {
        // Try to create lock file exclusively
        let _file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&self.path)?;
        Ok(())
    }

    pub fn release(&self) -> Result<(), std::io::Error> {
        std::fs::remove_file(&self.path)?;
        Ok(())
    }

    pub fn try_acquire(&self) -> bool {
        OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&self.path)
            .is_ok()
    }
}

// ============================================================================
// IPC Event Notification
// ============================================================================

/// Event notification for signaling new data
pub struct EventNotifier {
    observation_event_path: PathBuf,
    inference_event_path: PathBuf,
}

impl EventNotifier {
    pub fn new(base_path: &PathBuf) -> Result<Self, std::io::Error> {
        let observation_event_path = base_path.join("observation_event");
        let inference_event_path = base_path.join("inference_event");
        
        // Create event files
        std::fs::write(&observation_event_path, "0")?;
        std::fs::write(&inference_event_path, "0")?;

        Ok(Self {
            observation_event_path,
            inference_event_path,
        })
    }

    /// Signal that new observation is available (Rust → Julia)
    pub fn signal_observation(&self) -> Result<(), std::io::Error> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis()
            .to_string();
        std::fs::write(&self.observation_event_path, timestamp)?;
        Ok(())
    }

    /// Signal that inference is complete (Julia → Rust)
    pub fn signal_inference(&self) -> Result<(), std::io::Error> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis()
            .to_string();
        std::fs::write(&self.inference_event_path, timestamp)?;
        Ok(())
    }

    /// Check if observation event fired
    pub fn check_observation_event(&self) -> Result<i64, std::io::Error> {
        let content = std::fs::read_to_string(&self.observation_event_path)?;
        Ok(content.trim().parse().unwrap_or(0))
    }

    /// Check if inference event fired
    pub fn check_inference_event(&self) -> Result<i64, std::io::Error> {
        let content = std::fs::read_to_string(&self.inference_event_path)?;
        Ok(content.trim().parse().unwrap_or(0))
    }
}

// ============================================================================
// Cognitive Loop Integration
// ============================================================================

/// High-level cognitive loop controller
pub struct CognitiveLoop {
    bridge: Arc<MemoryBridge>,
    notifier: Arc<EventNotifier>,
}

impl CognitiveLoop {
    pub fn new(bridge: Arc<MemoryBridge>, notifier: Arc<EventNotifier>) -> Self {
        Self { bridge, notifier }
    }

    /// Execute one cycle of the cognitive loop
    /// 1. Sentry detects anomaly → writes to shared memory
    /// 2. Julia reads observation → computes prediction error
    /// 3. Julia minimizes free energy → writes predictions
    /// 4. Rust reads predictions → selects action
    pub fn execute_cycle(&self, sensory_data: Vec<f64>) -> Option<InferenceResponse> {
        // Step 1: Rust Sentry writes observation
        let obs_id = self.bridge.write_anomaly(&sensory_data, "medium");
        
        // Signal Julia that new data is available
        let _ = self.notifier.signal_observation();
        
        // In a real implementation, we would wait for Julia to process
        // For now, return the observation ID for tracking
        tracing::info!("Cognitive cycle started with observation: {}", obs_id);
        
        // Return the observation ID - in real implementation, would wait for Julia response
        None
    }

    /// Wait for and retrieve inference response
    pub fn wait_for_inference(&self, timeout_ms: u64, observation_id: Uuid) -> Option<InferenceResponse> {
        let start = std::time::Instant::now();
        
        while start.elapsed().as_millis() < timeout_ms as u128 {
            if let Some(response) = self.bridge.read_inference_response(observation_id) {
                return Some(response);
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        
        None
    }
}

// ============================================================================
// Screenshot Capture Module (Upgrade 4 - Vision Layer)
// ============================================================================
// Platform-specific screenshot capture using:
// - Linux: xcap crate
// - macOS: core-graphics
// - Windows: windows-capture

/// Screenshot capture result
#[derive(Debug, Clone)]
pub struct Screenshot {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,  // RGBA format
    pub timestamp: i64,
}

impl Screenshot {
    /// Encode screenshot as PNG
    pub fn to_png(&self) -> Vec<u8> {
        // Use basic PNG encoding
        // In production, use the `png` crate for proper encoding
        let mut png_data = Vec::new();
        
        // PNG signature
        png_data.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);
        
        // IHDR chunk (image header)
        let ihdr = self.create_ihdr_chunk();
        png_data.extend_from_slice(&ihdr);
        
        // IDAT chunk (image data)
        let idat = self.create_idat_chunk();
        png_data.extend_from_slice(&idat);
        
        // IEND chunk (image end)
        let iend = self.create_iend_chunk();
        png_data.extend_from_slice(&iend);
        
        png_data
    }
    
    fn create_ihdr_chunk(&self) -> Vec<u8> {
        use std::io::Write;
        
        let mut chunk = Vec::new();
        let mut data = Vec::new();
        
        // Width
        data.write_all(&self.width.to_be_bytes()).unwrap();
        // Height
        data.write_all(&self.height.to_be_bytes()).unwrap();
        // Bit depth (8)
        data.push(8);
        // Color type (6 = RGBA)
        data.push(6);
        // Compression method
        data.push(0);
        // Filter method
        data.push(0);
        // Interlace method
        data.push(0);
        
        let length = (data.len() as u32).to_be_bytes();
        chunk.extend_from_slice(&length);
        
        // Chunk type
        chunk.extend_from_slice(b"IHDR");
        
        // CRC (simplified - in production use proper CRC32)
        let crc = self.crc32(b"IHDR", &data);
        chunk.extend_from_slice(&data);
        chunk.extend_from_slice(&crc.to_be_bytes());
        
        chunk
    }
    
    fn create_idat_chunk(&self) -> Vec<u8> {
        use std::io::Write;
        
        let mut chunk = Vec::new();
        let mut data = Vec::new();
        
        // Add filter byte (0 = None) before each row
        for row in self.data.chunks((self.width * 4) as usize) {
            data.push(0);  // No filter
            data.extend_from_slice(row);
        }
        
        // Compress using deflate (simplified - in production use proper compression)
        let compressed = self.deflate_simple(&data);
        
        let length = (compressed.len() as u32).to_be_bytes();
        chunk.extend_from_slice(&length);
        
        // Chunk type
        chunk.extend_from_slice(b"IDAT");
        
        // CRC
        let crc = self.crc32(b"IDAT", &compressed);
        chunk.extend_from_slice(&compressed);
        chunk.extend_from_slice(&crc.to_be_bytes());
        
        chunk
    }
    
    fn create_iend_chunk(&self) -> Vec<u8> {
        vec![0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]
    }
    
    // Simple CRC32 calculation
    fn crc32(&self, chunk_type: &[u8], data: &[u8]) -> u32 {
        let mut crc: u32 = 0xFFFFFFFF;
        for byte in chunk_type.iter().chain(data.iter()) {
            crc ^= *byte as u32;
            for _ in 0..8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320;
                } else {
                    crc >>= 1;
                }
            }
        }
        !crc
    }
    
    // Simple deflate (store only, no actual compression)
    fn deflate_simple(&self, data: &[u8]) -> Vec<u8> {
        let mut result = Vec::new();
        
        // zlib header
        result.push(0x78);
        result.push(0x01);
        
        // Store blocks
        let mut remaining = data.len();
        let mut offset = 0;
        
        while remaining > 0 {
            let block_size = std::cmp::min(remaining, 65535);
            let is_last = remaining <= 65535;
            
            // Block header
            result.push(if is_last { 0x01 } else { 0x00 });
            result.extend_from_slice(&(block_size as u16).to_le_bytes());
            result.extend_from_slice(&((block_size as u16) ^ 0xFFFF).to_le_bytes());
            
            // Block data
            result.extend_from_slice(&data[offset..offset + block_size]);
            
            offset += block_size;
            remaining -= block_size;
        }
        
        // Adler-32 checksum
        let adler = self.adler32(data);
        result.extend_from_slice(&adler.to_be_bytes());
        
        result
    }
    
    fn adler32(&self, data: &[u8]) -> u32 {
        let mut a: u32 = 1;
        let mut b: u32 = 0;
        
        for byte in data {
            a = (a + *byte as u32) % 65521;
            b = (b + a) % 65521;
        }
        
        (b << 16) | a
    }
}

/// Screenshot capture error
#[derive(Debug)]
pub enum ScreenshotError {
    NoDisplay,
    CaptureError(String),
    UnsupportedPlatform,
}

/// Capture a screenshot using platform-specific methods
/// 
/// Returns Screenshot with RGBA data on success
pub fn capture_screenshot() -> Result<Screenshot, ScreenshotError> {
    #[cfg(target_os = "linux")]
    {
        capture_screenshot_linux()
    }
    
    #[cfg(target_os = "macos")]
    {
        capture_screenshot_macos()
    }
    
    #[cfg(target_os = "windows")]
    {
        capture_screenshot_windows()
    }
    
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Err(ScreenshotError::UnsupportedPlatform)
    }
}

#[cfg(target_os = "linux")]
fn capture_screenshot_linux() -> Result<Screenshot, ScreenshotError> {
    // Try using X11 or Wayland
    // In production, use `xcap` crate:
    // let img = xcap::Monitor::new(0).unwrap().capture_image().unwrap();
    
    // For now, return a placeholder
    Err(ScreenshotError::CaptureError("X11/Wayland capture requires xcap crate".to_string()))
}

#[cfg(target_os = "macos")]
fn capture_screenshot_macos() -> Result<Screenshot, ScreenshotError> {
    // In production, use core-graphics:
    // use core_graphics::display::CGMainDisplayID;
    // use core_graphics::image::CGDisplayCreateImage;
    
    Err(ScreenshotError::CaptureError("macOS capture requires core-graphics crate".to_string()))
}

#[cfg(target_os = "windows")]
fn capture_screenshot_windows() -> Result<Screenshot, ScreenshotError> {
    // In production, use windows-capture:
    // use windows_capture::Capture::desktop;
    
    Err(ScreenshotError::CaptureError("Windows capture requires windows-capture crate".to_string()))
}

/// Capture screenshot and return as base64-encoded PNG
pub fn capture_screenshot_base64() -> Result<String, ScreenshotError> {
    let screenshot = capture_screenshot()?;
    let png_data = screenshot.to_png();
    
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    Ok(STANDARD.encode(&png_data))
}

/// Screen region for partial capture
pub struct ScreenRegion {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Capture a specific region of the screen
pub fn capture_screen_region(region: ScreenRegion) -> Result<Screenshot, ScreenshotError> {
    // In production, implement platform-specific region capture
    Err(ScreenshotError::CaptureError("Region capture not yet implemented".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_observation_buffer() {
        let mut buffer = ObservationBuffer::new(3);
        
        let obs1 = SensoryObservation {
            id: Uuid::new_v4(),
            timestamp: 1000,
            source: SensorySource::Sentry,
            data_type: DataType::Float32,
            values: vec![1.0, 2.0, 3.0],
            metadata: HashMap::new(),
        };
        
        buffer.push(obs1.clone());
        assert_eq!(buffer.len(), 1);
        
        let obs2 = buffer.pop();
        assert!(obs2.is_some());
        assert!(buffer.is_empty());
    }

    #[test]
    fn test_shm_header() {
        let header = ShmHeader::new(1024);
        assert!(header.is_valid());
    }
}
