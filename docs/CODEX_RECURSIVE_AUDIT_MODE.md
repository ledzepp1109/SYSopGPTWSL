# Codex Recursive Audit Mode

This repo ships a project-local Codex operating scaffold under `.codex/`.
Its job is to keep Codex work here auditable, adversarial, and locally verifiable.

## Governing order

1. System / developer / direct user instructions
2. `AGENTS.md`
3. Project-local `.codex/config.toml`
4. Project-local agent role files under `.codex/agents/`

The repo rules still win.
In particular:
- stay inside this repo/worktree
- native Codex web search is allowed for contemporary upstream audit research
- shell-command network access stays off unless repo rules explicitly change
- do not pretend an already-running session hot-reloaded newly written config

## One-chain execution model

Material work in this repo should follow one chain of custody:

1. Baseline
   - gather observed local evidence with read-only probes, direct file reads, git state, and existing `sysop/` scripts
2. Researcher
   - summarize what the local evidence actually shows
3. Challenger
   - try to falsify the finding or proposed change
4. Implementer
   - edit only after the finding survives challenge review
5. Verifier
   - confirm the claimed effect locally and fail the change if the proof is weak
6. Memory capture
   - append a concise gotcha note to `NOTES.md`

This is a chain of custody, not a hard runtime sandbox.
Until runtime proof says otherwise, treat it as operator-enforced discipline.

## Mandatory gates

No material finding passes unless it survives all four checks:

1. Observed evidence
2. Strongest counterargument
3. Local verification or explicit proof that local verification is not possible
4. Rollback clarity

If any gate fails, the change is blocked.

## Proof states

The recursive audit scaffold should distinguish four different claims:

- `configured`
  - the repo-local files request a behavior
- `loaded`
  - shell-visible runtime state shows the repo layer taking effect
- `demonstrated`
  - the behavior was reproduced without a known confound
- `unproven`
  - current checks cannot prove the behavior safely

These are not interchangeable.
In particular:

- a config grep only proves `configured`
- a feature visible from the repo root but not from `/tmp` is evidence of `loaded`
- a session launched with `--search` is a confounded web-search test case and must not be used to attribute live search to repo-local `web_search = "live"`
- if there is no safe shell-side orchestration path, the full role chain remains `unproven` even when it is described and configured

## Repo-local files

- `.codex/config.toml`
  - project defaults for sandbox, approvals, feature gates, and agent wiring
- `.codex/agents/researcher.toml`
  - local-first evidence collector
- `.codex/agents/challenger.toml`
  - adversarial blocker
- `.codex/agents/implementer.toml`
  - constrained change agent
- `.codex/agents/verifier.toml`
  - local verification blocker
- `.codex/rules/sysop.rules`
  - minimal `execpolicy` guardrails for destructive or repo-prohibited command prefixes

## Existing sysop flow

The `sysop/` scripts remain the primary local audit path.
This scaffold augments them by making Codex posture part of the audit surface:

- `sysop/preflight.sh`
- `sysop/healthcheck.sh`
- `sysop/drift-check.sh`
- `sysop/run.sh all`

## Research posture

This mode intentionally separates two things:

- Native Codex web search
  - enabled for contemporary upstream research during audit work
  - use official docs, changelogs, release notes, and primary sources first
- Shell command networking
  - remains disabled via repo-local sandbox settings
  - no outbound fetches from `curl`, `npm`, `git`, or similar shell commands unless repo rules explicitly change

This keeps upstream research available without weakening repo-local write containment.

## Current limits

- `multi_agent`
  - can be partially load-checked from shell by comparing `codex features list` in this worktree vs `/tmp`
- `web_search = "live"`
  - the strongest archived proof set is `sysop/out/codex-runtime-20260306-154230/`:
  - `web_search = "disabled"` suppressed search in a fresh control
  - `codex exec -c 'web_search="live"'` restored search in that disabled control
  - a later `sysop/out/verify-search-matrix/` rerun hit a usage-limit failure on the override-live control, so that rerun is inconclusive rather than contradictory
  - no-flag search success still does not prove the current worktree's effective mode is `live`, because default cached search remains a live alternative explanation
- worktree / cwd isolation
  - treat one-worktree-per-task as repo discipline, not a hard runtime guarantee
  - local `codex-cli 0.111.0` controls showed that explicit `codex exec resume <SESSION_ID>` rebounds to the caller cwd/worktree
  - `fork` currently surfaces a workdir chooser between the session directory and current directory, which is safer only in that narrow sense
  - after `resume`, `fork`, or `apply`, verify `pwd`, branch, and intended worktree before editing
