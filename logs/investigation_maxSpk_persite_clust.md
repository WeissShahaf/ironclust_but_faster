# Investigation — `maxSpk_persite_clust`: minimal acceptable value + runtime when off

**Date:** 2026-07-16 · **Scope:** the per-site spike cap for label-based clustering (CID-13 area).
**Code:** `cluster_labels_persite_` (irc.m:2500), `cluster_site_` (2656), `cluster_site_capped_`
(2756), `nearest_in_set_` (2809), `persite_knn_` (2737) → `knn_cpu_` (26518).
**Not a code change — analysis only.**

---

## TL;DR

- **Minimal *functional* value:** `max(min_count, 2·nFet)`. `cluster_site_` only engages the cap when
  `maxSpk ≥ max(2, min_count)` (irc.m:2676); below that it is **silently disabled** and giant sites
  run fully uncapped. `cluster_labels_persite_` warns when `maxSpk < min_count` (2526). With the
  defaults (`min_count = 30`, and "min_count set to 2·#features if lower") this floor is ~30, but
  **~60–90 if `nFet` is a few dozen**. Never set it below this — it does nothing but print a warning.
- **Minimal *acceptable* value is data-dependent, not a constant.** It is set by the smallest real
  unit you need to keep, not by runtime. Rule of thumb: to preserve a unit that is fraction `p` of a
  capped site's spikes, you need **`m ≳ min_count / p`** (so its random subsample still holds ≥
  `min_count` spikes for isosplit to resolve it). Below that, small units on capped sites are
  **silently lost** (merged/dropped) — a quiet quality regression, not a crash.
- **Practical guidance:** floor **~10 000–20 000** for the intended use (bounding giant *noise*
  sites); **50 000 recommended** (only genuine giants capped, preserves units down to ~0.06% of the
  site). Runtime is **~linear in `m`**, so lower `m` is always faster — the binding constraint is
  small-cluster recall, never speed.
- **When off (`[]`), the top runtime levers:** (1) **suppress the noise upstream** so giant sites
  never form (`blank_thresh`, `qqFactor`, CAR, bad-channel exclusion) — the giants are usually
  artifact, so this *removes* the work (usually the biggest + most correct win); (2) right-size the
  worker pool (`nWorkers_clust` vs the local cluster profile) for the non-giant bulk; (3) GPU the
  per-site kNN — an **index-returning GPU kNN already exists** (`cuda_knn_` + `cuda_knn_index.ptx`,
  live in the drift path), so this is mostly *plumbing*, not kernel work (my earlier "needs kernel
  work" note pointed at the wrong wrapper); (4) kd-tree/approximate kNN for the O(n²) graph when there
  is no GPU; (5) a cheaper `vcCluster` if the printed `t_clu` breakdown says clustering (not kNN)
  dominates. The outer loop is **one site = one worker**, so pool width cannot bound a single giant;
  the only ways to shrink a giant are its kNN/clustering half (3–5), its spike count (1), or splitting
  that one site across workers (§4.8, high effort, generally dominated by 3–4). See the §4 comparison
  table for the head-to-head.

---

## 1. What the cap does (mechanism)

`cluster_site_capped_` (irc.m:2756), for a site of `n1` spikes with cap `m = maxSpk`:

1. **Deterministic subsample** of `m` spikes (seeded by the first global spike id → serial==parfor).
2. **Cluster the subset:** `fh_cluster(Xsub, P)` (isosplit5 by default) on `m` points.
3. **Subset kNN graph:** `persite_knn_(Xsub', knn, viSpkSub)` — `O(m²·nFet)`, global indices.
4. **Assign ALL `n1` spikes** to their nearest of the `m` clustered anchors (`nearest_in_set_`,
   chunked `pdist2 … 'Smallest',1`), copying that anchor's label, kNN row, and density —
   `O(n1·m·nFet)`. A subsample spike is its own nearest anchor (distance 0), so it keeps its own
   values. Every spike still gets a label + global kNN row + rho, so `S_clu_from_labels_` /
   `post_merge_` are unaffected.

Only sites with `n1 > m` take this branch; everything else is byte-identical to uncapped.

## 2. Cost model — why runtime is ~linear in `m`

Calibrated to the parameter's own measurement (`m = 50 000`, `n1 ≈ 1.12M` → **~90 s** total, isosplit
~5 s, "subset kNN + assignment" ~85 s):

