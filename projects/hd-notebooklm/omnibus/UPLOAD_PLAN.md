# NotebookLM upload plan (Omnibus_v1)

## Goal

- Each NotebookLM notebook gets **10–15 sources** (mega-PDFs and a small number of video sources).
- Every source stays under **200MB** (hard constraint).
- Provenance is preserved inside each mega-PDF (divider pages + source paths + SHA256).

## Step-by-step

1) Build outputs
- Run `Freeze-HDArchive.ps1` (optional, but recommended).
- Run `New-HDOmnibusSelection.ps1` to create `_plans\hd_omnibus_selection.csv`.
- Manually curate `hd_omnibus_selection.csv` to create:
  - ~8 notebooks total
  - ~10–15 `volume_id`s per notebook
  - ~10–30 PDFs per `volume_id`
- Run `Build-HDOmnibus.ps1`.
- Run `Write-HD_OMNIBUS_v1.ps1`.

2) Create NotebookLM notebooks (one per `notebook` name)
- Create notebooks with the same names used in `hd_omnibus_selection.csv`.

3) Upload order (per notebook)
1. Upload the notebook’s `Primer` mega-source (definitions + terms) if you create one.
2. Upload the most “rule-dense” mega-PDFs first (manuals/spec-like content).
3. Upload any video sources last (to avoid transcript word-limit surprises).

4) Sanity checks (per notebook)
- Confirm all sources uploaded successfully.
- Ask NotebookLM to:
  - summarize the notebook
  - list “tables/mappings implied by the content”
  - generate test vectors for a software implementation

## Handling the 500k-word limit

- PDFs often stay under the word limit even when large; video transcripts can blow it up quickly.
- Keep video packs small (or avoid them entirely in v1) unless the content is uniquely valuable.

