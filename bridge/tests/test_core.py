"""Tests for the pure parts of bridge.core (sam-e8s.2)."""
import json, os, tempfile, unittest
from bridge import core


def st(seq, p1_action="idle", p2_action="idle", frame=None):
    return {"seq": seq, "frame": frame or 1000 + seq, "timer": 90, "match_live": True, "gap": 160,
            "p1": {"char": "Earthquake", "x": 240, "y": 224, "health": 128, "max_health": 128, "rage": 0, "rage_max": 32,
                   "action": p1_action, "action_name": None, "action_word": 0, "action_age": 0, "airborne": False, "crouching": False},
            "p2": {"char": "Nakoruru", "x": 400, "y": 224, "health": 128, "max_health": 128, "rage": 0, "rage_max": 32,
                   "action": p2_action, "action_name": None, "action_word": 0, "action_age": 0, "airborne": False, "crouching": False}}


class History(unittest.TestCase):
    def test_distinct_consecutive_and_last3(self):
        h = core.ActionHistory()
        for i, a in enumerate(["idle", "idle", "walk_fwd", "walk_fwd", "startup", "active", "recovery", "idle"]):
            h.update(st(i, p2_action=a))
        self.assertEqual(h.last("p2"), ["active", "recovery", "idle"])
        self.assertEqual(h.last("p2", 5), ["walk_fwd", "startup", "active", "recovery", "idle"])
        self.assertEqual(h.last("p1"), ["idle"])

    def test_transition_frames_ignored(self):
        h = core.ActionHistory()
        for i, a in enumerate(["idle", "transition", "walk_back", "transition", "idle"]):
            h.update(st(i, p1_action=a))
        self.assertEqual(h.last("p1"), ["idle", "walk_back", "idle"])


class Writer(unittest.TestCase):
    def test_atomic_seq_and_intent_only(self):
        with tempfile.TemporaryDirectory() as d:
            w = core.ActionWriter(path=os.path.join(d, "action.json"), tmp=os.path.join(d, "action.tmp"))
            d1 = w.write({"p1": "attack"}, "test"); d2 = w.write({"p2": "block", "p1": "advance"}, "test")
            self.assertEqual((d1["seq"], d2["seq"]), (1, 2))
            on_disk = json.load(open(w.path))
            self.assertEqual(on_disk, {"seq": 2, "source": "test", "p1": {"intent": "advance"}, "p2": {"intent": "block"}})
            self.assertFalse(os.path.exists(w.tmp))
            text = json.dumps(on_disk)
            for button in ("P1 A", "P2 B", "Right", "Left", "Up", "Down"):
                self.assertNotIn(button, text)

    def test_rejects_bad_intent(self):
        with tempfile.TemporaryDirectory() as d:
            w = core.ActionWriter(path=os.path.join(d, "a.json"), tmp=os.path.join(d, "a.tmp"))
            with self.assertRaises(ValueError): w.write({"p1": "anti_air"}, "test")
            with self.assertRaises(ValueError): w.write({"p3": "attack"}, "test")


class TickerTest(unittest.TestCase):
    def test_three_hz_each_with_offset(self):
        now = [0.0]
        t = core.Ticker(period=1 / 3, now=lambda: now[0])
        fired = []
        while now[0] < 3.0:
            for w in t.due(): fired.append((round(now[0], 3), w))
            now[0] += 0.01
        p1 = [x for x in fired if x[1] == "p1"]; p2 = [x for x in fired if x[1] == "p2"]
        self.assertEqual(len(p1), 9); self.assertEqual(len(p2), 9)
        self.assertAlmostEqual(p2[0][0] - p1[0][0], 1 / 6, places=1)

    def test_resync_after_stall(self):
        now = [0.0]; t = core.Ticker(period=1 / 3, now=lambda: now[0])
        t.due(); now[0] = 5.0
        self.assertEqual(t.due(), ["p1", "p2"])          # one catch-up tick each, not fifteen
        now[0] = 5.1
        self.assertEqual(t.due(), [])


class Dummy(unittest.TestCase):
    def test_cycles_independently(self):
        dm = core.DummyDecisionMaker()
        self.assertEqual([dm.decide({}, "p1", []) for _ in range(6)], ["advance", "attack", "retreat", "block", "bait", "advance"])
        self.assertEqual(dm.decide({}, "p2", []), "advance")


class BridgeStep(unittest.TestCase):
    def test_step_logs_and_writes_only_due_fighters(self):
        with tempfile.TemporaryDirectory() as d:
            w = core.ActionWriter(path=os.path.join(d, "action.json"), tmp=os.path.join(d, "action.tmp"))
            b = core.Bridge(core.DummyDecisionMaker(), source="test", writer=w, log_path=os.path.join(d, "bridge.log"))
            now = [0.0]; b.ticker = core.Ticker(period=1 / 3, now=lambda: now[0])
            docs = b.step(st(1, p2_action="walk_fwd"))
            self.assertEqual([list(k for k in x if k in core.FIGHTERS) for x in docs], [["p1"]])   # p2 not due yet
            now[0] = 0.2; docs = b.step(st(2, p2_action="attack"))
            self.assertEqual([x["p2"]["intent"] for x in docs], ["advance"])
            now[0] = 0.4; docs = b.step(st(3, p2_action="attack"))       # p1 due again, sees p2's history
            self.assertEqual([x["p1"]["intent"] for x in docs], ["attack"])
            log = open(os.path.join(d, "bridge.log")).read()
            self.assertIn("decision p1 state_seq=1", log); self.assertIn("decision p1 state_seq=3", log)
            self.assertIn("opp_last3=walk_fwd,attack", log)
            b.log.close()


if __name__ == "__main__":
    unittest.main()
