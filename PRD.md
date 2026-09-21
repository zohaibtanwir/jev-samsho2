# PRD — Jev Plays Samurai Shodown II

**Status:** Draft v2
**Date:** 21 Sep 2026
**Owner:** Zohaib Tanwir

---

## 1. Goal

A desktop app. Press Start, Samurai Shodown II loads inside the app window, and two Jev agents play **Earthquake vs Nakoruru** live, with a panel below showing exactly what each Jev is doing.

## 2. Why

Show a reflex model making real-time fighting decisions from game state alone, and show that the same model, with the same questions, adapts to two very different fighters.

Earthquake and Nakoruru were chosen for contrast: large, slow and long-reaching against small, fast and mobile. That characterisation is from general knowledge of the roster, not checked in-game.

## 3. Feasibility

| Requirement | Status | Evidence |
|---|---|---|
| Emulator runs the game on the MacBook Air | Proven | `mame -str 30` → 100% speed. `-nothrottle` → 1446% |
| Script can press buttons | Documented, not executed | `field:set_value()` in MAME 0.289 Lua Input docs. Field names in `probe.txt` |
| Script can read game memory | Proven | `maincpu` program space reads in `probe.txt` |
| Script can exchange files with Python | Proven | `probe.txt` — FILE IO PASS, `os.rename` true |
| Script runs every frame | Proven | `probe.txt` — frame notifier PASS |
| Script can grab frames | Documented, not executed | `video:pixels()` added to MAME Lua in PR #5334 |
| Jev fast enough | Proven | `jev_latency.py` — 356 ms p50, 439 ms p99, ~59 ms inference |
| Jev reads a fight correctly | Proven, one sample | `jev_sample_response.json` — whiff punish, attack 0.80 |

## 4. Scope

**In**
- One game, Earthquake vs Nakoruru, Jev vs Jev
- Start, Pause, Reset, Stop controls
- Game view inside the app, single window
- Live telemetry panel
- Runs locally on the MacBook Air

**Out**
- Sound
- Other games or characters
- Human vs Jev
- Recording, hosting, sharing
- Training or tuning
- Special moves. Executor tables cover movement and normal attacks only
- Anti-air. The v1 reflex layer is block only

**Deferred to v2**
- Special-move tables per character, each move verified by an executor test
- Anti-air in the reflex layer

## 5. Stack

| Layer | Choice |
|---|---|
| App shell | Tauri 2 — native macOS app with a web UI |
| UI | React + TypeScript |
| Game view | Lua `video:pixels()` → bridge → JPEG → WebSocket → canvas, 30 fps |
| Bridge | Python, runs as a Tauri sidecar |
| Emulator | MAME 0.289, `-video none`, Lua script via `-autoboot_script` |
| Model | Jev via `POST https://api.typesafe.ai/v1/systemone` |

## 6. Controls

| Button | Behaviour |
|---|---|
| **Start** | Launches bridge and MAME, inserts coins, starts both players, selects Earthquake for P1 and Nakoruru for P2, begins the match |
| **Pause / Resume** | Freezes the game and stops Jev calls |
| **Reset** | Reloads a save state taken at match start. Round 1, full health, telemetry cleared |
| **Stop** | Shuts down MAME and the bridge. Panel keeps final totals |

**Rules**
- A Jev call in flight when Pause, Reset or Stop is pressed is discarded on return. It must never press buttons in a new round.
- Discarded calls still count toward tokens and cost.
- Pause, Reset and Stop are disabled until a match is running.

## 7. Telemetry panel

P1 and P2 side by side, each headed with its character name.

**Match bar** — round timer, both health bars, emulation speed, view fps.

**Decision**
- Current action, and how long ago it was decided
- Probability bar for every action option
- Bar for each yes/no question

**Buttons**
- Buttons held right now
- Total buttons pressed
- Source of each press: Jev or reflex layer

**Timing**
- Response time — full round trip, last and p50
- Decision time — Jev inference, **estimated** as round trip minus network. The API returns no timing field, so this is labelled as an estimate on screen
- Calls made, stale responses discarded

**Usage**
- Input and output tokens, running totals
- Cost, running total

## 8. How it works

1. **Lua script** reads fighter state from memory every frame, writes `/tmp/sam2/state.json`, reads `/tmp/sam2/action.json`, presses buttons. Files are written as `.tmp` then renamed, so neither side reads a half-written file.
2. **Lua script** also grabs every second frame with `video:pixels()` and writes it to `/tmp/sam2/frame.raw` the same way.
3. **Bridge** reads state, calls Jev for both fighters in parallel, writes the action back. Never blocks the game.
4. **Bridge** reads each frame, compresses to JPEG, sends it to the UI over the WebSocket along with telemetry.
5. **Jev** is called 3 times a second per fighter. Newest answer wins; older replies are dropped.
6. **Executor** turns Jev's intent into button presses over the following frames, using a separate move table per character.
7. **Reflex layer** handles anything faster than Jev can react. In v1 that is one rule: block an incoming hit. Plain rules, every frame. Anti-air is v2.

**Why a reflex layer:** Jev's round trip from Pune is ~21 frames at p50. Anti-air needs ~6. Jev sets strategy; local rules handle reflexes.

