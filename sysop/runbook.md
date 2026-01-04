# Runbook (SYSopGPTWSL)

## Operator loop
1) `./sysop/preflight.sh`
2) `./sysop/healthcheck.sh`
3) `./sysop/drift-check.sh`
4) Consult `sysop-report/2026-01-04_wsl_sysop.md` (repo copy) for baselines and operator notes.

## systemctl EPERM in Codex runner
- If `systemctl` fails with `Failed to connect to bus: Operation not permitted` inside Codex runner, do not assume systemd is broken.
- Authoritative check = run in an interactive Ubuntu shell:
  - `systemctl is-system-running`
  - `systemctl status dbus --no-pager`
- If interactive shell is broken too: from Windows PowerShell run `wsl --shutdown`, reopen Ubuntu, re-test.

## Backups + rollback
- Before any edit, create a timestamped backup next to the file: `<file>.bak-YYYYMMDD-HHMMSS`
- Rollback pattern: `cp -a <file>.bak-YYYYMMDD-HHMMSS <file>`

## Session handoff
When pausing work, fill out: `sysop/templates/session-handoff.md`

## Transcript capture (optional; OUTSIDE the repo)
To capture a terminal transcript without committing it:
- `mkdir -p ~/sysop-report/transcripts`
- `script -af ~/sysop-report/transcripts/$(date +%Y%m%d-%H%M%S)_wsl_sysop.log`
- `exit` when done
