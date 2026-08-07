# PLAN — optimizing the HIGH / HIGHEST headroom post-merge modes

> **REVIEWED 2026-08-06 — this document was substantially corrected.** Four independent read-only
> reviewers checked the original against source under the constraint *"no breaking of existing
> functionality or logic"*. **Five load-bearing claims were wrong**, two proposed changes would have
> silently altered merge behaviour while being labelled "bit-identical", and the original §7.3
> go/no-go gate is not executable on the production mode. What follows is the corrected plan.
> §"What the review overturned" records the errors so nobody re-derives them.

Status: **proposal only, nothing implemented.** Scope: the modes rated HIGH or HIGHEST in
`ironclust_post_merge_modes` (mode **3 excluded by request**) — i.e. modes **1, 8/9/10, 11, 12, 13, 17**.

All line references are `matlab/irc.m` unless a file is named. **No timings have been measured** —
every "×N" is an *operation count*. Establishing the timings is now item **P0**, because the
original plan's assumption that they already existed is false.

## Verified configuration

Read from `260324_afm18349_g0_tcat.imec0.ap_irc_all_full.prm`, the production recording:

`post_merge_mode = 17`, `vcCluster = 'isosplit'`, `fParfor = 0`, `maxWavCor = 0.985`,
`spkLim = [-6 11]`, `min_count = 50`, `knn = 50`, `frac_shift_merge = 0.15`,
`maxDist_site_um = 60`, `nTime_drift = 16`, `step_sec_drift = 60`, `nWorkers_clust = 8`,
`nSites_fet = 9`, `duration_file = 5267.53 s`. Measured on the `_jrc.mat`: **nClu = 661**,
17.6 M spikes, 16.88 M assigned.

Consequences: **`numel(viShift) = 5`** (`ceil(17·0.15/2)=2` → `-2:2`). `nDrift` on the
`post_merge_knn1` fallback path is `ceil(5267.53/60) = 88`. `miKnn` is **50**×nSpk int32 (≈3.5 GB).
`post_merge_mode0 = [17,4,12,15]` is consumed only inside `postCluster_` (`:11831`), which this
sort skips — a red herring.

---

## ⚠ `irc.m` line numbers shifted +112 (2026-08-06)

`S_clu_merge_small_` was inserted at `irc.m:4461`, so **every `irc.m` reference below past line 4438
is now ~112 lines low**. References in the standalone files (`clu_wave_similarity_paged.m`,
`post_merge_knn1.m`, `post_merge_knnwav.m`) are unaffected. Current anchors — navigate by function
name, not by the numbers in the prose:

| Function | Was | Now |
|---|---|---|
| `S_clu_wavcor_` | 18666 | **18778** |
| `waveform_similarity_clu_` | 32466 | **32578** |
| `templateMatch_post_` | 32679 | **32791** |
| `post_merge_local_` | 32709 | **32821** |
| `post_merge_similarity_cc_` | 32723 | **32835** |
| `templateMatch_post_burst_` | 32749 | **32861** |
| `graph_merge_` | 32899 | **33011** |

The five `find(S_clu.viClu == iClu)` sites are now `irc.m:4189` (`featureMatch_post_`), **32617**
(`waveform_similarity_clu_`), **32909** (`templateMatch_post_burst_`), **33031** (`graph_merge_`),
plus `clu_wave_similarity_paged.m:30` and `post_merge_knnwav.m:49`. `post_merge_classix.m:90` has
the same pattern.

Note `matlab/FIND_OPTIMIZATION_ANALYSIS.md` (2025-11-19) already flagged this defect class and
estimated "10-30 seconds (1.5-4.5% total runtime)". The measurement below shows that estimate is
**low** for the mode-17 path: phase 1 alone is 59.5 s.

## 0a. MEASURED (2026-08-06) — P0 is done, and it re-ranks everything

Instrumentation added to `clu_wave_similarity_paged.m` (phases 2/3 timed, the dead `t_func` at
`:13` now read, plus pair counters). Run on the production recording, mode 17, nClu = 661,
17.6 M spikes:

