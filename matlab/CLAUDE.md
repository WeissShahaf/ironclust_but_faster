# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

IronClust is a MATLAB-based spike sorting software for neural electrophysiology data analysis. It processes high-channel-count extracellular recordings to identify and cluster action potentials (spikes) from multiple neurons.

## Architecture and Core Components

### Main Entry Point
- **`irc.m`**: Primary command interface for IronClust (version 1) - handles all spike sorting operations
- **`irc2.m`**: Alternative version with different algorithms and optimizations
- Command pattern: `irc('command', arg1, arg2, ...)` for all operations

### Data Processing Pipeline
1. **Preprocessing**: Bandpass filtering, artifact removal, whitening
2. **Detection**: Threshold-based spike detection with GPU acceleration
3. **Feature Extraction**: Principal components, waveform features
4. **Clustering**: Density-based clustering with drift correction
5. **Post-processing**: Automated merging, manual curation GUI

### Key Configuration Files
- **`default.cfg`**: System-wide configuration settings
- **`default.prm`**: Default spike sorting parameters
- **`.prm` files**: Parameter files for individual recordings

### GPU Acceleration
- CUDA kernels in `.cu` files with compiled `.ptx` files
- GPU operations for spike detection, feature extraction, clustering
- Memory-efficient algorithms for large datasets

## Common Commands

### Running Spike Sorting
```matlab
% Basic spike sorting workflow
irc('makeprm', 'recording.bin', 'probe.prb')  % Create parameter file
irc('detect', 'recording.prm')                 % Detect spikes
irc('sort', 'recording.prm')                   % Sort spikes
irc('manual', 'recording.prm')                 % Manual curation GUI
```

### Data Analysis
```matlab
irc('describe', 'recording.prm')  % Display sorting statistics
irc('traces', 'recording.prm')    % View raw traces
irc('export', 'recording.prm')    % Export results
```

### Testing and Validation
```matlab
irc('unit-test')                   % Run unit tests
irc_scoreboard()                   % Run validation on ground-truth data
```

### GPU Setup
```matlab
irc('compile')  % Compile CUDA kernels
```

## File Organization

### Input/Output Files
- **Input**: `.bin` (raw data), `.prb` (probe geometry), `.prm` (parameters)
- **Output**: `_irc.mat` (sorting results), `_spkwav.mat` (waveforms), `_spkraw.mat` (raw spikes)

### Data Structures
- **`S0`**: Main state structure stored in UserData (contains S_clu, P, etc.)
- **`S_clu`**: Clustering results (spike times, cluster IDs, waveforms)
- **`P`**: Parameter structure loaded from .prm files

## Performance Optimizations

### Cluster Merging (manual curation GUI)
Merges and deletes are **queued, then applied together** — they are not applied on keypress:
- `[M]` queues a merge (`ui_merge_pending_`); `[D]`/Backspace/Delete queues a delete (`ui_delete_pending_`)
- `[U]` applies all pending operations and refreshes the figures (`execute_pending_and_update_`)
- `[Escape]` discards pending operations (`cancel_pending_operations_`)
- **Abort propagation (P2, 2026-07-16):** `delete_clu_`/`merge_clu_` return a 2nd output `fOk`
  (`false` when they roll back rather than commit a desync). All callers
  (`execute_pending_and_update_`, `ui_merge_`, `ui_delete_`, `delete_auto_`) gate their
  log/queue/overlay bookkeeping on `~fOk`, so an abort writes **no** phantom log entry, shifts
  **no** queue index, and pops no "Deleted N clusters" lie. A group `[U]` merge is atomic — a
  mid-group abort rolls back the **whole** group. On healthy input `fOk` is always `true`, so the
  guards are dead and behavior is byte-identical.

### Cluster state: `viClu` is authoritative, `cviSpk_clu` is a cache
- `S_clu.viClu` — per-**spike** cluster labels. **The source of truth.** Every cache rebuild
  derives from it (`S_clu_refresh_`, `S_clu_update_`, `merge_clu_pair_`).
- `S_clu.cviSpk_clu{i}` — per-**cluster** spike indices. A derived cache that exists to avoid
  `find()` over millions of spikes; it can drift stale relative to `viClu`.
- **`S_clu_select_` reindexes per-cluster fields only and CANNOT remap `viClu`** (that name ends
  in `Clu`, not `_clu`, so it matches none of its patterns). Any caller passing a permutation
  that changes cluster **identity** must remap `viClu` itself first — see `clu_reorder_` for the
  correct pattern. Omitting this silently corrupts cluster identity and `save0_()` persists it
  (this was the `reorder_clu_by_coords_` bug; see `logs/changes_log20260715.md`).
