#!/usr/bin/env python3
"""Control-channel check (sam-l4r.4): pause, resume, reset, stop via the
bridge's cmd.json while Jev calls are in flight. Verifies from the files:
- pause: state.json stops updating (emulator paused), timer frozen; no calls issued while paused
- resume: state.json advances again from the same timer
- reset: health back to 128/128, round 1; no press after the reset comes from an action issued before it
- stop: MAME and bridge exit
Stdlib only.   python3 tools/control_test.py    log: /tmp/sam2/control_test.log
"""
import json, os, re, time

STATE, CMD, TMP, PRESSES, BLOG = "/tmp/sam2/state.json", "/tmp/sam2/cmd.json", "/tmp/sam2/cmd.tmp", "/tmp/sam2/presses.log", "/tmp/sam2/bridge.log"
seq = 0
def state():
    while True:
        try:
            with open(STATE) as f: return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError): time.sleep(0.01)
def cmd(c):
    global seq; seq += 1
    with open(TMP, "w") as f: json.dump({"seq": seq, "cmd": c}, f)
    os.rename(TMP, CMD)
def bridge_lines(): return open(BLOG).read().split("\n")

def main():
    while not os.path.exists(STATE): time.sleep(0.2)
    while not state().get("match_live"): time.sleep(0.2)
    time.sleep(12)   # let the fight run (Jev calls in flight)
    log = open("/tmp/sam2/control_test.log", "w")
    def out(s): print(s); log.write(s + "\n"); log.flush()
    # --- pause
    s0 = state(); cmd("pause"); time.sleep(0.6); s1 = state(); n_calls_at_pause = sum(" call " in l for l in bridge_lines())
    time.sleep(3.0); s2 = state(); n_calls_after = sum(" call " in l for l in bridge_lines())
    out(f"PAUSE: before seq={s0['seq']} timer={s0['timer']} | 0.6s later seq={s1['seq']} timer={s1['timer']} paused={s1.get('paused')} | 3s later seq={s2['seq']} timer={s2['timer']} -> timer frozen={s1["timer"]==s2["timer"]==s0["timer"]}; calls issued during pause={n_calls_after-n_calls_at_pause}")
    # --- resume
    cmd("resume"); time.sleep(1.5); s3 = state()
    out(f"RESUME: seq={s3['seq']} timer={s3['timer']} paused={s3.get('paused')} -> advancing={s3['seq']>s2['seq']}, timer continued from {s2['timer']} to {s3['timer']}")
    time.sleep(4)
    # --- reset while calls are in flight
    before = state(); reset_wall = time.time(); cmd("reset"); time.sleep(0.3); r1 = state(); time.sleep(3.0); r2 = state()
    out(f"RESET: before hp={before['p1']['health']}/{before['p2']['health']} timer={before['timer']} | after 0.3s hp={r1['p1']['health']}/{r1['p2']['health']} timer={r1['timer']} gap={r1['gap']} | after 3s hp={r2['p1']['health']}/{r2['p2']['health']} timer={r2['timer']} control_seq={r2.get('control_seq')} last_control={r2.get('last_control')}")
    # stale-press check: find the reset frame from the Lua control log entry, the first action_seq applied after the reset in bridge.log, and scan presses.log
    reset_frame = r2["last_control"]["frame"]
    L = bridge_lines()
    ctrl = [l for l in L if " control reset " in l][-1]
    idx = L.index(ctrl)
    first_after = None
    for l in L[idx:]:
        m = re.search(r" applied .*", l)
        if m:
            m2 = re.search(r"seq_sent=(\d+)", l)
    # action seqs written after the reset = those with state seq > state seq at reset; simpler: read action seq numbers from the presses log
    presses = [p.split() for p in open(PRESSES).read().split("\n") if p.strip()]
    after = [p for p in presses if int(p[0]) > reset_frame and p[3] == "jev"]
    pre_reset_seqs = {int(p[5]) for p in presses if int(p[0]) <= reset_frame and p[3] == "jev" and len(p) > 5}
    max_pre = max(pre_reset_seqs) if pre_reset_seqs else 0
    stale = [p for p in after if len(p) > 5 and int(p[5]) <= max_pre]
    disc = sum(" discarded " in l for l in L[idx:])
    out(f"STALE-PRESS CHECK: reset at frame {reset_frame}; highest action seq pressed before reset={max_pre}; presses after reset={len(after)}; presses after reset from pre-reset actions={len(stale)}; replies discarded by the bridge after the control command={disc}")
    # tokens still counted for discarded replies: telemetry totals vs sum of in= fields is checked in the bead notes from bridge.log
    # --- stop
    cmd("stop"); time.sleep(4)
    pids = [l.split() for l in open("/tmp/sam2/pids").read().split("\n") if l.strip()]
    alive = {lab: os.system(f"kill -0 {pid} 2>/dev/null") == 0 for pid, lab in pids}
    out(f"STOP: processes alive after stop = {alive}")
    log.close()

if __name__ == "__main__":
    main()
