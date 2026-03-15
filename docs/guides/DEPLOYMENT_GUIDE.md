# ITHERIS Deployment Guide

> **Version:** 1.0.0  
> **Last Updated:** 2026-03-07  
> **System Status:** Experimental Prototype

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Build Instructions](#2-build-instructions)
3. [Configuration](#3-configuration)
4. [Running the System](#4-running-the-system)
5. [Systemd Deployment](#5-systemd-deployment)
6. [Health Monitoring](#6-health-monitoring)
7. [Troubleshooting](#7-troubleshooting)
8. [Recovery Procedures](#8-recovery-procedures)

---

## 1. Prerequisites

### 1.1 System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Ubuntu 20.04+ / Debian 11+ | Ubuntu 22.04 LTS |
| **CPU** | 2 cores | 4+ cores |
| **RAM** | 4 GB | 8+ GB |
| **Disk** | 2 GB free | 10+ GB free |

### 1.2 Required Software

#### Julia 1.9+

```bash
# Option 1: Install from Julia official binaries
cd /tmp
wget https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz
sudo tar -xzf julia-1.10.0-linux-x86_64.tar.gz -C /opt
sudo ln -s /opt/julia-1.10.0/bin/julia /usr/local/bin/julia

# Verify installation
julia --version
# Output: julia version 1.10.0
```

#### Rust 1.70+

```bash
# Option 1: Install via rustup (recommended)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Verify installation
rustc --version
# Output: rustc 1.70.0 (or higher)
cargo --version
# Output: cargo 1.70.0 (or higher)
```

#### System Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    libgit2-dev \
    libjulia-dev \
    julia \
    libncurses-dev \
    libatomic1
```

**Fedora/RHEL:**
```bash
sudo dnf install -y \
    gcc \
    gcc-c++ \
    cmake \
    pkg-config \
    openssl-devel \
    libgit2-devel \
    julia \
    ncurses-devel
```

### 1.3 Optional Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| **OpenSSL** | Cryptographic operations | Yes |
| **libgit2** | Git integration | No |
| **AWS SDK** | AWS KMS for key management | No (if using AWS KMS) |
| **Azure SDK** | Azure Key Vault | No (if using Azure) |
| **GCP SDK** | Google Cloud KMS | No (if using GCP) |

---

## 2. Build Instructions

### 2.1 Clone and Setup

```bash
# Clone the repository
git clone https://github.com/itheris/itheris.git
cd /home/user/projectx

# Verify directory structure
ls -la
# Should show: adaptive-kernel/, itheris-daemon/, interfaces/, config.toml
```

### 2.2 Building the Rust Daemon

```bash
# Navigate to daemon directory
cd itheris-daemon

# Build in debug mode (faster builds, slower execution)
cargo build

# Build in release mode (slower builds, optimal performance)
cargo build --release

# Verify build
ls -la target/release/itheris-daemon
```

**Build Options:**
```bash
# Build with specific features
cargo build --release --features "logging,telemetry"

# Build with custom target directory
cargo build --release --target-dir /custom/path
```

### 2.3 Building the Julia Kernel

```bash
# Navigate to adaptive-kernel
cd /home/user/projectx/adaptive-kernel

# Activate the Julia project
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Pre-compile the kernel (optional, speeds up first run)
julia --project=. -e 'using Itheris; println("Kernel compiled successfully")'
```

**Build Verification:**
```bash
# Run unit tests
julia --project=. -e 'include("tests/unit_kernel_test.jl")'

# Run integration tests
julia --project=. -e 'include("tests/test_integration.jl")'
```

### 2.4 Environment Setup

Create a `.env` file in the project root:

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your API keys
nano .env
```

Example `.env`:
```bash
# Required for LLM integration
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Optional: STT/TTS
ELEVENLABS_API_KEY=...

# Optional: AWS credentials (for KMS)
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
```

---

## 3. Configuration

### 3.1 Configuration File (config.toml)

The main configuration file is located at [`config.toml`](config.toml):

```toml
# ============================================================================
# COMMUNICATION CONFIG (Ears/Mouth)
# ============================================================================

[communication]
# Speech-to-Text (STT) Provider
stt_provider = "openai"  # Options: openai (whisper), coqui
stt_api_key = ""        # Your OpenAI API key for Whisper

# Text-to-Speech (TTS) Provider  
tts_provider = "elevenlabs"  # Options: elevenlabs, openai
tts_api_key = ""            # Your ElevenLabs API key
tts_voice_id = "21m00Tcm4TlvDq8ikWAM"  # Default voice ID

# Vision Language Model (VLM) - optional
vlm_provider = "openai"  # Options: openai (gpt4-v), anthropic (claude-v)
vlm_api_key = ""        # Your API key

# Safety threshold for auto-confirmation
require_confirmation_threshold = "TRUST_STANDARD"  # TRUST_RESTRICTED, TRUST_LIMITED, TRUST_STANDARD, TRUST_FULL

# ============================================================================
# SECURITY CONFIG (CRITICAL)
# ============================================================================

[security]
# Fail-closed security model - block by default
fail_closed = true

# Require kernel approval for all actions
require_kernel_approval = true

# Minimum score threshold (0-100)
score_threshold = 70

# Enable all security features
warden_enabled = true
sovereignty_gate_enabled = true
capability_registry_enabled = true

# Kernel approval bypass is DISABLED - cannot be overridden
kernel_approval_bypass = false
kernel_approval_bypass_override = false

# Input sanitization
input_sanitizer_strict = true
prompt_injection_block = true

# ============================================================================
# LOGGING CONFIG
# ============================================================================

[logging]
level = "info"  # trace, debug, info, warn, error
format = "json"  # json, text
output = "stdout"  # stdout, file, syslog
file_path = "/var/log/itheris-daemon.log"

# ============================================================================
# IPC CONFIG
# ============================================================================

[ipc]
# Communication method: shared_memory or tcp
method = "tcp"

# TCP settings
host = "127.0.0.1"
port = 9000

# Shared memory settings (if using shared_memory)
shm_key = 0x1_0000_0000
shm_size = 67108864  # 64MB

# Connection settings
connection_timeout = 5.0
reconnect_attempts = 3
reconnect_delay = 1.0

# ============================================================================
# MEMORY CONFIG
# ============================================================================

[memory]
# Maximum episodic memory entries
max_episodic_memory = 1000

# Memory consolidation interval (seconds)
consolidation_interval = 3600

# ============================================================================
# TELEMETRY CONFIG
# ============================================================================

[telemetry]
enabled = true
metrics_port = 9090
```

### 3.2 Security Settings

#### Trust Levels

The system implements five trust levels:

| Level | Score Range | Capabilities |
|-------|-------------|--------------|
| **BLOCKED** | 0-19 | No operations permitted |
| **RESTRICTED** | 20-39 | Read-only operations |
| **LIMITED** | 40-59 | Basic tools only |
| **STANDARD** | 60-79 | Most tools allowed |
| **FULL** | 80-100 | All operations permitted |

#### Capability Registry

Edit [`adaptive-kernel/registry/capability_registry.json`](adaptive-kernel/registry/capability_registry.json) to modify tool capabilities:

```json
{
  "capabilities": [
    {
      "id": "observe_cpu",
      "name": "CPU Observer",
      "description": "Read system CPU metrics",
      "cost": 1,
      "risk_level": "low",
      "reversibility": "full",
      "requires_approval": false
    },
    {
      "id": "safe_shell",
      "name": "Safe Shell Execution",
      "description": "Execute commands in sandbox",
      "cost": 10,
      "risk_level": "medium",
      "reversibility": "partial",
      "requires_approval": true
    },
    {
      "id": "write_file",
      "name": "File Writer",
      "description": "Write content to files",
      "cost": 5,
      "risk_level": "high",
      "reversibility": "difficult",
      "requires_approval": true
    }
  ]
}
```

### 3.3 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RUST_LOG` | Rust daemon logging level | `info` |
| `JULIA_PROJECT` | Julia project path | `./adaptive-kernel` |
| `ITHERIS_CONFIG` | Config file path | `./config.toml` |
| `ITHERIS_DATA_DIR` | Data directory | `/var/lib/itheris` |
| `ITHERIS_LOG_DIR` | Log directory | `/var/log/itheris` |

---

## 4. Running the System

### 4.1 Quick Start (Development Mode)

```bash
# From project root
cd /home/user/projectx

# Run the startup script
./run_itheris.sh

# Expected output:
# ===========================================
#   ITHERIS Sovereign Runtime Launcher
# ===========================================
# Found: julia version 1.10.0
# Building ITHERIS daemon...
# Build successful!
# Starting ITHERIS daemon...
# [2026-03-07T10:00:00] INFO: ITHERIS daemon started
# [2026-03-07T10:00:00] INFO: Julia kernel connected
# [2026-03-07T10:00:00] INFO: System ready
```

### 4.2 Manual Startup

#### Step 1: Start the Rust Daemon

```bash
# Terminal 1: Start the Rust daemon
cd /home/user/projectx
RUST_LOG=debug ./itheris-daemon/target/release/itheris-daemon --config config.toml
```

#### Step 2: Start the Julia Kernel

```bash
# Terminal 2: Start the Julia cognitive brain
cd /home/user/projectx/adaptive-kernel
julia --project=. -e 'using Itheris; Itheris.start()'
```

### 4.3 Testing the Installation

```bash
# Run the integration test
cd /home/user/projectx
julia --project=adaptive-kernel -e 'include("adaptive-kernel/tests/test_integration.jl")'

# Run a simple health check
julia --project=adaptive-kernel -e '
using Itheris
println("Testing IPC connection...")
connected = Itheris.IPC.is_brain_connected()
println("Brain connected: ", connected)
'
```

---

## 5. Systemd Deployment

### 5.1 Install as System Service

```bash
# Copy the service file
sudo cp itheris-daemon.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable the service (start on boot)
sudo systemctl enable itheris-daemon

# Create required directories
sudo mkdir -p /var/log/itheris-daemon
sudo mkdir -p /var/lib/itheris
sudo chown -R itheris:itheris /var/log/itheris-daemon
sudo chown -R itheris:itheris /var/lib/itheris
```

### 5.2 Service Management

```bash
# Start the service
sudo systemctl start itheris-daemon

# Check status
sudo systemctl status itheris-daemon

# View logs
sudo journalctl -u itheris-daemon -f

# Stop the service
sudo systemctl stop itheris-daemon

# Restart the service
sudo systemctl restart itheris-daemon
```

### 5.3 Service File Reference

The service file ([`itheris-daemon.service`](itheris-daemon.service)) includes:

```ini
[Unit]
Description=ITHERIS Sovereign Runtime Daemon
Documentation=https://github.com/itheris/itheris
After=network.target

[Service]
Type=simple
User=itheris
Group=itheris
WorkingDirectory=/home/user/projectx

# Environment
Environment=RUST_LOG=info

# Executable paths
ExecStart=/home/user/projectx/itheris-daemon/target/release/itheris-daemon

# Restart policy
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/itheris-daemon

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=itheris-daemon

[Install]
WantedBy=multi-user.target
```

---

## 6. Health Monitoring

### 6.1 Health Check Endpoints

```bash
# Check daemon health (if telemetry enabled)
curl http://localhost:9090/health

# Expected response:
# {
#   "status": "healthy",
#   "uptime_seconds": 3600,
#   "memory_used_mb": 256,
#   "cpu_percent": 12.5
# }
```

### 6.2 IPC Connection Status

```bash
# Check IPC connection from Julia side
julia --project=adaptive-kernel -e '
using IPC
channel = IPCChannel()
println("IPC State: ", channel.state)
println("Connected: ", IPC.is_brain_connected())
println("Last heartbeat: ", channel.last_heartbeat)
'
```

### 6.3 Log Monitoring

```bash
# Follow daemon logs
tail -f /var/log/itheris-daemon.log

# Filter by level
grep "ERROR" /var/log/itheris-daemon.log

# View recent errors
tail -n 100 /var/log/itheris-daemon.log | grep -A5 ERROR

# Systemd journal
sudo journalctl -u itheris-daemon --since "1 hour ago"
```

### 6.4 Metrics Collection

```bash
# View available metrics
curl http://localhost:9090/metrics

# Example metrics:
# - ipc_messages_sent_total
# - ipc_messages_received_total
# - kernel_approvals_total
# - kernel_denials_total
# - cognitive_cycles_total
# - trust_scores_average
```

---

## 7. Troubleshooting

### 7.1 Common Issues

#### Issue: Julia Not Found

```bash
# Error: julia: command not found
# Solution: Add Julia to PATH
export PATH="/opt/julia-1.10.0/bin:$PATH"
echo 'export PATH="/opt/julia-1.10.0/bin:$PATH"' >> ~/.bashrc
```

#### Issue: Rust Build Fails

```bash
# Error: could not find native static library `libjulia`
# Solution: Install Julia development headers
sudo apt-get install libjulia-dev

# Or rebuild with correct paths
cd itheris-daemon
cargo clean
JULIA_DIR=/opt/julia-1.10.0 cargo build --release
```

#### Issue: IPC Connection Refused

```bash
# Error: connect: connection refused
# Diagnosis: Check if daemon is running
ps aux | grep itheris-daemon

# Solution: Start the daemon first
./itheris-daemon/target/release/itheris-daemon --config config.toml &

# Check port availability
netstat -tlnp | grep 9000
```

#### Issue: Shared Memory Not Available

```bash
# Error: shmget: Operation not permitted
# Diagnosis: Check shared memory limits
df -h /dev/shm

# Solution: Increase shared memory
sudo shmctl -a -m 67108864  # 64MB
# Or add to /etc/fstab:
# tmpfs /dev/shm tmpfs defaults,size=1g 0 0
```

#### Issue: Permission Denied

```bash
# Error: Permission denied when creating /var/log/itheris-daemon
# Solution: Create directories with correct permissions
sudo mkdir -p /var/log/itheris-daemon
sudo mkdir -p /var/lib/itheris
sudo chown -R $USER:$USER /var/log/itheris-daemon
sudo chown -R $USER:$USER /var/lib/itheris
```

#### Issue: Kernel Approval Failures

```bash
# Symptom: All proposals denied
# Diagnosis: Check trust score and threshold
# View logs for denial reasons
grep "DENIED" /var/log/itheris-daemon.log

# Solution: Adjust score_threshold in config.toml
# Or modify proposal parameters to be lower risk
```

### 7.2 Debug Logging

#### Enable Debug Mode

```bash
# Rust daemon debug logging
RUST_LOG=debug ./itheris-daemon/target/release/itheris-daemon --config config.toml

# Julia side debug
julia --project=. -e 'ENV["JULIA_DEBUG"] = "Itheris"; using Itheris'
```

#### Trace IPC Messages

```julia
# In Julia REPL
using IPC
IPC.set_log_level(IPC.LOG_TRACE)

# This will print all IPC messages to stdout
```

### 7.3 Performance Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| High latency | Too many agents running | Reduce agent count in config |
| Memory exhaustion | Memory leak or large context | Restart daemon, check memory limits |
| CPU spikes | Infinite loop in brain | Check logs, restart brain |

```bash
# Profile memory usage
/usr/bin/time -v julia --project=. -e 'using Itheris'

# Profile CPU usage
top -p $(pgrep -f itheris-daemon)
```

---

## 8. Recovery Procedures

### 8.1 Graceful Shutdown

```bash
# Stop the systemd service
sudo systemctl stop itheris-daemon

# Or kill the processes gracefully
pkill -SIGTERM itheris-daemon
pkill -SIGTERM julia
```

### 8.2 Emergency Recovery

If the system becomes unresponsive:

```bash
# Force kill all related processes
pkill -9 -f itheris
pkill -9 julia

# Clear IPC shared memory (if using shared memory)
ipcrm -a

# Clear temporary files
rm -rf /tmp/itheris-*
rm -rf /var/lib/itheris/tmp/*

# Restart the system
./run_itheris.sh
```

### 8.3 Factory Reset

To reset the system to a clean state:

```bash
# Stop all services
sudo systemctl stop itheris-daemon
pkill -9 julia

# Clear all state
rm -rf /var/lib/itheris/*
rm -rf /var/log/itheris-daemon/*

# Recreate directories
sudo mkdir -p /var/log/itheris-daemon
sudo mkdir -p /var/lib/itheris
sudo chown -R itheris:itheris /var/log/itheris-daemon
sudo chown -R itheris:itheris /var/lib/itheris

# Rebuild from scratch
cd itheris-daemon && cargo build --release

# Restart services
sudo systemctl start itheris-daemon
```

### 8.4 Backup and Restore

#### Backup Configuration

```bash
# Backup critical files
tar -czf itheris-backup-$(date +%Y%m%d).tar.gz \
    config.toml \
    adaptive-kernel/registry/capability_registry.json \
    /var/lib/itheris/ \
    /var/log/itheris-daemon/
```

#### Restore from Backup

```bash
# Stop services
sudo systemctl stop itheris-daemon

# Extract backup
tar -xzf itheris-backup-20260307.tar.gz

# Restore permissions
sudo chown -R itheris:itheris /var/lib/itheris
sudo chown -R itheris:itheris /var/log/itheris-daemon

# Restart services
sudo systemctl start itheris-daemon
```

---

## Appendix A: Quick Reference Commands

```bash
# Development start
./run_itheris.sh

# Check status
systemctl status itheris-daemon

# View logs
journalctl -u itheris-daemon -f

# Restart
sudo systemctl restart itheris-daemon

# Test integration
julia --project=adaptive-kernel -e 'include("adaptive-kernel/tests/test_integration.jl")'
```

---

## Appendix B: File Locations

| File | Location |
|------|----------|
| Configuration | `/home/user/projectx/config.toml` |
| Capability Registry | `/home/user/projectx/adaptive-kernel/registry/capability_registry.json` |
| Daemon Binary | `/home/user/projectx/itheris-daemon/target/release/itheris-daemon` |
| Service File | `/etc/systemd/system/itheris-daemon.service` |
| Logs | `/var/log/itheris-daemon/` |
| Data | `/var/lib/itheris/` |

---

## Appendix C: Support and Resources

| Resource | URL |
|----------|-----|
| GitHub Repository | https://github.com/itheris/itheris |
| Documentation | See `ARCHITECTURE.md` |
| API Reference | See `API_REFERENCE.md` |
| Security Policy | See `SECURITY.md` |

---

*Document Version: 1.0.0*  
*Last Updated: 2026-03-07*  
*Classification: Deployment Guide*
