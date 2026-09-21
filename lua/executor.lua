-- executor.lua  (bead sam-amj.1)
-- Turns an intent (advance retreat attack block bait) into button presses
-- over the following frames, per fighter, facing-aware, using the observed
-- normals from lua/moves_<char>.lua. Lives in Lua because it needs the
-- frame-by-frame state (decision 21 Sep 2026: the bridge sends intent only).
--
--   local EX = dofile(dir .. "executor.lua")
--   local ex = EX.new{ who = "p1", port = ":edge:joy:JOY1", prefix = "P1 ", character = "Earthquake", log = fn }
--   ex:set_intent("attack", source, frame)      -- from action.json
--   ex:tick(frame, me, them)                    -- every frame, me/them = fighter tables from sam2core
--   ex:reflex(frame, names, hold_frames)        -- reflex layer override (sam-amj.3)
--
-- Rules: an intent stays in force until replaced. Walking intents hold the
-- direction every frame (recomputed from the X positions, so crossing sides
-- is handled). attack waits until the fighter can act (movement kind, not
-- landing / transition, no attack in progress), then taps the heavy normal
-- (A+B for both characters). bait taps A, then once the fighter can act
-- again walks away for BAIT_BACK frames. block holds away (and Down when the
-- opponent is airborne is NOT done: v1 keeps standing guard).
-- Every set_value is logged: "frame who buttons source intent".
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local MOVES = { Earthquake = dofile(here .. "moves_earthquake.lua"), Nakoruru = dofile(here .. "moves_nakoruru.lua") }

local EX = {}
EX.__index = EX
EX.BAIT_BACK = 20
EX.TAP = 4
EX.ATTACK_WAIT_MAX = 90     -- give up an attack intent that stays unactionable this long

function EX.new(o)
  local self = setmetatable(o, EX)
  self.held = {}            -- name -> true
  self.intent, self.source, self.intent_frame = nil, nil, 0
  self.plan = nil           -- pending sequence: { {names=, frames=, when="now"|"can_act"}, ... }
  self.step_left = 0
  self.moves = MOVES[self.character]
  self.counts = { jev = 0, reflex = 0, test = 0, other = 0 }
  self.presses = 0
  self.reflex_left = 0
  return self
end

local function field(self, name) return manager.machine.ioport.ports[self.port].fields[self.prefix .. name] end

function EX:_set(names, source, frame)
  local want = {}
  for _, n in ipairs(names) do want[n] = true end
  local changed = false
  for n in pairs(self.held) do if not want[n] then field(self, n):clear_value(); self.held[n] = nil; changed = true end end
  for n in pairs(want) do if not self.held[n] then field(self, n):set_value(1); self.held[n] = true; changed = true end end
  if changed and next(want) then
    self.presses = self.presses + 1
    local k = (source == "jev" or source == "reflex" or source == "test") and source or "other"
    self.counts[k] = self.counts[k] + 1
    if self.log then self.log(string.format("%d %s %s %s %s %d", frame, self.who, table.concat(names, "+"), source or "-", self.intent or "-", self.action_seq or 0)) end
  end
end

function EX:release_all() self:_set({}, nil, 0) end

local function can_act(me)
  local ph = me.action
  return ph == "idle" or ph == "walk_fwd" or ph == "walk_back" or ph == "crouch"
end

function EX:set_intent(intent, source, frame, action_seq)
  self.intent, self.source, self.intent_frame, self.action_seq = intent, source or "-", frame, action_seq or 0
  local heavy = self.moves and self.moves.heavy and self.moves.heavy.fields or { "A", "B" }
  local hb = {}
  for i, f in ipairs(heavy) do hb[i] = f:gsub("^P%d ", "") end
  if intent == "none" then self.plan = nil; self.intent = nil
  elseif intent == "attack" then
    self.plan = { { names = hb, frames = EX.TAP, when = "can_act" }, { names = {}, frames = 1 } }
  elseif intent == "bait" then
    self.plan = { { names = { "A" }, frames = EX.TAP, when = "can_act" }, { names = { "AWAY" }, frames = EX.BAIT_BACK, when = "can_act" }, { names = {}, frames = 1 } }
  else
    self.plan = nil       -- walking intents are continuous, handled in tick
  end
  self.step_left = 0
end

-- Reflex override: hold these buttons for `frames`, taking precedence over the intent.
function EX:reflex(frame, names, frames)
  self.reflex_names, self.reflex_left = names, frames
end

function EX:tick(frame, me, them)
  local toward = (them.x >= me.x) and "Right" or "Left"
  local away = (toward == "Right") and "Left" or "Right"
  local function resolve(names)
    local out = {}
    for i, n in ipairs(names) do out[i] = (n == "TOWARD") and toward or (n == "AWAY") and away or n end
    return out
  end
  -- 1. reflex layer wins
  if self.reflex_left > 0 then
    self.reflex_left = self.reflex_left - 1
    self:_set(resolve(self.reflex_names), "reflex", frame)
    return
  end
  -- 2. a plan in progress (attack / bait)
  if self.plan then
    if self.step_left > 0 then
      self.step_left = self.step_left - 1
      if self.step_left == 0 then table.remove(self.plan, 1); self:_set({}, nil, frame) end
      if self.plan and #self.plan == 0 then self.plan = nil end
      return
    end
    local step = self.plan[1]
    if not step then self.plan = nil; return end
    if step.when == "can_act" and not can_act(me) then
      if frame - self.intent_frame > EX.ATTACK_WAIT_MAX then self.plan = nil end   -- stale, drop it
      self:_set({}, nil, frame)
      return
    end
    self.step_left = step.frames
    self:_set(resolve(step.names), self.source, frame)
    if #step.names == 0 then table.remove(self.plan, 1); if #self.plan == 0 then self.plan = nil end; self.step_left = 0 end
    return
  end
  -- 3. continuous intents
  if self.intent == "advance" then self:_set({ toward }, self.source, frame)
  elseif self.intent == "retreat" or self.intent == "block" then self:_set({ away }, self.source, frame)
  else self:_set({}, nil, frame) end
end

return EX