| Term | Order | At m=50k, n1=1.12M | Share |
|---|---|---|---|
| cluster subset (isosplit) | grows steeply with `m` | ~5 s | small |
| subset kNN graph | `O(m²·nFet)` | ~3–4 s | small |
| **1-NN assignment** (`nearest_in_set_`) | **`O(n1·m·nFet)`** | **~81 s** | **dominant** |

The assignment term is `n1/m ≈ 22×` the subset-kNN term, so it dominates. For a **fixed** giant site
it is **linear in `m`**: `m = 25k → ~45 s`, `m = 50k → ~90 s`, `m = 100k → ~180 s` (plus the small,
super-linear isosplit term). **Uncapped**, the same site pays `O(n1²·nFet)` for the kNN (≈1.3e12 for
`n1=1.12M`) *and* isosplit on 1.12M points → tens of minutes to hours (the ~80 min figure).

**Consequence:** runtime never sets a *lower* bound on `m` — smaller is always faster. The floor is a
**quality** floor.

## 3. Minimal acceptable value

### 3a. Functional floor (hard)
`cluster_site_` activates the cap only if `maxSpk ≥ max(2, min_count)` (irc.m:2676). `min_count`
defaults to 30 and is raised to `2·nFet` if lower (`default.prm`), so the true floor is
**`max(min_count, 2·nFet)`** — typically ~30, but ~60–90 when features are a few dozen. Below it the
cap is a **no-op** (warned at 2526). So: never below this.

### 3b. Quality floor (the real answer)
The subsample must retain enough spikes of each real unit for isosplit to call it a mode. A unit that
is fraction `p` of the site contributes ~`Binomial(m, p)` ≈ `m·p` spikes to the subsample. To keep it
resolvable you need roughly

> **`m·p ≳ min_count`  ⇒  `m ≳ min_count / p_min`**

with a safety factor of ~2–5× for reliability (isosplit needs a *populated* mode, not just
`min_count`). `p_min` is the smallest unit fraction you are unwilling to lose **on the largest capped
site**. Worked examples on a 1.12M-spike site (`min_count = 30`):

| `m` | keeps units down to `p ≈ min_count/m` | ≈ spikes/unit on a 1.12M site | runtime/giant |
|---|---|---|---|
| 100 000 | 0.03 % | ~340 | ~180 s |
| 50 000 | 0.06 % | ~670 | ~90 s |
| 20 000 | 0.15 % | ~1 700 | ~40 s |
| 10 000 | 0.30 % | ~3 400 | ~20 s |
| 5 000 | 0.60 % | ~6 700 | ~10 s |

Prior measurement (CID-13): `m = 20 000` left **30.5 % of spikes clustered, 69.5 % 1-NN-propagated**
on this recording — expected, because the capped sites are dominated by noise where over-segmentation
is undesirable anyway.

### 3c. The noise-site subtlety
The intended targets (site 59 = 1.12M, site 328 = 1.0M vs a **median of 32 890**) are noise/artifact
channels with **no real units to preserve** — for them any `m ≥ functional floor` is acceptable, and
post-merge + SNR filtering discard the spurious splits. The risk of a low `m` is only a **real unit
buried in a giant site**. Since you can't cheaply tell per-site, pick `m` for the rarest real unit you
would accept losing → **50 000** is the safe default; **~10 000–20 000** is acceptable if you accept
that sub-~0.2 %-fraction units on the very largest sites may be merged.

### 3d. How to get a data-specific number
Measure rather than guess: sweep `m ∈ {5k,10k,20k,50k,100k}` on the busiest site and compare recovered
cluster count / small-unit recall against the uncapped result (the scratchpad `check_cap_impact.m` /
`measure_persite_timing` approach). Pick the smallest `m` at which small-unit recall plateaus.

## 4. If `maxSpk_persite_clust = []` (off): optimizing runtime

Uncapped, a giant site pays `O(n1²·nFet)` kNN (`knn_cpu_` → chunked exact `pdist2`) + full isosplit on
`n1`. Levers, best first:

1. **Right-size the worker pool (no code).** `nWorkers_clust = 12` default, clamped to `#cores` and to
   `parcluster('local').NumWorkers` (2561). The per-site loop is embarrassingly parallel; make sure the
   profile actually permits the requested width (`c = parcluster('local'); c.NumWorkers = 12;
   saveProfile(c)`), and balance workers against RAM (each worker holds a site's features + its `O(n1²)`
   distance chunk). CID-10 fixed a stale-undersized-pool reuse. **Caveat:** parallelism spreads work
   *across* sites but a single 1.12M-spike site still runs on **one** worker for ~80 min — the giant is
   what the cap exists for, and parallelism cannot bound it.

