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
- Main manual curation GUI: `irc_gui.m`
- Figure handles stored in `S0` structure
- Keyboard shortcuts documented in help menu

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
- `post_merge_mode0`: Automated merging modes