```
Phase 1  Finding spike indices : 59.5s   (65.7%)
Phase 2  Paged loading         : 20.4s   (22.5%, 14 pages)
Phase 3  Pairwise similarity   :  9.8s   (10.8%)
                          total: 90.5s
nClu=661 nDrift=16 nShift=5
pairs: 187,647 reached, 1,036 shared a site (0.55%)
```

**Verdict: drop the phase-3 work; promote the phase-1 fix.**

1. **Phase 3 is 10.8% of the kernel and ~2.6% of `post_merge_`** (the full in-memory `post_merge_`
   measured 370 s; this kernel is 90.5 s of it). §0's D1-D4 and worklist items P3/P4/P6 all target
   phase 3. Removing it *entirely* would be invisible. **These items are no longer worth their
   risk** and are demoted below.
2. **D1 is measurably nothing.** Only **0.55%** of pairs pass the `isempty(viSite12)` guard, so
   `mr2_` is evaluated 1,036 times, not 187,647. The original "~250× reduction" assumed every pair
   reached it. `intersect` (D2) does run all 187,647 times and is the bulk of the 9.8 s — but 9.8 s
   is the whole budget.
3. **The real cost is phase 1 at 65.7%**, which is `find(viClu_spk == iClu)` at `paged.m:30` —
   defect **D5**, previously ranked P5. At 661 × 17.6 M that is ~11.6 G comparisons per sort.
   `S_clu.cviSpk_clu` already holds exactly these lists (`post_merge_knn1.m:40` is the in-tree
   precedent). **This is now the only optimization worth doing here.**

Also confirmed on real data: `mrDist_clu` returns **41,643 NaN** ≈ 63 whole columns, i.e. ~63
clusters have **no kept drift bins** and hence `ctrWav_clu{i} = zeros(nT,nC,0)`. The original plan's
"precompute `cmr_norm{i}` for all clusters" would have called `reshape(x,[],0)` on these and
**errored** — the guard requirement in §0 is not hypothetical.

Not yet measured: `waveform_similarity_clu_` (mode 1) has no pairwise timer, because adding one
means editing `irc.m`, which invalidates an open curation GUI's callbacks. Mode 1 is not the
production mode; defer until `irc.m` is safe to touch.

### P1 IMPLEMENTED AND VERIFIED (2026-08-06)

`clu_wave_similarity_paged.m:30` now reads `S_clu.cviSpk_clu{iClu}` with a `numel >= nClu` guard
and a `find()` fallback. Measured on the production recording, same MATLAB session conditions:

| | before | after |
|---|---|---|
| Phase 1 | 21.2 s | **12.2 s** (−42%) |
| Phase 2 | 7.6 s | 7.3 s |
| Phase 3 | 2.0 s | 1.7 s |
| kernel total | 31.2 s | **21.6 s** (−31%) |

`isequaln(mrDist_clu_old, mrDist_clu_new) = 1`, decision matrix identical, same 41,643 NaN and same
240 pairs ≥ `maxWavCor`. **Bit-identical, as required.**

Caveat on absolute timings: two runs of the *unmodified* code gave 90.5 s and 31.2 s total
(cold vs warm page cache, and memory pressure from a preceding test in the same process). The
**ratios** are the robust finding — phase 1 was 65.7% and 67.9% of the kernel in those two runs.
Compare like-for-like runs only; the 31.2 → 21.6 s pair above is like-for-like.

Phase 1 is still the largest term at 12.2 s (56%). The residual is the per-drift inner loop
(`unique`, `mode`, `subsample_vr_`, `miKnn` indexing), not the removed scan. Phase 2 (7.3 s, 34%) is
now the second target and is unanalysed.

### Phase 2 MEASURED (2026-08-06) — do not optimize it

Sub-timers added to the paging loop:

```
phase2 breakdown: io 5.9s | find 1.0s | group 0.4s | sum 1.5s | rows 1,963,996 (14 x 661 scans)
```

