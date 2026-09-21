-- memmap_check2.lua  (bead sam-aug.3)
-- Per-frame log of timer, rage, state (crouch/air) and y for both players
-- through crouches, jumps and a hit, with screenshots to line up against.
--   /run-lua lua/memmap_check2.lua 3    log: /tmp/sam2/mem_timer_rage.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
SM.LOG = "/tmp/sam2/memmap_check2_events.txt"; SM.open_log(); local say = SM.say
local OUT = assert(io.open("/tmp/sam2/mem_timer_rage.txt", "w"))
OUT:write("frame timer p1_rage p2_rage p1_state p1_y p1_crouch p1_air p2_state p2_y p2_crouch p2_air p1_health event\n")
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local space, ev = nil, ""
local function snap(l) pcall(function() manager.machine.video:snapshot() end); ev = "snap " .. l end
local T = SM.MATCH_LIVE_AT + 180
local steps = {
  { at = T,        f = function() snap("idle, timer visible") end },
  { at = T + 240,  f = function() snap("timer 4 s later") end },
  { at = T + 250,  f = function() fld(J1, "P1 Down"):set_value(1); ev = "P1 Down held" end },
  { at = T + 310,  f = function() snap("P1 crouching") end },
  { at = T + 320,  f = function() fld(J1, "P1 Down"):clear_value(); ev = "P1 Down released" end },
  { at = T + 380,  f = function() fld(J1, "P1 Up"):set_value(1); ev = "P1 Up (jump)" end },
  { at = T + 384,  f = function() fld(J1, "P1 Up"):clear_value() end },
  { at = T + 404,  f = function() snap("P1 airborne") end },
  { at = T + 480,  f = function() fld(J2, "P2 Down"):set_value(1); ev = "P2 Down held" end },
  { at = T + 540,  f = function() snap("P2 crouching") end },
  { at = T + 550,  f = function() fld(J2, "P2 Down"):clear_value(); ev = "P2 Down released" end },
  { at = T + 610,  f = function() fld(J2, "P2 Up"):set_value(1); ev = "P2 Up (jump)" end },
  { at = T + 614,  f = function() fld(J2, "P2 Up"):clear_value() end },
  { at = T + 634,  f = function() snap("P2 airborne") end },
  { at = T + 720,  f = function() fld(J2, "P2 Left"):set_value(1); ev = "P2 walks in" end },
  { at = T + 765,  f = function() fld(J2, "P2 Left"):clear_value(); fld(J2, "P2 A"):set_value(1); fld(J2, "P2 B"):set_value(1); ev = "P2 A+B" end },
  { at = T + 769,  f = function() fld(J2, "P2 A"):clear_value(); fld(J2, "P2 B"):clear_value() end },
  { at = T + 900,  f = function() snap("after P2 A+B: P1 rage gauge") end },
  { at = T + 920,  f = function() fld(J1, "P1 B"):set_value(1); ev = "P1 B" end },
  { at = T + 924,  f = function() fld(J1, "P1 B"):clear_value() end },
  { at = T + 1060, f = function() snap("after P1 B: P2 rage gauge") end },
  { at = T + 1080, f = function() say("done"); OUT:close() end },
}
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("ERROR %s", tostring(e)) end end end
  if frame >= SM.MATCH_LIVE_AT and frame < T + 1080 then
    local a, b = MM.read_player(space, MM.p1), MM.read_player(space, MM.p2)
    OUT:write(string.format("%d %d %d %d %d %d %s %s %d %d %s %s %d %s\n", frame, MM.read_timer(space), a.rage, b.rage,
      a.state, a.y, tostring(a.crouching), tostring(a.airborne), b.state, b.y, tostring(b.crouching), tostring(b.airborne), a.health, ev)); ev = ""
  end
  if frame == T + 1081 then sub = nil end
end)
