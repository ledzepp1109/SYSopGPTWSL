# HD NotebookLM — Omnibus Builder (Windows)

Builds NotebookLM-ready “mega-sources” (PDF + optional video packs) from an **ARCHIVE** folder into a separate **EXPERIMENT** folder.

## Paths (as provided)

- ARCHIVE (read-only source): `G:\My Drive\Human Design Repo NotebookLM`
- EXPERIMENT (outputs): `G:\My Drive\Human Design Experiments\Omnibus_v1`

## NotebookLM Plus constraints (baked into scripts)

- Per source: **<200MB** OR **<500k words**
- Per notebook: **300 sources**
- No ZIPs
- No cross-notebook search

## What to run (recommended flow)

1) (Optional) Freeze snapshot of ARCHIVE for drift detection:

```powershell
powershell -ExecutionPolicy Bypass -File .\Freeze-HDArchive.ps1 `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1"
```

2) Generate an initial selection CSV from your `*_files.txt` manifests:

```powershell
powershell -ExecutionPolicy Bypass -File .\New-HDOmnibusSelection.ps1 `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1" `
  -ManifestGlob "G:\My Drive\Human Design Repo NotebookLM\\**\\*_files.txt"
```

3) Manually edit `hd_omnibus_selection.csv` (choose include/exclude + volumes).

4) Build omnibus outputs:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-HDOmnibus.ps1 `
  -ArchiveRoot "G:\My Drive\Human Design Repo NotebookLM" `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1" `
  -SelectionCsv "G:\My Drive\Human Design Experiments\Omnibus_v1\\_plans\\hd_omnibus_selection.csv"
```

5) Generate the master index:

```powershell
powershell -ExecutionPolicy Bypass -File .\Write-HD_OMNIBUS_v1.ps1 `
  -ExperimentRoot "G:\My Drive\Human Design Experiments\Omnibus_v1" `
  -SelectionCsv "G:\My Drive\Human Design Experiments\Omnibus_v1\\_plans\\hd_omnibus_selection.csv"
```

## Tool prerequisites (Windows PATH)

- `ffmpeg` + `ffprobe`
- `pdfsam-console` (PDFsam Console)
- Microsoft Word (for DOC/DOCX→PDF and divider/TOC pages); optional fallback to LibreOffice if installed

If a tool is missing, the scripts stop with a clear message.

## Output layout (under EXPERIMENT)

- `_plans\hd_omnibus_selection.csv` (your curated plan)
- `_build\pdf\...` merged PDFs (NotebookLM sources)
- `_build\video\...` processed videos/packs (NotebookLM sources)
- `_logs\...` build logs + per-volume manifests
- `HD_OMNIBUS_v1.md` master index for upload + extraction work

