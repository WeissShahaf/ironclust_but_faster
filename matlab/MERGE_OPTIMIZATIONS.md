# Cluster Merging Runtime Optimizations

This document describes the performance optimizations implemented for the IronClust cluster merging process in `irc.m`.

## Overview

The original merging process had several performance bottlenecks that have been addressed through targeted optimizations:

1. **Critical bottleneck in `merge_clu_pair_`** - Expensive `find()` operations on large arrays
2. **Redundant UI operations** - All figures updated immediately after each merge
3. **Memory allocation inefficiencies** - Creating new arrays instead of pre-allocating
4. **Full correlation matrix recalculation** - Entire matrix recalculated after each merge

## Implemented Optimizations

### 1. Critical Performance Bottleneck Fix

**File**: `irc.m` (function `merge_clu_pair_`)

**Problem**: The original code used `find(S_clu.viClu == iClu2)` which searches through the entire spike array (potentially millions of spikes).

**Solution**: Use pre-computed spike indices from `cviSpk_clu`:
```matlab
% Before (slow):
S_clu.viClu(S_clu.viClu == iClu2) = iClu1;
S_clu.cviSpk_clu{iClu1} = find(S_clu.viClu == iClu1);

% After (fast):
if ~isempty(S_clu.cviSpk_clu{iClu2})
    S_clu.viClu(S_clu.cviSpk_clu{iClu2}) = iClu1;
    % Efficient merging of spike indices
end
```

**Expected improvement**: 2-5x faster for large datasets

### 2. Deferred UI Updates

**File**: `irc.m` (function `ui_merge_`)

**Problem**: All figures were updated immediately after each merge operation, causing significant delays.

**Solution**: Added configurable deferred updates:
```matlab
% User can enable/disable immediate updates
fUpdateImmediate = get_set_(P, 'fUpdateImmediate', 1);
if fUpdateImmediate
    % Update figures immediately
    plot_FigWav_(S0);
    S0 = update_FigCor_(S0);
else
    % Mark for later update
    S0.figures_need_update = true;
end
```

**New features**:
- `[B]` key to batch update all figures
- Menu option to toggle deferred updates
- Performance monitoring with timing information

**Expected improvement**: 5-10x faster for multiple merges

### 3. Memory Allocation Optimization

**File**: `irc.m` (function `merge_clu_pair_`)

**Problem**: Arrays were concatenated inefficiently, creating temporary copies.

**Solution**: Pre-allocate memory for merged arrays:
```matlab
% Before (inefficient):
S_clu.cviSpk_clu{iClu1} = [S_clu.cviSpk_clu{iClu1}; S_clu.cviSpk_clu{iClu2}];

% After (efficient):
n1 = numel(S_clu.cviSpk_clu{iClu1});
n2 = numel(S_clu.cviSpk_clu{iClu2});
viSpk_combined = zeros(n1 + n2, 1);
viSpk_combined(1:n1) = S_clu.cviSpk_clu{iClu1};
viSpk_combined(n1+1:n1+n2) = S_clu.cviSpk_clu{iClu2};
S_clu.cviSpk_clu{iClu1} = viSpk_combined;
```

**Expected improvement**: 20-30% reduction in memory usage

### 4. Incremental Correlation Matrix Updates

**File**: `irc.m` (functions `update_correlation_after_merge_`, `compute_cluster_correlations_`)

**Problem**: Entire correlation matrix was recalculated after each merge.

**Solution**: Incremental updates that only modify affected elements:
```matlab
% Remove deleted cluster row/column
S_clu.mrWavCor(iClu2, :) = [];
S_clu.mrWavCor(:, iClu2) = [];

% Update only merged cluster correlations
S_clu.mrWavCor(iClu1, :) = compute_cluster_correlations_(S_clu, iClu1, P);
S_clu.mrWavCor(:, iClu1) = S_clu.mrWavCor(iClu1, :)';
```

**Expected improvement**: 3-5x faster correlation updates

### 5. Batch Merge Operations

**File**: `irc.m` (function `ui_merge_batch_`)

**Problem**: Only one merge at a time was possible.

**Solution**: Batch merge multiple cluster pairs with single UI update:
```matlab
% Perform all merges
for i = 1:size(merge_pairs, 1)
    S0.S_clu = merge_clu_(S0.S_clu, merge_pairs(i,1), merge_pairs(i,2), S0.P);
end

% Update UI once after all merges
S0 = update_all_figures_(S0);
```

**New features**:
- Menu option: "Edit > Batch merge..."
- Input dialog for multiple merge pairs
- Automatic conflict resolution

**Expected improvement**: 5-10x faster for multiple merges

## New User Interface Features

### Keyboard Shortcuts
- `[M]` - Merge selected clusters (existing)
- `[B]` - Batch update all figures (new)
- `[H]` - Help (existing)

### Menu Options
- **Edit > Batch merge...** - Open batch merge dialog
- **View > Performance: Deferred updates** - Toggle optimization mode

### Configuration Parameters
- `fUpdateImmediate` - Enable/disable immediate figure updates
- `fUpdateCorrelation` - Enable/disable correlation matrix updates

## Usage Instructions

### Enabling Deferred Updates
1. Go to **View > Performance: Deferred updates**
2. Figures will no longer update automatically after merges
3. Use `[B]` key or menu to update figures when ready

### Batch Merging
1. Go to **Edit > Batch merge...**
2. Enter merge pairs in format: `[1 2; 3 4; 5 6]`
3. Confirm the operation
4. All merges will be performed with single UI update

### Performance Monitoring
- Merge timing is automatically logged
- Warnings appear for slow operations (>0.1s)
- Performance metrics are saved in merge logs

## Expected Performance Improvements

| Operation | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Single merge | Baseline | 2-5x faster | Critical bottleneck fixed |
| Multiple merges | Baseline | 5-10x faster | Deferred updates + batch operations |
| Memory usage | Baseline | 20-30% less | Efficient allocation |
| Correlation updates | Baseline | 3-5x faster | Incremental updates |

## Backward Compatibility

All optimizations maintain full backward compatibility:
- Default behavior unchanged (`fUpdateImmediate = 1`)
- Original merge functionality preserved
- Fallback methods for edge cases
- No breaking changes to existing workflows

## Future Optimization Opportunities

1. **GPU acceleration** for correlation calculations
2. **Parallel processing** for batch operations
3. **Memory pooling** for spike arrays
4. **Lazy loading** of waveform data
5. **Caching** of frequently accessed cluster properties

## Testing Recommendations

1. Test with large datasets (>1M spikes)
2. Verify correlation matrix accuracy after merges
3. Check memory usage during batch operations
4. Validate undo/redo functionality
5. Test edge cases (empty clusters, single spikes)

## Troubleshooting

### Performance Issues
- Enable deferred updates for multiple merges
- Use batch merge for >5 cluster pairs
- Check if correlation updates are needed

### Memory Issues
- Monitor memory usage during large batch operations
- Consider breaking very large batches into smaller chunks

### Accuracy Issues
- Verify correlation matrix updates are working
- Check if `fUpdateCorrelation` is enabled
- Use `[B]` key to force full updates if needed
