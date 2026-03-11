"""
    MarketData.jl - Finance Market Data Module for Itheris

This module provides functions to fetch stock prices, historical data, and income 
statements via the MCP Finance Server. It integrates with the worker capability 
system using Model Context Protocol (MCP) over HTTP.

# API Key Management
- API keys should be set via environment variables at runtime
- For Yahoo Finance: Set `YF_API_KEY` environment variable
- Supports both free (no key) and premium (with key) modes

# MCP Integration
- Communicates with MCP Finance Server via HTTP transport
- Default endpoint: http://localhost:3000
- Configure via `MCP_FINANCE_ENDPOINT` environment variable

# Example Usage
```julia
using MarketData

# Get current stock price
price = get_stock_price("AAPL")

# Get historical data
history = get_historical_data("AAPL", "1mo")

# Get income statement
income = get_income_statement("AAPL")
```
"""
module MarketData

using HTTP
using JSON
using URIs

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default MCP Finance Server endpoint
const DEFAULT_ENDPOINT = "http://localhost:3000"
const DEFAULT_TIMEOUT = 30

# Allowed periods for historical data
const ALLOWED_PERIODS = ["1d", "5d", "1mo", "3mo", "6mo", "1y", "5y", "max"]

# Security: Allowed characters in stock symbols (prevent injection)
const SYMBOL_PATTERN = r"^[A-Z]{1,5}$"

# ============================================================================
# EXPORTS
# ============================================================================

export 
    get_stock_price,
    get_historical_data,
    get_income_statement,
    meta,
    execute

# ============================================================================
# CONFIGURATION FUNCTIONS
# ============================================================================

"""
    get_mcp_endpoint() -> String

Get the MCP Finance Server endpoint from environment or use default.
"""
function get_mcp_endpoint()::String
    return get(ENV, "MCP_FINANCE_ENDPOINT", DEFAULT_ENDPOINT)
end

"""
    get_yf_api_key() -> String

Get the Yahoo Finance API key from environment variable.
Returns empty string if not set (free mode).
"""
function get_yf_api_key()::String
    return get(ENV, "YF_API_KEY", "")
end

"""
    is_premium_mode() -> Bool

Check if running in premium mode (API key provided).
"""
function is_premium_mode()::Bool
    return !isempty(get_yf_api_key())
end

# ============================================================================
# INPUT VALIDATION
# ============================================================================

"""
    validate_symbol(symbol::String) -> Tuple{Bool, String}

Validate and sanitize stock symbol to prevent injection attacks.

Returns:
- Tuple of (is_valid, error_message)
"""
function validate_symbol(symbol::String)::Tuple{Bool, String}
    if isempty(symbol)
        return (false, "Symbol cannot be empty")
    end
    
    # Uppercase and trim
    sanitized = uppercase(strip(symbol))
    
    # Check against allowed pattern
    if !occursin(SYMBOL_PATTERN, sanitized)
        return (false, "Invalid symbol format. Must be 1-5 uppercase letters")
    end
    
    # Additional check: no special characters
    if any(c -> !isletter(c) || islowercase(c), sanitized)
        return (false, "Symbol must contain only uppercase letters")
    end
    
    return (true, "")
end

"""
    validate_period(period::String) -> Tuple{Bool, String}

Validate historical data period parameter.

Returns:
- Tuple of (is_valid, error_message)
"""
function validate_period(period::String)::Tuple{Bool, String}
    if isempty(period)
        return (false, "Period cannot be empty")
    end
    
    sanitized = lowercase(strip(period))
    
    if sanitized ∉ ALLOWED_PERIODS
        return (false, "Invalid period. Allowed: $(join(ALLOWED_PERIODS, ", "))")
    end
    
    return (true, "")
end

# ============================================================================
# MCP COMMUNICATION
# ============================================================================

"""
    make_mcp_request(method::String, params::Dict{String, Any}) -> Dict{String, Any}

Make a JSON-RPC request to the MCP Finance Server.

# Arguments
- `method::String`: The MCP method to call
- `params::Dict{String, Any}`: Parameters for the method

# Returns
- Dictionary with the response data or error information
"""
function make_mcp_request(method::String, params::Dict{String, Any})::Dict{String, Any}
    endpoint = get_mcp_endpoint()
    timeout = DEFAULT_TIMEOUT
    
    # Build MCP JSON-RPC request
    request_body = Dict(
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => method,
        "params" => params
    )
    
    # Add API key if available
    api_key = get_yf_api_key()
    if !isempty(api_key)
        request_body["params"]["api_key"] = api_key
    end
    
    try
        # Make HTTP POST request
        response = HTTP.post(
            endpoint,
            ["Content-Type" => "application/json"],
            JSON.json(request_body);
            timeout=timeout,
            readtimeout=timeout
        )
        
        # Parse response
        if response.status == 200
            response_data = JSON.parse(String(response.body))
            
            # Check for JSON-RPC error
            if haskey(response_data, "error")
                return Dict(
                    "success" => false,
                    "error" => response_data["error"],
                    "error_code" => get(response_data["error"], "code", -1),
                    "error_message" => get(response_data["error"], "message", "Unknown error")
                )
            end
            
            return Dict(
                "success" => true,
                "data" => get(response_data, "result", Dict())
            )
        else
            return Dict(
                "success" => false,
                "error" => "HTTP error",
                "error_code" => response.status,
                "error_message" => "Server returned status $(response.status)"
            )
        end
        
    catch e
        error_type = typeof(e)
        return Dict(
            "success" => false,
            "error" => string(error_type),
            "error_code" => -1,
            "error_message" => "Network error: $( sprint(showerror, e) )"
        )
    end
