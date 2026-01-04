#!/usr/bin/env bash
set -u

say() { printf '%s\n' "$*"; }
section() { say ""; say "== $* =="; }
have() { command -v "$1" >/dev/null 2>&1; }

run() {
    # Print the command, then run it best-effort (read-only).
    say ""
    say "+ $*"
    ( "$@" ) 2>&1 | sed -n '1,120p'
}

run_sh() {
    say ""
    say "+ $*"
    ( bash -lc "$*" ) 2>&1 | sed -n '1,120p'
}

say "WSL Healthcheck (read-only): $(date -Is 2>/dev/null || date)"

section "OS"
run_sh 'lsb_release -a || cat /etc/os-release'
run uname -a
run_sh 'cat /proc/version; echo "WSL_DISTRO_NAME=${WSL_DISTRO_NAME-}"; grep -i microsoft /proc/version || true'

section "WSL Config"
run_sh 'if [ -f /etc/wsl.conf ]; then echo "/etc/wsl.conf:"; sed -n "1,200p" /etc/wsl.conf; else echo "(no /etc/wsl.conf)"; fi'
run_sh "mount | grep -E ' /mnt/c ' || true"

section "Shell/PATH"
run_sh 'echo "SHELL=$SHELL"; echo "$PATH" | tr ":" "\n" | nl -ba | sed -n "1,120p"'

section "Git"
if have git; then
    run git --version
    run_sh 'echo -n "core.autocrlf="; git config --global --get core.autocrlf || true; echo -n "core.filemode="; git config --global --get core.filemode || true'
else
    say "git: missing"
fi

section "Node/NPM"
run_sh 'node -v 2>/dev/null || echo "node: not found"; npm -v 2>/dev/null || echo "npm: not found"'
if have npm; then
    run_sh 'npm config get prefix; npm prefix -g; npm root -g'
fi
run_sh 'command -v codex || true; codex --version 2>/dev/null || true'

section "Python"
run_sh 'python3 --version; pip3 --version 2>/dev/null || true'

section "SSH"
run_sh 'ls -la ~/.ssh 2>/dev/null || true; ssh-add -l 2>/dev/null || true'

section "Resources"
run df -h ~
run free -h
run_sh 'ls -la ~ | head -n 50'

section "systemd/dbus"
run_sh 'ps -p 1 -o comm=; ls -la /run/systemd/system 2>/dev/null || true; ls -la /run/dbus/system_bus_socket 2>/dev/null || true; systemctl --version'
run_sh 'systemctl is-system-running 2>&1 || true'
run_sh 'ps -ef | grep -E "dbus-daemon|dbus-broker" | grep -v grep || true'
