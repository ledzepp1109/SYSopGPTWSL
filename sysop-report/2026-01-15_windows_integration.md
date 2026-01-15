# Windows PATH Integration + Hybrid Automation (WSL)

Date: 2026-01-15

## What changed

Host-level WSL interop was updated (manual change outside this repo):
- `/etc/wsl.conf` → `[interop] appendWindowsPath=true`

Evidence (repo artifact):
- `sysop/out/healthcheck.txt` includes:
  - `[interop] enabled=true`
  - `[interop] appendWindowsPath=true`
  - Windows PATH segments under `$PATH` (for example `/mnt/c/WINDOWS/system32`, `/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/`, `/mnt/c/Program Files/PowerShell/7/`)

## Why

Enabling Windows PATH interop unlocks reliable hybrid automation:
- WSL can call Windows executables directly (PowerShell, `powercfg.exe`, etc.)
- When WSL↔Windows interop is available, the sysop pipeline can collect full Windows metrics from inside WSL (no separate Windows terminal required)
- Claude/Codex can orchestrate cross-OS workflows from a single WSL session (with approvals)

## Current system snapshot (from latest sysop artifacts)

Sources:
- `sysop/out/summary.md` (compiled summary)
- `sysop/out/windows_snapshot.json` (Windows-side facts)

Highlights:
- Host CPU: Intel(R) Core(TM) i5-1035G1 CPU @ 1.00GHz (cores=4, logical=8)
- Host RAM: 16852422656 bytes (~16GB)
- WSL memory visible to Linux: 11Gi total
- Windows power plan: High performance (GUID `8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`)

## Hybrid Automation Capabilities

New capabilities now available from WSL (because Windows executables are on `$PATH`):
- **PowerShell access**: `powershell.exe` (Windows PowerShell 5.1) and `pwsh.exe` (PowerShell 7+) when installed.
- **Windows CLI tooling**: `powercfg.exe`, `cmd.exe`, `wsl.exe`, plus other Windows-installed utilities.
- **Cross-OS orchestration**: run Windows commands, then immediately consume outputs from Linux tooling (and write artifacts into the repo under `sysop/out/`).

Operational guardrails:
- Prefer a drive-backed cwd when invoking Windows tools (UNC quirks): `(cd /mnt/c && <windows.exe> ...)`
- Translate paths when passing WSL paths to Windows tooling: `wslpath -w <path>`
- Use explicit `.exe` when you intend to call a Windows binary (avoids PATH precedence surprises).

Interop caveat (vsock):
- Some sandboxed runners block WSL↔Windows interop even when the PATH is present.
- Symptom observed in this Codex runner when invoking Windows binaries:
  - `UtilBindVsockAnyPort:307: socket failed 1`
- If you hit this, verify in a normal interactive WSL shell, or fall back to native Windows PowerShell.

Example use cases (read-only):
```bash
# Verify PowerShell is callable from WSL
(cd /mnt/c && powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion")

# Query Windows power plan
(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)

# Query Windows system info
(cd /mnt/c && powershell.exe -NoProfile -Command "Get-ComputerInfo | Select-Object CsName, OsName, OsVersion")
```

Repo-native use case:
```bash
# Collect the Windows snapshot artifacts into sysop/out/
./sysop/run.sh snapshot
```

## Performance impact

Expected impact is minimal:
- The Windows PATH is large, so PATH lookups can be slightly noisier/slower.
- For real workloads, CPU/memory/disk dominate; PATH size is typically negligible.

Bench note:
- ~20–28% variance between microbench runs is normal noise in this environment.
- Treat cross-run deltas with caution; changes in CPU allocation (`nproc`) and boost/power states can dominate.

Evidence:
- Baseline runs: `sysop-report/perf/` (2026-01-04)
- Latest run: `sysop/out/bench.txt` (2026-01-15)

## Security considerations

With Windows PATH interop enabled, WSL can invoke host Windows binaries:
- Treat calling `*.exe` from WSL as a host-impacting action (it can read/write Windows user data and system settings).
- Keep approvals gated (`approval_policy="on-request"`) for commands that cross OS boundaries or mutate state.
- Avoid running unknown Windows executables surfaced on PATH.
- Prefer running Windows commands from `/mnt/c` and passing only explicit, validated arguments.
