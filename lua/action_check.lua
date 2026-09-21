-- action_check.lua  (bead sam-e8s.1)
-- sam2 core with a screenshot taken whenever a new action.json is applied.
--   /run-lua lua/action_check.lua 3   then: python3 tools/action_test.py
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); C.SNAP_ON_ACTION = true
local frame = 0
-- keep the subscription referenced or MAME drops the notifier
SUB = emu.add_machine_frame_notifier(function() frame = frame + 1; C.tick(frame) end)
