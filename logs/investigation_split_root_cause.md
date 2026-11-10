# Investigation: manual-curation split produces wrong clusters

> **Tracker:** this is the raw investigation log. For status of every issue it uncovered, see
> [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md).

---

# ★ THE ANSWER

## 1. WHY it happens (hypothesis)

**`S_clu.cviSpk_clu` (the per-cluster spike cache) and `S_clu.viClu` (the per-spike labels)
have been permuted relative to each other. `cache{i}` holds cluster σ(i)'s spikes.** Measured
on the real data: **504/544** and **179/190** clusters affected (§3.2).

Everything you see is drawn from `cache{i}` — so you are looking at cluster σ(i). But
`split_clu_` finishes by calling `S_clu_update_`, which rebuilds from `find(viClu==i)` — a
**different cluster**. Hence:
- **Symptom A** — the split "yields thousands": you were shown σ(i) (small); the rebuild used
  i (large).
- **Symptom B** — children land hundreds of µm apart: `viSite_clu` is recomputed as
  `mode(viSite_spk(...))` over that different cluster. Measured on your geometry: a
  mis-identified cluster lands **p90 = 270 µm, max = 974 µm** away in depth (§3.2.1).

**The prime suspect for creating the permutation: `delete_clu_` (irc.m:9126-9152).** It calls
`S_clu_select_` to permute the cache inside a `try/catch` that only **prints** on failure
(9130-9134), then remaps `viClu` **unconditionally** at 9145. `struct_select_safe_`
(irc.m:19512) independently **skips any field it cannot resize, by design, with a console-only
warning** — so `cviSpk_clu` alone can be left un-permuted while every other per-cluster field
is remapped. Either route ⇒ cache and labels disagree, silently.

**Why this fits when nothing else did:**
- It needs **no `[O]`** — matching your report that the problem predates reordering.
- It needs **no re-sort** — every sort path ends in `S_clu_refresh_`, which rebuilds the cache
  from `viClu` (§7.1). The sort output should be clean.
- **You deleted 247 times on this file** — `iClu_del = min(viClu)-1` decrements per delete, so
  `min(viClu) = -247` is a *counter*: 247 opportunities to fire. (`_IRC_jrc.mat`: -9 → 9
  deletes, 179/190 desynced.)
- It is **self-amplifying**: once any field's length is off, `struct_select_` throws for it on
  the next delete → skipped → desync widens. That explains 504/544.
- It is **intermittent** — only when `struct_select_` actually throws.

