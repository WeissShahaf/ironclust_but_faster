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
2. **Everything else in the merge kernel was measured and dropped**, with reasons recorded. Two
   changes originally labelled "bit-identical" would in fact have silently altered merge behaviour.
3. **The merge kernel is not where the time is.** It is **8%** of `post_merge_`. `S_clu_wav_`
   (`irc.m:12266`) is **69%**. Optimizing merge modes cannot materially change `irc auto` runtime.
   Acting on that is what produced the largest win here (point 5).
4. **A separate, larger defect was found and fixed**: `min_count` was **never enforced** on
   label-based sorts. That is why clusters with 8 spikes survived a `min_count = 50` setting.
5. **Three optimizations shipped, each proven byte-identical on the real recording:**

| # | Change | Effect | Commit |
|---|---|---|---|
| 1 | Read the `cviSpk_clu` cache instead of rescanning `viClu` | merge kernel **31.2 s → 21.6 s (−31%)** | `83ffb5a` |
| 2 | `S_clu_sort_` permutes waveform/quality fields (**correctness**) | output unchanged; closes an `import_ksort_` desync | `2ad7efb` |
| 3 | Second `S_clu_wav_` recomputes only refrac-changed clusters | `post_merge_` **247 s → 179 s (−27.5%)** | `b75dee2` |

6. **Changes 2 and 3 are one finding, not two.** The unconditional full recompute at `irc.m:4026`
   was what silently repaired the mis-ordering change 2 fixes — so the bug *was* the 68 seconds.
   The carried fields could not be trusted, therefore all of them had to be rebuilt every pass.

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

### 3.3b Inside `S_clu_wav_` — where its 69% goes

`S_clu_wav_` is four pieces, not one: a `get_spkwav_` load and an `nClu` loop for filtered
waveforms, then the same again for raw (`fSkipRaw` is forced to 0 at `irc.m:12275`, so the raw
half always runs — hence ~2×nClu progress dots per call). Timers added to each:

```
call 1   loads 4.9s | loop spk 35.4s | loop raw 39.7s  ->  80.0s
call 2   loads 0.0s | loop spk 35.6s | loop raw 39.4s  ->  75.0s
```

**The `get_spkwav_` loads are effectively free inside `post_merge_`** — 0.0 s on the second call,
because the data is already resident. A separate cold-start measurement showed 12.4 s + 8.7 s, so
anyone profiling `S_clu_wav_` in isolation will over-attribute cost to I/O. **The per-cluster
median loops are essentially the entire cost**, which is what made change 3 worth doing: only the
loops shrink under `viClu_update`.

The work inside `clu_wav_` (`irc.m:12403`) is one line:

```matlab
mrWav_clu1 = fh1(get_wav_(viSpk_clu1), 3);   % median over EVERY spike in the cluster
```

with `get_wav_ = @(x) single(tnWav_(:,:,x))`. For the largest cluster (745,482 spikes) that
materialises roughly 18 × 9 × 745,482 × 4 B ≈ **480 MB** and takes a median across it.

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

### 3.7 Subsampling `clu_wav_`'s median — measured, and it changes merge decisions

The largest remaining lever, measured rather than assumed. `clu_wav_` medians over every spike in a
cluster (745,482 for the largest here; 527 of 661 clusters hold more than 1000 spikes), while
`nSamples_max = 1000` sits declared-and-unused at `irc.m:12406`.

**On that `nSamples_max = 1000` — do not read it as a disabled feature.** The name is a recycled
local, reused across `irc.m` with two unrelated meanings and no shared state (they are separate
function-local variables, so nothing collides):

