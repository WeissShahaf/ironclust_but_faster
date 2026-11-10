function S_report = repair_clu_sync(vcFile_in, vcFile_out)
% Repair a _jrc.mat whose S_clu.viClu has been remapped without its per-cluster
% arrays (or vice versa), by rebuilding viClu FROM the cviSpk_clu cache.
%
% [Usage]
% -----
% repair_clu_sync(vcFile_in)                % DRY RUN - reports only, writes nothing
% repair_clu_sync(vcFile_in, vcFile_out)    % writes the repaired copy to vcFile_out
% S_report = repair_clu_sync(...)           % returns the diagnostics as a struct
%
% [Background]
% -----
% S_clu holds the spike->cluster assignment twice: viClu (per-SPIKE labels) and
% cviSpk_clu (per-CLUSTER spike indices, plus viSite_clu/vnSpk_clu/vrPos*_clu keyed
% by the same index). S_clu_select_ reindexes the per-CLUSTER arrays but cannot touch
% viClu (its name ends in 'Clu', not '_clu'), so every caller must remap viClu itself.
% Callers that fail to - reorder_clu_by_coords_ (fixed 2026-07-15), or delete_clu_ when
% its try/catch swallows an S_clu_select_ failure - leave the two describing the SAME
% partition under DIFFERENT numbering. Views read the cache; split_clu_ rebuilds from
% viClu; the two disagree and cluster identity is silently swapped.
% See logs/investigation_split_root_cause.md.
%
% [Direction - READ THIS]
% -----
% This rebuilds viClu FROM the cache. Whether that is the RIGHT direction is a JUDGEMENT,
% not a measurement:
%   The GUI displays the cache, so the clusters the user inspected and curated are the
%   cache's clusters. Relabelling viClu to the cache matches what the user actually saw.
%
% ** The "direction check" below is CIRCULAR and proves nothing. ** vnSpk_clu (irc.m:7401),
% viSite_clu (irc.m:7407) and vrPosY_clu (S_clu_subsample_spk_:11652) are all DERIVED FROM
% cviSpk_clu. S_clu_select_ permutes the cache and its derivatives together as a unit, so
% they agree with each other by construction - whether the cache is pristine or garbage.
% The check is retained only because it rules out one narrow alternative (cache alone stale
% while viSite_clu tracked viClu). It is NOT evidence the cache is correct.
%
% Likewise the S_clu_assert_synced_ verification is near-vacuous: it compares viClu against
% the cache, which this function forces to agree. It can only fail when the cache is not a
% partition (overlaps) - which, on the observed files, it is not.
%
% Do NOT "repair" with S_clu_refresh_: it rebuilds the cache FROM viClu - the opposite
% direction - and would lock the corruption in irreversibly.
%
% Negative viClu values are DELETED clusters. They are preserved, but a cache entry that
% still holds a deleted cluster's spikes will RESURRECT it - this function refuses to write
% if that happens.
%
% [Status: 2026-07-15]
% -----
% The repair path DOES NOT WORK on the observed files (cache overlaps -> not a partition;
% 413k orphans; deleted clusters resurrected). It correctly refuses. Retained for its
% DIAGNOSTICS. See logs/investigation_split_root_cause.md.

if nargin < 2, vcFile_out = ''; end
fDry = isempty(vcFile_out);
fprintf('=== repair_clu_sync %s ===\n', ternary_(fDry, '(DRY RUN - nothing will be written)', '(WRITE MODE)'));
fprintf('  in : %s\n', vcFile_in);
if ~fDry, fprintf('  out: %s\n', vcFile_out); end
if ~exist(vcFile_in, 'file'), error('repair_clu_sync: input not found: %s', vcFile_in); end
if ~fDry && strcmpi(vcFile_in, vcFile_out)
    error('repair_clu_sync: refusing to overwrite the input. Write to a new file.');
end

