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

## Follow-ups closed later the same day (2026-07-25 evening)

**1. `_quality.csv` must be excluded in step with the spike-times CSV.** `preprocessFunctions.load_IRC`
(line ~2195) builds its `clusters` list from quality-CSV rows with **`note == 'single'`**. A unit
excluded only in the spike-times CSV (label → `-2`) therefore stayed in `clusters` with **zero**
spikes, tripping `preprocess_all.py:2384`'s `array_equal(unique(spike_clusters), sort(clusters))`
check → `UserWarning: something wrong with spike_clusters or clusters`, and putting a zero-spike
phantom unit into the SpikeInterface analyzer (all-zero template → NaN centre-of-mass). Downstream
`extract_spike_times_from_sorting(..., remove_empty=True)` drops it again, so it is not fatal — but
the analyzer is built with it. Fixed by setting `note='excluded'` (atomic write, `.bak_note` kept):
afm17307 241030 unit **663**; afm17372 241129 unit **107**. 241129 unit **165** was already `multi`
(outside `good_clusters`) and was left as-is so its original label survives. Only `note=='single'` /
`str.contains('single')` is ever consumed, so `excluded` is inert everywhere else.

**2. 241206 — the pipeline reads a different sort than the one that was excluded.** `paths-Copy.csv`
points 241206_0/_1 at **`shortwaves_histo_afm17372_241206_0_g0_…ap_IRC.csv`**, not the base
`afm17372_241206_0_g0_…ap_IRC.csv` that was re-exported and had unit 67 set to `-2`. The
`shortwaves_histo` sort was in the batch-resync set (LIKELY-CLEAN, no flagged fusions) and is PASS,
so **no exclusion is needed there** and nothing is missing downstream; the base-sort work is simply
not on the pipeline's path. Always resolve the sort via `paths-Copy.csv`, not by session name.

**3. Post-save PASS verification from disk.** The 10 batch-resynced Project_hierarchy files were
re-loaded from disk and re-checked: **10/10 PASS**, `desync=0` (previously only verified in memory
pre-save).

**4. cuniform `_quality.csv` resolved.** The 4 non-recovered cuniform files
(`test260317_afm18367`, `260320_afm18349`, `260320_afm18367`, `260324_afm18349`) were resynced —
curated `viClu` numbering preserved, cache + waveforms + positions + quality rebuilt, `_quality.csv`
re-exported. Re-verified from disk: **4/4 PASS** (36 / 259 / 138 / 190 clusters). All 5 cuniform
files are now PASS; backups kept.

## ⚠ `recover_from_snapshot` destroys the downstream unit selection — prefer `resync_clu` (2026-07-26)

**`note == 'single'` in `_quality.csv` is the ONLY gate that selects units downstream** — both projects
(`preprocessFunctions.load_IRC` ~line 2195; cuniform `load_irc_to_spi.py:170`,
`preprocessFunctions*.py`). Those notes come from `S_clu.csNote_clu`, i.e. the curator's labels.
`recover_from_snapshot` renumbers to a clean AUTO baseline and therefore **discards them**, so a
recovered file exports a `_quality.csv` with **every note blank** → `good_clusters` is empty →
**zero neurons downstream**. This was not visible in the `_jrc.mat` PASS check, which only tests the
`viClu`⇄`cviSpk_clu` invariant.

Both recovered files were reverted to the `resync` path (restore `.corrupt_orig` → `resync_clu` →
re-export CSVs); the recovered versions are kept as `_jrc.mat.recovered_bak` / `.csv.recovered_bak`:

| file | recovered (wrong) | resynced (now) |
|---|---|---|
| afm17372 241209 | 564 clu, **0 single** | 384 clu, **177 single** + 21 multi, desync=0 |
| cuniform 260317_afm18349 | 185 clu, quality CSV never re-exported (stale at 209 rows) | 209 clu, **84 single** + 13 multi, desync=0 |

**Rule going forward:** use `recover_from_snapshot` only when the curated `viClu` is genuinely
unusable *and* the loss of all `note` labels is acceptable (i.e. the file will be re-curated).
For anything feeding a `note=='single'` pipeline, **`resync_clu` is the correct tool** — it keeps
numbering *and* notes, and still clears the desync.

### Companion issue: zero-spike `single` units (pre-existing, unrelated to the desync)

Curator-**deleted** clusters (negative label in `viClu`) keep their old `note`. A row with
`note=='single'` and `nSpikes==0` therefore enters `good_clusters` contributing nothing → the
`preprocess_all.py:2384` `array_equal` warning + a zero-spike phantom unit in the analyzer.
Swept all 15 Dylan=1 quality CSVs (`scan_empty_single.py`): **20 units across 8 sessions** set to
`note='excluded'` (afm17307 241031 · afm17313 241029 · afm17372 241125/241127/241129/241202/
241206-shortwaves/241213), plus **17 more** in the resynced 241209.

**Residual, benign:** the same warning also fires when a `single` unit is simply silent inside a
trial's `[t1_s, tend_s]` window (verified on afm17313: unit 164, zero spikes in both trial windows
but present in the recording). That is inherent to per-trial windowing and is cleaned up downstream
by `extract_spike_times_from_sorting(..., remove_empty=True)`. Nothing to fix.

## `preprocess_all` recompute — completed 2026-07-26

All three animals re-run with `recompute_analyzers = True` (analyzer rebuilt from the corrected
spike-times CSVs, not loaded from cache):

| animal | sessions | runtime |
|---|---|---|
| afm17307 | 6/6 | 4h 43m |
| afm17313 | 2/2 | 16m |
| afm17372 | 14/14 (in 3 passes) | ~3h + partials |

**afm17372 needed `BORIS_required = False`** (`preprocess_all.py:100`) for 6 of its 14 sessions.
Those sessions fail `resolve_loom_times` with a BORIS-vs-Bonsai **loom count mismatch** — a
pre-existing behavioural-annotation backlog, *not* related to the sorting remediation: the
2026-07-02 rerun log (`logs/rerun_logs/local_afm17372.log` in the Project_hierarchy repo) records
the **identical six mismatches with identical counts**, as `[LOOM][WARN]` because that run also had
the flag off. Commit `eb81afc` (2026-06-15) introduced the strict/lenient split; `True` is the
file's stated default, so the same data became fatal.

| session | BORIS | Bonsai |
|---|---|---|
| 241125_0 | 1 | 2 |
| 241129_1 | 11 | 9 |
| 241206_1 | 6 | 17 |
| 241209 | 15 | 18 |
| 241210 | 35 | 34 |
| 241213 | 31 | 33 |

`resolve_loom_times` still snaps loom *timing* to the photodiode, so timing stays hardware-anchored;
only the count reconciliation is deferred. **`241206_1`'s 6-vs-17 gap is the one to look at first**
(11 unmatched, several clustered within seconds — possible Bonsai double-counting). The flag was
restored to `True` after the run, so these six will fail loudly again until the annotations are fixed.

**End-to-end confirmation on 241209** (the file that went recover → revert → resync): 384 clusters,
155 curated `single` after exclusions → **153 neurons** in the rebuilt analyzer (2 dropped as silent
inside the trial window by `remove_empty=True`). Under the recovered version it would have been **0**.

`recompute_analyzers` was deliberately **left at `True`** rather than restored to `"no"`: the cached
path is silent, so a future spike-data change would otherwise produce stale quality metrics with no
warning — the exact failure mode caught mid-run here.

## Not repairable by curation — still true
Curating a *still-desynced* file in the GUI compounds the damage; `recover`/`resync` fix it first.
Do not re-curate any un-remediated file in `irc manual` without a resync.