**65% of phase 2 is disk I/O** on the 13 GB `_spkwav.jrc` — irreducible without redesigning the
paging strategy. The `find(miSpk_drift_clu1(:,3) == iClu)` at `paged.m:91`, flagged in §0 as an
O(nLoads·nClu·rows) defect, costs **1.0 s**. Grouping rows by cluster once per page (`vi2cell_`-style,
or a stable `sort` + `cumsum` so per-cluster row order stays ascending and matches `find`) would
recover ~0.9 s of a ~26.7 s kernel — **3.4%**. Real defect, cheap fix, **not worth the regression
risk** on a kernel that is now verified bit-identical. Left in place deliberately.

### Part A (`min_count` enforcement) VERIFIED END-TO-END (2026-08-06)

Full in-memory `post_merge_` on `260324_afm18349_g0_tcat.imec0.ap_irc_all.prm` (661 clusters in,
nothing saved), run twice with identical results. Control = `fEnforce_min_count = 0`.

| | OFF (control) | ON (`fEnforce_min_count=1, fDiscard_count=0`) |
|---|---|---|
| `nClu` | 498 | **430** (68 absorbed) |
| assigned spikes | 16,875,724 | 16,875,718 |
| `min(vnSpk_clu)` | **8** | **61** |
| clusters `< min_count` (50) | **68** | **0** |
| per-cluster fields sized to `nClu` | ✓ (42 fields) | ✓ (42 fields) |
| `all(viClu(cviSpk_clu{i}) == i)` | ✓ bad=0 | ✓ bad=0 |

```
S_clu_merge_small_: absorbed 68/498 clusters (<50 spikes) into nearest,
1221 spikes moved; 0 left (no cluster within 60 um)
```

**Spike conservation is an invariant of `S_clu_merge_small_`, not of the pipeline.** Called
standalone on the OFF result it is exact: `16,875,724 -> 16,875,724`, `nClu 498 -> 430`. The −6
end-to-end delta is `S_clu_refrac_`, which runs *after* the new call site: absorbing a small
cluster into its neighbour puts formerly-separate spikes in one unit, exposing new refractory
violations (945 removed with the flag on vs 939 off). Do not write the pipeline-level equality as
an assertion — it is false by design.

### Where the time actually is — stop optimizing this kernel

After D5, the mode-17 kernel is ~22-27 s. The full in-memory `post_merge_` measured **370 s**, of
which "Calculating cluster mean waveform" (`S_clu_wav_`, called twice via `post_merge_wav_` and
`S_clu_update_wav_`) was **83.7 s + 144.5 s = 228 s (62%)**.

So the entire merge kernel — the subject of this whole plan — is **~7% of `post_merge_`**, and the
remaining optimizable slice inside it is a fraction of that. **If end-to-end `irc auto` time is the
goal, `S_clu_wav_` is the target, not this file.** That is a separate investigation and is out of
scope here.

> **UPDATE (2026-08-06): that investigation was carried out, and it paid.** `S_clu_wav_`'s cost is
> almost entirely its two per-cluster median loops — the `get_spkwav_` loads measure 0.0 s on the
> second call, because the data is already resident. Between `post_merge_`'s two `S_clu_wav_` calls
> only `S_clu_refrac_` changes membership, and only for 13 of 430 clusters. Making the second call
> incremental cut `post_merge_` from **247 s to 179 s (−27.5%)** with byte-identical output.
> It required first fixing `S_clu_sort_`, which reordered clusters through a hand-maintained
> seven-name list that omitted every waveform and quality field — harmless in `post_merge_` (the
> full recompute overwrote it) but saved straight to `_jrc.mat` by `import_ksort_`. Commits
> `2ad7efb` and `b75dee2`; full write-up in `logs/ironclust_post_merge_followup_2026-08-06.md` §4.2
> and §4.3.
>
> **UPDATE (2026-08-07): the S_clu_wav_ thread is closed and this plan is superseded.** A fourth
> change (`6072165`, `nSpk_max_clu_wav` — an opt-in, default-off cap on `clu_wav_`'s per-cluster
> median) took `post_merge_` from 179 s to **113 s, −54% against the 247 s baseline**, clustering
> byte-identical at every step. The whole chain was then closed out with one complete `irc sort`
> on a 600 s trim — the first time either new parameter went through detect, save, and the `.prm`
> round-trip rather than an in-memory replay. That test also surfaced and fixed an **unrelated
> pre-existing defect that made `irc detect` fail with `fGpu = 1`** (DI-17's `int64` is not
> supported by gpuArray; followup §6.2).
>
> **The largest remaining item is no longer in this plan's scope**: `post_merge_wav4_`'s pair loop
> at 20.7 s, 57% of which is one discarded distance matrix that can be column-blocked
> bit-identically. Everything in the re-ranked worklist below is either done or was measured out.
> Read followup §9 before picking anything up from here.

