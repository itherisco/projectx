//! # Julia Runtime Integration using jlrs
//!
//! This module provides integration with Julia using the jlrs crate.
//! It manages the embedded Julia runtime from Rust, replacing the previous
//! subprocess-based approach with direct embedded execution.
//!
//! Features:
//! - Manage Julia runtime from Rust (embedded mode)
//! - Start cognitive loop
//! - Control memory limits (metabolic gating)
//! - Call Julia functions directly with safe scoping
//! - Async-safe callbacks for parallel cognitive circuits

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, RwLock};
use std::path::PathBuf;
use thiserror::Error;

#[cfg(feature = "jlrs")]
use jlrs::prelude::*;
#[cfg(feature = "jlrs")]
use jlrs::runtime::{RuntimeBuilder, Runtime, managed::gc::GcFrame};

/// Julia runtime error
#[derive(Debug, Error)]
pub enum JuliaError {
    #[error("Julia runtime not initialized")]
    NotInitialized,
    #[error("Julia runtime error: {0}")]
    RuntimeError(String),
    #[error("Julia call error: {0}")]
    CallError(String),
    #[error("Memory limit exceeded")]
    MemoryLimitExceeded,
    #[error("Julia is not available")]
    JuliaNotAvailable,
    #[error("Failed to initialize Julia: {0}")]
    InitError(String),
    #[error("Scope error: {0}")]
    ScopeError(String),
}

/// Result type for Julia operations
pub type JuliaResult<T> = Result<T, JuliaError>;

/// Julia runtime state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JuliaState {
    Uninitialized,
    Initializing,
    Running,
    Stopped,
    Error,
}

impl JuliaState {
    fn from_usize(val: usize) -> Self {
        match val {
            0 => JuliaState::Uninitialized,
            1 => JuliaState::Initializing,
            2 => JuliaState::Running,
            3 => JuliaState::Stopped,
            4 => JuliaState::Error,
            _ => JuliaState::Uninitialized,
        }
    }
}

/// Julia runtime configuration
#[derive(Debug, Clone)]
pub struct JuliaConfig {
    /// Number of threads to use
    pub num_threads: Option<usize>,
    /// Memory limit in MB (0 = no limit, default 512MB for metabolic gating)
    pub memory_limit_mb: usize,
    /// Enable debug mode
    pub debug: bool,
    /// Julia project path
    pub project_path: Option<String>,
    /// Sysimage path (for faster startup)
    pub sysimage_path: Option<String>,
    /// Julia library path (JULIA_DIR)
    pub julia_dir: Option<String>,
    /// Enable async runtime for parallel cognitive circuits
    pub async_runtime: bool,
}

impl Default for JuliaConfig {
    fn default() -> Self {
        JuliaConfig {
            num_threads: Some(4),
            memory_limit_mb: 512, // 512MB metabolic energy cap
            debug: false,
            project_path: None,
            sysimage_path: None,
            julia_dir: None,
            async_runtime: true,
        }
    }
}

#[cfg(feature = "jlrs")]
struct JuliaRuntimeInner {
    runtime: Runtime,
    state: JuliaState,
    is_running: AtomicBool,
}

#[cfg(not(feature = "jlrs"))]
struct JuliaRuntimeInner {
    // Stub implementation
    state: JuliaState,
    is_running: AtomicBool,
}

/// Julia runtime manager with jlrs integration
pub struct JuliaRuntime {
    #[cfg(feature = "jlrs")]
    inner: Option<Arc<JuliaRuntimeInner>>,
    #[cfg(not(feature = "jlrs"))]
    inner: Option<Arc<JuliaRuntimeInner>>,
    config: JuliaConfig,
    state: Arc<AtomicUsize>,
}

#[cfg(feature = "jlrs")]
impl JuliaRuntime {
    /// Create a new Julia runtime manager with embedded Julia
    pub fn new(config: JuliaConfig) -> Self {
        JuliaRuntime {
            inner: None,
            config,
            state: Arc::new(AtomicUsize::new(JuliaState::Uninitialized as usize)),
        }
    }
    
    /// Get current state
    pub fn state(&self) -> JuliaState {
        JuliaState::from_usize(self.state.load(Ordering::Acquire))
    }
    
    /// Check if Julia is running
    pub fn is_running(&self) -> bool {
        self.state.load(Ordering::Acquire) == JuliaState::Running as usize
    }
    
