# cognition/Vision.jl - Multimodal Reflexes (Vision/Screenshot Layer)
# Upgrade 4: Gives JARVIS "Eyes" - screen-context awareness at speed
# Enables proactive assistance without waiting for user input

module Vision

using Dates
using UUIDs
using Base64
using JSON
using HTTP

# Import types from other cognition modules
include("types.jl")
using ..CognitionTypes

export 
    # Screen context types
    ScreenContext,
    VisionProcessor,
    
    # Core functions
    init_vision_processor,
    capture_screen,
    describe_screen,
    detect_focus_change,
    is_user_stuck,
    get_screen_context,
    start_vision_loop,
    stop_vision_loop,
    get_stuck_duration,
    should_offer_help,
    
    # Integration helpers
    get_screen_context_for_reality,
    check_stuck_with_vision,
    simulate_screen_context

# ============================================================================
# SCREEN CONTEXT STRUCT
# ============================================================================

"""
    ScreenContext - Represents the current screen state and user attention

Fields:
- timestamp: When this context was captured
- screenshot_path: Path to screenshot (or nothing if using base64)
- description: Vision-LLM output describing the screen
- focus_area: Detected area of user focus (e.g., terminal, browser)
- attention_state: Current attention state (:active, :idle, :context_switch)
"""
struct ScreenContext
    timestamp::DateTime
    screenshot_data::Union{Vector{UInt8}, Nothing}  # Raw PNG bytes in memory
    description::String
    focus_area::Union{Dict{Symbol, Any}, Nothing}
    attention_state::Symbol
    
    ScreenContext(
        timestamp::DateTime,
        screenshot_data::Union{Vector{UInt8}, Nothing},
        description::String,
        focus_area::Union{Dict{Symbol, Any}, Nothing},
        attention_state::Symbol
    ) = new(timestamp, screenshot_data, description, focus_area, attention_state)
end

# Convenience constructor with defaults
function ScreenContext(;
    timestamp::DateTime = now(),
    screenshot_data::Union{Vector{UInt8}, Nothing} = nothing,
    description::String = "",
    focus_area::Union{Dict{Symbol, Any}, Nothing} = nothing,
    attention_state::Symbol = :idle
)::ScreenContext
    return ScreenContext(timestamp, screenshot_data, description, focus_area, attention_state)
end

# ============================================================================
# VISION PROCESSOR
# ============================================================================

"""
    VisionProcessor - Handles screen capture and vision-LLM integration

Fields:
- capture_interval: Seconds between captures (default: 2.0)
- last_capture: Timestamp of last capture
- last_description: Last screen description
- context_history: Vector of recent ScreenContext entries
- ollama_endpoint: URL for Ollama API
- vision_model: Name of vision model to use
- enabled: Whether vision is currently enabled
- stuck_detection_threshold: Minutes before considering user "stuck"
"""
mutable struct VisionProcessor
    capture_interval::Float64    # seconds between captures
    last_capture::Union{DateTime, Nothing}
    last_description::String
    context_history::Vector{ScreenContext}
    ollama_endpoint::String
    vision_model::String
    enabled::Bool
    stuck_detection_threshold::Float64  # minutes
    max_history::Int
    
    function VisionProcessor(
        capture_interval::Float64 = 2.0,
        ollama_endpoint::String = "http://localhost:11434/api/generate",
        vision_model::String = "llava";
        stuck_detection_threshold::Float64 = 10.0,
        max_history::Int = 100
    )
        new(
            capture_interval,
            nothing,
            "",
            ScreenContext[],
            ollama_endpoint,
            vision_model,
            false,  # disabled by default until started
            stuck_detection_threshold,
            max_history
        )
    end
end

# ============================================================================
# INITIALIZATION
# ============================================================================

"""
    init_vision_processor(; kwargs...) → VisionProcessor
Initialize a new VisionProcessor with optional configuration.

# Arguments
- `interval::Float64=2.0`: Capture interval in seconds
- `endpoint::String="http://localhost:11434/api/generate"`: Ollama endpoint
- `model::String="llava"`: Vision model name
- `stuck_threshold::Float64=10.0`: Minutes before stuck detection
"""
function init_vision_processor(;
    interval::Float64 = 2.0,
    endpoint::String = "http://localhost:11434/api/generate",
    model::String = "llava",
    stuck_threshold::Float64 = 10.0
)::VisionProcessor
    @info "Initializing Vision Processor" interval endpoint model stuck_threshold
    
    vp = VisionProcessor(
        interval,
        endpoint,
        model;
        stuck_detection_threshold = stuck_threshold
    )
    
    return vp
end

# ============================================================================
# SCREEN CAPTURE
# ============================================================================

