# Changes Log - July 16, 2026

> **Tracker:** [`logs/ISSUE_TRACKER_cluster_identity.md`](ISSUE_TRACKER_cluster_identity.md)
> **Plan:** [`logs/plan_cluster_identity_hardening_20260716.md`](plan_cluster_identity_hardening_20260716.md)

## Summary

Cluster-identity **hardening** pass, implementing the detection/abort-handling plan drafted the
same day. The desync *class* was already closed in `87cd4f1`/`d954926` (all 5 `S_clu_select_`
callers remap `viClu`, sort path measured `0/547` stale). This pass closes the remaining
**detection** and **abort-surfacing** gaps — it changes no spike data.

Work proceeds in plan order (P1 → P3a → P2 → P3b), each shipped only with a negative control that
fails without the change.

## P1 — load-time desync detection (`load0_`) — DONE

**Problem.** `load0_` (`irc.m`) did a bare `load` + `set(0,'UserData',S0)` with **no validation**.
Every pre-fix corrupted `_jrc.mat` (including the user's) reopened **silently**; a viClu/cviSpk_clu
desync on disk was only surfaced when the user next *committed* an operation.

**Change.** After the load succeeds and `UserData` is set (right after the recursive-`S0` rmfield),
run the existing warn-only `S_clu_assert_synced_` on `S0.S_clu`. On a positive count, print a
one-line pointer to the CID-12 recovery guidance.

```matlab
if isstruct(S0) && isfield(S0, 'S_clu') && ~isempty(S0.S_clu)
    if S_clu_assert_synced_(S0.S_clu, ['load: ' vcFile_mat]) > 0
        fprintf(2, ['\tThis file was saved with a viClu/cviSpk_clu desync. Curating it may ' ...
            'compound the damage; re-sorting is the clean recovery. ' ...
            'See logs/ISSUE_TRACKER_cluster_identity.md (CID-12).\n']);
    end
end
```

**Why safe.** `S_clu_assert_synced_` is O(nSpk), warn-only, gated internally by `fCheck_clu_sync`
(default 1), and wrapped so it can never break a load. On a fresh sort it prints nothing; on a
corrupted file it names the affected clusters at open time. Additive.

## P3a — sync check on the `[O]` reorder path (`reorder_clu_by_coords_`) — DONE

**Problem.** `reorder_clu_by_coords_` writes straight to disk via `save0_()`, bypassing
`S_clu_commit_` where `S_clu_assert_synced_` normally runs — so the detector was **blind on the one
path the original CID-01 desync lived on**.

**Change.** One warn-only line between `set0_(S_clu)` and `save0_()`:

```matlab
set0_(S_clu);
S_clu_assert_synced_(S_clu, 'reorder_clu_by_coords_');   % detector was blind on the [O] path
S0 = gui_update_();
save0_();
```

**Why safe.** Warn-only, never gates, no data change. Additive.

## Verification — P1 + P3a negative control

`scratchpad/verify_p1_p3a.m` (internal funcs reached via `irc('call', …)`):

| # | Case | Expected | Result |
|---|---|---|---|
| 1 | `S_clu_assert_synced_` on healthy synthetic `S_clu` | `nBad = 0` | PASS |
| 2 | same on a cache-swapped (desynced) `S_clu` | `nBad = 2 (>0)` | PASS |
| 3 | `load0_` on a healthy `_jrc.mat` | no CID-12 warning | PASS |
| 4 | `load0_` on a desynced `_jrc.mat` | CID-12 + STALE warning at open time | PASS |

`0 failures`. Both new sites invoke the same detector (tests 1–2); test 4 is the P1 negative control
(without the `load0_` edit, no warning is emitted on open). `checkcode` reports no new parse errors.

## P2 — propagate the abort signal to the callers — DONE

**Decisions (user, 2026-07-16):** explicit `fOk` output; **all four** call-site groups.

**Problem.** `delete_clu_`/`merge_clu_` already **roll back** on failure (returning an unchanged
`S_clu`), but their callers didn't *detect* it. On an abort a caller still shifted the pending-queue
indices as if a cluster were removed and appended a `save_log_` entry for an operation that didn't
happen — the data stayed consistent (rollback did its job) but the **log and pending-queue
bookkeeping** desynced from reality. `delete_auto_` additionally popped a *"Deleted N clusters"*
msgbox that would be a lie on abort.

**Change (P2-core).** `delete_clu_` and `merge_clu_` now return an optional 2nd output `fOk`
(`false` at each existing rollback `return`, `true` at the normal end). Initialised `false` at the
top so the rollback paths are untouched. Fully backward-compatible — single-output callers are
unaffected; no logic added to the verified `S_clu` transforms.

**Call-site guards (all gate on `~fOk`):**

| Site | Function | Behavior on abort |
|---|---|---|
| **P2a** | `execute_pending_and_update_` delete loop | skip the log entry **and** the index shift (the `csLog` append moved from *before* the delete to *after* success — the phantom-log source) |
| **P2b** | `execute_pending_and_update_` merge loop | **whole-group** snapshot before the group; a mid-group abort restores the group and logs nothing (a group merge is one user action → atomic). Log staged and committed only on full-group success. |
| **P2c** | `ui_merge_` | early return before overlay/index/log bookkeeping; closes the wait cursor; leaves `iCluPaste` valid to retry |
| **P2d** | `ui_delete_` | early return before redraw/log; closes the wait cursor |
| **P2d** | `delete_auto_` | gates the *"Deleted N clusters"* msgbox + log on `fOk`; shows an abort message instead |

**Why healthy behavior is byte-identical.** `fOk` is `false` only on an already-malformed
`cviSpk_clu` (the sole thing that makes `struct_select_` throw / the content-check fail). On
healthy or permutation-desynced state `fOk` is always `true`, so every `~fOk` guard is dead and the
code path matches today's exactly (verified: the merge-loop log concatenates in the same order).
The one remaining single-output `delete_clu_` caller is `merge_clu_`'s internal delete (it detects
the abort via its existing `nClu` check — unchanged).

