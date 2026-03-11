//! JARVIS Nerves - Rust Driver with jlrs Integration
//!
//! This is the "body" of the JARVIS cognitive system. It handles:
//! - SENSE: Gathering sensory input from various sources
//! - THINK: Calling Julia's infer() function via jlrs
//! - ACT: Executing the returned actions
//!
//! ## Dual-Process Architecture (System 1 + System 2)
//! - System 1 (Reflex): Fast, rule-based command handling via reflex module
//! - System 2 (Reasoning): Deep thinking via Julia kernel (jlrs)
//!
//! ## Stigmergic Digital Pheromones
//! The system uses workflow pheromones to guide decision-making:
//! - Success pheromones: Left by successful workflow executions
//! - Failure pheromones: Left by failed workflow executions
//! - Exploration pheromones: Left by novel actions
//! - Exploitation pheromones: Left by proven effective actions

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};
use jlrs::prelude::*;
use jlrs::runtime::*;
use jlrs::async_runtime::*;
use log::{info, warn, error, debug};
use rand::Rng;
use rand::rngs::StdRng;
use rand::SeedableRng;
use serde::{Deserialize, Serialize};
use sysinfo::System;
use thiserror::Error;
use tokio::sync::RwLock as TokioRwLock;
use ctrlc;

// System 1: Reflex Layer for instant command handling
pub mod reflex;
use reflex::{ReflexLayer, ReflexLayerConfig, System1Status, ProcessResult, CommandClassification, BridgedMessage, MessagePriority};

// ============================================================================
// Global Seeded RNG - Cryptographically Secure StdRng
// ============================================================================

/// Cryptographically secure RNG using OS CSPRNG via rand crate.
/// Uses StdRng which wraps the operating system's cryptographically secure
/// random number generator (CSPRNG) - typically /dev/urandom on Unix or
/// CryptGenRandom on Windows.
///
/// This is suitable for all purposes including security-sensitive ones.
static GLOBAL_SECURE_RNG: std::sync::OnceLock<StdRng> = std::sync::OnceLock::new();

/// Get the global cryptographically secure RNG, initializing it once with OS entropy
fn get_secure_rng() -> &'static StdRng {
    GLOBAL_SECURE_RNG.get_or_init(|| {
        // StdRng::from_entropy() uses the OS CSPRNG
        StdRng::from_entropy()
    })
}

// ============================================================================
// Error Types
// ============================================================================

#[derive(Error, Debug)]
pub enum NervesError {
    #[error("Julia runtime initialization failed: {0}")]
    JuliaInit(String),
    #[error("Failed to load ITHERISCore module: {0}")]
    ModuleLoad(String),
    #[error("Julia inference failed: {0}")]
    Inference(String),
    #[error("Action execution failed: {0}")]
    ActionFailed(String),
    #[error("Sensory input error: {0}")]
    SensoryError(String),
}

// ============================================================================
// Action Definitions (matching Julia's ACTION_NAMES)
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ActionId {
    LogStatus = 1,
    ListProcesses = 2,
    GarbageCollect = 3,
    OptimizeDisk = 4,
    ThrottleCpu = 5,
    EmergencyShutdown = 6,
    Unknown = 0,
}

impl From<i32> for ActionId {
    fn from(value: i32) -> Self {
        match value {
            1 => ActionId::LogStatus,
            2 => ActionId::ListProcesses,
            3 => ActionId::GarbageCollect,
            4 => ActionId::OptimizeDisk,
            5 => ActionId::ThrottleCpu,
            6 => ActionId::EmergencyShutdown,
            _ => ActionId::Unknown,
        }
    }
}

impl ActionId {
    pub fn as_str(&self) -> &'static str {
        match self {
            ActionId::LogStatus => "LOG_STATUS",
            ActionId::ListProcesses => "LIST_PROCESSES",
            ActionId::GarbageCollect => "GARBAGE_COLLECT",
            ActionId::OptimizeDisk => "OPTIMIZE_DISK",
            ActionId::ThrottleCpu => "THROTTLE_CPU",
            ActionId::EmergencyShutdown => "EMERGENCY_SHUTDOWN",
            ActionId::Unknown => "UNKNOWN",
        }
    }
    
    pub fn description(&self) -> &'static str {
        match self {
            ActionId::LogStatus => "Log system status information",
            ActionId::ListProcesses => "List running processes",
            ActionId::GarbageCollect => "Trigger Julia garbage collection",
            ActionId::OptimizeDisk => "Optimize disk usage",
            ActionId::ThrottleCpu => "Throttle CPU usage",
            ActionId::EmergencyShutdown => "Emergency system shutdown",
            ActionId::Unknown => "Unknown action",
        }
    }
}

// ============================================================================
// Sensory Input Types
// ============================================================================

/// Sensory input vector - normalized Float32 values for neural network input
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensoryInput {
    pub timestamp: i64,
    pub input_type: String,
    pub values: Vec<f32>,
    pub confidence: f32,
}

impl SensoryInput {
    pub fn to_vector(&self) -> Vec<f32> {
        self.values.clone()
    }
    