    /// Initialize Julia runtime using jlrs
    pub fn initialize(&mut self) -> JuliaResult<()> {
        if self.state.load(Ordering::Acquire) != JuliaState::Uninitialized as usize {
            return Err(JuliaError::RuntimeError("Already initialized".to_string()));
        }
        
        self.state.store(JuliaState::Initializing as usize, Ordering::Release);
        
        // Build the runtime with configured options
        let mut builder = RuntimeBuilder::new()
            .num_threads(self.config.num_threads.unwrap_or(4));
        
        // Set memory limit for metabolic gating
        if self.config.memory_limit_mb > 0 {
            let limit_bytes = self.config.memory_limit_mb * 1024 * 1024;
            builder = builder.memory_limit(limit_bytes);
        }
        
        // Set sysimage if provided (faster startup)
        if let Some(ref sysimage) = self.config.sysimage_path {
            builder = builder.sysimage_path(sysimage);
        }
        
        // Set JULIA_DIR if provided
        if let Some(ref julia_dir) = self.config.julia_dir {
            std::env::set_var("JULIA_DIR", julia_dir);
        }
        
        // Build and initialize the runtime
        let runtime = builder
            .build()
            .map_err(|e| JuliaError::InitError(e.to_string()))?;
        
        // Create inner runtime state
        let inner = Arc::new(JuliaRuntimeInner {
            runtime,
            state: JuliaState::Running,
            is_running: AtomicBool::new(true),
        });
        
        self.inner = Some(inner);
        self.state.store(JuliaState::Running as usize, Ordering::Release);
        
        log::info!("[Julia] Embedded runtime initialized with jlrs (memory limit: {}MB)", self.config.memory_limit_mb);
        
        // Pre-warm JIT by loading the project
        self.prewarm_jit()?;
        
        Ok(())
    }
    
    /// Pre-warm JIT compiler to eliminate "time-to-first-plot" latency
    fn prewarm_jit(&self) -> JuliaResult<()> {
        if let Some(ref inner) = self.inner {
            // Use the runtime to pre-warm JIT
            inner.runtime
                .scope(|_frame| {
                    // Load the AdaptiveKernel module to trigger JIT compilation
                    // This is a no-op if the module doesn't exist, but warms up the JIT
                    let _ = jlrs::Julia::eval_string(_frame, "using Pkg");
                    Ok(())
                })
                .map_err(|e| JuliaError::RuntimeError(format!("JIT prewarm failed: {}", e)))?;
            
            log::info!("[Julia] JIT compiler pre-warmed");
        }
        Ok(())
    }
    
    /// Evaluate Julia code with safe scoping
    pub fn eval(&self, code: &str) -> JuliaResult<String> {
        let inner = self.inner.as_ref().ok_or(JuliaError::NotInitialized)?;
        
        inner.runtime
            .scope(|frame| {
                let result = frame.eval_string(code)?;
                Ok(result.to_string())
            })
            .map_err(|e| JuliaError::CallError(e.to_string()))
    }
    
    /// Call a Julia function by name with proper scoping
    pub fn call_function(&self, module: &str, function: &str, args: &[String]) -> JuliaResult<String> {
        let inner = self.inner.as_ref().ok_or(JuliaError::NotInitialized)?;
        
        inner.runtime
            .scope(|frame| {
                // Access the module
                let main_module = Module::main();
                let target_module = main_module.submodule(module.as_bytes())
                    .map_err(|e| JuliaError::ScopeError(e.to_string()))?;
                
                // Get the function
                let func = target_module.function(function.as_bytes())
                    .map_err(|e| JuliaError::ScopeError(format!("Function {} not found in {}: {}", function, module, e)))?;
                
                // Build arguments if any
                let mut jl_args = Vec::new();
                for arg in args {
                    jl_args.push(arg.as_managed());
                }
                
                // Call the function
                let result = if jl_args.is_empty() {
                    func.call0(frame)?
                } else if jl_args.len() == 1 {
                    func.call1(frame, jl_args[0])?
                } else if jl_args.len() == 2 {
                    func.call2(frame, jl_args[0], jl_args[1])?
                } else {
                    // For more arguments, use callN
                    func.call_n(frame, &jl_args)?
                };
                
                Ok(result.map(|v| v.to_string()).unwrap_or_else(|| "nothing".to_string()))
            })
            .map_err(|e| JuliaError::CallError(e.to_string()))
    }
    
    /// Call the ITHERISCore.infer() function for cognitive inference
    pub fn infer(&self, input_data: &str) -> JuliaResult<String> {
        self.call_function("ITHERISCore", "infer", &[input_data.to_string()])
    }
    
    /// Call the ITHERISCore.learn!() function for learning
    pub fn learn(&self, training_data: &str) -> JuliaResult<String> {
        self.call_function("ITHERISCore", "learn!", &[training_data.to_string()])
    }
    
