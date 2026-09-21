#!/usr/bin/env python3
"""Final acceptance run against PRD section 10 (bead sam-yku.9).

Drives the BUILT app through System Events (Accessibility): Start, a full
match to a winner (two rounds to one fighter), Pause + Resume, Reset, a
second full match, Stop. Logs one line per second to /tmp/sam2/acceptance.log:
  wall phase timer hp1 hp2 emulation_speed% view_fps calls presses1 presses2
emulation speed and the view fps (MJPEG frames delivered to the app per
second, the figure its overlay shows) both come from the bridge telemetry. Prints a summary per section 10 item.
Deps: websockets (already installed).   python3 tools/acceptance.py
"""
import asyncio, json, subprocess, threading, time, websockets

APP = "/Users/zohaibtanwir/projects/jev-samsho2/app/src-tauri/target/release/bundle/macos/Jev plays Samurai Shodown II.app"
B = 'of group "panel" of UI element 1 of scroll area 1 of group 1 of group 1 of window 1'
LOG = open("/tmp/sam2/acceptance.log", "w")
latest = {}

def osa(cmd):
    r = subprocess.run(["osascript", "-e", f'tell application "System Events" to tell process "app" to {cmd}'], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()

def click(name, expect_control=None, tries=6):
    """Raise the window, click; if `expect_control` is given, retry until bridge.log shows that control line."""
    before = open("/tmp/sam2/bridge.log").read().count(f" control {expect_control} ") if expect_control else 0
    for _ in range(tries):
        osa("set frontmost to true"); osa('perform action "AXRaise" of window 1'); time.sleep(0.6)
        r = osa(f'click button "{name}" {B}')
        if not expect_control: return r
        time.sleep(1.2)
        if open("/tmp/sam2/bridge.log").read().count(f" control {expect_control} ") > before: return r
    return "click NOT confirmed"
def view_fps():
    v = osa('get value of every static text of group 1 of group "game view" of UI element 1 of scroll area 1 of group 1 of group 1 of window 1')
    try: return int(v.split(",")[1].strip())
    except Exception: return None
def buttons(): return osa(f'get {{enabled of button "Start", enabled of button "Pause", enabled of button "Reset", enabled of button "Stop"}} {B}')

async def ws_reader():
    while True:
        try:
            async with websockets.connect("ws://127.0.0.1:8765", max_size=None) as ws:
                async for m in ws:
                    if isinstance(m, str): latest.update(json.loads(m))
        except Exception:
            await asyncio.sleep(0.5)

def logger(stop):
    last_fps, n = None, 0
    while not stop.is_set():
        st = latest.get("state") or {}
        mj = (latest.get("relay") or {}).get("mjpeg") or {}
        last_fps = mj.get("fps")                 # what the app's overlay shows: frames delivered to the view per second
        p = latest.get("panel") or {}
        tot = p.get("totals", {})
        pr = st.get("presses") or {}
        LOG.write(f"{time.time():.1f} {latest.get('phase','-')} {st.get('timer','-')} {st.get('p1',{}).get('health','-')} {st.get('p2',{}).get('health','-')} "
                  f"{(st.get('speed_percent') or 0):.1f} {last_fps if last_fps is not None else '-'} {tot.get('calls','-')} {pr.get('p1',{}).get('total','-')} {pr.get('p2',{}).get('total','-')}\n"); LOG.flush()
        n += 1; time.sleep(1.0)

def wait_for(pred, timeout, every=0.5):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if pred(): return True
        time.sleep(every)
    return False

class MatchTracker:
    """A round ends when a health reaches 0 and later both are back to full; two round wins to one side = match."""
    def __init__(self): self.wins = {"p1": 0, "p2": 0}; self.pending = None; self.rounds = []
    def feed(self):
        st = latest.get("state") or {}
        h1, h2 = st.get("p1", {}).get("health"), st.get("p2", {}).get("health")
        if h1 is None: return
        if self.pending is None:
            if h1 == 0 and h2 > 0: self.pending = "p2"
            elif h2 == 0 and h1 > 0: self.pending = "p1"
        elif h1 == 128 and h2 == 128:
            self.wins[self.pending] += 1; self.rounds.append(self.pending); self.pending = None
    def decided(self): return max(self.wins.values()) >= 2

def run_match(label, tracker, timeout=360):
    t0 = time.time()
    while time.time() - t0 < timeout:
        tracker.feed()
        if tracker.decided(): return f"{label}: winner {'Earthquake' if tracker.wins['p1']==2 else 'Nakoruru'} (rounds {tracker.rounds}) after {time.time()-t0:.0f} s"
        time.sleep(0.2)
    return f"{label}: NOT decided in {timeout} s (rounds {tracker.rounds})"

def main():
    out = []
    threading.Thread(target=lambda: asyncio.run(ws_reader()), daemon=True).start()
    stop = threading.Event(); threading.Thread(target=logger, args=(stop,), daemon=True).start()
    subprocess.run(["open", "-n", APP]); time.sleep(5)
    osa("set frontmost to true")
    out.append(f"window: {osa('get name of window 1')}; buttons before Start {buttons()}")
    t_start = time.time(); click("Start")
    ok = wait_for(lambda: latest.get("phase") == "running", 120)
    out.append(f"Start -> running: {'yes' if ok else 'NO'} in {time.time()-t_start:.1f} s; buttons {buttons()}")
    out.append(run_match("match 1", MatchTracker()))
    # Pause / Resume once
    t1 = (latest.get("state") or {}).get("timer"); click("Pause", "pause"); time.sleep(4); t2 = (latest.get("state") or {}).get("timer"); ph = latest.get("phase")
    click("Resume", "resume"); time.sleep(3); t3 = (latest.get("state") or {}).get("timer")
    out.append(f"Pause: timer {t1} -> {t2} after 4 s (phase {ph}); Resume: timer {t3} 3 s later")
    # Reset once
    click("Reset", "reset"); time.sleep(1.5); st = latest.get("state") or {}; pr = st.get("presses") or {}; p = latest.get("panel") or {}
    out.append(f"Reset: timer {st.get('timer')} hp {st.get('p1',{}).get('health')}/{st.get('p2',{}).get('health')} presses {pr.get('p1',{}).get('total')}/{pr.get('p2',{}).get('total')} panel calls {p.get('totals',{}).get('calls')} (all should be round-1 / zero)")
    out.append(run_match("match 2", MatchTracker()))
    p = latest.get("panel") or {}; click("Stop", "stop"); time.sleep(10)
    out.append(f"Stop: buttons {buttons()}; panel totals before stop calls={p.get('totals',{}).get('calls')} cost={p.get('totals',{}).get('cost_usd')}")
    stop.set(); LOG.close()
    # summary of the log
    rows = [l.split() for l in open("/tmp/sam2/acceptance.log") if l.strip()]
    sp = [float(r[5]) for r in rows if r[1] in ("running", "paused") and float(r[5]) > 0]
    fp = [int(r[6]) for r in rows if r[1] == "running" and r[6] != "-"]
    out.append(f"speed while running: n={len(sp)} min={min(sp):.1f} median={sorted(sp)[len(sp)//2]:.1f}; seconds under 99%: {sum(1 for x in sp if x < 99)}")
    out.append(f"view fps while running: n={len(fp)} min={min(fp)} median={sorted(fp)[len(fp)//2]}; samples under 28: {sum(1 for x in fp if x < 28)}")
    for line in out: print(line)
    open("/tmp/sam2/acceptance_summary.txt", "w").write("\n".join(out) + "\n")

if __name__ == "__main__":
    main()