"""
    capture_screen() → Union{Vector{UInt8}, Nothing}
Capture a screenshot and return as PNG bytes.
Returns nothing if capture fails (e.g., no display).

This is a placeholder - actual implementation would call into the Rust
memory-bridge for platform-specific screenshot capture.
"""
function capture_screen()::Union{Vector{UInt8}, Nothing}
    # In production, this would call the Rust screenshot function via FFI
    # For now, we'll check if there's a screenshot available from the bridge
    
    try
        # Try to call Rust bridge for screenshot
        # This would be: MemoryBridge.capture_screenshot()
        # For now, return nothing (no screenshot available)
        return nothing
    catch e
        @warn "Screenshot capture failed" exception=e
        return nothing
    end
end

"""
    capture_screen_placeholder() → Vector{UInt8}
Generate a placeholder screenshot for testing.
"""
function capture_screen_placeholder()::Vector{UInt8}
    # Return minimal valid PNG (1x1 transparent)
    return base64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
end

# ============================================================================
# VISION-LLM INTEGRATION
# ============================================================================

"""
    describe_screen(vp::VisionProcessor, image_data::Vector{UInt8}) → String
Send screenshot to vision-LLM and get description.

# Arguments
- vp: VisionProcessor instance
- image_data: PNG bytes of screenshot

# Returns
- One-sentence description of the screen
"""
function describe_screen(vp::VisionProcessor, image_data::Vector{UInt8})::String
    # Skip if vision is disabled or no endpoint
    if !vp.enabled || isempty(vp.ollama_endpoint)
        return "Vision disabled"
    end
    
    try
        # Convert image to base64
        image_b64 = base64encode(image_data)
        
        # Build prompt for concise description
        prompt = """Describe this screen in one sentence. Focus on:
- What application/window is visible
- What the user appears to be doing
- Any errors, warnings, or notable UI elements

Be very concise - one sentence only."""
        
        # Call Ollama API
        response = HTTP.post(
            vp.ollama_endpoint,
            JSON.json(Dict(
                "model" => vp.vision_model,
                "prompt" => prompt,
                "images" => [image_b64],
                "stream" => false,
                "options" => Dict(
                    "temperature" => 0.3,  # Low temperature for consistent output
                    "num_predict" => 100   # Short response
                )
            )),
            ["Content-Type" => "application/json"]
        )
        
        # Parse response
        result = JSON.parse(String(response.body))
        description = get(result, "response", "")
        
        # Clean up description (take first sentence only)
        description = strip(description)
        if occursin('.', description)
            description = split(description, '.')[1] * "."
        end
        
        return description
        
    catch e
        @warn "Vision-LLM description failed" exception=e
        return "Unable to describe screen"
    end
end

"""
    describe_screen_fallback(vp::VisionProcessor, image_data::Vector{UInt8}) → String
Fallback pixel-difference based description when vision-LLM unavailable.
"""
function describe_screen_fallback(vp::VisionProcessor, image_data::Vector{UInt8})::String
    # Simple heuristic: analyze image statistics
    # In a real implementation, this would do proper pixel analysis
    
    if isempty(image_data)
        return "No screen data available"
    end
    
    # Very basic heuristic based on data size
    # Real implementation would do actual pixel analysis
    size_hint = length(image_data)
    
    if size_hint < 1000
        return "Blank or minimal screen"
    elseif size_hint < 50000
        return "Simple application window"
    else
        return "Complex screen with multiple elements"
    end
end

# ============================================================================
# FOCUS DETECTION
# ============================================================================

"""
    detect_focus_change(vp::VisionProcessor, prev::ScreenContext, current::ScreenContext) → Symbol
Detect if user has changed focus between two screen contexts.

# Returns
- :context_switch if focus changed significantly
- :active if user is actively working
- :idle if no significant activity
"""
function detect_focus_change(
    vp::VisionProcessor, 
    prev::ScreenContext, 
    current::ScreenContext
)::Symbol
    
    # If either context has no description, can't determine
    if isempty(prev.description) || isempty(current.description)
        return :idle
    end
    
    # Compare descriptions for major changes
    prev_words = Set(split(lowercase(prev.description)))
    current_words = Set(split(lowercase(current.description)))
    
    # Calculate word overlap
    overlap = length(intersect(prev_words, current_words))
    total = length(union(prev_words, current_words))
    
    similarity = total > 0 ? overlap / total : 0.0
    
    if similarity < 0.3
        # Major change - context switch
        return :context_switch
    elseif similarity < 0.7
        # Some change but still related - active
        return :active
    else
        # Very similar - could be idle or same task
        return :active
    end
end

