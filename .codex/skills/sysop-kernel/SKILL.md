---
name: sysop-kernel
description: Run the SYSopGPTWSL operator kernel (repeatable sysop pipeline + diffable report + learning ledger), using Plan-first execution and explicit verification reporting.
metadata:
  short-description: Run sysop operator kernel
---

# SYSop Operator Kernel (skill)

Follow `AGENTS.md` (Plan-first; worktrees per task when parallel; verification required; auditable notes).

## Plan mode (no writes yet)
1) Read `AGENTS.md`, then `sysop/README_INDEX.md` (index-first).
2) Restate the operator goal (health/drift/snapshot/bench/report).
3) Define “done means…”:
   - fresh artifacts under `sysop/out/` (at least `sysop/out/report.md`)
   - if `./sysop/run.sh` is executed: a new entry appended to `learn/LEDGER.md`
4) Hypotheses (when something fails):
   - Windows interop unavailable (for example `powershell.exe`/vsock errors)
   - UNC cwd issues (Windows commands must run from `/mnt/c`)
   - `systemctl` bus blocked in the Codex runner (expected)
5) Minimal evidence (read-only) to gather as needed:
   - `./sysop/preflight.sh`
   - `./sysop/healthcheck.sh`
   - `command -v powershell.exe` (if Windows snapshot is requested)
6) Propose the exact `./sysop/run.sh ...` command(s) and STOP for approval:
   - `./sysop/run.sh all` (writes under `sysop/out/` and appends to `learn/LEDGER.md`)

## Execution mode (after approval)
- Run the approved `./sysop/run.sh ...` command(s) from repo root.
- Return results using the repo output format (see `AGENTS.md`), including:
  - report path: `sysop/out/report.md`
  - “Top bottlenecks” excerpt (if present)
  - latest `learn/LEDGER.md` excerpt (3–8 lines)

## Safety
- No destructive ops (`rm -rf`, `git reset --hard`, `git clean -fdx`).
- No writes outside the repo or to `/etc`.
- No internet fetches.

For details and rationale, see `references/OPERATOR_KERNEL.md`.
