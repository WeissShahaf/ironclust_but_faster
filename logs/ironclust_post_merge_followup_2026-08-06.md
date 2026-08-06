# IronClust `post_merge_` — follow-up to `ironclust_post_merge_modes` (2026-08-06)

Follows up on `ironclust_post_merge_modes.pdf` / `.drawio` / `.txt` (2026-08-06 10:05), which mapped
all 17 `post_merge_mode` algorithms with their parallelism, GPU use, and an **estimated**
"optimization headroom" column.

This document records what happened after that map was drawn: what was reviewed, what was actually
measured on a real recording, what was optimized, and — the larger part — **what was deliberately
not optimized and why**.

| | |
|---|---|
| Branch | `rewind` |
| Test recording | `E:\scratch\tmp\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_irc_all.prm` — 5267.53 s, 121.7 GB, 16.88 M spikes, 661 clusters |
| Config | `post_merge_mode = 17`, `vcCluster = isosplit`, `fParfor = 0`, `maxWavCor = 0.985`, `min_count = 50`, `nTime_drift = 16` |
| Method | Full in-memory `post_merge_` on the existing `_jrc.mat`. Nothing was ever saved; the user's sort is untouched. |
| Status | Changes are on disk, **not committed**. |

> **Note on the original document's line numbers — they are all stale.**
> Three functions and one call site were added to `irc.m`, shifting every anchor past line 4022.
> See the mapping table in §1.

---

## 0. Executive summary

1. **The headroom column was largely wrong, and measurement inverted its ranking.** The mode
   flagged `HIGHEST` (12, "textbook parfor target") and the pairwise `O(nClu²)` loops that the
   whole optimization effort was aimed at turned out to be **~7% of the merge kernel**. The real
   cost was an unflagged `find(viClu == iClu)` scan.
2. **One optimization was implemented and proven bit-identical**: replacing that scan with the
   `cviSpk_clu` cache. Merge kernel **31.2 s → 21.6 s (−31%)**; its dominant phase **−42%**.
3. **Everything else was measured and dropped**, with reasons recorded. Two changes originally
   labelled "bit-identical" would in fact have silently altered merge behaviour.
4. **The merge kernel is not where the time is.** It is **8%** of `post_merge_`. `S_clu_wav_`
   (`irc.m:12266`) is **69%**. Optimizing merge modes cannot materially change `irc auto` runtime.
5. **A separate, larger defect was found and fixed**: `min_count` was **never enforced** on
   label-based sorts. That is why clusters with 8 spikes survived a `min_count = 50` setting.

---

## 1. Line-number remap (the original document's anchors have moved)

`S_clu_merge_small_`, `get_cviSpk_clu_checked_` and `merge_small_verify_` were inserted at
`irc.m:4461`, plus one call site at `:4022` and in-place edits at three merge sites. The dispatch
`switch` itself did **not** move.

| Symbol | Original doc | **Current** | Δ |
|---|---|---|---|
| `post_merge_mode` dispatch `switch` | 3983-4005 | **3983-4005** | 0 |
| `maddist2_` (dead code, ungated `parfor`) | 4036 | **4041** (`parfor` at 4047) | +5 |
| `featureMatch_post_` (mode 2) | 4162 | **4167** (`for iSite` 4241; GPU 4247-4249) | +5 |
| `driftMatch_post_` (mode 3) | 32385 | **32583** | +198 |
| `waveform_similarity_clu_` (mode 1 kernel) | 32466 | **32664** | +198 |
| `templateMatch_post_` (mode 1) | 32679 | **32884** | +205 |
| `post_merge_local_` (mode 16) | 32709 | **32914** | +205 |
| `post_merge_similarity_cc_` (mode 15) | 32723 | **32928** | +205 |
| `templateMatch_post_burst_` (mode 13) | 32749 | **32954** | +205 |
| `graph_merge_` (mode 4) | 32899 | **33108** | +209 |
| `drift_merge_post_` (mode 5) | 33360 | **33572** | +212 |
| `post_merge_drift_` (modes 6/7) | 33464 | **33676** | +212 |
| `post_merge_cc_` (mode 14) | 33840 | **34052** | +212 |
| `S_clu_wavcor_` (common tail) | 18666 area | **18864** (`fGpu = 0` 18868; `fParfor` gate 18902; `parfor` 18907) | +198 |
| Common tail | 4018-4031 | **4018-4036** | new call at 4022 |

