# Changes Log - July 18, 2026

> **Plan:** `C:\Users\weisss\.claude\plans\velvet-tumbling-rocket.md` (measure-first, four review passes)
> **Grounding:** [`logs/investigation_maxSpk_persite_clust.md`](investigation_maxSpk_persite_clust.md),
> [`logs/plan_persite_spike_cap.md`](plan_persite_spike_cap.md)

## Summary

Two independent, additive performance changes to `matlab/irc.m` (+ `matlab/default.prm`), both scoped and
verified against the real `260324_afm18349` Neuropixels 2.0 recording (per-site label clustering,
`vcCluster='isosplit'`, `maxSpk_persite_clust` active):

1. **Part A — GPU-accelerate the per-site capped-cluster 1-NN assignment (`nearest_in_set_`).** On sites
   large enough to trip the `maxSpk_persite_clust` cap, every spike is assigned to its nearest clustered
   subsample member — a CPU-only chunked `pdist2` that a prior investigation identified as *"the structural
   killer for the cap regime."* Added an optional single-precision GPU path (gpuArray + `pdist2`) that is
   **measured ~25–28× faster than CPU with bit-exact indices**, with automatic CPU fallback on any GPU
   error, GPU-upload failure, or when running inside a `parfor` worker.
2. **Part B — cap the per-site clustering worker pool at 0.85× cores.** New `max_workers_(P)` helper +
   `parfor_core_factor` parameter (default 0.85), applied at the one place `irc.m` explicitly sizes a pool
   (`cluster_labels_persite_`). A general safety margin, **not** a fix for the separately-measured
   `fParfor=1` BLAS-oversubscription pessimization.

No commit changes any behavior for a run with `maxSpk_persite_clust=[]` (the default) — that path never
enters the capped branch — so the default configuration is byte-identical to before.

## Part A — GPU dispatch for `nearest_in_set_`

### Measure-first gate (Step 0)
Before writing any production code, a disposable script reproduced `nearest_in_set_`'s **exact** access
pattern (`nStep=10000`-chunked repeated `pdist2(..., 'euclidean', 'Smallest', 1)` against a fixed `m`-size
anchor set) on real cached features (`trFet_spk`) from the recording's busiest real site (#20,
n1 = 586,951 spikes, nFet = 36), CPU (double, as today) vs GPU (`gpuArray(single(...))`), RTX 4000 Ada:

| m (subsample) | n1 | CPU | GPU | speedup | index match |
|---|---|---|---|---|---|
| 100,000 | 586,951 | 181.1 s | 6.4 s | **28.1×** | 1.0000 |
| 150,000 | 586,951 | 259.9 s | 9.2 s | **28.1×** | 1.0000 |
| 200,000 | 586,951 | 340.4 s | 13.5 s | **25.2×** | 1.0000 |

This **disproved** a reviewer's hypothesis that the chunked pattern might be GPU-negative (each chunk is a
large `10000×m` distance block the GPU handles easily, unlike `persite_knn_`'s many-tiny-site regime), and
it **overturned the originally-planned `[X, Y]` upper CPU band**: GPU still wins 25× at n1 = 586,951, which
is *above* the proposed 400k ceiling, so an upper band would send the recording's 4 largest/costliest sites
backwards onto the slow path. Decision (user-confirmed): **GPU for all capped sites (`n1 > maxSpk`) when
`fGpu=1`, no upper band** — which also means `maxSpk_persite_clust` stays a plain **scalar** (no new API,
no parser, no `[X,Y]` vector), collapsing Part A to two functions.

