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
Usage: sysop/fixes/edit_wslconfig.sh [--repo-root <path>] [--out-dir <path>] [--dry-run]

Level 3 (MODIFY): in this repo, host config modifications are never executed automatically.
This generator writes a PowerShell script under sysop/out/fixes/ that backs up and edits ~/.wslconfig on Windows.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

fix_dir="$out_dir/fixes"
script_path="$fix_dir/edit_wslconfig.ps1"

if [ "$dry_run" -eq 1 ]; then
  say "DRY-RUN: would write: $script_path"
  exit 0
fi

mkdir -p "$fix_dir"
cat >"$script_path" <<'PS1'
[CmdletBinding()]
param(
  [Parameter()][int]$Processors = 0,
  [Parameter()][string]$Memory = "",
  [Parameter()][int]$SwapGB = 0
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Path = Join-Path $env:USERPROFILE ".wslconfig"
$Ts = Get-Date -Format "yyyyMMdd-HHmmss"

if (Test-Path $Path) {
  Copy-Item $Path "$Path.bak-$Ts" -Force
  Write-Host "Backup: $Path.bak-$Ts"
} else {
  Write-Host "No existing .wslconfig; creating new file."
}

$lines = @()
$lines += "[wsl2]"
if ($Processors -gt 0) { $lines += "processors=$Processors" }
if ($Memory -and $Memory.Trim().Length -gt 0) { $lines += "memory=$Memory" }
if ($SwapGB -gt 0) { $lines += "swap=${SwapGB}GB" }

$content = ($lines -join "`r`n") + "`r`n"
Set-Content -Path $Path -Value $content -Encoding ASCII

Write-Host "Wrote: $Path"
Write-Host "Apply (requires restart):"
Write-Host "  wsl --shutdown"
PS1

append_ledger_autofix \
  "$repo_root" \
  "Generate .wslconfig editor script (manual run)" \
  "3" "MODIFY" \
  "no (generated only)" \
  "(none) -> ${script_path}" \
  "(none)" \
  "rm -f \"$script_path\"" \
  "applied" \
  "$script_path"

say "Wrote: $script_path"
