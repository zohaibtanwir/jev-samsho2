//! Tauri shell for "Jev plays Samurai Shodown II".
//! The Python bridge is a *script sidecar*: we spawn it from the repo with a
//! login shell so it inherits the user's environment (TYPESAFE_API_KEY lives
//! in ~/.zshenv; this app never reads it). The bridge launches MAME and owns
//! its lifetime (`--launch-mame`); Stop asks the bridge to shut both down and
//! only falls back to killing the bridge's own PID.
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{Manager, State};

pub struct Sidecar(pub Mutex<Option<Child>>);

fn repo_root() -> String {
    std::env::var("SAM2_ROOT").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_default();
        format!("{home}/projects/jev-samsho2")
    })
}

#[derive(serde::Serialize)]
pub struct Status { running: bool, pid: Option<u32>, repo: String }

#[tauri::command]
fn bridge_status(state: State<Sidecar>) -> Status {
    let mut guard = state.0.lock().unwrap();
    let running = match guard.as_mut() {
        Some(child) => matches!(child.try_wait(), Ok(None)),
        None => false,
    };
    Status { running, pid: guard.as_ref().map(|c| c.id()), repo: repo_root() }
}

/// Start the bridge (which starts MAME). Windowed MAME when `windowed` is true.
#[tauri::command]
fn start_bridge(state: State<Sidecar>, windowed: Option<bool>) -> Result<Status, String> {
    let mut guard = state.0.lock().unwrap();
    if let Some(child) = guard.as_mut() {
        if matches!(child.try_wait(), Ok(None)) {
            return Err("bridge already running".into());
        }
    }
    let repo = repo_root();
    // Pick an interpreter that has the bridge's dependencies (websockets, Pillow):
    // $SAM2_PYTHON first, then the usual Mac locations, then whatever python3 is on PATH.
    let mut flags = String::from("--seconds 0 --jev --relay --launch-mame");
    if windowed.unwrap_or(false) { flags.push_str(" --mame-window"); }
    let args = format!(
        "for p in \"$SAM2_PYTHON\" /opt/anaconda3/bin/python3 /opt/homebrew/bin/python3 python3; do \
           [ -n \"$p\" ] && \"$p\" -c 'import websockets, PIL' 2>/dev/null && exec \"$p\" -m bridge.core {flags}; \
         done; echo 'no python3 with websockets + Pillow found (set SAM2_PYTHON)' >&2; exit 3");
    std::fs::create_dir_all("/tmp/sam2").map_err(|e| e.to_string())?;
    let log = std::fs::File::create("/tmp/sam2/bridge.out").map_err(|e| e.to_string())?;
    let child = Command::new("/bin/zsh")
        .args(["-lc", &args])
        .current_dir(&repo)
        .stdout(Stdio::from(log.try_clone().map_err(|e| e.to_string())?))
        .stderr(Stdio::from(log))
        .spawn()
        .map_err(|e| format!("spawn failed: {e}"))?;
    let pid = child.id();
    std::fs::write("/tmp/sam2/pids", format!("{pid} bridge\n")).ok();
    *guard = Some(child);
    Ok(Status { running: true, pid: Some(pid), repo })
}

/// Stop: the UI has already sent {"cmd":"stop"} over the WebSocket, which
/// makes the bridge exit MAME (Lua machine:exit) and end its own loop. Wait
/// for that; after `timeout_s` kill the bridge PID (never by name).
#[tauri::command]
fn stop_bridge(state: State<Sidecar>, timeout_s: Option<u64>) -> Result<String, String> {
    let mut guard = state.0.lock().unwrap();
    let Some(child) = guard.as_mut() else { return Ok("not running".into()) };
    let deadline = Instant::now() + Duration::from_secs(timeout_s.unwrap_or(8));
    loop {
        match child.try_wait() {
            Ok(Some(status)) => { *guard = None; std::fs::remove_file("/tmp/sam2/pids").ok(); return Ok(format!("bridge exited: {status}")); }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(200)),
            Ok(None) => {
                child.kill().map_err(|e| e.to_string())?;
                let _ = child.wait();
                *guard = None; std::fs::remove_file("/tmp/sam2/pids").ok();
                return Ok("bridge killed after timeout".into());
            }
            Err(e) => return Err(e.to_string()),
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(Sidecar(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![bridge_status, start_bridge, stop_bridge])
        .on_window_event(|window, event| {
            // closing the window must not orphan the bridge / MAME
            if let tauri::WindowEvent::Destroyed = event {
                let state: State<Sidecar> = window.state();
                let taken = state.0.lock().unwrap().take();
                if let Some(mut child) = taken {
                    let _ = child.kill();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