- `researcher -> challenger -> implementer -> verifier`
  - has no safe automated shell-side smoke test in this repo today
  - the chain is operator-enforced and conditionally trustworthy, not runtime-guaranteed
  - it can therefore be described, configured, and partially loaded without being fully demonstrated
- `execpolicy`
  - can demonstrate a few concrete command-prefix boundaries in the current CLI
  - does not enforce the full role chain and does not prove every shell form or runtime boundary
- codex shell probes
  - can emit recurring `arg0` temp-dir / PATH-update warnings on stderr
  - in this runner, those warnings correlated with sandboxed execution and disappeared in an unsandboxed `codex --version` check while `~/.codex/tmp/arg0` permissions looked normal
  - treat them as useful but noisy runtime evidence and as a likely sandbox-side artifact here, not a proven general Codex defect
- shell-command network isolation
  - remains intentionally un-demonstrated by the default `preflight` / `drift-check` read-only checks because those checks do not perform outbound shell networking
  - dedicated runtime proof now exists via `./sysop/codex-network-denial-probe.sh`

## Runtime controls that survived challenge

- Search attribution matrix
  - archived run `sysop/out/codex-runtime-20260306-154230/` showed no-flag `codex exec` from a worktree with the active audit scaffold can search
  - that archived run also showed the same probe from a sibling whose repo-local config was flipped to `web_search = "disabled"` returned `SEARCH=no`
  - that archived run also showed the disabled sibling returned `SEARCH=yes` again when launched with `codex exec -c 'web_search="live"' ...`
  - later rerun `sysop/out/verify-search-matrix/` failed the override-live control with a usage-limit error, so do not cite that rerun as proof of restoration
  - doctrine: repo-local `web_search` materially gates non-interactive availability, but no-flag success still does not isolate the current worktree's effective mode as `live`
- Non-interactive `--search` mismatch (`codex-cli 0.111.0` artifacts, retested on local `0.112.0`)
  - `codex exec --search ...` still errored with `unexpected argument '--search' found`
  - `codex --search exec ...` did not restore search in the disabled control here
  - doctrine: for non-interactive runtime probes, prefer explicit config overrides such as `-c 'web_search="live"'`; treat `--search` on `exec` as an unstable surface and watch upstream
- Shell-network isolation proof
  - `./sysop/codex-network-denial-probe.sh` now proves a host-side HTTPS control succeeds while both direct Codex sandboxing and repo-root `codex exec` shell execution reject outbound socket creation with `PermissionError: [Errno 1] Operation not permitted`
- Resume / fork boundary
  - explicit `codex exec resume <SESSION_ID>` followed the caller cwd when resumed from two different worktrees
  - `fork` exposed the cwd choice interactively instead of silently rebasing
  - doctrine: `resume` is unsafe to trust blindly across worktrees; `fork` is conditionally safer only because it currently surfaces the decision
- Fresh control hygiene
  - a disposable sibling created from `git worktree add ... HEAD` is a misleading control if the active runtime scaffold is uncommitted
  - doctrine: commit the active scaffold first or mirror the exact runtime files into the disposable control explicitly before drawing conclusions

## Restart semantics

Project-local `.codex/` settings are startup-scoped.
If you create or modify them during a running Codex session, that session does not become governed by the new mode retroactively.
Finish the current safe work, verify the written scaffolding, then relaunch Codex from this repo/worktree root.

## Deferred runtime behavior

This mode enables native Codex web search for audit-specific upstream research in the next session that loads this worktree config.
That does not replace local evidence, challenger review, verifier review, rollback clarity, or repo-local implementation boundaries.

## Fresh-session attribution test

To test whether repo-local web-search settings load without relying on a CLI `--search` flag, start a fresh session from outside the repo with:

```bash
codex -C /home/xhott/SYSopGPTWSL/wt/codex-audit-hardening --no-alt-screen
```

Then ask for a current official-doc lookup and explicitly require the session to state whether live web search was available and whether that availability can be attributed to repo-local config.

For repeatable runtime controls, use:

```bash
./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold
./sysop/codex-runtime-probe.sh resume-cwd --create-controls --mirror-scaffold
```
