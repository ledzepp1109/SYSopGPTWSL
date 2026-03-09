#!/usr/bin/env bash
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  sysop-gate.sh --repo <repo-root> --task "<task text>" [--commit]
  sysop-gate.sh --repo <repo-root> --task-file <path> [--commit]
  sysop-gate.sh --repo <repo-root> --task "<task text>" --probe-challenger-block
  sysop-gate.sh --repo <repo-root> --task "<task text>" --probe-verifier-fail
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

json_get() {
  local json_file="$1"
  local key="$2"
  python3 - "$json_file" "$key" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = payload
for part in sys.argv[2].split("."):
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value, sort_keys=True))
else:
    print(value)
PY
}

ensure_json_object() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(payload, dict):
    raise SystemExit(f"{path} did not contain a JSON object")
PY
}

cleanup_needed=0
temp_task_file=0
gate_task_file=""
repo_root_trap=""
gate_worktree=""
gate_branch=""

cleanup_on_exit() {
  if [ "${cleanup_needed:-0}" = "1" ] && [ -n "${repo_root_trap:-}" ] && [ -n "${gate_worktree:-}" ] && [ -n "${gate_branch:-}" ]; then
    cleanup_gate "$repo_root_trap" "$gate_worktree" "$gate_branch"
  fi
  if [ "${temp_task_file:-0}" = "1" ] && [ -n "${gate_task_file:-}" ] && [ -f "${gate_task_file:-}" ]; then
    unlink "$gate_task_file"
  fi
}

trap cleanup_on_exit EXIT

repo_is_clean() {
  local repo_root="$1"
  git -C "$repo_root" diff --quiet &&
    git -C "$repo_root" diff --cached --quiet &&
    [ -z "$(git -C "$repo_root" ls-files --others --exclude-standard)" ]
}

write_schema() {
  local target="$1"
  local stage="$2"
  case "$stage" in
    researcher)
      cat >"$target" <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["stage", "evidence", "risks", "approved_change_envelope"],
  "properties": {
    "stage": {"type": "string", "const": "researcher"},
    "evidence": {"type": "array", "items": {"type": "string"}},
    "risks": {"type": "array", "items": {"type": "string"}},
    "approved_change_envelope": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": false
}
EOF
      ;;
    challenger)
      cat >"$target" <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["stage", "verdict", "blocking_findings", "allowed_change_envelope"],
  "properties": {
    "stage": {"type": "string", "const": "challenger"},
    "verdict": {"type": "string", "enum": ["PASS", "BLOCK"]},
    "blocking_findings": {"type": "array", "items": {"type": "string"}},
    "allowed_change_envelope": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": false
}
EOF
      ;;
    implementer)
      cat >"$target" <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["stage", "summary", "changed_files", "rollback"],
  "properties": {
    "stage": {"type": "string", "const": "implementer"},
    "summary": {"type": "string"},
    "changed_files": {"type": "array", "items": {"type": "string"}},
    "rollback": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": false
}
EOF
      ;;
    verifier)
      cat >"$target" <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["stage", "verdict", "validated_effects", "remaining_risks"],
  "properties": {
    "stage": {"type": "string", "const": "verifier"},
    "verdict": {"type": "string", "enum": ["PASS", "FAIL"]},
    "validated_effects": {"type": "array", "items": {"type": "string"}},
    "remaining_risks": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": false
}
EOF
      ;;
    *)
      die "unknown schema stage: $stage"
      ;;
  esac
}

write_prompt() {
  local target="$1"
  local stage="$2"
  local task_file="$3"
  local run_dir_rel="$4"
  local probe_challenger_block="$5"
  local probe_verifier_fail="$6"
  local researcher_json="${7:-}"
  local challenger_json="${8:-}"
  local implementer_json="${9:-}"
  local task_text
  task_text="$(cat "$task_file")"

  case "$stage" in
    researcher)
      cat >"$target" <<EOF
You are the Researcher stage for sysop gate.
Work only in the current repository and do not modify files.
Use local repo evidence first and only use web search when current upstream truth matters.
The wrapper policy is authoritative for this run; do not reread governance docs unless the task specifically depends on them.
Collect only the minimum evidence needed for this task.
Task:
$task_text

Return raw JSON only that matches the provided schema.
The JSON must summarize:
- concrete evidence
- risks
- a narrow approved_change_envelope

The run artifact directory inside this worktree is: $run_dir_rel
EOF
      ;;
    challenger)
      cat >"$target" <<EOF
You are the Challenger stage for sysop gate.
Work only in the current repository and do not modify files.
Use the Researcher artifact below as input and return raw JSON only.
The wrapper policy is authoritative for this run; do not spend time rereading repo governance unless the task specifically depends on it.

Task:
$task_text

Researcher artifact:
$researcher_json

If the evidence is weak, overbroad, risky, or missing rollback clarity, return verdict BLOCK.
If everything is defensible, return verdict PASS.
EOF
      if [ "$probe_challenger_block" = "1" ]; then
        cat >>"$target" <<'EOF'

