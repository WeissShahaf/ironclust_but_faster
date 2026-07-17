# Plan — shank-aware cluster reordering (`[O]` key)

**Date:** 2026-07-17 · **Branch:** `rewind` · **Author:** design pass (no code yet)
**Depends on:** the CID-01 hardening in `87cd4f1` / `d372eac` (`reorder_clu_by_coords_` viClu-lockstep
remap + P3a sync detector — all committed).
**Tracker:** [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md)
(relates to **CID-01** — the reorder desync — and **CID-14** — `viShank_site` all `1`s on this probe).

---

## STATUS — LANDED (`80a5901`, 2026-07-17)

Implemented in `reorder_clu_by_coords_` and pushed. Reviewed (architecture + devil's-advocate),
verified **5/5** by the synthetic negative control, and hardened beyond this draft — see
`logs/changes_log20260717.md` §1 (`S_clu.nClu` used directly, position-length guard added,
`isSingleShank_` reused). §8's open decisions were resolved: tie-break `[shank, Y, X]`; land the
code dormant and treat CID-14 activation separately. **Activation on this recording is now done**
(the baked `viShank_site` line was commented out of the `.prm`; `loadParam_` returns `[1 2 3 4]`),
so `[O]` now orders by shank → depth. See `logs/changes_log20260717.md` §3 and the CID-14 tracker
entry.

---

## 0. Goal

Make the manual-GUI `[O]` reorder (`reorder_clu_by_coords_`, bound to `case 'o'` at `irc.m:6974`,
menu at `6480`) order clusters by **shank first, then depth (Y), then X** when the probe declares
real shank indices, and **fall back to the current X-then-Y** ordering when it does not. The change
must be **additive** and must **not** reintroduce the CID-01 identity desync.

**Why:** on a multi-shank probe, `[O]`'s current `sortrows([X, Y])` groups by exact X, so a shank's
two columns are ordered as *all of column 1, then all of column 2* rather than by depth within the
shank. Ordering by (shank, Y) interleaves the columns by depth — the layout users expect. X is a
rough proxy for shank today (shanks occupy different X ranges) but not an exact one.

---

## 1. How `[O]` reorder works today (baseline, for reference)

`reorder_clu_by_coords_` (`irc.m:10478-10527`) is a **pure relabeling**: it renumbers cluster IDs by
position; no spike moves between clusters, nothing is merged/split/deleted, cluster count is
unchanged. Steps:

1. Ensure `vrPosX_clu`/`vrPosY_clu` exist (`S_clu_position_`).
2. **Key:** `[~, viMap_clu] = sortrows([vrPosX_clu, vrPosY_clu], [1,2])` — `viMap_clu(new)=old`. *(10492-10494)*
3. **Guard:** `numel(viMap_clu) ~= nClu → refuse`. *(10505)*
4. Invert: `viOld2New(viMap_clu) = 1:nClu`. *(10510-10511)*
5. **Remap `viClu` (per-spike) in lockstep** — `viClu(assigned) = viOld2New(viClu(assigned))`. *(10512-10513)* ← the CID-01 fix.
6. **Reorder caches** — `S_clu_select_(S_clu, viMap_clu)` reindexes every `*_clu` field. *(10516)*
7. Rebuild `mrWavCor` diagonal. *(10517)*
8. Save — `set0_` → **`S_clu_assert_synced_`** (P3a detector, since `[O]` bypasses `S_clu_commit_`) → `gui_update_` → `save0_()`. *(10518-10524)*

The invariant preserved end-to-end: `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for every `i`.

---

## 2. The change (design)

Replace **only** the key computation at `irc.m:10492-10494`. Everything downstream (steps 3-8
above) is untouched.

```
Sort key selection:
  viShank_site = get_set_(P, 'viShank_site', [])
  IF  viShank_site non-empty
      AND numel(unique(viShank_site)) > 1                 (probe declares >1 real shank)
      AND S_clu.viSite_clu present, length == nClu, all in [1, numel(viShank_site)]
  THEN
      viShank_clu = viShank_site(S_clu.viSite_clu)         (shank of each cluster's peak site)
      viMap_clu   = sortrows([viShank_clu, vrPosY_clu, vrPosX_clu], [1,2,3])   -> shank, Y, X
  ELSE
      viMap_clu   = sortrows([vrPosX_clu, vrPosY_clu], [1,2])                    -> original X-then-Y
```

- **Additive:** the `else` branch is the current behavior, verbatim. No existing path is removed.
- **Cluster shank = shank of its peak site** (`viSite_clu`). Natural, unambiguous.
- **X kept as a tertiary tie-break** for determinism (pending §8 decision — could be `[shank, Y]` only).
- The four `if` conditions are guards: any failure → fall back rather than error or desync.

---

## 3. Safety analysis — why this cannot reintroduce CID-01

**CID-01 was a missing-`viClu`-remap bug, not a sort-key bug.** The corruption came from renumbering
the caches while leaving `viClu` on the old numbering. The fix (steps 5-8) is entirely **downstream
of `viMap_clu`** and runs identically for *any* permutation.

This change alters **only** how `viMap_clu` is computed. Its correctness rests on one property:

> **`viMap_clu` remains a valid permutation of `1:nClu`.** `sortrows` returns a permutation of the
> row indices whenever the key matrix has exactly `nClu` rows. `viShank_clu`, `vrPosY_clu`, and
> `vrPosX_clu` are each length `nClu`, so the key matrix is `nClu × k` and `viMap_clu` is a
> permutation of `1:nClu` — exactly as in the current X-then-Y path.

Given that property, the remap in step 5 and the reindex in step 6 preserve
`all(viClu(cviSpk_clu{i}) == i)` regardless of the *order* the permutation encodes. The sort key is
**orthogonal** to the invariant.

Defenses that remain in force, unchanged, as the last lines of defense:
- **Length guard** (`10505`): a wrong-length key ⇒ `numel(viMap_clu) ~= nClu` ⇒ **refuse** (no partial apply).
- **P3a detector** (`10522`): `S_clu_assert_synced_` runs on the `[O]` path before `save0_()`; a desync warns loudly.
- **P3b** (`struct_select_safe_` critical field): a `cviSpk_clu` resize failure re-throws → this
  no-try/catch caller **crashes** rather than silently desyncs.

Edge cases and why they stay safe:
- **NaN `vrPosY_clu`/`vrPosX_clu`** (cluster with no position): `sortrows` sorts NaN last → still a
  valid permutation. Identical behavior to the current fallback, which already sorts on these.
- **Ties in (shank, Y[, X])**: `sortrows` is stable → arbitrary-but-valid permutation.
- **`viSite_clu` out of range / wrong length / missing**: the `if` conditions fail → fall back to
  X-then-Y. No out-of-range index into `viShank_site` is ever taken.

**Net:** the change is a key-only edit whose single obligation (permutation of `1:nClu`) is
guaranteed by `sortrows` and re-checked by the existing length guard. It is orthogonal to the
mechanism that produced CID-01.

---

## 4. CID-14 dependency — this is a no-op on the current probe until the `.prb` is fixed

On the active recording (`..._irc_all.prm`, `viShank_site` line 389) **`P.viShank_site` is all `1`s**
even though `mrSiteXY` is multi-column/multi-shank. So `numel(unique(viShank_site)) > 1` is **false**
and the new branch **does not activate** — `[O]` still runs the X-then-Y fallback (byte-identical to
today). This is exactly **CID-14** in the tracker.

Two independent pieces:
1. **This code change** — makes `[O]` shank-aware *whenever real shank data is present*. Safe to land
   on its own; it simply lies dormant until (2).
2. **CID-14 `.prb` fix** — regenerate `IRC_all.prb` with real 1-based `shank` indices so
   `viShank_site` is not all `1`s. This is what *activates* the branch for this probe. Per the user's
   standing rule "do not edit existing `.prb` files," this is a **separate, opt-in** step (regenerate
   via the fixed generator, or hand-edit with explicit approval). Out of scope for the code change;
   tracked as CID-14.

---

## 5. Verification (negative-control harness, per this investigation's standard)

The shank branch cannot be exercised on the real file (all-shank-1 → fallback), so a **synthetic**
control is required. A scratchpad script (`scratchpad/verify_reorder_shank.m`, not committed) that:

1. **Shank ordering correctness** — build a synthetic `S_clu` with a known multi-shank
   `viShank_site` and scrambled positions; run the new key; assert `viMap_clu` orders clusters by
   `(shank, Y, X)`.
2. **Invariant preserved** — run the *full* `reorder_clu_by_coords_` on that fixture; assert
   `all(S_clu.viClu(S_clu.cviSpk_clu{i}) == i)` for every `i` **after** the remap (this is the CID-01
   guard — must hold).
3. **Fallback byte-identity** — with `viShank_site` all `1`s (or empty), assert the produced
   `viMap_clu` is **identical** to the current `sortrows([X,Y])` permutation (proves the additive
   change is a true no-op on the fallback path — the regression gate).
4. **Refuse guard intact** — a length-mismatched position/shank array still trips
   `numel(viMap_clu) ~= nClu` → refuse, no write.
5. **Unassigned spikes untouched** — `viClu <= 0` entries unchanged after remap.

Pass bar: 5/5, with test (3) proving the healthy/fallback path is unchanged from today.

---

## 6. Ordering & rollout

1. Land the **code change** (§2) behind the negative control (§5), gated on test (3) proving
   byte-identical fallback. Dormant on this probe until CID-14.
2. **CID-14 `.prb` fix** — separate, opt-in, needs explicit go-ahead (§4, §8). Only after this does
   the branch activate here.
3. No functions deleted; the change is additive/fallback-preserving per `CLAUDE.md`.

---

## 7. Explicitly out of scope

- **Re-plumbing `S_clu_select_` to remap `viClu` itself.** Rejected in the hardening plan; unrelated here.
- **Any change to the remap / guard / detector / save logic** (steps 3-8). This plan touches the key only.
- **Editing existing `.prb` files** without explicit approval (user standing rule).
- **Reordering triggered anywhere other than `[O]`.** `reorder_clu_by_coords_` is the only caller.

---

## 8. Open decisions (confirm before writing code)

1. **Tie-break ordering:** `[shank, Y, X]` (deterministic within a depth) or strictly `[shank, Y]`?
   *(Recommend `[shank, Y, X]` — deterministic, no downside.)*
2. **CID-14 `.prb`:** should the shank fix be pursued in parallel (regenerate / approve a `.prb`
   edit) so the branch actually activates for this probe, or land the code change dormant and defer
   the `.prb`? *(Recommend: land code now with the synthetic control; treat the `.prb` as a separate
   opt-in so the code change carries zero `.prb` risk.)*

---

## Appendix — exact change site

| Item | Location (anchor on function name; line numbers drift) |
|---|---|
| Function | `reorder_clu_by_coords_` — `irc.m:10478` |
| **Edit region (key only)** | `irc.m:10492-10494` (`mrPosXY_clu` + `sortrows`) |
| Unchanged: length guard | `irc.m:10505` |
| Unchanged: `viClu` lockstep remap | `irc.m:10510-10513` |
| Unchanged: cache reindex | `irc.m:10516` (`S_clu_select_`) |
| Unchanged: P3a detector | `irc.m:10522` (`S_clu_assert_synced_`) |
| Field read (new) | `P.viShank_site` (per-site shank), `S_clu.viSite_clu` (peak site per cluster) |

*Line numbers current as of this writing; re-`grep` the function name before editing.*
