-- pause_probe.lua  (bead sam-l4r.4)  Which pause API exists in MAME 0.289's
-- Lua, and what keeps running while paused? Log: /tmp/sam2/pause_probe.txt
local OUT = assert(io.open("/tmp/sam2/pause_probe.txt", "w"))
local function say(fmt, ...) local s = string.format(fmt, ...); print("[pause_probe] " .. s); OUT:write(s, "\n"); OUT:flush() end
local m = manager.machine
say("emu.pause=%s emu.unpause=%s machine.pause=%s machine.resume=%s machine.paused=%s",
  type(emu.pause), type(emu.unpause), type(m.pause), type(m.resume), tostring(m.paused))
say("emu.wait_next_update=%s emu.wait_next_frame=%s emu.register_periodic=%s", type(emu.wait_next_update), type(emu.wait_next_frame), type(emu.register_periodic))
PN = emu.add_machine_pause_notifier(function() say("pause notifier fired; machine.paused=%s", tostring(m.paused)) end)
RN = emu.add_machine_resume_notifier(function() say("resume notifier fired; machine.paused=%s", tostring(m.paused)) end)
local frame, updates_while_paused, paused_at = 0, 0, nil
local function do_pause()
  if type(m.pause) == "function" then m:pause(); say("called machine:pause()")
  elseif type(emu.pause) == "function" then emu.pause(); say("called emu.pause()")
  else say("NO pause function found") end
end
local function do_resume()
  if type(m.resume) == "function" then m:resume(); say("called machine:resume()")
  elseif type(emu.unpause) == "function" then emu.unpause(); say("called emu.unpause()")
  else say("NO resume function found") end
end
FN = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame == 120 then paused_at = os.time(); do_pause(); say("frame %d: after pause call machine.paused=%s", frame, tostring(m.paused)) end
  if frame == 121 then say("frame 121 notifier fired (paused=%s) - frames still advance?", tostring(m.paused)) end
end)
-- a coroutine that waits on UI updates: does it run while paused?
CO = coroutine.create(function()
  while true do
    emu.wait_next_update()
    if m.paused then
      updates_while_paused = updates_while_paused + 1
      if updates_while_paused == 120 then say("120 UI updates happened while paused (%d s wall) -> resuming", os.time() - paused_at); do_resume(); say("after resume call machine.paused=%s", tostring(m.paused)) end
    end
    if updates_while_paused >= 120 and not m.paused and frame > 121 then say("frames advancing again: frame=%d; done", frame); OUT:close(); return end
  end
end)
local ok, err = coroutine.resume(CO)
say("coroutine start: %s %s", tostring(ok), tostring(err))
