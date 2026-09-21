"""Jev decision-making for the bridge (bead sam-l4r.2).

PRD section 8 item 5: Jev is called 3 times a second per fighter; the newest
answer wins and older replies are dropped. A call takes ~350 ms, longer than
the 333 ms period, so calls overlap: each fighter has a small pool of worker
threads, each owning one keep-alive JevClient. Ticks are issued on schedule
whether or not a call is in flight; replies are applied only if the state
they answered is newer than the last applied one (else counted stale). The
game loop never waits: results are polled from a queue.
"""
from __future__ import annotations

import queue
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable

from bridge import jev

FIGHTERS = ("p1", "p2")


@dataclass
class CallResult:
    who: str
    state_seq: int
    issued_at: float
    decision: jev.Decision | None
    error: str | None
    rtt_ms: float


@dataclass
class Applier:
    """Newest-wins bookkeeping per fighter (pure, tested)."""
    last_applied: dict[str, int] = field(default_factory=lambda: {w: 0 for w in FIGHTERS})
    applied: int = 0
    stale: int = 0
    errors: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    def offer(self, r: CallResult) -> bool:
        """Account for a result; True if it should be applied."""
        if r.decision is None:
            self.errors += 1
            return False
        self.input_tokens += r.decision.input_tokens
        self.output_tokens += r.decision.output_tokens
        if r.state_seq <= self.last_applied[r.who]:
            self.stale += 1
            return False
        self.last_applied[r.who] = r.state_seq
        self.applied += 1
        return True


class JevPool:
    """Issues calls for one fighter on a pool of threads, each with its own client."""

    def __init__(self, who: str, results: "queue.Queue[CallResult]", workers: int = 3,
                 client_factory: Callable[[], Any] = jev.JevClient, model: str = jev.MODEL):
        self.who, self.results, self.model = who, results, model
        self.jobs: "queue.Queue[tuple[dict, int, list[str], float] | None]" = queue.Queue()
        self.in_flight = 0
        self._lock = threading.Lock()
        self.threads = [threading.Thread(target=self._worker, args=(client_factory(),), name=f"jev-{who}-{i}", daemon=True)
                        for i in range(workers)]
        for t in self.threads:
            t.start()

    def issue(self, state: dict[str, Any], opponent_history: list[str]) -> None:
        with self._lock:
            self.in_flight += 1
        self.jobs.put((state, state["seq"], list(opponent_history), time.monotonic()))

    def close(self) -> None:
        for _ in self.threads:
            self.jobs.put(None)

    def _worker(self, client) -> None:
        while True:
            job = self.jobs.get()
            if job is None:
                break
            state, seq, hist, issued = job
            req = jev.build_request(state, self.who, hist, model=self.model)
            t0 = time.perf_counter()
            try:
                d = client.call(req, who=self.who, state_seq=seq)
                res = CallResult(self.who, seq, issued, d, None, d.rtt_ms)
            except jev.JevError as e:
                res = CallResult(self.who, seq, issued, None, str(e), (time.perf_counter() - t0) * 1000)
            with self._lock:
                self.in_flight -= 1
            self.results.put(res)
        try:
            client.close()
        except Exception:
            pass


class JevDecisionMaker:
    """Not a synchronous DecisionMaker: the bridge calls tick()/drain().

    tick(state, who, history) issues a call; drain() yields (result, apply)
    pairs for every finished call, apply meaning 'newest for that fighter'.
    """

    def __init__(self, workers_per_fighter: int = 3, client_factory=jev.JevClient, model: str = jev.MODEL):
        self.results: "queue.Queue[CallResult]" = queue.Queue()
        self.pools = {w: JevPool(w, self.results, workers_per_fighter, client_factory, model) for w in FIGHTERS}
        self.applier = Applier()
        self.calls = 0
        self.rtts: list[float] = []

    def tick(self, state: dict[str, Any], who: str, opponent_history: list[str]) -> None:
        self.calls += 1
        self.pools[who].issue(state, opponent_history)

    def drain(self):
        while True:
            try:
                r = self.results.get_nowait()
            except queue.Empty:
                return
            if r.decision is not None:
                self.rtts.append(r.rtt_ms)
                if len(self.rtts) > 600:
                    del self.rtts[:200]
            yield r, self.applier.offer(r)

    def in_flight(self) -> int:
        return sum(p.in_flight for p in self.pools.values())

    def close(self) -> None:
        for p in self.pools.values():
            p.close()
