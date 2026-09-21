-- savestate_probe.lua  (bead sam-g6e.3)
-- Save a state once round 1 is live, let the match change visibly (P1 walks
-- right, timer runs), then load the state and see whether the game rewinds.
-- MAME 0.289 Lua ref (ref-core, running_machine): machine:save(filename) and
-- machine:load(filename) "schedule" the operation; they return immediately.
--
-- Run:  /run-lua lua/savestate_probe.lua 3      log: /tmp/sam2/savestate.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
SM.LOG = "/tmp/sam2/savestate.txt"; SM.open_log(); local say = SM.say

local STATE = "/tmp/sam2/match_start.sta"
local SAVE_AT = SM.MATCH_LIVE_AT + 60          -- 1804
local WALK_FROM, WALK_TO = SAVE_AT + 60, SAVE_AT + 360
local LOAD_AT = SAVE_AT + 600                  -- 2404, 10 s later
local snaps = {}
for _, fr in ipairs({ SAVE_AT - 1, SAVE_AT + 1, WALK_TO, LOAD_AT - 1, LOAD_AT + 1, LOAD_AT + 2, LOAD_AT + 10, LOAD_AT + 60, LOAD_AT + 300 }) do snaps[fr] = true end
local DONE_AT = LOAD_AT + 360

local right
local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if frame == WALK_FROM then right = manager.machine.ioport.ports[":edge:joy:JOY1"].fields["P1 Right"]; right:set_value(1); say("frame %5d  hold P1 Right", frame) end
  if frame == WALK_TO then right:clear_value(); say("frame %5d  release P1 Right", frame) end
  if frame == SAVE_AT then
    local ok, err = pcall(function() manager.machine:save(STATE) end)
    say("frame %5d  machine:save(%s) -> %s", frame, STATE, ok and "scheduled" or tostring(err))
  end
  if frame == LOAD_AT then
    local ok, err = pcall(function() manager.machine:load(STATE) end)
    say("frame %5d  machine:load(%s) -> %s", frame, STATE, ok and "scheduled" or tostring(err))
  end
  if snaps[frame] then
    local ok = pcall(function() manager.machine.video:snapshot() end)
    say("frame %5d  snapshot %s", frame, ok and "ok" or "FAILED")
  end
  if frame == DONE_AT then say("frame %5d  done", frame); sub = nil end
end)
