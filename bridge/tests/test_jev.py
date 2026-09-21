"""Offline tests for bridge.jev against the saved sample response (sam-l4r.1)."""
import json
import os
import pathlib
import unittest
from unittest import mock

from bridge import jev

FIX = pathlib.Path(__file__).parent / "fixtures"
SAMPLE = json.loads((FIX / "jev_sample_response.json").read_text())
STATE = json.loads((FIX / "state_sample.json").read_text())


class ParseResponse(unittest.TestCase):
    def test_sample_parses_to_decision(self):
        d = jev.parse_response(SAMPLE, who="p1", state_seq=42, rtt_ms=350.0)
        self.assertEqual(d.intent, "attack")
        self.assertAlmostEqual(d.confidence, 0.76)
        self.assertAlmostEqual(d.probabilities["attack"], 0.80)
        self.assertAlmostEqual(d.probabilities["advance"], 0.10)
        self.assertAlmostEqual(d.opponent_recovering, 0.83)
        self.assertEqual((d.input_tokens, d.output_tokens), (888, 121))
        self.assertEqual(d.model, "jev-1.13.0")
        self.assertEqual((d.who, d.state_seq, d.rtt_ms), ("p1", 42, 350.0))

    def test_noul_has_no_confidence_and_that_is_fine(self):
        self.assertNotIn("confidence", SAMPLE["answers"]["opponent_recovering"])
        jev.parse_response(SAMPLE)

    def test_choice_probabilities_are_a_dict_keyed_by_option(self):
        d = jev.parse_response(SAMPLE)
        self.assertIsInstance(d.probabilities, dict)
        self.assertTrue(set(jev.INTENTS) <= set(d.probabilities))

    def test_unknown_intent_rejected(self):
        bad = json.loads(json.dumps(SAMPLE)); bad["answers"]["action"]["choice"] = "anti_air"
        with self.assertRaises(jev.JevError):
            jev.parse_response(bad)

    def test_missing_answer_rejected(self):
        bad = json.loads(json.dumps(SAMPLE)); del bad["answers"]["opponent_recovering"]
        with self.assertRaises(jev.JevError):
            jev.parse_response(bad)

    def test_wrong_type_rejected(self):
        bad = json.loads(json.dumps(SAMPLE)); bad["answers"]["action"]["type"] = "score"
        with self.assertRaises(jev.JevError):
            jev.parse_response(bad)


class BuildRequest(unittest.TestCase):
    def test_exactly_two_questions(self):
        req = jev.build_request(STATE, "p1", [])
        self.assertEqual(set(req["questions"]), {"opponent_recovering", "action"})
        self.assertEqual(req["questions"]["opponent_recovering"]["type"], "noul")
        self.assertEqual(req["questions"]["action"]["type"], "choice")
        self.assertEqual(set(req["questions"]["action"]["criteria"]), set(jev.INTENTS))
        self.assertEqual(req["model"], jev.MODEL)

    def test_state_fields_for_p1(self):
        st = jev.build_state(STATE, "p1", ["idle", "walk_fwd", "recovery", "attack"])
        self.assertEqual(st["me"]["char"], "Earthquake"); self.assertEqual(st["them"]["char"], "Nakoruru")
        self.assertEqual(st["me"]["side"], "left"); self.assertEqual(st["them"]["side"], "right")
        self.assertEqual(st["gap_px"], abs(STATE["p2"]["x"] - STATE["p1"]["x"]))
        self.assertEqual(st["timer"], STATE["timer"])
        self.assertEqual(st["last_3_opponent_actions"], ["walk_fwd", "recovery", "attack"])
        for k in ("x", "y", "health", "max_health", "rage", "state", "airborne", "crouching"):
            self.assertIn(k, st["me"]); self.assertIn(k, st["them"])

    def test_state_fields_for_p2_are_mirrored(self):
        st = jev.build_state(STATE, "p2", [])
        self.assertEqual(st["me"]["char"], "Nakoruru"); self.assertEqual(st["me"]["side"], "right")
        self.assertEqual(st["them"]["char"], "Earthquake")

    def test_request_is_json_and_never_contains_the_key(self):
        with mock.patch.dict(os.environ, {jev.KEY_ENV: "not-a-real-key-XYZ"}):
            req = jev.build_request(STATE, "p1", [])
            body = json.dumps(req)
        self.assertNotIn("not-a-real-key-XYZ", body)
        self.assertNotIn("Bearer", body)


class ClientWithoutNetwork(unittest.TestCase):
    def test_missing_key_is_a_clean_error_without_network(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(jev.JevError) as cm:
                jev.JevClient().call({"model": "x", "state": {}, "questions": {}})
        self.assertIn(jev.KEY_ENV, str(cm.exception))

    def test_call_parses_a_mocked_200(self):
        class FakeResp:
            status = 200
            def read(self): return json.dumps(SAMPLE).encode()
        class FakeConn:
            def __init__(self, *a, **k): self.sent = None
            def connect(self): pass
            def request(self, method, path, body=None, headers=None):
                self.sent = (method, path, json.loads(body), dict(headers))
            def getresponse(self): return FakeResp()
            def close(self): pass
        with mock.patch.dict(os.environ, {jev.KEY_ENV: "not-a-real-key-XYZ"}), \
             mock.patch("http.client.HTTPSConnection", FakeConn):
            c = jev.JevClient()
            d = c.call(jev.build_request(STATE, "p2", ["attack"]), who="p2", state_seq=7)
            sent = c._conn.sent
        self.assertEqual(d.intent, "attack"); self.assertEqual(d.who, "p2"); self.assertEqual(d.state_seq, 7)
        self.assertEqual(sent[0:2], ("POST", jev.PATH))
        self.assertEqual(sent[3]["Authorization"], "Bearer not-a-real-key-XYZ")
        self.assertEqual(sent[3]["Connection"], "keep-alive")
        self.assertNotIn("Authorization", json.dumps(sent[2]))
        self.assertFalse(hasattr(c, "key") or hasattr(c, "_key"))

    def test_http_error_is_jeverror(self):
        class FakeResp:
            status = 401
            def read(self): return b'{"error":"nope"}'
        class FakeConn:
            def __init__(self, *a, **k): pass
            def connect(self): pass
            def request(self, *a, **k): pass
            def getresponse(self): return FakeResp()
            def close(self): pass
        with mock.patch.dict(os.environ, {jev.KEY_ENV: "not-a-real-key-XYZ"}), \
             mock.patch("http.client.HTTPSConnection", FakeConn):
            with self.assertRaises(jev.JevError) as cm:
                jev.JevClient().call(jev.build_request(STATE, "p1", []))
        self.assertIn("401", str(cm.exception)); self.assertNotIn("not-a-real-key", str(cm.exception))


if __name__ == "__main__":
    unittest.main()