"""
    detect_focus_area(description::String) → Union{Dict{Symbol, Any}, Nothing}
Parse description to extract likely focus area.
"""
function detect_focus_area(description::String)::Union{Dict{Symbol, Any}, Nothing}
    description_lower = lowercase(description)
    
    # Common application patterns
    focus = nothing
    
    if contains(description_lower, "terminal") || contains(description_lower, "command")
        focus = Dict(:app => :terminal, :type => :development)
    elseif contains(description_lower, "browser") || contains(description_lower, "web")
        focus = Dict(:app => :browser, :type => :browsing)
    elseif contains(description_lower, "code") || contains(description_lower, "editor")
        focus = Dict(:app => :editor, :type => :development)
    elseif contains(description_lower, "error") || contains(description_lower, "exception")
        focus = Dict(:app => :error, :type => :problem)
    elseif contains(description_lower, "terminal") && contains(description_lower, "error")
        focus = Dict(:app => :terminal, :type => :problem)
    end
    
    return focus
end

# ============================================================================
# STUCK DETECTION
# ============================================================================

"""
    is_user_stuck(vp::VisionProcessor; duration::Float64 = vp.stuck_detection_threshold) → Bool
Detect if user appears to be stuck on the same screen context.

# Arguments
- vp: VisionProcessor
- duration: Minutes to consider stuck (defaults to vp.stuck_detection_threshold)

# Returns
- true if user appears stuck (same context for > duration minutes)
"""
function is_user_stuck(
    vp::VisionProcessor; 
    duration::Float64 = vp.stuck_detection_threshold
)::Bool
    
    if length(vp.context_history) < 2
        return false
    end
    
    # Check recent contexts
    now = now()
    threshold = Minute(round(Int, duration))
    
    # Find contexts within the duration window
    recent_contexts = filter(ctx -> (now - ctx.timestamp) < threshold, vp.context_history)
    
    if length(recent_contexts) < 2
        return false
    end
    
    # Check if all recent contexts have similar descriptions
    descriptions = [ctx.description for ctx in recent_contexts]
    
    # If all descriptions are the same, user is stuck
    unique_descriptions = unique(descriptions)
    
    if length(unique_descriptions) == 1 && !isempty(descriptions[1])
        # Check if it's a problem context (contains error-like terms)
        desc_lower = lowercase(first(descriptions))
        if contains(desc_lower, "error") || contains(desc_lower, "fail") || 
           contains(desc_lower, "exception") || contains(desc_lower, "warning")
            return true
        end
    end
    
    return false
end

"""
    get_stuck_duration(vp::VisionProcessor) → Float64
Get how long the user has been in the current context (in minutes).
"""
function get_stuck_duration(vp::VisionProcessor)::Float64
    if isempty(vp.context_history)
        return 0.0
    end
    
    current = vp.context_history[end]
    duration = now() - current.timestamp
    
    return Minutes(duration) / 60.0
end

# ============================================================================
# CONTEXT MANAGEMENT
# ============================================================================

"""
    get_screen_context(vp::VisionProcessor) → Union{ScreenContext, Nothing}
Get the most recent screen context.
"""
function get_screen_context(vp::VisionProcessor)::Union{ScreenContext, Nothing}
    if isempty(vp.context_history)
        return nothing
    end
    
    return vp.context_history[end]
end

"""
    update_vision_context!(vp::VisionProcessor)
Capture and process current screen context.
This should be called periodically by the vision loop.
"""
function update_vision_context!(vp::VisionProcessor)
    # Capture screenshot
    screenshot = capture_screen()
    
    if screenshot === nothing
        # Try placeholder for testing
        screenshot = capture_screen_placeholder()
    end
    
    # Get description
    description = describe_screen(vp, screenshot)
    
    # Detect focus area
    focus_area = detect_focus_area(description)
    
    # Determine attention state
    attention_state = :idle
    
    if !isempty(vp.context_history)
        prev = vp.context_history[end]
        current_desc = ScreenContext(
            timestamp = now(),
            screenshot_data = screenshot,
            description = description,
            focus_area = focus_area,
            attention_state = :idle
        )
        attention_state = detect_focus_change(vp, prev, current_desc)
    end
    
    # Create new context
    context = ScreenContext(
        timestamp = now(),
        screenshot_data = screenshot,
        description = description,
        focus_area = focus_area,
        attention_state = attention_state
    )
    
    # Update processor state
    vp.last_capture = now()
    vp.last_description = description
    
    # Add to history (with pruning)
    push!(vp.context_history, context)
    
    if length(vp.context_history) > vp.max_history
        vp.context_history = vp.context_history[end - vp.max_history + 1:end]
    end
    
    return context
end

# ============================================================================
# VISION LOOP
# ============================================================================

# Task reference for the vision loop
const _vision_task = Ref{Union{Task, Nothing}}(nothing)

