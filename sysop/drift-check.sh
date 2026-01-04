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

path_count() {
  local needle="$1"
  printf '%s' "${PATH:-}" | awk -v RS=':' -v n="$needle" '$0==n {c++} END {print c+0}'
}

file_contains_fixed() {
  # $1=file, $2=fixed-string
  local file="$1"
  local needle="$2"
  grep -F -q -- "$needle" "$file"
}

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
report="$repo_root/sysop-report/2026-01-04_wsl_sysop.md"

expected_codex="$HOME/.npm-global/bin/codex"
expected_npm_prefix="$HOME/.npm-global"
expected_autocrlf="input"
npm_bin="$HOME/.npm-global/bin"

say "Drift check (read-only): $(date -Is 2>/dev/null || date)"
say "Repo: $repo_root"

say ""
say "== Toolchain =="
if have codex; then
  codex_path="$(command -v codex)"
  if [ "$codex_path" = "$expected_codex" ]; then
    pass "codex path: $codex_path"
  else
    warn "codex path: $codex_path (expected $expected_codex)"
  fi
  codex_ver="$(codex --version 2>/dev/null || true)"
  [ -n "$codex_ver" ] && say "INFO: codex --version: $codex_ver"
else
  fail "codex missing on PATH"
fi

if have npm; then
  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  if [ "$npm_prefix" = "$expected_npm_prefix" ]; then
    pass "npm prefix -g: $npm_prefix"
  else
    fail "npm prefix -g: ${npm_prefix:-<empty>} (expected $expected_npm_prefix)"
  fi
else
  fail "npm missing"
fi

if [ -d "$npm_bin" ]; then
  c="$(path_count "$npm_bin")"
  if [ "$c" = "1" ]; then
    pass "PATH contains $npm_bin exactly once"
  elif [ "$c" = "0" ]; then
    fail "PATH does not contain $npm_bin"
  else
    fail "PATH contains $npm_bin $c times (duplication)"
  fi
else
  warn "$npm_bin directory missing"
fi

if have git; then
  autocrlf="$(git config --global --get core.autocrlf 2>/dev/null || true)"
  if [ "$autocrlf" = "$expected_autocrlf" ]; then
    pass "git core.autocrlf=$autocrlf"
  else
    fail "git core.autocrlf=${autocrlf:-<unset>} (expected $expected_autocrlf)"
  fi
else
  fail "git missing"
fi

say ""
say "== SSH (local) =="
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  pass "~/.ssh/id_ed25519.pub present"
else
  fail "~/.ssh/id_ed25519.pub missing"
fi

if [ -f "$HOME/.ssh/config" ]; then
  if grep -Eq '^[[:space:]]*Host[[:space:]]+github\.com[[:space:]]*$' "$HOME/.ssh/config" \
    && grep -Eq '^[[:space:]]*IdentityFile[[:space:]]+~\/\.ssh\/id_ed25519[[:space:]]*$' "$HOME/.ssh/config" \
    && grep -Eq '^[[:space:]]*IdentitiesOnly[[:space:]]+yes[[:space:]]*$' "$HOME/.ssh/config"; then
    pass "~/.ssh/config has github.com IdentityFile + IdentitiesOnly"
  else
    warn "~/.ssh/config present but github.com block differs from expected"
  fi
else
  warn "~/.ssh/config missing (SSH may still work)"
fi
say "INFO: network auth test (manual): ssh -T git@github.com"

say ""
say "== Report =="
if [ -f "$report" ]; then
  pass "report present: $report"
  if file_contains_fixed "$report" "## Operator Note — \`systemctl\` EPERM in Codex runner"; then
    pass "report includes Codex-runner systemctl note"
  else
    fail "report missing Codex-runner systemctl note"
  fi
else
  fail "report missing: $report"
fi

say ""
say "== systemd/dbus (runner) =="
if have systemctl; then
  sys_out="$(systemctl is-system-running 2>&1 || true)"
  if printf '%s' "$sys_out" | grep -qi 'operation not permitted'; then
    warn "systemctl bus blocked in Codex runner; authoritative check = interactive shell + report"
  elif [ -n "$sys_out" ]; then
    pass "systemctl is-system-running: $sys_out"
  else
    warn "systemctl is-system-running produced no output"
  fi
else
  warn "systemctl not found"
fi

say ""
say "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
