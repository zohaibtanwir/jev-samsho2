-- moveids_check.lua  (bead sam-aug.4)
-- Per-frame log of both action words and the decoded phase through a
-- scripted set of moves, with a screenshot on each press.
--   /run-lua lua/moveids_check.lua 3    log: /tmp/sam2/mem_moves.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
local MV = dofile(here .. "moveids.lua")
SM.LOG = "/tmp/sam2/moveids_check_events.txt"; SM.open_log(); local say = SM.say
local OUT = assert(io.open("/tmp/sam2/mem_moves.txt", "w"))
OUT:write("frame p1_word p1_age p1_phase p1_name p2_word p2_age p2_phase p2_name p1_health p2_health event\n")
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local space, ev = nil, ""
local t1, t2 = MV.new_tracker("Earthquake"), MV.new_tracker("Nakoruru")
local function press(port, keys, label) return function() for _, k in ipairs(keys) do fld(port, k):set_value(1) end; pcall(function() manager.machine.video:snapshot() end); ev = label end end
local function release(port, keys) return function() for _, k in ipairs(keys) do fld(port, k):clear_value() end end end
local T = SM.MATCH_LIVE_AT + 180
local steps, t = {}, T
local function add(port, keys, label, hold, gap) steps[#steps + 1] = { at = t, f = press(port, keys, label) }; steps[#steps + 1] = { at = t + hold, f = release(port, keys) }; t = t + gap end
add(J1, { "P1 A" }, "P1 A", 4, 120); add(J1, { "P1 B" }, "P1 B", 4, 150); add(J1, { "P1 A", "P1 B" }, "P1 A+B", 4, 180)
add(J1, { "P1 Down" }, "P1 crouch", 40, 100); add(J1, { "P1 Up" }, "P1 jump", 4, 120); add(J1, { "P1 Right" }, "P1 walk fwd", 40, 100)
add(J2, { "P2 Left" }, "P2 walk fwd (left)", 45, 50); add(J2, { "P2 A" }, "P2 A", 4, 100); add(J2, { "P2 B" }, "P2 B", 4, 120); add(J2, { "P2 A", "P2 B" }, "P2 A+B", 4, 200)
add(J2, { "P2 Down" }, "P2 crouch", 40, 100); add(J2, { "P2 Up" }, "P2 jump", 4, 120); add(J2, { "P2 D" }, "P2 D", 4, 120)
steps[#steps + 1] = { at = t, f = function() say("done"); OUT:close() end }
local DONE_AT = t + 1
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("ERROR %s", tostring(e)) end end end
  if frame >= SM.MATCH_LIVE_AT and frame < DONE_AT then
    local w1, w2 = MM.read(space, MM.p1.state), MM.read(space, MM.p2.state)
    local a, b = t1:update(w1), t2:update(w2)
    OUT:write(string.format("%d %04X %d %s %s %04X %d %s %s %d %d %s\n", frame, w1, a.age, a.phase, (a.name or "-"):gsub(" ", "_"), w2, b.age, b.phase, (b.name or "-"):gsub(" ", "_"),
      MM.read(space, MM.p1.health), MM.read(space, MM.p2.health), ev)); ev = ""
  end
  if frame == DONE_AT then sub = nil end
end)