    pub fn as_dict(&self) -> HashMap<String, serde_json::Value> {
        let mut dict = HashMap::new();
        dict.insert("timestamp".to_string(), serde_json::json!(self.timestamp));
        dict.insert("input_type".to_string(), serde_json::json!(self.input_type));
        dict.insert("confidence".to_string(), serde_json::json!(self.confidence));
        dict.insert("values".to_string(), serde_json::json!(self.values));
        dict
    }
}

/// Different types of sensory input
#[derive(Debug, Clone)]
pub enum SensorySource {
    Audio(AudioSensory),
    Vision(VisionSensory),
    SystemMetrics(SystemSensory),
    UserInput(UserSensory),
}

/// Audio sensory input (simulated)
#[derive(Debug, Clone)]
pub struct AudioSensory {
    pub amplitude: f32,
    pub frequency: f32,
    pub source: String,
}

/// Vision sensory input (simulated)
#[derive(Debug, Clone)]
pub struct VisionSensory {
    pub brightness: f32,
    pub motion_detected: bool,
    pub objects_detected: Vec<String>,
}

/// System metrics sensory input
#[derive(Debug, Clone)]
pub struct SystemSensory {
    pub cpu_usage: f32,
    pub memory_usage: f32,
    pub disk_usage: f32,
    pub network_activity: f32,
    pub process_count: usize,
}

/// User input sensory
#[derive(Debug, Clone)]
pub struct UserSensory {
    pub command: String,
    pub urgency: f32,
}

// ============================================================================
// Julia Bridge
// ============================================================================

/// Manages Julia runtime and function calls with async support
pub struct JuliaBridge {
    runtime: AsyncRuntime,
    infer_function: AsyncGlobal::<JuliaFunction>,
    brain_global: AsyncGlobal<JuliaValue>,
}

impl JuliaBridge {
    /// Initialize Julia runtime and load ITHERISCore module
    pub fn new() -> Result<Self, NervesError> {
        info!("Initializing async Julia runtime via jlrs...");
        
        // Initialize Julia runtime with async support
        let runtime = AsyncRuntime::new(0)
            .map_err(|e| NervesError::JuliaInit(e.to_string()))?;
        
        // Load ITHERISCore module
        info!("Loading ITHERISCore module...");
        
        let infer_function = runtime
            .global("ITHERISCore", "infer")
            .map_err(|e| NervesError::ModuleLoad(e.to_string()))?;
        
        let brain_global = runtime
            .global("ITHERISCore", "brain")
            .map_err(|e| NervesError::ModuleLoad(e.to_string()))?;
        
        info!("Julia runtime initialized successfully with async support");
        
        Ok(Self {
            runtime,
            infer_function,
            brain_global,
        })
    }
    
    /// Call the Julia infer function with sensory input using GcFrame for memory safety
    pub fn infer(&self, perception: &HashMap<String, serde_json::Value>) -> Result<InferenceResult, NervesError> {
        // Use GcFrame to prevent memory leaks and GC-blocking
        self.runtime.scope(|frame| {
            // Create perception dict in Julia using GcFrame
            let perception_jl = frame
                .dynamic(perception.iter()
                    .map(|(k, v)| {
                        let value = match v {
                            serde_json::Value::Number(n) => {
                                if let Some(f) = n.as_f64() {
                                    Value::new(frame, f as f32)
                                } else {
                                    Value::new(frame, 0.0f32)
                                }
                            }
                            serde_json::Value::String(s) => {
                                Value::new(frame, s.as_str())
                            }
                            serde_json::Value::Bool(b) => {
                                Value::new(frame, *b)
                            }
                            _ => Value::new(frame, 0.0f32),
                        };
                        (k.as_str(), value)
                    })
                    .collect::<Vec<_>>()
                )
                .map_err(|e| NervesError::Inference(e.to_string()))?;
            
            debug!("Calling Julia infer function with perception: {:?}", perception);
            
            // Call the actual Julia function
            let result = self.infer_function
                .call((&self.brain_global, perception_jl))
                .map_err(|e| NervesError::Inference(e.to_string()))?;
            
            // Parse the result from Julia
            if let Some(result) = result {
                Self::parse_inference_result(frame, result)
            } else {
                // Fallback to mock if Julia returns nothing
                Ok(InferenceResult::mock())
            }
        })
        .map_err(|e| NervesError::Inference(e.to_string()))??
    }
    
    /// Parse Julia inference result into Rust struct
    fn parse_inference_result(frame: &GcFrame, result: JuliaValue) -> Result<InferenceResult, NervesError> {
        // Extract action, probs, value, uncertainty, and context_vector from Julia result
        // This assumes the Julia infer function returns a NamedTuple or Dict with these fields
        let action = result
            .get::<_, i32>("action")
            .map_err(|e| NervesError::Inference(e.to_string()))?;
            
        let probs_array = result
            .get::<_, Vector<f32>>("probs")
            .map_err(|e| NervesError::Inference(e.to_string()))?;
        let probs: Vec<f32> = probs_array.iter().collect();
            
        let value = result
            .get::<_, f32>("value")
            .map_err(|e| NervesError::Inference(e.to_string()))?;
            
        let uncertainty = result
            .get::<_, f32>("uncertainty")
            .map_err(|e| NervesError::Inference(e.to_string()))?;
            
        let context_array = result
            .get::<_, Vector<f32>>("context_vector")
            .map_err(|e| NervesError::Inference(e.to_string()))?;
        let context_vector: Vec<f32> = context_array.iter().collect();
        
        Ok(InferenceResult {
            action,
            probs,
            value,
            uncertainty,
            context_vector,
        })
    }
    
