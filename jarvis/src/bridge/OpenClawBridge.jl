# jarvis/src/bridge/OpenClawBridge.jl - OpenClaw Tool Container Interface
# HTTP/JSON interface to OpenClaw Docker endpoint with kernel safety checks

module OpenClawBridge

using HTTP
using JSON
using Dates
using UUIDs
using Logging
using Base.Threads

export 
    OpenClawConfig,
    ClawTool,
    ClawToolCall,
    ClawResult,
    CLAW_TOOLS,
    call_tool,
    list_tools,
    get_tool_manifest,
    test_connection,
    # Safety
    is_tool_allowed,
    validate_tool_call,
    set_kernel_ref!,
    get_kernel_ref

# Import Jarvis types from parent module
using ..JarvisTypes

# ============================================================================
# CONFIGURATION
# ============================================================================

"""
    OpenClawConfig - Configuration for OpenClaw tool container
"""
struct OpenClawConfig
    endpoint::String          # Docker endpoint (default: localhost:3000)
    api_key::String           # Optional API key for authentication
    timeout::Float64          # Request timeout in seconds
    retry_count::Int          # Number of retries on failure
    kernel_veto_enabled::Bool # Whether to check kernel before each call
    
    function OpenClawConfig(;
        endpoint::String = "http://localhost:3000",
        api_key::String = "",
        timeout::Float64 = 30.0,
        retry_count::Int = 3,
        kernel_veto_enabled::Bool = true
    )
        new(endpoint, api_key, timeout, retry_count, kernel_veto_enabled)
    end
end

# ============================================================================
# TOOL DEFINITIONS
# ============================================================================

"""
    ClawTool - Definition of an available OpenClaw tool
"""
struct ClawTool
    id::String
    name::String
    description::String
    category::String
    parameters::Dict{String, Any}
    requires_confirmation::Bool
    risk_level::Float32  # 0.0 to 1.0
    
    ClawTool(
        id::String,
        name::String,
        description::String,
        category::String;
        parameters::Dict{String, Any} = Dict{String, Any}(),
        requires_confirmation::Bool = false,
        risk_level::Float32 = 0.1f0
    ) = new(id, name, description, category, parameters, requires_confirmation, risk_level)
end

"""
    ClawToolCall - A request to execute a tool
"""
struct ClawToolCall
    tool_id::String
    parameters::Dict{String, Any}
    call_id::UUID
    timestamp::DateTime
    caller_context::String
    
    function ClawToolCall(
        tool_id::String,
        parameters::Dict{String, Any};
        caller_context::String = "brian"
    )
        new(tool_id, parameters, uuid4(), now(), caller_context)
    end
end

"""
    ClawResult - Result from a tool execution
"""
struct ClawResult
    call_id::UUID
    success::Bool
    result::Any
    error::Union{String, Nothing}
    execution_time_ms::Float64
    timestamp::DateTime
    
    function ClawResult(
        call_id::UUID,
        success::Bool,
        result::Any;
        error::Union{String, Nothing} = nothing,
        execution_time_ms::Float64 = 0.0
    )
        new(call_id, success, result, error, execution_time_ms, now())
    end
end

# ============================================================================
# TOOL MANIFEST - Available OpenClaw Tools
# ============================================================================

