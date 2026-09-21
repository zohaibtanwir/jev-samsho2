-- start_match_run.lua  (bead sam-g6e.2)
-- Standalone check of start_match.lua: run the Start sequence from cold
-- boot and snapshot every 120 frames afterwards.
--   /run-lua lua/start_match_run.lua 3      log: /tmp/sam2/start_match.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local M = dofile(here .. "start_match.lua")
M.open_log()
local say = M.say
local SNAP_AT = {}
for fr = M.SEQUENCE_END + 60, M.SEQUENCE_END + 1500, 120 do SNAP_AT[fr] = true end
local DONE_AT = M.SEQUENCE_END + 1560
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  M.tick(frame)
  if SNAP_AT[frame] then
    local ok, err = pcall(function() manager.machine.video:snapshot() end)
    say("frame %5d  snapshot %s", frame, ok and "ok" or tostring(err))
  end
  if frame == DONE_AT then say("frame %5d  done", frame); sub = nil end
end)
