# Changes Log - December 2, 2025

## Summary
Implemented CLASSIX clustering method (Mode 21) for post-merge clustering, added cluster reordering by spatial coordinates, and fixed critical bugs in auto-merge functionality.

## New Features

### 1. CLASSIX Clustering Method (Mode 21)
**Files Modified:**
- Created: `G:\spi_sorters\ironclust_but_faster\matlab\post_merge_classix.m`
- Modified: `G:\spi_sorters\ironclust_but_faster\matlab\irc.m` (lines 10286-10289)

**Description:**
Added CLASSIX (Fast and Explainable Clustering Based on Sorting) as a new post-merge clustering option. CLASSIX uses a sorting-based approach for fast and interpretable clustering.

**Usage:**
```matlab
P.post_merge_mode0 = 21;  % Enable CLASSIX clustering
```

**Optional Parameters:**
- `P.classix_radius = 0.5` - Grouping radius in normalized space (default: 0.5)
  - Smaller values → more clusters (tighter grouping)
  - Larger values → fewer clusters (looser grouping)
  - Typical range: 0.1 to 1.0
- `P.classix_minPts = P.min_count` - Minimum points per cluster (default: uses P.min_count)
- `P.classix_merge_tiny = 1` - Merge groups with < minPts points (default: 1)

**Implementation Details:**
- Extracts spike features from global `trFet_spk` tensor
- Reshapes features to (nSpk x nFeatures) matrix for CLASSIX
- Only clusters non-noise spikes (viClu > 0)
- Updates cluster centers based on highest delta values
- Calls `S_clu_refresh_()` to update cluster statistics
- Auto-scales data internally (centering + normalization by median norm)

**Algorithm Source:**
Based on CLASSIX implementation at `G:\spi_sorters\ironclust_but_faster\matlab\classix\classix.m`

---

### 2. Reorder Clusters by Spatial Coordinates
**Files Modified:**
- `G:\spi_sorters\ironclust_but_faster\matlab\irc.m` (lines 9397-9423, 6375, 5884)

**Description:**
Added functionality to reorder clusters based on their spatial coordinates (X first, then Y). This helps organize clusters by their physical location on the electrode array.

**Usage:**
- **Keyboard shortcut:** Press `o` in the GUI
- **Menu:** Edit → Re[o]rder by coordinates

**Implementation Details:**
- Function `reorder_clu_by_coords_()` at line 9397
- Ensures cluster positions are calculated via `S_clu_position_()`
- Sorts clusters using `sortrows()` on [vrPosX_clu, vrPosY_clu]
- Reorders clusters using `S_clu_select_()`
- Updates waveform correlation matrix
- Saves changes to disk
- Displays confirmation message with cluster count

**Keyboard Binding:** Added at line 6375 in `keyPressFcn_FigWav_()`

**Menu Item:** Added at line 5884 in Edit menu

---

## Bug Fixes

### 3. Fixed Missing save0_() Call in Auto-Merge
**Files Modified:**
- `G:\spi_sorters\ironclust_but_faster\matlab\irc.m` (line 18419)

**Issue:**
The `merge_auto_()` function was updating the GUI but not saving changes to disk, causing merged clusters to revert after closing and reopening the session.

**Fix:**
Added `save0_()` call after `gui_update_()` in the merge operation at line 18419.

**Impact:**
Auto-merge operations now persist correctly across sessions.

---

## Technical Notes

### CLASSIX Integration
- Works as a post-merge method (refines clusters after initial DPC clustering)
- Compatible with existing modes 0-20
- Can be combined in vector form: `P.post_merge_mode0 = [12, 15, 17, 21]`
- Default `post_merge_mode0` remains `[12, 15, 17]` (backward compatible)
- MEX compilation disabled by default for compatibility (set `opts.use_mex = 0`)

### Cluster Position Calculation
- Uses `S_clu_position_()` which computes cluster centroids from spike positions
- If `mrPos_spk` is available, uses spike position data directly
- Otherwise, computes weighted centroid from spike features and electrode positions
- Position fields: `S_clu.vrPosX_clu`, `S_clu.vrPosY_clu`

### Testing Recommendations
1. Test CLASSIX on small dataset with `post_merge_mode0 = 21`
2. Compare cluster quality with existing modes (11, 12, 15, 17)
3. Verify reorder function with multi-shank probes
4. Confirm auto-merge now saves correctly

---

## Files Changed

### New Files:
1. `G:\spi_sorters\ironclust_but_faster\matlab\post_merge_classix.m` (73 lines)

### Modified Files:
1. `G:\spi_sorters\ironclust_but_faster\matlab\irc.m`
   - Lines 10286-10289: Added case 21 for CLASSIX
   - Lines 9397-9423: Added `reorder_clu_by_coords_()` function
   - Line 6375: Added 'o' keyboard binding
   - Line 5884: Added menu item
   - Line 18419: Added `save0_()` call

---

## Backward Compatibility
- All changes are backward compatible
- No existing functionality modified
- Default parameters unchanged
- Mode 21 is purely additive
- Existing parameter files work without modification

---

## References
- CLASSIX Algorithm: X. Chen & S. Güttel. "Fast and explainable clustering based on sorting." arXiv:2202.01456, 2022.
- Implementation plan: `C:\Users\weisss\.claude-worktrees\matlab\happy-wright\PLAN_classix_mode21.md`
