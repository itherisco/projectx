//! ITHERIS TUI - Terminal User Interface for Jarvis/ITHERIS Full OS
//! 
//! Phase 1: Low-overhead headless monitoring component
//! Implements Section 9.4 of the architecture document

use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, List, ListItem, Paragraph, Row, Table},
    Frame, Terminal,
};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use std::{
    io,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};
use tokio::sync::mpsc;
use tracing::{error, info, warn};

mod telemetry {
    use tonic::codegen::http::uri::Uri;
    
    // Simplified telemetry types - in production these would be generated from protobuf
    #[derive(Debug, Clone)]
    pub struct TelemetryData {
        pub energy_level: f64,
        pub cpu_usage: f64,
        pub memory_usage: f64,
        pub tick_rate: f64,
        pub proposals: Vec<Proposal>,
        pub warden_uptime_secs: u64,
        pub connected: bool,
    }

    #[derive(Debug, Clone)]
    pub struct Proposal {
        pub id: String,
        pub description: String,
        pub status: ProposalStatus,
        pub timestamp: i64,
    }

    #[derive(Debug, Clone, PartialEq)]
    pub enum ProposalStatus {
        Pending,
        Approved,
        Vetoed,
    }

    impl Default for TelemetryData {
        fn default() -> Self {
            Self {
                energy_level: 100.0,
                cpu_usage: 0.0,
                memory_usage: 0.0,
                tick_rate: 136.1,
                proposals: Vec::new(),
                warden_uptime_secs: 0,
                connected: false,
            }
        }
    }
}

use telemetry::{ProposalStatus, TelemetryData};

/// Application state
struct App {
    data: TelemetryData,
    should_quit: AtomicBool,
    selected_panel: usize, // 0: Metabolic, 1: Decision Spine, 2: Warden Status
    last_update: std::time::Instant,
}

impl App {
    fn new() -> Self {
        Self {
            data: TelemetryData::default(),
            should_quit: AtomicBool::new(false),
            selected_panel: 0,
            last_update: std::time::Instant::now(),
        }
    }

    fn update_telemetry(&mut self, data: TelemetryData) {
        self.data = data;
        self.last_update = std::time::Instant::now();
    }

    fn toggle_quit(&self) {
        self.should_quit.store(true, Ordering::SeqCst);
    }

    fn move_selection_up(&mut self) {
        if self.selected_panel > 0 {
            self.selected_panel -= 1;
        }
    }

    fn move_selection_down(&mut self) {
        if self.selected_panel < 2 {
            self.selected_panel += 1;
        }
    }
}

/// Render the metabolic panel
fn render_metabolic_panel<B: ratatui::backend::Backend>(
    frame: &mut Frame<B>,
    area: Rect,
    data: &TelemetryData,
    selected: bool,
) {
    let border_style = if selected {
        Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    };

    let block = Block::default()
        .title(" Metabolic Panel ")
        .borders(Borders::ALL)
        .border_style(border_style);

    let inner = block.inner(area);
    frame.render_widget(block, area);

    // Energy gauge
    let energy_gauge = Gauge::default()
        .ratio(data.energy_level / 100.0)
        .label(format!("Energy: {:.1}%", data.energy_level))
        .style(Style::default().fg(if data.energy_level > 50.0 {
            Color::Green
        } else if data.energy_level > 20.0 {
            Color::Yellow
        } else {
            Color::Red
        }))
        .block(Block::default().title("Energy"));

    // CPU and Memory info
    let metrics = vec![
        Line::from(vec![
            Span::raw("CPU Usage: "),
            Span::styled(
                format!("{:.1}%", data.cpu_usage),
                Style::default().fg(Color::LightBlue),
            ),
        ]),
        Line::from(vec![
            Span::raw("Memory: "),
            Span::styled(
                format!("{:.1}%", data.memory_usage),
                Style::default().fg(Color::LightMagenta),
            ),
        ]),
        Line::from(vec![
            Span::raw("Tick Rate: "),
            Span::styled(
                format!("{:.1} Hz", data.tick_rate),
                Style::default().fg(Color::LightGreen),
            ),
        ]),
    ];

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(1),
        ])
        .split(inner);

    frame.render_widget(energy_gauge, chunks[0]);
    frame.render_widget(
        Paragraph::new(metrics[0].clone()).block(Block::default().title("CPU")),
        chunks[1],
    );
    frame.render_widget(
        Paragraph::new(metrics[1].clone()).block(Block::default().title("Memory")),
        chunks[2],
    );
    frame.render_widget(
        Paragraph::new(metrics[2].clone()),
        chunks[3],
    );
}

