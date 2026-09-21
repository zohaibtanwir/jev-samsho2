-- ptr_check.lua: do the fighter object pointers point at the right objects in round 1 of a fresh boot?
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua"); local MM = dofile(here .. "memmap.lua")
SM.LOG = "/tmp/sam2/ptr_check.txt"; SM.open_log(); local say = SM.say
local space; local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1; SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  if frame >= 1200 and frame % 120 == 0 and frame <= 3000 then
    local b1, b2 = space:read_u32(MM.P1_PTR), space:read_u32(MM.P2_PTR)
    say("frame %d  ptrP1=0x%06X ptrP2=0x%06X | via ptr: p1 x=%d hp=%d  p2 x=%d hp=%d | round-1 abs: p1 x=%d hp=%d  p2 x=%d hp=%d",
      frame, b1, b2, space:read_u16(b1 + 0x4E), space:read_u16(b1 + 0xBA), space:read_u16(b2 + 0x4E), space:read_u16(b2 + 0xBA),
      space:read_u16(0x105ACE), space:read_u16(0x105B3A), space:read_u16(0x10660E), space:read_u16(0x10667A))
    if frame == 3000 then say("done") end
  end
end)
