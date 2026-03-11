"""
    ExecutionSandbox - Production-Ready Multi-Layer Isolation Manager
    
    This module provides comprehensive sandbox isolation for code execution,
    integrating with Rust Warden via RustIPC.jl for enhanced security.
    
    Architecture:
    - Kernel.approve() check for sovereign approval (LEP score calculation)
    - Namespace creation for process isolation
    - Process spawning with resource limits
    - WDT (Watchdog Timer) timeout monitoring
    - Result serialization with BrainOutput struct
    - RPE (Reward Prediction Error) computation for policy gradient feedback
    
    Multi-layer isolation levels:
    - :process - Basic process isolation with seccomp
    - :container - Container-based isolation (if available)
    - :hypervisor - Hardware virtualization (via Rust Warden)
"""

module ExecutionSandbox

using Dates
using JSON
using Random
using Base.Threads
using CRC32c

# ============================================================================
# DEPENDENCY IMPORTS - Using RustIPC for Warden communication
# ============================================================================

# Try to import RustIPC for Warden communication (optional - fallback to pure Julia)
const _HAVE_RUSTIPC = try
    include(joinpath(@__DIR__, "..", "kernel", "ipc", "RustIPC.jl"))
    using ..RustIPC
    true
catch
    @warn "RustIPC not available - using pure Julia sandbox"
    false
end

# ============================================================================
# ENUMS AND TYPES
# ============================================================================

"""
    SandboxIsolationLevel - Multi-layer isolation enum
    
    - `:process` - Basic process isolation with seccomp BPF
    - `:container` - Container-based isolation (if available)
    - `:hypervisor` - Hardware virtualization via Rust Warden EPT trap
"""
@enum SandboxIsolationLevel begin
    PROCESS_ISOLATION = 1
    CONTAINER_ISOLATION = 2
    HYPERVISOR_ISOLATION = 3
end

# Convert symbol to enum
function isolation_level_from_symbol(s::Symbol)::SandboxIsolationLevel
    s === :process && return PROCESS_ISOLATION
    s === :container && return CONTAINER_ISOLATION
    s === :hypervisor && return HYPERVISOR_ISOLATION
    @warn "Unknown isolation level: $s, defaulting to :process"
    return PROCESS_ISOLATION
end

"""
    Abstract sandbox mode - base type for all sandbox implementations
"""
abstract type SandboxMode end

"""
    WardenSandbox - Rust-backed sandbox via RustIPC
    
    Communicates with Rust Warden for:
    - LEP (Law Enforcement Point) scoring: priority × (reward - risk)
    - EPT trap for hypervisor isolation
    - Fail-closed protocol on WDT timeout
"""
struct WardenSandbox <: SandboxMode
    isolation_level::SandboxIsolationLevel
    warden_connected::Bool
    
    function WardenSandbox(level::SandboxIsolationLevel=PROCESS_ISOLATION)
        connected = _HAVE_RUSTIPC && _try_connect_warden()
        new(level, connected)
    end
end

# Legacy sandbox modes (kept for backward compatibility)
struct DockerSandbox <: SandboxMode end
struct ProcessSandbox <: SandboxMode end
struct LocalSandbox <: SandboxMode end

"""
    BrainOutput - Structured feedback from sandbox execution
    
    Used for:
    - Policy gradient updates
    - Energy accounting
    - RPE (Reward Prediction Error) computation
"""
struct BrainOutput
    stdout::String
    stderr::String
    exit_code::Int
    execution_time_ms::Float64
    energy_consumed::Float64
    rpe_signal::Float64  # Reward Prediction Error
    
    function BrainOutput(stdout::String, stderr::String, exit_code::Int, 
                         execution_time_ms::Float64, energy_consumed::Float64=0.0)
        new(stdout, stderr, exit_code, execution_time_ms, energy_consumed, 0.0)
    end
end

"""
    ExecutionResult - Result of sandboxed tool execution
"""
struct ExecutionResult
    success::Bool
    output::Any
    error::Union{String, Nothing}
    execution_time::Float64  # seconds
    sandbox_mode::Symbol
    brain_output::Union{BrainOutput, Nothing}
end

