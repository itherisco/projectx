# ITHERIS Daemon

Sovereign runtime daemon that manages the Julia brain subprocess with fail-closed security.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ITHERIS Daemon v1.0                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ Secure Boot  │───▶│ Fail-Closed  │───▶│  Health API  │ │
│  │   Manager    │    │    Kernel    │    │   (Axum)     │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                   │                               │
│         ▼                   ▼                               │
│  ┌──────────────┐    ┌──────────────┐                     │
│  │ TPM Simula-  │    │   Watchdog   │                     │
│  │    tion      │    │   Monitor    │                     │
│  └──────────────┘    └──────────────┘                     │
│                             │                               │
│                             ▼                               │
│                      ┌──────────────┐                      │
│                      │ Julia Brain  │                      │
│                      │  Subprocess  │                      │
│                      └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Build

```bash
cd itheris-daemon
cargo build --release
```

### Run

```bash
# Using the shell script
./run_itheris.sh

# Or directly
./itheris-daemon/target/release/itheris-daemon
```

### Systemd Service

```bash
# Copy service file
sudo cp itheris-daemon.service /etc/systemd/system/

# Enable and start
sudo systemctl enable itheris-daemon
sudo systemctl start itheris-daemon
```

## HTTP API Endpoints

The daemon exposes a REST API on port 8080:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Get daemon health status |
| `/stats` | GET | Get kernel statistics |
| `/approve` | POST | Approve an action through the kernel |
| `/log` | GET | Get decision log |

### Health Response

```json
{
  "status": "healthy",
  "state": "Running",
  "uptime_secs": 3600,
  "brain_pid": 12345,
  "brain_healthy": true,
  "kernel_stats": {
    "approved": 100,
    "blocked": 5,
    "warden_healthy": true,
    "capabilities_count": 3
  },
  "boot_stages": [...]
}
```

### Approve Action

```json
POST /approve
{
  "id": "action-123",
  "action_type": "Execute",
  "target": "some_command",
  "requested_by": "julia_brain",
  "risk_level": 1,
  "timestamp": "2026-03-07T12:00:00Z"
}
```

## Secure Boot Sequence

The daemon performs a 4-stage secure boot:

1. **Stage 1**: Boot verification (SHA256 measurement)
2. **Stage 2**: Kernel integrity check
3. **Stage 3**: Julia brain verification
4. **Stage 4**: Capability registry validation

## Fail-Closed Security Model

If the Rust Warden fails:
- ALL outputs are blocked
- Default-deny security model
- All actions require capability grants
- High-risk actions require cryptographic evidence

## Configuration

Default configuration in `main.rs`:

```rust
DaemonConfig {
    julia_path: "julia",
    adaptive_kernel_path: "./adaptive-kernel",
    health_check_interval_secs: 30,
    watchdog_timeout_secs: 120,
    http_port: 8080,
    log_level: "info",
}
```
