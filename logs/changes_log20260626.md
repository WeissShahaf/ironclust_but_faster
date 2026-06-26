# Changes Log - June 26, 2026

## Summary
Hardening pass on the post-merge and per-site clustering paths after a 384-site
`isosplit` + spike-cap run crashed in `post_merge_`. Per-site label clustering with the
spike cap produces *many* small clusters (1081 in this run vs a handful under global
DPC), exposing empty / single-spike / gappy-label edge cases in code that assumed a few
large, non-empty clusters. Ten fixes were applied — all are crash fixes on degenerate
inputs or identity-for-healthy guards, so **no healthy run of any clustering method
changes its output**. A small `nearest_in_set_` performance tweak rode along.

Committed + pushed as `0f2ab3f` on `rewind` (`origin/rewind`). Design rationale and the
4-agent review that found the latent items are in `logs/plan_postmerge_robustness.md`.

## Background (the failing run)
`260317_afm18349_g0 ... _IRC_all_sites.prm`, `vcCluster='isosplit'`, mode-17 post-merge,
`maxSpk_persite_clust` active. The sort reached auto-merge and died in
`clu_wave_similarity_paged` (`cell2mat` "must be of the same data type"); after that was
fixed it died again in `post_merge_wav4_` (`cell2mat`/`cat` "Dimensions ... not
consistent"). Both are the same failure class: a per-cluster `cell2mat`/reduction where
an empty or single-spike cluster yields a wrong-shape or wrong-type element. A targeted
4-agent review of the live sort path (`post_merge_*`, `templateMatch_post_`, the
`S_clu_*` stat functions, and the per-site driver) found two more live crashes and three
latent ones.

## Changes

### A. Confirmed live-path crashes
- **`clu_wave_similarity_paged.m` (`cell2mat_vi_`)** — drop empty cells before
  `cell2mat`. An empty cluster is a `0×0 double` while non-empty cells carry `int32`
  spike indices (from `S_clu.miKnn`); mixing the two errors. The index column is computed
  separately and already accounts for empties, so the spike/cluster indices stay aligned.
- **`irc.m` `post_merge_wav4_`** — two fixes:
  - `median(mrPos_spk(x,:))'` returned a scalar `NaN` on an empty `x` (burst-emptied
    cluster); pinned to `nPos×1` via `reshape(median(...,1), nPos, 1)`.
  - a **1-spike** sub-cluster made `viSpk_(1:end*FRAC_NEAR)` = `1:0.5` = `[]`, so
    `mode([])`=`NaN` then `miSites(:,NaN)` crashed. Guarded with `max(1, end*FRAC_NEAR)`
    (binds only when `end*FRAC_NEAR < 1`, i.e. a single spike; ≥2 spikes unchanged).
- **`irc.m` `S_clu_refresh_` + `S_clu_map_index_`** — `mode(int32([]))` on an empty
  cluster can return a `double` NaN while populated clusters return `int32`, making
  `arrayfun` (uniform output) throw. Cast inside `mode(double(...))` so outputs are
  uniformly `double`; empties are then dropped by `S_clu_remove_empty_`.

### B. Latent hardening (per the plan)
- **`S_clu_from_labels_`** (D1) — `unique`-remap positive labels to a contiguous
  `1..nClu` range (0 = noise preserved) so a label gap can't drop an `icl` entry and
  misalign `icl` with cluster numbers. Identity for the shipped methods
  (kmeans/hdbscan/isosplit are contiguous by construction).
- **`cluster_site_` / `cluster_site_capped_`** (D2a) — wrap the O(n²) per-site kNN step
  in try/catch with a valid self-referential fallback, so a giant *uncapped* site that
  OOMs degrades to junk for that one site instead of aborting the whole multi-hour sort
  (the serial loop previously had no guard). The capped path collapses to one cluster on
  failure so it can't introduce a label gap.
- **`cluster_labels_persite_`** (D2b) — one-time warning when
  `maxSpk_persite_clust < min_count`, because `cluster_site_` silently ignores the cap in
  that case and giant sites then run fully uncapped.

### C. Deferred items, applied "only if it doesn't break other methods"
- **`cluster_classix_.m`** — same `unique`-remap as D1, before `nClu`. Safe: the stored
  `classix_out` / `classix_explain` are **never read** elsewhere in `matlab/`
  (grep-verified), so there is no label-value coupling to break.
- **`irc.m` `correlogram_`** — `max([int32(0); x(:)])` makes the per-cluster bin-max
  empty-cluster-safe and byte/type-identical for non-empty clusters (time bins are ≥1).
- **`irc.m` `waveform_similarity_clu_` + `templateMatch_post_burst_`** — `if
  isempty(viSpk1), continue;` guards the `viSpk1(vii1)` index against a 0-spike cluster.
  No-op for any cluster with ≥1 spike; serves post-merge modes 1/8/9/10/13/14.

### Performance (rode along in the same commit)
- **`irc.m` `nearest_in_set_`** — chunk size `nStep` 1000 → 10000. The per-site cap
  assigns every spike to its nearest subsample member via a chunked `pdist2`; larger
  blocks mean ~10× fewer calls and better BLAS efficiency on the big sites.

### Per-recording parameter (NOT in the repo)
- The failing recording's `.prm` (`maxSpk_persite_clust`) was lowered 50000 → 10000 to
  cut the dominant 1-NN assignment cost. This is the user's external `.prm`, not
  `default.prm`; recorded here for traceability only.

## Verification
- `checkcode('matlab/irc.m')` and `checkcode('matlab/cluster_classix_.m')` — **0
  syntax-class messages**, all four new try-blocks have catches, no new warnings on any
  edited line (R2023b).
- D1 is the identity on dense/ascending labels (the assembly's `cumsum` offsets), so a
  normal isosplit run is byte-identical; the remap only changes gappy input (the broken
  case).

## Status / deferred
- All ten fixes committed and pushed (`0f2ab3f` → `origin/rewind`). Nothing outstanding
  on this thread.
- Note (not done): `cluster_classix_` builds `S_clu` directly rather than via
  `S_clu_from_labels_`; the contiguity remap was duplicated there. If more label methods
  are added, consider routing them all through `S_clu_from_labels_` to keep one guard.

## Files
- Added: `logs/changes_log20260626.md`, `logs/plan_postmerge_robustness.md`.
- Modified: `matlab/irc.m`, `matlab/clu_wave_similarity_paged.m`,
  `matlab/cluster_classix_.m`.

---

## Update — GUI "Merge auto" silently discarded merges (`ea6a8dc`)

### Symptom
From the curation GUI, **Edit > Merge auto** printed `Merged 29 waveforms (459->430)`
and spent ~136 s recomputing cluster mean waveforms, but then popped up *"No clusters
are merged, adjust the correlation threshold"* and the cluster count stayed at **459**.

### Root cause — sign bug in `post_merge_wav_`
`post_merge_wav_` returns `[S_clu, nClu_merge]`. Inside the merge block it correctly
computes `nClu_merge = nClu_pre - S_clu.nClu` (= +29), but the function's **final** line
returned the opposite, `nClu_merge = S_clu.nClu - nClu_pre` (= −29). `merge_auto_` commits
the merged `S_clu` (`set0_`/`gui_update_`/`save0_`) only when `nClu_merge > 0`; with −29 it
took the else branch, so the computed merge was **discarded** and the GUI state never
changed. The waveform recomputation ran (the early-return guard at the in-block `+29` was
not hit), which is why time was spent with no result.

A git bisect of the line confirmed a **regression**: `b99996f` ("Refactor and streamline
cluster and UI operations") flipped the sign; it was `nClu_pre - S_clu.nClu` before
(`5489202`). So GUI threshold-merging had been silently no-op since that refactor.

### Fix
- `post_merge_wav_` final line restored to `nClu_merge = nClu_pre - S_clu.nClu` (positive
  = #clusters removed by merge + de-duplication), consistent with the in-block computation,
  so `merge_auto_` commits and reports correctly.
- Gated the stray `DEBUG post_merge_wav_:` print behind `fVerbose` (was always-on console
  noise left over from debugging this issue).

Pure logic fix; no effect on a healthy auto-`sort` run (that path calls
`post_merge_wav_(S_clu, 0, P)` with `fMerge=0` and ignores `nClu_merge`). To pick up the
fix in an open GUI session: `clear functions`, then click **Merge auto** again.

- Modified: `matlab/irc.m`.
