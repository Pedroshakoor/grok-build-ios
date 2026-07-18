#!/usr/bin/env python3
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
"""Minimal WebSocket ACP smoke client for `grok agent serve` (stdlib only)."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
from typing import Any
from urllib.parse import quote


def ws_connect(host: str, port: int, path: str, timeout: float = 10.0) -> socket.socket:
    sock = socket.create_connection((host, port), timeout=timeout)
    sock.settimeout(timeout)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(req.encode("ascii"))
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("websocket handshake eof")
        buf += chunk
    head, _rest = buf.split(b"\r\n\r\n", 1)
    status = head.split(b"\r\n", 1)[0]
    if b"101" not in status:
        raise RuntimeError(f"websocket handshake failed: {status!r}")
    return sock


def _read_exact(sock: socket.socket, n: int) -> bytes:
    out = b""
    while len(out) < n:
        chunk = sock.recv(n - len(out))
        if not chunk:
            raise RuntimeError("websocket eof")
        out += chunk
    return out


def ws_recv_text(sock: socket.socket) -> str:
    hdr = _read_exact(sock, 2)
    b1, b2 = hdr[0], hdr[1]
    opcode = b1 & 0x0F
    masked = (b2 & 0x80) != 0
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack("!H", _read_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", _read_exact(sock, 8))[0]
    mask = _read_exact(sock, 4) if masked else b""
    payload = _read_exact(sock, length)
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    if opcode == 0x8:
        raise RuntimeError("websocket closed")
    if opcode == 0x9:  # ping
        return ws_recv_text(sock)
    if opcode != 0x1:
        raise RuntimeError(f"unsupported opcode {opcode}")
    return payload.decode("utf-8")


def ws_send_text(sock: socket.socket, text: str) -> None:
    data = text.encode("utf-8")
    mask_bit = 0x80
    header = bytearray([0x81])  # FIN + text
    ln = len(data)
    mask_key = os.urandom(4)
    if ln < 126:
        header.append(mask_bit | ln)
    elif ln < 65536:
        header.append(mask_bit | 126)
        header.extend(struct.pack("!H", ln))
    else:
        header.append(mask_bit | 127)
        header.extend(struct.pack("!Q", ln))
    header.extend(mask_key)
    masked = bytes(b ^ mask_key[i % 4] for i, b in enumerate(data))
    sock.sendall(header + masked)


def rpc(sock: socket.socket, method: str, params: dict[str, Any], req_id: int) -> dict[str, Any]:
    msg = {"jsonrpc": "2.0", "method": method, "params": params, "id": req_id}
    ws_send_text(sock, json.dumps(msg, separators=(",", ":")))
    deadline = time.time() + 45.0
    while time.time() < deadline:
        raw = ws_recv_text(sock).strip()
        if raw == "ping" or not raw:
            continue
        obj = json.loads(raw)
        if obj.get("id") == req_id:
            return obj
    raise RuntimeError(f"timeout waiting for {method}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=2419)
    ap.add_argument("--secret", required=True)
    ap.add_argument("--api-key", default=os.environ.get("XAI_API_KEY", ""))
    ap.add_argument("--cwd", default="/tmp")
    args = ap.parse_args()

    path = f"/ws?server-key={quote(args.secret, safe='')}"
    sock = ws_connect(args.host, args.port, path)

    rpc(sock, "initialize", {"protocolVersion": 1}, 1)
    auth_params: dict[str, Any] = {"methodId": "xai.api_key"}
    if args.api_key:
        auth_params["_meta"] = {"xaiApiKey": args.api_key}
    rpc(sock, "authenticate", auth_params, 2)
    sess = rpc(sock, "session/new", {"cwd": args.cwd, "mcpServers": []}, 3)
    sid = (sess.get("result") or {}).get("sessionId")
    if not sid:
        print("FAIL: no sessionId", file=sys.stderr)
        return 1

    rpc(sock, "session/prompt", {
        "sessionId": sid,
        "prompt": [{"type": "text", "text": "Reply with exactly: OK"}],
    }, 4)

    assistant = False
    deadline = time.time() + 60.0
    while time.time() < deadline:
        raw = ws_recv_text(sock).strip()
        if raw == "ping" or not raw:
            continue
        obj = json.loads(raw)
        if obj.get("method") == "session/update":
            upd = (obj.get("params") or {}).get("update") or {}
            if upd.get("sessionUpdate") == "agent_message_chunk":
                text = (upd.get("content") or {}).get("text") or ""
                if text.strip():
                    assistant = True
                    break
        if obj.get("id") == 4 and (obj.get("result") or {}).get("stopReason"):
            assistant = True
            break

    sock.close()
    if not assistant:
        print("FAIL: no assistant chunk from grok agent serve", file=sys.stderr)
        return 1
    print("OK: grok agent serve WebSocket ACP smoke passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
