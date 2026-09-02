function tResult = sweep_post_merge(vcFile_prm, mnSweep, isi_thresh)
% In-memory post-merge parameter sweep for LABEL-BASED sorts (isosplit/kmeans/hdbscan/classix).
% For each row, resets viClu to the raw pre-merge baseline (viClu_premerge) and re-runs
% post_merge_ with the given [post_merge_mode, maxWavCor]. NOTHING is written to disk.
%
% Why reset first: irc('auto') re-merges on TOP of the current (already-merged) viClu and
% compounds. To compare merge settings fairly they must all start from the same baseline --
% the raw isosplit labels stored in S_clu.viClu_premerge (irc.m:3973).
%
% Picking a winner WITHOUT the GUI: nClu alone can't tell a good merge from a bad one, so each
% row also reports the two quantities that flag the two failure modes, from fields post_merge_
% already computes:
%   nRefrac  = # units with ISI refractory-violation ratio > isi_thresh (S_clu.vrIsiRatio_clu).
%              OVER-merging two neurons into one creates refractory violations -> want this LOW.
%   nDup     = # cluster pairs still split with waveform corr >= maxWavCor (upper tri of
%              S_clu.mrWavCor). UNDER-merging leaves near-duplicates -> want this LOW.
%              NOTE: mrWavCor on label sorts is same-peak-site biased, so nDup is a floor on
%              cross-site duplicates, not the full count -- use it as a relative signal.
%   medIsi   = median ISI-violation ratio across units (overall contamination trend).
% Rank by: fewest nRefrac and fewest nDup at a biologically plausible nClu. Then bake in the
% winner with irc('reset-to-premerge') and eyeball a few in irc('manual').
%
% Usage:
%   irc('addpath');                              % ensure irc.m is on the path
%   sweep_post_merge(prm)                        % default sweep (mode 8/17 x maxWavCor 0.985/0.97)
%   sweep_post_merge(prm, [17 0.985; 17 0.97; 17 0.96; 8 0.985])
%   sweep_post_merge(prm, [], 0.10)              % stricter refractory threshold
%
%   % CHAINS (sequential multi-stage merges): pass a CELL, each element an Nx2
%   % [mode maxWavCor; ...] applied in order from ONE baseline reset (no reset between stages).
%   sweep_post_merge(prm, {[17 .985; 4 .985], [4 .985; 17 .985]})   % 17->4 vs 4->17
%
% Numeric input: each row is a single-stage experiment [post_merge_mode (scalar), maxWavCor].
% Cell input: each element is a chain of stages. Returns a table of results.

if nargin < 2 || isempty(mnSweep)
    mnSweep = [ 8, 0.985;      % current setting (baseline for comparison)
               17, 0.985;
               17, 0.970;
               17, 0.960 ];
end
if nargin < 3 || isempty(isi_thresh), isi_thresh = 0.2; end   % ISI-violation ratio "bad" cutoff

% ---- load once (the slow part) --------------------------------------------
So = irc('call', 'loadParam_', {vcFile_prm, 0}, 2);  P = So.out1;
fprintf('vcCluster=%s  (current post_merge_mode=%s, maxWavCor=%s)\n', ...
    gv(P,'vcCluster'), gv(P,'post_merge_mode'), gv(P,'maxWavCor'));

Sc = irc('call', 'load_cached_', {P}, 2);  S0 = Sc.out1;  P = Sc.out2;
S_clu_base = S0.S_clu;
set(0, 'UserData', S0);

% ---- baseline guard --------------------------------------------------------
assert(isfield(S_clu_base,'viClu_premerge') && ~isempty(S_clu_base.viClu_premerge), ...
    'sweep_post_merge:no_snapshot', ...
    'viClu_premerge is absent/empty -- cannot reset to the raw baseline. Re-sort instead.');
nClu_raw     = double(max(S_clu_base.viClu_premerge(:)));
nClu_current = double(max(S_clu_base.viClu(:)));
fprintf('baseline: viClu_premerge nClu=%d   current viClu nClu=%d\n', nClu_raw, nClu_current);
% Heuristic: a fresh label-based sort over-segments, so the raw baseline should have many MORE
% clusters than the merged result. If it does not, viClu_premerge was likely overwritten by a
% prior irc('auto')/recurate (it is rewritten on every post_merge_, irc.m:3973) -> results suspect.
if nClu_raw <= nClu_current * 1.05
    fprintf(2, ['  WARNING: viClu_premerge is not substantially larger than the merged viClu. ', ...
        'It may have been overwritten by a prior auto/recurate; the sweep baseline may NOT be the\n', ...
        '  original isosplit labels. If unsure, do one full irc(''sort'') and sweep on that fresh file.\n']);
end

% ---- normalize to a cell of chains (each chain = Nx2 [mode maxWavCor] stages) --------------
% Numeric matrix -> each row is a single-stage experiment. Cell -> each element a chain that is
% applied in sequence from ONE baseline reset (stages compound; NO reset between stages).
% Chaining runs post_merge_ more than once, which is not its designed single-shot flow -- treat
% it as experimental. If a later stage errors it is likely a field the previous stage dropped.
if iscell(mnSweep)
    ccStages = mnSweep(:);
else
    ccStages = cell(size(mnSweep,1),1);
    for i = 1:size(mnSweep,1), ccStages{i} = mnSweep(i,:); end
end
fChain = any(cellfun(@(x)size(x,1) > 1, ccStages));   % any multi-stage experiment?
nExp = numel(ccStages);