/// Render the decision spine panel
fn render_decision_spine_panel<B: ratatui::backend::Backend>(
    frame: &mut Frame<B>,
    area: Rect,
    data: &TelemetryData,
    selected: bool,
) {
    let border_style = if selected {
        Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    };

    let block = Block::default()
        .title(" Decision Spine ")
        .borders(Borders::ALL)
        .border_style(border_style);

    let inner = block.inner(area);
    frame.render_widget(block, area);

    // Create proposal list
    let proposals: Vec<ListItem> = if data.proposals.is_empty() {
        vec![ListItem::new(Line::from(vec![
            Span::styled("No proposals pending", Style::default().fg(Color::DarkGray)),
        ]))]
    } else {
        data.proposals
            .iter()
            .map(|p| {
                let status_color = match p.status {
                    ProposalStatus::Pending => Color::Yellow,
                    ProposalStatus::Approved => Color::Green,
                    ProposalStatus::Vetoed => Color::Red,
                };
                let status_str = match p.status {
                    ProposalStatus::Pending => "PENDING",
                    ProposalStatus::Approved => "APPROVED",
                    ProposalStatus::Vetoed => "VETOED",
                };
                ListItem::new(Line::from(vec![
                    Span::raw(format!("{}: ", p.id)),
                    Span::styled(&p.description, Style::default().fg(Color::White)),
                    Span::raw(" ["),
                    Span::styled(status_str, Style::default().fg(status_color)),
                    Span::raw("]"),
                ]))
            })
            .collect()
    };

    let list = List::new(proposals)
        .block(Block::default())
        .start_corner(ratatui::layout::Corner::TopLeft);

    frame.render_widget(list, inner);
}

/// Render the warden status panel
fn render_warden_panel<B: ratatui::backend::Backend>(
    frame: &mut Frame<B>,
    area: Rect,
    data: &TelemetryData,
    selected: bool,
) {
    let border_style = if selected {
        Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    };

    let block = Block::default()
        .title(" Warden Status ")
        .borders(Borders::ALL)
        .border_style(border_style);

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let uptime = format_duration(data.warden_uptime_secs);
    let connection_status = if data.connected {
        Span::styled("CONNECTED", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
    } else {
        Span::styled("DISCONNECTED", Style::default().fg(Color::Red).add_modifier(Modifier::BOLD))
    };

    let status_lines = vec![
        Line::from(vec![
            Span::raw("Status: "),
            connection_status,
        ]),
        Line::from(vec![
            Span::raw("Uptime: "),
            Span::styled(uptime, Style::default().fg(Color::LightCyan)),
        ]),
        Line::from(vec![
            Span::raw("Endpoint: "),
            Span::styled("localhost:9090", Style::default().fg(Color::DarkGray)),
        ]),
        Line::from(vec![
            Span::raw("Refresh: "),
            Span::styled("10 Hz", Style::default().fg(Color::DarkGray)),
        ]),
    ];

    let paragraph = Paragraph::new(status_lines).block(Block::default());
    frame.render_widget(paragraph, inner);
}

fn format_duration(secs: u64) -> String {
    let hours = secs / 3600;
    let minutes = (secs % 3600) / 60;
    let seconds = secs % 60;
    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}

/// Main render function
fn render<B: ratatui::backend::Backend>(frame: &mut Frame<B>, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Min(10),  // Main content
            Constraint::Length(3), // Footer
        ])
        .split(frame.area());

    // Header
    let header = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(" ITHERIS ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Span::styled(" Jarvis/ITHERIS Full OS Interface ", Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled(" Phase 1: TUI Monitor ", Style::default().fg(Color::DarkGray)),
        ]),
    ])
    .block(Block::default().borders(Borders::ALL).title(" ITHERIS TUI "))
    .style(Style::default().bg(Color::Black));
    frame.render_widget(header, chunks[0]);

    // Main content - split into 3 panels
    let main_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(33),
            Constraint::Percentage(34),
            Constraint::Percentage(33),
        ])
        .split(chunks[1]);

    render_metabolic_panel(frame, main_chunks[0], &app.data, app.selected_panel == 0);
    render_decision_spine_panel(frame, main_chunks[1], &app.data, app.selected_panel == 1);
    render_warden_panel(frame, main_chunks[2], &app.data, app.selected_panel == 2);

    // Footer
    let footer = Paragraph::new(Line::from(vec![
        Span::raw("["),
        Span::styled("↑/↓", Style::default().fg(Color::Yellow)),
        Span::raw(" Navigate ] "),
        Span::raw("["),
        Span::styled("q", Style::default().fg(Color::Yellow)),
        Span::raw(" Quit ] "),
        Span::raw("| "),
        Span::styled("Warden: localhost:9090", Style::default().fg(Color::DarkGray)),
    ]))
    .block(Block::default().borders(Borders::ALL).title(" Controls "));
    frame.render_widget(footer, chunks[2]);
}

