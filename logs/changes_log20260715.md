# Changes Log - July 15, 2026

> **Tracker:** all issues in this log are indexed with status in
> [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md) (CID‑01 … CID‑15).

## Summary

Bug report from manual curation: (A) splitting a unit that should have very few spikes
produced two units with **thousands** of spikes; (B) splitting a unit sitting in a
consistently **narrow Y (depth) band** produced two units **hundreds of µm apart**. Both
occurred on **freshly-sorted** data, across three different split paths (auto-split PCA
dialog, FigTime `[S]`, drift-view `[S]`).

Investigation (code-architect + devil's-advocate agents + direct tracing) found **two
independent, confirmed defects**, both fixed here:

1. **`reorder_clu_by_coords_` (the `[O]` key) silently desynced `S_clu.viClu` from every
   per-cluster array, then saved the result to disk.** This is the root cause of both
   reported symptoms and the only mechanism that explains failures in all three split
   paths at once.
2. **`show_drift_view.m`'s `[S]` polygon was drawn on `gca` but evaluated against data
   read from the `SelectedTab` axes** — two different axes, never synchronised, invisible
   because both tabs' axes share an identical `Position`.

An initial hypothesis — that the interactive split paths read the raw `cviSpk_clu` cache
while `split_clu_` re-derives via `get_clu_spk_confirmed_` — was investigated and
**refuted**: that mismatch cannot produce "thousands of spikes" (the outputs are subsets
of the *confirmed* list, so small-in/small-out), and on a fresh sort the two agree anyway.
Routing those readers through the helper would have been cosmetic. It was not done.

## Background — the root cause (`[O]` / `reorder_clu_by_coords_`)

`reorder_clu_by_coords_` (`irc.m`, bound to `[O]` in FigWav via `keyPressFcn_FigWav_`)
sorts clusters by (X, Y) position and applies the permutation with `S_clu_select_`:

```matlab
[~, viMap_clu] = sortrows(mrPosXY_clu, [1, 2]);
S_clu = S_clu_select_(S_clu, viMap_clu);   % ... and that was all
...
save0_();                                   % persists the result
```

`S_clu_select_` reindexes every `v*_clu`, `c*_clu`, `t*_clu`, `m*_clu` field — including
`cviSpk_clu`, `viSite_clu`, `vnSpk_clu`, `csNote_clu`, `mrWavCor`. It does **not** touch
`S_clu.viClu`: that is a per-*spike* field whose name ends in `Clu`, not `_clu`, so it
matches none of `S_clu_select_`'s regexes, and by design that function cannot remap it —
the caller must.

The sibling function `clu_reorder_` gets this right: it remaps `viClu` in place *before*
calling `S_clu_select_` with a matching map. `reorder_clu_by_coords_` simply omitted that
step.

**Net effect of one `[O]` press:** the per-cluster arrays jump to the new position-sorted
numbering while `viClu` stays on the old one. For every cluster whose sorted rank differs
from its original index, `cviSpk_clu{i}` and `find(viClu==i)` now describe two *unrelated*
clusters. `save0_()` then writes that to disk.

### Why it produced the reported symptoms

After `[O]`, splitting cluster N:

1. The polygon mask still lines up — `get_clu_spk_confirmed_` finds zero agreement
   (`viClu(viSpk1)` holds the *old* id), so its complete-disagreement fallback returns the
   raw cache, which here is ironically **correct**.
2. `split_clu_` partitions the right spikes and computes the right child sites.
3. Then `S_clu_update_` re-derives everything **from the stale `viClu`**:

```matlab
viSpk_clu1 = find(S_clu.viClu == iClu1);                      % OLD numbering
S_clu.cviSpk_clu{iClu1} = viSpk_clu1;                         % -> foreign spike set
S_clu.viSite_clu(iClu1) = mode(S0.viSite_spk(viSpk_clu1));    % -> symptom B
S_clu.vnSpk_clu(iClu1)  = numel(viSpk_clu1);                  % -> symptom A
```

The unit's id resolves to whatever cluster *used* to wear that number → thousands of
spikes; and because the renumbering is sorted by position, the mismatched identity lands
hundreds of µm away. No prior merges/splits required, which is why it reproduced on a
fresh sort. `S_clu_update_` is common to **every** split path, which is why all three
paths failed.

Nothing caught it: `S_clu_valid_`, the codebase's only validity check, compares array
**lengths** to `nClu` and never compares `viClu` content against `cviSpk_clu`.

## Background — the drift-view axes bug (`show_drift_view.m`)

The `[S]` handler resolved the axes two different ways in the same function:

- `hPoly = impoly_()` — **no argument** → `impoly_` forwards `varargin{:}` to `impoly()`,
  which operates on **`gca`** (`hFig.CurrentAxes`).
- `hAx = uiTab_.Children(1)` — resolved from **`SelectedTab`**; `hPlot1` is read from *this*
  axes.

Switching a uitab does not update `hFig.CurrentAxes`, and nothing else synchronised them.
The two tab axes are created with an identical `Position [.05 .2 .9 .7]`, so they occupy
the same screen rectangle and the divergence is invisible. They share the same time
x-range but have very different y-ranges (Y-position ~1480–1540 µm vs X-position ~-12–62 µm).

So `inpolygon(time, Y-position, polyTime, poly-X-position)` — only the **vertical** is
miscalibrated. The selection degenerates into a **pure time-band spanning the cluster's
full depth extent**: thousands of spikes, both halves spanning the whole Y range, and
`mode(viSite_spk(...))` landing on arbitrary distant sites. Silent, because `numel(vlIn)`
still equals `nSpk1`. It only misbehaves when `CurrentAxes` is stale or points at the
other tab — clicking inside the visible axes first makes `gca == hAx` and it works, which
explains the intermittency.

## Changes

- **`irc.m` `reorder_clu_by_coords_`** — remap `S_clu.viClu` in lockstep with the
  per-cluster arrays *before* the existing `S_clu_select_` call, mirroring `clu_reorder_`'s
  proven idiom. Inverts `viMap_clu` (which maps new slot → old id) into an old id → new
  slot map, and leaves unassigned spikes (`viClu <= 0`) untouched. Added a guard that
  refuses to reorder — rather than desync — if the position array length doesn't match
  `nClu`.
- **`irc.m` `S_clu_select_`** — added a CONTRACT comment to the header documenting that
  this function reindexes per-*cluster* fields only, cannot remap the per-*spike* `viClu`,
  and that any caller changing cluster **identity** (a permutation, not just dropping
  trailing empties) must remap `viClu` itself first. This is the trap that produced the
  bug; the comment exists so the next author doesn't fall into it.
- **`show_drift_view.m` `keyPressFcn_` `'s'` case** — `impoly_()` → `impoly_(hAx)`, so the
  polygon is drawn on the same axes `hPlot1` is read from. Also gave the `hSplit` highlight
  line an explicit `hAx` parent (it also used `gca`). Matches the `line(hAx_, ...)` idiom
  already used elsewhere in the file.

No functions were deleted; all changes are additive or in-place fixes, per `CLAUDE.md`.

## Verification

Harness: `verify_reorder.m` (scratch), run in MATLAB R2023b against the **real**
`S_clu_select_` via `irc('call', ...)` on a synthetic 5-cluster `S_clu` deliberately
unsorted by Y. Invariant under test: `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for all `i`.

| Check | Result |
|---|---|
| `checkcode` parse errors, `irc.m` / `show_drift_view.m` | **0 / 0** |
| Pre-reorder invariant | holds (1) |
| **Negative control** — `S_clu_select_` only, no `viClu` remap (old behaviour) | **violated (0)** |
| Fixed — remap `viClu`, then `S_clu_select_` | **holds (1)** |
| `class(viClu)` preserved | `int32` |
| `vrPosY_clu` ascending after reorder | 1 → `[100 200 300 400 500]` |
| Unassigned spikes (`viClu<=0`) untouched | 3 zeros / 1 negative, unchanged |

**PASS.** The negative control is load-bearing: it reproduces the defect in isolation, so
the pass is meaningful rather than vacuous.

**Not exercised:** the `show_drift_view.m` fix is syntax-checked and traced but cannot be
reproduced headlessly — `impoly_` blocks on interactive polygon drawing, and its
`fDebug_ui` escape hatch returns `[]` without calling `impoly`. Needs a human drawing a
polygon on the Y-position tab. Low risk: `line(hAx, ...)` is already the idiom used when
the plots are created, and `impoly_(varargin)` → `impoly(varargin{:})` forwards a parent
handle as MATLAB's `impoly` expects.

**Remaining interactive checks:** split a unit in each path after pressing `[O]` and
confirm `numel(child1) + numel(child2) == numel(parent)` and that both children's
`mode(viSite_spk)` stay within the parent's site range; confirm `csNote_clu` and quality
metrics stay attached to the same physical cluster after `[O]`; regression-check merge,
delete, undo/redo, and `irc('unit-test')`.

## ⚠ Live consequence — existing `_jrc.mat` files may be corrupted

`reorder_clu_by_coords_` called `save0_()` **immediately after** creating the desync, so
any `_jrc.mat` on which `[O]` was pressed before this fix has the corruption baked in.

It is **not cleanly repairable**: post-`[O]` neither array alone is authoritative —
`viClu` holds old ids, `cviSpk_clu`/`viSite_clu`/`vnSpk_clu`/`csNote_clu`/`mrWavCor` hold
new ones — and inverting the permutation requires the pre-`[O]` `vrPosX_clu`/`vrPosY_clu`
ordering, which `S_clu_select_` overwrote.

Partial recovery *may* be possible for clusters `S_clu_update_` has not yet touched: the
cache is still correct there, so `viClu` could be rebuilt **from** `cviSpk_clu` (the
inverse of the normal direction). Any cluster already split or merged post-`[O]` has had
its cache overwritten from the stale `viClu` and is unrecoverable. **Re-sorting from raw
may be the only clean path. This needs a decision — no action taken.**

## Second pass — the deferred items, now implemented

After the two fixes above landed, the remaining findings were implemented as well.

### `split_clu_` no longer silently discards a split
`iClu2 = max(S_clu.viClu) + 1` → `max(double(S_clu.nClu), double(max(S_clu.viClu))) + 1`.
The old form allocated the "new" cluster **below** `nClu` whenever `max(viClu) < nClu`
(trailing empty clusters), overwriting a live index and then **shrinking** `nClu`, so the
per-cluster arrays no longer matched `nClu`, `S_clu_valid_` failed, and `S_clu_commit_`
reverted the entire split with only a console message. Taking the max of both bounds can
never clobber a live index nor shrink `nClu`. Verified: with `nClu=7` and labels reaching
only 4, the old code returned **5** (a live index); the fix returns **8**.

### `get_clu_spk_confirmed_`'s fallback now prefers `viClu`
On **total** cache/`viClu` disagreement the helper returned the raw cache. That is
backwards: `viClu` is authoritative (every rebuild derives *from* it), so a cache agreeing
with it on nothing is the stale one, and trusting it can resurrect the very corruption the
helper exists to prevent. It now prefers `viClu` and says so loudly. The original
"never return empty" guarantee is preserved: if `viClu` attributes no spikes at all to the
cluster, the cache is kept (with a different warning) rather than splitting nothing.

### New: `split_clu_by_id_` — split by absolute spike id
`split_clu_(iClu1, vlIn)` takes a **positional** mask over a list it re-derives internally,
so caller and callee must agree on population *and* order with nothing enforcing it; on
mismatch it silently truncates/zero-pads. The new additive wrapper builds the mask by
`ismember` against the same list `split_clu_` uses, making `numel(vlIn) == numel(viSpk1)`
unconditional and that failure mode structurally impossible. Verified: mask length stays
correct even when passed foreign ids, reversed order, or duplicates. `split_clu_` is
unchanged and remains valid for existing positional callers.

Wired to it: **FigTime `[S]`** (which already stashed the needed `S_fig.viSpk1` and simply
never used it), **drift-view `[S]`** (`viSpk1` now stashed on the axes alongside `hPlot1`),
and **FigProj `[S]`**. Each falls back to the positional path if a figure cached before the
change lacks the ids.

### FigProj: fixed, and restored as an opt-in view
FigProj turned out to be **dead code in this fork** — nothing calls
`create_figure_('FigProj', ...)`, so the figure never existed, `keyPressFcn_FigProj_` was
never bound, and its `[S]` split was unreachable. The drift view replaced it (see the
`create_figure_` block, the `[J]` key, and the "skip if FigProj replaced by FigDrift"
comment). It is now available again, **opt-in**:

- **`ui_show_FigProj_(fNewFig, hMenu)`** (new) — follows `ui_show_all_chan_`'s toggle
  pattern. **View > Show projection view** opens/closes it; thereafter `ui_show_elective_`
  refreshes it on every cluster selection. Called with no arguments it is a no-op unless
  already open, so users who never open it pay nothing.
- **`fet2proj_`** now returns **`viSpk01`** (7th output) — the global spike ids behind
  `mrMin1/mrMax1`, in plotted order. It was previously computed and thrown away, which is
  what destroyed the displayed-point → spike mapping.
- **Selected clusters are no longer subsampled.** `randomSelect_(..., P.nShow_proj)` is
  dropped for clusters 1/2; the background keeps its `nShow_proj*2` cap. This mirrors
  `getFet_clu_`/`plot_FigTime_`, whose `MAX_SAMPLE` cap likewise applies to the background
  branch only. Displaying ~50 dots of a 4000-spike cluster while `plot_split_` evaluated
  the polygon over all 4000 was the whole bug; the two are now the same population by
  construction.
- **`plot_split_`** evaluates against the **displayed** spikes (`S_fig.viSpk1`) rather than
  `S_clu.cviSpk_clu{iClu1}`. This also closes a second, independent mismatch: the display
  is filtered to `viSites0`, but the split was not — spikes detected elsewhere were
  invisible yet selectable, carried ~0 amplitude on `site12`, piled at the projection
  origin, and were swept in by any polygon near it. Its title now reads
  `Cluster %d (%d of %d spikes shown)` so the selectable count is explicit.
- `plot_split_` gained a third output `viSpk_in` (absolute ids); `vlIn` is retained for
  backward compatibility.

## Documentation corrections

- **`CLAUDE.md`** — the "Cluster Merging (from MERGE_OPTIMIZATIONS.md)" section described
  an API that does not exist (`fUpdateImmediate`, the `[B]` batch key, "Edit > Batch
  merge", incremental correlation updates). Replaced with the **real** queued-operation
  model: `[M]` queues a merge (`ui_merge_pending_`), `[D]`/Backspace/Delete queues a delete
  (`ui_delete_pending_`), `[U]` applies them (`execute_pending_and_update_`), `[Escape]`
  discards (`cancel_pending_operations_`). Added a section documenting that **`viClu` is
  authoritative and `cviSpk_clu` is a derived cache**, and the `S_clu_select_` contract —
  the trap that caused this bug.
- **`MERGE_OPTIMIZATIONS.md`** — kept (historical/design reference) but headed with a
  prominent **NOT IMPLEMENTED** banner enumerating exactly which claims are contradicted by
  `irc.m`.
- `CLAUDE.md` also now warns that **six** docs share this problem: `MERGE_OPTIMIZATIONS.md`,
  `OPTIMIZATION_SUMMARY.md`, `PROFILER_ANALYSIS.md`, `PERFORMANCE_AUDIT.md`,
  `GUI_PERFORMANCE_OPTIMIZATIONS.md`, `GPU_USAGE_ANALYSIS.md`. Only the first was annotated
  in detail; the others are flagged but not individually audited.

## Verification — second pass

Harnesses: `verify_split_fixes.m`, `verify_figproj.m` (scratch), MATLAB R2023b.

| Check | Result |
|---|---|
| `checkcode` parse errors, `irc.m` / `show_drift_view.m` | **0 / 0** |
| `get_clu_spk_confirmed_`: agree → cache; superset → shrinks to confirmed | OK |
| `get_clu_spk_confirmed_`: **total disagreement → uses `viClu`**, not the stale cache | OK |
| `get_clu_spk_confirmed_`: total disagreement **+ `viClu` empty** → keeps cache | OK |
| `split_clu_` alloc: normal (`max==nClu`) → `nClu+1`, unchanged from old behaviour | OK |
| `split_clu_` alloc: trailing empties → **8** (old code returned **5**, a live index) | OK |
| `split_clu_by_id_`: mask length == `nSpk1` for foreign ids / reversed / duplicates | OK |
| `split_clu_by_id_`: selects by identity, not position | OK |
| FigProj wiring (13 assertions: arity, stash, subsample, split path, menu, toggle) | OK |
| `plot_split_` raw `cviSpk_clu{iClu1}` reads **in code** | **0** (3 remain in comments) |

**PASS.** Note the FigProj harness initially reported a failure here — its regex counted
the string inside *comments*. The check was corrected to strip comment lines; the code was
already right. Recording this because the distinction matters: the first run was a test
bug, not a code bug.

**Still not exercised** (needs a human at the GUI): the drift-view `impoly_(hAx)` fix, the
FigProj view end-to-end, and the three `[S]` paths now routed through `split_clu_by_id_`.
`impoly_` blocks on interactive drawing and cannot be driven headlessly.

## Third pass — the content check (`S_clu_assert_synced_`)

`S_clu_valid_` compares array **lengths** to `nClu` and nothing else, so a cache describing
a wholly different set of spikes than `viClu` passed it silently. That is *why* the `[O]`
desync survived undetected and reached disk. Added **`S_clu_assert_synced_(S_clu, vcCaller)`**,
called from the existing `S_clu_commit_` choke point that every top-level GUI operation
already funnels through (`split_clu_`, `ui_merge_`, `ui_delete_`, `restore_log_`,
`execute_pending_and_update_`).

**It warns; it does not gate.** This is the central design decision. `S_clu_commit_`
*reverts* the caller's work when `S_clu_valid_` returns false, so folding a content check
into that verdict would mean a desync **silently discards the operation** — reproducing the
exact silent-data-loss mode this is meant to expose, and potentially wedging a session in
which every action appears to do nothing. It reports and lets the user decide. It also
never throws (wrapped): a diagnostic that breaks the GUI is worse than the bug it reports.

Detects **both** directions per cluster — cached spikes `viClu` attributes elsewhere
(`nForeign`), and spikes `viClu` attributes here that the cache omits (`nMiss`) — plus
out-of-range cache indices. Counts labels **once** via `accumarray` (O(nSpk)) rather than a
per-cluster `find()` (O(nSpk·nClu)), so it stays cheap on >1M-spike datasets. Output is
capped at 10 clusters. Gated by the new **`fCheck_clu_sync`** parameter (default `1`).

Also corrected `default.prm`'s `nShow_proj` comment: it now caps **background** spikes only.

### Verification — third pass
Harness: `verify_sync_check.m`, MATLAB R2023b.

| Check | Result |
|---|---|
| Healthy state → silent (0 flagged) | OK |
| **Reproduces the real `[O]` bug** — cache permuted, `viClu` not remapped → **4/4 flagged** | OK |
| Cache superset (foreign spikes bolted on) → 1 flagged | OK |
| Cache omits spikes `viClu` claims → 1 flagged | OK |
| Two clusters swapped → 2 flagged | OK |
| Out-of-range cache indices → flagged, no throw | OK |
| Empty struct / missing `nClu` / empty `viClu` → 0, no throw | OK |
| Unassigned spikes (`viClu<=0`) tolerated → 0 | OK |
| **Desynced state still passes `S_clu_valid_`** — warns, never reverts | OK |

**PASS.** The `[O]` reproduction is the load-bearing case: it simulates precisely what
`reorder_clu_by_coords_` did (`S_clu_select_` permutes `cviSpk_clu`, `viClu` untouched) and
the check flags every affected cluster.

## Still deferred (documented, not implemented)
- **`split_clu_`'s silent truncate/pad remains** (irc.m, in `split_clu_`). Now that all
  three interactive paths route through `split_clu_by_id_`, it is only reachable by the
  remaining positional callers (`cbf_split_psth_`, `auto_split_`, and the legacy
  fallbacks). It should eventually hard-fail loudly instead of silently correcting; the
  "final safety check" below it is dead code, since the branches above always force the
  lengths equal.
- **`cbf_split_psth_`** (the PSTH raster split) still passes positional indices via
  `S_Ax.viiSpk_clu`. `plot_figure_psth_` already has `viSpk_clu1` from `S_clu_time_` and
  could thread it through to `split_clu_by_id_` the same way the other three paths now do.
- **The five other stale docs** (`OPTIMIZATION_SUMMARY.md`, `PROFILER_ANALYSIS.md`,
  `PERFORMANCE_AUDIT.md`, `GUI_PERFORMANCE_OPTIMIZATIONS.md`, `GPU_USAGE_ANALYSIS.md`) are
  flagged in `CLAUDE.md` but not individually audited or annotated.

## ⚠ Documentation accuracy note

`MERGE_OPTIMIZATIONS.md` is **stale/aspirational, not descriptive**. The functions it
documents — `ui_merge_batch_`, `update_correlation_after_merge_`,
`compute_cluster_correlations_`, the `fUpdateImmediate` flag, the `[B]` batch key, and the
cached-index fast path in `merge_clu_pair_` — **do not exist** in the current `irc.m`
(`grep` returns zero matches for all of them). The actual `merge_clu_pair_` still uses the
"slow" `find(S_clu.viClu==iClu2)` path, and the real deferred-merge feature is a different,
unrelated implementation (`ui_merge_pending_` / `execute_pending_and_update_`).

**`CLAUDE.md`'s "Cluster Merging (from MERGE_OPTIMIZATIONS.md)" section inherits this
inaccuracy** and is auto-loaded into every session, so it actively misleads. Recommend
correcting or removing both. Not touched in this pass.

---

# Addendum — later on 2026-07-15 (commit `83776fc`)

Work after `87cd4f1`: measuring the corruption on the real files, attempting recovery, and
**retracting two claims made earlier in this same log**. See
`logs/issue_viclu_desync_20260715.md` for the consolidated issue report.

## Added: `matlab/repair_clu_sync.m`

Dry-run-by-default diagnostic + repair for a desynced `_jrc.mat`. **Its repair path does not
work on the observed data and correctly refuses to write** (5 blocking reasons). Retained for
its diagnostics. Never overwrites its input.

## ⛔ RETRACTION 1 — "the cache is authoritative" was an ARTIFACT, not a measurement

An earlier conclusion — *`viSite_clu`/`vnSpk_clu`/`vrPosY_clu` agree with the cache at ~100%,
therefore the cache is the authoritative side* — is **withdrawn**. Every field compared
**derives from the cache**:

| Field | Derived from | Where |
|---|---|---|
| `vnSpk_clu` | `cviSpk_clu` | irc.m:7401 — `cellfun(@numel, cviSpk_clu)` |
| `viSite_clu` | `cviSpk_clu` | irc.m:7407 — `mode(viSite_spk(cviSpk_clu{i}))` |
| `vrPosY_clu` | `cviSpk_clu` | `S_clu_position_`:17620 → `S_clu_subsample_spk_`:11652 |

`S_clu_select_` permutes the cache **and its derivatives together**, so they agree **by
construction** — whether the cache is pristine or garbage. **Proof: the check reports
`188/188 (100.0%)` on a file whose cache has 557,123 overlapping spikes and one entry spanning
14 labels.** A check that cannot fail never meant anything.

The `vrPosY_clu` shortfall (85.6%/94.5%) was **sampling noise**, not a mixed-state signal:
`S_clu_subsample_spk_` filters to centre-site spikes (11655), takes a mid-time window (11661),
then subsamples to 1000 (11663) — the test compared that against the full-set median at <5 µm.

## ⛔ RETRACTION 2 — "the curation is recoverable, do not re-sort" is WRONG

**The affected `_jrc.mat` files cannot be repaired.** The σ-recovery model assumed cache and
`viClu` encode the *same partition under different labels*. The one **non-circular** check
refutes it:

| purity (`_IRC_jrc.mat`) | |
|---|---|
| cache entries spanning exactly 1 `viClu` label | 138 / 190 |
| **spanning >1 label** | **52** (max **14** labels in one entry) |

Different partitions → **σ does not exist**. Dry-run confirms: 557,123 spikes claimed by >1
cluster, 413,533 orphaned, 7,172 deletions resurrected. **Re-sorting is the correct path.**

Cause: the damage **compounded** — each post-corruption split called `S_clu_update_`, writing
foreign spike sets over entries other clusters owned. Cumulative and order-dependent, so no
single global transform inverts it.

## ★ New evidence: 7,172 DELETED spikes sit inside live cache entries

A pure permutation cannot produce this — `[O]` moves which *slot* holds an entry, it never
injects deleted spikes into a live one. This implicates **`delete_clu_` (irc.m:9126-9152)**,
which remains **UNFIXED** and is now the top-priority item.

The `try/catch` at 9130 **cannot catch the failure**: `S_clu_select_` delegates to
`struct_select_safe_` (19512-19527), which swallows a per-field failure with a console warning
and **returns normally**. So `cviSpk_clu` can be left stale with no exception raised, after
which line 9145 remaps `viClu` unconditionally and 9149's `S_clu_valid_` (lengths only) passes.
Three layers of error handling; the failure walks through all three.

Worse, 9138 selects victims via `ismember(S_clu.viClu, viClu_delete)`. On an already-desynced
file the user deletes **what the GUI shows** (the cache's cluster) while the code marks negative
**whatever `viClu` says** — so **every delete compounds the damage into a new cluster.**

**Do not curate further until `delete_clu_` is fixed.** Proposed rollback-on-failure patch in
the issue report §6. Not applied yet — a sort was running against `irc.m`, and editing it
mid-run risks a reload mid-execution.

## Corrections to earlier claims in this log

- **`viClu_prematch` is NOT a defect.** Set at irc.m:4171 and read at 4173 — transient, always
  fresh at use. It is ~68 MB of per-spike dead weight persisted into every `_jrc.mat`; cleanup
  only, not corruption.
- **`post_merge_wav_` early return** — reported earlier as misplaced relative to
  `rmfield_(...'mrWavCor')`. **Unverified. Re-check before acting.**

---

# Addendum 2 — code fixes for the remaining open items (2026-07-15, later)

Three `irc.m` fixes, each verified with a negative control. Full write-up:
`logs/issue_viclu_desync_20260715.md`.

## 1. `delete_clu_` (irc.m:9140) — the same desync bug as `[O]`, now FIXED

Was: remapped `viClu` **unconditionally** while its cache remap sat in a `try/catch` that only
printed. Now: snapshots `S_clu`, verifies the cache was actually permuted, **rolls back**
rather than commit a half-applied remap.

### ★ The landmine this uncovered — a LENGTH check cannot detect the failure

The first attempt guarded on `numel(cviSpk_clu) == numel(viClu_keep)`. **It did not fire, and
only the negative control caught it.** `S_clu_select_` ends with a **length-reconcile block**
(irc.m:19669-19692) that force-fits wrong-length `v*_clu`/`c*_clu` fields to `nClu_new`,
**padding `cviSpk_clu` with `{[]}`**:

```
struct_select_safe_: skipped field "cviSpk_clu": Index exceeds ...
S_clu_select_: reconciled length of field "cviSpk_clu" to 4
  -> numel(cviSpk_clu) = 4 (expected 4)   <-- a length check PASSES
  -> DESYNCED clusters : 2                <-- while the content is wrong
```

**This is the same blind spot that makes `S_clu_valid_` vacuous.** The shipped guard therefore
compares **content**: the new cache must equal `S_clu_prev.cviSpk_clu(viClu_keep)`.
**Lengths in `S_clu` are actively falsified, not merely unchecked.**

### Caller impact — `merge_clu_` (irc.m:9344)

`delete_clu_` is the back half of every merge (`merge_clu_pair_` moves the spikes, then
`delete_clu_` removes the emptied source). An abort would leave the merge **half-applied**
while `ui_merge_clu_` calls `save_log_('merge %d %d')` **unconditionally** (irc.m:9334) —
logging a merge that did not happen. `merge_clu_` now snapshots and rolls the **whole merge**
back.

**⚠ Scope, stated honestly: this rollback is defence-in-depth and is probably UNREACHABLE.**
Tested on the real 547-cluster file: a cache malformed enough to fail `S_clu_select_` also
fails `S_clu_wav_` **first** (it indexes `cviSpk_clu{iClu}` for `iClu = 1..nClu`), so
`merge_clu_` throws before reaching `delete_clu_` — and **that throw is already safe**, since
MATLAB value semantics mean the caller's `S0.S_clu = merge_clu_(...)` assignment never runs,
nor does `save_log_`. The reachable, load-bearing guard is the one in **`delete_clu_`**, which
is called directly (9094, 9530, 19411) with nothing in front of it to throw first. Kept in
`merge_clu_` because `delete_clu_`'s abort returns *normally* rather than throwing, so it is
the only protection if the upstream ever becomes tolerant of a short cache.
**Cost:** one transient `S_clu` copy per merge (~250-500 MB at 17.6M spikes).

**Verified on REAL data 5/5** (`scratchpad/verify_merge_clu_real.m`, read-only): real merge
547→546 with **0 stale** per `S_clu_assert_synced_`; malformed cache fails loudly with caller
state byte-identical. Note 155,204+367,046 → **511,712** not 522,250 is *correct*:
`S_clu_refrac_` drops 10,538 ISI violators (2.02%). The first version of that test asserted an
exact sum and failed — the test was wrong, not the code.

**Verified 7/7** (`scratchpad/verify_delete_clu.m`): negative control reproduces the desync
(2 clusters) → fix leaves 0; rollback is byte-identical on `viClu` and `nClu`; happy path still
deletes (nClu 5→4), renumbers survivors 1..4, no desync.

## 2. `post_merge_wav_` (irc.m:4283) — CONFIRMED (was "unverified") and FIXED

The earlier report was right, and worse than described. 4286 stripped
`mrWavCor`/`trWav_raw_clu`/`tmrWav_raw_clu`; 4287 then returned early on `fSave_spkwav=0` —
**before** the rebuild that restores them.

1. **Latent crash:** signature is `[S_clu, nClu_merge]` and `auto_merge_` (irc.m:19440)
   requests **both** outputs with `fMerge=1`. The early return — and the `fMerge==0`
   fall-through — left `nClu_merge` **unassigned** → *"Output argument not assigned"*. Dormant
   only because this user runs `fSave_spkwav=1`.
2. **Cache destruction:** `mrWavCor` removed and never rebuilt.

Fix: `nClu_merge = 0` on entry; early return moved **before** the `rmfield_` so the bail-out is
a true no-op. **Verified 6/6** (`scratchpad/verify_post_merge_wav.m`).

## 3. parpool undersize-reuse (irc.m:2569) — FIXED

Was `elseif hPool.NumWorkers > nWorkers` — only ever **shrank** an oversized pool, so a stale
**undersized** pool was silently reused and the per-site loop ran narrow (observed: 3 workers
while the profile permits 8 and `.prm` requests 12). Now `~= nWorkers`: resizes either
direction and logs it. A correctly-sized pool is untouched, so it cannot disturb a run already
at the right width.

---

# Audit — do the fork's new clustering methods mishandle data? (2026-07-16)

**Verdict: no data-handling BUG found. But one setting is doing far more than it looks.**

## Checked and CLEAN

| Area | Finding |
|---|---|
| **global label offsets** (`cluster_labels_persite_`, irc.m:2620-2634) | **correct.** `viOffset = cumsum([0; vnLabel])` is safe *because* `cluster_site_` returns `nLabel = max(viLabel)` (irc.m:2695), **not** the unique count. Gappy labels (`[1 2 5]`) therefore reserve up to 5, so the next site cannot collide. Ids 3-4 are merely empty and get pruned. |
| **label contiguity** (`S_clu_from_labels_`, irc.m:2437-2441) | **safety net.** Remaps positive labels to 1..nClu via `unique`, so the gaps the max-based offsets create can't misalign `icl` with cluster numbers. `icl` is computed *after* the remap, so `icl(icl>0)` (2477) is the identity — no shrink/misalign. |
| **capped path propagation** (`cluster_site_capped_`, irc.m:2786-2803) | **indexes consistently.** `viLabel = viLabelSub(viNN)`, `miKnn1 = miKnnSub(:,viNN)`, `vrRho1 = vrRhoSub(viNN)`. Error fallback correctly resets `nLabel = 1` so no label gap is created. Subsample is RNG-seeded per site → identical under serial and parfor. |
| **parfor** | sliced outputs only; on failure the serial retry recomputes **all** sites, so no partial state survives. |
| **empirical** | **Test B: `S_clu_assert_synced_` = 0 / 547 stale on the fresh sort.** The clustering path produces a synced `S_clu`. |

## ★ MEASURED: `maxSpk_persite_clust = 20000` means most spikes were never clustered

Not a bug — documented behaviour of the per-site cap — but the magnitude is easy to miss.
Measured on this run (`scratchpad/check_cap_impact.m`):

| | |
|---|---|
| sites over the cap | **192 / 384 (50%)** — holding **91.3%** of all spikes |
| spikes **clustered** by ISO-SPLIT | 5,370,893 (**30.5%**) |
| spikes **1-NN propagated** | 12,245,613 (**69.5%**) |
| on capped sites, fraction clustered | median **38.5%**, **min 3.4%** |
| per-site counts | median 20,132 · mean 45,876 · p90 111,409 · **max 586,951** |

So ~70% of labels come from `nearest_in_set_` — copied from the nearest member of a 20k
random subsample — not from the clustering itself. On the busiest site (586,951 spikes) only
**3.4%** was clustered.

**Consequence: a unit is only resolvable if it has enough spikes IN THE SUBSAMPLE.** At 3.4%
sampling, a unit needs ~30x more spikes than `min_count` on that site to contribute
`min_count` points to the subsample; below that it is not found and its spikes are 1-NN'd into
whichever cluster is nearest. **Small units on busy sites are the ones at risk** — which is
worth noting given the original report concerned units "that should have very few spikes".

`default.prm`'s own comment recommends **50000-100000** to enable the cap; this run used
**20000**. Raising it trades sort time for recall of small units. Not changed — it is a
parameter choice, not a defect.

## Still open

- `struct_select_safe_` (19512) critical-field list, and excluding `cviSpk_clu` from the
  length-reconcile block (19669-19692). **Not changed:** both are on the sort path, and the
  `delete_clu_` content guard already blocks the damaging case locally.
- `P.viShank_site` all `1`s on a 4-shank Neuropixels 2.0 probe — belongs in the `.prb`.
- The fixes prevent *creating* a desync. They cannot make a delete correct on a file that is
  **already** desynced (`delete_clu_` still picks victims via `ismember(viClu, ...)`).
- `maxSpk_persite_clust = 20000` — a parameter choice, not a defect, but it left 69.5% of
  spikes 1-NN propagated rather than clustered (see the audit above).

## Environment note (not a code change)

Three stale entries — `D:\github\ironclustSW\{docker,img,matlab} - Copy` — were removed from
`C:\Program Files\MATLAB\R2023b\toolbox\local\pathdef.m` via `savepath`. They were already
being pruned at startup (hence the warnings) but a restored `matlab - Copy` would have
**shadowed the fixed `irc.m`**. Verified: `which('irc')` → `D:\github\ironclustSW\matlab\irc.m`.
Backup: `scratchpad/pathdef.m.backup`.
