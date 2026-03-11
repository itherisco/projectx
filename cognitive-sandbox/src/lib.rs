//! # Cognitive Sandbox - Wasmtime Runtime Host for ITHERIS Ω
//!
//! This module provides a Wasmtime-based runtime for dynamically loading
//! and executing WebAssembly agent modules (Sentry, Librarian, Action).
//!
//! ## Architecture
//!
//! - [`HostRuntime`] - Main runtime managing Wasmtime engine and module instances
//! - [`AgentModule`] - Represents a loaded Wasm agent module
//! - [`AgentInstance`] - Live instance of an agent with its execution context
//! - [`IpcChannel`] - Julia↔Rust inter-process communication
//! - [`WasmInterface`] - Contract defining WASM exports/imports

use anyhow::{Context, Result};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;
use wasmtime::{Engine, Instance, Linker, Module, Store};

// ============================================================================
// WASM Interface Contract
// ============================================================================

/// Interface definition for agent Wasm modules
/// All agent modules must implement these exports and can import these functions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WasmInterface {
    /// Module name (sentry, librarian, action)
    pub module_name: String,
    /// Version semver
    pub version: String,
    /// Exported functions agent provides
    pub exports: Vec<ExportFunc>,
    /// Required imports from host
    pub imports: Vec<ImportFunc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportFunc {
    pub name: String,
    pub description: String,
    pub params: Vec<ParamType>,
    pub return_type: Option<ParamType>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportFunc {
    pub name: String,
    pub description: String,
    pub params: Vec<ParamType>,
    pub return_type: Option<ParamType>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ParamType {
    I32,
    I64,
    F32,
    F64,
    String,
    Void,
}

/// Agent types in the holonic swarm
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AgentType {
    Sentry,
    Librarian,
    Action,
}

impl AgentType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AgentType::Sentry => "sentry",
            AgentType::Librarian => "librarian",
            AgentType::Action => "action",
        }
    }
}

// ============================================================================
// Agent Module and Instance
// ============================================================================

/// Represents a loaded Wasm module (not yet instantiated)
pub struct AgentModule {
    pub id: Uuid,
    pub module_name: String,
    pub version: String,
    pub path: String,
    pub interface: WasmInterface,
    _module: Module,
}

/// Live instance of an agent with execution context
pub struct AgentInstance {
    pub id: Uuid,
    pub module_id: Uuid,
    pub agent_type: AgentType,
    pub instance: Instance,
    pub store: Store<HostState>,
    pub loaded_at: chrono::DateTime<chrono::Utc>,
}

impl AgentInstance {
    /// Invoke a function on this agent instance
    pub fn invoke(&mut self, func_name: &str, args: &[wasmtime::Val]) -> Result<wasmtime::Val> {
        let func = self
            .instance
            .get_func(&self.store, func_name)
            .with_context(|| format!("Function '{}' not found in agent instance", func_name))?;

        let results = func
            .call(&mut self.store, args)
            .with_context(|| format!("Failed to invoke function '{}'", func_name))?;

        Ok(results.get(0).cloned().unwrap_or(wasmtime::Val::I32(0)))
    }
}

// ============================================================================
// Host State
// ============================================================================

/// State shared with Wasm instances
pub struct HostState {
    pub agent_id: Option<Uuid>,
    pub agent_type: Option<AgentType>,
    pub message_buffer: Vec<u8>,
    pub log_messages: Vec<LogMessage>,
}

impl HostState {
    pub fn new() -> Self {
        Self {
            agent_id: None,
            agent_type: None,
            message_buffer: Vec::new(),
            log_messages: Vec::new(),
        }
    }
}

