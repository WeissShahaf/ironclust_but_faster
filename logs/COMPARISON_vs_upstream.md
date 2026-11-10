# `rewind` vs official IronClust (`flatironinstitute/ironclust`, `upstream/master`)

**Generated:** 2026-07-22 · comparison of local branch `rewind` against `upstream/master`.

## Relationship
- `rewind` is **0 behind / 93 ahead** — it contains all of official `master` plus 93 fork commits.
- Diverged **2022-06-07** at merge-base `2d7b56c`; official `master` HEAD **is** that commit, i.e.
  flatiron's `master` has not changed since then (frozen). `upstream/dev` is older still (2019).
  **Nothing upstream is missing.**
- Overall: **406 files changed, +117,956 / −328** — overwhelmingly additive (321 files added, only
  **10 files** contain any deletions).

---

## (a) `matlab/irc.m` — function-level diff vs upstream

| metric | value |
|---|---|
| functions in upstream `irc.m` | 986 |
| functions in `rewind` `irc.m` | 1030 |
| **added** | **44** |
| **removed** | **0** |
| line diff | **+2,948 / −262** |

**No function was removed** (upholds the repo's "never delete functions" rule). The **262 deletions
are in-place line edits inside existing functions**, not function removals — i.e. the algorithmic
divergence is 44 new functions plus edits threaded through existing ones.

### The 44 added functions, by theme

**1. Curation & cluster-identity integrity** — the queued `[M]`/`[U]`/`[D]` merge/delete system, the
cross-shank guard, the desync detector, and the atomic-save/error helpers (the CID-01…15 + DI-01…22
work):
`init_pending_cache_`, `has_pending_operations_`, `add_pending_merge_`, `add_pending_delete_`,
`find_merge_group_`, `adjust_pending_indices_`, `ui_merge_pending_`, `ui_delete_pending_`,
`update_pending_markers_`, `clear_pending_markers_`, `cancel_pending_operations_`,
`execute_pending_and_update_`, `block_cross_shank_`, `shank_clu_`, `reorder_clu_by_coords_`,
`S_clu_assert_synced_`, `struct_select_safe_`, `get_clu_spk_confirmed_`, `atomic_replace_`,
`tempname_sibling_`, `disperr_strict_`

**2. Clustering methods & per-site engine** — CLASSIX / HDBSCAN / isosplit / k-means back-ends, the
per-site capped-cluster path, and its helpers (the "faster" work incl. GPU `nearest_in_set_`):
`cluster_site_`, `cluster_site_capped_`, `cluster_labels_persite_`, `persite_knn_`,
`nearest_in_set_`, `progress_persite_`, `cluster_isosplit_`, `isosplit_labels_`, `cluster_hdbscan_`,
`cluster_kmeans_`, `kmeans_labels_`, `S_clu_from_labels_`, `split_clu_by_id_`, `site_label_modes_`,
`auto_annotate_single_units_`, `max_workers_`

**3. GUI — FigMap / region view / projection**:
`apply_FigMap_color_`, `region_colormap_`, `cycle_FigMap_label_`, `FigMap_title_`,
`keyPressFcn_FigMap_`, `load_site_region_`, `ui_show_FigProj_`

### Existing functions edited (where the −262 live)
git's hunk-context surfaced these as directly touched: `cellstr2file_`, `clu_wav_`, `export_prm_`,
`load_spkfet_`, `post_merge_`, `rescaleProj_`, `split_clu_`, `ui_show_elective_`. The data-integrity
pass also edited (per the DI tracker) `struct_save_`, `save0_`, `fread_`, `fwrite_`, `write_spk_`,
`file2spk_`, `load_bin_`, `mn2tn_wav_`, `spikeMerge_`, `field2str_`, `wav_car_`, `mr2tr_`,
`sgfilt4_`/`sgfilt_init_`, `get_spkwav_`, the `cuda_*` kernels, `S_clu_select_`, `delete_clu_`,
`merge_clu_`/`merge_clu_pair_`, `S_clu_commit_`, `load0_` — all as additive guards / minimal edits
(healthy-path byte-identical).

---

## (b) The 10 files containing deletions vs upstream

| deletions | file | nature |
|---|---|---|
| **262** | `matlab/irc.m` | in-place edits inside existing functions (0 functions removed) |
| 18 | `matlab/irc2.m` | same fixes as irc.m (duplicated engine) |
| 17 | `matlab/default.prm` | parameter defaults tweaked / re-commented |
| 9 | `matlab/default.cfg` | config defaults |
| 8 | `matlab/default1.cfg` | config defaults |
| 6 | `matlab/kilosort.m` | Kilosort integration tweaks |
| 3 | `matlab/show_drift_view.m` | drift-view `[S]` fix (CID-02) |
| 2 | `README.md` | docs |
| 2 | `matlab/ksort2.txt` | Kilosort2 text |
| 1 | `matlab/clu_wave_similarity_paged.m` | 1-line edit |

Everything else in the +118k is **added** files — vendored deps (`matlab/classix/…`,
`npy-matlab/…`), SVG assets, full backup copies of `irc.m` (`matlab/irc.txt`, `matlab/irc_bkp.m`,
~31k lines each), the `logs/` documentation & scan artifacts, and the data CSV.

### Bottom line
`rewind` = official IronClust (frozen at 2022) **+ 93 additive commits**. Real algorithmic
divergence is concentrated in **`irc.m` (+2,948 / −262, +44 functions, 0 removed)** and `irc2.m`;
deletions are tiny (328 total, mostly config), and **no upstream function was removed**. See the
workflow diagram (`logs/WORKFLOW_diff_vs_upstream.*`) for the stage-by-stage differences in
**detection · sorting · merging · curation**.
