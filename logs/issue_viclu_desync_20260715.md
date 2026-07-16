# ISSUE: silent `viClu` / `cviSpk_clu` desync corrupts cluster identity on split, merge and delete

> **Tracker:** indexed as CID‑01…CID‑15 in
> [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md).

**Status:** root cause FIXED (`87cd4f1`); `delete_clu_` / `merge_clu_` / `post_merge_wav_` FIXED
2026‑07‑16 (uncommitted at time of writing).
**Severity:** data-corrupting, silent, persisted to disk
**Branch:** `rewind` · **Reported:** 2026-07-14 · **Root cause fixed:** 2026-07-15 ·
**Remaining GUI mutators fixed:** 2026-07-16
**Affected files on disk:** unrecoverable — see §7

---

## 1. Summary

IronClust stores the spike→cluster assignment **twice**. A helper that renumbers clusters
updates one copy and not the other, silently, then saves the result. Every subsequent split,
merge or delete then operates on **the wrong neuron**.

| | |
|---|---|
| **Symptom A** | splitting a unit with very few spikes yields two units with **thousands** |
| **Symptom B** | splitting a unit in a narrow depth band yields two units **hundreds of µm apart** |
| **Root cause** | `reorder_clu_by_coords_` (the `[O]` key) renumbered the per-cluster arrays but not the per-spike labels, then called `save0_()` |
| **Detection** | none — `S_clu_valid_` checks array *lengths* only |
| **Blast radius** | both of the user's `_jrc.mat` files: 179/190 and 504/544 clusters desynced |

---

## 2. The dual state representation (why this is possible at all)

```
S_clu.viClu          per-SPIKE cluster label, one per spike (17M).  <0 = deleted, 0 = unassigned
S_clu.cviSpk_clu{i}  per-CLUSTER spike indices for cluster i.       a CACHE, to avoid find() over 17M
```

Plus a family of per-cluster arrays keyed by the same index: `viSite_clu`, `vnSpk_clu`,
`vrPosX_clu`, `vrPosY_clu`, `csNote_clu`, `tmrWav_clu`, `mrWavCor`.

**`viClu` is authoritative. Everything else is derived.** `S_clu_refresh_` (irc.m:7394-7410)
shows the intended dependency chain:

```
cviSpk_clu := vi2cell_(viClu)              % 7400  -- cache from labels
vnSpk_clu  := cellfun(@numel, cviSpk_clu)  % 7401  -- from the CACHE
viSite_clu := mode(viSite_spk(cviSpk_clu)) % 7407  -- from the CACHE
```

`vrPosY_clu` likewise, via `S_clu_position_`:17620 → `S_clu_subsample_spk_`:11652.

**This chain is the trap.** The satellites derive from the *cache*, not from `viClu`. So when
something permutes the cache, the satellites follow it — and remain mutually consistent —
while `viClu` is left behind. The state *looks* healthy from every angle except the one that
matters.

---

## 3. The bug

### 3.1 The mechanism

`S_clu_select_` (irc.m:19531) reindexes fields by **name pattern**: `^v\w*_clu$`,
`^c\w*_clu$`, `^t\w*_clu$`, `^m\w*_clu$`.

> **`viClu` ends in `Clu`, not `_clu`. It matches none of them.**

That is by design — `viClu` is per-*spike*, not per-*cluster*, so a per-cluster permutation is
meaningless for it. **The caller must remap it.** `clu_reorder_` (irc.m:10227-10250) does this
correctly. `reorder_clu_by_coords_` did not:

```matlab
[~, viMap_clu] = sortrows(mrPosXY_clu, [1, 2]);   % sort clusters by (X, Y)
S_clu = S_clu_select_(S_clu, viMap_clu);          % renumber the cache + satellites
...                                                % viClu NEVER remapped
save0_();                                          % <-- persist the corruption
```

One `[O]` press → `cviSpk_clu{5}` and `find(viClu==5)` describe **two different neurons** →
written to disk.

### 3.2 Why it produces exactly these symptoms

The GUI **reads the cache**, so the unit you inspect looks correct. But `split_clu_` →
`S_clu_update_` (irc.m:11837-11840) **re-derives from `viClu`**:

```matlab
viSpk_clu1 = find(S_clu.viClu == iClu1);                    % the OLD numbering
S_clu.cviSpk_clu{iClu1} = viSpk_clu1;                       % overwrite cache with a foreign set
S_clu.viSite_clu(iClu1) = mode(S0.viSite_spk(viSpk_clu1));  % -> Symptom B
S_clu.vnSpk_clu(iClu1)  = numel(viSpk_clu1);                % -> Symptom A
```

