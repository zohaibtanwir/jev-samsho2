-- start_match.lua  (bead sam-g6e.2)
-- From a cold boot, bring samsho2 to round 1 of Earthquake (P1) vs
-- Nakoruru (P2) with no human input. This is the Start sequence the bridge
-- and the Tauri app will reuse (PRD section 6).
--
-- Standalone:  /run-lua lua/start_match.lua 3
--   (MAME launched from ~/mame with -skip_gameinfo -sound none)
-- Embedded:    SAM2_EMBED = true; local sm = dofile(dir .. "start_match.lua")
--              then call sm.tick(frame) from your own frame notifier; it
--              returns true once the sequence has finished.
--
-- Timeline (frames from script start), all proven in sam-2r2.x / sam-g6e.1:
--   300 Coin 1, 340 Coin 1, 420 1 Player Start, 500 2 Players Start,
--   700 P1 A + P2 A (skips the 2P how-to-play tutorial),
--   800.. cursor taps every 40 frames from lua/select_map.lua,
--   then P1 A + P2 A to confirm, VS screen ~240 frames later, stage ~420
--   frames later, round 1 live some frames after that (measured below).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local MAP = dofile(here .. "select_map.lua")

local M = { LOG = "/tmp/sam2/start_match.txt" }

-- ---- schedule -------------------------------------------------------------
local events = {}   -- { at, port, name } ; each is a TAP_FRAMES-long tap
local function tap(at, port, name) events[#events + 1] = { at = at, port = port, name = name } end
for _, k in ipairs(MAP.setup) do tap(k.at, k.port, k.name) end
local t = 800
for i = 1, math.max(MAP.p1.steps.count, MAP.p2.steps.count) do
  if i <= MAP.p1.steps.count then tap(t, MAP.p1.port, MAP.p1.steps.dir) end
  if i <= MAP.p2.steps.count then tap(t, MAP.p2.port, MAP.p2.steps.dir) end
  t = t + MAP.GAP_FRAMES
end
M.CONFIRM_AT = t + 40
tap(M.CONFIRM_AT, MAP.p1.port, MAP.p1.confirm)
tap(M.CONFIRM_AT, MAP.p2.port, MAP.p2.confirm)
M.SEQUENCE_END = M.CONFIRM_AT + MAP.TAP_FRAMES
-- Measured over three cold-boot runs (sam-g6e.2): EN GARDE on screen at
-- frame 1624, round-1 timer reading 99 at 1744. Frame-count based until the
-- memory map (Epic 4) gives a real 'round live' signal.
M.EN_GARDE_AT = 1624
M.MATCH_LIVE_AT = 1744
M.events = events

-- ---- runtime ----------------------------------------------------------------
local log
local function say(fmt, ...)
  local s = string.format(fmt, ...)
  print("[start_match] " .. s)
  if log then log:write(s, "\n"); log:flush() end
end
M.say = say

local function field(port_tag, name)
  local port = manager.machine.ioport.ports[port_tag]; if not port then error("no port " .. port_tag) end
  local f = port.fields[name]; if not f then error("no field '" .. name .. "' on " .. port_tag) end
  return f
end

function M.open_log()
  os.execute("mkdir -p /tmp/sam2")
  log = assert(io.open(M.LOG, "w"))
  say("start_match.lua  mame %s  %d taps, confirm at %d", tostring(emu.app_version()), #events, M.CONFIRM_AT)
end

-- resolve fields lazily (ports exist once the machine is running)
local resolved = false
local function resolve()
  for _, e in ipairs(events) do
    local ok, f = pcall(field, e.port, e.name)
    if ok then e.field = f else say("ERROR %s", tostring(f)) end
  end
  resolved = true
end

-- Call once per frame. Returns true when the sequence is complete.
function M.tick(frame)
  if not resolved then resolve() end
  for _, e in ipairs(events) do
    if e.field then
      if frame == e.at then e.field:set_value(1); say("frame %5d  tap %s", frame, e.name)
      elseif frame == e.at + MAP.TAP_FRAMES then e.field:clear_value() end
    end
  end
  return frame >= M.SEQUENCE_END
end

-- ---- standalone --------------------------------------------------------------
if not SAM2_EMBED then
  M.open_log()
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
    if frame == DONE_AT then say("frame %5d  done", frame); log:close(); sub = nil end
  end)
end

return M