| Meaning | Where | Status |
|---|---|---|
| time samples per file-read chunk | `plan_load_` / `partition_load_` (1382-1402), GPU chunking (~5412) | live |
| spike cap before an expensive per-cluster op, via `subsample_vr_` | `S_clu_subsample_spk_` (12514) → called from `S_clu_position_` | **live** |
| " | `load_wav_med_` (32543) → called from `ui_show_all_chan_`, a GUI display path | **live** |
| " | `driftMatch_post_` (32643) | live in mode 3 only |
| " | `mean_wav_lo_hi_` (12434), `spk_select_pos_` (12496), `S_clu_wav_pair_` (19016) | **dead — 0 callers each** |
| " | **`clu_wav_` (12406)** | **declared, never referenced** |

Three of the six spike-cap uses are dead code. Every use that is *live* sits in a position or
display helper, where subsampling is cheap and inconsequential — **not one of them feeds the merge
criterion.** So the `1000` in `clu_wav_` reads as a copy-paste remnant of a house idiom, not as
evidence that subsampling was designed for this path. An earlier draft of this document argued the
opposite from the presence of `mean_wav_lo_hi_`; that inference was wrong, because
`mean_wav_lo_hi_` is itself never called.

**Why this is a merge question, not a display question.** `S_clu_wavcor_` builds `mrWavCor` from
**`tmrWav_raw_clu`** when `fWavRaw_merge = 1` (`irc.m:18932-18937`) — the default, and this
configuration's setting. `mrWavCor >= maxWavCor` is what decides merges. So subsampling the median
directly perturbs the merge criterion.

Templates rebuilt at three sizes, then `mrWavCor` recomputed and compared against the full-median
baseline. Filtered and raw waveforms are loaded one at a time (~7 GB and ~14 GB), exactly as
`S_clu_wav_` does:

| `nSamples_max` | loop time | |Δ`mrWavCor`| over scored pairs (med / p99 / max) | **near threshold** (±0.05, ~990 pairs) med / max | pairs ≥ 0.985 | decision flips |
|---|---|---|---|---|---|
| full (current) | **171.7 s** | — | — | 102 | — |
| 4000 | 23.6 s | 0.0015 / 0.035 / 0.115 | **0.00066 / 0.0136** | 100 | 8 (**7.8%**) |
| 1000 | 7.0 s | 0.0037 / 0.060 / 0.127 | **0.0016 / 0.030** | 93 | 19 (**18.6%**) |
| 500 | 3.7 s | 0.0055 / 0.084 / 0.176 | **0.0025 / 0.056** | 82 | 26 (**25.5%**) |

**Get the denominators right.** Of 218,130 cluster pairs, only **6,967 are scored at all** (3.2%) —
`mrWavCor` scores only pairs that share sites. Of those, **102** clear the merge threshold. So a
flip rate quoted against all pairs (0.0087% at 1000) is meaningless; against the pairs that can
actually merge it is **one decision in five**, nearly all of them merges that stop happening.

**But the near-threshold column is the real finding.** Where the decision is actually made,
subsampling moves `mrWavCor` by a median of **0.0016** at `nSamples_max = 1000` — about 0.16% — and
never by more than 0.030. The alarming `max 0.127` occurs among poorly-correlated pairs that are
nowhere near merging. That is what one would expect: pairs sitting at 0.985 are near-identical,
high-SNR waveforms whose templates are well determined by far fewer than 745k spikes.

So the honest reading is that **subsampling does not produce bad templates — near the boundary they
are accurate to ~0.2%. The instability comes from `maxWavCor = 0.985` being a hard threshold with
~990 candidate pairs packed against it**, 19 of which sit inside a 0.003-wide noise band. That is a
property of the decision rule, not of the estimator.

This cuts both ways and neither side should be oversold. It weakens "subsampling is dangerous": the
templates are fine where it counts. It does *not* make the flips harmless: those pairs genuinely
merge or fail to, changing the cluster set — and a pair that is borderline under the full median is
not obviously resolved *correctly* by it either. The full-median answer is the incumbent one, not a
ground truth.

