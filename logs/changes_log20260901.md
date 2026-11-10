# Changes Log - September 1, 2026

## Summary

Additive tooling for **retuning the automated post-merge on label-based sorts**
(`vcCluster = 'isosplit'`/`'kmeans'`/`'hdbscan'`/`'classix'`) without a full re-sort, plus the
documentation of *why* the usual `post_merge_mode0` knob does nothing on those sorts.

1. **New command `irc reset-to-premerge`** (alias `reset-premerge`) — `matlab/irc.m`.
2. **New script `matlab/sweep_post_merge.m`** — non-destructive, in-memory post-merge parameter sweep.
3. **Docs** — `README.md`, `matlab/CLAUDE.md`, memory index.

No behaviour change for existing commands: `auto_` gained an optional 2nd argument that defaults to the
prior behaviour, so `auto_(P)` (the `irc auto` path) is byte-identical.

## Motivation

On a label-based sort the density-peak path is bypassed (`fet2clu_` sets `fLabelClu`, `post_merge_`
skips `postCluster_` at irc.m:3965). `post_merge_mode0` is read **only** inside `assign_clu_count_`,
whose sole caller is `postCluster_` — so on `isosplit` etc. **`post_merge_mode0` is inert**. Verified by
tracing every `postCluster_` call site (irc.m:2390 gated by `~fLabelClu`; irc.m:3965 gated by
`fPostCluster && ~fLabelClu` with `fet2clu_` passing `fPostCluster=0`; the others are the `spacetime`
reclust and `cluster_pca_`, neither on the isosplit path).

The merge that actually runs is governed by the **scalar** `post_merge_mode` + `maxWavCor` + the
automatic cross-site `post_merge_wav4_` pass. Iterating those meant either editing the `.prm` and
re-sorting (~100+ min), or `irc auto` — which re-merges **on top of** the current `viClu` and compounds
rather than starting clean.

## 1. `irc reset-to-premerge` (irc.m)

`auto_` gained `fReset_premerge` (default 0). When 1, after `load_cached_` it resets
`S_clu.viClu = S_clu.viClu_premerge` (the raw pre-merge baseline) before `post_merge_`, then saves as
usual. Dispatch: `case {'reset-to-premerge','reset-premerge'} -> auto_(P, 1)`.

- **Fast:** reuses cached detect/feature/kNN artifacts; only the clustering-finalize is redone.
- **Destructive like `auto`/`recurate`:** overwrites `_jrc.mat` (atomic `save0_`, keeps `.bak`),
  discards curation. Overwrites **in place by design** — the toolchain derives the `_jrc.mat` path from
  the `.prm` name, so a side-written file would be an orphan; keep alternatives by copying the `.prm`.
- **Idempotent:** `post_merge_` re-stores `viClu_premerge` from the reset `viClu` (irc.m:3973) before
  merging, so repeats restart from the same baseline.
- **Guards:** errors if `viClu_premerge` absent/empty; warns if `nClu(premerge) ≤ 1.05·nClu(current)`
  (baseline likely overwritten by a prior `auto`/`recurate`).

## 2. `sweep_post_merge.m`

`sweep_post_merge(prm, [post_merge_mode maxWavCor; ...])` loads the cached data **once**, then for each
row resets `viClu ← viClu_premerge`, overrides `P.post_merge_mode` (scalar) + `P.maxWavCor`, runs
`post_merge_` **in memory**, and prints a table of `nClu`, sync flag and time. **Never writes the
`_jrc.mat`** (no `save0_` call) — use it to choose settings, then bake in with `reset-to-premerge` or a
re-sort. Same `viClu_premerge` guard/warning as the command.

## Verification

- `checkcode` parse-clean on `matlab/irc.m` (0 parse errors) and `matlab/sweep_post_merge.m` (0 notes).
- Only two `auto_(` call sites (irc.m:250 `auto_(P)`, irc.m:252 `auto_(P,1)`); the arity change is safe.
- **Not yet run end-to-end on the recording** — `reset-to-premerge` overwrites the live `_jrc.mat`
  (destructive), so a functional run is left to the operator. Logic reuses the proven
  `auto_`/`post_merge_`/`save0_` path; the only new behaviour is the one-line `viClu` reset + guards.
