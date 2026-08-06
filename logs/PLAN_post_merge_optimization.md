# PLAN — optimizing the HIGH / HIGHEST headroom post-merge modes

Status: **proposal only, nothing implemented.** Scope: the modes rated HIGH or HIGHEST in
`ironclust_post_merge_modes` (mode **3 excluded by request**) — i.e. modes **1, 8/9/10, 11, 12, 13, 17**.

All line references are `matlab/irc.m` unless a file is named. Every claim below was read out of the
source; **no timings were measured** — all "×N" figures are *operation counts*, not wall-clock.

---

## 0. The central finding: one kernel, four modes

Modes **1, 12, 13, 17** each end in a byte-for-byte near-identical pairwise similarity loop:

| Mode | Location |
|---|---|
| 1 (and 8/9/10/14/15/16 via `templateMatch_post_`) | `waveform_similarity_clu_` **32628-32651** |
| 12 | `post_merge_knnwav.m` **156-178** |
| 13 | `templateMatch_post_burst_` **32852-32880** |
| 17 | `clu_wave_similarity_paged.m` **107-126** |

```matlab
for iClu1 = 1:nClu
    mr1_ = fh_norm_tr(shift_trWav_(ctrWav_clu{iClu1}, viShift));   % once per iClu1  - fine
    viSite_clu1 = repmat(viSite_clu1(:), numel(viShift), 1);
    vrDist_clu1 = zeros(nClu, 1, 'single');
    for iClu2 = iClu1+1:nClu
        viSite12 = intersect(viSite_clu1, viSite2);                % D2
        if isempty(viSite12), continue; end
        mr2_ = fh_norm_tr(ctrWav_clu{iClu2});                      % D1  <-- O(nClu^2)
        for iSite12_ = 1:numel(viSite12)
            mrDist12 = mr2_(:, viSite2==iSite12)' * mr1_(:, viSite_clu1==iSite12);   % D3
            vrDist_clu1(iClu2) = max(vrDist_clu1(iClu2), max(mrDist12(:)));
        end
    end
    mrDist_clu(:, iClu1) = vrDist_clu1;                            % column-sliced -> D4
end
```

Four defects, all shared:

- **D1 — `mr2_` normalised inside the inner loop.** `fh_norm_tr(ctrWav_clu{iClu2})` depends only on
  `iClu2`, yet runs once per *pair*: **O(nClu²) normalisations where O(nClu) suffice.** Each call
  reshapes + `std` + `rdivide` over `(nT·nC) × nDrift` (~340×64 ≈ 22 k elements). At nClu = 500 that
  is ~125 000 calls instead of 500 — a **~250× reduction** in that term. Mode 13 pays it **twice**
  (`mr2_` 32867 *and* `mr2b_` 32868).
- **D2 — `intersect` per pair** on small integer vectors, O(nClu²) times, each sorting internally.
- **D3 — `viSite2==iSite12` / `viSite_clu1==iSite12`** recomputed per (pair × site); both depend only
  on one cluster.
- **D4 — the `iClu1` loop writes only `mrDist_clu(:, iClu1)`.** Pure column-sliced output, no
  cross-iteration state → **textbook `parfor`**, and `ctrWav_clu` is *small* (see §5), so unlike the
  template phase there is no broadcast problem.

**Fixing this kernel once, in one shared helper, improves seven of the seventeen modes.**

### Proposed shared helper

New function `clu_pairwise_similarity_(ctrWav_clu, cviSite_clu, viShift, P)` returning `mrDist_clu`,
placed in `irc.m` beside `waveform_similarity_clu_`:

1. **Precompute once, before the outer loop** (kills D1/D2/D3):
   - `cmr_norm{i} = fh_norm_tr(ctrWav_clu{i})` — O(nClu).
   - `cmr_norm_shift{i} = fh_norm_tr(shift_trWav_(ctrWav_clu{i}, viShift))` — O(nClu).
   - `mlSite_clu` — `nSites × nClu` logical site-membership. Pair test becomes
     `any(mlSite_clu(:,i) & mlSite_clu(:,j))`; candidate list via one `mlSite_clu' * mlSite_clu`
     matrix product (or `find` on the boolean product) instead of nClu² `intersect` calls.
   - `cviIdx_site{i}` — per cluster, the column indices per site (replaces the `==` scans).
