---
name: stop-app
description: Stop only the processes listed in /tmp/sam2/pids (Stage 2 - bridge and MAME) — graceful first, force after a timeout — then confirm they are gone and clear the PID file.
disable-model-invocation: true
---

# stop-app

Stops exactly the PIDs recorded by `start-app` / `run-lua`. Nothing else. Assumes Stage 2 (labels `mame` and `bridge`), but works on whatever the file lists.

## Procedure

1. If `/tmp/sam2/pids` is missing or empty: report "nothing recorded" and stop.
2. Stop the **bridge first, then MAME** (so the bridge's last log line is written). For each line `<pid> <label>`:
   - `kill -0 <pid>` fails → record **already gone**.
   - Otherwise `kill -TERM <pid>`, then poll `kill -0 <pid>` once a second for up to 5 s. Gone → record **stopped gracefully (TERM)**. The bridge handles SIGTERM and exits within a second; MAME 0.289 ignores SIGTERM in practice, so expect it to need the next step.
   - Still alive after 5 s → `kill -KILL <pid>`, poll up to 2 s more. Gone → record **force-killed (KILL)**. Still alive → record **FAILED to stop** and do not clear the file.
3. Confirm: run `kill -0` on every PID once more. Only if all fail (all gone) run `rm -f /tmp/sam2/pids`.
4. Report a table: label, PID, outcome (already gone / TERM / KILL / FAILED), and whether `/tmp/sam2/pids` was cleared. Quote the last line of `/tmp/sam2/bridge.log` (should read `bridge stop ...`).

## Rules
- Never `pkill`, `killall`, or kill by name. Only PIDs from the file.
- Never clear the PID file while any listed process is alive.
