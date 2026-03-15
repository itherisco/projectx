//! ITHERIS Sovereign Kernel v5.0 - Main Control Console
//! User: badra222
//! Date: 2026-01-17
//! Authority: ABSOLUTE

mod crypto;
mod kernel;
mod debate;
mod state;
mod federation;
mod llm_advisor;
mod catastrophe;
mod iot_bridge;
mod ledger;
mod threat_model;
mod api_bridge;
mod database;
mod pipeline;
mod monitoring;
mod panic_translation;
mod ipc;

use crypto::CryptoAuthority;
use kernel::ItherisKernel;
use panic_translation::{catch_panic, TranslatedPanic, JuliaExceptionCode, FFIResult};
use debate::DebateEngine;
use state::GlobalState;
use federation::{Federation, Agent};
use llm_advisor::LLMAdvisor;
use catastrophe::CatastropheModel;
use iot_bridge::{IoTBridge, Device};
use ledger::ImmutableLedger;
use threat_model::ThreatModel;
use api_bridge::{APIBridge, ExternalAPI};
use database::{DatabaseManager, Database, DatabaseType};
use pipeline::{PipelineManager, PipelineStage};
use monitoring::Monitor;
use ipc::ring_buffer::IpcRingBuffer;
use ipc::SyncIpcRingBuffer;
use ipc::IPCError;
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
use std::io::{self, Write};
use std::collections::HashMap;

fn print_banner() {
    println!("\n╔═══════════════════════════════════════════════════════════════════════╗");
    println!("║      ITHERIS SOVEREIGN KERNEL v5.0 (2026-01-17)                      ║");
    println!("║      EXTERNAL INTEGRATION • API BRIDGES • DATA PIPELINES              ║");
    println!("║      Crypto • Cognition • Federation • IoT • Ledger • Threat         ║");
    println!("║      APIs • Databases • Pipelines • Monitoring                        ║");
    println!("║      User: badra222 | Authority: ABSOLUTE | Status: ONLINE           ║");
    println!("╚═══════════════════════════════════════════════════════════════════════╝\n");
}

fn init_systems() -> (
    ItherisKernel,
    DebateEngine,
    GlobalState,
    Federation,
    LLMAdvisor,
    CatastropheModel,
    IoTBridge,
    ImmutableLedger,
    ThreatModel,
    APIBridge,
    DatabaseManager,
    PipelineManager,
    Monitor,
    String,
) {
    // Core systems
    let mut kernel = ItherisKernel::new(vec![
        "STRATEGIST", "CRITIC", "SCOUT", "EXECUTOR", "OBSERVER",
    ]);

    let debate_engine = DebateEngine::new();
    let mut global_state = GlobalState::new();
    let mut federation = Federation::new();
    let llm_advisor = LLMAdvisor::new("GPT-4-ADVISOR", "gpt-4o");
    let catastrophe_model = CatastropheModel::new();
    let iot_bridge = IoTBridge::new();
    let ledger = ImmutableLedger::new(10);
    let threat_model = ThreatModel::new();

    // External integration systems
    let api_bridge = APIBridge::new(300); // 5 min cache
    let database_manager = DatabaseManager::new();
    let pipeline_manager = PipelineManager::new();
    let monitor = Monitor::new();

    // Set capabilities
    kernel.grant_capability(
        "STRATEGIST",
        vec!["REQUEST_EXECUTION", "QUERY_STATE"],
        86400,
    );
    kernel.grant_capability("CRITIC", vec!["VALIDATE", "CHALLENGE"], 86400);
    kernel.grant_capability("EXECUTOR", vec!["EXECUTE", "REPORT_RESULT"], 86400);

    // Register agents
    federation.register_agent(Agent {
        id: "STRATEGIST".to_string(),
        role: "Decision-maker".to_string(),
        status: "ONLINE".to_string(),
        last_heartbeat: chrono::Local::now().to_rfc3339(),
        capabilities: vec!["REQUEST_EXECUTION".to_string()],
        reputation: 0.95,
    });

    federation.register_agent(Agent {
        id: "CRITIC".to_string(),
        role: "Validator".to_string(),
        status: "ONLINE".to_string(),
        last_heartbeat: chrono::Local::now().to_rfc3339(),
        capabilities: vec!["VALIDATE".to_string()],
        reputation: 0.92,
    });

    federation.register_agent(Agent {
        id: "EXECUTOR".to_string(),
        role: "Executor".to_string(),
        status: "ONLINE".to_string(),
        last_heartbeat: chrono::Local::now().to_rfc3339(),
        capabilities: vec!["EXECUTE".to_string()],
        reputation: 0.88,
    });

    let _ = federation.connect_agents("STRATEGIST", "CRITIC");
    let _ = federation.connect_agents("CRITIC", "EXECUTOR");

    // Initialize state
    global_state.update("system_status", json!("ONLINE"), "v5.0 Production Ready");
    global_state.update("federation_size", json!(3), "3 agents");
    global_state.update("external_apis", json!(0), "Ready");
    global_state.update("databases", json!(0), "Ready");
    global_state.update("threat_level", json!(0), "Nominal");
    global_state.snapshot();

    println!("[KERNEL] All v5.0 subsystems initialized\n");

    let pipeline_id = String::new();

    (
        kernel,
        debate_engine,
        global_state,
        federation,
        llm_advisor,
        catastrophe_model,
        iot_bridge,
        ledger,
        threat_model,
        api_bridge,
        database_manager,
        pipeline_manager,
        monitor,
        pipeline_id,
    )
}

