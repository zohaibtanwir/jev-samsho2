---
name: start-app
description: Start the app for the current build stage (Stage 3 now, the Tauri app, which owns the bridge and MAME). Records PIDs in /tmp/sam2/pids and refuses to start over a running instance.
disable-model-invocation: true
argument-hint: "[--release]"
---

# start-app

**Stage this skill assumes: Stage 3 — the Tauri app (PRD §13 step 8).** The app spawns the Python bridge as a sidecar when you press **Start** in its window, and the bridge launches MAME. Stage 2 (bridge + MAME by hand) is over; for one-off Lua scripts use `/run-lua`; to run the bridge without the app: `cd ~/projects/jev-samsho2 && python3 -m bridge.core --seconds 0 --jev --relay --launch-mame` (record its PID yourself).

## Procedure

1. `mkdir -p /tmp/sam2`
2. **Refuse if anything is still running.** If `/tmp/sam2/pids` exists, for each line `<pid> <label>` run `kill -0 <pid>`; also check `/tmp/sam2/mame.pid`. If any is alive: print them, tell me to run `/stop-app`, start nothing. If none is alive, remove the stale files.
3. Launch the app and record its PID:

   **Dev build (default)** — source of truth, hot reload, Vite on :1420:
   ```bash
   cd /Users/zohaibtanwir/projects/jev-samsho2/app && source ~/.cargo/env && \
     nohup pnpm tauri dev > /tmp/sam2/tauri_dev.out 2>&1 &
   echo "$! tauri-dev" >> /tmp/sam2/pids
   ```
   then wait until `pgrep -f target/debug/app` returns a PID (up to 90 s on a cold build) and append it: `echo "<pid> app" >> /tmp/sam2/pids`.

   **`--release`** — the last `pnpm tauri build` bundle (may be stale; rebuild first if in doubt):
   ```bash
   open -n "/Users/zohaibtanwir/projects/jev-samsho2/app/src-tauri/target/release/bundle/macos/Jev plays Samurai Shodown II.app"
   ```
   then `pgrep -f "Jev plays Samurai Shodown II.app/Contents/MacOS/app"` and append `<pid> app`.

4. Confirm the window: `osascript -e 'tell application "System Events" to tell process "app" to get name of window 1'` should print `Jev plays Samurai Shodown II` (needs Accessibility, which is granted).
5. Report each PID in `/tmp/sam2/pids` as `alive`/`dead`. Say: **press Start in the window** to launch bridge + MAME (the app appends `<pid> bridge` to `/tmp/sam2/pids`; the bridge writes `/tmp/sam2/mame.pid`). Do not start the bridge by hand while the app is up.

## Where things are
- app stdout: `/tmp/sam2/tauri_dev.out` · bridge: `/tmp/sam2/bridge.out`, `/tmp/sam2/bridge.log` · MAME: `/tmp/sam2/mame.log` · Lua: `/tmp/sam2/start_match.txt` · state stream: `/tmp/sam2/state.json`

## Rules
- Never `pkill`/`killall`. Never start if step 2 finds a live PID.
- Never pass, print or write `TYPESAFE_API_KEY`; the bridge gets it from `~/.zshenv` via the login shell the app uses.
