# llm/config.jl - LLM Configuration Loader
# Reads LLM config from config.toml and creates appropriate clients

module LLMConfig

using Pkg.TOML
using Logging
using UUIDs

# Import client modules
include("client.jl")
include("openai.jl")
include("ollama.jl")
using ..LLMClientModule: AbstractLLMClient
using ..OpenAIClientModule: OpenAIClient, DEFAULT_OPENAI_MODEL
using ..OllamaClientModule: OllamaClient, DEFAULT_OLLAMA_BASE_URL, DEFAULT_OLLAMA_MODEL, check_ollama_running

export LLMConfig, load_llm_config
export create_llm_client, get_default_provider

# ============================================================================
# Constants
# ============================================================================

const DEFAULT_CONFIG_PATH = joinpath(pwd(), "config.toml")
const CONFIG_PATH_ENV = "PROJECTX_CONFIG_PATH"

# ============================================================================
# Config Types
# ============================================================================

"""
    LLMProvider

Enum for supported LLM providers.
"""
@enum LLMProvider begin
    OPENAI = 1
    OLLAMA = 2
    ANTHROPIC = 3
    LOCAL = 4  # Placeholder for other local providers
end

"""
    LLMConfig

Configuration for LLM integration.
"""
struct LLMConfig
    provider::LLMProvider
    model::String
    api_key::String
    base_url::String
    temperature::Float64
    max_tokens::Int
    top_p::Float64
    timeout::Float64
    config_path::String
    
    function LLMConfig(;
        provider::Symbol=:ollama,  # Default to ollama for no API cost
        model::String=DEFAULT_OLLAMA_MODEL,
        api_key::String="",
        base_url::String=DEFAULT_OLLAMA_BASE_URL,
        temperature::Float64=0.7,
        max_tokens::Int=2000,
        top_p::Float64=0.9,
        timeout::Float64=120.0,
        config_path::String=DEFAULT_CONFIG_PATH
    )
        provider_enum = if provider == :openai
            OPENAI
        elseif provider == :ollama
            OLLAMA
        elseif provider == :anthropic
            ANTHROPIC
        else
            LOCAL
        end
        
        new(provider_enum, model, api_key, base_url, temperature, max_tokens, top_p, timeout, config_path)
    end
end

# ============================================================================
# Config Loading
# ============================================================================

"""
    load_llm_config(path::String=DEFAULT_CONFIG_PATH) -> LLMConfig

Load LLM configuration from config.toml file.
"""
function load_llm_config(path::String=DEFAULT_CONFIG_PATH)::LLMConfig
    # Check environment variable first
    config_path = get(ENV, CONFIG_PATH_ENV, path)
    
    if !isfile(config_path)
        @warn "Config file not found: $config_path. Using defaults."
        return LLMConfig()
    end
    
    try
        config = TOML.parsefile(config_path)
        
        # Get LLM section (try both "llm" and "llm_config" for compatibility)
        llm_section = get(config, "llm", get(config, "llm_config", Dict()))
        
        if isempty(llm_section)
            @warn "No [llm] section found in config. Using defaults."
            return LLMConfig(; config_path=config_path)
        end
        
        # Parse provider
        provider_str = lowercase(get(llm_section, "provider", "ollama"))
        provider = Symbol(provider_str)
        
        # Get API key - check environment variable as fallback
        api_key = get(llm_section, "api_key", "")
        if isempty(api_key)
            if provider == :openai
                api_key = get(ENV, "OPENAI_API_KEY", "")
            elseif provider == :anthropic
                api_key = get(ENV, "ANTHROPIC_API_KEY", "")
            end
        end
        
        # Get model - use defaults based on provider
        model = get(llm_section, "model", "")
        if isempty(model)
            if provider == :openai
                model = DEFAULT_OPENAI_MODEL
            else
                model = DEFAULT_OLLAMA_MODEL
            end
        end
        
        # Get base URL for OpenAI-compatible APIs
        base_url = get(llm_section, "base_url", "")
        if isempty(base_url)
            if provider == :openai
                base_url = "https://api.openai.com/v1"
            else
                base_url = DEFAULT_OLLAMA_BASE_URL
            end
        end
        
        # Parse numeric options
        temperature = tryparse(Float64, get(llm_section, "temperature", "0.7"))
        temperature = temperature !== nothing ? temperature : 0.7
        
        max_tokens = tryparse(Int, get(llm_section, "max_tokens", "2000"))
        max_tokens = max_tokens !== nothing ? max_tokens : 2000
        
        top_p = tryparse(Float64, get(llm_section, "top_p", "0.9"))
        top_p = top_p !== nothing ? top_p : 0.9
        
        timeout = tryparse(Float64, get(llm_section, "timeout", "120.0"))
        timeout = timeout !== nothing ? timeout : 120.0
        
        @info "Loaded LLM config" provider=provider model=model base_url=base_url
        
        return LLMConfig(;
            provider=provider,
            model=model,
            api_key=api_key,
            base_url=base_url,
            temperature=temperature,
            max_tokens=max_tokens,
            top_p=top_p,
            timeout=timeout,
            config_path=config_path
        )
        
    catch e
        @error "Failed to parse config file" path=config_path exception=e
        return LLMConfig(; config_path=config_path)
    end