**Verification — P2 negative control.** `scratchpad/verify_p2.m`:

| # | Case | Expected | Result |
|---|---|---|---|
| 1 | `delete_clu_` healthy, delete last cluster | `fOk=true`, `nClu 5→4`, fields resized | PASS |
| 2 | `delete_clu_` healthy, delete a low cluster | `fOk=true`, cache/`viClu` invariant holds | PASS |
| 3 | `delete_clu_` on length-malformed `cviSpk_clu` (one short) | `fOk=false`, `S_clu` **byte-identical** (clean rollback) | PASS |
| 4 | same | delete_clu_ printed an ABORT message (rollback path fired) | PASS |

`0 failures`. This is a **true negative control**: requesting `[S_clu, fOk]` *throws* against pre-P2
code (delete_clu_ had one output), so the suite cannot pass without P2-core. `fOk` is the single
signal all five sites consume; `merge_clu_`'s `fOk` reduces to its internal `delete_clu_` abort
(rollback logic unchanged, previously verified 5/5 on real data in `verify_merge_clu_real.m`).
`merge_clu_` can't be exercised end-to-end headlessly (needs waveform data; no `_jrc.mat` present),
so its `fOk` is verified by construction (flag set at its two existing return points) + parse-clean
`checkcode`. Caller edits are additive `~fOk` guards, never taken on healthy input (see above).

## P3b — make `cviSpk_clu` a critical field (`struct_select_safe_`) — DONE

**Decision (user, 2026-07-16):** implement (accept the crash-vs-silent-corruption trade).

**Problem (CID-11, the enabler).** `struct_select_safe_` skips any field it can't resize **and
returns normally**; `S_clu_select_`'s length-reconcile then pads `cviSpk_clu` with `{[]}` to the
right length. Net: content stale, length correct, no exception — the mechanism that converts a loud
crash into silent corruption.

**Change.** `struct_select_safe_` gains an optional 5th arg `csCritical`. A field named in it that
throws is **re-thrown** instead of skipped. `S_clu_select_`'s c-group call passes `{'cviSpk_clu'}`.
The v-group and t-group calls omit it (default `{}`), so their behavior is unchanged. Fully
localized — `struct_select_safe_` is called only by `S_clu_select_`.

