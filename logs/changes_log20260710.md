# Changes Log - July 10, 2026

## Summary
Two small, additive changes to `matlab/irc.m` requested directly (no bug report):
1. Hardened the per-cluster waveform computation so it defaults to **median** (not mean)
   even in the (currently theoretical) case where `P.vcCluWavMode` is missing from a
   loaded `.prm`.
2. Added a `[5]` keyboard shortcut (and matching Info-menu item) in the manual curation
   GUI to annotate the selected unit as `collision` (spike collision), alongside the
   existing `[1]-[4]` single/multi/noise/axonal annotation hotkeys.

## Background — median vs. mean waveform
IronClust already had a mean/median toggle, `P.vcCluWavMode`, gating the single
choke-point for per-cluster waveform averaging (`clu_wav_`, used by `S_clu_wav_` and
`calc_raw_clu_`, which populate `S_clu.tmrWav_clu` / `tmrWav_spk_clu` / `tmrWav_raw_clu`
— consumed by every manual-GUI waveform display, `clu_info_`, `plot_tnWav_clu_`,
`plot_FigMap_`, and the "Export mean unit waveforms" menu items). `default.prm` already
sets `vcCluWavMode = 'median'`, and `loadParam_` always merges `default.prm` under the
user's `.prm`, so this already reaches `P` at runtime for any normally-loaded `.prm`.

The only gap: `get_set_(P, 'vcCluWavMode')` was called without a 3rd-argument default,
so `fMedian` would silently fall back to **mean** (or error) if `P.vcCluWavMode` were
ever absent from `P` (e.g. a hand-built `P` struct that skipped `loadParam_`). Fixed by
passing an explicit `'median'` default at both call sites. The existing mean option is
untouched — `rhs32_template.prm` still opts into `vcCluWavMode = 'mean'` explicitly and
continues to work as before.

A deeper audit (own + a background research agent) found one more mean() over spike
waveforms in the *default* automated post-merge path: `svd_mean_` (called from
`waveform_similarity_clu_`, `post_merge_mode2 = 19`, the default), which averages PCA
coefficients across spikes as part of merge-decision templates — not a value displayed
to the user. Left unchanged; this is a different kind of computation (drives automated
merge decisions, not the unit waveform shown/exported to the user) and out of scope for
this pass. Every other bare `mean()` found over spike waveforms
(`mean_wav_spk_`, `mean_tnWav_raw_`, `mean_align_spkwav_`, `tr2mr_mean_knn_`,
`post_merge_wav2_`, `post_merge_wav3_`) is dead/unreachable code with zero live callers
in `irc.m`, and `plot_clu_pairs_` (`irc plot-clupairs`) is a standalone diagnostic
command with a pre-existing unrelated bug (`meanSubt` undefined — should be
`meanSubt_`); neither was touched.

## Changes
- **`irc.m` `clu_wav_`** — `get_set_(S0.P, 'vcCluWavMode')` → `get_set_(S0.P,
  'vcCluWavMode', 'median')`.
- **`irc.m` `nanmean_int16_`** — same fix: `get_set_(P, 'vcCluWavMode')` →
  `get_set_(P, 'vcCluWavMode', 'median')`. (Currently dead code — no live callers — but
  hardened for consistency/future use.)
- **`irc.m` `keyPressFcn_FigWav_`** — added `case '5', unit_annotate_([], [], 'collision');`
  next to the existing `'1'`-`'4'` annotation hotkeys.
- **`irc.m` `add_menu_`** — added a `collision` entry to the unit-annotation Info menu,
  next to the existing `single`/`multi`/`noise` items.

## Verification
- `checkcode('matlab/irc.m')` — no parse errors; no new warnings on any edited line
  (pre-existing lint noise elsewhere in the file is unrelated).
- Manual re-read of both edited regions to confirm switch/menu syntax.
- Not run end-to-end in the MATLAB GUI (no interactive session available in this
  environment) — recommend a quick manual smoke test: open `irc manual` on any sorted
  `.prm`, press `5` on a selected unit and confirm it annotates as `collision`
  (visible via the Info menu / cluster label), and confirm `Edit prm file` / a fresh
  `irc sort` still runs without a `vcCluWavMode`-related error.

