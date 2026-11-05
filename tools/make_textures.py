"""Builds the PNG textures for the mod (rain drops, splashes, app icon).
Run: python3 tools/make_textures.py"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "mod")
random.seed(7)

def drops_atlas(path, size=1024, per_side=4):
    """4x4 atlas of thin rain streaks: a bright core, soft edges and a
    tapered head and tail, so drops read as fast-falling water."""
    cell = size // per_side
    alpha = np.zeros((size, size), np.float32)
    yy, xx = np.mgrid[0:cell, 0:cell].astype(np.float32)
    for cy in range(per_side):
        for cx in range(per_side):
            length = random.uniform(0.6, 0.95) * cell
            width = random.uniform(2.6, 4.2)
            x0 = cell / 2 + random.uniform(-cell * 0.15, cell * 0.15)
            top = (cell - length) / 2
            t = np.clip((yy - top) / length, 0, 1)
            inside = (yy >= top) & (yy <= top + length)
            # Tapered: thin at the top, fullest near the bottom (the drop head)
            w = width * (0.35 + 0.65 * t ** 0.7)
            core = np.exp(-((xx - x0) ** 2) / (2 * (w * 0.55) ** 2))
            along = np.clip(np.sin(np.pi * t), 0, 1) ** 0.6 * (0.55 + 0.45 * t)
            a = core * along * inside * random.uniform(0.75, 1.0)
            alpha[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = np.maximum(
                alpha[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell], a)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., 0] = 220
    rgba[..., 1] = 230
    rgba[..., 2] = 242
    rgba[..., 3] = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)

def splash_atlas(path, size=256, per_side=2):
    """2x2 atlas of splash rings, getting bigger and fainter."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cell = size // per_side
    for i in range(per_side * per_side):
        cx, cy = i % per_side, i // per_side
        layer = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        t = (i + 1) / (per_side * per_side)
        r = cell * (0.15 + 0.32 * t)
        a = int(220 * (1 - t * 0.7))
        c = cell / 2
        d.ellipse([c - r, c - r * 0.45, c + r, c + r * 0.45], outline=(230, 240, 250, a), width=3)
        for k in range(6):
            ang = k / 6 * 2 * math.pi + random.uniform(-0.3, 0.3)
            dx, dy = math.cos(ang) * r * 0.8, math.sin(ang) * r * 0.35 - r * 0.5 * (1 - t)
            d.ellipse([c + dx - 2, c + dy - 2, c + dx + 2, c + dy + 2], fill=(230, 240, 250, a))
        layer = layer.filter(ImageFilter.GaussianBlur(0.6))
        img.alpha_composite(layer, (cx * cell, cy * cell))
    img.save(path)

