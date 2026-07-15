# Changes Log - July 15, 2026

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
