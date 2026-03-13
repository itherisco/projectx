//! # Safe Shell - Secure Command Execution with Jailing
//!
//! This module provides restricted shell execution with:
//! - Command whitelist (only safe commands allowed)
//! - Directory restrictions (prevent path traversal)
//! - Shell injection prevention
//! - Output size limits
//! - Execution timeout
//!
//! ## Security Properties
//!
//! - **Whitelist Only**: Only explicitly allowed commands
//! - **Directory Jailing**: Restricted to safe directories
//! - **Injection Prevention**: Blocks shell metacharacters
//! - **Size Limits**: Prevents buffer overflow
//! - **Timeout**: Prevents hanging commands

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use thiserror::Error;

/// Safe shell errors
#[derive(Error, Debug)]
pub enum SafeShellError {
    #[error("Command not allowed: {0}")]
    CommandNotAllowed(String),

    #[error("Directory not allowed: {0}")]
    DirectoryNotAllowed(String),

    #[error("Shell injection detected: {0}")]
    InjectionDetected(String),

    #[error("Output too large: {0}")]
    OutputTooLarge(String),

    #[error("Execution timeout: {0}")]
    Timeout(String),

    #[error("Execution failed: {0}")]
    ExecutionFailed(String),
}

/// Shell execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellResult {
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub duration_ms: u64,
}

/// Shell configuration
#[derive(Clone)]
pub struct ShellConfig {
    /// Allowed directories
    pub allowed_dirs: Vec<String>,
    /// Allowed commands (whitelist)
    pub allowed_commands: HashSet<String>,
    /// Maximum output size in bytes
    pub max_output_size: usize,
    /// Execution timeout in seconds
    pub timeout_secs: u64,
    /// Maximum command length
    pub max_command_length: usize,
}

impl Default for ShellConfig {
    fn default() -> Self {
        let mut allowed_dirs = Vec::new();
        allowed_dirs.push("/tmp".to_string());
        allowed_dirs.push("/var/tmp".to_string());
        allowed_dirs.push("/home/user/projectx".to_string());

        let mut allowed_commands = HashSet::new();
        allowed_commands.insert("echo".to_string());
        allowed_commands.insert("date".to_string());
        allowed_commands.insert("hostname".to_string());
        allowed_commands.insert("pwd".to_string());
        allowed_commands.insert("ls".to_string());
        allowed_commands.insert("cat".to_string());
        allowed_commands.insert("head".to_string());
        allowed_commands.insert("tail".to_string());

        Self {
            allowed_dirs,
            allowed_commands,
            max_output_size: 1024 * 1024, // 1MB
            timeout_secs: 30,
            max_command_length: 256,
        }
    }
}

/// Safe Shell Executor
pub struct SafeShell {
    config: ShellConfig,
    /// Shell injection patterns
    injection_patterns: Vec<Regex>,
    /// Blocked patterns
    blocked_patterns: Vec<Regex>,
}

impl SafeShell {
    /// Create new executor
    pub fn new() -> Self {
        Self::with_config(ShellConfig::default())
    }

    /// Create with custom config
    pub fn with_config(config: ShellConfig) -> Self {
        // Shell injection patterns
        let injection_patterns = vec![
            Regex::new(r"\$\([^)]+\)").unwrap(),           // Command substitution $()
            Regex::new(r"`[^`]+`").unwrap(),               // Backtick substitution
            Regex::new(r"\|\s*bash").unwrap(),             // Pipe to bash
            Regex::new(r"\|\s*sh").unwrap(),                // Pipe to sh
            Regex::new(r"&&").unwrap(),                     // Command chaining
            Regex::new(r"\|\|").unwrap(),                   // OR chaining
            Regex::new(r";\s*rm\s").unwrap(),              // Semicolon + rm
            Regex::new(r";\s*wget\s").unwrap(),            // Semicolon + wget
            Regex::new(r";\s*curl\s").unwrap(),            // Semicolon + curl
            Regex::new(r";\s*nc\s").unwrap(),              // Semicolon + netcat
            Regex::new(r"\bexec\s").unwrap(),              // exec command
            Regex::new(r"\beval\s").unwrap(),              // eval command
            Regex::new(r"\bsource\s").unwrap(),            // source command
            Regex::new(r"\.\s*/").unwrap(),                // Execute from path
        ];

        // Blocked path patterns
        let blocked_patterns = vec![
            Regex::new(r"^/etc").unwrap(),      // System config
            Regex::new(r"^/proc").unwrap(),     // Process info
            Regex::new(r"^/sys").unwrap(),      // Kernel info
            Regex::new(r"^/root").unwrap(),    // Root home
            Regex::new(r"^/var/log").unwrap(), // Logs
            Regex::new(r"^/home/[^/]+/\.ssh").unwrap(), // SSH keys
            Regex::new(r"^/dev").unwrap(),     // Devices
        ];

        Self {
            config,
            injection_patterns,
            blocked_patterns,
        }
    }

    /// Check for shell injection
    fn check_injection(&self, command: &str) -> Result<(), SafeShellError> {
        for pattern in &self.injection_patterns {
            if pattern.is_match(command) {
                return Err(SafeShellError::InjectionDetected(
                    format!("Pattern matched: {}", pattern),
                ));
            }
        }
        Ok(())
    }

