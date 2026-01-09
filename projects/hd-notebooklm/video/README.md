# HD NotebookLM — Video Resume Toolkit (Windows)

This folder contains **Windows PowerShell scripts** to resume and harden video processing for NotebookLM sources.

## What it does

- Scans or reads a fixed video list (recommended) and processes videos **from a checkpoint**.
- Writes outputs to a separate **EXPERIMENT** folder (does not modify ARCHIVE).
- Enforces NotebookLM per-source limit: **<200MB per output file** (compress; optionally split if needed).
- Writes a manifest CSV + checkpoint JSON for reliable resume/retry.

## Quick start (recommended)

1) Choose paths:

- ARCHIVE (read-only): `G:\My Drive\Human Design Repo NotebookLM`
- EXPERIMENT (outputs): `G:\My Drive\Human Design Experiments\Omnibus_v1\_video`

2) Run (resume after 251):

```powershell
powershell -ExecutionPolicy Bypass -File .\Resume-HDVideos.ps1 `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_video" `
  -StartAfter 251 `
  -Resume
```

Preflight only (verify tools on PATH):

```powershell
powershell -ExecutionPolicy Bypass -File .\Resume-HDVideos.ps1 -SelfTest `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_video"
```

3) If you have a deterministic list in the exact intended order (best):

```powershell
powershell -ExecutionPolicy Bypass -File .\Resume-HDVideos.ps1 `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1\_video" `
  -VideoListPath "G:\My Drive\Human Design Repo NotebookLM\_manifests\videos_files.txt" `
  -StartAfter 251 `
  -Resume
```

## Outputs

Under `ExperimentRoot\_logs\`:
- `video_inventory.csv` (the ordered queue)
- `video_processing_manifest.csv` (append-only results)
- `checkpoint.json` (resume pointer + summary)

## Tool prerequisites

From PowerShell:
- `ffmpeg -version`
- `ffprobe -version`

If these aren’t found, install ffmpeg and ensure it’s on `PATH`.
