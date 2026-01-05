#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
out_dir="$repo_root/sysop/out"

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./sysop/run.sh [health|bench|snapshot|summarize|report|all]

Writes outputs under: sysop/out/
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

mkdir -p "$out_dir"

write_wsl_snapshot() {
  {
    say "SYSopGPTWSL WSL Snapshot"
    say "CollectedAt: $(date -Is 2>/dev/null || date)"
    say "RepoRoot: $repo_root"
    say ""
    say "== Kernel =="
    uname -a
    say ""
    say "== Resources =="
    say "[nproc]"
    nproc 2>/dev/null || true
    say ""
    say "[free -h]"
    free -h || true
    say ""
    say "== Filesystems =="
    say "[mount | grep ' /mnt/c ']"
    mount | grep -E ' /mnt/c ' || true
  } >"$out_dir/wsl_snapshot.txt"
}

step_health() {
  write_wsl_snapshot
  say "+ ./sysop/preflight.sh"
  ./sysop/preflight.sh 2>&1 | tee "$out_dir/preflight.txt"
  say "+ ./sysop/healthcheck.sh"
  ./sysop/healthcheck.sh 2>&1 | tee "$out_dir/healthcheck.txt"
  say "+ ./sysop/drift-check.sh"
  ./sysop/drift-check.sh 2>&1 | tee "$out_dir/drift-check.txt"
}

