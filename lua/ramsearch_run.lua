-- ramsearch_run.lua  (bead sam-aug.1)
-- Exercise lua/ramsearch.lua inside a live Earthquake vs Nakoruru match:
-- two idle snapshots (unchanged filter), then P1 walks right (increased /
-- changed filters), then idle again (unchanged). Not a real address hunt,
-- just proof that the harness works on live memory; Epic 4 tasks do the
-- hunting.
--   /run-lua lua/ramsearch_run.lua 3       log: /tmp/sam2/ramsearch.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local RS = dofile(here .. "ramsearch.lua")
SM.LOG = "/tmp/sam2/ramsearch.txt"; SM.open_log(); local say = SM.say
os.remove(SM.LOG)

local s16 = RS.new{ base = 0x100000, size = 0x10000, width = 16, log = function(m) say("w16 " .. m) end }
local s8  = RS.new{ base = 0x100000, size = 0x10000, width = 8,  log = function(m) say("w8  " .. m) end }
local T0 = SM.MATCH_LIVE_AT + 200     -- BEGIN gone, both idle
local steps = {
  { at = T0,       f = function() RS.selftest(say); s16:snapshot("idle1"); s8:snapshot("idle1") end },
  { at = T0 + 60,  f = function() s16:snapshot("idle2"); s8:snapshot("idle2"); s16:filter("unchanged"); s8:filter("unchanged") end },
  { at = T0 + 70,  f = function() manager.machine.ioport.ports[":edge:joy:JOY1"].fields["P1 Right"]:set_value(1); say("hold P1 Right") end },
  { at = T0 + 130, f = function() manager.machine.ioport.ports[":edge:joy:JOY1"].fields["P1 Right"]:clear_value(); say("release P1 Right")
                                  s16:snapshot("walked"); s8:snapshot("walked")
                                  s16:filter("changed"); s8:filter("changed")
                                  s16:report(SM.LOG, 40); s8:report(SM.LOG, 40) end },
  { at = T0 + 200, f = function() s16:snapshot("idle3"); s8:snapshot("idle3")
                                  s16:filter("unchanged"); s8:filter("unchanged")
                                  s16:report(SM.LOG, 40); s8:report(SM.LOG, 40)
                                  say("done") end },
}
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  for _, st in ipairs(steps) do
    if frame == st.at then
      local t0 = os.clock()
      local ok, err = pcall(st.f)
      say("frame %5d  step %s (%.1f ms)", frame, ok and "ok" or ("ERROR " .. tostring(err)), (os.clock() - t0) * 1000)
    end
  end
  if frame == T0 + 210 then sub = nil end
end)
