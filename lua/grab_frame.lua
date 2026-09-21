-- grab_frame.lua  (beads sam-7ij.1 / sam-7ij.2)
-- Grab one frame with screen:pixels() once the match is live and write it
-- atomically to /tmp/sam2/frame.raw (frame.tmp then rename), plus a
-- frame.meta line with width, height and byte count. Convert with
-- tools/raw2png.py. Runs the normal start sequence first so the frame shows
-- the fight, not the boot screen.
--   /run-lua lua/grab_frame.lua 3
--   headless (sam-7ij.2): same, launched with -video none instead of -window
-- MAME 0.289 Lua ref (screen_device): pixels() returns a binary string of
-- 32-bit pixels in HOST endian order, row-major, plus width and height.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
SM.LOG = "/tmp/sam2/grab_frame.txt"; SM.open_log(); local say = SM.say
local GRAB_AT = SM.MATCH_LIVE_AT + 240

local function grab()
  local screen = manager.machine.screens[":screen"]
  if not screen then error("no :screen device") end
  local t0 = os.clock()
  local px, w, h = screen:pixels()
  local dt = (os.clock() - t0) * 1000
  say("screen width=%d height=%d xscale=%.3f yscale=%.3f", screen.width, screen.height, screen.xscale, screen.yscale)
  say("pixels(): %d bytes, visible %dx%d, %d bytes/pixel, %.2f ms", #px, w, h, #px // (w * h), dt)
  local f = assert(io.open("/tmp/sam2/frame.tmp", "wb")); f:write(px); f:close()
  assert(os.rename("/tmp/sam2/frame.tmp", "/tmp/sam2/frame.raw"))
  local m = assert(io.open("/tmp/sam2/frame.meta.tmp", "w")); m:write(string.format("%d %d %d\n", w, h, #px)); m:close()
  os.rename("/tmp/sam2/frame.meta.tmp", "/tmp/sam2/frame.meta")
  say("wrote /tmp/sam2/frame.raw and frame.meta")
  -- a PNG from MAME's own renderer for comparison
  screen:snapshot("/tmp/sam2/frame_mame.png")
  say("wrote /tmp/sam2/frame_mame.png via screen:snapshot")
end

local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  if frame == GRAB_AT then
    local ok, err = pcall(grab)
    say(ok and "grab ok" or ("grab FAILED: " .. tostring(err)))
    say("done")
  end
end)
