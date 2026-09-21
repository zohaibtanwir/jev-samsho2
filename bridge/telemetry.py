"""Telemetry accounting for the panel (bead sam-l4r.3, PRD section 7).

Pure bookkeeping, fed by the bridge: record_call() when a call is issued,
record_reply() for every reply (applied or stale), record_error(). snapshot()
returns the JSON-ready object the UI consumes.

Cost rule (confirmed by Typesafe AI, 21 Sep 2026): input tokens at
0.042 USD per million, output tokens at zero.
Decision time is ESTIMATED as round trip minus the network baseline (median
TCP connect time measured at bridge start); the API returns no timing field.
"""
from __future__ import annotations

import statistics
import time
from typing import Any

USD_PER_INPUT_TOKEN = 0.042 / 1_000_000
USD_PER_OUTPUT_TOKEN = 0.0
FIGHTERS = ("p1", "p2")


def _p50(xs: list[float]) -> float | None:
    return statistics.median(xs) if xs else None


class FighterStats:
    def __init__(self, char: str):
        self.char = char
        self.calls = self.applied = self.stale = self.errors = 0
        self.input_tokens = self.output_tokens = 0
        self.rtts: list[float] = []
        self.last_rtt: float | None = None
        self.decision: dict[str, Any] | None = None     # last applied decision
        self.decided_at: float | None = None

    def cost_usd(self) -> float:
        return self.input_tokens * USD_PER_INPUT_TOKEN + self.output_tokens * USD_PER_OUTPUT_TOKEN


class Telemetry:
    def __init__(self, chars: dict[str, str], network_baseline_ms: float | None):
        self.f = {w: FighterStats(chars[w]) for w in FIGHTERS}
        self.network_baseline_ms = network_baseline_ms
        self.started = time.time()

    # ---- feeds
    def record_call(self, who: str) -> None:
        self.f[who].calls += 1

    def record_reply(self, who: str, rtt_ms: float, input_tokens: int, output_tokens: int, applied: bool,
                     intent: str | None = None, probabilities: dict[str, float] | None = None,
                     opponent_recovering: float | None = None, confidence: float | None = None,
                     state_seq: int | None = None, now: float | None = None) -> None:
        s = self.f[who]
        s.rtts.append(rtt_ms); s.last_rtt = rtt_ms
        if len(s.rtts) > 3000:
            del s.rtts[:1000]
        s.input_tokens += input_tokens; s.output_tokens += output_tokens
        if applied:
            s.applied += 1
            s.decided_at = now or time.time()
            s.decision = {"action": intent, "probabilities": probabilities or {}, "opponent_recovering": opponent_recovering,
                          "confidence": confidence, "state_seq": state_seq, "rtt_ms": rtt_ms}
        else:
            s.stale += 1

    def record_error(self, who: str) -> None:
        self.f[who].errors += 1

    def reset(self) -> None:
        """Reset (PRD section 6): clear running figures, keep the network baseline."""
        self.__init__({w: self.f[w].char for w in FIGHTERS}, self.network_baseline_ms)

    # ---- output
    def _est(self, rtt: float | None) -> float | None:
        if rtt is None or self.network_baseline_ms is None:
            return None
        return max(0.0, rtt - self.network_baseline_ms)

    def fighter(self, who: str, state_fighter: dict[str, Any], presses: dict[str, Any] | None, now: float) -> dict[str, Any]:
        s = self.f[who]
        p50 = _p50(s.rtts)
        return {
            "char": s.char,
            "decision": None if s.decision is None else {
                **s.decision, "decided_at": s.decided_at, "age_ms": (now - s.decided_at) * 1000.0 if s.decided_at else None},
            "buttons": {
                "held": (presses or {}).get("held", []),
                "total": (presses or {}).get("total", 0),
                "by_source": {"jev": (presses or {}).get("jev", 0), "reflex": (presses or {}).get("reflex", 0)},
            },
            "timing": {
                "response_ms_last": s.last_rtt, "response_ms_p50": p50,
                "decision_ms_last_estimated": self._est(s.last_rtt), "decision_ms_p50_estimated": self._est(p50),
                "network_baseline_ms": self.network_baseline_ms, "estimated_note": "decision time = round trip - network baseline; the API returns no timing field",
                "calls": s.calls, "stale_discarded": s.stale, "errors": s.errors, "applied": s.applied,
            },
            "usage": {"input_tokens": s.input_tokens, "output_tokens": s.output_tokens, "cost_usd": round(s.cost_usd(), 6)},
            "health": state_fighter.get("health"), "rage": state_fighter.get("rage"),
        }

    def snapshot(self, state: dict[str, Any], now: float | None = None) -> dict[str, Any]:
        now = now or time.time()
        presses = state.get("presses") or {}
        fighters = {w: self.fighter(w, state[w], presses.get(w), now) for w in FIGHTERS}
        tot = {k: sum(self.f[w].__dict__[k] for w in FIGHTERS) for k in ("calls", "applied", "stale", "errors", "input_tokens", "output_tokens")}
        tot["cost_usd"] = round(sum(self.f[w].cost_usd() for w in FIGHTERS), 6)
        return {
            "match": {"timer": state.get("timer"), "p1_health": state["p1"]["health"], "p2_health": state["p2"]["health"],
                      "max_health": state["p1"].get("max_health", 128), "emulation_speed_percent": state.get("speed_percent"),
                      "frame": state.get("frame"), "match_live": state.get("match_live")},
            "fighters": fighters, "totals": tot,
            "cost_rule": {"usd_per_million_input_tokens": 0.042, "usd_per_million_output_tokens": 0.0},
            "uptime_s": now - self.started,
        }
