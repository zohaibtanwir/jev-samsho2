-- moves_earthquake.lua
-- Observed button behaviour for Earthquake (P1 slot), bead sam-amj.5.
-- Method: save state once round 1 is live, reload before every press, tap
-- the button 4 frames, snapshot the animation, read the opponent's health
-- bar 90 frames later (bar = 128 px at full). lua/button_probe.lua pass 1
-- (start gap) and pass 2 (kicks after a 30-frame approach). Damage is the
-- bar shrink in pixels from the start-of-round gap; 0 means it did not
-- connect from there, not that it does no damage.
local M = {}

M.buttons = {
  A   = { name = "light slash",   damage_px = 9,  hits_from_start_gap = true,  note = "quick close swing, hit spark at +12..+16" },
  B   = { name = "medium slash",  damage_px = 16, hits_from_start_gap = true,  note = "forward chain-sickle sweep, hit at +16..+20" },
  C   = { name = "kick (short)",  damage_px = 0,  hits_from_start_gap = false, note = "standing kick; did not connect at start gap or after 30-frame approach" },
  D   = { name = "kick (high)",   damage_px = 0,  hits_from_start_gap = false, note = "higher/lunging kick; did not connect in tests" },
  AB  = { name = "heavy slash",   damage_px = 33, hits_from_start_gap = true,  note = "long windup, overhead smash, screen flash at +16, blood" },
  CD  = { name = "forward hop",   damage_px = 0,  hits_from_start_gap = false, note = "body lunge/hop, no hit at start gap; not an attack for the executor" },
}
-- Intent "attack" -> heavy normal, as observed (PRD section 8):
M.heavy = { fields = { "P1 A", "P1 B" }, key = "AB", damage_px = 33 }
M.light = { fields = { "P1 A" }, key = "A", damage_px = 9 }

return M
