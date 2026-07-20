# Sorted-dataset integrity report — `viClu` ⇄ `cviSpk_clu` desync scan

**Date:** 2026-07-20 · **Scope:** all ironclust sorts registered in both repos' paths CSVs
(`StempelLab/Project_hierarchy` and `StempelLab/cuniform_NPX`). **Method:** read-only —
no `_jrc.mat` was modified. **Branch:** `rewind`.

---

## 1. Executive summary

A read-only scan of every ironclust sort registered in the two projects' `paths` CSVs found
**22 unique `_jrc.mat` files that are corrupted** by the cluster-identity **desync** bug (the
`[O]`-reorder / CID-01 class), affecting **~37 session entries** across 5 animals. Two further
files are so damaged they **will not load at all**. All corrupted files are **not repairable and
must be re-sorted.**

| Repo | sort entries scanned | PASS | **DESYNC (corrupt)** | unique corrupt files | won't-load | not-checked |
|---|---|---|---|---|---|---|
| Project_hierarchy | 167 | 64 | 40 | **17** | 4 | 58 |
| cuniform_NPX | 26 | 8 | 9 | **5** | 2 | 7 |
| **Total** | **193** | **72** | **49** | **22** | **6** | **65** |

("DESYNC entries" > "unique files" because several sessions/segments and re-sort variants point at
the same physical file. "not-checked" = the CSV's `sorting_spikes` folder held no ironclust
`_jrc.mat`, e.g. Kilosort-only outputs or sessions not yet sorted.)

---

## 2. What the bug is (why these files are corrupted)

IronClust stores the spike→cluster assignment **twice**: `S_clu.viClu` (per-**spike** labels, the
source of truth) and `S_clu.cviSpk_clu` (per-**cluster** spike-index cache, derived). The
`[O]` "reorder clusters by coordinates" command sorted the clusters and applied the permutation with
`S_clu_select_`, which reindexes every per-cluster field **but not `viClu`** (its name ends in
`Clu`, not `_clu`). The old code never remapped `viClu`, then wrote straight to disk. After one
`[O]`, the two representations describe **different partitions of the spikes** — globally, across
essentially every cluster.

Once that desynced state exists on disk, any later curation that rebuilds one side from the other
(a split/merge, or a re-open) **bakes the mislabeling in**, and the two sides stop being a clean
permutation of each other (cache entries begin to span more than one `viClu` label). At that point
spikes are genuinely misassigned throughout the recording. This is **not** the same as the DI-01
`[U]` multi-group merge bug (which is bounded and internally consistent); the desync is global.

**It is not repairable.** `viClu` and the cache are different partitions, not the same one
relabelled, so no relabel-from-cache recovery is valid, and a "which side is authoritative" check
cannot work (the size/site/position fields all derive from the cache and agree with it by
construction). The sort pipeline itself is clean (every path ends in `S_clu_refresh_`) — this is a
GUI-curation artifact — so **re-sorting produces a correct file.** The bug was fixed 2026-07-15
(CID-01, commit `87cd4f1`); new sorts cannot desync, and `S_clu_assert_synced_` now warns at
file-open.

---

## 3. Method

- **Definitive test** (identical to `S_clu_assert_synced_`): for every cluster *i*,
  `all( viClu(cviSpk_clu{i}) == i )`. Any violation = desync.
  - `PASS` — cache and `viClu` agree.
  - `DESYNC` — disagree, but each cache entry maps to a single wrong label (clean permutation;
    typically a single `[O]`).
  - `DESYNC-SEVERE` — cache entries mix **multiple** `viClu` labels (compounded desync). **Every
    corrupted file found here is DESYNC-SEVERE.**
- **Spatial-coherence heuristic** (secondary; a PASS backstop): flags clusters where >10% of spikes
  sit on sites >8 away from the peak site (min 50 spikes/cluster). A **candidate to eyeball**, not a
  verdict — drift and genuinely large units can trip it. (This heuristic is being tightened in a
  follow-up; see §8.)
- **Session → file resolution:** each CSV row's `sorting_spikes` path → its parent folder → glob
  `*_jrc.mat`. Folders with several sorts (e.g. `merged_`, `histo_`, `shortwaves_`, `optimized_`,
  `all_sites`, `test…`) contribute one entry each. Sessions with no ironclust `_jrc.mat` are logged
  `SKIP:notfound`.
