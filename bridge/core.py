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
                 log_path: str = LOG_PATH, poll_s: float = 0.002):
        self.dm, self.source = decision_maker, source
        self.state_path, self.poll_s = state_path, poll_s
        self.writer = writer or ActionWriter()
        self.history = ActionHistory()
        self.ticker = Ticker()
        self.stats = LoopStats()
        self.log = open(log_path, "a")
        self.decisions = 0

    def _log(self, msg: str) -> None:
        self.log.write(f"{time.time():.3f} {msg}\n"); self.log.flush()

    def step(self, state: dict[str, Any]) -> list[dict[str, Any]]:
        """One pass with a fresh state: update history, fire due fighters."""
        self.history.update(state)
        out = []
        for who in self.ticker.due():
            other = "p2" if who == "p1" else "p1"
            intent = self.dm.decide(state, who, self.history.last(other))
            doc = self.writer.write({who: intent}, self.source)
            self.decisions += 1
            self._log(f"decision {who} state_seq={state['seq']} frame={state['frame']} intent={intent} action_seq={doc['seq']} "
                      f"opp_last3={','.join(self.history.last(other)) or '-'} gap={state['gap']} hp={state[who]['health']}")
            out.append(doc)
        return out

    stop_requested = False

    def run(self, seconds: float) -> None:
        """Run for `seconds`; 0 or less means until stop_requested (SIGTERM)."""
        self._log(f"bridge start source={self.source} tick={TICK_S:.3f}s seconds={seconds}")
        t_end = time.monotonic() + seconds if seconds > 0 else float("inf")
        last_seq, last_report = None, time.monotonic()
        while time.monotonic() < t_end and not self.stop_requested:
            t0 = time.perf_counter()
            st = read_state(self.state_path)
            if st is not None and st.get("seq") != last_seq and st.get("match_live"):
                last_seq = st["seq"]
                self.step(st)
            self.stats.add((time.perf_counter() - t0) * 1000.0)
            if time.monotonic() - last_report >= 5.0:
                self._log(self.stats.summary() + f" decisions={self.decisions}")
                last_report = time.monotonic()
            time.sleep(self.poll_s)
        self._log("bridge stop " + self.stats.summary() + f" decisions={self.decisions}")
        self.log.close()


def main(argv: list[str] | None = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="samsho2 bridge (dummy decision-maker)")
    ap.add_argument("--seconds", type=float, default=0.0, help="run time; 0 = until SIGTERM/SIGINT")
    ap.add_argument("--wait", type=float, default=90.0, help="max seconds to wait for a live match")
    a = ap.parse_args(argv)
    t0 = time.monotonic()
    while True:
        st = read_state()
        if st and st.get("match_live"):
            break
        if time.monotonic() - t0 > a.wait:
            print("no live match"); return 1
        time.sleep(0.1)
    import signal
    bridge = Bridge(DummyDecisionMaker(), source="dummy")
    def _stop(signum, frame):
        bridge.stop_requested = True
    signal.signal(signal.SIGTERM, _stop); signal.signal(signal.SIGINT, _stop)
    bridge.run(a.seconds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
