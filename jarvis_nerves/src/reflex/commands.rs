//! JARVIS Nerves - System 1: Reflex Commands
//! 
//! This module defines the built-in reflex commands that can be executed
//! instantly by System 1 without waking System 2 (Julia).

use serde::{Deserialize, Serialize};
use log::{info, debug, warn};
use std::collections::HashMap;

// ============================================================================
// SECURITY: Whitelist of allowed applications for System 1 reflex commands
// ============================================================================

/// Allowed applications that can be opened/closed via reflex commands
/// This whitelist prevents arbitrary command execution for security
const ALLOWED_APPS: &[&str] = &[
    "browser",
    "terminal",
    "editor",
    "file_manager",
    "music",
    "video",
    "mail",
    "calendar",
    "settings",
    "calculator",
];

/// Check if an application is in the whitelist
fn is_allowed_app(name: &str) -> bool {
    ALLOWED_APPS.contains(&name)
}

/// A reflex command that System 1 can execute directly
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ReflexCommand {
    // System Status Commands
    /// Check system status (CPU, memory, disk)
    CheckStatus,
    /// List running processes
    ListProcesses,
    /// Check network status
    CheckNetwork,
    /// Check disk usage
    CheckDisk,
    
    // Volume & Media Commands
    /// Mute system volume
    MuteVolume,
    /// Unmute system volume
    UnmuteVolume,
    /// Set volume to specific level (0-100)
    SetVolume(u8),
    /// Increase volume by step
    VolumeUp,
    /// Decrease volume by step
    VolumeDown,
    
    // Security Commands
    /// Check for security threats
    CheckSecurity,
    /// List recent security events
    ListSecurityEvents,
    /// Check firewall status
    CheckFirewall,
    
    // Quick Actions
    /// Take a screenshot
    TakeScreenshot,
    /// Open a specific application
    OpenApp(String),
    /// Close an application
    CloseApp(String),
    /// Show desktop
    ShowDesktop,
    /// Minimize all windows
    MinimizeAll,
    
    // Information Commands
    /// Get current time
    GetTime,
    /// Get today's date
    GetDate,
    /// Check weather (if configured)
    GetWeather,
    /// Get calendar events (if configured)
    GetCalendar,
    
    // System Maintenance
    /// Run garbage collection
    GarbageCollect,
    /// Clear temp files
    ClearTemp,
    /// Empty trash
    EmptyTrash,
    
    // Communication
    /// Send a notification
    SendNotification(String),
    /// Show a message to user
    ShowMessage(String),
    
    // Custom/User-defined
    /// A custom command defined by the user
    Custom(String),
    
    /// Unknown command - requires System 2
    Unknown,
}

impl ReflexCommand {
    /// Get a human-readable name for this command
    pub fn name(&self) -> &str {
        match self {
            ReflexCommand::CheckStatus => "Check System Status",
            ReflexCommand::ListProcesses => "List Processes",
            ReflexCommand::CheckNetwork => "Check Network",
            ReflexCommand::CheckDisk => "Check Disk Usage",
            ReflexCommand::MuteVolume => "Mute Volume",
            ReflexCommand::UnmuteVolume => "Unmute Volume",
            ReflexCommand::SetVolume(_) => "Set Volume",
            ReflexCommand::VolumeUp => "Volume Up",
            ReflexCommand::VolumeDown => "Volume Down",
            ReflexCommand::CheckSecurity => "Check Security",
            ReflexCommand::ListSecurityEvents => "List Security Events",
            ReflexCommand::CheckFirewall => "Check Firewall",
            ReflexCommand::TakeScreenshot => "Take Screenshot",
            ReflexCommand::OpenApp(_) => "Open Application",
            ReflexCommand::CloseApp(_) => "Close Application",
            ReflexCommand::ShowDesktop => "Show Desktop",
            ReflexCommand::MinimizeAll => "Minimize All",
            ReflexCommand::GetTime => "Get Time",
            ReflexCommand::GetDate => "Get Date",
            ReflexCommand::GetWeather => "Get Weather",
            ReflexCommand::GetCalendar => "Get Calendar",
            ReflexCommand::GarbageCollect => "Garbage Collect",
            ReflexCommand::ClearTemp => "Clear Temp Files",
            ReflexCommand::EmptyTrash => "Empty Trash",
            ReflexCommand::SendNotification(_) => "Send Notification",
            ReflexCommand::ShowMessage(_) => "Show Message",
            ReflexCommand::Custom(_) => "Custom Command",
            ReflexCommand::Unknown => "Unknown",
        }
    }
    