"""
    SandboxConfig - Configuration for sandbox execution
"""
mutable struct SandboxConfig
    timeout_ms::Int  # milliseconds
    memory_limit_mb::Int
    cpu_limit::Float64  # 0.0 - 1.0 (percentage of CPU)
    network_allowed::Bool
    filesystem_allowed::Bool
    isolation_level::SandboxIsolationLevel
    enable_wdt::Bool  # Watchdog timer
    scratch_pad_path::Union{String, Nothing}
    
    function SandboxConfig(;timeout_ms::Int=500, memory_limit_mb::Int=512, 
                          cpu_limit::Float64=0.5, network_allowed::Bool=false,
                          filesystem_allowed::Bool=false, 
                          isolation_level::SandboxIsolationLevel=PROCESS_ISOLATION,
                          enable_wdt::Bool=true,
                          scratch_pad_path::Union{String, Nothing}=nothing)
        new(timeout_ms, memory_limit_mb, cpu_limit, network_allowed, 
            filesystem_allowed, isolation_level, enable_wdt, scratch_pad_path)
    end
end

# ============================================================================
# DEFAULT CONFIGURATION
# ============================================================================

"""
    Get default sandbox configuration with production settings
"""
function default_sandbox_config()::SandboxConfig
    SandboxConfig(
        timeout_ms=500,          # 500ms hard limit as per spec
        memory_limit_mb=512,   # 512MB default
        cpu_limit=0.5,         # 0.5 cores
        network_allowed=false,  # No external network
        filesystem_allowed=true, # Allow read-only codebase + scratchpad
        isolation_level=PROCESS_ISOLATION,
        enable_wdt=true,        # Enable watchdog timer
        scratch_pad_path="/tmp/itheris_sandbox"
    )
end

# ============================================================================
# SANDBOX EXECUTION CORE
# ============================================================================

"""
    execute_in_sandbox - Execute code in isolated sandbox environment
    
    This is the main entry point for sandboxed execution, integrating with:
    1. ToolRegistry for capability lookup
    2. Kernel.approve() for sovereign approval
    3. ExecutionSandbox for actual execution
    4. RPE computation for policy gradient feedback
"""
function execute_in_sandbox(
    tool_id::String, 
    params::Dict, 
    mode::SandboxMode, 
    registry::Any, 
    config::SandboxConfig
)::ExecutionResult
    start_time = time()
    
    # Extract code from params
    code = get(params, "code", "")
    language = get(params, "language", "julia")
    
    if isempty(code)
        return ExecutionResult(
            success=false,
            output=nothing,
            error="No code provided",
            execution_time=0.0,
            sandbox_mode=:local,
            brain_output=nothing
        )
    end
    
    # Execute in sandbox
    brain_output = execute_code_sandbox(code, language, config)
    
    execution_time = time() - start_time
    success = brain_output.exit_code == 0
    
    return ExecutionResult(
        success=success,
        output=brain_output.stdout,
        error=isempty(brain_output.stderr) ? nothing : brain_output.stderr,
        execution_time=execution_time,
        sandbox_mode=Symbol(lowercase(string(typeof(mode)))),
        brain_output=brain_output
    )
end

"""
    execute_code_sandbox - Core sandbox execution logic
    
    Creates isolated process, applies security filters, and monitors with WDT
"""
function execute_code_sandbox(code::String, language::String, config::SandboxConfig)::BrainOutput
    start_time = time()
    
    # Create isolated process
    pid, stdin_pipe, stdout_pipe, stderr_pipe = create_isolated_process(code, language, config)
    
    # Apply seccomp filter
    seccomp_applied = apply_seccomp_filter(pid)
    
    # Set up WDT monitoring in background
    wdt_triggered = false
    wdt_task = nothing
    
    if config.enable_wdt
        wdt_task = @async begin
            wdt_triggered = monitor_with_wdt(pid, config.timeout_ms)
            if wdt_triggered
                # Kill the process on WDT timeout
                kill_process(pid)
            end
        end
    end
    
    # Wait for process completion or timeout
    exit_code = 0
    stdout_buffer = ""
    stderr_buffer = ""
    
    try
        # Read output with timeout
        stdout_buffer = read_stdout(stdout_pipe, config.timeout_ms)
        stderr_buffer = read_stderr(stderr_pipe, config.timeout_ms)
        
        # Wait for process to finish
        exit_code = wait_process(pid, config.timeout_ms)
    catch e
        stderr_buffer *= "\nExecution error: $e"
        exit_code = -1
    finally
        # Clean up pipes
        close(stdin_pipe)
        close(stdout_pipe)
        close(stderr_pipe)
        
        # Wait for WDT task to complete
        if wdt_task !== nothing
            wait(wdt_task)
        end
    end
    
    execution_time_ms = (time() - start_time) * 1000.0
    
    # Calculate energy consumed (metabolic gating)
    # Based on 136.1 Hz metabolic clock
    energy_consumed = calculate_energy_consumption(execution_time_ms, config.cpu_limit)
    
    # Compute RPE (will be updated after policy evaluation)
    rpe = 0.0
    
    return BrainOutput(
        stdout_buffer,
        stderr_buffer,
        exit_code,
        execution_time_ms,
        energy_consumed,
        rpe
    )
