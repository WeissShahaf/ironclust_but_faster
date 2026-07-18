# Changes Log - July 18, 2026

> **Plan:** `C:\Users\weisss\.claude\plans\velvet-tumbling-rocket.md` (measure-first, four review passes)
> **Grounding:** [`logs/investigation_maxSpk_persite_clust.md`](investigation_maxSpk_persite_clust.md),
> [`logs/plan_persite_spike_cap.md`](plan_persite_spike_cap.md)

## Summary

Two independent, additive performance changes to `matlab/irc.m` (+ `matlab/default.prm`), both scoped and
verified against the real `260324_afm18349` Neuropixels 2.0 recording (per-site label clustering,
`vcCluster='isosplit'`, `maxSpk_persite_clust` active):

1. **Part A — GPU-accelerate the per-site capped-cluster 1-NN assignment (`nearest_in_set_`).** On sites
   large enough to trip the `maxSpk_persite_clust` cap, every spike is assigned to its nearest clustered
   subsample member — a CPU-only chunked `pdist2` that a prior investigation identified as *"the structural
   killer for the cap regime."* Added an optional single-precision GPU path (gpuArray + `pdist2`) that is
   **measured ~25–28× faster than CPU with bit-exact indices**, with automatic CPU fallback on any GPU
   error, GPU-upload failure, or when running inside a `parfor` worker.
2. **Part B — cap the per-site clustering worker pool at 0.85× cores.** New `max_workers_(P)` helper +
   `parfor_core_factor` parameter (default 0.85), applied at the one place `irc.m` explicitly sizes a pool
   (`cluster_labels_persite_`). A general safety margin, **not** a fix for the separately-measured
   `fParfor=1` BLAS-oversubscription pessimization.

No commit changes any behavior for a run with `maxSpk_persite_clust=[]` (the default) — that path never
enters the capped branch — so the default configuration is byte-identical to before.

## Part A — GPU dispatch for `nearest_in_set_`

### Measure-first gate (Step 0)
Before writing any production code, a disposable script reproduced `nearest_in_set_`'s **exact** access
pattern (`nStep=10000`-chunked repeated `pdist2(..., 'euclidean', 'Smallest', 1)` against a fixed `m`-size
anchor set) on real cached features (`trFet_spk`) from the recording's busiest real site (#20,
n1 = 586,951 spikes, nFet = 36), CPU (double, as today) vs GPU (`gpuArray(single(...))`), RTX 4000 Ada:

| m (subsample) | n1 | CPU | GPU | speedup | index match |
|---|---|---|---|---|---|
| 100,000 | 586,951 | 181.1 s | 6.4 s | **28.1×** | 1.0000 |
| 150,000 | 586,951 | 259.9 s | 9.2 s | **28.1×** | 1.0000 |
| 200,000 | 586,951 | 340.4 s | 13.5 s | **25.2×** | 1.0000 |

This **disproved** a reviewer's hypothesis that the chunked pattern might be GPU-negative (each chunk is a
large `10000×m` distance block the GPU handles easily, unlike `persite_knn_`'s many-tiny-site regime), and
it **overturned the originally-planned `[X, Y]` upper CPU band**: GPU still wins 25× at n1 = 586,951, which
is *above* the proposed 400k ceiling, so an upper band would send the recording's 4 largest/costliest sites
backwards onto the slow path. Decision (user-confirmed): **GPU for all capped sites (`n1 > maxSpk`) when
`fGpu=1`, no upper band** — which also means `maxSpk_persite_clust` stays a plain **scalar** (no new API,
no parser, no `[X,Y]` vector), collapsing Part A to two functions.

