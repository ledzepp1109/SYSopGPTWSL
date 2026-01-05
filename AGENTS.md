# GPT/Codex WSL Sysop Repo

## Index-first
- Read `AGENTS.md` first, then `sysop/README_INDEX.md` before acting.

## Operating rules
- Read-only first: propose changes before edits/installs.
- Evidence discipline: back non-obvious claims with `man`/`--help` output or command results.
- Idempotent edits only; avoid duplicate lines in dotfiles.
- Backups + rollback: before editing a file outside the repo, create `*.bak-YYYYMMDD-HHMMSS` next to it and print the rollback command.

## Safety boundaries (repo)
- Never run destructive ops: `rm -rf`, `git reset --hard`, `git clean -fdx`.
- Never write outside this repo or to `/etc`.
- Do not change WSL interop settings or mount options.
- Do not fetch from the internet; work only with local repo content.
- Prefer Linux-native repos under `/home` (avoid `/mnt/c` unless required).

## Output format (operator)
- Do Now:
- Do Next:
- What Changed:
- Evidence: (command + key lines)

## Fresh-state practice
- If context gets messy, write a short summary to `learn/LEDGER.md` and continue.

## Repo layout
- `sysop/`: operator scripts (`preflight.sh`, `healthcheck.sh`) and local operator README.
- `sysop-report/`: living report(s); append updates rather than creating new reports unless necessary.