**Per-character work**
- Memory map: health and position are expected to sit in player-slot memory, shared by both characters. Inference, not verified.
- Move state: move IDs are per character. "In recovery" must be decoded for both.
- Executor: normals only in v1. Which attack each of A, B, C, D produces is recorded per character from observation, not assumed. Intent `attack` maps to that character's heavy normal as observed. Special-move sequences are v2.
- Questions: unchanged. The action set is generic.

## 9. Jev contract

**State per tick** — timer; for each fighter: character name, position, health, rage, current action, airborne, crouching; gap between fighters; opponent's last three actions.

**Questions per tick** — identical for both fighters
- `opponent_recovering` — noul: is the opponent in recovery from a missed attack
- `action` — choice: advance, retreat, attack, block, bait

**Wire shape, confirmed against a live response**
- Choice criteria: dict keyed by option
- Score criteria: list, 0-indexed
- Noul answers carry no confidence field
- Score values are fractional

**Cost** — ~888 input tokens per call, ~$0.000037 per call, ~$0.013 per 60-second round at 3 Hz for both fighters.

## 10. Success criteria

- One press of Start reaches a live Earthquake vs Nakoruru match
- A full match runs with no human input
- Game holds 100% speed with the panel and frame view running
- View holds 30 fps
- Every panel figure updates live and traces to a real call
- Pause, Reset and Stop behave as in section 6, with no stale presses after Reset

## 11. Decisions

| # | Decision | Outcome |
|---|---|---|
| D1 | How the two fighters differ | Different characters: Earthquake (P1) vs Nakoruru (P2). Same model, same questions. A style flag may be layered on later |
| D2 | Game view | Lua `video:pixels()`, MAME with no window, no sound |

## 12. Not yet verified

| Item | How to verify |
|---|---|
| `set_value()` moves a character in this game | Lua script holds `P1 Right` and watches the character walk |
| `video:pixels()` works with `-video none` | Grab one frame, write it out, open it |
| Frame file plus Jev files don't slow the game | Run both, watch emulation speed |
| Memory addresses for health, position, move state | RAM search during a live match |
| Move IDs for Earthquake and Nakoruru | RAM search per character |
| Save and load state from Lua, for Reset | Read MAME Lua core docs, then test |
| Character contrast holds in play | Watch a match |

## 13. Build order

1. Make a character move from Lua
2. Lua selects Earthquake and Nakoruru and starts the match
3. Grab one frame with `video:pixels()` under `-video none`
4. Find the memory addresses
5. Bridge with a dummy decision-maker
6. Swap in Jev
7. Executor move tables and reflex layer
8. Tauri shell, controls, frame view, panel

## 14. Work tracking — Beads

All tasks live in Beads (`bd`). Not in this document, not in markdown TODO lists. Beads is already installed on the development Mac.

### 14.1 One-time setup

Run from the project folder `~/projects/jev-samsho2`:

1. `git init` if the folder is not already a repo
2. `bd init --prefix sam` — creates the Beads database, writes `AGENTS.md` and Claude Code hooks. IDs look like `sam-a1b2`
3. Optional: `bd metrics off` — Beads sends anonymous command-usage metrics by default

### 14.2 Loading the plan

The build order in section 13 is broken into 36 tasks, T01–T36, in `seed_beads.py`. Each has a description, acceptance criteria and blocking dependencies.

1. `python3 seed_beads.py --dry-run` — prints the plan, creates nothing
2. `python3 seed_beads.py` — creates all tasks and links dependencies
3. `bd ready` — must list exactly three tasks: T01 walk right from Lua, T08 grab one frame, T28 Tauri shell

**Checks built into the seeder**
- Writes `.beads-seed-map.json` mapping T01–T36 to bead IDs, and refuses to run a second time so duplicates cannot be created. `--force` overrides
- If `bd create --json` does not return an ID, it stops and prints the raw output. That flag has not been verified against the installed version
- If `bd ready` lists most of the 36 tasks instead of three, dependency direction in `bd dep add` is reversed and the seeder needs fixing. The Beads README gives the form `bd dep add <child> <parent>` without stating which side blocks

### 14.3 Working the tasks

| Step | Command |
|---|---|
| See what can be worked on | `bd ready` |
| Read a task | `bd show <id>` |
| Take a task | `bd update <id> --claim` |
| Add evidence or findings | `bd update <id> --notes "..."` |
| Finish a task | `bd close <id> --reason "..."` |
| Add a task that was missed | `bd create "Title" -p <1-2> -t task`, then `bd dep add` to place it |

Do not use `bd edit` — it opens an interactive editor that agents cannot drive.

### 14.4 Rules

- A task closes only when its acceptance criteria are met, with evidence in its notes. Evidence names the artifact: a file, a command output, a screenshot
- Items in section 12, "Not yet verified", are closed by the task that verifies them. The verification result goes in that task's notes
- Commits reference the bead ID at the end, e.g. `Make P1 walk right from Lua (sam-a1b2)`
- If this PRD changes, update the affected beads. Do not re-seed
- Priority: P1 is on the critical path to a running match, P2 is everything else