end

"""
    load_llm_config_from_dict(config::Dict) -> LLMConfig

Load LLM configuration from a Dict (for programmatic config).
"""
function load_llm_config_from_dict(config::Dict)::LLMConfig
    provider_str = lowercase(get(config, "provider", "ollama"))
    provider = Symbol(provider_str)
    
    api_key = get(config, "api_key", "")
    model = get(config, "model", provider == :openai ? DEFAULT_OPENAI_MODEL : DEFAULT_OLLAMA_MODEL)
    base_url = get(config, "base_url", provider == :openai ? "https://api.openai.com/v1" : DEFAULT_OLLAMA_BASE_URL)
    temperature = get(config, "temperature", 0.7)
    max_tokens = get(config, "max_tokens", 2000)
    top_p = get(config, "top_p", 0.9)
    timeout = get(config, "timeout", 120.0)
    
    return LLMConfig(;
        provider=provider,
        model=model,
        api_key=api_key,
        base_url=base_url,
        temperature=temperature,
        max_tokens=max_tokens,
        top_p=top_p,
        timeout=timeout
    )
end

# ============================================================================
# Client Creation
# ============================================================================

"""
    create_llm_client(config::LLMConfig) -> Union{AbstractLLMClient, Nothing}

Create an LLM client from configuration.
Tries to create the best available client based on config.
"""
function create_llm_client(config::LLMConfig)::Union{AbstractLLMClient, Nothing}
    if config.provider == OPENAI
        return create_openai_client(config)
    elseif config.provider == OLLAMA
        return create_ollama_client(config)
    else
        @warn "Unsupported provider: $(config.provider). Trying Ollama as fallback."
        return create_ollama_client_fallback(config)
    end
end

"""
    create_openai_client(config::LLMConfig) -> Union{OpenAIClient, Nothing}
"""
function create_openai_client(config::LLMConfig)::Union{OpenAIClient, Nothing}
    if isempty(config.api_key)
        @warn "OpenAI API key not configured. Set OPENAI_API_KEY or provide api_key in config."
        return nothing
    end
    
    try
        client = OpenAIClient(
            config.api_key;
            base_url=config.base_url,
            model=config.model,
            timeout=config.timeout
        )
        
        @info "Created OpenAI client" model=config.model
        return client
        
    catch e
        @error "Failed to create OpenAI client" exception=e
        return nothing
    end
end

"""
    create_ollama_client(config::LLMConfig) -> Union{OllamaClient, Nothing}
"""
function create_ollama_client(config::LLMConfig)::Union{OllamaClient, Nothing}
    if !check_ollama_running(config.base_url)
        @warn "Ollama not running at $(config.base_url). Start with: ollama serve"
        return nothing
    end
    
    try
        client = OllamaClient(
            config.base_url,
            config.model;
            timeout=config.timeout
        )
        
        @info "Created Ollama client" model=config.model base_url=config.base_url
        return client
        
    catch e
        @error "Failed to create Ollama client" exception=e
        return nothing
    end
end

