# Security Policy

## Supported Versions

This project is under active development. Security fixes are applied to the latest commit on `main` only.

| Branch / release | Supported |
| ---------------- | --------- |
| `main` (latest)  | ✅        |
| Older commits    | ❌        |

There are no numbered releases yet. Pin a commit if you need a frozen snapshot; upgrade to latest `main` for patches.

## Scope

In scope for this repository:

- The iOS client (`ios/`)
- The optional companion bridge (`companion/`)
- Scripts and config that ship in this repo
- Handling of the ACP WebSocket secret, local network exposure, and related client-side trust issues

Out of scope (report upstream):

- [xai-org/grok-build](https://github.com/xai-org/grok-build) agent / CLI behavior
- xAI API, model, or account issues
- Third-party dependencies that are not introduced by this repo (see their own policies)

The `upstream-grok-build/` submodule is a pin of upstream; do not file submodule-only issues here unless this repo’s packaging or integration is at fault.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security bugs.**

Prefer one of:

1. **GitHub private vulnerability reporting** — on this repo: **Security → Report a vulnerability**  
   https://github.com/Pedroshakoor/grok-build-ios/security/advisories/new
2. If private reporting is unavailable, email the maintainer via the address on the GitHub profile for [@Pedroshakoor](https://github.com/Pedroshakoor), with subject `SECURITY: grok-build-ios`.

Please include:

- Description of the issue and impact
- Steps to reproduce (PoC if possible)
- Affected commit / branch
- Whether the issue is in this client, the companion bridge, or only when talking to `grok agent serve`

### What to expect

- **Acknowledgement:** within 7 days
- **Status update:** within 14 days of acknowledgement (accepted, declined, or needs more info)
- **Accepted:** we will work on a fix, coordinate disclosure timing, and credit you if you want
- **Declined:** we will say why (e.g. out of scope, not reproducible, accepted risk for a local-dev tool)

We ask that you give us a reasonable window to patch before public disclosure (typically 90 days, or sooner if we agree).

## Security notes for users

- Treat the ACP **Secret** like a password. Anyone on the network who has it can drive the agent.
- Prefer Simulator / localhost when possible. On a physical device, use a trusted LAN and understand that `grok agent serve` is a privileged local service.
- Rotate the secret (restart the agent) if it may have leaked.
- Never commit API keys or session secrets to this repo.