m = matfile(vcFile_in);
S_clu = m.S_clu;
viSite_spk = m.viSite_spk;
viClu0 = S_clu.viClu(:);
cvi = S_clu.cviSpk_clu;
nSpk = numel(viClu0);
% Do NOT silently min() these: if they disagree, every cache entry above nClu would be
% dropped and its spikes orphaned without the loop below ever seeing them.
fClu_mismatch = double(S_clu.nClu) ~= numel(cvi);
if fClu_mismatch
    fprintf(2, 'repair_clu_sync: nClu (%d) ~= numel(cviSpk_clu) (%d) - structure is inconsistent.\n', ...
        double(S_clu.nClu), numel(cvi));
end
nClu = min(double(S_clu.nClu), numel(cvi));

% ---------------------------------------------------------------- 1. current state
fprintf('\n--- BEFORE ---\n');
nBad0 = assert_ran_(S_clu_assert_synced_(S_clu, 'before-repair'), 'before-repair');
fprintf('  stale clusters              : %d / %d\n', nBad0, nClu);
fprintf('  spikes total                : %d\n', nSpk);
fprintf('  positive labels (assigned)  : %d\n', sum(viClu0 > 0));
fprintf('  negative labels (deleted)   : %d  (min=%d -> %d delete ops)\n', ...
    sum(viClu0 < 0), min(viClu0), abs(min(min(viClu0),0)));
fprintf('  zero labels (unassigned)    : %d\n', sum(viClu0 == 0));

% ------------------------------------------------- 2. is the cache really the truth?
[nSite_cache, nSite_viClu, nCmp] = deal(0);
for i = 1:nClu
    b = cvi{i}(:);
    a = find(viClu0 == i);
    if isempty(a) || isempty(b), continue; end
    if max(b) > nSpk || min(b) < 1, continue; end
    nCmp = nCmp + 1;
    s = double(S_clu.viSite_clu(i));
    if s == mode(double(viSite_spk(b))), nSite_cache = nSite_cache + 1; end
    if s == mode(double(viSite_spk(a))), nSite_viClu = nSite_viClu + 1; end
end
pct_cache = 100*nSite_cache/max(nCmp,1);
pct_viClu = 100*nSite_viClu/max(nCmp,1);
fprintf('\n--- DIRECTION CHECK (which side do the other per-cluster arrays follow?) ---\n');
fprintf('  viSite_clu agrees with cache : %d/%d (%.1f%%)\n', nSite_cache, nCmp, pct_cache);
fprintf('  viSite_clu agrees with viClu : %d/%d (%.1f%%)\n', nSite_viClu, nCmp, pct_viClu);
fCacheAuthoritative = nSite_cache > nSite_viClu * 1.5;
if fCacheAuthoritative
    fprintf('  ==> cache is authoritative. Rebuilding viClu FROM the cache is correct.\n');
else
    fprintf(2, '  ==> cache is NOT clearly authoritative. This repair is the WRONG direction.\n');
end

% ---------------------------------------------------------------- 3. sanity of cache
viCount = zeros(nSpk, 1, 'uint8');   % how many cache entries claim each spike
nOutOfRange = 0;
for i = 1:nClu
    v = cvi{i}(:);
    if isempty(v), continue; end
    if max(v) > nSpk || min(v) < 1, nOutOfRange = nOutOfRange + 1; continue; end
    viCount(v) = min(uint8(255), viCount(v) + uint8(1));
end
nDup = sum(viCount > 1);
nCovered = sum(viCount == 1);
fprintf('\n--- CACHE SANITY ---\n');
fprintf('  clusters with out-of-range indices : %d\n', nOutOfRange);
fprintf('  spikes claimed by >1 cluster       : %d  %s\n', nDup, ternary_(nDup>0,'<-- OVERLAP, ambiguous','') );
fprintf('  spikes claimed by exactly 1        : %d\n', nCovered);

% ------------------------------------------------------------- 3b. PURITY (not circular)
% The one honest question: are cache and viClu the SAME partition under different labels
% (a pure relabelling, sigma exists, repair is safe on identity grounds), or DIFFERENT
% partitions (sigma does not exist, and no relabelling can reconcile them)?
% Pure relabelling  <=> every cache entry maps onto exactly ONE viClu label.
vnLabels_clu = zeros(nClu, 1);
for i = 1:nClu
    v = cvi{i}(:);
    if isempty(v), continue; end
    if max(v) > nSpk || min(v) < 1, continue; end
    vnLabels_clu(i) = numel(unique(viClu0(v)));
