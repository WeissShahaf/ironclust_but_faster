# PLAN: per-shank common reference + per-shank whitening

Written 2026-10-06, consolidated 2026-10-07 (supersedes the earlier append-only version).
Status: **IMPLEMENTED 2026-10-07 (uncommitted) — see "Implementation and verification" at the bottom.** Branch `rewind`. Targets: `matlab/irc.m`, `matlab/spatial_whiten.m`, `matlab/default.prm` (comment only).
Reviewed by: code-architect, MATLAB expert, devil's advocate, Opus advisor.
Gate: user confirmed the 3 modes, MATLAB not running, go-ahead given, small-shank floor = 16 usable sites.

## Goal — three new `vcCommonRef` values, each working strictly WITHIN a shank
| value | does |
|---|---|
| `shankcmr` | subtract, from each site, the median over the sites of ITS shank |
| `shankwhiten` | spatial whitening whose neighbour lists contain only sites of the same shank (no CMR) |
| `shankcmrwhiten` | `shankcmr`, then `shankwhiten` on the result |

Nothing from another shank enters any median or any whitening neighbourhood.

## User decisions (final)
- Modes exactly as in the table above; whitening is wanted as an additional method.
- **Blanking reference** (`blank_thresh`, 2nd output of `wav_car_`) = **global `median_excl_` over all non-`viSiteZero` sites, taken on the input BEFORE any shank subtraction** — identical to what `'median'` mode feeds `car_reject_`. (Earlier "median of per-shank refs" dropped: with 2 shanks it is a mean and dilutes a one-shank artifact.) Same rule for all three modes.
- **Hard constraint: no existing functionality may break** (see "Regression safeguards").

## Findings (all read from code)
- `wav_car_` (irc.m:5386) switches on `lower(P.vcCommonRef)` → case labels must be lowercase. Called once PER CHUNK from `filt_car_` (irc.m:6016), gated by `nChans >= nChans_min_car` (8). Padding is trimmed before it (irc.m:6009), so per-sample CMR is chunk-safe.
- `filt_car_` 2nd output `vnWav11` → `car_reject_` (irc.m:18537-18541); `blank_thresh=8` is ON by default so it must return ONE trace.
- `findNearSites_` (irc.m:14475) ranks sites by full 2-D Euclidean distance (`pdist2_`, irc.m:18065). `viShank_site` only caps the COUNT (`min` shank size), never filters membership. Neighbour count `nSites_spk` = max #sites within `maxDist_site_spk_um` of any site. Existing `'whiten'` can therefore cross shanks: at shank ends (the shank runs out of sites) and across the gap when edge columns are close. Shanks have 1-5 columns, so no distance rule is safe → lists must be built from MEMBERSHIP.
- Existing `'whiten'` ignores `nSites_whiten` (`miSites_whiten` dead, irc.m:5426) and passes full `P.miSites`; `nSites_whiten` in default.prm is effectively unread for it.
- `spatial_whiten.m`: `persistent mrW_ miSites_` computed ONCE from the first chunk (lines 9-13); line 26 returns the cached `miSites_`, ignoring the argument thereafter; per-site matrix uses only `mrW1(:,1)` (line 55), so **row 1 of each miSites column must be the site itself**, and every column needs the same row count. Cleared only by `clear_filters_` (irc.m:33592), called at irc.m:19097 and 19218 (verify they run at the start of detect/sort).
- `spatial_whiten` assumes mean-subtracted input (line 36); existing `'whiten'` doesn't provide it. `shankcmrwhiten` does.
- `spkwav_car_` reads `vcSpkRef`, NOT `vcCommonRef` (irc.m:1240) → no downstream effect. MountainSort importer (irc.m:27225) needs no change. `describe` (irc.m:6129) just prints the string.
- GUI: preview forces `'none'` (irc.m:23490); `mr2ref_` (irc.m:24184) returns one vector for all sites, cannot show per-shank refs → **no GUI / `mr2ref_` work**. Only verify `menu_checkbox_` (irc.m:24076) doesn't error on an unlisted mode string.
- `isSingleShank_` (irc.m:17084): empty ⇒ single; does not check `numel == nSites`.
- `mean_excl_` (irc.m:17008) has a latent bug (indexes a count, not `viSiteZero`) — do NOT copy, do NOT fix.
- `filt_car_` is also called at irc.m:263, 3791, 19884, 28976 and may receive int16; the detect path casts to single first (irc.m:18519-18524).
- `irc2.m` has its own switch blocks (5017, 5052) — out of scope.