Timing caveat: absolute numbers vary 2-3x with page-cache state (unmodified code measured 90.5 s and
31.2 s total on different runs). Only compare like-for-like runs; the ratios are stable.

### Re-ranked worklist (supersedes §6)

| P | Item | Why |
|---|---|---|
| **P1** | D5: `find(viClu_spk == iClu)` → `cviSpk_clu` at `paged.m:30` (also `knnwav.m:49`, `irc.m:32505`, `:32797`, `:32919`) | **65.7% of the kernel.** Needs a sync precondition + `numel(cviSpk_clu) >= nClu` guard |
| **P2** | E1 `accumarray` (`post_merge_knn1.m:54`) + cast + clamp | Unmeasured (mode 11 is not in use here), self-contained, still sound |
| **P3** | E3 slice-fusion (`post_merge_knn1.m`) | Scaling fix, not speed |
| — | D1/D2/D3/D4 hoisting and `parfor` (old P3/P4/P6) | **Dropped.** ≤10.8% of the kernel, ~2.6% of `post_merge_`, and `logs/investigation_maxSpk_persite_clust.md:46-49` measured `fParfor=1` as a 2.6-3.2× *slowdown* here |
| — | Phase 2 paged loading (20.4%) | **Analysed — dropped.** 65% is disk I/O; the `paged.m:91` defect is 3.4% of the kernel. See "Phase 2 MEASURED" above |
| — | Phase 3 pairwise similarity (10.8%) | **Dropped.** 1.8-2.3 s measured. Also strictly blocked behind phase 2: `ctrWav_clu` is accumulated across *all* pages (`paged.m:110` inside `for iLoad`), so no cluster's template is complete early and phase 3 cannot start before the last page |

For context, the dominant cost in `post_merge_` overall is neither of these: "Calculating cluster
mean waveform" ran 83.7 s + 144.5 s = **228 s of the 370 s** total. If end-to-end `irc auto` time is
the actual goal, `S_clu_wav_` is the place to look, not the merge kernel.

## 0. What the review overturned

| # | Original claim | Reality | Consequence |
|---|---|---|---|
| 1 | D1: `mr2_` normalisation is O(nClu²); "~250× reduction" | `if isempty(viSite12), continue;` precedes `mr2_` at **all four** sites (`:32641`/`:32642`, `:32866`/`:32867`, `knnwav:168`/`:169`, `paged:116`/`:117`). Author comments at `:4009-4013` and `:32692-32694` state that same-site pairs are "~never set" | D1's real saving is single-digit ×. **D2 (`intersect`) is the actual quadratic term.** The ranking rationale was inverted |
| 2 | E3: phase 2 "only reduces `trDist_clu` to `max` over drift" | `post_merge_knn1.m:69` computes `mr2 = mr1 ./ vr1` — a ratio to the **self-overlap row** — *before* `max(...,[],2,'omitnan')` at `:70` | Implemented as written it converts a normalised ratio criterion into an absolute-overlap one. At `out_in_ratio_merge = 1/8` → **mass over-merging** |
| 3 | `parfor` on the pairwise loop is "~43 MB broadcast, genuinely safe" | `S_clu.nClu` is read *inside* the loop (`:32638`, `knnwav:165`, `:32863`). MATLAB has no field-level struct slicing → **the entire `S_clu` broadcasts**, `miKnn` included | Would OOM. Hoisting `nClu` is a hard prerequisite. `paged.m:19` is the only already-clean site |
| 4 | §7.3 "the existing prints already split the phases" | `paged.m:13` assigns `t_func = tic` and **never `toc`s**; phases 2/3 are untimed. `:32685`'s timer wraps the whole `waveform_similarity_clu_` call at `:32687` | **The go/no-go gate was not executable.** Instrumentation is now P0 |
| 5 | `S_clu_assert_synced_` as a precondition | `:20524` "Report (do NOT fix, do NOT gate)"; `:20540` "Never throws" | It cannot gate anything. "It would surface the desync" was false |

