# Issue Tracker — cluster-identity / dual-state integrity

**Scope:** the `S_clu.viClu` ⇄ `S_clu.cviSpk_clu` desync family and everything found while
chasing it (2026‑06‑25 → 2026‑07‑16). One tracker for the whole saga; deep dives live in the
linked docs.

**Theme.** IronClust stores the spike→cluster assignment twice — `viClu` (per‑**spike** labels,
authoritative) and `cviSpk_clu` (per‑**cluster** spike-index cache, derived). Several GUI paths
updated one and not the other, silently, and saved the result. The invariant that ties them:

> `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for every `i`.

**Legend.** ✅ fixed & committed · 🟡 fixed, uncommitted · 🔵 open/deferred · ⚪ not‑a‑bug ·
⛔ retracted claim

---

## Index

| ID | Title | Severity | Status | Commit |
|---|---|---|---|---|
| **CID‑01** | `reorder_clu_by_coords_` (`[O]`) desyncs `viClu` from the cache, then saves | critical | ✅ | `87cd4f1` |
| **CID‑02** | drift‑view `[S]` polygon drawn on `gca`, data read from `SelectedTab` axes | high | ✅ | `87cd4f1` |
| **CID‑03** | `split_clu_` uses `max(viClu)+1` → can silently revert the whole split | high | ✅ | `87cd4f1` |
| **CID‑04** | `get_clu_spk_confirmed_` fallback returns the wrong (cache) side | medium | ✅ | `87cd4f1` |
| **CID‑05** | FigProj shows 50 random dots but splits all N | medium | ✅ | `87cd4f1` |
| **CID‑06** | no desync detection anywhere (`S_clu_valid_` checks lengths only) | high | ✅ | `87cd4f1` |
| **CID‑07** | `delete_clu_` — same desync bug; remaps `viClu` even when cache remap fails | critical | ✅ | `d954926` |
| **CID‑08** | `merge_clu_` — a `delete_clu_` abort leaves a half‑applied, falsely‑logged merge | medium | ✅ | `d954926` |
| **CID‑09** | `post_merge_wav_` early return — unassigned output + `mrWavCor` stripped | high (latent) | ✅ | `d954926` |
| **CID‑10** | parpool undersize‑reuse — stale small pool silently reused | low | ✅ | `d954926` |
| **CID‑11** | `struct_select_safe_` skips silently **and** the length‑reconcile block falsifies lengths | high (enabler) | ✅ | `d372eac` |
| **CID‑12** | corrupted `_jrc.mat` on disk — **not recoverable**, re‑sort required | data‑loss | 🔵 | `83776fc` (tool) |
| **CID‑13** | `maxSpk_persite_clust = 20000` → 69.5% of spikes 1‑NN‑propagated, not clustered | advisory | 🔵 | — |
| **CID‑14** | `P.viShank_site` all `1`s on a 4‑shank Neuropixels 2.0 probe | medium | ✅ | *(generator, ext repo)* |
| **CID‑15** | `viClu_prematch` — 68 MB per‑spike copy persisted for no reason | trivial | ✅ | `525b8f5` |

**Prior related work (context, pre‑saga):** `ea6a8dc` GUI Merge‑auto sign bug (6/26) ·
`0f2ab3f` post‑merge/per‑site empty‑cluster hardening (6/26) · `97b69f8` per‑site cap
introduced (6/25) · `4f81aaa` worker clamp (6/25) · `45b5333` **failed** attempt at CID‑04's
symptom (7/10, see CID‑04).

---

## Issues

### CID‑01 ✅ `reorder_clu_by_coords_` (`[O]`) desyncs `viClu`, then saves — THE ROOT CAUSE
- **Symptom (user‑reported):** (A) splitting a tiny unit yields two units with **thousands** of
  spikes; (B) splitting a unit in a narrow depth band yields two units **hundreds of µm apart**.
  On freshly‑sorted data, across three split paths (auto‑split, FigTime `[S]`, drift‑view `[S]`).
- **Root cause:** `reorder_clu_by_coords_` (bound to `[O]`) sorts clusters by position and applies
  the permutation with `S_clu_select_`, which reindexes every `*_clu` field **but not `viClu`**
  (its name ends in `Clu`, not `_clu`). The caller must remap `viClu` itself; this one didn't,
  then called `save0_()`. After one `[O]`, `cviSpk_clu{i}` and `find(viClu==i)` describe different
  neurons. `split_clu_`→`S_clu_update_` rebuilds from the stale `viClu` → both symptoms.
- **Why all three paths:** `S_clu_update_` is common to every split path — one cause, three
  symptoms, on a fresh sort.
- **Fix:** remap `viClu` in lockstep before `S_clu_select_` (mirrors `clu_reorder_`); refuse to
  reorder if `numel(viMap_clu) ≠ nClu`. Added a CONTRACT comment on `S_clu_select_`.
- **Verified:** negative control (`scratchpad/verify_reorder.m`) — invariant breaks without the
  remap, holds with it; `int32` preserved; unassigned spikes untouched.
- **Detail:** `logs/investigation_split_root_cause.md`, `logs/issue_viclu_desync_20260715.md`.

### CID‑02 ✅ drift‑view `[S]` polygon on `gca`, data from `SelectedTab` axes
- **Symptom:** same A/B symptoms, drift‑view path only.
- **Root cause:** `show_drift_view.m` drew the polygon with `impoly_()` (→ `gca`) while reading
  spike data from `hAx = SelectedTab.Children(1)`. The two tabs' axes share an identical
  `Position`, so the divergence is invisible; on the Y‑tab the polygon degenerates into a
  time‑band selection across the full depth extent.
- **Fix:** `impoly_(hAx)`; explicit parent for `hSplit`. Routed `[S]` through
  `split_clu_by_id_`.
- **Caveat:** not exercisable headlessly (`impoly_` blocks); traced + syntax‑checked only.

### CID‑03 ✅ `split_clu_` silent revert via `max(viClu)+1`
- **Root cause:** new child id was `max(S_clu.viClu)+1`. With trailing empty clusters this
  clobbers a live index and shrinks `nClu` → `S_clu_valid_` fails → `S_clu_commit_` **silently
  reverts** the whole split (console‑only message).
- **Fix:** `iClu2 = max(nClu, max(viClu)) + 1`.
- **Verified:** old code returns live index 5 on the fixture; fixed returns 8.

### CID‑04 ✅ `get_clu_spk_confirmed_` fallback returns the wrong side — *and why `45b5333` failed*
- **Root cause:** on total `viClu`↔cache disagreement the helper returned the raw **cache**;
  `viClu` is authoritative.
- **History:** `45b5333` (7/10, *"cluster split could balloon a tiny cluster to thousands"*) tried
  to fix this exact symptom with the guard `any(vlConfirmed) && ~all(vlConfirmed)` — which can only
  **shrink** an over‑large cache and is a **no‑op against an under‑count**. It did not work. This is
  the second failed attempt in the saga (see also CID‑01's misdiagnoses in *Retractions*).
- **Fix:** fall back to `find(viClu==iClu1)` with a loud message.

### CID‑05 ✅ FigProj 50 dots, splits all N
- **Root cause:** `fet2proj_` random‑subsamples to `nShow_proj` (50) for display but never returns
  `viSpk01`, so `plot_split_` runs `inpolygon` over the full cluster. FigProj was also dead code in
  this fork.
- **Fix:** `fet2proj_` returns `viSpk01`; FigProj restored as opt‑in (View ▸ Show projection view).

### CID‑06 ✅ no desync detection — `S_clu_assert_synced_`
- **Gap:** `S_clu_valid_` compares array **lengths** to `nClu` only; a total content desync passes.
- **Fix:** new `S_clu_assert_synced_`, called from `S_clu_commit_`, gated by `fCheck_clu_sync`
  (default 1). Reports `nForeign` and `nMiss` **separately**. **Warns, never gates** — because
  `S_clu_commit_` reverts on `~valid`, so gating would reproduce the silent data loss.
- **Field use:** flagged 4/4 deliberately‑corrupted fixtures; **0/547 on the fresh re‑sort** (Test B).
- **Detection coverage extended (hardening, 2026‑07‑16, plan P1/P3a):** the detector originally ran
  **only** at the `S_clu_commit_` choke point, so a corrupted file opened silently and the `[O]`
  path (which `save0_()`s directly, bypassing commit) was never checked. Now also runs in **`load0_`**
  (announces a disk desync at open time → points to CID‑12 recovery) and in
  **`reorder_clu_by_coords_`** (the `[O]` path — the exact path CID‑01 lived on). Both warn‑only,
  additive. Verified: `scratchpad/verify_p1_p3a.m` 4/4. See `logs/changes_log20260716.md`.

### CID‑07 ✅ `delete_clu_` — same desync bug, now atomic
- **Root cause:** remapped `viClu` **unconditionally** while its cache remap sat in a `try/catch`
  that only printed — and the catch **cannot fire**, because `S_clu_select_`→`struct_select_safe_`
  swallows a per‑field failure and returns normally (see CID‑11). `S_clu_valid_` (lengths) then
  passes. Direct evidence: **7,172 deleted spikes found inside live cache entries** on the old file.
- **Second‑order effect:** picks victims via `ismember(viClu, viClu_delete)`, so on an
  already‑desynced file the user deletes what the GUI shows (the cache's cluster) while the code
  marks negative whatever `viClu` says — **each delete compounds the damage into a new cluster.**
  This is why the on‑disk corruption became cumulative and irreversible (CID‑12).
- **Fix:** snapshot `S_clu`; verify the cache was **actually permuted** (content:
  `isequal(new_cache, prev_cache(viClu_keep))`, *not* length — see CID‑11); roll back on failure.
- **Verified:** `scratchpad/verify_delete_clu.m` 7/7 — negative control reproduces the desync
  (2 clusters), fix leaves 0, rollback byte‑identical, happy path still deletes (5→4).

### CID‑08 ✅ `merge_clu_` — half‑applied, falsely‑logged merge
- **Root cause:** `delete_clu_` is the back half of every merge. Its new abort would leave the
  merge half‑applied (spikes moved, source survives empty) while `ui_merge_clu_` calls
  `save_log_('merge i j')` **unconditionally** — logging a merge that didn't finish.
- **Fix:** `merge_clu_` snapshots and rolls the **whole merge** back on a `delete_clu_` abort.
- **Honest scope:** **defence‑in‑depth, probably unreachable today.** A cache bad enough to fail
  `S_clu_select_` also fails `S_clu_wav_` *first*, so `merge_clu_` throws before reaching
  `delete_clu_` — and that throw is already safe (caller's `S0.S_clu = merge_clu_(...)` assignment
  never runs). Kept because `delete_clu_`'s abort returns *normally*, not by throwing. Cost: one
  transient `S_clu` copy per merge (~250–500 MB at 17.6M spikes).
- **Verified on REAL data:** `scratchpad/verify_merge_clu_real.m` 5/5 (read‑only) — real merge
  547→546, **0 stale**; malformed cache fails loudly, caller byte‑identical. (155,204+367,046 →
  **511,712**, not 522,250: `S_clu_refrac_` correctly drops 10,538 ISI violators.)

### CID‑09 ✅ `post_merge_wav_` early return — crash + cache destruction
- **Root cause:** 4286 strips `mrWavCor`/`trWav_raw_clu`/`tmrWav_raw_clu`; 4287 returns early when
  `fSave_spkwav=0` — **before** the rebuild that restores them. Signature is `[S_clu, nClu_merge]`
  and `auto_merge_` requests **both** outputs with `fMerge=1`, so `nClu_merge` unassigned → *"Output
  argument not assigned"*. Dormant only because this user runs `fSave_spkwav=1`.
- **Fix:** `nClu_merge = 0` on entry; move the early return **before** the `rmfield_` (true no‑op).
- **Verified:** `scratchpad/verify_post_merge_wav.m` 6/6.

### CID‑10 ✅ parpool undersize‑reuse
- **Root cause:** `elseif hPool.NumWorkers > nWorkers` only **shrank** an oversized pool; a
  pre‑existing undersized pool was reused as‑is (observed: 3 workers when the profile allows 8 and
  `.prm` asks for 12).
- **Fix:** `~= nWorkers` — resizes either direction and logs it. No‑op for a correctly‑sized pool.

### CID‑11 ✅ `struct_select_safe_` silent skip + length‑reconcile falsifies lengths *(the enabler)*
- **Two compounding mechanisms:**
  1. `struct_select_safe_` resizes each field independently and **skips a field it
     can't resize with a console warning, returning normally** — no exception propagates.
  2. `S_clu_select_`'s length‑reconcile block then force‑fits any wrong‑length
     `v*_clu`/`c*_clu` field to `nClu_new`, **padding `cviSpk_clu` with `{[]}`**.
- **Consequence:** after a skip, the length is right and the **content is wrong**. This is why
  `S_clu_valid_` is vacuous and why a length‑based guard in `delete_clu_` **silently failed** —
  caught only by the negative control (see *Retractions*).
- **Fix (hardening P3b, 2026‑07‑16):** `struct_select_safe_` gains an optional `csCritical` list;
  a critical field that throws **re‑throws** instead of being skipped. `S_clu_select_`'s c‑group
  call marks `cviSpk_clu` critical. `delete_clu_`'s try/catch turns the re‑throw into a clean
  rollback; the four non‑guarded callers (`S_clu_remove_empty_`, `S_clu_keep_`, `clu_reorder_`,
  `reorder_clu_by_coords_`) would now **crash** rather than silently corrupt — a deliberate
  crash‑vs‑silent‑corruption trade (user‑approved), and the sweep shows they run on consistent
  state where it never fires. Reconcile‑block mechanism (2) left intact; mechanism (1) is now
  closed for the identity‑bearing field.
- **Verified:** `scratchpad/verify_p3b.m` 3/3 — healthy unaffected, malformed re‑throws (pre‑P3b
  returned padded), `delete_clu_` still rolls back byte‑identical. See `logs/changes_log20260716.md`.

### CID‑12 🔵 corrupted `_jrc.mat` on disk — NOT recoverable
- **Measured** (old files): `_IRC_jrc.mat` 179/190 desynced; `_irc_all_jrc.mat` 504/544, 247 delete
  ops, 37% unassigned.
- **Recovery refuted.** The σ‑recovery model (cache and `viClu` = same partition relabelled) is
  false: **52/190 cache entries span >1 `viClu` label** (max 14) → different partitions, no σ.
  Dry‑run confirms: 557,123 spikes claimed by >1 cluster, 413,533 orphaned, 7,172 deletions
  resurrected. Cause: the damage **compounded** (CID‑07) — cumulative and order‑dependent, so no
  single transform inverts it.
- **Tool:** `matlab/repair_clu_sync.m` — dry‑run by default, refuses to write on this data (5
  blocking reasons), retained for diagnostics. **Do not trust its repair path.**
- **Resolution:** re‑sort. The sort pipeline is clean (Test B: 0/547 stale on the fresh output).
  `_IRC_jrc.mat` was **not** re‑sorted and remains corrupt.

### CID‑13 🔵 `maxSpk_persite_clust = 20000` — most spikes propagated, not clustered
- **Measured on the fresh sort:** 192/384 sites over the cap (91.3% of spikes); **30.5% clustered,
  69.5% 1‑NN‑propagated**; on the busiest site (586,951 spikes) only **3.4%** clustered.
- **Not a defect** — documented cap behaviour — but it means a small unit on a busy site is only
  found if it lands enough spikes in the 20k subsample. Connects to the original "very few spikes"
  report. `default.prm` recommends **50000–100000**; this run used 20000. Parameter choice.

### CID‑14 ✅ `P.viShank_site` all `1`s on a 4‑shank probe — fixed in the generator (X4, 2026‑07‑16)
- Neuropixels 2.0 (`NP2013 → np2_4s`) is 4 shanks × 2 columns, but the probe declared a single
  shank. IronClust defaults `viShank_site` to all `1`s when the `.prb` has no `shank` field
  (`load_prb_`, irc.m:2038), collapsing the drift‑view per‑shank filter and `[O]` sort semantics.
- **Root cause:** the `.prb` generator `SGLXMetaToCoords_PAG.py` (`writePRBFile`) omitted the
  `shank` field, though the sibling Kilosort export wrote `kcoords = shankInd + 1` from the same
  `.ap.meta` `snsGeomMap`.
- **Fix (external repo, per user's "do not edit existing `.prb` files"):** `writePRBFile` now emits a
  1‑based `shank` array trimmed by the same `remove_idx`. Verified end‑to‑end (generator → IronClust
  `load_prb_`): full probe → `{1,2,3,4}` (96 each); afm17313 "join_tips" PAG subset → `{1,4}`
  (200+14), matching meta `shankInd+1`. Existing `.prb` files untouched (regenerate to apply). See
  `logs/changes_log20260716.md` X4. Sibling generators still carry the same omission.
- **⚠ Activation blocker (2026‑07‑17):** regenerating / pointing `probe_file` at a shank‑bearing
  `.prb` is **not sufficient** on an existing `.prm`. `loadParam_` re‑reads the `.prb` (irc.m:1599)
  then `struct_merge_(P0, P)` (irc.m:1603) lets the **`.prm`** win (irc.m:20848), so a baked
  `viShank_site = [1,1,…]` line in the `.prm` overrides the probe on every load. **Fix:** comment
  out / delete that `.prm` line so the `.prb` shanks survive the merge. Proven via
  `irc('call','loadParam_',{prm})`: line present → `unique(viShank_site)=1`; removed → `[1 2 3 4]`×96.
  This is what *activates* the shank‑aware `[O]` reorder (`80a5901`). See `logs/changes_log20260717.md` §3.

### CID‑15 ✅ `viClu_prematch` — cleaned up (X1, 2026‑07‑16)
- Set/read on adjacent lines — transient, always fresh at use. Not a correctness bug, but it was a
  per‑spike copy (~68 MB) persisted into every `_jrc.mat` for no reason.
- **Fix (X1):** made it a **local** variable in the template‑match step instead of an `S_clu` field,
  so it never reaches the save path. `frac_changed` byte‑identical. `checkcode` clean; committed `525b8f5`.

---

## Timeline

| Date | Event |
|---|---|
| 2026‑06‑25 | `97b69f8` per‑site cap (CID‑13 origin); `4f81aaa` worker clamp (CID‑10 area) |
| 2026‑06‑26 | `0f2ab3f` empty‑cluster hardening; `ea6a8dc` GUI Merge‑auto sign bug |
| 2026‑07‑10 | `45b5333` **failed** fix of CID‑04's symptom (wrong direction — no‑op) |
| 2026‑07‑14 | bug re‑reported (tiny‑unit balloon + depth jump); investigation opens |
| 2026‑07‑15 | first diagnosis (positional mask) **refuted**; CID‑01 found & confirmed; `87cd4f1` ships CID‑01…06; measured the on‑disk corruption; recovery attempted and **refuted**; `83776fc` ships the investigation + `repair_clu_sync.m` |
| 2026‑07‑16 | CID‑07…10 fixed & verified; clustering‑method audit (CID‑13 measured); this tracker created. Re‑sort of `_irc_all.prm` completed clean (Test B, 0/547) |
| 2026‑07‑16 | hardening pass begins (plan `plan_cluster_identity_hardening_20260716.md`): **P1** load‑time detection + **P3a** `[O]`‑path detection landed (extend CID‑06), verified 4/4; P2/P3b pending user decisions |
| 2026‑07‑16 | hardening pass completes: **P2** abort‑propagation (explicit `fOk`, all 4 call‑site groups; `verify_p2.m` 4/4), **P3b** `cviSpk_clu` critical field (closes CID‑11; `verify_p3b.m` 3/3), **X3** `split_clu_` truncate/pad hard‑fail. CID‑07…10 marked committed (`d954926`). P2/P3b/X3 committed `d372eac`; X1 `525b8f5` |

---

## Retractions & methodological record

Kept deliberately — the *pattern* is the lesson: a model that fit the sampled evidence was stated
as established fact. Each was caught by a disconfirming test, not by inspection.

| # | Claim | How it fell |
|---|---|---|
| R1 | "positional‑mask truncation is the cause" | refuted by arithmetic (that path can only shrink a selection); the proposed fix was cosmetic |
| R2 | "`[O]` is confirmed the trigger, the last link is closed" | asked *"do you press `[O]`?"* (unfalsifiable) instead of *"does it happen **before** `[O]`?"* |
| R3 | "nothing is committed" | reported memory as fact; `git status` showed it was committed **and pushed** |
| R4 | "the curation is recoverable — do not re‑sort" | generalised from 4 sampled cache entries to 544; the dry‑run refuted it (CID‑12) |
| R5 | "the cache is authoritative" (direction check) | **circular** — every compared field derives from the cache; the check reports 100% on a cache with 557k overlaps and a 14‑label entry |
| R6 | length‑based guard in `delete_clu_` (`numel==numel`) | the reconcile block (CID‑11) falsifies lengths; the negative control caught it → replaced with a content check |

Also: three **test harness** bugs (not code bugs) were caught and fixed this saga — a regex
counting matches inside comments (FigProj), a two‑output `irc('call',…)` misuse (`post_merge_wav_`),
and an exact‑sum spike‑count assertion that ignored `S_clu_refrac_` (`merge_clu_`). Lesson: verify
the harness with a negative control before trusting a pass.

---

## Verification assets (`scratchpad/`, not committed)

| Script | Covers | Result |
|---|---|---|
| `verify_reorder.m` | CID‑01 | invariant breaks w/o remap, holds with |
| `verify_delete_clu.m` | CID‑07 | 7/7 |
| `verify_merge_clu_real.m` | CID‑08 (real data, read‑only) | 5/5 |
| `verify_post_merge_wav.m` | CID‑09 | 6/6 |
| `check_cap_impact.m` | CID‑13 | 69.5% propagated |
| `which_side_authoritative.m`, `prove_shift.m` | CID‑12 evidence | — |
| `verify_p1_p3a.m` | P1 (load0_) + P3a ([O]) detection | 4/4 |
| `verify_p2.m` | P2 (`delete_clu_`/`merge_clu_` `fOk` abort contract) | 4/4 |
| `verify_p3b.m` | P3b (`cviSpk_clu` critical field re‑throw) | 3/3 |

---

## Reference documents

- **`logs/ISSUE_TRACKER_cluster_identity.md`** — this file (index + status of all issues)
- **`logs/issue_viclu_desync_20260715.md`** — full bug report: what/how/why/fix per issue
- **`logs/investigation_split_root_cause.md`** — the raw investigation, measurements, retractions
- **`logs/changes_log20260715.md`** — dated changelog for `87cd4f1`, `83776fc`, and the 7/16 fixes
- **`matlab/CLAUDE.md`** — the durable invariant + "never trust a length check on `S_clu`" note
- **`matlab/repair_clu_sync.m`** — diagnostic/repair tool (dry‑run default; refuses on this data)
