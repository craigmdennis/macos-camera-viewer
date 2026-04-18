#!/usr/bin/env python3
"""Generate CameraViewer.icns from a programmatic icon design."""

import math
import os
import shutil
import subprocess
import sys
from PIL import Image, ImageDraw

SIZES = [16, 32, 64, 128, 256, 512, 1024]

def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size

    # Corner radius: ~22% of size (matches macOS icon spec)
    r = round(s * 0.225)

    # Background: deep navy/slate
    bg = (18, 22, 34, 255)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=bg)

    cx, cy = s / 2, s / 2

    # Outer lens ring (subtle lighter ring)
    lens_r = s * 0.30
    ring_w = max(1, round(s * 0.025))
    d.ellipse(
        [cx - lens_r, cy - lens_r, cx + lens_r, cy + lens_r],
        outline=(80, 120, 200, 200),
        width=ring_w,
    )

    # Mid lens ring
    mid_r = s * 0.21
    d.ellipse(
        [cx - mid_r, cy - mid_r, cx + mid_r, cy + mid_r],
        outline=(60, 100, 180, 160),
        width=ring_w,
    )

    # Lens fill: dark glass
    inner_r = s * 0.155
    d.ellipse(
        [cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r],
        fill=(30, 50, 100, 255),
    )

    # Iris segments (6 blades)
    iris_r = s * 0.155
    blade_count = 6
    blade_w = max(1, round(s * 0.018))
    for i in range(blade_count):
        angle = math.radians(i * 60)
        x1 = cx + math.cos(angle) * iris_r * 0.35
        y1 = cy + math.sin(angle) * iris_r * 0.35
        x2 = cx + math.cos(angle) * iris_r * 0.92
        y2 = cy + math.sin(angle) * iris_r * 0.92
        d.line([x1, y1, x2, y2], fill=(90, 140, 230, 180), width=blade_w)

    # Catchlight (specular highlight top-left of lens)
    hl_r = inner_r * 0.28
    hl_cx = cx - inner_r * 0.38
    hl_cy = cy - inner_r * 0.38
    d.ellipse(
        [hl_cx - hl_r, hl_cy - hl_r, hl_cx + hl_r, hl_cy + hl_r],
        fill=(200, 220, 255, 120),
    )

    # PIP corner indicator: small rounded rect bottom-right
    pip_margin = round(s * 0.08)
    pip_w = round(s * 0.22)
    pip_h = round(s * 0.14)
    pip_r = max(2, round(s * 0.03))
    pip_x = s - pip_margin - pip_w
    pip_y = s - pip_margin - pip_h
    d.rounded_rectangle(
        [pip_x, pip_y, pip_x + pip_w, pip_y + pip_h],
        radius=pip_r,
        fill=(60, 100, 200, 200),
        outline=(100, 150, 255, 220),
        width=max(1, round(s * 0.012)),
    )

    return img


def build_iconset(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for size in SIZES:
        img = draw_icon(size)
        img.save(os.path.join(out_dir, f"icon_{size}x{size}.png"))
        if size <= 512:
            img2x = draw_icon(size * 2)
            img2x.save(os.path.join(out_dir, f"icon_{size}x{size}@2x.png"))


def main() -> None:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    iconset_tmp = os.path.join(repo, "CameraViewer.iconset")
    icns_out = os.path.join(repo, "CameraViewer", "AppIcon.icns")

    if os.path.exists(iconset_tmp):
        shutil.rmtree(iconset_tmp)
    build_iconset(iconset_tmp)

    subprocess.run(
        ["iconutil", "-c", "icns", iconset_tmp, "-o", icns_out], check=True
    )
    shutil.rmtree(iconset_tmp)
    print(f"Icon written to {icns_out}")


if __name__ == "__main__":
    main()
