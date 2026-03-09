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

### 2026-01-15 (HD NotebookLM omnibus — Windows fallbacks)
- Mistake: Assuming `pdfsam-console` and Microsoft Word COM are always present; using a PowerShell helper param named `Args` (can break argument forwarding and leave Ghostscript stuck at `GS>`).
- Fix: Add Ghostscript merge fallback (`gswin64c.exe` + `-sOutputFile=...`), retry `/screen` on oversize; add LibreOffice fallback for DOC/DOCX conversion; rename helper param to `ArgumentList`.
- Proof (command + expected key lines):
  - Build: `pwsh.exe -NoProfile -ExecutionPolicy Bypass -File projects/hd-notebooklm/omnibus/Build-HDOmnibus.ps1 -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_build_auto\run_20260115-224244" -SelectionCsv "G:\My Drive\Human Design Experiments\Omnibus_v1\_build_auto\run_20260115-224244\_plans\hd_omnibus_selection.csv"` → `Build complete.`
- Scope / when it applies: building NotebookLM omnibus PDFs on Windows machines without PDFsam/Word installed.

### 2026-03-06 (Repo-local Codex recursive audit mode)
- Mistake: Adopting external Codex recipes without validating local feature gates, project-layer loading, or this repo’s no-internet / plan-first rules.
- Fix: Ship repo-local `.codex/config.toml` plus `researcher/challenger/implementer/verifier` role files, and make `sysop` probes check that the project config, role files, and `multi_agent` feature are actually active.
- Proof (command + expected key lines):
  - `./sysop/preflight.sh` → `PASS: repo-local Codex config present` and `PASS: multi_agent feature enabled`
  - `./sysop/drift-check.sh` → `PASS: multi_agent feature enabled via effective config`
  - `./sysop/run.sh all` → `sysop/out/report.md` contains `### Codex posture`
- Scope / when it applies: any Codex run in this repo that expects recursive self-audit behavior from repo-local config instead of one-off prompt text.

### 2026-03-06 (Audit web search vs shell network)
- Mistake: Treating native Codex web search and shell-command network access as the same switch makes audit mode either too weak or too permissive.
- Fix: Enable `web_search = "live"` in the repo-local audit config and audit roles, while keeping `[sandbox_workspace_write] network_access = false` so shell commands stay offline and writes stay repo-local.
- Proof (command + expected key lines):
  - `rg -n 'web_search = "live"|network_access = false' .codex/config.toml .codex/agents/*.toml`
  - `./sysop/preflight.sh` → `PASS: audit web search enabled in repo-local Codex config`
  - `./sysop/drift-check.sh` → `PASS: repo-local Codex config keeps shell command network access disabled`
  - `./sysop/run.sh all` → `sysop/out/report.md` shows both `audit web search` and `shell command network access remains disabled`
- Scope / when it applies: the dedicated recursive audit worktree/mode for Codex in this repo.

### 2026-03-06 (Configured vs loaded vs demonstrated Codex posture)
- Mistake: Treating config text or a confounded `--search` session as proof that repo-local Codex posture was loaded makes the audit system overclaim its own runtime state.
- Fix: Label Codex posture as `configured`, `loaded`, `demonstrated`, or `unproven`; compare repo-root vs `/tmp` for load signals like `multi_agent`; surface `codex` stderr warnings; and treat web-search success in a session launched with `--search` as confounded rather than dispositive.
- Proof (command + expected key lines):
  - `./sysop/preflight.sh` → `CONFIGURED: repo-local Codex config present`, `LOADED: multi_agent is true from repo root and not true from /tmp`, `UNPROVEN: fresh-session attribution test still required for repo-local web search`
  - `./sysop/drift-check.sh` → `LOADED: codex features list (repo root) emitted stderr warnings` if present, plus the same configured/loaded/unproven distinctions
  - `./sysop/healthcheck.sh` → `[codex --help | rg -- --search]` and `[/tmp: codex features list | rg]`
- Scope / when it applies: any repo-local Codex audit that needs trustworthy claims about what is merely configured versus actually loaded or demonstrated.

### 2026-03-06 (Fresh Codex runtime controls)
- Mistake: Treating a disposable sibling from `git worktree add ... HEAD` as a faithful fresh-session control when the active `.codex/` scaffold is uncommitted, or trusting `resume` to stay in the original worktree.
- Fix: Commit the active scaffold first or mirror the exact runtime files into the disposable control explicitly; after `codex exec resume <SESSION_ID>`, always run `pwd` and `git branch --show-current` before any edit. For non-interactive search probes, prefer explicit config overrides such as `-c 'web_search="live"'` over assuming `codex exec --search` works.
- Proof (command + expected key lines):
  - `./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold` → a disabled control reports `SEARCH=no` and an override-live control reports `SEARCH=yes`
  - `./sysop/codex-runtime-probe.sh resume-cwd --create-controls --mirror-scaffold` → `resume-from-repo` and `resume-from-live` report different `PWD=` / `BRANCH=` values for the same session id
  - `codex exec --search noop` → `unexpected argument '--search' found`
- Scope / when it applies: any Codex fresh-session attribution or cross-worktree resume probe in this repo.

### 2026-03-09 (Mixed runtime artifacts must not be merged into one proof)
- Mistake: Treating a later usage-limited rerun as interchangeable with the earlier successful search-matrix run made the repo easy to overread, because `sysop/out/verify-search-matrix/search-disabled-override-live.log` failed while `sysop/out/codex-runtime-20260306-154230/search-disabled-override-live.log` succeeded.
- Fix: Name the exact artifact directory that supplied a claim, and mark later usage-limited reruns as `inconclusive` instead of silently restating the old conclusion as if the newest logs proved it.
- Proof (command + expected key lines):
  - `rg -n '^SEARCH=' sysop/out/codex-runtime-20260306-154230/search-*.log` → disabled control `SEARCH=no`, override-live control `SEARCH=yes`
  - `rg -n 'usage limit' sysop/out/verify-search-matrix/search-disabled-override-live.log` → later rerun failed and should not be cited as a successful override-live proof
  - `./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold` → emits `RESULT=pass` only on a clean split, otherwise `RESULT=inconclusive`
- Scope / when it applies: any repo-local Codex runtime proof that mixes archived successful controls with newer but failed reruns.

### 2026-03-09 (Shell-network isolation must be runtime-proven, not inferred)
- Mistake: Treating `[sandbox_workspace_write].network_access = false` as sufficient proof left shell-network isolation partly trust-based.
- Fix: Add a dedicated runtime probe that establishes host-side network reachability, then proves both `codex sandbox linux --full-auto` and repo-root `codex exec` reject outbound socket creation with `PermissionError: [Errno 1] Operation not permitted`.
- Proof (command + expected key lines):
  - `./sysop/codex-network-denial-probe.sh` → `RESULT=pass`
  - `/tmp/.../host-control.log` → `HTTP_CODE=200`
  - `/tmp/.../direct-sandbox-socket.log` and `/tmp/.../repo-exec-socket.log` → `PermissionError: [Errno 1] Operation not permitted`
- Scope / when it applies: any claim that Codex shell networking is strictly denied rather than merely configured off.
