#!/usr/bin/env bash
set -u

pass_count=0
warn_count=0
fail_count=0

say() { printf '%s\n' "$*"; }
pass() { pass_count=$((pass_count + 1)); say "PASS: $*"; }
warn() { warn_count=$((warn_count + 1)); say "WARN: $*"; }
fail() { fail_count=$((fail_count + 1)); say "FAIL: $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

say "Claude operator check (WSL): $(date -Is 2>/dev/null || date)"

if is_wsl; then
  pass "WSL detected"
else
  warn "WSL not detected (script still runs, but assumptions may not hold)"
fi

if have claude; then
  pass "claude on PATH: $(command -v claude)"
  if have timeout; then
    ver="$(timeout 2s claude --version 2>/dev/null | head -n 1 || true)"
  else
    ver="$(claude --version 2>/dev/null | head -n 1 || true)"
  fi
  if [ -n "$ver" ]; then
    pass "claude --version: $ver"
  else
    warn "claude --version produced no output"
  fi
else
  fail "claude not found on PATH"
fi

claude_dir="$HOME/.claude"
entry_md="$claude_dir/CLAUDE.md"
ops_spec="$HOME/ops-operator/config/CLAUDE.md"

if [ -d "$claude_dir" ]; then
  pass "found: $claude_dir/"
else
  fail "missing: $claude_dir/ (Claude runtime state)"
fi

if [ -f "$entry_md" ]; then
  pass "found: $entry_md"
  if grep -Fq "ops-operator/config/CLAUDE.md" "$entry_md"; then
    pass "entrypoint references: ops-operator/config/CLAUDE.md"
  elif grep -Fq "ops-operator" "$entry_md"; then
    warn "entrypoint mentions ops-operator, but not config/CLAUDE.md (verify wiring)"
  else
    warn "entrypoint does not mention ops-operator (verify your SSOT)"
  fi
else
  fail "missing: $entry_md (expected Claude operator entrypoint)"
fi

if [ -f "$ops_spec" ]; then
  pass "found canonical spec: $ops_spec"
else
  warn "missing canonical spec at: $ops_spec (expected if you use ops-operator as SSOT)"
fi

say ""
say "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  say "Next: see $repo_root/docs/CLAUDE_WSL_OPERATOR.md"
  exit 1
fi
exit 0
