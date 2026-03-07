//! # Julia Runtime Integration
//!
//! This module provides integration with Julia using the jlrs crate.
//! It allows Rust to manage Julia runtime, call Julia functions directly,
//! and control memory limits.
//!
//! Features:
//! - Manage Julia runtime from Rust
//! - Start cognitive loop
//! - Control memory limits
//! - Call Julia functions directly

use jlrs::prelude::*;
use jlrs::runtime::{Runtime, RuntimeBuilder};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, RwLock};
use thiserror::Error;

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

/// Julia runtime configuration
#[derive(Debug, Clone)]
pub struct JuliaConfig {
    /// Number of threads to use
    pub num_threads: Option<usize>,
    /// Memory limit in MB (0 = no limit)
    pub memory_limit_mb: usize,
    /// Enable debug mode
    pub debug: bool,
    /// Julia project path
    pub project_path: Option<String>,
    /// Sysimage path (for faster startup)
    pub sysimage_path: Option<String>,
}

impl Default for JuliaConfig {
    fn default() -> Self {
        JuliaConfig {
            num_threads: Some(4),
            memory_limit_mb: 0, // No limit by default
            debug: false,
            project_path: None,
            sysimage_path: None,
        }
    }
}

/// Julia runtime manager
pub struct JuliaRuntime {
    runtime: Option<Runtime>,
    state: Arc<AtomicUsize>,
    config: JuliaConfig,
    is_running: AtomicBool,
}

impl JuliaRuntime {
    /// Create a new Julia runtime manager
    pub fn new(config: JuliaConfig) -> Self {
        JuliaRuntime {
            runtime: None,
            state: Arc::new(AtomicUsize::new(JuliaState::Uninitialized as usize)),
            config,
            is_running: AtomicBool::new(false),
        }
    }
    
    /// Get current state
    pub fn state(&self) -> JuliaState {
        JuliaState::from_usize(self.state.load(Ordering::Acquire))
    }
    
    /// Check if Julia is running
    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::Acquire)
    }
    
    /// Initialize Julia runtime
    pub fn initialize(&mut self) -> JuliaResult<()> {
        if self.state.load(Ordering::Acquire) != JuliaState::Uninitialized as usize {
            return Err(JuliaError::RuntimeError("Already initialized".to_string()));
        }
        
        self.state.store(JuliaState::Initializing as usize, Ordering::Release);
        
        // Build runtime
        let mut builder = RuntimeBuilder::new()
            .gradients(false);
        
        if let Some(threads) = self.config.num_threads {
            builder = builder.num_threads(threads);
        }
        
        if self.config.debug {
            builder = builder.debug(true);
        }
        
        if let Some(ref sysimage) = self.config.sysimage_path {
            // Load custom sysimage if provided
            log::info!("[Julia] Loading sysimage: {}", sysimage);
        }
        
        match builder.build() {
            Ok(runtime) => {
                self.runtime = Some(runtime);
                self.state.store(JuliaState::Running as usize, Ordering::Release);
                self.is_running.store(true, Ordering::Release);
                log::info!("[Julia] Runtime initialized successfully");
                Ok(())
            }
            Err(e) => {
                self.state.store(JuliaState::Error as usize, Ordering::Release);
                Err(JuliaError::RuntimeError(format!("Failed to initialize: {:?}", e)))
            }
        }
    }
    
    /// Call a Julia function
    pub fn call<F, R>(&self, f: F) -> JuliaResult<R>
    where
        F: for<'scope> FnOnce(&'scope JlrsIO) -> JuliaResult<R>,
    {
        let runtime = self.runtime.as_ref()
            .ok_or(JuliaError::NotInitialized)?;
        
        runtime
            .scope(|scope| f(scope))
            .map_err(|e| JuliaError::CallError(format!("{:?}", e)))
    }
    
    /// Evaluate Julia code
    pub fn eval(&self, code: &str) -> JuliaResult<JlValue> {
        self.call(|scope| {
            let code_jl = Code::new_str(code)
                .map_err(|e| JuliaError::CallError(format!("Invalid code: {:?}", e)))?;
            
            scope.eval(code_jl)
                .map_err(|e| JuliaError::CallError(format!("Eval error: {:?}", e)))
        })
    }
    
    /// Call a Julia function by name
    pub fn call_function(&self, module: &str, function: &str, args: &[JlValue]) -> JuliaResult<JlValue> {
        self.call(|scope| {
            // Get module
            let module = scope.module(module)
                .map_err(|e| JuliaError::CallError(format!("Module not found: {:?}", e)))?;
            
            // Get function
            let func = module
                .function(function, false)
                .map_err(|e| JuliaError::CallError(format!("Function not found: {:?}", e)))?;
            
            // Call function with arguments
            let result = if args.is_empty() {
                func.call0()
            } else if args.len() == 1 {
                func.call1(args[0])
            } else if args.len() == 2 {
                func.call2(args[0], args[1])
            } else if args.len() == 3 {
                func.call3(args[0], args[1], args[2])
            } else {
                return Err(JuliaError::CallError("Too many arguments".to_string()));
            };
            
            result.map_err(|e| JuliaError::CallError(format!("Call error: {:?}", e)))
        })
    }
    
    /// Get memory usage
    pub fn get_memory_usage(&self) -> JuliaResult<usize> {
        self.call(|scope| {
            // Call Julia's gc_total_memory
            let result = scope.eval(Code::new_str("Int(Base.gc_total_memory())")?)
                .map_err(|e| JuliaError::CallError(format!("{:?}", e)))?;
            
            let bytes = result.unbox::<i64>()
                .map_err(|e| JuliaError::CallError(format!("Failed to get memory: {:?}", e)))? as usize;
            
            Ok(bytes)
        })
    }
    
    /// Force garbage collection
    pub fn gc_collect(&self) -> JuliaResult<()> {
        self.call(|scope| {
            scope.eval(Code::new_str("GC.gc()")?)
                .map_err(|e| JuliaError::CallError(format!("GC error: {:?}", e)))?;
            Ok(())
        })
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
        if !self.is_running.load(Ordering::Acquire) {
            return Ok(());
        }
        
        // Force GC before stopping
        let _ = self.gc_collect();
        
        self.runtime = None;
        self.is_running.store(false, Ordering::Release);
        self.state.store(JuliaState::Stopped as usize, Ordering::Release);
        
        log::info!("[Julia] Runtime stopped");
        Ok(())
    }
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
pub fn call_julia_function(module: &str, function: &str, args: &[JlValue]) -> JuliaResult<JlValue> {
    let runtime = get_julia_runtime()?;
    let runtime = runtime.read()
        .map_err(|e| JuliaError::RuntimeError(e.to_string()))?;
    
    runtime.call_function(module, function, args)
}

/// Evaluate Julia code globally
pub fn eval_julia(code: &str) -> JuliaResult<JlValue> {
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
        assert_eq!(config.memory_limit_mb, 0);
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