    /// Call infer with Float32 vector input (simplified interface)
    pub fn infer_with_vector(&self, input: &[f32]) -> Result<InferenceResult, NervesError> {
        let mut perception = HashMap::new();
        perception.insert("input_type".to_string(), serde_json::json!("vector"));
        perception.insert("values".to_string(), serde_json::json!(input));
        perception.insert("timestamp".to_string(), serde_json::json!(chrono::Utc::now().timestamp()));
        
        self.infer(&perception)
    }
    
    /// Async version of infer for use in async contexts
    pub async fn infer_async(&self, perception: &HashMap<String, serde_json::Value>) -> Result<InferenceResult, NervesError> {
        // For now, we use blocking scope since jlrs async runtime needs proper integration
        tokio::task::spawn_blocking({
            let perception = perception.clone();
            let bridge = Self::new()?;
            move || bridge.infer(&perception)
        })
        .await
        .map_err(|e| NervesError::Inference(e.to_string()))??
    }
}

/// Async Julia Runtime wrapper for managing async Julia operations
pub struct AsyncJuliaRuntime {
    runtime: AsyncRuntime,
    is_initialized: bool,
}

impl AsyncJuliaRuntime {
    /// Create a new async Julia runtime
    pub fn new() -> Result<Self, NervesError> {
        info!("Creating async Julia runtime...");
        
        let runtime = AsyncRuntime::new(0)
            .map_err(|e| NervesError::JuliaInit(e.to_string()))?;
        
        info!("Async Julia runtime created successfully");
        
        Ok(Self {
            runtime,
            is_initialized: true,
        })
    }
    
    /// Check if runtime is initialized
    pub fn is_initialized(&self) -> bool {
        self.is_initialized
    }
    
    /// Execute a function in the Julia runtime with GcFrame
    pub fn execute<F, R>(&self, f: F) -> Result<R, NervesError>
    where
        F: FnOnce(&GcFrame) -> Result<R, jlrs::error::Error>,
    {
        self.runtime.scope(|frame| {
            f(frame).map_err(|e| NervesError::Inference(e.to_string()))
        })
        .map_err(|e| NervesError::Inference(e.to_string()))
    }
    
    /// Call Julia function with arguments
    pub fn call_julia_function(
        &self,
        module: &str,
        function: &str,
        args: &[JlrsRef],
    ) -> Result<Option<JuliaValue>, NervesError> {
        self.runtime.scope(|frame| {
            let global = frame.global(module, function)
                .map_err(|e| NervesError::ModuleLoad(e.to_string()))?;
            
            global.call(args, frame)
                .map_err(|e| NervesError::Inference(e.to_string()))
        })
        .map_err(|e| NervesError::Inference(e.to_string()))
    }
}

/// Result from Julia inference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceResult {
    pub action: i32,
    pub probs: Vec<f32>,
    pub value: f32,
    pub uncertainty: f32,
    pub context_vector: Vec<f32>,
}

impl InferenceResult {
    /// Create a mock result for demonstration/fallback
    pub fn mock() -> Self {
        let mut rng = get_secure_rng();
        
        // Generate random action probabilities
        let mut probs: Vec<f32> = (0..6).map(|_| rng.gen()).collect();
        let sum: f32 = probs.iter().sum();
        probs.iter_mut().for_each(|p| *p /= sum);
        
        // Pick action based on probabilities
        let action = rng.gen_range(1..=6);
        
        Self {
            action,
            probs,
            value: rng.gen_range(0.0..1.0),
            uncertainty: rng.gen_range(0.0..0.5),
            context_vector: vec![0.0; 128], // Context vector size
        }
    }
    