fn print_menu() {
    println!("\n╔═══════════════════════════════════════════════════════════════════════╗");
    println!("║            ITHERIS v5.0 CONTROL CENTER (Production)                 ║");
    println!("╠═══════════════════════════════════════════════════════════════════════╣");
    println!("║  [CORE COGNITION]                                                    ║");
    println!("║    1. STRATEGIST: Propose thought                                    ║");
    println!("║    2. CRITIC: Challenge position                                     ║");
    println!("║    3. RESOLVE: Internal debate                                       ║");
    println!("║    4. FEDERATION: Agent status                                       ║");
    println!("║                                                                       ║");
    println!("║  [EXTERNAL INTEGRATION]                                              ║");
    println!("║    5. REGISTER_API: Add external API                                 ║");
    println!("║    6. API_HEALTH: Check API status                                   ║");
    println!("║    7. API_REQUEST: Make API call                                     ║");
    println!("║    8. REGISTER_DB: Add database                                      ║");
    println!("║    9. DB_CONNECT: Test connection                                    ║");
    println!("║   10. DB_QUERY: Execute query                                        ║");
    println!("║   11. PIPELINE_CREATE: Create data pipeline                          ║");
    println!("║   12. PIPELINE_RUN: Execute pipeline                                 ║");
    println!("║                                                                       ║");
    println!("║  [OBSERVABILITY]                                                     ║");
    println!("║   13. METRIC: Record metric                                          ║");
    println!("║   14. ALERTS: View alerts                                            ║");
    println!("║   15. HEALTH: System health                                          ║");
    println!("║                                                                       ║");
    println!("║  [PHYSICAL & SECURITY]                                               ║");
    println!("║   16. REGISTER_DEVICE: Add IoT device                                ║");
    println!("║   17. DEVICE_COMMAND: Queue device command                           ║");
    println!("║   18. THREATS: Threat landscape                                      ║");
    println!("║   19. RISK: Risk assessment                                          ║");
    println!("║                                                                       ║");
    println!("║  [AUDIT & VERIFICATION]                                              ║");
    println!("║   20. LEDGER_RECORD: Record to ledger                                ║");
    println!("║   21. LEDGER_VERIFY: Verify integrity                                ║");
    println!("║   22. STATE: View global state                                       ║");
    println!("║                                                                       ║");
    println!("║   99. EXIT                                                           ║");
    println!("╚═══════════════════════════════════════════════════════════════════════╝");
    print!("\n> ");
    io::stdout().flush().unwrap();
}