---

## Update — Splitting a tiny (n=2/3) cluster could dump thousands of spikes into one half

### Symptom
In manual curation, selecting a unit displayed with only 2-3 spikes and running
`[S]` split would frequently produce two resulting clusters where one held
**thousands** of spikes instead of the ~2-3 total being redistributed.

### Root cause
`auto_split_` and `split_clu_` both fetched the cluster's spike indices from the
`S_clu.cviSpk_clu{iClu}` cache, while the count the GUI displays (and the split's
own "≥3 spikes required" gate) reads `S_clu.vnSpk_clu` — which is always kept in
sync with the authoritative per-spike label vector `S_clu.viClu`. `cviSpk_clu` is
documented as a "pre-computed... for fast cluster operations" performance cache,
and can go stale relative to `viClu`/`vnSpk_clu` after merge/reorder operations
(a `struct_select_safe_` skip-on-error path in `S_clu_select_` can leave
`cviSpk_clu` un-reindexed while `vnSpk_clu`/`viClu` do get remapped). Because
*both* `auto_split_` (building the waveforms to cluster) and `split_clu_`
(committing the split) consistently read the same stale `cviSpk_clu{iClu}`, no
length-mismatch ever fired — they agreed with each other, just not with the
cluster's true (small, correctly displayed) membership — so the auto-split
algorithm partitioned thousands of unrelated spikes from a stale cache entry
into two uneven groups.