    /// Get memory usage from Julia
    pub fn get_memory_usage(&self) -> JuliaResult<usize> {
        let inner = self.inner.as_ref().ok_or(JuliaError::NotInitialized)?;
        
        inner.runtime
            .scope(|frame| {
                // Call Julia's GC memory usage
                let code = "Int(Base.gc_live_bytes())";
                let result = frame.eval_string(code)?;
                Ok(result.unwrap().unbox::<i64>().map(|v| v as usize).unwrap_or(0))
            })
            .map_err(|e| JuliaError::CallError(e.to_string()))
    }
    
    /// Force garbage collection
    pub fn gc_collect(&self) -> JuliaResult<()> {
        let inner = self.inner.as_ref().ok_or(JuliaError::NotInitialized)?;
        
        inner.runtime
            .scope(|frame| {
                let _ = frame.eval_string("GC.gc()")?;
                Ok(())
            })
            .map_err(|e| JuliaError::CallError(e.to_string()))
    }
    
    /// Check memory limit (metabolic gating)
    pub fn check_memory_limit(&self) -> JuliaResult<()> {
        if self.config.memory_limit_mb > 0 {
            let usage = self.get_memory_usage()?;
            let limit = self.config.memory_limit_mb * 1024 * 1024;
            
            if usage > limit {
                log::warn!("[Julia] Memory limit exceeded: {}MB > {}MB", usage / (1024*1024), self.config.memory_limit_mb);
                return Err(JuliaError::MemoryLimitExceeded);
            }
        }
        Ok(())
    }
    
    /// Stop Julia runtime
    pub fn stop(&mut self) -> JuliaResult<()> {
        if !self.is_running() {
            return Ok(());
        }
        
        if let Some(ref inner) = self.inner {
            inner.is_running.store(false, Ordering::Release);
        }
        
        self.state.store(JuliaState::Stopped as usize, Ordering::Release);
        self.inner = None;
        
        log::info!("[Julia] Embedded runtime stopped");
        Ok(())
    }
}

#[cfg(not(feature = "jlrs"))]
impl JuliaRuntime {
    /// Create a new Julia runtime manager (stub)
    pub fn new(config: JuliaConfig) -> Self {
        JuliaRuntime {
            inner: None,
            config,
            state: Arc::new(AtomicUsize::new(JuliaState::Uninitialized as usize)),
        }
    }
    
    /// Get current state
    pub fn state(&self) -> JuliaState {
        JuliaState::from_usize(self.state.load(Ordering::Acquire))
    }
    
    /// Check if Julia is running
    pub fn is_running(&self) -> bool {
        self.state.load(Ordering::Acquire) == JuliaState::Running as usize
    }
    
    /// Initialize Julia runtime (stub)
    pub fn initialize(&mut self) -> JuliaResult<()> {
        if self.state.load(Ordering::Acquire) != JuliaState::Uninitialized as usize {
            return Err(JuliaError::RuntimeError("Already initialized".to_string()));
        }
        
        self.state.store(JuliaState::Initializing as usize, Ordering::Release);
        self.state.store(JuliaState::Running as usize, Ordering::Release);
        log::warn!("[Julia] Runtime initialized in STUB mode - jlrs feature not enabled");
        Ok(())
    }
    
    /// Evaluate Julia code (stub)
    pub fn eval(&self, _code: &str) -> JuliaResult<String> {
        log::warn!("[Julia] eval called but Julia integration is stubbed");
        Ok("nothing".to_string())
    }
    
    /// Call a Julia function (stub)
    pub fn call_function(&self, module: &str, function: &str, _args: &[String]) -> JuliaResult<String> {
        log::warn!("[Julia] call_function({}.{}) called but Julia integration is stubbed", module, function);
        Ok("nothing".to_string())
    }
    
    /// Get memory usage (stub)
    pub fn get_memory_usage(&self) -> JuliaResult<usize> {
        Ok(0)
    }
    
    /// Force garbage collection (stub)
    pub fn gc_collect(&self) -> JuliaResult<()> {
        Ok(())
    }
    
    /// Check memory limit
    pub fn check_memory_limit(&self) -> JuliaResult<()> {
        if self.config.memory_limit_mb > 0 {
            let usage = self.get_memory_usage()?;
            let limit = self.config.memory_limit_mb * 1024 * 1024;
            
            if usage > limit {
                return Err(JuliaError::MemoryLimitExceeded);
            }
        }
        Ok(())
    }
    
    /// Stop Julia runtime
    pub fn stop(&mut self) -> JuliaResult<()> {
        if !self.is_running() {
            return Ok(());
        }
        
        self.state.store(JuliaState::Stopped as usize, Ordering::Release);
        log::info!("[Julia] Runtime stopped (stub)");
        Ok(())
    }
}