fn main() {
    print_banner();

    let (
        mut kernel,
        mut debate_engine,
        mut global_state,
        mut federation,
        mut llm_advisor,
        mut catastrophe_model,
        mut iot_bridge,
        mut ledger,
        mut threat_model,
        mut api_bridge,
        mut database_manager,
        mut pipeline_manager,
        mut monitor,
        mut pipeline_id,
    ) = init_systems();

    // Initialize IPC ring buffer for Julia communication (thread-safe version)
    let ipc_buffer = SyncIpcRingBuffer::new();
    println!("[MAIN] IPC ring buffer initialized at /dev/shm/itheris_ipc (with mutex protection)");

    // Spawn IPC listener thread to handle Julia kernel requests
    let kernel_clone = Arc::new(Mutex::new(kernel));
    let ipc_clone = Arc::new(Mutex::new(ipc_buffer));
    let kernel_for_ipc = Arc::clone(&kernel_clone);
    
    std::thread::spawn(move || {
        println!("[IPC] Starting IPC listener thread...");
        loop {
            {
                // Use proper error handling instead of unwrap()
                let ipc_result = ipc_clone.lock();
                match ipc_result {
                    Ok(ipc) => {
                        // Use try_pop for non-blocking access
                        match ipc.try_pop() {
                            Ok(Some(entry)) => {
                                println!("[IPC] Received entry from Julia kernel");
                                
                                // DIAGNOSTIC: Log entry type for debugging
                                if let Some(entry_type) = entry.get_entry_type() {
                                    println!("[IPC_DIAG] Entry type: {:?}", entry_type);
                                }
                                
                                // FFI BOUNDARY: Wrap entry processing with catch_panic
                                // This catches Rust panics and translates them to Julia exceptions
                                let result = catch_panic(|| {
                                    // Use proper error handling instead of unwrap()
                                    let kernel_lock = kernel_for_ipc.lock();
                                    match kernel_lock {
                                        Ok(_kernel) => {
                                            // Process entry - verify signature, check capabilities, etc.
                                            // For now, just log that we received it
                                            println!("[IPC] Processing entry in panic-safe wrapper");
                                        }
                                        Err(poisoned) => {
                                            eprintln!("[IPC_ERROR] Kernel lock poisoned: {:?}", poisoned);
                                        }
                                    }
                                    true  // Return success
                                });
                                
                                match result.success {
                                    0 => {
                                        // DIAGNOSTIC: Log if entry is processed without panic
                                        println!("[IPC_DIAG] Entry processed successfully");
                                    },
                                    -1 => {
                                        // Panic was caught and translated - extract error info
                                        println!("[IPC_DIAG] PANIC CAUGHT at FFI boundary!");
                                        if !result.error_ptr.is_null() {
                                            let panic_info = &*result.error_ptr;
                                            println!("[IPC_DIAG] Exception code: {}", panic_info.exception_code);
                                            println!("[IPC_DIAG] Message: {}", panic_info.get_message());
                                        }
                                    },
                                    _ => {
                                        println!("[IPC_DIAG] Unknown error code: {}", result.success);
                                    }
                                }
                                
                                // Write response back
                                // ipc.push_response(...);
                            },
                            Ok(None) => {
                                // No entry available, this is normal
                            },
                            Err(e) => {
                                eprintln!("[IPC_ERROR] Failed to pop from ring buffer: {}", e);
                            }
                        }
                    },
                    Err(poisoned) => {
                        eprintln!("[IPC_ERROR] IPC lock poisoned: {:?}", poisoned);
                    }
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    });
    println!("[MAIN] IPC listener thread spawned");

    loop {
        print_menu();

        let mut choice = String::new();
        io::stdin().read_line(&mut choice).unwrap();

        match choice.trim() {
            "1" => {
                // STRATEGIST proposes
                let timestamp = chrono::Local::now().to_rfc3339();
                let nonce = uuid::Uuid::new_v4().to_string();

                let payload = json!({
                    "action": "execute_market_order",
                    "target": "trading_system",
                    "parameters": {"symbol": "BTC", "quantity": 0.5}
                });

                let evidence = Some(json!({
                    "reason": "Market conditions favorable",
                    "urgency": "high"
                }));

                match kernel.crypto.sign_thought(
                    "STRATEGIST",
                    "REQUEST_EXECUTION",
                    payload,
                    evidence,
                    timestamp,
                    nonce,
                ) {
                    Ok(signed) => {
                        println!("\n[✓] Thought signed: {}", &signed.message_hash[0..16]);
                        let position = debate_engine.propose(&signed);
                        println!("[✓] Position registered (confidence: {})", position.confidence);

                        ledger.record_entry(
                            "DECISION",
                            "STRATEGIST",
                            "REQUEST_EXECUTION",
                            json!({"proposal": position.claim}),
                            signed.signature.clone(),
                        );
                    }
                    Err(e) => println!("[✗] Error: {}", e),
                }
            }
            "2" => {
                // CRITIC challenges
                if let Some(pos) = debate_engine.positions.first().cloned() {
                    debate_engine.challenge(
                        "CRITIC",
                        &pos.thought_hash,
                        "Requires compliance approval".to_string(),
                        Some(json!({"rule": "DAILY_LIMIT"})),
                    );
                } else {
                    println!("[!] No positions to challenge");
                }
            }
            "3" => {
                // Resolve debate
                if let Some(pos) = debate_engine.positions.first().cloned() {
                    let outcome = debate_engine.resolve(&pos.thought_hash);
                    println!("\n[DEBATE OUTCOME]");
                    println!("  Verdict: {}", outcome.verdict);
                    println!("  Confidence: {}", outcome.proposition.confidence + outcome.confidence_delta);
                }
            }
            "4" => {
                // Federation status
                let agents = federation.get_agents();
                println!("\n[FEDERATION STATUS] ({} agents)", agents.len());
                for (id, agent) in agents {
                    println!("  {}: {} [rep: {:.2}]", id, agent.status, agent.reputation);
                }
            }
            "5" => {
                // Register API
                print!("API ID: ");
                io::stdout().flush().unwrap();
                let mut api_id = String::new();
                io::stdin().read_line(&mut api_id).unwrap();

                print!("API Name: ");
                io::stdout().flush().unwrap();
                let mut api_name = String::new();
                io::stdin().read_line(&mut api_name).unwrap();

                print!("Endpoint: ");
                io::stdout().flush().unwrap();
                let mut endpoint = String::new();
                io::stdin().read_line(&mut endpoint).unwrap();

                let api = ExternalAPI {
                    id: api_id.trim().to_string(),
                    name: api_name.trim().to_string(),
                    endpoint: endpoint.trim().to_string(),
                    auth_type: "API_KEY".to_string(),
                    auth_token: "placeholder".to_string(),
                    status: "UNKNOWN".to_string(),
                    last_health_check: "NEVER".to_string(),
                    response_time_ms: 0,
                };

                match api_bridge.register_api(api) {
                    Ok(_) => {
                        global_state.update("external_apis", json!(api_bridge.request_count()), "API registered");
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "6" => {
                // API health check
                print!("API ID: ");
                io::stdout().flush().unwrap();
                let mut api_id = String::new();
                io::stdin().read_line(&mut api_id).unwrap();
                let api_id = api_id.trim();

                match api_bridge.health_check(api_id) {
                    Ok(healthy) => {
                        println!("[✓] {}: {}", api_id, if healthy { "HEALTHY" } else { "DEGRADED" });
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "7" => {
                // API request
                print!("API ID: ");
                io::stdout().flush().unwrap();
                let mut api_id = String::new();
                io::stdin().read_line(&mut api_id).unwrap();
                let api_id = api_id.trim();

                print!("Path (e.g., /price): ");
                io::stdout().flush().unwrap();
                let mut path = String::new();
                io::stdin().read_line(&mut path).unwrap();
                let path = path.trim();

                match api_bridge.request(api_id, "GET", path, None) {
                    Ok(response) => {
                        println!("[✓] Response: {} ({}ms)", response.status_code, response.response_time_ms);
                        println!("  Data: {}", response.body);
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "8" => {
                // Register database
                print!("DB ID: ");
                io::stdout().flush().unwrap();
                let mut db_id = String::new();
                io::stdin().read_line(&mut db_id).unwrap();

                print!("DB Name: ");
                io::stdout().flush().unwrap();
                let mut db_name = String::new();
                io::stdin().read_line(&mut db_name).unwrap();

                let db = Database {
                    id: db_id.trim().to_string(),
                    name: db_name.trim().to_string(),
                    db_type: DatabaseType::PostgreSQL,
                    connection_string: "postgresql://localhost/itheris".to_string(),
                    status: "UNKNOWN".to_string(),
                    last_connection: "NEVER".to_string(),
                    query_count: 0,
                };

                match database_manager.register_database(db) {
                    Ok(_) => {
                        global_state.update("databases", json!(database_manager.query_count()), "DB registered");
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "9" => {
                // Test DB connection
                print!("DB ID: ");
                io::stdout().flush().unwrap();
                let mut db_id = String::new();
                io::stdin().read_line(&mut db_id).unwrap();
                let db_id = db_id.trim();

                match database_manager.test_connection(db_id) {
                    Ok(connected) => {
                        println!("[✓] {}: {}", db_id, if connected { "CONNECTED" } else { "FAILED" });
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "10" => {
                // Execute query
                print!("DB ID: ");
                io::stdout().flush().unwrap();
                let mut db_id = String::new();
                io::stdin().read_line(&mut db_id).unwrap();
                let db_id = db_id.trim();

                print!("Query (e.g., SELECT * FROM decisions): ");
                io::stdout().flush().unwrap();
                let mut query = String::new();
                io::stdin().read_line(&mut query).unwrap();
                let query = query.trim();

                match database_manager.execute_query(db_id, query, vec![]) {
                    Ok(result) => {
                        println!("[✓] Query executed");
                        println!("  Rows: {}", result.count);
                        println!("  Time: {}ms", result.execution_time_ms);
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "11" => {
                // Create pipeline
                pipeline_id = pipeline_manager.create_pipeline(
                    "Market Data Pipeline",
                    "ETL market data",
                    vec![
                        PipelineStage {
                            id: "s1".to_string(),
                            name: "Extract".to_string(),
                            stage_type: "EXTRACT".to_string(),
                            input_source: "API".to_string(),
                            output_destination: "temp".to_string(),
                            status: "READY".to_string(),
                            records_processed: 0,
                        },
                        PipelineStage {
                            id: "s2".to_string(),
                            name: "Transform".to_string(),
                            stage_type: "TRANSFORM".to_string(),
                            input_source: "temp".to_string(),
                            output_destination: "normalized".to_string(),
                            status: "READY".to_string(),
                            records_processed: 0,
                        },
                        PipelineStage {
                            id: "s3".to_string(),
                            name: "Load".to_string(),
                            stage_type: "LOAD".to_string(),
                            input_source: "normalized".to_string(),
                            output_destination: "database".to_string(),
                            status: "READY".to_string(),
                            records_processed: 0,
                        },
                    ],
                );
                println!("[✓] Pipeline created: {}", pipeline_id);
            }
            "12" => {
                // Execute pipeline
                if !pipeline_id.is_empty() {
                    match pipeline_manager.execute_pipeline(&pipeline_id) {
                        Ok(execution) => {
                            println!("[✓] Pipeline executed");
                            println!("  Status: {}", execution.status);
                            println!("  Records: {} success / {} failed",
                                     execution.successful_records, execution.failed_records);
                            println!("  Duration: {}ms", execution.duration_ms);
                        }
                        Err(e) => println!("[✗] {}", e),
                    }
                } else {
                    println!("[!] No pipeline created yet");
                }
            }
            "13" => {
                // Record metric
                print!("Metric name: ");
                io::stdout().flush().unwrap();
                let mut metric = String::new();
                io::stdin().read_line(&mut metric).unwrap();

                print!("Value: ");
                io::stdout().flush().unwrap();
                let mut value = String::new();
                io::stdin().read_line(&mut value).unwrap();
                let value: f32 = value.trim().parse().unwrap_or(0.0);

                monitor.record_metric(metric.trim(), value, "units", HashMap::new());
            }
            "14" => {
                // View alerts
                println!("\n[ACTIVE ALERTS]");
                for alert in monitor.get_alerts().iter().filter(|a| !a.resolved) {
                    println!("  [{}] {}: {} > {}", alert.severity, alert.metric_name, alert.current_value, alert.threshold);
                }
            }
            "15" => {
                // Health summary
                let health = monitor.health_summary();
                println!("\n[SYSTEM HEALTH]");
                println!("{}", serde_json::to_string_pretty(&health).unwrap());
            }
            "16" => {
                // Register device
                print!("Device ID: ");
                io::stdout().flush().unwrap();
                let mut dev_id = String::new();
                io::stdin().read_line(&mut dev_id).unwrap();

                print!("Device Type: ");
                io::stdout().flush().unwrap();
                let mut dev_type = String::new();
                io::stdin().read_line(&mut dev_type).unwrap();

                let device = Device {
                    id: dev_id.trim().to_string(),
                    device_type: dev_type.trim().to_string(),
                    location: "Facility A".to_string(),
                    status: "READY".to_string(),
                    last_seen: chrono::Local::now().to_rfc3339(),
                    capabilities: vec!["LOCK".to_string(), "UNLOCK".to_string()],
                    state: HashMap::new(),
                };

                match iot_bridge.register_device(device) {
                    Ok(_) => println!("[✓] Device registered"),
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "17" => {
                // Device command
                print!("Device ID: ");
                io::stdout().flush().unwrap();
                let mut dev_id = String::new();
                io::stdin().read_line(&mut dev_id).unwrap();

                print!("Action (LOCK/UNLOCK): ");
                io::stdout().flush().unwrap();
                let mut action = String::new();
                io::stdin().read_line(&mut action).unwrap();

                match iot_bridge.queue_command(
                    dev_id.trim(),
                    action.trim(),
                    json!({}),
                    "sig".to_string(),
                ) {
                    Ok(cmd_id) => {
                        println!("[✓] Command queued: {}", cmd_id);
                        ledger.record_entry(
                            "COMMAND",
                            "STRATEGIST",
                            action.trim(),
                            json!({"device": dev_id}),
                            "sig".to_string(),
                        );
                    }
                    Err(e) => println!("[✗] {}", e),
                }
            }
            "18" => {
                // Threat landscape
                let landscape = threat_model.threat_landscape();
                println!("\n[THREAT LANDSCAPE]");
                println!("{}", serde_json::to_string_pretty(&landscape).unwrap());
            }
            "19" => {
                // Risk assessment
                let risk = catastrophe_model.risk_assessment();
                println!("\n[RISK ASSESSMENT]");
                println!("{}", serde_json::to_string_pretty(&risk).unwrap());
            }
            "20" => {
                // Record to ledger
                ledger.record_entry(
                    "OPERATOR_LOG",
                    "badra222",
                    "CHECKPOINT",
                    json!({"note": "Manual checkpoint"}),
                    "sig".to_string(),
                );
            }
            "21" => {
                // Verify ledger
                if ledger.verify_integrity() {
                    println!("[✓] Ledger integrity confirmed");
                } else {
                    println!("[✗] TAMPERING DETECTED");
                }
            }
            "22" => {
                // View state
                println!("\n[GLOBAL STATE]");
                for (k, v) in global_state.get_current_state() {
                    println!("  {}: {}", k, v);
                }
            }
            "99" => {
                // Shutdown
                ledger.seal_block();
                println!("\n[SHUTDOWN] ITHERIS v5.0 offline at {}", chrono::Local::now());
                println!("[LEDGER] Final state sealed and immutable");
                break;
            }
            _ => println!("[!] Invalid choice"),
        }
    }
}

use chrono;
use uuid;