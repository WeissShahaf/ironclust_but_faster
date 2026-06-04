# Alternative Clustering Methods (kmeans / HDBSCAN / isosplit6)

## Overview

IronClust's primary clustering algorithm is selected with the `vcCluster` parameter.
In addition to the native density‑peak (DPC) methods, three **label‑based** methods are
available, plus a fixed CLASSIX:

| `vcCluster` | Method | Kind |
|---|---|---|
| `'spacetime'`, `'drift'`, `'drift-knn'`, `'xcov'` | native | density‑peak (DPC) |
| `'kmeans'` | k‑means (MATLAB built‑in) | label‑based |
| `'hdbscan'` | HDBSCAN\* (pure MATLAB) | label‑based |
| `'isosplit6'` (aliases `'isosplit'`, `'isosplit5'`) | ISO‑SPLIT | label‑based |
| `'classix'` | CLASSIX | label‑based |

**Density‑peak methods** produce `rho`/`delta` and let `postCluster_` assign clusters by
peak finding. **Label‑based methods** produce final cluster labels directly. To keep their
labels (the original CLASSIX bug was that they were overwritten), they set an internal flag
`S_clu.fLabelClu = 1`, and `fet2clu_` then **skips `postCluster_`** for them.

### How label‑based clustering works here

1. **Per‑site clustering.** Spike features (`trFet_spk`) are *local to each spike's detection
   site*, so spikes on different sites are not directly comparable. The driver
   `cluster_labels_persite_` loops over detection sites, clusters each site's spikes using its
   full local feature vector, and offsets the labels into a global id space.
2. **kNN graph + density.** For each site it also builds a kNN graph (`miKnn`) and density
   (`rho`) with global spike indices — these are required by the waveform‑based post‑merge.
3. **Cross‑site merge.** The normal `post_merge_` stage (e.g. template matching) then merges
   duplicate units that appear on neighboring sites.

So a label‑based run is: *per‑site over‑segmentation → waveform‑based merge across sites.*

---

## Selecting a method

In your `.prm` file set exactly one string:

```matlab
vcCluster = 'kmeans';      % or 'hdbscan' or 'isosplit6'
```

Then run sorting as usual:

```matlab
irc('sort', 'myrecording.prm')      % or irc('run', ...)
irc('describe', 'myrecording.prm')
irc('manual', 'myrecording.prm')
```

Matching is case‑insensitive. `'isosplit6'`, `'isosplit'`, and `'isosplit5'` all route to the
ISO‑SPLIT path.

---

## Parameter reference

All new parameters live in the **`#Alternative clustering methods`** block of `default.prm`.

### Method‑specific

| Parameter | Default | Method | Description |
|---|---|---|---|
| `kmeans_k` | `[]` | kmeans | Clusters **per site**. `[]` → use `maxCluPerSite`. Higher = more over‑segmentation (collapsed later by post‑merge). Internally capped at `floor(nSpk_site/2)`. |
| `kmeans_replicates` | `3` | kmeans | k‑means restarts; the lowest‑distortion result is kept. Higher = more stable, slower. |
| `kmeans_distance` | `'sqeuclidean'` | kmeans | `'sqeuclidean'` \| `'cityblock'` \| `'cosine'` \| `'correlation'`. |
| `kmeans_max_iter` | `100` | kmeans | Max Lloyd iterations per replicate. |
| `kmeans_start` | `'plus'` | kmeans | Initialization: `'plus'` (k‑means++) \| `'sample'` \| `'uniform'` \| `'cluster'`. |
| `kmeans_online` | `'off'` | kmeans | Online update phase `'off'`/`'on'` (on is slower, occasionally lower distortion). |
| `hdbscan_minClusterSize` | `[]` | hdbscan | Minimum spikes to form a cluster. `[]` → use `min_count`. ↑ = fewer, larger clusters. |
| `hdbscan_minPts` | `10` | hdbscan | Core‑distance neighborhood (HDBSCAN `min_samples`). ↑ = more conservative → **more spikes labeled noise (cluster 0)**. |
| `hdbscan_k_graph` | `[]` | hdbscan | kNN‑graph size used to build the MST. `[]` → `max(minPts,16)`. Larger = more accurate, slower. |
| `hdbscan_allow_single` | `0` | hdbscan | `1` allows one all‑points cluster per site instead of labelling everything noise when no clear split exists. |
| `isosplit_version` | `6` | isosplit | `6` = try the official isosplit6 (Python) then fall back to MATLAB `isosplit5`; `5` = use `isosplit5` directly (no Python probe). |
| `isosplit_isocut_threshold` | `1.0` | isosplit | Dip‑score cutoff. **Lower → merge more** (fewer clusters); higher → keep clusters split. The main isosplit knob. |
| `isosplit_min_cluster_size` | `10` | isosplit (v5) | Minimum cluster size during the merge/redistribute passes. |
| `isosplit_K_init` | `200` | isosplit (v5) | Number of initial parcels (over‑segmentation) per site. |
| `isosplit_max_iterations` | `1000` | isosplit (v5) | Safety cap on merge/redistribute iterations. |
| `isosplit_whiten` | `1` | isosplit (v5) | Whiten the comparison axis by pooled covariance (`1`=on, `0`=off). |

