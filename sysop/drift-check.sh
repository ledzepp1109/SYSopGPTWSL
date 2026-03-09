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

path_count() {
  local needle="$1"
  printf '%s' "${PATH:-}" | awk -v RS=':' -v n="$needle" '$0==n {c++} END {print c+0}'
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

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
report="$repo_root/sysop-report/2026-01-04_wsl_sysop.md"
project_codex="$repo_root/.codex/config.toml"
project_codex_doc="$repo_root/docs/CODEX_RECURSIVE_AUDIT_MODE.md"
project_agent_dir="$repo_root/.codex/agents"
project_execpolicy_rules="$repo_root/.codex/rules/sysop.rules"

expected_codex="$HOME/.npm-global/bin/codex"
expected_npm_prefix="$HOME/.npm-global"
expected_autocrlf="input"
npm_bin="$HOME/.npm-global/bin"

feature_enabled() {
  # $1 = full `codex features list` output, $2 = feature name
  local feature_lines="$1"
  local name="$2"
  printf '%s\n' "$feature_lines" | awk -v n="$name" '$1==n {print $3; found=1} END {if (!found) print ""}'
}

say "Drift check (read-only): $(date -Is 2>/dev/null || date)"
say "Repo: $repo_root"

say ""
say "== Codex posture proof levels =="
say "INFO: configured = repo files request a behavior"
say "INFO: loaded = shell-visible runtime state shows the repo layer taking effect"
say "INFO: demonstrated = behavior reproduced without a known confound"
say "INFO: unproven = current checks cannot prove it safely"
say 'INFO: confound note = if a Codex session was launched with `--search`, live web-search success does not prove repo-local `web_search = "live"` caused it'

say ""
say "== Toolchain =="
if have codex; then
  codex_path="$(command -v codex)"
  if [ "$codex_path" = "$expected_codex" ]; then
    pass "codex path: $codex_path"
  else
    warn "codex path: $codex_path (expected $expected_codex)"
  fi

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
  if [ -f "$project_execpolicy_rules" ]; then
    capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_deny_rm.out" "$probe_dir/repo_execpolicy_deny_rm.err" \
      codex execpolicy check --rules "$project_execpolicy_rules" --pretty rm -rf /
    repo_execpolicy_deny_rm_rc=$?
    capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_deny_curl.out" "$probe_dir/repo_execpolicy_deny_curl.err" \
      codex execpolicy check --rules "$project_execpolicy_rules" --pretty curl -fsSL https://example.com
    repo_execpolicy_deny_curl_rc=$?
    capture_cmd "$repo_root" "$probe_dir/repo_execpolicy_allow_git_status.out" "$probe_dir/repo_execpolicy_allow_git_status.err" \
      codex execpolicy check --rules "$project_execpolicy_rules" --pretty git status
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
  if [ -f "$project_execpolicy_rules" ]; then
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
    if [ "$(feature_enabled "$repo_features_out" multi_agent)" = "true" ]; then
      pass "LOADED: multi_agent visible from repo root"
    else
      fail "LOADED: multi_agent disabled or not visible from repo root"
    fi

    if [ "$(feature_enabled "$repo_features_out" unified_exec)" = "true" ]; then
      pass "LOADED: unified_exec visible from repo root"
    else
      warn "LOADED: unified_exec disabled or not visible from repo root"
    fi

    if [ "$(feature_enabled "$repo_features_out" shell_snapshot)" = "true" ]; then
      pass "LOADED: shell_snapshot visible from repo root"
    else
      warn "LOADED: shell_snapshot disabled or not visible from repo root"
    fi
  fi

  if [ "$tmp_features_rc" -ne 0 ] || [ -z "$tmp_features_out" ]; then
    warn "UNPROVEN: /tmp comparison for effective repo-local feature loading failed"
  elif [ "$(feature_enabled "$repo_features_out" multi_agent)" = "true" ] && [ "$(feature_enabled "$tmp_features_out" multi_agent)" != "true" ]; then
    pass "LOADED: multi_agent is true from repo root and not true from /tmp, proving repo-local config affects runtime"
  elif [ "$(feature_enabled "$repo_features_out" multi_agent)" = "true" ] && [ "$(feature_enabled "$tmp_features_out" multi_agent)" = "true" ]; then
    warn "UNPROVEN: multi_agent is also true in /tmp, so repo-local attribution would be ambiguous"
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

  if [ -f "$project_execpolicy_rules" ]; then
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
else
  fail "codex missing on PATH"
fi

if [ -f "$project_codex" ]; then
  pass "CONFIGURED: repo-local Codex config present: $project_codex"
else
  fail "CONFIGURED: repo-local Codex config missing: $project_codex"
fi

if [ -f "$project_codex" ] && file_contains_fixed "$project_codex" 'web_search = "live"'; then
  pass 'CONFIGURED: repo-local Codex config requests `web_search = "live"`'
else
  fail 'CONFIGURED: repo-local Codex config missing `web_search = "live"`'
fi

if [ -f "$project_codex" ] && file_contains_fixed "$project_codex" 'network_access = false'; then
  pass 'CONFIGURED: repo-local workspace-write sandbox keeps shell command network access disabled'
else
  fail 'CONFIGURED: repo-local workspace-write sandbox missing `network_access = false`'
fi

if [ -f "$project_codex" ] && file_contains_fixed "$project_codex" 'multi_agent = true'; then
  pass 'CONFIGURED: repo-local Codex config requests `multi_agent = true`'
else
  fail 'CONFIGURED: repo-local Codex config missing `multi_agent = true`'
fi

if [ -f "$project_codex_doc" ]; then
  pass "CONFIGURED: Codex recursive audit doc present: $project_codex_doc"
else
  fail "CONFIGURED: Codex recursive audit doc missing: $project_codex_doc"
fi

if [ -f "$project_execpolicy_rules" ]; then
  pass "CONFIGURED: repo-local execpolicy rules present: $project_execpolicy_rules"
else
  fail "CONFIGURED: repo-local execpolicy rules missing: $project_execpolicy_rules"
fi

missing_role_files=0
for role in researcher challenger implementer verifier; do
  role_file="$project_agent_dir/$role.toml"
  if [ ! -f "$role_file" ]; then
    fail "CONFIGURED: repo-local Codex role missing: $role_file"
    missing_role_files=1
  fi
done
if [ "$missing_role_files" = "0" ]; then
  pass "CONFIGURED: repo-local role chain files present under $project_agent_dir"
fi

web_search_role_drift=0
for role in researcher challenger verifier; do
  role_file="$project_agent_dir/$role.toml"
  if [ -f "$role_file" ] && ! file_contains_fixed "$role_file" 'web_search = "live"'; then
    fail "CONFIGURED: repo-local Codex role missing audit web search: $role_file"
    web_search_role_drift=1
  fi
done
if [ "$web_search_role_drift" = "0" ]; then
  pass "CONFIGURED: researcher/challenger/verifier roles request live web search"
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

if have npm; then
  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  if [ "$npm_prefix" = "$expected_npm_prefix" ]; then
    pass "npm prefix -g: $npm_prefix"
  else
    fail "npm prefix -g: ${npm_prefix:-<empty>} (expected $expected_npm_prefix)"
  fi
else
  fail "npm missing"
fi

if [ -d "$npm_bin" ]; then
  c="$(path_count "$npm_bin")"
  if [ "$c" = "1" ]; then
    pass "PATH contains $npm_bin exactly once"
  elif [ "$c" = "0" ]; then
    fail "PATH does not contain $npm_bin"
  else
    fail "PATH contains $npm_bin $c times (duplication)"
  fi
else
  warn "$npm_bin directory missing"
fi

if have git; then
  autocrlf="$(git config --global --get core.autocrlf 2>/dev/null || true)"
  if [ "$autocrlf" = "$expected_autocrlf" ]; then
    pass "git core.autocrlf=$autocrlf"
  else
    fail "git core.autocrlf=${autocrlf:-<unset>} (expected $expected_autocrlf)"
  fi
else
  fail "git missing"
fi

say ""
say "== SSH (local) =="
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  pass "~/.ssh/id_ed25519.pub present"
else
  fail "~/.ssh/id_ed25519.pub missing"
fi

if [ -f "$HOME/.ssh/config" ]; then
  if grep -Eq '^[[:space:]]*Host[[:space:]]+github\.com[[:space:]]*$' "$HOME/.ssh/config" \
    && grep -Eq '^[[:space:]]*IdentityFile[[:space:]]+~\/\.ssh\/id_ed25519[[:space:]]*$' "$HOME/.ssh/config" \
    && grep -Eq '^[[:space:]]*IdentitiesOnly[[:space:]]+yes[[:space:]]*$' "$HOME/.ssh/config"; then
    pass "~/.ssh/config has github.com IdentityFile + IdentitiesOnly"
  else
    warn "~/.ssh/config present but github.com block differs from expected"
  fi
else
  warn "~/.ssh/config missing (SSH may still work)"
fi
say "INFO: network auth test (manual): ssh -T git@github.com"

say ""
say "== Report =="
if [ -f "$report" ]; then
  pass "report present: $report"
  if file_contains_fixed "$report" "## Operator Note — \`systemctl\` EPERM in Codex runner"; then
    pass "report includes Codex-runner systemctl note"
  else
    fail "report missing Codex-runner systemctl note"
  fi
else
  fail "report missing: $report"
fi

say ""
say "== systemd/dbus (runner) =="
if have systemctl; then
  sys_out="$(systemctl is-system-running 2>&1 || true)"
  if printf '%s' "$sys_out" | grep -qi 'operation not permitted'; then
    pass "systemctl bus blocked in Codex runner (expected); authoritative check = interactive shell + report"
  elif printf '%s' "$sys_out" | grep -qi '^running$'; then
    pass "systemctl is-system-running: running"
  elif printf '%s' "$sys_out" | grep -qi 'failed to connect to bus'; then
    fail "systemctl failed to connect to bus: $sys_out"
  elif printf '%s' "$sys_out" | grep -qi 'not been booted with systemd'; then
    fail "systemd not PID 1 (systemctl): $sys_out"
  elif [ -n "$sys_out" ]; then
    warn "systemctl is-system-running: $sys_out"
  else
    warn "systemctl is-system-running produced no output"
  fi
else
  warn "systemctl not found"
fi

say ""
say "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
