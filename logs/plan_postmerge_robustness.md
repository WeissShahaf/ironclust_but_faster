# Plan: post-merge / per-site robustness hardening (empty & degenerate clusters)

**Date:** 2026-06-26
**Branch:** rewind
**Context:** Per-site label clustering (`vcCluster='isosplit'`) with the spike cap
(`maxSpk_persite_clust`) produces *many* small clusters (1081 in one run vs a handful
under global DPC). Code that assumed a few large, non-empty clusters now hits empty /
single-spike / gappy-label edge cases. Four confirmed crashes on the live sort path are
already fixed; this plan covers the remaining **latent** robustness items found by a
4-agent review of the post-merge and per-site paths.

---

## Final state — all 10 fixes applied (working tree, branch `rewind`, uncommitted)

`checkcode` clean on both edited files (`irc.m`, `cluster_classix_.m`): 0 syntax-class
messages, all try-blocks have catches, no new warnings on edited lines. Every change is
either a crash fix on a degenerate input or an identity-for-healthy guard — none alters
the output of a healthy run of any clustering method.

**A. Confirmed live-path crashes (the isosplit + cap run that was failing):**

| # | Location | Bug |
|---|----------|-----|
| 1 | `clu_wave_similarity_paged.m:148` | int32/double mix in `cell2mat` (all-drift-dropped cluster) |
| 2 | `irc.m:4339` | `median(0×nPos)'` scalar-NaN shape (burst-emptied cluster) |
| 3 | `irc.m:4391–4392` | 1-spike sub-cluster → `1:0.5`=`[]` → `mode([])`=NaN → `miSites(:,NaN)` |
| 4 | `irc.m:7354` + `7373` | `mode(int32([]))` double/int32 non-uniform `arrayfun` |

**B. Planned hardening (this plan, a+b):**

| # | Location | Change |
|---|----------|--------|
| 5 | `irc.m:2433–2441` | **D1** — `unique` remap → contiguous labels in `S_clu_from_labels_` |
| 6 | `irc.m:2697` + `2785` | **D2a** — try/catch around per-site kNN (uncapped + capped) |
| 7 | `irc.m:2453–2461` | **D2b** — warn when `maxSpk_persite_clust < min_count` |

**C. Deferred items, applied under "only if it doesn't break other methods":**

| # | Location | Change / safety basis |
|---|----------|-----------------------|
| 8 | `cluster_classix_.m` | CLASSIX contiguity remap; `classix_out` never read downstream (grep-verified) |
| 9 | `irc.m:32394` | `correlogram_` empty-cluster-safe bin-max; int32-identical for non-empty |
| 10 | `irc.m:31150` + `31429` | 0-spike `continue` guards in `waveform_similarity_clu_` / `templateMatch_post_burst_` |

---

## Scope of this plan: a + b + c

- **(a) D1** — label-contiguity guard in `S_clu_from_labels_`.
- **(b) D2** — graceful kNN failure in the per-site loop + a cap-misconfig warning.
- **(c)** — review `S_clu_sort_` and `correlogram_` (outcome: no change; documented below).

## Implementation status (2026-06-26) — DONE

- **D1** ✅ `irc.m:2433-2441` — `unique` remap of positive labels in `S_clu_from_labels_`.
- **D2a** ✅ `irc.m:2692-2705` (uncapped `cluster_site_`) + `irc.m:2784-2799` (capped
  `cluster_site_capped_`) — try/catch around the kNN step with valid fallbacks.
