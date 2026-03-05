module SafeHTTPRequest
using UUIDs
using HTTP
using URIs

# Import circuit breaker for resilience
const _circuit_breaker_enabled = Ref(false)

"""
    Enable or disable circuit breaker protection for HTTP requests
"""
function enable_circuit_breaker(enabled::Bool=true)
    _circuit_breaker_enabled[] = enabled
    if enabled
        println("[HTTP] Circuit breaker protection ENABLED")
    else
        println("[HTTP] Circuit breaker protection DISABLED")
    end
end

function is_circuit_breaker_enabled()::Bool
    return _circuit_breaker_enabled[]
end

export meta, execute, is_url_allowed, parse_url_strictly, enable_circuit_breaker, is_circuit_breaker_enabled

function meta()::Dict{String,Any}
    return Dict(
        "id"=>"safe_http_request",
        "name"=>"Safe HTTP Request",
        "description"=>"Perform read-only HTTP GET to whitelisted hosts with content filtering",
        "inputs"=>Dict(
            "url"=>"string - target URL (must be whitelisted)",
            "max_response_size"=>"int - max bytes to receive (default 1024)",
            "timeout"=>"int - request timeout in seconds (default 3)"
        ),
        "outputs"=>Dict(
            "status"=>"int - HTTP status code",
            "body_snippet"=>"string - truncated response body",
            "content_type"=>"string - response content type",
            "headers"=>"dict - response headers"
        ),
        "cost"=>0.03,
        "risk"=>"medium",
        "reversible"=>true,
        "confidence_model"=>"empirical",
        "filters"=>[
            "host_whitelist - only allows requests to pre-approved domains",
            "size_limit - caps response body to prevent memory issues",
            "timeout_enforced - prevents hanging on slow endpoints",
            "content_type_filter - restricts to safe content types (text, json, xml)"
        ]
    )
end

# ============================================================================
# FILTER CONFIGURATION
# ============================================================================

# Allowed hosts - extend this list to add more trusted domains
const WHITELIST = [
    "api.ipify.org",      # IP identification service
    "httpbin.org",        # HTTP testing
    "jsonplaceholder.typicode.com"  # Mock API
]

# Rate limiting: requests per minute
const HTTP_RATE_LIMIT = 30

# Request/response size limits (1MB max)
const MAX_REQUEST_SIZE = 1048576  # 1MB

# Allowed content types (whitelist approach for safety)
const ALLOWED_CONTENT_TYPES = [
    "text/plain",
    "text/html",
    "application/json",
    "application/xml",
    "application/javascript"
]

# Blocked patterns in URLs (security filter)
const BLOCKED_PATTERNS = [
    r"\.exe$",
    r"\.sh$",
    r"\.bat$",
    r"\.cmd$",
    r"data:text/html",
    r"javascript:",
    r"file://"
]

# SECURITY: Block curl flags that could be injected via URL
const BLOCKED_CURL_FLAGS = [
    r"-O",       # Output to file
    r"-o",       # Output to file
    r"-T",       # Upload file
    r"-d",       # POST data
    r"-F",       # Form data
    r"-u",       # Basic auth
    r"-A",       # User agent
    r"-e",       # Referer
    r"-H",       # Custom header
    r"-X",       # Request method
    r"--data",   # POST data
    r"--header", # Custom header
    r"--request", # Request method
    r"--user",   # Basic auth
]

# Default limits
const DEFAULT_MAX_SIZE = 1048576  # 1MB default (matching MAX_REQUEST_SIZE)
const DEFAULT_TIMEOUT = 3          # 3 seconds

