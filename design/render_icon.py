"""Render the mndict launcher icon (concept A, Aurora Orb) as PNG assets.

All artwork is generated from radial/linear gradient math — no sourced imagery.
Outputs (1024px supersampled 2x):
  app/app_icon.png                       full-bleed square (iOS + legacy Android)
  app/assets/icon/ic_adaptive_bg.png     aurora field, full bleed
  app/assets/icon/ic_adaptive_fg.png     orb on transparency, inside the
                                         adaptive-icon safe zone (~66%)
"""
import numpy as np
from PIL import Image
from pathlib import Path

S = 2048  # supersampled canvas
OUT = [
    (Path(__file__).parent.parent / "app" / "app_icon.png", "full"),
    (Path(__file__).parent.parent / "app" / "assets" / "icon" / "ic_adaptive_bg.png", "bg"),
    (Path(__file__).parent.parent / "app" / "assets" / "icon" / "ic_adaptive_fg.png", "fg"),
]

yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
u, v = xx / S, yy / S  # normalized 0..1

def hexc(h, a=1.0):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], np.float64), a

def linear(c0, c1):
    t = (u + v) / 2.0
    return c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]

def blob(img, cx, cy, r, color, opacity):
    """Additive-ish soft radial blob (gaussian falloff), alpha-composited over img."""
    d2 = ((u - cx) ** 2 + (v - cy) ** 2) / (r * r)
    m = np.exp(-d2 * 2.2) * opacity
    m = m[..., None]
    return img * (1 - m) + color * m

def radial(cx, cy, r, stops, alpha=None):
    """Radial gradient sampled with highlight offset inside the disc."""
    sx, sy = cx + (0.5 - cx) * 0.28, cy + (0.5 - cy) * 0.28  # highlight bias
    d = np.sqrt(((u - sx) / (r * 1.18)) ** 2 + ((v - sy) / (r * 1.18)) ** 2)
    d = np.clip(d, 0, 1)
    pos = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops])
    out = np.zeros((S, S, 3))
    for i in range(len(stops) - 1):
        m = (d >= pos[i]) & (d <= pos[i + 1])
        t = np.zeros_like(d)
        span = pos[i + 1] - pos[i]
        if span > 0:
            t[m] = (d[m] - pos[i]) / span
        out[m] = cols[i] * (1 - t[m, None]) + cols[i + 1] * t[m, None]
    a = np.ones((S, S)) if alpha is None else np.clip(alpha, 0, 1)
    return out, a

C = hexc

# ---------- aurora background (full icon + adaptive bg layer) ----------
_, a_blue = C("#9DB8FF")
_, a_orch = C("#E3B4F2")
_, a_teal = C("#96E6D3")
bg = linear(*[C("#E9EEFB")[0], C("#F5EFFA")[0]])
bg = blob(bg, 0.24, 0.20, 0.36, C("#9DB8FF")[0], 0.85)
bg = blob(bg, 0.84, 0.42, 0.32, C("#E3B4F2")[0], 0.75)
bg = blob(bg, 0.38, 0.88, 0.34, C("#96E6D3")[0], 0.65)

# ---------- orb ----------
def orb_layer(r):
    """Orb composited onto transparency: returns rgb, alpha.

    Two-tone like the in-app AuroraOrb: a violet base lit from the top-left
    with a magenta counter-light rising from the bottom right."""
    d = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2)
    disc = (d <= r).astype(np.float64)
    edge = np.clip((r - d) * S / 2.0, 0, 1)  # ~2px antialiased edge

    # violet base, lit from a highlight point offset toward the top-left
    stops = [
        (0.00, C("#CFC9FF")[0]),
        (0.38, C("#9D8FF2")[0]),
        (0.72, C("#7868E8")[0]),
        (1.00, C("#5A4ACD")[0]),
    ]
    hx, hy = 0.5 - r * 0.45, 0.5 - r * 0.52
    dhl = np.sqrt(((u - hx) / (r * 2.1)) ** 2 + ((v - hy) / (r * 2.1)) ** 2)
    dhl = np.clip(dhl, 0, 1)
    rgb = np.zeros((S, S, 3))
    pos = np.array([q for q, _ in stops])
    cols = np.array([c for _, c in stops])
    for i in range(len(stops) - 1):
        m = (dhl >= pos[i]) & (dhl <= pos[i + 1])
        t = np.zeros_like(dhl)
        span = pos[i + 1] - pos[i]
        if span > 0:
            t[m] = (dhl[m] - pos[i]) / span
        rgb[m] = cols[i] * (1 - t[m, None]) + cols[i + 1] * t[m, None]
    a = np.ones((S, S))

    # magenta counter-light from bottom-right inside the disc
    md = np.sqrt(((u - 0.66) / (r * 1.25)) ** 2 + ((v - 0.68) / (r * 1.25)) ** 2)
    mmag = np.clip(1 - md, 0, 1) ** 1.6 * 0.55
    mrgb = C("#E0A6E8")[0]
    rgb = rgb * (1 - mmag[..., None]) + mrgb * mmag[..., None]

    a = a * disc * edge

    # outer glow: violet halo strictly OUTSIDE the disc
    g = np.exp(-(d ** 2) / (r * 0.9) ** 2 * 1.6) * 0.40 * (1 - disc)
    rgb_g = C("#8B7FF0")[0]
    out_a = np.clip(a + g, 0, 1)
    out_rgb = (rgb * a[..., None] + rgb_g * g[..., None]) / np.maximum(out_a[..., None], 1e-6)

    # specular: soft white ellipse near the highlight
    sp = np.exp(-(((u - 0.405) / 0.095) ** 2 + ((v - 0.325) / 0.058) ** 2)) * 0.66 * disc
    out_rgb = out_rgb * (1 - sp[..., None]) + np.array([255.0, 255.0, 255.0]) * sp[..., None]
    return out_rgb, out_a

orb_r_full = 0.30   # diameter 60% of the tile
orb_r_fg = 0.265    # diameter 53% — inside the 66% adaptive safe zone

for path, kind in OUT:
    path.parent.mkdir(parents=True, exist_ok=True)
    if kind == "bg":
        img = bg.copy()
        alpha = np.ones((S, S))
    elif kind == "fg":
        rgb, alpha = orb_layer(orb_r_fg)
        img = rgb
    else:  # full
        img = bg.copy()
        # grounding shadow under the orb
        sh = np.exp(-(((u - 0.5) / 0.23) ** 2 + ((v - 0.79) / 0.055) ** 2)) * 0.12
        img = img * (1 - sh[..., None]) + C("#17203D")[0] * sh[..., None]
        orb_rgb, orb_a = orb_layer(orb_r_full)
        img = img * (1 - orb_a[..., None]) + orb_rgb * orb_a[..., None]
        alpha = np.ones((S, S))
    out = np.dstack([np.clip(img, 0, 255).astype(np.uint8),
                     np.clip(alpha * 255, 0, 255).astype(np.uint8)])
    im = Image.fromarray(out, "RGBA")
    im = im.resize((1024, 1024), Image.LANCZOS)
    im.save(path)
    print("wrote", path)
