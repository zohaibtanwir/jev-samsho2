-- select_probe.lua  (bead sam-g6e.1)
-- Probe used to map the character select grid (runs 1-4, see bead notes)
-- and now a playback check of lua/select_map.lua (run 5): drives both
-- cursors to Earthquake / Nakoruru, confirms, and snapshots what follows.
--
-- Run:  /run-lua lua/select_probe.lua 3
-- Log:  /tmp/sam2/select_probe.txt   (frame, action, snapshot ordinal)
-- Snapshots: ~/mame/snap/samsho2/NNNN.png in the order listed in the log.
--
-- Timings proven so far (sam-2r2.1/2): coin at 300, 1P start at 420, the
-- grid ignores input at 540 and accepts it by 720, and auto-picks about
-- 13 s (~780 frames) after it appears (~frame 430), i.e. around 1210.
-- Two credits go in so 2P start can join.

local OUT = "/tmp/sam2/select_probe.txt"
local P1, P2, START, COIN = ":edge:joy:JOY1", ":edge:joy:JOY2", ":edge:joy:START", ":AUDIO_COIN"
local TAP = 4  -- frames a tap is held

os.execute("mkdir -p /tmp/sam2")
local log = assert(io.open(OUT, "w"))
local function say(fmt, ...) local s = string.format(fmt, ...); print("[select_probe] " .. s); log:write(s, "\n"); log:flush() end
local function field(port_tag, name)
  local port = manager.machine.ioport.ports[port_tag]; if not port then error("no port " .. port_tag) end
  local f = port.fields[name]; if not f then error("no field '" .. name .. "' on " .. port_tag) end
  return f
end

-- build the schedule: {at, fields = {{port,name},...}, snap = bool, label}
local S = {}
local function press(at, label, ...) S[#S + 1] = { at = at, label = label, keys = { ... } } end
local function snap(at, label) S[#S + 1] = { at = at, label = label, snap = true } end

-- Run 5 (playback): drive both cursors from lua/select_map.lua, snapshot,
-- then confirm both with A and keep snapshotting to see what follows.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local MAP = dofile(here .. "select_map.lua")
for _, k in ipairs(MAP.setup) do press(k.at, k.name, { k.port, k.name }) end
snap(770, "default a"); snap(790, "default b")
local t = 800
local n = math.max(MAP.p1.steps.count, MAP.p2.steps.count)
for i = 1, n do
  local keys = {}
  if i <= MAP.p1.steps.count then keys[#keys + 1] = { MAP.p1.port, MAP.p1.steps.dir } end
  if i <= MAP.p2.steps.count then keys[#keys + 1] = { MAP.p2.port, MAP.p2.steps.dir } end
  press(t, "step " .. i, table.unpack(keys))
  t = t + MAP.GAP_FRAMES
end
snap(t + 10, "final cursors a"); snap(t + 24, "final cursors b")
t = t + 40
press(t, "confirm P1 A + P2 A", { MAP.p1.port, MAP.p1.confirm }, { MAP.p2.port, MAP.p2.confirm })
for i = 1, 8 do snap(t + 60 * i, "after confirm " .. i) end
t = t + 60 * 8
local DONE_AT = t + 30

-- resolve fields
for _, s in ipairs(S) do
  if s.keys then
    s.fields = {}
    for _, k in ipairs(s.keys) do
      local ok, f = pcall(field, k[1], k[2])
      if ok then s.fields[#s.fields + 1] = f else say("ERROR %s", tostring(f)) end
    end
  end
end
say("select_probe.lua  mame %s   %d scheduled actions, done at %d", tostring(emu.app_version()), #S, DONE_AT)

local frame, snapn, sub = 0, 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, s in ipairs(S) do
    if s.fields and frame == s.at then
      for _, f in ipairs(s.fields) do f:set_value(1) end
      say("frame %5d  press   %s", frame, s.label)
    elseif s.fields and frame == s.at + TAP then
      for _, f in ipairs(s.fields) do f:clear_value() end
    elseif s.snap and frame == s.at then
      snapn = snapn + 1
      local ok, err = pcall(function() manager.machine.video:snapshot() end)
      say("frame %5d  snap #%02d %s  (%s)", frame, snapn, ok and "ok" or "FAILED " .. tostring(err), s.label)
    end
  end
  if frame == DONE_AT then say("frame %5d  done", frame); log:close(); sub = nil end
end)
