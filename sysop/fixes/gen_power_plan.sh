#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
. "$script_dir/lib.sh"

out_dir="$repo_root/sysop/out"
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: sysop/fixes/gen_power_plan.sh [--repo-root <path>] [--out-dir <path>] [--dry-run]

Level 2 (GENERATE): writes a Windows PowerShell script under sysop/out/fixes/ to switch to Ultimate Performance.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

fix_dir="$out_dir/fixes"
script_path="$fix_dir/windows_power_plan_ultimate.ps1"

if [ "$dry_run" -eq 1 ]; then
  say "DRY-RUN: would write: $script_path"
  exit 0
fi

mkdir -p "$fix_dir"
cat >"$script_path" <<'PS1'
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "== Power plan (Ultimate Performance) =="

# Ultimate Performance base GUID (Windows 10/11 Pro/Workstation; may need duplication to appear in /L)
$UltimateBase = "e9a42b02-d5df-448d-aa00-03f14749eb61"

Write-Host "Active scheme (before):"
powercfg /GETACTIVESCHEME

$list = (powercfg /L | Out-String)
if ($list -notmatch [regex]::Escape($UltimateBase)) {
  Write-Host "Ultimate Performance not listed; duplicating base scheme..."
  powercfg -duplicatescheme $UltimateBase | Out-Null
}

$list = (powercfg /L | Out-String)
$m = [regex]::Match($list, "Power Scheme GUID:\s*([0-9a-fA-F-]+)\s+\(Ultimate Performance\)")
if (-not $m.Success) {
  throw "Could not find Ultimate Performance scheme after duplication."
}
$Ultimate = $m.Groups[1].Value

Write-Host "Setting active scheme to Ultimate Performance: $Ultimate"
powercfg /S $Ultimate

Write-Host "Active scheme (after):"
powercfg /GETACTIVESCHEME
PS1

append_ledger_autofix \
  "$repo_root" \
  "Generate Windows power plan script" \
  "2" "GENERATE" \
  "no (generated only)" \
  "(none) -> ${script_path}" \
  "(none)" \
  "del -Force \"$script_path\"  # from PowerShell, or rm -f \"$script_path\" from WSL" \
  "applied" \
  "$script_path"

say "Wrote: $script_path"
