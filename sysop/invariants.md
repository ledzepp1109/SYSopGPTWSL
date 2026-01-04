# Invariants (this machine)

Run `./sysop/drift-check.sh` to check these.

## Layout
- Repo contains: `sysop/` and `sysop-report/`
- Primary report: `sysop-report/2026-01-04_wsl_sysop.md`

## Toolchain
- `codex` resolves to `~/.npm-global/bin/codex`
- `npm prefix -g` is `~/.npm-global`
- PATH contains `~/.npm-global/bin` exactly once
- `git config --global core.autocrlf` is `input`

## SSH (network-dependent)
- `~/.ssh/id_ed25519.pub` exists
- `~/.ssh/config` contains a `Host github.com` entry using `~/.ssh/id_ed25519`
- Expected auth test: `ssh -T git@github.com` includes `successfully authenticated`

## systemd/dbus
- (Codex runner) `systemctl` may fail with EPERM; treat as runner limitation.
- (Interactive shell) `systemctl is-system-running` should be `running`; see the report’s “Post-WSL-restart status”.
