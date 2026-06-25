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

---

## Update — measurement result + per-site spike cap (implemented)

### Measurement (the "measure first" gate)
Profiled four graded sites SERIAL (40k / 100k / 200k / 353k spikes) with the new
`t_clu`/`t_knn` instrumentation. Result — **the kNN graph dominates, and its share
grows with site size, the clean O(n^2) signature**:

| site | spikes | clustering (isosplit) | kNN graph | kNN share |
|---|---|---|---|---|
| 357 | 40,021 | 2.9 s | 1.9 s | 40% |
| 351 | 99,980 | 7.8 s | 30.0 s | 79% |
| 150 | 201,057 | 18.9 s | 147.6 s | 89% |
| 71 | 352,819 | 39.1 s | **468.5 s** | **92%** |

Summed: clustering 69 s (10%) + kNN 648 s (90%). The 201k→353k step matches O(n^2)
within 3% (predicted 454 s, measured 468 s). Extrapolating to the real monster
**site 59 (1,124,504 spikes)**: kNN ≈ 468.5 s × (1.12M/353k)² ≈ **~4,800 s (~80 min)
for one site's kNN alone** — that is the stall observed during the full sort.

Conclusion: a per-site spike **cap** is the right fix — it bounds *both* the O(n^2)
kNN (the 90% cost) *and* the clustering. A kd-tree kNN would only help the kNN and
degrades at these "tens-of-dims" features (curse of dimensionality); the cap is
dimension-agnostic.

### New: `maxSpk_persite_clust` (per-site spike cap)
`matlab/default.prm` adds `maxSpk_persite_clust = []` (off by default → behaviour
byte-identical to before). When set, any site with more than `maxSpk` spikes:
1. clusters a **deterministic random subsample** of `maxSpk` spikes (seeded by the
   site's first global spike id → identical under serial and `parfor`);
2. builds the kNN graph on that subset only — **O(maxSpk²)** instead of O(n1²);
3. assigns **all** n1 spikes to their nearest subset member (1-NN), copying that
   member's label, global-index kNN row, and density.

Every spike still receives a label + a valid global kNN row + a density, so
`S_clu_from_labels_` and `post_merge_` are unaffected; only the giant (usually noise)
sites are approximated. The only residual cost that still scales with the full site
size is the 1-NN assignment pass (step 3), O(n1·maxSpk) chunked BLAS.

### Measured (cap ON, `maxSpk = 50000`, serial, the two real monster sites)
| capped site | spikes | clustering | subset kNN + assignment | total |
|---|---|---|---|---|
| 59  | 1,124,504 | 4.8 s | 85.9 s | **~91 s** |
| 328 | 1,000,272 | 4.3 s | 68.0 s | ~72 s |

Site 59 drops from ~80 min (uncapped, extrapolated) to **~90 s (~50×)** — not literally
"to seconds": isosplit on the 50k subset is ~5 s and the subset kNN is trivial, but the
1-NN assignment over all 1.12M spikes is the bulk of that ~86 s. It is bounded and
predictable, and it collapses the load-imbalance tail (worst site ~90 s instead of
~80 min), which was the actual problem.

### `matlab/irc.m`
- `cluster_site_`: added the capped branch (gated on `~isempty(maxSpk) && n1 > maxSpk`),
  which delegates to the new `cluster_site_capped_`. The uncapped path is untouched.
- New subfunction `cluster_site_capped_` (subsample → cluster subset → subset kNN →
  nearest-member propagation; `parfor`-safe; same `t_clu`/`t_knn` timing semantics).
- New subfunction `nearest_in_set_` (chunked `pdist2(...,'Smallest',1)`, mirrors
  `knn_cpu_`; pure of shared state).
- Extended the label-based clustering section banner to document the cap.

### Verification
- `checkcode` on `irc.m`: no parse errors.
- Cap **off** (default `[]`): the new branch is skipped entirely → byte-identical to
  the previously-verified serial==parallel result.
- Cap **on**, real giant sites: `zz_test_cap.m` keeps only the two biggest sites
  (1,124,504 and 1,000,272 spikes), enables `maxSpk = 50000`, and confirmed **PASS** —
  both finish in ~70-90 s (vs ~80 min uncapped), **100% of spikes labeled** on each,
  all `miKnn` indices valid global ids (in [1, 26,380,667]), and two capped runs give
  **byte-identical `viClu`** (determinism from the seeded subsample).

### Status
- Cap implemented on `irc.m` + `default.prm`; the recording's `.prm`
  (`..._IRC_all_sites.prm`, outside the repo) sets `maxSpk_persite_clust = 50000`.
- This supersedes the deferred LPT-scheduling / GPU-kNN options above: the cap removes
  the tail at its source rather than rescheduling or accelerating an O(n^2) cost.
