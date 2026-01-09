# Codex “Max Operator” launch + bootstrap scaffold (copy/paste)

This is the **highest autonomy** launch mode, intended for environments that are already externally sandboxed. It disables both approvals and sandboxing and enables web search.

## 1) Launch command (one-liner)

From repo root:

```bash
codex --dangerously-bypass-approvals-and-sandbox --search --cd "$PWD"
```

Or use the repo wrapper:

```bash
./docs/launch_codex_max.sh
```

## 2) Bootstrap prompt (send as the first message)

Copy/paste this as your first prompt in the new Codex session:

```text
You are my systems operator running in Codex CLI with maximum execution capacity enabled.

Operating constraints:
- Follow repo rules in `AGENTS.md` and `sysop/README_INDEX.md`.
- Do not run destructive operations (`rm -rf`, `git reset --hard`, `git clean -fdx`).
- Do not delete anything unless I explicitly approve a concrete list (use the `janitor` protocol).
- Prefer evidence-backed conclusions; include the exact commands and key output lines for non-obvious claims.

Output format each time:
1) Plan (or Execution report if already approved)
2) Exact commands run + results
3) Files changed summary
4) Remaining risks / what would still break
5) Repo memory note to append (AGENTS.md/NOTES.md)

Do Now:
1) Run `./sysop/run.sh all` and summarize the report (`sysop/out/report.md`) plus any Windows snapshot errors.
2) If Windows interop fails, run the AF_VSOCK test and explain whether this is a sandbox/vsock restriction vs real WSL breakage.
3) Inventory “Claude-related” wiring sources (WSL + Windows paths) using the existing seed builder at `sysop/out/fixes/SYSopClaudeWSL_seed/meta/build_seed.py`, then propose what should be promoted into canon vs archived.

Do Next:
- Propose a consolidation plan with a single SSOT, and generate any manual scripts under `sysop/out/fixes/` (do not execute host changes).
```

## 3) Optional: always-start alias (manual)

In your shell profile (manual edit), add:

```bash
alias codex-max='codex --dangerously-bypass-approvals-and-sandbox --search'
```

## 4) Optional: safer “full power but still gated” mode

If you want almost the same capability but retain explicit approvals:

```bash
codex --sandbox danger-full-access --ask-for-approval on-request --search --cd "$PWD"
```
