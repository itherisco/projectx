# ProjectX Jarvis/ITHERIS Full OS Interface Architecture

## Overview

The **ProjectX Jarvis Full OS Interface** is a comprehensive multi-platform management console architecture for the ITHERIS sovereign AI system. It provides secure, fail-closed access to the adaptive kernel through gRPC contracts, supporting terminal (TUI), desktop (Tauri), and web (WASM) interfaces.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLIENT INTERFACES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────────┐ │
│  │    TUI (Terminal)    │  │   Console (Tauri)   │  │  Console-WWW (WASM)│ │
│  │                      │  │                      │  │                     │ │
│  │  - ratatui           │  │  - Leptos + Tauri    │  │  - Leptos WASM      │ │
│  │  - gRPC via tonic    │  │  - Native desktop    │  │  - Browser-based    │ │
│  │  - Direct terminal   │  │  - System tray       │  │  - grpc-web proxy   │ │
│  └──────────┬───────────┘  └──────────┬───────────┘  └──────────┬────────┘ │
│             │                           │                           │          │
│             └───────────────────────────┼───────────────────────────┘          │
│                                         │                                      │
│                    ┌────────────────────┴────────────────────┐                  │
│                    │         gRPC Protocol Bridge            │                  │
│                    │  (tonic / grpc-web / direct connection) │                  │
│                    └────────────────────┬────────────────────┘                  │
│                                         │                                      │
└─────────────────────────────────────────┼──────────────────────────────────────┘
                                          │
┌─────────────────────────────────────────┼──────────────────────────────────────┐
│                           BACKEND SERVICES                                   │
├─────────────────────────────────────────┼──────────────────────────────────────┤
│                                         │                                      │
│  ┌──────────────────────────────────────┴───────────────────────────────────┐  │
│  │                    ITHERIS-DAEMON (Warden)                              │  │
│  │                                                                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ gRPC Server │  │ Security     │  │ Task        │  │ Julia Brain │  │  │
│  │  │ (tonic)     │  │ (JWT/Flow)   │  │ Orchestrator│  │ Integration │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                                                                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ Safe Shell  │  │ Safe HTTP    │  │ Secrets     │  │ FFI Layer   │  │  │
│  │  │              │  │ Request      │  │ Management  │  │ (jlrs)      │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  │                                                                          │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
│                                         │                                      │
└─────────────────────────────────────────┼──────────────────────────────────────┘
                                          │
                        ┌─────────────────┴─────────────────┐
                        │    ADAPTIVE KERNEL (Julia)          │
                        │                                      │
                        │  ┌─────────────────────────────┐    │
                        │  │ Cognitive Loop              │    │
                        │  │ - ReAct Agent               │    │
                        │  │ - Code Agent                │    │
                        │  │ - Strategist                │    │
                        │  │ - Auditor                   │    │
                        │  └─────────────────────────────┘    │
                        │                                      │
                        │  ┌─────────────────────────────┐    │
                        │  │ Decision Spine              │    │
                        │  │ - Proposal aggregation      │    │
                        │  │ - Conflict resolution       │    │
                        │  │ - Commitment tracking       │    │
                        │  └─────────────────────────────┘    │
                        │                                      │
                        │  ┌─────────────────────────────┐    │
                        │  │ Security Layer              │    │
                        │  │ - Input sanitization        │    │
                        │  │ - Flow integrity            │    │
                        │  │ - Risk classification       │    │
                        │  └─────────────────────────────┘    │
                        │                                      │
                        └──────────────────────────────────────┘
```

## Component Overview

### 1. Proto Definitions (`/proto/`)

The **gRPC service contracts** are defined in [`proto/warden.proto`](proto/warden.proto). This file defines:

- **Enums**: `ProposalStatus`, `RiskLevel`, `CognitiveMode`, `DecisionEventType`, `DecisionStatus`, `AgentType`, `ContainmentStatus`
- **Messages**: `TelemetryRequest`, `TelemetryResponse`, `ProposalRequest`, `ProposalResponse`, `ConfirmationRequest`, `ConfirmationResponse`, `DecisionRequest`, `DecisionEvent`, `ContainmentRequest`, `ContainmentResponse`
- **Service**: `WardenService` with 5 RPC methods

### 2. ITHERIS Daemon (`/itheris-daemon/`)

The **Warden gRPC server** is the central backend service:

- **gRPC Server**: Uses `tonic` for high-performance async gRPC
- **Security Layer**: JWT authentication, flow integrity checks, risk classification
- **Task Orchestrator**: Manages agent execution and proposal handling
- **Julia Integration**: Uses `jlrs` for embedded Julia runtime
- **Safe Capabilities**: Sandboxed shell and HTTP request handling
- **Secrets Management**: AES-GCM encryption, Argon2 key derivation

Key files:
- [`itheris-daemon/src/main.rs`](itheris-daemon/src/main.rs) - Entry point
- [`itheris-daemon/src/task_orchestrator.rs`](itheris-daemon/src/task_orchestrator.rs) - Task management
- [`itheris-daemon/src/jwt_auth.rs`](itheris-daemon/src/jwt_auth.rs) - Authentication
- [`itheris-daemon/src/flow_integrity.rs`](itheris-daemon/src/flow_integrity.rs) - Flow validation
- [`itheris-daemon/src/risk_classifier.rs`](itheris-daemon/src/risk_classifier.rs) - Risk assessment

### 3. Terminal TUI (`/tui/`)

The **terminal user interface** provides command-line access:

- **Framework**: `ratatui` for rich terminal UI
- **Protocol**: Direct gRPC connection via `tonic`
- **Display**: Real-time telemetry, decision streaming, containment status

### 4. Desktop Console (`/console/`)

The **Tauri desktop application**:

- **Framework**: Leptos + Tauri (Rust backend)
- **UI**: Bento grid layout with glassmorphism styling
- **Features**: System tray, native notifications, decision dashboard
- **Communication**: gRPC (native) or gRPC-Web (browser mode)

### 5. Web Console (`/console-www/`)

The **WASM web console**:

- **Framework**: Leptos compiled to WebAssembly
- **Protocol**: gRPC-Web via nginx proxy
- **Browser**: Runs in any modern browser without installation

## gRPC Service Contract

The core of the architecture is the [`WardenService`](proto/warden.proto:358) defined in `proto/warden.proto`:

### RPC Methods

| Method | Type | Description |
|--------|------|-------------|
| `StreamTelemetry` | Bidirectional streaming | Real-time system metrics |
| `SubmitProposal` | Unary | Submit brain proposal for kernel approval |
| `RequestConfirmation` | Unary | Request sovereign confirmation for high-risk actions |
| `StreamDecisions` | Server streaming | Subscribe to decision events |
| `TriggerContainment` | Unary | Emergency lockdown |

### Telemetry Data

The system streams:
- Metabolic energy level (0-100%)
- CPU/Memory usage
- Tick rate (ticks/second)
- Cognitive mode (Active/Idle/Sleep/Dream/Emergency)
- Agent confidences
- IPC latency
- Decision throughput
- Pending proposal queue depth

## Build and Run Instructions

### Prerequisites

- **Rust**: 1.70+ (for tonic, ratatui, Tauri)
- **Julia**: 1.9+ (for adaptive kernel)
- **Protocol Buffers**: `protoc` compiler
- **Node.js**: 18+ (for WASM builds)

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ITHERIS_JULIA_PATH` | Path to Julia binary | `julia` |
| `ITHERIS_GRPC_PORT` | gRPC server port | `50051` |
| `ITHERIS_JWT_SECRET` | JWT signing secret | (generated) |
| `ITHERIS_LOG_LEVEL` | Logging verbosity | `info` |