- **Read-only.** The tools (`check_jrc_one`, `check_jrc_sync`, `scan_jrc_report`, committed under
  `matlab/`) only `load()` and compute; they never write to a `_jrc.mat`.

---

## 4. Findings — Project_hierarchy (`paths-Copy.csv`, 146 sessions)

### 4.1 Corrupted (DESYNC-SEVERE) — 17 unique files → **re-sort**

| animal | sessions affected | file (folder / sort) | nClu | %spikes wrong |
|---|---|---|---|---|
| afm17307 | 241024 | `np2/afm17307/241024/…/…ap_IRC` | 220 | 99.4% |
| afm17307 | 241030_0/1/2 | `…/241030/…/…ap_IRC` | 799 | 99.4% |
| afm17307 | 241030_0/1/2 | `…/241030/…/merged_…ap_IRC` | 114 | 52.4% |
| afm17307 | 241031_0/1/2/3 | `…/241031/…/…ap_IRC` | 1122 | 93.0% |
| afm17313 | 241029_0/1/2/3 | `…/241029/…/…ap_IRC_PAG` | 314 | 99.4% |
| afm17372 | 241125_0/1/2 | `…/241125/…/…ap_IRC` | 219 | 98.1% |
| afm17372 | 241127_0/1/2 | `…/241127/…/…ap_shortlist_IRC` | 199 | 93.9% |
| afm17372 | 241129_0/1/2 | `…/241129/…/…ap_IRC` | 257 | 28.7% |
| afm17372 | 241202_0/1/2 | `…/241202/…/…ap_IRC` | 212 | 47.8% |
| afm17372 | 241206_0/1 | `…/241206/…/…ap_IRC` | 197 | 90.7% |
| afm17372 | 241206_0/1 | `…/241206/…/histo_…ap_IRC` | 110 | 60.1% |
| afm17372 | 241206_0/1 | `…/241206/…/shortwaves_histo_…ap_IRC` | 191 | 97.9% |
| afm17372 | 241209 / 241209_01 | `…/241209/…/…ap_irc` | 384 | 52.8% |
| afm17372 | 241209 / 241209_01 | `…/241209/…/optimized_…ap_irc` | 292 | 56.4% |
| afm17372 | 241210 | `…/241210/…/…ap_IRC` | 287 | 97.6% |
| afm17372 | 241212 | `…/241212/…/…ap_IRC` | 176 | 11.6% |
| afm17372 | 241213 | `…/241213/…/…lf_shortlist_IRC` | 181 | 97.1% |

Full paths + per-cluster counts: `logs/jrc_scan_project_hierarchy/AFFECTED_REPORT.md` and the
per-session `logs/*.log`.

### 4.2 Won't load (4 entries)
Four `_jrc.mat` returned MAT-file read errors ("File might be corrupt") — a distinct, non-desync
failure (bad/truncated save, the DI-02/05 class now fixed). Listed under "Not checked / load error"
in the per-repo report.

### 4.3 Clean (64 PASS) and review candidates (36 spatially flagged)
The remaining sorts pass the invariant. 36 PASS files carry ≥1 spatial-heuristic flag (e.g.
`afm17365_241202_0`, 21 flagged clusters) — candidates to eyeball, most likely benign drift. These
are being re-scored with a tightened heuristic (§8).

### 4.4 Note
Several **actively-analysed** afm17372 sessions (241125, 241127, 241129, 241202, 241206, 241209, …
— the sets iterated in `preprocess_all.py`) are among the corrupted. Downstream analyses built on
these sorts are affected.

---

## 5. Findings — cuniform_NPX (`Project_Motor/NPX/00_data/paths.csv`, 20 sessions)

### 5.1 Corrupted (DESYNC-SEVERE) — 5 unique files → **re-sort**

