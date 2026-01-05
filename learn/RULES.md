# Operator Kernel Rules

## Kernel rules (keep small; update when reality changes)

1) Index-first: read `AGENTS.md`, then `sysop/README_INDEX.md` before acting.
2) Safety boundary: never run `rm -rf`, `git reset --hard`, `git clean -fdx`; never write outside this repo or to `/etc`.
3) Windows/WSL interop: run Windows commands from a drive-backed cwd (`/mnt/c`) to avoid UNC cwd problems.
4) Windows JSON: parse snapshot JSON with `utf-8-sig` (PowerShell may emit a UTF-8 BOM).
5) Filesystem perf: keep perf-critical work under `/home`; `/mnt/c` is drvfs/9p and slower.