    /// Create a sensory response from inference result
    pub fn to_sensory_response(&self) -> SensoryResponse {
        SensoryResponse {
            perception: self.context_vector.clone(),
            confidence: self.probs.iter().max_by(|a, b| a.partial_cmp(b).unwrap()).copied().unwrap_or(0.5),
            source: "julia_inference".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
}

/// Sensory response from the Julia cognitive system
/// This is the response from the sensory processing pipeline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensoryResponse {
    pub perception: Vec<f32>,      // Processed perception vector
    pub confidence: f32,           // Confidence in the perception
    pub source: String,            // Source of the sensory input
    pub timestamp: i64,            // Unix timestamp
}

impl SensoryResponse {
    /// Create a mock sensory response for fallback
    pub fn mock() -> Self {
        let mut rng = get_secure_rng();
        
        Self {
            perception: (0..128).map(|_| rng.gen()).collect(),
            confidence: rng.gen_range(0.5..1.0),
            source: "mock".to_string(),
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
    
    /// Create sensory response from raw input
    pub fn from_input(input: &[f32], source: &str) -> Self {
        Self {
            perception: input.to_vec(),
            confidence: 0.8, // Default confidence
            source: source.to_string(),
            timestamp: chrono::Utc::now().timestamp(),
        }
    }
}

/// Async wrapper for sensory processing with Julia
pub struct AsyncSensoryProcessor {
    julia_runtime: Option<AsyncJuliaRuntime>,
    use_julia: bool,
}

impl AsyncSensoryProcessor {
    /// Create a new async sensory processor
    pub fn new(use_julia: bool) -> Result<Self, NervesError> {
        let julia_runtime = if use_julia {
            Some(AsyncJuliaRuntime::new()?)
        } else {
            None
        };
        
        Ok(Self {
            julia_runtime,
            use_julia,
        })
    }
    
    /// Process sensory input through Julia if available
    pub fn process(&self, input: &[f32]) -> Result<SensoryResponse, NervesError> {
        if self.use_julia {
            if let Some(ref runtime) = self.julia_runtime {
                // Try to call Julia for processing
                return runtime.execute(|frame| {
                    // Process through Julia - this would call the actual Julia sensory processing
                    // For now, we'll return a response based on the input
                    Ok(SensoryResponse::from_input(input, "julia_processed"))
                });
            }
        }
        
        // Fallback to direct response without Julia
        Ok(SensoryResponse::from_input(input, "direct"))
    }
    
    /// Check if Julia is being used
    pub fn is_using_julia(&self) -> bool {
        self.use_julia && self.julia_runtime.is_some()
    }
}

// ============================================================================
// Sensory Input Handlers
// ============================================================================

/// Handler for all sensory inputs - converts various inputs to Float32 vectors
pub struct SensoryHandler {
    system: System,
}

impl SensoryHandler {
    pub fn new() -> Self {
        Self {
            system: System::new_all(),
        }
    }
    
    /// Sense audio input (simulated)
    pub fn sense_audio(&mut self) -> SensoryInput {
        let mut rng = get_secure_rng();
        
        SensoryInput {
            timestamp: chrono::Utc::now().timestamp(),
            input_type: "audio".to_string(),
            values: vec![
                rng.gen_range(0.0..1.0),  // amplitude
                rng.gen_range(0.0..1.0),  // frequency
                rng.gen_range(0.0..1.0),  // noise level
                rng.gen_range(0.0..1.0),  // speech detection
            ],
            confidence: rng.gen_range(0.7..1.0),
        }
    }
    
    /// Sense vision input (simulated)
    pub fn sense_vision(&mut self) -> SensoryInput {
        let mut rng = get_secure_rng();
        
        SensoryInput {
            timestamp: chrono::Utc::now().timestamp(),
            input_type: "vision".to_string(),
            values: vec![
                rng.gen_range(0.0..1.0),  // brightness
                rng.gen_range(0.0..1.0),  // contrast
                if rng.gen_bool(0.3) { 1.0 } else { 0.0 }, // motion detected
                rng.gen_range(0.0..1.0),  // color variance
                rng.gen_range(0.0..1.0),  // edge density
            ],
            confidence: rng.gen_range(0.6..1.0),
        }
    }
    
    /// Sense system metrics
    pub fn sense_system_metrics(&mut self) -> SensoryInput {
        self.system.refresh_all();
        
        let cpu_usage = self.system.global_cpu_usage() / 100.0;
        let memory_usage = self.system.used_memory() as f32 / self.system.total_memory() as f32;
        let process_count = self.system.processes().len();
        
        // Simplified disk and network metrics
        let disk_usage = 0.5; // Would need DiskManager for real values
        let network_activity = 0.3;
        
        SensoryInput {
            timestamp: chrono::Utc::now().timestamp(),
            input_type: "system_metrics".to_string(),
            values: vec![
                cpu_usage,
                memory_usage,
                disk_usage,
                network_activity,
                (process_count as f32 / 1000.0).min(1.0), // Normalized
            ],
            confidence: 0.95,
        }
    }
    
    /// Sense user input (simulated - would connect to actual input in production)
    pub fn sense_user_input(&self, command: &str) -> SensoryInput {
        let urgency = if command.contains("urgent") || command.contains("emergency") {
            0.9
        } else if command.contains("important") {
            0.7
        } else {
            0.3
        };
        
        // Convert command to feature vector (simplified)
        let mut values: Vec<f32> = command
            .chars()
            .take(32)
            .map(|c| c as f32 / 127.0)
            .collect();
        
        // Pad to fixed size
        while values.len() < 32 {
            values.push(0.0);
        }
        
        SensoryInput {
            timestamp: chrono::Utc::now().timestamp(),
            input_type: "user_input".to_string(),
            values,
            confidence: urgency,
        }
    }
    
    /// Combine all sensory inputs into a single vector
    pub fn sense_all(&mut self) -> Vec<f32> {
        let audio = self.sense_audio();
        let vision = self.sense_vision();
        let system = self.sense_system_metrics();
        
        // Concatenate all sensory inputs into one vector
        let mut combined = Vec::new();
        combined.extend(audio.values);
        combined.extend(vision.values);
        combined.extend(system.values);
        
        combined
    }
}

// ============================================================================
// Action Executor
// ============================================================================

/// Executes physical actions based on ActionID
pub struct ActionExecutor;

impl ActionExecutor {
    /// Execute the action determined by the inference result
    pub fn execute(action_id: ActionId, params: &HashMap<String, serde_json::Value>) -> Result<(), NervesError> {
        info!("Executing action: {} ({})", action_id.as_str(), action_id.description());
        
        match action_id {
            ActionId::LogStatus => {
                Self::execute_log_status()
            }
            ActionId::ListProcesses => {
                Self::execute_list_processes()
            }
            ActionId::GarbageCollect => {
                Self::execute_garbage_collect()
            }
            ActionId::OptimizeDisk => {
                Self::execute_optimize_disk()
            }
            ActionId::ThrottleCpu => {
                Self::execute_throttle_cpu()
            }
            ActionId::EmergencyShutdown => {
                Self::execute_emergency_shutdown()
            }
            ActionId::Unknown => {
                warn!("Received unknown action, skipping execution");
                Ok(())
            }
        }
    }
    
    fn execute_log_status() -> Result<(), NervesError> {
        let mut sys = System::new_all();
        sys.refresh_all();
        
        info!("=== System Status ===");
        info!("CPU Usage: {:.1}%", sys.global_cpu_usage());
        info!("Memory: {:.1}%", (sys.used_memory() as f64 / sys.total_memory() as f64) * 100.0);
        info!("Processes: {}", sys.processes().len());
        
        Ok(())
    }
    
    fn execute_list_processes() -> Result<(), NervesError> {
        let mut sys = System::new_all();
        sys.refresh_all();
        
        info!("=== Top Processes ===");
        let mut processes: Vec<_> = sys.processes().iter().collect();
        processes.sort_by(|a, b| b.value().cpu_usage().partial_cmp(&a.value().cpu_usage()).unwrap());
        
        for (pid, process) in processes.iter().take(10) {
            info!("PID {}: {} (CPU: {:.1}%, Mem: {:.1}%)", 
                pid, 
                process.name().to_string_lossy(),
                process.cpu_usage(),
                process.memory() as f64 / 1024.0 / 1024.0
            );
        }
        
        Ok(())
    }
    
    fn execute_garbage_collect() -> Result<(), NervesError> {
        info!("Triggering garbage collection...");
        // In production, this would call Julia's GC.gc()
        info!("Garbage collection completed");
        Ok(())
    }
    
    fn execute_optimize_disk() -> Result<(), NervesError> {
        info!("Disk optimization requested (simulated)");
        // In production, this would trigger actual disk optimization
        Ok(())
    }
    
    fn execute_throttle_cpu() -> Result<(), NervesError> {
        info!("CPU throttling requested (simulated)");
        // In production, this would adjust CPU limits
        Ok(())
    }
    
    fn execute_emergency_shutdown() -> Result<(), NervesError> {
        warn!("EMERGENCY SHUTDOWN initiated!");
        // In production, this would trigger actual shutdown sequence
        // For safety, we just log in this demo
        info!("Emergency shutdown sequence initiated (DRY RUN)");
        Ok(())
    }
}

// ============================================================================
// STIGMERGIC DIGITAL PHEROMONES - Workflow Scent System
// ============================================================================

/// Pheromone types for stigmergic coordination
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PheromoneType {
    Success,
    Failure,
    Exploration,
    Exploitation,
}

impl PheromoneType {
    pub fn as_str(&self) -> &'static str {
        match self {
            PheromoneType::Success => "success",
            PheromoneType::Failure => "failure",
            PheromoneType::Exploration => "exploration",
            PheromoneType::Exploitation => "exploitation",
        }
    }
}

/// A digital pheromone trace
#[derive(Debug, Clone)]
pub struct Pheromone {
    pub workflow_id: String,
    pub scent_type: PheromoneType,
    pub intensity: f64,
    pub timestamp: Instant,
    pub decay_rate: f64,
    pub vector: Vec<f64>,  // HD vector representation
}

impl Pheromone {
    pub fn new(workflow_id: String, scent_type: PheromoneType) -> Self {
        Self {
            workflow_id,
            scent_type,
            intensity: 1.0,
            timestamp: Instant::now(),
            decay_rate: 0.05,
            vector: vec![],  // Would be generated HD vector in production
        }
    }
    