| animal | sessions affected | file | nClu | %wrong |
|---|---|---|---|---|
| afm18349 | 260317_0 | `260317_AFM-18349/catgt_…/…ap_IRC` | 209 | 88.1% |
| afm18349 | 260320_0 | `260320_AFM-18349/catgt_…/…ap_IRC` | 259 | 92.4% |
| afm18349 | 260324_0 | `260324_AFM-18349/catgt_…/…ap_IRC` | 190 | 91.6% |
| afm18367 | 260317_0/1 | `260317_AFM-18367/supercat_…/**test**260317_…ap_IRC` | 36 | 39.6% |
| afm18367 | 260320_0 | `260320_AFM-18367/…/…ap_IRC` | 138 | 43.4% |

The afm18349 260324 sort has **52 of 190 cache entries mixing labels** — the exact "52/190"
signature from the original desync forensics (`logs/issue_viclu_desync_20260715.md` §7); this scan
independently re-identifies the recording that investigation was built on.

### 5.2 Won't load (2 entries)
afm18349 260317 `…_IRC_all_sites_jrc.mat` — MAT-file read error ("File might be corrupt").

### 5.3 Clean and notable
- **8 PASS.** afm18367's **main** sorts (`260317`, `260324`) and its catgt **KS3/KS4** variants are
  clean — only the `test…` sort of 260317 is corrupt.
- The **local** testbed `E:\scratch\…afm18349 260324 …_IRC_all_jrc.mat` (949 clusters) is **clean**,
  but the **gpfs `…_IRC` sort of the same session is corrupt** — they are different sort runs. Local
  scratch and the gpfs registry are not the same files.
- Local `E:\scratch` also holds an afm18349 **260320** `_IRC_all` sort that is **DESYNC-SEVERE**
  (found during tool validation).

### 5.4 Not checked (7)
All three **afm18348** sessions (no sort yet) and a few afm18367 KS/SPI variants had no ironclust
`_jrc.mat` in the registry folder.

---

## 6. Affected-session index (quick reference)

**Project_hierarchy:** afm17307 {241024, 241030_0/1/2, 241031_0/1/2/3} · afm17313 {241029_0/1/2/3} ·
afm17372 {241125_0/1/2, 241127_0/1/2, 241129_0/1/2, 241202_0/1/2, 241206_0/1, 241209(_01), 241210,
241212, 241213}.

**cuniform_NPX:** afm18349 {260317_0, 260320_0, 260324_0} · afm18367 {260317_0/1 (test sort),
260320_0}.

---

## 7. Limitations

- **`PASS` is not a proof of "never corrupted."** It proves the file is *currently self-consistent*.
  A desync that was already baked into `viClu` by a bad split/merge and then re-cached will pass the
  invariant. The spatial heuristic is the backstop for that residual case (§8).
- **The DI-01 `[U]` multi-group merge bug is undetectable here** — that corruption is internally
  consistent by construction. Only manual review of batched merges can catch it.
- **Coverage = the CSV registry.** 65 sessions were "not checked" because no ironclust sort was
  found in the registered folder (Kilosort-only, unsorted, or sorts stored elsewhere). Local scratch
  copies (e.g. `E:\scratch`) are outside the CSVs and were only spot-checked.

---

## 8. Recommendations & next steps

1. **Re-sort the 22 corrupted files** (and re-derive any analysis built on them). Re-sorting fixes
   it; the pipeline is clean and the `[O]` bug that caused this is fixed.
2. **After each re-sort, verify** with `check_jrc_sync('<new_jrc.mat>')` — it should read `PASS`.
3. **Investigate the 6 won't-load files** separately (bad/truncated saves; re-sort or restore from
   backup).
4. **Tighten the spatial heuristic** (in progress) to cut false positives and surface only
   higher-confidence review candidates, then re-score the PASS set.
5. Optionally, generate ready-to-run re-sort command lists for the 22 files.

---

## 9. Artifacts (all committed on `rewind`)

- `matlab/check_jrc_one.m`, `matlab/check_jrc_sync.m`, `matlab/scan_jrc_report.m` — the read-only tools.
- `logs/DATASET_INTEGRITY_SUMMARY.md` — de-duplicated unique-file ↔ sessions table (full paths).
- `logs/jrc_scan_project_hierarchy/` and `logs/jrc_scan_cuniform/` — per-repo `AFFECTED_REPORT.md`,
  `manifest.csv`, and per-session `logs/*.log`.
- This report: `logs/DATASET_INTEGRITY_REPORT.md`.
