-- memmap_check.lua  (bead sam-aug.2)
-- Log the memmap fields every frame during a scripted sequence (walk to each
-- wall, jump, land a hit each way) and snapshot at the key moments so the
-- log lines up with what is on screen.
--   /run-lua lua/memmap_check.lua 3     log: /tmp/sam2/mem_health_pos.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
SM.LOG = "/tmp/sam2/memmap_check_events.txt"; SM.open_log(); local say = SM.say
local out = assert(io.open("/tmp/sam2/mem_health_pos.txt", "w"))
out:write("frame p1_x p1_y p1_health p2_x p2_y p2_health event\n")
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local space
local pending_event = ""
local function ev(s) pending_event = s; say("frame event: %s", s) end
local function snap() pcall(function() manager.machine.video:snapshot() end) end

local T = SM.MATCH_LIVE_AT + 180
local steps = {
  { at = T,        f = function() snap(); ev("snap idle") end },
  { at = T + 10,   f = function() fld(J1, "P1 Left"):set_value(1); ev("P1 walk left start") end },
  { at = T + 190,  f = function() fld(J1, "P1 Left"):clear_value(); snap(); ev("snap P1 at left wall") end },
  { at = T + 200,  f = function() fld(J1, "P1 Right"):set_value(1); ev("P1 walk right start") end },
  { at = T + 560,  f = function() fld(J1, "P1 Right"):clear_value(); snap(); ev("snap P1 pushed right") end },
  { at = T + 600,  f = function() fld(J2, "P2 Right"):set_value(1); ev("P2 walk right start") end },
  { at = T + 780,  f = function() fld(J2, "P2 Right"):clear_value(); snap(); ev("snap P2 at right wall") end },
  { at = T + 800,  f = function() fld(J1, "P1 Up"):set_value(1); ev("P1 jump") end },
  { at = T + 804,  f = function() fld(J1, "P1 Up"):clear_value() end },
  { at = T + 824,  f = function() snap(); ev("snap P1 airborne") end },
  { at = T + 880,  f = function() fld(J2, "P2 Up"):set_value(1); ev("P2 jump") end },
  { at = T + 884,  f = function() fld(J2, "P2 Up"):clear_value() end },
  { at = T + 904,  f = function() snap(); ev("snap P2 airborne") end },
  { at = T + 960,  f = function() fld(J2, "P2 Left"):set_value(1); ev("P2 walk left toward P1") end },
  { at = T + 1120, f = function() fld(J2, "P2 Left"):clear_value(); fld(J1, "P1 A"):set_value(1); fld(J1, "P1 B"):set_value(1); ev("P1 A+B") end },
  { at = T + 1124, f = function() fld(J1, "P1 A"):clear_value(); fld(J1, "P1 B"):clear_value() end },
  { at = T + 1150, f = function() snap(); ev("snap after P1 A+B") end },
  { at = T + 1240, f = function() fld(J2, "P2 Left"):set_value(1); ev("P2 walk left toward P1 again") end },
  { at = T + 1330, f = function() fld(J2, "P2 Left"):clear_value(); fld(J2, "P2 A"):set_value(1); fld(J2, "P2 B"):set_value(1); ev("P2 A+B") end },
  { at = T + 1334, f = function() fld(J2, "P2 A"):clear_value(); fld(J2, "P2 B"):clear_value() end },
  { at = T + 1370, f = function() snap(); ev("snap after P2 A+B") end },
  { at = T + 1400, f = function() say("done"); out:close() end },
}
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("ERROR %s", tostring(e)) end end end
  if frame >= SM.MATCH_LIVE_AT and frame < T + 1400 then
    local a, b = MM.read_player(space, MM.p1), MM.read_player(space, MM.p2)
    out:write(string.format("%d %d %d %d %d %d %d %s\n", frame, a.x, a.y, a.health, b.x, b.y, b.health, pending_event))
    pending_event = ""
  end
  if frame == T + 1401 then sub = nil end
end)
