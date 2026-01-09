# NOTES (SYSopGPTWSL)

This file is durable, repo-local operator memory for Codex + humans.
Prefer appending new entries (don’t rewrite history unless correcting a factual error).

## Avoid repeating this (append-only)

Template (copy/paste):
- Mistake:
- Fix:
- Proof (command + expected key lines):
- Scope / when it applies:

### 2026-01-09 (Codex operator workflow)
- Mistake: Starting edits or running write-producing commands (for example `./sysop/run.sh all`) without an approved plan; mixing multiple tasks in one worktree.
- Fix: Intake → Plan gate; one worktree per task under `wt/<task-slug>`; verify every change and report results.
- Proof (copy/paste runnable):
  - Worktree creation: `./sysop/wt-new.sh example-task`
  - Read-only verification: `./sysop/preflight.sh`
  - Guardrail check: `codex execpolicy check --rules .codex/rules/sysop.rules --pretty rm -rf /`
- Scope / when it applies: every Codex session in this repo.