A prior patch attempt is visible in the removed code itself: `split_clu_` had a
comment ("use cviSpk_clu to match auto_split_ ... to ensure vlIn indices
match") and a defensive length-adjust block that treated agreement between the
two functions as sufficient — it didn't address that both could be consistently
wrong. `auto_split_` even had a commented-out correct version of the fetch
(`find(S_clu.viClu==iClu1)`) sitting unused next to the cache-based line.
Root-caused via a background Opus investigation that traced every
`cviSpk_clu`/`viClu`/`vnSpk_clu` mutation site in `irc.m` and found a removed
`getFet_clu_` staleness guard (pre-`b99996f` "Refactor and streamline cluster
and UI operations") that had explicitly detected `cviSpk_clu` entries with
spikes whose `viClu` disagreed — direct historical evidence `viClu`/`vnSpk_clu`
are the trustworthy pair and `cviSpk_clu` is the one that drifts.

### Fix attempt #1 (REVERTED — caused a worse regression)
First pass switched both functions to read unconditionally from
`find(S_clu.viClu==iClu1)` instead of the `cviSpk_clu` cache, on the theory
(backed by a removed `getFet_clu_` staleness guard, see above) that `viClu` is
always the trustworthy side. Shipped, then the user reported splitting stopped
working **entirely** — `[S]` on any cluster showed an empty/near-empty preview
instead of either a correct or a lopsided split. That regression is worse than
the original bug, so this needs to be right, not just plausible.

Two follow-up checks, done properly this time (empirically, not just by
reading code):
1. Suspected `auto_split_wav_`'s `pca(mrSpkWav, 'NumComponents', 3)` couldn't
   handle a genuinely tiny (2-3 spike) input and was erroring/bailing before
   ever showing the split figure. Verified empirically in MATLAB
   (`test_pca_maxcomp.m`): the real constraint is `NumComponents <=
   min(nFeatures-1, nSpks)`. This **does** throw outright at nSpks=2 (unreachable
   through the GUI's own "≥3 spikes" gate) but **does not** fail at nSpks=3, the
   actual minimum the gate allows (`pca` happily returns exactly 3 components).
   So this theory doesn't explain the regression, but the `pca` call was still
   one bad input away from an uncaught error with no fallback — hardened it
   anyway (see "Also fixed" below) since it's a real latent gap, just not this
   one's root cause.
2. That leaves one explanation: in the user's actual live session,
   `S_clu.viClu` was returning too few (or zero) spikes for a cluster whose
   `cviSpk_clu`/`vnSpk_clu` said otherwise — i.e. in practice `cviSpk_clu` is
   the side that stayed reliable and `viClu` the side that drifted, the
   opposite of what the static evidence (the removed `getFet_clu_` guard)
   suggested. Given this could not be reproduced or inspected live (no MATLAB
   GUI session / real sorted recording available in this environment), the
   static-analysis-only conclusion about *which* field is authoritative is not
   trustworthy enough to hardcode as done in attempt #1.

### Fix attempt #2 (shipped) — cross-validate instead of picking a side
New shared helper `get_clu_spk_confirmed_(S_clu, iClu1)`, used by both
`auto_split_` and `split_clu_`:
- Start from the `cviSpk_clu` cache (the side that empirically kept working).
- Intersect with spikes `S_clu.viClu` also attributes to `iClu1`. This can only
  **shrink** an over-large/stale cache entry, never grow it — directly bounding
  the original "thousands of spikes" failure mode.
- If the intersection comes back empty (the two sources disagree completely),
  fall back to the raw, unfiltered cache rather than returning nothing — this
  is what prevents attempt #1's "no spikes at all" regression.
- `split_clu_` calls the identical helper so `vlIn`/`vlSpkIn` stay index-aligned
  between the two functions (same invariant the original, insufficient patch in
  the code was reaching for).
- Verified with a standalone scenario test (`test_get_clu_spk_confirmed.m`,
  outside the repo, not committed) covering: (1) cache/viClu agree — no-op: (2)
  the original stale/huge-cache bug — correctly shrinks to the confirmed
  subset; (3) the attempt-#1 regression shape (viClu disagrees with the entire
  cache) — falls back to the cache instead of going empty; (4) empty cache
  entry — falls back to `find(viClu==iClu1)`. All four pass.

### Also fixed — `auto_split_wav_` PCA component count
Regardless of it not being the regression's root cause, `pca(mrSpkWav,
'NumComponents', 3)` was one unguarded call away from throwing outright on a
tiny-enough cluster (confirmed at nSpks=2, which the `auto_split_` gate
currently keeps unreachable, but the function has no gate of its own). Capped
the request to `min(3, nFeatures-1, nSpks)` — empirically verified to be a
no-op for nSpks>=3 (identical behavior to the old hardcoded 3) and to degrade
gracefully instead of erroring below that.

### Deferred (flagged, not fixed this pass)
- `getFet_clu_` (feeds FigProj/FigTime feature displays and the *manual*
  polygon-based split route via `plot_split_`) reads the same stale
  `cviSpk_clu{iClu1}` cache. Left as-is: it's a read-only display path (lower
  severity than the destructive commit fixed above), the manual-split route's
  destructive commit still goes through the now-fixed `split_clu_` (so it can
  no longer balloon a tiny cluster into thousands, just potentially preview/
  select from a stale feature set), and `find()` over the full spike-label
  vector on every feature redraw has a real performance cost worth weighing
  separately rather than folding into this fix.
- The underlying `struct_select_safe_` skip-on-error mechanism that lets
  `cviSpk_clu` drift out of alignment with `viClu` in the first place was not
  touched — the fix addresses the point of use (the only place that matters for
  correctness of a destructive operation), not the upstream cache-staleness
  source itself.

### Verification
- `checkcode('matlab/irc.m')` — no parse errors; no new warnings on any of the
  edited lines; same total lint-message count as before this whole day's edits
  (998), confirming nothing else regressed.
- `pca()`'s exact `NumComponents` constraint and `get_clu_spk_confirmed_`'s
  4 scenarios were checked by actually running MATLAB against synthetic
  inputs (not just read/reasoned about) — see the two attempts above. This is
  a step up from fix attempt #1, which was static-analysis-only and shipped a
  regression as a result.
- Still **not** run end-to-end in the real MATLAB GUI against a real sorted
  recording (none available in this environment) — the empirical checks above
  cover the isolated logic, not the full integrated `irc manual` flow.
  Recommended smoke test: on a sorted `.prm` with a cluster displayed as n=2 or
  n=3, `[S]` split it and confirm (a) the preview figure actually shows a
  split (not blank), and (b) both resulting clusters stay small (sum ≈
  original n) instead of one ballooning. If it's easy to do, also flag which
  behavior you're seeing (previously: "no spikes displayed"; before that:
  "one huge cluster") in case another round of iteration is needed — the
  fallback-to-cache behavior means a genuine, deep desync between `cviSpk_clu`
  and `viClu` would now show the *original* symptom again (bounded, not
  unbounded) rather than an empty split, which would itself be useful
  diagnostic signal.

---

## Update — Follow-up: does the same staleness class touch automated `irc sort`?

### Question
The split bug above was traced to `cviSpk_clu` (a cache) drifting stale
relative to `viClu`/`vnSpk_clu` (authoritative). `clu_wav_` — the function
computing per-cluster waveform templates used by both the GUI display *and*
the automated merge-decision correlation matrix (`S_clu_wavcor_`) — also reads
from `cviSpk_clu{iClu}`, unchanged by this pass. Given that, could the same
underlying desync (not the specific, now-fixed `auto_split_`/`split_clu_` bug)
have corrupted results from an automated `irc('sort', ...)` run?

### Answer
**No for the specific bug fixed above** — confirmed directly: every call site
of `auto_split_`/`split_clu_` (grepped across `irc.m`) is a manual-curation
GUI callback (menu item, `[S]` keyboard handler, polygon-select handler).
`irc('sort', ...)` never calls either function, so that exact code path cannot
have touched an automated run.

**Leaning no, but not provably zero, for the deeper `cviSpk_clu`-staleness
mechanism in general**, per a background investigation that traced every
automated call chain touching `cviSpk_clu`:
- `S_clu_refresh_` and `S_clu_map_index_` — the automated pipeline's own
  rebuild points — unconditionally recompute `cviSpk_clu = vi2cell_(viClu)`
  from `viClu` directly, bypassing `S_clu_select_`/`struct_select_safe_`
  entirely for this field. Self-healing by construction.
- `S_clu_refrac_`, part of the automated auto-merge chain
  (`S_clu_wavcor_merge_` → `S_clu_map_index_` → `S_clu_refrac_` →
  `S_clu_wav_`), updates `viClu`, `cviSpk_clu{iClu1}`, and `vnSpk_clu(iClu1)`
  together in lockstep, and runs immediately after a fresh
  `S_clu_map_index_` rebuild — so `clu_wav_`'s read of `cviSpk_clu` in this
  chain is fed a cache that was just rebuilt, not one that had a chance to
  drift.
- `S_clu_remove_empty_`/`S_clu_keep_` do route through `S_clu_select_`/
  `struct_select_safe_` (the actual skip-on-error mechanism implicated in the
  GUI bug), but every automated predecessor traced hands them an
  already-consistent cache — the skip path's precondition wasn't observed to
  be set up anywhere in the automated chain.
- No evidence in `logs/*.md` that the `struct_select_safe_` skip-on-error
  warning has ever actually fired during a real run (only the source lines
  defining the warning were found, not an incident report).
- `logs/changes_log20260626.md`'s earlier, independent hardening pass already
  verified "no healthy run of any clustering method changes its output."

**Residual uncertainty**: not every automated caller of `S_clu_select_` was
exhaustively checked (e.g. `S_clu_from_labels_`, the per-site cluster assembly
path), so an as-yet-unfound desync-introduction point elsewhere in the
automated pipeline can't be fully ruled out by static tracing alone.

### Deferred (not fixed this pass — investigation only)
No code changes made for this question; `clu_wav_`'s read from `cviSpk_clu`
was left as-is, consistent with the finding that the automated chain feeds it
an already-fresh cache in every traced path.

### Suggested resolving check (not run — no live session available)
Re-run the degenerate per-site scenario from `changes_log20260626.md`
(isosplit + spike cap producing ~1000+ small clusters) and grep console
output for `struct_select_safe_: skipped field` / `S_clu_select_: Warning` /
`S_clu_select_: Error resizing`. If none fire, that's empirical (not just
static) confirmation the automated path stays clean in practice.

---

## Update — Resolving check: does the skip-path actually produce a stale cache?

### What this checks
The prior update left one open question: does the automated pipeline ever hit
`struct_select_safe_`'s skip-on-error path in `S_clu_select_`, and if so, does
`cviSpk_clu` end up stale relative to `viClu` afterward, or is the "final
length reconciliation" block (added in the June 26 hardening pass) enough to
keep it correct? This was checked empirically rather than by further static
reading.

### Method (Tier 2 — verbatim code, synthetic inputs; no real recording available)
No real failing `.bin`/`.prm` session exists in this environment, and standing
up a synthetic end-to-end `irc('sort', ...)` run (probe file, raw data, full
parameter set, GPU-dependent stages) was judged impractical for the signal it
would add. Instead, `struct_select_`, `struct_select_safe_`, `S_clu_select_`,
`S_clu_wavcor_remap_`, `S_clu_remove_empty_`, `S_clu_keep_`, and `vi2cell_`
were copied **verbatim** (not reimplemented) from the current `irc.m` into a
standalone script
(scratchpad `test_stale_cache_check.m`, not part of the repo) and driven
against a synthetic `S_clu` shaped like the real 1081-cluster degenerate run
(many clusters sized 0-5, ~50 empty, plus `viSite_clu`/`mrWavCor`/
`csNote_clu`/`tmrWav_clu` so all of `S_clu_select_`'s field-type branches are
exercised). Three scenarios, run via `matlab -batch`:
- **A — healthy**: `cviSpk_clu` correctly sized before calling
  `S_clu_remove_empty_`.
- **B**: `cviSpk_clu` deliberately one cell short before the call (simulating
  a field that drifted out of sync from some earlier, unmodeled operation),
  then `S_clu_remove_empty_`.
- **C**: same corruption, via `S_clu_keep_` instead.

### Result
- **Scenario A (healthy)**: no warnings printed; post-call `cviSpk_clu`
  matched a from-`viClu` rebuild exactly. Confirms the June 26 claim — a
  clean input produces no skip and no drift.
- **Scenario B**: `struct_select_: Error resizing field "cviSpk_clu" ...The
  logical indices contain a true value outside of the array bounds.` →
  `struct_select_safe_: skipped field "cviSpk_clu": ...` → `S_clu_select_:
  reconciled length of field "cviSpk_clu" to 859` all fired, exactly as the
  source predicts. After the call, `cviSpk_clu` had the *correct length*
  (859, matching the new `nClu`) but **wrong contents** — 857 of 859 clusters
  diverged from a `viClu`-derived rebuild (e.g. cluster 3: truth 1 spike,
  cache 0 spikes). The length-reconciliation block pads/truncates the
  *stale* pre-skip array rather than rebuilding it, so the resulting
  `S_clu` is shape-consistent (won't crash on a dimension mismatch) but
  silently wrong — and it prints to stderr, not somewhere a batch/automated
  run's log would typically surface.
- **Scenario C (`S_clu_keep_`)**: same pattern — skip fires, reconciliation
  masks the shape, 846 of 848 clusters diverge.

### Interpretation
This **confirms the mechanism is real and not merely theoretical**: if
`cviSpk_clu` is ever mis-sized relative to `S_clu.nClu` at the moment
`S_clu_remove_empty_`/`S_clu_keep_` runs, the current code silently produces
a shape-valid but content-stale cache, matching exactly the failure class
behind the manual-split bug fixed earlier today.

What this test does **not** show: whether the automated `irc('sort', ...)`
pipeline ever actually produces that mis-sized precondition on its own. That
question was addressed separately (see the previous update) by tracing every
automated caller — `S_clu_refresh_`/`S_clu_map_index_` rebuild `cviSpk_clu`
directly from `viClu` (bypassing this mechanism entirely), and the automated
callers of `S_clu_remove_empty_`/`S_clu_keep_` were found to hand them an
already-consistent cache in every path traced. Combining both results: the
**vulnerability is live and would bite silently if triggered**, but no
concrete automated trigger path has been found, and this test does not
change that — a full synthetic or real end-to-end `irc sort` run (Tier 1)
would be needed to either produce or rule out the triggering precondition
itself.

### Verification
- `matlab -batch` run of `test_stale_cache_check.m` (scratchpad, not
  committed) — exit code 0, all three scenarios completed, output as above.
- Not run against the real pipeline or a real recording (none available);
  this is synthetic-input verbatim-code testing, one tier down from a live
  `irc sort` run.

## Files
- Added: `logs/changes_log20260710.md`.
- Modified: `matlab/irc.m`.
