#!/usr/bin/env python3
"""Hand-drive action.json for the sam-e8s.1 check.

Writes one action every `gap` seconds (tmp + rename), sampling state.json
before and 0.5 s after each, and prints what changed. Stdlib only.
    python3 tools/action_test.py
"""
import json, os, time

ACTION = "/tmp/sam2/action.json"; TMP = "/tmp/sam2/action.tmp"; STATE = "/tmp/sam2/state.json"

def state():
    for _ in range(50):
        try:
            with open(STATE) as f: return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError): time.sleep(0.01)
    raise SystemExit("no state.json")

def send(seq, p1=None, p2=None):
    a = {"seq": seq, "source": "test"}
    if p1: a["p1"] = {"intent": p1}
    if p2: a["p2"] = {"intent": p2}
    with open(TMP, "w") as f: json.dump(a, f)
    os.rename(TMP, ACTION)

def main():
    t0 = time.time()
    while not os.path.exists(STATE):
        if time.time() - t0 > 90: raise SystemExit("state.json never appeared")
        time.sleep(0.2)
    while not state().get("match_live"): time.sleep(0.2)
    time.sleep(2.0)
    plan = [("p1", "advance"), ("p1", "retreat"), ("p1", "attack"), ("p1", "block"), ("p1", "bait"),
            ("p2", "advance"), ("p2", "retreat"), ("p2", "attack"), ("p2", "block"), ("p2", "bait"),
            ("both", "advance")]
    log = open("/tmp/sam2/action_test.log", "w")
    for i, (who, intent) in enumerate(plan, start=1):
        before = state()
        send(i, p1=intent if who in ("p1", "both") else None, p2=intent if who in ("p2", "both") else None)
        time.sleep(0.5)
        mid = state()
        time.sleep(1.5)
        after = state()
        key = "p1" if who == "p1" else "p2"
        line = (f"seq {i:2d} {who:4s} {intent:8s} | {key} x {before[key]['x']}->{mid[key]['x']}->{after[key]['x']} "
                f"action@0.5s={mid[key]['action']}/{mid[key].get('action_name')} | other hp {before['p1' if key=='p2' else 'p2']['health']}->{after['p1' if key=='p2' else 'p2']['health']} "
                f"| lua saw seq {mid.get('action_seq')} last={mid.get('last_action')}")
        print(line); log.write(line + "\n"); log.flush()
    # stale / replayed seq must be ignored
    before = state(); send(3, p1="advance"); time.sleep(0.7); after = state()
    line = f"replay seq 3 -> lua action_seq stays {after.get('action_seq')} (was {before.get('action_seq')}), p1 x {before['p1']['x']}->{after['p1']['x']}"
    print(line); log.write(line + "\n"); log.close()

if __name__ == "__main__":
    main()
