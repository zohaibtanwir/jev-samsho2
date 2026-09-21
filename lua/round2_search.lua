-- round2_search.lua  (finding from sam-l4r.5: memory map dies after round 1)
-- Lua alone ends round 1 (P1 heavy-slashes until P2's round-1 health reads 0),
-- waits for round 2 to be live, then reruns the X / health staged searches
-- from memsearch_pos_health.lua relative to that moment.
--   /run-lua lua/round2_search.lua 3     log: /tmp/sam2/round2_search.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
local RS = dofile(here .. "ramsearch.lua")
SM.LOG = "/tmp/sam2/round2_search.txt"; SM.open_log(); local say = SM.say
local STATE = "/tmp/sam2/round2.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function hold(p, ...) for _, n in ipairs({ ... }) do fld(p, n):set_value(1) end end
local function rel(p, ...) for _, n in ipairs({ ... }) do fld(p, n):clear_value() end end
local function load() manager.machine:load(STATE) end
local function snap() pcall(function() manager.machine.video:snapshot() end) end
local space
local S = {}
local function new(n, w) S[n] = RS.new{ base = 0x100000, size = 0x10000, width = w, log = function(m) say(n .. ": " .. m) end } end
local function both(p, f) f(S[p .. "16"]); f(S[p .. "8"]) end
local function rep(p, n) S[p .. "16"]:report(say, n); S[p .. "8"]:report(say, n) end

local phase, t0, low_seen, next_attack = "kill", 0, false, 0
local steps = {}
local function at(off, f) steps[#steps + 1] = { at = off, f = f } end
-- stages relative to T2 (round 2 live)
at(0,   function() manager.machine:save(STATE); snap(); say("round 2 state saved") end)
local t = 30
at(t,       function() new("p1x16", 16); new("p1x8", 8); both("p1x", function(s) s:snapshot("idle") end) end)
at(t + 30,  function() both("p1x", function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(J1, "P1 Right") end)
at(t + 70,  function() rel(J1, "P1 Right"); both("p1x", function(s) s:snapshot("right"); s:filter("increased") end) end)
at(t + 130, function() both("p1x", function(s) s:snapshot("settled") end); hold(J1, "P1 Left") end)
at(t + 170, function() rel(J1, "P1 Left"); both("p1x", function(s) s:snapshot("left"); s:filter("decreased") end); rep("p1x", 30) end)
t = t + 200
at(t,       function() load() end)
at(t + 20,  function() new("p2x16", 16); new("p2x8", 8); both("p2x", function(s) s:snapshot("idle") end) end)
at(t + 50,  function() both("p2x", function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(J2, "P2 Left") end)
at(t + 90,  function() rel(J2, "P2 Left"); both("p2x", function(s) s:snapshot("left"); s:filter("decreased") end) end)
at(t + 150, function() both("p2x", function(s) s:snapshot("settled") end); hold(J2, "P2 Right") end)
at(t + 190, function() rel(J2, "P2 Right"); both("p2x", function(s) s:snapshot("right"); s:filter("increased") end); rep("p2x", 30) end)
t = t + 220
at(t,       function() load() end)
at(t + 20,  function() new("p2h16", 16); new("p2h8", 8); both("p2h", function(s) s:snapshot("full") end) end)
at(t + 50,  function() both("p2h", function(s) s:snapshot("full2"); s:filter("unchanged") end); hold(J1, "P1 A", "P1 B") end)
at(t + 54,  function() rel(J1, "P1 A", "P1 B") end)
at(t + 140, function() both("p2h", function(s) s:snapshot("hitAB"); s:filter("decreased") end); snap() end)
at(t + 200, function() both("p2h", function(s) s:snapshot("idle"); s:filter("unchanged") end); load() end)
at(t + 220, function() both("p2h", function(s) s:snapshot("reload"); s:filter("equal_snap", 1) end); hold(J1, "P1 B") end)
at(t + 224, function() rel(J1, "P1 B") end)
at(t + 310, function() both("p2h", function(s) s:snapshot("hitB"); s:filter("decreased") end) end)
at(t + 370, function() both("p2h", function(s) s:snapshot("idle2"); s:filter("unchanged") end); rep("p2h", 40) end)
t = t + 400
at(t,       function() load() end)
at(t + 20,  function() new("p1h16", 16); new("p1h8", 8); both("p1h", function(s) s:snapshot("full") end); hold(J2, "P2 Left") end)
at(t + 65,  function() rel(J2, "P2 Left"); both("p1h", function(s) s:snapshot("full2"); s:filter("unchanged") end); hold(J2, "P2 A", "P2 B") end)
at(t + 69,  function() rel(J2, "P2 A", "P2 B") end)
at(t + 160, function() both("p1h", function(s) s:snapshot("hitAB"); s:filter("decreased") end); snap() end)
at(t + 220, function() both("p1h", function(s) s:snapshot("idle"); s:filter("unchanged") end); rep("p1h", 40); say("done") end)

local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if frame < SM.MATCH_LIVE_AT + 120 then return end
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  if phase == "kill" then
    local p1, p2 = MM.read_player(space, MM.p1), MM.read_player(space, MM.p2)
    local timer = MM.read_timer(space)
    if p2.health > 0 then
      local gap = p2.x - p1.x
      if frame >= next_attack then
        if gap > 165 then hold(J1, "P1 Right") elseif gap < 90 then rel(J1, "P1 Right"); hold(J1, "P1 Left")
        else rel(J1, "P1 Right", "P1 Left"); hold(J1, "P1 A", "P1 B"); next_attack = frame + 110 end
      end
      if frame == next_attack - 106 then rel(J1, "P1 A", "P1 B") end
    else
      rel(J1, "P1 Right", "P1 Left", "P1 A", "P1 B")
      if timer < 90 then low_seen = true end
      if low_seen and timer >= 98 then phase = "r2intro"; t0 = frame; say("frame %d  round 2 timer reset seen; old-map hp %d/%d", frame, p1.health, p2.health) end
    end
  elseif phase == "r2intro" then
    if frame == t0 + 420 then phase = "stages"; t0 = frame; say("frame %d  T2 = round 2 assumed live", frame) end
  elseif phase == "stages" then
    for _, st in ipairs(steps) do if frame == t0 + st.at then local ok, e = pcall(st.f); if not ok then say("ERROR %s", tostring(e)) end end end
  end
end)
