# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
"""TLS identity, pairing PIN, and device tokens for the Grok Build companion."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path
from typing import Any

DEFAULT_STATE_DIR = Path(
    os.environ.get("GROK_COMPANION_STATE_DIR", str(Path.home() / ".grok-build-companion"))
)
PAIR_LINE_PREFIX = "grok_pair"
PAIR_RESULT_PREFIX = "grok_pair_result"


def log(msg: str) -> None:
    print(f"[companion-tls] {msg}", file=sys.stderr, flush=True)


def cert_fingerprint(cert_path: Path) -> str:
    """SHA-256 of certificate DER (matches iOS SecCertificateCopyData)."""
    pem = cert_path.read_bytes()
    proc = subprocess.run(
        ["openssl", "x509", "-in", "/dev/stdin", "-outform", "DER"],
        input=pem,
        check=True,
        capture_output=True,
    )
    return hashlib.sha256(proc.stdout).hexdigest()


def ensure_cert(state_dir: Path | None = None) -> tuple[Path, Path, str]:
    state = state_dir or DEFAULT_STATE_DIR
    state.mkdir(parents=True, exist_ok=True)
    cert = state / "server.crt"
    key = state / "server.key"

    if not cert.exists() or not key.exists():
        log(f"generating TLS identity in {state}")
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", str(key), "-out", str(cert),
                "-days", "3650", "-nodes",
                "-subj", "/CN=Grok Build Companion/O=Pedro Shakour",
            ],
            check=True,
            capture_output=True,
        )
        key.chmod(0o600)

    fp = cert_fingerprint(cert)
    (state / "fingerprint.txt").write_text(fp, encoding="utf-8")
    return cert, key, fp


def fresh_pin(state_dir: Path | None = None) -> str:
    state = state_dir or DEFAULT_STATE_DIR
    state.mkdir(parents=True, exist_ok=True)
    env_pin = os.environ.get("GROK_COMPANION_PIN", "").strip()
    if env_pin:
        pin = env_pin
    else:
        pin = f"{secrets.randbelow(900_000) + 100_000:06d}"
    (state / "pin.txt").write_text(pin, encoding="utf-8")
    return pin


def ensure_tls_identity(state_dir: Path | None = None) -> tuple[Path, Path, str, str]:
    cert, key, fp = ensure_cert(state_dir)
    pin = fresh_pin(state_dir)
    return cert, key, pin, fp


def tokens_path(state_dir: Path | None = None) -> Path:
    return (state_dir or DEFAULT_STATE_DIR) / "paired_tokens.json"


def load_tokens(state_dir: Path | None = None) -> dict[str, str]:
    path = tokens_path(state_dir)
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def save_tokens(tokens: dict[str, str], state_dir: Path | None = None) -> None:
    path = tokens_path(state_dir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(tokens, indent=2), encoding="utf-8")
    path.chmod(0o600)


def issue_token(state_dir: Path | None = None) -> str:
    token = secrets.token_urlsafe(32)
    tokens = load_tokens(state_dir)
    tokens[token] = "paired"
    save_tokens(tokens, state_dir)
    return token


def validate_token(token: str, state_dir: Path | None = None) -> bool:
    if not token or not token.strip():
        return False
    return token.strip() in load_tokens(state_dir)


def parse_pair_line(line: str) -> dict[str, Any] | None:
    line = line.strip()
    if not line:
        return None
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    pair = obj.get(PAIR_LINE_PREFIX)
    return pair if isinstance(pair, dict) else None


def pair_result(ok: bool, token: str | None = None, error: str | None = None) -> str:
    body: dict[str, Any] = {"ok": ok}
    if token:
        body["token"] = token
    if error:
        body["error"] = error
    return json.dumps({PAIR_RESULT_PREFIX: body}, separators=(",", ":")) + "\n"


def verify_pair(
    pair: dict[str, Any],
    expected_pin: str,
    state_dir: Path | None = None,
) -> tuple[bool, str | None, str | None]:
    token = pair.get("token")
    if isinstance(token, str) and validate_token(token, state_dir):
        return True, token.strip(), None
    pin = pair.get("pin")
    if isinstance(pin, str) and pin.strip() == expected_pin:
        return True, issue_token(state_dir), None
    return False, None, "Invalid PIN or pairing token"
