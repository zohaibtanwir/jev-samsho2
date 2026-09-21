"""Newest-wins and pool behaviour with a fake client (sam-l4r.2)."""
import json, pathlib, threading, time, unittest
from bridge import jev, jevdm
from bridge.jevdm import Applier, CallResult, JevDecisionMaker

FIX = pathlib.Path(__file__).parent / "fixtures"
SAMPLE = json.loads((FIX / "jev_sample_response.json").read_text())
STATE = json.loads((FIX / "state_sample.json").read_text())

def dec(seq, who="p1", intent="attack"):
    d = jev.parse_response(SAMPLE, who=who, state_seq=seq, rtt_ms=300.0); d.intent = intent; return d


class ApplierTest(unittest.TestCase):
    def test_newest_wins_and_stale_counted(self):
        a = Applier()
        self.assertTrue(a.offer(CallResult("p1", 10, 0, dec(10), None, 300)))
        self.assertFalse(a.offer(CallResult("p1", 8, 0, dec(8), None, 300)))     # older reply arrives later: dropped
        self.assertTrue(a.offer(CallResult("p1", 12, 0, dec(12), None, 300)))
        self.assertFalse(a.offer(CallResult("p1", 12, 0, dec(12), None, 300)))   # same seq: stale
        self.assertTrue(a.offer(CallResult("p2", 9, 0, dec(9, "p2"), None, 300)))  # fighters independent
        self.assertEqual((a.applied, a.stale, a.errors), (3, 2, 0))
        self.assertEqual((a.input_tokens, a.output_tokens), (888 * 5, 121 * 5))  # stale replies still count tokens

    def test_error_counted_not_applied(self):
        a = Applier()
        self.assertFalse(a.offer(CallResult("p1", 5, 0, None, "HTTP 500", 100)))
        self.assertEqual(a.errors, 1); self.assertEqual(a.last_applied["p1"], 0)


class SlowFakeClient:
    """Answers after `delay` seconds; delay can depend on the state seq to reorder replies."""
    def __init__(self, delays):
        self.delays = delays
    def call(self, req, who="p1", state_seq=0):
        time.sleep(self.delays.get(state_seq, 0.01))
        return dec(state_seq, who)
    def close(self): pass


class PoolTest(unittest.TestCase):
    def test_overlapping_calls_reorder_and_newest_wins(self):
        delays = {1: 0.30, 2: 0.05, 3: 0.10}        # reply order will be 2, 3, 1
        dm = JevDecisionMaker(workers_per_fighter=3, client_factory=lambda: SlowFakeClient(delays))
        try:
            for seq in (1, 2, 3):
                st = dict(STATE); st["seq"] = seq
                dm.tick(st, "p1", [])
            self.assertEqual(dm.calls, 3)
            got = []
            deadline = time.time() + 2
            while len(got) < 3 and time.time() < deadline:
                got += list(dm.drain()); time.sleep(0.01)
            order = [r.state_seq for r, _ in got]
            applied = [(r.state_seq, ok) for r, ok in got]
            self.assertEqual(order, [2, 3, 1])
            self.assertEqual(applied, [(2, True), (3, True), (1, False)])
            self.assertEqual((dm.applier.applied, dm.applier.stale), (2, 1))
            self.assertEqual(dm.in_flight(), 0)
        finally:
            dm.close()


if __name__ == "__main__":
    unittest.main()
