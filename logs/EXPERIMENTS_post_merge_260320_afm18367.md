# Post-merge parameter experiments — 260320_afm18367

**Recording:** `260320_afm18367_g0_tcat.imec0.ap` (Neuropixels, 385 ch, 5029 s)
**Sort:** `vcCluster = 'isosplit'` (isosplit5), label-based (bypasses DPC / `postCluster_`)
**Test copy:** `E:\scratch\tmp\260320_afm18367_g0_imec0\remerge\` (parent dir left untouched; `.bin` read-only)
**Goal:** fix **over-merge of different waveform shapes** + **under-merge of similar shapes**.

## Key facts (why these knobs)

- `post_merge_mode0` is **inert** on label-based sorts (read only inside the skipped `postCluster_`). Ignore it.
- The merge is governed by: scalar **`post_merge_mode`**, **`maxWavCor`**, and the auto cross-site `post_merge_wav4_` pass.
  - mode `1` = same-peak-site `templateMatch_post_` only → misses cross-site duplicates (under-merge).
  - mode `8` (current) = shape-**blind** `post_merge_knn1` (kNN-overlap, `out_in_ratio_merge`=1/8) → then same-site templateMatch → over-merges different shapes + still misses cross-site similars.
  - mode `17` = cross-site, drift-aware `clu_wave_similarity_paged` → templateMatch → shape-based, cross-site.
- Over-merge of *different* shapes ≈ `post_merge_knn1` (mode 8). Under-merge of *similar* shapes ≈ same-site restriction + strict `maxWavCor` (0.985).

## Baseline status ⚠

| date | file | viClu_premerge nClu | current viClu nClu | verdict |
|---|---|---|---|---|
| 2026-09-01 | (test copy, pre-resort) | 2463 | 2463 | **premerge == current** — NOT the raw isosplit baseline (overwritten by a prior auto/recurate, or the original sort barely merged). Sweep from here can only merge *further*, cannot undo existing over-merges. |

**Action required:** run one full `irc('sort', prm)` on the test copy to regenerate `viClu_premerge` = raw over-segmented labels, then sweep/`reset-to-premerge` on that fresh file. After a clean sort, `premerge nClu` should be **>>** merged `nClu` and the warning should clear.

## Candidate settings (try in this order)

| # | Parameter | Current | Try | Iterate via |
|---|-----------|---------|-----|-------------|
| 1 | `post_merge_mode` | `8` | `17` | in-memory sweep |
| 2 | `maxWavCor` | `0.985` | `0.985 → 0.975 → 0.965` | in-memory sweep |
| 3 | `post_merge_mode0` | `[8,4,17,12]` | remove (inert) | — |
| 4 | `out_in_ratio_merge` | unset (1/8) | `0.5` (only if keeping mode 8) | in-memory sweep |
| 5 | `isosplit_isocut_threshold` | `0.8` | `1.0` (up to ~1.3) | full re-sort |
| 6 | `knn` | `50` | `30` | full re-sort |

## Results log

Fill one row per `sweep_post_merge` row or `reset-to-premerge` run. `nClu` from the sweep table / `irc describe`; "good units" = `note=='single'` count after curation (optional).

| date | baseline clean? | post_merge_mode | maxWavCor | other | result nClu | synced | good units | notes |
|------|-----------------|-----------------|-----------|-------|-------------|--------|-----------|-------|
|      |                 | 8 (ref)         | 0.985     |       |             |        |           | current settings, reference |
|      |                 | 17              | 0.985     |       |             |        |           |       |
|      |                 | 17              | 0.975     |       |             |        |           |       |
|      |                 | 17              | 0.965     |       |             |        |           |       |
|      |                 |                 |           |       |             |        |           |       |

## Workflow

```matlab
prm = 'E:\scratch\tmp\260320_afm18367_g0_imec0\remerge\...IRC_all_sites.prm';
irc('sort', prm)                 % 1. clean baseline (needs raw .bin reachable via vcFile)
T = sweep_post_merge(prm, [8 .985; 17 .985; 17 .975; 17 .965]);   % 2. shortlist by numbers (no save)
% 3. edit .prm to the winner (post_merge_mode, maxWavCor), then:
irc('reset-to-premerge', prm)    % 4. bake in from raw baseline (saves, keeps .bak)
irc('manual', prm)               % 5. inspect (answer "Yes" = load last saved)
```