def droplet_normals(path, size=1024, count=900, rmin=3, rmax=11, runs=0, seed=1, color_path=None):
    """Tileable normal map of water beads (and optional short runs) for the
    detail-normal slot of car materials. Flat areas are (128,128,255)."""
    rng = np.random.default_rng(seed)
    h = np.zeros((size, size), np.float32)
    def bead(cx, cy, rx, ry):
        r = int(max(rx, ry)) + 2
        ys, xs = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float32)
        d = (xs / rx) ** 2 + (ys / ry) ** 2
        dome = np.sqrt(np.clip(1 - d, 0, 1)) * min(rx, ry)
        iy = (np.arange(-r, r + 1) + int(cy)) % size
        ix = (np.arange(-r, r + 1) + int(cx)) % size
        sub = h[np.ix_(iy, ix)]
        h[np.ix_(iy, ix)] = np.maximum(sub, dome)
    # Many small beads, fewer big ones
    for _ in range(count):
        r = rmin + (rmax - rmin) * rng.random() ** 2.2
        bead(rng.random() * size, rng.random() * size, r * rng.uniform(0.85, 1.15), r * rng.uniform(0.85, 1.2))
    # Runs: a big drop with a thin trail above it
    for _ in range(runs):
        x, y = rng.random() * size, rng.random() * size
        r = rng.uniform(rmax * 0.8, rmax * 1.3)
        bead(x, y, r, r * 1.15)
        trail = int(rng.uniform(40, 140))
        for k in range(0, trail, 2):
            bead(x + math.sin(k * 0.05) * 2, y - r - k, r * 0.32, r * 0.5)
    # Normals from the height field (wrapping, so the texture tiles)
    k = 1.6
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * k
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * k
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    img = ((n * 0.5 + 0.5) * 255).round().astype(np.uint8)
    Image.fromarray(img, "RGB").save(path)
    if color_path:
        # Colour detail: 50% grey is "no change"; beads get a bright highlight
        # on the upper left and a darker edge, like light through water
        light = np.array([-0.45, -0.55, 0.7]); light /= np.linalg.norm(light)
        spec = np.clip((n * light).sum(2), 0, 1) ** 24
        wet = h > 0.05
        edge = wet & (n[..., 2] < 0.75)
        g = np.full(h.shape, 128.0)
        g[edge] -= 26
        g += spec * 120 * wet
        g = np.clip(g, 0, 255).astype(np.uint8)
        Image.fromarray(np.dstack([g, g, g]), "RGB").save(color_path)

def splash_droplet(path, size=64):
    """A small, bright water droplet for the splash particles."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (size / 2)
    a = np.clip(1 - d, 0, 1) ** 1.5
    hl = np.exp(-(((xx - c * 0.75) ** 2 + (yy - c * 0.7) ** 2) / (2 * (size * 0.08) ** 2)))
    rgb = np.clip(200 + hl * 55, 0, 255)
    img = np.dstack([rgb * 0.93, rgb * 0.97, rgb, np.clip(a * 255, 0, 255)]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path)

def splash_ripple(path, size=256):
    """A thin ring for the ripples that spread on the ground."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (size / 2)
    ring = np.exp(-((d - 0.82) ** 2) / (2 * 0.035 ** 2))
    inner = np.exp(-((d - 0.55) ** 2) / (2 * 0.03 ** 2)) * 0.45
    a = np.clip(ring + inner, 0, 1) * (d < 1)
    img = np.dstack([np.full_like(a, 225), np.full_like(a, 235), np.full_like(a, 245), a * 255]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path)

def app_icon(path, size=128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([20, 22, 70, 62], fill=(200, 210, 225, 255))
    d.ellipse([48, 12, 108, 64], fill=(215, 225, 238, 255))
    d.rounded_rectangle([18, 40, 112, 68], 14, fill=(215, 225, 238, 255))
    for i, x in enumerate([34, 56, 78, 100]):
        y = 80 + (i % 2) * 12
        d.line([x, y, x - 8, y + 22], fill=(95, 176, 255, 255), width=6)
    img.save(path)

os.makedirs(os.path.join(ROOT, "art", "beamng_weather"), exist_ok=True)
drops_atlas(os.path.join(ROOT, "art", "beamng_weather", "rain_drops.png"))
splash_atlas(os.path.join(ROOT, "art", "beamng_weather", "rain_splash.png"))
art = os.path.join(ROOT, "art", "beamng_weather")
droplet_normals(os.path.join(art, "droplets_body_n.png"), count=1100, rmin=2.5, rmax=9, runs=0, seed=1,
                color_path=os.path.join(art, "droplets_body_d.png"))
droplet_normals(os.path.join(art, "droplets_glass_n.png"), count=650, rmin=3, rmax=14, runs=40, seed=2,
                color_path=os.path.join(art, "droplets_glass_d.png"))
splash_droplet(os.path.join(art, "splash_droplet.png"))
splash_ripple(os.path.join(art, "splash_ripple.png"))
app_icon(os.path.join(ROOT, "ui", "modules", "apps", "BeamNGWeatherRain", "app.png"))
print("textures written")