"""
    create_ollama_client_fallback(config::LLMConfig) -> Union{OllamaClient, Nothing}

Try to create an Ollama client as fallback.
"""
function create_ollama_client_fallback(config::LLMConfig)::Union{OllamaClient, Nothing}
    # Try default Ollama settings
    if check_ollama_running()
        return create_ollama_client(LLMConfig())
    end
    
    # Try with configured base_url
    if config.base_url != DEFAULT_OLLAMA_BASE_URL
        if check_ollama_running(config.base_url)
            return create_ollama_client(config)
        end
    end
    
    @warn "No LLM client available. Install Ollama or configure OpenAI."
    return nothing
end

"""
    create_llm_client_auto(; config_path::String=DEFAULT_CONFIG_PATH) -> Union{AbstractLLMClient, Nothing}

Automatically create the best available LLM client.
Priority: Ollama (local, free) > OpenAI
"""
function create_llm_client_auto(; config_path::String=DEFAULT_CONFIG_PATH)::Union{AbstractLLMClient, Nothing}
    # Try loading from config
    config = load_llm_config(config_path)
    
    # Try to create the configured client
    client = create_llm_client(config)
    if client !== nothing
        return client
    end
    
    # Fallback: Try Ollama with defaults
    if check_ollama_running()
        @info "Using Ollama with default settings"
        return OllamaClient()
    end
    
    # Fallback: Try OpenAI if API key available
    api_key = get(ENV, "OPENAI_API_KEY", "")
    if !isempty(api_key)
        @info "Using OpenAI with environment API key"
        return OpenAIClient(api_key)
    end
    
    @error "No LLM client available. Configure Ollama or OpenAI."
    return nothing
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    get_default_provider() -> Symbol

Get the default provider (ollama for no cost).
"""
function get_default_provider()::Symbol
    if check_ollama_running()
        return :ollama
    else
        return :openai
    end
end

"""
    is_llm_available(config::LLMConfig) -> Bool

Check if the configured LLM is available.
"""
function is_llm_available(config::LLMConfig)::Bool
    client = create_llm_client(config)
    if client === nothing
        return false
    end
    
    try
        return is_available(client)
    catch e
        return false
    end
end

"""
    get_provider_name(provider::LLMProvider) -> String

Get human-readable provider name.
"""
function get_provider_name(provider::LLMProvider)::String
    if provider == OPENAI
        return "OpenAI"
    elseif provider == OLLAMA
        return "Ollama"
    elseif provider == ANTHROPIC
        return "Anthropic"
    else
        return "Local"
    end
end

"""
    get_available_models(config::LLMConfig) -> Vector{String}

Get list of available models for the configured provider.
"""
function get_available_models(config::LLMConfig)::Vector{String}
    client = create_llm_client(config)
    if client === nothing
        return String[]
    end
    
    try
        return list_models(client)
    catch e
        @warn "Failed to list models" exception=e
        return [config.model]
    end
end

# ============================================================================
# Global Client Management
# ============================================================================

# Global client instance
const _global_client = Ref{Union{AbstractLLMClient, Nothing}}(nothing)
const _global_config = Ref{Union{LLMConfig, Nothing}}(nothing)

"""
    set_global_client(client::AbstractLLMClient, config::LLMConfig)

Set the global LLM client.
"""
function set_global_client(client::AbstractLLMClient, config::LLMConfig)
    _global_client[] = client
    _global_config[] = config
    @info "Global LLM client set" provider=get_provider_name(config.provider) model=config.model
end

"""
    get_global_client() -> Union{AbstractLLMClient, Nothing}

Get the global LLM client.
"""
function get_global_client()::Union{AbstractLLMClient, Nothing}
    return _global_client[]
end

"""
    get_global_config() -> Union{LLMConfig, Nothing}

Get the global LLM config.
"""
function get_global_config()::Union{LLMConfig, Nothing}
    return _global_config[]
end

"""
    init_llm(; config_path::String=DEFAULT_CONFIG_PATH) -> Bool

Initialize the global LLM client. Returns true if successful.
"""
function init_llm(; config_path::String=DEFAULT_CONFIG_PATH)::Bool
    client = create_llm_client_auto(; config_path=config_path)
    
    if client !== nothing
        config = load_llm_config(config_path)
        set_global_client(client, config)
        return true
    end
    
    return false
end

end # module