/// Global Julia runtime reference
static JULIA_RUNTIME: RwLock<Option<Arc<RwLock<JuliaRuntime>>>> = RwLock::new(None);

/// Initialize global Julia runtime
pub fn init_julia_runtime(config: JuliaConfig) -> JuliaResult<()> {
    let mut runtime = JuliaRuntime::new(config);
    runtime.initialize()?;
    
    let mut guard = JULIA_RUNTIME.write()
        .map_err(|e| JuliaError::RuntimeError(e.to_string()))?;
    
    *guard = Some(Arc::new(RwLock::new(runtime)));
    
    Ok(())
}

/// Get global Julia runtime
pub fn get_julia_runtime() -> JuliaResult<Arc<RwLock<JuliaRuntime>>> {
    let guard = JULIA_RUNTIME.read()
        .map_err(|e| JuliaError::RuntimeError(e.to_string()))?;
    
    guard.clone()
        .ok_or(JuliaError::NotInitialized)
}

/// Call Julia function globally
pub fn call_julia_function(module: &str, function: &str, args: &[String]) -> JuliaResult<String> {
    let runtime = get_julia_runtime()?;
    let runtime = runtime.read()
        .map_err(|e| JuliaError::RuntimeError(e.to_string()))?;
    
    runtime.call_function(module, function, args)
}

/// Evaluate Julia code globally
pub fn eval_julia(code: &str) -> JuliaResult<String> {
    let runtime = get_julia_runtime()?;
    let runtime = runtime.read()
        .map_err(|e| JuliaError::RuntimeError(e.to_string()))?;
    
    runtime.eval(code)
}

/// Start cognitive loop in Julia
pub fn start_cognitive_loop() -> JuliaResult<()> {
    call_julia_function("AdaptiveKernel", "start_cognitive_loop", &[])?;
    Ok(())
}

/// Stop cognitive loop in Julia
pub fn stop_cognitive_loop() -> JuliaResult<()> {
    call_julia_function("AdaptiveKernel", "stop_cognitive_loop", &[])?;
    Ok(())
}

// ============================================================================
// C FFI functions for Julia to call
// ============================================================================

/// Initialize Julia from C (exported for Julia to call)
#[no_mangle]
pub extern "C" fn julia_init() -> i32 {
    let config = JuliaConfig::default();
    match init_julia_runtime(config) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Get Julia state (exported for Julia to call)
#[no_mangle]
pub extern "C" fn julia_get_state() -> i32 {
    match get_julia_runtime() {
        Ok(runtime) => {
            match runtime.read() {
                Ok(r) => r.state() as i32,
                Err(_) => -1,
            }
        }
        Err(_) => 0, // Uninitialized
    }
}

/// Check if Julia is running (exported for Julia to call)
#[no_mangle]
pub extern "C" fn julia_is_running() -> i32 {
    match get_julia_runtime() {
        Ok(runtime) => {
            match runtime.read() {
                Ok(r) => if r.is_running() { 1 } else { 0 },
                Err(_) => 0,
            }
        }
        Err(_) => 0,
    }
}

/// Get memory usage in MB (exported for Julia to call)
#[no_mangle]
pub extern "C" fn julia_get_memory_mb() -> i32 {
    match get_julia_runtime() {
        Ok(runtime) => {
            match runtime.read() {
                Ok(r) => {
                    match r.get_memory_usage() {
                        Ok(bytes) => (bytes / (1024 * 1024)) as i32,
                        Err(_) => -1,
                    }
                }
                Err(_) => -1,
            }
        }
        Err(_) => -1,
    }
}

/// Stop Julia runtime from C (exported for Julia to call)
#[no_mangle]
pub extern "C" fn julia_stop() -> i32 {
    match get_julia_runtime() {
        Ok(runtime) => {
            match runtime.write() {
                Ok(mut r) => {
                    match r.stop() {
                        Ok(()) => 0,
                        Err(_) => -1,
                    }
                }
                Err(_) => -1,
            }
        }
        Err(_) => -1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_julia_config() {
        let config = JuliaConfig::default();
        assert_eq!(config.num_threads, Some(4));
        assert_eq!(config.memory_limit_mb, 512); // Now defaults to 512MB
    }
    
    #[test]
    fn test_julia_state() {
        assert_eq!(JuliaState::from_usize(0), JuliaState::Uninitialized);
        assert_eq!(JuliaState::from_usize(1), JuliaState::Initializing);
        assert_eq!(JuliaState::from_usize(2), JuliaState::Running);
        assert_eq!(JuliaState::from_usize(3), JuliaState::Stopped);
        assert_eq!(JuliaState::from_usize(4), JuliaState::Error);
    }
}