Probe override:
- This is a challenger-block probe.
- Return verdict BLOCK and explain that implementation must not proceed.
EOF
      elif [ "$probe_verifier_fail" = "1" ]; then
        cat >>"$target" <<'EOF'

Probe override:
- This is a verifier-fail probe.
- If the researcher envelope is narrow and local-only, return verdict PASS so the verifier stage becomes the enforcement point.
EOF
      fi
      ;;
    implementer)
      cat >"$target" <<EOF
You are the Implementer stage for sysop gate.
You may edit only inside the current worktree.
The wrapper policy is authoritative for this run; do not reread repo governance unless the task specifically depends on it.
Task:
$task_text

Researcher artifact:
$researcher_json

Challenger artifact:
$challenger_json

Apply only the narrow approved change envelope.
Keep the diff minimal and reversible.
Do not commit.
Return raw JSON only describing summary, changed_files, and rollback.
EOF
      if [ "$probe_verifier_fail" = "1" ]; then
        cat >>"$target" <<EOF

Probe override:
- Create the file $run_dir_rel/probe-verifier-fail.txt containing exactly: created-by-implementer
EOF
      fi
      ;;
    verifier)
      cat >"$target" <<EOF
You are the Verifier stage for sysop gate.
Work only in the current repository and do not modify files.
The wrapper policy is authoritative for this run; do not reread repo governance unless the task specifically depends on it.
Task:
$task_text

Researcher artifact:
$researcher_json

Challenger artifact:
$challenger_json

Implementer artifact:
$implementer_json

Validate the claimed effect locally.
Return verdict FAIL if the claimed outcome is not demonstrated.
Return raw JSON only.
EOF
      if [ "$probe_verifier_fail" = "1" ]; then
        cat >>"$target" <<EOF

Probe override:
- This is a verifier-fail probe.
- Fail unless the file $run_dir_rel/probe-verifier-fail.expected exists.
EOF
      fi
      ;;
    *)
      die "unknown prompt stage: $stage"
      ;;
  esac
}

run_stage() {
  local stage="$1"
  local repo_root="$2"
  local worktree="$3"
  local prompt_file="$4"
  local schema_file="$5"
  local json_output="$6"
  local stdout_log="$7"
  local stderr_log="$8"

  local sandbox_mode read_reasoning web_search
  case "$stage" in
    researcher|challenger|verifier)
      sandbox_mode="read-only"
      read_reasoning="xhigh"
      web_search="live"
      ;;
    implementer)
      sandbox_mode="workspace-write"
      read_reasoning="xhigh"
      web_search="disabled"
      ;;
    *)
      die "unknown stage: $stage"
      ;;
  esac

  codex exec \
    -C "$worktree" \
    -s "$sandbox_mode" \
    -m "gpt-5.4" \
    -c 'features.multi_agent=false' \
    -c 'approval_policy="never"' \
    -c "model_reasoning_effort=\"$read_reasoning\"" \
    -c "web_search=\"$web_search\"" \
    -c 'sandbox_workspace_write.network_access=false' \
    --output-schema "$schema_file" \
    -o "$json_output" \
    - <"$prompt_file" >"$stdout_log" 2>"$stderr_log"

  ensure_json_object "$json_output"
}

cleanup_gate() {
  local repo_root="$1"
  local gate_worktree="$2"
  local gate_branch="$3"
  git -C "$repo_root" worktree remove --force "$gate_worktree" >/dev/null 2>&1 || true
  git -C "$repo_root" branch -D "$gate_branch" >/dev/null 2>&1 || true
}

