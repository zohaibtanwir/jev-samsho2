#!/usr/bin/env python3
"""Convert /tmp/sam2/frame.raw (32-bit pixels from MAME's screen:pixels(),
host-endian, row-major) to a PNG. Uses Pillow if installed (it is on this
Mac: 10.4.0), else writes a PPM you can open with Preview.
    python3 tools/raw2png.py [frame.raw] [frame.meta] [out.png]
"""
import struct, sys, zlib

def main():
    raw_p = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sam2/frame.raw"
    meta_p = sys.argv[2] if len(sys.argv) > 2 else "/tmp/sam2/frame.meta"
    out_p = sys.argv[3] if len(sys.argv) > 3 else "/tmp/sam2/frame.png"
    w, h, n = (int(x) for x in open(meta_p).read().split())
    raw = open(raw_p, "rb").read()
    assert len(raw) == n == w * h * 4, (len(raw), n, w, h)
    # host-endian 32-bit: on Apple silicon little-endian, so bytes are B,G,R,A for an 0xAARRGGBB value
    px = struct.unpack("<%dI" % (w * h), raw)
    rgb = bytearray(w * h * 3)
    for i, v in enumerate(px):
        rgb[3 * i] = (v >> 16) & 0xFF; rgb[3 * i + 1] = (v >> 8) & 0xFF; rgb[3 * i + 2] = v & 0xFF
    try:
        from PIL import Image
        Image.frombytes("RGB", (w, h), bytes(rgb)).save(out_p)
        print(f"wrote {out_p} ({w}x{h}) with Pillow")
    except ImportError:
        ppm = out_p.rsplit(".", 1)[0] + ".ppm"
        with open(ppm, "wb") as f:
            f.write(b"P6\n%d %d\n255\n" % (w, h)); f.write(bytes(rgb))
        print(f"Pillow not installed; wrote {ppm}")

if __name__ == "__main__":
    main()