Further corrections:

- **`cmr_norm_shift` is pure waste.** `mr1_` is already computed once per `iClu1` (`:32635`) —
  O(nClu). Precomputing it saves **zero** operations and costs ~225 MB at nClu = 500 with
  `numel(viShift) = 5`. Dropped.
- **Mode 16 gains nothing.** `post_merge_local_` passes a non-empty `mrDist_clu` (`:32715`) into
  `templateMatch_post_`, so the `isempty` short-circuit at `:32686` skips the kernel.
- **Mode 13 cannot join a shared helper.** Its inner loop computes three products and a three-way
  max (`:32871-32874`), not one. And since `mr1b_` is broken, a *clean* helper changes its output.
- **A shared helper introduces a silent mode substitution.** `knnwav.m`/`paged.m` reach `irc.m`
  locals only via `irc('call',…)` → `test_`, whose catch swallows everything and returns `[]`
  (`:21477-21480`, `:21497`). For mode 17 that means `mrDist_clu = []` → `isempty` at `:32686`
  fires → **mode 17 silently becomes mode 1**, loading the full `tnWav_spk`, with only a
  `disperr_` line in the log.
- **`mlSite_clu` cannot represent site 0**, which `viSite_clu1` can contain (`mode` at `:32552`)
  and which `intersect` currently keeps.
- **Any precompute must carry the `isempty` guard.** `ctrWav_clu{i}` can be `zeros(nT,nC,0)`, and
  `reshape(x,[],0)` **errors**. `paged.m:142-147` calls this "common with many small clusters from
  per-site clustering" — i.e. this exact configuration.
- **P1's snippet errors on real data** — needs `double()` (`viClu` is int32, `:7637`) and a range
  clamp. Copy `:20552-20553` verbatim.
- **The `find(viClu==iClu)` defect has five sites, not three** — add `:32797` and `:32919`.
- **`graph_merge_` is unreachable here** (only caller `:3997`, mode 4), and its `parfor` is on the
  *inner* loop, re-broadcasting `cm_miSpk_knn` once per outer iteration.
- **In-repo measurement contradicts the parfor item:**
  `logs/investigation_maxSpk_persite_clust.md:46-49` measured `fParfor = 1` as a **2.6-3.2×
  slowdown** on this machine (BLAS oversubscription). The kernel's hot op is a GEMM.
- **New defect, previously unlisted:** `paged.m:91` `find(miSpk_drift_clu1(:,3) == iClu)` sits
  inside `for iClu` (`:85`) inside `for iLoad` (`:72`) — O(nLoads·nClu·rows), in the production mode.

**Disconfirmed hypotheses** (do not re-raise): `viSite_clu1` is a legal `parfor` temporary — it is
assigned from `cviSite_clu{iClu1}` at `:32633` before `:32636` reassigns it. And P1's `accumarray`
identity holds under duplicates, `viClu <= 0`, and empty input.

---

## 1. The shared kernel

Modes **1, 12, 17** end in an equivalent pairwise loop (**mode 13 is structurally different** —
see above):

