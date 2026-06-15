mod claude_parser;
mod models;
mod tray;

use models::ClaudeLocalUsage;
use tauri::Manager;

#[tauri::command]
fn get_claude_local_usage() -> ClaudeLocalUsage {
    claude_parser::compute()
}

#[tauri::command]
fn save_window_position(app: tauri::AppHandle, x: i32, y: i32) {
    if let Ok(data_dir) = app.path().app_data_dir() {
        let _ = std::fs::create_dir_all(&data_dir);
        let _ = std::fs::write(
            data_dir.join("window_position.json"),
            format!(r#"{{"x":{},"y":{}}}"#, x, y),
        );
    }
}

#[tauri::command]
fn get_saved_position(app: tauri::AppHandle) -> Option<serde_json::Value> {
    let data_dir = app.path().app_data_dir().ok()?;
    let content = std::fs::read_to_string(data_dir.join("window_position.json")).ok()?;
    serde_json::from_str(&content).ok()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

    // Ctrl+Shift+U on Windows/Linux, Cmd+Shift+U on macOS
    #[cfg(target_os = "macos")]
    let toggle_mod = Modifiers::SUPER | Modifiers::SHIFT;
    #[cfg(not(target_os = "macos"))]
    let toggle_mod = Modifiers::CONTROL | Modifiers::SHIFT;

    let toggle_shortcut = Shortcut::new(Some(toggle_mod), Code::KeyU);

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        // Register global shortcut with handler
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(move |app, shortcut, event| {
                    if event.state() != ShortcutState::Pressed {
                        return;
                    }
                    if shortcut.matches(Modifiers::SHIFT, Code::KeyU) {
                        // matches any modifier+Shift+U — filter to our shortcut only
                        let _ = shortcut; // suppress unused warning
                    }
                    // Toggle window visibility
                    if let Some(win) = app.get_webview_window("main") {
                        let visible = win.is_visible().unwrap_or(false);
                        if visible {
                            let _ = win.hide();
                        } else {
                            let _ = win.show();
                            let _ = win.set_focus();
                        }
                    }
                })
                .build(),
        )
        .setup(move |app| {
            tray::setup(app)?;

            // Restore saved window position
            if let Some(win) = app.get_webview_window("main") {
                if let Ok(data_dir) = app.path().app_data_dir() {
                    if let Ok(content) =
                        std::fs::read_to_string(data_dir.join("window_position.json"))
                    {
                        if let Ok(pos) = serde_json::from_str::<serde_json::Value>(&content) {
                            let x = pos["x"].as_i64().unwrap_or(100) as i32;
                            let y = pos["y"].as_i64().unwrap_or(100) as i32;
                            let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
                        }
                    }
                }
            }

            // Register global shortcut
            app.handle()
                .global_shortcut()
                .register(toggle_shortcut)
                .ok();

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_claude_local_usage,
            save_window_position,
            get_saved_position,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
