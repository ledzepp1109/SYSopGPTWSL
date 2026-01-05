# sysop index (Operator Kernel)

One command:
- `./sysop/run.sh all`

Outputs (diffable, overwritten each run):
- `sysop/out/report.md`
- `sysop/out/windows_snapshot.json`
- `sysop/out/wsl_snapshot.txt`
- `sysop/out/bench.txt`

## Reused scripts
- `sysop/preflight.sh` — fast read-only sanity checks
- `sysop/healthcheck.sh` — broader WSL audit (note: `systemctl` can be blocked in the Codex runner)
- `sysop/drift-check.sh` — invariants check vs `sysop-report/2026-01-04_wsl_sysop.md`
- `sysop/windows/collect-windows.ps1` — Windows snapshot collector
- `sysop/perf/wsl-bench.sh` — WSL microbench (CPU/mem/disk)
- `sysop/perf/summarize.sh` — parses snapshots + bench into a report

## Self-tests (no network)
- `./sysop/run.sh health`
- `./sysop/run.sh snapshot`
- `./sysop/run.sh bench`
- `./sysop/run.sh report`
- `codex execpolicy check --rules .codex/rules/sysop.rules --pretty rm -rf /`
- `codex execpolicy check --rules .codex/rules/sysop.rules --pretty git status`

## Known pitfalls
- UNC cwd: run Windows commands from a drive-backed cwd (`/mnt/c`), not from `\\\\wsl$\\...`.
- UTF-8 BOM: Windows JSON may be BOM-prefixed; Linux readers must use `utf-8-sig` (or strip BOM).
- `/mnt/c` perf: drvfs/9p is slower than the Linux filesystem; keep the repo under `/home`.
- `.wslconfig` caps apply only after `wsl --shutdown` (run from Windows PowerShell).
