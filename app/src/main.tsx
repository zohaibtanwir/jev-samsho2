import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

/** Never leave a blank window: show the error and a Reload button. Cmd-R reloads too. */
class ErrorBoundary extends React.Component<{ children: React.ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) { return { error }; }
  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: 24, color: "#e6e6e6", background: "#101114", height: "100vh", font: "14px -apple-system, sans-serif" }}>
          <h2>UI error</h2>
          <pre style={{ whiteSpace: "pre-wrap", color: "#f59e0b" }}>{String(this.state.error?.message || this.state.error)}</pre>
          <button onClick={() => location.reload()} style={{ padding: "8px 18px" }}>Reload UI</button>
          <p style={{ color: "#8a8f98" }}>The bridge and MAME keep running; reloading the UI does not touch them.</p>
        </div>
      );
    }
    return this.props.children;
  }
}
window.addEventListener("keydown", (e) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "r") { e.preventDefault(); location.reload(); } });

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode><ErrorBoundary><App /></ErrorBoundary></React.StrictMode>,
);
