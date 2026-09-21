"""macOS thread QoS (bead sam-yku.10). Processes spawned by a GUI app, and
threads created inside them, start in a low scheduling class; that made MAME
(our child) and the MJPEG writer stall. Call set_interactive() at the top of
every thread we care about, and once in main before spawning MAME."""
import sys

QOS_CLASS_USER_INTERACTIVE = 0x21


def set_interactive() -> str:
    if sys.platform != "darwin":
        return "n/a"
    try:
        import ctypes
        lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        rc = lib.pthread_set_qos_class_self_np(ctypes.c_uint(QOS_CLASS_USER_INTERACTIVE), ctypes.c_int(0))
        return f"qos user-interactive rc={rc}"
    except Exception as e:      # never fatal
        return f"qos failed: {e}"
