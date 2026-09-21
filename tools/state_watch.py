#!/usr/bin/env python3
"""Append every new /tmp/sam2/state.json to /tmp/sam2/state_log.jsonl.

Polls the file; a new `seq` means a new frame. Stdlib only.
    python3 tools/state_watch.py [seconds]
"""
import json, os, sys, time

SRC = "/tmp/sam2/state.json"
DST = "/tmp/sam2/state_log.jsonl"

def main():
    limit = float(sys.argv[1]) if len(sys.argv) > 1 else 60.0
    t0 = time.time(); last_seq = None; n = 0; bad = 0
    with open(DST, "w") as out:
        while time.time() - t0 < limit:
            try:
                with open(SRC) as f:
                    st = json.load(f)
            except FileNotFoundError:
                time.sleep(0.005); continue
            except json.JSONDecodeError:
                bad += 1; time.sleep(0.002); continue
            if st.get("seq") != last_seq:
                last_seq = st.get("seq"); n += 1
                out.write(json.dumps(st, separators=(",", ":")) + "\n")
            time.sleep(0.004)
    print(f"wrote {n} states to {DST} in {limit:.0f}s; decode errors: {bad}")

if __name__ == "__main__":
    main()