## Design
### Helpers (new local functions in irc.m; nothing existing edited)
- `shank_groups_(P, nSites)` → cell of site-index vectors, one per `unique(viShank_site(:))`. Falls back to ONE group (all sites) if `viShank_site` is empty, has `numel ~= nSites`, or has a single value. Guard copied from irc.m:8952.
- `shank_miSites_(P, nSites_whiten)` → `miSites_shank` (n × nSites): column `i` = site `i` first, then its nearest sites on the SAME shank by `mrSiteXY` distance, `viSiteZero` excluded from candidates. `n = min(nSites_whiten, size(P.miSites,1), min usable sites over shanks with ≥3 usable sites)`. (`nSites_whiten`=16 and `P.miSites` rows=11 on the user's probe ⇒ n=11, same count as plain `whiten`, so results are comparable.)

### `wav_car_` new cases (lowercase labels)
- **`shankcmr`**: if `shank_groups_` returns one group → run the existing `'median'` branch (shared code ⇒ exact equivalence, no int16 rounding difference). Else: `vnWav1_mean = median_excl_(mnWav1, P)` computed first (blanking ref); then per shank `single(median(mnWav1(:,usable),2,'omitnan'))` subtracted from that shank's sites (cast back to input class). Shanks with <3 usable sites: left un-subtracted, warn once. Never let NaN into the output or the 2nd output. GPU: try on device, fall back to gathering only the shank subset.
- **`shankwhiten`**: `mnWav1 = spatial_whiten(mnWav1, shank_miSites_(...), 1)`; 2nd output = `median_excl_` of the input, computed before whitening (the blanking rule above). This differs from existing `'whiten'`, which returns `[]` and lets `mr2ref_` supply a plain mean. Sites on shanks with <3 usable sites: pass through un-whitened with a warning (note scale mismatch vs whitened sites).
- **`shankcmrwhiten`**: `shankcmr` step, then the `shankwhiten` step; 2nd output = the pre-subtraction global median.
- Post-switch block (`fMeanSite_drift` / `viSiteZero` zeroing, irc.m:5437-5444) untouched and shared.

### `spatial_whiten.m` (optional 3rd arg, default behaviour byte-identical)
Add `fKeyed` (default 0). When 1, recompute if `isempty(mrW_) || ~isequal(miSites_, miSites)`. Only the new modes pass 1. Residual limitation: cache is still shared — `whiten` after a shank mode in the same session reuses shank lists until `clear_filters_()`.

### Docs
`default.prm:72` list gets the three values; fix the misleading `nSites_whiten` note (:73) only to say it is used by the shank modes.

## Regression safeguards (HARD CONSTRAINT)
1. Additive only: no change to existing cases, `mean_excl_`, `mr2ref_`, GUI, `irc2.m`; unknown modes fall through exactly as today.
2. `spatial_whiten` default path (`fKeyed=0`) unchanged.
3. Baseline FIRST: `git status` clean on `rewind`; with UNMODIFIED code capture `filt_car_` output (in memory, trimmed real .prm) for `none, mean, median, tmean, nmean, whiten, whiten-mean, whiten-median`; after the change assert `isequal` byte-identical for each.
4. Run `irc unit-test` before and after; record the baseline; if it already fails, say so rather than compare.
5. The new code runs only for the three new labels; confirm baseline .prm files use none/median/whiten only.
6. Launch MATLAB via PowerShell; in-memory only (no save, no full sort).

## Test plan (real recording, time-trimmed .prm; no synthetic data)
- All safeguards above.
- Single-shank probe (or forced single group): `shankcmr` == `median` exactly.
- Multi-shank: per-shank ref == manual median over that shank's columns; other shanks' columns unchanged by that shank's data.
- `shankwhiten`: no neighbour list crosses a shank, row 1 == self, equal row count; run on real `.prb` files with 1…5 columns if available.
- Two consecutive chunks → identical whitening matrix.
- `whiten` then `shankwhiten` in one session → shank lists used (cache key works).
- `shankcmrwhiten` == `shankcmr` then `spatial_whiten` with `shank_miSites_`.
- Edge cases: shank with 1-2 usable sites; shank wholly in `viSiteZero`; `fMeanSite_drift` on; int16 vs single input; GPU vs CPU; `viShank_site` wrong length / non-contiguous labels.
- Detection-only on a trimmed real .prm, `median` vs each new mode: spike count and the `Rejecting X % of time due to motion` line (cheap sort-quality proxy). Full-sort comparison is an optional follow-up.
- Single-shank `shankwhiten` is NOT expected to equal `whiten` (different neighbour count rule when `nSites_whiten` < rows) — do not assert equivalence.

## Probe check already done (read-only, 2026-10-07)
For `afm17372_241213_0_g0_tcat.imec0.ap.resorted.prm` → `IRC_all_sites.prb`: 107 sites, shanks 48/36/23, min inter-shank distance 250 µm, `nSites_spk`=11 → 0 of 93 live sites have a cross-shank neighbour, so plain `whiten` is already per-shank BY GEOMETRY there. The 384-site `..ap_IRC.prb` (4 shanks, min 218.5 µm): 5 of 359 live sites cross. **Mismatch to resolve before any test on this .prm:** its `viSiteZero` has 11 of 25 entries beyond the 107-site probe (the prb was rewritten 14:29 after the .prm at 12:36).

## Known limitations (not fixing)
- Whitening rescales amplitude (`scaleproc=100`): qqFactor/MAD thresholds and Vpp are not comparable with `median` sorts. Quality/`note` pipelines tuned on median-referenced data may shift.
- Whitening matrix is fixed from the first chunk (an artifact there propagates).
- `irc2.m` does not understand the new modes (a shared .prm silently behaves as unmodified there).
- `nneigh_min_detect`, `maxDist_site_spk_um` semantics unchanged (see session notes): the latter only sets the shared neighbour COUNT, not a per-site radius.

## Open items
- Go-ahead to edit `irc.m` / `spatial_whiten.m`.
- Resolve the .prm ↔ .prb mismatch above before using that file for tests.
- Pass-through of sites on <3-usable-site shanks under `shankwhiten` is a chosen default (warn); say if you'd rather error out.

## Implementation and verification (2026-10-07)
Decisions at go-ahead: **small-shank floor = 16 usable sites** (was 3), exposed as `nSites_min_shank` (default 16); applies to both the CMR skip and the whitening pass-through; a single-shank probe ignores it.

### Changes (uncommitted on `rewind`)
- `matlab/irc.m`: new `case {'shankcmr','shankwhiten','shankcmrwhiten'}` in `wav_car_`; new local functions `wav_car_shank_`, `shank_groups_`, `shank_miSites_`, `warn_once_` (all after `wav_car_`). No existing case or function edited.
- `matlab/spatial_whiten.m`: optional 3rd arg `fKeyed` (default 0 ⇒ unchanged).
- `matlab/default.prm`: `vcCommonRef` list, `nSites_whiten` note, new `nSites_min_shank`.
- `matlab/CLAUDE.md`: new section "Per-shank common reference / whitening".
- Not touched: `mr2ref_`, GUI, `irc2.m`, `mean_excl_`, `clear_filters_`.

### Verification (real recording `afm17372_241213_0_g0_tcat.imec0.ap.bin`, 3 s at t=60 s, 106 sites / 3 shanks, `ap_resorted_new.prm` copied to scratch; in-memory `filt_car_`, nothing saved)
Harnesses in the session scratchpad: `shank_harness2.m` (baseline/after), `shank_checks.m`, `iso.m`.
- **Regression:** baseline captured on UNMODIFIED code, then re-run: `none, mean, median, tmean, nmean, whiten, whiten-mean, whiten-median` × {no viSiteZero, 7 viSiteZero} → **16/16 `isequaln` (outputs and ref)**.
- **New modes (20 checks, all PASS):** shankcmr == manual per-shank median; blank ref == `median`-mode ref; other shanks unaffected by a perturbed shank while global `median` does leak (control); whitening lists 0 cross-shank / row 1 == self / equal row count; `shankcmrwhiten` == `shankcmr` → `spatial_whiten`; forced single shank == `median` exactly; wrong-length `viShank_site` falls back to `median`; floor=30 leaves the 23-site shank untouched (CMR) and passes it through (whiten); `whiten` then `shankwhiten` uses shank lists; two chunks share one matrix; int16 input; `fMeanSite_drift=1`.
- Test-design note: the bandpass filter is not bit-reproducible (~5e-5 float noise even with `vcCommonRef='none'`), so the isolation check uses a 1e-3 tolerance with `median` as a positive control (leak ≈ 15).

### Not done / caveats
- **`irc unit-test` was NOT run** before/after (the plan asked for it); the byte-identical baseline comparison above is the regression evidence instead.
- `tmean`/`nmean` error on single-precision input in the unmodified code too (recorded as baseline; identical before/after).
- Not tested: GPU path (`fGpu=0` throughout), a probe with a shank under 16 usable sites in a real run beyond the floor=30 simulation, full detect/sort and sort-quality comparison (`Rejecting X %`, spike counts) between `median` and the new modes.
- Nothing committed.
