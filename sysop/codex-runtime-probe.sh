#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
default_report_dir="$repo_root/sysop/out/codex-runtime-$(date +%Y%m%d-%H%M%S)"
sibling_root="$(cd -- "$repo_root/.." && pwd)"

live_worktree="${CODEX_RUNTIME_LIVE_WORKTREE:-$sibling_root/codex-fresh-runtime-control}"
disabled_worktree="${CODEX_RUNTIME_DISABLED_WORKTREE:-$sibling_root/codex-search-disabled-control}"
report_dir="$default_report_dir"
create_controls=0
mirror_scaffold=0
mode="all"

search_prompt='Answer in exactly three lines. Line 1: SEARCH=<yes/no/unknown> for whether web search is available in this session. Line 2: URL=<one official OpenAI URL you actually used, or none>. Line 3: FACT=<what the Codex CLI --search flag does, according to that official doc, or why you could not look it up>. Use official OpenAI docs only. Do not rely on local repo files beyond required operating instructions. Do not spawn subagents. Do not add any extra text.'
ready_prompt='Answer in exactly one line: READY=1. Do not edit files.'
resume_prompt='Do not edit files. Run pwd and git branch --show-current, then answer with exactly two lines: PWD=<pwd> and BRANCH=<branch>.'

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./sysop/codex-runtime-probe.sh [search-matrix|resume-cwd|all] [options]

Runtime probe harness for Codex trust-boundary checks.
This script is intentionally explicit:
- it does not run as part of `./sysop/run.sh all`
- it creates disposable sibling worktrees only when `--create-controls` is passed
- it mirrors the current runtime scaffold only when `--mirror-scaffold` is passed
- it preserves raw stdout/stderr under a report directory for later challenge review

Options:
  --live-worktree PATH       Path for the search-enabled disposable worktree
  --disabled-worktree PATH   Path for the web_search=disabled disposable worktree
  --report-dir PATH          Directory for raw probe artifacts
  --create-controls          Create missing disposable worktrees with detached HEAD
  --mirror-scaffold          Copy current AGENTS/README/.codex runtime scaffold into controls
  -h, --help                 Show help

Examples:
  ./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold
  ./sysop/codex-runtime-probe.sh resume-cwd --create-controls --mirror-scaffold
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

