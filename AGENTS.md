# GPT/Codex WSL Sysop Repo

## Index-first
- Read `AGENTS.md` first, then `sysop/README_INDEX.md` before acting.

## Codex operator contract (non-negotiable)
- Start in PLAN MODE: no edits and no write-producing commands until a human approves the plan.
- Intake first: identify tasks, then choose sequential vs parallel; if parallel, one worktree per task (`wt/<task-slug>`).
- One worktree per task: never mix unrelated changes; each worktree gets its own branch.
- Verification required: every change ends with the relevant tests/build/lint (or closest available verification) and reported results.
- Falsifiable debugging: for each bug, propose 2–3 hypotheses, then collect the minimum evidence to confirm one.
- Auditable work: small commits, stable reproduction steps, and clear per-worktree notes.
- Durable repo memory: after success, append an “avoid repeating this” note to `NOTES.md` (mistake → fix → proof command).

## Workflow (A→G)

### A) Intake → choose concurrency shape
- Identify tasks (feature A, bug B, refactor C).
- Decide: sequential vs parallel.
- If parallel: create one worktree per task (hard boundary) before editing anything.

### B) Plan mode (no edits yet)
- Define “done means…” checks (tests passing, build clean, UI fixed).
- For each bug: generate 2–3 plausible hypotheses (especially UI).
- Decide minimal evidence to confirm one hypothesis.
- Draft an execution checklist (ordered steps + verification gates).
- STOP and ask for approval before proceeding to execution.

### C) State isolation (worktrees)
- Create one worktree per task: `wt/<task-slug>`.
- Ensure each worktree has its own branch.
- Helper: `./sysop/wt-new.sh <task-slug> [base-ref]`.
- Keep cross-task changes forbidden unless explicitly planned.

### D) Execute (edits happen now)
- Apply changes exactly as per the approved plan.
- Keep commits small inside each worktree.
- For UI: collect evidence via browser automation if available; save artifacts to stable paths for diffing.

### E) Verification loop (non-negotiable)
- Run unit/integration tests.
- Run build/lint/typecheck.
- If UI: run Playwright (or equivalent) and compare screenshots.
- If failed: update hypothesis → gather only missing evidence → retry.

### F) Review + integrate
- Produce a concise review note per worktree: what changed, why it should work, how it was verified.
- Human reviews and commits/merges (or explicitly tells Codex to proceed).
- Optional: PR stacking/reorder when multiple PRs exist; keep each PR a composable slice.

### G) Durable memory capture (Codex-side)
- Write “gotchas” into `NOTES.md` (or `AGENTS.md`): mistake → fix → test that proves it.
- Record repeatable commands (copy/paste runnable).

## Safety boundaries (repo)
- Never run destructive ops: `rm -rf`, `git reset --hard`, `git clean -fdx`.
- Never write outside this repo or to `/etc`.
- Do not change WSL interop settings or mount options.
- Do not fetch from the internet; work only with local repo content.
- Prefer Linux-native repos under `/home` (avoid `/mnt/c` unless required).

## Interop status (WSL ↔ Windows)
- As of `2026-01-15`, WSL is configured with `/etc/wsl.conf` `[interop] appendWindowsPath=true`, enabling calls to Windows binaries from WSL (for example `powershell.exe`, `pwsh.exe`, `powercfg.exe`).
- Treat Windows `.exe` calls as host actions: prefer a drive-backed cwd (`/mnt/c`) and beware PATH precedence (Windows tools can shadow Linux ones).
- Note: some sandboxed runners block WSL↔Windows interop even when PATH is present (symptom: `UtilBindVsockAnyPort: ... socket failed 1`); fall back to a normal interactive WSL shell or native Windows PowerShell.

## Safety boundaries (auto-fix mode)
Auto-applied (Level 1):
- ✅ Repo-scoped retries and artifact regeneration with backups + rollback commands.

Generated only (Level 2–4):
- ✅ PowerShell/scripts/instructions for manual review under `sysop/out/fixes/`.

Never auto-applied:
- ❌ Any host/system change (e.g., `.wslconfig`, power plan changes, `wsl --shutdown`, package installs).

## Operating rules
- Read-only first: propose changes before edits/installs.
- Evidence discipline: back non-obvious claims with `man`/`--help` output or command results.
- Idempotent edits only; avoid duplicate lines in dotfiles.
- Backups + rollback: before editing a file outside the repo, create `*.bak-YYYYMMDD-HHMMSS` next to it and print the rollback command.

## Output format (every response)
1) Plan (or Execution report if already approved)
2) Exact commands run + results
3) Files changed summary
4) Remaining risks / what would still break
5) Repo memory note to append (`AGENTS.md`/`NOTES.md`)

## Fresh-state practice
- If context gets messy, write a short summary to `learn/LEDGER.md` and continue.

## Repo layout
- `sysop/`: operator scripts (`preflight.sh`, `healthcheck.sh`) and local operator README.
- `sysop-report/`: living report(s); append updates rather than creating new reports unless necessary.
