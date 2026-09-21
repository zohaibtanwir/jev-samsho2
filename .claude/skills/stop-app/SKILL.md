---
name: stop-app
description: Stop only the processes listed in /tmp/sam2/pids (Stage 3 - the Tauri app, plus any bridge/MAME it left) — graceful first, force after a timeout — then confirm they are gone and clear the PID files.
disable-model-invocation: true
---

# stop-app

Assumes Stage 3: the Tauri app owns bridge and MAME. Stops exactly the PIDs recorded in `/tmp/sam2/pids` (labels `app`, `tauri-dev`, `bridge`, ...) and, if still alive afterwards, the MAME PID in `/tmp/sam2/mame.pid`. Nothing else.

## Procedure

1. If `/tmp/sam2/pids` is missing or empty and `/tmp/sam2/mame.pid` is absent: report "nothing recorded" and stop.
2. Prefer the app's own Stop: if the window is up, click Stop (`osascript ... click button "Stop" of group "panel" of UI element 1 of scroll area 1 of group 1 of group 1 of window 1` on process `app`) and wait up to 10 s — the bridge exits MAME via Lua and quits. Then continue with the file anyway.
3. Order: **bridge first, then app, then tauri-dev, then MAME** (so logs flush and nothing is orphaned). For each PID:
   - `kill -0 <pid>` fails → **already gone**.
   - else `kill -TERM <pid>`, poll `kill -0` once a second for up to 5 s → **stopped gracefully (TERM)**. The bridge handles SIGTERM and stops its MAME child (kill by that PID after 6 s). MAME itself ignores SIGTERM.
   - still alive → `kill -KILL <pid>`, poll 2 s → **force-killed (KILL)**; still alive → **FAILED**, keep the files.
4. Orphan check: if `/tmp/sam2/mame.pid` names a live process not in the pids file, report it as an orphan and stop it the same way (by that PID). Never kill by name.
5. Confirm all listed PIDs fail `kill -0`; only then `rm -f /tmp/sam2/pids /tmp/sam2/mame.pid`.
6. Report a table: label, PID, outcome, and whether the files were cleared; quote the last `/tmp/sam2/bridge.log` line (`bridge stop ...` when it went cleanly).

## Rules
- Never `pkill`, `killall`, or kill by name. Only PIDs from the files.
- Never clear the PID files while any listed process is alive.
