#!/usr/bin/env python3
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
"""Render upstream pager braille logo (logo07.txt) as iOS AppIcon."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / "ios/GrokApp/GrokApp/Resources/logo07.txt"
OUT = ROOT / "ios/GrokApp/GrokApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
BG = (20, 20, 20)  # #141414 groknight bg_base
FG = (232, 232, 232)


def main() -> int:
    text = LOGO.read_text(encoding="utf-8").strip("\n")
    img = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)
    font_size = 72
    font = None
    for name in ("Menlo.ttc", "SFMono-Regular.otf", "Courier New.ttf"):
        try:
            font = ImageFont.truetype(name, font_size)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    lines = text.split("\n")
    # Measure block
    line_heights = []
    max_w = 0
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        max_w = max(max_w, w)
        line_heights.append(h)
    total_h = sum(line_heights) + (len(lines) - 1) * 4
    x0 = (SIZE - max_w) // 2
    y0 = (SIZE - total_h) // 2
    y = y0
    for i, line in enumerate(lines):
        bbox = draw.textbbox((0, 0), line, font=font)
        w = bbox[2] - bbox[0]
        x = x0 + (max_w - w) // 2
        draw.text((x, y), line, font=font, fill=FG)
        y += line_heights[i] + 4

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, format="PNG")
    print(f"OK: wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
