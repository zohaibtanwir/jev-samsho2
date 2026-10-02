-- perf_check.lua  (bead sam-yku.11) core + per-second timing to /tmp/sam2/speed.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); C.SPEED_PATH = "/tmp/sam2/speed.txt"
if os.getenv("SAM2_NOFRAMES") then C.FRAMES = false end
local frame = 0
SUB = emu.add_machine_frame_notifier(function() frame = frame + 1; C.tick(frame) end)