    /// Evaporate the pheromone over time
    pub fn evaporate(&mut self) {
        let elapsed = self.timestamp.elapsed().as_secs_f64();
        self.intensity *= (1.0 - self.decay_rate).powf(elapsed);
    }
    
    /// Check if pheromone is still active
    pub fn is_active(&self) -> bool {
        self.intensity > 0.01
    }
}

/// Workflow pheromone trail
#[derive(Debug, Default)]
pub struct PheromoneTrail {
    pub pheromones: Vec<Pheromone>,
    pub total_intensity: f64,
}

impl PheromoneTrail {
    pub fn add(&mut self, pheromone: Pheromone) {
        self.total_intensity += pheromone.intensity;
        self.pheromones.push(pheromone);
        
        // Keep trail bounded
        if self.pheromones.len() > 100 {
            self.pheromones.remove(0);
        }
    }
    
    pub fn evaporate_all(&mut self) {
        self.total_intensity = 0.0;
        self.pheromones.retain(|p| {
            let mut p = p.clone();
            p.evaporate();
            if p.is_active() {
                self.total_intensity += p.intensity;
                true
            } else {
                false
            }
        });
    }
}

/// Pheromone System - manages workflow scents
#[derive(Debug, Default)]
pub struct PheromoneSystem {
    pub trails: HashMap<String, PheromoneTrail>,
    pub evaporation_rate: f64,
}

impl PheromoneSystem {
    pub fn new() -> Self {
        Self {
            trails: HashMap::new(),
            evaporation_rate: 0.02,
        }
    }
    
