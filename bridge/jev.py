"""Jev client for the samsho2 bridge (bead sam-l4r.1).

Builds the PRD section 9 request for one fighter from a state.json object,
posts it to Jev over one persistent keep-alive HTTPS connection, and parses
the response using the wire shape confirmed in jev_sample_response.json:

  choice answer: {"type": "choice", "choice": str, "confidence": float,
                  "probabilities": {option: float}}
  noul answer:   {"type": "noul", "noul": float}      (no confidence field)
  usage:         {"input_tokens": int, "output_tokens": int}

The API key is read from TYPESAFE_API_KEY at call time only. It is never
stored on the client object, logged, or included in any error message.
Stdlib only.
"""
from __future__ import annotations

import http.client
import json
import os
import socket
import ssl
import time
from dataclasses import dataclass, field
from typing import Any

HOST = os.environ.get("JEV_HOST", "api.typesafe.ai")
PATH = os.environ.get("JEV_PATH", "/v1/systemone")
MODEL = os.environ.get("JEV_MODEL", "jev-latest")
KEY_ENV = "TYPESAFE_API_KEY"

INTENTS = ("advance", "retreat", "attack", "block", "bait")

# Heavy-slash reach per character, in pixels of gap (sam-amj.5 / sam-aug.2):
# Earthquake's A+B landed at the 160 px start gap and whiffed at 60;
# Nakoruru needed ~45 frames of walking from 160 before anything landed.
REACH = {"Earthquake": {"min": 80, "max": 175}, "Nakoruru": {"min": 0, "max": 110}}

# Same two questions and five options as PRD section 9. The criteria wording
# was rewritten on 21 Sep 2026 (bead sam-l4r.5): under the first wording
# ("attack ... only when they are in recovery") both fighters chose advance
# 99% of the time and stood face to face for a whole round.
QUESTIONS: dict[str, Any] = {
    "opponent_recovering": {
        "type": "noul",
        "instructions": (
            "Is the opponent currently in recovery frames from an attack, or "
            "otherwise unable to block or move for the next few frames?"
        ),
    },
    "action": {
        "type": "choice",
        "instructions": (
            "What should I do in the next half second? This is a weapon fighting game: "
            "rounds are won by landing heavy slashes, and standing still next to the "
            "opponent gains nothing."
        ),
        "criteria": {
            "attack": "Swing my heavy slash now. Correct when me.in_range is true and the opponent is idle, walking, or in recovery. Also correct when the opponent is recovering from a missed attack. This is the default choice when in range.",
            "advance": "Walk toward the opponent. Correct when me.in_range is false and the opponent is not attacking.",
            "block": "Hold guard. Correct when the opponent is in startup or active attack frames and within their reach.",
            "bait": "Whiff a light attack at the edge of range to draw a reaction I can punish. Correct when both of us are idle just outside range.",
            "retreat": "Step back. Correct when I am low on health with a lead to protect, or the opponent has full rage and I am not in range.",
        },
    },
}


class JevError(Exception):
    """Transport or protocol failure. Never carries the API key."""


@dataclass
class Decision:
    who: str                      # "p1" or "p2"
    state_seq: int                # seq of the state.json this was asked about
    intent: str
    confidence: float
    probabilities: dict[str, float]
    opponent_recovering: float
    input_tokens: int
    output_tokens: int
    rtt_ms: float
    model: str
    raw: dict[str, Any] = field(repr=False, default_factory=dict)


# ---------------------------------------------------------------- request

def in_range(char: str, gap: int) -> bool:
    r = REACH.get(char, {"min": 0, "max": 110})
    return r["min"] <= gap <= r["max"]


def _fighter(f: dict[str, Any], side: str, gap: int) -> dict[str, Any]:
    idle = f["action"] in ("idle", "walk_fwd", "walk_back", "crouch")
    return {
        "char": f["char"], "side": side, "x": f["x"], "y": f["y"],
        "health": f["health"], "max_health": f.get("max_health", 128),
        "rage": f["rage"], "rage_max": f.get("rage_max", 32),
        "state": f.get("action_name") or f["action"],
        "phase": f["action"],
        "idle_frames": int(f.get("action_age", 0)) if idle else 0,
        "in_range": in_range(f["char"], gap),
        "attacking": f["action"] in ("startup", "active"),
        "recovering": f["action"] == "recovery",
        "stunned": f["action"] == "hitstun",
        "airborne": bool(f["airborne"]), "crouching": bool(f["crouching"]),
    }


def build_state(state: dict[str, Any], who: str, last_opponent_actions: list[str]) -> dict[str, Any]:
    """PRD section 9 state for fighter `who` ("p1" or "p2")."""
    me_key, them_key = ("p1", "p2") if who == "p1" else ("p2", "p1")
    me, them = state[me_key], state[them_key]
    me_side = "left" if me["x"] <= them["x"] else "right"
    them_side = "right" if me_side == "left" else "left"
    gap = abs(them["x"] - me["x"])
    return {
        "game": "Samurai Shodown II",
        "frame": state["frame"],
        "timer": state["timer"],
        "me": _fighter(me, me_side, gap),
        "them": _fighter(them, them_side, gap),
        "gap_px": gap,
        "last_3_opponent_actions": list(last_opponent_actions)[-3:],
    }