The deltas are monotonic and fully accounted for by the insertions — no function was nested or lost
(function count went 1039 → 1042).

---

## 2. What was DONE

### 2.1 A four-reviewer audit of the optimization plan

The plan in `logs/PLAN_post_merge_optimization.md` was reviewed by four independent read-only
reviewers, including a devil's advocate, under the constraint *"no breaking of existing
functionality or logic."* **Five load-bearing claims were overturned.** The two most dangerous:

- A proposed "bit-identical" fusion in `post_merge_knn1.m` **was not bit-identical**. Line 69
  computes `mr2 = mr1 ./ vr1` — a ratio against the self-overlap row — *before* the
  `max(..., [], 2, 'omitnan')`. Fusing the `max` into the loop converts a normalized-ratio
  criterion into an absolute one. At `out_in_ratio_merge = 1/8` that means **mass over-merging**.
- A proposed `parfor` was described as safe on a "~43 MB broadcast". In fact `S_clu.nClu` is read
  *inside* the loop, and MATLAB has no field-level struct slicing, so **the whole `S_clu`
  broadcasts** — including `miKnn`, 50 × nSpk int32. It would have run out of memory.

Also established: a `parfor` classification error **cannot be caught by `try/catch`** — it is
parse-time, and the statement is parsed even when `fParfor = 0`. A mis-classified `parfor` in
`waveform_similarity_clu_` would therefore break the **default** merge mode for every user, not
just those who enable parallelism.

### 2.2 Root-caused the sub-`min_count` clusters

**Symptom:** clusters with 1-10 spikes survive a sort configured with `min_count` between 30 and 300.

**Cause:** `min_count` is enforced only inside `postCluster_`, which is the sole caller of both
count filters (`dpclus_remove_count_`, `S_clu_remove_count_`). `irc.m:3964` reads

```matlab
if fPostCluster && ~fLabelClu, S_clu = postCluster_(S_clu, P); end
```

so for every **label-based** clustering method — `isosplit`, `isosplit5/6`, `kmeans`, `hdbscan`,
`classix` — `postCluster_` is skipped and **`min_count` is never applied at all**. Nothing
downstream replaces it: `cluster_site_` gates on the *site's* spike total, not per label;
`S_clu_from_labels_` applies no count filter; `S_clu_remove_empty_` removes only *empty* clusters.

It is not a merge bug — merging only grows clusters. It looks post-merge because `S_clu_refrac_`
runs last and only ever shrinks clusters.

**Second finding:** `fDiscard_count` — documented in `default.prm`, `rhs32_template.prm`,
`sample_sample_merge.prm` and the user's own `.prm` as *"Discard cluster under minimum count. set
to zero to absorb to the nearest cluster"* — **was read by no `.m` file in the repository.** A dead
parameter promising exactly the needed behaviour.

### 2.3 Implemented the fix

`S_clu_merge_small_` (`irc.m:4461`), called at `irc.m:4022` before `post_merge_wav_` so every
per-cluster field downstream is rebuilt against the final cluster set. It absorbs each
sub-`min_count` cluster into the **nearest surviving cluster by centroid distance**, capped at
`maxDist_site_um`. Targets are drawn only from clusters that already pass the threshold, so there
is no chaining and the result is order-independent. A cluster with no neighbour in range is **left
alone** — never force-merged, never discarded — and reported.