step_snapshot() {
  require_cmd wslpath
  require_cmd powershell.exe

  local script_win out_win
  script_win="$(wslpath -w "$repo_root/sysop/windows/collect-windows.ps1")"
  out_win="$(wslpath -w "$out_dir")"

  say "+ (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$script_win\" -OutDir \"$out_win\")"
  (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_win" -OutDir "$out_win")

  test -f "$out_dir/windows_snapshot.json" || die "missing: $out_dir/windows_snapshot.json"
}

fs_tiny_bench() {
  # $1=directory, $2=label
  local dir="$1"
  local label="$2"

  local tmpfile bytes bs count
  bytes=$((128 * 1024 * 1024))
  bs="4M"
  count=32

  if ! tmpfile="$(mktemp -p "$dir" sysop-bench.XXXXXX 2>&1)"; then
    say "${label} SKIP: mktemp failed in ${dir}: ${tmpfile}"
    return 0
  fi

  local start_ns end_ns write_s write_mib_s read_s read_mib_s read_mode
  start_ns="$(date +%s%N)"
  dd if=/dev/zero of="$tmpfile" bs="$bs" count="$count" conv=fdatasync status=none
  end_ns="$(date +%s%N)"
  write_s="$(awk -v a="$start_ns" -v b="$end_ns" 'BEGIN{print (b-a)/1e9}')"
  write_mib_s="$(awk -v bytes="$bytes" -v s="$write_s" 'BEGIN{printf "%.1f", (bytes/1024/1024)/s}')"

  read_mode="iflag=direct"
  start_ns="$(date +%s%N)"
  if dd if="$tmpfile" of=/dev/null bs="$bs" iflag=direct status=none 2>/dev/null; then
    end_ns="$(date +%s%N)"
  else
    read_mode="(cached)"
    end_ns="$(date +%s%N)"
    start_ns="$(date +%s%N)"
    dd if="$tmpfile" of=/dev/null bs="$bs" status=none
    end_ns="$(date +%s%N)"
  fi
  read_s="$(awk -v a="$start_ns" -v b="$end_ns" 'BEGIN{print (b-a)/1e9}')"
  read_mib_s="$(awk -v bytes="$bytes" -v s="$read_s" 'BEGIN{printf "%.1f", (bytes/1024/1024)/s}')"

  rm -f "$tmpfile"

  say "${label} write: seconds=${write_s} mib_per_s=${write_mib_s} (fdatasync)"
  say "${label} read:  seconds=${read_s} mib_per_s=${read_mib_s} mode=${read_mode}"
}

step_bench() {
  {
    say "SYSopGPTWSL Bench"
    say "CollectedAt: $(date -Is 2>/dev/null || date)"
    say "RepoRoot: $repo_root"
    say ""
    say "== WSL Bench (CPU/mem/disk) =="
    WSL_BENCH_OUT_FILE=/dev/stdout ./sysop/perf/wsl-bench.sh 2>&1
    say ""
    say "== Tiny FS compare (/tmp vs /mnt/c) =="
    fs_tiny_bench /tmp "[/tmp]"
    if [ -d /mnt/c ]; then
      mntc_dir=""
      if [ -d "/mnt/c/Users/$USER" ] && [ -w "/mnt/c/Users/$USER" ]; then
        mntc_dir="/mnt/c/Users/$USER"
      elif [ -d "/mnt/c/Users" ] && [ -w "/mnt/c/Users" ]; then
        mntc_dir="/mnt/c/Users"
      elif [ -w "/mnt/c" ]; then
        mntc_dir="/mnt/c"
      fi

      if [ -n "$mntc_dir" ]; then
        say "mnt/c bench dir: ${mntc_dir}"
        fs_tiny_bench "$mntc_dir" "[/mnt/c]"
      else
        say "SKIP: no writable dir found under /mnt/c for bench"
      fi
    else
      say "SKIP: /mnt/c not present"
    fi
  } | tee "$out_dir/bench.txt"
}

step_summarize() {
  say "+ ./sysop/perf/summarize.sh | tee sysop/out/summary.md"
  ./sysop/perf/summarize.sh | tee "$out_dir/summary.md"
}

step_report() {
  if [ ! -f "$out_dir/summary.md" ]; then
    step_summarize >/dev/null
  fi
  cp -f "$out_dir/summary.md" "$out_dir/report.md"
  say "Wrote: $out_dir/report.md"
}

append_ledger_entry() {
  local ledger_dir ledger now nproc_out mntc_line win_power
  ledger_dir="$repo_root/learn"
  ledger="$ledger_dir/LEDGER.md"

  mkdir -p "$ledger_dir"
  if [ ! -f "$ledger" ]; then
    cat >"$ledger" <<'EOF'
# Learning Ledger (append-only)

This file is appended by `./sysop/run.sh all` after a successful run.
EOF
  fi

  now="$(date -Is 2>/dev/null || date)"
  nproc_out="$(nproc 2>/dev/null || echo '?')"
  mntc_line="$(mount | grep -E ' /mnt/c ' | head -n 1 || true)"

  win_power="(unknown)"
  if command -v python3 >/dev/null 2>&1 && [ -f "$out_dir/windows_snapshot.json" ]; then
    win_power="$(
      python3 - "$out_dir/windows_snapshot.json" <<'PY' 2>/dev/null || true
import json
import sys

p = sys.argv[1]
with open(p, "r", encoding="utf-8-sig") as f:
    data = json.load(f)

out = (
    data.get("windows", {})
        .get("power", {})
        .get("powercfg_active_scheme", {})
        .get("output", "")
        .strip()
        .splitlines()
)
print(out[0] if out else "(missing powercfg_active_scheme.output)")
PY
    )"
  fi

  cat >>"$ledger" <<EOF

## ${now}

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - \`nproc\`: ${nproc_out}
  - \`mount | grep ' /mnt/c '\`: ${mntc_line:-"(none)"}
  - Windows power: ${win_power}
- Regression risk: Low; outputs are under \`sysop/out/\`.
- Rule extracted: Always run Windows snapshot from \`/mnt/c\` and parse snapshot JSON with \`utf-8-sig\`.
- Where encoded: \`sysop/run.sh\`, \`sysop/perf/summarize.sh\`, \`sysop/windows/collect-windows.ps1\`
EOF
}

cmd="${1:-all}"
case "$cmd" in
  health) step_health ;;
  bench) step_bench ;;
  snapshot) step_snapshot ;;
  summarize) step_summarize ;;
  report) step_report ;;
  all)
    step_health
    step_bench
    step_snapshot
    step_summarize
    step_report
    append_ledger_entry
    ;;
  -h|--help|help) usage ;;
  *) usage; exit 2 ;;
esac
