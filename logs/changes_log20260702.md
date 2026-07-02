# Changes Log - July 2, 2026

## Summary
Two threads: (1) a new **probe-map site-label / region** feature in the manual-curation GUI,
and (2) a documentation pass so the README reflects the full divergence from upstream
`flatironinstitute/ironclust`.

## Probe map: site labels & region colouring (`matlab/irc.m`)
In the manual-curation **probe map** window (opened with `e`), the per-site identifier text is
now switchable and can be driven from an anatomical region map.

- **`c` cycles the site labels**: `channel #` → `site #` → `region`. The active mode is shown
  in the window title. Implemented as `keyPressFcn_FigMap_` (the probe map previously had no
  key handler) plus `cycle_FigMap_label_` and `site_label_modes_`.
- **Region source** — a new `.prm` parameter `vcFile_site_region` names a CSV of `key,region`
  rows. `key` is matched first as a **channel number** (against `viSite2Chan`), then as a
  **1-based site index**; a non-numeric header row and blank lines are tolerated; whitespace is
  trimmed; sites the CSV does not cover are labelled `?` (`load_site_region_`). The `region`
  mode is only offered when the CSV is set and parseable, so behaviour is unchanged when it is
  not.
- **Region colour-coding** — in `region` mode the site boxes are coloured categorically (one
  colour per region, `apply_FigMap_color_` + `region_colormap_`, `lines`/`hsv` palette) instead
  of by the selected cluster's Vpp. Switching back to `channel #` / `site #` restores the Vpp
  (jet) colouring.
- The identifier text is offset by +20 µm in x so it clears the site box.
- `default.prm` gains `vcFile_site_region = '';` in the `#Display parameters` block.

Verification: `checkcode('matlab/irc.m')` clean on the edited region (R2023b); headless tests
of the CSV parse/map and the region-colour path all pass.

## Documentation (`README.md`)
- Added a top-of-file **fork notice** and a new **"What's different from upstream IronClust"**
  section: new clustering methods (per-site kmeans/HDBSCAN/isosplit6, CLASSIX), performance
  (parallel per-site clustering, `maxSpk_persite_clust`, I/O tuning), robustness/bug fixes, GUI
  changes, a table of **changed default parameters** (upstream → fork), and the list of **new
  parameters**.
- Documented the probe-map controls under **Manual curation → Probe map window** and annotated
  the `e` shortcut row.

## Files
- Modified: `matlab/irc.m`, `matlab/default.prm`, `README.md`.
- Added: `logs/changes_log20260702.md`.