**Gating.** `fDiscard_count` ships as `1` in every `.prm`, so honouring it directly would make
existing label-based sorts start *deleting* clusters they currently keep. A new
**`fEnforce_min_count = 0`** (default OFF) was added to `default.prm`; with it off, `post_merge_`
is byte-identical to before. Only when it is `1` is `fDiscard_count` consulted:
`1` = discard, `0` = absorb into nearest.

### 2.4 Desync hardening

The repository has a documented history of 22 corrupted sorts caused by `S_clu.viClu` and its
derived cache `S_clu.cviSpk_clu` falling out of sync. Two defences were added:

- **`merge_small_verify_`** — `S_clu_merge_small_` snapshots `S_clu` before touching it, and after
  `S_clu_refresh_` verifies both that `all(viClu(cviSpk_clu{i}) == i)` for every cluster and that
  no spike was lost. Any failure **rolls back the entire operation**. This follows `delete_clu_`'s
  existing pattern. It matters because `S_clu_select_`'s length-reconcile block actively falsifies
  field *lengths*, so only a **content** check can detect a desync.
- **`get_cviSpk_clu_checked_`** (`irc.m:4575`) — the optimization in §4 reads the cache instead of
  recomputing from `viClu`. This accessor first verifies, in one O(nSpk) pass, that the cache
  provably equals `find(viClu == i)` for every cluster; if not it returns `{}`, the caller falls
  back to `find()`, and a warning names the file. **A corrupt cache can slow the merge down; it
  cannot change the result.**

---

## 3. What was MEASURED

All numbers from the real recording. Absolute values vary 2-3× with OS page-cache state; ratios are
stable. Compare like-for-like runs only.

### 3.1 The merge kernel, by phase — this inverted the whole plan

`clu_wave_similarity_paged.m` had a `tic` at line 13 that was never `toc`'d, and phases 2 and 3
were untimed. **The plan's own go/no-go gate was not executable.** Instrumentation came first.

First measurement, before any optimization:

| Phase | Time | Share | Original doc's assessment |
|---|---|---|---|
| **1 — find spike indices** (`paged.m:41`) | **59.5 s** | **65.7%** | *not mentioned at all* |
| 2 — paged loading (`paged.m:87`) | 20.4 s | 22.5% | not mentioned |
| 3 — pairwise similarity (`paged.m:139`) | 9.8 s | 10.8% | **the entire subject of the plan** |

The `O(nClu²)` pair loop that the optimization effort existed to fix was the **smallest** phase.

### 3.2 Why the `O(nClu²)` loop is cheap — the decisive counter-measurement

```
pairs: 189,366 reached, 1,036 shared a site (0.55%)
```

Every one of the four pairwise sites is preceded by `if isempty(viSite12), continue; end`.
**99.45% of pairs exit before doing any work.** The plan's claimed "~250× reduction" from hoisting
work out of that loop was computed against a body that essentially never executes. The source
comments already said as much (`irc.m:4009-4013`) — nobody had measured it.

### 3.3 End-to-end `post_merge_` profile — the merge kernel is 8%

Full in-memory run, current code, flag off (control), 661 clusters in:

| Step | Time | Share |
|---|---|---|
| **`S_clu_wav_` — "Calculating cluster mean waveform" ×2** (`irc.m:12266`) | **261.2 s** (147.4 + 113.8) | **68.9%** |
| `post_merge_wav_` template merge | 46.6 s | 12.3% |
| **mode-17 merge kernel** (`clu_wave_similarity_paged`) | **31.5 s** | **8.3%** |
| `correlogram_` | 7.0 s | 1.8% |
| `S_clu_self_corr_` ×2 | 4.8 s | 1.3% |
| `S_clu_wavcor_` — "Computing waveform correlation" ×2 | 2.2 s | 0.6% |
| **Total** | **379 s** | |

### 3.4 A correction to the original document's "common tail" table

The original correctly identified `post_merge_wav_ → S_clu_wavcor_` and
`S_clu_update_wav_ → S_clu_wavcor_` as *"the only `fParfor`-gated work in the entire post-merge."*
Measurement adds a sting:

- The `parfor` at `irc.m:18907` lives in **`S_clu_wavcor_`** — measured at **2.2 s total**.
- The expensive part of those same two steps is **`S_clu_wav_`** (`irc.m:12266`) — **261 s**, and it
  is **serial, with no `parfor` and no GPU**.

**`fParfor = 1` parallelises the 2.2-second step and not the 261-second one.** This is the single
most actionable finding in this document, and it is out of scope for merge-mode work.

### 3.5 Phase 2 sub-timers — measured, then declined

```
phase2 breakdown: io 8.2s | find 0.9s | group 0.4s | sum 1.4s | rows 1,963,996 (14 pages × 661 scans)
```

**65% of phase 2 is disk I/O** on the 13 GB `_spkwav.jrc`. The `find(miSpk_drift_clu1(:,3) == iClu)`
at `paged.m:106`, which the plan flagged as an O(nLoads·nClu·rows) defect, costs **0.9 s** — 3% of
the kernel. Real defect, cheap fix, **not worth the regression risk** on a kernel now verified
bit-identical. Left in place deliberately.

### 3.6 Phase 3 is strictly blocked behind phase 2

Phase 2 accumulates `ctrWav_clu{iClu}` **across pages** (`paged.m:120`, inside `for iLoad`), and
`miSpk_drift_clu` is sorted by spike index, so every cluster receives contributions from nearly
every page. No cluster's template is complete before the last page. Phase 3 cannot start early for
any cluster, and phase 2's `for iClu` is not trivially parallel either. Dependency chain:
phase 1 → `miSpk_drift_clu` → phase 2 → `ctrWav_clu` → phase 3.

---

## 4. What was OPTIMIZED

### The one change: read `cviSpk_clu` instead of rescanning `viClu`

Phase 1 was executing `find(viClu_spk == iClu)` once per cluster — a full O(nSpk) scan over 16.9 M
spikes, 661 times, when `S_clu.cviSpk_clu` already holds exactly that answer.

**No stage was removed.** Phase 1 still runs in full, and the `find()` is still in the loop. The
entire change is one line — `clu_wave_similarity_paged.m:42`:

```matlab
for iClu = 1:nClu
    if fCache, viSpk1 = cviSpk_clu{iClu}; else, viSpk1 = find(viClu_spk == iClu); end
    viSpk1 = viSpk1(:);
```

What was eliminated is 661 redundant *recomputations*, not a step. `S_clu.cviSpk_clu{i}` is by
definition the list `find(viClu == i)` returns, and `post_merge_` rebuilds it from `viClu`
immediately before this point (`S_clu_refresh_` at `irc.m:3966`, and again inside `S_clu_sort_`).
The loop was rescanning all 16.9 M spikes 661 times to recompute a value already in memory — same
values, same ascending order. The drift binning, kNN expansion, mode-site selection and min-count
keep flag that follow are untouched.

Applied at five call sites, each guarded by `get_cviSpk_clu_checked_`:

| File | Function | Accessor call | Guarded loop |
|---|---|---|---|
| `clu_wave_similarity_paged.m` | mode 17 (production) | 39 | 42 |
| `post_merge_knnwav.m` | mode 12 | 53 | 56 |
| `irc.m` | `waveform_similarity_clu_` (mode 1) | 32707 | 32710 |
| `irc.m` | `templateMatch_post_burst_` (mode 13) | 33003 | 33006 |
| `irc.m` | `graph_merge_` (mode 4) | 33128 | 33131 |

One accessor call per function, each verifying the cache once before its loop.

**Result:**

| | Before | After | Δ |
|---|---|---|---|
| Merge kernel (mode 17) | 31.2 s | **21.6 s** | **−31%** |
| Phase 1 | 21.2 s | **12.2 s** | **−42%** |

**Correctness:** `isequaln(mrDist_clu_golden, mrDist_clu_new) = 1` on the full real recording — a
NaN-dominated 661 × 661 matrix, so `isequaln` rather than `isequal`.

