-- memsearch_rage.lua  (bead sam-aug.3)
-- Rage (POW) search with relaxed timing: the gauge fills over time, so
-- compare 300 frames after the hit, require stability 60 frames later,
-- reload, repeat. P1 gets hit by Nakoruru A+B; P2 gets hit by Earthquake B.
--   /run-lua lua/memsearch_rage.lua 3   log: /tmp/sam2/memsearch_rage.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local RS = dofile(here .. "ramsearch.lua")
SM.LOG = "/tmp/sam2/memsearch_rage.txt"; SM.open_log(); local say = SM.say
local STATE = "/tmp/sam2/memsearch3.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function hold(p, ...) for _, n in ipairs({ ... }) do fld(p, n):set_value(1) end end
local function rel(p, ...) for _, n in ipairs({ ... }) do fld(p, n):clear_value() end end
local function load() manager.machine:load(STATE) end
local function snap(l) pcall(function() manager.machine.video:snapshot() end); say("screenshot: " .. l) end
local S = {}
local function new(n, w) S[n] = RS.new{ base = 0x100000, size = 0x10000, width = w, log = function(m) say(n .. ": " .. m) end } end
local function both(p, f) f(S[p .. "16"]); f(S[p .. "8"]) end
local function rep(p, n) S[p .. "16"]:report(say, n); S[p .. "8"]:report(say, n) end
local steps = {}
local function at(fr, f) steps[#steps + 1] = { at = fr, f = f } end
local T = SM.MATCH_LIVE_AT + 180
at(T, function() manager.machine:save(STATE); say("state saved") end)

local function stage(prefix, t, attack)   -- attack(): starts the hit sequence; takes <= 70 frames
  at(t,       function() load() end)
  at(t + 20,  function() new(prefix .. "16", 16); new(prefix .. "8", 8); both(prefix, function(s) s:snapshot("idle") end) end)
  at(t + 40,  function() both(prefix, function(s) s:snapshot("idle2"); s:filter("unchanged") end); attack() end)
  at(t + 400, function() both(prefix, function(s) s:snapshot("hit1+300"); s:filter("increased") end); snap(prefix .. " after hit 1") end)
  at(t + 460, function() both(prefix, function(s) s:snapshot("hit1+360"); s:filter("unchanged") end); load() end)
  at(t + 480, function() both(prefix, function(s) s:snapshot("reload"); s:filter("equal_snap", 1) end); attack() end)
  at(t + 840, function() both(prefix, function(s) s:snapshot("hit2+300"); s:filter("increased") end) end)
  at(t + 900, function() both(prefix, function(s) s:snapshot("hit2+360"); s:filter("unchanged") end); rep(prefix, 60) end)
  return t + 920
end
local pending = {}
local function p2_hits_p1() hold(J2, "P2 Left"); pending[#pending + 1] = { 45, function() rel(J2, "P2 Left"); hold(J2, "P2 A", "P2 B") end }; pending[#pending + 1] = { 49, function() rel(J2, "P2 A", "P2 B") end } end
local function p1_hits_p2() hold(J1, "P1 B"); pending[#pending + 1] = { 4, function() rel(J1, "P1 B") end } end
local t = stage("r1", T + 30, p2_hits_p1)
t = stage("r2", t, p1_hits_p2)
at(t, function() say("done") end)
local DONE_AT = t + 5
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("frame %d ERROR %s", frame, tostring(e)) end end end
  for i = #pending, 1, -1 do local p = pending[i]; p[1] = p[1] - 1; if p[1] <= 0 then pcall(p[2]); table.remove(pending, i) end end
  if frame == DONE_AT then sub = nil end
end)
