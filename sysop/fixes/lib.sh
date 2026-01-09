#!/usr/bin/env bash
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }

now_iso() { date -Is 2>/dev/null || date; }
ts_compact() { date +%Y%m%d-%H%M%S 2>/dev/null || date +%s; }

ensure_ledger() {
  local repo_root="$1"
  local ledger_dir ledger
  ledger_dir="$repo_root/learn"
  ledger="$ledger_dir/LEDGER.md"
  mkdir -p "$ledger_dir"
  if [ ! -f "$ledger" ]; then
    cat >"$ledger" <<'EOF'
# Learning Ledger (append-only)

This file is appended by `./sysop/run.sh all` after a successful run.
EOF
  fi
  printf '%s\n' "$ledger"
}

append_ledger_autofix() {
  # Required args:
  # 1=repo_root 2=fix 3=risk_num 4=risk_name 5=approval 6=changes 7=backup 8=rollback 9=status 10=evidence
  local repo_root="$1"
  local fix="$2"
  local risk_num="$3"
  local risk_name="$4"
  local approval="$5"
  local changes="$6"
  local backup="$7"
  local rollback="$8"
  local status="$9"
  local evidence="${10}"

  local ledger now
  ledger="$(ensure_ledger "$repo_root")"
  now="$(now_iso)"

  cat >>"$ledger" <<EOF

## ${now} [AUTO-FIX]

- Fix: ${fix}
- Risk: ${risk_num} (${risk_name})
- Approval: ${approval}
- Changes: ${changes}
- Backup: ${backup}
- Rollback: \`${rollback}\`
- Status: ${status}
- Evidence: ${evidence}
EOF
}

json_win_error_kind() {
  # args: 1=windows_snapshot.json path
  local json_path="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' ""
    return 0
  fi
  python3 - "$json_path" <<'PY' 2>/dev/null || true
import json
import sys

p = sys.argv[1]
try:
    with open(p, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception:
    print("")
    raise SystemExit(0)

kind = (
    (data.get("windows") or {})
        .get("error", {})
        .get("kind", "")
)
print(kind)
PY
}

is_interactive() {
  [ -t 0 ] && [ -t 1 ]
}

prompt_apply() {
  # args: 1=title, 2=details (single line)
  local title="$1"
  local details="$2"

  say ""
  say "Issue: ${title}"
  say "${details}"
  say -n "Apply? [y/N/skip] "

  local ans=""
  if ! is_interactive; then
    say "N (non-interactive)"
    return 1
  fi

  read -r ans || true
  case "${ans}" in
    y|Y|yes|YES) return 0 ;;
    skip|SKIP) return 1 ;;
    *) return 1 ;;
  esac
}