**Safety, proven not argued:** a test deliberately corrupted `cviSpk_clu` (swapped two clusters'
entries) and re-ran the kernel. Output was **byte-identical to the golden result**, and phase 1
rose from 12.2 s to 23.7 s — the guard rejected the bad cache and fell back to `find()`, exactly as
designed. Desync suite: **6/6 pass**, covering healthy-accepted, swapped-rejected,
truncated-rejected (the case a membership-only check would miss), short-cache-rejected, the
byte-identity test, and the `S_clu_merge_small_` post-check.

---

## 5. What was NOT optimized — and why

This is the substantive part of the follow-up. Nearly everything in the original headroom column
was examined and declined **on measurement**, not on effort.

| Item | Original claim | Why it was not done |
|---|---|---|
| **`parfor` the pairwise loop** (modes 1, 12, 17) | Mode 12 = "HIGHEST — textbook parfor target" | Measured at **10.8% of the kernel, ~0.9% of `post_merge_`**, with **0.55% of pairs** reaching the body. Also `logs/investigation_maxSpk_persite_clust.md:46-49` measured `fParfor = 1` as a **2.6-3.2× slowdown** on this machine — the hot op is a GEMM that already uses all cores. And a mis-classified `parfor` breaks the default mode for everyone, uncatchably. |
| **D1 — hoist `mr2_` out of the inner loop** | "~250× reduction" | The `isempty(viSite12)` short-circuit precedes `mr2_` at **all four** sites. Saving is single-digit ×, of 10.8%. |
| **`cmr_norm_shift` precompute** | listed as a win | **Pure waste.** `mr1_` is already O(nClu); precomputing costs ~225 MB at nClu = 500 and saves nothing. Removed from the plan. |
| **Shared-kernel refactor** across modes 1/12/17 | "extract first, then optimize" | **Abandoned.** `knnwav.m` and `paged.m` can only reach `irc.m` via `irc('call', …)`, whose `test_` shim swallows every exception and returns `[]`. For mode 17 that yields `mrDist_clu = []`, the `isempty` guard fires, and **mode 17 silently degrades to mode 1** — a wrong sort with no error. Any shared helper must live in its own `.m` file on the path. |
| **Phase 2 paging** | 22.5% of kernel | 65% of it is irreducible disk I/O; the one real defect is 3% of the kernel. Declined. |
| **Phase 3 / `paged.m:106` `find`** | — | 0.9 s. Declined; risk exceeds reward. |
| **Mode 16** joining the shared kernel | "Med" | Provably gains nothing — the `isempty` short-circuit at its call site means the new path is never taken. |
| **Mode 13 `mr1b_` bug fix** | "High" | **Dropped, not deferred.** `mr2b_`/`mrDist12b` are live, so only one of two burst terms is dead. "Fixing" it adds a term to a `max`, which can only *increase* merges — in a mode with no users and no validation data. |
| **Mode 4 `graph_merge_` ungated `parfor`** | "always spins a pool even when fParfor = 0" | Still true, still unfixed. `graph_merge_`'s only caller is the mode-4 case at `irc.m:3997`; this configuration never reaches it. Received the §4 change only. |
| **Modes 5, 6, 7** | "Med" / "Med-high" | Unusable on label-based sorts — they need `S_clu.S_drift`, built only by the DPC path. The original document already noted this; measurement confirmed it. |
| **Mode 3** | "High but risky" | Excluded from scope by request. |
| **Mode 2 (the only GPU mode)** | "Low-med" | Not exercised by this configuration; not measured, not touched. |
| **`accumarray` at `post_merge_knn1.m:54`** | still sound | **Specified but not implemented.** Targets mode 11, which this configuration does not run, so it cannot be verified on real data. `post_merge_knn1.m` is unmodified. |
| **Slice-fusion in `post_merge_knn1.m`** | replaces the unsafe max-fusion | **Specified but not implemented**, same reason. It is a memory-scaling fix, not a speed fix. |
| **`S_clu_wav_` (261 s, 69%)** | — | **The real target — deliberately out of scope.** This effort was scoped to merge modes. Flagged for a separate investigation. |

