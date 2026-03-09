#!/usr/bin/env bash
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./sysop/apply-codex-target-state.sh <compact-source-file> <repo-root>

Applies the Phase 3 Codex target state with timestamped backups and an audit report.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

abs_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
}

backup_file() {
  local src="$1"
  local backup_root="$2"
  [ -e "$src" ] || return 0
  local rel
  rel="$(python3 - "$src" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1]).resolve()
if path.is_absolute():
    rel = path.as_posix().lstrip("/")
else:
    rel = path.as_posix()
print(rel)
PY
)"
  mkdir -p "$backup_root/$(dirname "$rel")"
  cp -a "$src" "$backup_root/$rel"
}

write_repo_config() {
  local target="$1"
  cat >"$target" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
web_search = "live"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false

[features]
multi_agent = true

[agents]
max_threads = 4
max_depth = 2

[agents.researcher]
description = "Evidence-first researcher. Establish observed local evidence before change."
config_file = "agents/researcher.toml"

[agents.challenger]
description = "Adversarial reviewer. Produce the strongest blocking counterargument and stop weak changes."
config_file = "agents/challenger.toml"

[agents.implementer]
description = "Minimal-diff implementer. Apply only approved changes with rollback in mind."
config_file = "agents/implementer.toml"

[agents.verifier]
description = "Local verifier. Confirm claimed effects and fail unresolved changes."
config_file = "agents/verifier.toml"
EOF
}

write_role_configs() {
  local agents_dir="$1"
  mkdir -p "$agents_dir"

  cat >"$agents_dir/researcher.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
sandbox_mode = "read-only"
web_search = "live"

developer_instructions = """
You are the Researcher role.
- Stay read-only.
- Establish observed local evidence before proposing any change.
- Use official docs, official changelogs, and direct local reproduction as primary evidence.
- Use live web search when current upstream truth matters.
- Do not shortcut into implementation.
"""
EOF

  cat >"$agents_dir/challenger.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
sandbox_mode = "read-only"
web_search = "live"

developer_instructions = """
You are the Challenger role.
- Stay read-only.
- Build the strongest adversarial case against the plan.
- Block unsafe, weak, or under-evidenced changes.
- Use official docs, official changelogs, and direct local reproduction as primary evidence.
- Use live web search when current upstream truth matters.
"""
EOF

  cat >"$agents_dir/implementer.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
sandbox_mode = "workspace-write"
web_search = "disabled"

[sandbox_workspace_write]
network_access = false

developer_instructions = """
You are the Implementer role.
- Apply only changes that survived researcher and challenger review.
- Keep diffs minimal and reversible.
- Never commit on your own.
- Prefer local evidence and local edits over speculation.
"""
EOF

  cat >"$agents_dir/verifier.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
sandbox_mode = "read-only"
web_search = "live"

developer_instructions = """
You are the Verifier role.
- Stay read-only.
- Confirm claimed effects locally.
- Fail unresolved, weak, or insufficiently demonstrated outcomes.
- Use official docs, official changelogs, and direct local reproduction as primary evidence.
- Use live web search when current upstream truth matters.
"""
EOF
}

upsert_agents_doctrine() {
  local target="$1"
  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
if path.exists():
    text = path.read_text(encoding="utf-8")
else:
    text = "# GPT/Codex WSL Sysop Repo\n"

block = """<!-- BEGIN SYSOP GATE DOCTRINE -->
## Sysop Gate Doctrine
- All material changes must flow through `Researcher -> Challenger -> Implementer -> Verifier`.
- The hard enforcement point for material changes is `sysop/sysop-gate.sh`.
- No material change may be treated as complete, and no commit may be created by the steady-state gate, unless all four stages complete successfully.
- Researcher and Challenger establish and challenge evidence first. Implementer acts only on a passed challenge. Verifier must confirm the final state before commit.
- Primary docs, official changelogs, and direct local reproduction outrank issue trackers, forums, and other advisory sources.
- If the gate returns `BLOCK` or `FAIL`, do not bypass it by direct editing unless the user explicitly waives the gate for that task.
- For steady-state material changes, this doctrine outranks any older manual workflow text below if they conflict.
<!-- END SYSOP GATE DOCTRINE -->
"""

start = "<!-- BEGIN SYSOP GATE DOCTRINE -->"
end = "<!-- END SYSOP GATE DOCTRINE -->"

if start in text and end in text:
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    new_text = before.rstrip() + "\n\n" + block + after
else:
    lines = text.splitlines()
    if lines:
        insert_at = 1
        while insert_at < len(lines) and lines[insert_at].startswith("#"):
            insert_at += 1
        prefix = "\n".join(lines[:insert_at]).rstrip()
        suffix = "\n".join(lines[insert_at:]).lstrip()
        new_text = prefix + "\n\n" + block
        if suffix:
            new_text += "\n\n" + suffix
    else:
        new_text = block

    if not new_text.endswith("\n"):
        new_text += "\n"

path.write_text(new_text, encoding="utf-8")
PY
}

