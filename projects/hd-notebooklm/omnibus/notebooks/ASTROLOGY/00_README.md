# Notebook: ASTROLOGY

Goal: extract the astro-to-HD bridge: how planetary positions become HD activations (gates/lines).

## Extraction prompts (copy/paste)

1) Derive the full pipeline from birth info to activations:
   - time zone/DST handling
   - UT conversion
   - ephemeris lookup/interpolation
   - zodiac degree → gate/line mapping
2) Extract “Design date” calculation (if described):
   - what is the offset rule (e.g., ~88° solar arc / ~88 days)?
   - how to compute it deterministically
3) Enumerate required reference data files (ephemeris ranges; mapping tables) with suggested open formats (CSV/JSON).
4) Propose verification strategy:
   - compare to known commercial software outputs
   - tolerance/rounding rules

