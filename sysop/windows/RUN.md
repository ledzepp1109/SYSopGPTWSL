# Windows snapshot collection

Preferred (from repo root):
- `./sysop/run.sh snapshot`

## Manual run (drive-backed cwd; avoids UNC warnings)

```bash
SCRIPT_WIN="$(wslpath -w "$PWD/sysop/windows/collect-windows.ps1")"
OUT_WIN="$(wslpath -w "$PWD/sysop/out")"
(cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WIN" -OutDir "$OUT_WIN")
```

Outputs (written into the repo):
- `sysop/out/windows_snapshot.txt`
- `sysop/out/windows_snapshot.json`

Notes:
- Windows PowerShell may emit UTF-8 BOM in JSON; Linux readers should use `utf-8-sig`.

Rollback:
- `rm -f sysop/out/windows_snapshot.txt sysop/out/windows_snapshot.json`
