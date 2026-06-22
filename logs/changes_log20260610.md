# Changes Log - June 10, 2026

## Summary
Documentation update: revised the repository `README.md` to cover the new clustering methods
and the manual-curation keyboard shortcuts. No code behavior changed. (For the underlying
features and parameters, see `logs/changes_log20260602.md` and
`matlab/CLUSTERING_METHODS.md`.)

## Changes

### README.md
- **Added "Clustering methods" section.** Documents the `vcCluster` parameter and lists all
  options in a table: the native density-peak methods (`drift-knn` default, `spacetime`,
  `drift`, `xcov`) and the per-site label-based methods (`kmeans`, `hdbscan`, `isosplit6`,
  `classix`), with dependency notes (e.g. kmeans needs the Statistics & ML Toolbox; isosplit6
  tries the Python backend and falls back to pure-MATLAB isosplit5). Explains how to switch
  method (set `vcCluster` in the `.prm`, then `irc sort`) and links to
  `matlab/CLUSTERING_METHODS.md` and `matlab/default.prm` for the full parameter reference.
- **Added "Manual curation" section.** Describes the deferred-edit workflow (queue merges with
  `m` / deletes with `d`, apply all with `u`, cancel with `Esc`) and a complete keyboard-shortcut
  table for the cluster waveform view, transcribed directly from `keyPressFcn_FigWav_` in
  `irc.m` so it matches the actual GUI: cluster navigation (`←`/`→`, `Shift`+arrows, `Home`/`End`),
  amplitude scaling (`↑`/`↓`), merge/delete/split (`m`/`d`/`s`), apply/cancel (`u`/`Esc`),
  reorder (`o`), annotations (`1`–`4` = single/multi/noise/axonal), and the plot views
  (`c` correlogram, `i` ISI histogram, `v` ISI return map, `t` time view, `e` probe map,
  `j` drift view, `p` PSTH, `w`/`n`/`a`/`f`/`h`).

## Notes
- The README is otherwise written around the `irc2` commands, but the new clustering methods and
  the manual-curation GUI are implemented in the `irc` (v1) pipeline (`fet2clu_` /
  `keyPressFcn_FigWav_` in `irc.m`). The two new sections therefore use `irc` commands
  (`irc sort`, `irc manual`) for accuracy; the rest of the `irc2`-based tutorial is unchanged.
- The label-based methods are wired into `irc`'s clustering path, not `irc2`'s separate pipeline.

## Files
- Modified: `README.md`
- Added: `logs/changes_log20260610.md`