---

## 6. Verification on the real recording

Full in-memory `post_merge_`, run twice with identical results. Nothing saved.

| | OFF (control) | ON (`fEnforce_min_count=1, fDiscard_count=0`) |
|---|---|---|
| `nClu` | 498 | **430** (68 absorbed) |
| assigned spikes | 16,875,724 | 16,875,718 |
| `min(vnSpk_clu)` | **8** | **61** |
| clusters below `min_count` (50) | **68** | **0** |
| per-cluster fields sized to `nClu` | ✓ (42 fields) | ✓ (42 fields) |
| `all(viClu(cviSpk_clu{i}) == i)` | ✓ 0 bad | ✓ 0 bad |
| runtime | 379 s | 266 s |

```
S_clu_merge_small_: absorbed 68/498 clusters (<50 spikes) into nearest,
1221 spikes moved; 0 left (no cluster within 60 um)
```

**On spike conservation.** It is an invariant of `S_clu_merge_small_`, **not** of the pipeline.
Called standalone it is exact: `16,875,724 → 16,875,724`, `nClu 498 → 430`. The −6 end-to-end delta
is `S_clu_refrac_`, which runs *after* the new call site: absorbing a small cluster into its
neighbour puts formerly-separate spikes into one unit, exposing new refractory violations
(945 removed with the flag on vs 939 off). Asserting pipeline-level equality is wrong by design —
noted here because it was initially written as an assertion and reported a false failure.

### Bugs found in this work's own code, on real data

- `min_count = []` (documented to mean "no filtering") absorbed 61 clusters using the default
  threshold of 30. Cause: `get_set_(P, 'min_count', 30)` substitutes its default for `[]`, so an
  `isempty` check *after* that call is dead code. Fixed by testing `P.min_count` directly, before
  `get_set_`.
- With `maxDist_site_um = 0.01` one cluster was still absorbed — two clusters share an identical
  median position, distance exactly 0. The code was right; the test assertion was too strict.

Neither would have been caught without running on a real recording.

---

## 7. Files changed (uncommitted)

| File | Change |
|---|---|
| `matlab/irc.m` | `S_clu_merge_small_` (4461), `get_cviSpk_clu_checked_` (4575), `merge_small_verify_` (4614); call site 4022; §4 change at 3 sites |
| `matlab/clu_wave_similarity_paged.m` | §4 change; phase timers and sub-timers; pair counters; three-phase structure documented |
| `matlab/post_merge_knnwav.m` | §4 change |
| `matlab/default.prm` | new `fEnforce_min_count = 0`; `fDiscard_count` marked live; `min_count` comment records the label-sort caveat |
| `matlab/CLAUDE.md` | two new sections: `min_count` not enforced on label-based sorts; how to read `cviSpk_clu` safely |
| `logs/PLAN_post_merge_optimization.md` | rewritten with the review corrections, the measured results, and the re-ranked worklist |

`matlab/post_merge_knn1.m` is **unmodified** (see §5).

## 8. Open decisions

1. **Nothing is committed.**
2. **The `_jrc.mat` is untouched at 661 clusters.** Putting the 430-cluster result on disk requires
   `irc auto` + save, which resets `csNote_clu`. Since `note == 'single'` is the only downstream
   unit selector, that would discard existing curation notes.
3. **`irc.m` changed on disk.** Any manual-curation GUI opened before these edits holds stale
   function handles and its callbacks will fail. Relaunch it.

## 9. Recommended next step

Not more merge-mode work. **`S_clu_wav_` (`irc.m:12266`) is 69% of `post_merge_`, runs twice, and
is serial with no GPU** — while the `fParfor` flag accelerates a neighbouring 2.2-second step. That
is where end-to-end `irc auto` time actually is.
