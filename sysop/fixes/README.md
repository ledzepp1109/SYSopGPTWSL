## sysop auto-fix taxonomy (repo-scoped)

Goal: enable safe, semi-autonomous remediation of detected issues via `./sysop/run.sh all --apply-fixes`.

This repo enforces a hard boundary: **no writes outside the repo** (and never to `/etc`). Any fix that would modify host/Windows config is **generate-only**.

### Risk levels

| Level | Name | Auto-apply? | What it means in this repo |
|---:|---|---|---|
| 1 | SAFE | Yes (only with `--auto-approve-safe`, otherwise prompt) | Idempotent, repo-scoped changes (mostly re-running steps and backing up artifacts). |
| 2 | GENERATE | Yes | Generates scripts/instructions under `sysop/out/fixes/` for manual review. |
| 3 | MODIFY | Prompt required | Not executed when target is outside the repo; emits generate-only output instead. |
| 4 | MANUAL | Never | Emits instructions only. |

### Usage

```bash
# Diagnostics only
./sysop/run.sh all

# Enable fixes: Level 1 (prompted), plus Level 2 generators
./sysop/run.sh all --apply-fixes

# Auto-apply Level 1 SAFE fixes (still never modifies outside the repo)
./sysop/run.sh all --apply-fixes --auto-approve-safe

# Show what would happen (no fix writes, no generated scripts; diagnostics still run)
./sysop/run.sh all --apply-fixes --dry-run
```

### Outputs

Generated artifacts go under:
- `sysop/out/fixes/`

Each fix appends an `[AUTO-FIX]` entry to:
- `learn/LEDGER.md`