**`subsample_vr_` is deterministic.** Two independent draws at 1000 produced byte-identical
`mrWavCor` — 0 flips between them. So the choice is reproducible run-to-run; the objection that
subsampling would make sorts non-deterministic does not apply.

**Amplitude:** at 1000, `vrVmin_clu` shifts by a median of 0.375% but a maximum of **29.9%** on one
cluster — worse than the max at 500 (5.5%). A single badly-behaved cluster, but it propagates into
SNR and unit selection.

**Verdict: do not change the default, and if it ships, 4000 rather than 1000.**

At `nSamples_max = 4000` you keep 100 of 102 merges, near-threshold error is 0.00066, amplitude
error is bounded at 2.4%, and the loops still fall 171.7 s → 23.6 s — which would take
`post_merge_` from 179 s to roughly 110 s. At 1000 you trade one merge decision in five for a
further 16 seconds, which is a poor exchange. Either way it belongs behind an explicit, documented
opt-in carrying these numbers, never folded into a commit labelled "optimization".

**Two other effects to weigh, beyond `mrWavCor`.** The template also drives
`find_peakSite_snr_clu_` (`irc.m:4435`), which deletes units whose template peak site sits further
than `maxDist_site_um` from `viSite_clu` — a *second* path from template to cluster count, not
measured here. And `vrVmin_clu` feeds `vrSnr_clu` and the quality CSV. `mrPos_clu` is **not**
affected: `S_clu_wav_` computes it from `S0.mrPos_spk` over the full spike list, not via `clu_wav_`.

*A defect in the first run of this measurement:* median and p99 of |Δ`mrWavCor`| came back `NaN`
because non-finite entries were not excluded. Flip counts, pair counts and `max |Δ|` were never
affected (`NaN >= thr` is false on both sides), so the original verdict held — but the typical
perturbation, which is the number that actually reframed the conclusion, was missing until the
re-run.

---

## 4. What was OPTIMIZED

Three changes, each proven byte-identical on the real recording before being committed.

### 4.1 Read `cviSpk_clu` instead of rescanning `viClu` — `83ffb5a`

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

### 4.2 `S_clu_sort_` now permutes waveform and quality fields — `2ad7efb` (correctness)

`S_clu_sort_` remaps `viClu`, then reordered per-cluster fields through a **hand-maintained list of
seven names**: `cviSpk_clu, vrPosX_clu, vrPosY_clu, vnSpk_clu, viSite_clu, cviTime_clu,
csNote_clu`. Every waveform and quality field was missing from it — `tmrWav_spk_clu`,
`trWav_spk_clu`, `tmrWav_raw_clu`, `trWav_raw_clu`, `tmrWav_clu`, `mrPos_clu`, `vrVmin_clu`,
`viSite_min_clu`, `mrWavCor`, `vrSnr_clu`, `vrIsoDist_clu`, `vrIsiRatio_clu`, `vrLRatio_clu` — so
after a sort those stayed in the **pre-sort** numbering while `viClu`/`cviSpk_clu` had moved to the
**post-sort** numbering.

Two call sites, two very different outcomes:

| Call site | Outcome |
|---|---|
| `post_merge_` (`irc.m:4024`) | **Masked.** `S_clu_update_wav_` at `:4026` recomputes all of those fields unconditionally, overwriting the mis-ordering before anything reads it. Masked by accident, not by design. |
| `import_ksort_` (`irc.m:13434`) | **Not masked.** `S_clu_new_` computes the fields, the sort renumbers without permuting them, and `save0_` writes the result to `_jrc.mat` — every unit carrying another unit's waveform, SNR and `mrWavCor` row. |

Fixed by reordering through **`S_clu_select_`**, which reindexes per-cluster fields by pattern
(`v*_clu`/`t*_clu`/`c*_clu`/`m*_clu`), remaps `mrWavCor` across both cluster axes via
`S_clu_wavcor_remap_`, and detects `[X × nClu]` vs `[nClu × X]` orientation. Its contract
(`irc.m:20561`) is that the caller remaps `viClu` first — which `S_clu_sort_` already did. No list
left to rot. That header comment names this exact failure mode: *"reorder_clu_by_coords_ omitted it
and produced a silent, saved viClu/cviSpk_clu desync."*

