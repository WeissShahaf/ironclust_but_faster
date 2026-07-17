# Changes Log - July 17, 2026

> **Tracker:** [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md)
> **Plan:** [`logs/plan_reorder_shank_aware_20260717.md`](plan_reorder_shank_aware_20260717.md)

## Summary

Two improvements surfaced while auditing the per-site clustering and `[O]` curation paths on the
`260324_afm18349` Neuropixels 2.0 recording (17.6M spikes, 384 sites, `vcCluster='kmeans'`):

1. **Shank-aware `[O]` reorder** (code, `irc.m`) — landed, reviewed, verified. Commit `80a5901`.
2. **Per-site cap 100k → 200k + `fParfor=0`** (parameters on the recording's `.prm`, not repo code).

Plus a **CID-14 activation finding**: pointing `probe_file` at a shank-bearing `.prb` is **not
enough** to activate shanks — the `.prm`'s baked `viShank_site` overrides it. Documented below and
folded into CID-14.

---

## 1. Shank-aware `[O]` reorder (`reorder_clu_by_coords_`) — DONE (`80a5901`)

**Problem.** `[O]` sorted clusters by `sortrows([X, Y])`. On a multi-shank probe that groups by
exact X (all of a shank's first column, then its second) instead of ordering each shank by depth.

**Change (key block only, `irc.m:~10494-10520`).** When the probe declares >1 real shank, sort by
**shank → Y (depth) → X**; otherwise fall back to the original X-then-Y, verbatim.

```matlab
viShank_site = get_(P, 'viShank_site');
fShankSort_clu = ~isSingleShank_(P) ...
    && isfield(S_clu, 'viSite_clu') && numel(S_clu.viSite_clu) == S_clu.nClu ...
    && numel(S_clu.vrPosX_clu) == S_clu.nClu && numel(S_clu.vrPosY_clu) == S_clu.nClu ...
    && all(S_clu.viSite_clu(:) >= 1 & S_clu.viSite_clu(:) <= numel(viShank_site));
if fShankSort_clu
    viShank_clu = viShank_site(S_clu.viSite_clu);
    [~, viMap_clu] = sortrows([viShank_clu(:), S_clu.vrPosY_clu(:), S_clu.vrPosX_clu(:)], [1,2,3]);
else
    mrPosXY_clu = [S_clu.vrPosX_clu(:), S_clu.vrPosY_clu(:)];
    [~, viMap_clu] = sortrows(mrPosXY_clu, [1, 2]);
end
```
The msgbox and docstring were branched to stop claiming "(X, then Y)" after a shank sort. Everything
downstream of `viMap_clu` (the CID-01 `viClu` lockstep remap, `S_clu_select_`, the P3a
`S_clu_assert_synced_` detector, `save0_`) is **unchanged**.

**Reviewed** by an architecture pass and an adversarial (devil's-advocate) pass. Both confirmed it
**cannot reintroduce the CID-01 identity desync** — the sort key is orthogonal to the remap, and
`sortrows` always returns a valid `1:nClu` permutation. Three defects the first-draft pseudocode
would have shipped were folded in:
- **[blocker]** the guard referenced `nClu`, which is not assigned until *after* the edit site →
  use `S_clu.nClu` directly (would have crashed the first real multi-shank `[O]`, invisible in
  fallback-only testing on this all-shank-1 recording).
- **[medium]** `viSite_clu` tracks `nClu` tightly but `vrPos*_clu` is recomputed only when *empty*,
  so a stale-length position array would crash the key `horzcat` where today's code skips gracefully
  → length-guard all three key vectors.
- **[should]** reuse the existing `isSingleShank_` predicate (irc.m:16090); keep the `(:)`
  normalization (required, not cosmetic — `viShank_site(viSite_clu)` inherits `viShank_site`'s
  probe-dependent orientation).

**Verified.** `checkcode irc.m` clean in the edited region; a synthetic negative-control harness
passed **5/5**: shank ordering, CID-01 invariant preserved after remap, fallback byte-identical to
today (regression gate), stale-position graceful fallback (no crash), and NaN `viSite_clu` fallback.

**Dormant until the probe declares shanks.** This recording's `viShank_site` is all `1`s (CID-14),
so `[O]` keeps the X-then-Y fallback here until that is fixed — see §3.

---

## 2. Per-site cap 100k → 200k, `fParfor=0` (recording `.prm`, not repo code)

On the recording's `..._ap_irc_all.prm` (outside this repo):
- `maxSpk_persite_clust = 100000 → 200000` (line 207). Read via
  `get_set_(P,'maxSpk_persite_clust',[])` in `cluster_site_` (irc.m:2675). Predicted effect from
  per-site counts: propagation 27.6% → 11.9%, over-cap sites 49 → 17. Takes effect on a new sort.
- `fParfor = 1 → 0` (line 21). **Required** at the 200k cap on this 128 GB box: the per-site
  transient is ~16 GB/site, and `parfor (iSite, nWorkers)` (irc.m:2599, `nWorkers_clust=12`) would
  run up to 12 concurrently → OOM. Serial → ~16 GB + ~62 GB base ≈ ~78 GB peak. The plan had
  assumed `fParfor` was already 0; it was not — surfaced and resolved with the user.

**Re-sort command:** `irc sort` (not `irc spikesort`) — `sort_` reuses existing detection
(irc.m:1069 only re-detects `if ~is_detected_`) and re-runs only clustering (`fet2clu_`, which
includes the automated `post_merge_`). It overwrites `..._irc_all_jrc.mat`, discarding any manual
curation on it; back up first if needed.

---

## 3. CID-14 activation finding — swapping `probe_file` is NOT enough

**The recording now has a correct shank-bearing probe** (`IRC_with_shanks.prb`: standard
`geometry`/`channels`/`shank`/`pad`, `shank` = `[1 2 3 4]` × 96, geometry/channels identical to the
old `IRC_all.prb`), and `probe_file` was pointed at it. **Yet `viShank_site` still loads as all
`1`s.**

**Root cause.** `loadParam_` re-reads the `.prb` into `P0` (irc.m:1599, `load_prb_`) and then does
`P = struct_merge_(P0, P)` (irc.m:1603). `struct_merge_` lets the **second** argument win
(irc.m:20848), and the second argument is `P` = the `.prm`'s baked values. The `.prm` bakes
`viShank_site = [1,1,...]` (line 389), so it **overrides** the probe's real shanks on every load.
(This is also why the old `IRC_all.prb`, which defines `geometry2`/`channels2` — misnamed, so
`load_prb_` reads empty — still sorted: the `.prm`'s baked `mrSiteXY`/`viSite2Chan` covered it.)

**Empirical confirmation** (`irc('call','loadParam_',{prm})`):

| `.prm` state | `unique(P.viShank_site)` |
|---|---|
| `probe_file=IRC_with_shanks.prb`, line 389 present | `1` (all-1s — probe overridden) |
| same, line 389 removed | `[1 2 3 4]` × 96 (probe activates) |

**Fix (`.prm` edit, respects "do not edit `.prb`"):** comment out / delete the baked
`viShank_site` line (389). Then `load_prb_` supplies the 4-shank vector and it survives the merge.
`viSite2Chan` is identity `1..384`, so the probe's channel-ordered `shank` maps directly onto sites.

**Order of operations:**
- `[O]`-only on the current 100k sort: comment out line 389 → `irc manual` → `[O]` orders by shank.
- Shank-aware clustering (recommended alongside the 200k cap): comment out line 389 **first**, then
  `irc sort`. `viShank_site` also feeds the sort/drift (`nShanks` at irc.m:5759, per-shank site
  distance ~13559), so this makes sites on different shanks stop being treated as neighbors — more
  correct for a 4-shank probe, but it changes clustering vs. the all-1s sort.

**Sanity check after editing:**
```matlab
P = irc('call','loadParam_',{prm}); unique(P.viShank_site(:))'   % expect [1 2 3 4]
```

---

## 4. Cross-shank merge guard (`irc sort` / `irc auto` / manual `[M]`/`[U]`) — DONE (headless-verified)

> **Plan:** `C:\Users\weisss\.claude\plans\purrfect-bouncing-rainbow.md` (reviewed: architecture +
> devil's-advocate). Reject cluster merges across shanks at every merge-decision point. Additive;
> a **byte-identical no-op** on single-shank / shank-less probes and whenever `fMerge_across_shank=1`.

**Two helpers** (next to `isSingleShank_`, irc.m ~16216):
- `shank_clu_(S_clu, P)` — per-cluster peak-site shank `viShank_site(viSite_clu)`; returns `[]`
  ("do not guard") on single-shank / empty `viShank_site` / all-identical shank / `viSite_clu`
  wrong-length or out-of-range. Mirrors the `reorder_clu_by_coords_` gating.
- `block_cross_shank_(ml, viShank_clu)` — zeroes cross-shank entries of a cluster×cluster boolean
  merge-adjacency via the symmetric outer product `viShank_clu(:) ~= viShank_clu(:)'` (symmetric
  because `ml2map_` does `ml | ml'`). **Strictly subtractive** → can only collapse *fewer* clusters,
  so no `viClu`/`cviSpk_clu` desync is reachable. **Size fail-safe:** no-op unless `ml` is square
  and `numel(viShank_clu)==size(ml,1)`, so a misaligned automated site degrades to *no protection,
  never a crash or a wrong mask*.

**Param** `fMerge_across_shank` (default **0** = guard on; `1` = allow). Added to `default.prm`; read
inline via `get_set_(P,'fMerge_across_shank',0)` at every hook (no central registry, matching
`fMerge_spk`). It is the one `fMerge_*` where `0` *enables* a behavior — noted in the code.

**Manual hooks (the only real behavior change):**
- **A** `ui_merge_pending_` — reject a cross-shank pair before it enters the queue (`msgbox_` + return).
  Transitivity keeps every queued `[U]` group single-shank (`add_pending_merge_` has one caller).
- **B** `merge_clu_` — reject before any mutation, returning the default `fOk=false`; the sole caller
  `ui_merge_` already gates on `~fOk` (added a `msgbox_` there). Covers the immediate Time/Proj/WavCor `[m]`.
- **C** `execute_pending_and_update_` group loop — backstop that recomputes `shank_clu_` **fresh each
  iteration** (the loop renumbers indices in place) and reuses the group snapshot-rollback + `msgbox_`.

**Automated masks (defensive — the geometric rule `maxDist_site_um < shank_spacing` already makes
these ~never fire).** `if ~get_set_(...), ml = block_cross_shank_(ml, shank_clu_(S_clu,P)); end`
immediately before `ml2map_` at **11 sites**: REQUIRED — `templateMatch_post_` (default mode 1),
`post_merge_wav4_` (kmeans default + GUI "Merge auto"), `S_clu_peak_merge_` (default DPC path);
additional — `featureMatch_post_`, `driftMatch_post_`, `templateMatch_post_burst_`,
`post_merge_similarity_cc_`, `graph_merge_`, `drift_merge_post_`, `post_merge_drift_`, `post_merge_cc_`.
- **`S_clu_peak_merge_` is special:** it runs *before* `S_clu_refresh_` in `assign_clu_count_`, so
  `S_clu.viSite_clu` is not yet label-aligned. `mnKnn_clu` (from `calc_dist_knn_clu`) is indexed by
  cluster **label** `1..nClu`, and label *i*'s center is `S_clu.icl(i)`, so the per-label shank is
  derived from `viSite_spk(S_clu.icl)` (guarded on `numel(icl)==size(mnKnn_clu,1)`), *not* `shank_clu_`.

**Why CID-safe:** masks are strictly subtractive (fewer collapses, still a valid surjective relabel);
pairwise hooks reject before any mutation; no-op on single-shank / `fMerge_across_shank=1`.

**Known limits (honest):** transitive-bridge suppression (a same-shank A–C reachable *only* via a
cross-shank B is also dropped — not corruption, only fewer merges); peak-shank is a proxy (a unit
drifting across a shank boundary could be wrongly blocked — implausible on 250 µm-spaced NP2.0).

**Verified (headless).** `checkcode irc.m` clean in the edited regions (only pre-existing SPRIX/TRYNC
style notes remain); negative-control harness `scratchpad/verify_cross_shank_merge.m` passed **22/22**:
mask+`ml2map_` separation with same-shank chain still collapsing (T1), regression no-op on
`[]`/size-mismatch/all-identical (T2), `shank_clu_` fallbacks (T3), mask symmetry (T4), and `merge_clu_`
Hook B rejecting a cross-shank pair *byte-identically before mutation* while `fMerge_across_shank=1`
falls through (T5).

**Live-verified on the real recording (in-memory, no save).** The full re-`irc sort` re-clustered
cleanly (1287 clusters, ~145 min) but its auto-merge crashed on a **pre-existing, unrelated `.prm`
bug** (see below), upstream of every mask. So the mask path was instead exercised via an in-memory
`post_merge_` on the existing sorted `_jrc.mat` (`scratchpad/verify_postmerge_inmem.m`): replicates
`auto_`'s load + `post_merge_` with a **scalar** `post_merge_mode=17` (→ `templateMatch_post_`, which
carries the cross-shank mask), guard on (`fMerge_across_shank=0`), 4 shanks active
(`unique(viShank_site)=[1 2 3 4]`), **no `save0_`** (on-disk `_jrc.mat` byte-identical before/after).
Result: `templateMatch_post_` merged 5 real clusters (934→929) without crashing on the real
~934×934 adjacency; **0/929 final clusters span >1 shank by member-spike sites**; per-shank peak-site
distribution `[239 230 193 267]`; **CID-01 invariant `all(viClu(cviSpk_clu{i})==i)` holds**. This
confirms the mask is correctly placed/wired and non-crashing on real data, and that legitimate
same-shank merges still proceed. (Combined with the 22/22 harness — which proves the mask actually
*blocks* cross-shank edges when they exist — coverage is: harness = blocking correctness, live run =
placement/wiring + no-crash + no identity corruption.)

**Still not run:** the interactive `irc manual` `[M]`/`[U]` check (needs a live figure; user-driven).

### Pre-existing bug surfaced (separate from the guard): `post_merge_mode` as an array

`irc>fet2clu_` (irc.m:2382) unconditionally calls `post_merge_`, whose dispatch is
`switch get_set_(P,'post_merge_mode',1)` (irc.m:3910) — a **scalar** switch. The recording's `.prm`
had `post_merge_mode = [17,4,12,15]` (an array, evidently copy-pasted from the `post_merge_mode0`
line, which *is* array-capable — its dispatcher at irc.m:11501 guards `numel(post_merge_mode0)>1`).
Switching on an array throws `SWITCH expression must be a scalar or a character vector`, so **any**
`irc('sort')` on this `.prm` crashes at auto-merge, with or without the cross-shank change. `default.prm`
is correct (`post_merge_mode = 1;` scalar, `post_merge_mode0 = [12,17];` array). **Fix (user-authorized):**
set the recording's `post_merge_mode = 17;` (scalar, first element). `post_merge_mode0` left as-is
(irrelevant on this `fLabelClu`/iso-split path, which skips `postCluster_`). No `irc.m` change made for
this — it is a recording-`.prm` fix, not a code fix.
