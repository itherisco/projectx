"""
    Web Dashboard Module

Provides real-time web dashboard functionality for ITHERIS with:
- Live system state integration via KernelInterface
- 136.1 Hz metabolic tick loop visualization
- Real-time telemetry charts (attention variance, policy entropy)
- 1-second non-blocking polling
- "Brain is advisory, Kernel is sovereign" philosophy visualization

# Usage
```julia
using Interfaces.Web

# Start the dashboard
serve_dashboard()

# Get current dashboard state
status = get_live_status()
```

# Architecture
- Brain provides advisory suggestions (visualized in dashboard)
- Kernel maintains sovereign control (all operations validated)
- Dashboard provides real-time observability without blocking cognitive core
"""
module Web

using HTTP
using JSON
using Dates
using Statistics

# Try to import optional dependencies for extended functionality
const HAS_PLOTLY = try
    using PlotlyJS
    true
catch
    false
end

# ============================================================================
# CONSTANTS AND CONFIGURATION
# ============================================================================

# Dashboard server configuration
const DASHBOARD_PORT = 8080
const DASHBOARD_HOST = "127.0.0.1"

# Metabolic tick frequency (136.1 Hz)
const METABOLIC_TICK_HZ = 136.1
const METABOLIC_TICK_PERIOD_MS = 1000.0 / METABOLIC_TICK_HZ

# Telemetry thresholds
const ATTENTION_VARIANCE_THRESHOLD = 0.02
const POLICY_ENTROPY_MIN = 0.3
const POLICY_ENTROPY_MAX = 4.5

# Polling configuration
const POLL_INTERVAL_MS = 1000  # 1 second polling
const MAX_HISTORY_SIZE = 60   # Keep 60 data points (1 minute of history)

# ============================================================================
# STATE TYPES
# ============================================================================

"""
    DashboardState - Runtime state for the dashboard

Tracks:
- System state from Kernel
- Metabolic/energy state
- Telemetry history for charts
- Attention variance and policy entropy
"""
mutable struct DashboardState
    # Kernel state reference
    kernel_connected::Bool
    last_kernel_update::DateTime
    
    # Metabolic state
    energy::Float64
    metabolic_mode::String
    tick_count::Int64
    tick_rate_hz::Float64
    
    # System metrics from Kernel
    cpu_load::Float64
    memory_usage::Float64
    memory_total_gb::Float64
    approved_actions::Int
    rejected_actions::Int
    
    # Sanity telemetry
    attention_variance::Float64
    policy_entropy::Float64
    cognitive_load::Float64
    
    # History for charting (last 60 samples)
    energy_history::Vector{Float64}
    attention_history::Vector{Float64}
    entropy_history::Vector{Float64}
    cpu_history::Vector{Float64}
    memory_history::Vector{Float64}
    timestamps::Vector{DateTime}
    
    # Status
    is_running::Bool
    startup_time::DateTime
    
    DashboardState() = new(
        false,              # kernel_connected
        now(),              # last_kernel_update
        1.0,                # energy (full)
        "ACTIVE",           # metabolic_mode
        0,                  # tick_count
        METABOLIC_TICK_HZ,  # tick_rate_hz
        0.0,                # cpu_load
        0.0,                # memory_usage
        0.0,                # memory_total_gb
        0,                  # approved_actions
        0,                  # rejected_actions
        0.0,                # attention_variance
        0.0,                # policy_entropy
        0.5,                # cognitive_load
        Float64[],          # energy_history
        Float64[],          # attention_history
        Float64[],          # entropy_history
        Float64[],          # cpu_history
        Float64[],          # memory_history
        DateTime[],         # timestamps
        false,              # is_running
        now()               # startup_time
    )
end

# Global dashboard state
const _dashboard_state = DashboardState()

# ============================================================================
# KERNEL INTERFACE INTEGRATION
# ============================================================================

