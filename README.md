# Jev plays Samurai Shodown II

Two [Jev](https://typesafe.ai) agents fight each other in Samurai Shodown II, live, inside a macOS app,
with a panel showing every decision: what each agent chose, how sure it was, how long it took and what it cost.

Press **Start** and about 40 seconds later Earthquake (P1) and Nakoruru (P2) are fighting with no human input.
Same model, same questions, two very different bodies.

**Status:** v1 complete — 37 of 40 beads closed (`bd list --status closed`). Open: one performance
investigation (`sam-yku.11`) and two v2 items (specials, anti-air). `PRD.md` is the spec and the source of truth.

---

## Requirements

Everything below was true on the development Mac (MacBook Air M3, macOS Tahoe) as of 2 Oct 2026.

| What | Notes |
|---|---|
| MAME 0.289 with `samsho2` | In `~/mame` with ROMs in `~/mame/roms`. The rompath in `mame.ini` is relative, **so MAME must be launched from `~/mame`** — every script here does. `mame -verifyroms samsho2` passes. |
| Python 3.12 | Plus `websockets` and `Pillow` (`bridge/requirements.txt`). Nothing else; the rest is stdlib. |
| `TYPESAFE_API_KEY` | In the environment (e.g. `~/.zshenv`). Never printed, logged or written to a file. |
| Rust + Node + pnpm | Only to build the desktop app (`rustup`, Node 22, pnpm 11). Not needed for the headless stack. |

## Quick start

### The app

```bash
open "/Applications/Jev plays Samurai Shodown II.app"
```

Press **Start**. A small MAME window (320×272) appears while the Lua script coins up, picks the two
fighters and starts the match; the fight then streams into the app at 30 fps with the panel live.
**Pause / Resume**, **Reset** (back to round 1, full health) and **Stop** behave as in PRD §6.

To build it yourself:

```bash
cd app && source ~/.cargo/env && pnpm install && pnpm tauri build
```

The bundle lands in `app/src-tauri/target/release/bundle/` (`.app` and `.dmg`). See [app/README.md](app/README.md)
for the dev loop (`pnpm tauri dev`) and how the Python bridge is spawned as a sidecar.

### Headless, no app

```bash
cd ~/projects/jev-samsho2
python3 -m bridge.core --seconds 0 --jev --relay --launch-mame
```

The bridge launches MAME itself and serves:

- `http://127.0.0.1:8766/stream` — the game as MJPEG (open [tools/mjpeg.html](tools/mjpeg.html))
- `ws://127.0.0.1:8765` — telemetry JSON and control commands (open [tools/view.html](tools/view.html)
  through a local HTTP server; a `file://` page cannot open the socket)

Stop it with `{"seq": n, "cmd": "stop"}` written to `/tmp/sam2/cmd.json`, or Ctrl-C.
Swap `--jev` for nothing to run the dummy decision-maker and spend no tokens.

### Tests

```bash
python3 -m unittest discover -s bridge/tests -t .     # 31 tests, no network, no MAME
```

## How it works

```
MAME + lua/sam2core.lua            Python bridge (bridge/)                 UI
──────────────────────            ──────────────────────                  ──
reads fighter state ──► /tmp/sam2/state.json ──► Jev, 3 Hz per fighter ──► WebSocket :8765 (telemetry, controls)
presses buttons     ◄── /tmp/sam2/action.json ◄── intent only
grabs every 2nd frame ► frame.raw ────────────► JPEG ─────────────────────► MJPEG :8766 (game view)
                        control.json ◄───────── pause / resume / reset / stop
```

- **Lua** (`lua/sam2core.lua`) runs inside MAME every frame: reads the memory map, writes `state.json`,
  reads `action.json`, expands intents into button presses (`lua/executor.lua`), runs the block-only
  reflex layer, grabs frames. Files are written `.tmp` then renamed, so neither side reads a half-written file.
- **The bridge** (`bridge/core.py`) never blocks the game: it polls state, calls Jev for both fighters in
  parallel on keep-alive connections (`bridge/jev.py`, `bridge/jevdm.py`), applies the newest answer and
  discards older ones, and keeps the telemetry accounts (`bridge/telemetry.py`).
- **Jev** gets two questions per fighter per tick: `opponent_recovering` (noul) and `action`
  (choice: advance / retreat / attack / block / bait). The bridge sends *intent only* — every button is
  chosen in Lua, because only Lua sees every frame.
- **The app** (`app/`) is a Tauri 2 shell: it spawns the bridge as a sidecar, shows the MJPEG stream in an
  `<img>` and the panel from the telemetry, and sends control commands.

The file contract is written down in [docs/protocol.md](docs/protocol.md).

## What was reverse-engineered

The game's memory was mapped from scratch with a Lua RAM-diff harness (`lua/ramsearch.lua`); the findings
live in code, with the bead that proved each one in its comments:

- [`lua/memmap.lua`](lua/memmap.lua) — the fighter objects **move between rounds**, so everything is read
  through two pointers (`0x100A46`, `0x100A4A`) with fixed offsets: x `+0x4E`, y `+0x50`, health `+0xBA`,
  state `+0xC4`, rage `+0xF0`; round timer at `0x100AC6` in BCD.
- [`lua/moveids.lua`](lua/moveids.lua) — the action word decodes as kind + id: movement (idle, walk,
  crouch, airborne, landing), attack (A, B, C, D, A+B) and hit stun. The ids are **shared** by both
  characters; only the timings differ, so "in recovery" is decoded from the age of the move.
- [`lua/moves_earthquake.lua`](lua/moves_earthquake.lua) / [`lua/moves_nakoruru.lua`](lua/moves_nakoruru.lua) —
  what each button actually does, measured from damage, not assumed. The heavy normal is the **A+B chord**
  for both fighters.

Every item in PRD §12 "Not yet verified" was verified; the beads carry the evidence
(`bd show sam-aug.5`, `bd show sam-amj.4`, …).

## Repo layout

| Path | What |
|---|---|
| `PRD.md` | The spec. Source of truth. |
| `lua/` | Everything that runs inside MAME. `sam2.lua` is the entry point; `sam2core.lua` the core; the `*_check.lua` and `*_probe.lua` files are the experiments that produced the facts. |
| `bridge/` | The Python bridge: `core.py` (loop, controls), `jev.py` (API client), `jevdm.py` (3 Hz pools, newest wins), `telemetry.py` (panel figures), `relay.py` + `mjpeg.py` (video), `tests/`. |
| `app/` | Tauri 2 + React + TypeScript desktop app. |
| `tools/` | Test drivers and viewers: `acceptance.py` (the PRD §10 run), `control_test.py`, `executor_test.py`, `view.html`, `mjpeg.html`. |
| `docs/protocol.md` | The `state.json` / `action.json` / `control.json` contract. |
| `.claude/skills/` | `start-app`, `stop-app`, `run-lua`, `close-task`. |

`/tmp/sam2/` is the runtime scratch folder (state, frames, logs, PIDs). Frame files go to
`/Volumes/sam2ram` when that RAM disk exists, otherwise `/tmp/sam2`.

## Telemetry and cost

The panel shows, per fighter: current action with its probabilities, the `opponent_recovering` value,
buttons held and total presses by source (Jev or reflex), response time (last and p50), decision time —
labelled **estimated**, because the API returns no timing field, so it is the round trip minus a TCP
baseline measured at startup — calls made, stale responses discarded, tokens and cost.

Measured: round trip p50 **353 ms** (`bd show sam-l4r.2`), ~873 input and ~73 output tokens per call
(`bd show sam-yku.7`: 36,656 in / 3,075 out over 42 calls), input billed at $0.042/M and **output at zero**.
A full session — two matches, both fighters at 3 Hz — cost **$0.036** (`bd show sam-yku.9`, acceptance run 3).

## Known limits

- The whole thing is unsigned and Mac-only; Gatekeeper needs a right-click → Open the first time.
- Emulation speed and view fps sit at 100% and 30 fps by median, but about 2% of seconds dip
  (worst seen 89% and 16 fps) under the built app. Tracked in `sam-yku.11`.
- Earthquake loses more often than not: his heavy slash whiffs at close range and his 78-frame recovery
  is punishable. A range check in the executor would even it up; it is not done.
- No special moves and no anti-air in v1 (PRD §4, "Deferred to v2": `sam-ocu.1`, `sam-ocu.2`).
- The reflex layer blocks but never crouch-blocks: lows are not decoded.

## Working on it

Tasks live in [Beads](https://github.com/gastownhall/beads), not in markdown:

```bash
bd ready          # what can be worked on now
bd show <id>      # one task with its acceptance criteria and evidence
bd list --status closed
```

A task closes only when its acceptance criteria are met and the close note names the file or command
output that proves it — see `CLAUDE.md` for the rules this project is built under.
