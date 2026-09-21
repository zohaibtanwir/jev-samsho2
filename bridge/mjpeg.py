"""MJPEG stream for the app's game view (bead sam-yku.10).

GET http://127.0.0.1:8766/stream returns multipart/x-mixed-replace; each
part is the newest JPEG the relay encoded. A WKWebView <img> renders this
natively, with no JavaScript per frame. Each client connection counts the
frames it was sent in the last second (`fps`), which the telemetry reports
as the view fps. Stdlib only.
"""
from __future__ import annotations

import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", 8766
BOUNDARY = b"sam2frame"


class FrameBus:
    def __init__(self):
        self.cond = threading.Condition()
        self.seq = 0
        self.jpg: bytes | None = None
        self.clients: dict[int, deque] = {}     # client id -> timestamps of frames sent in the last second
        self._next_id = 1
        self.lock = threading.Lock()

    def publish(self, jpg: bytes) -> None:
        with self.cond:
            self.jpg, self.seq = jpg, self.seq + 1
            self.cond.notify_all()

    def wait_newer(self, seq: int, timeout: float = 1.0):
        with self.cond:
            if self.seq == seq:
                self.cond.wait(timeout)
            return self.seq, self.jpg

    def register(self) -> int:
        with self.lock:
            cid = self._next_id; self._next_id += 1
            self.clients[cid] = deque()
            return cid

    def unregister(self, cid: int) -> None:
        with self.lock:
            self.clients.pop(cid, None)

    def sent(self, cid: int) -> None:
        now = time.monotonic()
        with self.lock:
            d = self.clients.get(cid)
            if d is None:
                return
            d.append(now)
            while d and d[0] < now - 1.0:
                d.popleft()

    def stats(self) -> dict:
        now = time.monotonic()
        with self.lock:
            fps = {cid: sum(1 for t in d if t >= now - 1.0) for cid, d in self.clients.items()}
        return {"clients": len(fps), "fps_per_client": fps, "fps": max(fps.values()) if fps else 0, "frames_published": self.seq}


BUS = FrameBus()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):   # quiet
        pass

    def do_GET(self):
        if self.path.split("?")[0] != "/stream":
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
        cid = BUS.register()
        from bridge.qos import set_interactive
        set_interactive()                       # this handler thread streams frames: keep it responsive
        try:
            self.send_response(200)
            self.send_header("Content-Type", f"multipart/x-mixed-replace; boundary={BOUNDARY.decode()}")
            self.send_header("Cache-Control", "no-cache, no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            seq = -1
            while True:
                seq, jpg = BUS.wait_newer(seq)
                if jpg is None:
                    continue
                self.wfile.write(b"--" + BOUNDARY + b"\r\nContent-Type: image/jpeg\r\nContent-Length: " + str(len(jpg)).encode() + b"\r\n\r\n" + jpg + b"\r\n")
                self.wfile.flush()
                BUS.sent(cid)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            BUS.unregister(cid)


def serve(host: str = HOST, port: int = PORT) -> ThreadingHTTPServer:
    srv = ThreadingHTTPServer((host, port), Handler)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, name="mjpeg", daemon=True).start()
    return srv
