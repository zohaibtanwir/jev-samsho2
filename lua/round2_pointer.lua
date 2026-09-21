-- round2_pointer.lua  (memory map moves between rounds; find how to follow it)
-- Dump the 64 KiB work RAM in round 1 and again in round 2 (Lua kills P2
-- to end round 1), and print the fields at the predicted offsets of the
-- round-2 block candidates. Offline: find 32-bit words whose value moved
-- by the same delta as the X address did (a pointer to the fighter object).
--   /run-lua lua/round2_pointer.lua 3   out: /tmp/sam2/round2_pointer.txt, ram_r1.bin, ram_r2.bin
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
SM.LOG = "/tmp/sam2/round2_pointer.txt"; SM.open_log(); local say = SM.say
local J1 = ":edge:joy:JOY1"
local function fld(n) return manager.machine.ioport.ports[J1].fields[n] end
local function hold(...) for _, n in ipairs({ ... }) do fld(n):set_value(1) end end
local function rel(...) for _, n in ipairs({ ... }) do fld(n):clear_value() end end
local space
local function dump(path) local f = assert(io.open(path, "wb")); f:write(space:read_range(0x100000, 0x10FFFF, 8)); f:close(); say("dumped " .. path) end
local function show(label, xaddr)
  say("%s block at X=0x%06X: x=%d y=%d health(+6C)=%d state(+76)=0x%04X rage(+A2)=%d", label, xaddr,
    space:read_u16(xaddr), space:read_u16(xaddr + 2), space:read_u16(xaddr + 0x6C), space:read_u16(xaddr + 0x76), space:read_u8(xaddr + 0xA2))
end
local phase, t0, low_seen, next_attack = "r1", 0, false, 0
local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if frame < SM.MATCH_LIVE_AT + 120 then return end
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  if phase == "r1" then
    dump("/tmp/sam2/ram_r1.bin"); show("round 1 P1", 0x105ACE); show("round 1 P2", 0x10660E); phase = "kill"
  elseif phase == "kill" then
    local p1, p2 = MM.read_player(space, MM.p1), MM.read_player(space, MM.p2)
    local timer = MM.read_timer(space)
    if p2.health > 0 then
      local gap = p2.x - p1.x
      if frame >= next_attack then
        if gap > 165 then hold("P1 Right") elseif gap < 90 then rel("P1 Right"); hold("P1 Left")
        else rel("P1 Right", "P1 Left"); hold("P1 A", "P1 B"); next_attack = frame + 110 end
      end
      if frame == next_attack - 106 then rel("P1 A", "P1 B") end
    else
      rel("P1 Right", "P1 Left", "P1 A", "P1 B")
      if timer < 90 then low_seen = true end
      if low_seen and timer >= 98 then phase = "r2intro"; t0 = frame; say("frame %d  round 2 timer reset", frame) end
    end
  elseif phase == "r2intro" and frame == t0 + 480 then
    dump("/tmp/sam2/ram_r2.bin")
    for _, x in ipairs({ 0x10300E, 0x104E6E }) do show("round 2 P1 cand", x) end
    for _, x in ipairs({ 0x10312E, 0x105E2E, 0x102BDC }) do show("round 2 P2 cand", x) end
    show("round 2 old P1", 0x105ACE); show("round 2 old P2", 0x10660E)
    say("done"); phase = "done"
  end
end)
