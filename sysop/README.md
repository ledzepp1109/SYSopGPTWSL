# sysop (WSL)

## Run checks
- One command (recommended): `./sysop/run.sh all`
- Preflight (fast): `./sysop/preflight.sh`
- Healthcheck (more complete): `./sysop/healthcheck.sh`
- Drift check (invariants): `./sysop/drift-check.sh`
- Print baseline block: `./sysop/collect-baseline.sh`

## systemd/dbus recovery (WSL)
If `systemctl` errors (e.g., `Failed to connect to bus: Operation not permitted`):
1) From Windows PowerShell (outside WSL): `wsl --shutdown`
2) Reopen Ubuntu, then re-test (interactive shell):
   - `systemctl is-system-running`
   - `systemctl status dbus --no-pager`

## Rollbacks / backups
This project writes timestamped backups next to files before edits, e.g.:
- `~/.bashrc.bak-20260104-085207`
- `~/.profile.bak-20260104-085207`
- `~/.gitconfig.bak-20260104-091354`

Rollback pattern:
- `cp -a <file>.bak-YYYYMMDD-HHMMSS <file>`

## Guardrail
Do not edit `/etc/wsl.conf` for this project.
