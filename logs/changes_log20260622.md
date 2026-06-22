# Changes Log - June 22, 2026

## Summary
Two changes on the `rewind` branch: (1) a repository cleanup removing dead duplicate
copies of `irc.m` and a bundled archive, and (2) bug fixes in `irc.m` so that the per-site
label-based clustering methods (`kmeans`/`hdbscan`/`isosplit`/`classix`) keep their cluster
labels through the post-merge stage. No existing behavior was removed; the label-clustering
fixes only affect the label-based `vcCluster` paths.

## Changes

### Repository cleanup (commit `b5cd593`)
- **Removed 7 full snapshot copies of `irc.m`** that were checked in alongside the live file:
  `irc - Copy.m`, `irc - Copy (2).m`, `irc_20251119.m`, `irc_20251127.m`, `irc_20251201.m`,
  `irc_CPU_optimized.m`, `irc_optimized_gui.m`. Together ~229k lines. Git history retains every
  snapshot; nothing in the codebase referenced them by name.
- **Removed `nla-group-classix-matlab-1.3.0.0.zip`** (~24 MB), already unpacked into
  `matlab/classix/`.

### Label-based clustering fixes (commit `638096e`)
- **`post_merge_` (irc.m ~3585):** detect label-based clustering via `S_clu.fLabelClu` (set by
  the clusterer) or the active `vcCluster` (robust when a saved `_jrc.mat` predates the flag),
  and **skip `postCluster_`** for these methods. Previously the density-peak (DPC) re-assignment
  ran with an empty `S_clu.icl` and collapsed every label-based result into a single cluster.
- **Persist `fLabelClu` on `S_clu`** across `struct_copy_` so the saved `_jrc.mat` keeps the
  bypass on reload.
- **Cross-site merge for label methods (irc.m ~3645):** per-site label clustering splits one
  neuron across adjacent sites, and `templateMatch_post_` only compares clusters sharing an
  exact peak site, so duplicates never merged. Run the position-based `post_merge_wav4_`
  (radius `maxDist_site_um`, ~55um) for label methods when `0 < maxWavCor < 1` so cross-site
  duplicates collapse.
- **Correlogram guard (irc.m ~32081):** return an empty/NaN matrix when `nClu < 2`. With a
  single cluster, `squareform(pdist(...))` is `0x0` and the downstream `mrDist_clu(:,iClu1)`
  indexing threw "Index in position 2 exceeds array bounds."

### Documentation (commit `638096e`, README) — see `logs/changes_log20260610.md`
- Added the "Clustering methods" and "Manual curation" sections to `README.md` (the
  `vcCluster` method table and the cluster-waveform keyboard shortcuts).

## Files
- Removed: `irc - Copy.m`, `irc - Copy (2).m`, `irc_20251119.m`, `irc_20251127.m`,
  `irc_20251201.m`, `irc_CPU_optimized.m`, `irc_optimized_gui.m`,
  `nla-group-classix-matlab-1.3.0.0.zip`
- Modified: `matlab/irc.m`, `README.md`
- Added: `logs/changes_log20260622.md`
