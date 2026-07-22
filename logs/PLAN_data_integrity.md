# Plan: Data-integrity remediation — ✅ COMPLETE (all 22 items, 2026-07-18)

> **Status: DONE.** This started as "Phase 0 (foundation) + DI-01 + DI-02/05" and, under a
> keep-going directive, was carried through **all 22 findings** in
> `logs/ISSUE_TRACKER_data_integrity.md`, then a **read-only field scan** of existing sorts (see
> "Follow-on" below — 22 corrupted `_jrc.mat` found). Full narrative lives in that tracker,
> `logs/changes_log20260718.md`, and `logs/DATASET_INTEGRITY_REPORT.md`. This file is the record.

## Context

A four-agent read-only audit + a code-architect + a devil's-advocate review produced
`logs/ISSUE_TRACKER_data_integrity.md` (22 findings, DI-01…DI-22, prioritized, with solution
designs and a phased build plan). All are distinct from the already-fixed `viClu`⇄`cviSpk_clu`
desync family (whose 15 CID fixes were re-verified present). The top finding — DI-01, a silent,
saveable multi-group `[U]` merge corruption — was independently hand-verified twice.

## What shipped (6 commits on `rewind`)

| Commit | Items |
|---|---|
| `bcbe008` | DI-01 `[U]` merge reconcile · DI-02/05 atomic `struct_save_` · foundation A1/A2/A4 |
| `a7910e0` | DI-06 `.prm` read-guard · DI-15 `export-prm` total-loss |
| `925d13f` | DI-10 GPU kernel launch-config · DI-11 `get_spkwav_` file key |
| `349a0e1` | DI-12/16/17/18/22 (quick wins) |
| `1cb9888` | DI-03/04/07/08/09/13/14/19/20/21 (detection pipeline + cache keys) |
| (pre-work) | `74b9e84`/`1dcc3fe` — the earlier GPU `nearest_in_set_` + parfor-cap work |

### Shared foundation (reused across fixes)
- **A1** `tempname_sibling_` + `atomic_replace_` (both `irc.m`/`irc2.m`) — temp+rename+`.bak`,
  refuses to commit an empty temp. Powers DI-02/05/06/15.
- **A2** `disperr_strict_` (`irc.m`) — print-then-rethrow sibling of the swallowing `disperr_`.
- **A4** `fread_` default-off `fStrict` (both files; own catch rethrows) + `fwrite_` short-write
  count check. Powers DI-04/07.

## Deliberate partials (documented, not oversights)
- **DI-04** — feature path made strict (`load_spkfet_`/`get_spkfet_`; a truncated `_spkfet.jrc`
  errors instead of silently misaligning clustering features). Raw/spk *display* loaders left
  lenient — they route through `get_spkwav_`'s swallow-to-`[]`, and narrowing that risked GUI code
  that tolerates `[]`.
- **DI-14** — stale-lock auto-removal on timeout added; the check-then-act TOCTOU in `lock_dir_` is
  a documented residual (needs a `mkdir`-based atomic lock across three `irc2.m` functions).
- **DI-08/09** — reviewed **count-and-continue** policy (loud, unmissable end-of-loop warnings)
  rather than an unconditional re-throw (would abort a multi-hour run) or a structural spike-drop
  (deeper change). Makes the corruption visible; does not yet remove the affected spikes.

## Verification
Five MATLAB harnesses on the real dev box (R2023b), all green; `irc.m`/`irc2.m` parse clean
(checkcode 0 parse errors):
`verify_phase012.m` (12) · `verify_phase3.m` (7) · `verify_phase5.m` (4) · `verify_phase_qw.m` (5)
· `verify_phase_det.m` (DI-07/DI-04 functional + parse). Scripts live in the session scratchpad
(not committed).

## Follow-on: dataset-integrity diagnostics + field scan (2026-07-20/21)

After the fixes, built **read-only** diagnostics and scanned existing sorts in both projects' paths
CSVs for the pre-2026-07-15 `[O]`-reorder / CID-01 desync (`viClu`⇄`cviSpk_clu`).

**Tools (committed on `rewind`, in `matlab/`):**
- `check_jrc_one.m` / `check_jrc_sync.m` — per-file / interactive invariant check
  `all(viClu(cviSpk_clu{i})==i)` + a drift-robust spatial heuristic (time-interleaved secondary
  depth population).
- `scan_jrc_report.m` — batch over a `label,jrc` manifest → per-session logs + `AFFECTED_REPORT.md`.
- `analyze_desync.m` — clean-permutation vs compounded breakdown (how much grouping survives).
- `export_desync_clusters.m` — per-(session,cluster) CSV (`clean|partial|mixed` + fused labels).

**Findings (read-only; nothing re-sorted):** `logs/DATASET_INTEGRITY_REPORT.md`,
`DATASET_INTEGRITY_SUMMARY.md`, `logs/jrc_scan_*/`. **22 unique corrupted `_jrc.mat`** — 17
Project_hierarchy (afm17307/17313/17372), 5 cuniform_NPX (afm18349/18367); all DESYNC-SEVERE; +6
files that won't load. Forensic: each is 54–92% cleanly-permuted (grouping intact, just renumbered)
with a compounded minority → **re-sort** (not repairable). Per-session surviving clusters:
`logs/jrc_scan_desync_forensic/clusters_by_session.csv`.

**Repos/CSVs:** Project_hierarchy `\\gpfs…\project_hierarchy\data\paths-Copy.csv`; cuniform_NPX
(`C:\ProgramData\uv_projects\cuniform_NPX`) `\\gpfs…\Project_Motor\NPX\00_data\paths.csv`.

## Not done / follow-ups
- **No full end-to-end `irc('sort', …)`** was run (multi-hour). The detection-pipeline changes are
  additive and gated behind failure paths, and every default-config path is byte-identical — but a
  single real sort pass on the testbed recording is the recommended final gate before production
  reliance.
- DI-04 raw/spk display path, DI-14 TOCTOU, and DI-08/09 structural spike-drop remain as noted
  residuals in the tracker.