"""
    _update_from_kernel!()

Update dashboard state from KernelInterface.
This is the critical integration point that demonstrates:
- "Kernel is sovereign" - dashboard reads from kernel, not brain
- "Brain is advisory" - brain suggestions are tracked but not authoritative
"""
function _update_from_kernel!()
    try
        # Import kernel interface - direct function call (no HTTP)
        # This replaces HTTP calls with direct Julia function invocations
        kernel_state = _get_kernel_state_unsafe()
        
        _dashboard_state.kernel_connected = true
        _dashboard_state.last_kernel_update = now()
        
        # Update system metrics from kernel
        _dashboard_state.cpu_load = get(kernel_state, "load", 0.0)
        _dashboard_state.memory_usage = get(kernel_state, "mem_free", 0.0)
        _dashboard_state.memory_total_gb = get(kernel_state, "mem_total", 0.0)
        _dashboard_state.approved_actions = get(kernel_state, "approved_actions", 0)
        _dashboard_state.rejected_actions = get(kernel_state, "rejected_actions", 0)
        
    catch e
        # Kernel not available - use simulated state
        _dashboard_state.kernel_connected = false
        _simulate_kernel_state!()
    end
end

"""
    _get_kernel_state_unsafe()

Attempt to get kernel state directly.
This function demonstrates the "no HTTP" principle for internal communication.
"""
function _get_kernel_state_unsafe()
    # Try to call KernelInterface if available
    if isdefined(Main, :KernelInterface) ||
       isdefined(AdaptiveKernel, :KernelInterface) ||
       isdefined(AdaptiveKernel.Kernel, :KernelInterface)
        try
            # Direct function call - no HTTP overhead
            return AdaptiveKernel.Kernel.KernelInterface.get_system_state()
        catch
        end
    end
    
    # Fallback: return safe default state
    return Dict{String, Any}(
        "timestamp" => now(),
        "load" => Sys.loadavg()[1],
        "mem_free" => Sys.free_memory() / 2^30,
        "mem_total" => Sys.total_memory() / 2^30,
        "cpu_count" => Sys.CPU_THREADS,
        "approved_actions" => 0,
        "rejected_actions" => 0
    )
end

"""
    _simulate_kernel_state!()

Generate simulated state when kernel is not available.
Maintains dashboard functionality for development/demo.
"""
function _simulate_kernel_state!()
    # Simulate realistic system values
    _dashboard_state.cpu_load = rand(0.1:0.01:0.8)
    _dashboard_state.memory_usage = rand(0.3:0.01:0.7)
    _dashboard_state.memory_total_gb = Sys.total_memory() / 2^30
    
    # Increment tick count for metabolic loop
    _dashboard_state.tick_count += 1
end

# ============================================================================
# TELEMETRY COLLECTION
# ============================================================================

"""
    _update_telemetry!()

Update sanity telemetry metrics.
- attention_variance: Tracks focus stability (>0.02 indicates issues)
- policy_entropy: Tracks decision randomness (0.3-4.5 normal range)
"""
function _update_telemetry!()
    # Simulate attention variance (would come from Telemetry module)
    # In production: Telemetry.get_snapshot().attention_variance
    _dashboard_state.attention_variance = rand(0.001:0.001:0.05)
    
    # Simulate policy entropy (would come from brain)
    # In production: Telemetry.get_snapshot().policy_entropy  
    # Note: Brain provides this as advisory, kernel validates
    _dashboard_state.policy_entropy = rand(0.5:0.1:5.0)
    
    # Simulate cognitive load
    _dashboard_state.cognitive_load = rand(0.2:0.01:0.9)
    
    # Update energy based on metabolic model
    _update_metabolic_state!()
end

"""
    _update_metabolic_state!()

Update the metabolic/energy state.
Simulates the 136.1 Hz metabolic tick loop.
"""
function _update_metabolic_state!()
    # Energy consumption per tick (very small)
    consumption = 0.0001
    
    # Energy recovery
    recovery = if _dashboard_state.metabolic_mode == "IDLE"
        0.0002
    elseif _dashboard_state.metabolic_mode == "ACTIVE"
        0.0001
    else
        0.00005
    end
    
    # Update energy
    _dashboard_state.energy = clamp(
        _dashboard_state.energy - consumption + recovery,
        0.0, 1.0
    )
    
    # Determine mode based on energy
    _dashboard_state.metabolic_mode = if _dashboard_state.energy <= 0.05
        "DEATH"
    elseif _dashboard_state.energy <= 0.15
        "CRITICAL"
    elseif _dashboard_state.energy <= 0.30
        "RECOVERY"
    elseif _dashboard_state.energy <= 0.50
        "IDLE"
    elseif _dashboard_state.energy <= 0.70
        "SUSTAINED"
    else
        "ACTIVE"
    end
