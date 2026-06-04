# Changes Log - June 2, 2026

## Summary
Added three new primary clustering methods to `irc.m` — **kmeans**, **HDBSCAN**, and
**isosplit6** — as per-site, label-based methods that bypass density-peak clustering (DPC)
and are merged across sites by the existing waveform-based post-merge. Fixed the previously
broken **CLASSIX** primary clustering, restored the missing **jisotonic5** MEX dependency
(so `isocut5`/`isosplit5` work), and fixed a **pre-existing manual-merge crash** in the
curation GUI. Exposed full tuning parameters for all new methods in `default.prm`.

---

## New Features

### 1. Label-based clustering methods (kmeans / HDBSCAN / isosplit6)

Selectable via `vcCluster`:
```matlab
vcCluster = 'kmeans';     % or 'hdbscan' or 'isosplit6' ('isosplit'/'isosplit5' alias to v5)
```

**Architecture (the key difference from DPC):**
- DPC methods produce `rho`/`delta`; `postCluster_` then assigns clusters by peak finding.
- Label-based methods produce final labels directly and set `S_clu.fLabelClu = 1`, which makes
  `fet2clu_` **skip `postCluster_`** so the labels are not overwritten (this was the original
  CLASSIX bug). See `irc.m` `fet2clu_`.
- Clustering is **per detection site** (features in `trFet_spk` are local to each spike's site),
  via `cluster_labels_persite_`. Each site is over-segmented, labels are offset into a global id
  space, and the normal `post_merge_` stage merges duplicate units across sites.
- The per-site driver also builds a real per-site kNN graph (`miKnn`) and density (`rho`) with
  global indices (using the native `knn_cpu_`), which the waveform-based post-merge requires.
- `S_clu_from_labels_` packages labels + `miKnn`/`rho` into a valid `S_clu`.

**Files:**
- Modified: `matlab/irc.m` — `fet2clu_` dispatch + `fLabelClu` bypass; new subfunctions
  `cluster_kmeans_`, `cluster_hdbscan_`, `cluster_isosplit_`, `cluster_labels_persite_`,
  `persite_knn_`, `S_clu_from_labels_`, `kmeans_labels_`, `isosplit_labels_`.
- Created: `matlab/hdbscan_fit.m` — pure-MATLAB HDBSCAN\* (core distances → mutual-reachability
  MST → condensed tree → Excess-of-Mass stability). Uses `knnsearch` if available, else a
  chunked brute-force kNN.
- Created: `matlab/isosplit5.m` — pure-MATLAB ISO-SPLIT v5 (reuses `isocut5.m`/`jisotonic5.m`).
- Created: `matlab/isosplit6.m` — runs the official ISO-SPLIT v6 via MATLAB's Python bridge,
  and on any failure the dispatcher falls back to `isosplit5` (the "try v6, else v5" behavior).
- Created: `matlab/CLUSTERING_METHODS.md` — usage and parameter reference.

**Dependencies:**
- kmeans and HDBSCAN's `knnsearch` use the Statistics and Machine Learning Toolbox (HDBSCAN has
  a brute-force fallback if absent).
- True isosplit6 needs a configured MATLAB Python (R2023b: CPython 3.9–3.11) and
  `pip install isosplit6 numpy`; otherwise `isosplit5` is used automatically.

---

## Bug Fixes

### 1. CLASSIX primary clustering was broken (labels clobbered)
`fet2clu_` always called `postCluster_`, which deletes `viClu` and re-derives clusters from
density peaks — discarding CLASSIX's labels (it only had dummy `rho`/`delta`). Fixed by the
`fLabelClu` bypass; `cluster_classix_.m` now sets `S_clu.fLabelClu = 1` (and a safe
self-referential `miKnn` for post-merge).
- Modified: `matlab/cluster_classix_.m`, `matlab/irc.m` (`fet2clu_`).

### 2. Missing jisotonic5 MEX dependency
The repo ships `jisotonic5.m` but not `jisotonic5_mex.cpp`/`.mex*`, so `isocut5`/`isosplit5`
failed at runtime trying to compile it. Added a pure-MATLAB drop-in (weighted PAVA isotonic
regression with MSE tracking). A real `.mex*` takes precedence if added later.
- Created: `matlab/jisotonic5_mex.m`.