end

# ============================================================================
# PUBLIC API FUNCTIONS
# ============================================================================

"""
    get_stock_price(symbol::String) -> Dict{String, Any}

Fetch the current stock price for a given symbol.

# Arguments
- `symbol::String`: Stock ticker symbol (e.g., "AAPL", "GOOGL")

# Returns
- Dictionary with:
  - `success::Bool`: Whether the request succeeded
  - `symbol::String`: The stock symbol
  - `price::Float64`: Current stock price (if successful)
  - `currency::String`: Currency code (e.g., "USD")
  - `timestamp::String`: ISO timestamp of the price
  - `error_message::String`: Error description (if failed)

# Example
```julia
result = get_stock_price("AAPL")
if result["success"]
    println("AAPL price: \$(result[\"price\"])")
end
```
"""
function get_stock_price(symbol::String)::Dict{String, Any}
    # Validate input
    valid, error_msg = validate_symbol(symbol)
    if !valid
        return Dict(
            "success" => false,
            "error" => "validation_error",
            "error_message" => error_msg
        )
    end
    
    # Sanitize symbol
    sanitized = uppercase(strip(symbol))
    
    # Make MCP request
    result = make_mcp_request("finance.get_stock_price", Dict("symbol" => sanitized))
    
    # Add metadata to response
    if result["success"]
        return Dict(
            "success" => true,
            "symbol" => sanitized,
            "price" => get(result["data"], "price", 0.0),
            "currency" => get(result["data"], "currency", "USD"),
            "timestamp" => get(result["data"], "timestamp", string(now())),
            "market_status" => get(result["data"], "market_status", "unknown"),
            "source" => "mcp_finance"
        )
    else
        return Dict(
            "success" => false,
            "symbol" => sanitized,
            "error" => get(result, "error", "unknown"),
            "error_message" => get(result, "error_message", "Failed to fetch stock price")
        )
    end
end

"""
    get_historical_data(symbol::String, period::String) -> Dict{String, Any}

Fetch historical stock data for a given symbol and time period.

# Arguments
- `symbol::String`: Stock ticker symbol (e.g., "AAPL", "GOOGL")
- `period::String`: Time period for historical data. Allowed values:
  - "1d" - 1 day
  - "5d" - 5 days
  - "1mo" - 1 month
  - "3mo" - 3 months
  - "6mo" - 6 months
  - "1y" - 1 year
  - "5y" - 5 years
  - "max" - Maximum available

# Returns
- Dictionary with:
  - `success::Bool`: Whether the request succeeded
  - `symbol::String`: The stock symbol
  - `period::String`: The requested period
  - `data::Array`: Array of historical data points
  - `error_message::String`: Error description (if failed)

# Example
```julia
result = get_historical_data("AAPL", "1mo")
if result["success"]
    for day in result["data"]
        println("Date: \$(day[\"date\"]), Close: \$(day[\"close\"])")
    end
end
```
"""
function get_historical_data(symbol::String, period::String)::Dict{String, Any}
    # Validate symbol
    valid, error_msg = validate_symbol(symbol)
    if !valid
        return Dict(
            "success" => false,
            "error" => "validation_error",
            "error_message" => error_msg
        )
    end
    
    # Validate period
    valid, error_msg = validate_period(period)
    if !valid
        return Dict(
            "success" => false,
            "error" => "validation_error",
            "error_message" => error_msg
        )
    end
    
    # Sanitize inputs
    sanitized_symbol = uppercase(strip(symbol))
    sanitized_period = lowercase(strip(period))
    
    # Make MCP request
    result = make_mcp_request(
        "finance.get_historical_data",
        Dict(
            "symbol" => sanitized_symbol,
            "period" => sanitized_period
        )
    )
    
    # Add metadata to response
    if result["success"]
        return Dict(
            "success" => true,
            "symbol" => sanitized_symbol,
            "period" => sanitized_period,
            "data" => get(result["data"], "history", []),
            "metadata" => Dict(
                "period_start" => get(result["data"], "period_start", ""),
                "period_end" => get(result["data"], "period_end", ""),
                "data_points" => length(get(result["data"], "history", []))
            ),
            "source" => "mcp_finance"
        )
    else
        return Dict(
            "success" => false,
            "symbol" => sanitized_symbol,
            "period" => sanitized_period,
            "error" => get(result, "error", "unknown"),
            "error_message" => get(result, "error_message", "Failed to fetch historical data")
        )
    end