**Verified:** `post_merge_` output unchanged — 20 fields compared, 20 same, 0 differ. It has to be
unchanged, since every affected field is recomputed downstream regardless; that is what makes this
a safe correctness fix rather than a behavioural one.

### 4.3 Second `S_clu_wav_` recomputes only refrac-changed clusters — `b75dee2`

`post_merge_` called `S_clu_wav_` twice over **every** cluster. Between the two calls only
`S_clu_refrac_` changes membership, and it only zeroes labels and shrinks `cviSpk_clu`/`vnSpk_clu`
in place (`irc.m:12599-12602`) — it never renumbers and never drops a cluster. So every cluster it
does not touch still holds exactly the waveforms the first pass computed. On this recording it
touched **13 of 430**.

`S_clu_wav_` has always supported `viClu_update` for this. Nothing used it because §4.2's
mis-ordering meant the carried fields could not be trusted — the full recompute *was* the repair.

- `S_clu_update_wav_` takes an optional 4th argument; `[]` (what all four existing callers get)
  means "recompute everything".
- `post_merge_` snapshots `vnSpk_clu` around `S_clu_refrac_` and passes the clusters whose count
  changed. Since refrac can only shrink a cluster, a count change is a **complete** signal — so
  `S_clu_refrac_` itself needed no modification.
- Falls back to `[]` if refrac changed nothing or the count vector changes length. The failure
  mode is "slower", never "wrong".

| | Before | After | Δ |
|---|---|---|---|
| `post_merge_` end-to-end | 247 s | **179 s** | **−27.5%** |
| 2nd `S_clu_wav_` | 75.0 s | ~7 s | 13/430 clusters |

**Verified:** same golden, same 20 fields, 20 same / 0 differ.

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
| **`S_clu_wav_` (261 s, 69%)** | — | **Was** out of scope; subsequently taken up — see §4.2 and §4.3, which removed 27.5% of `post_merge_`. What remains below is what was declined *within* it. |
| **Subsampling in `clu_wav_`** | — | **Measured, then declined — it changes merge decisions.** See §3.7 for the numbers: at `nSamples_max = 1000` the loops drop from 171.7 s to 7.1 s, but **18.6% of merge-eligible pairs change state**. Even at 4000 it is 7.8%. This is a scientific choice about what a cluster template is, not an optimization. |
| **Re-enabling the `fWavRaw_merge` gate** | — | **Declined — and more load-bearing than it looks.** `irc.m:12275` forces `fSkipRaw = 0`; the line above it, gating on `fWavRaw_merge`, is commented out. Skipping the raw loop would save ~40 s per pass — but `S_clu_wavcor_` reads **`tmrWav_raw_clu`** when `fWavRaw_merge = 1` (`irc.m:18932-18937`), which is the default and this configuration's setting. The raw waveforms *are* the merge criterion, not just quality/display. Skipping them without also setting `fWavRaw_merge = 0` would break merging outright. |
| **First `S_clu_wav_` pass (80 s)** | — | Not touched. It runs inside `post_merge_wav_` after a merge has just changed cluster membership wholesale, so there is no small "changed set" to exploit as there is for the second pass. Now the single largest item in `post_merge_`. |

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
- The §3.7 subsampling measurement reported `median` and `p99` of |Δ`mrWavCor`| as `NaN`, because
  `mrWavCor` contains NaN entries that were not excluded. Flip counts, pair counts and `max |Δ|`
  are unaffected, so the conclusion held — but the typical perturbation went unmeasured.
