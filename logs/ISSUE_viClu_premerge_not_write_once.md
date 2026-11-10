# `viClu_premerge` is not write-once (+ `miClu_log` is never persisted)

Found 2026-08-02 during the design review for `irc recurate`, by a devil's-advocate review pass;
both items verified first-hand against `matlab/irc.m` before filing. Neither is fixed — this is the
record and the proposal.

---

## Issue 1 — `S_clu.viClu_premerge` is overwritten on every `post_merge_`

**Claim that was wrong.** `matlab/CLAUDE.md` described `viClu_premerge` as a *"pristine write-once
snapshot"*, and the field remediation of the 22 corrupt sorts leaned on that when choosing
`recover_from_snapshot.m`.

**Reality.** In `post_merge_`, immediately before the `csNote_clu` reset:

```matlab
S_clu = S_clu_position_(S_clu);
S_clu.viClu_premerge = S_clu.viClu;      % <-- unconditional, every call
S_clu.csNote_clu = cell(S_clu.nClu, 1);  %reset note
```

There is no `isfield`/`isempty` guard. Every `post_merge_` rewrites it.

### Why it is usually harmless, and when it is not

`post_merge_` runs `postCluster_` **only** when `~fLabelClu`:

```matlab
fLabelClu = get_set_(S_clu, 'fLabelClu', 0) || ...
    ismember(lower(get_set_(P, 'vcCluster', '')), {'kmeans','hdbscan','isosplit','isosplit5','isosplit6','classix'});
...
if fPostCluster && ~fLabelClu, S_clu = postCluster_(S_clu, P); end
```

- **DPC sorts (`~fLabelClu`)** — `postCluster_` deletes and regenerates `viClu` from the density
  graph, so the value stored into `viClu_premerge` *is* a genuine auto baseline. Safe.
- **Label-based sorts (`fLabelClu`: kmeans / hdbscan / isosplit / classix)** — `postCluster_` is
  skipped, so `viClu` is still whatever `struct_copy_` carried in: the **curated** labelling. The
  snapshot is overwritten with curated labels, and `recover_from_snapshot.m` can no longer restore
  a pristine baseline for that file. Silent — nothing warns, and the `_jrc.mat` still passes the
  `viClu`⇄`cviSpk_clu` sync check.

### What triggers it
Any path that reaches `post_merge_` and then saves: `irc manual` → **"No"**, the new
`irc recurate`, `irc auto`, and `recover_from_snapshot.m` itself.

### Blast radius here
The cuniform sorts are isosplit/hdbscan, i.e. exactly the `fLabelClu` case. Nothing is currently
broken — the cuniform pilot was reverted from `recover_from_snapshot` to `resync_clu` on 2026-07-26
for the unrelated `csNote_clu` reason — but the guarantee the docs advertised does not exist.

### Proposed fix (NOT applied — changes the sort pipeline)

Make the assignment write-once:

```matlab
if ~isfield(S_clu, 'viClu_premerge') || isempty(S_clu.viClu_premerge)
    S_clu.viClu_premerge = S_clu.viClu;
end
```

**Why it was not bundled with `irc recurate`:** `post_merge_` is on the main sort path
(`irc sort`/`irc auto`), so this is a behaviour change to a healthy default path — precisely what
`CLAUDE.md`'s "additive or fixes only / preserve existing functionality" rule says to isolate. It
needs its own before/after test on a real recording, and a decision about existing files whose
snapshot is already overwritten (the fix cannot recover those).

**Interim mitigation, shipped:** `irc recurate`'s consent dialog names this consequence when the
sort is label-based (`confirm_recurate_`), and `CLAUDE.md` now carries the correction.

---

## Issue 2 — `miClu_log` is never persisted, so `restore_log_` can zero `viClu`

`save_log_` builds the in-memory undo history:

```matlab
if isempty(miClu_log)
    miClu_log = zeros([numel(S_clu.viClu), P.MAX_LOG], 'int16');
end
miClu_log(:, 2:end) = miClu_log(:, 1:end-1);
miClu_log(:, 1) = int16(S_clu.viClu);
%struct_save_(strrep(P.vcFile_prm, '.prm', '_log.mat'), 'cS_log', cS_log);   % <-- COMMENTED OUT
S_log.viClu = int16(S_clu.viClu);
struct_save_(S_log, strrep(P.vcFile_prm, '.prm', '_log.mat'), 0);
```

Only `S_log` (the latest `vcCmd`/`datenum`/`csNote_clu`/`viClu`) reaches disk. **`miClu_log` is
never saved and never loaded** — `manual_` restores only `S0.cS_log` from `<prm>_log.mat`.

So in a fresh session `miClu_log` starts as all zeros, and the history menu's `restore_log_(iMenu)`
for any depth ≥ 2 would restore an all-zero `viClu`.

**Status:** believed pre-existing and unrelated to any recent change. **Not verified end-to-end** —
the exact menu-enable conditions were not traced, so it is possible the affected menu items are
disabled in a fresh session and the bug is unreachable. Needs its own reproduction before any fix.

---

## Follow-ups

1. Decide on the write-once guard for `viClu_premerge`; if adopted, test on a real recording and
   document that pre-existing files cannot be retro-fixed.
2. Reproduce or rule out the `miClu_log` restore path.
3. Consider a read-only checker that reports whether a given `_jrc.mat`'s `viClu_premerge` still
   differs from its `viClu` — a cheap proxy for "is my snapshot still pristine?" — and wire it into
   the existing `check_jrc_*` diagnostics.
