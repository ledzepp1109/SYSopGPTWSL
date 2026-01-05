#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || date)"
out_file="${WSL_BENCH_OUT_FILE:-}"
if [ -z "$out_file" ]; then
  out_dir="${WSL_BENCH_OUT_DIR:-$repo_root/sysop-report/perf}"
  mkdir -p "$out_dir"
  out_file="$out_dir/wsl-bench-${ts}.txt"
else
  case "$out_file" in
    /dev/stdout|/dev/stderr|/dev/null) ;;
    *) mkdir -p "$(dirname -- "$out_file")" ;;
  esac
fi

say() { printf '%s\n' "$*"; }

bench_body() {
  say "## WSL Bench (${ts})"
  say ""
  say "Context:"
  say "- repo_root: $repo_root"
  say "- uname: $(uname -a)"
  say "- nproc: $(nproc 2>/dev/null || echo '?')"
  say "- python3: $(python3 --version 2>/dev/null || echo 'missing')"
  say ""

  say "== CPU (sha256 loop) =="
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import hashlib
import os
import time

def loops_for_seconds(seconds: float) -> int:
    data = b"x" * 1024
    n = 0
    end = time.perf_counter() + seconds
    while time.perf_counter() < end:
        hashlib.sha256(data).digest()
        n += 1
    return n

single_s = float(os.environ.get("WSL_BENCH_CPU_SINGLE_SECONDS", "15"))

t0 = time.perf_counter()
single_n = loops_for_seconds(single_s)
t1 = time.perf_counter()
single_dt = t1 - t0
print(f"CPU single-thread: seconds={single_dt:.3f} loops={single_n} rate_per_s={single_n/single_dt:.0f}")
PY
    multi_s="${WSL_BENCH_CPU_MULTI_SECONDS:-30}"
    workers="${WSL_BENCH_WORKERS:-$(nproc 2>/dev/null || echo 1)}"
    if [ "${workers}" -lt 1 ] 2>/dev/null; then
      workers=1
    fi

    cpu_tmp="$(mktemp -d -p /tmp wsl-bench.cpu.XXXXXX)"
    fail=0
    pids=()
    start_ns="$(date +%s%N)"
    for i in $(seq 1 "$workers"); do
      python3 - "$multi_s" >"$cpu_tmp/${i}.out" 2>"$cpu_tmp/${i}.err" <<'PY' &
import hashlib
import sys
import time

seconds = float(sys.argv[1])
data = b"x" * 1024
n = 0
end = time.perf_counter() + seconds
while time.perf_counter() < end:
    hashlib.sha256(data).digest()
    n += 1
print(n)
PY
      pids+=("$!")
    done

    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        fail=1
      fi
    done
    end_ns="$(date +%s%N)"

    wall_s="$(awk -v a="$start_ns" -v b="$end_ns" 'BEGIN{print (b-a)/1e9}')"

    if [ "$fail" -eq 0 ]; then
      total_loops="$(awk '{s+=$1} END{print s+0}' "$cpu_tmp"/*.out 2>/dev/null || echo 0)"
      rate_per_s="$(awk -v loops="$total_loops" -v s="$wall_s" 'BEGIN{printf "%.0f", loops/s}')"
      say "CPU multi-process: workers=${workers} seconds=${wall_s} loops=${total_loops} rate_per_s=${rate_per_s}"
    else
      say "WARN: CPU multi-process bench failed (worker nonzero exit)"
      say "INFO: first error (if any):"
      sed -n '1,5p' "$cpu_tmp"/*.err 2>/dev/null | sed -n '1,5p' || true
    fi

    rm -f "$cpu_tmp"/* 2>/dev/null || true
    rmdir "$cpu_tmp" 2>/dev/null || true
  else
    say "SKIP: python3 missing"
  fi
  say ""

  say "== Memory (allocation + touch) =="
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import os
import time

mb = int(os.environ.get("WSL_BENCH_MEM_MB", "256"))
size = mb * 1024 * 1024

t0 = time.perf_counter()
b = bytearray(size)
t1 = time.perf_counter()

step = 4096
for i in range(0, len(b), step):
    b[i] = (b[i] + 1) & 0xFF
t2 = time.perf_counter()

print(f"Memory alloc: mb={mb} seconds={t1-t0:.3f}")
print(f"Memory touch: mb={mb} seconds={t2-t1:.3f} page_step={step}")
PY
  else
    say "SKIP: python3 missing"
  fi
  say ""

  say "== Disk (/tmp write + fsync, then read) =="
  tmpfile="$(mktemp -p /tmp wsl-bench.XXXXXX)"
  bytes=$((512 * 1024 * 1024))
  bs="4M"
  count=128

  say "Temp file: ${tmpfile} (size=512MiB)"

  start_ns="$(date +%s%N)"
  dd if=/dev/zero of="$tmpfile" bs="$bs" count="$count" conv=fdatasync status=none
  end_ns="$(date +%s%N)"
  write_s="$(awk -v a="$start_ns" -v b="$end_ns" 'BEGIN{print (b-a)/1e9}')"
  write_mib_s="$(awk -v bytes="$bytes" -v s="$write_s" 'BEGIN{printf "%.1f", (bytes/1024/1024)/s}')"
  say "Disk write: seconds=${write_s} mib_per_s=${write_mib_s} (fdatasync)"

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
  say "Disk read: seconds=${read_s} mib_per_s=${read_mib_s} mode=${read_mode}"

  rm -f "$tmpfile"
  say ""

  say "== Notes =="
  say "- Disk read results can be cache-influenced; write uses fdatasync for a stronger signal."
}

case "$out_file" in
  /dev/stdout)
    bench_body
    ;;
  /dev/stderr)
    bench_body >&2
    ;;
  /dev/null)
    bench_body >/dev/null
    ;;
  *)
    bench_body | tee "$out_file"
    ;;
esac

case "$out_file" in
  /dev/stdout|/dev/stderr|/dev/null) ;;
  *)
    say ""
    say "Wrote: $out_file"
    ;;
esac