### Changes
- **`irc.m` `nearest_in_set_`** — new optional trailing arg `fUseGpu` (default `false`; `nargin<3`
  preserves today's CPU-only path byte-identically). When true and not inside a `parfor` worker
  (`isempty(getCurrentTask())`), uploads the constant anchor set once via `gpuArray_` (which retries after a
  `gpuDevice(1)` reset), then runs the chunked `pdist2` on `gpuArray(single(...))`, VRAM-budgeting the
  chunk size from `gpuDevice().AvailableMemory`. **Any GPU error → logs, discards partial results, falls
  through to the unchanged CPU loop.** Because it runs once per site, one site's GPU failure falls back to
  CPU for that site while later sites retry GPU.
- **`irc.m` `cluster_site_capped_`** — passes `fUseGpu = get_set_(P, 'fGpu', 0)` into `nearest_in_set_`
  (any capped site is a GPU candidate; no upper band). Signature unchanged. Added a defensive
  `all(viNN >= 1 & viNN <= m)` post-call check that, if violated, throws into the existing try/catch →
  single-cluster fallback (guards against a future refactor weakening the parfor guard).
- **`default.prm`** — documented the GPU behavior and the `fGpu=0` escape hatch on the
  `maxSpk_persite_clust` comment.

### Deliberate behavior change (flagged)
For a config that already sets `maxSpk_persite_clust` **and** `fGpu=1`, the capped-site assignment now runs
on GPU instead of CPU. Output was **bit-exact** on real data, but the GPU path is single precision (CPU is
double), so on a near-exact distance tie the arg-min index *could* differ — i.e. not categorically
byte-identical. Escape hatch: `fGpu=0` forces the CPU path. Default (`maxSpk_persite_clust=[]`) is
unaffected.

## Part B — parfor worker-pool cap at 0.85× cores

### Real-evidence caveat
`logs/investigation_maxSpk_persite_clust.md` measured `fParfor=1` as a **~3× pessimization vs serial**,
*independent of worker count* (parfor×2 through ×12 all lose to serial), root cause BLAS-thread
oversubscription. A worker-count cap does **not** fix that; this change is a general safety margin only,
and `fParfor=0` remains the measured-correct setting for this workload class.

### Changes
- **`irc.m` `max_workers_(P)`** (new helper, near `gpuArray_`) — `floor(parfor_core_factor * nCores)` using
  the same probe `cluster_labels_persite_` already used (`parcluster('local').NumWorkers`, fallback
  `feature('numcores')`); factor defaults to 0.85, overridable via `P.parfor_core_factor`.
- **`irc.m` `cluster_labels_persite_`** — the pool-sizing block now clamps to `max_workers_(P)` (the only
  place `irc.m` explicitly sizes a pool).
- **`default.prm`** — new `parfor_core_factor = 0.85` in `#Execution parameters`.

An earlier draft's `ensure_parpool_cap_` pre-hook in `sort_` (to cap the other 33 bare `parfor` sites) was
**dropped** after review: it would fight `cluster_labels_persite_`'s own resize logic (delete/recreate the
pool it just built whenever `nWorkers_clust ≠ max_workers_`), and would pay `parpool` startup on every sort
by default (since `fParfor` defaults to 1) even when nothing downstream uses parallelism.

## Verification (MATLAB R2023b, real dev box + real recording; no synthetic-only claims)

- **`checkcode('irc.m')`** — no new messages on any edited line.
- **Part A, GPU == CPU:** `nearest_in_set_` bit-identical indices GPU vs CPU (`isequal` true, 0 mismatches)
  on synthetic input; Step 0 confirmed the same (index match 1.0000) on the real 587k-spike site.
- **Part A, CPU-only path:** 2-arg call (`nargin<3`) unchanged.
- **Part A, parfor guard:** `nearest_in_set_(...,true)` called from inside 2 `parfor` workers returns
  results matching the CPU reference exactly (`getCurrentTask()` → GPU declined → CPU used); serial GPU
  still works after pool teardown.
- **Part A, CPU fallback:** the GPU-upload-failure route (`fGpu_ok=0`) and the parfor-guard route both hit
  the CPU loop and are verified correct; the mid-loop GPU-exception catch falls through to that same proven
  CPU loop (verified by construction — a clean live GPU exception can't be forced without contrived fault
  injection, since the VRAM budget prevents OOM and `gpuArray_` auto-resets/retries).
- **Part B, `max_workers_`:** returns 13 = `floor(0.85 × 16)` on this box (profile reports 16 workers, not
  the 20 physical cores); `factor=0.5` → 8. The real `.prm`'s `nWorkers_clust=12` sits below the 13 cap, so
  B is a **no-op for this recording** (`min(12,13)=12`) and only bites requests > 13.
- **Not run:** a full end-to-end `irc sort` on the real recording (multi-hour). The changes are localized
  and the default `maxSpk_persite_clust=[]` path is untouched.

## Files
- Modified: `matlab/irc.m`, `matlab/default.prm`.
- Added: `logs/changes_log20260718.md`.

---

# Data-integrity remediation — audit + Phase 0-2 fixes (2026-07-18, later same day)

> **Tracker:** [`logs/ISSUE_TRACKER_data_integrity.md`](ISSUE_TRACKER_data_integrity.md) (22 findings
> DI-01…DI-22, prioritized, with solution designs + a phased build plan). Produced by a four-agent
> read-only audit (persistence/file-I/O · cluster-identity · detect/feature pipeline · cache mechanics),
> then a code-architect + devil's-advocate review. All 22 are distinct from the already-fixed
> `viClu`⇄`cviSpk_clu` desync family; the 15 CID fixes were re-verified present in current code.

