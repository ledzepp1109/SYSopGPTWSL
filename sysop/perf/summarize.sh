#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

win_json="$repo_root/sysop-report/windows/snapshot.json"
win_txt="$repo_root/sysop-report/windows/snapshot.txt"
run_md="$repo_root/sysop/windows/RUN.md"

latest_bench="$(ls -1t "$repo_root"/sysop-report/perf/wsl-bench-*.txt 2>/dev/null | head -n 1 || true)"

say() { printf '%s\n' "$*"; }

say "Perf Baseline Summary (read-only): $(date -Is 2>/dev/null || date)"
say "Repo: $repo_root"
say ""

say "== Windows snapshot =="
if [ -f "$win_json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$win_json" <<'PY'
import json
import sys

p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    data = json.load(f)

w = data.get("windows", {})

def first(obj, key):
    v = obj.get(key)
    if isinstance(v, dict):
        return v.get("data")
    return None

cpu = first(w, "cpu")
cs = first(w, "computer_system")
gpu = first(w, "gpu")
osinfo = first(w, "os")
power_active = w.get("power", {}).get("powercfg_active_scheme", {}).get("output", "")

def summarize_cpu(cpu_obj):
    if isinstance(cpu_obj, list) and cpu_obj:
        c0 = cpu_obj[0]
    elif isinstance(cpu_obj, dict):
        c0 = cpu_obj
    else:
        return "Windows CPU: (unknown)"
    return (
        f"Windows CPU: {c0.get('Name')} "
        f"(cores={c0.get('NumberOfCores')}, logical={c0.get('NumberOfLogicalProcessors')}, "
        f"max_mhz={c0.get('MaxClockSpeed')}, current_mhz={c0.get('CurrentClockSpeed')})"
    )

print(summarize_cpu(cpu))
if isinstance(cs, dict):
    print(f"Windows RAM bytes: {cs.get('TotalPhysicalMemory')}")
    print(f"Windows Model: {cs.get('Manufacturer')} {cs.get('Model')}")
if isinstance(osinfo, dict):
    print(f"Windows OS: {osinfo.get('Caption')} (build={osinfo.get('BuildNumber')}, arch={osinfo.get('OSArchitecture')})")
if isinstance(gpu, list) and gpu:
    g0 = gpu[0]
    print(f"Windows GPU: {g0.get('Name')} (driver={g0.get('DriverVersion')})")
elif isinstance(gpu, dict):
    print(f"Windows GPU: {gpu.get('Name')} (driver={gpu.get('DriverVersion')})")

if power_active:
    first_line = power_active.strip().splitlines()[0]
    print(f"Windows power: {first_line}")
else:
    print("Windows power: (unknown)")
PY
  else
    say "INFO: snapshot.json present but python3 missing (can’t summarize JSON)"
    say "INFO: see: $win_txt"
  fi
else
  say "MISSING: $win_json"
  if [ -f "$run_md" ]; then
    say ""
    say "Generate it from interactive WSL (copy/paste):"
    awk 'BEGIN{in_block=0} /^```bash/{in_block=1; next} /^```/{in_block=0} in_block{print}' "$run_md" || true
  else
    say "INFO: missing helper doc: $run_md"
  fi
fi

say ""
say "== WSL bench =="
if [ -n "$latest_bench" ] && [ -f "$latest_bench" ]; then
  say "Latest: $latest_bench"
  rg -n '^CPU (single-thread|multi-process):' "$latest_bench" || true
  rg -n '^Memory (alloc|touch):' "$latest_bench" || true
  rg -n '^Disk (write|read):' "$latest_bench" || true
else
  say "MISSING: sysop-report/perf/wsl-bench-*.txt"
  say "Run: ./sysop/perf/wsl-bench.sh"
fi
