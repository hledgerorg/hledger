#!/usr/bin/env python3
"""Generate hledger-web/config/favicon.ico from one of the marks in config/.

The .svg files beside the .ico are the source of truth; this reproduces their
geometry and rasterises it, because the .ico has to be a raster format and no
image library is assumed to be installed. Standard library only.

  tools/mkfavicon.py          # the shipped mark: coin struck with an equals sign
  tools/mkfavicon.py h        # the alternative: coin struck with a lowercase h
  tools/mkfavicon.py = out.ico

Coverage is computed by 4x4 supersampling, so edges are antialiased. The three
sizes a browser asks for (16, 32, 48) are PNG-compressed inside the ICO
container, which keeps all three near 1.2 kB; the uncompressed BMP form would be
about 15 kB, embedded in every binary. Every browser released this century
reads PNG-in-ICO.
"""
import math, os, struct, sys, zlib

RIM, FACE, DEVICE = (0xD8, 0x7E, 0x12), (0xF4, 0xB5, 0x19), (0x7A, 0x44, 0x06)
SS = 4  # subsamples per axis

# --- geometry, in the 32x32 unit space of the svgs ---------------------------

def circle(x, y, cx, cy, r):
    return (x - cx)**2 + (y - cy)**2 <= r*r

def rrect(x, y, x0, y0, x1, y1, r):
    if not (x0 <= x <= x1 and y0 <= y <= y1): return False
    qx, qy = min(max(x, x0 + r), x1 - r), min(max(y, y0 + r), y1 - r)
    return (x - qx)**2 + (y - qy)**2 <= r*r + 1e-9

def capsule(x, y, x0, y0, x1, y1, r):
    """A stroked segment with round caps: distance to the segment <= r."""
    dx, dy = x1 - x0, y1 - y0
    L2 = dx*dx + dy*dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((x - x0)*dx + (y - y0)*dy) / L2))
    return (x - (x0 + t*dx))**2 + (y - (y0 + t*dy))**2 <= r*r

def upper_arc(x, y, cx, cy, r, half):
    """The top half of a stroked circular arc of radius r, stroke half-width."""
    if y > cy: return False
    d = math.hypot(x - cx, y - cy)
    return r - half <= d <= r + half

def equals(x, y):
    if rrect(x, y, 8.2, 10.2, 23.8, 14.4, 1.6): return DEVICE
    if rrect(x, y, 8.2, 17.6, 23.8, 21.8, 1.6): return DEVICE
    return None

def aitch(x, y):
    # M11 7.5 V25 M11 17.8 A5.2 5.2 0 0 1 21.4 17.8 V25, stroke-width 4.1
    if capsule(x, y, 11, 7.5, 11, 25, 2.05): return DEVICE
    if capsule(x, y, 21.4, 17.8, 21.4, 25, 2.05): return DEVICE
    if upper_arc(x, y, 16.2, 17.8, 5.2, 2.05): return DEVICE
    return None

MARKS = {"=": equals, "equals": equals, "h": aitch}

def shade(device, x, y):
    c = device(x, y)
    if c: return c
    if circle(x, y, 16, 16, 12.6): return FACE
    if circle(x, y, 16, 16, 15.5): return RIM
    return None

# --- raster, png, ico --------------------------------------------------------

def render(device, size):
    rows, step = [], 32.0 / (size * SS)
    for py in range(size):
        row = []
        for px in range(size):
            sr = sg = sb = n = 0
            for sy in range(SS):
                for sx in range(SS):
                    c = shade(device, (px*SS + sx + 0.5) * step, (py*SS + sy + 0.5) * step)
                    if c:
                        sr += c[0]; sg += c[1]; sb += c[2]; n += 1
            row.append((0,0,0,0) if n == 0 else (sr//n, sg//n, sb//n, (n*255)//(SS*SS)))
        rows.append(row)
    return rows

def png(rows):
    size = len(rows)
    raw = b"".join(b"\x00" + bytes(v for px in r for v in px) for r in rows)
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))

def ico(sizes, payloads):
    out, off = struct.pack("<HHH", 0, 1, len(sizes)), 6 + 16*len(sizes)
    for s, p in zip(sizes, payloads):
        out += struct.pack("<BBBBHHII", s & 0xFF, s & 0xFF, 0, 0, 1, 32, len(p), off)
        off += len(p)
    return out + b"".join(payloads)

def main(argv):
    name = argv[1] if len(argv) > 1 else "="
    if name not in MARKS:
        sys.exit("unknown mark %r; choose one of: %s" % (name, ", ".join(sorted(MARKS))))
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(here, os.pardir, "hledger-web", "config", "favicon.ico")
    dest = argv[2] if len(argv) > 2 else os.path.normpath(default)
    sizes = [16, 32, 48]
    open(dest, "wb").write(ico(sizes, [png(render(MARKS[name], s)) for s in sizes]))
    print("wrote %s (%s, %d bytes)" % (dest, name, os.path.getsize(dest)))

if __name__ == "__main__":
    main(sys.argv)
