import { useState } from "react";
import "./App.css";

type Phase = "stopped" | "booting" | "selecting" | "running" | "paused";

export default function App() {
  const [phase] = useState<Phase>("stopped");   // wired to the bridge in sam-yku.4
  const running = phase === "running" || phase === "paused";
  return (
    <div className="app">
      <section className="view" aria-label="game view">
        <canvas id="game" width={320} height={224} />
        <div className="view-overlay">game view · 320×224 scaled · frames arrive in sam-yku.5</div>
      </section>
      <section className="panel" aria-label="panel">
        <div className="controls">
          <button className="primary" disabled={running}>Start</button>
          <button disabled={!running}>{phase === "paused" ? "Resume" : "Pause"}</button>
          <button disabled={!running}>Reset</button>
          <button disabled={!running}>Stop</button>
          <span className="status">status: <b>{phase}</b></span>
        </div>
        <div className="fighters">
          <div className="fighter"><h2>Earthquake</h2><p className="muted">telemetry panel · sam-yku.6 / sam-yku.7</p></div>
          <div className="fighter"><h2>Nakoruru</h2><p className="muted">telemetry panel · sam-yku.6 / sam-yku.7</p></div>
        </div>
      </section>
    </div>
  );
}