end
vlTested = vnLabels_clu > 0;
nPure = sum(vnLabels_clu == 1);
nMixed = sum(vnLabels_clu > 1);
fprintf('\n--- PURITY: is this a pure relabelling? (the ONE non-circular check) ---\n');
fprintf('  cache entries spanning exactly 1 viClu label : %d / %d\n', nPure, sum(vlTested));
fprintf('  cache entries spanning >1 viClu label        : %d  %s\n', nMixed, ...
    ternary_(nMixed>0, '<-- DIFFERENT PARTITIONS, not a relabelling', ''));
if nMixed > 0
    fprintf('  max labels in one cache entry                : %d\n', max(vnLabels_clu));
    fprintf(2, '  ==> cache and viClu describe DIFFERENT partitions. No relabelling reconciles them.\n');
else
    fprintf('  ==> pure relabelling: labels are arbitrary, so rebuilding viClu is identity-safe.\n');
end

% ---------------------------------------------------------------- 4. the repair
viClu1 = viClu0;
viClu1(viClu1 > 0) = 0;              % clear assigned; keep negatives (deleted)
nResurrect = 0;
for i = 1:nClu
    v = cvi{i}(:);
    if isempty(v), continue; end
    if max(v) > nSpk || min(v) < 1, continue; end
    % A cache entry can still hold a DELETED cluster's spikes: delete_clu_ (irc.m:9139)
    % marks viClu negative, but if struct_select_safe_ (19524) silently skipped
    % cviSpk_clu, that entry was never pruned. Assigning +i here would not merely
    % resurrect them - if the per-cluster arrays at slot i WERE compacted, the spikes
    % land inside a DIFFERENT, legitimately-kept cluster and contaminate its identity.
    vlDel = viClu0(v) < 0;
    if any(vlDel)
        nResurrect = nResurrect + sum(vlDel);
        v = v(~vlDel);
        if isempty(v), continue; end
    end
    viClu1(v) = cast(i, 'like', viClu0);
end

% ---------------------------------------------------------------- 5. what changed
vlWasPos = viClu0 > 0;
nLost    = sum(vlWasPos & viClu1 == 0);     % assigned before, orphaned after
nGained  = sum(viClu0 == 0 & viClu1 > 0);
nMoved   = sum(vlWasPos & viClu1 > 0 & viClu0 ~= viClu1);
nSame    = sum(vlWasPos & viClu0 == viClu1);
nNegKept = sum(viClu0 < 0 & viClu1 == viClu0);
fprintf('\n--- CHANGES ---\n');
fprintf('  spikes keeping their label   : %d\n', nSame);
fprintf('  spikes RE-LABELLED           : %d\n', nMoved);
fprintf('  spikes newly assigned (0->N) : %d\n', nGained);
fprintf('  spikes ORPHANED (N->0)       : %d  %s\n', nLost, ternary_(nLost>0,'<-- in no cache entry','') );
fprintf('  deleted labels preserved     : %d / %d  %s\n', nNegKept, sum(viClu0 < 0), ...
    ternary_(nNegKept < sum(viClu0<0), '<-- DELETIONS LOST', ''));
fprintf('  deleted spikes still in cache: %d  %s\n', nResurrect, ternary_(nResurrect>0, ...
    '<-- would have been RESURRECTED / merged into a live cluster; excluded', ''));

% ---------------------------------------------------------------- 6. verify
S_rep = S_clu; S_rep.viClu = viClu1;
fprintf('\n--- AFTER ---\n');
nBad1 = assert_ran_(S_clu_assert_synced_(S_rep, 'after-repair'), 'after-repair');
fprintf('  stale clusters : %d / %d   (was %d)\n', nBad1, nClu, nBad0);

nNeg0 = sum(viClu0 < 0);
S_report = struct('nBad_before', nBad0, 'nBad_after', nBad1, 'nClu', nClu, ...
    'pct_cache', pct_cache, 'pct_viClu', pct_viClu, 'fCacheAuthoritative', fCacheAuthoritative, ...
    'nRelabelled', nMoved, 'nOrphaned', nLost, 'nGained', nGained, 'nDup', nDup, ...
    'nOutOfRange', nOutOfRange, 'nNeg_kept', nNegKept, 'nNeg_before', nNeg0, ...
    'nPure', nPure, 'nMixed', nMixed, 'fClu_mismatch', fClu_mismatch, ...
    'nResurrect', nResurrect);