2. **`parfor iClu1`** over the outer loop (D4), gated on `get_set_(P,'fParfor',1)` with a `try/catch`
   fallback to `for` — mirroring the existing idiom at **18704-18723** so behaviour is unchanged when
   the pool is unavailable. Do **not** copy `graph_merge_`'s ungated `parfor` (32939), which spins a
   pool even when the user set `fParfor = 0`.
3. Return bit-identical `mrDist_clu`. The arithmetic is unchanged — only hoisted and reordered — so
   equality against the current output is a hard requirement, not a tolerance check.

Then reduce the four call sites to invoke the helper. Mode 13 keeps its extra `b` template set as a
second helper argument.

### Correctness bug found while reading mode 13

`templateMatch_post_burst_` **32856** sets `mr1b_ = fh_norm_tr(ctrWav_b_clu{iClu1})`, then **32860**
immediately overwrites it with `fh_norm_tr(shift_trWav_(ctrWav_clu{iClu1}, viShift))` — the *same
RHS as `mr1_` on 32858*, reading `ctrWav_clu`, not `ctrWav_b_clu`. So `mr1b_ == mr1_`, making
`mrDist1b2` (32872) a duplicate of `mrDist12` (32871) and rendering half the burst comparison dead.
Almost certainly a copy-paste slip. **Fix separately from the optimization** — it changes results,
so it must not be bundled with a bit-identical refactor.

---

## 1. Mode 1 — `templateMatch_post_` → `waveform_similarity_clu_` (32466)

Two phases: template build **32504-32626**, pairwise **32628-32651**.

- **Pairwise:** covered entirely by §0.
- **Template build, D5:** `viSpk1 = find(S_clu.viClu == iClu)` at **32505**, inside `for iClu` →
  a full O(nSpk) scan per cluster, **O(nClu · nSpk) overall**. `S_clu.cviSpk_clu{iClu}` is exactly
  this list and is already maintained. `post_merge_knn1.m:40` already uses it — the pattern is proven
  in-tree. Replace, with a `S_clu_assert_synced_`-style precondition (the cache/`viClu` invariant must
  hold; on a desynced file this changes results, which is *correct* — it would surface the desync).
- **Template build, D6:** `for iClu` is per-cluster independent (writes only `ctrWav_clu{iClu}`,
  `cviSite_clu{iClu}`) → `parfor`-shaped, **but blocked by the `tnWav_spk` broadcast** (§5). Do not
  attempt until §5 is resolved.

**Effort:** low once the §0 helper exists (call-site swap + the `cviSpk_clu` change).

---

## 2. Modes 8 / 9 / 10 — `post_merge_knn1` + `templateMatch_post_` compositions

No code of their own — they are compositions:
`8 = templateMatch_post_(post_merge_knn1(…))`, `9 = post_merge_knn1(templateMatch_post_(…))`,
`10 = post_merge_knn1(templateMatch_post_(post_merge_knn1(…)))` (**3991-3993**).

**They need no separate work.** They inherit §1 and §3 automatically. Mode 10 runs `post_merge_knn1`
**twice**, so it benefits doubly from §3. Worth noting only so nobody plans them independently.

---

## 3. Mode 11 — `post_merge_knn1.m` (and the 8/9/10 half)

Structurally different from the kernel family — kNN set-overlap, no waveforms. Three defects:

- **E1 — `ismember` in the innermost position (line 54).**
  `vr_ = cellfun(@(y)mean(ismember(viSpk_out11(:), y)), S_clu.cviSpk_clu(viClu2))`
  runs an `ismember` of a large vector against *each* candidate cluster's spike list, for every
  (iClu × iDrift). Replace with a **single `accumarray` pass**:
  ```matlab
  viClu_out = S_clu.viClu(viSpk_out11(:));           % label of every out-neighbour
  vnCount   = accumarray(viClu_out(viClu_out>0), 1, [nClu 1]);
  vr_       = vnCount(viClu2) / numel(viSpk_out11);
  ```
  Turns O(|viClu2| · |viSpk_out11|) into O(|viSpk_out11|). **The single biggest win in this mode.**
  *Precondition:* `viClu` and `cviSpk_clu` must agree — the invariant `S_clu_assert_synced_` checks.
  State it in a comment; the identity is exact only under that invariant.
