# Learning Ledger (append-only)

This file is appended by `./sysop/run.sh all` after a successful run.


## 2026-01-04T21:45:38-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 4
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-04T21:58:51-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 4
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-04T22:13:25-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 6
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`
