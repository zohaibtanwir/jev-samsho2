-- sam2core.lua
-- The game-side core: starts the match (start_match.lua), reads the memory
-- map every frame and writes /tmp/sam2/state.json (PRD section 9 state)
-- atomically (state.tmp then os.rename). Later tasks add the action reader
-- and the frame writer here. Entry points: lua/sam2.lua (autoboot) and the
-- check scripts, which call core.init() then core.tick(frame) per frame.
--   (bead sam-aug.5)
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SM = dofile(here .. "start_match.lua")
local MM = dofile(here .. "memmap.lua")
local MV = dofile(here .. "moveids.lua")

local C = { SM = SM, MM = MM, MV = MV, STATE_PATH = "/tmp/sam2/state.json", TMP_PATH = "/tmp/sam2/state.tmp" }
C.P1_NAME, C.P2_NAME = "Earthquake", "Nakoruru"

-- JSON: MAME ships a json module; fall back to a tiny encoder if absent.
local ok_json, json = pcall(require, "json")
local function enc(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local out = {}
      for i, x in ipairs(v) do out[i] = enc(x) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = string.format("%q:%s", k, enc(v[k])) end
    return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "number" then return tostring(v)
  elseif t == "boolean" then return v and "true" or "false"
  else return "null" end
end
C.encode = (ok_json and json.stringify) or enc
C.json_source = ok_json and "mame json module" or "builtin encoder"

local space, tr1, tr2, seq
function C.init()
  SM.open_log()
  SM.say("sam2core: json via %s", C.json_source)
  tr1, tr2 = MV.new_tracker(C.P1_NAME), MV.new_tracker(C.P2_NAME)
  seq = 0
end

local function fighter(name, p, tr, other)
  local w = MM.read(space, p.state)
  local d = tr:update(w)
  local y = MM.read(space, p.y)
  return {
    char = name, x = MM.read(space, p.x), y = y,
    health = MM.read(space, p.health), max_health = MM.health_max,
    rage = MM.read(space, p.rage), rage_max = MM.rage_max,
    action = d.phase, action_name = d.name, action_word = w, action_age = d.age,
    airborne = (w == MM.STATE_AIR) or (y < MM.ground_y),
    crouching = (w == MM.STATE_CROUCH),
  }
end

-- Build the state table for this frame (also returned for the check scripts).
function C.read_state(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  local p1 = fighter(C.P1_NAME, MM.p1, tr1)
  local p2 = fighter(C.P2_NAME, MM.p2, tr2)
  seq = seq + 1
  return {
    seq = seq, frame = frame, timer = MM.read_timer(space),
    match_live = frame >= SM.MATCH_LIVE_AT,
    p1 = p1, p2 = p2, gap = math.abs(p2.x - p1.x),
  }
end

function C.write_state(st)
  local f = io.open(C.TMP_PATH, "w")
  if not f then return false end
  f:write(C.encode(st)); f:close()
  return os.rename(C.TMP_PATH, C.STATE_PATH)
end

-- Per-frame entry. Returns the state table once the match is live, else nil.
function C.tick(frame)
  SM.tick(frame)
  if frame < SM.MATCH_LIVE_AT then return nil end
  local st = C.read_state(frame)
  C.write_state(st)
  return st
end

return C
