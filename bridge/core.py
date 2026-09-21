"""Bridge core: state.json in, intents out (bead sam-e8s.2).

Pure parts (testable without MAME): ActionHistory, ActionWriter, Ticker,
DummyDecisionMaker. `Bridge.run()` wires them to the files in /tmp/sam2.
The bridge sends intent only; every button press is chosen in Lua.
Stdlib only.
"""
from __future__ import annotations

import json
import os
import statistics
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable, Protocol

SAM2 = "/tmp/sam2"
STATE_PATH = os.path.join(SAM2, "state.json")
CONTROL_PATH = os.path.join(SAM2, "control.json")
CONTROL_TMP = os.path.join(SAM2, "control.tmp")
CMD_PATH = os.path.join(SAM2, "cmd.json")        # local command input (tests / CLI): {"seq": n, "cmd": "pause"}
COMMANDS = ("pause", "resume", "reset", "stop")
ACTION_PATH = os.path.join(SAM2, "action.json")
ACTION_TMP = os.path.join(SAM2, "action.tmp")
LOG_PATH = os.path.join(SAM2, "bridge.log")

INTENTS = ("advance", "retreat", "attack", "block", "bait")
FIGHTERS = ("p1", "p2")
TICK_S = 1.0 / 3.0            # PRD section 8: 3 calls per second per fighter
IGNORED_PHASES = {"transition"}


# ------------------------------------------------------------ state input

def read_state(path: str = STATE_PATH) -> dict[str, Any] | None:
    """Return the parsed state.json or None if absent / mid-rename."""
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


class ActionHistory:
    """Distinct consecutive action phases per fighter, newest last.

    'opponent's last three actions' (PRD section 9) = history[other][-3:].
    """

    def __init__(self, keep: int = 8):
        self._h: dict[str, deque[str]] = {w: deque(maxlen=keep) for w in FIGHTERS}

    def update(self, state: dict[str, Any]) -> None:
        for w in FIGHTERS:
            a = state[w]["action"]
            if a in IGNORED_PHASES:
                continue
            if not self._h[w] or self._h[w][-1] != a:
                self._h[w].append(a)

    def last(self, who: str, n: int = 3) -> list[str]:
        return list(self._h[who])[-n:]


# ------------------------------------------------------------- decisions

class DecisionMaker(Protocol):
    def decide(self, state: dict[str, Any], who: str, opponent_history: list[str]) -> str: ...


class DummyDecisionMaker:
    """Cycles through the intents on a fixed schedule, independently per fighter."""

    CYCLE = ("advance", "attack", "retreat", "block", "bait")

    def __init__(self):
        self._i = {w: 0 for w in FIGHTERS}

    def decide(self, state: dict[str, Any], who: str, opponent_history: list[str]) -> str:
        intent = self.CYCLE[self._i[who] % len(self.CYCLE)]
        self._i[who] += 1
        return intent


# ------------------------------------------------------------ action out

class ActionWriter:
    """Writes intent-only action files atomically with an increasing seq."""

    def __init__(self, path: str = ACTION_PATH, tmp: str = ACTION_TMP):
        self.path, self.tmp, self.seq = path, tmp, 0

    def write(self, intents: dict[str, str], source: str) -> dict[str, Any]:
        for w, it in intents.items():
            if w not in FIGHTERS or it not in INTENTS:
                raise ValueError(f"bad intent {w}={it!r}")
        self.seq += 1
        doc: dict[str, Any] = {"seq": self.seq, "source": source}
        for w, it in intents.items():
            doc[w] = {"intent": it}
        with open(self.tmp, "w") as f:
            json.dump(doc, f)
        os.replace(self.tmp, self.path)
        return doc


# ------------------------------------------------------------------ tick

class Ticker:
    """Per-fighter fixed-rate ticks; p2 runs half a period after p1."""

    def __init__(self, period: float = TICK_S, now: Callable[[], float] = time.monotonic):
        self.period, self.now = period, now
        t = now()
        self.next = {"p1": t, "p2": t + period / 2}

    def due(self) -> list[str]:
        t = self.now()
        out = [w for w in FIGHTERS if t >= self.next[w]]
        for w in out:
            # keep phase: schedule from the previous deadline, not from now
            self.next[w] += self.period
            if self.next[w] < t - self.period:      # fell far behind: resync
                self.next[w] = t + self.period
        return out


# --------------------------------------------------------------- bridge