- `S_clu_valid_` checks array **lengths** only, never content — it will not catch a desync.
- **The invariant to preserve:** `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for every `i`.
  `S_clu_assert_synced_` (gated by `fCheck_clu_sync`, default 1) checks it and **warns without
  gating** — gating would make `S_clu_commit_` revert, which is the very silent-data-loss mode it
  exists to expose. It runs from `S_clu_commit_` **and** (added 2026-07-16, plan P1/P3a) from
  `load0_` (a disk desync is announced at open time, not just on the next commit) and from
  `reorder_clu_by_coords_` (the `[O]` path, which `save0_()`s directly and bypasses the commit
  choke point — the exact path the original desync lived on).

### ⚠ Never trust a LENGTH check on `S_clu` — the lengths are actively falsified

`S_clu_select_` ends with a **length-reconcile block** that force-fits every wrong-length
`v*_clu` / `c*_clu` field to `nClu_new`. Historically, combined with `struct_select_safe_` —
which skipped a field it could not resize and **returned normally without raising** — the result
was: content stale, length correct, no exception. This is why `S_clu_valid_` is vacuous here, and
it silently defeated a length-based guard in `delete_clu_` (caught only by a negative control).

> **P3b (2026-07-16) closed this for the identity-bearing field.** `struct_select_safe_` now takes
> a `csCritical` list; `S_clu_select_` marks **`cviSpk_clu` critical**, so a resize failure on it
> **re-throws** instead of being skipped-and-padded. `delete_clu_`'s try/catch turns that into a
> clean rollback; the four non-guarded callers (`S_clu_remove_empty_`, `S_clu_keep_`,
> `clu_reorder_`, `reorder_clu_by_coords_`) would **crash** rather than silently desync — a
> deliberate crash-vs-silent-corruption trade. **The reconcile block still falsifies the OTHER
> fields' lengths**, so the rule below stands for everything except `cviSpk_clu`.

**Any guard in this area must compare CONTENT** — e.g. the new cache must equal
`S_clu_prev.cviSpk_clu(viClu_keep)`. See `delete_clu_` for the correct pattern.

> **`delete_clu_` (irc.m:9140) — FIXED 2026-07-15, and it is the reference pattern.** It used
> to remap `viClu` unconditionally while its cache remap sat in a `try/catch` that only
> printed — and the catch **could not fire** (see above). It now snapshots `S_clu`, verifies
> the cache was *actually permuted* (content, not length), and **rolls back** rather than
> commit a half-applied remap. Note `delete_clu_` is also the back half of every merge
> (`merge_clu_`, irc.m:9314), so an abort leaves the merge half-applied — the source survives
> as an *empty* cluster; `merge_clu_` detects and reports this. Evidence the bug was real:
> 7,172 deleted spikes were found inside live cache entries.
>
> **Still true regardless of the fix:** `delete_clu_` picks victims via
> `ismember(viClu, viClu_delete)`. On an *already*-desynced file the user deletes what the GUI
> shows (the **cache's** cluster) while the code marks negative whatever **`viClu`** says —
> so each delete compounds the damage. The fix prevents *creating* a desync; it cannot make a
> delete correct on a file that is already desynced. Heed `S_clu_assert_synced_`'s warning.

> **Corrupted `_jrc.mat` files are NOT repairable.** Do not attempt a relabel-from-cache
> recovery: cache and `viClu` are *different partitions*, not the same one relabelled (52/190
> cache entries span >1 label). Do not trust a "which side is authoritative" check —
> `vnSpk_clu`/`viSite_clu`/`vrPosY_clu` all **derive from the cache** (irc.m:7401, 7407,
> `S_clu_subsample_spk_`:11652), so they agree with it by construction and such a check
> **cannot fail**. See `logs/issue_viclu_desync_20260715.md` §7. Re-sort instead — the sort
> pipeline is clean (every path ends in `S_clu_refresh_`); this is a GUI-curation artifact.

> **Stale docs — do not trust:** `MERGE_OPTIMIZATIONS.md`, `OPTIMIZATION_SUMMARY.md`,
> `PROFILER_ANALYSIS.md`, `PERFORMANCE_AUDIT.md`, `GUI_PERFORMANCE_OPTIMIZATIONS.md`, and
> `GPU_USAGE_ANALYSIS.md` describe functions that **do not exist** in `irc.m`
> (`ui_merge_batch_`, `update_correlation_after_merge_`, `compute_cluster_correlations_`,
> `fUpdateImmediate`, `fUpdateCorrelation`, the `[B]` batch key, and a cached-index fast path in
> `merge_clu_pair_`). They are proposals that were never implemented. Verify against `irc.m`
> before relying on any claim in them.

### Data-integrity hardening (2026-07-18) — see `logs/ISSUE_TRACKER_data_integrity.md`

A 22-item audit (DI-01…DI-22) fixed silent corruption/loss + cache-staleness across persistence, the
detect/feature pipeline, and caches (branch `rewind`, commits `bcbe008`→`1cb9888`). Contracts a future
change must **preserve**:

- **`struct_save_` returns `fOk` and writes atomically** (temp `<file>.tmp` → `movefile` → `.bak`;
  refuses an empty temp) — in **both** `irc.m` and `irc2.m` (the function is duplicated). `save0_`
  checks `fOk`, shows a blocking `msgbox_`, and **returns without running `export_prm_`** on failure.
  Do not revert to a direct `save(...)` — it guards a good `_jrc.mat` against crash/lock truncation
  (DI-02/05).
- **`[U]` multi-group merge** (`execute_pending_and_update_`) reconciles the *not-yet-processed*
  pending groups after each in-group `delete_clu_` (concatenation form, reusing
  `adjust_pending_indices_`). Without it, batching ≥2 merge groups silently merges the wrong clusters,
  and `S_clu_assert_synced_` does **not** catch it (wrong-but-consistent). DI-01 — distinct from the
  `viClu`/`cviSpk_clu` desync family.
- **`fread_`/`load_bin_` take a default-off `fStrict`** that rethrows on a short read; the **feature**
  loaders (`load_spkfet_`, `get_spkfet_`) pass `true`, so a truncated `_spkfet.jrc` errors instead of
  silently misaligning clustering features (DI-04). Raw/spk display loaders stay lenient by design.
- **`write_spk_` returns `fOk`** (guards `fopen('W')==-1`, checks `fwrite` counts); `file2spk_` **aborts**
  on a failed/short write and builds its `dimm_*` template from the **first non-empty chunk** so a quiet
  tail no longer zeroes dims 1-2 (DI-03/07).
- **`disperr_` still swallows AND resets the GPU** (`gpuDevice(1)`). For paths that must fail loud, use
  the new **`disperr_strict_`** (print + rethrow). The per-site `mn2tn_wav_`/`spikeMerge_` catches now
  **count + warn loudly** instead of swallowing (DI-08/09, count-and-continue — not a hard abort).
- **Cache keys:** `get_spkwav_` keyed on `vcFile_prm` (DI-11, mirrors `get_spkfet_`); the GPU CUDA
  kernels recompute launch config every call (DI-10); `sgfilt4_`/`sgfilt_init_` key on `fGpu` (DI-19).
- **Not yet run:** a full end-to-end `irc('sort', …)` on a real recording — recommended before relying
  on the detection-pipeline changes in production.

### Testing existing sorts for the desync — read-only diagnostics (2026-07-20)

`matlab/check_jrc_sync.m` (+ `check_jrc_one.m`) tests any `_jrc.mat`/`.prm`/folder/list for the
`viClu`⇄`cviSpk_clu` desync (`all(viClu(cviSpk_clu{i})==i)`); `scan_jrc_report.m` batches a
`label,jrc` manifest → per-session logs + an `AFFECTED_REPORT.md`; `analyze_desync.m` reports
clean-permutation-vs-compounded (how much grouping survives); `export_desync_clusters.m` emits a
per-(session,cluster) CSV. **All strictly read-only — they only `load()`, never write a `_jrc.mat`.**

`matlab/repair_clu_sync.m` belongs to this group **in practice**: it has a write mode, but on every
file observed so far it refuses to use it, so treat it as a diagnostic.

```matlab
repair_clu_sync(vcFile_jrc)                  % DRY RUN — reports only, writes nothing
S = repair_clu_sync(vcFile_jrc);             % same, returns the diagnostics struct
repair_clu_sync(vcFile_jrc, vcFile_out)      % WRITE — only if the dry-run VERDICT is clean
```

- One arg = dry run; two args = write a **new** file (it errors if in == out). `irc.m` must be on
  the path — it reaches `S_clu_assert_synced_` via `irc('call', …)`, and `assert_ran_` errors rather
  than let an **un-run** check read as a pass (`test_` swallows dispatch errors and returns `[]`).
- It rebuilds **`viClu` FROM `cviSpk_clu`** — the opposite direction from `S_clu_refresh_`, which
  rebuilds the cache from `viClu`. Never "repair" a desync with `S_clu_refresh_`: it locks the
  corruption in irreversibly.
- **The only non-circular block in its output is PURITY** ("cache entries spanning >1 viClu label").
  `>0` means cache and `viClu` are *different partitions* and no relabelling reconciles them. The
  **DIRECTION CHECK is circular by construction** — `viSite_clu`/`vnSpk_clu`/`vrPosY_clu` all derive
  from the cache, so they agree with it whether it is pristine or garbage; it cannot fail. The
  after-repair `S_clu_assert_synced_` is likewise near-vacuous (it checks what the function just
  forced to agree).
- Write mode hard-refuses on any of: unconverged, mixed partitions, duplicate-claimed spikes, lost
  deletions, **resurrected** deleted spikes (negative `viClu` still sitting in a cache entry),
  orphans, out-of-range indices, `nClu ~= numel(cviSpk_clu)`, or a failed direction check.
- **Status: the repair path does not work on any observed file** (overlapping cache → not a
  partition; 413k orphans; deleted clusters resurrected) and correctly refuses — see
  `logs/investigation_split_root_cause.md`. For an actual fix use `resync_clu.m` (preferred) or
  `recover_from_snapshot.m` below.

A field scan of both projects' paths CSVs found **22 corrupted sorts** (afm17307/17313/17372 in
Project_hierarchy; afm18349/18367 in cuniform_NPX), all DESYNC-SEVERE (see
`logs/DATASET_INTEGRITY_REPORT.md` and `logs/jrc_scan_*/`). A `PASS` means "currently
self-consistent", not "never corrupted"; the DI-01 `[U]` wrong-merge is undetectable by these tools
(internally consistent). **The old "not repairable → re-sort" verdict is superseded** — the
write-side tools below remediated all 22 without a re-sort (2026-07-25).

### Remediating the desync — write-side recovery tools (2026-07-25)

Companions to the read-only diagnostics (`matlab/`, committed `56389c0`) that fix a desynced
`_jrc.mat` **without a full re-sort** — detection artifacts (`_spkfet/_spkraw/_spkwav`) and the kNN
graph (`rho/delta/miKnn`) are cached on disk, so only the fast clustering-finalize is redone:

- **`recover_from_snapshot.m`** — reset `S_clu.viClu = viClu_premerge` (but see the write-once
  correction below) and re-run `post_merge_` → synced clustering + all per-cluster fields rebuilt. **Discards curation
  (renumbers to a clean AUTO baseline).** DPC regenerates `viClu` from the density graph; label-based
  re-merges. Use when the curated `viClu` is genuinely broken (many fusions).
  > **⚠ It also wipes `csNote_clu`, and that breaks downstream selection.** Both consumer pipelines
  > (Project_hierarchy `preprocessFunctions.load_IRC`, cuniform `load_irc_to_spi.py`) select units
  > **solely** by `_quality.csv` `note == 'single'`. A recovered file exports every note blank →
  > `good_clusters` empty → **zero neurons downstream**, and the `_jrc.mat` PASS check cannot see it
  > (it only tests the `viClu`⇄`cviSpk_clu` invariant). Both files recovered on 2026-07-25 were
  > reverted to `resync_clu` for exactly this reason. **Prefer `resync_clu` unless the file will be
  > re-curated by hand.** See `logs/REMEDIATION_desync_field_20260725.md`.

> ### ⚠ CORRECTION (2026-08-02): `viClu_premerge` is **NOT** write-once
>
> This file previously called it a "pristine write-once snapshot". That is **wrong**.
> `post_merge_` assigns `S_clu.viClu_premerge = S_clu.viClu` **unconditionally, every time**
> (`irc.m`, immediately before the `csNote_clu` reset).
>
> - **DPC sorts are safe**: `postCluster_` regenerates `viClu` from the density graph first, so
>   what gets stored is a genuine auto baseline.
> - **Label-based sorts are NOT**: `postCluster_` is skipped when `fLabelClu`
>   (kmeans/hdbscan/isosplit/classix), so `viClu` at that point is still the **curated** labelling.
>   Every `post_merge_` + save therefore overwrites the snapshot with curated labels and
>   **permanently disables `recover_from_snapshot.m` for that file** — silently.
>
> Practical rule: on a label-based sort, treat `viClu_premerge` as "whatever the last recompute
> saw", not as a pristine baseline. Verify it before relying on it. Reaching the recompute branch —
> via `irc manual` → "No", or `irc recurate` — is what triggers the overwrite; `irc recurate` warns
> about this in its consent dialog when the sort is label-based.
> Full write-up: `logs/ISSUE_viClu_premerge_not_write_once.md`.

### `irc recurate` — curation GUI without the load prompt (2026-08-02)

`irc('recurate', prm)` opens the same GUI as `irc manual` but **always** takes the recompute branch,
skipping the "Load last saved or recompute?" dialog. It is the `'no'` answer with no chance of
mis-clicking `'yes'` — implemented as a fourth `vcMode` in `manual_` alongside
`'normal'`/`'debug'`/`'groundtruth'`; the `'normal'` path is untouched.

It is **destructive** and gated behind an OK/Cancel consent dialog (`confirm_recurate_`) that names
every consequence: merges/splits/deletes discarded, `csNote_clu` reset (→ zero neurons downstream
until re-curated, see the quality-CSV note gate above), `<prm>_log.mat` removed, and — for
label-based sorts only — `viClu_premerge` overwritten.

- **`backup_log_file_`** copies `<prm>_log.mat` → `<prm>_log.mat.bak_recurate` first. `clear_log_`
  deletes that file *immediately*, before the user ever reaches the GUI's save prompt, and it is the
  only record of `csNote_clu`/`viClu` outside the `_jrc.mat` (`save_log_` writes both).
- Buttons are **OK/Cancel, not Yes/No, on purpose**: `questdlg_` returns `'Yes'` whenever the global
  `fDebug_ui==1`, which with Yes/No would mean *proceed destructively* in a headless run. `'Yes'`
  matches neither button, so it falls through to Cancel.
- The dispatch case **must** end in `return;` — same as `manual-gt`/`manual-test`. The alias
  `manual-recurate` was deliberately **not** added: it contains the substring `'manual'` and would
  be re-caught by the greedy `contains_` fallback, re-opening the GUI with the very dialog the
  command exists to skip.
- **`resync_clu.m`** — **keeps** the curated `viClu` numbering; rebuilds `cviSpk_clu` + waveforms +
  positions + **quality** from it (stays aligned with the exported spike-times CSV). Fixes
  `_quality.csv` and the `_jrc.mat` desync (→ PASS) without renumbering. **Gotchas:** `S_clu_update_`
  **crashes** on a desynced start (it rebuilds `mrWavCor`); instead call `S_clu_refresh_(S_clu,0)`
  (keep empties) then `S_clu_wav_`, `S_clu_position_`, `S_clu_quality_` **with `viClu_update` omitted**
  (full-rebuild branch — passing `1:nClu` hits the incremental branch, which also crashes); empty
  (all-deleted) clusters get `viSite_clu=NaN` from `mode([])` → set a placeholder site (1) before
  `S_clu_wav_`.
- **`exclude_flagged_units.m`** — set CSV column-2 (viClu unit id) of flagged fusion units to **-2**
  (deleted marker; atomic + `.bak`). **`reexport_csv.m`** — re-export `[time,viClu,site]` from the
  current sort (`irc export-csv`, no waveform load).
- **`assess_viclu.m` / `assess_viclu_detail.m`** — read-only; group spikes **by `viClu`** (the CSV
  source) and flag two-neuron-fusion units (bimodal depth, time-interleaved); detail emits the unit
  ids (= CSV column 2).

**Excluding a unit takes TWO edits, not one.** Setting a unit's spike-times CSV label to `-2`
(`exclude_flagged_units.m`) does **not** remove it from `_quality.csv`, where `note` still says
`single` — so it stays in `good_clusters` with zero spikes, trips
`preprocess_all.py:2384`'s `array_equal(unique(spike_clusters), sort(clusters))` check, and puts a
zero-spike phantom unit (all-zero template → NaN centre-of-mass) into the SpikeInterface analyzer.
Always also set that row's `note` to something other than `single` (`'excluded'` is inert — only
`== 'single'` / `contains('single')` is ever read). Same applies to **curator-deleted** clusters,
which keep their old `note`: a `note=='single'` row with `nSpikes==0` is the same bug (37 such units
found and fixed across the Dylan=1 set, 2026-07-26). A unit that is merely **silent inside a trial's
`[t1_s, tend_s]` window** also trips the warning; that one is benign and inherent to per-trial
windowing — `extract_spike_times_from_sorting(..., remove_empty=True)` drops it.

**Load-bearing fact:** `export_csv_` writes **`viClu`** directly (irc.m:10341), *not* `cviSpk_clu` —
so a DESYNC-SEVERE `_jrc.mat` does **not** by itself invalidate the exported **spike-times** CSV
(correctness == `viClu` coherence). But `export_quality_` reads the **cache-derived** per-cluster
fields, so `_quality.csv` **is** wrong on a desynced file and needs `resync_clu`.

**Field remediation (2026-07-25):** all 22 corrupt sorts remediated, PASS-verified on disk, backups
kept — see `logs/REMEDIATION_desync_field_20260725.md`. Project_hierarchy Dylan=1 (afm17307/17313/
17372): 241209 recovered; 241030/241129/241206 + 10 LIKELY-CLEAN resynced; fusion units `-2`-excluded
in spike-times CSVs; then `preprocess_all` (shaf branch, `recompute_analyzers=True`) re-run. cuniform:
pilot recovered, other 4 assessed `viClu`-coherent.

### `min_count` is NOT enforced on label-based sorts (2026-08-06)

`min_count` is applied **only** inside `postCluster_` — `dpclus_remove_count_` (irc.m:11897/11902/
11907) and `S_clu_remove_count_` (irc.m:11893, its *sole* caller). `post_merge_` skips
`postCluster_` entirely when `fLabelClu` (irc.m:3964), so on `vcCluster =
kmeans|hdbscan|isosplit|isosplit6|classix` **min_count does nothing at all**.

Nothing downstream substitutes for it: `cluster_site_` gates on the **site's** spike total, never
on each label it returns (its "pruned later if tiny" comment refers to the `postCluster_` pruning
that never runs); `S_clu_from_labels_` applies no count filter; `S_clu_remove_empty_` removes only
**empty** clusters. `S_clu_refrac_` (irc.m:4020) runs after merging and only **shrinks** clusters,
with no count re-check — which makes the symptom look like a merge artifact when the origin is
per-site clustering. **Merging never creates small clusters; it only grows them.**

Measured on `260324_afm18349` (`min_count = 50`, isosplit, mode 17): **68 of 661 clusters below
threshold, smallest 8 spikes**, holding 1221 spikes (0.01% of assigned).

**`fDiscard_count` was a dead parameter** — present in `default.prm`, `rhs32_template.prm`,
`sample_sample_merge.prm` promising *"set to zero to absorb to the nearest cluster"*, and read by
**no `.m` file**. It is now live, but **only** via the new opt-in:

- **`fEnforce_min_count`** (default **0** = off ⇒ `post_merge_` byte-identical to before) enables
  `S_clu_merge_small_`, called just before `post_merge_wav_` (irc.m:4018) so every per-cluster
  field downstream is rebuilt against the final cluster set.
- With it on, **`fDiscard_count`** picks the action: `0` (**default since 2026-09-02**) = **absorb
  into the nearest surviving cluster** by centroid distance (median `mrPos_spk`, the same metric
  `post_merge_wav4_` uses — a sub-threshold cluster's mean waveform is noise-dominated), capped at
  `maxDist_site_um`; `1` = spikes to noise (`viClu = 0`, the legacy DPC semantics, **lossy**).
  The default was flipped 1→0 in the `get_set_` fallback and all three shipped `.prm` files:
  enabling a size floor asks for a minimum, not for spikes to be thrown away, so the lossy action
  must be opt-in. **An existing `.prm` still carries `fDiscard_count = 1`** — read the file, not
  the default, before turning the floor on for an old parameter set.
- Targets are drawn only from clusters **at or above** `min_count`, so there is no chaining and the
  result is order-independent. A small cluster with no surviving neighbour in range is **left
  alone** — never force-merged, never discarded.
- Strict `<`, unlike `S_clu_remove_count_`'s `<=`. `fEnforce_min_count` had to be a *separate* flag
  because `fDiscard_count` historically shipped as `1` everywhere: honouring it directly would have
  made every existing label-based sort start deleting clusters it currently keeps.
- Verified on the real recording (`260324_afm18349`), both standalone and through a full in-memory
  `post_merge_`: off ⇒ `viClu` byte-identical; absorb ⇒ 68 clusters folded in, min size 8→61, none
  left below threshold, cache/`viClu` in sync, all per-cluster fields sized to the new `nClu`.
  End-to-end the merge ran 661→500→498 first, then absorbed 68 → **430**.
- **`S_clu_merge_small_` conserves spikes exactly, but the pipeline around it does not — and that is
  correct.** `S_clu_refrac_` (irc.m:4025) runs *after* the absorb and drops spikes violating
  `spkRefrac_merge_ms` **within** a cluster. Folding a small cluster into a neighbour turns
  previously-legal spike pairs into genuine refractory violations, so a few more get removed
  (measured: 945 vs 939, i.e. 6 extra out of 16.88 M). Assert conservation on the **function**, not
  on end-to-end assigned-spike counts. Every merge has this property, including the ordinary
  template merges.

### Reading `cviSpk_clu` as a fast path — `get_cviSpk_clu_checked_` (2026-08-06)

Several post-merge template loops used `find(S_clu.viClu == iClu)` inside `for iClu`, i.e. an
O(nClu · nSpk) scan. On the reference recording (661 clusters × 17.6 M spikes) that was **~66% of
`clu_wave_similarity_paged`'s runtime**. `S_clu.cviSpk_clu` already holds exactly these lists.

**Do NOT read the cache directly for this.** It is derived state and can go stale; building
templates from a stale cache and then merging on them yields a *self-consistent but wrong*
clustering — the DI-01 class that no sync checker can detect after the fact. `viClu` is
authoritative; the cache is only an accelerator.

`get_cviSpk_clu_checked_(S_clu, vcCaller)` returns the cache **only if it provably equals
`find(viClu==i)` for every cluster**, else `{}` (caller falls back to `find`) plus a stderr warning.
It reconstructs a labelling from the cache alone and compares it to `viClu`, and also compares total
entry counts — catching wrong members, missing spikes, extra spikes and cross-cluster duplicates.
A *length* test would not: `S_clu_select_` force-fits wrong-length fields (see above).

Cost is **one O(nSpk) pass** versus the O(nClu · nSpk) scan it replaces — ~0.15% of the work saved.

Call sites: `clu_wave_similarity_paged.m:30`, `post_merge_knnwav.m:49`,
`waveform_similarity_clu_`, `templateMatch_post_burst_`, `graph_merge_` (all in `irc.m`). The two
standalone files reach it through the usual `irc('call', …)` shim; if the shim itself fails it
returns `[]`, which lands on the same safe fallback.

Verified on the real recording: healthy cache accepted; swapped, truncated and short caches all
rejected; and **a deliberately desynced cache produced byte-identical `mrDist_clu` to the healthy
run** (phase 1 fell back to 23.7 s from 12.2 s, proving the slow path engaged). Measured effect when
healthy: kernel 31.2 s → 21.6 s (−31%), `isequaln` with the pre-change output.

`S_clu_merge_small_` (which *writes* `viClu`) additionally snapshots and **rolls back** if its
post-condition fails — `merge_small_verify_`, following `delete_clu_`'s pattern. It checks the
invariant by content and, for the absorb mode, that no spike was lost.

### `irc reset-to-premerge` — re-merge from the raw baseline without a re-sort (2026-09-01)

`irc('reset-to-premerge', prm)` (alias `reset-premerge`) is `auto_` with **one** change: before
`post_merge_`, it resets `S_clu.viClu = S_clu.viClu_premerge`. Plain `irc auto` re-merges on top of
the current (already-merged/curated) `viClu` and **compounds**; reset-to-premerge re-applies the merge
from the raw pre-cluster baseline, so a changed `post_merge_mode`/`maxWavCor` takes effect from scratch
using only the cached detect/feature/kNN artifacts (minutes, no re-detect/re-cluster).

- Implemented as an optional 2nd arg `auto_(P, fReset_premerge)` (default 0 ⇒ existing `auto_(P)`
  byte-identical). Dispatch case at irc.m ~252 calls `auto_(P, 1)`. **It saves** (atomic `save0_`,
  keeps `.bak`) and **discards curation**, like `auto`/`recurate`.
- **Idempotent w.r.t. the baseline:** `post_merge_` re-stores `viClu_premerge` from the reset `viClu`
  (irc.m ~3973) *before* merging, so repeating it always restarts from the same raw labels.
- Guards: **errors** if `viClu_premerge` is absent/empty; and if `nClu(premerge) ≤ 1.05·nClu(current)`
  it **stops and asks** (`confirm_premerge_baseline_`, 2026-09-04 — it used to only print to stderr
  and proceed). A label-based sort over-segments, so a baseline that isn't much larger than the merged
  result was probably overwritten by a prior `auto`/`recurate` (see the "not write-once" correction
  above) — that is exactly when a full re-sort is warranted, and this command overwrites in place.
  Cancel returns **before anything is computed or written**. Buttons are **OK/Cancel, not Yes/No**,
  for the same reason as `confirm_recurate_`: `questdlg_` returns `'Yes'` whenever `fDebug_ui==1`,
  which matches neither button and so falls through to Cancel — a headless run aborts instead of
  silently overwriting a sort whose baseline is unreliable.
- **Overwrites in place on purpose — do NOT add a "new file" mode.** The whole toolchain derives the
  `_jrc.mat` path from the `.prm` name (`strrep(vcFile_prm,'.prm','_jrc.mat')`), so a side-written
  `_jrc.mat` is an orphan no `irc` command loads. Keep multiple results by copying the `.prm`.

**Is answering `No` to `irc manual`'s "Load last saved or recompute?" the same as
`reset-to-premerge`? Only on DPC sorts.** `manual_`'s `'no'` branch runs
`post_merge_(S0.S_clu, P)` on the **loaded** `viClu` then `clear_log_`; it never touches
`viClu_premerge`, and it does **not** write the `_jrc.mat` (only the GUI's exit prompt does).
What that means depends entirely on `fLabelClu`:

| | `No` at `irc manual` | `irc reset-to-premerge` |
|---|---|---|
| starting `viClu` | the loaded (curated) one | reset to `viClu_premerge` first |
| **DPC sorts** (`drift-knn`, `spacetime`, …) | `postCluster_` **`rmfield`s `viClu`** (irc.m:11933-11935) and rebuilds it from `rho`/`delta`/`icl`, so curation is discarded and the merge restarts from the auto clustering | same `rmfield` **discards the reset** — the `viClu_premerge` assignment is a no-op here |
| ⇒ clustering result | **identical** to reset-to-premerge | identical to `No` |
| **label sorts** (`isosplit`/`kmeans`/`hdbscan`/`classix`) | `postCluster_` is **skipped** ⇒ merges **on top of curated labels, compounding** | true reset to the raw baseline |
| ⇒ clustering result | **not a reset** | the reset |
| `<prm>_log.mat` | deleted (`clear_log_`) | deleted (`clear_log_`) |
| `csNote_clu` | reset by `post_merge_` | reset by `post_merge_` |
| writes `_jrc.mat` | no — only if you save on GUI exit | **yes, in place**, atomically, keeps `.bak` |
| opens a GUI | yes | no |

**So on a label-based sort, answering `No` is actively harmful**: it merges on top of curated
labels *and* `post_merge_`'s unconditional `S_clu.viClu_premerge = S_clu.viClu` (irc.m ~3975) then
overwrites the baseline with those curated labels — permanently disabling `reset-to-premerge` and
`recover_from_snapshot` for that file. On a DPC sort `No` is harmless (the baseline it stores is a
genuine regenerated auto clustering). `irc recurate` is the same `'no'` branch behind a consent
dialog; use it rather than clicking `No`.

**Tuning the merge on label-based sorts (`isosplit`/`kmeans`/`hdbscan`/`classix`).** `post_merge_mode0`
is read **only** inside `assign_clu_count_`, whose sole caller `postCluster_` these sorts **skip**
(irc.m:3965 gates on `~fLabelClu`; `fet2clu_` also calls `post_merge_(…,0)`), so `post_merge_mode0` is
**inert** — verified by tracing every `postCluster_` call site. The merge is governed by: the **scalar**
`post_merge_mode` (mode `1` = same-peak-site `templateMatch_post_` only; mode `8` runs the *shape-blind*
`post_merge_knn1` first, then same-site templateMatch; mode `17` = cross-site drift-aware
`clu_wave_similarity_paged` → templateMatch), the `maxWavCor` threshold, and the automatic cross-site
`post_merge_wav4_` pass (the `fLabelClu && 0<maxWavCor<1` branch at irc.m ~4008). Over-merging of
*different* shapes is typically `post_merge_knn1` (mode 8, shape-blind, `out_in_ratio_merge` default 1/8);
under-merging of *similar* shapes is the same-site restriction of mode 1/8 plus a strict `maxWavCor`.
`matlab/sweep_post_merge.m` re-runs `post_merge_` **in memory** (no save) over a list of
`[post_merge_mode, maxWavCor]` rows from the raw baseline and prints resulting cluster counts + sync — use
it to pick settings, then bake in with one `reset-to-premerge` (or `irc sort`).

### Which default parameters DISCARD data — audit (2026-09-02)

`default.prm` comments describe intent, not behaviour: two parameters have been found documented as
live while read by no code (`fDiscard_count`, dead for years; `thresh_mad_clu`, below). **Trace a
parameter to its reader before tuning it or quoting its comment.** Result of tracing every
data-discarding default:

| parameter | default | discards | on by default? |
|---|---|---|---|
| `blank_thresh` | `[8]` | **spikes, at detection** | **yes** — deliberate, keep |
| `fRemove_duplicate` | `1` | **whole clusters** | **yes** — deliberate, keep |
| `fDiscard_count` | `0` *(was 1)* | spikes → `viClu=0` | no (gated by `fEnforce_min_count=0`) |
| `spkRefrac_merge_ms` | `.5` | a few spikes per merge | yes — inherent to merging |
| `thresh_mad_clu` | `7.5` | **nothing — dead** | n/a |

- **`blank_thresh = [8]` blanks 5 ms windows and those spikes are never detected.** `car_reject_`
  (irc.m:1915) bins the common reference by `blank_period_ms` and rejects windows over 8 MAD;
  `detect_spikes_` (irc.m:13402) keeps only spikes inside surviving windows. Upstream of everything —
  no later stage can recover them. Prints `Rejecting X % of time due to motion`; **read that line.**
  Note irc.m's own fallbacks are `[]` = off (`struct_default_` irc.m:1688, `get_set_` irc.m:1917) and
  the MountainSort importer maps `mask_out_artifacts=false` → `[]` (irc.m:27022), so `default.prm`
  deliberately overrides the library default to ON. **Operator decision 2026-09-02: keep `8`** — it
  rarely triggers on non-artifact events. Do not "fix" it to `[]`.
- **`fRemove_duplicate = 1` deletes whole clusters** whose detection site is farther than
  `maxDist_site_um` from their min-waveform site (irc.m:4437-4444, inside `post_merge_wav_`, via
  `S_clu_keep_`). Prints `N duplicate units removed`. **Operator decision 2026-09-02: keep.**
- **`fDiscard_count` default flipped `1` → `0` (absorb) on 2026-09-02**, in the `get_set_` fallback
  and all three shipped `.prm` files — see the `min_count` section above. **An existing `.prm` on disk
  still carries `1`**: the file beats the default, so read the file before setting
  `fEnforce_min_count = 1` on an old parameter set.
- **`thresh_mad_clu` is DEAD.** Its only reader is `S_clu_cleanup_` (irc.m:19609), which has **no
  caller** in `irc.m` — the Mahalanobis outlier removal its comment promises never runs. Tuning it
  does nothing.

### Memory Management
- Spike waveforms optionally saved (`fSave_spkwav` parameter)
- Page-based loading for large files
- GPU memory pooling

## Integration with Other Tools

### Kilosort Integration
```matlab
kilosort('config', P)      % Configure Kilosort with IronClust parameters
kilosort('rezToPhy', ...)  % Export to Phy format
```

### MountainSort Integration
- Import/export MDA format files
- `convert_mda.m` for format conversion

### Export Formats
- Klusters format: `irc2klusters.m`
- Phy format: `irc2phy.m`
- MDA format: Various `convert_mda_*` functions

## Important Development Rules

### Code Preservation
- **NEVER delete existing functions** - All existing functions must be preserved for backward compatibility
- When improving functionality, add new functions or extend existing ones rather than removing code
- Comment out deprecated code rather than deleting it if absolutely necessary

### Critical: Preserve Existing Functionality
- **CRITICAL: Always ensure any changes to the code don't break existing functionality**
- Unless the user explicitly specifies to modify or remove existing behavior, all changes must be additive or fixes only
- Test that existing workflows continue to work after any modifications
- When fixing bugs, ensure the fix doesn't introduce regressions in other parts of the code

## Development Notes

### Error Handling
- Error logs saved to `error_log.mat`
- Global variable `all_vnthresh` tracks threshold iterations
- Lock files prevent concurrent access

### GUI Components
- Manual curation GUI: **`manual_` → `figures_manual_` in `irc.m`**, not `irc_gui.m` (that is an
  unrelated GUIDE/`.fig` launcher). `show_drift_view.m` is the one curation window living in its
  own file; it reaches `irc.m`'s local functions through `irc('call', …)` shims.
- Per-figure state lives in that figure's own `UserData` (`S_fig`); the window **tags** are listed
  in `S0.csFig`, and `S0.cvrFigPos0` holds their startup positions **by index into `csFig`**
  (`figures_manual_` builds it with `cellfun` over `csFig`, so appending a tag is index-safe).
- **`get_fig_` and `get_fig_cache_` CREATE the figure when `findobj` misses.** This is the single
  most common GUI bug in this file: a lookup meant to test "is this window open?" silently pops a
  blank, axis-less window instead. It caused the unbidden "Projection rendering OFF" window, and
  it is why `reset_position_`/`save_figures_` can resurrect any closed `csFig` tag. For an
  optional window, resolve with `findobj('Tag', …, 'Type','figure')` and make the toggle **hide**
  rather than close.
- Keyboard shortcuts are in each figure's `S_fig.csHelp` (`[H]`); several entries there and in the
  window titles are stale (`[J] projection view` is the drift view; `[A]`, `[C]`, `[E]`, and
  Shift+Left/Right "features" on FigTime are advertised but not implemented).

#### The two time views — `FigTime` and `FigTime2` (2026-09-04)

The bottom strip holds **two independent copies of the same window**: `FigTime` (`[.15 0 .35 .25]`,
Vpp) and `FigTime2` (`[.5 0 .35 .25]`, PCA). They share every code path —
`plot_FigTime_`/`update_FigTime_`/`rescale_FigTime_`/`keyPressFcn_FigTime_` all take a trailing
`vcTag` (default `'FigTime'`) — so `[S]` split, `[M]` merge, `[B]`, `[R]`, `[T]` and the site/scale
keys behave identically in both. `keyPressFcn_FigTime_` derives the tag from `get(hObject,'Tag')`.

- **The feature is per-window, and `getFet_site_`/`getFet_clu_` were NOT changed.** They read `P`
  out of the `S0` they are handed, so each window overrides `S0.P.vcFet_show` on a *local* copy
  (`fet_show_`). Never write that back: the `Projection` menu, `plot_FigProj_` and `plot_split_`
  all read the global `P.vcFet_show`. In `update_FigTime_` the override **must come after** the
  vestigial `set0_(P)` — that line writes the whole `P` to global state on every arrow keypress.
- FigTime keeps the original `Projection` menu (global `P.vcFet_show`); FigTime2 has its own
  `Projection (2nd time view)` menu → `proj_view2_`, which stores the choice in FigTime2's `S_fig`
  and redraws only that window. Default `vcFet_show2` = `'pca'`. `plot_FigTime_`'s `struct_merge_`
  does not overwrite `vcFet_show`, so the choice survives a replot.
- `ui_show_FigTime2_` (called from `ui_show_elective_`, i.e. on **every** cluster selection) is the
  only entry point; it returns early while hidden, so `View > Show 2nd time view` is a real cost
  switch. Autoscale reads the quantile straight off `hPlot1`/`hPlot2` `YData` rather than
  recomputing features the way `auto_scale_proj_time_` does for FigTime — selected clusters are
  **not** subsampled (the `MAX_SAMPLE=10000` cap in `getFet_clu_` applies to *background* spikes
  only), so a second feature pass is not cheap.
- **`abs()` in `getFet_clu_` plus the hardcoded non-negative y-limits fold PC1's negative lobe onto
  the positive one.** Correct for Vpp, lossy for PCA. Left as-is deliberately (the 2nd view is
  meant to be *exactly* the existing window). Note also that `pca` derives a **separate** eigenbasis
  for each plotted population (background / black / red) while `ppca` reuses cluster 1's basis for
  all three — so **`ppca` is the comparable one** for split/merge decisions.
- **`impoly_` must be passed the axes.** `impoly_()` with no argument parents to `gca`. With one
  time window that could not diverge; with two, a polygon drawn in one and evaluated against the
  other's `hPlot1` yields a plausible mask, the `numel()` guard compares **counts only**, and
  `split_clu_by_id_` commits the wrong split silently inside a `try/catch` — the wrong-but-consistent
  class no sync checker detects. Both `[S]` handlers now pass `S_fig.hAx` (`show_drift_view.m` did
  this already).

#### `FigProj` is opt-in and off by default

`ui_show_FigProj_` used `get_fig_`, so its "not open ⇒ no-op" guard could never fire and the
"Projection rendering OFF - press [Q] to render" window appeared on the first cluster selection,
while its menu item could only ever *close* it. `auto_scale_proj_time_` created it a second way.
Both now use `findobj`, so the View item toggles both ways and the window is genuinely opt-in;
`close_figure_uncheck_menu_` (written long ago, never wired) is now its `CloseRequestFcn`.
`plot_FigProj_`, `[Q]` and its projection-space `[S]` lasso are unchanged and still reachable.

### CUDA Requirements
- Compute capability 3.5+ (Kepler or newer)
- CUDA toolkit version depends on MATLAB version
- Visual Studio required for compilation on Windows

## Important Parameters

### Critical for Performance
- `nTime_drift`: Time bins for drift correction
- `maxSite`: Number of sites per cluster
- `nC_max`: Maximum clusters per site
- `fGpu`: Enable/disable GPU acceleration

### Critical for Accuracy
- `qqFactor`: Detection threshold multiplier
- `spkLim_ms`: Spike waveform time window
- `freqLim`: Bandpass filter frequency limits
- `post_merge_mode` (**scalar**) + `maxWavCor`: the automated merge. On label-based sorts
  (`kmeans`/`hdbscan`/`isosplit`/`classix`) these are the ONLY merge knobs —
  **`post_merge_mode0` is inert there**, read only inside `assign_clu_count_` ← `postCluster_`,
  which those sorts skip. See the `reset-to-premerge` section above.
- `blank_thresh`: artifact blanking — ON by default and it drops spikes at detection. See the
  data-discarding audit above.