# Plan: per-site spike cap for label-based clustering

## Problem
Per-site, label-based clustering (`vcCluster = isosplit/hdbscan/kmeans`) cost is driven
by the site's spike count `n1`:
- the per-site kNN graph (`persite_knn_` → `pdist2`) is **O(n1^2)**;
- the clustering algorithm (isosplit5 / hdbscan) grows steeply with `n1` too.

On the real recording a few **noise/artifact channels** are enormous: site 59 =
1,124,504 spikes, site 328 = 1.0M, vs a **median of 32,890**. Those sites are ~34x the
median in size → ~1,170x the kNN cost, and they dominate (stall) the whole sort. We do
not want to over-segment noise channels anyway, so subsampling them is also arguably
*more* correct.

## Goal
Bound the per-site work by clustering at most `maxSpk` spikes per site and propagating
the result to the rest, so a 1.1M-spike site costs about the same as a `maxSpk`-spike
site. Off by default (byte-identical to today); only large sites are affected when on.

## Parameter (default.prm, `#Alternative clustering methods` block)
```
maxSpk_persite_clust = [];   % cap spikes used for per-site clustering ([]=off / no cap).
                             % Sites with more spikes cluster a random subsample of this
                             % many; the rest are assigned to the nearest subsample unit.
                             % Bounds the O(n^2) kNN and the clustering cost on huge
                             % (usually noise) channels. Try 50000-100000 to enable.
```
(No other param needed; the subsample is random with a per-site deterministic seed.)

## Where: `cluster_site_` in irc.m (the per-site worker)
`cluster_site_` already isolates one site's clustering + kNN and is `parfor`-safe. Add a
capped branch; the existing full path is unchanged when the cap is off or `n1 <= maxSpk`.

### Capped branch (when `maxSpk` set and `n1 > maxSpk`, m = maxSpk)
1. **Deterministic subsample.** `rng(double(viSpk1(1)))` (stable per-site seed → identical
   under serial and parfor), then `viSub = randperm(n1, m)` (local indices); `Xsub =
   X(viSub,:)`, `viSpkSub = viSpk1(viSub)`.
2. **Cluster the subset.** `labelSub = fh_cluster(Xsub, P)` (isosplit/hdbscan/kmeans on m
   points — bounded).
3. **Subset kNN graph.** `[miKnnSub, rhoSub] = persite_knn_(Xsub', knn, viSpkSub)` —
   O(m^2), bounded; global indices point only into the subset (valid global spike ids).
4. **Assign ALL n1 spikes to the nearest subset member** (new helper `nearest_in_set_`,
   chunked `pdist2(...,'Smallest',1)`, O(n1*m), chunked so memory is bounded):
   - `viNN = nearest_in_set_(X', Xsub')`  % for each of n1 spikes, its nearest subset col
   - `viLabel = labelSub(viNN)`           % label = nearest subset member's label
   - `miKnn1  = miKnnSub(:, viNN)`         % copy that member's kNN row (global indices)
   - `vrRho1  = rhoSub(viNN)`              % copy that member's density
   A subset spike is its own nearest member (distance 0) → keeps its own label/kNN.
5. `nLabel = max([0; viLabel(viLabel>0)])` (unchanged), `t_clu`/`t_knn` measured as today
   (t_clu wraps steps 1-2, t_knn wraps steps 3-4).

### New helper `nearest_in_set_(mrFet_all, mrFet_sub)` (irc.m subfunction)
- Inputs: `nFet x n1` and `nFet x m`. Returns `viNN` (n1 x 1, index into the m columns).
- Chunk the n1 queries (e.g. 1000 at a time, mirroring `knn_cpu_`):
  `[~, ix] = pdist2(mrFet_sub', mrFet_all(:,blk)', 'euclidean', 'Smallest', 1);`
- Pure of shared state → safe under `parfor`.

## Cost (site 59, n1≈1.12M, m=50k, nFet≈tens)
| Step | Before (full) | After (capped) |
|---|---|---|
| clustering | isosplit on 1.12M (minutes-hours) | isosplit on 50k (seconds) |
| kNN graph | O(n1^2) ≈ 1.3e12 | O(m^2) ≈ 2.5e9 |
| assignment | — | O(n1*m) ≈ 5.6e10, chunked BLAS (~seconds) |

Net: a monster site drops from "stalls the sort" to seconds, bounded and predictable.
This bounds BOTH the kNN and the clustering, so it is the right fix regardless of which
the measurement shows dominates (the kd-tree-kNN alternative only helps if the kNN
dominates AND the features are low-dimensional).

## Correctness / backward-compatibility
- **Off by default** (`maxSpk_persite_clust = []`) → the capped branch never runs →
  behavior byte-identical to current (verified the same way as the parallelization).
- **Reproducible**: per-site seed makes serial == parfor for capped sites too.
- **Every spike still gets a label, a kNN row, and a density** → `S_clu_from_labels_` and
  `post_merge_` see a fully-populated `miKnn`/`rho`/`viClu` exactly as before; global
  label offsets (cumsum) are unaffected (each site still reports its own `nLabel`).
- **Downstream impact** is confined to capped (huge, usually noise) sites: their labels
  and kNN are approximate (subset-propagated). Normal sites are untouched.

## Verification (MATLAB R2023b)
1. checkcode: 0 syntax errors; `cluster_site_`/`nearest_in_set_` `parfor`-clean.
2. Cap OFF: re-run the serial-vs-parallel equality test → `viClu`/`miKnn`/`vrRho`
   unchanged from current.
3. Cap ON, synthetic: a site of N >> maxSpk clusters in ~the time of a maxSpk site;
   all spikes labeled; `miKnn` indices valid/global; serial == parfor (seeded).
4. Real data: `measure_persite_timing(prm)` (or a full sort) on site 59 finishes in
   seconds instead of stalling.

## Dependency / sequencing
- The running graded-site measurement (`zz_measure_split`) reports the t_clu vs t_knn
  split. The cap is robust either way, but the split tells us how aggressive `maxSpk`
  must be (if isosplit-bound, even a generous cap helps; if kNN-bound, the O(m^2) term
  is what matters).
- Suggested default when enabling for this recording: `maxSpk_persite_clust = 50000`
  (≈ above the 75th percentile of site sizes, so only the genuine giants are capped).

## Files to touch
- `matlab/irc.m`: capped branch in `cluster_site_`; new `nearest_in_set_` subfunction.
- `matlab/default.prm`: add `maxSpk_persite_clust = [];` with the comment above.
- changelog entry; update the `cluster_labels_persite_` banner to mention the cap.