"""
    CLAW_TOOLS - Constant listing available OpenClaw tools
    These are the tools available in the OpenClaw Docker container
"""
const CLAW_TOOLS = Dict{String, ClawTool}(
    # Google Calendar tools
    "google_calendar_insert" => ClawTool(
        "google_calendar_insert",
        "Google Calendar Insert",
        "Create a new Google Calendar event",
        "productivity";
        parameters = Dict{String, Any}(
            "title" => Dict("type" => "string", "required" => true),
            "start_time" => Dict("type" => "datetime", "required" => true),
            "end_time" => Dict("type" => "datetime", "required" => false),
            "description" => Dict("type" => "string", "required" => false),
            "location" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = true,
        risk_level = 0.3f0
    ),
    "google_calendar_list" => ClawTool(
        "google_calendar_list",
        "Google Calendar List",
        "List upcoming Google Calendar events",
        "productivity";
        parameters = Dict{String, Any}(
            "max_results" => Dict("type" => "integer", "required" => false),
            "time_min" => Dict("type" => "datetime", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    
    # Gmail tools
    "gmail_send" => ClawTool(
        "gmail_send",
        "Gmail Send",
        "Send an email via Gmail",
        "communication";
        parameters = Dict{String, Any}(
            "to" => Dict("type" => "string", "required" => true),
            "subject" => Dict("type" => "string", "required" => true),
            "body" => Dict("type" => "string", "required" => true),
            "cc" => Dict("type" => "string", "required" => false),
            "attachments" => Dict("type" => "array", "required" => false)
        ),
        requires_confirmation = true,
        risk_level = 0.6f0
    ),
    "gmail_read" => ClawTool(
        "gmail_read",
        "Gmail Read",
        "Read recent emails from Gmail",
        "communication";
        parameters = Dict{String, Any}(
            "max_results" => Dict("type" => "integer", "required" => false),
            "query" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.2f0
    ),
    
    # System tools
    "system_shell" => ClawTool(
        "system_shell",
        "System Shell",
        "Execute a shell command on the host system",
        "system";
        parameters = Dict{String, Any}(
            "command" => Dict("type" => "string", "required" => true),
            "timeout" => Dict("type" => "integer", "required" => false),
            "working_dir" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = true,
        risk_level = 0.8f0
    ),
    "system_info" => ClawTool(
        "system_info",
        "System Info",
        "Get system information (CPU, memory, disk)",
        "system";
        parameters = Dict{String, Any}(
            "metrics" => Dict("type" => "array", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    
    # Web tools
    "web_search" => ClawTool(
        "web_search",
        "Web Search",
        "Perform a web search",
        "information";
        parameters = Dict{String, Any}(
            "query" => Dict("type" => "string", "required" => true),
            "num_results" => Dict("type" => "integer", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    "web_fetch" => ClawTool(
        "web_fetch",
        "Web Fetch",
        "Fetch content from a URL",
        "information";
        parameters = Dict{String, Any}(
            "url" => Dict("type" => "string", "required" => true),
            "method" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.2f0
    ),
    
    # File tools
    "file_read" => ClawTool(
        "file_read",
        "File Read",
        "Read content from a file",
        "filesystem";
        parameters = Dict{String, Any}(
            "path" => Dict("type" => "string", "required" => true),
            "encoding" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    "file_write" => ClawTool(
        "file_write",
        "File Write",
        "Write content to a file",
        "filesystem";
        parameters = Dict{String, Any}(
            "path" => Dict("type" => "string", "required" => true),
            "content" => Dict("type" => "string", "required" => true),
            "append" => Dict("type" => "boolean", "required" => false)
        ),
        requires_confirmation = true,
        risk_level = 0.5f0
    ),
    "file_list" => ClawTool(
        "file_list",
        "File List",
        "List files in a directory",
        "filesystem";
        parameters = Dict{String, Any}(
            "path" => Dict("type" => "string", "required" => true),
            "pattern" => Dict("type" => "string", "required" => false),
            "recursive" => Dict("type" => "boolean", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    
    # Notification tools
    "notification_send" => ClawTool(
        "notification_send",
        "Notification Send",
        "Send a system notification",
        "interface";
        parameters = Dict{String, Any}(
            "title" => Dict("type" => "string", "required" => true),
            "message" => Dict("type" => "string", "required" => true),
            "urgency" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    ),
    
    # Spotify tools
    "spotify_play" => ClawTool(
        "spotify_play",
        "Spotify Play",
        "Play music on Spotify",
        "entertainment";
        parameters = Dict{String, Any}(
            "track" => Dict("type" => "string", "required" => false),
            "artist" => Dict("type" => "string", "required" => false),
            "playlist" => Dict("type" => "string", "required" => false)
        ),
        requires_confirmation = false,
        risk_level = 0.2f0
    ),
    "spotify_control" => ClawTool(
        "spotify_control",
        "Spotify Control",
        "Control Spotify playback (pause, next, etc.)",
        "entertainment";
        parameters = Dict{String, Any}(
            "action" => Dict("type" => "string", "required" => true)
        ),
        requires_confirmation = false,
        risk_level = 0.1f0
    )
)

# ============================================================================
# KERNEL SAFETY CHECK INTERFACE
# ============================================================================

# Thread-safe kernel reference using ReentrantLock
const _KERNEL_LOCK = ReentrantLock()
const _KERNEL_REF = Ref{Any}(nothing)

"""
    set_kernel_ref! - Thread-safe setting of kernel reference
    
    # Arguments
    - kernel::Any: Reference to the Adaptive Kernel
"""
function set_kernel_ref!(kernel::Any)
    lock(_KERNEL_LOCK) do
        _KERNEL_REF[] = kernel
    end
end

"""
    get_kernel_ref - Thread-safe getting of kernel reference
    
    # Returns
    - Any: The kernel reference or nothing if not set
"""
function get_kernel_ref()
    lock(_KERNEL_LOCK) do
        return _KERNEL_REF[]
    end
end

"""
    kernel_veto_check - Check if kernel allows the tool call
    Returns (allowed::Bool, reason::String)
"""
function kernel_veto_check(tool_call::ClawToolCall)::Tuple{Bool, String}
    if KERNEL_REF[] === nothing
        # No kernel available, allow by default with warning
        Logging.@warn("[CLAW] No kernel reference - allowing tool call by default")
        return true, "no_kernel"
    end
    
    try
        # Get the tool definition
        tool = get(CLAW_TOOLS, tool_call.tool_id, nothing)
        if tool === nothing
            return false, "unknown_tool"
        end
        
        # Build a simple veto check request
        # In the full implementation, this would call Kernel.veto_check()
        # For now, we check risk level
        if tool.risk_level > 0.7f0
            return false, "high_risk_tool_blocked"
        end
        
        return true, "approved"
    catch e
        Logging.@error(string("CLAW Kernel veto check failed: ", e))
        return false, "kernel_error"
    end
end

# ============================================================================
# API FUNCTIONS
# ============================================================================

"""
    get_tool_manifest - Get all available tools
"""
function get_tool_manifest()::Vector{Dict{String, Any}}
    manifest = Dict{String, Any}[]
    for (id, tool) in CLAW_TOOLS
        push!(manifest, Dict(
            "id" => tool.id,
            "name" => tool.name,
            "description" => tool.description,
            "category" => tool.category,
            "parameters" => tool.parameters,
            "requires_confirmation" => tool.requires_confirmation,
            "risk_level" => tool.risk_level
        ))
    end
    return manifest
end

"""
    list_tools - List tool IDs by category
"""
function list_tools(; category::Union{String, Nothing} = nothing)::Vector{String}
    if category === nothing
        return collect(keys(CLAW_TOOLS))
    end
    
    return [id for (id, tool) in CLAW_TOOLS if tool.category == category]
end

"""
    test_connection - Test connectivity to OpenClaw endpoint
"""
function test_connection(config::OpenClawConfig)::Tuple{Bool, String}
    try
        headers = Dict{String, String}()
        if !isempty(config.api_key)
            headers["Authorization"] = string("Bearer ", config.api_key)
        end
        
        response = HTTP.get(
            string(config.endpoint, "/health"),
            headers;
            timeout = config.timeout
        )
        
        if response.status == 200
            return true, "connected"
        else
            return false, "health_check_failed"
        end
    catch e
        return false, string(e)
    end
end

"""
    validate_tool_call - Validate tool call parameters
"""
function validate_tool_call(tool_call::ClawToolCall)::Tuple{Bool, String}
    # Check tool exists
    tool = get(CLAW_TOOLS, tool_call.tool_id, nothing)
    if tool === nothing
        return false, string("Unknown tool: ", tool_call.tool_id)
    end
    
    # Check required parameters
    for (param_name, param_def) in tool.parameters
        if get(param_def, "required", false) === true
            if !haskey(tool_call.parameters, param_name)
                return false, string("Missing required parameter: ", param_name)
            end
        end
    end
    
    return true, "valid"
end

"""
    is_tool_allowed - Check if a tool can be called (safety check)
"""
function is_tool_allowed(tool_call::ClawToolCall; trust_level::TrustLevel = TRUST_STANDARD)::Tuple{Bool, String}
    # Get tool definition
    tool = get(CLAW_TOOLS, tool_call.tool_id, nothing)
    if tool === nothing
        return false, "Unknown tool"
    end
    
    # Check trust level requirements
    required_trust = if tool.risk_level > 0.7f0
        TRUST_FULL
    elseif tool.risk_level > 0.4f0
        TRUST_STANDARD
    else
        TRUST_LIMITED
    end
    
    if trust_level < required_trust
        return false, "Insufficient trust level"
    end
    
    # Check kernel veto
    allowed, reason = kernel_veto_check(tool_call)
    if !allowed
        return false, string("Kernel veto: ", reason)
    end
    
    return true, "allowed"
end

"""
    call_tool - Execute an OpenClaw tool
"""
function call_tool(
    config::OpenClawConfig,
    tool_call::ClawToolCall
)::ClawResult
    
    Logging.@info(string("[CLAW] Calling tool: ", tool_call.tool_id))
    
    # Validate tool call
    valid, reason = validate_tool_call(tool_call)
    if !valid
        Logging.@error(string("[CLAW] Validation failed: ", reason))
        return ClawResult(
            tool_call.call_id,
            false,
            nothing;
            error = string("Validation failed: ", reason)
        )
    end
    
    # Safety check - kernel veto
    if config.kernel_veto_enabled
        allowed, reason = kernel_veto_check(tool_call)
        if !allowed
            Logging.@warn(string("[CLAW] Tool call blocked by kernel: ", reason))
            return ClawResult(
                tool_call.call_id,
                false,
                nothing;
                error = string("Blocked by kernel: ", reason)
            )
        end
    end
    
    # Build request
    start_time = time()
    
    headers = Dict{String, String}(
        "Content-Type" => "application/json"
    )
    if !isempty(config.api_key)
        headers["Authorization"] = string("Bearer ", config.api_key)
    end
    
    body = JSON.json(Dict(
        "tool" => tool_call.tool_id,
        "parameters" => tool_call.parameters,
        "call_id" => string(tool_call.call_id),
        "context" => tool_call.caller_context
    ))
    
    # Make request with retries
    last_error = nothing
    for attempt in 1:config.retry_count
        try
            response = HTTP.post(
                string(config.endpoint, "/execute"),
                headers,
                body;
                timeout = config.timeout
            )
            
            execution_time = (time() - start_time) * 1000
            
            if response.status == 200
                data = JSON.parse(String(response.body))
                Logging.@info(string("[CLAW] Tool executed successfully in ", round(execution_time; digits=2), "ms"))
                
                return ClawResult(
                    tool_call.call_id,
                    get(data, "success", true),
                    get(data, "result", nothing);
                    error = get(data, "error", nothing),
                    execution_time_ms = execution_time
                )
            else
                last_error = string("HTTP ", response.status)
            end
        catch e
            last_error = string(e)
            warn_msg = string("[CLAW] Attempt ", attempt, " failed: ", e)
            Logging.@warn(warn_msg)
        end
        
        # Exponential backoff
        if attempt < config.retry_count
            sleep(2^(attempt - 1) * 0.5)
        end
    end
    
    err_msg = string("[CLAW] All retry attempts failed: ", last_error)
    Logging.@error(err_msg)
    return ClawResult(
        tool_call.call_id,
        false,
        nothing;
        error = string("Failed after ", config.retry_count, " attempts: ", last_error),
        execution_time_ms = (time() - start_time) * 1000
    )
end

# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

"""
    call_tool - Execute a tool by name with parameters
"""
function call_tool(
    config::OpenClawConfig,
    tool_name::String,
    parameters::Dict{String, Any};
    caller_context::String = "brian"
)::ClawResult
    tool_call = ClawToolCall(tool_name, parameters; caller_context = caller_context)
    return call_tool(config, tool_call)
end

end # module OpenClawBridge
