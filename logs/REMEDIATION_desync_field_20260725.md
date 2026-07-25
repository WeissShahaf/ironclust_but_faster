# Field remediation of the `viClu`⇄`cviSpk_clu` desync — 2026-07-25

Remediation of the **22 corrupted sorts** found by the read-only field scan
(`logs/DATASET_INTEGRITY_REPORT.md`, `logs/jrc_scan_*/`). **Every corrupt `_jrc.mat` was fixed in
place without a full re-sort**, superseding the earlier "not repairable → re-sort" verdict.

## Why no re-sort was needed
- Detection artifacts (`_spkfet/_spkraw/_spkwav.jrc`) and the kNN graph (`rho/delta/ordrho/nneigh/
  miKnn`, `icl`) are **separate, intact files** on disk — only `S_clu` inside `_jrc.mat` was corrupt.
- A pristine write-once **`viClu_premerge`** snapshot (and `viClu_auto` on newer sorts) survives the
  curation bugs (ends in `_premerge`/`_auto`, so the `S_clu_select_` reindex can't touch it).
- **`export_csv_` writes `viClu`** (irc.m:10341), *not* the cache — so the exported **spike-times**
  CSV was never built from the corrupt `cviSpk_clu`; correctness == `viClu` coherence. Only
  `export_quality_` (cache-derived per-cluster fields) needed rebuilding.

## Two remediation modes (tools committed `56389c0`, `matlab/`)
| tool | what | curation | numbering |
|---|---|---|---|
| `recover_from_snapshot.m` | `viClu=viClu_premerge` → `post_merge_` (DPC regen / label re-merge) | **discarded** (clean auto baseline) | renumbered |
| `resync_clu.m` | keep curated `viClu`; rebuild `cviSpk_clu`+wav+pos+**quality** | **preserved** | preserved |
| `exclude_flagged_units.m` | set flagged fusion units' CSV col-2 → **-2** | — | — |
| `reexport_csv.m` | re-export `[time,viClu,site]` from current sort | — | — |
| `assess_viclu*.m` | read-only: group by `viClu`, flag two-neuron fusions | — | — |

## viClu-coherence assessment (read-only, `assess_viclu.m`)
16 Dylan=1 Project_hierarchy files: **10 LIKELY-CLEAN** (0 fusions), **3 MINOR** (241030/241129/
241206, 1-2 fusion units), **3 SUSPECT** (241209 base 12 + optimized 4, merged_241030 45% affected).
5 cuniform files: **all LIKELY-CLEAN**. Flagged unit ids (= CSV col-2) in
`\\gpfs…\project_hierarchy\data\flagged_units.csv`; verdicts in `assess_viclu_results.csv`.

## What was applied — Project_hierarchy Dylan=1 (afm17307/17313/17372)
| session | spike-times CSV | quality CSV | `_jrc.mat` |
|---|---|---|---|
| afm17372 241209 | recovered → re-exported (564 clu) | re-exported | recovered, PASS |
| afm17372 241129 | units 107,165 → -2 | resynced | resynced, PASS |
| afm17372 241206 | re-exported → unit 67 → -2 | resynced | resynced, PASS |
| afm17307 241030 | unit 663 → -2 | resynced | resynced, PASS |
| afm17307 241031 · afm17313 241029 · afm17372 241125/241127/241202/241206(histo,shortwaves)/241210/241212/241213 | already correct (viClu-based) | **resynced** | resynced, PASS |

- `merged_241030` (45% fused) and `optimized_241209` are non-official variants → **use the base sort**,
  not remediated.
- `afm17307_241024`: Dylan blank, already marked "needs resorting" → not remediated.
- Every write kept a backup: `_jrc.mat.bak` (+ `.corrupt_orig` for 241209); CSV `.bak`/`.bak_preexport`.

## cuniform_NPX (afm18349/18367)
Pilot `260317_afm18349` (isosplit) **recovered** → PASS (185 clu). Other 4 (`test260317_afm18367`
hdbscan, `260320_afm18349` isosplit, `260320_afm18367` drift-knn, `260324_afm18349` isosplit) assessed
**`viClu`-coherent** — their spike-times CSVs are trustworthy as-is; resync only if their `_quality.csv`
feeds a downstream pipeline.

## Downstream: `preprocess_all` rerun
Project_hierarchy repo `C:\ProgramData\uv_projects\Project_hierarchy_SW`, branch `shahaf_weiss`,
`uv run preprocessing/preprocess_all.py`. Config at top of `preprocess_all.py`: `animal` + `sessions`
(lines 82-83, one animal per run), `recompute_analyzers` (line 165). **`recompute_analyzers` must be
`True`** so the SpikeInterface analyzer (waveforms + SNR/ISI/BombCell/UnitRefine quality/labels) is
rebuilt from the corrected spikes; `"no"` reuses the previous run's cached analyzer and does **not**
reflect the fixes. Re-run per animal:
afm17307 `["241030_0","241030_1","241030_2","241031_0","241031_1","241031_3"]`;
afm17313 `["241029_1","241029_3"]`;
afm17372 `["241125_0","241125_1","241125_2","241127_1","241129_1","241129_2","241202_1","241202_2","241206_0","241206_1","241209","241210","241212","241213"]`.
(Restore lines 82-83/165 to their originals afterward: `animal="afm17365"`, `sessions=["241219_01"]`,
`recompute_analyzers="no"`.)

## Not repairable by curation — still true
Curating a *still-desynced* file in the GUI compounds the damage; `recover`/`resync` fix it first.
Do not re-curate any un-remediated file in `irc manual` without a resync.
