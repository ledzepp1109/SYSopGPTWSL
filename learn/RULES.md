# Operator Kernel Rules (machine-readable)

These rules are intentionally small, stable, and grounded in repeated WSL/Windows operator failures.

## Rule 1) Index-first

### Pattern
- Description: Before acting, read `AGENTS.md`, then `sysop/README_INDEX.md` (index-first).

### Symptom
- You start making changes or running commands without understanding repo boundaries, outputs, or operator flow.

### Fix

```bash
sed -n '1,200p' AGENTS.md
sed -n '1,200p' sysop/README_INDEX.md
```

### Evidence
- LEDGER timestamp: `2026-01-04T23:56:22-06:00`
- Frequency: Applies to every operator session
- Impact: High (prevents policy violations and wasted work)

### Encoded
- In: `AGENTS.md`, `sysop/README_INDEX.md`, `.codex/skills/sysop-kernel/SKILL.md`
- Verify:

```bash
rg -n "Index-first|AGENTS\\.md|README_INDEX\\.md" AGENTS.md sysop/README_INDEX.md .codex/skills/sysop-kernel/SKILL.md
```

## Rule 2) Safety boundary

### Pattern
- Description: Never run destructive ops (`rm -rf`, `git reset --hard`, `git clean -fdx`); never write outside this repo or to `/etc`.

### Symptom
- You are about to “clean up” or “reset” state aggressively, or a command would write to system paths.

### Fix
- Prefer read-only commands first; when writing, confine changes to the repo and keep them reversible.

```bash
# Read-only first
git status
rg -n "TODO|FIXME" .

# If you must change files, keep it inside the repo:
./sysop/run.sh all
```

### Evidence
- LEDGER timestamp: `2026-01-04T23:56:22-06:00`
- Frequency: Applies to every operator session
- Impact: Critical (prevents data loss and system drift)

### Encoded
- In: `AGENTS.md`, `.codex/skills/sysop-kernel/SKILL.md`
- Verify:

```bash
rg -n "Safety boundaries|rm -rf|git reset --hard|git clean -fdx|/etc" AGENTS.md .codex/skills/sysop-kernel/SKILL.md
```

## Rule 3) Windows/WSL interop (UNC cwd)

### Pattern
- Regex: `^\\\\\\\\wsl\\$\\\\` (UNC cwd on the Windows side)
- Description: Run Windows commands from a drive-backed cwd (`/mnt/c`) to avoid UNC cwd problems.

### Symptom
- Windows commands fail or warn when launched from WSL paths (especially if the Windows process inherits a UNC cwd).

### Fix

```bash
SCRIPT_WIN="$(wslpath -w "$PWD/sysop/windows/collect-windows.ps1")"
OUT_WIN="$(wslpath -w "$PWD/sysop/out")"
(cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_WIN" -OutDir "$OUT_WIN")
```

For one-off Windows utilities:

```bash
(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)
```

### Evidence
- LEDGER timestamp: `2026-01-04T22:13:25-06:00`
- Frequency: Observed repeatedly (3 baseline runs in `learn/LEDGER.md`)
- Impact: High (Windows snapshot step can fail or behave inconsistently)

### Encoded
- In: `sysop/run.sh`, `sysop/windows/RUN.md`
- Verify:

```bash
rg -n "cd /mnt/c" sysop/run.sh sysop/windows/RUN.md
rg -n "UNC cwd|\\\\\\\\wsl\\$" sysop/README_INDEX.md
```

## Rule 4) Windows JSON (UTF-8 BOM)

### Pattern
- Description: Parse snapshot JSON with `utf-8-sig` because PowerShell may emit UTF-8 with a BOM.

### Symptom
- JSON parsing fails on `sysop/out/windows_snapshot.json` even though the file “looks like JSON”.

### Fix

```python
import json

with open("sysop/out/windows_snapshot.json", "r", encoding="utf-8-sig") as f:
    data = json.load(f)
```

### Evidence
- LEDGER timestamp: `2026-01-04T22:13:25-06:00`
- Frequency: Observed repeatedly (3 baseline runs in `learn/LEDGER.md`)
- Impact: High (report generation and post-processing can fail)

### Encoded
- In: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/RUN.md`
- Verify:

```bash
rg -n "utf-8-sig" sysop/run.sh sysop/perf/summarize.sh sysop/windows/RUN.md
```

## Rule 5) Filesystem perf (`/home` vs `/mnt/c`)

### Pattern
- Description: Keep perf-critical work under `/home`; `/mnt/c` is drvfs/9p and slower.

### Symptom
- Builds, benches, and file-heavy workflows are unexpectedly slow.

### Fix
- Keep this repo under `/home/...` and only touch `/mnt/c` when interop is required.

```bash
pwd  # should be /home/.../SYSopGPTWSL (not /mnt/c/...)

# Optional: copy artifacts to Windows only when needed
cp -f sysop/out/report.md "/mnt/c/Users/<WindowsUser>/Desktop/sysop-report.md"
```

### Evidence
- LEDGER timestamp: `2026-01-04T22:13:25-06:00` (records `/mnt/c` mount as 9p/drvfs)
- Frequency: Common in WSL2 workloads that touch Windows files
- Impact: Medium–High (can dominate end-to-end runtime)

### Encoded
- In: `sysop/run.sh` (tiny FS compare), `sysop/perf/summarize.sh` (bottleneck callout), `sysop/README_INDEX.md`
- Verify:

```bash
rg -n "/mnt/c|drvfs|9p|Tiny FS compare" sysop/run.sh sysop/perf/summarize.sh sysop/README_INDEX.md
```

---

Footer: This structured format is intentionally machine-readable, enabling future AI-driven rule compilation, automated verification, and recursive improvement from new `learn/LEDGER.md` evidence.
