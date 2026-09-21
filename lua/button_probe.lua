-- button_probe.lua  (bead sam-amj.5)
-- Start an Earthquake vs Nakoruru match, then tap each attack button (and
-- the A+B / C+D chords) for P1 Earthquake, then for P2 Nakoruru, with three
-- snapshots after every tap, so what each button does is read off the
-- frames rather than assumed.
--
-- Run:  /run-lua lua/button_probe.lua 3
-- Log:  /tmp/sam2/buttons.txt      Snapshots: ~/mame/snap/samsho2/NNNN.png

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
SM.LOG = "/tmp/sam2/buttons.txt"
SM.open_log()
local say = SM.say

local P1, P2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local COMBOS = { {"A"}, {"B"}, {"C"}, {"D"}, {"A","B"}, {"C","D"} }
local GAP, HOLD = 180, 4
local SNAP_OFFSETS = { 6, 18, 36 }

local function field(port_tag, name)
  local f = manager.machine.ioport.ports[port_tag].fields[name]
  if not f then error("no field " .. name) end
  return f
end

-- schedule: P1 first, then P2
local presses = {}
local t = SM.MATCH_LIVE_AT + 60
for _, who in ipairs({ { port = P1, pre = "P1 ", who = "P1 Earthquake" }, { port = P2, pre = "P2 ", who = "P2 Nakoruru" } }) do
  for _, combo in ipairs(COMBOS) do
    local names = {}
    for i, b in ipairs(combo) do names[i] = who.pre .. b end
    presses[#presses + 1] = { at = t, port = who.port, names = names, label = who.who .. " " .. table.concat(combo, "+") }
    t = t + GAP
  end
end
local DONE_AT = t + 60
local snaps = {}
for _, p in ipairs(presses) do
  for _, off in ipairs(SNAP_OFFSETS) do snaps[p.at + off] = p.label .. " +" .. off end
end

local frame, sub, resolved = 0, nil, false
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if not resolved and frame > 10 then
    for _, p in ipairs(presses) do
      p.fields = {}
      for i, n in ipairs(p.names) do p.fields[i] = field(p.port, n) end
    end
    resolved = true
    say("button probe: %d presses from frame %d, %d snapshots", #presses, presses[1].at, #presses * #SNAP_OFFSETS)
  end
  for _, p in ipairs(presses) do
    if frame == p.at then for _, f in ipairs(p.fields) do f:set_value(1) end; say("frame %5d  press   %s", frame, p.label)
    elseif frame == p.at + HOLD then for _, f in ipairs(p.fields) do f:clear_value() end end
  end
  if snaps[frame] then
    local ok = pcall(function() manager.machine.video:snapshot() end)
    say("frame %5d  snap %s (%s)", frame, ok and "ok" or "FAILED", snaps[frame])
  end
  if frame == DONE_AT then say("frame %5d  done", frame); sub = nil end
end)
