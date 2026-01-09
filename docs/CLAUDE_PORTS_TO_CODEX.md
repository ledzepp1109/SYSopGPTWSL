# High-ROI ports from Claude scaffolding into Codex CLI (this repo)

This repo already encodes a lot of the “Claude operator” ideas in a Codex-native way (skills + operator scripts). The best ports are the **principles and workflows**, not Claude-specific config schemas.

## Implemented ports (effective in this repo)

- **Janitor protocol as a Codex skill**: `.codex/skills/janitor/SKILL.md`
  - Triggers on “clean up / cleanup / declutter / delete files / bloat …”
  - Enforces: inventory → present → approval → act → verify
- **WSL↔Windows interop failure handling** (vsock):
  - Manual recovery + sandbox/vsock diagnosis: `sysop/out/fixes/manual_steps.md`
  - AF_VSOCK probe identifies when Codex sandbox blocks interop.

## “Ready to port next” (high leverage)

- **Context priming workflow** (fast session start):
  - Codex equivalent would be a `context-prime` skill that reads `AGENTS.md`, `sysop/README_INDEX.md`, then runs `./sysop/run.sh health` and summarizes anomalies.
- **Safety tiers as an operator rubric**:
  - Convert the Windows “Tier 0–3” model into a Codex skill that tags actions as:
    - Tier 0: read-only
    - Tier 1: repo-scoped reversible edits
    - Tier 2–4: generate-only scripts under `sysop/out/fixes/`
- **“Write script → run script” rule for PowerShell**:
  - When Windows interop is available, Codex should prefer generating `.ps1` files and running them, not inline `powershell -Command ...` (prevents quoting/path mangling).

## Claude-only items (don’t port verbatim)

- `.claude/settings*.json` schema and `autoApproval` fields
- Claude hook lifecycle + tool identifiers
- Claude Desktop MCP config format (store it as reference only)

## Source material (for harvesting)

The deduped seed catalogue includes the original Claude wiring and is designed for cherry-picking:
- `sysop/out/fixes/SYSopClaudeWSL_seed/canon/CODEX_CROSSWALK.md`
- `sysop/out/fixes/SYSopClaudeWSL_seed/canon/START_HERE.md`
