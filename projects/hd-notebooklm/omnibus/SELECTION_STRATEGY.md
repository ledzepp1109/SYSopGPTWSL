# File selection strategy (Omnibus_v1)

Objective: reduce thousands of items into **10–15 sources per NotebookLM notebook** while keeping provenance.

## Include (default)

- PDFs with high “rule density” (manuals, reference tables, spec-like docs).
- DOC/DOCX only when no PDF exists (convert to PDF during build).
- A small curated set of videos only when they clearly encode derivation rules not present in text (keep packs small).

## Exclude (default)

- Images (charts/diagrams) unless essential to explain a derivation rule.
- Audio-only lectures (very high word count if transcribed; not needed for v1).
- Duplicate formats:
  - Prefer PDF over DOC/DOCX.
  - Prefer the newest/cleanest scan when the same PDF exists in multiple places.

## Notebooks (v1 recommended)

Because NotebookLM has **no cross-notebook search**, each notebook should include a “Primer” mega-source with common terms.

1) `CORE_TEACHINGS` — axioms, definitions, foundational mechanics
2) `TYPES_STRATEGY_AUTHORITY` — type/strategy/authority/profile derivations
3) `CENTERS_MECHANICS` — centers/channels/gates/definition algorithms
4) `INCARNATION_CROSSES` — cross derivation + naming spec + mapping tables
5) `PHS_NUTRITION` — determination/environment outputs + mapping tables
6) `BG5` — BG5 overlays, naming, mapping differences
7) `ASTROLOGY` — ephemeris + degree→gate/line mapping + design-date rule
8) `ADVANCED` — variables, dream rave, tones/bases, any additional systems

## How to use `hd_omnibus_selection.csv`

- One row per original file.
- You control grouping by setting:
  - `notebook` (target NotebookLM notebook)
  - `volume_id` and `volume_title` (which mega-source it joins)
  - `volume_kind` (`pdf_merge`, `video_single`, `video_concat`)
  - `action` (`include`/`exclude`)

Rule of thumb:
- Each `volume_id` should contain **10–30 PDFs** and output a single merged PDF under 200MB.

