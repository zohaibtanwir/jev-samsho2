-- select_map.lua  (bead sam-g6e.1)
-- Character-select data for Samurai Shodown II (samsho2, MAME 0.289).
-- Read off select_probe.lua run 4 snapshots (~/mame/snap/samsho2/0077-0100.png,
-- large art per cursor step). Frame counts are from script start after
-- -autoboot_delay 3, launched with -skip_gameinfo.
--
-- The grid behaves as one 15-slot cycle. From the default cursor (Haohmaru),
-- each Right tap advances one slot and wraps; Left goes the other way.
--   0 Haohmaru  1 Genjuro  2 Hanzo  3 Charlotte  4 Wan-Fu  5 Gen-an
--   6 Nakoruru  7 Jubei    8 Ukyo   9 Cham Cham  10 Earthquake
--   11 Nicotine 12 Galford 13 Sieger 14 Kyoshiro
--
-- Timeline that gets both players onto a live grid:
--   frame 300 Coin 1, 340 Coin 1 (second credit), 420 "1 Player Start",
--   500 "2 Players Start" (P2 joins). 2P start leads to a how-to-play
--   tutorial; one tap of A on both sides at frame 700 skips it. The grid is
--   live by frame 760 and auto-picks between frames 1240 and 1360, so all
--   cursor moves must finish before ~1200. A 4-frame tap moves one slot;
--   40 frames between taps was reliable (30 was too, 20 was not tested).

local M = {}

M.TAP_FRAMES = 4      -- how long a tap is held
M.GAP_FRAMES = 40     -- frames between taps
M.GRID_LIVE_AT = 760  -- first frame the grid accepts input (proven)
M.AUTO_PICK_AT = 1240 -- earliest frame the game picks for you (proven)

M.setup = {
  { at = 300, port = ":AUDIO_COIN",     name = "Coin 1" },
  { at = 340, port = ":AUDIO_COIN",     name = "Coin 1" },
  { at = 420, port = ":edge:joy:START", name = "1 Player Start" },
  { at = 500, port = ":edge:joy:START", name = "2 Players Start" },
  { at = 700, port = ":edge:joy:JOY1",  name = "P1 A" },   -- skip tutorial
  { at = 700, port = ":edge:joy:JOY2",  name = "P2 A" },
}

-- Steps from the default slot. Shortest path in each case; the long path is
-- the one the probe actually walked, kept as a fallback.
M.p1 = {
  target = "Earthquake", slot = 10, port = ":edge:joy:JOY1",
  steps    = { dir = "P1 Left",  count = 5 },
  fallback = { dir = "P1 Right", count = 10 },
  confirm  = "P1 A",
}
M.p2 = {
  target = "Nakoruru", slot = 6, port = ":edge:joy:JOY2",
  steps    = { dir = "P2 Right", count = 6 },
  fallback = { dir = "P2 Left",  count = 9 },
  confirm  = "P2 A",
}

return M