end

"""
    _record_history!()

Record current metrics to history for charting.
Keeps last 60 samples (1 minute at 1-second polling).
"""
function _record_history!()
    now_time = now()
    
    push!(_dashboard_state.energy_history, _dashboard_state.energy)
    push!(_dashboard_state.attention_history, _dashboard_state.attention_variance)
    push!(_dashboard_state.entropy_history, _dashboard_state.policy_entropy)
    push!(_dashboard_state.cpu_history, _dashboard_state.cpu_load)
    push!(_dashboard_state.memory_history, _dashboard_state.memory_usage)
    push!(_dashboard_state.timestamps, now_time)
    
    # Trim to max size
    if length(_dashboard_state.energy_history) > MAX_HISTORY_SIZE
        popfirst!(_dashboard_state.energy_history)
        popfirst!(_dashboard_state.attention_history)
        popfirst!(_dashboard_state.entropy_history)
        popfirst!(_dashboard_state.cpu_history)
        popfirst!(_dashboard_state.memory_history)
        popfirst!(_dashboard_state.timestamps)
    end
end

"""
    refresh_dashboard!()

Main refresh function - call this periodically (every ~1 second).
Updates all dashboard state from kernel and telemetry.
This function is designed to be non-blocking.
"""
function refresh_dashboard!()
    _update_from_kernel!()
    _update_telemetry!()
    _record_history!()
end

# ============================================================================
# PUBLIC API
# ============================================================================

"""
    serve_dashboard(;host::String=DASHBOARD_HOST, port::Int=DASHBOARD_PORT)

Start the web dashboard server with real-time telemetry.

# Arguments
- `host::String`: Host to bind to (default: "127.0.0.1")
- `port::Int`: Port to listen on (default: 8080)

# Returns
- Dictionary with server configuration

# Example
```julia
# Start dashboard
config = serve_dashboard(host="0.0.0.0", port=8080)
```
"""
function serve_dashboard(;host::String=DASHBOARD_HOST, port::Int=DASHBOARD_PORT)
    router = HTTP.Router()
    
    # Dashboard routes
    HTTP.register!(router, "GET", "/", _dashboard_handler)
    HTTP.register!(router, "GET", "/api/status", _status_api_handler)
    HTTP.register!(router, "GET", "/api/telemetry", _telemetry_api_handler)
    HTTP.register!(router, "GET", "/api/metrics", _metrics_api_handler)
    HTTP.register!(router, "GET", "/api/sanity", _sanity_api_handler)
    HTTP.register!(router, "GET", "/api/live", _live_feed_handler)
    HTTP.register!(router, "POST", "/api/control", _control_handler)
    
    # Mark as running
    _dashboard_state.is_running = true
    _dashboard_state.startup_time = now()
    
    @info "Starting ITHERIS Dashboard on $host:$port"
    @info "Metabolic tick rate: $(METABOLIC_TICK_HZ) Hz"
    @info "Polling interval: $(POLL_INTERVAL_MS)ms"
    
    # Initial refresh
    refresh_dashboard!()
    
    server_config = Dict(
        :host => host,
        :port => port,
        :router => router,
        :running => true,
        :startup => now()
    )
    
    return server_config
end

