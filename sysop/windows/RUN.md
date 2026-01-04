# Windows snapshot collection

This repo can’t reliably execute Windows binaries from the Codex runner. Run this from an interactive WSL shell (or Windows PowerShell).

## Run (interactive WSL, from repo root)

```bash
SCRIPT_WIN="$(wslpath -w "$PWD/sysop/windows/collect-windows.ps1")"; (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WIN")
```

Outputs (written into the repo):
- `sysop-report/windows/snapshot.txt`
- `sysop-report/windows/snapshot.json`

Rollback:
- `rm -f sysop-report/windows/snapshot.txt sysop-report/windows/snapshot.json`
