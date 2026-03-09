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
