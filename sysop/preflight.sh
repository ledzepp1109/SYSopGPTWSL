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

capture_cmd() {
    local cwd="$1"
    local out_file="$2"
    local err_file="$3"
    shift 3
    (
        cd "$cwd" || exit 1
        "$@"
    ) >"$out_file" 2>"$err_file"
}

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
repo_codex_config="$repo_root/.codex/config.toml"
repo_codex_doc="$repo_root/docs/CODEX_RECURSIVE_AUDIT_MODE.md"
repo_agent_dir="$repo_root/.codex/agents"
repo_execpolicy_rules="$repo_root/.codex/rules/sysop.rules"

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

feature_enabled() {
    # $1 = full `codex features list` output, $2 = feature name
    local feature_lines="$1"
    local name="$2"
    printf '%s\n' "$feature_lines" | awk -v n="$name" '$1==n {print $3; found=1} END {if (!found) print ""}'
}

file_contains_fixed() {
    # $1=file, $2=fixed-string
    local file="$1"
    local needle="$2"
    grep -F -q -- "$needle" "$file"
}

stderr_has_codex_probe_contamination() {
    local err_file="$1"
    grep -E -q 'failed to clean up stale arg0 temp dirs|could not update PATH' "$err_file"
}

emit_captured_stderr() {
    local label="$1"
    local err_file="$2"
    if [ -s "$err_file" ]; then
        warn "UNPROVEN: $label emitted stderr warnings; probe output may be contaminated"
        if stderr_has_codex_probe_contamination "$err_file"; then
            warn "UNPROVEN: Codex startup warnings contaminated $label; treat this probe as useful but noisy runtime evidence"
        fi
        awk -v p="INFO: ${label} stderr: " 'NR <= 20 { print p $0 }' "$err_file"
    fi
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

for extra_bin in "$HOME/.local/bin" "$HOME/.bun/bin"; do
    if [ -d "$extra_bin" ]; then
        count="$(path_has_exactly_once "$extra_bin")"
        if [ "$count" = "1" ]; then
            pass "PATH contains $extra_bin exactly once"
        elif [ "$count" = "0" ]; then
            warn "PATH does not contain $extra_bin"
        else
            warn "PATH contains $extra_bin $count times (duplication)"
        fi
    fi
done

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

say ""
say "== Codex posture proof levels =="
say "INFO: configured = repo files request a behavior"
say "INFO: loaded = shell-visible runtime state shows the repo layer taking effect"
say "INFO: demonstrated = behavior reproduced without a known confound"
say "INFO: unproven = current checks cannot prove it safely"
say 'INFO: confound note = if a Codex session was launched with `--search`, live web-search success does not prove repo-local `web_search = "live"` caused it'

if [ -f "$repo_codex_config" ]; then
    pass "CONFIGURED: repo-local Codex config present: $repo_codex_config"
else
    fail "CONFIGURED: repo-local Codex config missing: $repo_codex_config"
fi

if [ -f "$repo_codex_doc" ]; then
    pass "CONFIGURED: Codex recursive audit doc present: $repo_codex_doc"
else
    fail "CONFIGURED: Codex recursive audit doc missing: $repo_codex_doc"
fi

if [ -f "$repo_execpolicy_rules" ]; then
    pass "CONFIGURED: repo-local execpolicy rules present: $repo_execpolicy_rules"
else
    fail "CONFIGURED: repo-local execpolicy rules missing: $repo_execpolicy_rules"
fi

missing_role_files=0
for role in researcher challenger implementer verifier; do
    role_file="$repo_agent_dir/$role.toml"
    if [ ! -f "$role_file" ]; then
        fail "CONFIGURED: repo-local Codex role missing: $role_file"
        missing_role_files=1
    fi
done
if [ "$missing_role_files" = "0" ]; then
    pass "CONFIGURED: repo-local role chain files present under $repo_agent_dir"
fi

if [ -f "$repo_codex_config" ] && file_contains_fixed "$repo_codex_config" 'web_search = "live"'; then
    pass 'CONFIGURED: repo-local Codex config requests `web_search = "live"`'
else
    fail 'CONFIGURED: repo-local Codex config missing `web_search = "live"`'
fi

web_search_role_drift=0
for role in researcher challenger verifier; do
    role_file="$repo_agent_dir/$role.toml"
    if [ -f "$role_file" ] && ! file_contains_fixed "$role_file" 'web_search = "live"'; then
        fail "CONFIGURED: repo-local role missing audit web search: $role_file"
        web_search_role_drift=1
    fi
done
if [ "$web_search_role_drift" = "0" ]; then
    pass "CONFIGURED: researcher/challenger/verifier roles request live web search"
fi

if [ -f "$repo_codex_config" ] && file_contains_fixed "$repo_codex_config" 'network_access = false'; then
    pass 'CONFIGURED: repo-local workspace-write sandbox keeps shell command network access disabled'
else
    fail 'CONFIGURED: repo-local workspace-write sandbox missing `network_access = false`'
fi

if [ -f "$repo_codex_config" ] && file_contains_fixed "$repo_codex_config" 'multi_agent = true'; then
    pass 'CONFIGURED: repo-local Codex config requests `multi_agent = true`'
else
    fail 'CONFIGURED: repo-local Codex config missing `multi_agent = true`'
fi

if have codex; then
    probe_dir="$(mktemp -d)"
    trap 'rm -rf "$probe_dir"' EXIT

    capture_cmd "$repo_root" "$probe_dir/repo_version.out" "$probe_dir/repo_version.err" codex --version
    repo_version_rc=$?
    capture_cmd "$repo_root" "$probe_dir/repo_features.out" "$probe_dir/repo_features.err" codex features list
    repo_features_rc=$?
    capture_cmd "/tmp" "$probe_dir/tmp_features.out" "$probe_dir/tmp_features.err" codex features list
    tmp_features_rc=$?
    capture_cmd "$repo_root" "$probe_dir/repo_help.out" "$probe_dir/repo_help.err" codex --help
    repo_help_rc=$?
    capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_help.out" "$probe_dir/repo_execpolicy_help.err" codex help execpolicy
    repo_execpolicy_help_rc=$?
    if [ -f "$repo_execpolicy_rules" ]; then
        capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_deny_rm.out" "$probe_dir/repo_execpolicy_deny_rm.err" \
            codex execpolicy check --rules "$repo_execpolicy_rules" --pretty rm -rf /
        repo_execpolicy_deny_rm_rc=$?
        capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_deny_curl.out" "$probe_dir/repo_execpolicy_deny_curl.err" \
            codex execpolicy check --rules "$repo_execpolicy_rules" --pretty curl -fsSL https://example.com
        repo_execpolicy_deny_curl_rc=$?
        capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_allow_git_status.out" "$probe_dir/repo_execpolicy_allow_git_status.err" \
            codex execpolicy check --rules "$repo_execpolicy_rules" --pretty git status
        repo_execpolicy_allow_git_status_rc=$?
    else
        repo_execpolicy_deny_rm_rc=1
        repo_execpolicy_deny_curl_rc=1
        repo_execpolicy_allow_git_status_rc=1
    fi

    emit_captured_stderr "codex --version (repo root)" "$probe_dir/repo_version.err"
    emit_captured_stderr "codex features list (repo root)" "$probe_dir/repo_features.err"
    emit_captured_stderr "codex features list (/tmp)" "$probe_dir/tmp_features.err"
    emit_captured_stderr "codex --help (repo root)" "$probe_dir/repo_help.err"
    emit_captured_stderr "codex help execpolicy (repo root)" "$probe_dir/repo_execpolicy_help.err"
    if [ -f "$repo_execpolicy_rules" ]; then
        emit_captured_stderr "codex execpolicy check (deny rm -rf / sample)" "$probe_dir/repo_execpolicy_deny_rm.err"
        emit_captured_stderr "codex execpolicy check (deny curl sample)" "$probe_dir/repo_execpolicy_deny_curl.err"
        emit_captured_stderr "codex execpolicy check (allow git status sample)" "$probe_dir/repo_execpolicy_allow_git_status.err"
    fi

    repo_version_out="$(cat "$probe_dir/repo_version.out")"
    repo_features_out="$(cat "$probe_dir/repo_features.out")"
    tmp_features_out="$(cat "$probe_dir/tmp_features.out")"
    repo_help_out="$(cat "$probe_dir/repo_help.out")"
    repo_execpolicy_help_out="$(cat "$probe_dir/repo_execpolicy_help.out")"

    if [ "$repo_version_rc" -ne 0 ] || [ -z "$repo_version_out" ]; then
        warn "UNPROVEN: codex --version did not return cleanly from repo root"
    else
        say "INFO: codex --version: $repo_version_out"
    fi

    if [ "$repo_features_rc" -ne 0 ] || [ -z "$repo_features_out" ]; then
        fail "LOADED: codex features list failed from repo root"
    else
        multi_agent_state="$(feature_enabled "$repo_features_out" multi_agent)"
        unified_exec_state="$(feature_enabled "$repo_features_out" unified_exec)"
        shell_snapshot_state="$(feature_enabled "$repo_features_out" shell_snapshot)"

        if [ "$multi_agent_state" = "true" ]; then
            pass "LOADED: multi_agent visible from repo root"
        else
            fail "LOADED: multi_agent disabled or unavailable from repo root"
        fi

        if [ "$unified_exec_state" = "true" ]; then
            pass "LOADED: unified_exec visible from repo root"
        else
            warn "LOADED: unified_exec disabled or unavailable from repo root"
        fi

        if [ "$shell_snapshot_state" = "true" ]; then
            pass "LOADED: shell_snapshot visible from repo root"
        else
            warn "LOADED: shell_snapshot disabled or unavailable from repo root"
        fi
    fi

    if [ "$tmp_features_rc" -ne 0 ] || [ -z "$tmp_features_out" ]; then
        warn "UNPROVEN: /tmp comparison for effective repo-local feature loading failed"
    else
        tmp_multi_agent_state="$(feature_enabled "$tmp_features_out" multi_agent)"
        if [ "${multi_agent_state:-}" = "true" ] && [ "$tmp_multi_agent_state" != "true" ]; then
            pass "LOADED: multi_agent is true from repo root and not true from /tmp, proving repo-local config affects runtime"
        elif [ "${multi_agent_state:-}" = "true" ] && [ "$tmp_multi_agent_state" = "true" ]; then
            warn "UNPROVEN: multi_agent is also true in /tmp, so repo-local attribution would be ambiguous"
        fi
    fi

    if [ "$repo_help_rc" -ne 0 ] || [ -z "$repo_help_out" ]; then
        warn "UNPROVEN: unable to inspect Codex CLI help for search capability"
    elif printf '%s\n' "$repo_help_out" | grep -F -q -- '--search'; then
        warn 'DEMONSTRATED: Codex CLI binary exposes a `--search` capability, but that does not prove repo-local `web_search = "live"` was loaded'
    else
        warn 'UNPROVEN: Codex CLI help did not expose a `--search` flag from this shell probe'
    fi

    if [ "$repo_execpolicy_help_rc" -ne 0 ] || [ -z "$repo_execpolicy_help_out" ]; then
        warn "UNPROVEN: codex help execpolicy did not return cleanly from repo root"
    else
        pass "DEMONSTRATED: codex help execpolicy is available in the current CLI"
    fi

    if [ -f "$repo_execpolicy_rules" ]; then
        if [ "$repo_execpolicy_deny_rm_rc" -eq 0 ] && file_contains_fixed "$probe_dir/repo_execpolicy_deny_rm.out" '"decision": "forbidden"'; then
            pass 'DEMONSTRATED: execpolicy forbids destructive `rm -rf /` sample'
        else
            warn 'UNPROVEN: execpolicy did not clearly forbid destructive `rm -rf /` sample'
        fi

        if [ "$repo_execpolicy_deny_curl_rc" -eq 0 ] && file_contains_fixed "$probe_dir/repo_execpolicy_deny_curl.out" '"decision": "forbidden"'; then
            pass 'DEMONSTRATED: execpolicy forbids representative shell-network `curl` fetch sample'
        else
            warn 'UNPROVEN: execpolicy did not clearly forbid representative shell-network `curl` fetch sample'
        fi

        if [ "$repo_execpolicy_allow_git_status_rc" -eq 0 ] && ! file_contains_fixed "$probe_dir/repo_execpolicy_allow_git_status.out" '"decision": "forbidden"'; then
            pass 'DEMONSTRATED: execpolicy leaves benign `git status` sample unblocked'
        else
            warn 'UNPROVEN: execpolicy unexpectedly blocked benign `git status` sample'
        fi
    fi
fi

warn 'LOADED: repo-local web_search load is unproven from shell-side probes; `codex features list` exposes no positive web-search flag'
warn 'DEMONSTRATED: this check does not count current-session live web-search success as repo-local proof when `--search` may have been used at launch'
warn 'UNPROVEN: fresh-session attribution test still required for repo-local web search'
warn 'LOADED: no supported shell-side probe proves the researcher/challenger/implementer/verifier role files are the effective runtime agent configs'
warn 'DEMONSTRATED: no safe automated role-chain smoke test is implemented in repo-local shell checks'
warn 'UNPROVEN: end-to-end mandatory role-chain blocking semantics remain only partially proven'
warn 'LOADED: no shell-side runtime introspection proves the shell-network sandbox is active beyond config text'
warn 'DEMONSTRATED: execpolicy checks can prove a few concrete command-prefix boundaries, but they do not prove the full role chain or every shell form'
warn 'DEMONSTRATED: this check intentionally does not attempt outbound shell networking'
warn 'UNPROVEN: shell-network isolation still needs a controlled negative test if stronger runtime proof is required'

if have claude; then
    pass "claude: $(command -v claude)"
    claude_md="$HOME/.claude/CLAUDE.md"
    if [ -f "$claude_md" ]; then
        pass "Claude operator entrypoint: $claude_md"
        if grep -Fq "ops-operator/config/CLAUDE.md" "$claude_md"; then
            ops_spec="$HOME/ops-operator/config/CLAUDE.md"
            if [ -f "$ops_spec" ]; then
                pass "Claude operator spec present: $ops_spec"
            else
                warn "Claude operator spec missing at $ops_spec"
            fi
        else
            warn "Claude operator entrypoint does not reference ops-operator/config/CLAUDE.md"
        fi
    else
        warn "Claude operator entrypoint missing: $claude_md"
    fi
else
    warn "claude not found on PATH (skip Claude operator checks)"
fi

git_repo_status

say "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"
if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
