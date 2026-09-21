-- button_probe.lua  (bead sam-amj.5)
-- What does each attack button do for Earthquake (P1) and Nakoruru (P2)?
-- A save state is taken once round 1 is live; before every press the state
-- is reloaded so each button starts from identical positions. Snapshots
-- cover the animation and one late frame shows the opponent's health bar,
-- so "heavy" is read from damage, not from guesswork. Chords A+B and C+D
-- are included because the game's own tutorial hints at combinations.
--
-- Run:  /run-lua lua/button_probe.lua 3            (pass 1, start gap)
--       SAM2_PASS=2 /run-lua lua/button_probe.lua 3 (pass 2, approach walks)
-- Log:  /tmp/sam2/buttons.txt      Snapshots: ~/mame/snap/samsho2/NNNN.png

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
SM.LOG = "/tmp/sam2/buttons.txt"; SM.open_log(); local say = SM.say

local P1, P2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local COMBOS = { {"A"}, {"B"}, {"C"}, {"D"}, {"A","B"}, {"C","D"} }
local STATE = "/tmp/sam2/button_probe.sta"
local SAVE_AT = SM.MATCH_LIVE_AT + 180          -- 1924: BEGIN banner is gone by then
local SLOT = 240                                 -- frames per button trial
local HOLD = 4
local SNAP_OFFSETS = { 4, 8, 12, 16, 20, 26, 32, 40, 90 }

local function field(port_tag, name)
  local f = manager.machine.ioport.ports[port_tag].fields[name]; if not f then error("no field " .. name) end; return f
end

-- Trials: {who, combo, approach}. approach = frames to walk toward the
-- opponent after the load and before the press (0 = press from start gap).
-- Pass 1 (start gap) showed Nakoruru reaches nothing from there, and
-- Earthquake's kicks fall short, so pass 2 adds approach walks.
local PASS = os.getenv("SAM2_PASS") or "1"
local plan = {}
local function add(who, approach) for _, c in ipairs(COMBOS) do plan[#plan + 1] = { who = who, combo = c, approach = approach } end end
if PASS == "1" then
  add("P1", 0); add("P2", 0)
else
  add("P2", 45); add("P2", 75)
  plan[#plan + 1] = { who = "P1", combo = {"C"}, approach = 30 }
  plan[#plan + 1] = { who = "P1", combo = {"D"}, approach = 30 }
end
local WHO = { P1 = { port = P1, pre = "P1 ", name = "P1 Earthquake", toward = "P1 Right" },
              P2 = { port = P2, pre = "P2 ", name = "P2 Nakoruru",   toward = "P2 Left" } }
local trials = {}
local t = SAVE_AT + 60
for _, pl in ipairs(plan) do
  local who = WHO[pl.who]
  local names = {}
  for i, b in ipairs(pl.combo) do names[i] = who.pre .. b end
  trials[#trials + 1] = { load_at = t, walk_at = t + 10, approach = pl.approach, toward = who.toward,
    press_at = t + 30 + pl.approach, port = who.port, names = names,
    label = who.name .. " " .. table.concat(pl.combo, "+") .. (pl.approach > 0 and (" approach" .. pl.approach) or "") }
  t = t + SLOT + pl.approach
end
local DONE_AT = t + 30
local snaps = {}
for _, tr in ipairs(trials) do for _, off in ipairs(SNAP_OFFSETS) do snaps[tr.press_at + off] = tr.label .. " +" .. off end end

local frame, sub, resolved = 0, nil, false
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if not resolved and frame > 10 then
    for _, tr in ipairs(trials) do tr.fields = {}; for i, n in ipairs(tr.names) do tr.fields[i] = field(tr.port, n) end end
    resolved = true
    say("button probe pass %s: %d trials, save at %d, first press %d, %d snapshots", PASS, #trials, SAVE_AT, trials[1].press_at, #trials * #SNAP_OFFSETS)
  end
  if frame == SAVE_AT then
    local ok, err = pcall(function() manager.machine:save(STATE) end)
    say("frame %5d  save state -> %s", frame, ok and "scheduled" or tostring(err))
  end
  for _, tr in ipairs(trials) do
    if frame == tr.load_at then pcall(function() manager.machine:load(STATE) end); say("frame %5d  load state", frame)
    elseif tr.approach > 0 and frame == tr.walk_at then tr.walk = field(tr.port, tr.toward); tr.walk:set_value(1); say("frame %5d  walk %s for %d", frame, tr.toward, tr.approach)
    elseif tr.approach > 0 and frame == tr.walk_at + tr.approach then tr.walk:clear_value()
    elseif frame == tr.press_at then for _, f in ipairs(tr.fields) do f:set_value(1) end; say("frame %5d  press   %s", frame, tr.label)
    elseif frame == tr.press_at + HOLD then for _, f in ipairs(tr.fields) do f:clear_value() end end
  end
  if snaps[frame] then
    local ok = pcall(function() manager.machine.video:snapshot() end)
    say("frame %5d  snap %s (%s)", frame, ok and "ok" or "FAILED", snaps[frame])
  end
  if frame == DONE_AT then say("frame %5d  done", frame); sub = nil end
end)