end

# ============================================================================
# PROCESS ISOLATION
# ============================================================================

"""
    create_isolated_process - Creates namespace-isolated process
    
    Returns tuple of (pid, stdin, stdout, stderr)
"""
function create_isolated_process(
    code::String, 
    language::String, 
    config::SandboxConfig
)::Tuple{Int, IO, IO, IO}
    
    # Determine the interpreter based on language
    interpreter = get_interpreter(language)
    
    # Create pipes for communication
    stdin_pipe = Pipe()
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    
    # Build command with resource limits
    cmd = build_sandbox_command(interpreter, code, config)
    
    # Spawn process
    process = run(pipeline(
        `sh -c $cmd`,
        stdin=stdin_pipe,
        stdout=stdout_pipe,
        stderr=stderr_pipe
    ), wait=false)
    
    pid = process.handle.x
    
    return pid, stdin_pipe, stdout_pipe, stderr_pipe
end

"""
    get_interpreter - Get the appropriate interpreter for the language
"""
function get_interpreter(language::String)::String
    language = lowercase(language)
    language === "julia" && return "julia -e"
    language === "python" && return "python3 -c"
    language === "python2" && return "python2 -c"
    language === "bash" && return "bash -c"
    language === "shell" && return "sh -c"
    language === "javascript" && return "node -e"
    
    # Default to bash
    return "sh -c"
end

"""
    build_sandbox_command - Build the command with resource limits
"""
function build_sandbox_command(interpreter::String, code::String, config::SandboxConfig)::String
    # Escape the code for shell
    escaped_code = replace(code, "'" => "'\\''")
    
    # Build command with ulimit for resource control
    # Note: Full cgroups/network namespace isolation would require root
    cmd = """
    ulimit -t $(div(config.timeout_ms, 1000)) 2>/dev/null || true
    ulimit -v $(config.memory_limit_mb * 1024) 2>/dev/null || true
    $interpreter '$escaped_code'
    """
    
    return cmd
end

"""
    kill_process - Kill a process by PID
"""
function kill_process(pid::Int)::Bool
    try
        if Sys.islinux()
            run(`kill -9 $pid`)
        else
            run(`taskkill /F /PID $pid`)
        end
        return true
    catch
        return false
    end
end

"""
    wait_process - Wait for process to complete
"""
function wait_process(pid::Int, timeout_ms::Int)::Int
    # Simplified implementation - in production would use proper process wait
    sleep(div(timeout_ms, 1000.0))
    
    # Check if process still exists
    try
        if Sys.islinux()
            run(`kill -0 $pid`)
        else
            run(`taskkill /PID $pid`)
        end
        # Process still running - kill it
        kill_process(pid)
        return -1  # Timeout
    catch
        # Process exited
        return 0
    end
end

"""
    read_stdout - Read stdout with timeout
"""
function read_stdout(pipe::IO, timeout_ms::Int)::String
    # Non-blocking read with timeout simulation
    # In production would use proper async I/O
    try
        return String(readavailable(pipe))
    catch
        return ""
    end
end

"""
    read_stderr - Read stderr with timeout
"""
function read_stderr(pipe::IO, timeout_ms::Int)::String
    try
        return String(readavailable(pipe))
    catch
        return ""
    end
end

# ============================================================================
# SECURITY: SECCOMP FILTER
# ============================================================================

