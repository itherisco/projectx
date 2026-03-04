# JARVIS Runtime - Integration Guide

## Overview

This document describes how to integrate the Rust JARVIS Runtime with the Julia Adaptive Kernel.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         JARVIS Runtime (Rust)                    │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐│
│  │  REST API   │  │  WebSocket  │  │  Prometheus Metrics    ││
│  │  (Axum)     │  │  (Streaming)│  │  /metrics               ││
│  └─────────────┘  └─────────────┘  └─────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────┐│
│  │  Capability  │ │   Event      │ │   Knowledge Graph       ││
│  │  Manager     │ │   Bus        │ │   (Petgraph)            ││
│  └──────────────┘ └──────────────┘ └────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────┐│
│  │  Session     │ │   Auth       │ │   Proactive Engine     ││
│  │  Manager     │ │  (JWT)       │ │                         ││
│  └──────────────┘ └──────────────┘ └────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                    IPC (Unix Socket / TCP)
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Julia Adaptive Kernel                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────────────┐│
│  │  Kernel      │ │  Cognition   │ │   Capabilities         ││
│  │  (approve)   │ │  (Attention) │ │   (Tools)              ││
│  └──────────────┘ └──────────────┘ └────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Julia Integration

### Option 1: Unix Socket IPC

```julia
# Julia side - RustIPC.jl
using Sockets

function call_kernel(request::Dict)
    sock = UnixSocket("/var/run/jarvis/kernel.sock")
    write(sock, JSON.json(request))
    response = read(sock, String)
    return JSON.parse(response)
end
```

### Option 2: HTTP IPC

```julia
# Julia side
using HTTP

function call_kernel(request::Dict)
    response = HTTP.post(
        "http://localhost:8080/kernel",
        ["Content-Type" => "application/json"],
        JSON.json(request)
    )
    return JSON.parse(response.body)
end
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/chat` | POST | Send message |
| `/memory` | GET | Query memory |
| `/suggestions` | GET | Get proactive suggestions |
| `/capabilities` | GET | List capabilities |
| `/metrics` | GET | Prometheus metrics |

## Kernel Sovereignty

All tool execution requires Kernel approval:

```rust
// Rust - capability execution
let approval = ApprovalToken::new(user_id, capabilities, 60);
manager.execute("tool_name", input, &approval).await?;
```

The Kernel retains sole authority over:
- Tool approval
- Execution authorization
- Safety validation

## Running

### Development
```bash
cd jarvis_runtime
cargo run -- --dev --listen 127.0.0.1:8080
```

### Production (systemd)
```bash
sudo cp systemd/jarvisd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable jarvisd
sudo systemctl start jarvisd
```

### Docker
```bash
docker build -t jarvis-runtime .
docker run -d -p 8080:8080 jarvis-runtime
```

## Configuration

Create `config.toml`:

```toml
[Runtime]
mode = "daemon"
listen = "0.0.0.0:8080"
log_level = "info"

[Security]
jwt_secret = "your-secret-key"
session_timeout = 3600

[Kernel]
socket_path = "/var/run/jarvis/kernel.sock"
```