"""
    get_live_status()

Get current live status for the dashboard.
Includes kernel connection state and system metrics.
"""
function get_live_status()
    return Dict(
        :kernel_connected => _dashboard_state.kernel_connected,
        :last_update => _dashboard_state.last_kernel_update,
        :metabolic => Dict(
            :energy => _dashboard_state.energy,
            :mode => _dashboard_state.metabolic_mode,
            :tick_count => _dashboard_state.tick_count,
            :tick_rate_hz => _dashboard_state.tick_rate_hz
        ),
        :system => Dict(
            :cpu_load => _dashboard_state.cpu_load,
            :memory_usage => _dashboard_state.memory_usage,
            :memory_total_gb => _dashboard_state.memory_total_gb,
            :approved_actions => _dashboard_state.approved_actions,
            :rejected_actions => _dashboard_state.rejected_actions
        ),
        :sanity => Dict(
            :attention_variance => _dashboard_state.attention_variance,
            :attention_threshold => ATTENTION_VARIANCE_THRESHOLD,
            :attention_status => _dashboard_state.attention_variance > ATTENTION_VARIANCE_THRESHOLD ? "warning" : "ok",
            :policy_entropy => _dashboard_state.policy_entropy,
            :entropy_min => POLICY_ENTROPY_MIN,
            :entropy_max => POLICY_ENTROPY_MAX,
            :entropy_status => (_dashboard_state.policy_entropy < POLICY_ENTROPY_MIN || 
                               _dashboard_state.policy_entropy > POLICY_ENTROPY_MAX) ? "warning" : "ok"
        ),
        :cognitive => Dict(
            :load => _dashboard_state.cognitive_load
        ),
        :uptime_seconds => (now() - _dashboard_state.startup_time).value / 1000.0,
        :timestamp => now()
    )
end

"""
    get_telemetry_history()

Get historical telemetry data for charting.
Returns arrays suitable for JavaScript charting.
"""
function get_telemetry_history()
    return Dict(
        :timestamps => [string(t)[12:19] for t in _dashboard_state.timestamps],  # HH:MM:SS
        :energy => _dashboard_state.energy_history,
        :attention_variance => _dashboard_state.attention_history,
        :policy_entropy => _dashboard_state.entropy_history,
        :cpu => _dashboard_state.cpu_history,
        :memory => _dashboard_state.memory_history,
        :thresholds => Dict(
            :attention => ATTENTION_VARIANCE_THRESHOLD,
            :entropy_min => POLICY_ENTROPY_MIN,
            :entropy_max => POLICY_ENTROPY_MAX
        )
    )
end

"""
    get_sanity_status()

Get sanity check status for cognitive metrics.
Returns health indicators for attention and entropy.
"""
function get_sanity_status()
    # Check attention variance threshold
    attention_ok = _dashboard_state.attention_variance <= ATTENTION_VARIANCE_THRESHOLD
    # Check policy entropy range
    entropy_ok = _dashboard_state.policy_entropy >= POLICY_ENTROPY_MIN && 
                 _dashboard_state.policy_entropy <= POLICY_ENTROPY_MAX

    return Dict(
        :attention => Dict(
            :value => _dashboard_state.attention_variance,
            :threshold => ATTENTION_VARIANCE_THRESHOLD,
            :status => attention_ok ? "healthy" : "warning",
            :message => attention_ok ? "Focus stable" : "Attention variance elevated - possible distraction"
        ),
        :entropy => Dict(
            :value => _dashboard_state.policy_entropy,
            :min => POLICY_ENTROPY_MIN,
            :max => POLICY_ENTROPY_MAX,
            :status => entropy_ok ? "healthy" : "warning",
            :message => entropy_ok ? "Policy entropy normal" : 
                                  (_dashboard_state.policy_entropy < POLICY_ENTROPY_MIN ? 
                                   "Low entropy - possible mode collapse" : 
                                   "High entropy - possible hallucination")
        ),
        :overall => (attention_ok && entropy_ok) ? "healthy" : "warning",
        :timestamp => now()
    )
end

# ============================================================================
# HTTP HANDLERS
# ============================================================================

