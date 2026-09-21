-- bridge_check.lua  (bead sam-e8s.2)
-- sam2 core with a screenshot every 5 s, for runs driven by the bridge.
--   /run-lua lua/bridge_check.lua 3   then: python3 -m bridge.core --seconds 30
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init()
local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  C.tick(frame)
  if frame >= C.SM.MATCH_LIVE_AT and (frame - C.SM.MATCH_LIVE_AT) % 300 == 0 then pcall(function() manager.machine.video:snapshot() end) end
end)
