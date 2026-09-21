// Telemetry panel per PRD section 7 (beads sam-yku.6 / sam-yku.7). Every figure
// comes from the bridge's `panel` object; nothing is computed from placeholders.
const OPTIONS = ["advance", "retreat", "attack", "block", "bait"] as const;
const f1 = (v: number | null | undefined, d = 0) => (v == null ? "–" : v.toFixed(d));
const usd = (v: number | null | undefined) => (v == null ? "–" : `$${v.toFixed(4)}`);

function Bar({ value, max, color }: { value: number; max: number; color?: string }) {
  const pct = Math.max(0, Math.min(100, (100 * value) / max));
  return <div className="bar"><div className="bar-fill" style={{ width: `${pct}%`, background: color }} /></div>;
}

export function Panel({ panel, state, viewFps }: { panel: any; state: any; viewFps: number }) {
  const m = panel?.match;
  return (
    <>
      <div className="matchbar">
        <div className="hp left"><span>Earthquake {m ? m.p1_health : "–"}</span><Bar value={m?.p1_health ?? 0} max={m?.max_health ?? 128} /></div>
        <div className="timer">{m ? m.timer : "–"}</div>
        <div className="hp right"><span>{m ? m.p2_health : "–"} Nakoruru</span><Bar value={m?.p2_health ?? 0} max={m?.max_health ?? 128} /></div>
        <div className="meta">emulation {f1(m?.emulation_speed_percent, 1)}% · view {viewFps} fps · frame {m?.frame ?? "–"}</div>
      </div>
      <div className="fighters">
        {(["p1", "p2"] as const).map((who) => <Fighter key={who} who={who} f={panel?.fighters?.[who]} s={state?.[who]} />)}
      </div>
    </>
  );
}

function Fighter({ who, f, s }: { who: "p1" | "p2"; f: any; s: any }) {
  const d = f?.decision; const t = f?.timing; const u = f?.usage; const b = f?.buttons;
  return (
    <div className="fighter">
      <h2>{f?.char ?? (who === "p1" ? "Earthquake" : "Nakoruru")}</h2>
      <h3>Decision</h3>
      <div className="row"><span className="k">current action</span><span className="v">{d?.action ?? "–"} <small>{d ? `decided ${f1(d.age_ms / 1000, 1)} s ago` : ""}</small></span></div>
      {OPTIONS.map((o) => (
        <div className="row prob" key={o}><span className="k">{o}</span><Bar value={d?.probabilities?.[o] ?? 0} max={1} color={d?.action === o ? "var(--accent)" : undefined} /><span className="v num">{f1((d?.probabilities?.[o] ?? 0) * 100)}%</span></div>
      ))}
      <div className="row prob"><span className="k">opponent recovering?</span><Bar value={d?.opponent_recovering ?? 0} max={1} color="#3b82f6" /><span className="v num">{f1((d?.opponent_recovering ?? 0) * 100)}%</span></div>
      <h3>Buttons</h3>
      <div className="row"><span className="k">held now</span><span className="v">{b?.held?.length ? b.held.join(" + ") : "–"}{s?.action ? <small> · {s.action}{s.action_name ? ` (${s.action_name})` : ""}</small> : null}</span></div>
      <div className="row"><span className="k">total presses</span><span className="v">{b?.total ?? "–"} <small>jev {b?.by_source?.jev ?? 0} · reflex {b?.by_source?.reflex ?? 0}</small></span></div>
      <h3>Timing</h3>
      <div className="row"><span className="k">response time</span><span className="v">{f1(t?.response_ms_last)} ms <small>p50 {f1(t?.response_ms_p50)} ms</small></span></div>
      <div className="row"><span className="k">decision time <em>(estimated)</em></span><span className="v">{f1(t?.decision_ms_last_estimated)} ms <small>p50 {f1(t?.decision_ms_p50_estimated)} ms · round trip − {f1(t?.network_baseline_ms)} ms network</small></span></div>
      <div className="row"><span className="k">calls · stale discarded</span><span className="v">{t?.calls ?? "–"} · {t?.stale_discarded ?? "–"}{t?.discarded_on_control ? <small> · {t.discarded_on_control} discarded on pause/reset</small> : null}</span></div>
      <h3>Usage</h3>
      <div className="row"><span className="k">tokens in · out</span><span className="v">{u?.input_tokens ?? "–"} · {u?.output_tokens ?? "–"}</span></div>
      <div className="row"><span className="k">cost</span><span className="v">{usd(u?.cost_usd)}</span></div>
    </div>
  );
}
