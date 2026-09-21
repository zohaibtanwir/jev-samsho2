-- coin_start.lua  (bead sam-2r2.1)
-- Insert a coin and press 1 Player Start from an autoboot script.
--
-- Run from ~/mame (rompath in mame.ini is relative):
--   mame samsho2 -window -nomaximize -autoboot_script <abs path>/lua/coin_start.lua -autoboot_delay 3
-- or from the project:  /run-lua lua/coin_start.lua 3
--
-- Port and field names are copied from /tmp/sam2/probe.txt.
-- set_value(v) on a digital field holds the override until clear_value()
-- (MAME Lua ref, ioport_field), so each press is a set at one frame and a
-- clear a few frames later, driven by the machine frame notifier.

local OUT = "/tmp/sam2/coin_start.txt"

-- Frames are counted from the moment this script starts running, i.e. after
-- -autoboot_delay. The Neo Geo BIOS may still be on its boot screen for the
-- first seconds, so the coin goes in late enough to land in attract mode.
local SCHEDULE = {
  { at = 300, hold = 8, port = ":AUDIO_COIN",     name = "Coin 1" },
  { at = 420, hold = 8, port = ":edge:joy:START", name = "1 Player Start" },
}
local DONE_AT = 600  -- frames; log a final line and stop the notifier

os.execute("mkdir -p /tmp/sam2")
local log = assert(io.open(OUT, "w"))
local function say(fmt, ...)
  local s = string.format(fmt, ...)
  print("[coin_start] " .. s)
  log:write(s, "\n")
  log:flush()
end

local function field(port_tag, name)
  local port = manager.machine.ioport.ports[port_tag]
  if not port then error("no port " .. port_tag) end
  local f = port.fields[name]
  if not f then error("no field '" .. name .. "' on " .. port_tag) end
  return f
end

say("coin_start.lua  mame %s", tostring(emu.app_version()))
for _, step in ipairs(SCHEDULE) do
  local ok, f = pcall(field, step.port, step.name)
  if ok then
    step.field = f
    say("found  %-18s %-16s mask 0x%X", step.port, step.name, f.mask)
  else
    say("ERROR  %s", tostring(f))
  end
end

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
  if frame == DONE_AT then
    say("frame %5d  done. MAME left running; stop it with /stop-app", frame)
    log:close()
    sub = nil  -- drop the subscription so the notifier stops
  end
end)
