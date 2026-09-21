"""WebSocket relay: frames as JPEG + telemetry as JSON (bead sam-e8s.4).

Runs in a background thread with its own asyncio loop. A FrameSource polls
/tmp/sam2/frame.meta for a new frame_seq, reads frame.raw (32-bit xRGB,
little-endian = BGRA bytes), JPEG-encodes it with Pillow and broadcasts it
as a binary message. `publish(telemetry)` broadcasts a JSON text message.
Clients: tools/view.html (test page), later the Tauri UI.

Dependencies: websockets, Pillow (bridge/requirements.txt).
"""
from __future__ import annotations

import asyncio
import io
import json
import os
import threading
import time
from typing import Any

from PIL import Image
import websockets

SAM2 = "/tmp/sam2"
FRAME_RAW = os.path.join(SAM2, "frame.raw")
FRAME_META = os.path.join(SAM2, "frame.meta")
HOST, PORT = "127.0.0.1", 8765
JPEG_QUALITY = 80


def read_meta(path: str = FRAME_META) -> tuple[int, int, int, int, int] | None:
    """(width, height, nbytes, emu_frame, frame_seq) or None."""
    try:
        parts = open(path).read().split()
        return int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
    except (FileNotFoundError, ValueError, IndexError):
        return None


def encode_jpeg(raw: bytes, w: int, h: int, quality: int = JPEG_QUALITY) -> bytes:
    if len(raw) != w * h * 4:
        raise ValueError(f"frame size {len(raw)} != {w}x{h}x4")
    img = Image.frombuffer("RGBA", (w, h), raw, "raw", "BGRA", 0, 1).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


class Relay:
    def __init__(self, host: str = HOST, port: int = PORT, poll_s: float = 0.004):
        self.host, self.port, self.poll_s = host, port, poll_s
        self.loop: asyncio.AbstractEventLoop | None = None
        self.clients: set = set()
        self.frames_sent = 0
        self.last_seq = -1
        self.encode_ms: list[float] = []
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self.ready = threading.Event()

    # ---- lifecycle
    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, name="relay", daemon=True)
        self._thread.start()
        self.ready.wait(5)

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(3)

    def _run(self) -> None:
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self._main())

    async def _main(self) -> None:
        async with websockets.serve(self._handler, self.host, self.port, max_size=None):
            self.ready.set()
            await self._frame_pump()

    async def _handler(self, ws) -> None:
        self.clients.add(ws)
        try:
            async for _ in ws:      # clients send nothing we act on
                pass
        finally:
            self.clients.discard(ws)

    # ---- broadcast
    async def _broadcast(self, msg) -> None:
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send(msg)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)

    def publish(self, telemetry: dict[str, Any]) -> None:
        """Thread-safe: schedule a JSON text broadcast."""
        if self.loop and self.clients:
            asyncio.run_coroutine_threadsafe(self._broadcast(json.dumps(telemetry, separators=(",", ":"))), self.loop)

    async def _frame_pump(self) -> None:
        while not self._stop.is_set():
            meta = read_meta()
            if meta and meta[4] != self.last_seq and self.clients:
                w, h, n, emu_frame, seq = meta
                try:
                    raw = open(FRAME_RAW, "rb").read()
                    if len(raw) == n:
                        t0 = time.perf_counter()
                        jpg = encode_jpeg(raw, w, h)
                        self.encode_ms.append((time.perf_counter() - t0) * 1000)
                        if len(self.encode_ms) > 300:
                            del self.encode_ms[:100]
                        self.last_seq = seq
                        self.frames_sent += 1
                        await self._broadcast(jpg)
                except (FileNotFoundError, ValueError):
                    pass
            await asyncio.sleep(self.poll_s)

    def stats(self) -> dict[str, Any]:
        e = sorted(self.encode_ms)
        return {"clients": len(self.clients), "frames_sent": self.frames_sent, "last_frame_seq": self.last_seq,
                "encode_ms_p50": e[len(e) // 2] if e else None, "encode_ms_max": e[-1] if e else None}