### 3. Manual-merge crash in the curation GUI (pre-existing)
Merging clusters could crash with `Unable to perform assignment ... 60-by-1 vs 62-by-1` in
`S_clu_wavcor_`. Root cause: `struct_select_` rethrows when one per-cluster field is mis-sized,
which aborted `S_clu_select_` **before** `viSite_clu`/`mrWavCor` were remapped, while `nClu` was
still decremented — desyncing the per-cluster arrays. (Unrelated to the new clustering methods;
reproduced with drift-knn-sorted data.)
- Fix: `S_clu_select_` now resizes each per-cluster field independently (`struct_select_safe_`)
  so one malformed field can't abort the others, plus a final length-reconciliation pass that
  forces all vector/cell per-cluster fields to the kept-cluster count. `delete_clu_` warns
  (non-modal) instead of popping a blocking error dialog if anything is still inconsistent.
- Modified: `matlab/irc.m` (`S_clu_select_`, new `struct_select_safe_`, `delete_clu_`).
  The shared `struct_select_` (used elsewhere) was left unchanged.

---

## Parameters (added to `matlab/default.prm`, `#Alternative clustering methods` block)

### kmeans
| Parameter | Default | Description |
|---|---|---|
| `kmeans_k` | `[]` | Clusters per site (`[]` → `maxCluPerSite`). |
| `kmeans_replicates` | `3` | Restarts; best distortion kept. |
| `kmeans_distance` | `'sqeuclidean'` | `sqeuclidean`/`cityblock`/`cosine`/`correlation`. |
| `kmeans_max_iter` | `100` | Max Lloyd iterations per replicate. |
| `kmeans_start` | `'plus'` | `plus`/`sample`/`uniform`/`cluster`. |
| `kmeans_online` | `'off'` | Online update phase `off`/`on`. |

### HDBSCAN
| Parameter | Default | Description |
|---|---|---|
| `hdbscan_minClusterSize` | `[]` | Min spikes/cluster (`[]` → `min_count`). |
| `hdbscan_minPts` | `10` | Core-distance neighborhood (`min_samples`). |
| `hdbscan_k_graph` | `[]` | kNN-graph size for MST (`[]` → `max(minPts,16)`). |
| `hdbscan_allow_single` | `0` | Allow a single all-points cluster per site vs noise. |

### isosplit
| Parameter | Default | Description |
|---|---|---|
| `isosplit_version` | `6` | Try v6 (Python) then fall back to v5; `5` = v5 directly. |
| `isosplit_isocut_threshold` | `1.0` | Dip-score cutoff (lower → merge more). |
| `isosplit_min_cluster_size` | `10` | v5 min cluster size during merge/redistribute. |
| `isosplit_K_init` | `200` | v5 initial parcels per site. |
| `isosplit_max_iterations` | `1000` | v5 iteration cap. |
| `isosplit_whiten` | `1` | v5 whiten comparison axis by pooled covariance. |

Shared parameters that also affect these methods: `min_count`, `maxCluPerSite`, `knn`, and the
post-merge parameters (`post_merge_mode`, `maxWavCor`, ...). `vcCluster` default remains
`'drift-knn'`.

---

## Verification (MATLAB R2023b)
- 0 parse/syntax errors across `irc.m`, `hdbscan_fit.m`, `isosplit5.m`, `isosplit6.m`,
  `jisotonic5_mex.m`, `cluster_classix_.m`.
- Algorithm self-tests on synthetic data: isosplit5 recovers 3 blobs; HDBSCAN recovers 2 blobs
  + correct noise; `hdbscan_allow_single` and `hdbscan_k_graph` and the isosplit `opts` take
  effect; isosplit6 throws cleanly without a Python backend and falls back to v5.
- Integration via `irc('call', ...)` with synthetic `S0`/`trFet_spk`: all three methods produce
  a valid `S_clu` (`fLabelClu=1`, `numel(icl)==nClu`, `miKnn` sized `knn×nSpk` with valid global
  indices, all spikes assigned).
- Manual-merge fix: `S_clu_select_`/`delete_clu_` produce a consistent `S_clu` even with a
  deliberately malformed per-cluster field (`viSite_clu`/`mrWavCor`/waveforms/counts all match
  `nClu`).
- End-to-end `irc('sort')` on a real recording was not run here (no dataset in the dev
  environment); recommended as the final check on user data.
