#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec codex \
  --dangerously-bypass-approvals-and-sandbox \
  --search \
  --cd "$repo_root" \
  "$@"
