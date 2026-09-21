-- memsearch_pos_health.lua  (bead sam-aug.2)
-- Staged searches for P1/P2 X, Y and health using lua/ramsearch.lua with a
-- save state to reset positions between stages. Each stage: reset the
-- candidate set, cause one thing to change, filter, report.
--   /run-lua lua/memsearch_pos_health.lua 3    log: /tmp/sam2/memsearch_pos_health.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local RS = dofile(here .. "ramsearch.lua")
SM.LOG = "/tmp/sam2/memsearch_pos_health.txt"; SM.open_log(); local say = SM.say
local STATE = "/tmp/sam2/memsearch.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function hold(p, n) fld(p, n):set_value(1) end
local function rel(p, n) fld(p, n):clear_value() end
local function load() manager.machine:load(STATE) end

local S = {}   -- searches by name
local function new(name, width) S[name] = RS.new{ base = 0x100000, size = 0x10000, width = width, log = function(m) say(name .. ": " .. m) end }; return S[name] end
local function rep(name, n) S[name]:report(say, n or 25) end

local T = SM.MATCH_LIVE_AT + 180   -- 1924
local steps = {}
local function at(fr, f) steps[#steps + 1] = { at = fr, f = f } end

-- stage 0: save state once round is live and BEGIN is gone
at(T, function() manager.machine:save(STATE); say("state saved") end)

-- stage 1: P1 X. idle -> walk right (increased) -> settle 60 -> walk left (decreased)
-- (no 'unchanged' right after a walk: the walk animation keeps moving X for a while)
local t = T + 30
at(t,       function() new("p1x16", 16); new("p1x8", 8); S.p1x16:snapshot("idle"); S.p1x8:snapshot("idle") end)
at(t + 30,  function() S.p1x16:snapshot("idle2"); S.p1x8:snapshot("idle2"); S.p1x16:filter("unchanged"); S.p1x8:filter("unchanged"); hold(J1, "P1 Right") end)
at(t + 70,  function() rel(J1, "P1 Right"); S.p1x16:snapshot("right"); S.p1x8:snapshot("right"); S.p1x16:filter("increased"); S.p1x8:filter("increased") end)
at(t + 130, function() S.p1x16:snapshot("settled"); S.p1x8:snapshot("settled"); hold(J1, "P1 Left") end)
at(t + 170, function() rel(J1, "P1 Left"); S.p1x16:snapshot("left"); S.p1x8:snapshot("left"); S.p1x16:filter("decreased"); S.p1x8:filter("decreased") end)
at(t + 230, function() S.p1x16:snapshot("settled2"); S.p1x8:snapshot("settled2"); rep("p1x16", 40); rep("p1x8", 40) end)

-- stage 2: P2 X. load, idle -> walk left (decreased) -> settle -> walk right (increased)
t = t + 260
at(t,       function() load() end)
at(t + 20,  function() new("p2x16", 16); new("p2x8", 8); S.p2x16:snapshot("idle"); S.p2x8:snapshot("idle") end)
at(t + 50,  function() S.p2x16:snapshot("idle2"); S.p2x8:snapshot("idle2"); S.p2x16:filter("unchanged"); S.p2x8:filter("unchanged"); hold(J2, "P2 Left") end)
at(t + 90,  function() rel(J2, "P2 Left"); S.p2x16:snapshot("left"); S.p2x8:snapshot("left"); S.p2x16:filter("decreased"); S.p2x8:filter("decreased") end)
at(t + 150, function() S.p2x16:snapshot("settled"); S.p2x8:snapshot("settled"); hold(J2, "P2 Right") end)
at(t + 190, function() rel(J2, "P2 Right"); S.p2x16:snapshot("right"); S.p2x8:snapshot("right"); S.p2x16:filter("increased"); S.p2x8:filter("increased") end)
at(t + 250, function() S.p2x16:snapshot("settled2"); S.p2x8:snapshot("settled2"); rep("p2x16", 40); rep("p2x8", 40) end)

-- stage 3: P1 Y. load, idle, tap Up, mid-jump snapshots, landed
t = t + 280
at(t,       function() load() end)
at(t + 20,  function() new("p1y16", 16); new("p1y8", 8); S.p1y16:snapshot("idle"); S.p1y8:snapshot("idle") end)
at(t + 50,  function() S.p1y16:snapshot("idle2"); S.p1y8:snapshot("idle2"); S.p1y16:filter("unchanged"); S.p1y8:filter("unchanged"); hold(J1, "P1 Up") end)
at(t + 54,  function() rel(J1, "P1 Up") end)
at(t + 66,  function() S.p1y16:snapshot("rising"); S.p1y8:snapshot("rising"); S.p1y16:filter("changed"); S.p1y8:filter("changed") end)
at(t + 80,  function() S.p1y16:snapshot("mid"); S.p1y8:snapshot("mid"); S.p1y16:filter("changed"); S.p1y8:filter("changed") end)
at(t + 150, function() S.p1y16:snapshot("landed"); S.p1y8:snapshot("landed"); S.p1y16:filter("equal_snap", 1); S.p1y8:filter("equal_snap", 1); rep("p1y16", 60); rep("p1y8", 60) end)

-- stage 4: P2 Y (same with P2 Up)
t = t + 180
at(t,       function() load() end)
at(t + 20,  function() new("p2y16", 16); new("p2y8", 8); S.p2y16:snapshot("idle"); S.p2y8:snapshot("idle") end)
at(t + 50,  function() S.p2y16:snapshot("idle2"); S.p2y8:snapshot("idle2"); S.p2y16:filter("unchanged"); S.p2y8:filter("unchanged"); hold(J2, "P2 Up") end)
at(t + 54,  function() rel(J2, "P2 Up") end)
at(t + 66,  function() S.p2y16:snapshot("rising"); S.p2y8:snapshot("rising"); S.p2y16:filter("changed"); S.p2y8:filter("changed") end)
at(t + 80,  function() S.p2y16:snapshot("mid"); S.p2y8:snapshot("mid"); S.p2y16:filter("changed"); S.p2y8:filter("changed") end)
at(t + 150, function() S.p2y16:snapshot("landed"); S.p2y8:snapshot("landed"); S.p2y16:filter("equal_snap", 1); S.p2y8:filter("equal_snap", 1); rep("p2y16", 60); rep("p2y8", 60) end)

-- stage 5: P2 health. Constraints: unchanged while idle; decreases when
-- P1 A+B lands (heavy, -33 px); unchanged for 60 idle frames after; back to
-- the full value after a reload; decreases again when P1 B lands (-16 px);
-- unchanged after. Reload between hits because a hit knocks the target out
-- of reach.
t = t + 180
at(t,       function() load() end)
at(t + 20,  function() new("p2h16", 16); new("p2h8", 8); S.p2h16:snapshot("full"); S.p2h8:snapshot("full") end)
at(t + 50,  function() S.p2h16:snapshot("full2"); S.p2h8:snapshot("full2"); S.p2h16:filter("unchanged"); S.p2h8:filter("unchanged"); hold(J1, "P1 A"); hold(J1, "P1 B") end)
at(t + 54,  function() rel(J1, "P1 A"); rel(J1, "P1 B") end)
at(t + 140, function() S.p2h16:snapshot("hitAB"); S.p2h8:snapshot("hitAB"); S.p2h16:filter("decreased"); S.p2h8:filter("decreased") end)
at(t + 200, function() S.p2h16:snapshot("idle"); S.p2h8:snapshot("idle"); S.p2h16:filter("unchanged"); S.p2h8:filter("unchanged"); load() end)
at(t + 220, function() S.p2h16:snapshot("reload"); S.p2h8:snapshot("reload"); S.p2h16:filter("equal_snap", 1); S.p2h8:filter("equal_snap", 1); hold(J1, "P1 B") end)
at(t + 224, function() rel(J1, "P1 B") end)
at(t + 310, function() S.p2h16:snapshot("hitB"); S.p2h8:snapshot("hitB"); S.p2h16:filter("decreased"); S.p2h8:filter("decreased") end)
at(t + 370, function() S.p2h16:snapshot("idle2"); S.p2h8:snapshot("idle2"); S.p2h16:filter("unchanged"); S.p2h8:filter("unchanged"); rep("p2h16", 250); rep("p2h8", 250) end)

-- stage 6: P1 health, same shape with Nakoruru walking in 45 frames first
t = t + 400
at(t,       function() load() end)
at(t + 20,  function() new("p1h16", 16); new("p1h8", 8); S.p1h16:snapshot("full"); S.p1h8:snapshot("full"); hold(J2, "P2 Left") end)
at(t + 65,  function() rel(J2, "P2 Left"); S.p1h16:snapshot("full2"); S.p1h8:snapshot("full2"); S.p1h16:filter("unchanged"); S.p1h8:filter("unchanged"); hold(J2, "P2 A"); hold(J2, "P2 B") end)
at(t + 69,  function() rel(J2, "P2 A"); rel(J2, "P2 B") end)
at(t + 160, function() S.p1h16:snapshot("hitAB"); S.p1h8:snapshot("hitAB"); S.p1h16:filter("decreased"); S.p1h8:filter("decreased") end)
at(t + 220, function() S.p1h16:snapshot("idle"); S.p1h8:snapshot("idle"); S.p1h16:filter("unchanged"); S.p1h8:filter("unchanged"); load() end)
at(t + 240, function() S.p1h16:snapshot("reload"); S.p1h8:snapshot("reload"); S.p1h16:filter("equal_snap", 1); S.p1h8:filter("equal_snap", 1); hold(J2, "P2 Left") end)
at(t + 285, function() rel(J2, "P2 Left"); hold(J2, "P2 B") end)
at(t + 289, function() rel(J2, "P2 B") end)
at(t + 380, function() S.p1h16:snapshot("hitB"); S.p1h8:snapshot("hitB"); S.p1h16:filter("decreased"); S.p1h8:filter("decreased") end)
at(t + 440, function() S.p1h16:snapshot("idle2"); S.p1h8:snapshot("idle2"); S.p1h16:filter("unchanged"); S.p1h8:filter("unchanged"); rep("p1h16", 250); rep("p1h8", 250); say("done") end)
local DONE_AT = t + 450

local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  for _, st in ipairs(steps) do
    if frame == st.at then
      local ok, err = pcall(st.f)
      if not ok then say("frame %5d  ERROR %s", frame, tostring(err)) end
    end
  end
  if frame == DONE_AT then sub = nil end
end)