| Mode | Location |
|---|---|
| 1 (and 8/9/10/14/15 via `templateMatch_post_`) | `waveform_similarity_clu_` **32632-32651** |
| 12 | `post_merge_knnwav.m` **156-178** |
| 17 | `clu_wave_similarity_paged.m` **107-126** |

```matlab
for iClu1 = 1:S_clu.nClu
    viSite_clu1 = cviSite_clu{iClu1};                              % :32633  <-- assigned FIRST
    if isempty(viSite_clu1), continue; end
    mr1_ = fh_norm_tr(shift_trWav_(ctrWav_clu{iClu1}, viShift));   % :32635  already O(nClu)
    viSite_clu1 = repmat(viSite_clu1(:), numel(viShift), 1);       % :32636  legal temporary
    vrDist_clu1 = zeros(S_clu.nClu, 1, 'single');
    for iClu2 = iClu1+1:S_clu.nClu                                 % :32638  <-- S_clu read here
        viSite2  = cviSite_clu{iClu2};
        viSite12 = intersect(viSite_clu1, viSite2);                % :32640  D2 - the real O(nClu^2)
        if isempty(viSite12), continue; end                        % :32641  fires for most pairs
        mr2_ = fh_norm_tr(ctrWav_clu{iClu2});                      % :32642  D1 - reached rarely
        for iSite12_ = 1:numel(viSite12)
            mrDist12 = mr2_(:, viSite2==iSite12)' * mr1_(:, viSite_clu1==iSite12);   % D3
            vrDist_clu1(iClu2) = max(vrDist_clu1(iClu2), max(mrDist12(:)));
        end
    end
    mrDist_clu(:, iClu1) = vrDist_clu1;                            % :32649  column-sliced
end
```

- **D2 — `intersect` per pair.** Runs *before* the guard, so genuinely O(nClu²), each call sorting
  internally. **This is the target.** `irc2.m:3044` already carries the cheap in-tree mitigation:
  `if ~any(ismember(viSite_clu1, viSite2)), continue; end` before the `intersect`.
- **D1 — `mr2_` inside the inner loop.** Real but small: reached only for site-sharing pairs.
  Worth hoisting once D2 is done, with the `isempty` guard above.
- **D3 — the `==` scans.** Note they run against *different* vectors: `viSite_clu1` is the
  **repmat'd** length-`nDrift·nShift` vector indexing the **shifted** `mr1_`, while `viSite2` is
  un-repmat'd and indexes the **unshifted** `mr2_`. Two index sets, not one.
- **D4 — column-sliced output**, so `parfor`-shaped *provided* `nClu` is hoisted out of `:32638`.

Mode 17 additionally accumulates in **double** (`paged.m:89` has no class argument) where modes
1/12 use `single` — a shared helper that normalises the class would change mode 17's output.

---

## 2. Modes 8 / 9 / 10

Pure compositions (**3991-3993**): `8 = templateMatch_post_(post_merge_knn1(…))`,
`9 = post_merge_knn1(templateMatch_post_(…))`,
`10 = post_merge_knn1(templateMatch_post_(post_merge_knn1(…)))`.
**No separate work** — they inherit §1 and §3. Mode 10 runs `post_merge_knn1` twice.

---

## 3. Mode 11 — `post_merge_knn1.m`

- **E1 — `ismember` innermost (line 54).**
  `vr_ = cellfun(@(y)mean(ismember(viSpk_out11(:), y)), S_clu.cviSpk_clu(viClu2))` → replace with a
  single `accumarray` pass. The identity holds exactly (duplicates counted with multiplicity by
  both forms; `viClu<=0` excluded from both numerators and retained in both denominators; empty
  input gives `NaN` both ways). **Must** copy the cast and clamp from `:20552-20553`:
  ```matlab
  vlOk    = viClu_out >= 1 & viClu_out <= nClu;
  vnCount = accumarray(double(viClu_out(vlOk)), 1, [nClu 1]);
  ```
  Without the clamp `accumarray` **errors** where `ismember` silently tolerated; without
  `double()` it errors on the int32 subscript. `viClu2` holds ~9 candidates
  (`nSites_fet = 9`), so this is ~10× on that term, not the O(n) framing originally claimed.
