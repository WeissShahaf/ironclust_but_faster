function recover_from_snapshot()
% Rebuild a CLEAN _jrc.mat from the pristine pre-merge snapshot, reproducing the
% AUTOMATIC (uncurated) clustering with fully consistent per-cluster fields.
%
% Method-agnostic:
%   - DPC (drift-knn/...):  post_merge_ regenerates viClu from the density graph.
%   - label-based (isosplit/hdbscan/...): post_merge_ re-merges from viClu_premerge.
% Either way post_merge_ rebuilds cviSpk_clu + all per-cluster fields via proven pipeline code,
% so the result is synced by construction. Curation is discarded (it lived in the corrupt viClu).
%
% RECOVER_SAVE=1 -> atomically overwrite the _jrc.mat (keeps .bak) but ONLY after the sync check
% passes. Anything else (default) = DRY RUN: reports before/after, writes NOTHING.
prm   = getenv('RECOVER_PRM');
logf  = getenv('RECOVER_LOG');
fSave = strcmpi(getenv('RECOVER_SAVE'), '1');
try, diary(logf); catch, end
fprintf('=== recover_from_snapshot (fSave=%d) ===\n', fSave);
fprintf('PRM: %s\n', prm);
try
    So = irc('call','loadParam_',{prm, 0}, 2);  P = So.out1;
    fprintf('vcCluster=%s  post_merge_mode=%s\n', gv(P,'vcCluster'), gv(P,'post_merge_mode'));

    tL = tic;
    Sc = irc('call','load_cached_',{P}, 2);  S0 = Sc.out1;  P = Sc.out2;
    fprintf('load_cached_ took %.1f s\n', toc(tL));
    set(0, 'UserData', S0);
    S_clu = S0.S_clu;

    report_sync('BEFORE (corrupt, as-saved)   ', S_clu);
    n_pre  = snap_nclu(S_clu, 'viClu_premerge');
    n_auto = snap_nclu(S_clu, 'viClu_auto');
    fprintf('snapshot cluster counts: viClu_premerge=%s  viClu_auto=%s\n', numstr(n_pre), numstr(n_auto));

    if isfield(S_clu,'viClu_premerge') && ~isempty(S_clu.viClu_premerge)
        src = 'viClu_premerge';  S_clu.viClu = S_clu.viClu_premerge;
    elseif isfield(S_clu,'viClu_auto') && ~isempty(S_clu.viClu_auto)
        src = 'viClu_auto';      S_clu.viClu = S_clu.viClu_auto;
    else
        error('recover:no_snapshot','No clean snapshot (viClu_premerge/viClu_auto) present.');
    end
    fprintf('reset viClu <- %s, re-running post_merge_ ...\n', src);

    tM = tic;
    Sm = irc('call','post_merge_',{S_clu, P}, 2);  S_clu2 = Sm.out1;
    fprintf('post_merge_ (rebuild) took %.1f s\n', toc(tM));

    ok = report_sync('AFTER  (rebuilt from snapshot)', S_clu2);
    fprintf('rebuilt nClu=%d   (stored viClu_auto nClu=%s)\n', S_clu2.nClu, numstr(n_auto));

    if fSave
        if ~ok
            fprintf(2, 'REFUSING TO SAVE: rebuilt S_clu is NOT synced.\n');
        else
            S0.S_clu = S_clu2;  set(0,'UserData',S0);
            vcJrc = strrep(P.vcFile_prm, '.prm', '_jrc.mat');
            fprintf('SAVING (atomic, keeps .bak) -> %s\n', vcJrc);
            irc('call','save0_',{vcJrc, 1});
            fprintf('SAVED.\n');
        end
    else
        fprintf('DRY RUN: nothing written to disk.\n');
    end
    fprintf('=== DONE ===\n');
catch err
    fprintf(2, 'ERROR: %s\n', err.message);
    for i=1:numel(err.stack)
        fprintf(2, '  at %s (line %d)\n', err.stack(i).name, err.stack(i).line);
    end
end
try, diary off; catch, end
end

function ok = report_sync(tag, S_clu)
viClu = double(S_clu.viClu(:)); cvi = S_clu.cviSpk_clu; n = numel(viClu);
bad = 0; mixed = 0;
for i = 1:numel(cvi)
    vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=n);
    if isempty(vi), continue; end
    lab = viClu(vi);
    if any(lab ~= i), bad = bad + 1; end
    if numel(unique(lab)) > 1, mixed = mixed + 1; end
end
ok = (bad == 0);
if ok, v = 'SYNCED (clean)'; else, v = 'DESYNC'; end
fprintf('  [%s] nClu=%d cache_entries=%d desync=%d mixed=%d -> %s\n', tag, numel(cvi), numel(cvi), bad, mixed, v);
end

function n = snap_nclu(S_clu, f)
if isfield(S_clu,f) && ~isempty(S_clu.(f)), n = double(max(S_clu.(f)(:))); else, n = NaN; end
end
function s = numstr(n), if isnan(n), s = '<absent>'; else, s = num2str(n); end, end
function s = gv(P,f)
if isstruct(P) && isfield(P,f), v = P.(f); if ischar(v), s = v; else, s = mat2str(v); end
else, s = '<unset>'; end
end