2. **Suppress the noise that creates giant sites (no code, usually the right fix).** The giants are
   artifact channels; stop them reaching 1M spikes upstream:
   - `blank_thresh` (default 8 MAD) + `blank_period_ms` (5 ms) — common-mean artifact blanking; lower
     `blank_thresh` to blank more.
   - `qqFactor` (detection threshold, default 5) — raise to detect fewer noise crossings.
   - common-average/median referencing; exclude known-bad channels from the `.prb`.
   This removes the work instead of bounding it, and is *more* correct (you don't want 1M noise spikes
   clustered at all).

3. **GPU the per-site kNN (code — less work than first thought).** The `O(n1²)` kNN dominates
   uncapped giants, and `persite_knn_` currently calls the **CPU** `knn_cpu_`. Two GPU kNN wrappers
   exist: `cuda_knn__` (irc.m:26543, kernel `cuda_knn.ptx`) returns density ONLY — its `miKnn` output
   is commented out (26568-69) and it forces CPU when indices are requested — **but `cuda_knn_`**
   (single trailing underscore, irc.m:26476, kernel `cuda_knn_index.ptx`, "it computes the index of
   KNN") **already returns neighbor indices from the GPU** and is a live, exercised path (used by
   `rho_drift_knn_` at 26462 and the merge/split path at 17549). So this is mostly **plumbing** — point
   `persite_knn_` at `cuda_knn_`, gather `vrKnn`/`miKnn`, map local→global indices — not new kernel
   work (my earlier "needs kernel work" note pointed at the wrong wrapper). Caveats: `cuda_knn_`
   engages the GPU only when the feature dim `nC ≤ nC_max` (default 36) and auto-falls-back to
   `knn_cpu_` otherwise (so it is a safe swap), and under the per-site `parfor` many workers would
   contend for one GPU — so the natural pairing is to pull the few giant sites OUT of the `parfor` and
   GPU them (see lever 8), leaving the small-site bulk on the CPU pool. Highest-value structural win
   for an uncapped, kNN-dominated giant.

4. **kd-tree / approximate kNN (code).** `knn_cpu_` is exact `O(n1²)`. `knnsearch(...,'NSMethod',
   'kdtree')` is ~`O(n1 log n1)` for low-dimensional features; `nFet` is a few dozen, so a kd-tree
   still beats exhaustive at `n1 ≈ 1M` (with mild degradation as dimension grows). Helps only when the
   printed `t_knn` share dominates.

5. **Cheaper clustering method (config).** isosplit5 grows steeply with `n1`. If the `cluster_labels_
   persite_` breakdown (`clustering X s (Y%) + kNN …`, irc.m:2641) shows **clustering** dominating,
   switching `vcCluster` to k-means (`cluster_kmeans_`, `O(n1·k·iter)`) or hdbscan cuts it sharply;
   `post_merge_` collapses the over-segmentation. Trades some accuracy for speed.

6. **Feature dimensionality (config).** Distance cost is linear in `nFet`; fewer PCs/sites per feature
   shrinks both kNN and clustering, at some feature-resolution cost.

7. **Does NOT help:** lowering `knn` (30). `pdist2(...,'Smallest',knn)` computes all `O(n1²)` distances
   regardless of `knn`; `knn` only affects the selection. Not a speed lever for the graph.

8. **Split one giant site across workers — intra-site parallelism (code, high effort, usually
   dominated).** The outer loop is one-site-one-worker (`parfor (iSite = 1:nSites, nWorkers)`,
   irc.m:2599), so a single giant never gets more than one core no matter how wide the pool — lever 1's
   blind spot. The giant's *kNN* half IS internally parallel: `knn_cpu_`'s query-block loop
   (`for i1 = 1:nStep_knn:n1`, 26532) and `nearest_in_set_`'s assignment loop (2819) are embarrassingly
   parallel over query blocks, so they could be spread across workers. **Blocker:** MATLAB runs an
   inner `parfor` *serially* when already inside a `parfor`, so you cannot simply nest it — you must
   restructure: detect giants, pull them out of the outer `parfor`, and process them one at a time with
   the whole pool devoted to an inner block-`parfor` (or `spmd`/`parfeval`) over the kNN. This
   parallelizes only the **kNN** half, not isosplit (iterative, not trivially parallel), so it does
   nothing for a clustering-dominated giant. It is the CPU cousin of lever 3 and overlaps lever 4: with
   a GPU, lever 3 gives thousands of lanes for far less restructuring; on CPU, lever 4 (kd-tree) buys
   the `O(n1²)→O(n1 log n1)` asymptotic win with a one-line `knnsearch` swap. So lever 8's only unique
   niche is a single kNN-dominated giant, **no** GPU, features too high-dimensional for a kd-tree to
   help, and many idle cores — rare. Highest engineering cost of the eight, so it ranks last.

