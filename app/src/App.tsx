import { useEffect, useRef, useState } from "react";
import "./App.css";
import { BridgeSocket, bridgeStatus, startBridge, stopBridge, type Telemetry } from "./bridge";
import { useFrameSink } from "./FrameView";
import { Panel } from "./Panel";

type Phase = "stopped" | "booting" | "running" | "between_rounds" | "paused";

export default function App() {
  const [phase, setPhase] = useState<Phase>("stopped");
  const [msg, setMsg] = useState<string>("");
  const [tele, setTele] = useState<Telemetry | null>(null);
  const [finalPanel, setFinalPanel] = useState<any>(null);     // kept after Stop (PRD §6)
  const [wsOpen, setWsOpen] = useState(false);
  const startedAt = useRef<number | null>(null);
  const sock = useRef<BridgeSocket | null>(null);
  const frame = useFrameSink();
  const inTauri = "__TAURI_INTERNALS__" in window;
  // after a UI reload, re-adopt a sidecar that is already running (else Start/Stop get out of step)
  useEffect(() => { if (!inTauri) return; bridgeStatus().then((s) => { if (s.running) setPhase("booting"); }).catch(() => {}); }, [inTauri]);

  const latest = useRef<Telemetry | null>(null);
  useEffect(() => {
    // telemetry arrives with every emulated frame (~60/s); keep the newest and flush to React at 10 Hz
    const s = new BridgeSocket(frame.onFrame, (t) => { latest.current = t; }, setWsOpen);
    s.open(); sock.current = s;
    const id = setInterval(() => { if (latest.current) { setTele(latest.current); latest.current = null; } }, 100);
    return () => { clearInterval(id); s.close(); };
  }, []);

  // phase follows the bridge's signal while it is running
  useEffect(() => {
    if (!tele) return;
    const p = tele.phase as Phase;
    if (p === "running" && startedAt.current) { setMsg(`match running ${((Date.now() - startedAt.current) / 1000).toFixed(1)} s after Start`); startedAt.current = null; }
    if (phase !== "stopped" || !inTauri) setPhase(p);   // browser preview follows the bridge
  }, [tele]);
  // if the sidecar dies, drop back to stopped
  useEffect(() => { const id = setInterval(async () => { if (!inTauri) return; try { const s = await bridgeStatus(); if (!s.running && phase !== "stopped") { setPhase("stopped"); setMsg("bridge exited"); } } catch {} }, 2000); return () => clearInterval(id); }, [phase, inTauri]);

  const running = phase === "running" || phase === "between_rounds" || phase === "paused";

  async function onStart() {
    try { setMsg(""); setFinalPanel(null); setTele(null); startedAt.current = Date.now(); const st = await startBridge(false); setPhase("booting"); setMsg(`bridge pid ${st.pid} · booting MAME + Lua start sequence (~30 s)`); }
    catch (e) { setMsg(String(e)); }
  }
  async function onStop() {
    setFinalPanel(tele?.panel ?? null);
    sock.current?.send("stop");
    try { const r = await stopBridge(8); setMsg(r); } catch (e) { setMsg(String(e)); }
    setPhase("stopped");
  }
  const onPause = () => sock.current?.send(phase === "paused" ? "resume" : "pause");
  const onReset = () => { sock.current?.send("reset"); setMsg("reset sent"); };

  const panel = tele?.panel ?? finalPanel;               // after Stop the last telemetry stays on screen
  return (
    <div className="app">
      <section className="view" aria-label="game view">
        <canvas id="game" ref={frame.canvas} width={320} height={224} />
        <div className="view-overlay">view fps <b>{frame.fps}</b> · frames {frame.frames} · dropped {frame.dropped.current} · ws {wsOpen ? "open" : "closed"}</div>
      </section>
      <section className="panel" aria-label="panel">
        <div className="controls">
          <button className="primary" disabled={phase !== "stopped"} onClick={onStart}>Start</button>
          <button disabled={!running} onClick={onPause}>{phase === "paused" ? "Resume" : "Pause"}</button>
          <button disabled={!running} onClick={onReset}>Reset</button>
          <button disabled={phase === "stopped"} onClick={onStop}>Stop</button>
          <span className="status">status: <b>{phase}</b>{msg ? ` · ${msg}` : ""}{inTauri ? "" : " · browser preview (no process control)"}</span>
        </div>
        <Panel panel={panel} state={tele?.state} viewFps={frame.fps} />
      </section>
    </div>
  );
}