You split the small unit you can see; the code splits whatever cluster *used to* wear that
number. Because the renumbering is **sorted by position**, the impostor is systematically far
away in depth — Symptom B is not random, it is the sort order leaking through. Measured on
this probe: `[O]` displaces 492/544 clusters, median 19 µm, **p90 270 µm, max 974 µm**.

**One cause, both symptoms, all three split paths, on a fresh sort.** No other candidate fit.

### 3.3 Nothing caught it

`S_clu_valid_` (the only validity check) compares array **lengths** against `nClu`. A total
content desync passes it. There was no invariant check anywhere.

---

## 4. How it was discovered

1. **Reported** from curation: two symptoms, three split paths, also on freshly-sorted data.
2. **First hypothesis — WRONG.** Blamed a positional-mask truncation in `split_clu_`. The
   devil's advocate refuted it by arithmetic: that path can only ever *shrink* a selection —
   small in, small out. It cannot manufacture thousands of spikes. The proposed fix was
   cosmetic and was not shipped.
3. **The "all three paths" constraint broke it open.** A defect inside any single view could
   not explain all three. Only something common to every split path could — which pointed at
   `S_clu_update_`, and from there to what could make `viClu` wrong in the first place.
4. **Confirmed by negative control**, not by inspection: a harness on a synthetic 5-cluster
   `S_clu`, calling the *real* `S_clu_select_`. With the `viClu` remap removed, the invariant
   `all(viClu(cviSpk_clu{i}) == i)` **breaks**; with it, it holds. The negative control is the
   load-bearing part — it proves the harness can detect the defect, so the pass means something.
5. **Confirmed on the user's real data** (see §7).

### Methodological failures worth recording

Four wrong claims were made and retracted during this investigation. They are recorded because
the *pattern* is the lesson:

| Claim | Why it was wrong |
|---|---|
| "positional-mask truncation is the cause" | refuted by arithmetic; would have shipped a cosmetic fix |
| "**M1 is the trigger, the last link is closed**" | asked *"do you press `[O]`?"* (unfalsifiable) instead of *"does it happen **before** you press `[O]`?"* (disconfirming). "They use it sometimes" ≠ "it preceded the failures" |
| "nothing is committed" | reported memory as fact without running `git status`; it was committed **and pushed** |
| "**the curation is recoverable — do not re-sort**" | generalised from **four** sampled cache entries to 544. The dry-run refuted it |

**The common thread: a model that fit the sampled evidence was stated as established fact.**
The dry-run existed only because of the earlier errors, and it is what caught the last one.
Every load-bearing claim in this document is now backed by a measurement or a negative control.

---

## 5. The fix (shipped in `87cd4f1`)

| # | Fix | Why |
|---|---|---|
| **M1** | `reorder_clu_by_coords_` remaps `viClu` in lockstep before `S_clu_select_`, mirroring `clu_reorder_`'s proven idiom. Refuses to reorder if `numel(viMap_clu) ~= nClu` rather than desync. | the root cause |
| **M2** | `show_drift_view.m`: `impoly_(hAx)` (was `impoly_()` → `gca`), explicit parent for `hSplit` | polygon drawn on one axes, data read from another; invisible because both tabs' axes share an identical `Position` |
| **D4** | `split_clu_`: `iClu2 = max(nClu, max(viClu)) + 1` (was `max(viClu)+1`) | could clobber a live index → `nClu` shrinks → `S_clu_valid_` fails → `S_clu_commit_` **silently reverts** the whole split |
| **E-2** | `get_clu_spk_confirmed_`: fallback flipped to `viClu` | the original guard `any(vlConfirmed) && ~all(...)` can only shrink an over-large cache — a **no-op against an under-count**. This is why `45b5333` failed to fix the same symptom on 2026-07-10 |
| **B** | new `split_clu_by_id_(iClu1, viSpk_in)` — builds the mask by `ismember` against the same list `split_clu_` uses | makes mask-length agreement structural rather than coincidental |
| **D1** | `fet2proj_` returns `viSpk01`; FigProj restored as opt-in (it was dead code in this fork) | 50 random dots were shown but all N spikes split |
| **E-1** | new `S_clu_assert_synced_`, called from `S_clu_commit_`, gated by `fCheck_clu_sync` (default 1) | **the detection that never existed.** Reports `nForeign` and `nMiss` *separately* — the key discriminator. **Warns, never gates**, because `S_clu_commit_` reverts on `~S_clu_valid_` and gating would reproduce the silent data loss |
| **doc** | CONTRACT comment on `S_clu_select_` | the next caller must not repeat this |