"""
    start_vision_loop(vp::VisionProcessor)
Start the background vision capture loop.
"""
function start_vision_loop(vp::VisionProcessor)
    if vp.enabled
        @warn "Vision loop already running"
        return
    end
    
    vp.enabled = true
    
    # Create background task
    _vision_task[] = @async begin
        while vp.enabled
            try
                update_vision_context!(vp)
            catch e
                @error "Vision loop error" exception=e
            end
            
            # Sleep for capture interval
            sleep(vp.capture_interval)
        end
    end
    
    @info "Vision loop started" interval=vp.capture_interval
end

"""
    stop_vision_loop(vp::VisionProcessor)
Stop the background vision capture loop.
"""
function stop_vision_loop(vp::VisionProcessor)
    vp.enabled = false
    
    if _vision_task[] !== nothing
        try
            wait(_vision_task[])
        catch
            # Task may have already finished
        end
        _vision_task[] = nothing
    end
    
    @info "Vision loop stopped"
end

# ============================================================================
# INTEGRATION HELPERS
# ============================================================================

"""
    get_screen_context_for_reality(vp::VisionProcessor) → Dict{Symbol, Any}
Convert screen context to a reality-compatible format.
"""
function get_screen_context_for_reality(vp::VisionProcessor)::Dict{Symbol, Any}
    context = get_screen_context(vp)
    
    if context === nothing
        return Dict{Symbol, Any}()
    end
    
    return Dict(
        :timestamp => context.timestamp,
        :description => context.description,
        :focus_area => context.focus_area,
        :attention_state => context.attention_state,
        :is_stuck => is_user_stuck(vp),
        :stuck_duration => get_stuck_duration(vp)
    )
end

"""
    check_stuck_with_vision(vp::VisionProcessor) → Tuple{Bool, String}
Check if user is stuck and generate appropriate help offer.
Returns (is_stuck, help_message)
"""
function check_stuck_with_vision(vp::VisionProcessor)::Tuple{Bool, String}
    if !is_user_stuck(vp)
        return false, ""
    end
    
    stuck_duration = get_stuck_duration(vp)
    context = get_screen_context(vp)
    
    if context === nothing
        return true, "I notice you've been at the same screen for $(round(stuck_duration, digits=1)) minutes. Would you like some help?"
    end
    
    # Generate contextual help message
    desc = context.description
    
    if contains(lowercase(desc), "error")
        return true, "I see you're looking at an error. Would you like me to help analyze it?"
    elseif contains(lowercase(desc), "fail")
        return true, "Something seems to have failed. Want me to help debug?"
    elseif contains(lowercase(desc), "exception")
        return true, "There's an exception on screen. Shall I help trace it?"
    else
        return true, "You've been on this screen for $(round(stuck_duration, digits=1)) minutes. Need any help?"
    end
end

# ============================================================================
# PROACTIVE ASSISTANCE
# ============================================================================

"""
    should_offer_help(vp::VisionProcessor) → Tuple{Bool, String}
Determine if JARVIS should proactively offer help.
"""
function should_offer_help(vp::VisionProcessor)::Tuple{Bool, String}
    # Don't offer if idle
    context = get_screen_context(vp)
    
    if context === nothing
        return false, ""
    end
    
    if context.attention_state == :idle
        return false, ""
    end
    
    # Check if stuck
    is_stuck, message = check_stuck_with_vision(vp)
    
    if is_stuck
        return true, message
    end
    
    # Check for context switching patterns
    if length(vp.context_history) >= 5
        recent_states = [ctx.attention_state for ctx in vp.context_history[end-4:end]]
        
        # If many context switches, offer to save state
        switch_count = count(==(:context_switch), recent_states)
        
        if switch_count >= 3
            return true, "You seem to be switching between tasks frequently. Want me to help organize your work?"
        end
    end
    
    return false, ""
end

# ============================================================================
# TESTING UTILITIES
# ============================================================================

"""
    simulate_screen_context(vp::VisionProcessor, description::String)
Add a simulated screen context for testing.
"""
function simulate_screen_context(vp::VisionProcessor, description::String)
    focus_area = detect_focus_area(description)
    
    attention_state = :active
    if !isempty(vp.context_history)
        prev = vp.context_history[end]
        current = ScreenContext(
            timestamp = now(),
            screenshot_data = UInt8[],
            description = description,
            focus_area = focus_area,
            attention_state = :active
        )
        attention_state = detect_focus_change(vp, prev, current)
    end
    
    context = ScreenContext(
        timestamp = now(),
        screenshot_data = UInt8[],
        description = description,
        focus_area = focus_area,
        attention_state = attention_state
    )
    
    push!(vp.context_history, context)
    vp.last_description = description
    vp.last_capture = now()
    
    if length(vp.context_history) > vp.max_history
        vp.context_history = vp.context_history[end - vp.max_history + 1:end]
    end
end

end # module Vision
