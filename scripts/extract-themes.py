#!/usr/bin/env python3
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

"""Extract pager theme palettes from upstream Rust theme sources.

Reads xai-grok-pager-render/src/theme/*.rs and writes shared/themes/*.json
with semantic token names matching Theme::{groknight,grokday,...} fields.

Upstream pin: upstream-grok-build @ SOURCE_REV in PLAN.md (read-only).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_SRC = (
    ROOT
    / "upstream-grok-build"
    / "crates"
    / "codegen"
    / "xai-grok-pager-render"
    / "src"
    / "theme"
)
OUT_DIR = ROOT / "shared" / "themes"

# Rust source file -> (constructor fn name, output stem, display metadata)
THEME_FILES: list[tuple[str, str, str, list[str], bool]] = [
    ("groknight.rs", "groknight", "groknight", ["grok-night", "dark"], False),
    ("grokday.rs", "grokday", "grokday", ["grok-day", "light", "day"], False),
    ("tokyonight.rs", "tokyonight", "tokyonight", ["tokyo-night", "tokyo"], True),
    ("rosepine.rs", "rosepine_moon", "rosepine-moon", [
        "rosepine", "rose-pine", "rosepine-moon", "rose-pine-moon",
    ], True),
    ("oscura.rs", "oscura_midnight", "oscura-midnight", ["oscura", "oscura-midnight"], True),
]

AUTO_META = {
    "name": "auto",
    "display_name": "auto",
    "aliases": ["system"],
    "requires_truecolor": False,
    "resolved_dark": "groknight",
    "resolved_light": "grokday",
    "tokens": {},
    "note": "Meta-variant: follows system appearance; colors resolved at runtime per 06-theming.md",
}

RGB_CONST_RE = re.compile(
    r"pub\s+const\s+(\w+):\s*Color\s*=\s*rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
    r"(?:\s*;\s*(?://|#).*?#([0-9a-fA-F]{6}))?",
)
RGB_INLINE_RE = re.compile(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)")
COLOR_RGB_RE = re.compile(
    r"Color::Rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
)
HEX_COMMENT_RE = re.compile(r"#([0-9a-fA-F]{6})")
FN_RE = re.compile(r"pub\s+const\s+fn\s+(\w+)\s*\(\s*\)\s*->\s*Self\s*\{", re.MULTILINE)


def rgb_to_hex(r: int, g: int, b: int) -> str:
    return f"#{r:02x}{g:02x}{b:02x}"


def parse_palette(source: str) -> dict[str, str]:
    """Map palette const names to lowercase hex from rgb() definitions."""
    palette: dict[str, str] = {}
    for match in RGB_CONST_RE.finditer(source):
        name, r, g, b, hex_from_comment = match.groups()
        if hex_from_comment:
            palette[name] = f"#{hex_from_comment.lower()}"
        else:
            palette[name] = rgb_to_hex(int(r), int(g), int(b))
    return palette


def resolve_color_expr(expr: str, palette: dict[str, str]) -> str | None:
    expr = expr.strip().rstrip(",")
    if not expr or expr.startswith("Modifier::"):
        return None

    m = RGB_INLINE_RE.search(expr)
    if m:
        r, g, b = (int(x) for x in m.groups())
        return rgb_to_hex(r, g, b)

    m = COLOR_RGB_RE.search(expr)
    if m:
        r, g, b = (int(x) for x in m.groups())
        return rgb_to_hex(r, g, b)

    # Palette constant (possibly with trailing comment)
    ident = re.match(r"([A-Z][A-Z0-9_]*)", expr)
    if ident and ident.group(1) in palette:
        return palette[ident.group(1)]

    # Inline hex in comment, e.g. rgb(28, 28, 28) // lighter ...
    hexes = HEX_COMMENT_RE.findall(expr)
    if hexes:
        return f"#{hexes[-1].lower()}"

    return None


def extract_fn_body(source: str, fn_name: str) -> str:
    marker = f"pub const fn {fn_name}() -> Self {{"
    start = source.find(marker)
    if start < 0:
        raise ValueError(f"constructor {fn_name}() not found")
    brace = source.find("{", start)
    depth = 0
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : i]
    raise ValueError(f"unclosed body for {fn_name}()")


def parse_theme_tokens(body: str, palette: dict[str, str]) -> dict[str, str]:
    tokens: dict[str, str] = {}
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        if key.endswith("_mod"):
            continue
        if not key[0].islower():
            continue
        hex_val = resolve_color_expr(value, palette)
        if hex_val:
            tokens[key] = hex_val
    return tokens


def extract_theme(path: Path, fn_name: str) -> dict[str, str]:
    source = path.read_text(encoding="utf-8")
    palette = parse_palette(source)
    body = extract_fn_body(source, fn_name)
    return parse_theme_tokens(body, palette)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for filename, fn_name, stem, aliases, requires_tc in THEME_FILES:
        src = THEME_SRC / filename
        if not src.is_file():
            print(f"error: missing upstream theme source {src}", file=sys.stderr)
            return 1
        tokens = extract_theme(src, fn_name)
        payload = {
            "name": stem,
            "display_name": stem,
            "aliases": aliases,
            "requires_truecolor": requires_tc,
            "source_file": f"xai-grok-pager-render/src/theme/{filename}",
            "constructor": f"Theme::{fn_name}()",
            "tokens": tokens,
        }
        out = OUT_DIR / f"{stem}.json"
        out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {out.relative_to(ROOT)} ({len(tokens)} tokens)")

    auto_path = OUT_DIR / "auto.json"
    auto_path.write_text(json.dumps(AUTO_META, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {auto_path.relative_to(ROOT)} (meta only)")

    # Sanity: PLAN.md contract values for GrokNight
    groknight = json.loads((OUT_DIR / "groknight.json").read_text(encoding="utf-8"))
    t = groknight["tokens"]
    assert t.get("bg_base") == "#141414", t.get("bg_base")
    assert t.get("accent_assistant") == "#bb9af7", t.get("accent_assistant")
    print("groknight.json: bg_base=#141414 accent_assistant=#bb9af7 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
