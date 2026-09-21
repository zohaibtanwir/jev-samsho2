---
name: start-app
description: Start the app for the current build stage (MAME + Lua now; bridge + MAME later; Tauri app last). Records PIDs in /tmp/sam2/pids and refuses to start over a running instance.
disable-model-invocation: true
argument-hint: "[lua-script-path] [autoboot-delay-seconds]"
---

# start-app

**Stage this skill assumes: Stage 1 — MAME + a Lua script (PRD §13 steps 1–4).**
When the build moves to Stage 2 (bridge + MAME, PRD §13 steps 5–7) or Stage 3 (Tauri app, step 8), update this file and `stop-app` first. There is a Beads task for that; do not start a later stage with a stale skill.

## Procedure

1. `mkdir -p /tmp/sam2`
2. **Refuse if anything is still running.** If `/tmp/sam2/pids` exists, for each line `<pid> <label>` run `kill -0 <pid>`. If any process is alive, stop: print the live PIDs and tell me to run `/stop-app`. Do not start anything.
3. Launch for the current stage. Every process is started in the background and its PID appended to `/tmp/sam2/pids` as `<pid> <label>`.

   **Stage 1 launch.** Always from `~/mame` (the rompath in `mame.ini` is relative). The script is `$0` if given, otherwise the project's current main Lua script; if no script is given and none exists in the repo yet, say so and stop. Delay is `$1`, default 3.
   ```bash
   cd ~/mame && nohup mame samsho2 -window -nomaximize -skip_gameinfo -sound none \
     -autoboot_script <abs-path-to-script> -autoboot_delay <delay> \
     > /tmp/sam2/mame.log 2>&1 &
   echo "$! mame" >> /tmp/sam2/pids
   ```
   `-skip_gameinfo` is mandatory: without it MAME waits on a "press any button" info screen and nothing is hands-free. `-sound none` stays until told otherwise. Use `-video none` instead of `-window -nomaximize` only when the task explicitly needs headless MAME (PRD §5, §12 frame-grab check).

   Stage 2 (not yet): also start the Python bridge from the project folder, log to `/tmp/sam2/bridge.log`, record `<pid> bridge`.
   Stage 3 (not yet): start the Tauri app; it owns bridge + MAME itself. Record `<pid> tauri`.

4. Wait 2 seconds, then for each line in `/tmp/sam2/pids` run `kill -0 <pid>` and report `alive` / `dead` per label with its PID. If any is dead, print the last 20 lines of its log.

## Rules
- Never use `pkill`/`killall`. Never start if step 2 finds a live PID.
- Never pass or print `TYPESAFE_API_KEY`; the bridge reads it from the environment it inherits.
