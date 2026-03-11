//! # Cognitive Sandbox - Binary Entry Point
//!
//! Main executable for the Wasmtime runtime host.
//! Provides CLI for loading, instantiating, and invoking agent modules.

use anyhow::Result;
use cognitive_sandbox::{AgentType, HostRuntime};
use std::path::Path;
use tracing::{info, Level};
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

fn setup_logging() {
    // Create logs directory
    let log_dir = std::path::Path::new("logs");
    std::fs::create_dir_all(log_dir).ok();

    // Create rolling file appender
    let file_appender = RollingFileAppender::new(Rotation::DAILY, log_dir, "cognitive-sandbox.log");

    // Setup tracing subscriber with both console and file output
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,cognitive_sandbox=debug"));

    tracing_subscriber::registry()
        .with(filter)
        .with(fmt::layer().with_writer(std::io::stdout))
        .with(fmt::layer().with_writer(file_appender).with_ansi(false))
        .init();

    info!("Logging initialized");
}

fn print_banner() {
    println!(
        r#"
    ╔═══════════════════════════════════════════════════════════╗
    ║           ITHERIS Ω - Cognitive Sandbox                    ║
    ║           Wasmtime Runtime Host - Phase 1                  ║
    ╚═══════════════════════════════════════════════════════════╝
    "#
    );
}

fn print_help() {
    println!(
        r#"
Usage: cognitive-sandbox [OPTIONS] <COMMAND>

Commands:
    load <path> <name>     Load a Wasm module from path
    list-modules           List all loaded modules
    list-instances         List all active instances
    instantiate <module-id> <agent-type>  Instantiate a module (sentry|librarian|action)
    invoke <instance-id> <func> [args...]  Invoke a function on an instance
    unload <instance-id>   Unload an agent instance
    hot-swap <module-id> <instance-id>  Hot-swap an instance
    ipc-send <to> <msg>    Send IPC message to Julia
    demo                   Run demonstration
    help                   Show this help

Options:
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help
"#
    );
}

#[tokio::main]
async fn main() -> Result<()> {
    setup_logging();
    print_banner();

    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        print_help();
        return Ok(());
    }

    let mut runtime = HostRuntime::new()?;

    match args[1].as_str() {
        "load" => {
            if args.len() < 4 {
                println!("Usage: load <path> <name>");
                return Ok(());
            }
            let path = Path::new(&args[2]);
            let name = &args[3];
            let id = runtime.load_module(path, name)?;
            println!("Module loaded with ID: {}", id);
        }
        "list-modules" => {
            println!("\nLoaded Modules:");
            println!("-----------------------------------");
            for (id, name, version) in runtime.list_modules() {
                println!("  {} - {} v{}", id, name, version);
            }
        }
        "list-instances" => {
            println!("\nActive Instances:");
            println!("-----------------------------------");
            for (id, agent_type) in runtime.list_instances() {
                println!("  {} - {:?}", id, agent_type);
            }
        }
        "instantiate" => {
            if args.len() < 4 {
                println!("Usage: instantiate <module-id> <agent-type>");
                return Ok(());
            }
            let module_id = uuid::Uuid::parse_str(&args[2])?;
            let agent_type = match args[3].as_str() {
                "sentry" => AgentType::Sentry,
                "librarian" => AgentType::Librarian,
                "action" => AgentType::Action,
                _ => {
                    println!("Invalid agent type. Use: sentry, librarian, or action");
                    return Ok(());
                }
            };
            let instance_id = runtime.instantiate(module_id, agent_type)?;
            println!("Instance created with ID: {}", instance_id);
        }
        "invoke" => {
            if args.len() < 4 {
                println!("Usage: invoke <instance-id> <func> [args...]");
                return Ok(());
            }
            let instance_id = uuid::Uuid::parse_str(&args[2])?;
            let func = &args[3];
            let invoke_args: Vec<i32> = args[4..]
                .iter()
                .filter_map(|s| s.parse().ok())
                .collect();
            let result = runtime.invoke(instance_id, func, &invoke_args)?;
            println!("Result: {}", result);
        }
        "unload" => {
            if args.len() < 3 {
                println!("Usage: unload <instance-id>");
                return Ok(());
            }
            let instance_id = uuid::Uuid::parse_str(&args[2])?;
            runtime.unload_instance(instance_id)?;
            println!("Instance {} unloaded", instance_id);
        }
        "hot-swap" => {
            if args.len() < 4 {
                println!("Usage: hot-swap <module-id> <instance-id>");
                return Ok(());
            }
            let module_id = uuid::Uuid::parse_str(&args[2])?;
            let old_instance_id = uuid::Uuid::parse_str(&args[3])?;
            let new_id = runtime.hot_swap(module_id, old_instance_id)?;
            println!("Hot-swap complete. New instance: {}", new_id);
        }
        "demo" => {
            println!("\n=== Running Demonstration ===\n");
            run_demo(&mut runtime).await?;
        }
        "help" => {
            print_help();
        }
        _ => {
            println!("Unknown command: {}", args[1]);
            print_help();
        }
    }

    Ok(())
}

async fn run_demo(runtime: &mut HostRuntime) -> Result<()> {
    println!("1. Creating host runtime... OK");

    // Check if demo wasm modules exist
    let demo_path = Path::new("modules/demo.wasm");
    if !demo_path.exists() {
        println!("\nNote: Demo Wasm modules not found.");
        println!("      Create placeholder modules in 'modules/' directory to test loading.");
        println!("\n=== Demo Complete ===");
        println!("\nThe runtime is ready to load WebAssembly modules.");
        println!("Expected interface:");
        println!("  - init() -> void");
        println!("  - process(input_ptr: i32, input_len: i32) -> i32");
        return Ok(());
    }

    // Try to load demo module
    println!("2. Loading demo module from {}...", demo_path.display());
    match runtime.load_module(demo_path, "demo_agent") {
        Ok(module_id) => {
            println!("   Module loaded: {}", module_id);

            // Try to instantiate
            println!("3. Instantiating as Sentry agent...");
            match runtime.instantiate(module_id, AgentType::Sentry) {
                Ok(instance_id) => {
                    println!("   Instance created: {}", instance_id);

                    // Try to invoke
                    println!("4. Invoking 'process' function...");
                    match runtime.invoke(instance_id, "process", &[0, 0]) {
                        Ok(result) => println!("   Result: {}", result),
                        Err(e) => println!("   Invoke error (expected): {}", e),
                    }
                }
                Err(e) => println!("   Instantiate error (expected): {}", e),
            }
        }
        Err(e) => println!("   Load error (expected if no wasm): {}", e),
    }

    println!("\n=== Demo Complete ===");
    Ok(())
}
