-- state_check.lua  (bead sam-aug.5)
-- Run the core (state.json every frame) through a scripted 30 s of events,
-- with a screenshot on each event so /tmp/sam2/state_log.jsonl (from
-- tools/state_watch.py) can be lined up with the screen.
--   /run-lua lua/state_check.lua 3     events: /tmp/sam2/start_match.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); local say = C.SM.say
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function snap() pcall(function() manager.machine.video:snapshot() end) end
local T = C.SM.MATCH_LIVE_AT + 120
local steps, t = {}, T
local function add(port, keys, label, hold, gap)
  local at = t
  steps[#steps + 1] = { at = at, f = function() for _, k in ipairs(keys) do fld(port, k):set_value(1) end; snap(); say("frame %d  EVENT %s", at, label) end }
  steps[#steps + 1] = { at = t + hold, f = function() for _, k in ipairs(keys) do fld(port, k):clear_value() end end }
  t = t + gap
end
add(J1, { "P1 Right" }, "P1 walk right", 60, 120)
add(J1, { "P1 Up" }, "P1 jump", 4, 100)
add(J1, { "P1 Down" }, "P1 crouch", 40, 80)
add(J1, { "P1 A", "P1 B" }, "P1 A+B (heavy)", 4, 200)
add(J2, { "P2 Left" }, "P2 walk left", 60, 100)
add(J2, { "P2 Up" }, "P2 jump", 4, 100)
add(J2, { "P2 A", "P2 B" }, "P2 A+B (heavy)", 4, 200)
add(J1, { "P1 B" }, "P1 B (medium)", 4, 160)
add(J2, { "P2 D" }, "P2 D (kick)", 4, 160)
add(J1, { "P1 Left" }, "P1 walk left", 60, 120)
steps[#steps + 1] = { at = t + 300, f = function() snap(); say("frame %d  EVENT end", t + 300); say("done") end }
local DONE_AT = t + 301
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  C.tick(frame)
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("ERROR %s", tostring(e)) end end end
  if frame == DONE_AT then sub = nil end
end)
