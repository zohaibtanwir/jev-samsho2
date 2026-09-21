-- rage_check.lua  (bead sam-aug.3)
-- Land three hits on P1 in a row (Nakoruru walks in by the memory-map gap,
-- then A+B), then reload and land three P1 B hits on P2. Log the rage
-- candidate bytes and health every frame; snapshot after each hit.
--   /run-lua lua/rage_check.lua 3   log: /tmp/sam2/rage_check.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
SM.LOG = "/tmp/sam2/rage_check_events.txt"; SM.open_log(); local say = SM.say
local RS = dofile(here .. "ramsearch.lua")
local S1 = RS.new{ base = 0x100000, size = 0x10000, width = 16, log = function(m) say("s16 " .. m) end }
local S8 = RS.new{ base = 0x100000, size = 0x10000, width = 8, log = function(m) say("s8  " .. m) end }
local function rs_snap(l) S1:snapshot(l); S8:snapshot(l) end
local function rs_inc() S1:filter("increased"); S8:filter("increased") end
local OUT = assert(io.open("/tmp/sam2/rage_check.txt", "w"))
OUT:write("frame p1x p2x p1h p2h A88 A89 ADA ADB rage1 rage2 event\n")
local STATE = "/tmp/sam2/rage_check.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local space
local phase, phase_t, hits, event = "wait", 0, 0, ""
local T = SM.MATCH_LIVE_AT + 180
local walking = false
local function snap() pcall(function() manager.machine.video:snapshot() end) end
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  local p1, p2 = MM.read_player(space, MM.p1), MM.read_player(space, MM.p2)
  local r = function(a) return space:read_u8(a) end
  if frame == T then manager.machine:save(STATE); phase = "p2hitsp1"; phase_t = frame; hits = 0; event = "saved"; rs_snap("before") end
  if phase == "p2hitsp1" then
    local gap = p2.x - p1.x
    if hits < 3 and frame - phase_t > 220 then
      if gap > 60 and not walking then fld(J2, "P2 Left"):set_value(1); walking = true
      elseif gap <= 60 and walking then fld(J2, "P2 Left"):clear_value(); walking = false
        fld(J2, "P2 A"):set_value(1); fld(J2, "P2 B"):set_value(1); hits = hits + 1; phase_t = frame; event = "P2 A+B #" .. hits
      end
    end
    if frame == phase_t + 4 then fld(J2, "P2 A"):clear_value(); fld(J2, "P2 B"):clear_value() end
    if frame == phase_t + 80 and hits > 0 then snap(); event = "snap after hit " .. hits end
    if frame == phase_t + 200 and hits > 0 then rs_snap("p1hit" .. hits); rs_inc() end
    if hits == 3 and frame - phase_t > 300 then S1:report(say, 60); S8:report(say, 60); S1:reset(); S8:reset(); manager.machine:load(STATE); phase = "p1hitsp2"; phase_t = frame + 20; hits = 0; event = "reload" end
    if phase == "p1hitsp2" and frame == phase_t - 5 then end
  elseif phase == "p1hitsp2" then
    local gap = p2.x - p1.x
    if hits < 3 and frame - phase_t > 220 then
      if gap > 170 and not walking then fld(J1, "P1 Right"):set_value(1); walking = true
      elseif gap <= 170 then
        if walking then fld(J1, "P1 Right"):clear_value(); walking = false end
        fld(J1, "P1 B"):set_value(1); hits = hits + 1; phase_t = frame; event = "P1 B #" .. hits
      end
    end
    if frame == phase_t + 4 then fld(J1, "P1 B"):clear_value() end
    if frame == phase_t + 80 and hits > 0 then snap(); event = "snap after hit " .. hits end
    if frame == phase_t + 200 and hits > 0 then rs_snap("p2hit" .. hits); rs_inc() end
    if hits == 0 and frame == phase_t + 60 then rs_snap("before2") end
    if hits == 3 and frame - phase_t > 300 then S1:report(say, 60); S8:report(say, 60); phase = "done"; say("done"); OUT:close() end
  end
  if phase ~= "wait" and phase ~= "done" then
    OUT:write(string.format("%d %d %d %d %d %d %d %d %d %d %d %s\n", frame, p1.x, p2.x, p1.health, p2.health,
      r(0x100A88), r(0x100A89), r(0x100ADA), r(0x100ADB), r(0x105B70), r(0x1066B0), event)); event = ""
  end
  if phase == "done" then sub = nil end
end)