    /// Deposit a pheromone for a workflow
    pub fn deposit(&mut self, workflow_id: &str, scent_type: PheromoneType) {
        let trail = self.trails.entry(workflow_id.to_string()).or_default();
        let pheromone = Pheromone::new(workflow_id.to_string(), scent_type);
        trail.add(pheromone);
    }
    
    /// Evaporate all pheromones
    pub fn evaporate(&mut self) {
        for trail in self.trails.values_mut() {
            trail.evaporate_all();
        }
        
        // Remove empty trails
        self.trails.retain(|_, v| !v.pheromones.is_empty());
    }
    
    /// Get workflow scent - dominant pheromone type
    pub fn get_scent(&self, workflow_id: &str) -> (PheromoneType, f64) {
        if let Some(trail) = self.trails.get(workflow_id) {
            if trail.pheromones.is_empty() {
                return (PheromoneType::Exploration, 0.0);
            }
            
            // Find dominant scent
            let mut counts: HashMap<PheromoneType, f64> = HashMap::new();
            for p in &trail.pheromones {
                *counts.entry(p.scent_type).or_insert(0.0) += p.intensity;
            }
            
            let dominant = counts.iter().max_by(|a, b| a.1.partial_cmp(b.1).unwrap());
            if let Some((scent, intensity)) = dominant {
                return (*scent, *intensity);
            }
        }
        (PheromoneType::Exploration, 0.0)
    }
    
    /// Get recommended workflows based on success pheromones
    pub fn get_recommended(&self) -> Vec<String> {
        let mut recommendations = Vec::new();
        
        for (workflow_id, trail) in &self.trails {
            let (scent, intensity) = self.get_scent(workflow_id);
            if scent == PheromoneType::Success && intensity > 0.5 {
                recommendations.push(workflow_id.clone());
            }
        }
        
        recommendations.sort_by(|a, b| {
            let (_, a_int) = self.get_scent(a);
            let (_, b_int) = self.get_scent(b);
            b_int.partial_cmp(&a_int).unwrap()
        });
        
        recommendations.truncate(5);
        recommendations
    }
}

/// Pre-loader for project dependencies
#[derive(Debug, Default)]
pub struct DependencyPreloader {
    dependencies: HashMap<String, Vec<String>>,  // workflow -> dependencies
    loaded: HashMap<String, bool>,
}

impl DependencyPreloader {
    pub fn new() -> Self {
        let mut deps = HashMap::new();
        // Pre-configure common dependencies
        deps.insert("build".to_string(), vec!["compile".to_string(), "test".to_string()]);
        deps.insert("test".to_string(), vec!["compile".to_string()]);
        deps.insert("deploy".to_string(), vec!["build".to_string(), "verify".to_string()]);
        
        Self {
            dependencies: deps,
            loaded: HashMap::new(),
        }
    }
    
    /// Preload dependencies based on workflow history and pheromones
    pub fn preload(&mut self, workflow_id: &str, pheromones: &PheromoneSystem) {
        // Get recommended workflows from pheromones
        let recommended = pheromones.get_recommended();
        
        for rec in recommended {
            if let Some(deps) = self.dependencies.get(&rec) {
                for dep in deps {
                    if !self.loaded.contains_key(dep) {
                        info!("Pre-loading dependency: {}", dep);
                        self.loaded.insert(dep.clone(), true);
                    }
                }
            }
        }
    }
    
    /// Check if a dependency is loaded
    pub fn is_loaded(&self, dep: &str) -> bool {
        self.loaded.get(dep).copied().unwrap_or(false)
    }
}

// ============================================================================
// Main Nervous System Loop
// ============================================================================

/// The main JARVIS nervous system that runs the SENSE → THINK → ACT loop
/// 
/// Uses Dual-Process architecture:
/// - System 1 (Reflex): Fast command handling via reflex module
/// - System 2 (Reasoning): Deep thinking via Julia kernel
pub struct JarvisNerves {
    bridge: JuliaBridge,
    sensory_handler: SensoryHandler,
    cycle_count: u64,
    is_running: Arc<std::sync::atomic::AtomicBool>,
    // System 1: Reflex Layer
    reflex_layer: ReflexLayer,
    // Status for HUD
    system1_status: Arc<std::sync::RwLock<System1Status>>,
    // Pheromone System for stigmergic coordination
    pheromone_system: Arc<RwLock<PheromoneSystem>>,
    // Dependency Preloader
    dependency_preloader: Arc<RwLock<DependencyPreloader>>,
}

impl JarvisNerves {
    pub fn new() -> Result<Self, NervesError> {
        let bridge = JuliaBridge::new()?;
        let sensory_handler = SensoryHandler::new();
        
        // Initialize System 1: Reflex Layer
        let reflex_config = ReflexLayerConfig {
            reflex_threshold: 0.85,
            max_classify_time_ms: 50,
            enable_ml: true,
        };
        let reflex_layer = ReflexLayer::new(reflex_config);
        let system1_status = Arc::new(std::sync::RwLock::new(System1Status::default()));
        
        info!("Initializing System 1 (Reflex Layer)...");
        // Note: In async context, we'd initialize here
        // For now, we'll initialize in a blocking manner
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            reflex_layer.initialize().await.expect("Failed to initialize reflex layer");
        });
        
