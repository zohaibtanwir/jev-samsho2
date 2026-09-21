import { useEffect, useRef, useState } from "react";

/** Draws JPEG blobs on a 320x224 canvas at up to the arrival rate (30 fps);
 *  drops frames rather than queueing them (sam-yku.5). Decodes through an
 *  HTMLImageElement + object URL, which is cheap in WebKit (WKWebView); at
 *  most one decode in flight, a second arrival while busy replaces the
 *  pending one (newest wins), older ones are counted as dropped. */
export function useFrameSink() {
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const busy = useRef(false);
  const pending = useRef<Blob | null>(null);
  const times = useRef<number[]>([]);
  const dropped = useRef(0);
  const img = useRef<HTMLImageElement | null>(null);
  const count = useRef(0);
  const [fps, setFps] = useState(0);
  const [frames, setFrames] = useState(0);

  const draw = (blob: Blob) => {
    busy.current = true;
    const el = img.current ?? (img.current = new Image());
    const url = URL.createObjectURL(blob);
    el.onload = () => {
      const c = canvas.current; if (c) c.getContext("2d")!.drawImage(el, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url);
      const now = performance.now(); const t = times.current; t.push(now); while (t.length && t[0] < now - 1000) t.shift();
      count.current += 1;                       // no React state per frame: flushed 4x per second below
      busy.current = false;
      const next = pending.current; pending.current = null;
      if (next) draw(next);
    };
    el.onerror = () => { URL.revokeObjectURL(url); busy.current = false; };
    el.src = url;
  };
  const onFrame = (blob: Blob) => {
    if (busy.current) { if (pending.current) dropped.current++; pending.current = blob; return; }
    draw(blob);
  };
  useEffect(() => { const id = setInterval(() => { const now = performance.now(); const t = times.current; while (t.length && t[0] < now - 1000) t.shift(); setFps(t.length); setFrames(count.current); }, 250); return () => clearInterval(id); }, []);
  return { canvas, onFrame, fps, frames, dropped };
}
