//! ITHERIS TPM Unsealing Ceremony UI Component
//! 
//! Leptos component for TPM unsealing ceremony UI.

use leptos::*;
use std::collections::HashMap;

/// Unsealing request state
#[derive(Debug, Clone)]
pub struct UnsealingState {
    pub pcr_values: HashMap<String, Vec<u8>>,
    pub auth_input: String,
    pub is_requesting: bool,
    pub last_result: Option<bool>,
}

impl Default for UnsealingState {
    fn default() -> Self {
        let mut pcr_values = HashMap::new();
        // Initialize with placeholder PCR values
        for i in 0..8 {
            pcr_values.insert(format!("PCR{}", i), vec![0u8; 32]);
        }
        Self {
            pcr_values,
            auth_input: String::new(),
            is_requesting: false,
            last_result: None,
        }
    }
}

/// UnsealingTile - TPM Unsealing Ceremony UI
#[component]
pub fn UnsealingTile() -> impl IntoView {
    let (pcr_0, set_pcr_0) = create_signal(String::from("0000000000000000000000000000000000000000"));
    let (pcr_1, set_pcr_1) = create_signal(String::from("0000000000000000000000000000000000000000"));
    let (pcr_2, set_pcr_2) = create_signal(String::from("0000000000000000000000000000000000000000"));
    let (auth_value, set_auth_value) = create_signal(String::new());
    let (is_unsealing, set_is_unsealing) = create_signal(false);
    let (unseal_status, set_unseal_status) = create_signal::<Option<&str>>(None);

    let handle_unseal = move |_| {
        set_is_unsealing.set(true);
        
        // In a real implementation, this would call the gRPC service
        // For now, simulate the unsealing process
        spawn_local(async move {
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            set_is_unsealing.set(false);
            set_unseal_status.set(Some("UNSEALED"));
        });
    };

    view! {
        <div class="unsealing-tile">
            <div class="tile-header">
                <h3>"TPM UNSEALING"</h3>
                <span class="security-badge">"SECURE"</span>
            </div>

            <div class="unsealing-content">
                <div class="pcr-section">
                    <h4>"PCR MEASUREMENTS"</h4>
                    <div class="pcr-grid">
                        <div class="pcr-input">
                            <label>"PCR0"</label>
                            <input 
                                type="text" 
                                value=pcr_0
                                oninput=move |e| set_pcr_0.set(event_target_value(&e))
                                placeholder="SHA-256 hash"
                            />
                        </div>
                        <div class="pcr-input">
                            <label>"PCR1"</label>
                            <input 
                                type="text" 
                                value=pcr_1
                                oninput=move |e| set_pcr_1.set(event_target_value(&e))
                                placeholder="SHA-256 hash"
                            />
                        </div>
                        <div class="pcr-input">
                            <label>"PCR2"</label>
                            <input 
                                type="text" 
                                value=pcr_2
                                oninput=move |e| set_pcr_2.set(event_target_value(&e))
                                placeholder="SHA-256 hash"
                            />
                        </div>
                    </div>
                </div>

                <div class="auth-section">
                    <h4>"AUTHENTICATION"</h4>
                    <div class="auth-input-container">
                        <input 
                            type="password" 
                            value=auth_value
                            oninput=move |e| set_auth_value.set(event_target_value(&e))
                            placeholder="Enter authorization key"
                            class="auth-input"
                        />
                        <span class="auth-icon">"🔐"</span>
                    </div>
                </div>

                <div class="unseal-button-container">
                    <button 
                        class="unseal-button"
                        disabled=is_unsealing
                        on:click=handle_unseal
                    >
                        {move || if is_unsealing() { "UNSEALING..." } else { "INITIATE UNSEALING" }}
                    </button>
                </div>

                {move || {
                    if let Some(status) = unseal_status() {
                        Some(view! {
                            <div class="status-display" class:success=true>
                                <span class="status-icon">"✓"</span>
                                <span>{status}</span>
                            </div>
                        })
                    } else {
                        None
                    }
                }}
            </div>

            <div class="security-notice">
                <span class="notice-icon">"ℹ"</span>
                <span>"TPM 2.0 required for unsealing operations"</span>
            </div>
        </div>
    }
}

pub const UNSEALING_TILE_CSS: &str = r#"
.unsealing-tile {
    background: linear-gradient(135deg, #1a1a2e 0%, #0f172a 100%);
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 20px;
}

.unsealing-tile .tile-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 1px solid #334155;
}

.unsealing-tile h3 {
    color: #e2e8f0;
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 2px;
    margin: 0;
}

.security-badge {
    padding: 4px 8px;
    background: rgba(34, 197, 94, 0.2);
    color: #22c55e;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1px;
    border-radius: 4px;
}

.unsealing-content {
    display: flex;
    flex-direction: column;
    gap: 20px;
}

.pcr-section h4, .auth-section h4 {
    color: #64748b;
    font-size: 11px;
    letter-spacing: 1px;
    margin: 0 0 12px 0;
}

.pcr-grid {
    display: flex;
    flex-direction: column;
    gap: 8px;
}

.pcr-input {
    display: flex;
    align-items: center;
    gap: 12px;
}

.pcr-input label {
    min-width: 50px;
    color: #94a3b8;
    font-size: 11px;
    font-family: 'JetBrains Mono', monospace;
}

.pcr-input input {
    flex: 1;
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 4px;
    padding: 8px 12px;
    color: #22c55e;
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
}

.pcr-input input:focus {
    outline: none;
    border-color: #22c55e;
    box-shadow: 0 0 0 2px rgba(34, 197, 94, 0.2);
}

.auth-input-container {
    position: relative;
    display: flex;
    align-items: center;
}

.auth-input {
    width: 100%;
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 4px;
    padding: 12px 40px 12px 12px;
    color: #e2e8f0;
    font-size: 14px;
}

.auth-input:focus {
    outline: none;
    border-color: #3b82f6;
    box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.2);
}

.auth-icon {
    position: absolute;
    right: 12px;
    font-size: 16px;
}

.unseal-button-container {
    margin-top: 8px;
}

.unseal-button {
    width: 100%;
    padding: 14px 24px;
    background: linear-gradient(135deg, #7c3aed 0%, #5b21b6 100%);
    border: none;
    border-radius: 8px;
    color: white;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 2px;
    cursor: pointer;
    transition: all 0.3s ease;
}

.unseal-button:hover:not(:disabled) {
    background: linear-gradient(135deg, #8b5cf6 0%, #6d28d9 100%);
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(124, 58, 237, 0.4);
}

.unseal-button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
}

.status-display {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 12px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 2px;
}

.status-display.success {
    background: rgba(34, 197, 94, 0.1);
    border: 1px solid #22c55e;
    color: #22c55e;
}

.status-icon {
    font-size: 18px;
}

.security-notice {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 20px;
    padding-top: 15px;
    border-top: 1px solid #334155;
    color: #64748b;
    font-size: 11px;
}

.notice-icon {
    font-size: 14px;
}
"#;
