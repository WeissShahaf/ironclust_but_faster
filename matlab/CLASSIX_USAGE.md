# CLASSIX Usage Guide

## Overview
CLASSIX is implemented as TWO INDEPENDENT methods that can be used separately or together:

1. **SORTING (Primary Clustering)**: `vcCluster = 'classix'` - Initial spike clustering
2. **MERGING (Post-Merge Refinement)**: `post_merge_mode0 = 21` - Refines existing clusters

These are **completely independent** - you can use one, the other, or both.

## Quick Reference

### Parameter File Location
All CLASSIX parameters are defined in `default.prm` (lines 171-181).

### Parameter Summary Table
| Parameter | Default | Location | Description |
|-----------|---------|----------|-------------|
| `vcCluster` | `'drift-knn'` | `default.prm:146` | Set to `'classix'` for SORTING mode |
| `post_merge_mode0` | `[12,15,17]` | `default.prm:161` | Set to `21` for MERGING mode |
| `classix_radius` | `0.5` | `default.prm:177` | Grouping radius (0.1-1.0) |
| `classix_minPts` | `[]` | `default.prm:178` | Min spikes/cluster ([] = use min_count) |
| `classix_merge_tiny` | `1` | `default.prm:179` | Merge tiny groups |
| `classix_use_mex` | `1` | `default.prm:180` | MEX acceleration |
| `classix_verbose` | `0` | `default.prm:181` | Detailed output |

---

## Valid Configuration Patterns

### 1. CLASSIX for SORTING Only (RECOMMENDED for speed)
```matlab
% Use CLASSIX as primary clustering, bypass DPC
vcCluster = 'classix';
classix_radius = 0.5;

% Use default post-merge methods (or none)
% post_merge_mode0 = [12, 15, 17];  % traditional merge methods
% post_merge_mode0 = [];             % no post-merge
```

**When to use:**
- You want maximum speed (skips expensive DPC computation)
- Your data is clean and CLASSIX produces good initial clusters
- Large datasets where DPC is too slow

**Performance:** Dramatically faster than DPC (2M spikes in ~0.5 seconds)

---

### 2. CLASSIX for MERGING Only (RECOMMENDED for refinement)
```matlab
% Use traditional DPC for initial clustering
vcCluster = 'drift-knn';  % or 'spacetime' or 'drift'

% Use CLASSIX to refine/re-cluster after DPC
post_merge_mode0 = 21;
classix_radius = 0.5;
```

**When to use:**
- You want DPC's robust initial clustering
- Then use CLASSIX to refine and merge over-split clusters
- Conservative approach: DPC then CLASSIX refinement

**Performance:** Full DPC + fast CLASSIX refinement

---

### 3. DPC + Traditional Merge (Default)
```matlab
% Traditional pipeline (default)
vcCluster = 'drift-knn';
post_merge_mode0 = [12, 15, 17];  % waveform-based merging
```

**When to use:**
- Standard IronClust pipeline
- No CLASSIX used

---

### 4. CLASSIX + Traditional Merge (Hybrid)
```matlab
% Use CLASSIX for initial clustering
vcCluster = 'classix';
classix_radius = 0.5;

% Then apply traditional waveform-based merging
post_merge_mode0 = [12, 15, 17];
```

**When to use:**
- CLASSIX for fast initial clustering
- Traditional methods for waveform-based refinement
- Good compromise between speed and quality

---

### 5. CLASSIX for BOTH (Not Recommended)
```matlab
% Use CLASSIX for primary clustering
vcCluster = 'classix';

% Then use CLASSIX again for post-merge
post_merge_mode0 = 21;
classix_radius = 0.5;
```

**WARNING:** This clusters twice with CLASSIX, which is usually redundant.

**When to use:**
- Rarely useful
- You might want different radius values for each stage
- System will warn you about this configuration

---

## Parameters (Apply to Both Modes)

All CLASSIX parameters work for BOTH sorting and merging:

```matlab
classix_radius = 0.5;        % Grouping radius (0.1-1.0)
                             % Smaller = more clusters
                             % Larger = fewer clusters

classix_minPts = 30;         % Minimum spikes per cluster
                             % Default: uses P.min_count

classix_merge_tiny = 1;      % Merge groups with < minPts
                             % 0 = keep tiny clusters separate
                             % 1 = merge into nearest large cluster

classix_use_mex = 1;         % MEX acceleration (2-4x speedup)
                             % 0 = disable MEX (compatibility mode)
                             % 1 = enable (default, uses multi-threaded BLAS)

classix_verbose = 0;         % Detailed output
                             % 0 = quiet
                             % 1 = show timing, stats, distance computations
```

---

## Independence Verification

### SORTING (`cluster_classix_.m`):
- **Input**: Raw spike features from `trFet_spk`
- **Process**: Clusters ALL spikes from scratch
- **Output**: Complete S_clu structure
- **Dependencies**: None (bypasses DPC entirely)
- **Uses**: `classix(mrFet, ...)` on all spikes

### MERGING (`post_merge_classix.m`):
- **Input**: Existing S_clu with clustered spikes
- **Process**: Re-clusters non-noise spikes only
- **Output**: Updated S_clu structure
- **Dependencies**: Requires prior clustering (from ANY method)
- **Uses**: `classix(mrFet_valid, ...)` on viClu > 0

**Key Point:** They operate on the same data (`trFet_spk`) but at different stages:
- SORTING: Before any clustering exists
- MERGING: After initial clustering exists

---

## Quick Start Examples

### Fastest Configuration (CLASSIX only):
```matlab
vcCluster = 'classix';
classix_radius = 0.5;
post_merge_mode0 = [];  % no post-merge
```

### Most Conservative (DPC + CLASSIX refinement):
```matlab
vcCluster = 'drift-knn';
post_merge_mode0 = 21;
classix_radius = 0.5;
```

### Balanced (CLASSIX + traditional merge):
```matlab
vcCluster = 'classix';
post_merge_mode0 = [12, 15, 17];
classix_radius = 0.5;
```

---

## Troubleshooting

### If you see warning about redundant configuration:
```
WARNING: Using CLASSIX for both primary clustering AND post-merge.
```

**Fix:** Choose one of:
- Use CLASSIX only for sorting: `vcCluster = 'classix'`, remove mode 21
- Use CLASSIX only for merging: `vcCluster = 'drift-knn'`, keep mode 21

### If MEX compilation fails:
```matlab
classix_use_mex = 0;  % Disable MEX, use pure MATLAB
```

### If too many small clusters:
```matlab
classix_radius = 0.8;      % Increase radius (fewer clusters)
classix_minPts = 50;       % Increase minimum size
```

### If too few clusters:
```matlab
classix_radius = 0.3;      % Decrease radius (more clusters)
classix_minPts = 10;       % Decrease minimum size
```

---

## Performance Comparison

| Configuration | DPC Time | CLASSIX Time | Total Time |
|---------------|----------|--------------|------------|
| DPC only | 100% | 0% | 100% |
| CLASSIX only | 0% | ~0.5s | **~1-5%** ⚡ |
| DPC + CLASSIX merge | 100% | ~0.5s | ~101% |
| CLASSIX + traditional | 0% | ~0.5s + merge | ~10-20% ⚡ |

**Note:** DPC time varies with dataset size, CLASSIX is consistently fast (~0.5s for 2M spikes)

---

## References
- CLASSIX paper: Chen & Güttel (2022). arXiv:2202.01456
- Implementation: `matlab/classix/classix.m`
- IronClust documentation: See main README.md
