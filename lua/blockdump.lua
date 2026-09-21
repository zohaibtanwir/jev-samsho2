-- blockdump.lua  (beads sam-aug.3 / sam-aug.4)
-- Dump the player-block region of work RAM (0x105A00-0x1068FF, both player
-- blocks 0xB40 apart) plus the globals at 0x100A00-0x100AFF at fine
-- intervals around staged events, for offline diffing in Python. One line
-- per dump: "<frame> <label> <hex>".
--   /run-lua lua/blockdump.lua 3     out: /tmp/sam2/blockdump.txt
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
SM.LOG = "/tmp/sam2/blockdump_events.txt"; SM.open_log(); local say = SM.say
local OUT = assert(io.open("/tmp/sam2/blockdump.txt", "w"))
local STATE = "/tmp/sam2/blockdump.sta"
local J1, J2 = ":edge:joy:JOY1", ":edge:joy:JOY2"
local function fld(p, n) return manager.machine.ioport.ports[p].fields[n] end
local function hold(p, ...) for _, n in ipairs({ ... }) do fld(p, n):set_value(1) end end
local function rel(p, ...) for _, n in ipairs({ ... }) do fld(p, n):clear_value() end end
local function load() manager.machine:load(STATE) end
local REGIONS = { { 0x105A00, 0xF00 }, { 0x100A00, 0x100 } }
local space
local function dump(frame, label)
  local parts = {}
  for _, r in ipairs(REGIONS) do
    local raw = space:read_range(r[1], r[1] + r[2] - 1, 8)
    parts[#parts + 1] = (raw:gsub(".", function(c) return string.format("%02X", c:byte()) end))
  end
  OUT:write(frame, " ", label, " ", table.concat(parts, ""), "\n")
end
OUT:write("# regions: 0x105A00+0xF00, 0x100A00+0x100 ; hex bytes concatenated\n")

local steps, dumps = {}, {}   -- dumps[frame] = label
local function at(fr, f) steps[#steps + 1] = { at = fr, f = f } end
local function series(from, every, count, label) for i = 0, count - 1 do dumps[from + i * every] = string.format("%s+%d", label, i * every) end end
local T = SM.MATCH_LIVE_AT + 180
at(T, function() manager.machine:save(STATE); say("state saved") end)
local t = T + 30

-- A: P1 gets hit (rage P1, hitstun IDs). P2 walks in 45, A+B. dump every 5 frames for 400 frames from the press
at(t, function() load() end); at(t + 20, function() hold(J2, "P2 Left") end)
at(t + 65, function() rel(J2, "P2 Left"); hold(J2, "P2 A", "P2 B") end); at(t + 69, function() rel(J2, "P2 A", "P2 B") end)
dumps[t + 60] = "A_idle"; series(t + 65, 5, 80, "A_p1hit")
t = t + 480

-- B: P2 gets hit (rage P2). P1 B from the start gap. dump every 5 for 400
at(t, function() load() end); at(t + 50, function() hold(J1, "P1 B") end); at(t + 54, function() rel(J1, "P1 B") end)
dumps[t + 45] = "B_idle"; series(t + 50, 5, 80, "B_p2hit")
t = t + 470

-- C: P1 moves, each from a reload: dump every 2 frames for 80 frames from the press
local moves = {
  { "P1_A", J1, { "P1 A" } }, { "P1_B", J1, { "P1 B" } }, { "P1_C", J1, { "P1 C" } }, { "P1_D", J1, { "P1 D" } },
  { "P1_AB", J1, { "P1 A", "P1 B" } }, { "P1_walkR", J1, { "P1 Right" }, 40 }, { "P1_walkL", J1, { "P1 Left" }, 40 },
  { "P1_crouch", J1, { "P1 Down" }, 40 }, { "P1_jump", J1, { "P1 Up" } }, { "P1_block", J1, { "P1 Left" }, 40, "P2hits" },
  { "P2_A", J2, { "P2 A" } }, { "P2_B", J2, { "P2 B" } }, { "P2_C", J2, { "P2 C" } }, { "P2_D", J2, { "P2 D" } },
  { "P2_AB", J2, { "P2 A", "P2 B" } }, { "P2_walkL", J2, { "P2 Left" }, 40 }, { "P2_walkR", J2, { "P2 Right" }, 40 },
  { "P2_crouch", J2, { "P2 Down" }, 40 }, { "P2_jump", J2, { "P2 Up" } },
}
for _, m in ipairs(moves) do
  local name, port, keys, holdf, extra = m[1], m[2], m[3], m[4] or 4, m[5]
  local t0 = t
  at(t0, function() load() end)
  if name:match("^P2_") and not name:match("walk") and not name:match("crouch") and not name:match("jump") then
    -- Nakoruru must walk in 45 frames for her attacks to reach
    at(t0 + 20, function() hold(J2, "P2 Left") end); at(t0 + 65, function() rel(J2, "P2 Left") end)
    t0 = t0 + 50
  end
  dumps[t0 + 15] = name .. "_idle"
  at(t0 + 20, function() hold(port, table.unpack(keys)); say("%s press", name) end)
  at(t0 + 20 + holdf, function() rel(port, table.unpack(keys)) end)
  if extra == "P2hits" then at(t0 + 30, function() hold(J2, "P2 Left") end); at(t0 + 75, function() rel(J2, "P2 Left"); hold(J2, "P2 A", "P2 B") end); at(t0 + 79, function() rel(J2, "P2 A", "P2 B") end) end
  series(t0 + 20, 2, extra and 60 or 40, name)
  t = t0 + (extra and 180 or 130)
end
local DONE_AT = t + 10
at(DONE_AT - 1, function() OUT:close(); say("done") end)

local frame, sub = 0, nil
sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  SM.tick(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  for _, st in ipairs(steps) do if frame == st.at then local ok, e = pcall(st.f); if not ok then say("frame %d ERROR %s", frame, tostring(e)) end end end
  if dumps[frame] then dump(frame, dumps[frame]) end
  if frame == DONE_AT then sub = nil end
end)
