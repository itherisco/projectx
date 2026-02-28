"""
    VoicePipeline - Coordinates STT → Cognition → TTS flow

This module provides a unified voice pipeline that coordinates:
1. Speech-to-Text (Whisper) for input
2. Text-to-Speech (ElevenLabs) for output
3. Complete voice interaction loops

# Example
```julia
using JARVIS

# Create voice pipeline
pipeline = VoicePipeline(mode=STREAMING)

# Process voice input
audio_input = read("input.wav")
text = process_voice_input(pipeline, audio_input)

# Process voice output
audio_output = process_voice_output(pipeline, "Hello, I am JARVIS!")

# Run complete voice loop
audio_input_fn = () -> read("input.wav")
audio_output_fn = audio -> write("output.mp3", audio)
result_text = voice_loop(pipeline, audio_input_fn, audio_output_fn)
```
"""
@enum VoiceMode STREAMING BATCH

"""
    VoicePipeline

Coordinates STT and TTS for complete voice interactions.

# Fields
- `stt::WhisperSTT`: Speech-to-text engine
- `tts::ElevenLabsTTS`: Text-to-speech engine
- `mode::VoiceMode`: Processing mode (STREAMING or BATCH)
- `audio_buffer::Vector{UInt8}`: Buffer for accumulating audio chunks
- `sample_rate::Int`: Audio sample rate (default 16000)
- `channels::Int`: Number of audio channels (default 1 for mono)
"""
mutable struct VoicePipeline
    stt::WhisperSTT
    tts::ElevenLabsTTS
    mode::VoiceMode
    audio_buffer::Vector{UInt8}
    sample_rate::Int
    channels::Int
    
    function VoicePipeline(;mode::VoiceMode=STREAMING,
                          sample_rate::Int=16000,
                          channels::Int=1)
        stt = WhisperSTT()
        tts = ElevenLabsTTS()
        new(stt, tts, mode, Vector{UInt8}(), sample_rate, channels)
    end
end

"""
    process_voice_input(pipeline::VoicePipeline, audio_data::Vector{UInt8})::String

Process audio input through STT to get text.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `audio_data::Vector{UInt8}`: Raw audio bytes

# Returns
- `String`: Transcribed text
"""
function process_voice_input(pipeline::VoicePipeline, audio_data::Vector{UInt8})::String
    if isempty(audio_data)
        @warn "Empty audio data provided to process_voice_input"
        return ""
    end
    
    # For streaming mode, accumulate audio
    if pipeline.mode == STREAMING
        # In streaming mode, we would typically accumulate chunks
        # For now, just process the current chunk
        append!(pipeline.audio_buffer, audio_data)
        return transcribe(pipeline.audio_buffer, pipeline.stt)
    else
        # In batch mode, process directly
        return transcribe(audio_data, pipeline.stt)
    end
end

"""
    process_voice_output(pipeline::VoicePipeline, text::String)::Vector{UInt8}

Process text through TTS to get audio output.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `text::String`: Text to convert to speech

# Returns
- `Vector{UInt8}`: Audio bytes
"""
function process_voice_output(pipeline::VoicePipeline, text::String)::Vector{UInt8}
    if isempty(text)
        @warn "Empty text provided to process_voice_output"
        return UInt8[]
    end
    
    return speak(text, pipeline.tts)
end

"""
    voice_loop(pipeline::VoicePipeline, audio_input_fn::Function, audio_output_fn::Function)

Run a complete voice interaction loop.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `audio_input_fn::Function`: Function that returns audio input bytes
- `audio_output_fn::Function`: Function that accepts audio output bytes

# Returns
- `String`: Transcribed text from input (for cognition processing)

# Notes
This function:
1. Gets audio input via audio_input_fn
2. Transcribes to text via STT
3. Returns text for cognition (cognition not handled here)
4. If you want full loop with TTS response, use voice_loop_with_response
"""
function voice_loop(pipeline::VoicePipeline, audio_input_fn::Function, audio_output_fn::Function)
    # 1. Get audio input
    audio = audio_input_fn()
    
    if isempty(audio)
        @warn "No audio received from input function"
        return ""
    end
    
    # 2. Transcribe to text
    text = process_voice_input(pipeline, audio)
    
    return text
end

