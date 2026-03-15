# VisionLanguageModel.jl must be included before this file

"""
    VisionRiskFilter - Block sensitive content before VLM
"""
struct VisionRiskFilter
    blocked_patterns::Vector{Regex}
    
    function VisionRiskFilter()
        new([
            # SSN patterns (US) - matches xxx-xx-xxxx, xxx xx xxxx, xxxxxxxxx
            r"\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b",
            # Credit cards - matches 16-digit cards with optional separators
            r"\b(?:\d{4}[-\s]?){3}\d{4}\b",
            # Password variations (case-insensitive) - matches password=, passwd:, pwd etc.
            r"(?i)\b(passwd|password|pwd|pass)\b[:=]\S+",
            # API keys and secrets (case-insensitive) - matches api_key=, secret-key:, access_token etc.
            r"(?i)(api[_-]?key|secret[_-]?key|access[_-]?token)\b[:=]\S+",
            # Email addresses
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
            # Phone numbers (US) - matches various formats: (555) 555-5555, 555-555-5555, +1 555 555 5555
            r"\b(?:\+?1[-. \s]?)?\(?[0-9]{3}\)?[-. \s]?[0-9]{3}[-. \s]?[0-9]{4}\b"
        ])
    end
end

"""
    check_risk(image_data::Vector{UInt8}, filter::VisionRiskFilter)::Bool
Check if image contains risky content (simplified - would use OCR in production)
"""
function check_risk(image_data::Vector{UInt8}, filter::VisionRiskFilter)::Bool
    # In production, would first extract text from image and check against patterns
    # For now, return false (no risk detected)
    return false
end

"""
    ImagePipeline - From camera/file to VLM analysis
"""
mutable struct ImagePipeline
    vlm::VLMClient
    preprocessor::Any  # ImagePreprocessor
    risk_filter::VisionRiskFilter
    
    function ImagePipeline(;vlm::VLMClient=GPT4VClient())
        new(vlm, nothing, VisionRiskFilter())
    end
end

"""
    analyze(pipeline::ImagePipeline, image_data::Vector{UInt8}, prompt::String)::VisionResult
Analyze image through VLM with risk filtering
"""
function analyze(pipeline::ImagePipeline, image_data::Vector{UInt8}, prompt::String)::VisionResult
    # Check for risky content first
    if check_risk(image_data, pipeline.risk_filter)
        return VisionResult(
            description="[Image blocked - sensitive content detected]",
            objects=String[],
            text_detected="",
            confidence=0.0f0
        )
    end
    
    # Analyze with VLM
    return analyze_image(pipeline.vlm, image_data, prompt)
end

"""
    analyze_file(pipeline::ImagePipeline, image_path::String, prompt::String)::VisionResult
Load and analyze image file
"""
function analyze_file(pipeline::ImagePipeline, image_path::String, prompt::String)::VisionResult
    if !isfile(image_path)
        return VisionResult(
            description="[Image file not found: $image_path]",
            objects=String[],
            text_detected="",
            confidence=0.0f0
        )
    end
    
    # Read file
    image_data = read(image_path)
    
    # Analyze
    return analyze(pipeline, image_data, prompt)
end

"""
    get_client_name(pipeline::ImagePipeline)::String
Get the name of the VLM client being used
"""
function get_client_name(pipeline::ImagePipeline)::String
    return typeof(pipeline.vlm).name.name
end