### Shared parameters that also affect these methods

| Parameter | Default | Effect |
|---|---|---|
| `min_count` | `30` | Sites with fewer spikes are kept as a single cluster (not sub‑clustered); also the default HDBSCAN min size; post‑merge prunes clusters below it. |
| `maxCluPerSite` | `20` | Default `k` for kmeans when `kmeans_k = []`. |
| `knn` | `30` | Neighbors used to build the per‑site `miKnn`/`rho` consumed by post‑merge. |

### Post‑merge stage (runs after every method)

Cross‑site duplicates are merged by the normal pipeline, so these still apply:
`post_merge_mode` (default `1`, template matching), `maxWavCor` (default `0.985` — lower =
more aggressive merging), `spkLim_factor_merge`, `frac_shift_merge`, `fRemove_duplicate`.

All ISO‑SPLIT v5 internal options are now exposed as `isosplit_*` parameters above
(`isosplit_min_cluster_size`, `isosplit_K_init`, `isosplit_max_iterations`, `isosplit_whiten`).
They apply only to the pure‑MATLAB v5 path; the Python isosplit6 backend uses its own defaults.

---

## Per‑method notes

### kmeans
- Uses MATLAB's built‑in `kmeans` (Statistics & Machine Learning Toolbox).
- Has no notion of the "right" number of clusters, so it **over‑segments** each site to
  `k = kmeans_k` (default `maxCluPerSite`) and relies on post‑merge to collapse redundant
  units. Increase `kmeans_k` if real units are being lumped; decrease it for speed.

### HDBSCAN
- Pure‑MATLAB implementation in `hdbscan_fit.m` (mutual‑reachability kNN graph → MST →
  condensed tree → Excess‑of‑Mass stability). No external toolbox required for the algorithm
  itself; it uses `knnsearch` when available (Statistics & ML Toolbox) and falls back to a
  chunked brute‑force kNN otherwise.
- Labels spikes it considers noise as **0** (left unassigned). Raise `hdbscan_minPts` or
  `hdbscan_minClusterSize` for cleaner, more conservative clusters; lower them to keep more
  spikes.

### isosplit6
- `cluster_isosplit_` calls `isosplit6.m`, which runs the official ISO‑SPLIT v6 through
  MATLAB's Python bridge. **Requirements:** a configured Python (R2023b: CPython 3.9–3.11)
  and `pip install isosplit6 numpy`. Verify with:
  ```matlab
  pyenv                                    % check/Set the interpreter
  py.importlib.import_module('isosplit6')   % must not error
  ```
- If the Python backend is unavailable, it **automatically falls back** to the pure‑MATLAB
  `isosplit5.m` (reuses the repo's `isocut5.m` + `jisotonic5.m`). To skip the probe entirely
  set `isosplit_version = 5`.

---

## Dependencies

- **kmeans** and HDBSCAN's `knnsearch`: Statistics and Machine Learning Toolbox (HDBSCAN has a
  brute‑force fallback if it is missing).
- **isosplit6** (true v6): a working MATLAB Python environment + the `isosplit6` package.
  Otherwise `isosplit5` (no extra dependency) is used.
- `isocut5.m`/`isosplit5.m` require `jisotonic5_mex`; the repo ships `jisotonic5.m` but **not**
  the MEX source, so a pure‑MATLAB `jisotonic5_mex.m` is provided (a real `.mex*` would take
  precedence if added).

---

## Tuning quick‑start

- **Too many tiny/split units:** lower `isosplit_isocut_threshold` (~0.8), raise
  `hdbscan_minPts`/`hdbscan_minClusterSize`, or lower `kmeans_k`; and/or lower `maxWavCor` for
  more post‑merge.
- **Units getting lumped together:** raise `isosplit_isocut_threshold` (~1.5), lower
  `hdbscan_minPts`, raise `kmeans_k`, and/or lower `min_count`.

---

## Files

- `matlab/irc.m` — `fet2clu_` dispatch + `fLabelClu` bypass; `cluster_kmeans_`,
  `cluster_hdbscan_`, `cluster_isosplit_`, `cluster_labels_persite_`, `persite_knn_`,
  `S_clu_from_labels_`.
- `matlab/hdbscan_fit.m` — pure‑MATLAB HDBSCAN\*.
- `matlab/isosplit5.m` — pure‑MATLAB ISO‑SPLIT (reuses `isocut5.m`/`jisotonic5.m`).
- `matlab/isosplit6.m` — official isosplit6 via Python, with v5 fallback.
- `matlab/jisotonic5_mex.m` — pure‑MATLAB isotonic regression (restores `isocut5`/`isosplit5`).
- `matlab/cluster_classix_.m` — sets `fLabelClu` (fixes CLASSIX label clobbering).
- `matlab/default.prm` — parameter block + extended `vcCluster` comment.

See also: `CLASSIX_USAGE.md`.