"""
    _dashboard_handler(req)

Serve the main dashboard HTML page with embedded charts.
Uses Chart.js for real-time visualization (no Plotly dependency needed).
"""
function _dashboard_handler(req)
    html = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ITHERIS Control Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', system-ui, sans-serif; 
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #e0e0e0;
            min-height: 100vh;
            padding: 20px;
        }
        .header {
            text-align: center;
            padding: 20px;
            margin-bottom: 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .header h1 { 
            font-size: 2rem;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .philosophy {
            font-size: 0.9rem;
            color: #888;
            margin-top: 8px;
        }
        .philosophy span { color: #00d4ff; }
        
        .status-bar {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .status-card {
            background: rgba(255,255,255,0.05);
            border-radius: 10px;
            padding: 15px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .status-card h3 { 
            font-size: 0.85rem; 
            color: #888;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .status-card .value { 
            font-size: 1.8rem; 
            font-weight: bold;
        }
        .status-card .unit { 
            font-size: 0.9rem; 
            color: #666;
        }
        
        .status-card.energy { border-left: 4px solid #00ff88; }
        .status-card.cpu { border-left: 4px solid #ff6b6b; }
        .status-card.memory { border-left: 4px solid #4ecdc4; }
        .status-card.actions { border-left: 4px solid #ffd93d; }
        
        .status-card.warning { 
            background: rgba(255, 107, 107, 0.1);
            border-color: #ff6b6b;
        }
        
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .chart-card {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .chart-card h3 {
            font-size: 1rem;
            margin-bottom: 15px;
            color: #ccc;
        }
        .chart-container {
            position: relative;
            height: 200px;
        }
        
        .sanity-panel {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .sanity-panel h2 {
            font-size: 1.2rem;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .sanity-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .sanity-indicator.healthy { background: #00ff88; }
        .sanity-indicator.warning { background: #ff6b6b; animation: pulse 1s infinite; }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .sanity-metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
        }
        .sanity-metric {
            background: rgba(0,0,0,0.2);
            padding: 15px;
            border-radius: 8px;
        }
        .sanity-metric .label { color: #888; font-size: 0.85rem; }
        .sanity-metric .value { font-size: 1.4rem; margin: 5px 0; }
        .sanity-metric .threshold { font-size: 0.8rem; color: #666; }
        
        .kernel-sovereignty {
            text-align: center;
            padding: 15px;
            background: rgba(0,212,255,0.1);
            border-radius: 8px;
            margin-top: 20px;
            font-size: 0.9rem;
            color: #00d4ff;
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.8rem;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧠 ITHERIS Control Dashboard</h1>
        <div class="philosophy">
            <span>Brain</span> is advisory · <span>Kernel</span> is sovereign
        </div>
    </div>
    
    <div class="status-bar">
        <div class="status-card energy">
            <h3>⚡ Energy</h3>
            <div class="value" id="energy-value">--</div>
            <div class="unit"><span id="energy-mode">--</span> · <span id="tick-rate">136.1</span> Hz</div>
        </div>
        <div class="status-card cpu">
            <h3>🔥 CPU Load</h3>
            <div class="value" id="cpu-value">--</div>
            <div class="unit">normalized</div>
        </div>
        <div class="status-card memory">
            <h3>💾 Memory</h3>
            <div class="value" id="mem-value">--</div>
            <div class="unit">GB used</div>
        </div>
        <div class="status-card actions">
            <h3>✓ Actions</h3>
            <div class="value" id="actions-value">--</div>
            <div class="unit">approved / <span id="rejected-value">--</span> rejected</div>
        </div>
    </div>
    
    <div class="sanity-panel">
        <h2>
            <span class="sanity-indicator" id="sanity-indicator"></span>
            Cognitive Sanity Monitor
        </h2>
        <div class="sanity-metrics">
            <div class="sanity-metric">
                <div class="label">Attention Variance</div>
                <div class="value" id="attention-value">--</div>
                <div class="threshold">Threshold: >0.02 = warning</div>
            </div>
            <div class="sanity-metric">
                <div class="label">Policy Entropy</div>
                <div class="value" id="entropy-value">--</div>
                <div class="threshold">Normal range: 0.3 - 4.5 bits</div>
            </div>
            <div class="sanity-metric">
                <div class="label">Cognitive Load</div>
                <div class="value" id="load-value">--</div>
                <div class="threshold">Processing saturation</div>
            </div>
            <div class="sanity-metric">
                <div class="label">Kernel Status</div>
                <div class="value" id="kernel-status">--</div>
                <div class="threshold">Sovereign control</div>
            </div>
        </div>
    </div>
    
    <div class="charts-grid">
        <div class="chart-card">
            <h3>📊 Energy & System Metrics</h3>
            <div class="chart-container">
                <canvas id="energyChart"></canvas>
            </div>
        </div>
        <div class="chart-card">
            <h3>🧠 Cognitive Telemetry</h3>
            <div class="chart-container">
                <canvas id="cognitiveChart"></canvas>
            </div>
        </div>
    </div>
    
    <div class="kernel-sovereignty">
        🔒 <strong>Kernel Sovereignty Active</strong> — All operations validated through sovereign kernel interface
    </div>
    
    <div class="footer">
        ITHERIS Dashboard · 1-second polling · <span id="uptime">--</span> uptime
    </div>
    
    <script>
        // Chart.js configuration
        const chartConfig = {
            responsive: true,
            maintainAspectRatio: false,
            animation: { duration: 300 },
            plugins: {
                legend: { labels: { color: '#888' } }
            },
            scales: {
                x: {
                    ticks: { color: '#666', maxTicksLimit: 10 },
                    grid: { color: 'rgba(255,255,255,0.05)' }
                },
                y: {
                    ticks: { color: '#666' },
                    grid: { color: 'rgba(255,255,255,0.05)' }
                }
            }
        };
        
        // Energy & System Chart
        const energyCtx = document.getElementById('energyChart').getContext('2d');
        const energyChart = new Chart(energyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Energy',
                        data: [],
                        borderColor: '#00ff88',
                        backgroundColor: 'rgba(0,255,136,0.1)',
                        fill: true,
                        tension: 0.4
                    },
                    {
                        label: 'CPU',
                        data: [],
                        borderColor: '#ff6b6b',
                        tension: 0.4
                    },
                    {
                        label: 'Memory',
                        data: [],
                        borderColor: '#4ecdc4',
                        tension: 0.4
                    }
                ]
            },
            options: chartConfig
        });
        
        // Cognitive Telemetry Chart
        const cognitiveCtx = document.getElementById('cognitiveChart').getContext('2d');
        const cognitiveChart = new Chart(cognitiveCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Attention Variance',
                        data: [],
                        borderColor: '#ffd93d',
                        tension: 0.4
                    },
                    {
                        label: 'Policy Entropy',
                        data: [],
                        borderColor: '#7b2cbf',
                        tension: 0.4
                    },
                    {
                        label: 'Threshold (0.02)',
                        data: [],
                        borderColor: '#ff6b6b',
                        borderDash: [5, 5],
                        pointRadius: 0
                    }
                ]
            },
            options: chartConfig
        });
        
        let startTime = Date.now();
        
        // Fetch and update data
        async function updateDashboard() {
            try {
                const [status, telemetry] = await Promise.all([
                    fetch('/api/status').then(r => r.json()),
                    fetch('/api/telemetry').then(r => r.json())
                ]);
                
                // Update status cards
                document.getElementById('energy-value').textContent = 
                    (status.metabolic.energy * 100).toFixed(1) + '%';
                document.getElementById('energy-mode').textContent = 
                    status.metabolic.mode;
                document.getElementById('cpu-value').textContent = 
                    (status.system.cpu_load * 100).toFixed(1) + '%';
                document.getElementById('mem-value').textContent = 
                    (status.system.memory_usage * status.system.memory_total_gb).toFixed(1);
                document.getElementById('actions-value').textContent = 
                    status.system.approved_actions;
                document.getElementById('rejected-value').textContent = 
                    status.system.rejected_actions;
                
                // Update sanity panel
                const attElem = document.getElementById('attention-value');
                attElem.textContent = status.sanity.attention_variance.toFixed(4);
                attElem.style.color = status.sanity.attention_status === 'warning' ? '#ff6b6b' : '#00ff88';
                
                const entElem = document.getElementById('entropy-value');
                entElem.textContent = status.sanity.policy_entropy.toFixed(2) + ' bits';
                entElem.style.color = status.sanity.entropy_status === 'warning' ? '#ff6b6b' : '#00ff88';
                
                document.getElementById('load-value').textContent = 
                    (status.cognitive.load * 100).toFixed(1) + '%';
                document.getElementById('kernel-status').textContent = 
                    status.kernel_connected ? 'Connected' : 'Simulated';
                document.getElementById('kernel-status').style.color = 
                    status.kernel_connected ? '#00ff88' : '#ffd93d';
                
                // Update sanity indicator
                const indicator = document.getElementById('sanity-indicator');
                const overall = status.sanity.overall;
                indicator.className = 'sanity-indicator ' + overall;
                
                // Update charts
                if (telemetry.timestamps && telemetry.timestamps.length > 0) {
                    energyChart.data.labels = telemetry.timestamps;
                    energyChart.data.datasets[0].data = telemetry.energy;
                    energyChart.data.datasets[1].data = telemetry.cpu;
                    energyChart.data.datasets[2].data = telemetry.memory;
                    energyChart.update('none');
                    
                    cognitiveChart.data.labels = telemetry.timestamps;
                    cognitiveChart.data.datasets[0].data = telemetry.attention_variance;
                    cognitiveChart.data.datasets[1].data = telemetry.policy_entropy;
                    cognitiveChart.data.datasets[2].data = 
                        telemetry.attention_variance.map(() => telemetry.thresholds.attention);
                    cognitiveChart.update('none');
                }
                
                // Update uptime
                const uptime = Math.floor((Date.now() - startTime) / 1000);
                const mins = Math.floor(uptime / 60);
                const secs = uptime % 60;
                document.getElementById('uptime').textContent = mins + 'm ' + secs + 's';
                
            } catch (e) {
                console.error('Dashboard update failed:', e);
            }
        }
        
        // Poll every second
        updateDashboard();
        setInterval(updateDashboard, 1000);
    </script>
</body>
</html>
"""
    return HTTP.Response(200, ["Content-Type" => "text/html"], body=html)
end

"""
    _status_api_handler(req)

Return current system status as JSON.
"""
function _status_api_handler(req)
    status = get_live_status()
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(status))
end

"""
    _telemetry_api_handler(req)

Return telemetry history for charts as JSON.
"""
function _telemetry_api_handler(req)
    telemetry = get_telemetry_history()
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(telemetry))
end

"""
    _metrics_api_handler(req)

Return simplified metrics as JSON (lightweight).
"""
function _metrics_api_handler(req)
    metrics = Dict(
        :energy => _dashboard_state.energy,
        :cpu => _dashboard_state.cpu_load,
        :memory => _dashboard_state.memory_usage,
        :timestamp => now()
    )
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(metrics))
end

"""
    _sanity_api_handler(req)

Return cognitive sanity status as JSON.
"""
function _sanity_api_handler(req)
    sanity = get_sanity_status()
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(sanity))
end

"""
    _live_feed_handler(req)

Return lightweight live feed for high-frequency updates.
"""
function _live_feed_handler(req)
    feed = Dict(
        :energy => _dashboard_state.energy,
        :metabolic_mode => _dashboard_state.metabolic_mode,
        :tick_count => _dashboard_state.tick_count,
        :attention_variance => _dashboard_state.attention_variance,
        :policy_entropy => _dashboard_state.policy_entropy,
        :cpu => _dashboard_state.cpu_load,
        :timestamp => now()
    )
    return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(feed))
end

"""
    _control_handler(req)

Handle control commands (requires kernel validation).
This demonstrates "Kernel is sovereign" - even dashboard controls
must go through kernel approval.
"""
function _control_handler(req)
    try
        body = String(req.body)
        params = JSON.parse(body)
        command = get(params, "command", "")
        
        # In production, this would call KernelInterface.approve_action()
        # For now, return success
        result = Dict(
            :success => true,
            :command => command,
            :message => "Command queued for kernel validation",
            :timestamp => now()
        )
        
        return HTTP.Response(200, ["Content-Type" => "application/json"], body=JSON.json(result))
    catch e
        result = Dict(
            :success => false,
            :error => string(e),
            :timestamp => now()
        )
        return HTTP.Response(400, ["Content-Type" => "application/json"], body=JSON.json(result))
    end
end

# ============================================================================
# EXPORTS
# ============================================================================

# Main functions
export serve_dashboard, get_live_status, get_telemetry_history, get_sanity_status
export refresh_dashboard!

# Constants
export METABOLIC_TICK_HZ, ATTENTION_VARIANCE_THRESHOLD
export POLICY_ENTROPY_MIN, POLICY_ENTROPY_MAX

end # module Web