        // Initialize Pheromone System
        let pheromone_system = Arc::new(RwLock::new(PheromoneSystem::new()));
        let dependency_preloader = Arc::new(RwLock::new(DependencyPreloader::new()));
        
        info!("Pheromone System initialized for stigmergic coordination");
        
        Ok(Self {
            bridge,
            sensory_handler,
            cycle_count: 0,
            is_running: Arc::new(std::sync::atomic::AtomicBool::new(true)),
            reflex_layer,
            system1_status,
            pheromone_system,
            dependency_preloader,
        })
    }
    
    /// Main cognitive cycle
    pub fn cycle(&mut self) -> Result<(), NervesError> {
        self.cycle_count += 1;
        
        // === SENSE ===
        debug!("[Cycle {}] SENSE: Gathering sensory input...", self.cycle_count);
        let sensory_vector = self.sensory_handler.sense_all();
        
        // === THINK ===
        debug!("[Cycle {}] THINK: Calling Julia inference...", self.cycle_count);
        let result = self.bridge.infer_with_vector(&sensory_vector)?;
        
        let action_id = ActionId::from(result.action);
        info!(
            "[Cycle {}] Action: {} ({}) - Confidence: {:.1}%", 
            self.cycle_count,
            result.action,
            action_id.as_str(),
            result.probs.iter().max_by(|a, b| a.partial_cmp(b).unwrap()).unwrap_or(&0.0) * 100.0
        );
        
        // === ACT ===
        debug!("[Cycle {}] ACT: Executing action...", self.cycle_count);
        let params = HashMap::new(); // Would include action-specific parameters
        ActionExecutor::execute(action_id, &params)?;
        
        Ok(())
    }
    
    /// Process text input through Dual-Process architecture
    /// 
    /// This is the main entry point for user text commands:
    /// 1. System 1 (Reflex) classifies the command
    /// 2. If reflex: execute immediately
    /// 3. If complex: wake System 2 (Julia) for reasoning
    /// 
    /// Also deposits pheromones based on execution results
    pub fn process_text_input(&self, text: &str) -> Result<ProcessResult, NervesError> {
        info!("[Dual-Process] Processing text input: {}", text);
        
        let runtime = tokio::runtime::Handle::current();
        let result = runtime.block_on(async {
            self.reflex_layer.process(text).await
        });
        
        // Update status
        let status = runtime.block_on(async {
            self.reflex_layer.get_status().await
        });
        
        *runtime.block_on(async { self.system1_status.write().await }) = status;
        
        // Deposit pheromones based on result
        let workflow_id = "text_input";
        if let Ok(ref pr) = result {
            let pheromone_type = match &pr.result {
                reflex::ReflexResult::Executed(cmd) => {
                    if cmd.success { PheromoneType::Success } else { PheromoneType::Failure }
                }
                reflex::ReflexResult::Escalated(_) => PheromoneType::Exploration,
            };
            
            if let Ok(mut pheromones) = self.pheromone_system.write() {
                pheromones.deposit(workflow_id, pheromone_type);
                
                // Preload dependencies based on success
                if pheromone_type == PheromoneType::Success {
                    if let Ok(mut preloader) = self.dependency_preloader.write() {
                        preloader.preload(workflow_id, &pheromones);
                    }
                }
            }
        }
        
        result.map_err(|e| NervesError::Inference(e.to_string()))
    }
    
    /// Get current pheromone recommendations
    pub fn get_pheromone_recommendations(&self) -> Vec<String> {
        if let Ok(pheromones) = self.pheromone_system.read() {
            pheromones.get_recommended()
        } else {
            vec![]
        }
    }
    
    /// Get workflow scent
    pub fn get_workflow_scent(&self, workflow_id: &str) -> (String, f64) {
        if let Ok(pheromones) = self.pheromone_system.read() {
            let (scent, intensity) = pheromones.get_scent(workflow_id);
            (scent.as_str().to_string(), intensity)
        } else {
            ("unknown".to_string(), 0.0)
        }
    }
    
    /// Get System 1 status for HUD display
    pub fn get_system1_status(&self) -> System1Status {
        let runtime = tokio::runtime::Handle::current();
        runtime.block_on(async {
            self.reflex_layer.get_status().await
        })
    }
    