### Comparison at a glance

Ordered by recommended priority: shrink the giant's spike count first, schedule the bulk, then attack
its kNN/clustering halves. "Attacks" = which factor of the giant's `clustering(n1) + O(n1²·nFet)` kNN
cost the lever reduces. The **cap** is included as the baseline it is (the intended one-line fix); the
rest are what remains when the cap is off.

| Lever | Attacks | Effort | Win on one giant | Key limit / risk |
|---|---|---|---|---|
| **Cap** (`maxSpk_persite_clust`) | n1 for kNN **and** clustering | 1 line (config) | ~80 min → ~90 s | quality floor `m ≳ min_count/p_min`; the intended fix |
| **2.** Upstream noise suppression | spike **count** n1 (removes the work) | config / `.prb` | giant disappears (n1 → ~median) | over-blank drops real units; per-recording tuning |
| **1.** Right-size worker pool | scheduling (bulk only) | config + profile | non-giant bulk ~min(cores, RAM/site)× | **cannot bound one giant**; RAM per worker |
| **3.** GPU per-site kNN (`cuda_knn_`) | kNN half | plumbing (path exists) | `O(n1²)` → GPU-seconds | nFet ≤ nC_max (36) else CPU; single-GPU contention under parfor |
| **4.** kd-tree / approx kNN | kNN half | small code | `O(n1²)` → ~`O(n1 log n1)` | degrades as nFet grows; approx nudges rho/miKnn |
| **5.** Cheaper `vcCluster` (kmeans) | clustering half | config | steep → linear in n1 | accuracy; leans on `post_merge_` |
| **6.** Fewer features (`nPcPerChan`) | both halves (∝ nFet) | config | linear in nFet | feature-resolution loss |
| **8.** Intra-site multi-worker | kNN half | **large code** | kNN ~×#workers on one site | nested-parfor blocker → restructure; no help to isosplit; dominated by 3/4 |
| — Lower `knn` | — | — | **none** | `pdist2` computes all distances regardless |

**Decision shortcut:** read the printed `t_clu` vs `t_knn` split (below) → if **kNN**-bound, use lever 3
(GPU present) or lever 4 (no GPU); if **clustering**-bound, use lever 5. In all cases prefer lever 2 if
the giants are artifact (they usually are), and keep lever 1 sized for the bulk. Reach for lever 8 only
in its narrow niche above.

**Diagnostic first:** `cluster_labels_persite_` already prints the summed `t_clu` vs `t_knn` split and
the top-5 slowest sites (irc.m:2641-2650). Read that once — it says whether to attack the kNN
(levers 3-4) or the clustering (lever 5), and which sites are the giants (lever 2).

## 5. Bottom line

- The cap's runtime is **linear in `m`** and dominated by the `O(n1·m)` 1-NN assignment; the floor on
  `m` is therefore about **small-cluster recall**, not speed. Keep `m ≳ min_count / p_min`; never below
  `max(min_count, 2·nFet)`. **50 000** is the safe default; **~10–20 k** is acceptable for bounding
  noise giants if you accept losing sub-~0.2 % units on the largest sites.
- With the cap **off**, the cheapest real wins are **upstream noise suppression** (so giants never
  form) and **right-sizing the pool** for the non-giant bulk; the biggest structural win is
  **GPU-ing the per-site kNN** — and an index-returning GPU kNN (`cuda_knn_` / `cuda_knn_index.ptx`)
  **already exists** and is exercised elsewhere, so wiring `persite_knn_` to it is mostly plumbing, not
  kernel work. The outer loop is one-site-one-worker, so pool width alone cannot bound a single giant
  (splitting one site across workers is possible but high-effort and dominated by the GPU/kd-tree
  levers) — bounding that giant is exactly the gap the cap fills. See §4's comparison table for the
  head-to-head.
