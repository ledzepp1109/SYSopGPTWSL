#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
. "$script_dir/lib.sh"

out_dir="$repo_root/sysop/out"
auto_approve_safe=0
dry_run=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --auto-approve-safe) auto_approve_safe=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: sysop/fixes/apply.sh --repo-root <path> --out-dir <path> [--auto-approve-safe] [--dry-run]

Applies Level 1 SAFE fixes (best-effort retries) and generates Level 2-4 scripts/instructions under sysop/out/fixes/.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

win_json="$out_dir/windows_snapshot.json"
win_log="$out_dir/windows_snapshot.invoke.log"

kind="$(json_win_error_kind "$win_json")"
need_manual=0
failed=0

if [ -n "$kind" ]; then
  # Level 1: attempt retry (or determine manual requirement).
  retry_args=(--repo-root "$repo_root" --out-dir "$out_dir" --max-attempts 3)
  if [ "$auto_approve_safe" -eq 1 ]; then
    retry_args+=(--auto-approve-safe)
  fi
  if [ "$dry_run" -eq 1 ]; then
    retry_args+=(--dry-run)
  fi

  set +e
  "$script_dir/vsock_retry.sh" "${retry_args[@]}"
  rc=$?
  set -e

  case "$rc" in
    0) ;;
    2) need_manual=1 ;;
    *) failed=1 ;;
  esac

  # If snapshot still failing or interop appears down, generate manual scripts.
  kind2="$(json_win_error_kind "$win_json")"
  if [ -n "$kind2" ]; then
    if [ -f "$win_log" ] && grep -q "UtilBindVsockAnyPort" "$win_log"; then
      need_manual=1
    fi

    gen_args=(--repo-root "$repo_root" --out-dir "$out_dir")
    if [ "$dry_run" -eq 1 ]; then
      gen_args+=(--dry-run)
    fi

    "$script_dir/gen_power_plan.sh" "${gen_args[@]}" || true
    "$script_dir/edit_wslconfig.sh" "${gen_args[@]}" || true
    "$script_dir/manual_steps.sh" "${gen_args[@]}" || true
  fi
else
  say "No fixes suggested: Windows snapshot present and parseable."
fi

if [ "$failed" -eq 1 ]; then
  exit 1
fi
if [ "$need_manual" -eq 1 ]; then
  exit 2
fi
exit 0
