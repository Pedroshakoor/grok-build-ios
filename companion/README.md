# Companion (legacy)

Optional TCP/TLS + Bonjour bridge for LAN experiments.

**Default path:** use official `grok agent serve` (see root [README](../README.md)).

```bash
./companion/scripts/start-acp-bridge.sh --real
```

Stub (tests only):

```bash
export GROK_COMPANION_INSECURE=1
python3 companion/scripts/acp_tcp_bridge.py --stub --no-tls --no-pair --host 127.0.0.1 --port 7391
```