**Verification:** all with negative controls in MATLAB R2023b. `S_clu_assert_synced_` flags 4/4
of the deliberately-corrupted cases. `int32` class preserved; unassigned (`<=0`) spikes
untouched. M2 is **not** exercisable headlessly (`impoly_` blocks on interactive drawing) —
traced and syntax-checked only.

---

## 6. ✅ FIXED (2026-07-15, later) — `delete_clu_` carried the same bug

**Now fixed and verified with a negative control** (`scratchpad/verify_delete_clu.m`, 7/7 pass).
The analysis below is retained because it explains *why* the guard is shaped the way it is.

### ★ The landmine that a length check cannot see (found by the negative control)

The first attempt at this fix checked `numel(cviSpk_clu) == numel(viClu_keep)`. **It did not
fire, and the test caught it.** `S_clu_select_` ends with a **length-reconcile block**
(irc.m:19669-19692) that force-fits every wrong-length `v*_clu` / `c*_clu` field to `nClu_new`
— truncating, or **padding `cviSpk_clu` with `{[]}`**:

```matlab
if iscell(val)
    if numel(val) > nClu_new, val = val(1:nClu_new); else, val(end+1:nClu_new) = {[]}; end
```

So after `struct_select_safe_` skips the cache, the reconcile **repairs its length while
leaving its content unpermuted**. Observed in the control:

```
struct_select_safe_: skipped field "cviSpk_clu": Index exceeds ...
S_clu_select_: reconciled length of field "cviSpk_clu" to 4
  -> numel(cviSpk_clu) = 4  (expected 4)   <-- a length check PASSES
  -> DESYNCED clusters : 2                 <-- while the content is wrong
```

**This is the same blind spot that makes `S_clu_valid_` useless**, and it is why the shipped
guard compares **content**: the new cache must equal `S_clu_prev.cviSpk_clu(viClu_keep)`.
Any future check in this area must do likewise — **lengths in `S_clu` are actively
falsified by the reconcile block, not merely unchecked.**

### The original analysis — `delete_clu_` (irc.m:9126-9152 as it was):

```matlab
try
    S_clu = S_clu_select_(S_clu, viClu_keep);   % 9131 -- permutes cache + satellites
catch
    fprintf(2, 'delete_clu_: error selecting'); % 9132-9134 -- SWALLOWED, then continues
end
...
S_clu.viClu(vlMap) = viMap(S_clu.viClu(vlMap)); % 9145 -- remaps viClu UNCONDITIONALLY
S_clu.nClu = nClu_new;                          % 9146 -- and commits the new count
```

If 9131 fails, the cache is not remapped but **`viClu` is remapped anyway** → the exact desync
this issue is about.

### The subtle part: the `try/catch` cannot actually catch it

`S_clu_select_` delegates to **`struct_select_safe_`** (irc.m:19512-19527), which resizes each
field independently and **swallows a per-field failure with a console warning**:

```matlab
catch ME
    fprintf(2, 'struct_select_safe_: skipped field "%s": %s\n', csNames{i}, ME.message);
end
```

So if `cviSpk_clu` alone fails to resize, **no exception ever reaches `delete_clu_`'s catch**.
`S_clu_select_` returns "successfully" with the cache stale and the satellites remapped, and
line 9145 then remaps `viClu`. The guard at 9149 (`S_clu_valid_`) only checks lengths, so it
passes. **Three layers of error handling, and the failure walks through all three silently.**

### Direct evidence this happens

On `_IRC_jrc.mat`: **7,172 spikes whose `viClu` is negative (deleted) are still sitting inside
a live `cviSpk_clu` entry** (concentrated in `cache{1}`). A pure permutation *cannot* produce
this — `[O]` moves which slot holds an entry, it never injects deleted spikes into a live one.
Only a failed prune, or a delete executed on an already-desynced state, can.

### The second-order effect (why this is worse than `[O]`)

