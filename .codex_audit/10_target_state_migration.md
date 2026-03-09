# Target State Migration

- Timestamp: 2026-03-09 04:45:02 America/Chicago
- Compact source: `/home/xhott/SYSopGPTWSL/.codex_audit/compact-source-of-truth.md`
- Classifier report: `/home/xhott/SYSopGPTWSL/.codex_audit/09_compact_target_diff.md`
- Backup dir: `/home/xhott/SYSopGPTWSL/.codex_audit/migrations/20260309-044502`

## Compact limitation
- The pasted `/compact` blob was a placeholder literal, not an actual runtime dump.
- Result: `09_compact_target_diff.md` correctly classified the compact evidence as missing for every target element.
- Migration decisions therefore used direct local reproduction plus current upstream docs as the operational truth source.

## Live pre-migration classification
Already encoded correctly:
- `~/.codex/config.toml` already existed and already pinned `model = "gpt-5.4"` plus `model_reasoning_effort = "xhigh"`.
- `~/SYSopGPTWSL/.codex/config.toml` already existed and already encoded `model = "gpt-5.4"`, `web_search = "live"`, `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `[sandbox_workspace_write].network_access = false`, `[features].multi_agent = true`, `[agents].max_threads = 4`, `[agents].max_depth = 2`, and all four role registrations.
- `sysop/codex-network-denial-probe.sh` already existed and remained sound under direct inspection.
- Experimental control worktrees already advertised intentional divergence (`codex-fresh-runtime-control`, `codex-search-disabled-control`) and were correctly treated as non-sync targets.

Present but misconfigured:
- Repo-root `.codex/config.toml` used `model_reasoning_effort = "high"` instead of `xhigh`.
- Repo-root `.codex/config.toml` carried extra Phase 2 fields (`personality`, `allow_login_shell`, `check_for_update_on_startup`, `developer_instructions`, `unified_exec`, `shell_snapshot`) rather than the exact Phase 3 logical shape.
- Repo-root `AGENTS.md` described the stage chain but did not hardwire `sysop/sysop-gate.sh` as the authoritative steady-state enforcement point.
- Repo-root role TOMLs were close but not yet in the exact target posture; Implementer was missing explicit workspace network denial.
- `~/.codex/config.toml` lacked trust entries for the existing `~/SYSopGPTWSL/wt/*` worktrees.
- `wt/codex-audit-hardening/.codex/config.toml` still mirrored the older Phase 2 `high` reasoning scaffold.

Completely missing:
- `sysop/sysop-gate.sh` did not exist.
- `sysop/compact-target-diff.py` did not exist.
- `sysop/apply-codex-target-state.sh` did not exist.
- The AGENTS doctrine block required for idempotent upsert and future steady-state enforcement did not exist.

## Applied changes
- Wrote repo-root `/home/xhott/SYSopGPTWSL/.codex/config.toml` to the exact Phase 3 target shape.
- Wrote role files:
  - `/home/xhott/SYSopGPTWSL/.codex/agents/researcher.toml`
  - `/home/xhott/SYSopGPTWSL/.codex/agents/challenger.toml`
  - `/home/xhott/SYSopGPTWSL/.codex/agents/implementer.toml`
  - `/home/xhott/SYSopGPTWSL/.codex/agents/verifier.toml`
- Upserted the `<!-- BEGIN SYSOP GATE DOCTRINE -->` block into `/home/xhott/SYSopGPTWSL/AGENTS.md`.
- Minimally patched `/home/xhott/.codex/config.toml`:
  - preserved unrelated personal settings
  - preserved existing trusted projects
  - ensured `model = "gpt-5.4"`
  - ensured `model_reasoning_effort = "xhigh"`
  - removed stale `steer = true` if present
  - added trust blocks for every existing `/home/xhott/SYSopGPTWSL/wt/*`
- Synced the root Codex scaffold into `/home/xhott/SYSopGPTWSL/wt/codex-audit-hardening` because it is the aligned audit worktree.
- Deliberately did not normalize:
  - `/home/xhott/SYSopGPTWSL/wt/codex-fresh-runtime-control`
  - `/home/xhott/SYSopGPTWSL/wt/codex-search-disabled-control`
  Reason: they are explicit control worktrees with intentionally divergent runtime behavior.
- Added migration/orchestration scripts:
  - `/home/xhott/SYSopGPTWSL/sysop/compact-target-diff.py`
  - `/home/xhott/SYSopGPTWSL/sysop/apply-codex-target-state.sh`
  - `/home/xhott/SYSopGPTWSL/sysop/sysop-gate.sh`

## Wrapper defects found and fixed during live proving
- Trap scope bug:
  - First gate probe left a disposable worktree behind because the `EXIT` trap referenced function-local variables after scope teardown.
  - Fix: moved cleanup state to trap-safe globals and centralized cleanup in `cleanup_on_exit`.
- Invalid JSON Schema for `codex exec --output-schema`:
  - Local `0.112.0` rejected schemas where `const` fields lacked an explicit `"type": "string"`.
  - Fix: added explicit types for all stage `stage` fields.
- Wrong probe control path:
  - The first verifier-fail probe was blocked by Challenger before Verifier ran.
  - Fix: in `--probe-verifier-fail` mode, Challenger is explicitly instructed to PASS when the researcher envelope is narrow and local-only so Verifier becomes the enforcement point.

## Worktree sync decisions
- Synced:
  - `codex-audit-hardening`
- Skipped as intentional controls:
  - `codex-fresh-runtime-control`
  - `codex-search-disabled-control`
- Skipped because no worktree-local `.codex/config.toml` existed:
  - `claude-operator-wsl`
  - `claude-sysop-max-config`
  - `codex-operator-workflow`
  - `crash-20260119`
  - `docx-v29-publication-ready`
  - `hd-omnibus`
  - `hd-omnibus-windows-fallbacks`
  - `hd-video-resume`
  - `skills-workflow-config`
  - `win-perf-audit-20260127`

## Source-of-truth references used
- Official config reference: https://developers.openai.com/codex/config-reference
- Official config basics: https://developers.openai.com/codex/config-basics
- Official AGENTS.md behavior: https://developers.openai.com/codex/agents-md
- Official multi-agent config: https://developers.openai.com/codex/multi-agents
- Official CLI reference: https://developers.openai.com/codex/cli/reference
- Official product note on instruction/source aggregation: https://openai.com/index/unrolling-the-codex-agent-loop/
- Advisory only: GitHub issue about `exec --search` mismatch, used only as secondary context: https://github.com/openai/codex/issues/3496
