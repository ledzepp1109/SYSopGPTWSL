# SYSopGPTWSL

GPT/Codex-native operator assets for this WSL Ubuntu environment.

Requires Codex CLI `>=0.76.0`.

Setup guide: `docs/CODEX_SETUP.md`

## Contents
- `sysop/`: read-only scripts and operator notes
  - `sysop/preflight.sh`
  - `sysop/healthcheck.sh`
- `sysop/claude/`: Claude-on-WSL verification helpers
  - `sysop/claude/check_wsl.sh`
- `sysop-report/`: baseline + ongoing notes
  - `sysop-report/2026-01-04_wsl_sysop.md`
  - `sysop-report/2026-01-05_claude_docs_audit.md`
- `docs/`: operator docs
  - `docs/CLAUDE_WSL_OPERATOR.md`

## WSL-specific gotchas

- `learn/RULES.md` (UNC cwd, PowerShell UTF-8 BOM, `/home` vs `/mnt/c` perf)
- Hybrid automation from WSL into Windows (PowerShell/Windows binaries): `docs/CODEX_SETUP.md`

## Usage
- Run `sysop/preflight.sh` first, then `sysop/healthcheck.sh`.
- Or run the operator kernel: `./sysop/run.sh all` (writes `sysop/out/` and appends to `learn/LEDGER.md`).
- Consult `sysop-report/2026-01-04_wsl_sysop.md` for current baseline + operator notes.

## Quick start (Codex)

From the repo root:

1. Start Codex: `codex`
2. Trigger the sysop skill by typing: `sysop`
3. Follow the Plan → Approval flow, then run the operator kernel: `./sysop/run.sh all`

## Codex workflow
- Follow `AGENTS.md` (Plan-first; worktrees per task; verification required).
- Treat `./sysop/run.sh ...` as EXECUTION MODE because it writes artifacts under `sysop/out/`.
- Worktree helper: `./sysop/wt-new.sh <task-slug> [base-ref]`

## Design decisions

- Air-gap compatible: no MCP integration and no internet fetching required for normal operation.
- No shipped `config.toml`: operator policy is documented, but config remains user-scoped at `~/.codex/config.toml`.