**Confidence:** the mechanism is confirmed in code and satisfies every constraint. It is **not
yet confirmed as the origin in your specific files** — see §2. This distinction is being kept
deliberately: this bug has now defeated two fixes (`45b5333`, and nearly this session's) by
exactly the leap of "plausible mechanism ⇒ diagnosis".

**A second, independent candidate remains:** `reorder_clu_by_coords_` (`[O]`) has the same
shape and its X-then-Y ordering on your 4-shank probe moves **492/544** clusters — remarkably
close to the 504 observed (§3.2.1). It is already fixed in `87cd4f1`. Your C4 ("predates
reordering") is the only thing arguing against it, and C4 has not been tested.

## 2. HOW to test it

**Test A — catch it in the act (cheapest, most direct).** The failure already prints. Run a
curation session with the console visible and delete clusters as you normally would. Watch for:
```
delete_clu_: error selecting
struct_select_safe_: skipped field "cviSpk_clu": <message>
```
Then immediately:
```matlab
S0 = get(0,'UserData');
irc('call','S_clu_assert_synced_',{S0.S_clu,'after-delete'})
```
0 before the delete and >0 after **proves it**, and the skipped-field message names the exact
field and reason. *(`S_clu_assert_synced_` ships in `87cd4f1`.)*

**Test B — sort vs curation (settles `[O]` vs delete).** On a **copy** — `irc sort` overwrites
`_jrc.mat` and would destroy your curation:
```matlab
irc('sort','copy.prm');  S0 = load('copy_jrc.mat');
irc('call','S_clu_assert_synced_',{S0.S_clu,'fresh-sort'})
```
- **0** → the sort is clean; corruption is introduced by the GUI (delete and/or `[O]`).
- **>0** → both static sweeps are wrong and the sort itself is implicated (§8.2).

**Test C — bisect the history.** `_log.mat` holds `cS_log`/`miClu_log` snapshots. Running the
check across successive log entries locates the first desynced state and the operation that
caused it, without re-sorting.

## 3. HOW to recover the data — ⛔ NO KNOWN WORKING METHOD (see retraction below)

> ## ⛔ RETRACTED — the repair does NOT work. Measured 2026-07-15.
>
> An earlier revision of this section claimed "the cache is internally coherent, σ is
> recoverable, the curation is salvageable, do not re-sort." **That was wrong.** It
> generalised from four sampled cache entries. `repair_clu_sync.m` was dry-run on
> `_IRC_jrc.mat` and **failed to converge**:
>
> ```
> spikes claimed by >1 cluster : 557,123    <-- the cache is NOT a partition
> spikes ORPHANED (N->0)       : 413,533    <-- in no cache entry at all
> deleted labels preserved     : 71,430 / 78,602  <-- 7,172 deleted spikes RESURRECTED
> stale clusters after repair  : 62 / 190   (was 179)  -> DID NOT CONVERGE
> ```
>
> **Three independent reasons the σ-recovery model is dead:**
> 1. **The cache entries OVERLAP.** 557k spikes belong to >1 entry, so `viClu(cache{i}) = i`
>    is a last-writer-wins race. `cache{3}` holds 23,366 spikes; only 325 survive as label 3.
>    A permutation of a valid partition cannot overlap — therefore the cache is not one.
> 2. **413k spikes are in no cache entry**, and would be silently orphaned to unassigned.
> 3. **Deleted clusters still hold cache entries** (`S_clu_select_` never dropped them when it
>    failed), so the rebuild resurrects 7,172 deleted spikes as live clusters.
>
> **Where the overlap came from:** every split performed *after* the corruption called
> `S_clu_update_`, which writes `cache{i} = find(viClu==i)` — a *foreign* spike set — over
> entries other clusters already owned. Post-corruption splits did not merely fail; they
> **compounded** the damage into the cache. This also means the damage is **cumulative and
> ordered**, so no single global transform can undo it.
>
> **Current position: these two files are probably NOT repairable by any simple transform.**
> The log-bisect (§2 Test C) is the only remaining avenue — find the last `_log.mat` entry that
> passes `S_clu_assert_synced_` and replay from there — and it may recover nothing if the
> corruption predates the log. Re-sorting is back on the table. `repair_clu_sync.m` is retained
> because its *diagnostics* are useful and it correctly refuses to write; do not trust its
> repair path.

**Superseded reasoning (kept for the record):** the cache appeared internally coherent — each
sampled `cache{i}` contained exactly one cluster's spikes (§3.2), suggesting `cache` and
`viClu` encoded the **same partition** under different labels, with σ recoverable.

### ⛔ RETRACTED (2026-07-15): "the CACHE is authoritative" was an ARTIFACT, not a measurement

**The direction check is circular. It proves nothing.** Raised by the devil's-advocate review,
verified against the source. **Every field I compared derives FROM the cache:**

| Field | Derived from | Where |
|---|---|---|
| `cviSpk_clu` | `viClu` | `S_clu_refresh_` irc.m:7400 (`vi2cell_`) |
| `vnSpk_clu` | **`cviSpk_clu`** | irc.m:7401 — `cellfun(@numel, S_clu.cviSpk_clu)` |
| `viSite_clu` | **`cviSpk_clu`** | irc.m:7407 — `mode(viSite_spk(S_clu.cviSpk_clu{iClu}))` |
| `vrPosY_clu` | **`cviSpk_clu`** | `S_clu_position_`:17620 → `S_clu_subsample_spk_`:11652 |

and `S_clu_update_`:11838-11840 computes `cviSpk_clu`, `viSite_clu`, `vnSpk_clu` from **one
`find()` in three consecutive lines**.

So when `S_clu_select_` permutes the per-cluster arrays, it permutes the cache **and its own
derivatives together, as a unit**. They stay mutually consistent *by construction* — whether
the cache is pristine or garbage. **`viSite_clu` agreeing with the cache 543/544 is the same
number read twice.** It would report ~100% either way. It is co-movement, not correctness.

The table below is retained only to show what the artifact looks like. **Do not cite it as
evidence.** `repair_clu_sync.m`'s `fCacheAuthoritative` gate (line 78) is decorative.

| | `_IRC_jrc.mat` | `_irc_all_jrc.mat` |
|---|---|---|
| clusters compared | 188 | 544 |
| `viSite_clu` agrees with cache | 188 (100%) | 543 (99.8%) |
| `viSite_clu` agrees with `viClu` | 62 (33.0%) | 42 (7.7%) |
| `vnSpk_clu` agrees with cache | 188 (100%) | 543 (99.8%) |
| `vnSpk_clu` agrees with `viClu` | 11 (5.9%) | 40 (7.4%) |
| `vrPosY_clu` agrees with cache | 161 (85.6%) | 514 (94.5%) |
| `vrPosY_clu` agrees with `viClu` | 55 (29.3%) | 44 (8.1%) |

**The `vrPosY_clu` shortfall is not a mixed-state signal either** — it is sampling noise.
`S_clu_subsample_spk_` filters to centre-site spikes (11655), takes a mid-time window
(11661), then subsamples to 1000 (11663). The stored median is over *that*; my test compared
it to the median over the *full* set at <5 µm tolerance. Different quantities.

**What the check DOES discriminate** (its one real, narrow property): it separates "the cache
side moved as a unit" from "the cache alone went stale while `viSite_clu` tracked `viClu`".
That rules out a lone-cache-staleness story. It says nothing about which numbering is *right*.

Nor does it discriminate `delete_clu_`'s swallowed failure from `[O]` — both leave the
per-cluster fields mutually consistent with `viClu` out of step. §2 Test A settles that.

### ★ PURITY — the one non-circular measurement, and it is decisive (2026-07-15)

The honest question is not "which side is authoritative" but: **are cache and `viClu` the same
partition under different labels** (σ exists → relabelling is identity-safe), **or different
partitions** (σ does not exist → nothing reconciles them)? A pure relabelling ⟺ every cache
entry maps onto exactly **one** `viClu` label. Measured on `_IRC_jrc.mat`:

| | |
|---|---|
| cache entries spanning exactly 1 `viClu` label | 138 / 190 |
| **cache entries spanning >1 label** | **52** |
| **max labels inside a single cache entry** | **14** |

**52 of 190 clusters are genuinely mixed. The two sides describe DIFFERENT partitions. No
relabelling — no σ — can reconcile them.** This is not "unproven"; it is **refuted**.

**And the direction check reports `188/188 (100.0%)` "cache is authoritative" on this very
file** — a cache with 557,123 overlapping spikes and an entry spanning 14 labels. That is the
circularity demonstrated empirically: **the check awards a perfect score to a cache that is
not even a partition.** It cannot fail, so it never meant anything.

### ★ NEW EVIDENCE (2026-07-15): 7,172 DELETED spikes are sitting inside cache entries

Surfaced by the architect review's resurrection finding, then measured. On `_IRC_jrc.mat`,
**7,172 spikes whose `viClu` is negative (deleted) still appear in a live `cviSpk_clu` entry**
— concentrated in `cache{1}`, matching the assert's `Clu1: 7172 cached spikes belong elsewhere`.

**A pure permutation cannot produce this.** `[O]`/`S_clu_select_` permutes *which slot* holds
an entry; it never injects deleted spikes into a live one. Two mechanisms can:

1. **`delete_clu_`'s prune failed** — `struct_select_safe_` (19524) silently skipped
   `cviSpk_clu`, so the deleted cluster's entry was never dropped; `viClu` went negative
   (9139) while the cache kept the spikes.
2. **A delete ran on an already-desynced state** — `delete_clu_` marks negative whatever
   `viClu == iClu` says, but the user deleted what the **GUI showed** (the *cache's* cluster).
   The wrong spikes go negative, and they are scattered across other clusters' cache entries.

Both implicate **`delete_clu_` (irc.m:9126-9152)**, and (2) means **each delete on a desynced
file compounds the damage into a new, unrelated cluster**. This is independent support for the
"cumulative and ordered" conclusion in the retraction — and a concrete reason **not to curate
further on the unfixed code**.

**Do not over-read it as settling the ORIGIN.** It shows deletes are *implicated*; it does not
prove they *started* it. §2 Test A still settles that.

### The only honest argument for rebuilding from the cache

Not a measurement — a **judgement about intent**, and it should be labelled as one:

> The GUI **displays** the cache. The clusters the user inspected, judged, split and annotated
> are therefore the **cache's** clusters. Relabelling `viClu` to the cache restores consistency
> across the maximum number of fields **and matches what the user actually saw.**

That is a reasonable argument. It is not proof, and it collapses anyway for the clusters where
cache and `viClu` describe **different partitions** rather than the same one relabelled — see
the retraction block above, and the `cache{3} → viClu labels [25 26]` evidence in §3.2.

### ⛔ The repair — DOES NOT WORK. Retained for the record; do NOT run it.

> **This procedure is REFUTED. Do not follow it on real data.** It was written before the
> `repair_clu_sync.m` dry-run and the purity measurement, both of which killed it (see the
> `⛔ RETRACTED` blocks at the top of §3 and the `★ PURITY` result). The relabel-from-cache
> below assumes cache and `viClu` are the *same partition relabelled*; they are **different
> partitions** (52/190 cache entries span >1 label; 557k spikes claimed by >1 cluster; 413k
> orphaned; 7,172 deletions resurrected). Running it corrupts the file further. **Re-sort is the
> only recovery.** The code is kept verbatim only so this record shows exactly what was tried.

~~**Work on a copy.** Rebuild `viClu` from the cache, preserving deleted clusters:~~

```matlab
% ⛔ DO NOT RUN — refuted; produces overlaps/orphans/resurrections. Kept for the record only.
vcSrc = 'yourfile_jrc.mat';  vcDst = 'yourfile_REPAIRED_jrc.mat';
S0 = load(vcSrc);  S = S0.S_clu;
n = min(double(S.nClu), numel(S.cviSpk_clu));

% 1. Clear only the POSITIVE labels. Negatives are deleted clusters (keep them).
S.viClu(S.viClu > 0) = 0;

% 2. Relabel from the cache.  <-- THE FLAW: the cache is not a partition, so this
%    last-writer-wins loop overlaps and orphans spikes. It cannot reconcile the two sides.
for i = 1:n
    v = S.cviSpk_clu{i};
    if ~isempty(v), S.viClu(v) = int32(i); end
end

% 3. Verify — and note this check is near-vacuous here: it compares viClu against the very
%    cache step 2 forced it to match. On the observed files it still reports >0 (overlaps).
S0.S_clu = S;
irc('call','S_clu_assert_synced_',{S0.S_clu,'after-repair'})

% 4. (never reached in practice — step 3 does not report 0 on the observed files)
save(vcDst, '-struct', 'S0', '-v7.3');
```

Also do **not** run `S_clu_refresh_` as a repair: it rebuilds the cache *from* `viClu` — the
opposite direction — and would lock in the corruption irreversibly.

**Why it fails, in one line:** the cache is not a partition (it overlaps and has gaps), so no
relabelling of `viClu` can equal it. The definitive test was `repair_clu_sync.m`, which refuses
to write with five blocking reasons. See CID-12 in the tracker.

---

**Status: OPEN — but narrowed to a single, testable claim.** Root cause **not established**.
Six real bugs were found and fixed along the way (commit `87cd4f1`); **none is confirmed as
the cause of the reported symptoms**.

**MEASURED (§3.2):** the desync is **real, massive, and present in the user's actual files** —
**504/544** and **179/190** clusters disagree between `cviSpk_clu` and `viClu`; 10.7M and 2.9M
spikes misfiled. Independently reproduced by the user. It is a **permutation**: `cache{i}`
holds cluster σ(i)'s spikes — internally coherent, wrongly indexed. This fully explains both
symptoms: views read `cache{i}` (one cluster), `S_clu_update_` rebuilds from
`find(viClu==i)` (a different one).

**REMAINING QUESTION:** does the **sort** produce it, or `[O]` (`reorder_clu_by_coords_`)
during curation? Both files supplied are post-curation, so they cannot distinguish. §3.3
argues the sort is clean by construction (every path ends in `S_clu_refresh_`) and that `[O]`'s
X-then-Y ordering matches the observed shuffle — **but that is reasoning, not measurement, and
this investigation has already been wrong twice by exactly that route.** §8.1 is the deciding
test.

**The meta-conclusion, which may matter more:** commit `45b5333` (2026-07-10) reports the
*identical* symptom and its fix guards the **wrong direction** — it is a no-op against an
under-counting cache (§3.1). This bug has now survived two fix attempts, and this session
nearly shipped a third. Each round found *a* real defect that could plausibly explain the
symptom, and shipped without confirming the mechanism against real data.

**Branch:** `rewind` · **Buggy code as observed by the user:** `e65776c` (the working tree now
contains the fixes, so the original must be read via `git show e65776c:matlab/irc.m`).

---

## 1. The reports

- **Symptom A** — splitting a unit that *should have very few spikes* yields two units with
  **thousands** of spikes.
- **Symptom B** — splitting a unit that looks *consistently in a very narrow Y (depth) band*
  yields two units **hundreds of µm apart**.

Both intermittent ("sometimes").

## 2. Constraints (established by asking, in order)

| # | Constraint | Consequence |
|---|---|---|
| C1 | Paths used: **auto-split** (PCA dialog), **FigTime `[S]`**, **drift-view `[S]`**. Not FigProj. | Any mechanism local to one view is insufficient. |
| C2 | Happens on a **freshly-sorted** dataset. | Kills curation-induced cache drift as the sole cause. |
| C3 | The user **does** press `[O]` (reorder by coords). | Initially taken as confirmation of M1. **This was a mistake — see §5.** |
| C4 | The problem is present **after sorting but BEFORE reordering**. | **Kills M1 as the trigger.** Whatever it is, it is in the sort output or in code reachable with no reorder. |

C4 arrived last and invalidated the conclusion drawn from C3.

---

## 3. The structural argument (the spine of the investigation)

This is the one piece of reasoning that has survived every round, and it heavily constrains
the answer.

**`split_clu_` cannot create spikes.** It partitions one list into two:

```matlab
viSpk2 = viSpk1(vlIn);
viSpk1 = viSpk1(~vlIn);
```

Total is conserved. So a split *yielding* thousands cannot come from the partition. The only
route is `S_clu_update_` (orig irc.m:11704-11716), which re-derives everything from `viClu`:

```matlab
viSpk_clu1 = find(S_clu.viClu == iClu1);                      % <-- the only source of "more"
S_clu.cviSpk_clu{iClu1} = viSpk_clu1;
S_clu.viSite_clu(iClu1) = mode(S0.viSite_spk(viSpk_clu1));    % -> Symptom B
S_clu.vnSpk_clu(iClu1)  = numel(viSpk_clu1);                  % -> Symptom A
```

**Therefore, for a unit that DISPLAYS as tiny to BECOME thousands, the cache must
UNDER-count relative to the labels:**

```
numel(S_clu.cviSpk_clu{i})  <<  sum(S_clu.viClu == i)
```

Because every view reads the **cache** — `getFet_clu_` (FigTime), `show_drift_view.m:44`
(drift view), `get_clu_spk_confirmed_` (auto-split), `S_clu_time_` — so the unit looks tiny;
while `S_clu_update_` rebuilds from **`viClu`**, so it explodes.

This simultaneously explains **Symptom B**: `viSite_clu` is recomputed as
`mode(viSite_spk(...))` over the *larger, hidden, spatially broader* population, so the
children's peak sites land far from where the displayed unit appeared to be.

It also explains why **all three paths** fail identically (C1): they differ only in how they
build the mask; they all funnel into `split_clu_` → `S_clu_update_`.

**Refinement (adversarial review, confirmed):** only **`iClu1`** can balloon. Because
`iClu2 = max(viClu)+1`, **no spike anywhere carries label `iClu2`** before
`S_clu.viClu(viSpk2) = iClu2`, so `find(viClu==iClu2)` returns *exactly* what was circled.
The new child is therefore incapable of ballooning — the parent absorbs the hidden
population. Any report of "two units with thousands" should be read as *one child correct,
one child exploded*, or as a total that far exceeds what was displayed.

**This argument is the reason the investigation is now focused on "where can the cache
under-count?" rather than on the split code itself.**

---

## 3.1 THE DIRECTION — and why the previous fix (45b5333) failed

This is the most important finding of the investigation.

The desync must be **cache UNDER-counts** (`nMiss > 0`), never over-counts. That single fact
is decisive, because of how the existing guard is written (orig irc.m:9787-9789):

```matlab
vlConfirmed = S_clu.viClu(viSpk1) == iClu1;
if any(vlConfirmed) && ~all(vlConfirmed)
    viSpk1 = viSpk1(vlConfirmed);
end
```

`get_clu_spk_confirmed_` can **only shrink an over-large cache**. Against an **under-large**
cache, every cached spike *does* confirm → `all(vlConfirmed)` is true → **the guard is a
no-op**. So:

- no truncation, no console warning, `nSpk1 == numel(vlIn)` — everything looks healthy
- the split proceeds cleanly on the small displayed list
- `S_clu_update_` then rebuilds `iClu1` from `viClu` → **thousands** (Symptom A)
- `mode(viSite_spk(...))` over the hidden population → **hundreds of µm** (Symptom B)

**Commit `45b5333`'s subject line is literally "fix: cluster split could balloon a tiny
cluster to thousands of spikes."** The identical symptom was reported before, on
2026-07-10. That fix introduced `get_clu_spk_confirmed_` — which guards the **wrong
direction** and is a no-op against the actual failure. Its own comment is the tell:

> *"…which can disagree with the cache after some merge/reorder operations… falls back to the
> raw cache… empirically remains reliable in practice."*

That session **observed the desync, never found its origin, and papered over it**. This
session then repeated the same error twice more (the positional-mask diagnosis, then M1).
**Three fixes, three unverified mechanisms, same bug.** The pattern is the finding: each
round located *a* real defect that could plausibly produce the symptom, and shipped without
ever confirming the mechanism against the user's data.

---

## 3.2 MEASURED ON REAL DATA (2026-07-15) — the desync is REAL and MASSIVE

The user supplied `E:\scratch\tmp\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0`.
The check of §4 was run on both sorted results. **The deduction of §3 is now an observation.**

| | `_IRC_jrc.mat` (Jun 9) | `_irc_all_jrc.mat` (Jul 15) |
|---|---|---|
| `nClu` | 190 | 544 |
| `numel(viClu)` | 3,414,842 | 17,616,506 |
| **clusters with `nMiss>0`** | **177 / 190** | **504 / 544** |
| **clusters with `nForeign>0`** | **179 / 190** | **504 / 544** |
| spikes `viClu` claims, cache omits | 2,919,246 | 10,721,344 |
| `min(viClu)` | **-9** | **-247** |
| unassigned (`viClu<=0`) | 203,750 (5.97%) | 6,510,875 (**36.96%**) |

**Config (answers §9.1):** `vcCluster = 'isosplit'` (the **label-based** path — `fLabelClu`,
skips `postCluster_`, the least battle-tested branch), `post_merge_mode = 17` / `1`,
`post_merge_mode0 = 17`, `min_count = 30`, `fSave_spkwav = 1`, `maxWavCor = 0.99`,
`nSites_fet = 9`, `nShow_proj = 5` (not the default 50), `fText = 0`.

### It is a PERMUTATION, not a shift
Offset testing (`cache{i+k} == find(viClu==i)`) found **no** k with a meaningful hit rate
(best: k=0 at 5.8% / 7.4%). But the label composition of individual cache entries is decisive:

```
_IRC_jrc.mat:   cache{2}   -> viClu label 3          (single label)
                cache{3}   -> viClu labels [25 26]
                cache{111} -> viClu label 110        n=134015, exact
                cache{112} -> viClu label 111        n=121954, exact
_irc_all_jrc:   cache{2}   -> viClu labels [0 281 282]
                cache{3}   -> viClu label 291
                cache{111} -> viClu label 138
                cache{112} -> viClu label 140
```

**Each cache entry holds exactly one cluster's spikes — filed under the wrong index.** The
cache is internally coherent; only the *indexing* is wrong. That is the exact signature of
`S_clu_select_` applying a permutation that `viClu` never received (§6, the
`S_clu_select_` contract). An arbitrary permutation — which is what `sortrows`-by-position
produces — not the constant offset a renumbering bug would give.

This **fully explains both symptoms** and needs no further mechanism: every view reads
`cache{i}` (shows cluster σ(i)), `S_clu_update_` rebuilds from `find(viClu==i)` (a *different*
cluster) → wrong count (**A**) and wrong `mode(viSite_spk(...))` (**B**).

### What this does NOT yet establish
**Both files are POST-CURATION, not fresh sorts.** They contain `iCluCopy`, `hCopy`,
`hPaste`, `cviMerge_pending`, `viDelete_pending` — GUI state. So they cannot distinguish:

- **(a)** the sort produces the desync, versus
- **(b)** `[O]` (`reorder_clu_by_coords_`) produced it during curation — which fits *perfectly*:
  it applies `sortrows` by (X,Y) → an arbitrary permutation → and `S_clu_sort_(S_clu,
  'viSite_clu')` (irc.m:3894) already position-orders clusters during `post_merge_`, so `[O]`
  yields a **near-identity permutation with local swaps** — exactly the observed
  `cache{111}->110`, `cache{112}->111` pattern.

**The user reported the symptom predates `[O]` (C4), which contradicts (b). That contradiction
is now the crux of the investigation.** Resolving it requires a `_jrc.mat` straight out of
`irc sort` with no GUI interaction (see §8).

### 3.2.1 QUANTITATIVE FINGERPRINT — `[O]`'s damage matches the observed damage

Probe geometry read from the user's `P` (`_irc_all_jrc.mat`):

```
nSites = 384
X: unique = [27 59 277 527 559 809]      -> 4 groups ~250um apart, 32um columns within
Y: range  = [0 1425] um, 96 distinct
P.viShank_site: single value 1           <-- SEE 3.2.2, this is wrong
```

Four X-groups at ~250 µm pitch with 2 columns each = **Neuropixels 2.0, 4 shanks × 2 columns**
(confirmed by the user). **X is therefore SHANK position, spanning 0-809 µm.**

`reorder_clu_by_coords_` sorts `sortrows(mrPosXY_clu, [1, 2])` — **X first**, i.e. **by shank
first**, destroying the depth ordering that `post_merge_`'s `S_clu_sort_(S_clu,'viSite_clu')`
(irc.m:3894) established. Simulated on the user's actual 544 cluster centroids:

| Measure | Value |
|---|---|
| clusters that move under `[O]` (X-then-Y vs identity) | **492 / 544** |
| clusters actually desynced in the file (§3.2) | **504 / 544** |
| `\|Y(new slot) − Y(old slot)\|` — how far a mis-identified cluster lands in depth | median **19 µm**, p90 **270 µm**, max **974 µm** |

**492 ≈ 504: `[O]`'s permutation moves essentially the same set of clusters that is observed
desynced.** And the depth displacement distribution — p90 = 270 µm, max = 974 µm — **is
Symptom B, quantitatively, derived from the user's own geometry**. "Hundreds of µm apart" is
not hyperbole; it is the arithmetic consequence of X-first sorting a 4-shank probe.

This is the strongest evidence in the investigation. It is still not proof (§3.3), because it
does not exclude the sort *also* producing a permutation — but no other candidate reproduces
both the *scale* (≈500/544) and the *depth distribution* of the observed damage.

### 3.2.2 Separate defect: a 4-shank probe declared as single-shank

`P.viShank_site` contains a single unique value (`1`) for all 384 sites, on a probe whose
geometry is unambiguously 4-shank. Consequences worth checking independently:
- `show_drift_view.m:85` filters background spikes by
  `P.viShank_site(viSite_spk(viSpk0)) == iShank1` → always true → **the drift view's
  background mixes all four shanks**.
- `show_drift_view.m:58` (`if iShank1 ~= iShank2, iClu2 = []; end`) never fires.
- FigMap's per-shank axis limits (`get_lim_shank_`) and `plot_FigMap_`'s shank title collapse.
- **Two clusters at the same depth on different shanks are indistinguishable in the
  Y-position view** — 750 µm apart in X, plotted on top of each other. This may independently
  contribute to Symptom B's *appearance* (a "tight Y band" that actually spans four shanks).

Fix belongs in the `.prb` (`IRC_all.prb` / `IRC.prb`), not in `irc.m`. Not yet raised with the
user.

### 3.2.3 ⭐ THE MECHANISM — `delete_clu_` remaps `viClu` even when the cache remap FAILED

**User-supplied domain fact (2026-07-15): negative `viClu` values are DELETED clusters.** That
retires the §3.2 "unexplained" note and, combined with the code, identifies the mechanism.

`delete_clu_` (irc.m:9126-9152):

```matlab
viClu_keep = setdiff(1:nClu_prev, viClu_delete);
try
    S_clu = S_clu_select_(S_clu, viClu_keep);      % 9131 — permutes/compacts the CACHE
catch
    fprintf(2, 'delete_clu_: error selecting');    % 9132-9134 — SWALLOWS the failure
end
iClu_del = min(S_clu.viClu) - 1;                   % 9136 — the negative delete marker
if iClu_del==0, iClu_del = -1; end
S_clu.viClu(vlDelete_spk) = iClu_del;              % 9139
vlMap = S_clu.viClu > 0;
viMap(viClu_keep) = 1:nClu_new;
S_clu.viClu(vlMap) = viMap(S_clu.viClu(vlMap));    % 9145 — remaps viClu UNCONDITIONALLY
S_clu.nClu = nClu_new;                             % 9146
```

**If `S_clu_select_` fails at 9131, the cache is never permuted — but line 9145 remaps `viClu`
regardless.** Cache un-permuted + labels remapped = **the exact permutation desync measured in
§3.2**. This is structurally the same defect as `reorder_clu_by_coords_`, but triggered by an
*exception* rather than a keystroke.

**There are two independent routes into it:**

1. **`delete_clu_`'s own `try/catch`** (9130-9134) swallows a whole-`S_clu_select_` failure.
2. **`struct_select_safe_` (irc.m:19512-19527) skips throwing fields BY DESIGN**, with only a
   console warning:
   ```matlab
   for i = 1:numel(csNames)
       try
           S = struct_select_(S, csNames(i), viKeep, iDimm);
       catch ME
           fprintf(2, 'struct_select_safe_: skipped field "%s": %s\n', ...);
       end
   end
   ```
   So **`cviSpk_clu` alone can be skipped** while every other per-cluster field is remapped —
   producing a desync in exactly one field, which is what was observed. Its own docstring says
   it exists to stop "a single malformed per-cluster field from leaving the other fields
   un-remapped". **That earlier hardening converted a loud crash into silent corruption.**

**Why this satisfies every constraint — including C4:**

| Constraint | Satisfied? |
|---|---|
| C1 — all three split paths | ✓ the desync is in `S_clu`; every path funnels through `split_clu_`→`S_clu_update_` |
| C2 — "fresh sort" | ✓ needs no re-sort, only deletes (a routine curation action) |
| C4 — **predates `[O]`** | ✓ **`delete_clu_` has nothing to do with reordering** |
| Intermittent | ✓ only fires when `S_clu_select_`/`struct_select_` actually throws |
| Symptom A / B | ✓ permutation → `S_clu_update_` rebuilds `iClu1` from a different cluster |

**The user deleted 247 times on this file.** `iClu_del = min(viClu)-1` decrements once per
delete, so `min(viClu) = -247` is a **counter**: 247 delete operations, 247 opportunities for
this to fire. (`_IRC_jrc.mat`: `min = -9` → 9 deletes, 179/190 desynced.)

**It is also self-amplifying.** Once any field's length is inconsistent, `struct_select_`
throws for it on the *next* delete → skipped → desync widens → more length inconsistency. That
explains how 504/544 clusters end up affected, and why both files are so thoroughly wrecked.

**Status: CONFIRMED as a live mechanism** (code traced end-to-end, satisfies all constraints,
matches the measured signature). **NOT yet confirmed as the specific origin in these files** —
that requires catching the console warning (`delete_clu_: error selecting` /
`struct_select_safe_: skipped field "cviSpk_clu"`) on a real delete, or the §8.1 test. Given
this investigation's record, that distinction is being kept.

### 3.3 The `[O]` hypothesis is now secondary — but C4 must be re-tested, not assumed

Two findings, taken together, make (b) the leading explanation:

1. **Every sort-pipeline path ends in `S_clu_refresh_`, which rebuilds `cviSpk_clu` from
   `viClu`.** Both agents' independent sweeps confirm this (§7.1), and the last candidate —
   `S_clu_sort_(S_clu,'viSite_clu')` called from `post_merge_` (irc.m:3894) — turns out to
   remap `viClu` via `mapIndex_` (irc.m:11684, comment `% fixed`) **and** call
   `S_clu_refresh_` (11687). **So the sort output should be consistent by construction.**
2. **`reorder_clu_by_coords_` is the only known path that permutes without remapping `viClu`**
   (§6), and its permutation shape *matches the data*: it sorts by **X then Y**, whereas
   `post_merge_` already ordered clusters by `viSite_clu` (depth). On a multi-column
   Neuropixels probe those orderings differ enormously — X-first groups by column — which
   explains the observed **large** shuffle (`cache{2}→3`, `cache{4}→9`) rather than the
   near-identity a depth-vs-depth reorder would give.

**This does NOT re-confirm M1.** That is precisely the error of §5.2 — a fitting mechanism plus
a user who owns the trigger is not a diagnosis. C4 ("present before reordering") is a
recollection about files with a two-month curation history (Jun 9 → Jul 15); it has not been
tested. **The test in §8.1 settles it and must be run before M1 is credited.**

### Unexplained and suspicious
`min(viClu) = -247` and `-9`. **Negative cluster labels should not exist.** Every renumbering
path (`unique(viClu+1)-1`, `S_clu_remove_empty_`) maps `<1` to `0`. A label of `-247` means
something writes negative values into `viClu` after the last refresh, or a refresh never ran.
Not yet traced. Also: 36.96% of spikes unassigned in the larger file.

---

## 4. Testable prediction (how to settle this in one run)

`S_clu_assert_synced_` — added in `87cd4f1` — reports, per cluster, `nForeign` (cached spikes
`viClu` attributes elsewhere) and **`nMiss`** (spikes `viClu` attributes here that the cache
omits) **separately**. That separation is exactly the discriminator this investigation needs.

**Load a freshly-sorted `_jrc.mat` — one that reproduces the bug, with NO `[O]` pressed — and
run the check.** Three possible outcomes, each conclusive:

| Result | Meaning |
|---|---|
| **`nMiss > 0`** | **CONFIRMED.** Cache under-counts. Explains all five constraints *and* why 45b5333 failed. The desync is baked into the sort output; hunt narrows to the pipeline. |
| **`nForeign > 0`, `nMiss == 0`** | Over-count → the structural argument is **wrong**. Reopen from scratch. |
| **Both 0** | The sort output is **clean**. The defect is live in the GUI, not in the file — M2 (drift-view axes) returns as the candidate for that path, and auto-split/FigTime need a separate explanation. |

This is a genuine falsification test. **It must be run before any further code archaeology,
and before any third fix is shipped.**

> **Status: this is a DEDUCTION, not an OBSERVATION.** "The cache under-counts after sorting"
> is currently inferred from the symptoms plus the impossibility of the alternatives. It has
> not been seen in the user's data. Given this investigation has already shipped three fixes
> on three unverified mechanisms, that distinction is the whole point.

---

## 5. Errors made in this investigation (recorded deliberately)

### 5.1 First diagnosis — WRONG
Claimed the interactive paths read the raw `cviSpk_clu` cache while `split_clu_` re-derives
via `get_clu_spk_confirmed_`, and the length mismatch got silently truncated (irc.m:10511-10523).

**Refuted by arithmetic, not opinion:** if the cache is stale-*large*, the confirmed list is
*smaller*, so the split's outputs are subsets of a **small** list — small in, small out. It
cannot produce thousands. The proposed fix (routing readers through
`get_clu_spk_confirmed_`) was **cosmetic**: it aligns the mask to the *same wrong population*.

### 5.2 Second diagnosis (M1, `reorder_clu_by_coords_`) — real bug, OVER-CLAIMED as the cause
`reorder_clu_by_coords_` genuinely renumbered every per-cluster array via `S_clu_select_`
without remapping `viClu`, then `save0_()` persisted it. Real, proven in code, reproduced in
a test, fixed.

**But the inference was invalid.** The reasoning was:

> mechanism fits the symptoms + user confirms they press `[O]` ⟹ M1 is the cause

*"They use the trigger sometimes"* is not *"the trigger preceded the failures."* The
conclusion was written up as "**M1 is the trigger. The last behavioural link is closed**" on
the strength of a yes/no answer that never established ordering. C4 later refuted it
directly. **The failure mode was wanting the confirming answer and asking a question that
could only confirm.** The right question was: *"does it happen before you press `[O]`?"* —
which is what the user eventually volunteered, unprompted.

### 5.3 Stale state reported as fact
Told the user "nothing is committed" while they had already committed the work themselves
(`87cd4f1`, pushed). Reported remembered state instead of checking.

---

## 6. Ruled out (traced, with evidence)

| Candidate | Verdict | Evidence |
|---|---|---|
| `S_clu_refrac_` shrinking the cache | **Clean** | Sets `viClu(removed)=0` (orig 11739) **and** shrinks the cache (11741) and `vnSpk_clu` (11742). Consistent. (Minor: line 11701 uses `max(viClu)` not `nClu`.) |
| `S_clu_refresh_` | **Clean** | `nClu=max(viClu)` (7397), `cviSpk_clu = vi2cell_(viClu, nClu)` (7400), `vnSpk_clu` from the cache (7401). Derived from `viClu` every time. |
| `S_clu_map_index_` | **Clean** | Remaps `viClu` (7418) then rebuilds the cache from it (7422). |
| `clu_reorder_` arithmetic | **Consistent** | Worked example: `viMap_clu` (10245-10247) exactly matches the `viClu` renumbering (10241-10243); `vlAdd` is computed *before* the relabel. **But see §7 — its effect on cluster IDENTITY was not audited.** |
| `delete_clu_`, `S_clu_new_`/`restore_log_` (undo), `execute_pending_and_update_` | **Clean** | All keep `viClu`/cache in lockstep; `S_clu_new_` does a full `S_clu_refresh_` rebuild. |
| FigTime subsampling | **Not subsampled** | `getFet_clu_` (8925-8936): the `MAX_SAMPLE=10000` cap applies **only** to the background branch. FigTime `[S]` is WYSIWYG. |
| Point ordering in plots | **Ascending** | `vi2cell_` (3163) and `find()` both yield ascending indices; `update_plot_` never reorders. |
| Plot staleness (wrong cluster displayed) | **Refreshed** | `button_CluWav_simulate_` refreshes FigTime (6054) and the drift view (6061 → `ui_show_elective_` → `ui_show_drift_view_`, fresh `S0`). |
| FigTime "position view" (`hPlot1_track`) | **Dead code** | Never created anywhere; referenced only at 7176-7177 (guarded, always false) and 8636. |
| M1 (`[O]` reorder desync) | **Real bug, NOT the trigger** | Refuted by C4. Fixed anyway. |

---

## 7. Open leads (under audit)

1. **`S_clu_remove_empty_` uses two different sources of truth** (irc.m:7434-7449):
   ```matlab
   vlKeep_clu = S_clu.vnSpk_clu > 0;          % what to DROP  -- a cached count
   S_clu = S_clu_select_(S_clu, vlKeep_clu);
   [~,~,S_clu.viClu] = unique(S_clu.viClu);   % how to RENUMBER -- the actual labels
   ```
   These agree only while `vnSpk_clu(i) > 0 ⟺ any(viClu==i)`. Inside `S_clu_refresh_` that
   holds (`vnSpk_clu` is recomputed one line earlier, 7401). **Called anywhere else with a
   stale `vnSpk_clu`, the drop set and the renumbering diverge** — and this sits in the
   **automated sort path**, requiring no keypress, which fits C2+C4. *Callers not yet
   enumerated.*
2. **`clu_reorder_` runs inside EVERY split** (irc.m:10610) and renumbers clusters. Its
   arithmetic is self-consistent, but its effect on `S0.iCluCopy`/`iCluPaste`, the FigWav
   x-axis mapping, and cached `S_fig` state was **not** audited. If the indices the user
   selected stop meaning what they meant, the *second* split of a session could operate on a
   mis-identified cluster — needs no `[O]`, and is intermittent.
3. **The fork's non-default clustering.** `P.vcCluster` may be `classix`/`isosplit6`/etc.,
   which take a **label-based** path (`fLabelClu=1`) that **skips `postCluster_`** and builds
   `S_clu` via `S_clu_from_labels_`/`cluster_labels_persite_`. Newer and less exercised than
   the default density-peak path. Does it produce a consistent `cviSpk_clu`/`viClu`/`nClu`?
4. **Is the cache rebuilt from `viClu` on load?** If `load0_` (13076) re-runs
   `S_clu_refresh_`, any sort-time desync self-heals when the GUI opens the file — which
   would **kill the structural argument**. Decisive; not yet confirmed.
5. **Symptom B may be partly expected behaviour.** `mrPos_spk` (what the drift view plots) is
   an interpolated centroid; `viSite_clu` is `mode(viSite_spk)`, the *peak detection site*. A
   unit sitting between sites can be tight in centroid-Y while its peak site flips
   spike-to-spike. That predicts divergence of *tens* of µm, not hundreds — so it is probably
   a co-factor at most, but the actual probe geometry (`P.mrSiteXY`, `viShank_site`) has not
   been checked.

## 7.1 Sort-pipeline sweep — every mutator traced CONSISTENT

An adversarial audit of every `viClu`/`cviSpk_clu` mutator in the sort path found **no**
origin for the under-count. All end in a rebuild-from-`viClu`:

| Function | orig line | Verdict |
|---|---|---|
| `S_clu_refrac_` | 11614-11617 | `viClu→0` **and** cache shrinks. Consistent. |
| `S_clu_cleanup_` | 18331-18333 | Consistent. |
| `S_clu_remove_count_` | 11276-11280 | `viClu→0` then `S_clu_refresh_`. Consistent. |
| `templateMatch_post_` | 4172 | Mutates `viClu` **without** the cache — but `S_clu_refresh_` at 4203 resyncs. Consistent. |
| `post_merge_wav4_` | 4462-4463 | `S_clu_map_index_` + `S_clu_refresh_`. Consistent. |
| `vi2cell_` | 3163-3183 | The `vi_change`/`vl_remove` splice is correct (nested-paren case checked). |
| `S_clu_remove_empty_` / `S_clu_keep_` | 7429/7448 | `unique`-renumber matches `S_clu_select_`'s compaction. Consistent — this retires lead §7.1 below. |
| `cluster_labels_persite_` | 2619-2626 | `nLabel=max(...)` creates gaps, never collisions; `S_clu_from_labels_` compacts at 2437-2441. Consistent. |

**This is a negative result, and it matters:** the under-count cannot be found by static
analysis of the *default* path. Either it arises from a **conditional** path taken only under
this user's config (a `catch`, an early return, a non-default `post_merge_mode`), or the
deduction in §3 is wrong. Both are resolved by §4's test, not by more reading.

**Caveat recorded:** the first sweep used a `[^)]*` regex that silently missed nested-paren
writes such as `S_clu.viClu(viSpk1(~vlKeep1))=0`. It was re-run correctly; the table reflects
the corrected sweep. Noted because a false-clean sweep would have been invisible.

### Two real defects found in passing (low confidence as the trigger)
- **`S_clu.viClu_prematch = S_clu.viClu`** (orig 4171) — a **per-spike** field whose name ends
  in `match`, not `_clu`. `S_clu_select_` never reindexes it and `S_clu_valid_` never checks
  it, so after any cluster removal or permutation it is stale garbage that `frac_changed`
  (4173) compares against. Same class of trap as `viClu` itself.
- **`post_merge_wav_`** (orig 4287) — `if ~get_set_(P,'fSave_spkwav',1), return; end` is an
  early return placed **after** `rmfield_(..., 'mrWavCor')` at 4286. With `fSave_spkwav=0` it
  leaves `S_clu` stripped, skips the merge entirely, and leaves `nClu_merge` unassigned.

---

## 8. NEXT STEPS (in order — do not reorder)

Steps 1-2 of the original plan are **DONE** (§3.2): the check was run on real data, the desync
is confirmed and massive, and the config is known (`vcCluster='isosplit'`, label-based path).

### 8.1 THE DECIDING TEST — sort-vs-`[O]` (do this first)
Produce a `_jrc.mat` **straight out of `irc sort`, with zero GUI interaction, and no `[O]`**,
then run the check *before opening the manual GUI*:
```matlab
irc('sort', 'yourfile.prm')      % or re-sort a COPY, to avoid overwriting curated results
S0 = load('yourfile_jrc.mat');
irc('call', 'S_clu_assert_synced_', {S0.S_clu, 'fresh-sort'})
```
- **Reports 0** → the sort is clean; the desync is introduced by the GUI. Combined with §3.3,
  `[O]` is then the confirmed cause, C4 was a misrecollection, and **the fix in `87cd4f1`
  already closes it** — verify by pressing `[O]` on the fixed code and re-running the check
  (it must still report 0).
- **Reports >0** → the sort itself produces it, §3.3's reasoning is wrong despite both sweeps,
  and the origin is in a conditional path — go to §8.2.

> **Warning:** `irc sort` overwrites `_jrc.mat`. Work on a **copy** of the `.prm`/output, or
> the curated results in that folder will be lost. Do not run this against the existing files.

### 8.2 If the sort output is dirty
Instrument the pipeline: call `S_clu_assert_synced_` after each stage (`fet2clu_`,
`postCluster_`, `post_merge_`, `S_clu_sort_`, `S_clu_refrac_`, immediately before `save0_`)
and bisect which stage first reports non-zero. One run localises it. Prioritise the
**label-based branch** (`vcCluster='isosplit'` → `fLabelClu=1`, skips `postCluster_`,
`S_clu_from_labels_`/`cluster_labels_persite_`), since that is this user's actual path and is
the least exercised.

### 8.3 Trace `min(viClu) < 0` (independent, unexplained)
`-247` and `-9` observed. Negative labels should not exist — every renumbering path maps `<1`
to `0`. Find what writes them and whether a refresh is being skipped. This may be a second,
separate defect, and 36.96% unassigned spikes in the larger file is worth explaining too.

### 8.4 ⛔ Repair vs re-sort — REPAIR REFUTED, RE-SORT is the recovery
> **This section's original claim ("a repair may be possible without re-sorting; recover the
> permutation σ") is RETRACTED.** It assumed the cache was internally coherent (each entry
> exactly one cluster's spikes). Later measurement disproved that: 52/190 cache entries span
> **multiple** `viClu` labels, 557k spikes are claimed by >1 cluster, 413k are orphaned. There
> is no σ — the two sides are different partitions, not the same one relabelled. See the
> `★ PURITY` result in §3, the `⛔` repair block above, and CID-12. **Re-sort is the only
> recovery** (the sort pipeline is clean: fresh re-sort measured 0/547 stale).

*(Original text, retained for the record:)* ~~The existing files are confirmed corrupted (§3.2).
But because the cache is internally coherent, a repair may be possible without re-sorting:
recover the permutation σ by matching `cache{i}` against `find(viClu==j)`. Clusters already
split/merged post-corruption are the exception.~~

### 8.5 Cheap and correct regardless of the above
- `get_clu_spk_confirmed_`'s guard cannot detect an under-count by construction (§3.1).
  Comparing `numel(cache{i})` against `sum(viClu==i)` catches the direction that matters.
- Fix `viClu_prematch` (a per-spike field `S_clu_select_` never reindexes) and
  `post_merge_wav_`'s early return (§7.1).
- Consider making `S_clu_assert_synced_` run once on load (`load0_` does **no** validation —
  confirmed, orig irc.m:12951-12973), so a corrupted file announces itself when opened.

---

## 9. Questions outstanding for the user

1. **What are `P.vcCluster`, `post_merge_mode`, `fSave_spkwav`, and `min_count`?**
   Highest-information question. The static sweep found the *default* path clean, so a
   conditional path is the prime remaining suspect. The fork's label-based clustering
   (`classix`/`isosplit6`, `fLabelClu=1`, which **skips `postCluster_`**) is far less
   battle-tested than upstream density-peak; and `fSave_spkwav=0` silently skips whole
   branches of post-merge (§7.1).
2. **How were you judging "should have very few spikes"?** `default.prm` sets `fText = 0`, so
   FigWav does **not** display per-unit spike counts unless `[N]` is pressed. If the
   judgement came from the waveform's appearance rather than a displayed count, then "a unit
   that should have few spikes" may in fact be a unit that *has* thousands — and Symptom A
   could partly be a display/expectation gap rather than corruption. Cheaper to answer than
   either audit, and it changes the search.
3. **Was the 2026-07-10 report (`45b5333`) the same bug?** Its subject is "cluster split
   could balloon a tiny cluster to thousands of spikes" — identical to Symptom A. If so, this
   has now survived two fix attempts, which is itself strong evidence that neither addressed
   the real mechanism (§3.1).

---

## 9. Real bugs found and fixed en route (commit `87cd4f1`)

None of these is confirmed as the reported root cause; all were independently verified.

1. **`reorder_clu_by_coords_` (M1)** — `[O]` renumbered every per-cluster array without
   remapping `viClu`, and `save0_()` persisted the desync. Verified with a negative control
   that reproduces the corruption.
2. **`show_drift_view.m` `[S]` (M2)** — the polygon was drawn on `gca` (`impoly_()` with no
   argument) while the data was read from the `SelectedTab` axes; the two tabs share an
   identical `Position`, so the divergence was invisible, and only the vertical axis was
   miscalibrated (both share the time x-range) — degenerating the selection into a time band
   spanning the cluster's full depth. **Explains both symptoms, but only for the drift view.**
3. **`split_clu_` silent discard** — `iClu2 = max(viClu)+1` could clobber a live index and
   shrink `nClu`, failing `S_clu_valid_` so `S_clu_commit_` reverted the entire split.
4. **`get_clu_spk_confirmed_` backwards fallback** — on total disagreement it returned the
   *raw cache* rather than the authoritative `viClu`.
5. **FigProj** — turned out to be **dead code** in this fork (nothing calls
   `create_figure_('FigProj')`); its `nShow_proj=50` display-vs-full-population split bug was
   therefore unreachable. Fixed and restored as an opt-in view.
6. **`S_clu_assert_synced_`** — the content check that would have caught this class. §4's test
   depends on it.

---

## 10. Method notes

- **The devil's-advocate agent was the highest-value part of this investigation.** It killed
  diagnosis #1 with arithmetic and found the FigProj and drift-view mechanisms. Confirmation
  bias was the binding constraint throughout, not missing information.
- **The negative control is what makes a passing test mean anything.** Every fix here ships
  with one; the `[O]` fix's test reproduces the corruption before proving the fix removes it.
  Separately, the FigProj harness's first "failure" was a *test* bug (a regex counting
  matches inside comments) — worth distinguishing from a code bug rather than quietly
  "fixing" the code.
- **Ask questions that can disconfirm.** "Do you press `[O]`?" could only confirm. "Does it
  happen *before* you press `[O]`?" would have saved a round.
- **A plausible mechanism is not a diagnosis.** Three rounds each found a *real* bug that
  *could* produce the symptom, and each was written up with more confidence than the evidence
  carried. Real-bug-found and root-cause-found are different claims; conflating them is how
  `45b5333` shipped a fix for the wrong direction and how this session nearly shipped a third.
- **Build the instrument before the fix.** `S_clu_assert_synced_` was added as a *by-product*
  of round 3, and it turns out to be the only thing that can settle rounds 1-4. It should have
  been step one. The cheapest move in a state-corruption bug is to make the state observable.
- **A negative result from a static sweep is information, not failure.** Every sort-pipeline
  mutator tracing clean (§7.1) is what promotes "conditional path under this user's config"
  from an afterthought to the leading hypothesis — and it is why §9's config question now
  outranks more code reading.