% ---- sweep -----------------------------------------------------------------
[viMode, vrCor, vnClu, vnRefrac, vnDup, vrMedIsi, vlSync, vrSec] = deal(nan(nExp,1));
csChain = cell(nExp,1);
for iExp = 1:nExp
    mnStages = ccStages{iExp};
    S_clu = S_clu_base;
    S_clu.viClu = S_clu_base.viClu_premerge;      % reset to raw baseline ONCE per experiment
    t1 = tic;
    for iStage = 1:size(mnStages,1)               % apply stages in order (no reset between)
        P.post_merge_mode  = mnStages(iStage,1);  % scalar (DI-18)
        P.post_merge_mode0 = mnStages(iStage,1);  % inert on label sorts; keep consistent
        P.maxWavCor        = mnStages(iStage,2);
        S_clu.P = P;
        S0.S_clu = S_clu; set(0,'UserData',S0);    % expose current state to internal get0_
        Sm = irc('call', 'post_merge_', {S_clu, P}, 2);  S_clu = Sm.out1;
    end
    sec = toc(t1);
    S_clu2 = S_clu;

    [nRefrac, medIsi] = isi_quality_(S_clu2, isi_thresh);   % over-merge signal
    nDup = dup_pairs_(S_clu2, mnStages(end,2));              % under-merge signal (final threshold)
    csChain{iExp} = chain_str_(mnStages);
    if size(mnStages,1) == 1, viMode(iExp) = mnStages(1,1); vrCor(iExp) = mnStages(1,2); end
    vnClu(iExp)    = S_clu2.nClu;
    vnRefrac(iExp) = nRefrac;
    vnDup(iExp)    = nDup;
    vrMedIsi(iExp) = medIsi;
    vlSync(iExp)   = is_synced_(S_clu2);
    vrSec(iExp)    = sec;
    fprintf('  [%d/%d] %-24s ->  nClu=%d  nRefrac=%d  nDup=%d  medIsi=%.3f  synced=%d  (%.1fs)\n', ...
        iExp, nExp, csChain{iExp}, S_clu2.nClu, nRefrac, nDup, medIsi, vlSync(iExp), sec);
end

% Restore the in-memory cache to the on-disk state. load_cached_ reuses UserData for the same
% .prm whenever S_clu is non-empty (irc.m:1149-1171) instead of reloading from disk, so leaving
% the last swept (unsaved) result here would make a later irc('manual'/'auto', prm) in THIS
% session silently operate on it rather than the disk _jrc.mat. Restoring the baseline keeps the
% cache valid (no slow reload) and consistent with disk.
S0.S_clu = S_clu_base; set(0, 'UserData', S0);

if fChain
    tResult = table(csChain, vnClu, vnRefrac, vnDup, vrMedIsi, vlSync, vrSec, ...
        'VariableNames', {'chain','nClu','nRefrac','nDup','medIsi','synced','sec'});
else
    tResult = table(viMode, vrCor, vnClu, vnRefrac, vnDup, vrMedIsi, vlSync, vrSec, ...
        'VariableNames', {'post_merge_mode','maxWavCor','nClu','nRefrac','nDup','medIsi','synced','sec'});
end
fprintf('\n=== sweep done (nothing saved; in-memory cache restored to disk state) ===\n');
fprintf('rank by: LOW nRefrac (less over-merge) + LOW nDup (less under-merge) at a plausible nClu.\n');
disp(tResult);
end %func

% --- "17@0.985 -> 4@0.985" label for a chain of [mode maxWavCor] stages ---------------------
function s = chain_str_(mn)
c = arrayfun(@(i)sprintf('%d@%.3g', mn(i,1), mn(i,2)), 1:size(mn,1), 'UniformOutput', 0);
s = strjoin(c, ' -> ');
end %func


% --- over-merge signal: units whose refractory-violation ratio exceeds isi_thresh ----------
function [nRefrac, medIsi] = isi_quality_(S_clu, isi_thresh)
[nRefrac, medIsi] = deal(NaN);
if isfield(S_clu,'vrIsiRatio_clu') && ~isempty(S_clu.vrIsiRatio_clu)
    vr = double(S_clu.vrIsiRatio_clu(:)); vr = vr(isfinite(vr));
    if ~isempty(vr), nRefrac = sum(vr > isi_thresh); medIsi = median(vr); end
end
end %func

% --- under-merge signal: cluster pairs left split with waveform corr >= maxCor --------------
% Upper triangle of S_clu.mrWavCor (same-peak-site biased on label sorts -> a floor, not the
% full cross-site duplicate count). NaN/zero off-diagonals never exceed a >0 maxCor.
function nDup = dup_pairs_(S_clu, maxCor)
nDup = NaN;
if isfield(S_clu,'mrWavCor') && ~isempty(S_clu.mrWavCor) && maxCor > 0 && maxCor < 1
    M = double(S_clu.mrWavCor); M = triu(M, 1);
    nDup = sum(M(:) >= maxCor);
end
end %func


% --- viClu <-> cviSpk_clu invariant, content-based (see CLAUDE.md) ---------
function ok = is_synced_(S_clu)
viClu = double(S_clu.viClu(:)); cvi = S_clu.cviSpk_clu; n = numel(viClu); bad = 0;
for i = 1:numel(cvi)
    vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=n);
    if ~isempty(vi) && any(viClu(vi) ~= i), bad = bad + 1; end
end
ok = (bad == 0);
end %func

function s = gv(P,f)
if isstruct(P) && isfield(P,f), v = P.(f); if ischar(v), s = v; else, s = mat2str(v); end
else, s = '<unset>'; end
end %func
