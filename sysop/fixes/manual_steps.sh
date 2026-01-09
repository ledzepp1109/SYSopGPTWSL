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
Usage: sysop/fixes/manual_steps.sh [--repo-root <path>] [--out-dir <path>] [--dry-run]

Level 4 (MANUAL): writes instructions only (no commands executed).
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

fix_dir="$out_dir/fixes"
doc_path="$fix_dir/manual_steps.md"

if [ "$dry_run" -eq 1 ]; then
  say "DRY-RUN: would write: $doc_path"
  exit 0
fi

mkdir -p "$fix_dir"
cat >"$doc_path" <<'MD'
# SYSopGPTWSL manual steps (generated)

These steps are never auto-executed by this repo.

## WSL/Windows interop seems down (vsock / powershell.exe fails)

### First: check if this is a Codex sandbox restriction (AF_VSOCK blocked)

In some sandboxed Codex runs, Linux `AF_VSOCK` sockets are blocked, which breaks **all** Windows interop
from WSL and shows errors like:

- `UtilBindVsockAnyPort: socket failed 1`

Quick test (run in the same environment where interop is failing):

```bash
python3 - <<'PY'
import socket
s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
s.close()
print("AF_VSOCK OK")
PY
```

If you see `PermissionError(1, 'Operation not permitted')`, start Codex without sandboxing:

```bash
# Less risky: no sandbox, approvals still on-request
codex --sandbox danger-full-access --ask-for-approval on-request

# Max autonomy (EXTREMELY DANGEROUS):
codex --dangerously-bypass-approvals-and-sandbox
```

Then re-run:

```bash
./sysop/run.sh snapshot
./sysop/run.sh report
```

### If interop is broken outside Codex too: restart WSL

From **Windows PowerShell** (not inside WSL):

```powershell
wsl --shutdown
```

Then reopen Ubuntu and re-run:

```bash
./sysop/run.sh snapshot
./sysop/run.sh report
```

If that still fails, collect evidence:

```powershell
wsl --status
wsl -l -v
```
MD

append_ledger_autofix \
  "$repo_root" \
  "Generate manual recovery steps" \
  "4" "MANUAL" \
  "no (generated only)" \
  "(none) -> ${doc_path}" \
  "(none)" \
  "rm -f \"$doc_path\"" \
  "applied" \
  "$doc_path"

say "Wrote: $doc_path"
