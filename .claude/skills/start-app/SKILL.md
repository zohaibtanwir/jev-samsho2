---
name: start-app
description: Start the app for the current build stage (Stage 2 now, bridge + MAME). Records PIDs in /tmp/sam2/pids and refuses to start over a running instance.
disable-model-invocation: true
argument-hint: "[--headless]"
---

# start-app

**Stage this skill assumes: Stage 2 — Python bridge + MAME running `lua/sam2.lua` (PRD §13 steps 5–7).**
Stage 1 (MAME + a probe script) is over; use `/run-lua` for one-off scripts. When the build moves to Stage 3 (Tauri app owns bridge and MAME, PRD §13 step 8), update this file and `stop-app` first (bead sam-yku.3).

## Procedure

1. `mkdir -p /tmp/sam2`
2. **Refuse if anything is still running.** If `/tmp/sam2/pids` exists, for each line `<pid> <label>` run `kill -0 <pid>`. If any is alive: print them, tell me to run `/stop-app`, start nothing. If none is alive, remove the stale file.
3. Launch, in this order, appending `<pid> <label>` to `/tmp/sam2/pids` for each:

   **MAME** — always from `~/mame` (relative rompath). Windowed by default so we can watch; `--headless` swaps `-window -nomaximize` for `-video none` (PRD §5).
   ```bash
   cd ~/mame && nohup mame samsho2 -window -nomaximize -skip_gameinfo -sound none \
     -autoboot_script /Users/zohaibtanwir/projects/jev-samsho2/lua/sam2.lua -autoboot_delay 3 \
     > /tmp/sam2/mame.log 2>&1 &
   echo "$! mame" >> /tmp/sam2/pids
   ```
   `-skip_gameinfo` is mandatory (otherwise MAME waits on a "press any button" screen). `-sound none` stays until told otherwise.

   **Bridge** — from the project folder; it waits for the match to go live (~30 s), then runs until stopped. It inherits `TYPESAFE_API_KEY` from the environment; never pass or print it.
   ```bash
   cd /Users/zohaibtanwir/projects/jev-samsho2 && nohup python3 -m bridge.core --seconds 0 --jev --relay \
     > /tmp/sam2/bridge.out 2>&1 &
   echo "$! bridge" >> /tmp/sam2/pids
   ```
   `--jev` decides with Jev (drop it for the dummy decision-maker); `--relay` serves frames + telemetry on ws://127.0.0.1:8765 for `tools/view.html` (serve that page with `python3 -m http.server 8090` from `tools/` if you want to watch in a browser; record that PID too).

4. Wait 2 s, then for each line in `/tmp/sam2/pids` run `kill -0 <pid>` and report `alive`/`dead` per label with its PID. If any is dead, print the last 20 lines of its log (`/tmp/sam2/mame.log`, `/tmp/sam2/bridge.out`).

## Where things are
- Lua log: `/tmp/sam2/start_match.txt` · state stream: `/tmp/sam2/state.json` · bridge decisions: `/tmp/sam2/bridge.log`

## Rules
- Never `pkill`/`killall`. Never start if step 2 finds a live PID.
- Never pass, print or write `TYPESAFE_API_KEY`.
