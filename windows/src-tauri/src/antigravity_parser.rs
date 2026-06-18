use std::process::Command;
use std::time::Duration;
use regex::Regex;
use chrono::Utc;
use crate::models::{AntigravityUsageRaw, QuotaLaneRaw};

// On Windows, spawning a console subprocess (wmic/netstat) pops a visible
// console window for a split second. CREATE_NO_WINDOW suppresses it.
#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[cfg(target_os = "windows")]
fn hidden_command(program: &str) -> Command {
    use std::os::windows::process::CommandExt;
    let mut cmd = Command::new(program);
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd
}

#[cfg(not(target_os = "windows"))]
fn hidden_command(program: &str) -> Command {
    Command::new(program)
}

#[derive(Debug)]
struct ServerCandidate {
    pid: u32,
    csrf_token: String,
    score: i32,
}

pub fn compute() -> Option<AntigravityUsageRaw> {
    let mut servers = discover_servers();
    servers.sort_by(|a, b| b.score.cmp(&a.score));

    for server in servers {
        let ports = listening_ports(server.pid);
        for port in ports {
            if let Some(root) = fetch_user_status(port, &server.csrf_token) {
                if let Some(usage) = parse_user_status(root) {
                    return Some(usage);
                }
            }
        }
    }
    None
}

fn discover_servers() -> Vec<ServerCandidate> {
    let mut candidates = Vec::new();

    let output = if cfg!(target_os = "windows") {
        hidden_command("wmic")
            .args(&["process", "get", "ProcessId,CommandLine", "/FORMAT:CSV"])
            .output()
    } else {
        hidden_command("ps")
            .args(&["ax", "-o", "pid=,command="])
            .output()
    };

    let output = match output {
        Ok(o) => o,
        Err(_) => return candidates,
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    // compile once before iterating — Regex::new is not cheap
    let token_re = Regex::new(r"--csrf_token[=\s]+([A-Za-z0-9-]+)").expect("static regex");

    for line in stdout.lines() {
        if !line.contains("language_server") || !line.contains("--csrf_token") || !line.contains("antigravity") {
            continue;
        }

        let pid: u32 = if cfg!(target_os = "windows") {
            // wmic output CSV: Node,CommandLine,ProcessId
            let parts: Vec<&str> = line.split(',').collect();
            if parts.len() >= 3 {
                parts.last().unwrap().trim().parse().unwrap_or(0)
            } else {
                continue;
            }
        } else {
            // ps output: PID COMMAND
            let trimmed = line.trim();
            if let Some(idx) = trimmed.find(' ') {
                trimmed[..idx].parse().unwrap_or(0)
            } else {
                continue;
            }
        };

        if pid == 0 {
            continue;
        }

        if let Some(caps) = token_re.captures(line) {
            let csrf_token = caps[1].to_string();
            let mut score = 0;
            if line.contains("project_hint") || line.contains("--project_path") {
                score += 100;
            }
            if line.contains("app_data_dir") {
                score += 20;
            }
            if line.contains("enable_lsp") {
                score += 10;
            }
            candidates.push(ServerCandidate { pid, csrf_token, score });
        }
    }
    candidates
}

fn listening_ports(pid: u32) -> Vec<u16> {
    let mut ports = Vec::new();

    if cfg!(target_os = "windows") {
        if let Ok(output) = hidden_command("netstat").args(&["-ano", "-p", "TCP"]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("LISTENING") && line.contains(&format!(" {}", pid)) {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        let addr = parts[1];
                        if let Some(idx) = addr.rfind(':') {
                            if let Ok(port) = addr[idx + 1..].parse::<u16>() {
                                ports.push(port);
                            }
                        }
                    }
                }
            }
        }
    } else {
        let pid_str = pid.to_string();
        if let Ok(output) = hidden_command("lsof").args(&["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", &pid_str]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("LISTEN") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    for part in parts {
                        if part.contains("TCP") {
                            continue;
                        }
                        if part.contains(':') && !part.starts_with("TCP") {
                            if let Some(idx) = part.rfind(':') {
                                if let Ok(port) = part[idx + 1..].parse::<u16>() {
                                    ports.push(port);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ports
}

fn fetch_user_status(port: u16, csrf_token: &str) -> Option<serde_json::Value> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .ok()?;
    
    let url = format!("http://127.0.0.1:{}/exa.language_server_pb.LanguageServerService/GetUserStatus", port);
    
    let body = serde_json::json!({
        "metadata": {
            "ideName": "antigravity",
            "extensionName": "antigravity",
            "locale": "en"
        }
    });

    let res = client.post(&url)
        .header("Content-Type", "application/json")
        .header("Connect-Protocol-Version", "1")
        .header("X-Codeium-Csrf-Token", csrf_token)
        .json(&body)
        .send()
        .ok()?;

    if res.status().is_success() {
        res.json::<serde_json::Value>().ok()
    } else {
        None
    }
}

fn parse_user_status(root: serde_json::Value) -> Option<AntigravityUsageRaw> {
    let configs = root
        .get("userStatus")?
        .get("cascadeModelConfigData")?
        .get("clientModelConfigs")?
        .as_array()?;

    let mut lanes = Vec::new();

    for config in configs {
        let label = config.get("label").and_then(|v| v.as_str()).unwrap_or("Unknown").to_string();
        
        if let Some(quota) = config.get("quotaInfo") {
            let remaining = quota.get("remainingFraction").and_then(|v| v.as_f64()).unwrap_or(1.0);
            let pct = (1.0 - remaining) * 100.0;
            
            let reset_text = if let Some(rt) = quota.get("resetTime") {
                let seconds = if let Some(secs_str) = rt.get("seconds").and_then(|s| s.as_str()) {
                    secs_str.parse::<i64>().unwrap_or(0)
                } else if let Some(secs_num) = rt.get("seconds").and_then(|s| s.as_i64()) {
                    secs_num
                } else {
                    0
                };
                
                if seconds > 0 {
                    let now = Utc::now().timestamp();
                    let diff = seconds - now;
                    if diff > 0 {
                        let hours = diff / 3600;
                        let mins = (diff % 3600) / 60;
                        Some(format!("{}h {}m", hours, mins))
                    } else {
                        Some("Reset".to_string())
                    }
                } else {
                    None
                }
            } else {
                None
            };

            lanes.push(QuotaLaneRaw {
                id: label.clone(),
                label: label.clone(),
                group: None,
                pct,
                reset_text,
            });
        }
    }

    if lanes.is_empty() {
        return None;
    }

    Some(AntigravityUsageRaw {
        plan_name: root.get("userStatus").and_then(|u| u.get("planName")).and_then(|p| p.as_str()).map(|s| s.to_string()),
        lanes,
        fetched_at: Utc::now().to_rfc3339(),
    })
}
