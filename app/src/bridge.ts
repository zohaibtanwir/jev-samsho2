// Talks to the Tauri side (process control) and to the bridge's WebSocket
// (frames, telemetry, control commands). Shared by App and the panel.
import { invoke } from "@tauri-apps/api/core";

export type Status = { running: boolean; pid: number | null; repo: string };
export const WS_URL = "ws://127.0.0.1:8765";

export const startBridge = (windowed = false) => invoke<Status>("start_bridge", { windowed });
export const stopBridge = (timeoutS = 8) => invoke<string>("stop_bridge", { timeoutS });
export const bridgeStatus = () => invoke<Status>("bridge_status");

export type Telemetry = { type: "telemetry"; wall: number; state: any; panel: any; paused: boolean; phase: string; jev: any; loop: string; relay: any };

/** Persistent WebSocket with reconnect. onFrame gets JPEG blobs, onTelemetry parsed JSON. */
export class BridgeSocket {
  private ws: WebSocket | null = null;
  private closed = false;
  connected = false;
  constructor(private onFrame: (b: Blob) => void, private onTelemetry: (t: Telemetry) => void, private onState?: (c: boolean) => void) {}
  open() {
    this.closed = false;
    const ws = new WebSocket(WS_URL);
    ws.binaryType = "blob";
    ws.onopen = () => { this.connected = true; this.onState?.(true); };
    ws.onclose = () => { this.connected = false; this.onState?.(false); if (!this.closed) setTimeout(() => this.open(), 1000); };
    ws.onmessage = (e) => { if (typeof e.data === "string") this.onTelemetry(JSON.parse(e.data)); else this.onFrame(e.data); };
    this.ws = ws;
  }
  send(cmd: "pause" | "resume" | "reset" | "stop") {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) { this.ws.send(JSON.stringify({ cmd })); return true; }
    return false;
  }
  close() { this.closed = true; this.ws?.close(); }
}
