import { useEffect, useRef, useState } from "react";
import "./App.css";
import { BridgeSocket, bridgeStatus, startBridge, stopBridge, type Telemetry } from "./bridge";

type Phase = "stopped" | "booting" | "running" | "paused";

export default function App() {
  const [phase, setPhase] = useState<Phase>("stopped");
  const [msg, setMsg] = useState<string>("");
  const [tele, setTele] = useState<Telemetry | null>(null);
  const sock = useRef<BridgeSocket | null>(null);

  useEffect(() => {
    const s = new BridgeSocket(() => {}, (t) => setTele(t));
    s.open(); sock.current = s;
    return () => s.close();
  }, []);

  const inTauri = "__TAURI_INTERNALS__" in window;
  const running = phase === "running" || phase === "paused";

  async function onStart() {
    try { setMsg(""); const st = await startBridge(false); setPhase("booting"); setMsg(`bridge pid ${st.pid}`); }
    catch (e) { setMsg(String(e)); }
  }
  async function onStop() {
    sock.current?.send("stop");
    try { const r = await stopBridge(8); setMsg(r); } catch (e) { setMsg(String(e)); }
    setPhase("stopped");
  }
  // sam-yku.4 gates on the bridge's match-running signal; for now, telemetry arriving = running
  useEffect(() => { if (tele && phase === "booting") setPhase("running"); }, [tele, phase]);
  useEffect(() => { const id = setInterval(async () => { if (!inTauri) return; try { const s = await bridgeStatus(); if (!s.running && phase !== "stopped") setPhase("stopped"); } catch {} }, 2000); return () => clearInterval(id); }, [phase, inTauri]);

  return (
    <div className="app">
      <section className="view" aria-label="game view">
        <canvas id="game" width={320} height={224} />
        <div className="view-overlay">game view · 320×224 scaled · frames arrive in sam-yku.5</div>
      </section>
      <section className="panel" aria-label="panel">
        <div className="controls">
          <button className="primary" disabled={running || phase === "booting"} onClick={onStart}>Start</button>
          <button disabled={!running}>{phase === "paused" ? "Resume" : "Pause"}</button>
          <button disabled={!running}>Reset</button>
          <button disabled={!running && phase !== "booting"} onClick={onStop}>Stop</button>
          <span className="status">status: <b>{phase}</b>{msg ? ` · ${msg}` : ""}{inTauri ? "" : " · (browser preview: no process control)"}</span>
        </div>
        <div className="fighters">
          <div className="fighter"><h2>Earthquake</h2><p className="muted">telemetry panel · sam-yku.6 / sam-yku.7{tele ? ` · hp ${tele.state?.p1?.health}` : ""}</p></div>
          <div className="fighter"><h2>Nakoruru</h2><p className="muted">telemetry panel · sam-yku.6 / sam-yku.7{tele ? ` · hp ${tele.state?.p2?.health}` : ""}</p></div>
        </div>
      </section>
    </div>
  );
}
