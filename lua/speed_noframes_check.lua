-- speed_noframes_check.lua  (bead sam-e8s.5)
-- sam2 core with the frame writer OFF and speed logged to /tmp/sam2/speed.txt,
-- the comparison run for the "files don't slow the game" measurement.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); C.FRAMES = false; C.SPEED_PATH = "/tmp/sam2/speed.txt"
local frame = 0
SUB = emu.add_machine_frame_notifier(function() frame = frame + 1; C.tick(frame) end)
