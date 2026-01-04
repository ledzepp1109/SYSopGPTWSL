# GPT/Codex WSL Sysop Repo

## Operating rules
- Read-only first: propose changes before edits/installs.
- Evidence discipline: back non-obvious claims with `man`/`--help` output or command results.
- Idempotent edits only; avoid duplicate lines in dotfiles.
- Backups + rollback: before editing a file outside the repo, create `*.bak-YYYYMMDD-HHMMSS` next to it and print the rollback command.
- Do NOT change WSL interop settings or mount options.
- Prefer Linux-native repos under `/home` (avoid `/mnt/c` unless required).

## Repo layout
- `sysop/`: operator scripts (`preflight.sh`, `healthcheck.sh`) and local operator README.
- `sysop-report/`: living report(s); append updates rather than creating new reports unless necessary.
