# SYSopGPTWSL Report

- CollectedAt: 2026-01-04T22:13:25-06:00
- Repo: /home/xhott/SYSopGPTWSL
- Artifacts: /home/xhott/SYSopGPTWSL/sysop/out

## Evidence (artifacts)

### WSL snapshot
- File: `/home/xhott/SYSopGPTWSL/sysop/out/wsl_snapshot.txt`
```text
9:[nproc]
12:[free -h]
14:Mem:           9.7Gi       504Mi       8.9Gi       3.5Mi       538Mi       9.2Gi
15:Swap:          4.0Gi          0B       4.0Gi
18:[mount | grep ' /mnt/c ']
```

### Windows snapshot
- File: `/home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json`
```text
Windows CPU: Intel(R) Core(TM) i5-1035G1 CPU @ 1.00GHz (cores=4, logical=8, max_mhz=1201, current_mhz=1201)
Windows RAM bytes: 16852422656
Windows Model: HP HP Laptop 14-dq1xxx
Windows OS: Microsoft Windows 11 Home (build=26200, arch=64-bit)
Windows GPU: Intel(R) UHD Graphics (driver=31.0.101.2137)
Windows power: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
```

### Bench
- File: `/home/xhott/SYSopGPTWSL/sysop/out/bench.txt`
```text
15:CPU single-thread: seconds=15.000 loops=9821730 rate_per_s=654782
16:CPU multi-process: workers=6 seconds=30.0463 loops=56649294 rate_per_s=1885400
19:Memory alloc: mb=256 seconds=0.274
20:Memory touch: mb=256 seconds=0.014 page_step=4096
24:Disk write: seconds=0.612775 mib_per_s=835.5 (fdatasync)
25:Disk read: seconds=0.106314 mib_per_s=4815.9 mode=iflag=direct
31:[/tmp] write: seconds=0.119348 mib_per_s=1072.5 (fdatasync)
32:[/tmp] read:  seconds=0.0250808 mib_per_s=5103.5 mode=iflag=direct
34:[/mnt/c] write: seconds=1.2864 mib_per_s=99.5 (fdatasync)
35:[/mnt/c] read:  seconds=0.838378 mib_per_s=152.7 mode=iflag=direct
```

## Top bottlenecks (ranked)
1) WSL not using full host resources (if you’re pushing CPU/RAM-intensive work)
   - Evidence: WSL `nproc`=6 vs Windows logical=8
   - Evidence: WSL Mem(total)=9.7Gi vs Windows RAM(bytes)=16852422656
2) Windows power plan not set to Ultimate Performance (if you want max boost/latency bias)
   - Evidence: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
3) Cross-OS filesystem overhead on /mnt/c (drvfs/9p)
   - Evidence: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
4) /mnt/c IO throughput can be materially lower than Linux FS
   - Evidence: see the `[/tmp]` vs `[/mnt/c]` lines in `/home/xhott/SYSopGPTWSL/sysop/out/bench.txt`
5) Windows snapshot JSON may be UTF-8 BOM-prefixed (pipeline must be BOM-tolerant)
   - Evidence: report generation uses `utf-8-sig` when reading `windows_snapshot.json`

## Suggested tuning commands (not run by this repo)

### Windows power plan (from WSL; avoids UNC cwd)
```bash
# Verify
(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)

# Switch to Ultimate Performance
(cd /mnt/c && powercfg.exe /S 1a2f010b-65d0-4f4b-915d-3c8c3705ef0d)

# Rollback to current scheme
(cd /mnt/c && powercfg.exe /S 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c)
```

### WSL resource caps (.wslconfig) — example workflow (Windows PowerShell)
- This repo will not edit `.wslconfig` for you; apply changes manually with backup + rollback.
```powershell
# Backup current .wslconfig (if present)
$p = Join-Path $env:USERPROFILE ".wslconfig"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path $p) { Copy-Item $p "$p.bak-$ts" -Force }

# Rollback example (replace <timestamp>):
Copy-Item "$p.bak-<timestamp>" $p -Force

# Edit $p to adjust caps under [wsl2], then apply:
wsl --shutdown

# Verify after reopening WSL:
#   nproc
#   free -h
```
