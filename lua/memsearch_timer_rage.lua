-- memsearch_timer_rage.lua  (bead sam-aug.3)
-- Staged searches for the round timer, each player's rage (POW), a crouch
-- indicator and an airborne flag, using lua/ramsearch.lua and a save state.
--   /run-lua lua/memsearch_timer_rage.lua 3    log: /tmp/sam2/memsearch_timer_rage.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local RS = dofile(here .. "ramsearch.lua")
SM.LOG = "/tmp/sam2/memsearch_timer_rage.txt"; SM.open_log(); local say = SM.say
local STATE = "/tmp/sam2/memsearch2.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function hold(p, n) fld(p, n):set_value(1) end
local function rel(p, n) fld(p, n):clear_value() end
local function load() manager.machine:load(STATE) end
local function snap(label) pcall(function() manager.machine.video:snapshot() end); say("screenshot: " .. label) end
local S = {}
local function new(name, width) S[name] = RS.new{ base = 0x100000, size = 0x10000, width = width, log = function(m) say(name .. ": " .. m) end } end
local function both(prefix, f) f(S[prefix .. "16"]); f(S[prefix .. "8"]) end
local function rep(prefix, n) S[prefix .. "16"]:report(say, n); S[prefix .. "8"]:report(say, n) end
local steps = {}
local function at(fr, f) steps[#steps + 1] = { at = fr, f = f } end
local T = SM.MATCH_LIVE_AT + 180

-- stage 0: save
at(T, function() manager.machine:save(STATE); say("state saved") end)

-- stage 1: timer. three snapshots 120 frames apart, decreasing; screenshots to read the digits
local t = T + 30
at(t,       function() new("tm16", 16); new("tm8", 8); both("tm", function(s) s:snapshot("t0") end); snap("timer t0") end)
at(t + 120, function() both("tm", function(s) s:snapshot("t1"); s:filter("decreased") end); snap("timer t1") end)
at(t + 240, function() both("tm", function(s) s:snapshot("t2"); s:filter("decreased"); s:filter("between", 0, 0x99) end); snap("timer t2"); rep("tm", 40) end)

-- stage 2: P1 rage. P2 walks in and lands A+B twice (reload in between); rage must rise each time and hold while idle
t = t + 280
at(t,       function() load() end)
at(t + 20,  function() new("r116", 16); new("r18", 8); both("r1", function(s) s:snapshot("idle") end); hold(J2, "P2 Left") end)
at(t + 65,  function() rel(J2, "P2 Left"); both("r1", function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(J2, "P2 A"); hold(J2, "P2 B") end)
at(t + 69,  function() rel(J2, "P2 A"); rel(J2, "P2 B") end)
at(t + 160, function() both("r1", function(s) s:snapshot("hit1"); s:filter("increased") end) end)
at(t + 220, function() both("r1", function(s) s:snapshot("idle3"); s:filter("unchanged") end); load() end)
at(t + 240, function() both("r1", function(s) s:snapshot("reload"); s:filter("equal_snap", 1) end); hold(J2, "P2 Left") end)
at(t + 285, function() rel(J2, "P2 Left"); hold(J2, "P2 A"); hold(J2, "P2 B") end)
at(t + 289, function() rel(J2, "P2 A"); rel(J2, "P2 B") end)
at(t + 380, function() both("r1", function(s) s:snapshot("hit2"); s:filter("increased") end) end)
at(t + 440, function() both("r1", function(s) s:snapshot("idle4"); s:filter("unchanged") end); snap("P1 rage after hit"); rep("r1", 40) end)

-- stage 3: P2 rage. P1 B lands from the start gap, twice with a reload
t = t + 470
at(t,       function() load() end)
at(t + 20,  function() new("r216", 16); new("r28", 8); both("r2", function(s) s:snapshot("idle") end) end)
at(t + 50,  function() both("r2", function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(J1, "P1 B") end)
at(t + 54,  function() rel(J1, "P1 B") end)
at(t + 140, function() both("r2", function(s) s:snapshot("hit1"); s:filter("increased") end) end)
at(t + 200, function() both("r2", function(s) s:snapshot("idle3"); s:filter("unchanged") end); load() end)
at(t + 220, function() both("r2", function(s) s:snapshot("reload"); s:filter("equal_snap", 1) end); hold(J1, "P1 B") end)
at(t + 224, function() rel(J1, "P1 B") end)
at(t + 310, function() both("r2", function(s) s:snapshot("hit2"); s:filter("increased") end) end)
at(t + 370, function() both("r2", function(s) s:snapshot("idle4"); s:filter("unchanged") end); snap("P2 rage after hit"); rep("r2", 40) end)

-- stage 4/5: crouch flag, P1 then P2. idle -> crouch (changed) -> still crouched (unchanged) -> stood up (back to idle value)
for i, who in ipairs({ { J = J1, d = "P1 Down", n = "c1" }, { J = J2, d = "P2 Down", n = "c2" } }) do
  t = t + (i == 1 and 400 or 200)
  local w = who
  at(t,       function() load() end)
  at(t + 20,  function() new(w.n .. "16", 16); new(w.n .. "8", 8); both(w.n, function(s) s:snapshot("idle") end) end)
  at(t + 50,  function() both(w.n, function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(w.J, w.d) end)
  at(t + 80,  function() both(w.n, function(s) s:snapshot("crouch"); s:filter("changed") end); snap(w.d .. " held") end)
  at(t + 110, function() both(w.n, function(s) s:snapshot("crouch2"); s:filter("unchanged") end); rel(w.J, w.d) end)
  at(t + 150, function() both(w.n, function(s) s:snapshot("stood"); s:filter("equal_snap", 1) end); rep(w.n, 40) end)
end

-- stage 6/7: airborne flag, P1 then P2. changed vs idle 16 frames into the jump, unchanged between +16 and +26 (Y is not), back after landing
for i, who in ipairs({ { J = J1, u = "P1 Up", n = "a1" }, { J = J2, u = "P2 Up", n = "a2" } }) do
  t = t + 200
  local w = who
  at(t,       function() load() end)
  at(t + 20,  function() new(w.n .. "16", 16); new(w.n .. "8", 8); both(w.n, function(s) s:snapshot("idle") end) end)
  at(t + 50,  function() both(w.n, function(s) s:snapshot("idle2"); s:filter("unchanged") end); hold(w.J, w.u) end)
  at(t + 54,  function() rel(w.J, w.u) end)
  at(t + 66,  function() both(w.n, function(s) s:snapshot("air1"); s:filter("changed") end) end)
  at(t + 76,  function() both(w.n, function(s) s:snapshot("air2"); s:filter("unchanged") end); snap(w.u .. " airborne") end)
  at(t + 150, function() both(w.n, function(s) s:snapshot("landed"); s:filter("equal_snap", 1) end); rep(w.n, 40); if i == 2 then say("done") end end)
end
local DONE_AT = t + 160

local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("frame %d ERROR %s", frame, tostring(e)) end end end
  if frame == DONE_AT then sub = nil end
end)
