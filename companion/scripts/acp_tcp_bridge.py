#!/usr/bin/env python3
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
"""TLS + PIN companion bridge: newline JSON-RPC (ACP) ↔ `grok agent stdio`."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shlex
import shutil
import ssl
import sys
import uuid
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from companion_tls import (  # noqa: E402
    DEFAULT_STATE_DIR,
    ensure_tls_identity,
    log as tls_log,
    parse_pair_line,
    pair_result,
    verify_pair,
)
from companion_ext import (  # noqa: E402
    CONFIG_GET_METHOD,
    CONFIG_SET_METHOD,
    MERMAID_RENDER_METHOD,
    handle_companion_rpc,
)

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 7391
XAI_API_KEY_METHOD_ID = "xai.api_key"
WORKSPACE_LIST_METHOD = "workspace/list"
COMPANION_METHODS = {MERMAID_RENDER_METHOD, CONFIG_GET_METHOD, CONFIG_SET_METHOD}


def log(msg: str) -> None:
    print(f"[acp-bridge] {msg}", file=sys.stderr, flush=True)


def find_grok(upstream: Path) -> list[str] | None:
    grok = shutil.which("grok")
    if grok:
        return [grok, "agent", "stdio"]
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
            "agent",
            "stdio",
        ]
    return None


def extract_api_key(msg: dict[str, Any]) -> str | None:
    params = msg.get("params") or {}
    if not isinstance(params, dict):
        return None
    meta = params.get("_meta") or {}
    if isinstance(meta, dict):
        for key in ("xaiApiKey", "apiKey", "XAI_API_KEY"):
            val = meta.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
    for key in ("xaiApiKey", "apiKey"):
        val = params.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return None


def list_workspace_files(workspace: Path, max_files: int = 500) -> list[str]:
    root = workspace.resolve()
    if not root.is_dir():
        return []
    out: list[str] = []
    skip = {".git", "node_modules", "build", "DerivedData", "target", ".build"}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip and not d.startswith(".")]
        rel_dir = Path(dirpath).relative_to(root)
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            rel = (rel_dir / name) if str(rel_dir) != "." else Path(name)
            out.append(str(rel).replace("\\", "/"))
            if len(out) >= max_files:
                return out
    return out


class AcpStub:
    def __init__(self, upstream: Path | None = None) -> None:
        self.session_id = f"stub-{uuid.uuid4().hex[:12]}"
        self.initialized = False
        self.authenticated = False
        self.upstream = upstream or Path(__file__).resolve().parents[2] / "upstream-grok-build"

    def handle(self, line: str) -> list[str]:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return [json.dumps({
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": "Parse error"},
            })]

        if msg.get("method"):
            return self._handle_request(msg)
        return []

    def _handle_request(self, msg: dict[str, Any]) -> list[str]:
        method = msg.get("method", "")
        req_id = msg.get("id")
        out: list[str] = []

        companion = handle_companion_rpc(msg, self.upstream)
        if companion is not None:
            out.append(companion.decode("utf-8").rstrip("\n"))
            return out

        if method == WORKSPACE_LIST_METHOD:
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"files": ["README.md", "PLAN.md", "ios/GrokApp/GrokApp/GrokApp.swift"]},
            }))
            return out

        if method == "initialize":
            self.initialized = True
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": 1,
                    "agentCapabilities": {
                        "loadSession": True,
                        "promptCapabilities": {"image": False, "audio": False},
                    },
                    "authMethods": [{
                        "id": XAI_API_KEY_METHOD_ID,
                        "name": "xai.api_key",
                        "description": "XAI_API_KEY or api_key in config.toml",
                    }],
                },
            }))
            return out

        if method == "authenticate":
            params = msg.get("params") or {}
            method_id = params.get("methodId") if isinstance(params, dict) else None
            key = extract_api_key(msg)
            if key:
                log("stub: received API key via authenticate (not logged)")
            if method_id not in (None, XAI_API_KEY_METHOD_ID, "stub-api-key"):
                out.append(json.dumps({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32000, "message": f"Stub: unknown auth method {method_id}"},
                }))
                return out
            self.authenticated = True
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"_meta": {"team_name": "stub"}},
            }))
            return out

        if method in ("session/new", "session/create"):
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "sessionId": self.session_id,
                    "models": {"currentModelId": "grok-build-stub"},
                },
            }))
            return out

        if method == "session/prompt":
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"stopReason": "end_turn"},
            }))
            out.extend(self._fake_turn_notifications())
            return out

        if method == "session/cancel":
            out.append(json.dumps({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {},
            }))
            return out

        out.append(json.dumps({
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Stub: method not implemented: {method}"},
        }))
        return out

    def _fake_turn_notifications(self) -> list[str]:
        tool_id = f"tool-{uuid.uuid4().hex[:8]}"
        session = self.session_id
        return [
            json.dumps({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": session,
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": "Hello from ACP stub. "},
                    },
                },
            }),
            json.dumps({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": session,
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": "Running a sample tool…"},
                    },
                },
            }),
            json.dumps({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": session,
                    "update": {
                        "sessionUpdate": "tool_call",
                        "toolCallId": tool_id,
                        "title": "read_file",
                        "kind": "read",
                        "status": "in_progress",
                        "rawInput": {"path": "README.md"},
                    },
                },
            }),
            json.dumps({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": session,
                    "update": {
                        "sessionUpdate": "tool_call_update",
                        "toolCallId": tool_id,
                        "status": "completed",
                        "rawOutput": {"content": "# Grok stub output\n"},
                    },
                },
            }),
        ]


async def require_pairing(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    pin: str,
    require_pair: bool,
    state_dir: Path,
) -> bool:
    if not require_pair:
        return True
    try:
        line = await asyncio.wait_for(reader.readline(), timeout=30.0)
    except asyncio.TimeoutError:
        writer.write(pair_result(False, error="Pairing timeout").encode("utf-8"))
        await writer.drain()
        return False
    text = line.decode("utf-8", errors="replace").strip()
    pair = parse_pair_line(text)
    if not pair:
        writer.write(pair_result(False, error="Expected grok_pair line").encode("utf-8"))
        await writer.drain()
        return False
    ok, token, err = verify_pair(pair, pin, state_dir)
    if not ok:
        writer.write(pair_result(False, error=err or "Pairing failed").encode("utf-8"))
        await writer.drain()
        return False
    writer.write(pair_result(True, token=token).encode("utf-8"))
    await writer.drain()
    return True


async def pipe_stream(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    label: str,
    normalize: Callable[[bytes], bytes] | None = None,
) -> None:
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            if normalize is not None:
                line = normalize(line)
            writer.write(line)
            await writer.drain()
    except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError):
        pass
    finally:
        log(f"{label}: stream closed")
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


def normalize_acp_line(line: bytes, workspace: Path) -> bytes:
    text = line.decode("utf-8", errors="replace").replace("\\/", "/")
    stripped = text.strip()
    if not stripped:
        return text.encode("utf-8")
    try:
        msg = json.loads(stripped)
    except json.JSONDecodeError:
        return text.encode("utf-8")
    if msg.get("method") in ("session/new", "session/create"):
        params = msg.setdefault("params", {})
        if not isinstance(params, dict):
            params = {}
            msg["params"] = params
        cwd = params.get("cwd")
        if not cwd or cwd in (".", ""):
            params["cwd"] = str(workspace.resolve())
        else:
            p = Path(str(cwd))
            if not p.is_absolute():
                params["cwd"] = str((workspace / p).resolve())
        text = json.dumps(msg, separators=(",", ":")) + ("\n" if text.endswith("\n") else "")
        return text.encode("utf-8")
    if not text.endswith("\n") and line.endswith(b"\n"):
        text += "\n"
    return text.encode("utf-8")


async def handle_workspace_list(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    workspace: Path,
) -> bool:
    """Handle one workspace/list line; return True if handled (caller should continue reading)."""
    line = await reader.readline()
    if not line:
        return False
    stripped = line.decode("utf-8", errors="replace").strip().replace("\\/", "/")
    if not stripped:
        return True
    try:
        msg = json.loads(stripped)
    except json.JSONDecodeError:
        return False
    if msg.get("method") != WORKSPACE_LIST_METHOD:
        # Put line back by re-processing in caller — store in buffer
        return False
    req_id = msg.get("id")
    files = list_workspace_files(workspace)
    writer.write((json.dumps({
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {"files": files},
    }) + "\n").encode("utf-8"))
    await writer.drain()
    return True


async def handle_tcp_client_stub(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    pin: str,
    require_pair: bool,
    state_dir: Path,
    upstream: Path,
) -> None:
    peer = writer.get_extra_info("peername")
    if not await require_pairing(reader, writer, pin, require_pair, state_dir):
        log(f"stub: pairing failed from {peer}")
        return
    stub = AcpStub(upstream=upstream)
    log(f"stub client connected from {peer}")
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="replace").strip().replace("\\/", "/")
            if not text:
                continue
            for reply in stub.handle(text):
                writer.write((reply + "\n").encode("utf-8"))
                await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()
        log("stub client disconnected")


def _local_initialize_result(req_id: Any) -> bytes:
    """Reply to phone initialize without spawning yet (avoids auth deadlock)."""
    return (json.dumps({
        "jsonrpc": "2.0",
        "id": req_id,
        "result": {
            "protocolVersion": 1,
            "agentCapabilities": {
                "loadSession": True,
                "promptCapabilities": {"image": False, "audio": False},
            },
            "authMethods": [{
                "id": XAI_API_KEY_METHOD_ID,
                "name": "xai.api_key",
                "description": "XAI_API_KEY or api_key in config.toml",
            }],
        },
    }) + "\n").encode("utf-8")


def _rewrite_authenticate_for_grok(msg: dict[str, Any]) -> bytes:
    """Official grok expects headless auth + XAI_API_KEY in env (not phone xaiApiKey meta)."""
    params = dict(msg.get("params") or {})
    meta = dict(params.get("_meta") or {}) if isinstance(params.get("_meta"), dict) else {}
    meta.pop("xaiApiKey", None)
    meta.pop("apiKey", None)
    meta.pop("XAI_API_KEY", None)
    meta["headless"] = True
    params["_meta"] = meta
    params.setdefault("methodId", XAI_API_KEY_METHOD_ID)
    out = dict(msg)
    out["params"] = params
    return (json.dumps(out) + "\n").encode("utf-8")


async def handle_tcp_client_real(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    grok_argv: list[str],
    cwd: Path,
    pin: str,
    require_pair: bool,
    state_dir: Path,
    upstream: Path,
) -> None:
    peer = writer.get_extra_info("peername")
    if not await require_pairing(reader, writer, pin, require_pair, state_dir):
        log(f"pairing failed from {peer}")
        return
    log(f"client paired from {peer}")
    buffered: list[bytes] = []
    api_key: str | None = None
    workspace = Path(os.environ.get("GROK_COMPANION_CWD") or cwd or Path.cwd())
    # Phone waits for initialize before authenticate. Answer initialize locally,
    # wait for authenticate (so we can inject XAI_API_KEY), then spawn grok.
    # Grok's own initialize response must be dropped (phone already got ours).
    initialize_req_id: Any = None
    skip_initialize_response = False

    try:
        while True:
            line = await reader.readline()
            if not line:
                return
            line = normalize_acp_line(line, workspace)
            stripped = line.decode("utf-8", errors="replace").strip()
            if not stripped:
                continue
            try:
                msg = json.loads(stripped.replace("\\/", "/"))
            except json.JSONDecodeError:
                continue
            method = msg.get("method")
            if method == WORKSPACE_LIST_METHOD:
                req_id = msg.get("id")
                files = list_workspace_files(workspace)
                writer.write((json.dumps({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"files": files},
                }) + "\n").encode("utf-8"))
                await writer.drain()
                continue

            if method in (MERMAID_RENDER_METHOD, CONFIG_GET_METHOD, CONFIG_SET_METHOD):
                reply = handle_companion_rpc(msg, upstream)
                if reply is not None:
                    writer.write(reply)
                    await writer.drain()
                continue

            if method == "initialize":
                initialize_req_id = msg.get("id")
                skip_initialize_response = True
                buffered.append(line)
                writer.write(_local_initialize_result(initialize_req_id))
                await writer.drain()
                log("local initialize reply (waiting for authenticate before spawn)")
                continue

            if method == "authenticate":
                api_key = extract_api_key(msg)
                buffered.append(_rewrite_authenticate_for_grok(msg))
                break

            buffered.append(line)
            if method in ("session/new", "session/create", "session/prompt"):
                break

        env = os.environ.copy()
        if api_key:
            env["XAI_API_KEY"] = api_key
            log("injected XAI_API_KEY from phone authenticate (not logged)")
        elif not env.get("XAI_API_KEY"):
            log("no phone API key — grok will use ~/.grok/auth.json if present")
        # Force Grok Build harness identity (same escape hatch as upstream tests).
        env.setdefault("GROK_AGENT", "grok-build")
        env.setdefault("GROK_MODEL", "grok-build-0.1")

        log(f"spawning: {shlex.join(grok_argv)} (cwd={workspace})")
        proc = await asyncio.create_subprocess_exec(
            *grok_argv,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=None,
            cwd=str(workspace),
            env=env,
        )
        assert proc.stdin and proc.stdout
        for raw in buffered:
            proc.stdin.write(raw)
        await proc.stdin.drain()
        await handle_tcp_client_stdio(
            reader,
            writer,
            proc,
            workspace,
            upstream=upstream,
            drop_response_id=initialize_req_id if skip_initialize_response else None,
        )
    finally:
        log(f"client disconnected from {peer}")


async def pipe_stream_drop_id(
    src: asyncio.StreamReader,
    dst: asyncio.StreamWriter,
    label: str,
    drop_response_id: Any,
) -> None:
    """stdio→tcp pipe that drops one JSON-RPC response matching drop_response_id."""
    dropped = drop_response_id is None
    try:
        while True:
            line = await src.readline()
            if not line:
                break
            if not dropped:
                try:
                    msg = json.loads(line.decode("utf-8", errors="replace").strip().replace("\\/", "/"))
                    if msg.get("id") == drop_response_id and "result" in msg:
                        dropped = True
                        log(f"{label}: dropped duplicate initialize response id={drop_response_id!r}")
                        continue
                except (json.JSONDecodeError, AttributeError):
                    pass
            dst.write(line)
            await dst.drain()
    except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError):
        pass
    finally:
        log(f"{label}: stream closed")


async def pipe_client_to_stdio(
    client_reader: asyncio.StreamReader,
    proc_stdin: asyncio.StreamWriter,
    client_writer: asyncio.StreamWriter,
    workspace: Path,
    upstream: Path,
) -> None:
    """tcp→stdio with companion method intercept (mermaid / config / workspace)."""
    try:
        while True:
            line = await client_reader.readline()
            if not line:
                break
            line = normalize_acp_line(line, workspace)
            stripped = line.decode("utf-8", errors="replace").strip()
            if not stripped:
                continue
            try:
                msg = json.loads(stripped.replace("\\/", "/"))
            except json.JSONDecodeError:
                proc_stdin.write(line if line.endswith(b"\n") else line + b"\n")
                await proc_stdin.drain()
                continue

            method = msg.get("method")
            if method == WORKSPACE_LIST_METHOD:
                req_id = msg.get("id")
                files = list_workspace_files(workspace)
                client_writer.write((json.dumps({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"files": files},
                }) + "\n").encode("utf-8"))
                await client_writer.drain()
                continue

            companion = handle_companion_rpc(msg, upstream)
            if companion is not None:
                client_writer.write(companion)
                await client_writer.drain()
                continue

            out = line if line.endswith(b"\n") else line + b"\n"
            proc_stdin.write(out)
            await proc_stdin.drain()
    except (asyncio.CancelledError, ConnectionResetError, BrokenPipeError):
        pass
    finally:
        log("tcp→stdio: stream closed")
        try:
            proc_stdin.close()
            await proc_stdin.wait_closed()
        except Exception:
            pass


async def handle_tcp_client_stdio(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    proc: asyncio.subprocess.Process,
    workspace: Path,
    upstream: Path,
    drop_response_id: Any = None,
) -> None:
    assert proc.stdin and proc.stdout
    t1 = asyncio.create_task(
        pipe_client_to_stdio(client_reader, proc.stdin, client_writer, workspace, upstream)
    )
    if drop_response_id is not None:
        t2 = asyncio.create_task(
            pipe_stream_drop_id(proc.stdout, client_writer, "stdio→tcp", drop_response_id)
        )
    else:
        t2 = asyncio.create_task(pipe_stream(proc.stdout, client_writer, "stdio→tcp"))
    await asyncio.wait({t1, t2}, return_when=asyncio.FIRST_COMPLETED)
    for t in (t1, t2):
        t.cancel()
    if proc.returncode is None:
        proc.terminate()
        try:
            await asyncio.wait_for(proc.wait(), timeout=3)
        except asyncio.TimeoutError:
            proc.kill()


async def run_server(
    host: str,
    port: int,
    grok_argv: list[str] | None,
    cwd: Path,
    ssl_context: ssl.SSLContext | None,
    pin: str,
    require_pair: bool,
    state_dir: Path,
    stub: bool,
    upstream: Path,
) -> None:
    async def on_client(
        reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        if stub or grok_argv is None:
            await handle_tcp_client_stub(
                reader, writer, pin, require_pair, state_dir, upstream
            )
        else:
            await handle_tcp_client_real(
                reader, writer, grok_argv, cwd, pin, require_pair, state_dir, upstream
            )

    server = await asyncio.start_server(on_client, host, port, ssl=ssl_context)
    mode = "STUB" if stub or grok_argv is None else "REAL"
    tls_label = "TLS" if ssl_context else "plain"
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets or [])
    log(f"{mode} {tls_label} listening on {addrs}")
    if require_pair:
        log(f"PAIR PIN: {pin}  (share with phone during setup)")
    async with server:
        await server.serve_forever()


def build_ssl_context(cert: Path, key: Path) -> ssl.SSLContext:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=str(cert), keyfile=str(key))
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    return ctx


def main() -> int:
    parser = argparse.ArgumentParser(description="Grok ACP TLS companion bridge")
    parser.add_argument("--host", default=os.environ.get("GROK_ACP_HOST", DEFAULT_HOST))
    parser.add_argument("--port", type=int, default=int(os.environ.get("GROK_ACP_PORT", DEFAULT_PORT)))
    parser.add_argument("--stub", action="store_true", help="Protocol stub (no grok)")
    parser.add_argument("--real", action="store_true", help="Require real grok")
    parser.add_argument("--no-tls", action="store_true", help="Plain TCP (requires GROK_COMPANION_INSECURE=1)")
    parser.add_argument("--no-pair", action="store_true", help="Skip PIN (requires GROK_COMPANION_INSECURE=1)")
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE_DIR)
    parser.add_argument(
        "--upstream",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "upstream-grok-build",
    )
    args = parser.parse_args()

    insecure_ok = os.environ.get("GROK_COMPANION_INSECURE", "").strip().lower() in ("1", "true", "yes")
    loopback_hosts = {"127.0.0.1", "localhost", "::1", "0.0.0.0"}
    host_norm = args.host.strip().lower()
    if args.no_tls or args.no_pair:
        if not insecure_ok:
            log("ERROR: --no-tls/--no-pair require GROK_COMPANION_INSECURE=1 (automated tests only)")
            return 1
        if host_norm not in loopback_hosts:
            log("ERROR: insecure mode is only allowed on loopback (127.0.0.1)")
            return 1

    cert, key, pin, fp_full = ensure_tls_identity(args.state_dir)
    fp_short = fp_full[:16]

    # Emit machine-readable banner for start-acp-bridge.sh / Bonjour TXT
    print(json.dumps({
        "grok_companion": {
            "port": args.port,
            "pin": pin,
            "fingerprint": fp_full,
            "fingerprint_short": fp_short,
            "tls": not args.no_tls,
        }
    }), flush=True)

    use_tls = not args.no_tls
    require_pair = not args.no_pair

    if args.stub:
        ssl_ctx = build_ssl_context(cert, key) if use_tls else None
        asyncio.run(run_server(
            args.host, args.port, None, args.upstream, ssl_ctx,
            pin, require_pair, args.state_dir, stub=True, upstream=args.upstream,
        ))
        return 0

    grok_argv = find_grok(args.upstream)
    if not grok_argv:
        if args.real:
            log("ERROR: --real requires grok on PATH or cargo+upstream build")
            return 1
        log("grok not found — falling back to STUB (pass --stub explicitly for tests)")
        ssl_ctx = build_ssl_context(cert, key) if use_tls else None
        asyncio.run(run_server(
            args.host, args.port, None, args.upstream, ssl_ctx,
            pin, require_pair, args.state_dir, stub=True, upstream=args.upstream,
        ))
        return 0

    if not use_tls or not require_pair:
        log("WARNING: real grok without TLS+PIN is discouraged; use defaults for production")
    ssl_ctx = build_ssl_context(cert, key) if use_tls else None
    asyncio.run(run_server(
        args.host, args.port, grok_argv, args.upstream, ssl_ctx,
        pin, require_pair, args.state_dir, stub=False, upstream=args.upstream,
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