"""
    voice_loop_with_response(pipeline::VoicePipeline, audio_input_fn::Function, audio_output_fn::Function)

Run complete voice interaction loop with TTS response.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `audio_input_fn::Function`: Function that returns audio input bytes
- `audio_output_fn::Function`: Function that accepts audio output bytes

# Returns
- `String`: Transcribed text from input
"""
function voice_loop_with_response(pipeline::VoicePipeline, audio_input_fn::Function, audio_output_fn::Function)
    # 1. Get audio input
    audio = audio_input_fn()
    
    if isempty(audio)
        @warn "No audio received from input function"
        return ""
    end
    
    # 2. Transcribe to text
    text = process_voice_input(pipeline, audio)
    
    # Note: In a full implementation, this is where cognition would process the text
    # and generate a response. For now, we just return the transcribed text.
    # The caller would need to process through cognition and get a response.
    
    return text
end

"""
    stream_audio_chunk(pipeline::VoicePipeline, audio_chunk::Vector{UInt8})::String

Process a streaming audio chunk and return text when complete.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `audio_chunk::Vector{UInt8}`: Audio chunk bytes

# Returns
- `String`: Transcribed text (may be empty if more chunks expected)
"""
function stream_audio_chunk(pipeline::VoicePipeline, audio_chunk::Vector{UInt8})::String
    if pipeline.mode != STREAMING
        @warn "stream_audio_chunk called but pipeline is not in STREAMING mode"
        return ""
    end
    
    # Accumulate audio chunk
    append!(pipeline.audio_buffer, audio_chunk)
    
    # In a real implementation, you'd have logic to detect speech segments
    # and only transcribe when a complete segment is detected
    # For now, just transcribe the accumulated buffer
    
    if length(pipeline.audio_buffer) > 1000  # Minimum buffer size threshold
        text = transcribe(pipeline.audio_buffer, pipeline.stt)
        # Clear buffer after transcription
        empty!(pipeline.audio_buffer)
        return text
    end
    
    return ""
end

"""
    clear_buffer(pipeline::VoicePipeline)

Clear the audio buffer.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
"""
function clear_buffer(pipeline::VoicePipeline)
    empty!(pipeline.audio_buffer)
end

"""
    get_buffer_size(pipeline::VoicePipeline)::Int

Get current audio buffer size.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance

# Returns
- `Int`: Number of bytes in buffer
"""
function get_buffer_size(pipeline::VoicePipeline)::Int
    return length(pipeline.audio_buffer)
end

"""
    is_stt_available(pipeline::VoicePipeline)::Bool

Check if STT is available.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance

# Returns
- `Bool`: True if STT is configured and available
"""
function is_stt_available(pipeline::VoicePipeline)::Bool
    return is_available(pipeline.stt)
end

"""
    is_tts_available(pipeline::VoicePipeline)::Bool

Check if TTS is available.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance

# Returns
- `Bool`: True if TTS is configured and available
"""
function is_tts_available(pipeline::VoicePipeline)::Bool
    return is_available(pipeline.tts)
end

"""
    set_voice(pipeline::VoicePipeline, voice_id::String)

Set the TTS voice.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `voice_id::String`: ElevenLabs voice ID
"""
function set_voice(pipeline::VoicePipeline, voice_id::String)
    pipeline.tts = ElevenLabsTTS(voice_id=voice_id)
end

"""
    set_language(pipeline::VoicePipeline, language::String)

Set the STT language.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `language::String`: Language code (e.g., "en", "es", "fr")
"""
function set_language(pipeline::VoicePipeline, language::String)
    pipeline.stt = WhisperSTT(language=language)
end

"""
    set_mode(pipeline::VoicePipeline, mode::VoiceMode)

Set the voice pipeline mode.

# Arguments
- `pipeline::VoicePipeline`: VoicePipeline instance
- `mode::VoiceMode`: STREAMING or BATCH
"""
function set_mode(pipeline::VoicePipeline, mode::VoiceMode)
    pipeline.mode = mode
    # Clear buffer when switching modes
    clear_buffer(pipeline)
end

# Export public API
export VoicePipeline, VoiceMode, STREAMING, BATCH,
       process_voice_input, process_voice_output,
       voice_loop, voice_loop_with_response,
       stream_audio_chunk, clear_buffer, get_buffer_size,
       is_stt_available, is_tts_available,
       set_voice, set_language, set_mode
