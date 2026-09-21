---
name: run-lua
description: Run one Lua script against samsho2 in MAME (windowed, from ~/mame, via -autoboot_script) with the same PID bookkeeping as start-app, and report where the script's output went.
disable-model-invocation: true
argument-hint: "<lua-script-path> [autoboot-delay-seconds]"
---

# run-lua

Runs `$0` against `samsho2`. Delay is `$1`, default 3 seconds. Use this for one-off probes and per-task test scripts; use `/start-app` for the app itself.

## Procedure

1. Resolve `$0` to an absolute path and confirm it exists; if not, stop and say so.
2. `mkdir -p /tmp/sam2`
3. Same guard as `start-app`: if any PID in `/tmp/sam2/pids` is alive (`kill -0`), refuse and tell me to run `/stop-app`.
4. Launch from `~/mame`, windowed:
   ```bash
   cd ~/mame && nohup mame samsho2 -window -nomaximize -skip_gameinfo -sound none \
     -autoboot_script <abs-script> -autoboot_delay <delay> \
     > /tmp/sam2/mame.log 2>&1 &
   echo "$! mame" >> /tmp/sam2/pids
   ```
   `-skip_gameinfo` is mandatory (otherwise MAME waits on a "press any button" info screen); `-sound none` stays until told otherwise. Add other MAME flags only when the task names them (e.g. `-video none` for the headless frame-grab check).
5. Wait 2 s, `kill -0` the PID, report `alive`/`dead` with the PID. If dead, print the last 20 lines of `/tmp/sam2/mame.log`.
6. Report where output is:
   - MAME stdout/stderr, including Lua `print()`: `/tmp/sam2/mame.log`
   - Any file the script itself writes: read the script for its output path(s) (e.g. `probe.lua` → `/tmp/sam2/probe.txt`) and name them explicitly.

MAME stays running until `/stop-app` (or the script calls `manager.machine:exit()`). Say which applies.

## Rules
- Never `pkill`/`killall`. Never start over a live PID.
- Never print or write `TYPESAFE_API_KEY`.