- **E2 — `find(ismember(viSpk1, cviSpk_drift{iDrift}))` (line 45)**, inside the nClu × nDrift loop.
  Build a per-spike drift-bin id vector **once** (`viDrift_spk`, which `S_drift` already carries when
  present), then select with `viDrift_spk(viSpk1) == iDrift`. Removes an `ismember` from a
  nClu × nDrift loop.
- **E3 — `trDist_clu = nan(nClu, nDrift, nClu)` (line 36) is O(nClu² · nDrift) memory.**
  At nClu = 500, nDrift = 64 → ~128 MB; at nClu = 2000 → **~2 GB**. Phase 2 (lines 64-80) only ever
  reduces it to `max` over the drift dimension. Fuse the reduction into phase 1 and keep an
  `nClu × nClu` matrix — drops the peak by a factor of `nDrift`. This is a **scaling fix, not a
  speed fix**, and matters most on the per-site label-based sorts that produce many clusters.

`parfor` on `for iClu` (line 39) is possible (`trDist_clu(:,:,iClu)` is slice-3 output) but should be
**deferred** — E1/E2 likely remove most of the cost, and E3 must land first or each worker holds a
copy of a multi-GB array.

**Effort:** medium. **Independent of §0** — can proceed in parallel.

---

## 4. Mode 12 — `post_merge_knnwav.m`

Rated HIGHEST in the table. Two phases:

- **Pairwise (156-178):** covered by §0, identical code.
- **Template build (48-143):** same `find(S_clu.viClu == iClu)` defect at **line 49** → use
  `cviSpk_clu` (D5). Same `parfor` shape as §1, same `tnWav_spk` broadcast blocker (§5).
- Note the `switch 3` at line 59 and `switch 1` at line 97 are dead-branch selectors (constants).
  **Leave them.** They are the author's A/B scaffolding, and the repo rule is to preserve rather
  than delete. Only the *taken* branch needs optimizing.

**Effort:** low once §0 exists.

---

## 5. Mode 17 — `clu_wave_similarity_paged.m`

- **Phase 3 (107-126):** covered by §0.
- **Phases 1-2 (29-99) are already the good design.** This is the only mode that **pages waveforms
  from `_spkwav.jrc`** (`load_spkwav_`, 163+) instead of holding `tnWav_spk` whole, accumulating
  per-cluster sums incrementally. Its `for iClu` at **85** is inside the page loop and accumulates
  into `ctrWav_clu` across pages — **not** trivially parallel (cross-page carry).
- Phase 1's `find(viClu_spk == iClu)` at **line 30** still has defect D5 → `cviSpk_clu`.

### The cross-cutting constraint: `tnWav_spk` cannot be broadcast

Modes 1, 12, 13 call `get_spkwav_(P, fUse_raw)` and hold the **entire** spike-waveform tensor.
Order of magnitude for `260317_afm18349` (spkLim_ms `[-0.2 0.35]` → ~17 samples, ~20 channels,
~19.7 M spikes, int16): **≈ 13 GB**. Under `parfor`, a broadcast variable is copied **per worker** —
at `nWorkers_clust = 18` that is not merely slow, it is impossible.

**Therefore:**
- `parfor` on the **pairwise** phase is safe — it touches only `ctrWav_clu`
  (nClu × nDrift templates ≈ 500 × 64 × 340 singles ≈ **43 MB**), which broadcasts fine.
- `parfor` on the **template-build** phase is **blocked** until those modes adopt mode 17's paged
  loader. That is a much larger change and is explicitly **out of scope here**.

---

## 6. Prioritized worklist

