@AGENTS.md

# Jev plays Samurai Shodown II — project rules

## Source of truth
- `PRD.md` is the source of truth. Do not change it without my approval.
- Beads is the only place tasks live. No markdown TODO lists.

## Planning vs execution
- Planning and execution are separate. Never claim or start a task until I have approved the plan.
- A task closes only when its acceptance criteria are met. Close notes must name the file or command output that proves it. Use the `close-task` skill; it is the only way a bead gets closed.
- When stating something as fact, name the artifact. When inferring, say so.

## Git
- Commit messages end with the bead ID, e.g. `Make P1 walk right from Lua (sam-a1b2)`.
- Never use silent git flags such as `-q`.
- No git remote exists. Commit locally, never push. Ignore the push steps in `AGENTS.md` until a remote is added.

## Secrets
- The Jev API key is in the `TYPESAFE_API_KEY` environment variable. Never print it, log it, or write it to any file.

## Known environment
- MacBook Air M3, macOS Tahoe.
- Beads is already installed. Do not install it.
- MAME 0.289 is installed. The working folder is `~/mame`. ROMs are in `~/mame/roms`. The rompath in `~/mame/mame.ini` is relative, so MAME must be launched from `~/mame`.
- `samsho2` verifies as good: `mame -verifyroms samsho2`.
- Existing artifacts; read them before planning:
  - `~/mame/probe.lua` and `/tmp/sam2/probe.txt`: device list, ioport field names, file IO test. `/tmp` may be cleared by a reboot; if `probe.txt` is gone, say so, do not rerun it.
  - `~/projects/jev_latency.py` and `~/projects/jev_sample_response.json`: Jev API contract, latency results, confirmed response shape.
- Runtime scratch folder is `/tmp/sam2`. Process PIDs started by the `start-app` / `run-lua` skills live in `/tmp/sam2/pids`.