- **E2 — `find(ismember(viSpk1, cviSpk_drift{iDrift}))` (line 45).** Substituting
  `viDrift_spk(viSpk1) == iDrift` is exact — `:26809` builds `cviSpk_drift` as a contiguous
  disjoint partition and `:26811` is its exact inverse. **But `S_drift` does not exist on this
  sort** (`S_clu_from_labels_` never creates it; verified `has S_drift = 0` on the real
  `_jrc.mat`), so `post_merge_knn1.m:15-19` catches and `:22-30` synthesises its own bins. The fix
  must derive the drift-id vector from whichever `cviSpk_drift` is in play, and must not assume
  orientation (`:28` yields row vectors, `drift_similarity_` column).
- **E3 — `trDist_clu = nan(nClu, nDrift, nClu)` (line 36).** **Respecified.** Do *not* fuse the
  reduction — phase 2 is a max of a **ratio**, not of raw values. Instead fuse the **slice**:
  allocate `mr1 = nan(nClu, nDrift)` inside the phase-1 `for iClu` loop, fill at `:55`, and paste
  `:66-70` **verbatim** at the bottom of that iteration. Memory drops by a factor of **nClu**
  rather than nDrift, and bit-identity is structural rather than argued. Keep the `nan` seed, keep
  `'omitnan'`, and do **not** guard the `vr1 == 0` division — `Inf` is load-bearing.
  The dead `case 1` branch (`:71-78`) reads individual drift bins via `ind2sub`; preserve it by
  commenting rather than deleting, per the repo's code-preservation rule.

---

## 4. Mode 12 — `post_merge_knnwav.m`

Pairwise (156-178) covered by §1. Template build (48-143) carries the `find(S_clu.viClu == iClu)`
defect at **line 49** — and, unlike `:32507`, has **no `isempty` guard**, so it already crashes on a
0-spike cluster. The `switch 3` (`:59`) and `switch 1` (`:97`) constant selectors are the author's
A/B scaffolding: **leave them.** Note `:159` computes `mr1_` and `:161` immediately overwrites it —
the same idiom as mode 13's bug, and evidence that it is house style rather than intent.

---

## 5. Mode 17 — `clu_wave_similarity_paged.m`

Phase 3 (107-126) covered by §1. **Phases 1-2 are the good design** — the only mode that pages from
`_spkwav.jrc` (`load_spkwav_`, 163+) instead of holding `tnWav_spk` whole; its `for iClu` at `:85`
carries `ctrWav_clu` across pages, so it is *not* trivially parallel. Two defects remain:
`find(viClu_spk == iClu)` at **line 30**, and — unlisted until this review — **line 91**
`find(miSpk_drift_clu1(:,3) == iClu)` nested inside both `for iClu` (`:85`) and `for iLoad`
(`:72`), i.e. O(nLoads·nClu·rows).

### The cross-cutting constraint: `tnWav_spk` cannot be broadcast

Modes 1, 12, 13 (and 16, `:32714`) call `get_spkwav_` and hold the entire tensor. Order of
magnitude here: 18 samples × ~20 channels × 17.6 M spikes × int16 ≈ **12 GB**. Under `parfor` a
broadcast variable is copied **per worker**. So `parfor` on the **pairwise** phase is viable
(`ctrWav_clu` is ~43 MB) but on the **template-build** phase is **blocked** until those modes adopt
mode 17's paged loader — explicitly out of scope.

---

## 6. Prioritized worklist

