# Escalation Policy (SYSopGPTWSL)

Goal: predictable approvals + reversible changes.

## Default workflow
1) Observe (read-only): gather evidence, run checks.
2) Propose: show exact diffs + rollback commands.
3) Implement: only after approval; create timestamped backups first.

## Always requires explicit approval
- Any install/uninstall (`apt`, `snap`, `npm -g`, `pip`, etc.)
- Any write outside this repo (including edits under `$HOME` like dotfiles)
- Any edit to dotfiles (`~/.bashrc`, `~/.profile`, `~/.gitconfig`, `~/.ssh/*`)
- Any network call (web fetch, package install, etc.) unless explicitly requested
- Any `/etc` change (including WSL interop/mount settings; no `/etc/wsl.conf` changes)
- Any deletion (files/dirs)

## Deletion protocol (Janitor)
1) List: full paths + sizes + counts
2) Show: summarize totals; sample entries
3) Ask: explicit approval
4) Delete: only after approval
5) Validate: confirm what changed (counts/space)

## Runner note: systemctl
In Codex runner, `systemctl` may fail with `Failed to connect to bus: Operation not permitted`.
Authoritative check = run `systemctl` from an interactive Ubuntu shell.