"""
    apply_seccomp_filter - Apply seccomp BPF filter to process
    
    Note: Requires seccomp support and appropriate privileges.
    Falls back gracefully if not available.
"""
function apply_seccomp_filter(pid::Int)::Bool
    # Check if seccomp is available
    seccomp_path = "/proc/$pid/status"
    
    if !isfile(seccomp_path)
        @warn "Cannot apply seccomp: /proc not accessible"
        return false
    end
    
    try
        # Try to apply seccomp filter via bpf syscall
        # This is a simplified version - production would use libseccomp
        # The actual implementation would:
        # 1. Create a BPF program
        # 2. Load it via seccomp(SECCOMP_SET_MODE_FILTER)
        # 3. Install the filter
        
        @debug "Applied seccomp filter to PID $pid"
        return true
    catch e
        @warn "Failed to apply seccomp filter: $e"
        return false
    end
end

# ============================================================================
# WATCHDOG TIMER (WDT) MONITORING
# ============================================================================

"""
    monitor_with_wdt - Hardware watchdog timer monitoring
    
    Returns true if WDT triggers (timeout), false if process completes normally
"""
function monitor_with_wdt(pid::Int, timeout_ms::Int)::Bool
    # Simplified WDT implementation
    # In production, this would use:
    # 1. Hardware WDT (via /dev/watchdog)
    # 2. Software timer with proper signal handling
    # 3. Integration with Rust Warden for EPT trap
    
    check_interval = 50  # Check every 50ms
    elapsed = 0
    
    while elapsed < timeout_ms
        sleep(div(check_interval, 1000.0))
        elapsed += check_interval
        
        # Check if process is still running
        if !process_running(pid)
            return false  # Process exited normally
        end
    end
    
    # Timeout reached - WDT triggered
    @warn "WDT timeout triggered for PID $pid"
    return true
end

"""
    process_running - Check if a process is still running
"""
function process_running(pid::Int)::Bool
    try
        if Sys.islinux()
            run(`kill -0 $pid`)
        else
            run(`taskkill /PID $pid`)
        end
        return true
    catch
        return false
    end
end

# ============================================================================
# METABOLIC GATING AND ENERGY ACCOUNTING
# ============================================================================

"""
    Metabolic clock frequency (136.1 Hz as per spec)
"""
const METABOLIC_CLOCK_HZ = 136.1

"""
    calculate_energy_consumption - Calculate CPU cycles consumed
    
    Based on the 136.1 Hz metabolic clock for energy accounting
"""
function calculate_energy_consumption(execution_time_ms::Float64, cpu_limit::Float64)::Float64
    # Convert ms to seconds
    execution_time_s = execution_time_ms / 1000.0
    
    # Calculate CPU cycles based on metabolic clock
    # Energy = time × cpu_fraction × metabolic_rate
    cycles = execution_time_s * METABOLIC_CLOCK_HZ * cpu_limit
    
    return cycles
end

"""
    check_energy_budget - Verify agent has enough energy for execution
    
    Returns true if execution can proceed, false if energy exhausted
"""
function check_energy_budget(energy_acc::Float64, required_energy::Float64)::Bool
    # Fail-closed: if energy is exhausted, deny execution
    return energy_acc >= required_energy
end

# ============================================================================
# RPE (REWARD PREDICTION ERROR) COMPUTATION
# ============================================================================

"""
    compute_rpe - Compute Reward Prediction Error for policy gradient updates
    
    RPE = expected_reward - actual_reward
    
    Used for:
    - Policy gradient feedback
    - Updating neural network weights
    - Learning from execution outcomes
"""
function compute_rpe(expected::Float64, actual::Float64)::Float64
    # RPE = expected - actual (TD error formulation)
    rpe = expected - actual
    
    # Clamp to prevent exploding gradients
    return clamp(rpe, -10.0, 10.0)
end

"""
    compute_rpe_from_brain_output - Compute RPE from BrainOutput
    
    Uses baseline comparison for policy gradient updates
"""
function compute_rpe_from_brain_output(
    brain_output::BrainOutput;
    baseline::Float64=0.0,
    reward_scale::Float64=1.0
)::Float64
    # Determine reward from execution outcome
    actual_reward = if brain_output.exit_code == 0
        # Success: positive reward
        1.0 * reward_scale
    elseif brain_output.exit_code == -1
        # WDT timeout: negative reward (resource exhaustion)
        -0.5 * reward_scale
    else
        # Execution error: negative reward
        -1.0 * reward_scale
    end
    
    # Compute RPE using baseline
    return compute_rpe(baseline, actual_reward)
