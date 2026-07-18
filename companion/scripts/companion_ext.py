# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
"""Companion-owned ACP extensions (mermaid render + shell config.toml)."""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path
from typing import Any

MERMAID_RENDER_METHOD = "x.ai/companion/mermaid_render"
CONFIG_GET_METHOD = "x.ai/companion/config_get"
CONFIG_SET_METHOD = "x.ai/companion/config_set"

# Shell-owned `[ui]` keys we expose to iOS (settings/defs.rs).
UI_BOOL_KEYS = {
    "show_thinking_blocks",
    "show_timestamps",
    "remember_tool_approvals",
    "prompt_suggestions",
    "group_tool_verbs",
    "collapsed_edit_blocks",
}
UI_STRING_KEYS = {
    "render_mermaid",  # auto | on | off
    "permission_mode",  # default | ask | auto | always_approve (stored as canonical)
}

UI_DEFAULTS: dict[str, Any] = {
    "show_thinking_blocks": True,
    "show_timestamps": True,
    "remember_tool_approvals": False,
    "prompt_suggestions": True,
    "group_tool_verbs": True,
    "collapsed_edit_blocks": False,
    "render_mermaid": "auto",
    "permission_mode": "default",
}


def log(msg: str) -> None:
    print(f"[companion-ext] {msg}", file=__import__("sys").stderr, flush=True)


def grok_home() -> Path:
    env = os.environ.get("GROK_HOME")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".grok"


def config_toml_path() -> Path:
    return grok_home() / "config.toml"


def find_pager(upstream: Path) -> list[str] | None:
    """Resolve argv prefix that runs xai-grok-pager (before subcommand args)."""
    pager = shutil.which("xai-grok-pager")
    if pager:
        return [pager]
    for candidate in (
        upstream / "target" / "release" / "xai-grok-pager",
        upstream / "target" / "debug" / "xai-grok-pager",
    ):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return [str(candidate)]
    cargo = shutil.which("cargo")
    if cargo and (upstream / "Cargo.toml").is_file():
        return [
            cargo,
            "run",
            "--quiet",
            "--manifest-path",
            str(upstream / "Cargo.toml"),
            "-p",
            "xai-grok-pager-bin",
            "--",
        ]
    return None


