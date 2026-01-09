#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

out_dir="$repo_root/sysop/out"
win_json="$out_dir/windows_snapshot.json"
win_txt="$out_dir/windows_snapshot.txt"
wsl_txt="$out_dir/wsl_snapshot.txt"
bench_txt="$out_dir/bench.txt"

mkdir -p "$out_dir"

say() { printf '%s\n' "$*"; }

now="$(date -Is 2>/dev/null || date)"

say "# SYSopGPTWSL Report"
say ""
say "- CollectedAt: $now"
say "- Repo: $repo_root"
say "- Artifacts: $out_dir"

wsl_nproc="$(nproc 2>/dev/null || true)"
wsl_mem_total="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2; exit}' || true)"
wsl_mntc="$(mount | grep -E ' /mnt/c ' | head -n 1 || true)"

win_logical=""
win_ram_bytes=""
power_active_line=""
power_active_guid=""
power_ultimate_guid=""
if command -v python3 >/dev/null 2>&1 && [ -f "$win_json" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      win_logical) win_logical="$v" ;;
      win_ram_bytes) win_ram_bytes="$v" ;;
      power_active_line) power_active_line="$v" ;;
      power_active_guid) power_active_guid="$v" ;;
      power_ultimate_guid) power_ultimate_guid="$v" ;;
    esac
  done < <(
    python3 - "$win_json" <<'PY'
import json
import re
import sys

p = sys.argv[1]
try:
    with open(p, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception:
    raise SystemExit(0)

w = data.get("windows", {})
cpu = (w.get("cpu") or {}).get("data") or {}
cs = (w.get("computer_system") or {}).get("data") or {}
power = w.get("power") or {}

active_out = ((power.get("powercfg_active_scheme") or {}).get("output") or "").strip()
active_line = active_out.splitlines()[0] if active_out else ""
active_guid = ""
m = re.search(r"Power Scheme GUID:\s*([0-9a-fA-F-]+)", active_line)
if m:
    active_guid = m.group(1)

list_out = ((power.get("powercfg_list") or {}).get("output") or "")
ultimate_guid = ""
for line in list_out.splitlines():
    m = re.search(r"Power Scheme GUID:\s*([0-9a-fA-F-]+)\s+\(Ultimate Performance\)", line)
    if m:
        ultimate_guid = m.group(1)
        break

print(f"win_logical={cpu.get('NumberOfLogicalProcessors','')}")
print(f"win_ram_bytes={cs.get('TotalPhysicalMemory','')}")
print(f"power_active_line={active_line}")
print(f"power_active_guid={active_guid}")
print(f"power_ultimate_guid={ultimate_guid}")
PY
  )
fi

say ""
say "## Evidence (artifacts)"

say ""
say "### WSL snapshot"
if [ -f "$wsl_txt" ]; then
  say "- File: \`$wsl_txt\`"
  say '```text'
  rg -n '^\[nproc\]$|^\[free -h\]$|^Mem:|^Swap:|^\[mount' "$wsl_txt" || true
  say '```'
else
  say "- MISSING: \`$wsl_txt\`"
  say "- Run: \`./sysop/run.sh health\`"
fi

say ""
say "### Windows snapshot"
if [ -f "$win_json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    say "- File: \`$win_json\`"
    say '```text'
    python3 - "$win_json" <<'PY'
import json
import sys

p = sys.argv[1]
try:
    with open(p, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception as e:
    print("Snapshot JSON parse failed (likely BOM).")
    print(f"File: {p}")
    print(f"Error: {e}")
    print("")
    print("Regenerate snapshot (from repo root):")
    print("  ./sysop/run.sh snapshot")
    raise SystemExit(1)

w = data.get("windows", {})

err = w.get("error")
if isinstance(err, dict):
    kind = err.get("kind", "unknown")
    msg = err.get("message", "")
    cmd = err.get("command", "")
    rc = err.get("exit_code", "")
    logf = err.get("log_file", "")
    print(f"Windows snapshot ERROR: kind={kind}")
    if msg:
        print(f"Message: {msg}")
    if cmd:
        print(f"Command: {cmd}")
    if rc != "":
        print(f"Exit code: {rc}")
    if logf:
        print(f"Log file: {logf}")
    raise SystemExit(0)

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
    say '```'
  else
    say "- INFO: windows_snapshot.json present but python3 missing (can’t summarize JSON)"
    say "- INFO: see: \`$win_txt\`"
  fi
else
  say "- MISSING: \`$win_json\`"
  say "- Run: \`./sysop/run.sh snapshot\`"
fi

say ""
say "### Bench"
if [ -f "$bench_txt" ]; then
  say "- File: \`$bench_txt\`"
  say '```text'
  rg -n '^CPU (single-thread|multi-process):' "$bench_txt" || true
  rg -n '^Memory (alloc|touch):' "$bench_txt" || true
  rg -n -F 'Disk write:' "$bench_txt" || true
  rg -n -F 'Disk read:' "$bench_txt" || true
  rg -n -F '[/tmp] ' "$bench_txt" || true
  rg -n -F '[/mnt/c] ' "$bench_txt" || true
  say '```'
else
  say "- MISSING: \`$bench_txt\`"
  say "- Run: \`./sysop/run.sh bench\`"
fi

say ""
say "## Top bottlenecks (ranked)"

say "1) WSL not using full host resources (if you’re pushing CPU/RAM-intensive work)"
if [ -n "$wsl_nproc" ] && [ -n "$win_logical" ]; then
  say "   - Evidence: WSL \`nproc\`=${wsl_nproc} vs Windows logical=${win_logical}"
else
  say "   - Evidence: (missing WSL/Windows CPU counts)"
fi
if [ -n "$wsl_mem_total" ] && [ -n "$win_ram_bytes" ]; then
  say "   - Evidence: WSL Mem(total)=${wsl_mem_total} vs Windows RAM(bytes)=${win_ram_bytes}"
fi

say "2) Windows power plan not set to Ultimate Performance (if you want max boost/latency bias)"
if [ -n "$power_active_line" ]; then
  say "   - Evidence: ${power_active_line}"
else
  say "   - Evidence: (missing powercfg active scheme)"
fi

say "3) Cross-OS filesystem overhead on /mnt/c (drvfs/9p)"
if [ -n "$wsl_mntc" ]; then
  say "   - Evidence: ${wsl_mntc}"
else
  say "   - Evidence: (missing /mnt/c mount line)"
fi

say "4) /mnt/c IO throughput can be materially lower than Linux FS"
if [ -f "$bench_txt" ]; then
  say "   - Evidence: see the \`[/tmp]\` vs \`[/mnt/c]\` lines in \`$bench_txt\`"
else
  say "   - Evidence: (missing bench)"
fi

say "5) Windows snapshot JSON may be UTF-8 BOM-prefixed (pipeline must be BOM-tolerant)"
say "   - Evidence: report generation uses \`utf-8-sig\` when reading \`windows_snapshot.json\`"

say ""
say "## Suggested tuning commands (not run by this repo)"
say ""
say "### Windows power plan (from WSL; avoids UNC cwd)"
if [ -n "$power_active_guid" ] && [ -n "$power_ultimate_guid" ]; then
  say '```bash'
  say "# Verify"
  say "(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)"
  say ""
  say "# Switch to Ultimate Performance"
  say "(cd /mnt/c && powercfg.exe /S ${power_ultimate_guid})"
  say ""
  say "# Rollback to current scheme"
  say "(cd /mnt/c && powercfg.exe /S ${power_active_guid})"
  say '```'
else
  say "- INFO: couldn’t extract GUIDs from windows_snapshot.json (missing snapshot or powercfg output)"
fi

say ""
say "### WSL resource caps (.wslconfig) — example workflow (Windows PowerShell)"
say "- This repo will not edit \`.wslconfig\` for you; apply changes manually with backup + rollback."
say '```powershell'
say "# Backup current .wslconfig (if present)"
say '$p = Join-Path $env:USERPROFILE ".wslconfig"'
say '$ts = Get-Date -Format "yyyyMMdd-HHmmss"'
say 'if (Test-Path $p) { Copy-Item $p "$p.bak-$ts" -Force }'
say ''
say '# Rollback example (replace <timestamp>):'
say 'Copy-Item "$p.bak-<timestamp>" $p -Force'
say ""
say '# Edit $p to adjust caps under [wsl2], then apply:'
say "wsl --shutdown"
say ""
say "# Verify after reopening WSL:"
say "#   nproc"
say "#   free -h"
say '```'
