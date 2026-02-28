"""
    Config - Main configuration struct
"""
struct Config
    environment::String
    llm_provider::String
    llm_model::String
    openclaw_endpoint::String
    log_level::String
    debug_mode::Bool
    
    # Voice settings
    stt_provider::String
    tts_provider::String
    
    # Vision settings
    vlm_provider::String
    
    # Security settings
    require_confirmation::Bool
    max_execution_time::Int
    
    function Config(;environment="development",
                   llm_provider="openai",
                   llm_model="gpt-4",
                   openclaw_endpoint="http://localhost:3000",
                   log_level="info",
                   debug_mode=false,
                   stt_provider="whisper",
                   tts_provider="elevenlabs",
                   vlm_provider="gpt4v",
                   require_confirmation=true,
                   max_execution_time=30)
        new(environment, llm_provider, llm_model, openclaw_endpoint, 
            log_level, debug_mode, stt_provider, tts_provider, 
            vlm_provider, require_confirmation, max_execution_time)
    end
end

"""
    ConfigLoader - Environment-aware configuration
"""
mutable struct ConfigLoader
    base_config::Dict{String, Any}
    environment::String
    
    function ConfigLoader(env::String="development")
        new(Dict{String, Any}(), env)
    end
end

"""
    load_config(env::String="development")::Config
Load configuration for the specified environment
"""
function load_config(env::String="development")::Config
    loader = ConfigLoader(env)
    config_dict = _load_config_files(loader)
    return _dict_to_config(config_dict)
end

"""
    _load_config_files - Load base and environment-specific configs
"""
function _load_config_files(loader::ConfigLoader)::Dict{String, Any}
    # Start with defaults
    config = Dict{String, Any}(
        "environment" => loader.environment,
        "llm_provider" => "openai",
        "llm_model" => "gpt-4",
        "openclaw_endpoint" => "http://localhost:3000",
        "log_level" => "info",
        "debug_mode" => false,
        "stt_provider" => "whisper",
        "tts_provider" => "elevenlabs",
        "vlm_provider" => "gpt4v",
        "require_confirmation" => true,
        "max_execution_time" => 30
    )
    
    # Try to load from config.toml if exists
    config_path = joinpath(pwd(), "config.toml")
    if isfile(config_path)
        try
            toml_config = _read_toml(config_path)
            merge!(config, toml_config)
            @info "Loaded config from $config_path"
        catch e
            @warn "Failed to load config.toml: $e"
        end
    end
    
    # Environment-specific overrides
    env_file = joinpath(pwd(), "config", "environments", "$(loader.environment).toml")
    if isfile(env_file)
        try
            env_config = _read_toml(env_file)
            merge!(config, env_config)
            @info "Loaded environment config from $env_file"
        catch e
            @warn "Failed to load environment config: $e"
        end
    end
    
    return config
end

"""
    _read_toml - Read TOML file (simplified - would use TOML.jl in practice)
"""
function _read_toml(path::String)::Dict{String, Any}
    # Placeholder - in practice would use TOML.jl
    # For now, return empty dict
    return Dict{String, Any}()
end

"""
    _dict_to_config - Convert dict to Config struct
"""
function _dict_to_config(d::Dict{String, Any})::Config
    return Config(
        environment=get(d, "environment", "development"),
        llm_provider=get(d, "llm_provider", "openai"),
        llm_model=get(d, "llm_model", "gpt-4"),
        openclaw_endpoint=get(d, "openclaw_endpoint", "http://localhost:3000"),
        log_level=get(d, "log_level", "info"),
        debug_mode=get(d, "debug_mode", false),
        stt_provider=get(d, "stt_provider", "whisper"),
        tts_provider=get(d, "tts_provider", "elevenlabs"),
        vlm_provider=get(d, "vlm_provider", "gpt4v"),
        require_confirmation=get(d, "require_confirmation", true),
        max_execution_time=get(d, "max_execution_time", 30)
    )
end

"""
    get_required_secrets(config::Config)::Vector{String}
Get list of required secrets for a configuration
"""
function get_required_secrets(config::Config)::Vector{String}
    required = String["LLM_API_KEY"]
    
    if config.stt_provider == "whisper"
        push!(required, "WHISPER_API_KEY")
    end
    
    if config.tts_provider == "elevenlabs"
        push!(required, "ELEVENLABS_API_KEY")
    end
    
    if config.vlm_provider == "gpt4v" || config.llm_provider == "openai"
        push!(required, "OPENAI_API_KEY")
    elseif config.vlm_provider == "claude" || config.llm_provider == "anthropic"
        push!(required, "ANTHROPIC_API_KEY")
    end
    
    return required
end