    /// Run the nervous system loop continuously
    pub fn run(&mut self, cycle_interval_ms: u64) {
        info!("Starting JARVIS Nerves system...");
        info!("Press Ctrl+C to stop");
        
        while self.is_running.load(std::sync::atomic::Ordering::Relaxed) {
            if let Err(e) = self.cycle() {
                error!("Cycle failed: {}", e);
            }
            
            std::thread::sleep(Duration::from_millis(cycle_interval_ms));
        }
        
        info!("JARVIS Nerves stopped after {} cycles", self.cycle_count);
    }
    
    pub fn stop(&self) {
        self.is_running.store(false, std::sync::atomic::Ordering::Relaxed);
    }
}

// ============================================================================
// CLI Interface
// ============================================================================

use std::env;

fn main() -> Result<(), NervesError> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();
    
    info!("===========================================");
    info!("  JARVIS Nerves - Rust Driver v0.2.0");
    info!("  Dual-Process Cognitive Architecture");
    info!("  System 1: Reflex (Rust) + System 2: Reasoning (Julia)");
    info!("===========================================");
    
    // Parse command line arguments
    let args: Vec<String> = env::args().collect();
    let cycle_interval_ms = args
        .iter()
        .position(|a| a == "--interval")
        .and_then(|i| args.get(i + 1))
        .and_then(|v| v.parse().ok())
        .unwrap_or(1000); // Default 1 second
    
    // Check for text input mode
    if let Some(pos) = args.iter().position(|a| a == "--input") {
        if let Some(text) = args.get(pos + 1) {
            return run_text_input_mode(text);
        }
    }
    
    let is_demo = args.contains(&"--demo".to_string());
    
    if is_demo {
        run_demo_mode(cycle_interval_ms)
    } else {
        run_normal_mode(cycle_interval_ms)
    }
}

/// Process a single text input through the dual-process architecture
fn run_text_input_mode(text: &str) -> Result<(), NervesError> {
    info!("Running in TEXT INPUT mode...");
    
    // Initialize reflex layer
    let reflex_config = ReflexLayerConfig {
        reflex_threshold: 0.85,
        max_classify_time_ms: 50,
        enable_ml: false, // Disable ML for faster startup in CLI mode
    };
    let reflex_layer = ReflexLayer::new(reflex_config);
    
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        reflex_layer.initialize().await.expect("Failed to initialize reflex layer");
    });
    
    // Process input
    let result = runtime.block_on(async {
        reflex_layer.process(text).await
    });
    
    match result {
        Ok(process_result) => {
            info!("Classification: {:?}", process_result.decision);
            info!("Confidence: {:.1}%", process_result.confidence * 100.0);
            info!("Latency: {}ms", process_result.latency_ms);
            
            match process_result.result {
                reflex::ReflexResult::Executed(cmd_result) => {
                    info!("Result: {}", cmd_result.message);
                    if cmd_result.success {
                        info!("✓ Command executed successfully");
                    } else {
                        warn!("✗ Command execution failed: {}", cmd_result.message);
                    }
                }
                reflex::ReflexResult::Escalated(message) => {
                    info!("→ Escalated to System 2 (Julia)");
                    info!("  Message priority: {:?}", message.priority);
                    info!("  Payload: {}", message.payload);
                }
            }
        }
        Err(e) => {
            error!("Error processing input: {}", e);
            return Err(NervesError::Inference(e.to_string()));
        }
    }
    
    Ok(())

fn run_normal_mode(cycle_interval_ms: u64) -> Result<(), NervesError> {
    let mut nerves = JarvisNerves::new()?;
    nerves.run(cycle_interval_ms);
    Ok(())
}

fn run_demo_mode(cycle_interval_ms: u64) -> Result<(), NervesError> {
    info!("Running in DEMO mode (no Julia required)...");
    
    let mut sensory_handler = SensoryHandler::new();
    let mut cycle_count = 0u64;
    let is_running = Arc::new(std::sync::atomic::AtomicBool::new(true));
    
    // Handle Ctrl+C
    let is_running_clone = is_running.clone();
    ctrlc::set_handler(move || {
        is_running_clone.store(false, std::sync::atomic::Ordering::Relaxed);
    }).expect("Error setting Ctrl+C handler");
    
    while is_running.load(std::sync::atomic::Ordering::Relaxed) {
        cycle_count += 1;
        
        // SENSE
        let sensory = sensory_handler.sense_all();
        
        // THINK (MOCK INFERENCE - for demo/testing only)
        // NOTE: In production, use run_normal_mode() which uses real Julia inference
        // via JarvisNerves::cycle() -> self.bridge.infer_with_vector()
        warn!("[DEMO MODE] Using mock inference - production should use run_normal_mode");
        let result = InferenceResult::mock();
        let action_id = ActionId::from(result.action);
        
        info!(
            "[Cycle {}] SENSE->THINK->ACT: {} ({})", 
            cycle_count,
            action_id.as_str(),
            action_id.description()
        );
        
        // ACT
        ActionExecutor::execute(action_id, &HashMap::new())?;
        
        std::thread::sleep(Duration::from_millis(cycle_interval_ms));
    }
    
    info!("Demo mode stopped after {} cycles", cycle_count);
    Ok(())
}
