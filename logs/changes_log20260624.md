# Changes Log - June 24, 2026

## Summary
Parallelized and instrumented the per-site, label-based clustering loop
(`vcCluster = 'kmeans' | 'hdbscan' | 'isosplit6'`) in `irc.m`. The driver that all
three methods share, `cluster_labels_persite_`, previously processed the detection
sites in a single serial `for` loop with only bare-dot progress — for a 384-site
Neuropixels recording this ran for "dozens of hours" with essentially no feedback.
It now runs the sites in parallel across a capped worker pool and reports running
progress with an ETA. Verified on real data: 8 workers at ~98% utilization, i.e.
~8x throughput on the clustering stage, with bit-for-bit identical results to the
serial path.

## Changes

### `matlab/irc.m` — `cluster_labels_persite_` (per-site clustering driver)
- **Removed the loop-carried dependency** that blocked parallelization. The old loop
  accumulated a global label `offset` across sites (`offset = offset + max(label)`),
  which is sequential. Each site is now clustered independently into local labels
  (1..k per site) and the global offsets are applied **after** the loop via a
  cumulative sum of per-site cluster counts (`cumsum`). This reproduces the old
  global labels exactly (verified: serial vs. parallel `viClu`/`miKnn`/`vrRho` are
  `isequal`).
- **Parallel execution** via `parfor (iSite = 1:nSites, nWorkers)`. Per-site features
  are pre-sliced into a cell array (kept `single` to limit memory; cast to `double`
  inside the worker) so the loop body carries no shared/global state. Falls back
  automatically to a serial loop (with the same progress reporting) if the Parallel
  Computing Toolbox / pool is unavailable, or if the `parfor` throws.
- **Worker cap** (`nWorkers_clust`, default 12, clamped to `feature('numcores')`). Each
  worker holds one site's feature matrix + its kNN distance matrix (~8 GB/worker on this
  recording), so size it to available RAM; lower to 4-8 if memory-bound. The pool is
  sized to the cap (an oversized existing pool is shrunk).
- **Per-site timing breakdown.** `cluster_site_` now returns the CPU-time spent on the
  clustering algorithm (`t_clu`) vs. the kNN graph (`t_knn`); the driver prints the summed
  split over all sites plus the top-5 slowest sites (with spike counts). This is the
  measurement that decides whether GPU/other optimization is worth it (e.g. GPU the kNN
  only if it dominates).
- **Progress + ETA.** New reporter `progress_persite_` prints
  `k/N sites done (Xs elapsed, ~Ys remaining)` (refreshing ~50 times over the run),
  driven by a `parallel.pool.DataQueue` `afterEach` callback in the parallel path and
  a direct per-iteration tick in the serial path.
- New helper subfunctions: `cluster_site_` (clusters one site + builds its
  global-index kNN graph; pure of shared state so it is `parfor`-safe) and
  `progress_persite_`. The existing `persite_knn_` and `S_clu_from_labels_` are
  unchanged; the three callers (`cluster_kmeans_`, `cluster_hdbscan_`,
  `cluster_isosplit_`) are unchanged — they still call `cluster_labels_persite_`
  with the same signature.

### Parameters
- Added `nWorkers_clust` (default `12`) to `matlab/default.prm` (in the
  `#Alternative clustering methods` block) and to the active recording `.prm`.
  Set `fParfor = 0` to force the serial path; lower `nWorkers_clust` (4-8) if RAM-bound.

## Notes / scope
- This covers the three per-site label methods, which all funnel through one driver.
  The native density-peak methods (`drift-knn`, `spacetime`, `drift`, `xcov`) are a
  separate, already-GPU-accelerated path and were intentionally left untouched.
- Load balance (observed on the 384-site `isosplit` run, 8 workers): the loop is ~98%
  utilized through the bulk but develops a heavy tail — per-site time rose from ~78 s/site
  mid-run to ~601 s/site for the final batch, and worker CPU-time spread ~3x (10k-30k s).
  A few very high-spike-count sites, processed late, strand individual workers while the
  rest idle (each site is one indivisible parfor task; the per-site kNN is O(n^2)).
  Candidate fixes, DEFERRED pending the timing breakdown above:
    * biggest-site-first (LPT) scheduling so the giants start early and overlap the small
      sites (cheap; makes cluster label IDs schedule-dependent, partition unchanged);
    * a `gpuArray pdist2` path for the per-site kNN (20 GB VRAM is ample since the kNN is
      chunked) — worth it only if `t_knn` dominates on the big sites;
    * capping/subsampling per-site spikes for the kNN.
  Decision is to MEASURE first (the new t_clu/t_knn split), then optimize.

## Verification (MATLAB R2023b Update 5)
- `checkcode('irc.m')`: 0 syntax/parse errors; the new `parfor` produces no
  classification warnings (all variables correctly sliced/broadcast).
- Synthetic equality test (deterministic per-site clusterer): serial and
  `nWorkers_clust=8` parallel runs give `isequal` `viClu`, `miKnn`, and `vrRho`
  (nClu=48, all 906 spikes assigned, `miKnn` 10x906 with valid global indices).
- Real recording (`260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites.prm`,
  `vcCluster='isosplit'`, 384 sites): pool connects with 8 workers, log prints
  `Per-site clustering over 384 sites (parallel: 8 workers)`, and all 8 workers run
  at ~98% CPU utilization (+~315 worker-CPU-seconds per 40s wall-clock window).

## Files
- Modified: `matlab/irc.m`, `matlab/default.prm`, the active recording `.prm`.
- Added: `logs/changes_log20260624.md`.
