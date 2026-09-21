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

-- Minimal JSON decoder (objects, arrays, strings without escapes beyond \", numbers, true/false/null).
local function decode(s)
  local pos = 1
  local function ws() pos = s:find("%S", pos) or #s + 1 end
  local val
  local function str()
    local i = pos + 1; local out = {}
    while true do
      local c = s:sub(i, i)
      if c == "" then error("unterminated string") end
      if c == "\\" then out[#out + 1] = s:sub(i + 1, i + 1); i = i + 2
      elseif c == '"' then pos = i + 1; return table.concat(out)
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function val()
    ws(); local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws(); local k = str(); ws(); assert(s:sub(pos, pos) == ":", "expected :"); pos = pos + 1
        t[k] = val(); ws(); local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t elseif d ~= "," then error("expected , or }") end
      end
    elseif c == "[" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = val(); ws(); local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t elseif d ~= "," then error("expected , or ]") end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("bad json at " .. pos) end
      pos = pos + #num; return tonumber(num)
    end
  end
  return val()
end
C.decode = (ok_json and json.parse) or decode

-- ---- action.json: intents from the bridge (beads sam-e8s.1, sam-amj.1) ---
-- {"seq": n, "source": "jev", "p1": {"intent": "advance|retreat|attack|block|bait"}, "p2": {...}}
-- Applied when seq is newer than the last one consumed; expansion into
-- presses is done by lua/executor.lua, which logs every press to
-- /tmp/sam2/presses.log ("frame who buttons source intent").
local EX = dofile(here .. "executor.lua")
C.ACTION_PATH = "/tmp/sam2/action.json"
C.PRESS_LOG = "/tmp/sam2/presses.log"
C.INTENTS = { advance = true, retreat = true, attack = true, block = true, bait = true, none = true }  -- none: release everything (tests, pause)
C.SNAP_ON_ACTION = false
local last_action_seq = 0
local press_f
local function press_log(line)
  press_f = press_f or io.open(C.PRESS_LOG, "a")
  if press_f then press_f:write(line, "\n"); press_f:flush() end
end
C.ex = {
  p1 = EX.new{ who = "p1", port = ":edge:joy:JOY1", prefix = "P1 ", character = C.P1_NAME, log = press_log },
  p2 = EX.new{ who = "p2", port = ":edge:joy:JOY2", prefix = "P2 ", character = C.P2_NAME, log = press_log },
}
C.action_log = {}   -- last few applied actions, for the check scripts
function C.poll_action(st, frame)
  local f = io.open(C.ACTION_PATH, "r"); if not f then return nil end
  local txt = f:read("a"); f:close()
  local ok, a = pcall(C.decode, txt)
  if not ok or type(a) ~= "table" or type(a.seq) ~= "number" or a.seq <= last_action_seq then return nil end
  last_action_seq = a.seq
  local applied = {}
  for _, who in ipairs({ "p1", "p2" }) do
    local it = a[who] and a[who].intent
    if it and C.INTENTS[it] then applied[who] = it; C.ex[who]:set_intent(it, a.source or "-", frame) end
  end
  C.action_log[#C.action_log + 1] = { seq = a.seq, frame = frame, p1 = applied.p1, p2 = applied.p2, source = a.source }
  if #C.action_log > 50 then table.remove(C.action_log, 1) end
  SM.say("frame %d  action seq %d  p1=%s p2=%s src=%s", frame, a.seq, tostring(applied.p1), tostring(applied.p2), tostring(a.source))
  if C.SNAP_ON_ACTION then pcall(function() manager.machine.video:snapshot() end) end
  return a
end
local function step_exec(st)
  C.ex.p1:tick(st.frame, st.p1, st.p2)
  C.ex.p2:tick(st.frame, st.p2, st.p1)
end

local space, tr1, tr2, seq
function C.init()
  SM.open_log()
  SM.say("sam2core: json via %s", C.json_source)
  tr1, tr2 = MV.new_tracker(C.P1_NAME), MV.new_tracker(C.P2_NAME)
  seq = 0
end

local function fighter(name, p, tr)
  local r = MM.read_player(space, p)          -- follows the per-round object pointer
  local d = tr:update(r.state)
  return {
    char = name, x = r.x, y = r.y,
    health = r.health, max_health = MM.health_max,
    rage = r.rage, rage_max = MM.rage_max,
    action = d.phase, action_name = d.name, action_word = r.state, action_age = d.age,
    airborne = r.airborne, crouching = r.crouching, base = r.base,
  }
end

-- Build the state table for this frame (also returned for the check scripts).
function C.read_state(frame)
  space = space or manager.machine.devices[":maincpu"].spaces["program"]
  local p1 = fighter(C.P1_NAME, MM.p1, tr1)
  local p2 = fighter(C.P2_NAME, MM.p2, tr2)
  seq = seq + 1
  local last = C.action_log[#C.action_log]
  local presses = {}
  for _, who in ipairs({ "p1", "p2" }) do
    local e = C.ex[who]; presses[who] = { total = e.presses, jev = e.counts.jev, reflex = e.counts.reflex, test = e.counts.test, held = (function() local h = {} for n in pairs(e.held) do h[#h + 1] = n end table.sort(h) return h end)(), intent = e.intent }
  end
  return {
    presses = presses,
    seq = seq, frame = frame, timer = MM.read_timer(space),
    speed_percent = manager.machine.video.speed_percent * 100,
    match_live = frame >= SM.MATCH_LIVE_AT,
    p1 = p1, p2 = p2, gap = math.abs(p2.x - p1.x),
    action_seq = last_action_seq, last_action = last and { seq = last.seq, frame = last.frame, p1 = last.p1, p2 = last.p2 } or nil,
  }
end

function C.write_state(st)
  local f = io.open(C.TMP_PATH, "w")
  if not f then return false end
  f:write(C.encode(st)); f:close()
  return os.rename(C.TMP_PATH, C.STATE_PATH)
end

-- ---- frame writer (bead sam-7ij.3) -----------------------------------------
-- Every FRAME_EVERY-th frame: screen:pixels() -> frame.tmp -> rename to
-- frame.raw, then frame.meta ("w h bytes frame seq wallclock") the same way.
-- C.FRAMES = false turns it off (used by the speed comparison in sam-e8s.5).
C.FRAMES = true
C.FRAME_EVERY = 2
C.FRAME_PATH, C.FRAME_TMP = "/tmp/sam2/frame.raw", "/tmp/sam2/frame.tmp"
C.META_PATH, C.META_TMP = "/tmp/sam2/frame.meta", "/tmp/sam2/frame.meta.tmp"
local frame_seq = 0
local screen
function C.write_frame(frame)
  screen = screen or manager.machine.screens[":screen"]
  local px, w, h = screen:pixels()
  local f = io.open(C.FRAME_TMP, "wb"); if not f then return false end
  f:write(px); f:close()
  if not os.rename(C.FRAME_TMP, C.FRAME_PATH) then return false end
  frame_seq = frame_seq + 1
  local m = io.open(C.META_TMP, "w"); if not m then return false end
  m:write(string.format("%d %d %d %d %d %.3f\n", w, h, #px, frame, frame_seq, os.time() + (os.clock() % 1))); m:close()
  return os.rename(C.META_TMP, C.META_PATH)
end

-- ---- speed log ---------------------------------------------------------------
-- Once a second: "frame speed" where speed = video.speed_percent * 100. Despite
-- the name, speed_percent read 1.0 at full speed on MAME 0.289 (a ratio);
-- the raw value is logged in the third column.
C.SPEED_PATH = nil   -- set a path to enable
local speed_f
function C.log_speed(frame)
  if not C.SPEED_PATH then return end
  speed_f = speed_f or io.open(C.SPEED_PATH, "w")
  if speed_f then local r = manager.machine.video.speed_percent; speed_f:write(string.format("%d %.1f %.4f\n", frame, r * 100, r)); speed_f:flush() end
end

-- Per-frame entry. Returns the state table once the match is live, else nil.
function C.tick(frame)
  SM.tick(frame)
  if frame < SM.MATCH_LIVE_AT then return nil end
  local st = C.read_state(frame)
  C.write_state(st)
  step_exec(st)
  C.poll_action(st, frame)
  if C.FRAMES and frame % C.FRAME_EVERY == 0 then C.write_frame(frame) end
  if frame % 60 == 0 then C.log_speed(frame) end
  return st
end

return C
