# Plan: `irc recurate` — curation GUI from a fresh auto clustering, no load-prompt

*(First implementation step: copy this file to `logs/PLAN_irc_recurate.md` in the repo — plan mode
blocks creating it now.)*

## Context

`irc('manual', prm)` always opens with the modal **"Load last saved or recompute?"** dialog
(`irc.m:6059`), and there is no way to pre-answer it. The only suppression mechanism is the global
`fDebug_ui`, which forces `'Yes'` for *every* dialog (`questdlg_`, `irc.m:21845`) — the wrong answer
and far too broad — and `manual_` hard-resets it to 0 at `irc.m:6052` before the dialog anyway. The
one existing no-prompt recompute path, `irc manual-test` → `manual_(P,'debug')` (`irc.m:249`), also
sets `fDebug_ui = 1`, making every later GUI confirmation auto-"Yes" — unsafe for real curation.

Goal: a command that opens the same GUI, always takes the **recompute** branch (a clean AUTO
baseline to curate from), behind one explicit consent dialog.

**Honest scope note.** With the consent dialog the user asked for, this saves *zero clicks* versus
`irc manual` → "No". The gain is determinism and self-documentation: you cannot mis-click into the
wrong branch, and the intent is legible in a command history. That is the whole benefit — worth
weighing before building it.

## Reviews performed