Implemented **Phase 0 (shared foundation) + Phase 1 (DI-01) + Phase 2 (DI-02/05)** — the two
highest-severity, saveable, silent-corruption/loss bugs plus reusable infrastructure. Everything is
**additive** and no-op for existing callers on the healthy path.

## DI-01 (critical) — `[U]` multi-group merge silently merged the wrong clusters
`execute_pending_and_update_` (irc.m ~9843) processed each queued merge **group** against *static*
indices, but each in-group `delete_clu_` renumbers higher clusters. Step 1 deletes reconciled the
pending groups (`adjust_pending_indices_`, irc.m:9776); Step 2's per-group deletes did **not** — so with
≥2 groups in one `[U]`, a later group merged the wrong clusters (e.g. queue Clu3+5 and Clu7+9 → the
second merge hit original Clu8+Clu10). Internally consistent, so `S_clu_assert_synced_` reported 0 stale
— no detector caught it, and it saved to `_jrc.mat`. **Fix:** after each in-group delete, reconcile the
not-yet-processed groups via concatenation (the naive `cviMerge_pending(iGroup+1:end) = ...` form throws
because `adjust_pending_indices_` drops sub-2-member groups). Hand-verified twice (auditor +
devil's-advocate) and by the harness.

## DI-02 + DI-05 (critical) — silent save failure + non-atomic overwrite of `_jrc.mat`
`struct_save_` was `void` and never re-threw: 3 failed `save()` retries (AV/OneDrive/indexer lock, disk
full) printed "Saving failed" and returned as success — every unsaved curation lost silently. It also
`save()`d straight to the destination, so an interruption mid-write destroyed the previously-good file.
**Fix (both irc.m:15174 + irc2.m:7016 — the function is duplicated across files):** `struct_save_` now
returns `fOk` and writes atomically (`save` to `<file>.tmp` → `atomic_replace_` → `.bak` of the prior
file); `save0_` (irc.m:13161) checks `fOk`, blocks the false "success" (skips `export_prm_`), and warns.

## Foundation (A1/A2/A4) — reused by later phases
- **`tempname_sibling_` + `atomic_replace_`** (both files) — atomic temp+rename+backup helper
  (builtins only; refuses to commit a missing/zero-byte temp). Reused by DI-06/DI-15 in later phases.
- **`disperr_strict_`** (irc.m) — print-then-rethrow sibling of `disperr_` (whose console-only swallow
  is the root cause behind DI-02/06/07/08/09). Unused this phase; DI-08/09 wire to it in Phase 6.
- **`fread_` gains default-off `fStrict`** (both files) — `error`s on a short read; **its own `catch`
  now rethrows in strict mode** (else the strict error was swallowed at layer 0 — caught during
  verification). Default-off ⇒ the hot `load_file_`/detection path is byte-identical; DI-04 wires the
  `load_spk*_` callers in Phase 4.
- **`fwrite_` short-write count check** (irc.m) — returns `fSuccess=0` on a disk-full short count (which
  `fwrite` does not throw on). No-op until `write_spk_` consumes it in DI-07/Phase 4.

## Verification (MATLAB R2023b, real dev box)
`scratchpad/verify_phase012.m` — **12 checks, all green**: irc.m/irc2.m parse clean (checkcode: 0 parse
errors); DI-01 reconcile `[7,9]→[6,8]`; `struct_save_` healthy (`fOk=1`, content match, no `.tmp` litter)
and failure (`fOk=0`, no exception, **prior good file intact**); `atomic_replace_` refuses empty temp;
`fread_` 3-arg lenient unchanged + `fStrict` throws; `fwrite_` healthy returns 1. Not run: the full
GUI-driven `[U]` integration test (arithmetic negative control covers DI-01's logic, mirroring the
CID-01 `verify_reorder.m` convention).

## Files
- Modified: `matlab/irc.m`, `matlab/irc2.m`.
- Added: `logs/ISSUE_TRACKER_data_integrity.md`, `scratchpad/verify_phase012.m` (test harness, not committed).

## Phase 3 (later same day) — DI-06 + DI-15 (`.prm` integrity)

Both reuse the Phase 0 atomic-write foundation. `irc.m` only.

### DI-06 (high) — a transient read failure silently truncated the live `.prm`
`file2cellstr_`'s `catch` returned `{}` — indistinguishable from an empty file — so a momentary lock on
the `.prm` at edit time made `edit_prm_file_` rewrite it with only the currently-loaded `P` fields,
dropping comments/directives. **Fix:** `file2cellstr_` (irc.m:21907) returns a 2nd output `fOk`, `false`
only when the file EXISTS but can't be read (an *absent* file stays `fOk=true`, so `edit_prm_file_` can
still create a prm from scratch); `edit_prm_file_` (irc.m:21878) aborts instead of truncating on
`fOk=false`; `cellstr2file_` (irc.m:22010) writes to a temp then renames (atomic; `movefile` so a
legitimately-empty text file isn't refused). 4 other `file2cellstr_` callers and ~10 `cellstr2file_`
callers are unaffected (backward-compatible signature, behavior-preserving writes).

### DI-15 (high, upgraded from medium) — `export-prm` wiped the user's `.prm` in a fresh session
`irc('export-prm','x.prm')` (standalone form, no 2nd arg) `copyfile`'d the bare default template over the
target BEFORE reading `P`; in a fresh session `get0_('P')` is empty, so `P` was then read from the
*already-clobbered* file — permanently losing the user's probe/thresholds. **Fix:** `export_prm_`
(irc.m:23413) reads `P` from the source first, builds the full prm into a temp, and `atomic_replace_`s it
onto the target (with a `.bak`).

### Verification
`scratchpad/verify_phase3.m` — 7 checks, all green: irc.m parses clean; `file2cellstr_` readable/absent;
`edit_prm_file_` round-trip preserves comments+params (no truncation); `cellstr2file_` non-empty + empty;
**DI-15 standalone export preserves the user setting** (`sRateHz=12345`, was clobbered to default before).

## Phase 5 (later same day) — DI-10 + DI-11 (cache keys)

`irc.m` only; independent of the persistence work; lower-risk (no hot-path control-flow changes).

### DI-10 (high) — GPU kernel launch config baked in at construction, stale across files
The 7 GPU DPC/kNN kernels set `ThreadBlockSize`/`SharedMemorySize` inside their construction guard (keyed
on `nC` only, or `isempty(CK)`) while only `GridSize` was recomputed each call. A second file in the same
session with the same `nC` but different `P.nThreads`/`P.CHUNK`/`nC_max` (and bypassing `batch_`'s
`irc('clear')`) would launch a new-sized grid against the old shared-memory size. **Fix:** recompute all
three launch properties **every call** (mirroring irc2's `search_knn_drift_`), right before each kernel
`feval`, in `cuda_rho_`/`cuda_delta_`/`cuda_rho_drift_`/`cuda_delta_drift_`/`cuda_knn_`/`cuda_knn__`/
`cuda_delta_knn_`. Behavior-identical on single-file sessions (same values recomputed). Not exercised by
the testbed recording (`vcCluster='isosplit'` bypasses the DPC path).

### DI-11 (high) — get_spkwav_ global cache had no file key
`get_spkwav_`'s `tnWav_spk`/`tnWav_raw` globals were invalidated only on `isempty()`; the sole file-switch
cleaner was `load_cached_`, so any caller reaching `get_spkwav_` without it served the previous file's
waveforms. **Fix:** added a `persistent vcFile_prm_` key (mirroring `get_spkfet_`) that clears the globals
on a `vcFile_prm` change. Byte-identical for single-file sessions.

### Verification
`scratchpad/verify_phase5.m` — all green: irc.m parses clean; 7/7 DI-10 recompute sites present; DI-11
same-file keeps the cache and a file switch clears the stale global. DI-10's runtime multi-file GPU
divergence check is deferred (needs GPU hardware + two differently-configured recordings).

## Quick wins (later same day) — DI-12, DI-16, DI-17, DI-18, DI-22

Five small, low-risk fixes.
- **DI-12** (cosmetic) — `field2str_` (irc.m + irc2.m) gains `case 'string'` (formats a MATLAB `string`
  like a char literal, honoring `fDoubleQuote`) instead of warning + returning `''`. This is the exact
  error the user hit on 2026-07-18 (a `string`-class param blanked a line in the exported `_full.prm`).
- **DI-16** (non-default config) — `wav_car_`'s `'tmean'`/`'nmean'` branches now `sum(single(...))`
  before dividing, so an int16 reference sum can't saturate at ±32767 during large correlated events.
- **DI-17** (narrow) — `mr2tr_`'s `miRange = bsxfun(@plus, int64(...), int64(...))` (both sites) avoids
  int32 index saturation on >~20 h untransposed single-block recordings.
- **DI-18** (crash) — `post_merge_` coerces `post_merge_mode` to a scalar before the switch, so a `.prm`
  that sets it as an array (copy-paste from `post_merge_mode0`) no longer crashes the sort. Already hit
  in production (see project memory).
- **DI-22** (resource leak) — `readmda_paged_` (irc2.m) closes the previous file's `fid` before
  reopening on a file switch.

Verified (`scratchpad/verify_phase_qw.m`, all green): irc.m/irc2.m parse clean; `field2str_(string)` →
`'hello'`/`"hello"`; `mr2tr_` int64 returns the correct shape with no error; DI-16/18/22 edits present.
