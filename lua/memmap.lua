-- memmap.lua
-- Memory map for samsho2 (MAME 0.289, maincpu program space), found with
-- lua/ramsearch.lua. Each entry: address, width in bits, how it was found.
-- Two player blocks 0xB40 apart: P1 at 0x105A.., P2 at 0x1066... The
-- blocks 0x120 after each (0x105BEE.., 0x1064EE..) carry copies of X and
-- are not the player. See bead sam-aug.2 notes for the search runs.
local M = {}

M.P1_P2_STRIDE = 0xB40

M.p1 = {
  x      = { addr = 0x105ACE, width = 16, note = "240 (0xF0) at round start; +1/frame walking; 0x10B..0x13B seen. sam-aug.2" },
  y      = { addr = 0x105AD0, width = 16, note = "0xE0 on the ground; decreases in the air (0x55 near apex); back to 0xE0 on landing. sam-aug.2" },
  health = { addr = 0x105B3A, width = 16, note = "0x80 (128) full; -0x1F after Nakoruru A+B, -0x12 after B; matches the 128 px bar 1:1. Drains ~1/frame after a hit, not instantly. sam-aug.2" },
  rage   = { addr = 0x105B70, width = 8,  note = "POW gauge. 0 at round start; +1/frame while health drains after a hit (+17 for a 31-damage hit, +6 for 16); saturates at 32 = rage max (flashing POW plate). sam-aug.3" },
  state  = { addr = 0x105B44, width = 16, note = "0 standing, 4 crouching (P1 Down held), 6 airborne (whole jump). sam-aug.3" },
}
M.p2 = {
  x      = { addr = 0x10660E, width = 16, note = "400 (0x190) at round start; 0x122..0x176 seen while walking. sam-aug.2" },
  y      = { addr = 0x106610, width = 16, note = "0xE0 on the ground; 0x74 near apex of a jump. sam-aug.2" },
  health = { addr = 0x10667A, width = 16, note = "0x80 full; -0x23 after Earthquake A+B, -0x11 after B. sam-aug.2" },
  rage   = { addr = 0x1066B0, width = 8,  note = "POW gauge, same behaviour as P1 (+6 per Earthquake B hit). sam-aug.3" },
  state  = { addr = 0x106684, width = 16, note = "0 standing, 4 crouching, 6 airborne. sam-aug.3" },
}
M.timer = { addr = 0x100AC6, width = 8, note = "Round timer, BCD: 0x96 = 96 on screen. Decrements about every 40 frames. sam-aug.3", bcd = true }
M.rage_max = 32
M.STATE_STAND, M.STATE_CROUCH, M.STATE_AIR = 0, 4, 6

-- Not the player, but found on the way (sam-aug.3): per-player score in BCD
-- at 0x105B12 / 0x106652 (+250 per medium hit, +550 per heavy), hits-landed
-- counters at 0x105B64 / 0x1066A4, last-hit code at 0x100A88 / 0x100A89,
-- last-hit damage at 0x100ADA, shared post-hit timer at 0x105AFA / 0x10663A.

M.health_max = 0x80
M.ground_y = 0xE0

-- Not players, but useful: move with the camera/scroll when either walks.
M.camera_x_candidates = { 0x100A7E, 0x1059AE }

function M.read(space, e)
  if e.width == 8 then return space:read_u8(e.addr) end
  return space:read_u16(e.addr)
end

-- Read all fields of a player block into a table.
function M.read_player(space, p)
  local st = M.read(space, p.state)
  local y = M.read(space, p.y)
  return { x = M.read(space, p.x), y = y, health = M.read(space, p.health), rage = M.read(space, p.rage),
           state = st, crouching = (st == M.STATE_CROUCH), airborne = (st == M.STATE_AIR) or (y < M.ground_y) }
end

function M.bcd(v) return (v >> 4) * 10 + (v & 0xF) end
function M.read_timer(space) return M.bcd(M.read(space, M.timer)) end

return M