### Building the ITHERIS Daemon

```bash
cd itheris-daemon

# Build with gRPC support
cargo build --release

# Or with Julia integration (requires jlrs)
cargo build --release --features julia
```

### Building the TUI

```bash
cd tui

# Build the terminal interface
cargo build --release
```

### Building the Desktop Console

```bash
cd console

# Build Tauri app
cargo build --release --features tauri

# Generate Tauri bundle
cargo tauri build
```

### Building the Web Console

```bash
cd console-www

# Build WASM
wasm-pack build --target web

# Or use the build script
./build.sh
```

### Running the Full System

```bash
# Start the ITHERIS daemon (Warden gRPC server)
cd itheris-daemon
cargo run --release

# In another terminal, start the TUI
cd tui
cargo run --release

# Or start the desktop console
cd console
cargo tauri dev

# Or serve the web console
cd console-www
./build.sh
# Then serve via nginx or similar
```

## Configuration Options

### ITHERIS Daemon Configuration

The daemon reads from `config.toml` in the project root:

```toml
[daemon]
grpc_host = "127.0.0.1"
grpc_port = 50051

[jwt]
secret = "your-secret-key"
expiration_hours = 24

[security]
require_confirmation_for_high_risk = true
max_proposal_size = 1048576

[julia]
path = "julia"
init_script = "init.jl"
```

### TUI Configuration

```toml
[tui]
refresh_rate_ms = 1000
show_agent_details = true
log_path = "/var/log/itheris/tui.log"
```

### Console Configuration

```toml
[console]
theme = "circadian"
enable_animations = true
default_view = "telemetry"
```

## Security Model

### Fail-Closed Architecture

The system operates under a **fail-closed** security model:
- Unknown actions are **denied by default**
- High-risk operations require **sovereign confirmation**
- Containment can be triggered at any time to halt all operations

### Authentication

- **JWT-based** authentication for all gRPC calls
- Token expiration and refresh mechanisms
- Role-based access control (optional)

### Flow Integrity

- Each request is validated against flow integrity rules
- TPM-based verification for critical operations (when available)
- Cryptographic attestation of system state

## Decision Flow

```
┌─────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Agent  │────▶│   Warden     │────▶│   Kernel    │────▶│ Confirmation│
│Proposal │     │  (gRPC)      │     │ (Julia)     │     │   (Human)    │
└─────────┘     └──────────────┘     └─────────────┘     └──────────────┘
                                                                 │
                              ┌─────────────────────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │   Execution      │
                     │   (if approved)  │
                     └─────────────────┘
```

## Troubleshooting

### Common Issues

1. **gRPC connection refused**
   - Ensure ITHERIS daemon is running on the correct port
   - Check firewall rules

2. **Julia integration fails**
   - Verify Julia path in configuration
   - Check jlrs compatibility

3. **WASM build errors**
   - Ensure wasm-pack is installed
   - Check Rust target: `rustup target add wasm32-unknown-unknown`

4. **Tauri build fails**
   - Ensure system dependencies for Tauri are installed
   - Check WebView2 (Windows) or WebKitGTK (Linux)

## API Reference

For detailed API documentation, see [`API_REFERENCE.md`](API_REFERENCE.md).

## Architecture Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) - Detailed system architecture
- [`ARCHITECTURE_RUST_WARDEN.md`](ARCHITECTURE_RUST_WARDEN.md) - Rust Warden implementation
- [`COGNITIVE_LOOP.md`](COGNITIVE_LOOP.md) - Cognitive processing loop
- [`SYSTEM_ARCHITECTURE.md`](SYSTEM_ARCHITECTURE.md) - High-level system design
