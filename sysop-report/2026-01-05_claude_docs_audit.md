# Claude Docs Audit (WSL + Windows) — 2026-01-05

## Scope (what was scanned)

This audit covers Claude-related content in:
- **WSL (Linux filesystem):** `/home/xhott/.claude*`, `/home/xhott/ops-operator`, `/home/xhott/archives`, `/home/xhott/ops_bootstrap/reports/*`
- **Windows user profile (via WSL `/mnt/c`):** `C:\Users\xhott\.claude*`, `C:\Users\xhott\.claude-win-control`, and name-matches in `Documents/`, `Downloads/`, `Desktop/`

Not scanned exhaustively:
- Whole-drive `/mnt/c` recursion (beyond the directories above)
- Other Windows users / other drives

## Executive summary (what you actually have)

You effectively have **two Claude ecosystems**:

1) **WSL / Linux-first (current target architecture)**
- Runtime state: `~/.claude/` (Claude Code on WSL)
- Canonical spec + operator tooling: `~/ops-operator/`
- Global WSL defaults already point to `ops-operator` (`~/.claude/CLAUDE.md`)

2) **Windows / PowerShell-first (legacy / parallel)**
- Multiple profiles: `C:\Users\xhott\.claude`, `.claude-coding`, `.claude-sysadmin`, `.claude-fileops`
- A full legacy orchestrator workspace repo: `C:\Users\xhott\.claude-win-control\`
- Additional one-off docs sitting in `Downloads\` and `Documents\`

The biggest consolidation wins are:
- **Deduplicate exact copies** (several files are byte-identical across WSL archives and Windows workspaces).
- **Separate “tool state” from “human-authored docs”** and move the latter into one canonical knowledge base (SSOT).
- **Move Claude docs out of `Downloads\`** into an “Inbox/Archive” structure.

## Inventory (high-signal)

### WSL (Linux filesystem)

**Claude Code runtime state (WSL):**
- `~/.claude/` — ~16M, ~410 files
  - Key human-authored doc: `~/.claude/CLAUDE.md` (33 lines) → points to `~/ops-operator/config/CLAUDE.md`
  - Tool-managed state: `debug/`, `projects/`, `file-history/`, `todos/`, `settings*.json`, `history.jsonl`
- `~/.claude.json` + `~/.claude.json.backup` — Claude Code local state (top-level keys are non-secret; includes `projects`, onboarding flags, etc.)

**Canonical operator workspace (WSL):**
- `~/ops-operator/` — ~53M, ~1185 files
  - Core spec: `~/ops-operator/config/CLAUDE.md` (293 lines; Linux-first + explicit pwsh bridge)
  - Safety + epistemics: `~/ops-operator/config/epistemic-rules.md`, `~/ops-operator/config/invariants.md`
  - Windows ops reference: `~/ops-operator/docs/windows-operations.md`
  - Archive snapshots: `~/ops-operator/artifacts/from_archive/20251231_181747/*`

**Backups / archived exports (WSL):**
- `~/archives/claude-backup-20251209-180554.tar.gz`
- `~/archives/archive-manifest.txt` / `~/archives/source-manifest.txt` (file lists of what was captured)

### Windows user profile (via `/mnt/c/Users/xhott`)

**Claude Code runtime state + docs (Windows):**
- `C:\Users\xhott\.claude\` — ~39M, ~2594 files (has top-level docs + lots of tool state)
  - Top-level docs: `CLAUDE.md`, `CONFIGURATION.md`, `MEMO.md`, `SETUP_COMPLETE_README.md`, `THROTTLESTOP_CONFIGURATION_GUIDE.md`
  - Contains `agents/`, `commands/`, `hooks/`, `memory/` (human-authored), plus large `debug/`, `projects/`, `file-history/`, etc.
- `C:\Users\xhott\.claude-coding\` — ~1.2M (profile)
- `C:\Users\xhott\.claude-sysadmin\` — ~72K (profile)
- `C:\Users\xhott\.claude-fileops\` — ~12K (profile)
- `C:\Users\xhott\.claude-server-commander\` — ~696K (logs/config)
- `C:\Users\xhott\.claude.md` — PowerShell-via-Git-Bash guidance (133 lines)
- `C:\Users\xhott\.claude-win-control\` — ~1.5M, ~202 files (a full Windows orchestrator repo; many overlapping docs)

**Name-matched “loose” docs (Windows):**
- `Documents\claude-operator-setup-complete.md` (WSL build summary; overlaps with `ops-operator` spec)
- `Downloads\claude-sonnet-45-vscode-agent.md` (902 lines; Copilot/Claude agent profile)
- `Downloads\MANDATORY DOCUMENT CLAUDE PROMPTING.txt` (339 lines)
- `Downloads\✳ Google Drive CLAUDE FIRST TIME SETUP CHAT.txt` (9020 lines transcript; overlaps with summarized setup docs)
- `Downloads\Copy of Claude's _Yolo Mode_ Fixes` + `.txt` (exact duplicates; JSON content)

## Redundancy + consolidation opportunities

### A) Exact duplicates (byte-identical)

These are safe de-duplication targets (keep one “canonical archive” copy, replace others with references or archive-delete after verification):

1) **Legacy CLAUDE.md snapshots duplicated across locations**
- `C:\Users\xhott\.claude\CLAUDE.md`
  - is identical to: `~/ops-operator/artifacts/from_archive/20251231_181747/tier4_claude_md/windows-dot-claude.CLAUDE.md`
  - sha256: `4ea6082ce7350d26a4005b056925411e083585d66f861509106ba9ddc2faf39b`
- `C:\Users\xhott\.claude-coding\CLAUDE.md`
  - is identical to: `~/ops-operator/artifacts/from_archive/20251231_181747/tier4_claude_md/windows-coding.CLAUDE.md`
  - sha256: `9e97a8693703a68cba204ca68fc30ba70151283a808f4043348ebfd5c5a1b097`
- `C:\Users\xhott\.claude-win-control\CLAUDE.md`
  - is identical to: `~/ops-operator/artifacts/from_archive/20251231_181747/tier4_claude_md/win-control.CLAUDE.md`
  - sha256: `069c7efe22cb5d3da8cffdd7a246c79159ba798b51c81269b458ca07fe378f6b`

2) **Legacy agent definitions duplicated across locations**
- `C:\Users\xhott\.claude-win-control\.github\agents\*.md`
  - are identical to files under: `~/ops-operator/artifacts/from_archive/20251231_181747/tier*_*/agents/*.md`
  - example sha256: `claude-sonnet-windows.agent.md` → `3394e78aed698cd50264312489888b20cda960689d065b0855e7782836175330`

3) **Downloads duplicate**
- `Downloads\Copy of Claude's _Yolo Mode_ Fixes` and `Downloads\Copy of Claude's _Yolo Mode_ Fixes.txt` are identical.
  - sha256: `980b0d16bc1dbe02f57b14ecef871af5b6df86e3595cc0cca2539fbef11aaf42`

### B) “Same idea, multiple docs” (high overlap)

These aren’t byte-identical, but are largely redundant in *purpose*:
- `.claude-win-control\` has multiple overlapping onboarding/summary docs (`README.md`, `INDEX.md`, `QUICK_START*.md`, `QUICK_REFERENCE.md`, `SETUP_COMPLETE.md`, `TRANSFER_COMPLETE.md`, etc.).
- `Documents\claude-operator-setup-complete.md` overlaps heavily with the WSL-first “canonical” narrative already codified in `~/ops-operator/config/CLAUDE.md`.
- `Downloads\✳ ... FIRST TIME SETUP CHAT.txt` is a raw transcript that overlaps with curated summaries like `.claude-win-control\GOOGLE_DRIVE_MCP_SETUP.md`.

### C) “Tool state vs documentation” mixing

Several `.claude*` directories mix:
- “state” (debug logs, history, file-history, projects, todos)
- “docs” (CLAUDE.md, MEMO.md, CONFIGURATION.md, commands, agents)

This makes it hard to know what’s authoritative vs incidental.

## Proposed target structure (SSOT + clean runtime)

### Principle 1: Treat `.claude*` as runtime state, not a knowledge base

Keep required runtime files in:
- `~/.claude/` (WSL Claude Code)
- `C:\Users\xhott\.claude*` (Windows Claude Code profiles)

But stop using `.claude*` as the place to store “final docs”, except the minimal `CLAUDE.md` entrypoints.

### Principle 2: One canonical “Claude KB” (version-controlled)

Recommended SSOT (because you already point to it from WSL):
- `~/ops-operator/` as the canonical Claude operator repo

Suggested additions (structure only; content consolidation can be incremental):
```
ops-operator/
  docs/
    index.md
    mcp/
      google-drive.md
    platforms/
      windows-powershell.md
      wsl-bridge.md
    legacy/
      windows-orchestrator/   # archived snapshots / frozen docs
  config/
    profiles/
      windows-coding.md
      windows-sysadmin.md
      fileops.md
```

### Principle 3: Explicit “Inbox” and “Archive” for loose files

On Windows:
- `Documents\Claude\Inbox\` (anything currently living in `Downloads\`)
- `Documents\Claude\Archive\YYYY\...` (historical exports, transcripts, PDFs)

On WSL:
- `~/archives/claude/` (tarballs + manifests; you already have most of this)

## Consolidation plan (copy-first, reversible)

This is intentionally non-destructive. The goal is to end with:
- One SSOT for “how Claude should operate”
- Runtime `.claude*` directories only containing what the tool needs + minimal entrypoint docs
- `Downloads\` drained of long-lived docs

1) **Decide “active mode”**
- Preferred: WSL-first only
- Optional: dual-mode (WSL + Windows), but then enforce a single SSOT and make Windows entrypoints point to it

2) **Move loose docs out of Downloads**
- Move to `Documents\Claude\Inbox\` (or similar), then triage into SSOT or Archive.

3) **De-duplicate exact duplicates**
- Keep the “best home” copy (usually SSOT or Archive), and remove extra copies after confirming hashes match.

4) **Collapse `.claude-win-control` docs**
- Keep only: `README.md` + `INDEX.md` (or a single combined doc) as entrypoints.
- Move the rest under a `docs/` subtree, or archive the entire repo if you’re now WSL-first.

5) **Convert raw transcripts into summaries**
- Keep transcript in Archive.
- Extract a short “how to” into SSOT (example: keep `.claude-win-control/GOOGLE_DRIVE_MCP_SETUP.md`, archive the 9020-line chat log).

## Evidence (commands run + key results)

WSL `.claude` size:
- `du -h --max-depth=1 /home/xhott/.claude` → total ~16M

Windows `.claude*` sizes:
- `du -sh /mnt/c/Users/xhott/.claude*` → `.claude` ~39M; `.claude-win-control` ~1.5M; `.claude-coding` ~1.2M

Exact duplicates (sha256):
- `sha256sum /mnt/c/Users/xhott/.claude/CLAUDE.md /home/xhott/ops-operator/.../windows-dot-claude.CLAUDE.md` → identical
- `sha256sum /mnt/c/Users/xhott/.claude-coding/CLAUDE.md /home/xhott/ops-operator/.../windows-coding.CLAUDE.md` → identical
- `sha256sum /mnt/c/Users/xhott/.claude-win-control/CLAUDE.md /home/xhott/ops-operator/.../win-control.CLAUDE.md` → identical
- `sha256sum "Downloads/Copy of Claude's _Yolo Mode_ Fixes"*` → identical hashes

---

## Update — 2026-01-06 (seed refresh + NotebookLM wiring surfaced)

### Seed bundle refresh

Regenerated: `sysop/out/fixes/SYSopClaudeWSL_seed/` to better match “substantive wiring” goals:
- Excluded Python venv bloat (`.venv/`, `site-packages/`) from `~/ops-operator`
- Added NotebookLM project docs:
  - `C:\Users\xhott\Documents\NotebookLM_HD_Project\MASTER_PLAN.md`
  - `C:\Users\xhott\Documents\NotebookLM_HD_Project\FILE_INVENTORY.md`
  - `C:\Users\xhott\Documents\NotebookLM_HD_Project\LEARNINGS_AND_WORKFLOWS.md`
- Added MediaPipeline implementation:
  - `C:\Users\xhott\Documents\MediaPipeline\`
- Added Claude Desktop MCP wiring:
  - `C:\Users\xhott\AppData\Roaming\Claude\claude_desktop_config.json`
- Added “prior attempt” scripts:
  - `C:\Users\xhott\.claude\tmp\`

Seed stats (post-refresh):
- Unique objects: 319
- Manifest provenance rows: 456

### NotebookLM project map

See: `sysop/out/fixes/SYSopClaudeWSL_seed/canon/NOTEBOOKLM_HUMAN_DESIGN_PROJECT_MAP.md`

### Interop roadblock observed in this Codex/WSL runner

Attempting to execute Windows binaries from WSL (e.g., `powershell.exe`, `cmd.exe`) failed with:
- `WSL ... ERROR: UtilBindVsockAnyPort:307: socket failed 1`

Implication: in this environment, you can read Windows files via `/mnt/c`, but should run Drive-dependent scripts (e.g., anything that needs `G:\My Drive\...`) from native Windows PowerShell.