| P | Item | Modes | Bit-identical? | Notes |
|---|---|---|---|---|
| **P0** | **Instrumentation only** — `toc` for `paged.m` phases 2/3 (fix the dead `t_func` at `:13`), a pairwise timer in `waveform_similarity_clu_`, and prints of `nClu`/`nDrift`/`numel(viShift)` | — | yes, no arithmetic | **Prerequisite for every ranking decision below.** Without it the pairwise phase in the production mode is unmeasurable |
| **P1** | E1 `accumarray` + cast + clamp (`post_merge_knn1.m:54`) | 8/9/10, 11 | yes | Independent file; can proceed in parallel |
| **P2** | E3 **slice-fusion** | 8/9/10, 11 | yes, structurally | Scaling fix; needs no pool |
| **P3** | D2 only (site-0-safe), applied to **`clu_wave_similarity_paged.m` alone** | 17 | yes, `isequaln` | Production mode, standalone file, `nClu` already hoisted at `:19`, no `S_clu` in the loop. Smallest blast radius |
| **P4** | Replicate P3 to `:32632-32651` and `knnwav.m:155-178` — **one commit each** | 1, 8/9/10, 12, 14, 15 | yes | `irc.m` backs the **default** mode; never bundle |
| **P5** | D5 `cviSpk_clu` swap (5 sites) + `paged.m:91` | 1, 12, 17 | no, on a desynced file | Needs an explicit sync precondition and a `numel(cviSpk_clu) >= nClu` guard |
| **P6** | `parfor` the pairwise loop — **only if P0's numbers justify it** | same as P3/P4 | must prove serial == parallel | Preconditions: hoist `nClu`; probe whether unassigned sliced-output columns keep their pre-loop `NaN`; the serial fallback must re-init the output; measure a `maxNumCompThreads`-capped serial control |
| — | Mode 13 `mr1b_` (`:32856`/`:32860`) | 13 | **drop, not defer** | `mr2b_`/`mrDist12b` (`:32868`/`:32873`) are **live**, so only one of two burst terms is dead. "Fixing" it adds a term to a `max` → can only *increase* merges, in a mode with no user, no test recording and no validation data |
| — | `graph_merge_` `fParfor` gate | 4 | yes | Unreachable in this config. Last, alone, or skip |
| — | Template-phase `parfor` | 1, 12, 13 | — | **Not recommended.** Blocked by the `tnWav_spk` broadcast (§5) |

**A `try/catch` cannot catch a `parfor` classification error** — that is raised at parse time, and
the statement is parsed even when `fParfor = 0`. A mis-classified `parfor` in
`waveform_similarity_clu_` would break the **default** mode for every user. Classification must be
provably correct at write time; the fallback buys nothing.

**Do not extract a shared helper first.** Fix one call site in place, prove `isequaln`, then
replicate one commit per file. If a helper is extracted at all it belongs in its **own `.m` file on
the path**, never inside `irc.m` — see the `irc('call')` error-swallowing path in §0.

---

## 7. Verification

**P1-P4 must produce bit-identical output.** They reorder and hoist; they do not change arithmetic.
Any difference is a bug, not a tolerance issue.

1. **Measure first (P0).** Record the phase split on the production `.prm` *before* deciding
   whether P3/P4/P6 are worth doing. If the pairwise phase is not a meaningful share, drop them and
   re-rank.
2. **Golden-output harness.** In memory on the existing `_jrc.mat`, assert
   `isequaln(mrDist_clu_old, mrDist_clu_new)`. Use `isequaln`, not `isequal` — the matrix is
   NaN-dominated by design (`:32631`). Add a second tier that asserts the *decision* is stable:
   `isequal(old >= P.maxWavCor, new >= P.maxWavCor)`.
3. **Real recording, time-trimmed.** `260324_afm18349_g0_tcat.imec0.ap_irc_all_full.prm`
   (`vcCluster = 'isosplit'`, `post_merge_mode = 17`, nClu = 661). Include at least one cluster
   whose drift bins were all dropped — that is the only input exercising the `reshape(x,[],0)`
   crash path.
4. **P6 additionally:** assert serial == parallel, and confirm no pool is created when
   `fParfor = 0` (`gcp('nocreate')` before and after).

## 8. Out of scope

Mode 3 (excluded by request). Template-phase parallelisation (§5). Porting modes 1/12/13 to the
paged loader. Any change to `post_merge_mode` defaults. The mode-13 `mr1b_` bug (dropped, see §6).