def build_request(state: dict[str, Any], who: str, last_opponent_actions: list[str], model: str = MODEL) -> dict[str, Any]:
    return {"model": model, "state": build_state(state, who, last_opponent_actions), "questions": QUESTIONS}


# --------------------------------------------------------------- response

def parse_response(body: dict[str, Any], who: str = "p1", state_seq: int = 0, rtt_ms: float = 0.0) -> Decision:
    try:
        answers = body["answers"]
        action = answers["action"]
        if action.get("type") != "choice":
            raise JevError(f"action answer type {action.get('type')!r}, expected choice")
        intent = action["choice"]
        if intent not in INTENTS:
            raise JevError(f"unknown intent {intent!r}")
        probs = {k: float(v) for k, v in action["probabilities"].items()}
        rec = answers["opponent_recovering"]
        if rec.get("type") != "noul":
            raise JevError(f"opponent_recovering type {rec.get('type')!r}, expected noul")
        usage = body.get("usage", {})
        return Decision(
            who=who, state_seq=state_seq, intent=intent,
            confidence=float(action.get("confidence", 0.0)), probabilities=probs,
            opponent_recovering=float(rec["noul"]),
            input_tokens=int(usage.get("input_tokens", 0)), output_tokens=int(usage.get("output_tokens", 0)),
            rtt_ms=rtt_ms, model=str(body.get("model", "")), raw=body,
        )
    except (KeyError, TypeError, ValueError) as e:
        raise JevError(f"malformed response: {type(e).__name__}: {e}") from e


# ----------------------------------------------------------------- client

class JevClient:
    """One persistent HTTPS connection. Not thread-safe: one per worker."""

    def __init__(self, host: str = HOST, path: str = PATH, timeout: float = 10.0):
        self.host, self.path, self.timeout = host, path, timeout
        self._conn: http.client.HTTPSConnection | None = None
        self._ctx = ssl.create_default_context()

    def _connect(self) -> http.client.HTTPSConnection:
        if self._conn is None:
            self._conn = http.client.HTTPSConnection(self.host, 443, context=self._ctx, timeout=self.timeout)
            self._conn.connect()
        return self._conn

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            finally:
                self._conn = None

    @staticmethod
    def _headers() -> dict[str, str]:
        key = os.environ.get(KEY_ENV)
        if not key:
            raise JevError(f"{KEY_ENV} is not set")
        return {"Authorization": f"Bearer {key}", "Content-Type": "application/json", "Connection": "keep-alive"}

    def call(self, request: dict[str, Any], who: str = "p1", state_seq: int = 0) -> Decision:
        payload = json.dumps(request).encode()
        headers = self._headers()          # built per call, discarded after
        t0 = time.perf_counter()
        try:
            conn = self._connect()
            conn.request("POST", self.path, body=payload, headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
        except (OSError, http.client.HTTPException, socket.timeout) as e:
            self.close()
            raise JevError(f"transport: {type(e).__name__}: {e}") from e
        finally:
            del headers
        rtt_ms = (time.perf_counter() - t0) * 1000.0
        if resp.status != 200:
            self.close()
            raise JevError(f"HTTP {resp.status}: {raw[:200].decode(errors='replace')}")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError as e:
            raise JevError(f"non-JSON body: {e}") from e
        return parse_response(body, who=who, state_seq=state_seq, rtt_ms=rtt_ms)


def measure_rtt(host: str = HOST, rounds: int = 5) -> list[float]:
    """Plain TCP connect times in ms, the network baseline used to estimate
    inference time (PRD section 7: decision time = round trip - network)."""
    out = []
    for _ in range(rounds):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(5)
        t0 = time.perf_counter()
        try:
            s.connect((host, 443)); out.append((time.perf_counter() - t0) * 1000.0)
        except OSError:
            pass
        finally:
            s.close()
    return out


# ------------------------------------------------------------------ smoke

def _smoke() -> int:
    """One live call from a state sample. Prints the parsed Decision only."""
    import pathlib
    here = pathlib.Path(__file__).parent
    state = json.loads((here / "tests" / "fixtures" / "state_sample.json").read_text())
    req = build_request(state, "p1", ["idle", "walk_fwd", "attack"])
    client = JevClient()
    try:
        d = client.call(req, who="p1", state_seq=state["seq"])
    finally:
        client.close()
    print(f"model={d.model} intent={d.intent} confidence={d.confidence:.2f} opponent_recovering={d.opponent_recovering:.2f}")
    print("probabilities=" + " ".join(f"{k}={v:.2f}" for k, v in sorted(d.probabilities.items(), key=lambda kv: -kv[1])))
    print(f"usage in={d.input_tokens} out={d.output_tokens} rtt_ms={d.rtt_ms:.1f}")
    return 0


if __name__ == "__main__":
    import sys
    if "--smoke" in sys.argv:
        try:
            sys.exit(_smoke())
        except JevError as e:
            print(f"JevError: {e}"); sys.exit(1)
    print(__doc__)
