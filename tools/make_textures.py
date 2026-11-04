"""Builds the PNG textures for the mod (rain drops, splashes, app icon).
Run: python3 tools/make_textures.py"""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "mod")
random.seed(7)

def drops_atlas(path, size=512, per_side=4):
    """4x4 atlas of thin, motion-blurred rain streaks (white, alpha)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cell = size // per_side
    for cy in range(per_side):
        for cx in range(per_side):
            layer = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            w = random.uniform(1.5, 3.0)
            length = random.uniform(0.55, 0.9) * cell
            x = cell / 2 + random.uniform(-4, 4)
            top = (cell - length) / 2
            steps = 40
            for i in range(steps):
                t = i / (steps - 1)
                a = int(200 * math.sin(t * math.pi) ** 0.8)
                y = top + t * length
                d.ellipse([x - w, y - w, x + w, y + w], fill=(225, 235, 245, a))
            layer = layer.filter(ImageFilter.GaussianBlur(0.8))
            img.alpha_composite(layer, (cx * cell, cy * cell))
    img.save(path)

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
app_icon(os.path.join(ROOT, "ui", "modules", "apps", "BeamNGWeatherRain", "app.png"))
print("textures written")
