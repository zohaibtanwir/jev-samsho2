-- reflex_check.lua  (bead sam-amj.3)
-- No Jev, no intents: one fighter is scripted to walk in and heavy-slash
-- four times; the other has no intent and only the reflex layer. Then swap.
-- Screenshot 10 frames after each attack press; health before/after each.
--   /run-lua lua/reflex_check.lua 3     log: /tmp/sam2/start_match.txt (say lines), presses.log
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local C = dofile(here .. "sam2core.lua")
C.init(); local say = C.SM.say
local J = { p1 = ":edge:joy:JOY1", p2 = ":edge:joy:JOY2" }
local PFX = { p1 = "P1 ", p2 = "P2 " }
local function fld(who, n) return manager.machine.ioport.ports[J[who]].fields[PFX[who] .. n] end
local function snap() pcall(function() manager.machine.video:snapshot() end) end
local script = { { atk = "p2", def = "p1", reach = 100, n = 4 }, { atk = "p1", def = "p2", reach = 150, n = 4 } }
local si, hits, phase, t0, hp_before = 1, 0, "approach", 0, 0
local frame = 0
SUB = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  local st = C.tick(frame)
  if not st or frame < C.SM.MATCH_LIVE_AT + 120 then return end
  local sc = script[si]; if not sc then return end
  local atk, def = sc.atk, sc.def
  local toward = (st[def].x >= st[atk].x) and "Right" or "Left"
  local away = (toward == "Right") and "Left" or "Right"
  if phase == "approach" then
    if st.gap > sc.reach then fld(atk, toward):set_value(1); fld(atk, away):clear_value()
    else fld(atk, toward):clear_value()
      if st[atk].action == "idle" or st[atk].action == "walk_fwd" then
        hp_before = st[def].health
        fld(atk, "A"):set_value(1); fld(atk, "B"):set_value(1); phase = "swing"; t0 = frame
        say("frame %d  %s attacks %s (A+B) at gap %d, defender hp %d, defender intent=%s", frame, atk, def, st.gap, hp_before, tostring(C.ex[def].intent))
      end
    end
  elseif phase == "swing" then
    if frame == t0 + 4 then fld(atk, "A"):clear_value(); fld(atk, "B"):clear_value() end
    if frame == t0 + 12 then snap() end
    if frame == t0 + 110 then
      hits = hits + 1
      say("frame %d  result: defender %s hp %d -> %d (%s), defender action now %s, reflex events %s=%d", frame, def, hp_before, st[def].health,
        st[def].health == hp_before and "NO DAMAGE" or "damaged", st[def].action, def, C.reflex_events[def])
      -- back off so the next approach is from range
      fld(atk, away):set_value(1); phase = "backoff"; t0 = frame
    end
  elseif phase == "backoff" then
    if frame == t0 + 70 then fld(atk, away):clear_value()
      if hits >= sc.n then si = si + 1; hits = 0; if not script[si] then say("done") end end
      phase = "approach"
    end
  end
end)
