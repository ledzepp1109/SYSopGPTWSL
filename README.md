# SYSopGPTWSL

GPT/Codex-native operator assets for this WSL Ubuntu environment.

## Contents
- `sysop/`: read-only scripts and operator notes
  - `sysop/preflight.sh`
  - `sysop/healthcheck.sh`
- `sysop-report/`: baseline + ongoing notes
  - `sysop-report/2026-01-04_wsl_sysop.md`

## Usage
- Run `sysop/preflight.sh` first, then `sysop/healthcheck.sh`.
- Or run the operator kernel: `./sysop/run.sh all` (writes `sysop/out/` and appends to `learn/LEDGER.md`).
- Consult `sysop-report/2026-01-04_wsl_sysop.md` for current baseline + operator notes.

## Codex workflow
- Follow `AGENTS.md` (Plan-first; worktrees per task; verification required).
- Treat `./sysop/run.sh ...` as EXECUTION MODE because it writes artifacts under `sysop/out/`.
