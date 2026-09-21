-- frame_writer_check.lua  (bead sam-7ij.3)
-- sam2 core with the frame writer on and speed logged once a second to
-- /tmp/sam2/speed.txt. Run 60 s windowed, then 60 s with -video none.
--   /run-lua lua/frame_writer_check.lua 3
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); C.SPEED_PATH = "/tmp/sam2/speed.txt"
local frame = 0
SUB = emu.add_machine_frame_notifier(function() frame = frame + 1; C.tick(frame) end)
