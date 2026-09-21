---
name: stop-app
description: Stop only the processes listed in /tmp/sam2/pids — graceful first, force after a timeout — then confirm they are gone and clear the PID file.
disable-model-invocation: true
---

# stop-app

Stops exactly the PIDs recorded by `start-app` / `run-lua`. Nothing else.

## Procedure

1. If `/tmp/sam2/pids` is missing or empty: report "nothing recorded" and stop.
2. For each line `<pid> <label>`:
   - `kill -0 <pid>` fails → record **already gone**.
   - Otherwise `kill -TERM <pid>`, then poll `kill -0 <pid>` once a second for up to 5 s. Gone → record **stopped gracefully (TERM)**.
   - Still alive after 5 s → `kill -KILL <pid>`, poll up to 2 s more. Gone → record **force-killed (KILL)**. Still alive → record **FAILED to stop** and do not clear the file.
3. Confirm: run `kill -0` on every PID once more. Only if all fail (all gone) run `rm -f /tmp/sam2/pids`.
4. Report a table: label, PID, outcome (already gone / TERM / KILL / FAILED), and whether `/tmp/sam2/pids` was cleared.

## Rules
- Never `pkill`, `killall`, or kill by name. Only PIDs from the file.
- Never clear the PID file while any listed process is alive.