- **D2b** ✅ `irc.m:2453-2461` — cap-below-`min_count` warning in `cluster_labels_persite_`.
- **(c)** ✅ reviewed, no required change; optional `correlogram_` guard applied (below).
- **Deferred items — now also applied (2026-06-26, "only if it doesn't break other methods"):**
  - **CLASSIX contiguity** ✅ `cluster_classix_.m` — same `unique` remap before `nClu`.
    Safe: `classix_out`/`classix_explain` are stored but **never read** anywhere in
    `matlab/` (grep-verified), so no label-value coupling; identity for dense labels.
  - **`correlogram_` guard** ✅ `irc.m:32394` — `max([int32(0); x(:)])` keeps the bin-max
    empty-cluster-safe and type-identical for non-empty clusters (all methods).
  - **0-spike twins** ✅ `irc.m:31150` (`waveform_similarity_clu_`) + `irc.m:31429`
    (`templateMatch_post_burst_`) — `if isempty(viSpk1), continue;`. No-op for healthy
    clusters; pre-initialized cells + the merge loop's `isempty` guard make it safe.
- **Verification:** `checkcode` clean on both `irc.m` (0 syntax-class) and
  `cluster_classix_.m` (0 syntax-class); all try blocks have catches; no new warnings on
  edited lines.

---

## (a) D1 — make `S_clu_from_labels_` robust to gappy labels

**Problem.** `S_clu_from_labels_` (irc.m:2423) assumes the positive labels in `viClu`
form a dense `1..nClu` set. It builds `icl` of length `nClu = max(viClu)` and at line
2468 does `S_clu.icl = icl(icl>0)`. If any label value in `1..max` has **zero** spikes
(a gap), that `icl` entry stays 0 and is dropped, so `numel(icl) < nClu` and every later
entry is shifted. Downstream `post_merge_wav2_` (irc.m:4651) asserts
`viClu(icl(iClu))==iClu` and indexes `icl(1:nCl)` → assert trip or out-of-range.

**Reachability.** The three shipped methods are contiguous-by-construction
(kmeans `EmptyAction='singleton'`, isosplit5 ends with `relabel_`, hdbscan maps to
`1..K`), so this is **latent today**. It becomes live for any label source that is *not*
guaranteed contiguous — notably **CLASSIX**, whose labels come from an external library
(`cluster_classix_.m:82` uses the same `icl(icl>0)` pattern standalone).

**Fix.** Relabel positive labels to a dense range at the top of `S_clu_from_labels_`,
preserving `0` = noise. Insert immediately after `viClu = int32(viClu(:));` (line 2432),
**before** `nClu` is computed (line 2434):

```matlab
viClu = int32(viClu(:));
% Make positive labels contiguous (1..nClu) so a gap in the input labels (possible
% from an external/custom fh_cluster, e.g. CLASSIX) can't create an empty cluster id
% that drops an icl entry below and misaligns icl with cluster numbers. 0 (noise) kept.
vlPos = viClu > 0;
if any(vlPos)
    [~, ~, vi1] = unique(viClu(vlPos));
    viClu(vlPos) = int32(vi1);
end
nSpk = numel(viClu);
nClu = double(max([0; double(viClu)]));
```

**Why byte-identical for shipped methods.** The assembly in `cluster_labels_persite_`
already emits labels as contiguous, ascending, offset blocks (`cumsum`). For an
already-dense ascending vector, `unique`'s third output maps each element to its own rank
→ identity remap → `viClu` unchanged → `icl`, `ordrho`, etc. identical.

**Risk.** Low. Only changes behavior when the input is gappy, which is exactly the
broken case. Touches cluster-identity numbering, so verify the post-merge assert path.

**Parallel spot (out of scope, note for later):** `cluster_classix_.m:82` builds `S_clu`
itself and does not call `S_clu_from_labels_`, so it needs the same guard independently
if CLASSIX is used. Flag only; not editing in this pass.

---

## (b) D2 — graceful per-site kNN failure + cap-misconfig warning

### D2a — wrap the per-site kNN step so one giant site can't kill the run

**Problem.** In `cluster_site_` (irc.m:2635) only `fh_cluster` is wrapped in try/catch
(2665–2671). The O(n²) kNN step `persite_knn_(X', knn, viSpk1)` (irc.m:2677) is **not**.
The parfor driver retries serially on any throw (irc.m:2583), but the **serial** loop
(irc.m:2589–2595) has no guard, so an OOM/throw on a huge *uncapped* site propagates out
and aborts the whole (multi-hour) sort. The design intends per-site graceful
degradation — the clustering throw already degrades to a single cluster; the kNN step
should too.