@dataclass
class LoopStats:
    samples: deque = field(default_factory=lambda: deque(maxlen=2000))

    def add(self, ms: float) -> None:
        self.samples.append(ms)

    def summary(self) -> str:
        if not self.samples:
            return "no samples"
        s = sorted(self.samples)
        return f"loop ms p50={statistics.median(s):.2f} p99={s[int(0.99 * (len(s) - 1))]:.2f} max={s[-1]:.2f} n={len(s)}"


class Bridge:
    def __init__(self, decision_maker: DecisionMaker, source: str = "dummy",
                 state_path: str = STATE_PATH, writer: ActionWriter | None = None,
                 log_path: str = LOG_PATH, poll_s: float = 0.002, relay=None):
        self.dm, self.source = decision_maker, source
        self.relay = relay
        self.gate = "-"
        self.tele = None          # bridge.telemetry.Telemetry, set by main() for the Jev path
        self.paused = False
        self.control_seq = 0
        self._cmd_seq_seen = 0
        self.last_decision: dict[str, dict[str, Any]] = {}
        self.state_path, self.poll_s = state_path, poll_s
        self.writer = writer or ActionWriter()
        self.history = ActionHistory()
        self.ticker = Ticker()
        self.stats = LoopStats()
        self.log = open(log_path, "a")
        self.decisions = 0

    def _log(self, msg: str) -> None:
        self.log.write(f"{time.time():.3f} {msg}\n"); self.log.flush()

    def _round_live(self, state: dict[str, Any]) -> bool:
        # No round-phase field yet: treat a KO'd fighter as 'not live' so we do
        # not burn calls between rounds (findings in sam-e8s.2 / sam-e8s.4).
        if not state.get("match_live"):
            self.gate = "match_live=false"; return False
        if state["p1"]["health"] <= 0 or state["p2"]["health"] <= 0:
            self.gate = f"health p1={state['p1']['health']} p2={state['p2']['health']}"; return False
        self.gate = "live"; return True

    def step(self, state: dict[str, Any]) -> list[dict[str, Any]]:
        """One pass with a fresh state: update history, fire due fighters."""
        self.history.update(state)
        out = []
        if hasattr(self.dm, "drain"):
            return self._step_async(state)
        for who in self.ticker.due():
            other = "p2" if who == "p1" else "p1"
            intent = self.dm.decide(state, who, self.history.last(other))
            doc = self.writer.write({who: intent}, self.source)
            self.decisions += 1
            self.last_decision[who] = {"intent": intent, "state_seq": state["seq"], "frame": state["frame"],
                                       "action_seq": doc["seq"], "wall": time.time(), "opp_last3": self.history.last(other)}
            self._log(f"decision {who} state_seq={state['seq']} frame={state['frame']} intent={intent} action_seq={doc['seq']} "
                      f"opp_last3={','.join(self.history.last(other)) or '-'} gap={state['gap']} hp={state[who]['health']}")
            out.append(doc)
        return out

    stop_requested = False

    def _step_async(self, state: dict[str, Any]) -> list[dict[str, Any]]:
        """Jev path: issue due calls without waiting, apply finished ones (newest wins)."""
        out = []
        live = self._round_live(state) and not self.paused
        due = self.ticker.due()          # keep the schedule moving even when gated
        if state["frame"] % 60 == 0:
            self._log(f"state frame={state['frame']} timer={state['timer']} hp={state['p1']['health']}/{state['p2']['health']} "
                      f"gap={state['gap']} p1={state['p1']['action']} p2={state['p2']['action']} gate={self.gate} in_flight={self.dm.in_flight()}")
        if live:
            for who in due:
                other = "p2" if who == "p1" else "p1"
                self.dm.tick(state, who, self.history.last(other))
                if self.tele: self.tele.record_call(who)
                self._log(f"call {who} state_seq={state['seq']} frame={state['frame']} hp={state[who]['health']} in_flight={self.dm.in_flight()}")
        for r, apply in self.dm.drain():
            a = self.dm.applier
            if r.decision is None:
                if self.tele: self.tele.record_error(r.who)
                self._log(f"error {r.who} state_seq={r.state_seq} rtt_ms={r.rtt_ms:.0f} {r.error}")
                continue
            d = r.decision
            discarded = (r.epoch != a.epoch)
            if self.tele:
                self.tele.record_reply(r.who, d.rtt_ms, d.input_tokens, d.output_tokens, apply, intent=d.intent, probabilities=d.probabilities,
                                       opponent_recovering=d.opponent_recovering, confidence=d.confidence, state_seq=r.state_seq, discarded=discarded)
            mark = "applied" if apply else ("discarded" if discarded else "stale")
            if apply:
                if self._round_live(state):
                    doc = self.writer.write({r.who: d.intent}, self.source)
                    action_seq = doc["seq"]
                    out.append(doc)
                else:
                    action_seq = None; mark = "applied-noround"
                self.decisions += 1
                self.last_decision[r.who] = {"intent": d.intent, "state_seq": r.state_seq, "frame": state["frame"], "action_seq": action_seq,
                                             "wall": time.time(), "rtt_ms": d.rtt_ms, "confidence": d.confidence,
                                             "probabilities": d.probabilities, "opponent_recovering": d.opponent_recovering,
                                             "opp_last3": self.history.last("p2" if r.who == "p1" else "p1")}
            self._log(f"reply {r.who} seq_sent={r.state_seq} epoch={r.epoch} last_applied={a.last_applied[r.who]} rtt_ms={d.rtt_ms:.0f} intent={d.intent} "
                      f"conf={d.confidence:.2f} recovering={d.opponent_recovering:.2f} {mark} in={d.input_tokens} out={d.output_tokens} "
                      f"totals calls={self.dm.calls} applied={a.applied} stale={a.stale} discarded={a.discarded} errors={a.errors}")
        return out

    def telemetry(self, state: dict[str, Any]) -> dict[str, Any]:
        """What the UI gets with every new state (grows in sam-l4r.3)."""
        jv = None
        if hasattr(self.dm, "applier"):
            a = self.dm.applier; r = sorted(self.dm.rtts)
            jv = {"calls": self.dm.calls, "applied": a.applied, "stale": a.stale, "errors": a.errors, "in_flight": self.dm.in_flight(),
                  "input_tokens": a.input_tokens, "output_tokens": a.output_tokens,
                  "rtt_ms_last": r and self.dm.rtts[-1], "rtt_ms_p50": r[len(r) // 2] if r else None}
        if self.paused: phase = "paused"
        elif self._round_live(state): phase = "running"
        elif state.get("match_live"): phase = "between_rounds"
        else: phase = "booting"
        return {"type": "telemetry", "wall": time.time(), "state": state, "source": self.source, "paused": self.paused, "control_seq": self.control_seq, "phase": phase,
                "panel": self.tele.snapshot(state) if self.tele else None,
                "decisions": self.decisions, "last_decision": self.last_decision, "jev": jv,
                "loop": self.stats.summary(), "relay": self.relay.stats() if self.relay else None}

    # ---- control channel (bead sam-l4r.4)
    def command(self, cmd: str) -> dict[str, Any]:
        """pause / resume / reset / stop. Bumps the Jev epoch so in-flight
        replies are discarded on return (still counted), forwards to Lua via
        control.json, and adjusts bridge state. Returns what was done."""
        if cmd not in COMMANDS:
            return {"ok": False, "error": f"unknown command {cmd!r}"}
        if cmd in ("pause", "reset", "stop") and hasattr(self.dm, "applier"):
            self.dm.applier.bump_epoch()
        if cmd == "pause":
            self.paused = True
        elif cmd == "resume":
            self.paused = False
        elif cmd == "reset":
            self.paused = False
            self.history = ActionHistory()
            if self.tele:
                self.tele.reset()
            self.last_decision = {}
            self.decisions = 0
        elif cmd == "stop":
            self.stop_requested = True
        self.control_seq += 1
        with open(CONTROL_TMP, "w") as f:
            json.dump({"seq": self.control_seq, "cmd": cmd}, f)
        os.replace(CONTROL_TMP, CONTROL_PATH)
        self._log(f"control {cmd} control_seq={self.control_seq} epoch={getattr(getattr(self.dm, 'applier', None), 'epoch', None)} in_flight={self.dm.in_flight() if hasattr(self.dm, 'in_flight') else 0}")
        return {"ok": True, "cmd": cmd, "control_seq": self.control_seq}

    def _poll_cmd_file(self) -> None:
        try:
            with open(CMD_PATH) as f:
                c = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return
        if isinstance(c, dict) and isinstance(c.get("seq"), int) and c["seq"] > self._cmd_seq_seen:
            self._cmd_seq_seen = c["seq"]
            self.command(c.get("cmd", ""))

    def run(self, seconds: float) -> None:
        """Run for `seconds`; 0 or less means until stop_requested (SIGTERM)."""
        self._log(f"bridge start source={self.source} tick={TICK_S:.3f}s seconds={seconds}")
        t_end = time.monotonic() + seconds if seconds > 0 else float("inf")
        last_seq, last_report = None, time.monotonic()
        while time.monotonic() < t_end and not self.stop_requested:
            t0 = time.perf_counter()
            self._poll_cmd_file()
            if self.relay:
                for cmd in self.relay.drain_commands():
                    self.command(cmd)
            st = read_state(self.state_path)
            if st is not None and st.get("seq") != last_seq and st.get("match_live"):
                last_seq = st["seq"]
                try:
                    self.step(st)
                except Exception as e:      # never let one bad state kill the loop; log it
                    import traceback
                    self._log("EXCEPTION in step: " + traceback.format_exc().replace("\n", " | "))
                if self.relay:
                    self.relay.publish(self.telemetry(st))
            self.stats.add((time.perf_counter() - t0) * 1000.0)
            if time.monotonic() - last_report >= 5.0:
                self._log(self.stats.summary() + f" decisions={self.decisions}")
                last_report = time.monotonic()
            time.sleep(self.poll_s)
        self._log("bridge stop " + self.stats.summary() + f" decisions={self.decisions}")
        self.log.close()


MAME_DIR = os.path.expanduser("~/mame")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAME_LOG = os.path.join(SAM2, "mame.log")


def launch_mame(windowed: bool = False):
    """Start MAME from ~/mame (relative rompath) with lua/sam2.lua. Returns the Popen."""
    import subprocess
    os.makedirs(SAM2, exist_ok=True)
    video = ["-window", "-nomaximize"] if windowed else ["-video", "none"]
    cmd = ["mame", "samsho2", *video, "-sound", "none", "-skip_gameinfo",
           "-autoboot_script", os.path.join(REPO, "lua", "sam2.lua"), "-autoboot_delay", "3"]
    log = open(MAME_LOG, "w")
    p = subprocess.Popen(cmd, cwd=MAME_DIR, stdout=log, stderr=subprocess.STDOUT)
    with open(os.path.join(SAM2, "mame.pid"), "w") as f:
        f.write(str(p.pid))
    return p


def stop_mame(p, timeout: float = 6.0) -> str | None:
    """After the Lua side has been told to exit, wait; then kill this PID only."""
    if p is None:
        return None
    t0 = time.monotonic()
    while p.poll() is None and time.monotonic() - t0 < timeout:
        time.sleep(0.2)
    if p.poll() is None:
        p.kill(); p.wait(3)
        return "killed"
    return "exited"


def main(argv: list[str] | None = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="samsho2 bridge (dummy decision-maker)")
    ap.add_argument("--seconds", type=float, default=0.0, help="run time; 0 = until SIGTERM/SIGINT")
    ap.add_argument("--wait", type=float, default=90.0, help="max seconds to wait for a live match")
    ap.add_argument("--relay", action="store_true", help="serve frames + telemetry on ws://127.0.0.1:8765")
    ap.add_argument("--jev", action="store_true", help="decide with Jev instead of the dummy (needs TYPESAFE_API_KEY)")
    ap.add_argument("--launch-mame", action="store_true", help="launch MAME (from ~/mame, lua/sam2.lua) and own its lifetime; used by the Tauri app")
    ap.add_argument("--mame-window", action="store_true", help="with --launch-mame: windowed instead of -video none")
    a = ap.parse_args(argv)
    mame = None
    if a.launch_mame:
        mame = launch_mame(windowed=a.mame_window)
    t0 = time.monotonic()
    while True:
        st = read_state()
        if st and st.get("match_live"):
            break
        if time.monotonic() - t0 > a.wait or (mame is not None and mame.poll() is not None):
            why = f"timeout after {a.wait}s" if time.monotonic() - t0 > a.wait else f"mame exited with {mame.returncode}"
            print(f"no live match: {why}"); stop_mame(mame); return 1
        time.sleep(0.1)
    import signal
    relay = None
    if a.relay:
        from bridge.relay import Relay
        relay = Relay(); relay.start()
    from bridge.telemetry import Telemetry
    baseline = None
    if a.jev:
        from bridge.jevdm import JevDecisionMaker
        from bridge import jev as jevmod
        rtts = jevmod.measure_rtt(rounds=5)
        baseline = statistics.median(rtts) if rtts else None
        dm, source = JevDecisionMaker(), "jev"
    else:
        dm, source = DummyDecisionMaker(), "dummy"
    bridge = Bridge(dm, source=source, relay=relay)
    bridge.tele = Telemetry({"p1": "Earthquake", "p2": "Nakoruru"}, baseline)
    bridge._log(f"network baseline (median TCP connect) = {baseline} ms")
    def _stop(signum, frame):
        bridge.stop_requested = True
    signal.signal(signal.SIGTERM, _stop); signal.signal(signal.SIGINT, _stop)
    try:
        bridge.run(a.seconds)
    finally:
        stop_mame(mame)
    if hasattr(dm, "close"):
        dm.close()
    if relay:
        relay.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
