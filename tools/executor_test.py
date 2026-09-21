#!/usr/bin/env python3
"""Drive the executor through every intent for both fighters (sam-amj.1).

Sends action files (tmp + rename) and samples state.json; then asks Lua for
a forward jump by P2 (marker file) to cross sides and checks that advance
now moves each fighter the other way. Stdlib only.
    python3 tools/executor_test.py    log: /tmp/sam2/executor_test.log
"""
import json, os, time

ACTION, TMP, STATE = "/tmp/sam2/action.json", "/tmp/sam2/action.tmp", "/tmp/sam2/state.json"
seq = 0

def state():
    while True:
        try:
            with open(STATE) as f: return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError): time.sleep(0.01)

def send(p1=None, p2=None, source="test"):
    global seq; seq += 1
    a = {"seq": seq, "source": source}
    if p1: a["p1"] = {"intent": p1}
    if p2: a["p2"] = {"intent": p2}
    with open(TMP, "w") as f: json.dump(a, f)
    os.rename(TMP, ACTION)

def main():
    while not os.path.exists(STATE): time.sleep(0.2)
    while not state().get("match_live"): time.sleep(0.2)
    time.sleep(2.5)
    log = open("/tmp/sam2/executor_test.log", "w")
    def out(s): print(s); log.write(s + "\n"); log.flush()
    def trial(who, intent, settle=1.6):
        other = "p2" if who == "p1" else "p1"
        b = state(); send(**{who: intent}); time.sleep(0.5); m = state(); time.sleep(settle); a = state()
        out(f"{who} {intent:8s} x {b[who]['x']}->{m[who]['x']}->{a[who]['x']} (other x {b[other]['x']}) "
            f"action@0.5s={m[who]['action']}/{m[who].get('action_name')} other hp {b[other]['health']}->{a[other]['health']} "
            f"held@0.5s={m['presses'][who]['held']} presses={a['presses'][who]}")
        send(**{who: "block"}, source="test"); time.sleep(0.3)   # neutral-ish: hold away briefly
        send(**{who: "retreat"}); time.sleep(0.1)
        return b, m, a
    # a small helper to stop a fighter: there is no 'idle' intent, so we send retreat then let it be
    out("== P1 Earthquake ==")
    for it in ("advance", "retreat", "block", "attack", "bait"): trial("p1", it)
    out("== P2 Nakoruru ==")
    for it in ("advance", "retreat", "block", "attack", "bait"): trial("p2", it)
    # crossing sides: neutralise both, walk P2 adjacent, then a scripted forward jump over P1
    out("== crossing ==")
    send(p1="none", p2="none"); time.sleep(0.3)
    send(p2="advance")
    for _ in range(60):
        s = state()
        if abs(s["p2"]["x"] - s["p1"]["x"]) <= 70: break
        time.sleep(0.1)
    send(p2="none"); time.sleep(0.4)
    s0 = state(); open("/tmp/sam2/do_jump", "w").close(); time.sleep(1.6); s1 = state()
    out(f"before jump p1 x={s0['p1']['x']} p2 x={s0['p2']['x']}; after p1 x={s1['p1']['x']} p2 x={s1['p2']['x']} crossed={s1['p2']['x'] < s1['p1']['x']}")
    if s1['p2']['x'] < s1['p1']['x']:
        b = state(); send(p1="advance", p2="advance"); time.sleep(0.8); a = state()
        out(f"advance after crossing: p1 x {b['p1']['x']}->{a['p1']['x']} (should decrease), p2 x {b['p2']['x']}->{a['p2']['x']} (should increase) held p1={a['presses']['p1']['held']} p2={a['presses']['p2']['held']}")
        send(p1="retreat", p2="retreat"); time.sleep(0.8); a2 = state()
        out(f"retreat after crossing: p1 x {a['p1']['x']}->{a2['p1']['x']} (should increase), p2 x {a['p2']['x']}->{a2['p2']['x']} (should decrease)")
        send(p1="none", p2="none")
    log.close()

if __name__ == "__main__":
    main()