**Fix.** Wrap the uncapped kNN call (irc.m:2675–2678) in try/catch that emits a valid,
self-referential fallback (same shapes/types as a normal return):

```matlab
% --- per-site kNN graph + density (global indices) for post-merge ---
hT = tic;
try
    [miKnn1, vrRho1] = persite_knn_(X', knn, viSpk1);
catch ME
    fprintf(2, '\n\tsite (%d spikes) kNN graph failed (%s); self-referential fallback\n', n1, ME.message);
    miKnn1 = repmat(int32(viSpk1(:)'), knn, 1);   % each spike -> itself (valid global idx)
    vrRho1 = ones(n1, 1, 'single');
end
t_knn = toc(hT);
```

The capped path (`cluster_site_capped_`, kNN at irc.m:2758) is already bounded to
`m ≤ maxSpk` so OOM is unlikely; wrapping it too is optional and lower priority. Apply the
same try/catch there for completeness.

**Risk.** Low. Pure additive guard; the fallback matches the existing `n1==0` degenerate
shapes (`int32` knn-row, `single` rho). A degraded site yields meaningless post-merge for
its spikes, but the run completes instead of dying.

### D2b — warn when the cap is silently ignored

**Problem.** `cluster_site_:2655` activates the cap only when
`maxSpk >= max(2, min_count)`. If a user sets `maxSpk_persite_clust` **below** `min_count`
(30), the cap is silently dropped and every giant site runs fully uncapped — the exact
configuration meant to bound O(n²) instead removes the bound, with no message.

**Fix.** One-time warning in `cluster_labels_persite_`, after `min_count` is read
(irc.m:2512):

```matlab
maxSpk = get_set_(P, 'maxSpk_persite_clust', []);
if ~isempty(maxSpk) && maxSpk < max(2, min_count)
    fprintf(2, '\tmaxSpk_persite_clust (%g) < min_count (%d): cap ignored, sites run uncapped.\n', ...
        maxSpk, max(2, min_count));
end
```

**Risk.** None (diagnostic only).

---

## (c) Review of `S_clu_sort_` and `correlogram_` — outcome: NO CHANGE

Both run at the very end of `post_merge_` (irc.m:3905 and 3908) and were not in the
agent scopes. Reviewed here:

- **`S_clu_sort_` (irc.m:11293)** — only computes a sort permutation of
  `S_clu.(vcField_sort)` (e.g. `viSite_clu`) and reorders. `sort` tolerates NaN (sorts
  last); no `cell2mat`/reduction/empty-index hazard. **Safe.**
- **`correlogram_` (irc.m:32338)** — already hardened with a `nClu<2` guard
  (32346–32353). Its remaining risks (`max(cellfun(@max, cviTime_b_clu))` at 32355 →
  `max([])` → `cellfun` `UniformOutput` error on an empty cluster; and
  `P.mrSiteXY(S_clu.viSite_clu,:)` at 32358 → NaN index) only fire on a **gappy/empty**
  `viClu`. In the live path `viClu` is gap-free by the time `correlogram_` runs (3908):
  1. the merges that *can* create gaps are `templateMatch_post_` (3870, via
     `S_clu_map_index_`) and `post_merge_wav4_` (3902);
  2. `post_merge_wav4_` calls `S_clu_refresh_` with `fRemoveEmpty=1` (irc.m:4320), which
     drops empty clusters and compacts the numbering — this is the actual gap-free
     guarantee on the user's mode-17 + `fLabelClu` path;
  3. `post_merge_wav_` (3904) runs with `fMerge=0` so it doesn't re-merge; its duplicate
     removal goes through `S_clu_keep_`, which compacts;
  4. `S_clu_refrac_` (3906) then **retains ≥1 spike per cluster** — its removal loop
     (11353–11360) never drops index 1 (`diff`-based violations start at index 2) — so it
     cannot re-introduce an empty cluster.

  **Safe in the live path.** The safety is *conditional* on a compacting refresh
  preceding `correlogram_`; it is **not** intrinsic to `correlogram_` itself.

