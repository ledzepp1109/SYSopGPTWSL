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

## 2026-01-04T23:56:22-06:00

- Symptom: Repo documentation needed alignment with Codex CLI `>=0.76.0` and progressive disclosure triggers.
- Cause hypothesis: Skill metadata and operator docs were correct but not optimized for newer Codex discovery/debugging flows.
- Fix applied: Added skill trigger metadata, setup guide, and machine-readable rules format.
- Evidence:
  - Added: `docs/CODEX_SETUP.md`
  - Updated: `.codex/skills/sysop-kernel/SKILL.md`, `learn/RULES.md`, `sysop/README_INDEX.md`, `README.md`
  - Added: `.codex/skills/sysop-kernel/references/CHANGELOG.md`
- Regression risk: Low; documentation-only changes.
- Rule extracted: Keep operator rules and skill metadata structured for automated reuse (progressive disclosure + rule compilation).
- Where encoded: `learn/RULES.md`, `.codex/skills/sysop-kernel/SKILL.md`

## 2026-01-05T00:12:14-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 6
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: (missing powercfg_active_scheme.output)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-05T00:44:31-06:00 [AUTO-FIX]

- Fix: Retry Windows snapshot
- Risk: 1 (SAFE)
- Approval: auto (flag)
- Changes: windows_snapshot: powershell_failed -> powershell_failed
- Backup: /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json.bak-20260105-004431 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.txt.bak-20260105-004431 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.invoke.log.bak-20260105-004431
- Rollback: `for f in /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json.bak-20260105-004431 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.txt.bak-20260105-004431 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.invoke.log.bak-20260105-004431; do orig="${f%.bak-*}"; cp -a "/home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.invoke.log" "$orig"; done`
- Status: pending-restart
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json

## 2026-01-05T00:44:31-06:00 [AUTO-FIX]

- Fix: Generate Windows power plan script
- Risk: 2 (GENERATE)
- Approval: no (generated only)
- Changes: (none) -> /home/xhott/SYSopGPTWSL/sysop/out/fixes/windows_power_plan_ultimate.ps1
- Backup: (none)
- Rollback: `del -Force "/home/xhott/SYSopGPTWSL/sysop/out/fixes/windows_power_plan_ultimate.ps1"  # from PowerShell, or rm -f "/home/xhott/SYSopGPTWSL/sysop/out/fixes/windows_power_plan_ultimate.ps1" from WSL`
- Status: applied
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/fixes/windows_power_plan_ultimate.ps1

## 2026-01-05T00:44:31-06:00 [AUTO-FIX]

- Fix: Generate .wslconfig editor script (manual run)
- Risk: 3 (MODIFY)
- Approval: no (generated only)
- Changes: (none) -> /home/xhott/SYSopGPTWSL/sysop/out/fixes/edit_wslconfig.ps1
- Backup: (none)
- Rollback: `rm -f "/home/xhott/SYSopGPTWSL/sysop/out/fixes/edit_wslconfig.ps1"`
- Status: applied
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/fixes/edit_wslconfig.ps1

## 2026-01-05T00:44:31-06:00 [AUTO-FIX]

- Fix: Generate manual recovery steps
- Risk: 4 (MANUAL)
- Approval: no (generated only)
- Changes: (none) -> /home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md
- Backup: (none)
- Rollback: `rm -f "/home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md"`
- Status: applied
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md

## 2026-01-05T00:44:31-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 6
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: (missing powercfg_active_scheme.output)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-05T00:45:14-06:00 [AUTO-FIX]

- Fix: Retry Windows snapshot
- Risk: 1 (SAFE)
- Approval: auto (flag)
- Changes: windows_snapshot: powershell_failed -> powershell_failed
- Backup: /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json.bak-20260105-004514 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.txt.bak-20260105-004514 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.invoke.log.bak-20260105-004514
- Rollback: `for f in /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json.bak-20260105-004514 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.txt.bak-20260105-004514 /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.invoke.log.bak-20260105-004514; do orig="${f%.bak-*}"; cp -a "$f" "$orig"; done`
- Status: pending-restart
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/windows_snapshot.json

## 2026-01-05T09:54:33-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 6
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: (missing powercfg_active_scheme.output)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-05T10:32:02-06:00

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

## 2026-01-05T16:48:54-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 8
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: (missing powercfg_active_scheme.output)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`

## 2026-01-06T16:45:23-06:00

- Symptom: Need a deduped, provenance-preserving “Claude wiring” seed repo + NotebookLM project wiring surfaced for export.
- Cause hypothesis: Prior seed included `~/ops-operator/.venv` (3rd-party libs) and missed NotebookLM/MediaPipeline docs.
- Fix applied: Regenerated `sysop/out/fixes/SYSopClaudeWSL_seed/` excluding `.venv`/`site-packages`, adding:
  - `C:\Users\xhott\AppData\Roaming\Claude\claude_desktop_config.json`
  - `C:\Users\xhott\Documents\NotebookLM_HD_Project\`
  - `C:\Users\xhott\Documents\MediaPipeline\`
  - `C:\Users\xhott\.claude\tmp\`
- Evidence:
  - Seed stats: 319 objects, 456 manifest rows (`sysop/out/fixes/SYSopClaudeWSL_seed/meta/BUILD_INFO.md`)
  - Interop failure observed when attempting `powershell.exe`/`cmd.exe` from WSL: `UtilBindVsockAnyPort ... socket failed 1`
  - NotebookLM project map: `sysop/out/fixes/SYSopClaudeWSL_seed/canon/NOTEBOOKLM_HUMAN_DESIGN_PROJECT_MAP.md`

## 2026-01-06T16:55:57-06:00 [AUTO-FIX]

- Fix: Generate manual recovery steps
- Risk: 4 (MANUAL)
- Approval: no (generated only)
- Changes: (none) -> /home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md
- Backup: (none)
- Rollback: `rm -f "/home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md"`
- Status: applied
- Evidence: /home/xhott/SYSopGPTWSL/sysop/out/fixes/manual_steps.md

## 2026-01-06T17:37:47-06:00

- Symptom: Routine sysop run (baseline)
- Cause hypothesis: N/A (baseline)
- Fix applied: none (report-only run)
- Evidence:
  - `nproc`: 8
  - `mount | grep ' /mnt/c '`: C:\ on /mnt/c type 9p (rw,noatime,aname=drvfs;path=C:\;uid=1000;gid=1000;symlinkroot=/mnt/,cache=5,access=client,msize=65536,trans=fd,rfd=6,wfd=6)
  - Windows power: Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
- Regression risk: Low; outputs are under `sysop/out/`.
- Rule extracted: Always run Windows snapshot from `/mnt/c` and parse snapshot JSON with `utf-8-sig`.
- Where encoded: `sysop/run.sh`, `sysop/perf/summarize.sh`, `sysop/windows/collect-windows.ps1`
