-- sam2.lua — autoboot entry: start the match and stream state.json.
--   /start-app  (stage 1)  or  /run-lua lua/sam2.lua 3
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init()
local frame = 0
local sub
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  C.tick(frame)
end)