| P | Item | Modes fixed | Effort | Risk | Why this rank |
|---|---|---|---|---|---|
| **P0** | §0 D1+D2+D3 — hoist `mr2_`, precompute site membership + index lists, **serial only** | 1, 8/9/10, 12, 13, 14, 15, 16, 17 | S | **Very low** | Biggest ops reduction (~250× on the D1 term at nClu=500) for the least risk. Pure hoisting — arithmetic untouched, so the acceptance test is bit-identical output. No pool, no memory change. **Do this first and measure before anything else.** |
| **P1** | §3 E1 — `accumarray` replacing the `ismember`/`cellfun` in `post_merge_knn1.m:54` | 8/9/10, 11 | S | Low | Second-largest single win; self-contained; independent of P0 so it can run in parallel. Needs the `viClu`⇄`cviSpk_clu` invariant stated as a precondition. |
| **P2** | §0 D4 — `parfor` the pairwise outer loop, gated on `fParfor` like 18704 | same as P0 | S | Low-med | Only worth doing **after** P0: hoisting may shrink this phase enough that pool startup dominates. Small broadcast (~43 MB), so genuinely safe. |
| **P3** | §1/§4 D5 — `find(viClu==iClu)` → `cviSpk_clu` in 32505, knnwav:49, paged:30 | 1, 12, 17 | S | Low-med | Removes an O(nClu · nSpk) scan. Ranked below P2 only because it is behaviourally load-bearing on a **desynced** `_jrc.mat` — must land with an explicit sync precondition. |
| **P4** | §3 E2 + E3 — drift-id vector; fuse the `max` to drop `trDist_clu` to nClu × nClu | 8/9/10, 11 | M | Med | E3 is a **scaling** fix (2 GB at nClu=2000), not a speed fix. Do it before anyone runs mode 11 on a many-cluster label-based sort. |
| **P5** | Mode 13 `mr1b_` correctness bug (32856/32860) | 13 | S | **Changes results** | Real bug, but mode 13 is not in use here. Must be a **separate commit** from every bit-identical change above. |
| **P6** | `graph_merge_` ungated `parfor` (32939) → gate on `fParfor` | 4 | S | Low | Not a HIGH-headroom item, but it violates the user's explicit `fParfor = 0`. Cheap correctness-of-intent fix. |
| — | Template-phase `parfor` (D6) | 1, 12, 13 | L | **High** | **Not recommended.** Blocked by the ~13 GB `tnWav_spk` broadcast (§5). Would require porting to mode 17's paged loader first. |

**Recommended first slice: P0 + P1.** Both are pure hoisting/reformulation, both are verifiable by
bit-identical output, and between them they touch every mode in scope.

---

## 7. Verification

Non-negotiable: **P0-P4 must produce bit-identical `mrDist_clu` / `viClu`.** They reorder and hoist
computation; they do not change arithmetic. Any difference is a bug, not a tolerance issue.

1. **Golden-output harness.** On an existing `_jrc.mat`, call the target function in memory before
   and after via `irc('call', …)` and assert `isequaln(mrDist_clu_old, mrDist_clu_new)`. Use the
   in-memory `post_merge_` route (no save) rather than a re-sort — the established ~7 min path.
2. **Real recording, not synthetic.** Use a time-trimmed `.prm` off
   `260317_afm18349_g0_tcat.imec0.ap_IRC_with_shanks.prm` (`vcCluster = 'isosplit'`,
   `post_merge_mode = 17`) so the exercised path is the one actually in production here.
3. **Measure before optimizing.** The existing prints already split the phases —
   `Automated merging (post-hoc)` (template build) vs `Merging templates` (pairwise) vs
   `Computing waveform correlation` (the common tail). **Record all three first**; if the pairwise
   phase is not a meaningful share, P0/P2 are not worth doing and this plan should be re-ranked.
4. **`parfor` items (P2) additionally:** assert serial == parallel output, and confirm no pool is
   created when `fParfor = 0`.
5. **P5 (mode 13) has no bit-identical test** — it changes results by design. Verify by inspection
   that `mr1b_` now derives from `ctrWav_b_clu`, and report the merge-count delta.

## 8. Out of scope

Mode 3 (excluded by request). Template-phase parallelisation (§5). Porting modes 1/12/13 to the
paged loader. Any change to `post_merge_mode` defaults. Any behavioural change beyond P5/P6, both of
which are flagged as result-changing and separately committed.
