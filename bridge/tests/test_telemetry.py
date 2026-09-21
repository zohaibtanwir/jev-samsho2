import json, pathlib, unittest
from bridge.telemetry import Telemetry, USD_PER_INPUT_TOKEN

STATE = json.loads((pathlib.Path(__file__).parent / "fixtures" / "state_sample.json").read_text())

class TelemetryTest(unittest.TestCase):
    def setUp(self):
        self.t = Telemetry({"p1": "Earthquake", "p2": "Nakoruru"}, network_baseline_ms=250.0)

    def test_counts_tokens_cost_and_estimate(self):
        t = self.t
        for _ in range(3): t.record_call("p1")
        t.record_reply("p1", 350.0, 800, 75, True, intent="attack", probabilities={"attack": 0.7}, opponent_recovering=0.2, confidence=0.7, state_seq=10, now=100.0)
        t.record_reply("p1", 410.0, 810, 75, False)          # stale still costs tokens
        t.record_error("p1")
        snap = t.snapshot(STATE, now=100.5)
        f = snap["fighters"]["p1"]
        self.assertEqual(f["timing"]["calls"], 3); self.assertEqual(f["timing"]["applied"], 1); self.assertEqual(f["timing"]["stale_discarded"], 1); self.assertEqual(f["timing"]["errors"], 1)
        self.assertEqual(f["usage"]["input_tokens"], 1610); self.assertEqual(f["usage"]["output_tokens"], 150)
        self.assertAlmostEqual(f["usage"]["cost_usd"], round(1610 * USD_PER_INPUT_TOKEN, 6))
        self.assertAlmostEqual(f["timing"]["response_ms_last"], 410.0); self.assertAlmostEqual(f["timing"]["response_ms_p50"], 380.0)
        self.assertAlmostEqual(f["timing"]["decision_ms_last_estimated"], 160.0); self.assertAlmostEqual(f["timing"]["decision_ms_p50_estimated"], 130.0)
        self.assertEqual(f["decision"]["action"], "attack"); self.assertAlmostEqual(f["decision"]["age_ms"], 500.0)
        self.assertEqual(snap["totals"]["calls"], 3); self.assertAlmostEqual(snap["totals"]["cost_usd"], f["usage"]["cost_usd"])
        self.assertEqual(snap["fighters"]["p2"]["decision"], None)

    def test_output_tokens_cost_nothing(self):
        self.t.record_reply("p2", 300.0, 0, 5000, True, intent="advance")
        self.assertEqual(self.t.snapshot(STATE)["fighters"]["p2"]["usage"]["cost_usd"], 0.0)

    def test_reset_clears_but_keeps_baseline(self):
        self.t.record_call("p1"); self.t.record_reply("p1", 300.0, 100, 1, True, intent="block")
        self.t.reset()
        s = self.t.snapshot(STATE)
        self.assertEqual(s["totals"]["calls"], 0); self.assertEqual(s["fighters"]["p1"]["timing"]["network_baseline_ms"], 250.0)

    def test_no_baseline_means_no_estimate(self):
        t = Telemetry({"p1": "Earthquake", "p2": "Nakoruru"}, None)
        t.record_reply("p1", 300.0, 1, 1, True, intent="block")
        self.assertIsNone(t.snapshot(STATE)["fighters"]["p1"]["timing"]["decision_ms_last_estimated"])

if __name__ == "__main__":
    unittest.main()
