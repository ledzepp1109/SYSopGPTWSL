#!/usr/bin/env bash
set -u

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
report="$repo_root/sysop-report/2026-01-04_wsl_sysop.md"

today="$(date +%F 2>/dev/null || date)"

say() { printf '%s\n' "$*"; }

say "## Current Baseline Snapshot (${today})"
say ""

if [ -f "$report" ]; then
  interactive_line="$(grep -F -- "- systemd/dbus (interactive Ubuntu shell):" "$report" | tail -n 1 || true)"
  if [ -n "$interactive_line" ]; then
    say "$interactive_line"
  else
    say "- systemd/dbus (interactive Ubuntu shell): (unknown; run systemctl in interactive shell and update report)"
  fi
else
  say "- systemd/dbus (interactive Ubuntu shell): (unknown; report missing)"
fi

runner_sysctl="$(systemctl is-system-running 2>&1 || true)"
if [ -n "$runner_sysctl" ]; then
  say "- systemd/dbus (Codex runner): systemctl is-system-running => ${runner_sysctl}"
else
  say "- systemd/dbus (Codex runner): systemctl is-system-running => (no output)"
fi

codex_path="$(command -v codex 2>/dev/null || true)"
codex_ver="$(codex --version 2>/dev/null || true)"
if [ -n "$codex_path" ]; then
  say "- codex: ${codex_path} (${codex_ver})"
else
  say "- codex: (not found)"
fi

npm_prefix="$(npm prefix -g 2>/dev/null || true)"
npm_root="$(npm root -g 2>/dev/null || true)"
if [ -n "$npm_prefix" ]; then
  say "- npm: npm prefix -g=${npm_prefix}; npm root -g=${npm_root}"
else
  say "- npm: (not found)"
fi

autocrlf="$(git config --global --get core.autocrlf 2>/dev/null || true)"
say "- git: core.autocrlf=${autocrlf:-<unset>}"

ssh_line=""
if [ -f "$report" ]; then
  ssh_line="$(grep -F -- "- ssh:" "$report" | tail -n 1 || true)"
fi
if [ -n "$ssh_line" ]; then
  say "$ssh_line"
else
  say "- ssh: (manual) ssh -T git@github.com"
fi

path_lines="$(echo "${PATH:-}" | tr ':' '\n' | nl -ba)"
matches="$(printf '%s\n' "$path_lines" | grep -F '.npm-global/bin' || true)"
if [ -n "$matches" ]; then
  count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  first_seg="$(printf '%s\n' "$matches" | head -n 1 | awk '{print $1}')"
  say "- PATH: .npm-global/bin appears ${count} time(s) (first segment ${first_seg})"
else
  say "- PATH: .npm-global/bin not found"
fi
