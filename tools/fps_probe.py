#!/usr/bin/env python3
"""Sample emulation speed and the MJPEG view fps once a second for N seconds (sam-yku.10)."""
import asyncio, json, subprocess, sys, time, websockets
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
rows = []
async def main():
    async with websockets.connect("ws://127.0.0.1:8765", max_size=None) as ws:
        t_last = 0
        while len(rows) < N:
            m = await ws.recv()
            if not isinstance(m, str): continue
            j = json.loads(m); now = time.time()
            if now - t_last >= 1.0 and j.get("phase") in ("running", "between_rounds", "paused"):
                t_last = now
                st = j["state"]; mj = (j.get("relay") or {}).get("mjpeg") or {}
                rows.append((j["phase"], st["timer"], st.get("speed_percent", 0), mj.get("fps", 0), mj.get("clients", 0)))
asyncio.run(main())
sp = [r[2] for r in rows if r[0] == "running"]; fp = [r[3] for r in rows if r[0] == "running"]
print(f"samples={len(rows)} running={len(sp)} speed min={min(sp):.1f} median={sorted(sp)[len(sp)//2]:.1f} under99={sum(1 for x in sp if x < 99)} | mjpeg fps min={min(fp)} median={sorted(fp)[len(fp)//2]} under28={sum(1 for x in fp if x < 28)} clients={rows[-1][4]}")
open("/tmp/sam2/fps_probe.txt", "w").write("\n".join(" ".join(map(str, r)) for r in rows) + "\n")