"""
    parse_url_strictly - Parse URL and extract hostname securely
    Returns (hostname, error_message) tuple
"""
function parse_url_strictly(url::String)::Tuple{Union{String, Nothing}, Union{String, Nothing}}
    # Check for blocked patterns first
    url_lower = lowercase(url)
    for pattern in BLOCKED_PATTERNS
        if occursin(pattern, url_lower)
            return (nothing, "URL matches blocked pattern: $(pattern)")
        end
    end
    
    # SECURITY: Check for curl flag injection attempts
    for flag_pattern in BLOCKED_CURL_FLAGS
        if occursin(flag_pattern, url)
            return (nothing, "Curl flag injection detected: $(flag_pattern)")
        end
    end
    
    # Parse URL using URI module for proper parsing
    try
        # Ensure URL has a scheme
        url_to_parse = startswith(url, "http") ? url : "http://$url"
        uri = URI(url_to_parse)
        
        # Extract hostname
        hostname = uri.host
        
        if hostname === nothing || isempty(hostname)
            return (nothing, "Invalid URL: no hostname found")
        end
        
        # Block IP addresses (prevent IP-based bypass)
        if occursin(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", hostname)
            return (nothing, "IP addresses not allowed")
        end
        
        # Block localhost and private addresses
        if hostname in ["localhost", "127.0.0.1", "::1"] || startswith(hostname, "192.168.") || startswith(hostname, "10.") || startswith(hostname, "172.16.")
            return (nothing, "Private/local addresses not allowed")
        end
        
        return (hostname, nothing)
    catch e
        return (nothing, "Failed to parse URL: $(typeof(e))")
    end
end

"""
    is_url_allowed - Check if URL is allowed using strict hostname matching
    SECURITY: Uses exact hostname matching to prevent subdomain bypass
"""
function is_url_allowed(url::String)::Tuple{Bool, String}
    # Parse URL strictly
    hostname, error = parse_url_strictly(url)
    if hostname === nothing
        return (false, error)
    end
    
    # Exact hostname match only (prevents subdomain bypass)
    # e.g., "api.example.com.evil.com" won't match "example.com"
    if hostname ∈ WHITELIST
        return (true, "allowed")
    end
    
    # Also check for exact match with www prefix
    if hostname == "www.$hostname" && "www.$hostname" ∈ WHITELIST
        return (true, "allowed")
    end
    
    return (false, "Hostname '$hostname' not in whitelist")
end

function is_content_allowed(content_type::String)::Bool
    lowercase_ct = lowercase(content_type)
    return any(startswith(lowercase_ct, allowed) for allowed in ALLOWED_CONTENT_TYPES)
end

function execute(params::Dict{String,Any})::Dict{String,Any}
    # Parse parameters with defaults
    url = get(params, "url", "https://example.com")
    max_size = get(params, "max_response_size", DEFAULT_MAX_SIZE)
    timeout = get(params, "timeout", DEFAULT_TIMEOUT)
    
    # SECURITY: Strict URL validation
    allowed, reason = is_url_allowed(url)
    if !allowed
        return Dict(
            "success"=>false, 
            "effect"=>"url_filtered: $(reason)", 
            "actual_confidence"=>0.0, 
            "energy_cost"=>0.0,
            "filter_reason"=>reason
        )
    end
    
    # Check circuit breaker if enabled
    if _circuit_breaker_enabled[]
        # Check if the breaker allows requests
        # For now, we implement a simple in-memory circuit breaker check
        # In production, this would integrate with the global circuit breaker manager
        circuit_open = _check_http_circuit_breaker(url)
        if circuit_open
            return Dict(
                "success"=>false,
                "effect"=>"circuit_breaker_open",
                "actual_confidence"=>0.0,
                "energy_cost"=>0.0,
                "filter_reason"=>"Circuit breaker is open for HTTP requests"
            )
        end
    end
    
    # Execute HTTP request with circuit breaker tracking
    _execute_http_request(url, max_size, timeout)
end

# ============================================================================
# Circuit Breaker State for HTTP Requests
# ============================================================================

# Simple in-memory circuit breaker state
const _http_failure_count = Ref(0)
const _http_last_failure = Ref(0.0)
const _http_circuit_open = Ref(false)
const _http_circuit_open_time = Ref(0.0)

const HTTP_FAILURE_THRESHOLD = 5
const HTTP_CIRCUIT_TIMEOUT = 60.0  # seconds

"""
    Check if circuit breaker is open for HTTP requests
"""
function _check_http_circuit_breaker(url::String)::Bool
    if _http_circuit_open[]
        # Check if timeout has elapsed
        elapsed = time() - _http_circuit_open_time[]
        if elapsed > HTTP_CIRCUIT_TIMEOUT
            # Transition to half-open (allow one request)
            _http_circuit_open[] = false
            _http_failure_count[] = 0
            println("[HTTP] Circuit breaker entering HALF_OPEN state")
            return false
        end
        return true
    end
    return false
end

"""
    Record HTTP success and potentially close the circuit
"""
function _record_http_success()
    _http_failure_count[] = 0
    # If we were in half-open state (failure_count was reset), close the circuit
    if _http_circuit_open[]
        elapsed = time() - _http_circuit_open_time[]
        if elapsed > HTTP_CIRCUIT_TIMEOUT
            _http_circuit_open[] = false
            println("[HTTP] Circuit breaker CLOSED after successful recovery")
        end
    end
end

"""
    Record HTTP failure and potentially open the circuit
"""
function _record_http_failure()
    _http_failure_count[] += 1
    _http_last_failure[] = time()
    
    if _http_failure_count[] >= HTTP_FAILURE_THRESHOLD
        _http_circuit_open[] = true
        _http_circuit_open_time[] = time()
        println("[HTTP] Circuit breaker OPENED after $(_http_failure_count[]) failures")
    end
end

"""
    Get HTTP circuit breaker status
"""
function get_http_circuit_status()::Dict{String, Any}
    Dict(
        "open"=>_http_circuit_open[],
        "failure_count"=>_http_failure_count[],
        "last_failure"=>_http_last_failure[],
        "time_open"=>_http_circuit_open[] ? time() - _http_circuit_open_time[] : 0
    )
end

"""
    Reset HTTP circuit breaker (for testing or manual recovery)
"""
function reset_http_circuit_breaker()
    _http_failure_count[] = 0
    _http_last_failure[] = 0.0
    _http_circuit_open[] = false
    _http_circuit_open_time[] = 0.0
    println("[HTTP] Circuit breaker manually reset")
end

"""
    Execute the actual HTTP request with circuit breaker tracking
"""
function _execute_http_request(url::String, max_size::Int, timeout::Int)::Dict{String,Any}
    # Use HTTP.jl with proper timeout instead of curl
    try
        # Parse URL for HTTP request
        url_to_fetch = startswith(url, "http") ? url : "http://$url"
        
        response = HTTP.get(
            url_to_fetch;
            timeout=timeout,
            readtimeout=timeout
        )
        
        # Record success
        if _circuit_breaker_enabled[]
            _record_http_success()
        end
        
        status_code = response.status
        content_type = get(response.headers, "Content-Type", "text/plain")
        body = String(response.body)
        
        # Content type filter
        if !is_content_allowed(content_type)
            return Dict(
                "success"=>false,
                "effect"=>"content_type_blocked",
                "actual_confidence"=>0.0,
                "energy_cost"=>0.01,
                "filter_reason"=>"content type '$(content_type)' not allowed"
            )
        end
        
        # Truncate body to max_size
        snippet = body[1:min(end, max_size)]
        
        # SECURITY: Sanitize output - mask potentially sensitive headers
        sanitized_headers = Dict{String, String}()
        sensitive_keys = ["authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token"]
        for (k, v) in response.headers
            if lowercase(k) ∈ sensitive_keys
                sanitized_headers[k] = "***REDACTED***"
            else
                sanitized_headers[k] = v
            end
        end
        
        return Dict(
            "success"=>true, 
            "effect"=>"fetched", 
            "actual_confidence"=>0.9, 
            "energy_cost"=>0.03,
            "data"=>Dict(
                "status"=>status_code,
                "body_snippet"=>snippet,
                "content_type"=>content_type,
                "headers"=>sanitized_headers,
                "size_truncated"=>length(body) > max_size
            )
        )
    catch e
        # Record failure
        if _circuit_breaker_enabled[]
            _record_http_failure()
        end
        
        return Dict(
            "success"=>false, 
            "effect"=>"http_failed: $(typeof(e))", 
            "actual_confidence"=>0.0, 
            "energy_cost"=>0.0
        )
    end
end

export get_http_circuit_status, reset_http_circuit_breaker

end  # module