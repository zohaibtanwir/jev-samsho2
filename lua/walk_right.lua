-- walk_right.lua  (bead sam-2r2.2)
-- Coin, start, accept the default fighter with P1 A, then hold P1 Right
-- through the start of round 1 so the character walks right.
-- Verifies PRD section 12: "set_value() moves a character in this game".
--
-- Run:  /run-lua lua/walk_right.lua 3   (launch adds -skip_gameinfo -sound none)
-- Log:  /tmp/sam2/walk_right.txt
-- Snapshots: ~/mame/snap/samsho2/NNNN.png (video:snapshot(), one per SNAP_AT frame)
--
-- Frame counts are from script start (after -autoboot_delay). Timings for
-- coin and start are the ones proven in coin_start.lua (sam-2r2.1). Nothing
-- reads game memory yet, so the hold window is deliberately wide: it covers
-- the VS screen and the round-1 intro, and the character walks as soon as
-- the round is live. A single set_value() at the start of the hold and one
-- clear_value() at the end also tests whether the override persists.

local OUT = "/tmp/sam2/walk_right.txt"
local P1 = ":edge:joy:JOY1"
local SCHEDULE = {
  { at = 300,  hold = 8,    port = ":AUDIO_COIN",     name = "Coin 1" },
  { at = 420,  hold = 8,    port = ":edge:joy:START", name = "1 Player Start" },
  -- run 1 showed the grid ignores A at frame 540 (2 s after Start) and that
  -- held Right moves the select cursor; so confirm later, then skip the
  -- story intro with A taps, then hold Right across a 50 s window.
  { at = 720,  hold = 8,    port = P1, name = "P1 A" },      -- confirm default fighter
  { at = 1200, hold = 8,    port = P1, name = "P1 A" },      -- skip story text
  { at = 1500, hold = 8,    port = P1, name = "P1 A" },      -- skip story text
  { at = 1000, hold = 3000, port = P1, name = "P1 Right" },  -- 50 s hold
}
local SNAP_AT = {}
for fr = 1000, 4000, 240 do SNAP_AT[#SNAP_AT + 1] = fr end
local DONE_AT = 4060

os.execute("mkdir -p /tmp/sam2")
local log = assert(io.open(OUT, "w"))
local function say(fmt, ...)
  local s = string.format(fmt, ...)
  print("[walk_right] " .. s)
  log:write(s, "\n"); log:flush()
end
local function field(port_tag, name)
  local port = manager.machine.ioport.ports[port_tag]
  if not port then error("no port " .. port_tag) end
  local f = port.fields[name]
  if not f then error("no field '" .. name .. "' on " .. port_tag) end
  return f
end

say("walk_right.lua  mame %s", tostring(emu.app_version()))
for _, step in ipairs(SCHEDULE) do
  local ok, f = pcall(field, step.port, step.name)
  if ok then step.field = f; say("found  %-18s %-16s mask 0x%X", step.port, step.name, f.mask)
  else say("ERROR  %s", tostring(f)) end
end

local snaps = {}
for _, fr in ipairs(SNAP_AT) do snaps[fr] = true end

local frame = 0
local sub
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  for _, step in ipairs(SCHEDULE) do
    if step.field then
      if frame == step.at then
        step.field:set_value(1)
        say("frame %5d  press   %s", frame, step.name)
      elseif frame == step.at + step.hold then
        step.field:clear_value()
        say("frame %5d  release %s", frame, step.name)
      end
    end
  end
  if snaps[frame] then
    local ok, err = pcall(function() manager.machine.video:snapshot() end)
    say("frame %5d  snapshot %s", frame, ok and "ok" or ("FAILED " .. tostring(err)))
  end
  if frame == DONE_AT then
    say("frame %5d  done. MAME left running; stop it with /stop-app", frame)
    log:close()
    sub = nil
  end
end)
