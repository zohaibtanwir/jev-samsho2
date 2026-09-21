-- moves_nakoruru.lua
-- Observed button behaviour for Nakoruru (P2 slot), bead sam-amj.5.
-- Same method as moves_earthquake.lua. Nothing reaches Earthquake from the
-- start-of-round gap (all six buttons: opponent bar stayed 128), so damage
-- was measured after walking in 45 frames; a 75-frame approach gave the
-- same numbers.
local M = {}

M.buttons = {
  A   = { name = "light slash",   damage_px = 8,  hits_from_start_gap = false, note = "quick short dagger slash, arc at +8" },
  B   = { name = "medium slash",  damage_px = 18, hits_from_start_gap = false, note = "overhead dagger slash, arc at +12, low follow-through +16" },
  C   = { name = "light kick",    damage_px = 4,  hits_from_start_gap = false, note = "low kick, +8..+12" },
  D   = { name = "strong kick",   damage_px = 9,  hits_from_start_gap = false, note = "high kick, leg at head height +12..+16" },
  AB  = { name = "heavy slash",   damage_px = 31, hits_from_start_gap = false, note = "long windup +8..+20, big slash at +26" },
  CD  = { name = "hop attack",    damage_px = 13, hits_from_start_gap = false, note = "leap/flip that connects when close; not a normal slash" },
}
M.heavy = { fields = { "P2 A", "P2 B" }, key = "AB", damage_px = 31 }
M.light = { fields = { "P2 A" }, key = "A", damage_px = 8 }
-- Reach: needs ~45 frames of walking from the start gap before anything lands.
M.approach_frames_from_start_gap = 45

return M