def render_mermaid(
    source: str,
    upstream: Path,
    *,
    theme: str = "dark",
    quality: str = "open",
    width: int = 960,
    timeout_s: float = 45.0,
) -> dict[str, Any]:
    pager = find_pager(upstream)
    if not pager:
        return {"error": "xai-grok-pager not found (install grok-build or build upstream)"}
    theme_arg = "dark" if theme.lower() in ("dark", "night") else "light"
    quality_arg = "open" if quality.lower() != "terminal" else "terminal"
    with tempfile.TemporaryDirectory(prefix="grok-mermaid-") as tmp:
        out_path = Path(tmp) / "diagram.png"
        argv = list(pager) + [
            "__mermaid-render",
            "--out",
            str(out_path),
            "--theme",
            theme_arg,
            "--quality",
            quality_arg,
            "--width",
            str(max(120, min(width, 4096))),
        ]
        try:
            proc = subprocess.run(
                argv,
                input=source.encode("utf-8"),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return {"error": "mermaid render timed out"}
        except FileNotFoundError:
            return {"error": "xai-grok-pager executable missing"}
        if proc.returncode != 0 or not out_path.is_file():
            err = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
            return {"error": err or f"mermaid render failed (exit {proc.returncode})"}
        data = out_path.read_bytes()
        if not data:
            return {"error": "mermaid render produced empty PNG"}
        return {"pngBase64": base64.b64encode(data).decode("ascii")}


def _read_ui_section() -> dict[str, Any]:
    path = config_toml_path()
    if not path.is_file():
        return {}
    try:
        raw = path.read_text(encoding="utf-8")
        data = tomllib.loads(raw)
    except (OSError, tomllib.TOMLDecodeError) as e:
        log(f"config read failed: {e}")
        return {}
    ui = data.get("ui")
    return dict(ui) if isinstance(ui, dict) else {}


def config_get() -> dict[str, Any]:
    ui = _read_ui_section()
    values: dict[str, Any] = {}
    for key, default in UI_DEFAULTS.items():
        if key in ui:
            values[key] = ui[key]
        else:
            values[key] = default
    return {
        "path": str(config_toml_path()),
        "values": values,
    }


def _format_toml_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    raise TypeError(f"unsupported toml value: {type(value)}")


def _upsert_ui_keys(text: str, updates: dict[str, Any]) -> str:
    """Patch or append `[ui]` keys without a full TOML rewriter."""
    if not updates:
        return text
    lines = text.splitlines(keepends=True)
    if not lines and text:
        lines = [text]
    ui_start = None
    ui_end = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "[ui]":
            ui_start = i
            continue
        if ui_start is not None and ui_end is None:
            if stripped.startswith("[") and stripped.endswith("]") and stripped != "[ui]":
                ui_end = i
                break
    if ui_start is None:
        block = ["\n" if text and not text.endswith("\n") else "", "[ui]\n"]
        for k, v in updates.items():
            block.append(f"{k} = {_format_toml_value(v)}\n")
        return text + "".join(block)

    end = ui_end if ui_end is not None else len(lines)
    section = lines[ui_start + 1 : end]
    remaining = dict(updates)
    new_section: list[str] = []
    key_re = re.compile(r"^([A-Za-z0-9_.-]+)\s*=")
    for line in section:
        m = key_re.match(line.strip())
        if m and m.group(1) in remaining:
            key = m.group(1)
            new_section.append(f"{key} = {_format_toml_value(remaining.pop(key))}\n")
        else:
            new_section.append(line)
    for key, value in remaining.items():
        new_section.append(f"{key} = {_format_toml_value(value)}\n")
    return "".join(lines[: ui_start + 1] + new_section + lines[end:])


def config_set(values: dict[str, Any]) -> dict[str, Any]:
    updates: dict[str, Any] = {}
    for key, value in values.items():
        if key in UI_BOOL_KEYS:
            if not isinstance(value, bool):
                return {"error": f"{key} must be bool"}
            updates[key] = value
        elif key in UI_STRING_KEYS:
            if not isinstance(value, str) or not value:
                return {"error": f"{key} must be non-empty string"}
            updates[key] = value
        else:
            return {"error": f"unsupported key: {key}"}
    path = config_toml_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.is_file() else ""
    updated = _upsert_ui_keys(existing, updates)
    path.write_text(updated, encoding="utf-8")
    return config_get()


def handle_companion_rpc(
    msg: dict[str, Any],
    upstream: Path,
) -> bytes | None:
    """If msg is a companion-owned method, return a full JSON-RPC response line."""
    method = msg.get("method")
    if method not in (MERMAID_RENDER_METHOD, CONFIG_GET_METHOD, CONFIG_SET_METHOD):
        return None
    req_id = msg.get("id")
    params = msg.get("params") if isinstance(msg.get("params"), dict) else {}

    if method == MERMAID_RENDER_METHOD:
        source = params.get("source")
        if not isinstance(source, str) or not source.strip():
            body: dict[str, Any] = {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32602, "message": "source required"},
            }
        else:
            result = render_mermaid(
                source,
                upstream,
                theme=str(params.get("theme") or "dark"),
                quality=str(params.get("quality") or "open"),
                width=int(params.get("width") or 960),
            )
            if "error" in result:
                body = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32000, "message": result["error"]},
                }
            else:
                body = {"jsonrpc": "2.0", "id": req_id, "result": result}
        return (json.dumps(body) + "\n").encode("utf-8")

    if method == CONFIG_GET_METHOD:
        body = {"jsonrpc": "2.0", "id": req_id, "result": config_get()}
        return (json.dumps(body) + "\n").encode("utf-8")

    if method == CONFIG_SET_METHOD:
        values = params.get("values") if isinstance(params.get("values"), dict) else {}
        result = config_set(values)
        if "error" in result:
            body = {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32602, "message": result["error"]},
            }
        else:
            body = {"jsonrpc": "2.0", "id": req_id, "result": result}
        return (json.dumps(body) + "\n").encode("utf-8")

    return None
