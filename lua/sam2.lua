-- sam2.lua — autoboot entry: start the match and stream state.json.
--   /start-app  (stage 2)  or  /run-lua lua/sam2.lua 3
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init()
local frame = 0
-- The subscription must stay referenced (a global here) or MAME drops the
-- notifier as soon as this chunk returns.
SAM2_SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  C.tick(frame)
end)