end

"""
    get_income_statement(symbol::String) -> Dict{String, Any}

Fetch the income statement data for a given company.

# Arguments
- `symbol::String`: Stock ticker symbol (e.g., "AAPL", "GOOGL")

# Returns
- Dictionary with:
  - `success::Bool`: Whether the request succeeded
  - `symbol::String`: The stock symbol
  - `data::Dict`: Income statement data including:
    - `revenue::Float64`: Total revenue
    - `net_income::Float64`: Net income
    - `operating_income::Float64`: Operating income
    - `eps::Float64`: Earnings per share
    - `period::String`: Reporting period
  - `error_message::String`: Error description (if failed)

# Example
```julia
result = get_income_statement("AAPL")
if result["success"]
    println("Revenue: \$(result[\"data\"][\"revenue\"])")
end
```
"""
function get_income_statement(symbol::String)::Dict{String, Any}
    # Validate input
    valid, error_msg = validate_symbol(symbol)
    if !valid
        return Dict(
            "success" => false,
            "error" => "validation_error",
            "error_message" => error_msg
        )
    end
    
    # Sanitize symbol
    sanitized = uppercase(strip(symbol))
    
    # Make MCP request
    result = make_mcp_request("finance.get_income_statement", Dict("symbol" => sanitized))
    
    # Add metadata to response
    if result["success"]
        return Dict(
            "success" => true,
            "symbol" => sanitized,
            "data" => get(result["data"], "income_statement", Dict()),
            "metadata" => Dict(
                "period" => get(result["data"], "period", ""),
                "fiscal_year" => get(result["data"], "fiscal_year", ""),
                "reported_date" => get(result["data"], "reported_date", "")
            ),
            "source" => "mcp_finance"
        )
    else
        return Dict(
            "success" => false,
            "symbol" => sanitized,
            "error" => get(result, "error", "unknown"),
            "error_message" => get(result, "error_message", "Failed to fetch income statement")
        )
    end
end

# ============================================================================
# MCP INTEGRATION HOOKS
# ============================================================================

"""
    meta() -> Dict{String, Any}

Return metadata about this capability for the MCP registry.
"""
function meta()::Dict{String, Any}
    return Dict(
        "id" => "market_data",
        "name" => "Market Data",
        "description" => "Fetch stock prices, historical data, and income statements from financial data providers",
        "inputs" => Dict(
            "symbol" => "string - Stock ticker symbol (1-5 uppercase letters)",
            "period" => "string - Historical data period (1d, 5d, 1mo, 3mo, 6mo, 1y, 5y, max)"
        ),
        "outputs" => Dict(
            "price" => "float - Current stock price",
            "history" => "array - Historical data points",
            "income_statement" => "dict - Financial statement data"
        ),
        "cost" => 0.05,
        "risk" => "low",
        "reversible" => true,
        "confidence_model" => "empirical",
        "filters" => [
            "symbol_validation - validates stock symbol format",
            "period_validation - validates historical data period",
            "api_key_management - handles API key securely via environment"
        ]
    )
end

"""
    execute(params::Dict{String, Any}) -> Dict{String, Any}

Execute the market data capability based on the provided action parameter.

# Arguments
- `params::Dict{String, Any}`: Dictionary containing:
  - `action::String`: The action to perform ("price", "history", "income")
  - `symbol::String`: Stock ticker symbol
  - `period::String`: (Optional) Historical data period for "history" action

# Returns
- Dictionary with the result or error information
"""
function execute(params::Dict{String, Any})::Dict{String, Any}
    action = get(params, "action", "price")
    symbol = get(params, "symbol", "")
    
    if isempty(symbol)
        return Dict(
            "success" => false,
            "effect" => "missing_symbol",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "error_message" => "Symbol is required"
        )
    end
    
    if action == "price"
        result = get_stock_price(symbol)
    elseif action == "history"
        period = get(params, "period", "1mo")
        result = get_historical_data(symbol, period)
    elseif action == "income"
        result = get_income_statement(symbol)
    else
        return Dict(
            "success" => false,
            "effect" => "invalid_action",
            "actual_confidence" => 0.0,
            "energy_cost" => 0.0,
            "error_message" => "Invalid action. Use: price, history, or income"
        )
    end
    
    # Transform to standard response format
    return Dict(
        "success" => result["success"],
        "effect" => result["success"] ? "data_fetched" : "fetch_failed",
        "actual_confidence" => result["success"] ? 0.9 : 0.0,
        "energy_cost" => 0.05,
        "data" => result
    )
end

end # module
