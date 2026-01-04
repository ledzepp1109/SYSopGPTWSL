#!/usr/bin/env bash
set -u

pass_count=0
warn_count=0
fail_count=0

say() { printf '%s\n' "$*"; }
pass() { pass_count=$((pass_count + 1)); say "PASS: $*"; }
warn() { warn_count=$((warn_count + 1)); say "WARN: $*"; }
fail() { fail_count=$((fail_count + 1)); say "FAIL: $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

in_windows_mount() {
    case "${PWD:-}" in
        /mnt/*) return 0 ;;
        *) return 1 ;;
    esac
}

git_repo_status() {
    if ! have git; then
        warn "git not found"
        return 0
    fi
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        pass "not in a git repo (skipping git cleanliness check)"
        return 0
    fi
    if git diff --quiet --ignore-submodules -- 2>/dev/null && git diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
        pass "git working tree clean"
    else
        warn "git working tree has local changes"
    fi
}

path_has_exactly_once() {
    # $1 = path segment to search for
    local needle="$1"
    local count
    count="$(
        printf '%s' "${PATH:-}" | awk -v RS=':' -v n="$needle" '$0==n {c++} END {print c+0}'
    )"
    printf '%s' "$count"
}

say "Preflight (read-only): $(date -Is 2>/dev/null || date)"

if is_wsl; then
    pass "WSL detected"
else
    warn "WSL not detected (unexpected in this environment)"
fi

if in_windows_mount; then
    warn "PWD is under /mnt (Windows filesystem); prefer working under $HOME for perf and Linux semantics"
else
    pass "PWD is not under /mnt"
fi

if have codex; then
    pass "codex on PATH: $(command -v codex)"
else
    fail "codex not found on PATH"
fi

if have npm; then
    npm_prefix="$(npm config get prefix 2>/dev/null || true)"
    if [ "$npm_prefix" = "$HOME/.npm-global" ]; then
        pass "npm prefix is user-level: $npm_prefix"
    else
        warn "npm prefix is not $HOME/.npm-global (got: ${npm_prefix:-<empty>})"
    fi
else
    warn "npm not found"
fi

npm_bin="$HOME/.npm-global/bin"
if [ -d "$npm_bin" ]; then
    count="$(path_has_exactly_once "$npm_bin")"
    if [ "$count" = "1" ]; then
        pass "PATH contains $npm_bin exactly once"
    elif [ "$count" = "0" ]; then
        fail "PATH does not contain $npm_bin"
    else
        warn "PATH contains $npm_bin $count times (duplication)"
    fi
else
    warn "$npm_bin directory missing"
fi

if have node; then
    pass "node: $(node -v 2>/dev/null || true)"
else
    warn "node not found"
fi

if have python3; then
    pass "python3: $(python3 --version 2>/dev/null || true)"
else
    warn "python3 not found"
fi

git_repo_status

say "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"
if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