run_capture() {
  local outfile="$1"
  shift
  set +e
  "$@" >"$outfile" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

run_capture_in_dir() {
  local cwd="$1"
  local outfile="$2"
  shift 2
  set +e
  (
    cd "$cwd" || exit 1
    "$@"
  ) >"$outfile" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

extract_key() {
  local key="$1"
  local file="$2"
  grep -E "^${key}=" "$file" | tail -n 1 | sed "s/^${key}=//"
}

extract_session_id() {
  local file="$1"
  awk '/^session id: / {print $3; exit}' "$file"
}

extract_startup_workdir() {
  local file="$1"
  awk '/^workdir: / {print $2; exit}' "$file"
}

extract_error_hint() {
  local file="$1"
  if grep -F -q "You've hit your usage limit" "$file"; then
    printf 'usage_limit'
    return 0
  fi
  awk '
    /^ERROR:/ {print substr($0, 8); exit}
    /unexpected argument/ {print $0; exit}
  ' "$file"
}

print_log_excerpt() {
  local file="$1"
  if [ -f "$file" ]; then
    sed -n '1,40p' "$file"
  fi
}

write_scaffold_hashes() {
  local label="$1"
  local root="$2"
  local outfile="$report_dir/${label}-scaffold.sha256"
  : >"$outfile"
  (
    cd "$root" || exit 1
    for rel in \
      AGENTS.md \
      sysop/README_INDEX.md \
      .codex/config.toml \
      .codex/rules/sysop.rules \
      .codex/agents/challenger.toml \
      .codex/agents/implementer.toml \
      .codex/agents/researcher.toml \
      .codex/agents/verifier.toml
    do
      if [ -f "$rel" ]; then
        sha256sum "$rel"
      else
        printf 'MISSING  %s\n' "$rel"
      fi
    done
  ) >>"$outfile"
}

ensure_worktree() {
  local path="$1"
  local label="$2"

  if git -C "$path" rev-parse --show-toplevel >/dev/null 2>&1; then
    say "INFO: reusing ${label} worktree: $path"
    return 0
  fi

  if [ -e "$path" ]; then
    die "${label} path exists but is not a git worktree: $path"
  fi

  if [ "$create_controls" != "1" ]; then
    die "${label} worktree missing: $path (rerun with --create-controls)"
  fi

  git -C "$repo_root" worktree add --detach "$path" HEAD >/dev/null
  say "INFO: created detached disposable ${label} worktree: $path"
}

mirror_runtime_scaffold() {
  local dest="$1"
  local mode_name="$2"

  if [ "$mirror_scaffold" != "1" ]; then
    say "WARN: --mirror-scaffold not set; ${mode_name} control may be confounded if it differs from the current repo scaffold"
    return 0
  fi

  mkdir -p "$dest/.codex/agents" "$dest/.codex/rules" "$dest/sysop"
  cp -f "$repo_root/AGENTS.md" "$dest/AGENTS.md"
  cp -f "$repo_root/sysop/README_INDEX.md" "$dest/sysop/README_INDEX.md"
  cp -f "$repo_root/.codex/config.toml" "$dest/.codex/config.toml"
  cp -f "$repo_root/.codex/rules/sysop.rules" "$dest/.codex/rules/sysop.rules"
  cp -f "$repo_root/.codex/agents/"*.toml "$dest/.codex/agents/"

  if [ "$mode_name" = "disabled" ]; then
    perl -0pi -e 's/web_search = "live"/web_search = "disabled"/' "$dest/.codex/config.toml"
  fi

  say "INFO: mirrored current runtime scaffold into $dest (${mode_name})"
}

run_search_probe() {
  local label="$1"
  local workdir="$2"
  shift 2
  local outfile="$report_dir/${label}.log"
  local rc
  local -a cmd=(codex exec -C "$workdir")
  while [ "$#" -gt 0 ]; do
    cmd+=("$1")
    shift
  done
  cmd+=("$search_prompt")

  rc="$(run_capture "$outfile" "${cmd[@]}")"

  say ""
  say "== ${label} =="
  say "WORKDIR=${workdir}"
  say "RC=${rc}"
  say "SEARCH=$(extract_key SEARCH "$outfile" || true)"
  say "URL=$(extract_key URL "$outfile" || true)"
  say "FACT=$(extract_key FACT "$outfile" || true)"
  say "STARTUP_WORKDIR=$(extract_startup_workdir "$outfile" || true)"
  local err_hint
  err_hint="$(extract_error_hint "$outfile" || true)"
  if [ -n "$err_hint" ]; then
    say "ERROR_HINT=$err_hint"
  fi
  local sid
  sid="$(extract_session_id "$outfile" || true)"
  if [ -n "$sid" ]; then
    say "SESSION_ID=$sid"
  fi
  say "LOG=${outfile}"
}

run_exec_search_parser_probe() {
  local outfile="$report_dir/exec-search-parser.log"
  local rc
  rc="$(run_capture "$outfile" codex exec --search noop)"
  say ""
  say "== exec-search-parser =="
  say "RC=${rc}"
  print_log_excerpt "$outfile"
  say "LOG=${outfile}"
}

run_search_matrix() {
  ensure_worktree "$live_worktree" "live"
  ensure_worktree "$disabled_worktree" "disabled"

  mirror_runtime_scaffold "$live_worktree" "live"
  mirror_runtime_scaffold "$disabled_worktree" "disabled"

  write_scaffold_hashes "repo-current" "$repo_root"
  write_scaffold_hashes "live-control" "$live_worktree"
  write_scaffold_hashes "disabled-control" "$disabled_worktree"

  say "== search-matrix setup =="
  say "REPO_ROOT=$repo_root"
  say "LIVE_WORKTREE=$live_worktree"
  say "DISABLED_WORKTREE=$disabled_worktree"
  say "REPORT_DIR=$report_dir"

  run_search_probe "search-live-no-flag" "$live_worktree"
  run_search_probe "search-disabled-no-flag" "$disabled_worktree"
  run_search_probe "search-disabled-override-live" "$disabled_worktree" -c 'web_search="live"'
  run_exec_search_parser_probe

  local live_no_flag disabled_no_flag override_live
  local live_no_flag_err disabled_no_flag_err override_live_err
  live_no_flag="$(extract_key SEARCH "$report_dir/search-live-no-flag.log" || true)"
  disabled_no_flag="$(extract_key SEARCH "$report_dir/search-disabled-no-flag.log" || true)"
  override_live="$(extract_key SEARCH "$report_dir/search-disabled-override-live.log" || true)"
  live_no_flag_err="$(extract_error_hint "$report_dir/search-live-no-flag.log" || true)"
  disabled_no_flag_err="$(extract_error_hint "$report_dir/search-disabled-no-flag.log" || true)"
  override_live_err="$(extract_error_hint "$report_dir/search-disabled-override-live.log" || true)"

  say ""
  say "== search-matrix verdict =="
  if [ "$disabled_no_flag" = "no" ] && [ "$override_live" = "yes" ]; then
    say "RESULT=pass"
    say "SUMMARY=repo-local web_search materially affects fresh non-interactive codex exec availability"
  elif [ -n "$override_live_err" ]; then
    say "RESULT=inconclusive"
    say "SUMMARY=override-live control did not complete cleanly (${override_live_err}); do not treat this rerun as proof against an archived success case"
  elif [ "$disabled_no_flag" != "no" ]; then
    say "RESULT=inconclusive"
    say "SUMMARY=disabled control did not report SEARCH=no; current run cannot attribute availability changes to repo-local config"
  else
    say "RESULT=inconclusive"
    say "SUMMARY=expected SEARCH=no / SEARCH=yes split was not reproduced cleanly"
  fi
  if [ -n "$live_no_flag_err" ]; then
    say "NOTE=live-no-flag control emitted ${live_no_flag_err}"
  fi
  if [ -n "$disabled_no_flag_err" ]; then
    say "NOTE=disabled-no-flag control emitted ${disabled_no_flag_err}"
  fi

  say ""
  say "== search-matrix doctrine =="
  say "Fresh no-flag search success alone does not prove repo-local live mode."
  say "If disabled/no-flag reports SEARCH=no while override-live reports SEARCH=yes, repo-local web_search config is materially affecting exec-session availability."
  say "Use the raw logs before claiming anything stronger about effective live vs cached mode."
}

run_resume_probe() {
  ensure_worktree "$live_worktree" "live"
  mirror_runtime_scaffold "$live_worktree" "live"
  write_scaffold_hashes "repo-current" "$repo_root"
  write_scaffold_hashes "live-control" "$live_worktree"

  local seed_out="$report_dir/resume-seed.log"
  local seed_rc session_id
  seed_rc="$(run_capture "$seed_out" codex exec -C "$live_worktree" "$ready_prompt")"
  session_id="$(extract_session_id "$seed_out" || true)"

  say "== resume-cwd setup =="
  say "LIVE_WORKTREE=$live_worktree"
  say "REPORT_DIR=$report_dir"
  say "SEED_RC=$seed_rc"
  say "SEED_LOG=$seed_out"

  if [ -z "$session_id" ]; then
    die "could not extract session id from $seed_out"
  fi

  say "SESSION_ID=$session_id"

  local repo_out="$report_dir/resume-from-repo.log"
  local repo_rc
  repo_rc="$(run_capture_in_dir "$repo_root" "$repo_out" codex exec resume "$session_id" "$resume_prompt")"
  say ""
  say "== resume-from-repo =="
  say "RC=$repo_rc"
  say "STARTUP_WORKDIR=$(extract_startup_workdir "$repo_out" || true)"
  say "PWD=$(extract_key PWD "$repo_out" || true)"
  say "BRANCH=$(extract_key BRANCH "$repo_out" || true)"
  local repo_err_hint
  repo_err_hint="$(extract_error_hint "$repo_out" || true)"
  if [ -n "$repo_err_hint" ]; then
    say "ERROR_HINT=$repo_err_hint"
  fi
  say "LOG=$repo_out"

  local live_out="$report_dir/resume-from-live.log"
  local live_rc
  live_rc="$(run_capture_in_dir "$live_worktree" "$live_out" codex exec resume "$session_id" "$resume_prompt")"
  say ""
  say "== resume-from-live =="
  say "RC=$live_rc"
  say "STARTUP_WORKDIR=$(extract_startup_workdir "$live_out" || true)"
  say "PWD=$(extract_key PWD "$live_out" || true)"
  say "BRANCH=$(extract_key BRANCH "$live_out" || true)"
  local live_err_hint
  live_err_hint="$(extract_error_hint "$live_out" || true)"
  if [ -n "$live_err_hint" ]; then
    say "ERROR_HINT=$live_err_hint"
  fi
  say "LOG=$live_out"

  say ""
  say "== resume-cwd doctrine =="
  say "If resume-from-repo and resume-from-live report different PWD/BRANCH values, explicit codex exec resume is caller-cwd-bound in this environment."
  say "Manual fork follow-up (interactive): codex --no-alt-screen fork $session_id"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    search-matrix|resume-cwd|all)
      mode="$1"
      ;;
    --live-worktree)
      shift
      [ "$#" -gt 0 ] || die "--live-worktree requires a path"
      live_worktree="$1"
      ;;
    --disabled-worktree)
      shift
      [ "$#" -gt 0 ] || die "--disabled-worktree requires a path"
      disabled_worktree="$1"
      ;;
    --report-dir)
      shift
      [ "$#" -gt 0 ] || die "--report-dir requires a path"
      report_dir="$1"
      ;;
    --create-controls)
      create_controls=1
      ;;
    --mirror-scaffold)
      mirror_scaffold=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

require_cmd git
require_cmd codex
require_cmd perl

mkdir -p "$report_dir"

say "Codex runtime probe: $(date -Is 2>/dev/null || date)"
say "MODE=$mode"
say "CREATE_CONTROLS=$create_controls"
say "MIRROR_SCAFFOLD=$mirror_scaffold"

case "$mode" in
  search-matrix)
    run_search_matrix
    ;;
  resume-cwd)
    run_resume_probe
    ;;
  all)
    run_search_matrix
    say ""
    run_resume_probe
    ;;
esac