### Changes
- **`irc.m` `nearest_in_set_`** — new optional trailing arg `fUseGpu` (default `false`; `nargin<3`
  preserves today's CPU-only path byte-identically). When true and not inside a `parfor` worker
  (`isempty(getCurrentTask())`), uploads the constant anchor set once via `gpuArray_` (which retries after a
  `gpuDevice(1)` reset), then runs the chunked `pdist2` on `gpuArray(single(...))`, VRAM-budgeting the
  chunk size from `gpuDevice().AvailableMemory`. **Any GPU error → logs, discards partial results, falls
  through to the unchanged CPU loop.** Because it runs once per site, one site's GPU failure falls back to
  CPU for that site while later sites retry GPU.
- **`irc.m` `cluster_site_capped_`** — passes `fUseGpu = get_set_(P, 'fGpu', 0)` into `nearest_in_set_`
  (any capped site is a GPU candidate; no upper band). Signature unchanged. Added a defensive
  `all(viNN >= 1 & viNN <= m)` post-call check that, if violated, throws into the existing try/catch →
  single-cluster fallback (guards against a future refactor weakening the parfor guard).
- **`default.prm`** — documented the GPU behavior and the `fGpu=0` escape hatch on the
  `maxSpk_persite_clust` comment.

### Deliberate behavior change (flagged)
For a config that already sets `maxSpk_persite_clust` **and** `fGpu=1`, the capped-site assignment now runs
on GPU instead of CPU. Output was **bit-exact** on real data, but the GPU path is single precision (CPU is
double), so on a near-exact distance tie the arg-min index *could* differ — i.e. not categorically
byte-identical. Escape hatch: `fGpu=0` forces the CPU path. Default (`maxSpk_persite_clust=[]`) is
unaffected.

## Part B — parfor worker-pool cap at 0.85× cores

### Real-evidence caveat
`logs/investigation_maxSpk_persite_clust.md` measured `fParfor=1` as a **~3× pessimization vs serial**,
*independent of worker count* (parfor×2 through ×12 all lose to serial), root cause BLAS-thread
oversubscription. A worker-count cap does **not** fix that; this change is a general safety margin only,
and `fParfor=0` remains the measured-correct setting for this workload class.

### Changes
- **`irc.m` `max_workers_(P)`** (new helper, near `gpuArray_`) — `floor(parfor_core_factor * nCores)` using
  the same probe `cluster_labels_persite_` already used (`parcluster('local').NumWorkers`, fallback
  `feature('numcores')`); factor defaults to 0.85, overridable via `P.parfor_core_factor`.
- **`irc.m` `cluster_labels_persite_`** — the pool-sizing block now clamps to `max_workers_(P)` (the only
  place `irc.m` explicitly sizes a pool).
- **`default.prm`** — new `parfor_core_factor = 0.85` in `#Execution parameters`.

An earlier draft's `ensure_parpool_cap_` pre-hook in `sort_` (to cap the other 33 bare `parfor` sites) was
**dropped** after review: it would fight `cluster_labels_persite_`'s own resize logic (delete/recreate the
pool it just built whenever `nWorkers_clust ≠ max_workers_`), and would pay `parpool` startup on every sort
by default (since `fParfor` defaults to 1) even when nothing downstream uses parallelism.

## Verification (MATLAB R2023b, real dev box + real recording; no synthetic-only claims)

- **`checkcode('irc.m')`** — no new messages on any edited line.
- **Part A, GPU == CPU:** `nearest_in_set_` bit-identical indices GPU vs CPU (`isequal` true, 0 mismatches)
  on synthetic input; Step 0 confirmed the same (index match 1.0000) on the real 587k-spike site.
- **Part A, CPU-only path:** 2-arg call (`nargin<3`) unchanged.
- **Part A, parfor guard:** `nearest_in_set_(...,true)` called from inside 2 `parfor` workers returns
  results matching the CPU reference exactly (`getCurrentTask()` → GPU declined → CPU used); serial GPU
  still works after pool teardown.
- **Part A, CPU fallback:** the GPU-upload-failure route (`fGpu_ok=0`) and the parfor-guard route both hit
  the CPU loop and are verified correct; the mid-loop GPU-exception catch falls through to that same proven
  CPU loop (verified by construction — a clean live GPU exception can't be forced without contrived fault
  injection, since the VRAM budget prevents OOM and `gpuArray_` auto-resets/retries).
- **Part B, `max_workers_`:** returns 13 = `floor(0.85 × 16)` on this box (profile reports 16 workers, not
  the 20 physical cores); `factor=0.5` → 8. The real `.prm`'s `nWorkers_clust=12` sits below the 13 cap, so
  B is a **no-op for this recording** (`min(12,13)=12`) and only bites requests > 13.
- **Not run:** a full end-to-end `irc sort` on the real recording (multi-hour). The changes are localized
  and the default `maxSpk_persite_clust=[]` path is untouched.

## Files
- Modified: `matlab/irc.m`, `matlab/default.prm`.
- Added: `logs/changes_log20260718.md`.