- Argued that subsampling "was clearly intended" in `clu_wav_` from the neighbouring
  `mean_wav_lo_hi_`. That function has **zero callers**. Inferring intent from adjacent code
  without checking whether the adjacent code is reachable is exactly the trap this codebase sets:
  `irc.m` carries a lot of dead code, and three of the six `nSamples_max` spike-cap uses are dead.

Neither of the first two would have been caught without running on a real recording; the last two
were caught by re-reading rather than by running.

---

## 7. Files changed — committed to `rewind`, 2026-08-06

| Commit | Contents |
|---|---|
| `83ffb5a` | `min_count` enforcement + the `cviSpk_clu` fast path. `irc.m` (`S_clu_merge_small_` 4461, `get_cviSpk_clu_checked_` 4575, `merge_small_verify_` 4614, call site 4022, §4.1 at 3 sites), `clu_wave_similarity_paged.m`, `post_merge_knnwav.m`, `default.prm`, `CLAUDE.md` |
| `330ea6e` | docs: the rewritten plan and this follow-up |
| `2ad7efb` | §4.2 — `S_clu_sort_` permutes waveform/quality fields; `S_clu_wav_` instrumentation |
| `b75dee2` | §4.3 — incremental second `S_clu_wav_` |

`matlab/post_merge_knn1.m` is **unmodified** (see §5).

## 8. Open decisions

1. **The `_jrc.mat` is untouched at 661 clusters.** Putting the 430-cluster result on disk requires
   `irc auto` + save, which resets `csNote_clu`. Since `note == 'single'` is the only downstream
   unit selector, that would discard existing curation notes.
2. **`irc.m` changed on disk.** Any manual-curation GUI opened before these edits holds stale
   function handles and its callbacks will fail. Relaunch it.
3. **Re-running affected sorts.** §4.2 fixes a desync that only bites `import_ksort_`. Any
   `_jrc.mat` produced by that path carries per-unit waveform/SNR/`mrWavCor` values belonging to
   other units and should be re-imported. Sorts produced through `post_merge_` are unaffected —
   there the mis-ordering was always overwritten before use.

## 9. Recommended next step

`post_merge_` is now **179 s**, down from 247 s. The profile has shifted, so the old advice
("go after `S_clu_wav_`") is spent — §4.3 took the cheap 27.5%, and what is left in `S_clu_wav_`
is guarded by quality decisions rather than engineering ones.

The remaining items, in order of size:

1. **First `S_clu_wav_` pass — 80 s, now the largest single item.** No small changed-set to
   exploit: it runs inside `post_merge_wav_` right after a merge has changed membership wholesale.
2. **Subsampling — measured in §3.7, and the case is better than it first looked.** By far the
   biggest lever, and *not* blocked on further measurement. Near the merge threshold the templates
   are accurate to ~0.2% even at `nSamples_max = 1000`; the flips come from `maxWavCor` being a
   hard threshold with ~990 candidates against it. **4000 is the defensible setting**: 100 of 102
   merges preserved, 171.7 s → 23.6 s of loop time, `post_merge_` ~179 s → ~110 s. It still needs
   to be an explicit opt-in, and the second template→cluster-count path
   (`find_peakSite_snr_clu_`, `irc.m:4435`) should be measured before it ships.
3. **`post_merge_wav_` template merge — ~35 s.** Never profiled. The only remaining item that might
   still yield a free win.

Note that the `fParfor` observation in §3.4 still stands and is still unaddressed: the flag
parallelises `S_clu_wavcor_` (2.2 s) and not `S_clu_wav_` (now ~86 s).

**A caution for whoever picks this up.** `irc.m` contains a lot of unreachable code — this session
found `mean_wav_lo_hi_`, `spk_select_pos_`, `S_clu_wav_pair_` and `maddist2_` with zero callers,
and `fDiscard_count` documented in four `.prm` files while read by none. Do not infer intent from
neighbouring code without first checking that the neighbour is reachable. Two of the errors listed
in §6 came from exactly that.
