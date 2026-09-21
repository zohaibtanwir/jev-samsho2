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
  health = { addr = 0x105B3A, width = 16, note = "0x80 (128) full; -0x1F after Nakoruru A+B, -0x12 after B; matches the 128 px bar 1:1. sam-aug.2" },
}
M.p2 = {
  x      = { addr = 0x10660E, width = 16, note = "400 (0x190) at round start; 0x122..0x176 seen while walking. sam-aug.2" },
  y      = { addr = 0x106610, width = 16, note = "0xE0 on the ground; 0x74 near apex of a jump. sam-aug.2" },
  health = { addr = 0x10667A, width = 16, note = "0x80 full; -0x23 after Earthquake A+B, -0x11 after B. sam-aug.2" },
}
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
  return { x = M.read(space, p.x), y = M.read(space, p.y), health = M.read(space, p.health) }
end

return M
