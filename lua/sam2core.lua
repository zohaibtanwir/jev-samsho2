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

-- ---- action.json: intents from the bridge (bead sam-e8s.1) -----------------
-- {"seq": n, "p1": {"intent": "advance|retreat|attack|block|bait"}, "p2": {...}}
-- Applied when seq is newer than the last one consumed. Minimal expansion
-- (the proper executor is Epic 7): each intent holds inputs for
-- ACTION_FRAMES frames; direction is chosen from the two X positions.
C.ACTION_PATH = "/tmp/sam2/action.json"
C.ACTION_FRAMES = 20
C.INTENTS = { advance = true, retreat = true, attack = true, block = true, bait = true }
C.SNAP_ON_ACTION = false
local last_action_seq = 0
local exec = { p1 = { held = {}, left = 0, queue = {} }, p2 = { held = {}, left = 0, queue = {} } }
local PORT = { p1 = ":edge:joy:JOY1", p2 = ":edge:joy:JOY2" }
local PFX = { p1 = "P1 ", p2 = "P2 " }
local function fld(who, name) return manager.machine.ioport.ports[PORT[who]].fields[PFX[who] .. name] end
local function release_all(who) for n in pairs(exec[who].held) do fld(who, n):clear_value() end; exec[who].held = {} end
local function hold(who, names, frames)
  release_all(who)
  for _, n in ipairs(names) do fld(who, n):set_value(1); exec[who].held[n] = true end
  exec[who].left = frames
end
C.action_log = {}   -- last few applied actions, for the check scripts
local function apply_intent(who, intent, st)
  local me, other = st[who], st[who == "p1" and "p2" or "p1"]
  local toward = (other.x >= me.x) and "Right" or "Left"
  local away = (toward == "Right") and "Left" or "Right"
  local e = exec[who]; e.queue = {}
  if intent == "advance" then hold(who, { toward }, C.ACTION_FRAMES)
  elseif intent == "retreat" then hold(who, { away }, C.ACTION_FRAMES)
  elseif intent == "block" then hold(who, { away }, C.ACTION_FRAMES)
  elseif intent == "attack" then hold(who, { "A", "B" }, 4)
  elseif intent == "bait" then hold(who, { "A" }, 4); e.queue = { { names = { away }, frames = C.ACTION_FRAMES - 4 } }
  else return false end
  return true
end
function C.poll_action(st, frame)
  local f = io.open(C.ACTION_PATH, "r"); if not f then return nil end
  local txt = f:read("a"); f:close()
  local ok, a = pcall(C.decode, txt)
  if not ok or type(a) ~= "table" or type(a.seq) ~= "number" or a.seq <= last_action_seq then return nil end
  last_action_seq = a.seq
  local applied = {}
  for _, who in ipairs({ "p1", "p2" }) do
    local it = a[who] and a[who].intent
    if it and C.INTENTS[it] then applied[who] = it; apply_intent(who, it, st) end
  end
  C.action_log[#C.action_log + 1] = { seq = a.seq, frame = frame, p1 = applied.p1, p2 = applied.p2, source = a.source }
  if #C.action_log > 50 then table.remove(C.action_log, 1) end
  SM.say("frame %d  action seq %d  p1=%s p2=%s", frame, a.seq, tostring(applied.p1), tostring(applied.p2))
  if C.SNAP_ON_ACTION then pcall(function() manager.machine.video:snapshot() end) end
  return a
end
local function step_exec(who)
  local e = exec[who]
  if e.left > 0 then
    e.left = e.left - 1
    if e.left == 0 then
      release_all(who)
      local nxt = table.remove(e.queue, 1)
      if nxt then hold(who, nxt.names, nxt.frames) end
    end
  end
end

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
  local last = C.action_log[#C.action_log]
  return {
    seq = seq, frame = frame, timer = MM.read_timer(space),
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

-- Per-frame entry. Returns the state table once the match is live, else nil.
function C.tick(frame)
  SM.tick(frame)
  if frame < SM.MATCH_LIVE_AT then return nil end
  local st = C.read_state(frame)
  C.write_state(st)
  step_exec("p1"); step_exec("p2")
  C.poll_action(st, frame)
  return st
end

return C