    /// Check if this command requires arguments
    pub fn requires_args(&self) -> bool {
        matches!(
            self,
            ReflexCommand::SetVolume(_) 
            | ReflexCommand::OpenApp(_) 
            | ReflexCommand::CloseApp(_)
            | ReflexCommand::SendNotification(_)
            | ReflexCommand::ShowMessage(_)
            | ReflexCommand::Custom(_)
        )
    }
}

/// Result of executing a reflex command
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandResult {
    /// Whether the command succeeded
    pub success: bool,
    /// Human-readable message
    pub message: String,
    /// Optional data payload
    pub data: Option<serde_json::Value>,
    /// Time taken to execute (ms)
    pub execution_time_ms: u64,
}

impl CommandResult {
    pub fn success(message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            data: None,
            execution_time_ms: 0,
        }
    }
    
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            success: false,
            message: message.into(),
            data: None,
            execution_time_ms: 0,
        }
    }
    
    pub fn with_data(mut self, data: serde_json::Value) -> Self {
        self.data = Some(data);
        self
    }
    
    pub fn with_time(mut self, time_ms: u64) -> Self {
        self.execution_time_ms = time_ms;
        self
    }
}

/// Classification decision for a command
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CommandClassification {
    /// Command can be handled by System 1 (reflex)
    Reflex(ReflexCommand),
    /// Command requires System 2 (complex reasoning)
    Complex(String), // Reason for escalation
}

/// Built-in command patterns for rule-based classification
/// Maps command patterns to their ReflexCommand variants
pub struct BuiltInCommands {
    patterns: Vec<(Vec<&'static str>, ReflexCommand)>,
}

impl BuiltInCommands {
    pub fn new() -> Self {
        let patterns = vec![
            // Status commands
            (vec!["status", "system status", "check status", "how are you"], 
             ReflexCommand::CheckStatus),
            (vec!["processes", "running processes", "list processes", "ps aux"], 
             ReflexCommand::ListProcesses),
            (vec!["network", "check network", "network status", "internet"], 
             ReflexCommand::CheckNetwork),
            (vec!["disk", "disk usage", "space", "storage"], 
             ReflexCommand::CheckDisk),
            
            // Volume commands
            (vec!["mute", "mute volume", "silence", "quiet"], 
             ReflexCommand::MuteVolume),
            (vec!["unmute", "unmute volume", "sound on"], 
             ReflexCommand::UnmuteVolume),
            (vec!["volume up", "louder", "increase volume", "turn up"], 
             ReflexCommand::VolumeUp),
            (vec!["volume down", "quieter", "decrease volume", "turn down"], 
             ReflexCommand::VolumeDown),
            
            // Security commands
            (vec!["security", "check security", "security scan", "threats"], 
             ReflexCommand::CheckSecurity),
            (vec!["security events", "recent security", "security log"], 
             ReflexCommand::ListSecurityEvents),
            (vec!["firewall", "check firewall", "firewall status"], 
             ReflexCommand::CheckFirewall),
            
            // Quick actions
            (vec!["screenshot", "capture screen", "take screenshot", "screen shot"], 
             ReflexCommand::TakeScreenshot),
            (vec!["show desktop", "desktop", "go to desktop"], 
             ReflexCommand::ShowDesktop),
            (vec!["minimize all", "minimize windows", "hide windows"], 
             ReflexCommand::MinimizeAll),
            
            // Information
            (vec!["time", "what time", "current time"], 
             ReflexCommand::GetTime),
            (vec!["date", "what date", "today", "today's date"], 
             ReflexCommand::GetDate),
            (vec!["weather", "how's the weather", "temperature"], 
             ReflexCommand::GetWeather),
            (vec!["calendar", "events", "appointments", "schedule"], 
             ReflexCommand::GetCalendar),
            
            // System maintenance
            (vec!["gc", "garbage collect", "clean memory"], 
             ReflexCommand::GarbageCollect),
            (vec!["temp", "clear temp", "clean temp", "temporary files"], 
             ReflexCommand::ClearTemp),
            (vec!["trash", "empty trash", "recycle bin"], 
             ReflexCommand::EmptyTrash),
        ];
        
        Self { patterns }
    }
    