**Behavior change (as flagged).** With `cviSpk_clu` critical, a resize failure propagates out of
`S_clu_select_`:
- `delete_clu_` — has try/catch → **rolls back cleanly** (the enabler's main route; abort message
  is now *"S_clu_select_ failed"* rather than the content-check message — both roll back).
- `S_clu_remove_empty_`, `S_clu_keep_`, `clu_reorder_`, `reorder_clu_by_coords_` — no try/catch →
  the exception is **uncaught and crashes that op**. This trades *silent corruption* for a *loud
  crash* (strictly better for data integrity — nothing is saved). The sweep confirmed these four run
  on consistent `S_clu` where `cviSpk_clu` never throws, so in practice it never fires.

**Verification — P3b negative control.** `scratchpad/verify_p3b.m`:

| # | Case | Expected | Result |
|---|---|---|---|
| A | `S_clu_select_` on healthy `S_clu` | no throw, `cviSpk_clu` resized correctly | PASS |
| B | `S_clu_select_` on length-malformed `cviSpk_clu` | **re-throws**, no *"skipped field"* message | PASS |
| C | `delete_clu_` on the malformed fixture | still rolls back (`fOk=false`, byte-identical) via rethrow→catch | PASS |

`0 failures`. **True negative control:** pre-P3b, case B returned normally (padded) instead of
throwing. Re-ran `verify_p2.m` after P3b → still 4/4 (`delete_clu_`'s rollback now routes through
the catch, unchanged outcome).

## X3 — `split_clu_` positional truncate/pad now hard-fails — DONE

**Decision (user, 2026-07-16):** hard-fail now.

**Problem.** `split_clu_`'s logical-mask branch silently **truncated** (`vlIn(1:nSpk1)`) or
**zero-padded** a `vlIn` whose length didn't match the cluster's spike list. A mismatch means the
caller built the mask against a different (or differently-ordered) population than `split_clu_`
re-derives via `get_clu_spk_confirmed_` — so the silent adjust misapplied the mask and split the
*wrong* spikes. The "final safety check" below it was dead code (the adjust forced the length).

**Change.** The length-mismatch case now **refuses loudly**: `fprintf(2, …)` + a `msgbox_`, closes
the wait message and cursor, and returns without splitting — reusing the function's existing
loud-abort idiom (same as the empty-selection guard), so no figures are left dangling. It points the
caller to `split_clu_by_id_` (absolute-id split, where `numel(vlIn)==numel(viSpk1)` holds by
construction). The interactive polygon paths already route through `split_clu_by_id_`; only
`auto_split_`/`cbf_split_psth_` reach this branch, and on a healthy sort the lengths always match, so
the guard never fires. The final safety check is kept as harmless defense-in-depth (now documented).

**Verification.** No data mutation and no behavior change on a matched mask (the common path);
`checkcode` parse-clean. `split_clu_` is GUI-blocking (needs the FigWav figure cache + sorted-data
globals) and, like CID-02, is not exercisable headlessly — verified by trace + syntax check. The
change is a pure control-flow *refuse-to-proceed*: strictly safer than silently cutting the wrong
spikes.

## Net summary

| Item | Status | irc.m functions | Verified |
|---|---|---|---|
| P1 | done | `load0_` | `verify_p1_p3a.m` 4/4 |
| P3a | done | `reorder_clu_by_coords_` | `verify_p1_p3a.m` 4/4 |
| P2-core + P2a–d | done | `delete_clu_`, `merge_clu_`, `execute_pending_and_update_`, `ui_merge_`, `ui_delete_`, `delete_auto_` | `verify_p2.m` 4/4 |
| P3b | done | `struct_select_safe_`, `S_clu_select_` | `verify_p3b.m` 3/3 |
| X3 | done | `split_clu_` | trace + `checkcode` |

No functions deleted; all changes additive or fail-loud, per `CLAUDE.md`. Deferred (independent):
X1 (`viClu_prematch` dead weight, CID-15), X2 (PSTH split routing), X4 (probe shanks, CID-14 — a
`.prb` data fix). Detection/abort-handling gaps from the plan are now closed.