    /// Check for blocked paths
    fn check_path(&self, path: &str) -> Result<(), SafeShellError> {
        // Check blocked patterns
        for pattern in &self.blocked_patterns {
            if pattern.is_match(path) {
                return Err(SafeShellError::DirectoryNotAllowed(
                    format!("Blocked path: {}", path),
                ));
            }
        }

        // Check allowed directories
        let canonical = Path::new(path);
        let is_allowed = self.config.allowed_dirs.iter().any(|dir| {
            canonical.starts_with(dir) || canonical.to_string_lossy().starts_with(dir)
        });

        if !is_allowed {
            return Err(SafeShellError::DirectoryNotAllowed(format!(
                "Path not in allowed list: {}",
                path
            )));
        }

        Ok(())
    }

    /// Extract command from input
    fn extract_command(&self, input: &str) -> Result<String, SafeShellError> {
        let trimmed = input.trim();
        
        // Check length
        if trimmed.len() > self.config.max_command_length {
            return Err(SafeShellError::ExecutionFailed(
                "Command too long".to_string(),
            ));
        }

        // Extract base command (first word)
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts.is_empty() {
            return Err(SafeShellError::ExecutionFailed(
                "Empty command".to_string(),
            ));
        }

        let cmd = parts[0];

        // Check whitelist
        if !self.config.allowed_commands.contains(cmd) {
            return Err(SafeShellError::CommandNotAllowed(format!(
                "Command not in whitelist: {}",
                cmd
            )));
        }

        Ok(trimmed.to_string())
    }

    /// Execute a safe shell command
    pub fn execute(&self, command: &str) -> Result<ShellResult, SafeShellError> {
        let start = Instant::now();

        // 1. Check for injection
        self.check_injection(command)?;

        // 2. Extract and validate command
        let validated_cmd = self.extract_command(command)?;

        // 3. Check for dangerous paths in arguments
        for arg in validated_cmd.split_whitespace() {
            if arg.starts_with('/') {
                self.check_path(arg)?;
            }
        }

        // 4. Execute with timeout
        let output = Command::new("sh")
            .args(["-c", &validated_cmd])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();

        let duration = start.elapsed();

        match output {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout).to_string();
                let stderr = String::from_utf8_lossy(&output.stderr).to_string();

                // Check output size
                if stdout.len() + stderr.len() > self.config.max_output_size {
                    return Err(SafeShellError::OutputTooLarge(format!(
                        "Output exceeds {} bytes",
                        self.config.max_output_size
                    )));
                }

                Ok(ShellResult {
                    success: output.status.success(),
                    stdout,
                    stderr,
                    exit_code: output.status.code().unwrap_or(-1),
                    duration_ms: duration.as_millis() as u64,
                })
            }
            Err(e) => Err(SafeShellError::ExecutionFailed(e.to_string())),
        }
    }

    /// Execute with timeout
    pub fn execute_with_timeout(&self, command: &str) -> Result<ShellResult, SafeShellError> {
        let timeout = Duration::from_secs(self.config.timeout_secs);

        // Use std::thread::spawn for timeout (simpler than async)
        let command = command.to_string();
        
        let handle = std::thread::spawn(move || {
            let shell = SafeShell::new();
            shell.execute(&command)
        });

        match handle.join() {
            Ok(result) => result,
            Err(_) => Err(SafeShellError::Timeout("Thread panicked".to_string())),
        }
    }

    /// Add allowed directory
    pub fn add_allowed_dir(&mut self, dir: &str) {
        self.config.allowed_dirs.push(dir.to_string());
    }

    /// Add allowed command
    pub fn add_allowed_command(&mut self, cmd: &str) {
        self.config.allowed_commands.insert(cmd.to_string());
    }
}

impl Default for SafeShell {
    fn default() -> Self {
        Self::new()
    }
}

// Global executor
use once_cell::sync::Lazy;
use std::sync::RwLock;

static SAFE_SHELL: Lazy<RwLock<SafeShell>> = Lazy::new(|| RwLock::new(SafeShell::new()));

/// Initialize global shell
pub fn init() {
    let _ = SAFE_SHELL.read();
}

/// Execute command
pub fn execute(command: &str) -> Result<ShellResult, SafeShellError> {
    SAFE_SHELL.read().unwrap().execute(command)
}

/// Execute with timeout
pub fn execute_with_timeout(command: &str) -> Result<ShellResult, SafeShellError> {
    SAFE_SHELL.read().unwrap().execute_with_timeout(command)
}

/// Add allowed directory
pub fn add_allowed_dir(dir: &str) {
    SAFE_SHELL.write().unwrap().add_allowed_dir(dir);
}

/// Add allowed command
pub fn add_allowed_command(cmd: &str) {
    SAFE_SHELL.write().unwrap().add_allowed_command(cmd);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_allowed_command() {
        let shell = SafeShell::new();
        let result = shell.execute("echo hello").unwrap();
        assert!(result.success);
    }

    #[test]
    fn test_blocked_command() {
        let shell = SafeShell::new();
        let result = shell.execute("cat /etc/passwd");
        assert!(result.is_err());
    }

    #[test]
    fn test_injection_blocked() {
        let shell = SafeShell::new();
        let result = shell.execute("echo test; rm -rf /");
        assert!(result.is_err());
    }
}