/// Simulate telemetry data for demo purposes
/// In production, this would connect to the actual gRPC endpoint
fn generate_demo_telemetry() -> TelemetryData {
    use std::time::{SystemTime, UNIX_EPOCH};
    
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Generate some demo proposals
    let proposals = vec![
        telemetry::Proposal {
            id: "PROP-001".to_string(),
            description: "Optimize memory allocation".to_string(),
            status: ProposalStatus::Pending,
            timestamp: now as i64,
        },
        telemetry::Proposal {
            id: "PROP-002".to_string(),
            description: "Approve network request".to_string(),
            status: ProposalStatus::Approved,
            timestamp: (now - 10) as i64,
        },
        telemetry::Proposal {
            id: "PROP-003".to_string(),
            description: "Reject unsafe shell command".to_string(),
            status: ProposalStatus::Vetoed,
            timestamp: (now - 30) as i64,
        },
    ];

    // Simulate varying metrics
    let time_factor = (now % 60) as f64 / 10.0;
    
    TelemetryData {
        energy_level: 75.0 + (time_factor.sin() * 20.0),
        cpu_usage: 15.0 + (time_factor.cos() * 10.0),
        memory_usage: 40.0 + (time_factor.sin() * 5.0),
        tick_rate: 136.1,
        proposals,
        warden_uptime_secs: now % 86400, // Reset daily
        connected: true,
    }
}

#[tokio::main]
async fn main() -> io::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    info!("Starting ITHERIS TUI - Phase 1 Monitor");

    // Set up terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(
        stdout,
        EnterAlternateScreen,
        EnableMouseCapture
    )?;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create application state
    let mut app = App::new();
    
    // Set up signal handler for graceful shutdown
    let app_ref = &app;
    
    // Main event loop
    let result = run_app(&mut terminal, app).await;

    // Cleanup
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(e) = result {
        error!("Application error: {}", e);
    }

    info!("ITHERIS TUI shutdown complete");
    Ok(())
}

async fn run_app<B: ratatui::backend::Backend>(
    terminal: &mut Terminal<B>,
    mut app: App,
) -> io::Result<()> {
    // Tick rate: 10 Hz (100ms intervals)
    let tick_rate = Duration::from_millis(100);
    let mut last_tick = std::time::Instant::now();
    
    // Demo mode: Generate simulated telemetry
    let mut demo_mode = true;
    
    loop {
        // Render the UI
        terminal.draw(|f| render(f, &app))?;

        // Check for timeout
        let timeout = tick_rate
            .checked_sub(last_tick.elapsed())
            .unwrap_or(Duration::ZERO);

        // Poll for events with timeout
        if event::poll(timeout).map_err(|e| io::Error::new(io::ErrorKind::Other, e))? {
            if let Event::Key(key) = event::read().map_err(|e| io::Error::new(io::ErrorKind::Other, e))? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Char('Q') => {
                            app.toggle_quit();
                            break;
                        }
                        KeyCode::Up | KeyCode::Char('k') => {
                            app.move_selection_up();
                        }
                        KeyCode::Down | KeyCode::Char('j') => {
                            app.move_selection_down();
                        }
                        _ => {}
                    }
                }
            }
        }

        // Update telemetry (demo mode or try gRPC)
        if last_tick.elapsed() >= tick_rate {
            let telemetry = if demo_mode {
                // In demo mode, generate simulated data
                generate_demo_telemetry()
            } else {
                // In production, would connect to gRPC here
                // For now, fall back to demo
                generate_demo_telemetry()
            };
            
            app.update_telemetry(telemetry);
            last_tick = std::time::Instant::now();
        }

        // Check quit flag
        if app.should_quit.load(Ordering::SeqCst) {
            break;
        }
    }

    Ok(())
}