Line 9138 selects victims via `ismember(S_clu.viClu, viClu_delete)` — i.e. from `viClu`. On an
already-desynced file the user deletes **what the GUI shows** (the *cache's* cluster) while the
code marks negative **whatever `viClu` says**. The wrong spikes are deleted, scattered across
other clusters' entries. **Every delete on a desynced file compounds the damage into a new,
unrelated cluster.** This is the mechanism that made the observed corruption cumulative,
order-dependent, and therefore irreversible (§7).

### The shipped fix

Atomic: snapshot, then roll back rather than commit a half-applied remap. The second guard
compares **content**, not length, for the reason above:

```matlab
S_clu_prev = S_clu;                       % snapshot BEFORE any mutation
try
    S_clu = S_clu_select_(S_clu, viClu_keep);
catch ME
    S_clu = S_clu_prev;                   % roll back; do NOT remap viClu
    fprintf(2, 'delete_clu_: S_clu_select_ failed (%s)\n', ME.message);
    return;
end
% struct_select_safe_ can skip a field WITHOUT throwing, and the reconcile block then
% fixes its LENGTH while leaving its CONTENT stale -- so verify the permutation itself.
if isfield(S_clu, 'cviSpk_clu')
    fCache_ok = isequal(reshape(S_clu.cviSpk_clu, [], 1), ...
                        reshape(S_clu_prev.cviSpk_clu(viClu_keep), [], 1));
    if ~fCache_ok, S_clu = S_clu_prev; ... return; end
end
```

### Caller impact — `merge_clu_` (irc.m:9344)

`delete_clu_` is also the **back half of every merge**: `merge_clu_pair_` moves the spikes,
then `delete_clu_` removes the emptied source. An abort there would leave the merge
**half-applied** — spikes moved, source still present as an *empty* cluster — while
`ui_merge_clu_` calls `save_log_('merge %d %d')` **unconditionally** (irc.m:9334), logging a
merge that did not fully happen. `merge_clu_` therefore snapshots and rolls the **whole merge**
back, so it either completes or leaves nothing behind.

**⚠ Honest scope: this rollback is defence-in-depth, and is probably UNREACHABLE today.**
Verified against the real 547-cluster file (`scratchpad/verify_merge_clu_real.m`): a cache
malformed enough to make `S_clu_select_` fail **also makes `S_clu_wav_` fail first** — it
indexes `cviSpk_clu{iClu}` for `iClu = 1..nClu`, so it throws before `delete_clu_` is ever
reached. And **that throw is already safe**: MATLAB value semantics mean the caller's
`S0.S_clu = merge_clu_(S0.S_clu, ...)` (irc.m:9316) never performs the assignment, and the
unconditional `save_log_` at 9334 never runs. Confirmed: caller state byte-identical.

So the reachable, valuable guard is the one in **`delete_clu_`**, which *is* called directly
(irc.m:9094 UI delete, 9530 pending delete, 19411 auto-delete) with no waveform pass in front
of it to throw first. Kept in `merge_clu_` anyway because `delete_clu_`'s abort returns
**normally** (it does not throw), so if any future change makes the upstream tolerant of a
short cache, this becomes the only thing preventing a silently half-applied, falsely-logged
merge. **Cost:** one transient `S_clu` copy per merge (~250-500 MB at 17.6M spikes; ~2% of a
17 GB session).

### Verification on real data (`scratchpad/verify_merge_clu_real.m`) — 5/5, read-only

Against the freshly-sorted 547-cluster / 17.6M-spike file:

| Check | Result |
|---|---|
| real merge completes (Clu 2 → Clu 1) | nClu **547 → 546** |
| merged cluster absorbed both parents | 155,204 + 367,046 → **511,712** |
| `S_clu_assert_synced_` after a real merge | **0 stale** |
| malformed cache → fails loudly, does not half-apply | throws |
| caller's `S_clu` untouched on failure | byte-identical |

**Note:** 511,712 ≠ 522,250 is *correct* — `S_clu_refrac_` (irc.m:9348) drops refractory
violations, here 10,538 spikes (2.02%). An earlier version of this test asserted an exact
`n1+n2` and failed; the test was wrong, not the code.

### Verification (`scratchpad/verify_delete_clu.m`) — 7/7

| Check | Result |
|---|---|
| **negative control** reproduces the desync (guard removed) | **2 clusters desynced** |
| fixed `delete_clu_` leaves no desync | 0 |
| rollback: `viClu` byte-identical to input | ✔ |
| rollback: `nClu` unchanged | ✔ |
| **happy path** still deletes (healthy cache) | nClu 5 → 4 |
| happy path leaves no desync | 0 |
| happy path renumbers survivors to 1..4 | ✔ |

The negative control is load-bearing: it fails without the fix, so the pass is meaningful.

### Also fixed in the same pass

**`post_merge_wav_` (irc.m:4283) — CONFIRMED and fixed.** The earlier "unverified" report was
correct, and the defect was worse than described. Line 4286 stripped
`mrWavCor` / `trWav_raw_clu` / `tmrWav_raw_clu`, then 4287 returned early when
`fSave_spkwav=0` — **before** the rebuild at the bottom that restores them. Two failures:

1. **Latent crash.** The signature is `[S_clu, nClu_merge]`, and `auto_merge_` (irc.m:19440)
   requests **both** outputs with `fMerge=1`. On the early return — and on the `fMerge==0`
   fall-through — `nClu_merge` was **never assigned** → *"Output argument 'nClu_merge' is not
   assigned"*. Dormant only because this user runs `fSave_spkwav=1`.
2. **Cache destruction.** `mrWavCor` was removed and never rebuilt.

Fix: initialise `nClu_merge = 0` on entry, and move the early return **before** the
`rmfield_` so the bail-out path is a true no-op. Verified 6/6
(`scratchpad/verify_post_merge_wav.m`): two-output call no longer errors, `nClu_merge == 0`,
and all three fields are preserved byte-identically.

**parpool undersize-reuse (irc.m:2569) — fixed.** Was `elseif hPool.NumWorkers > nWorkers`
(only ever *shrank* an oversized pool), so a stale undersized pool was silently reused and the
whole per-site loop ran narrow. Now `~= nWorkers` — resizes in either direction, and logs it.
No-op for a correctly-sized pool, so it cannot disturb a run already at the right width.

### Remaining (lower priority)

| Item | Location | Note |
|---|---|---|
| `struct_select_safe_` skips silently | irc.m:19512-19527 | the *enabler*. Resilience is deliberate (a malformed quality array shouldn't abort a merge) — but skipping `cviSpk_clu` is categorically different from skipping `vrSnr_clu`. Consider a **critical-field list**. Not changed: it is called on the sort path, and the `delete_clu_` content guard already blocks the damaging case locally. |
| **length-reconcile block** | irc.m:19669-19692 | **actively falsifies lengths** by padding `cviSpk_clu` with `{[]}`. Makes `S_clu_valid_` vacuous and defeats any length-based guard. It does warn on `fprintf(2,...)`. Consider excluding `cviSpk_clu`, or promoting the warning to a hard failure. |
| `viClu_prematch` | irc.m:4171-4173 | **NOT a bug** — set and read on adjacent lines, transient. It is a per-spike copy (~68 MB) persisted into every `_jrc.mat` for no reason. Cleanup only. |
| `P.viShank_site` all `1`s | `IRC_all.prb` / `IRC.prb` (not `irc.m`) | probe declared single-shank, but Neuropixels 2.0 is **4 shanks × 2 columns**. Affects `[O]`'s sort order among other things. |

---

## 7. Data impact — the affected files are NOT recoverable

Measured on `E:\scratch\tmp\catgt_260324_afm18349_g0\...`:

| | `_IRC_jrc.mat` | `_irc_all_jrc.mat` |
|---|---|---|
| nClu | 190 | 544 |
| spikes | 3,414,842 | 17,616,506 |
| **desynced clusters** | **179 / 190** | **504 / 544** |
| delete ops (`min(viClu)`) | −9 | **−247** |
| unassigned | 5.97% | 36.96% |

### Why no repair exists

The hoped-for model was that the two sides encode the **same partition under different labels**
— if so, recover the permutation σ and relabel. **Refuted by the one non-circular measurement:**

| purity check (`_IRC_jrc.mat`) | |
|---|---|
| cache entries spanning exactly 1 `viClu` label | 138 / 190 |
| **spanning >1 label** | **52** |
| **max labels in a single entry** | **14** |

**52/190 clusters are genuinely mixed → the two sides are DIFFERENT partitions → σ does not
exist.** Confirmed by the dry-run: **557,123 spikes claimed by >1 cluster** (the cache is not
even a partition), **413,533 orphaned**, 7,172 deletions resurrected. `repair_clu_sync.m`
refuses to write, with five blocking reasons.

**Cause: the damage compounded.** Every post-corruption split called `S_clu_update_`, writing
foreign spike sets over entries other clusters owned; every delete scattered wrong negatives.
Cumulative and order-dependent → **no single global transform inverts it.**

### ⚠ The "direction check" was an artifact — do not resurrect it

An earlier conclusion — *"`viSite_clu`/`vnSpk_clu` agree with the cache at ~100%, therefore the
cache is authoritative"* — is **retracted**. Per §2, those fields **derive from the cache**;
`S_clu_select_` permutes them together with it, so they agree **by construction**, pristine or
garbage. **Proof: the check reports `188/188 (100.0%)` on the very file whose cache has 557k
overlaps and a 14-label entry.** It cannot fail, so it never meant anything.

Any future recovery attempt must use a witness **not derived from the cache** — e.g. recompute
mean waveforms from candidate labels and correlate against the raw data in `_spkwav.jrc`
(a real neuron is a tight cluster; a mislabelled mixture is not). Note `tmrWav_clu` is **not**
such a witness: `S_clu_wav_` builds it from the cache too.

---

## 8. Recommendations

1. **Fix `delete_clu_` (§6) before any further curation.** It is the same defect class as the
   root cause, still live, and it *compounds* damage on every press.
2. **Re-sort the affected recordings.** The sort pipeline is **clean** — every sort-time
   `viClu` mutator traces to `S_clu_refresh_`, which rebuilds the cache from `viClu`
   (`S_clu_sort_`:11669 remaps via `mapIndex_` at 11684 **and** refreshes at 11687). The
   corruption is purely a GUI-curation artifact. **Note `load0_` does *not* refresh** (bare
   `load` + `set(0,'UserData')`), so a desync on disk survives reload — which is why detection
   at commit time matters.
3. **Keep `fCheck_clu_sync = 1`.** It is the only thing standing between a future desync and
   another two months of lost curation.
4. **Adopt the invariant as the codebase's contract:**
   `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for every `i`.
   Any function touching cluster identity must preserve it.
5. **Prefer a rollback-on-failure discipline over resilient-skip** for *identity-bearing*
   fields. `struct_select_safe_`'s tolerance is right for quality metrics and wrong for
   `cviSpk_clu`. A half-applied identity remap is worse than a failed operation.
6. **Treat "the check passed" as meaningful only if the check can fail.** Two of this
   investigation's checks could not: the direction check (circular by construction) and
   `S_clu_assert_synced_` on repaired output (compares what the repair forced to agree).
   Negative controls are cheap; use them.

## 9. Next steps

**Done (verified with negative controls):**
- [x] **`delete_clu_` rollback fix (§6)** — 7/7
- [x] **`post_merge_wav_`** — confirmed and fixed, 6/6 (the earlier "verify or drop" is resolved)
- [x] **parpool undersize-reuse (irc.m:2569)** — fixed
- [x] **Test B** — re-sort ran clean: `S_clu_assert_synced_` = **0/547** on the fresh output, so
      the sort path is clean in practice, not just by tracing

**Still open:**
- [ ] Consider a critical-field list in `struct_select_safe_`, and excluding `cviSpk_clu` from
      the length-reconcile block (irc.m:19669-19692) — it falsifies the lengths that
      `S_clu_valid_` trusts. (Planned as P3b in `logs/plan_cluster_identity_hardening_20260716.md`.)
- [ ] Propagate the abort signal to `delete_clu_`/`merge_clu_` callers so an abort can't write a
      phantom log entry (plan P2). Load-time detection (plan P1) + `[O]`-path detection (plan P3a).
- [ ] **Test A** — catch a live failure: curate with the console visible, watch for
      `delete_clu_: error selecting` / `struct_select_safe_: skipped field "cviSpk_clu"`. This is
      what would distinguish `delete_clu_` from `[O]` as the *origin* (not required now that both
      are fixed; kept as a diagnostic if the symptom recurs).
- [ ] Fix `viShank_site` in the `.prb` (4-shank Neuropixels 2.0 declared as single-shank; CID-14).

## 10. References

- `logs/investigation_split_root_cause.md` — full trace, measurements, retractions
- `logs/changes_log20260715.md` — changelog for `87cd4f1`
- `matlab/repair_clu_sync.m` — diagnostics + refusing repair (dry-run default)
- `87cd4f1` — the fixes · `83776fc` — investigation + repair tool
- `45b5333` (2026-07-10) — an **earlier attempt at this same symptom that guarded the wrong
  direction** and was a no-op. Its existence is evidence this bug has been misdiagnosed before.