probe_is_sound() {
  local target="$1"
  [ -f "$target" ] || return 1
  grep -q 'codex sandbox linux --full-auto' "$target" &&
    grep -q 'codex exec -C "\\$repo_root"' "$target" &&
    grep -q 'RESULT=pass' "$target"
}

write_network_probe() {
  local target="$1"
  cat >"$target" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
report_dir="${CODEX_NETWORK_PROBE_REPORT_DIR:-$repo_root/sysop/out/codex-network-denial-$(date +%Y%m%d-%H%M%S)}"
control_url="${CODEX_NETWORK_PROBE_URL:-https://example.com}"
control_ip="${CODEX_NETWORK_PROBE_IP:-93.184.216.34}"

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./sysop/codex-network-denial-probe.sh [--report-dir PATH]
USAGE
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

extract_key() {
  local key="$1"
  local file="$2"
  grep -E "^${key}=" "$file" | tail -n 1 | sed "s/^${key}=//"
}

socket_python='import socket; s=socket.socket(); s.settimeout(5); s.connect(("'"$control_ip"'", 443)); print("CONNECTED")'
exec_prompt="Do not use web search. Run exactly this shell command and nothing else before answering: python3 -c '$socket_python' . Then answer exactly three lines: RC=<exit code>; OUT=<stdout or none>; ERR=<stderr or none>."

while [ "$#" -gt 0 ]; do
  case "$1" in
    --report-dir)
      shift
      [ "$#" -gt 0 ] || die "--report-dir requires a path"
      report_dir="$1"
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

require_cmd codex
require_cmd curl
require_cmd python3

mkdir -p "$report_dir"

host_log="$report_dir/host-control.log"
direct_log="$report_dir/direct-sandbox-socket.log"
exec_log="$report_dir/repo-exec-socket.log"

host_rc="$(run_capture "$host_log" curl -I -sS -o /dev/null -w 'HTTP_CODE=%{http_code}\n' --max-time 5 "$control_url")"
direct_rc="$(run_capture "$direct_log" codex sandbox linux --full-auto python3 -c "$socket_python")"
exec_rc="$(run_capture "$exec_log" codex exec -C "$repo_root" "$exec_prompt")"

host_http_code="$(extract_key HTTP_CODE "$host_log" || true)"
exec_shell_rc="$(extract_key RC "$exec_log" || true)"
exec_shell_err="$(extract_key ERR "$exec_log" || true)"

host_ok=0
direct_denied=0
exec_denied=0

case "$host_http_code" in
  2*|3*) host_ok=1 ;;
esac

if grep -E -q 'PermissionError|Operation not permitted' "$direct_log"; then
  direct_denied=1
fi

if [ "$exec_shell_rc" = "1" ] && printf '%s' "$exec_shell_err" | grep -E -q 'PermissionError|Operation not permitted'; then
  exec_denied=1
fi

say "REPORT_DIR=$report_dir"
say "HOST_RC=$host_rc"
say "HOST_HTTP_CODE=${host_http_code:-unknown}"
say "DIRECT_RC=$direct_rc"
say "EXEC_RC=$exec_rc"
say "EXEC_SHELL_RC=${exec_shell_rc:-unknown}"

if [ "$host_ok" = "1" ] && [ "$direct_denied" = "1" ] && [ "$exec_denied" = "1" ]; then
  say "RESULT=pass"
elif [ "$host_ok" != "1" ]; then
  say "RESULT=inconclusive"
elif grep -q 'CONNECTED' "$direct_log" || printf '%s' "$exec_shell_err" | grep -q 'CONNECTED'; then
  say "RESULT=fail"
else
  say "RESULT=inconclusive"
fi
EOF
  chmod +x "$target"
}

