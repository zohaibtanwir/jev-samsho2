# Lua ⇄ bridge file protocol

Both files live in `/tmp/sam2/`. Every writer writes `<name>.tmp` and then
renames it over `<name>.json`, so a reader never sees a half-written file
(PRD §8). Readers detect a new file by the `seq` field, not by mtime.

## state.json — written by Lua every frame (sam-aug.5)

```json
{"seq": 1765, "frame": 3508, "timer": 57, "match_live": true, "gap": 241,
 "p1": {"char": "Earthquake", "x": 78, "y": 224, "health": 97, "max_health": 128,
        "rage": 17, "rage_max": 32, "action": "idle", "action_name": null,
        "action_word": 0, "action_age": 362, "airborne": false, "crouching": false},
 "p2": {"char": "Nakoruru", "x": 319, "y": 224, "health": 128, "max_health": 128,
        "rage": 0, "rage_max": 32, "action": "idle", "action_name": null,
        "action_word": 0, "action_age": 557, "airborne": false, "crouching": false},
 "action_seq": 3, "last_action": {"seq": 3, "frame": 3400, "p1": "advance", "p2": "block"}}
```

- `action` is a phase: `idle walk_fwd walk_back crouch air landing startup
  active recovery hitstun transition`. `action_name` names the attack
  (e.g. `A+B heavy slash`) while one is in progress. `action_age` is frames
  since the action word last changed.
- `x` grows to the right; the fighters start at 240 and 400 (gap 160). `y`
  is 224 on the ground and smaller in the air.
- `health` 0..128 = the on-screen bar in pixels. `rage` 0..32.
- `timer` is the on-screen round timer.
- The bridge derives "opponent's last three actions" from the `action`
  history (PRD §8).

## action.json — written by the bridge, read by Lua (sam-e8s.1)

```json
{"seq": 4, "session": 1789994000, "source": "jev", "p1": {"intent": "attack"}, "p2": {"intent": "retreat"}}
```

- `seq` must increase within a `session` (the bridge's start time); Lua applies
  a file once, when `seq` is newer than the last one it consumed in that
  session, and resets its high-water mark when `session` changes. Both sides
  delete a leftover `action.json` at startup.
- `intent` per fighter is one of `advance retreat attack block bait`, plus
  `none` (release all inputs; used by tests and Pause). A fighter key may be
  omitted to leave that fighter alone.
- `source` is free text carried through to `state.json.last_action` and the
  press log (`jev`, `reflex`, `test`, ...).
- The bridge sends intent only; all button expansion happens in Lua
  (decision 21 Sep 2026). Minimal expansion in v0 (sam-e8s.1), replaced by
  the executor in Epic 7:
  - `advance` hold toward the opponent for 20 frames
  - `retreat` / `block` hold away for 20 frames
  - `attack` tap A+B (the heavy normal for both characters)
  - `bait` tap A, then hold away for 16 frames
  "Toward" is chosen from the two `x` values each time an action is applied.
