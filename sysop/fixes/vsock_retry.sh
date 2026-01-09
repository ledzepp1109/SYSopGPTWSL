#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
. "$script_dir/lib.sh"

out_dir="$repo_root/sysop/out"
max_attempts=3
auto_approve_safe=0
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --max-attempts) max_attempts="$2"; shift 2 ;;
    --auto-approve-safe) auto_approve_safe=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: sysop/fixes/vsock_retry.sh [--repo-root <path>] [--out-dir <path>] [--max-attempts N] [--auto-approve-safe] [--dry-run]

Level 1 (SAFE): best-effort retry of Windows snapshot collection when it fails.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

win_json="$out_dir/windows_snapshot.json"
win_log="$out_dir/windows_snapshot.invoke.log"

kind="$(json_win_error_kind "$win_json")"
if [ -z "$kind" ]; then
  say "No-op: Windows snapshot has no recorded error."
  exit 0
fi

title="Windows snapshot failed (kind=${kind})"
details="Fix: retry snapshot (Level 1 SAFE, repo-scoped artifacts only)"

if [ "$dry_run" -eq 1 ]; then
  say "DRY-RUN: would retry snapshot up to ${max_attempts} times."
  exit 0
fi

if [ "$auto_approve_safe" -ne 1 ]; then
  if ! prompt_apply "$title" "$details"; then
    append_ledger_autofix \
      "$repo_root" \
      "Retry Windows snapshot (skipped)" \
      "1" "SAFE" \
      "no (prompt)" \
      "windows_snapshot: ${kind} -> (unchanged)" \
      "(none)" \
      ":" \
      "skipped" \
      "$win_json"
    exit 0
  fi
fi

backup_ts="$(ts_compact)"
backup_list=()
for f in "$out_dir/windows_snapshot.json" "$out_dir/windows_snapshot.txt" "$out_dir/windows_snapshot.invoke.log"; do
  if [ -f "$f" ]; then
    bak="${f}.bak-${backup_ts}"
    cp -a "$f" "$bak"
    backup_list+=("$bak")
  fi
done

rollback_cmd=":"
if [ "${#backup_list[@]}" -gt 0 ]; then
  rollback_cmd="for f in ${backup_list[*]}; do orig=\"\${f%.bak-*}\"; cp -a \"\$f\" \"\$orig\"; done"
fi

attempt=1
sleep_s=1
status="failed"
before_kind="$kind"

while [ "$attempt" -le "$max_attempts" ]; do
  say "Retry attempt ${attempt}/${max_attempts}: ./sysop/run.sh snapshot"
  (cd "$repo_root" && ./sysop/run.sh snapshot) >/dev/null 2>&1 || true

  kind="$(json_win_error_kind "$win_json")"
  if [ -z "$kind" ]; then
    status="applied"
    break
  fi

  if [ -f "$win_log" ] && grep -q "UtilBindVsockAnyPort" "$win_log"; then
    status="pending-restart"
    break
  fi

  attempt=$((attempt + 1))
  sleep "$sleep_s"
  sleep_s=$((sleep_s * 2))
done

after_kind="${kind:-"(none)"}"
approval="yes"
if [ "$auto_approve_safe" -eq 1 ]; then
  approval="auto (flag)"
fi

append_ledger_autofix \
  "$repo_root" \
  "Retry Windows snapshot" \
  "1" "SAFE" \
  "$approval" \
  "windows_snapshot: ${before_kind} -> ${after_kind}" \
  "${backup_list[*]:-(none)}" \
  "$rollback_cmd" \
  "$status" \
  "$win_json"

case "$status" in
  applied) exit 0 ;;
  pending-restart) exit 2 ;;
  *) exit 1 ;;
esac
