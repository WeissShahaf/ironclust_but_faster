# Issue Tracker — data-integrity: persistence, pipeline & cache

**Scope:** data-corruption / data-loss and cache-staleness issues in `matlab/irc.m` (+ `matlab/irc2.m`),
found in a four-agent read-only audit on **2026-07-18** (persistence/file-I/O · cluster-identity
mutation · detect/feature numeric pipeline · cache-handling mechanics), then **reviewed by a
code-architect and a devil's-advocate** (2026-07-18) whose corrections are folded in below. Every
issue here is **new** and **distinct** from the `viClu`⇄`cviSpk_clu` desync family tracked in
[`ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md) (whose 15 CID fixes were
re-verified present in current code — see Appendix A).

**Legend.** ✅ fixed & committed · 🟡 fixed, uncommitted · 🔵 open/deferred · ⚪ not-a-bug ·
⛔ retracted. **ALL 22 items (DI-01…DI-22) are now 🟡 implemented 2026-07-18 (uncommitted → committed on
`rewind`).** Two are deliberately partial, noted in their entries: **DI-04** (feature path made strict —
the corruption that feeds clustering; the raw/spk *display* loaders left lenient) and **DI-14** (stale-lock
auto-removal added; the check-then-act TOCTOU race left as a documented residual needing a mkdir-lock
refactor). **DI-08/DI-09** follow the reviewed count-and-continue policy (loud, unmissable warnings)
rather than dropping the affected spikes or hard-aborting a multi-hour run.

**Confidence** = the mechanism is real, independent of trigger likelihood. **DI-01 was hand-verified
twice** (auditor + devil's-advocate, independently). Line numbers verified against source on 2026-07-18;
re-confirm before editing.

---

## ⚠ Two facts that change how every fix must be written

**1. `disperr_()` (irc.m:20343) swallows failures — the root cause behind half of these.** It does
only `fprintf(2, …)`; it never re-throws or returns a status. So nearly every `try/catch` in the
persistence/detection code silently downgrades a hard failure (locked file, disk full, GPU error, bad
index) into one red console line and **continues as if it succeeded**. Underlies DI-02/06/07/08/09;
colours DI-05/13. Remediation = give critical paths **explicit error propagation** (see §A2), *not* a
blanket promotion of `disperr_` to throwing (that would crash dozens of cosmetic call sites).

**2. `irc.m` and `irc2.m` are separate function namespaces — several targets are DUPLICATED, not
shared.** `irc2.m` has its own byte-identical copies of `struct_save_` (irc2.m:7016), `fread_`
(irc2.m:6378), `field2str_` (irc2.m:9236), `cellstr2file_` (irc2.m:8308), and a *different*
same-named `get_spkwav_` (irc2.m:4960). **A fix to any of these must be applied to both copies.**
BUT `disperr_` and `edit_prm_file_` in `irc2.m` are thin delegating stubs (irc2.m:9842-9843) that call
through to the real `irc.m` implementation — fixing those in `irc.m` is free for `irc2.m`. Missing a
duplicated copy is the single easiest way to half-migrate this plan.

---

## ✅ Implemented 2026-07-18 — ALL 22 items (DI-01…DI-22)

Commits on `rewind`: `bcbe008` (DI-01/02/05 + foundation), `a7910e0` (DI-06/15), `925d13f` (DI-10/11),
`349a0e1` (DI-12/16/17/18/22), + a final commit (DI-03/04/07/08/09/13/14/19/20/21). Verified on the real
dev box (R2023b) across five MATLAB harnesses (`verify_phase012.m` 12, `verify_phase3.m` 7,
`verify_phase5.m` 4, `verify_phase_qw.m` 5, `verify_phase_det.m` — DI-07/DI-04 functional + parse), all
green; `irc.m`/`irc2.m` parse clean (checkcode: 0 parse errors). No full end-to-end sort was run
(multi-hour) — the detection-pipeline changes are additive, gated behind failure paths, and every
default-config path is unchanged.
- **DI-01** 🟡 — `execute_pending_and_update_` (irc.m ~9843) now reconciles the not-yet-processed
  pending groups after each in-group delete (concatenation form, reusing `adjust_pending_indices_`).
  Verified: `{[3,5],[7,9]}` → after group 1 deletes Clu5, group 2 correctly shifts `[7,9]`→`[6,8]`
  (was left stale before). Byte-identical for single-group `[U]`.
- **DI-02 + DI-05** 🟡 — `struct_save_` (**both** irc.m:15174 + irc2.m:7016) returns `fOk` and writes
  atomically (temp → `atomic_replace_` → `.bak`); `save0_` (irc.m:13161) blocks a false "success" and
  warns via `msgbox_`. Verified: healthy save `fOk=1`, content matches, no `.tmp` litter; bad-path
  `fOk=0`, no exception, **prior good `_jrc.mat` intact**; `atomic_replace_` refuses an empty temp.
- **DI-06** 🟡 — `file2cellstr_` (irc.m:21907) now distinguishes a read failure on an *existing* file
  (`fOk=false` → `edit_prm_file_` aborts rather than truncating the live `.prm`) from an *absent* file
  (`fOk=true`, so new-`.prm` creation still works); `cellstr2file_` (irc.m:22010) writes to a temp then
  renames (atomic; `movefile` not `atomic_replace_` so a legitimately-empty text file isn't refused).
  Verified: edit round-trip preserves comments + untouched params; absent-file path still creates; empty
  write still works.
- **DI-15** 🟡 — `export_prm_` (irc.m:23413) now reads `P` from the source **before** touching the
  target and builds the full prm into a temp (atomic replace + `.bak`), so `irc('export-prm','x.prm')`
  in a fresh session no longer wipes the user's settings. Verified: `sRateHz=12345` survives a
  standalone export (was clobbered to the default before). Both reuse the A1 helpers from Phase 0.
- **DI-10** 🟡 — the 7 GPU DPC/kNN kernels (`cuda_rho_`/`cuda_delta_`/`cuda_rho_drift_`/
  `cuda_delta_drift_`/`cuda_knn_`/`cuda_knn__`/`cuda_delta_knn_`) now recompute
  `ThreadBlockSize`/`SharedMemorySize`/`GridSize` **every call** (mirroring irc2's `search_knn_drift_`)
  instead of baking them in at kernel construction — so an interactive multi-file session bypassing
  `batch_`'s `irc('clear')` no longer launches a new-sized grid against an old-sized shared-memory
  buffer. Verified structurally (7/7 recompute sites) + parse-clean; the runtime multi-file GPU
  divergence test is deferred (needs GPU hardware + two differently-configured recordings).
- **DI-11** 🟡 — `get_spkwav_` (irc.m:24442) gains a `persistent vcFile_prm_` key and clears its
  `tnWav_spk`/`tnWav_raw` globals on a file switch (copying `get_spkfet_`'s pattern), so a caller
  reaching it without `load_cached_` no longer serves the previous file's waveforms. Verified:
  same-file keeps the cache, a file switch invalidates it.
- **Foundation (A1/A2/A4)** — `tempname_sibling_`/`atomic_replace_` (both files), `disperr_strict_`
  (irc.m), `fread_` default-off `fStrict` (both files; its own catch now rethrows in strict mode so a
  strict error isn't swallowed at layer 0), `fwrite_` short-write count check (irc.m). **All default-off
  / no-op for every current caller** — DI-04/DI-07 consumers are wired in Phase 4. `fread_` 3-arg lenient
  path verified byte-identical.

- **Quick wins** 🟡 — **DI-12** `field2str_` (both files) `case 'string'`; **DI-16** `wav_car_`
  `sum(single(...))`; **DI-17** `mr2tr_` int64 indices; **DI-18** `post_merge_mode` scalar coercion;
  **DI-22** `readmda_paged_` closes the previous fid on a file switch.
- **Cache keys** 🟡 — **DI-19** `sgfilt4_`/`sgfilt_init_` add `fGpu` to the rebuild key; **DI-20**
  `S_clu_wav_pair_` recomputes `viT` every call; **DI-21** dead-code caches (`fread_spkwav_/raw_`,
  `fid_fet_cache_`) get a `%WARNING` (comment-only — confirmed no live callers).
- **Detection pipeline** 🟡 — **DI-07** `write_spk_` returns `fOk`, guards `fopen`, and `file2spk_`
  aborts on a failed/short write; **DI-03** `file2spk_` captures a `dimm_*` template from the first
  non-empty chunk (a quiet tail no longer zeroes dims 1-2) + a degenerate-template safety assert;
  **DI-04** `load_bin_` gains a working `fStrict` (rethrows a short read) and the **feature** loaders
  (`load_spkfet_`/`get_spkfet_`) opt in — a truncated `_spkfet.jrc` now errors instead of silently
  misaligning clustering features (raw/spk display loaders left lenient — see the DI-04 caveat below);
  **DI-13** an `onCleanup` closes the `.jrc` handles if the detection loop throws; **DI-08/DI-09** the
  per-site `mn2tn_wav_`/`spikeMerge_` catches now count failures and emit a loud end-of-loop summary
  instead of silently swallowing (phantom-zero / dropped spikes made visible, not hidden); **DI-14**
  `waitfor_lock_` removes a stale lock on timeout (the check-then-act TOCTOU residual is noted).

**Two deliberate partials** (documented, not oversights): **DI-04** wired the feature path (the
clustering-corrupting one) but not the raw/spk *display* loaders — those go through `get_spkwav_`'s
swallow-to-`[]`, so a short read there surfaces as an empty-array downstream error rather than silent
misalignment, and narrowing that catch risked GUI code that tolerates `[]`. **DI-14** removes a stale
lock but keeps the non-atomic `lock_dir_` create; a true fix needs a `mkdir`-based lock coordinated
across `waitfor_lock_`/`lock_dir_`/`unlock_dir_` (a larger refactor of an `irc2.m`-only caching path).

## Priority ranking (impact × trigger-likelihood ÷ fix-cost)

Reconciled from the architect ranking + devil's-advocate re-ranks. "Cost" assumes the §A shared
helpers exist.

| # | ID | Why it's here | Cost |
|---|---|---|---|
| 1 | **DI-01** | Silent saved corruption on the core `[U]` workflow; no detector fires; fix is ~4 lines (once corrected — see entry) | trivial |
| 2 | **DI-02 + DI-05** | Data-loss on the most consequential save path; one shared edit closes both | small |
| 3 | **DI-07** | Multi-hour runs "succeed" while writing empty/truncated spike files; compounds DI-04 | small |
| 4 | **DI-04** | Silent spike↔waveform *misalignment* (wrong, not missing); real fix is a 4-layer swallow chain | medium |
| 5 | **DI-15** | **Upgraded to high/high** — total, unrecoverable `.prm` loss in the documented standalone CLI form; folds into §A1 for ~free | trivial (w/ A1) |
| 6 | **DI-06** | Very high-traffic path (15+ call sites); read-guard is ~5 lines | small |
| 7 | **DI-10** | High/high but narrow trigger (interactive multi-file loop bypassing `batch_`'s `irc('clear')`); mechanical, needs GPU to test | medium |
| 8 | **DI-03** | High/high; needs per-field care to avoid a false assert on the legit `fSave_spkwav=0` case | medium |
| 9 | **DI-11** | **Confidence → medium** (cited path is guarded by `load_cached_`); fix is copy-paste of a proven pattern | trivial |
| 10 | **DI-08** | Medium; **fix must be count-and-continue, NOT re-throw** (see entry); also repairs the defeated GPU→CPU retry | small |
| 11 | **DI-09** | Medium; same shape/fix policy as DI-08 | small |
| 12 | **DI-18** | One-liner, **already hit in production** (`MEMORY.md`); a crash not corruption, so low urgency but zero-cost quick win | trivial |
| 13 | **DI-12** | One-liner; cosmetic only (sorting data untouched — the 2026-07-18 error) | trivial |
| 14 | **DI-20** | Merge-*preview* comparison only, not persisted data | trivial |
| 15 | **DI-19** | Narrow cross-session trigger (`fGpu` constant within a file) | trivial |
| 16 | **DI-13** | `onCleanup` fix, but touches a hot detection loop's control flow | small |
| 17 | **DI-14** | `irc2.m`-only concurrent-session race + 1 h stall; distinct `mkdir`-lock primitive | medium |
| 18 | **DI-16** | **Severity → low-med** (double non-default combo, one option undocumented); trivial cast fix | trivial |
| 19 | **DI-22** | Resource leak, not correctness | trivial |
| 20 | **DI-17** | Very narrow (>20 h untransposed single-block) | trivial |
| 21 | **DI-21** | Dead code, no live risk; comment-only per no-delete rule | trivial |

**Quick wins to do opportunistically any time (independent, ~1 line each):** DI-12, DI-16, DI-17, DI-18, DI-22.
**Structural work needing the §C phasing:** DI-01 … DI-11 + DI-15.

---

## Index

| ID | Title | Tier | Severity | Conf. | Status |
|---|---|---|---|---|---|
| **DI-01** | `[U]` multi-group merge never reconciles later groups' indices → merges wrong clusters, saves it | 1 | **critical** | high (2× hand-verified) | 🟡 |
| **DI-02** | `struct_save_` swallows total save failure — no return, no re-throw | 1 | **critical** | high | 🟡 |
| **DI-03** | `file2spk_` uses last chunk as `dimm_*` template — zero-spike tail zeroes it | 1 | high | high | 🟡 |
| **DI-04** | `fread_` silent short-read reshape → spike↔waveform misalignment (4-layer swallow chain) | 1 | high | high | 🟡 |
| **DI-05** | Non-atomic `_jrc.mat` overwrite — no temp+rename/backup | 2 | high | high | 🟡 |
| **DI-06** | `.prm` read-modify-write truncates the live file on a transient read failure | 2 | high | med-high | 🟡 |
| **DI-07** | `write_spk_`/`fwrite_` failures discarded during detection | 2 | high | high | 🟡 |
| **DI-08** | `mn2tn_wav_` per-site catch → phantom zero waveforms + defeats GPU→CPU retry | 2 | medium | medium | 🟡 |
| **DI-09** | `spikeMerge_` per-site catch drops a whole site's spikes for the chunk | 2 | medium | medium | 🟡 |
| **DI-10** | GPU CUDA-kernel caches keyed on `nC` only — stale `SharedMemorySize` across files | 2 | high | high | 🟡 |
| **DI-11** | `get_spkwav_` global cache has no `vcFile_prm` key of its own | 2 | high | **medium** | 🟡 |
| **DI-12** | `field2str_` can't format MATLAB `string` class *(the error seen 2026-07-18)* | 3 | cosmetic | high | 🟡 |
| **DI-13** | No `fclose` cleanup on mid-detection exception; unbuffered `'W'` handles | 3 | low-med | medium | 🟡 |
| **DI-14** | irc2 stale-lock never cleared + check-then-act lock race (TOCTOU) | 3 | medium | medium | 🟡 |
| **DI-15** | `export-prm` clobbers target before verify → **total unrecoverable config loss** | 2 | **high** | **high** | 🟡 |
| **DI-16** | `wav_car_` int16 saturating sum corrupts the CAR reference | 3 | **low-med** | med-high | 🟡 |
| **DI-17** | int32 saturation for untransposed >~20 h recordings | 3 | low (narrow) | low-med | 🟡 |
| **DI-18** | `post_merge_mode` array → hard crash; no validation/coercion | 3 | low (crash) | high | 🟡 |
| **DI-19** | `sgfilt4_`/`sgfilt_init_` cache key omits `fGpu` | 3 | low-med | medium | 🟡 |
| **DI-20** | `S_clu_wav_pair_` `viT` window cache never invalidates; reset path is dead | 3 | medium | medium | 🟡 |
| **DI-21** | Dead-code unkeyed caches (`fid_fet_cache_`, `fread_spkwav_/raw_`) | 3 | low (dormant) | high | 🟡 |
| **DI-22** | `readmda_paged_` file-handle leak on file switch | 3 | low | medium | 🟡 |

---

## A. Shared infrastructure (build once, reuse across issues)

### A1. Atomic-write helpers — subsume DI-02, DI-05, DI-06 (write half), DI-15
Two new additive functions:
```matlab
function vcFile_tmp = tempname_sibling_(vcFile_final)
% Same-directory temp path so movefile stays on one volume (required for atomicity).
vcFile_tmp = [vcFile_final, '.tmp'];
end %func

function fOk = atomic_replace_(vcFile_tmp, vcFile_final, fKeep_bak)
% Commit a fully-written temp file over vcFile_final. REFUSES to commit a missing/zero-byte
% temp (never destroys a good file with a bad one). Optional .bak of the prior file.
if nargin<3, fKeep_bak = false; end
fOk = false;
try
    S_dir = dir(vcFile_tmp);
    if isempty(S_dir) || S_dir.bytes == 0
        fprintf(2, 'atomic_replace_: refusing to commit missing/empty temp: %s\n', vcFile_tmp); return;
    end
    if fKeep_bak && exist_file_(vcFile_final)
        try copyfile(vcFile_final, [vcFile_final, '.bak'], 'f'); catch, end   % best-effort
    end
    movefile(vcFile_tmp, vcFile_final, 'f');
    fOk = exist_file_(vcFile_final);
catch hErr
    disperr_('atomic_replace_ failed', hErr);
end
end %func
```
Route through it: `struct_save_` (irc.m:15174 **and** irc2.m:7016) → DI-02+DI-05; `cellstr2file_`
(irc.m:21923) → DI-06 write half; `export_prm_` (irc.m:23326) → DI-15. **Known limitation to record:**
`[vcFile,'.tmp']` is not collision-proof across two concurrent processes — that's DI-14's territory;
acceptable for a single-user desktop session.

### A2. Error-propagation convention — replaces the `disperr_` swallow (DI-02/06/07/08/09)
**Two conventions, chosen per site (both additive; `disperr_` itself untouched):**
- **Status-return** (preferred where the caller can act): give the function an `fOk`/`fSuccess`
  output — exactly the `[S_clu, fOk] = delete_clu_(…)` idiom CLAUDE.md already documents. Adding an
  output to a currently-void function is safe: every bare-statement caller stays legal. Use for
  `struct_save_`, `cellstr2file_`/`file2cellstr_`, `fwrite_`/`write_spk_`.
- **`disperr_strict_`** (new sibling — do NOT overload `disperr_`, it has dozens of legitimately
  swallowing cosmetic callers): prints via `disperr_` then re-throws. Reserve for sites with no clean
  status channel. **Note the DI-08/09 caveat below** — inside the huge-iteration detection loop, an
  *unconditional* re-throw is the wrong default; those two use count-and-continue instead.

### A3. Keyed-cache idiom — DI-11, DI-19, DI-20, DI-21, and the DI-10 variant
Reference (already in-tree, `get_spkfet_` irc.m:24341): `persistent data_ key_; if key ~= key_ ||
isempty(data_), rebuild; key_ = key; end`. Copy-paste (a shared helper is awkward under `persistent`
scoping — the codebase already copy-pastes this). Apply to DI-11 (`vcFile_prm` key), DI-19 (`fGpu`
key), DI-20 (`spkLim_raw`/`spkLim_factor_merge` key), DI-21 (comment-only — dead code). DI-10 is the
*"recompute unconditionally"* variant (cheap scalar props, not a multi-MB array) — see its entry.

### A4. Strict-mode I/O params — `fread_` (DI-04) + `fwrite_` (DI-07)
Add an additive, **default-off** `fStrict` to `fread_` (irc.m:5734 **and** irc2.m:6378) that
`error()`s on a short read; and make `fwrite_` (irc.m:24296) compare the written count to
`numel(vr)`. Default-off is what keeps the shared primitives byte-identical for the ~15 lenient
callers (e.g. `load_file_`, the hot detection-read path) — **only** the `load_spk*_` callers opt in.
This directly resolves the devil's-advocate concern that a strict *shared* `fread_` would add a crash
risk to every detection run.

---

## Tier 1 — silent, *saveable* corruption/loss on common/default paths

### DI-01 🔵 `[U]` multi-group merge never reconciles later groups' indices — **hand-verified ×2**
- **Location:** `execute_pending_and_update_`, **irc.m:9780-9859**. In-group delete succeeds at
  irc.m:9834, log staged at 9842, local-only adjust at 9845-9852. Helper `adjust_pending_indices_`
  at irc.m:9909-9923; Step 1's correct use at irc.m:9776.
- **Mechanism:** Step 2 reads each group *statically* from `S0.cviMerge_pending{iGroup}` (line 9781).
  Every in-group `delete_clu_` renumbers all clusters `> iClu_source` down by one, but the code only
  shifts the *current* group's local `viClu_group`/`iClu_target` — never
  `S0.cviMerge_pending{iGroup+1:end}`. The comment at line 9844 claims "this group **and other
  groups**"; the code does only "this group." `adjust_pending_indices_` is wired into Step 1 deletes
  (9776) and the immediate-`[M]` path (9445) but **never** here.
- **Repro (both reviewers traced independently):** `nClu=10`; `[M]` Clu3+5, `[M]` Clu7+9 (disjoint →
  two groups via transitive grouping, `add_pending_merge_` irc.m:9590-9592); `[U]`. Group 1 merges
  5→3, deletes 5, renumbers 6-10→5-9; group 2 read as stale `[7,9]` merges **original 8+10**, and the
  intended 7+9 never happens. If deletions push a later group's IDs past `nClu`, the bound check
  (9787) silently drops it. **`S_clu_assert_synced_` reports 0 stale** (each merge is internally
  consistent) → no detector; saves to `_jrc.mat`. **Only triggers with ≥2 groups in one `[U]`
  batch** — applying one merge per `[U]` never hits it.
- **Severity:** critical. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW (commit `1a4ce9e` edited this exact
  loop for cross-shank but not this).
- **Scoped fix — CORRECTED (the naive one-liner throws):** after line 9842, before the local adjust:
  ```matlab
  % Reconcile the NOT-yet-processed groups for this in-group delete (mirrors Step 1, line 9776).
  % Use concatenation, NOT `cviMerge_pending(iGroup+1:end) = adjust_pending_indices_(...)`:
  % adjust_pending_indices_ DROPS groups that fall below 2 members (line 9921), so the returned
  % cell can be SHORTER than the LHS range -> `A(idx)=B` throws on a size mismatch.
  if iGroup < numel(S0.cviMerge_pending)
      cviTail = adjust_pending_indices_(S0.cviMerge_pending(iGroup+1:end), iClu_source);
      S0.cviMerge_pending = [S0.cviMerge_pending(1:iGroup); cviTail(:)];
  end
  ```
  **Edge case to flag in code:** the outer `for iGroup = 1:numel(...)` caches `numel` once; if the
  tail shrinks, a later `iGroup` can index past the shortened array → a **loud crash**, which is the
  acceptable crash-vs-silent-corruption trade (CLAUDE.md P3b). Regression risk otherwise low: touches
  only `S0.cviMerge_pending`, never `S_clu`; single-group `[U]` never enters the branch → byte-identical.
- **Test (GUI-entangled — cannot be pure-headless):** (1) fast arithmetic negative control driving the
  corrected snippet + real `adjust_pending_indices_` via `irc('call', …)`, asserting group 2 becomes
  `[6,8]` after deleting Clu5 (not stale `[7,9]`); (2) full session on a real sorted `.prm`: snapshot
  `cviSpk_clu{3,5,7,9}`, set `cviMerge_pending={[3,5],[7,9]}`, run
  `irc('call','execute_pending_and_update_',{})`, assert survivors = union(orig 3,5) and union(orig
  7,9) — **not** {3∪6}/{8∪10}. Checking `S_clu_assert_synced_`==0 is explicitly **not** sufficient.

### DI-02 🔵 `struct_save_` swallows total save failure
- **Location:** `struct_save_` **irc.m:15174-15204** + duplicate **irc2.m:7016** (fix both); caller
  `save0_` irc.m:13161 (+ ~18 other `irc.m` sites, ~14 in `irc2.m`).
- **Mechanism:** no output arg, never re-throws. 3 failed `save()` retries print "Saving failed" and
  return normally; `save0_`'s `try/catch` can't fire → caller reports success.
- **Repro:** `_jrc.mat` momentarily locked (AV/OneDrive/indexer) during a curation save → 3 red lines
  in a scrolling log → user closes MATLAB → **all unsaved curation lost silently.**
- **Severity:** critical. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix (folds in A1+A2 in one edit):** add `fOk` output; write to `tempname_sibling_`, then
  `atomic_replace_(…, true)` on success (DI-05 for free); on all-retries-failed print a clear
  "NOT updated — previous version preserved." `save0_` checks `fOk`, shows `msgbox_` ("curation only in
  memory — do not close MATLAB"), and **returns without** running `export_prm_` as if saved. `msgbox_`
  already respects `fDebug_ui` so batch runs don't hang. Healthy path unchanged.

### DI-03 🔵 `file2spk_` dimension template from the last (possibly empty) chunk
- **Location:** `file2spk_` **irc.m:18191**; per-chunk assign irc.m:18254, write-through 18256,
  template consume **18285-18287**; `wav2spk_` early-return on empty chunk irc.m:17692 (buffers `[]`
  from 17611).
- **Mechanism:** the post-loop `size()/class()` reads whatever the *last* iteration left. A zero-spike
  final chunk → `dimm_*(1:2)` zeroed even though earlier chunks wrote real waveforms/features. On
  reload `fread(prod([0,0,N]))` = 0 bytes → empty `[0,0,N]`; `spk_pos_` (irc.m:1048) indexes
  `1:nSites_spk` on a 0-length dim → crash discarding the whole run (or, on a tolerant path, a silent
  empty-feature sort).
- **Repro:** any long/multi-file recording whose trailing segment is quiet (post-record rest, blank
  trailing file, low rate).
- **Severity:** high. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** capture a `dimm_*`/`type_*` template from the **first chunk with >0 spikes** and use
  it when the final chunk is empty; `assert(dimm_fet(1)>0 && dimm_fet(2)>0, …)`. **Care:**
  `dimm_raw/spk` can be *legitimately* all-empty when `fSave_spkwav=0` (write_spk_ case-3 guard,
  irc.m:24275-24280) — assert on `dimm_fet` only (features always exist when spikes do), not raw/spk.
- **Test:** two-chunk real `.bin`/`.prm` (chunk 1 has spikes, chunk 2 sub-threshold); `irc('detect')`;
  assert `dimm_raw(1:2)`/`dimm_fet(1:2)` non-zero and a subsequent `irc('sort')` doesn't crash.

### DI-04 🔵 `fread_` silent short-read — expanded: a 4-layer swallow chain
- **Location:** `fread_` **irc.m:5734-5763** + duplicate **irc2.m:6378**; consumers
  `load_spkraw_`/`load_spkwav_`/`load_spkfet_` (irc.m:24129-24166) via `load_bin_` (irc.m:2241-2296).
- **Mechanism + expanded finding:** a short read is silently reshaped to a *smaller valid-looking*
  array → every spike indexes the wrong waveform. **Making `fread_` strict is necessary but not
  sufficient** — the error is re-swallowed up to 3 more times on the way out: `fread_`'s own catch
  (5734) → `load_bin_` catch (2286-2295) → `load_spkraw_` catch (24136-24142) → `get_spkwav_` catch
  (24318-24335). (`load_spkwav_`/`load_spkfet_` have no local catch; `get_spkfet_` calls `load_bin_`
  directly.)
- **Repro:** any partial/interrupted/truncated `.jrc` (i.e. DI-07's output) with authoritative-but-now-
  wrong `dimm` in `_jrc.mat` → silent spike↔waveform **misalignment**.
- **Severity:** high. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** thread `fStrict` (A4, default-off) through `fread_`→`load_bin_`→`load_spk*_`, and
  **narrow the intermediate catches** so a strict error actually surfaces: `load_bin_` `rethrow` when
  `fStrict`; `load_spkraw_`/`get_spkwav_` catches narrowed to only the legit `fSave_spkwav=0`/not-yet-
  detected empties (rethrow real short-reads via `disperr_strict_`). **Constraint:** fix the
  `load_spk*_` callers, **not** the shared `fread_`/`load_bin_` default — `load_file_` (the hot raw
  read, irc.m:1482) must stay lenient.
- **Test:** truncate `_spkwav.jrc` a few KB on a real detected recording (leave `_jrc.mat` `dimm`
  intact); before: `irc('manual')` silently misaligns; after: loads throw a clear short-read error.
  Same script exercises DI-07's failure mode.

---

## Tier 2 — real, narrower trigger / specific conditions

### DI-05 🔵 Non-atomic `_jrc.mat` overwrite
- **Location:** `save0_`→`struct_save_` irc.m:13161 / 15183 (+ irc2.m:7016). **Fully covered by the
  DI-02 edit** (A1 temp+rename). No separate design.
- **Severity:** high. **Confidence:** high. **Scoped fix:** as DI-02. **Test:** pre-create a truncated
  `.tmp` and confirm `atomic_replace_` refuses to commit it, leaving the prior good `_jrc.mat` intact.

### DI-06 🔵 `.prm` read-modify-write truncates the live file on a transient read failure
- **Location:** `file2cellstr_` **irc.m:21820**, `edit_prm_file_` **irc.m:21791**, `cellstr2file_`
  **irc.m:21923**. `edit_prm_file_` is the **only** caller of `file2cellstr_` (grep-confirmed).
- **Mechanism:** `file2cellstr_`'s catch returns `{}` — indistinguishable from empty → the live `.prm`
  is rewritten with only currently-loaded `P` fields, dropping comments/directives.
  **Devil's-advocate refinement:** at the normal `edit_prm_file_(P, P.vcFile_prm)` sites, `P` already
  holds correct values, so the loss is *comments/structure*, not tuned values — the worst case (tuned
  value loss) only manifests chained with DI-15's clobber-before-read pattern.
- **Severity:** high. **Confidence:** med-high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix (two halves, both required):** (1) read-guard — `file2cellstr_` returns `[csLines, fOk]`,
  `fOk=false` on `fid<0`; `edit_prm_file_` `error`s (never truncates) on a bad read. (2) atomic write —
  route `cellstr2file_` through A1. **Do not ship one half without the other** (read-guard alone still
  overwrites non-atomically; atomic-write alone still blanks comments "atomically").
- **Test:** hold the `.prm` open exclusively from a 2nd process, call `edit_prm_file_`, assert it errors
  and the original bytes are unchanged.

### DI-07 🔵 `write_spk_`/`fwrite_` failures discarded during detection
- **Location:** `write_spk_` **irc.m:24252-24292** (fids 24269-24281 unchecked; `fwrite_` calls
  24286-24288 discard the return); `fwrite_` **irc.m:24296-24306**. Callers irc.m:18230/18256/18272,
  29401-29403.
- **Mechanism:** `fopen` unchecked; `fwrite_` swallows into a `fSuccess` the caller ignores; a
  disk-full `fwrite` returns a short count never compared. Run "succeeds" with empty/truncated `.jrc`
  while `_jrc.mat` records in-memory dims (compounds DI-04).
- **Severity:** high. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** guard each `fopen` (`==-1` → error); `fwrite_` compares count to `numel` (A4) and
  returns `fSuccess`; `write_spk_` case-3 returns `fOk`; `file2spk_` aborts the run on a failed write
  (partial-but-committed chunks stay readable). **Devil's-advocate add:** pair with the same bounded
  3× retry-with-pause `struct_save_` already uses before declaring failure — a single AV blip
  shouldn't kill an 8-hour run.
- **Test:** exclusively lock one `.jrc` target from a 2nd process, run `irc('detect')`, assert it errors
  at the `fopen` guard instead of silently writing zero spikes.

### DI-08 🔵 `mn2tn_wav_` per-site catch → phantom zero waveforms + defeats GPU→CPU retry
- **Location:** `mn2tn_wav_` **irc.m:9137-9156** (buffers pre-zeroed 9132-9136; catch 9154-9156);
  outer retry it defeats: `wav2spk_` **irc.m:17704-17712**.
- **Mechanism:** the catch swallows **any** per-site throw, leaving that site's slice at pre-allocated
  **zeros** (real times, zero features → degenerate near-origin spikes) and consuming the exception so
  `wav2spk_`'s GPU→CPU retry never fires.
- **Severity:** medium. **Confidence:** medium. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix — DEVIL'S-ADVOCATE OVERRIDE (do NOT lead with re-throw):** the architect proposed
  `disperr_strict_` re-throw, but this catch runs inside the per-chunk×per-site loop (thousands of
  iterations); an **unconditional re-throw turns one transient hiccup into a total multi-hour-run
  abort** — and worse, a re-thrown *non-GPU* error hits `wav2spk_`'s whole-chunk CPU retry, fails
  identically, and dies uncaught. **Correct default:** (a) *narrow* the catch to genuine GPU errors and
  let those propagate to the existing GPU→CPU retry (that part of the architect design is right); (b)
  for other per-site failures, **do not keep phantom zeros** — drop those spikes and **count** them;
  (c) emit a loud, unmissable **end-of-run summary** of dropped counts and **refuse to let
  `save0_`/`describe` report a clean success** while the drop count is nonzero; (d) escalate to a hard
  abort only if a per-chunk failure **rate** crosses a threshold (systemic, not transient). This trades
  a rare silent corruption for a visible, bounded, recoverable degrade — not a common crash.
- **Test:** inject a per-site throw for one site on one chunk; assert the run finishes, the spikes for
  that site/chunk are dropped (not zero-valued), the end-of-run summary reports the count, and
  `describe`/save won't claim clean success.

### DI-09 🔵 `spikeMerge_` per-site catch drops a whole site's spikes for the chunk
- **Location:** `spikeMerge_` **irc.m:1759-1767** (cells pre-init empty 1742). Live path
  (`spike_refrac_`/`__` dead — call sites 1839/18025 commented out).
- **Mechanism/severity/status:** as DI-08 (a throw → that site contributes zero spikes for the chunk,
  only a `disperr_` print). Medium / medium / NEW.
- **Scoped fix:** same policy as DI-08 — count-and-continue + loud end-of-run summary + block clean
  success + threshold abort. Not an unconditional re-throw.

### DI-10 🔵 GPU CUDA-kernel caches keyed on `nC` only
- **Location:** `cuda_rho_` **irc.m:3114-3155**, `cuda_delta_` 3238, `cuda_rho_drift_` 26996,
  `cuda_delta_drift_` 27025, `cuda_knn_` 26749, `cuda_knn__` 26816, `cuda_delta_knn_` 26903. Reference
  counter-pattern (recompute-every-call): `search_knn_drift_` irc2.m:3731-3789.
- **Mechanism:** `GridSize` recomputed each call from current `P.CHUNK`, but
  `SharedMemorySize`/`ThreadBlockSize` baked in only inside the `nC_ ~= nC` branch using the first
  call's `P.nThreads`/`P.CHUNK`/`nC_max`. Same `nC` + different `nThreads`/`CHUNK` → new-sized grid vs
  old-sized shared memory.
- **Devil's-advocate concession (auditor self-limited correctly):** `irc('clear')` (irc.m:21160) clears
  all persistents and `batch_` (irc.m:5068) calls it before each file — so **only interactive/scripted
  multi-file loops that bypass `batch_`** are exposed.
- **Severity:** high. **Confidence:** high. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** apply `search_knn_drift_`'s shape to all 7 — cache only the `CUDAKernel` construction
  (`isempty(CK) || nC_~=nC`), **reassign `ThreadBlockSize`/`SharedMemorySize`/`GridSize` every call**
  (property assignment, not a recompile — proven safe in production, byte-identical on single-file
  sessions).
- **Test (GPU hardware):** `irc('sort',A)` then `irc('sort',B)` (same `nC`, different `nThreads`/`CHUNK`)
  without `irc('clear')`; assert B matches its `irc('clear')`-isolated baseline.

### DI-11 🔵 `get_spkwav_` global cache has no `vcFile_prm` key
- **Location:** `get_spkwav_` **irc.m:24311-24336** (+ a *different* same-named function irc2.m:4960).
  Reference: `get_spkfet_` irc.m:24341.
- **Mechanism:** invalidates on `isempty()` only; the only thing clearing the globals on a file switch
  is `load_cached_` (irc.m:1130). A caller reaching it without `load_cached_` serves file-A waveforms
  for file-B indices.
- **Devil's-advocate re-rank → confidence medium:** the cited path (`post_merge_drift_`, irc.m:33011)
  is actually reached via `auto_` (irc.m:17147), which calls `load_cached_` first (line 17153); and
  `sort_` populates the globals from this run's own detection. Live exposure requires bypassing both
  command entry points (direct script/console call). Fix still cheap and worth doing.
- **Severity:** high. **Confidence:** medium. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** add `persistent vcFile_prm_` (A3); reload when `P.vcFile_prm` changes. Byte-identical
  on single-file sessions.

### DI-15 🔵 `export-prm` clobbers the target before verify — **total, unrecoverable config loss** *(upgraded)*
- **Location:** `export_prm_` **irc.m:23326-23343** (`copyfile(default_prm, vcFile_out_prm, 'f')` at
  23333 before the patch at 23336). CLI form `irc('export-prm','recording.prm')` (irc.m:190, `vcArg2=''`
  → `vcFile_out_prm == vcFile_prm`).
- **Devil's-advocate upgrade (was "medium/narrow"):** hand-traced the **standalone** form from a fresh
  session (the form the built-in help shows, irc.m:485): `copyfile` clobbers `recording.prm` with the
  bare template → `P = get0_('P')` returns `[]` (empty UserData) → `P = file2struct_(vcFile_prm)` reads
  from the **already-clobbered** file → `edit_prm_file_` patches default values into a default file.
  **The user's probe/channel config/thresholds are permanently gone, unconditionally, with no in-memory
  copy** — not "if the patch throws." This is the natural way to use an export utility.
- **Severity:** **high**. **Confidence:** **high**. **Status:** 🟡 done 2026-07-18 · was NEW.
- **Scoped fix:** build the patched content in a temp (`copyfile → vcFile_tmp`; `edit_prm_file_(P,
  vcFile_tmp)`), then `atomic_replace_` only on success (A1). Also fix the doc/behavior mismatch (help
  implies a `_full.prm` default output the code doesn't apply). **Follow-up:** grep other
  `copyfile(_, 'f')`-then-patch sites for the same same-file collapse.

---

## Tier 3 — robustness gaps / non-default config / dead code / cosmetic

### DI-12 🔵 `field2str_` can't format the MATLAB `string` class — *the error seen 2026-07-18*
- **Location:** `field2str_` **irc.m:21864-21918** (`otherwise` 21899-21902) + duplicate **irc2.m:9236**
  (same `otherwise` bug at irc2.m:9273 — fix both for consistency). Reached via
  `save0_`→`export_prm_`→`edit_prm_file_`.
- **Impact:** the `_jrc.mat` save **completed before** this ran; only the throwaway `_full.prm` gets one
  blank line. **No sorting data touched.** Cosmetic.
- **Scoped fix:** `case 'string', vcStr = field2str_(char(val), fDoubleQuote); return;` before
  `otherwise`; optionally coerce `string`→`char` at `loadParam_`.

### DI-13 🔵 No `fclose` cleanup on mid-detection exception; unbuffered `'W'` handles
- **Location:** detection loop **irc.m:18230-18272** (no try/catch around `wav2spk_`/`write_spk_`); no
  `fclose('all')` in `irc.m`; `'W'` fids irc.m:24269-24271, 2215, 6966.
- **Mechanism:** a throw before the 0-arg cleanup leaves the three `.jrc` handles open; `'W'` skips
  auto-flush → buffered spike data at risk + files locked for the session.
- **Severity:** low-med. **Confidence:** medium. **Scoped fix:** guard the open fids with `onCleanup`
  (flush+close deterministically on any exit). Care: touches a hot loop's control flow.

### DI-14 🔵 irc2 stale-lock never cleared + check-then-act lock race (TOCTOU)
- **Location:** `waitfor_lock_`/`lock_dir_` **irc2.m:446-482**; consumers `detect_cache_`/`sort_cache_`
  irc2.m:315-391.
- **Mechanism:** a crashed process leaves the lock forever → every later cached run stalls 1 h then
  proceeds anyway; check-then-act create lets two processes both compute + `struct_save_` to the same
  cache concurrently.
- **Severity:** medium. **Confidence:** medium. **Scoped fix:** atomic `mkdir` **lock directory**
  (atomic on all FSes; MATLAB has no `O_EXCL` for files); on timeout, delete the stale lock (with a
  warning) rather than proceeding while it exists. Distinct primitive from A1-A3.

### DI-16 🔵 `wav_car_` int16 saturating sum corrupts the CAR reference *(severity → low-med)*
- **Location:** `wav_car_` **irc.m:5109-5124** (`sum(int16 …)` 5112/5119, author-flagged "may go out of
  range").
- **Devil's-advocate re-rank:** requires **two** non-default settings at once —
  `vcCommonRef∈{'tmean','nmean'}` (default `'none'`; these two aren't even listed in default.prm:72) +
  `vcDataType_filter='int16'` (default `'single'`). Real mechanism, narrow trigger → low-med.
- **Scoped fix:** `sum(single(mnWav2(:,viChan_keep)), 2)` before dividing (trivially safe).

### DI-17 🔵 int32 saturation for untransposed >~20 h recordings
- **Location:** `mr2tr_` **irc.m:13502** (`int32(viTime0)+int32(viTime)`), enabled by `plan_load_`
  disabling chunking when `~P.fTranspose_bin` (irc.m:1387-1388).
- **Mechanism:** `int32()` saturates; an untransposed single-block file >~2.147×10⁹ samples (~19.9 h @
  30 kHz) collides all later spike times at the clamp. Very narrow.
- **Severity:** low. **Confidence:** low-med. **Scoped fix:** `int64` for `miRange` (precedent:
  `spikeMerge_` irc.m:1740), or force chunking for untransposed.

### DI-18 🔵 `post_merge_mode` array → hard crash; no validation/coercion *(quick win)*
- **Location:** `post_merge_` switch **irc.m:3956**. **Already hit in production** (`MEMORY.md`:
  "post_merge_mode must be scalar").
- **Mechanism:** an array-valued `post_merge_mode` (copy-paste from array-capable `post_merge_mode0`)
  throws `SWITCH expression must be a scalar or char vector`, crashing before auto-merge. A **crash**
  (self-announcing, nothing saved), not silent corruption.
- **Severity:** low. **Confidence:** high. **Scoped fix:** one line — `if numel(post_merge_mode)>1,
  post_merge_mode = post_merge_mode(1); end` (or coerce in `loadParam_`). Zero interaction risk → do it
  alongside DI-12.

### DI-19 🔵 `sgfilt4_`/`sgfilt_init_` cache key omits `fGpu`
- **Location:** **irc.m:3860 / 3886** (rebuild keyed on `n1`/`nData`/`nFilt` only). Callers `filt_car_`.
- **Mechanism:** same dims + flipped `fGpu` returns cached CPU/GPU arrays → device-location mismatch.
  `fGpu` constant within a file → cross-session risk only.
- **Severity:** low-med. **Scoped fix:** add `fGpu` to the rebuild condition (A3).

### DI-20 🔵 `S_clu_wav_pair_` `viT` window cache never invalidates; reset path dead
- **Location:** **irc.m:18392** (`persistent viT`; zero-arg reset hook has **no call sites**).
- **Mechanism:** `viT` derived from `spkLim_raw`/`spkLim_factor_merge` once per process; two `.prm` with
  different windows in one session apply the wrong window to merge-*preview* comparisons.
- **Severity:** medium (preview only, not persisted). **Scoped fix:** key `viT` on those params (A3), or
  recompute each call (cheap).

### DI-21 🔵 Dead-code unkeyed caches
- **Location:** `fid_fet_cache_` **irc2.m:4140** (set/clear commented out 4368/4391);
  `fread_spkwav_`/`fread_spkraw_` **irc.m:24171/24204** (no call sites). Same "no key beyond isempty"
  defect as DI-11 — currently **dead**, no live risk.
- **Severity:** low. **Scoped fix:** add a `%WARNING: unkeyed cache — see DI-11 before reactivating`
  comment at each `persistent` (do **not** delete — no-delete rule).

### DI-22 🔵 `readmda_paged_` file-handle leak on file switch
- **Location:** **irc2.m:5213**.
- **Mechanism:** a new `P` re-inits safely (no stale content) but the previous `fid` isn't closed unless
  the caller first calls `readmda_paged_('close')` → handle leak (resource, not correctness).
- **Severity:** low. **Scoped fix:** close the old `fid` in the new-file branch.

---

## C. Build / sequencing plan

**Phase 0 — foundation (pure additions, zero existing call-site changes; land + `checkcode` first):**
`tempname_sibling_`/`atomic_replace_` (A1); `disperr_strict_` (A2); `fStrict` params on
`fread_`/`fwrite_` (A4, default-off).

**Phase 1 — DI-01** (independent, smallest, highest payoff — ship alone).

**Phase 2 — save integrity (needs A1): DI-02+DI-05 together** (`struct_save_` in **both** files + `save0_`
check). Splitting them leaves a half-migrated status/atomicity.

**Phase 3 — `.prm` integrity (needs A1): DI-06 read-guard + write-atomicity together**; DI-15 folds in
here (one-line reuse of A1).

**Phase 4 — detection write/reload triangle:** DI-07 (write side) → DI-04 (read side, whole swallow
chain) → DI-03 (same `file2spk_`, same PR). Compounding; sequence within the phase.

**Phase 5 — cache keys (independent, any order):** DI-11, DI-19, DI-20 (A3); DI-10 (GPU-hardware test);
DI-21 (comment-only).

**Phase 6 — Tier-3 remainder:** DI-08/09 (count-and-continue policy), DI-12, DI-13, DI-14, DI-16, DI-17,
DI-18, DI-22 — opportunistic.

**Must NOT ship half-migrated:** (a) `fOk` on `struct_save_` without `save0_` checking it; (b) strict
`fread_` without narrowing the intermediate `load_bin_`/`load_spkraw_`/`get_spkwav_` catches (else a
no-op); (c) either half of DI-06 alone; (d) a fix to a duplicated function in only one of `irc.m`/`irc2.m`.

## E. CLAUDE.md constraint & ripple notes
- No fix deletes a function or changes healthy-path behavior (per-item "regression risk" notes).
- Duplicated (not shared): `struct_save_`, `fread_`, `field2str_`, `cellstr2file_` — fix both copies.
  Delegating stubs (free via `irc.m`): `disperr_`, `edit_prm_file_`.
- Adding outputs to void functions (`struct_save_`, `write_spk_`, `file2cellstr_`) is additive — but
  grep each (~15-30 call sites) at implementation time to confirm none already assign the result.
- `get_spkwav_`'s narrowed catch (DI-04) is the one place a genuinely *behavioral* change occurs on an
  **unhealthy** path (thrown error instead of `[]`): keep the catch but make it conditional (swallow
  `fSave_spkwav=0` empties, rethrow real short-reads). Callers that currently tolerate `[]` will see an
  exception on that error path — intended, but flag it.
- DI-01's reconcile introduces a **new possible loud crash** (later group shrinks below 2 → outer loop
  indexes past the shortened cell) — the correct crash-vs-silent-corruption trade (P3b), called out
  explicitly, not silently absorbed.

---

## Appendix A — verified fixed (re-confirmed present in current code, 2026-07-18)

| CID | Verified at |
|---|---|
| CID-01 `reorder_clu_by_coords_` remaps `viClu` before `S_clu_select_` | irc.m:10631-10651 |
| CID-03 `split_clu_` `iClu2 = max(nClu, max(viClu))+1` | irc.m:10930-10935 |
| CID-04 `get_clu_spk_confirmed_` falls back to `viClu` | irc.m:10080-10120 |
| CID-06 `S_clu_assert_synced_` (warn-only, `fCheck_clu_sync`) | irc.m:20167-20234; called 10654-10657, 20238-20249 |
| CID-07 `delete_clu_` content-based rollback | irc.m:9242-9318 |
| CID-08 `merge_clu_` whole-merge rollback | irc.m:9465-9517 |
| CID-09 `post_merge_wav_` init + early return moved | irc.m:4343-4357 |
| CID-11 `struct_select_safe_` `csCritical` re-throw for `cviSpk_clu` | irc.m:19953-20016 |
| P2 `fOk` gated at every call site | irc.m:9192-9224, 9411-9461, 9757-9777, 19844-19858 |
| Cross-shank guard (Hooks A/B/C + 11 automated `ml2map_` sites) | 9663-9676, 9474-9486, 9811-9830, 16262-16326 |

`clu_reorder_`, `merge_clu_pair_`, `S_clu_update_`, `S_clu_refresh_`/`_remove_empty_`/`_keep_`,
`S_clu_map_index_`, `S_clu_wavcor_merge_` all follow the correct "remap `viClu` first, rebuild cache
after" idiom — no desync found.

## Appendix B — checked and safe (do not re-flag)

- `get_spkfet_` (irc.m:24341) — keyed on `P.vcFile_prm` + dim check; the reference pattern.
- `load_cached_` (irc.m:1130) — correct global-cache gatekeeper (clears globals on file mismatch);
  guards DI-11's cited path via `auto_`.
- `set0_`/`get0_` (irc.m:21941/21719) — `set0_` overlays named fields onto a freshly re-read S0.
- `read_cfg_`/`loadParam_` (irc.m:845/1559) — stateless, re-read each call.
- `get_tag_`/`get_fig_cache_` (irc.m:12645/12667) — self-healing, cleared on GUI entry.
- `get_screensize_` (irc.m:12428) — content-based invalidation.
- Chunk-boundary spike dedup in `wav2spk_` (irc.m:17687-17691) — correct pre/post-pad handoff.
- `spikeMerge_` `int64(viSpk)` (irc.m:1740) — already hardened vs long-recording int32 overflow.
- irc2 `search_knn_drift_`/`search_delta_drift_` (irc2.m:3729/3793) — reassign kernel dims every call
  (the pattern DI-10 should adopt).
- `irc('clear')` (irc.m:21160) + `batch_` (irc.m:5068) — clears all persistents between files,
  limiting DI-10's exposure to loops that bypass `batch_`.

---

## Review log

- **2026-07-18 audit** — four read-only agents (persistence · cluster-identity · detect/feature ·
  cache). All 22 findings new vs the CID desync family.
- **2026-07-18 code-architect review** — designed shared infra (A1-A4); found `irc.m`/`irc2.m`
  duplication; **corrected DI-01's fix** (concatenation, not range-assign, else it throws); expanded
  DI-04 to the 4-layer swallow chain; per-issue solution + test designs; build sequence; priority table.
- **2026-07-18 devil's-advocate review** — independently re-traced and **confirmed DI-01**; **upgraded
  DI-15 to high/high** (total unrecoverable config loss in standalone CLI); **overrode DI-08/09 fix**
  (count-and-continue, not blanket re-throw — the latter would abort multi-hour runs); scoped DI-04 to
  `load_spk*_` (keep shared `fread_` lenient); re-ranked DI-11 (→medium, path guarded), DI-16 (→low-med),
  DI-18 (→quick-win). Conceded DI-10's self-limiting scope.

*No source files modified — documentation + design only. Related:
[`ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md), `CLAUDE.md`.*
