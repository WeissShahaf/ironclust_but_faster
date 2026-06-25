# Changes Log - June 25, 2026

## Summary
Follow-up to the per-site clustering parallelization (see
`logs/changes_log20260624.md`, committed as `perf: parallelize per-site label
clustering`). Adds a profiling utility and documentation so the next optimization
(GPU kNN vs. scheduling) can be chosen from measured data instead of guesses. No
change to sorting behavior.

## Background (from the 384-site `isosplit` run)
The parallel per-site loop is ~98% utilized through the bulk but develops a heavy
**tail**: per-site time rose from ~78 s/site mid-run to ~600 s/site for the final
batch, and worker CPU-time spread ~3x. A handful of very high-spike-count sites,
processed late, strand individual workers (each site is one indivisible `parfor`
task; the per-site kNN is O(n^2)). The open question is whether that tail is
**kNN-bound** (→ a GPU `pdist2` would help) or **clustering-bound** (→ GPU won't help
the sequential isosplit/hdbscan cores; biggest-site-first scheduling / spike capping
would). That is decided by the t_clu vs t_knn split, which this tooling measures.

## Changes

### New: `matlab/measure_persite_timing.m`
Profiling helper. Loads a recording's cached features (`loadParam_` + `load_cached_`,
reusing irc's own loaders), keeps only the N biggest detection sites (blanks the rest
so the driver skips them), and runs just the per-site clustering for those sites via
`irc('call', 'cluster_isosplit_'|'cluster_hdbscan_'|'cluster_kmeans_', ...)`. It
prints the summed clustering-vs-kNN CPU-time split and the slowest sites, reproducing
the expensive tail in minutes rather than the hours a full re-sort costs.
- Does **not** run post-merge and does **not** modify any saved results.
- `measure_persite_timing(prm)` profiles the top 16 sites with the `.prm` settings;
  `measure_persite_timing(prm, nTopSites, nWorkers)` overrides the count / worker cap.
- Dispatches to the clusterer named by `vcCluster`; defaults to isosplit otherwise.

### `matlab/irc.m` (documentation only)
- Expanded the section banner above the label-based clustering helpers to document the
  shared driver, the `parfor` parallelism + `nWorkers_clust` cap, the post-loop label
  offset (equivalent to the old serial offset), the `progress_persite_` progress/ETA
  reporter, the `t_clu`/`t_knn` timing instrumentation, the `measure_persite_timing.m`
  profiler, and the known giant-site tail limitation. No code behavior changed.

## How to use
After a sort's detect/feature stage is cached:
```matlab
measure_persite_timing('E:\...\..._IRC_all_sites.prm');        % top 16 biggest sites
measure_persite_timing('E:\...\..._IRC_all_sites.prm', 24, 8); % 24 sites, 8 workers
```
Read the printed line `Per-site work ... clustering X% + kNN Y%`:
- kNN a large share on the big sites → build the `gpuArray pdist2` path for `persite_knn_`.
- clustering the large share → add biggest-site-first (LPT) scheduling; consider
  capping per-site spikes for the kNN.

## Status / deferred
- The parallelization, `nWorkers_clust = 12`, and timing instrumentation are committed
  on `rewind` (and pushed to `origin/rewind`).
- LPT scheduling and the GPU kNN path remain **deferred pending this measurement**, per
  the agreed "measure first" plan.

## Files
- Added: `matlab/measure_persite_timing.m`, `logs/changes_log20260625.md`.
- Modified: `matlab/irc.m` (documentation comment only).