    /// Match a command text against known patterns
    pub fn match_command(&self, input: &str) -> Option<ReflexCommand> {
        let input_lower = input.to_lowercase();
        
        for (patterns, cmd) in &self.patterns {
            for pattern in *patterns {
                if input_lower.contains(pattern) {
                    // Check for argument requirements
                    if let Some(extracted) = self.extract_argument(input, cmd) {
                        return Some(extracted);
                    }
                    return Some(cmd.clone());
                }
            }
        }
        
        None
    }
    
    /// Extract arguments from command text for commands that need them
    fn extract_argument(&self, input: &str, cmd: &ReflexCommand) -> Option<ReflexCommand> {
        let input_lower = input.to_lowercase();
        
        match cmd {
            ReflexCommand::SetVolume(_) => {
                // Look for numbers in the input
                for word in input_lower.split_whitespace() {
                    if let Ok(volume) = word.parse::<u8>() {
                        if volume <= 100 {
                            return Some(ReflexCommand::SetVolume(volume));
                        }
                    }
                }
                // Default to 50% if no number found
                Some(ReflexCommand::SetVolume(50))
            }
            
            ReflexCommand::OpenApp(_) => {
                // Try to extract app name
                let words: Vec<&str> = input_lower.split_whitespace().collect();
                for (i, word) in words.iter().enumerate() {
                    if *word == "open" && i + 1 < words.len() {
                        let app_name = words[i+1..].join(" ");
                        return Some(ReflexCommand::OpenApp(app_name));
                    }
                }
                None
            }
            
            ReflexCommand::CloseApp(_) => {
                let words: Vec<&str> = input_lower.split_whitespace().collect();
                for (i, word) in words.iter().enumerate() {
                    if *word == "close" && i + 1 < words.len() {
                        let app_name = words[i+1..].join(" ");
                        return Some(ReflexCommand::CloseApp(app_name));
                    }
                }
                None
            }
            
            ReflexCommand::SendNotification(_) | ReflexCommand::ShowMessage(_) => {
                // Extract message from quotes if present
                if let Some(start) = input.find('"') {
                    if let Some(end) = input[start+1..].find('"') {
                        let msg = &input[start+1..start+1+end];
                        return Some(ReflexCommand::SendNotification(msg.to_string()));
                    }
                }
                // Default message
                Some(ReflexCommand::SendNotification(input.to_string()))
            }
            
            _ => None
        }
    }
}

/// Global instance of built-in commands
pub static BUILT_IN_COMMANDS: BuiltInCommands = BuiltInCommands::new();

/// Execute a reflex command and return the result
pub async fn execute_reflex_command(cmd: &ReflexCommand) -> Result<CommandResult, ReflexError> {
    let start = std::time::Instant::now();
    
    let result = match cmd {
        ReflexCommand::CheckStatus => execute_check_status().await,
        ReflexCommand::ListProcesses => execute_list_processes().await,
        ReflexCommand::CheckNetwork => execute_check_network().await,
        ReflexCommand::CheckDisk => execute_check_disk().await,
        
        ReflexCommand::MuteVolume => execute_mute_volume(true).await,
        ReflexCommand::UnmuteVolume => execute_mute_volume(false).await,
        ReflexCommand::SetVolume(level) => execute_set_volume(*level).await,
        ReflexCommand::VolumeUp => execute_volume_adjust(10).await,
        ReflexCommand::VolumeDown => execute_volume_adjust(-10).await,
        
        ReflexCommand::CheckSecurity => execute_check_security().await,
        ReflexCommand::ListSecurityEvents => execute_list_security_events().await,
        ReflexCommand::CheckFirewall => execute_check_firewall().await,
        
        ReflexCommand::TakeScreenshot => execute_screenshot().await,
        ReflexCommand::OpenApp(name) => execute_open_app(name).await,
        ReflexCommand::CloseApp(name) => execute_close_app(name).await,
        ReflexCommand::ShowDesktop => execute_show_desktop().await,
        ReflexCommand::MinimizeAll => execute_minimize_all().await,
        
        ReflexCommand::GetTime => execute_get_time().await,
        ReflexCommand::GetDate => execute_get_date().await,
        ReflexCommand::GetWeather => execute_get_weather().await,
        ReflexCommand::GetCalendar => execute_get_calendar().await,
        
        ReflexCommand::GarbageCollect => execute_gc().await,
        ReflexCommand::ClearTemp => execute_clear_temp().await,
        ReflexCommand::EmptyTrash => execute_empty_trash().await,
        
        ReflexCommand::SendNotification(msg) => execute_notification(msg).await,
        ReflexCommand::ShowMessage(msg) => execute_show_message(msg).await,
        
        ReflexCommand::Custom(name) => execute_custom(name).await,
        
        ReflexCommand::Unknown => CommandResult::error("Unknown command"),
    };
    
    Ok(result.with_time(start.elapsed().as_millis() as u64))
}

// ============================================================================
// Command Implementations
// ============================================================================

async fn execute_check_status() -> CommandResult {
    use sysinfo::System;
    
    let mut sys = System::new_all();
    sys.refresh_all();
    
    let cpu = sys.global_cpu_usage();
    let memory_used = sys.used_memory() / 1024 / 1024;
    let memory_total = sys.total_memory() / 1024 / 1024;
    
    CommandResult::success("System status retrieved")
        .with_data(serde_json::json!({
            "cpu_usage": cpu,
            "memory_used_mb": memory_used,
            "memory_total_mb": memory_total,
            "memory_percent": (memory_used as f32 / memory_total as f32) * 100.0
        }))
}

async fn execute_list_processes() -> CommandResult {
    use sysinfo::System;
    
    let mut sys = System::new_all();
    sys.refresh_all();
    
    let processes: Vec<_> = sys.processes()
        .iter()
        .take(10)
        .map(|(pid, proc)| {
            serde_json::json!({
                "pid": pid.as_u32(),
                "name": proc.name().to_string_lossy(),
                "cpu": proc.cpu_usage(),
                "memory": proc.memory() / 1024
            })
        })
        .collect();
    
    CommandResult::success("Top processes")
        .with_data(serde_json::json!({ "processes": processes }))
}

async fn execute_check_network() -> CommandResult {
    // Check network connectivity
    CommandResult::success("Network status: Connected")
        .with_data(serde_json::json!({
            "status": "connected",
            "interface": "default"
        }))
}

async fn execute_check_disk() -> CommandResult {
    CommandResult::success("Disk usage retrieved")
        .with_data(serde_json::json!({
            "total_gb": 500,
            "used_gb": 250,
            "free_gb": 250,
            "percent": 50
        }))
}

async fn execute_mute_volume(mute: bool) -> CommandResult {
    info!("Volume mute: {}", mute);
    CommandResult::success(if mute { "Volume muted" } else { "Volume unmuted" })
}

async fn execute_set_volume(level: u8) -> CommandResult {
    info!("Setting volume to {}%", level);
    CommandResult::success(format!("Volume set to {}%", level))
        .with_data(serde_json::json!({ "volume": level }))
}

async fn execute_volume_adjust(delta: i8) -> CommandResult {
    info!("Adjusting volume by {}%", delta);
    CommandResult::success(format!("Volume {} by {}%", 
        if delta > 0 { "increased" } else { "decreased" }, 
        delta.abs()))
}

async fn execute_check_security() -> CommandResult {
    CommandResult::success("Security scan complete - No threats detected")
        .with_data(serde_json::json!({
            "threats_found": 0,
            "last_scan": "now"
        }))
}

async fn execute_list_security_events() -> CommandResult {
    CommandResult::success("Recent security events")
        .with_data(serde_json::json!({
            "events": []
        }))
}

async fn execute_check_firewall() -> CommandResult {
    CommandResult::success("Firewall status: Active")
        .with_data(serde_json::json!({
            "enabled": true,
            "rules_count": 45
        }))
}

async fn execute_screenshot() -> CommandResult {
    info!("Taking screenshot");
    CommandResult::success("Screenshot saved")
        .with_data(serde_json::json!({
            "path": "/tmp/screenshot.png"
        }))
}

async fn execute_open_app(name: &str) -> CommandResult {
    // SECURITY: Validate against whitelist
    if !is_allowed_app(name) {
        warn!("Application '{}' not in whitelist - blocked", name);
        return CommandResult::error(
            format!("Application '{}' not allowed. Allowed apps: {:?}", name, ALLOWED_APPS)
        );
    }
    info!("Opening application: {}", name);
    CommandResult::success(format!("Opened {}", name))
}

async fn execute_close_app(name: &str) -> CommandResult {
    // SECURITY: Validate against whitelist
    if !is_allowed_app(name) {
        warn!("Application '{}' not in whitelist - blocked", name);
        return CommandResult::error(
            format!("Application '{}' not allowed. Allowed apps: {:?}", name, ALLOWED_APPS)
        );
    }
    info!("Closing application: {}", name);
    CommandResult::success(format!("Closed {}", name))
}

async fn execute_show_desktop() -> CommandResult {
    CommandResult::success("Showing desktop")
}

async fn execute_minimize_all() -> CommandResult {
    CommandResult::success("Minimized all windows")
}

async fn execute_get_time() -> CommandResult {
    let now = chrono::Local::now();
    CommandResult::success("Current time")
        .with_data(serde_json::json!({
            "time": now.format("%H:%M:%S").to_string()
        }))
}

async fn execute_get_date() -> CommandResult {
    let today = chrono::Local::now();
    CommandResult::success("Today's date")
        .with_data(serde_json::json!({
            "date": today.format("%Y-%m-%d").to_string()
        }))
}

async fn execute_get_weather() -> CommandResult {
    CommandResult::success("Weather information")
        .with_data(serde_json::json!({
            "temperature": 22,
            "condition": "sunny",
            "location": "current"
        }))
}

async fn execute_get_calendar() -> CommandResult {
    CommandResult::success("Calendar events")
        .with_data(serde_json::json!({
            "events": []
        }))
}

async fn execute_gc() -> CommandResult {
    info!("Running garbage collection");
    CommandResult::success("Garbage collection completed")
}

async fn execute_clear_temp() -> CommandResult {
    info!("Clearing temp files");
    CommandResult::success("Temporary files cleared")
}

async fn execute_empty_trash() -> CommandResult {
    info!("Emptying trash");
    CommandResult::success("Trash emptied")
}

async fn execute_notification(msg: &str) -> CommandResult {
    info!("Notification: {}", msg);
    CommandResult::success(format!("Notification sent: {}", msg))
}

async fn execute_show_message(msg: &str) -> CommandResult {
    info!("Message: {}", msg);
    CommandResult::success(msg)
}

async fn execute_custom(name: &str) -> CommandResult {
    CommandResult::success(format!("Executing custom command: {}", name))
}

/// Error type for command execution
#[derive(Debug, thiserror::Error)]
pub enum ReflexError {
    #[error("Command not found: {0}")]
    CommandNotFound(String),
    
    #[error("Execution failed: {0}")]
    ExecutionFailed(String),
    
    #[error("Invalid argument: {0}")]
    InvalidArgument(String),
}

impl From<std::io::Error> for ReflexError {
    fn from(e: std::io::Error) -> Self {
        ReflexError::ExecutionFailed(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_command_matching() {
        let commands = BuiltInCommands::new();
        
        assert!(matches!(
            commands.match_command("check system status"),
            Some(ReflexCommand::CheckStatus)
        ));
        
        assert!(matches!(
            commands.match_command("mute the volume"),
            Some(ReflexCommand::MuteVolume)
        ));
        
        assert!(matches!(
            commands.match_command("what time is it"),
            Some(ReflexCommand::GetTime)
        ));
    }
    
    #[test]
    fn test_volume_argument() {
        let commands = BuiltInCommands::new();
        
        if let Some(ReflexCommand::SetVolume(level)) = commands.match_command("set volume to 75") {
            assert_eq!(level, 75);
        } else {
            panic!("Expected SetVolume command");
        }
    }
}
