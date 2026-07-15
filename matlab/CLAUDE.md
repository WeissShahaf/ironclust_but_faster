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