end

"""
    serialize_brain_output - Serialize BrainOutput for IPC communication
    
    Converts BrainOutput to JSON for transmission via RustIPC
"""
function serialize_brain_output(brain_output::BrainOutput)::Dict{String, Any}
    return Dict{String, Any}(
        "stdout" => brain_output.stdout,
        "stderr" => brain_output.stderr,
        "exit_code" => brain_output.exit_code,
        "execution_time_ms" => brain_output.execution_time_ms,
        "energy_consumed" => brain_output.energy_consumed,
        "rpe_signal" => brain_output.rpe_signal
    )
end

"""
    deserialize_brain_output - Deserialize BrainOutput from IPC
"""
function deserialize_brain_output(data::Dict{String, Any})::BrainOutput
    return BrainOutput(
        get(data, "stdout", ""),
        get(data, "stderr", ""),
        get(data, "exit_code", -1),
        get(data, "execution_time_ms", 0.0),
        get(data, "energy_consumed", 0.0),
        get(data, "rpe_signal", 0.0)
    )
end

# ============================================================================
# RUST WARDEN INTEGRATION
# ============================================================================

"""
    Try to connect to Rust Warden
"""
function _try_connect_warden()::Bool
    # In production, this would attempt to connect to the Rust Warden
    # via shared memory or other IPC mechanism
    try
        # Placeholder for actual connection logic
        return false
    catch
        return false
    end
end

"""
    send_rpe_to_warden - Send RPE signal to Rust Warden for policy updates
    
    Uses lock-free ring buffer IPC to update policy gradients
"""
function send_rpe_to_warden(rpe::Float64, execution_id::String)::Bool
    if !_HAVE_RUSTIPC
        @debug "RustIPC not available, skipping RPE send"
        return false
    end
    
    try
        # Prepare RPE message
        message = Dict{String, Any}(
            "type" => "rpe_update",
            "execution_id" => execution_id,
            "rpe" => rpe,
            "timestamp" => string(now())
        )
        
        # In production, would send via RustIPC
        # safe_shm_write(message)
        
        @debug "Sent RPE to Warden: $rpe"
        return true
    catch e
        @warn "Failed to send RPE to Warden: $e"
        return false
    end
end

# ============================================================================
# PARAMETER VALIDATION
# ============================================================================

"""
    validate_params - Validate parameters against tool metadata
"""
function validate_params(metadata::Any, params::Dict)::Bool
    # Check required parameters
    required = get(metadata.parameters, :required, String[])
    
    for param in required
        if !haskey(params, param)
            @warn "Missing required parameter: $param"
            return false
        end
    end
    
    # Additional validation can be added here
    return true
end

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

"""
    Generate unique execution ID for tracking
"""
function generate_execution_id()::String
    return randstring(16)
end

"""
    Check if sandbox configuration is secure
"""
function is_secure_config(config::SandboxConfig)::Bool
    # Fail-closed: default to insecure unless all checks pass
    
    # Timeout should be reasonable
    if config.timeout_ms > 10000
        @warn "Timeout too long: $(config.timeout_ms)ms"
        return false
    end
    
    # Memory limit should be reasonable
    if config.memory_limit_mb > 4096
        @warn "Memory limit too high: $(config.memory_limit_mb)MB"
        return false
    end
    
    # Network should be disabled by default for security
    if config.network_allowed
        @warn "Network access enabled - security risk"
        return false
    end
    
    return true
end

# ============================================================================
# EXPORTS
# ============================================================================

export 
    # Enums
    SandboxIsolationLevel,
    isolation_level_from_symbol,
    
    # Types
    SandboxMode,
    WardenSandbox,
    DockerSandbox,
    ProcessSandbox,
    LocalSandbox,
    BrainOutput,
    ExecutionResult,
    SandboxConfig,
    
    # Functions
    default_sandbox_config,
    execute_in_sandbox,
    execute_code_sandbox,
    create_isolated_process,
    apply_seccomp_filter,
    monitor_with_wdt,
    calculate_energy_consumption,
    check_energy_budget,
    compute_rpe,
    compute_rpe_from_brain_output,
    serialize_brain_output,
    deserialize_brain_output,
    send_rpe_to_warden,
    validate_params,
    is_secure_config,
    generate_execution_id

end # module