**Conclusion:** no required code change for (c). **Optional defense-in-depth** (recommended
but deferred): guard `correlogram_:32355` against empty clusters, e.g.
`max_time = max(cellfun(@(x)max([0;double(x(:))]), cviTime_b_clu))`, so a future reordering
that let a gappy `viClu` through would degrade gracefully instead of erroring. Listed under
Deferred below.

---

## Verification plan

1. **Static:** `checkcode irc.m` — expect clean (no new mlint warnings from the inserted
   try/catch / `unique` remap / `fprintf`).
2. **D1 identity (no regression):** the remap must be a no-op for the shipped contiguous
   methods. Inline check during a normal isosplit run — capture `viClu` immediately
   before the new block and assert `isequal(viClu_after_remap, viClu_before)`; expect true
   because the `cumsum`-offset labels are already dense & ascending (so `unique`'s ranks
   are the identity). Remove the temp assert after confirming.
3. **D1 gappy (the fix):** the realistic trigger is a label method that returns a gap.
   Rather than synthesize an `S0`, drive it end-to-end — run `vcCluster='classix'` (whose
   external labels aren't contiguity-guaranteed) and confirm `numel(S_clu.icl)==S_clu.nClu`
   after `S_clu_from_labels_`, and that `post_merge_wav2_`'s `assert(iCl==iClu)` (irc.m:4651)
   holds. (Pre-fix, a gap would shorten `icl` and trip that assert.)
4. **D2a:** confirm a normal run never enters the catch (no fallback message printed); the
   fallback only triggers on an actual kNN throw, so healthy runs are byte-identical.
5. **D2b:** set `maxSpk_persite_clust = 5` (< `min_count`=30) and confirm the one-time
   warning prints and the run proceeds uncapped (behavior otherwise unchanged).
6. **End-to-end:** re-run `irc sort` on the afm18349 prm (cap=10000). Expect it to clear
   `clu_wave_similarity_paged` → `templateMatch_post_` → `post_merge_wav4_` →
   `S_clu_refrac_` → `correlogram_` to completion.

## Risk notes

- **D1** is the only change that can alter cluster identity, and only for *gappy* input
  (the broken case). Callers pass freshly-assembled labels with no external cross-reference
  to the pre-remap values (the per-site drivers `cluster_kmeans_`/`_hdbscan_`/`_isosplit_`
  build `viClu` locally), so renumbering is safe. Healthy (dense) input → identity.
- **D2a/D2b** are purely additive (a guard + a diagnostic); neither changes a healthy run.

## Deferred / out of scope (recorded, not edited this pass)

- **CLASSIX standalone contiguity** — `cluster_classix_.m:82` builds `S_clu` directly with
  the same `icl(icl>0)` pattern and does *not* route through `S_clu_from_labels_`, so the
  D1 fix does not cover it. Apply the same `unique`-remap there if/when CLASSIX is used.
- **`correlogram_:32355` empty-cluster guard** — optional defense-in-depth (see (c)); only
  matters if a future change lets a gappy `viClu` reach `correlogram_` without a refresh.
- **0-spike index crash twins** — `waveform_similarity_clu_:31110` and
  `templateMatch_post_burst_:31388` (`viSpk1(vii1)` on an empty cluster). Unreachable after
  `S_clu_refresh_` guarantees ≥1 spike/cluster, and off the mode-17 path (those serve modes
  1/8/9/10/13/14). Defensive-only; a one-line `if isempty(viSpk1), continue; end` guard
  would harden them if those modes are ever exercised with per-site clustering.

## Rollback

Each change is an isolated, additive block (a remap, two try/catch wraps, one warning).
Revert individually with no cross-dependencies. None alters the output of a healthy run.
