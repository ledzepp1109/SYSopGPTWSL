# sysop index (Operator Kernel)

## Codex workflow (Plan-first)
- Treat `./sysop/run.sh ...` as EXECUTION MODE: it writes under `sysop/out/` and appends to `learn/LEDGER.md`.
- In PLAN MODE, prefer read-only probes (`./sysop/preflight.sh`, `./sysop/healthcheck.sh`) to gather evidence.
- If this sysop work is one task among many, isolate it in its own worktree/branch (see `AGENTS.md`).
- Worktree helper: `./sysop/wt-new.sh <task-slug> [base-ref]`.

One command (after plan approval):
- `./sysop/run.sh all`

Auto-fix mode (repo-scoped; generates scripts for manual host changes):
- `./sysop/run.sh all --apply-fixes`
- `./sysop/run.sh all --apply-fixes --auto-approve-safe`
- `./sysop/run.sh all --apply-fixes --dry-run`

Outputs (diffable, overwritten each run):
- `sysop/out/report.md`
- `sysop/out/windows_snapshot.json`
- `sysop/out/wsl_snapshot.txt`
- `sysop/out/bench.txt`

Notes:
- Windows snapshot is best-effort: if Windows interop is unavailable, `windows_snapshot.json` is a placeholder with an error and the run continues.
- `/mnt/c` microbench is skipped by default (set `SYSOP_ALLOW_MNT_C_BENCH=1` to enable).
- Auto-fix artifacts (generated scripts/instructions): `sysop/out/fixes/` (see `sysop/fixes/README.md`).

## Reused scripts
- `sysop/preflight.sh` — fast read-only sanity checks
- `sysop/healthcheck.sh` — broader WSL audit (note: `systemctl` can be blocked in the Codex runner)
- `sysop/drift-check.sh` — invariants check vs `sysop-report/2026-01-04_wsl_sysop.md`
- `sysop/claude/check_wsl.sh` — verifies Claude-on-WSL wiring (CLI + entrypoint doc + ops-operator SSOT)
- `sysop/windows/collect-windows.ps1` — Windows snapshot collector
- `sysop/perf/wsl-bench.sh` — WSL microbench (CPU/mem/disk)
- `sysop/perf/summarize.sh` — parses snapshots + bench into a report

## Self-tests (no network)
- `./sysop/run.sh health`
- `./sysop/run.sh snapshot`
- `./sysop/run.sh bench`
- `./sysop/run.sh report`
- `./sysop/claude/check_wsl.sh`
- `codex execpolicy check --rules .codex/rules/sysop.rules --pretty rm -rf /`
- `codex execpolicy check --rules .codex/rules/sysop.rules --pretty git status`

## Debugging with `/ps` Command (Codex CLI `>=0.76.0`)

When a run appears “stuck” (long PowerShell call, blocked `systemctl`, slow IO), use `/ps` inside Codex CLI to inspect active subprocesses and their state.

Examples (in the Codex CLI chat):

```text
/ps
```

When to use:
- A command is taking longer than expected and you want to confirm it is still running.
- You suspect a subprocess is blocked (e.g., `powershell.exe`, `wslpath`, `systemctl`, `dd`).
- You need visibility before deciding whether to stop/retry with a smaller step (e.g., `./sysop/run.sh snapshot` vs `./sysop/run.sh all`).

## Common Error Recovery

Cross-reference:
- Rules: `../learn/RULES.md`
- Evidence: `../learn/LEDGER.md` (see `2026-01-04T22:13:25-06:00` for extracted interop rules)

### PowerShell BOM Issue (Rule #4)

Symptom:
- `json.load(...)` fails on `sysop/out/windows_snapshot.json`, or tools complain about “invalid JSON”.

Root cause:
- Windows PowerShell may emit UTF-8 JSON with a BOM prefix.

Fix (Python):

```python
import json

with open("sysop/out/windows_snapshot.json", "r", encoding="utf-8-sig") as f:
    data = json.load(f)
```

Fix (regenerate snapshot):

```bash
./sysop/run.sh snapshot
```

### UNC Path Issues (Rule #3)

Symptom:
- Windows commands fail or warn when invoked from a UNC-backed cwd like `\\\\wsl$\\...`.

Root cause:
- Some Windows tools behave poorly when the *current working directory* is UNC.

Fix (drive-backed cwd for Windows commands):

```bash
SCRIPT_WIN="$(wslpath -w "$PWD/sysop/windows/collect-windows.ps1")"
OUT_WIN="$(wslpath -w "$PWD/sysop/out")"
(cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WIN" -OutDir "$OUT_WIN")
```

Also applies to one-off Windows utilities:

```bash
(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)
```

### Performance: `/home` vs `/mnt/c` (Rule #5)

Guidelines:
- Keep the repo and perf-critical workloads under `/home/...` (Linux filesystem).
- Use `/mnt/c` only for Windows interop needs (Windows commands, copying artifacts to open in Windows apps).

Exceptions:
- If you must hand a file to a Windows GUI app, copy the artifact to a Windows path (temporary or ad-hoc).

Balance strategy:

```bash
# Keep repo in Linux filesystem
pwd  # should be /home/.../SYSopGPTWSL

# Copy an artifact to Windows (only when needed)
cp -f sysop/out/report.md "/mnt/c/Users/<WindowsUser>/Desktop/sysop-report.md"
```

## Known pitfalls
- UNC cwd: run Windows commands from a drive-backed cwd (`/mnt/c`), not from `\\\\wsl$\\...`.
- UTF-8 BOM: Windows JSON may be BOM-prefixed; Linux readers must use `utf-8-sig` (or strip BOM).
- `/mnt/c` perf: drvfs/9p is slower than the Linux filesystem; keep the repo under `/home`.
- `.wslconfig` caps apply only after `wsl --shutdown` (run from Windows PowerShell).
