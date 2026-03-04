//! # ITHERIS Sovereign Intelligence Kernel v5.0
//! 
//! A complete, cryptographically-verified, sovereign intelligence system
//! with multi-agent cognition, external integrations, and immutable audit trails.
//!
//! This kernel can run in two modes:
//! - **User-space** (default): Standard application with ZMQ/Tokio IPC
//! - **Bare-metal** (feature "bare-metal"): Ring 0 microkernel with GDT/IDT/paging
//!
//! Author: badra222
//! Date: 2026-01-17

pub mod crypto;
pub mod kernel;
pub mod debate;
pub mod state;
pub mod federation;
pub mod llm_advisor;
pub mod catastrophe;
pub mod iot_bridge;
pub mod ledger;
pub mod threat_model;
pub mod api_bridge;
pub mod database;
pub mod pipeline;
pub mod monitoring;
pub mod panic_translation;

// Bare-metal modules (Ring 0)
#[cfg(feature = "bare-metal")]
pub mod boot;

#[cfg(feature = "bare-metal")]
pub mod memory;

#[cfg(feature = "bare-metal")]
pub mod ipc;

#[cfg(feature = "bare-metal")]
pub mod tpm;

#[cfg(feature = "bare-metal")]
pub mod container;

// Re-exports
pub use crypto::{CryptoAuthority, SignedThought};
pub use kernel::ItherisKernel;
pub use debate::{DebateEngine, Position, Challenge, DebateOutcome};
pub use state::GlobalState;
pub use federation::{Federation, Agent, Message};
pub use llm_advisor::{LLMAdvisor, Advice};
pub use catastrophe::{CatastropheModel, Scenario, CatastropheEvent};
pub use iot_bridge::{IoTBridge, Device, Command, CommandResult};
pub use ledger::{ImmutableLedger, LedgerBlock, LedgerEntry};
pub use threat_model::{ThreatModel, Threat, AttackSimulation};
pub use api_bridge::{APIBridge, ExternalAPI, APIRequest, APIResponse};
pub use database::{DatabaseManager, Database, DatabaseType, Query, QueryResult};
pub use pipeline::{PipelineManager, DataPipeline, PipelineStage, PipelineExecution};
pub use monitoring::{Monitor, Metric, Alert};
pub use panic_translation::{TranslatedPanic, FFIResult, JuliaExceptionCode, catch_panic, catch_panic_ptr, free_translated_panic, raise_julia_exception, install_panic_hook, panic_in_progress};

// Bare-metal re-exports
#[cfg(feature = "bare-metal")]
pub use boot;

#[cfg(feature = "bare-metal")]
pub use memory;

#[cfg(feature = "bare-metal")]
pub use ipc::{self, IPCEntry, IPCEntryType, IPCFlags, IPCError, IPCResult, SyncIpcRingBuffer, SharedSyncBuffer, ring_buffer::RING_BUFFER_CAPACITY, shm::{ShmRegion, ShmLock, ShmReadGuard, ShmWriteGuard, ShmSequence, ShmError, ShmResult}};

#[cfg(feature = "bare-metal")]
pub use tpm;

/// System version
pub const ITHERIS_VERSION: &str = "5.0.0";
/// System name
pub const ITHERIS_NAME: &str = "ITHERIS";
/// Authority
pub const AUTHORITY: &str = "badra222";
/// Whether running in bare-metal mode
#[cfg(feature = "bare-metal")]
pub const IS_BARE_METAL: bool = true;
#[cfg(not(feature = "bare-metal"))]
pub const IS_BARE_METAL: bool = false;