% ---------------------------------------------------------------- 7. write
% Every one of these was previously measured, printed, and then IGNORED at the gate.
% They are hard refusals now: each means the repair silently invents data.
csRefuse = {};
if nBad1 ~= 0
    csRefuse{end+1} = sprintf('did not converge (%d stale clusters remain)', nBad1);
end
if nMixed > 0
    csRefuse{end+1} = sprintf(['%d cache entries span >1 viClu label: the two sides are ' ...
        'DIFFERENT partitions, not a relabelling'], nMixed);
end
if nDup > 0
    csRefuse{end+1} = sprintf(['%d spikes are claimed by >1 cache entry: the cache is not a ' ...
        'partition, so the rebuild is last-wins/ambiguous'], nDup);
end
if nNegKept < nNeg0   % belt-and-braces: the exclusion above should make this unreachable
    csRefuse{end+1} = sprintf(['%d deleted spikes LOST their deletion despite the exclusion ' ...
        '(%d negatives before, %d preserved)'], nNeg0 - nNegKept, nNeg0, nNegKept);
end
if nResurrect > 0
    csRefuse{end+1} = sprintf(['%d deleted spikes are still sitting in cache entries: proof ' ...
        'those entries were never pruned by delete_clu_, i.e. the cache is demonstrably stale'], ...
        nResurrect);
end
if nLost > 0
    csRefuse{end+1} = sprintf('%d spikes would be ORPHANED (assigned before, in no cache entry after)', nLost);
end
if nOutOfRange > 0
    csRefuse{end+1} = sprintf('%d cache entries hold out-of-range spike indices', nOutOfRange);
end
if fClu_mismatch
    csRefuse{end+1} = 'nClu disagrees with numel(cviSpk_clu)';
end
if ~fCacheAuthoritative
    csRefuse{end+1} = 'direction check did not favour the cache (note: this check is circular - weak evidence either way)';
end

fprintf('\n--- VERDICT ---\n');
if isempty(csRefuse)
    fprintf('  Repair is self-consistent: 0 stale clusters, cache is a clean partition,\n');
    fprintf('  no orphans, no resurrections. NOTE: this means the result is WELL-FORMED,\n');
    fprintf('  not that the cache numbering is CORRECT - that remains a judgement.\n');
else
    fprintf(2, '  REFUSING - the repair would corrupt this file:\n');
    for i = 1:numel(csRefuse), fprintf(2, '    %d. %s\n', i, csRefuse{i}); end
end
if fDry
    fprintf('\n  DRY RUN - nothing written. Re-run with an output path to apply.\n');
    return;
end
if ~isempty(csRefuse)
    error('repair_clu_sync: refusing to write (%d blocking problems, see verdict above).', numel(csRefuse));
end
fprintf('\n  writing %s ...\n', vcFile_out);
S0 = load(vcFile_in);
S0.S_clu = S_rep;
save(vcFile_out, '-struct', 'S0', '-v7.3');
fprintf('  done.\n');
end %func


%--------------------------------------------------------------------------
function out = ternary_(c, a, b)
if c, out = a; else, out = b; end
end %func


%--------------------------------------------------------------------------
function n = assert_ran_(n, vcWhen)
% irc('call',...) -> call_ (irc.m:20666) -> test_ (irc.m:20646-20649) SWALLOWS any
% dispatch error and returns []. A bare `if n ~= 0` on [] evaluates to false, so a
% verification that never ran would read as "0 stale clusters" and PASS the gate.
% Never let an un-run check look like a passing one.
if ~isscalar(n) || ~isnumeric(n)
    error(['repair_clu_sync: the %s verification did not run (S_clu_assert_synced_ ' ...
        'returned empty/non-scalar). Is a current irc.m on the MATLAB path? ' ...
        'Refusing to continue - an un-run check must never read as a pass.'], vcWhen);
end
end %func


%==========================================================================
% call irc.m
function out1 = S_clu_assert_synced_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
