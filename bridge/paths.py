"""Where the Lua <-> bridge exchange files live (bead sam-yku.11).

The emulator thread writes state.json every other frame and reads action.json
every frame; on APFS those writes stalled MAME for 10-17 ms at a time, which
showed up as seconds below 99% speed. They go on a RAM disk when one is
mounted. Logs stay in /tmp/sam2: they are append-and-flush, off the hot path.

    SAM2_DIR   exchange files (state/action/control/frames). Default:
               /Volumes/sam2ram if mounted, else /tmp/sam2.
    SAM2_LOGS  logs and PID files. Default /tmp/sam2.

Create the RAM disk with tools/ramdisk.sh (optional; everything works without).
"""
import os
import subprocess

LOGS = os.environ.get("SAM2_LOGS") or "/tmp/sam2"
RAMDISK = "/Volumes/sam2ram"
DIR = os.environ.get("SAM2_DIR") or (RAMDISK if os.path.isdir(RAMDISK) else LOGS)

os.makedirs(LOGS, exist_ok=True)
os.makedirs(DIR, exist_ok=True)

_mounted_by_us = False


def _refresh() -> None:
    """Recompute the exchange paths after DIR may have changed."""
    g = globals()
    g["DIR"] = os.environ.get("SAM2_DIR") or (RAMDISK if os.path.isdir(RAMDISK) else LOGS)
    os.makedirs(g["DIR"], exist_ok=True)
    for name, f in (("STATE", "state.json"), ("ACTION", "action.json"), ("ACTION_TMP", "action.tmp"),
                    ("CONTROL", "control.json"), ("CONTROL_TMP", "control.tmp"), ("CMD", "cmd.json"),
                    ("FRAME_RAW", "frame.raw"), ("FRAME_META", "frame.meta")):
        g[name] = os.path.join(g["DIR"], f)


def _quiet_volume(d: str) -> str:
    """Keep Spotlight and FSEvents off our scratch volume.

    We create and rename files ~100 times a second and write 8.6 MB/s of
    frames; with indexing on, the volume occasionally blocked for ~1 s, which
    the emulator thread felt as a long action.json read (bead sam-yku.11).
    `.metadata_never_index` and `.fseventsd/no_log` are honoured without sudo.
    """
    out = []
    try:
        open(os.path.join(d, ".metadata_never_index"), "w").close()
        os.makedirs(os.path.join(d, ".fseventsd"), exist_ok=True)
        open(os.path.join(d, ".fseventsd", "no_log"), "w").close()
        out.append("indexing off")
    except Exception as e:
        out.append(f"indexing flags failed: {e}")
    try:    # best effort; needs no sudo for a user-mounted volume in most setups
        r = subprocess.run(["mdutil", "-i", "off", d], capture_output=True, text=True, timeout=10)
        out.append("mdutil off" if r.returncode == 0 else "mdutil declined")
    except Exception:
        out.append("mdutil unavailable")
    return ", ".join(out)


def _usable(d: str) -> tuple[bool, str]:
    """Can we actually write and read back in this directory? A RAM disk under
    /Volumes can be invisible to a process spawned by a GUI app (TCC treats it
    as a removable volume), and the failure looks like 'file not found'."""
    probe = os.path.join(d, ".sam2_probe")
    try:
        with open(probe, "w") as f:
            f.write("ok")
        with open(probe) as f:
            back = f.read()
        os.remove(probe)
        return (back == "ok"), "ok" if back == "ok" else f"read back {back!r}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


def ensure_ramdisk(size_mb: int = 64) -> str:
    """Mount the RAM disk if it is absent, unless SAM2_DIR or SAM2_NO_RAMDISK say otherwise.

    Why: reading action.json from APFS stalled the emulator thread for up to
    123 ms, costing a whole second of emulation (bead sam-yku.11). It is a
    plain user-level `hdiutil attach` + `diskutil eraseVolume`; release()
    unmounts it again when we were the ones who mounted it.
    """
    global _mounted_by_us
    if os.environ.get("SAM2_DIR") or os.environ.get("SAM2_NO_RAMDISK"):
        return f"ram disk skipped (env); exchange dir {DIR}"
    if os.path.isdir(RAMDISK):
        _refresh()
        quiet = _quiet_volume(RAMDISK)
        ok, why = _usable(RAMDISK)
        if ok:
            return f"ram disk already mounted at {RAMDISK}; {quiet}; exchange dir {DIR}"
        os.environ["SAM2_DIR"] = LOGS          # children (MAME) must agree with us
        _refresh()
        return f"ram disk at {RAMDISK} not usable by this process ({why}); exchange dir {DIR} (expect occasional speed dips)"
    try:
        dev = subprocess.run(["hdiutil", "attach", "-nomount", f"ram://{size_mb * 2048}"],
                             capture_output=True, text=True, timeout=20, check=True).stdout.split()[0]
        subprocess.run(["diskutil", "eraseVolume", "HFS+", "sam2ram", dev],
                       capture_output=True, text=True, timeout=40, check=True)
        _mounted_by_us = True
        _refresh()
        quiet = _quiet_volume(RAMDISK)
        ok, why = _usable(RAMDISK)
        if not ok:
            os.environ["SAM2_DIR"] = LOGS      # children (MAME) must agree with us
            _refresh()
            return f"ram disk mounted at {RAMDISK} ({dev}) but not usable by this process ({why}); exchange dir {DIR}"
        return f"ram disk mounted at {RAMDISK} ({dev}); {quiet}; exchange dir {DIR}"
    except Exception as e:
        _refresh()
        return f"ram disk unavailable ({type(e).__name__}); exchange dir {DIR} (expect occasional speed dips)"


def release() -> str:
    """Unmount the RAM disk if this process mounted it."""
    global _mounted_by_us
    if not _mounted_by_us:
        return "ram disk left as found"
    try:
        subprocess.run(["diskutil", "unmount", RAMDISK], capture_output=True, text=True, timeout=20)
        _mounted_by_us = False
        return f"ram disk unmounted ({RAMDISK})"
    except Exception as e:
        return f"ram disk unmount failed: {e}"


STATE = os.path.join(DIR, "state.json")
ACTION = os.path.join(DIR, "action.json")
ACTION_TMP = os.path.join(DIR, "action.tmp")
CONTROL = os.path.join(DIR, "control.json")
CONTROL_TMP = os.path.join(DIR, "control.tmp")
CMD = os.path.join(DIR, "cmd.json")
FRAME_RAW = os.path.join(DIR, "frame.raw")
FRAME_META = os.path.join(DIR, "frame.meta")

BRIDGE_LOG = os.path.join(LOGS, "bridge.log")
PIDS = os.path.join(LOGS, "pids")
MAME_LOG = os.path.join(LOGS, "mame.log")