main() {
  require_cmd codex
  require_cmd git
  require_cmd python3

  local repo_root=""
  local task_text=""
  local task_file=""
  local do_commit=0
  local probe_challenger_block=0
  local probe_verifier_fail=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        shift
        [ "$#" -gt 0 ] || die "--repo requires a path"
        repo_root="$1"
        ;;
      --task)
        shift
        [ "$#" -gt 0 ] || die "--task requires text"
        task_text="$1"
        ;;
      --task-file)
        shift
        [ "$#" -gt 0 ] || die "--task-file requires a path"
        task_file="$1"
        ;;
      --commit)
        do_commit=1
        ;;
      --probe-challenger-block)
        probe_challenger_block=1
        ;;
      --probe-verifier-fail)
        probe_verifier_fail=1
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

  [ -n "$repo_root" ] || die "--repo is required"
  repo_root="$(python3 - "$repo_root" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"
  [ -d "$repo_root/.git" ] || die "not a git repo: $repo_root"
  repo_root_trap="$repo_root"
  mkdir -p "$repo_root/.codex_audit" "$repo_root/wt"

  if [ -n "$task_text" ] && [ -n "$task_file" ]; then
    die "use either --task or --task-file, not both"
  fi
  if [ -z "$task_text" ] && [ -z "$task_file" ]; then
    die "one of --task or --task-file is required"
  fi
  temp_task_file=0
  if [ -n "$task_text" ]; then
    task_file="$(mktemp /tmp/sysop-gate-task-XXXXXX.txt)"
    printf '%s\n' "$task_text" >"$task_file"
    temp_task_file=1
  else
    task_file="$(python3 - "$task_file" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"
  fi
  [ -f "$task_file" ] || die "task file not found: $task_file"
  gate_task_file="$task_file"

  repo_is_clean "$repo_root" || die "repo must be clean before sysop gate starts"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local base_ref run_dir run_dir_rel
  base_ref="$(git -C "$repo_root" rev-parse HEAD)"
  gate_branch="gate-$timestamp"
  gate_worktree="$repo_root/wt/.gate-$timestamp"
  run_dir_rel=".codex_audit/gate-runs/$timestamp"
  run_dir="$gate_worktree/$run_dir_rel"

  cleanup_needed=1

  git -C "$repo_root" branch "$gate_branch" "$base_ref" >/dev/null
  git -C "$repo_root" worktree add "$gate_worktree" "$gate_branch" >/dev/null
  mkdir -p "$run_dir"
  cp -f "$task_file" "$run_dir/task.txt"

  local research_schema challenge_schema implement_schema verify_schema
  research_schema="$run_dir/01_researcher.schema.json"
  challenge_schema="$run_dir/02_challenger.schema.json"
  implement_schema="$run_dir/03_implementer.schema.json"
  verify_schema="$run_dir/04_verifier.schema.json"
  write_schema "$research_schema" researcher
  write_schema "$challenge_schema" challenger
  write_schema "$implement_schema" implementer
  write_schema "$verify_schema" verifier

  local research_prompt research_json
  research_prompt="$run_dir/01_researcher.prompt.txt"
  research_json="$run_dir/01_researcher.json"
  write_prompt "$research_prompt" researcher "$run_dir/task.txt" "$run_dir_rel" "$probe_challenger_block" "$probe_verifier_fail"
  run_stage researcher "$repo_root" "$gate_worktree" "$research_prompt" "$research_schema" "$research_json" "$run_dir/01_researcher.stdout.log" "$run_dir/01_researcher.stderr.log"

  local challenge_prompt challenge_json challenge_verdict
  challenge_prompt="$run_dir/02_challenger.prompt.txt"
  challenge_json="$run_dir/02_challenger.json"
  write_prompt "$challenge_prompt" challenger "$run_dir/task.txt" "$run_dir_rel" "$probe_challenger_block" "$probe_verifier_fail" "$(cat "$research_json")"
  run_stage challenger "$repo_root" "$gate_worktree" "$challenge_prompt" "$challenge_schema" "$challenge_json" "$run_dir/02_challenger.stdout.log" "$run_dir/02_challenger.stderr.log"
  challenge_verdict="$(json_get "$challenge_json" verdict)"

  if [ "$challenge_verdict" != "PASS" ]; then
    cleanup_gate "$repo_root" "$gate_worktree" "$gate_branch"
    cleanup_needed=0
    say "GATE_BLOCK"
    say "WORKTREE_REMOVED=$gate_worktree"
    exit 1
  fi

  local implement_prompt implement_json
  implement_prompt="$run_dir/03_implementer.prompt.txt"
  implement_json="$run_dir/03_implementer.json"
  write_prompt "$implement_prompt" implementer "$run_dir/task.txt" "$run_dir_rel" "$probe_challenger_block" "$probe_verifier_fail" "$(cat "$research_json")" "$(cat "$challenge_json")"
  run_stage implementer "$repo_root" "$gate_worktree" "$implement_prompt" "$implement_schema" "$implement_json" "$run_dir/03_implementer.stdout.log" "$run_dir/03_implementer.stderr.log"

  local verify_prompt verify_json verify_verdict
  verify_prompt="$run_dir/04_verifier.prompt.txt"
  verify_json="$run_dir/04_verifier.json"
  write_prompt "$verify_prompt" verifier "$run_dir/task.txt" "$run_dir_rel" "$probe_challenger_block" "$probe_verifier_fail" "$(cat "$research_json")" "$(cat "$challenge_json")" "$(cat "$implement_json")"
  run_stage verifier "$repo_root" "$gate_worktree" "$verify_prompt" "$verify_schema" "$verify_json" "$run_dir/04_verifier.stdout.log" "$run_dir/04_verifier.stderr.log"
  verify_verdict="$(json_get "$verify_json" verdict)"

  if [ "$verify_verdict" != "PASS" ]; then
    cleanup_gate "$repo_root" "$gate_worktree" "$gate_branch"
    cleanup_needed=0
    say "GATE_FAIL"
    say "WORKTREE_REMOVED=$gate_worktree"
    exit 1
  fi

  if [ "$do_commit" = "1" ]; then
    if ! git -C "$gate_worktree" diff --quiet || ! git -C "$gate_worktree" diff --cached --quiet || [ -n "$(git -C "$gate_worktree" ls-files --others --exclude-standard)" ]; then
      git -C "$gate_worktree" add -A
      git -C "$gate_worktree" commit -m "sysop-gate: $(head -n 1 "$run_dir/task.txt" | cut -c1-72)" >/dev/null
    fi
  fi

  cleanup_needed=0
  say "GATE_PASS"
  say "WORKTREE=$gate_worktree"
  say "RUN_DIR=$run_dir"
}

main "$@"
