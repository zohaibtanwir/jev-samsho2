-- memmap.lua
-- Memory map for samsho2 (MAME 0.289, maincpu program space), found with
-- lua/ramsearch.lua. Each entry: address, width in bits, how it was found.
-- Two player blocks 0xB40 apart: P1 at 0x105A.., P2 at 0x1066... The
-- blocks 0x120 after each (0x105BEE.., 0x1064EE..) carry copies of X and
-- are not the player. See bead sam-aug.2 notes for the search runs.
local M = {}

-- ---------------------------------------------------------------------------
-- The fighter objects MOVE between rounds (found while closing sam-l4r.5:
-- round 1 P1 at 0x105A80, round 2 at 0x104E20; P2 0x1065C0 -> 0x1030E0).
-- Two 32-bit pointers in low work RAM always point at the live objects:
--   P1 object pointer 0x100A46, P2 object pointer 0x100A4A
-- (found by diffing full RAM dumps between rounds: the only words that moved
-- by exactly the same delta as the X address). All fields below are offsets
-- from that base; the absolute addresses recorded by sam-aug.2/3/4 are the
-- round-1 values (base + offset) and are kept for reference.
-- ---------------------------------------------------------------------------
M.P1_PTR, M.P2_PTR = 0x100A46, 0x100A4A
M.OFF = { x = 0x4E, y = 0x50, score = 0x92, health = 0xBA, state = 0xC4, hits = 0xE4, rage = 0xF0 }
M.BASE_R1 = { p1 = 0x105A80, p2 = 0x1065C0 }

function M.base(space, who)
  local b = space:read_u32(who == "p1" and M.P1_PTR or M.P2_PTR)
  if b < 0x100000 or b > 0x10FF00 then return nil end
  return b
end

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

-- Read all fields of a player block into a table, following the object pointer.
-- p is M.p1 or M.p2 (used only to know which pointer to follow).
function M.read_player(space, p)
  local who = (p == M.p1) and "p1" or "p2"
  local b = M.base(space, who) or M.BASE_R1[who]
  local st = space:read_u16(b + M.OFF.state)
  local y = space:read_u16(b + M.OFF.y)
  return { x = space:read_u16(b + M.OFF.x), y = y, health = space:read_u16(b + M.OFF.health), rage = space:read_u8(b + M.OFF.rage),
           state = st, crouching = (st == M.STATE_CROUCH), airborne = (st == M.STATE_AIR) or (y < M.ground_y), base = b }
end

function M.bcd(v) return (v >> 4) * 10 + (v & 0xF) end
function M.read_timer(space) return M.bcd(M.read(space, M.timer)) end

return M