impl Default for HostState {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogMessage {
    pub level: String,
    pub message: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

// ============================================================================
// IPC Channel
// ============================================================================

/// Inter-process communication channel for Julia↔Rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcMessage {
    pub id: Uuid,
    pub from: String,
    pub to: String,
    pub payload: Vec<u8>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl IpcMessage {
    pub fn new(from: &str, to: &str, payload: Vec<u8>) -> Self {
        Self {
            id: Uuid::new_v4(),
            from: from.to_string(),
            to: to.to_string(),
            payload,
            timestamp: chrono::Utc::now(),
        }
    }
}

/// IPC Channel for communication with Julia runtime
pub struct IpcChannel {
    pub send_queue: Arc<RwLock<Vec<IpcMessage>>>,
    pub receive_queue: Arc<RwLock<Vec<IpcMessage>>>,
}

impl IpcChannel {
    pub fn new() -> Self {
        Self {
            send_queue: Arc::new(RwLock::new(Vec::new())),
            receive_queue: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Send a message to Julia
    pub fn send(&self, msg: IpcMessage) {
        self.send_queue.write().push(msg);
    }

    /// Receive a message from Julia
    pub fn receive(&self) -> Option<IpcMessage> {
        self.receive_queue.write().pop()
    }
}

impl Default for IpcChannel {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Host Runtime
// ============================================================================

/// Main Wasmtime runtime for managing agent modules
pub struct HostRuntime {
    engine: Engine,
    linker: Linker<HostState>,
    modules: HashMap<Uuid, AgentModule>,
    instances: HashMap<Uuid, AgentInstance>,
    ipc_channel: IpcChannel,
}

impl HostRuntime {
    /// Create a new host runtime
    pub fn new() -> Result<Self> {
        info!("Initializing Wasmtime host runtime");

        let engine = Engine::default();
        let mut linker = Linker::new(&engine);

        // Link WASI (if needed)
        // wasmtime_wasi::add_to_linker(&mut linker, |s| s)?;

        // Link host functions
        Self::link_host_functions(&mut linker)?;

        info!("Wasmtime engine initialized successfully");

        Ok(Self {
            engine,
            linker,
            modules: HashMap::new(),
            instances: HashMap::new(),
            ipc_channel: IpcChannel::new(),
        })
    }

    /// Link host functions that Wasm modules can import
    fn link_host_functions(linker: &mut Linker<HostState>) -> Result<()> {
        // Host logging function
        linker.func_wrap(
            "host",
            "log",
            |mut store: wasmtime::StoreContextMut<HostState>, level: i32, ptr: i32, len: i32| {
                let memory = store
                    .get_store()
                    .get(wasmtime::MemoryIndex::new(0))
                    .unwrap();
                let data = memory.data(&store);
                let msg = String::from_utf8_lossy(&data[ptr as usize..(ptr + len) as usize]);
                let level_str = match level {
                    0 => "DEBUG",
                    1 => "INFO",
                    2 => "WARN",
                    3 => "ERROR",
                    _ => "UNKNOWN",
                };
                tracing::debug!(level = level_str, "{}", msg);
            },
        )?;

        // Host memory allocation
        linker.func_wrap(
            "host",
            "allocate",
            |mut store: wasmtime::StoreContextMut<HostState>, size: i32| -> i32 {
                let mem = store
                    .get_store()
                    .get(wasmtime::MemoryIndex::new(0))
                    .unwrap();
                let current_len = mem.data(&store).len();
                let new_len = current_len + size as usize;
                // In real implementation, would actually grow memory
                current_len as i32
            },
        )?;

        // Host memory deallocation
        linker.func_wrap(
            "host",
            "deallocate",
            |_store: wasmtime::StoreContextMut<HostState>, _ptr: i32, _size: i32| {},
        )?;

        // Get agent ID
        linker.func_wrap(
            "host",
            "get_agent_id",
            |store: wasmtime::StoreContextMut<HostState>| -> i32 {
                store
                    .data()
                    .agent_id
                    .map(|id| id.as_u128() as i32)
                    .unwrap_or(0)
            },
        )?;

        info!("Host functions linked successfully");
        Ok(())
    }

    /// Load a Wasm module from file
    pub fn load_module(&mut self, path: &Path, module_name: &str) -> Result<Uuid> {
        info!("Loading Wasm module: {} from {:?}", module_name, path);

        let module =
            Module::from_file(&self.engine, path).with_context(|| format!("Failed to load module from {:?}", path))?;

        // Extract interface from module (in real implementation, would parse wasm metadata)
        let interface = WasmInterface {
            module_name: module_name.to_string(),
            version: "0.1.0".to_string(),
            exports: vec![ExportFunc {
                name: "process".to_string(),
                description: "Main agent processing function".to_string(),
                params: vec![ParamType::I32, ParamType::I32],
                return_type: Some(ParamType::I32),
            }],
            imports: vec![],
        };

        let id = Uuid::new_v4();
        let agent_module = AgentModule {
            id,
            module_name: module_name.to_string(),
            version: "0.1.0".to_string(),
            path: path.to_string_lossy().to_string(),
            interface,
            _module: module,
        };

        self.modules.insert(id, agent_module);
        info!("Module loaded successfully with ID: {}", id);

        Ok(id)
    }

    /// Instantiate a loaded module
    pub fn instantiate(&mut self, module_id: Uuid, agent_type: AgentType) -> Result<Uuid> {
        info!("Instantiating module: {} as {:?}", module_id, agent_type);

        let agent_module = self
            .modules
            .get(&module_id)
            .with_context(|| format!("Module {} not found", module_id))?;

        let mut store = Store::new(&self.engine, HostState::new());
        store.data_mut().agent_type = Some(agent_type);

        // Get the module from our stored reference
        let module = &agent_module._module;

        let instance = self
            .linker
            .instantiate(&mut store, module)
            .with_context(|| "Failed to instantiate module")?;

        // Call the init function if it exists
        if let Some(init_func) = instance.get_func(&store, "init") {
            if let Err(e) = init_func.call(&mut store, &[]) {
                warn!("Init function returned error (non-fatal): {:?}", e);
            }
        }

        let instance_id = Uuid::new_v4();
        let agent_instance = AgentInstance {
            id: instance_id,
            module_id,
            agent_type,
            instance,
            store,
            loaded_at: chrono::Utc::now(),
        };

        self.instances.insert(instance_id, agent_instance);
        info!("Module instantiated successfully with instance ID: {}", instance_id);

        Ok(instance_id)
    }

    /// Invoke a function on an agent instance
    pub fn invoke(
        &mut self,
        instance_id: Uuid,
        func_name: &str,
        args: &[i32],
    ) -> Result<i32> {
        let instance = self
            .instances
            .get_mut(&instance_id)
            .with_context(|| format!("Instance {} not found", instance_id))?;

        let wasm_args: Vec<wasmtime::Val> = args.iter().map(|&v| wasmtime::Val::I32(v)).collect();
        let result = instance.invoke(func_name, &wasm_args)?;

        Ok(result.i32().unwrap_or(0))
    }

    /// Unload an agent instance
    pub fn unload_instance(&mut self, instance_id: Uuid) -> Result<()> {
        info!("Unloading instance: {}", instance_id);
        self.instances
            .remove(&instance_id)
            .with_context(|| format!("Instance {} not found", instance_id))?;
        Ok(())
    }

    /// Hot-swap: unload old instance and load new one
    pub fn hot_swap(&mut self, module_id: Uuid, old_instance_id: Uuid) -> Result<Uuid> {
        info!("Hot-swapping instance {} with module {}", old_instance_id, module_id);
        
        // Get agent type from old instance
        let agent_type = self
            .instances
            .get(&old_instance_id)
            .map(|i| i.agent_type)
            .unwrap_or(AgentType::Sentry);

        // Unload old instance
        self.unload_instance(old_instance_id)?;

        // Load new instance
        self.instantiate(module_id, agent_type)
    }

    /// Get IPC channel
    pub fn ipc(&self) -> &IpcChannel {
        &self.ipc_channel
    }

    /// List all loaded modules
    pub fn list_modules(&self) -> Vec<(Uuid, String, String)> {
        self.modules
            .iter()
            .map(|(id, m)| (id, m.module_name.clone(), m.version.clone()))
            .collect()
    }

    /// List all active instances
    pub fn list_instances(&self) -> Vec<(Uuid, AgentType)> {
        self.instances
            .iter()
            .map(|(id, i)| (*id, i.agent_type))
            .collect()
    }
}

impl Default for HostRuntime {
    fn default() -> Self {
        Self::new().expect("Failed to create default HostRuntime")
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_host_runtime_creation() {
        let runtime = HostRuntime::new();
        assert!(runtime.is_ok());
    }

    #[test]
    fn test_interface_definition() {
        let interface = WasmInterface {
            module_name: "test".to_string(),
            version: "1.0.0".to_string(),
            exports: vec![],
            imports: vec![],
        };
        assert_eq!(interface.module_name, "test");
    }

    #[test]
    fn test_agent_type() {
        assert_eq!(AgentType::Sentry.as_str(), "sentry");
        assert_eq!(AgentType::Librarian.as_str(), "librarian");
        assert_eq!(AgentType::Action.as_str(), "action");
    }

    #[test]
    fn test_ipc_channel() {
        let channel = IpcChannel::new();
        let msg = IpcMessage::new("julia", "rust", b"test payload".to_vec());
        channel.send(msg);
        assert!(channel.receive().is_some());
    }
}
