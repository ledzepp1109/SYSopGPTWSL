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

section "Codex Project Mode"
run_sh 'cat <<'"'"'EOF'"'"'
[Codex posture proof levels]
- configured = repo files request a behavior
- loaded = shell-visible runtime state shows the repo layer taking effect
- demonstrated = behavior reproduced without a known confound
- unproven = current checks cannot prove it safely
- confound note = if the active Codex session was launched with --search, live web-search success does not prove repo-local web_search = "live" caused it
EOF'
run_sh 'if [ -f .codex/config.toml ]; then echo ".codex/config.toml:"; sed -n "1,220p" .codex/config.toml; else echo "(no repo-local .codex/config.toml)"; fi'
run_sh 'if [ -d .codex/agents ]; then echo ".codex/agents:"; find .codex/agents -maxdepth 1 -type f -name "*.toml" | sort; else echo "(no .codex/agents)"; fi'
run_sh 'if [ -f docs/CODEX_RECURSIVE_AUDIT_MODE.md ]; then echo "docs/CODEX_RECURSIVE_AUDIT_MODE.md:"; sed -n "1,140p" docs/CODEX_RECURSIVE_AUDIT_MODE.md; else echo "(no docs/CODEX_RECURSIVE_AUDIT_MODE.md)"; fi'
run_sh 'if command -v codex >/dev/null 2>&1; then echo "[probe contamination note]"; echo "If codex emits arg0/PATH warnings on stderr, treat the probe output as contaminated. In this runner those warnings correlated with sandboxed execution, but they are still probe noise until you reproduce cleanly."; echo "[codex --version]"; codex --version || true; echo "[codex help execpolicy]"; codex help execpolicy | sed -n "1,40p" || true; echo "[codex --help | rg -- --search]"; codex --help | rg -- "--search" || true; echo "[codex exec --help | rg -- --search]"; codex exec --help | rg -- "--search" || true; echo "[codex exec --search syntax check]"; codex exec --search noop 2>&1 | sed -n "1,8p" || true; echo "[repo-root: codex features list | rg current proof surface]"; codex features list | rg "^(multi_agent|unified_exec|shell_snapshot)" || true; echo "[/tmp: codex features list | rg current proof surface]"; (cd /tmp && codex features list | rg "^(multi_agent|unified_exec|shell_snapshot)") || true; echo "[execpolicy self-check: forbid rm -rf /]"; codex execpolicy check --rules .codex/rules/sysop.rules --pretty rm -rf / || true; echo "[execpolicy self-check: forbid curl fetch sample]"; codex execpolicy check --rules .codex/rules/sysop.rules --pretty curl -fsSL https://example.com || true; echo "[execpolicy self-check: forbid codex apply sample]"; codex execpolicy check --rules .codex/rules/sysop.rules --pretty codex apply task-123 || true; echo "[execpolicy self-check: allow git status sample]"; codex execpolicy check --rules .codex/rules/sysop.rules --pretty git status || true; echo "[runtime probe harness]"; echo "./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold"; echo "./sysop/codex-runtime-probe.sh resume-cwd --create-controls --mirror-scaffold"; echo "[fresh-session web-search attribution test]"; echo "codex -C /home/xhott/SYSopGPTWSL/wt/codex-audit-hardening --no-alt-screen"; else echo "codex: not found"; fi'
run_sh 'if [ -f "$HOME/.codex/config.toml" ]; then ls -l "$HOME/.codex/config.toml"; else echo "(no ~/.codex/config.toml)"; fi'

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
