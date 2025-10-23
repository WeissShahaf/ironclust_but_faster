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

### Cluster Merging (from MERGE_OPTIMIZATIONS.md)
- Deferred UI updates: Toggle with `fUpdateImmediate` parameter
- Batch merging: Use `[B]` key or Edit > Batch merge menu
- Pre-computed spike indices in `cviSpk_clu` for fast cluster operations
- Incremental correlation matrix updates

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