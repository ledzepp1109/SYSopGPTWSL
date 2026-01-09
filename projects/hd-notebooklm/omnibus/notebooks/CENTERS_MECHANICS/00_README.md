# Notebook: CENTERS_MECHANICS

Goal: extract rules for **centers, channels, gates, lines** and how those turn into “defined/undefined” states.

## Extraction prompts (copy/paste)

1) Write a canonical data model:
   - centers
   - channels (two gates)
   - gates (one center endpoint)
   - which combinations imply definition
2) Extract rules for “definition types” (single, split, etc.) if present; express as an algorithm.
3) Identify any tables needed (e.g., gate → hexagram → line mapping) and enumerate them.
4) Produce implementation notes for a renderer:
   - what must be shown on a bodygraph
   - how color/lines/activation marks are encoded
5) Generate unit tests for channel/center activation logic (purely mechanical).