main() {
  [ "$#" -eq 2 ] || {
    usage
    exit 2
  }

  require_cmd python3

  local compact_source repo_root
  compact_source="$(abs_path "$1")"
  repo_root="$(abs_path "$2")"

  [ -f "$compact_source" ] || die "compact source file not found: $compact_source"
  [ -d "$repo_root/.git" ] || die "repo root is not a git repository: $repo_root"

  local script_dir
  script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local classifier="$script_dir/compact-target-diff.py"
  [ -x "$classifier" ] || chmod +x "$classifier"

  local audit_dir="$repo_root/.codex_audit"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local migration_dir="$audit_dir/migrations/$timestamp"
  local classifier_report="$audit_dir/09_compact_target_diff.md"
  mkdir -p "$migration_dir" "$audit_dir"

  "$classifier" "$compact_source" >"$classifier_report"

  local user_config="$HOME/.codex/config.toml"
  local repo_config="$repo_root/.codex/config.toml"
  local repo_agents_dir="$repo_root/.codex/agents"
  local repo_agents="$repo_root/AGENTS.md"
  local network_probe="$repo_root/sysop/codex-network-denial-probe.sh"
  local gate_script="$repo_root/sysop/sysop-gate.sh"

  mkdir -p "$repo_root/.codex" "$repo_root/sysop"

  backup_file "$user_config" "$migration_dir"
  backup_file "$repo_config" "$migration_dir"
  backup_file "$repo_agents" "$migration_dir"
  backup_file "$network_probe" "$migration_dir"
  backup_file "$gate_script" "$migration_dir"
  backup_file "$repo_root/.codex/agents/researcher.toml" "$migration_dir"
  backup_file "$repo_root/.codex/agents/challenger.toml" "$migration_dir"
  backup_file "$repo_root/.codex/agents/implementer.toml" "$migration_dir"
  backup_file "$repo_root/.codex/agents/verifier.toml" "$migration_dir"

  write_repo_config "$repo_config"
  write_role_configs "$repo_agents_dir"
  upsert_agents_doctrine "$repo_agents"

  if ! probe_is_sound "$network_probe"; then
    backup_file "$network_probe" "$migration_dir"
    write_network_probe "$network_probe"
  fi

  backup_file "$repo_root/sysop/compact-target-diff.py" "$migration_dir"
  backup_file "$repo_root/sysop/apply-codex-target-state.sh" "$migration_dir"
  backup_file "$repo_root/sysop/sysop-gate.sh" "$migration_dir"

  if [ "$script_dir/compact-target-diff.py" != "$repo_root/sysop/compact-target-diff.py" ]; then
    cp -f "$script_dir/compact-target-diff.py" "$repo_root/sysop/compact-target-diff.py"
  fi
  if [ "$script_dir/apply-codex-target-state.sh" != "$repo_root/sysop/apply-codex-target-state.sh" ]; then
    cp -f "$script_dir/apply-codex-target-state.sh" "$repo_root/sysop/apply-codex-target-state.sh"
  fi
  if [ "$script_dir/sysop-gate.sh" != "$repo_root/sysop/sysop-gate.sh" ]; then
    cp -f "$script_dir/sysop-gate.sh" "$repo_root/sysop/sysop-gate.sh"
  fi
  chmod +x "$repo_root/sysop/compact-target-diff.py" "$repo_root/sysop/apply-codex-target-state.sh" "$repo_root/sysop/sysop-gate.sh"

  python3 - "$user_config" "$repo_root" "$repo_root"/wt/* <<'PY'
from pathlib import Path
import sys

user_config = Path(sys.argv[1]).expanduser()
repo_root = Path(sys.argv[2]).resolve()
worktrees = [Path(arg).resolve() for arg in sys.argv[3:] if Path(arg).exists()]

if user_config.exists():
    lines = user_config.read_text(encoding="utf-8").splitlines()
else:
    lines = []

while lines and not lines[-1].strip():
    lines.pop()

top_level = []
tables = []
in_table = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        in_table = True
    if not in_table:
        top_level.append(line)
    else:
        tables.append(line)

def upsert_top_level(key: str, value: str) -> None:
    prefix = f"{key} ="
    for idx, line in enumerate(top_level):
        if line.strip().startswith(prefix):
            top_level[idx] = f'{key} = "{value}"'
            return
    top_level.append(f'{key} = "{value}"')

filtered_top_level = []
for line in top_level:
    if line.strip() == "steer = true":
        continue
    filtered_top_level.append(line)
top_level = filtered_top_level

upsert_top_level("model", "gpt-5.4")
upsert_top_level("model_reasoning_effort", "xhigh")

project_targets = [repo_root] + sorted(worktrees)
table_text = "\n".join(tables)

def set_trust(text: str, project_path: str) -> str:
    lines = text.splitlines()
    block_header = f'[projects."{project_path}"]'
    out = []
    idx = 0
    found = False
    while idx < len(lines):
      line = lines[idx]
      out.append(line)
      idx += 1
      if line.strip() != block_header:
          continue
      found = True
      inserted = False
      while idx < len(lines) and not (lines[idx].strip().startswith("[") and lines[idx].strip().endswith("]")):
          if lines[idx].strip().startswith("trust_level ="):
              out.append('trust_level = "trusted"')
              idx += 1
              inserted = True
              while idx < len(lines) and not (lines[idx].strip().startswith("[") and lines[idx].strip().endswith("]")):
                  out.append(lines[idx])
                  idx += 1
              break
          out.append(lines[idx])
          idx += 1
      if not inserted:
          out.append('trust_level = "trusted"')
    if not found:
        if out and out[-1].strip():
            out.append("")
        out.extend([block_header, 'trust_level = "trusted"'])
    return "\n".join(out)

for path in project_targets:
    table_text = set_trust(table_text, path.as_posix())

result = "\n".join(top_level).rstrip()
if table_text.strip():
    result = (result + "\n\n" + table_text.strip() + "\n").lstrip("\n")
else:
    result = result + "\n"

user_config.parent.mkdir(parents=True, exist_ok=True)
user_config.write_text(result, encoding="utf-8")
PY

  local synced_worktrees=()
  local skipped_worktrees=()
  local wt_dir
  for wt_dir in "$repo_root"/wt/*; do
    [ -d "$wt_dir" ] || continue
    local wt_name
    wt_name="$(basename "$wt_dir")"
    if [ ! -f "$wt_dir/.codex/config.toml" ]; then
      skipped_worktrees+=("$wt_name:no-config")
      continue
    fi
    if [[ "$wt_name" == "codex-fresh-runtime-control" || "$wt_name" == "codex-search-disabled-control" ]]; then
      skipped_worktrees+=("$wt_name:intentional-control")
      continue
    fi
    backup_file "$wt_dir/.codex/config.toml" "$migration_dir"
    backup_file "$wt_dir/.codex/agents/researcher.toml" "$migration_dir"
    backup_file "$wt_dir/.codex/agents/challenger.toml" "$migration_dir"
    backup_file "$wt_dir/.codex/agents/implementer.toml" "$migration_dir"
    backup_file "$wt_dir/.codex/agents/verifier.toml" "$migration_dir"
    backup_file "$wt_dir/AGENTS.md" "$migration_dir"
    mkdir -p "$wt_dir/.codex/agents"
    cp -f "$repo_config" "$wt_dir/.codex/config.toml"
    cp -f "$repo_agents_dir/"*.toml "$wt_dir/.codex/agents/"
    cp -f "$repo_agents" "$wt_dir/AGENTS.md"
    synced_worktrees+=("$wt_name")
  done

  cat >"$audit_dir/10_target_state_migration.md" <<EOF
# Target State Migration

- Timestamp: $timestamp
- Compact source: \`$compact_source\`
- Classifier report: \`$classifier_report\`
- Backup dir: \`$migration_dir\`
- Repo root: \`$repo_root\`

## Root files applied
- \`.codex/config.toml\`
- \`.codex/agents/researcher.toml\`
- \`.codex/agents/challenger.toml\`
- \`.codex/agents/implementer.toml\`
- \`.codex/agents/verifier.toml\`
- \`AGENTS.md\`
- \`sysop/codex-network-denial-probe.sh\` (reused if sound; rewritten only if unsound or missing)

## User config patch targets
- \`model = "gpt-5.4"\`
- \`model_reasoning_effort = "xhigh"\`
- remove \`steer = true\` if present
- trust \`$repo_root\`
- trust every existing \`$repo_root/wt/*\`

## Worktree sync decisions
- Synced: ${synced_worktrees[*]:-(none)}
- Skipped: ${skipped_worktrees[*]:-(none)}

## Notes
- The saved compact source was a placeholder rather than a concrete runtime dump, so the classifier report records absence of compact evidence separately from live repo inspection.
- Experimental control worktrees were not blindly normalized when their names or configs indicated intentional divergence.
EOF

  say "APPLY_DONE"
  say "BACKUP_DIR=$migration_dir"
  say "CLASSIFIER_REPORT=$classifier_report"
}

main "$@"
