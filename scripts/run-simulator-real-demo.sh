#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Deprecated alias — use run-simulator-demo.sh (official grok agent serve).
exec "$(cd "$(dirname "$0")" && pwd)/run-simulator-demo.sh" "$@"
