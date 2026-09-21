-- executor_check.lua  (bead sam-amj.1)
-- sam2 core + screenshot on each applied action + a scripted forward jump by
-- P2 (Up+Left held 6 frames) when /tmp/sam2/do_jump appears, so the test
-- driver can put the fighters on crossed sides.
--   /run-lua lua/executor_check.lua 3   then: python3 tools/executor_test.py
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); C.SNAP_ON_ACTION = true
local frame, jump_at = 0, nil
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  C.tick(frame)
  if frame % 10 == 0 and not jump_at and io.open("/tmp/sam2/do_jump") then
    os.remove("/tmp/sam2/do_jump"); jump_at = frame
    local p = manager.machine.ioport.ports[":edge:joy:JOY2"].fields
    p["P2 Up"]:set_value(1); p["P2 Left"]:set_value(1); C.SM.say("frame %d  scripted P2 forward jump", frame)
  end
  if jump_at and frame == jump_at + 6 then
    local p = manager.machine.ioport.ports[":edge:joy:JOY2"].fields
    p["P2 Up"]:clear_value(); p["P2 Left"]:clear_value()
  end
  if jump_at and frame == jump_at + 60 then jump_at = nil end
end)