Three independent read-only reviews (architect, regression, devil's advocate). Architecture and
regression safety came back **clean**; the design (extending `manual_`'s `vcMode` switch) was
confirmed as the *correct* idiom, not merely acceptable. The devil's advocate found two real
problems, both verified first-hand against the code.

### ⚠ Finding 1 — `CLAUDE.md:207` is wrong: `viClu_premerge` is NOT write-once

`irc.m:3967` `S_clu.viClu_premerge = S_clu.viClu;` runs **unconditionally on every `post_merge_`**.

This matters independently of this feature. `postCluster_` is skipped when `fLabelClu`
(`irc.m:3959`, covering kmeans/hdbscan/isosplit/classix), so for those sorts `viClu` at line 3967 is
still the **curated** labelling — every `post_merge_` + save overwrites the pristine snapshot with
curated labels, silently and permanently disabling `recover_from_snapshot.m` for that file. DPC
sorts are safe because `postCluster_` regenerates `viClu` first.

Live relevance: the cuniform sorts are isosplit/hdbscan. Nothing is currently broken — the cuniform
pilot was reverted to `resync_clu` — but the documented guarantee is false and must be corrected.

**Actions:** (a) fix the `CLAUDE.md` claim; (b) have `recurate`'s consent dialog name this
consequence when `fLabelClu` is true; (c) file — do **not** bundle — a separate proposal to make
`irc.m:3967` write-once, since that changes `post_merge_` for the sort pipeline too.

### ⚠ Finding 2 — `clear_log_` destroys the only off-`_jrc.mat` copy of the notes

`clear_log_` (`irc.m:17239`) deletes `<prm>_log.mat` **immediately**, before any save prompt.
Everything else in the recompute branch is in-memory and abandonable by declining `save_manual_`
(`irc.m:6735`) — the log file is not. And `_log.mat` really does hold curation state:
`save_log_` writes `S_log` with `csNote_clu` (`irc.m:16755`) and `viClu` (`irc.m:16770`) via
`struct_save_` at `irc.m:16771`.

**Action:** `recurate` renames `<prm>_log.mat` → `<prm>_log.mat.bak_recurate` before calling
`clear_log_`, so the pre-recurate notes survive. Purely additive; `clear_log_` itself is untouched.

### Corrections to my earlier draft (from the reviews)

- The `_log.mat` reload at `irc.m:6107-6109` after `clear_log_` is **not** a bug — `load_` returns
  empty and `save_log_` writes fresh. The existing "No" branch already does exactly this, so the new
  mode inherits a proven path.
- **Drop the `'manual-recurate'` alias.** It contains the substring `'manual'`, so the greedy
  `contains_` fallback at `irc.m:294` would re-invoke `manual_(P)` — reopening the GUI with the very
  dialog we skip — if the `return;` were ever dropped. `'recurate'` alone matches none of
  `{'manual',' gui','ui'}`, which removes the hazard outright instead of guarding it.
- **Use `sprintf` with `\n`, not a cell array**, for the dialog message: all seven `questdlg_` call
  sites pass a single char array. Exact arity precedent: `irc.m:21135`.

## Implementation — 5 additive edits, nothing existing modified

**1. New mode in `manual_`'s switch (`irc.m:6055`), after `case 'normal'`:**

```matlab
    case 'recurate'
        % Skip the load-vs-recompute prompt; always recompute (== the 'normal' 'no'
        % branch) after explicit consent. Destructive: post_merge_ resets csNote_clu
        % (irc.m:3968) and clear_log_ DELETES <prm>_log.mat (irc.m:17239).
        if ~confirm_recurate_(P), return; end
        backup_log_file_(P);            % preserve <prm>_log.mat before clear_log_
        [S_clu, S0] = post_merge_(S0.S_clu, P);
        S0 = clear_log_(S0);
```

`S_clu` unused: deliberate parity with `irc.m:6061`.

**2. `confirm_recurate_(P)`** — returns logical; message via `sprintf`, buttons **OK / Cancel**,
default **Cancel**. Names: merges/splits/deletes lost, unit notes lost (and that
`note=='single'` is the only downstream unit selector), `_log.mat` backed up then removed, and —
when `fLabelClu` is true for this sort — that `viClu_premerge` will be overwritten.

OK/Cancel is chosen over Yes/No deliberately: under `fDebug_ui==1` `questdlg_` returns `'Yes'`,
which with Yes/No would mean *proceed destructively* in a headless run; with OK/Cancel it matches
neither button and falls to Cancel.

**3. `backup_log_file_(P)`** — if `<prm>_log.mat` exists, `copyfile` it to `<prm>_log.mat.bak_recurate`
(overwriting a previous backup), printing the path. Mirrors the `.bak` convention of
`atomic_replace_` (`irc.m:15281`).

**4. Dispatch** — in the Type-C switch beside `case 'manual-gt'` (`irc.m:216`):

```matlab
    case 'recurate', manual_(P, 'recurate'); return;   % return: matches manual-gt/manual-test
```

Type C is correct — `P` is loaded at `irc.m:211` before that switch.

**5. Help text** — three lines after the `irc manual` entries (`irc.m:443-446`).

## Files

- `matlab/irc.m` — new `case` in `manual_` (~6068), `confirm_recurate_`, `backup_log_file_`,
  dispatch case (~216), help lines (~446).
- `matlab/CLAUDE.md` — **correct the `viClu_premerge` write-once claim (line ~207)**; document
  `recurate`.
- `logs/PLAN_irc_recurate.md` — this plan.
- `logs/ISSUE_viClu_premerge_not_write_once.md` — new: Finding 1 plus the `miClu_log` issue below.

Out of scope: `irc2.m` / `irc2_manual.m` (different mechanism — `irc2_manual.m:11` only prompts when
`<prm>_manual_irc.mat` exists, and "no" merely rebuilds `S_manual`; no `post_merge_`, no log delete).

## Separate finding to file, not fix here

`miClu_log` is never persisted — `save_log_` writes only `S_log` (the `cS_log` save at `irc.m:16769`
is commented out). On a fresh session it initialises to zeros (`irc.m:16765`), so the history menu's
`restore_log_(2)` would restore an all-zero `viClu` (`irc.m:16828`). Pre-existing, unrelated to this
change, and needs its own verification pass.

## Verification

1. `checkcode('irc.m')` → 0 parse errors.
2. `git diff` shows **only additions**; nothing inside `irc.m:6058-6068` (`case 'normal'`) changes.
3. `irc('recurate')` with no prm fails like `irc('manual')` does, not via `help_()`.
4. **Consent blocks**: on a scratchpad **copy**, run `irc('recurate', copy.prm)` → Cancel. GUI does
   not open; `_log.mat` present and unmodified; `_jrc.mat` mtime unchanged; no `.bak_recurate`.
5. **Recompute path**: same copy → OK. GUI opens; `_log.mat.bak_recurate` exists with the original
   content; `_log.mat` recreated fresh by `save_log_('start')`; `S_clu.csNote_clu` all empty.
   Cluster count identical to `irc('manual', copy.prm)` → "No".
6. **fLabelClu warning**: repeat 4 on an isosplit/hdbscan copy (a cuniform sort) and confirm the
   dialog names the `viClu_premerge` consequence.
7. **No regression**: `irc('manual', copy.prm)` still prompts; "Yes" opens with curation intact.

Steps 4-7 run on a **copy** (`.prm`, `_jrc.mat`, `_spk*` and `_log.mat` siblings) in the scratchpad —
never on a remediated production sort.
