-- moveids.lua  (bead sam-aug.4)
-- Action word decode for samsho2. One 16-bit word per player
-- (memmap p1.state 0x105B44 / p2.state 0x106684). High byte = kind, low
-- byte = id. Read from lua/blockdump.lua dumps every 2 frames (bead notes).
--
--   kind 0x00  movement:  0 idle, 1 walk forward, 2 walk back (blocks when
--                         the opponent attacks), 4 crouch, 6 airborne,
--                         0x12 landing recovery (~16 frames), 0x0B/0x0A
--                         crouch-down / stand-up transitions (few frames),
--                         0xFFFF for the last frame of some moves.
--   kind 0x01  attack:    low byte is the button: A=0x01 B=0x06 C=0x10 D=0x15
--                         A+B=0x0B. Same ids for Earthquake and Nakoruru;
--                         durations and hit frames differ per character.
--                         The word holds the same value from the first frame
--                         to the last, so "recovery" is decoded from the
--                         move's age: frames since the word last changed.
--   kind 0x03  hit stun:  low byte 1 light, 2 medium, 6 heavy. Lasts ~50
--                         frames after a medium hit, ~90 after a heavy.
--   (block stun was not observed in the dumps: unknown code.)
local M = {}

M.KIND_MOVE, M.KIND_ATTACK, M.KIND_HITSTUN = 0x00, 0x01, 0x03
M.MOVE = { idle = 0x00, walk_fwd = 0x01, walk_back = 0x02, crouch = 0x04, air = 0x06, landing = 0x12, crouch_down = 0x0B, stand_up = 0x0A }
M.ATTACK = { A = 0x01, B = 0x06, C = 0x10, D = 0x15, AB = 0x0B }

-- Per character, per attack id: total frames, first frame the hit lands
-- (from the opponent's health), and the frame after which we call it
-- recovery. Measured from a 4-frame tap at the start gap (Earthquake) or
-- after a 45-frame walk-in (Nakoruru). Kicks that never connected in tests
-- (Earthquake C, D) get active_end from the animation midpoint.
M.earthquake = {
  [0x01] = { name = "A light slash",  total = 30, hit_at = 10, active_end = 16 },
  [0x06] = { name = "B medium slash", total = 64, hit_at = 14, active_end = 22 },
  [0x0B] = { name = "A+B heavy slash", total = 78, hit_at = 16, active_end = 26 },
  [0x10] = { name = "C kick",         total = 26, hit_at = nil, active_end = 16 },
  [0x15] = { name = "D kick",         total = 36, hit_at = nil, active_end = 20 },
}
M.nakoruru = {
  [0x01] = { name = "A light slash",  total = 22, hit_at = 6,  active_end = 12 },
  [0x06] = { name = "B medium slash", total = 42, hit_at = 6,  active_end = 14 },
  [0x0B] = { name = "A+B heavy slash", total = 78, hit_at = 10, active_end = 40 },  -- two hits: +10 and ~+35
  [0x10] = { name = "C light kick",   total = 22, hit_at = 10, active_end = 14 },
  [0x15] = { name = "D strong kick",  total = 46, hit_at = 8,  active_end = 18 },
}
M.by_character = { Earthquake = M.earthquake, Nakoruru = M.nakoruru }

-- Tracker: call update(word) once per frame; returns a table
-- { word, kind, id, age, phase, name } where phase is one of
-- idle walk_fwd walk_back crouch air landing transition startup active recovery hitstun unknown.
function M.new_tracker(character)
  local tbl = M.by_character[character] or {}
  local t = { last = nil, age = 0 }
  function t:update(word)
    if word == self.last then self.age = self.age + 1 else self.last = word; self.age = 0 end
    local kind, id = word >> 8, word & 0xFF
    local r = { word = word, kind = kind, id = id, age = self.age }
    if word == 0xFFFF then r.phase = "transition"
    elseif kind == M.KIND_ATTACK then
      local mv = tbl[id]
      r.name = mv and mv.name or string.format("attack 0x%02X", id)
      if not mv then r.phase = "active"
      elseif self.age > mv.active_end then r.phase = "recovery"
      elseif mv.hit_at and self.age < mv.hit_at - 2 then r.phase = "startup"
      else r.phase = "active" end
    elseif kind == M.KIND_HITSTUN then r.phase = "hitstun"
    elseif kind == M.KIND_MOVE then
      for n, v in pairs(M.MOVE) do if v == id then r.phase = n end end
      if id == M.MOVE.crouch_down or id == M.MOVE.stand_up then r.phase = "transition" end
      r.phase = r.phase or "unknown"
    else r.phase = "unknown" end
    return r
  end
  return t
end

return M
