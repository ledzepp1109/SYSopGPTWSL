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

### 2026-01-09 (Claude operator wiring on WSL)
- Mistake: Assuming `claude` is installed and pointing at the canonical operator spec without checking (leading to inconsistent behavior across shells/profiles).
- Fix: Verify with `./sysop/claude/check_wsl.sh`; if needed, generate a manual repair script via `./sysop/claude/gen_fix_wsl_operator.sh`.
- Proof (command + expected key lines): `./sysop/claude/check_wsl.sh` → `Summary: ... FAIL=0`
- Scope / when it applies: when using Claude Code (`claude`) inside WSL.

### 2026-01-09 (HD NotebookLM video processing resume + MediaPipeline AV1 mismatch)
- Mistake: Hardcoding video encode strategies (e.g. `["av1","h264"]`) while config only defines `h264`, causing crashes mid-run and making “resume from checkpoint” unreliable.
- Fix: Derive strategies from config keys (and guard lookups with `.get(...)`); use an append-only manifest + checkpoint file for resumable processing.
- Proof (Windows PowerShell, copy/paste runnable):
  - Tool preflight: `powershell -ExecutionPolicy Bypass -File projects/hd-notebooklm/video/Resume-HDVideos.ps1 -SelfTest -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_video"`
  - Resume run (checkpoint 251/860): `powershell -ExecutionPolicy Bypass -File projects/hd-notebooklm/video/Resume-HDVideos.ps1 -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_video" -StartAfter 251 -Resume`
  - MediaPipeline patch artifact: `projects/hd-notebooklm/video/MediaPipeline_av1_h264_fix.patch`
- Scope / when it applies: any HD/NotebookLM video processing pipeline that needs to resume safely after failures.

### 2026-01-15 (WSL ↔ Windows hybrid automation)
- Mistake: Expecting Windows tools (for example `powershell.exe`) to be callable from WSL without confirming WSL interop and PATH wiring; running Windows commands from a UNC-backed cwd.
- Fix: Enable `/etc/wsl.conf` `[interop] appendWindowsPath=true` (manual host change) and run Windows commands from a drive-backed cwd (`/mnt/c`) with explicit `.exe` names.
- Proof (command + expected key lines):
  - `./sysop/healthcheck.sh | rg -n "appendWindowsPath=true"`
  - `(cd /mnt/c && powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion")`
- Scope / when it applies: any cross-OS workflow (Windows snapshot collection, power plan queries, hybrid automation from Codex/Claude).
