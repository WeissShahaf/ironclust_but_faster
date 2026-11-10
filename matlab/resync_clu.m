function resync_clu()
% RESYNC_CLU  Fix a desynced _jrc.mat by rebuilding cviSpk_clu + all per-cluster fields (waveforms,
% positions, quality, mrWavCor) FROM the current curated viClu -- keeping viClu's numbering (so it
% still matches the already-patched spike-times CSV), unlike recover_from_snapshot which regenerates.
%
% Env: RESYNC_PRM, RESYNC_LOG, RESYNC_SAVE=1 (persist the synced _jrc.mat), RESYNC_QUAL=1 (also
% export _quality.csv). Default = DRY RUN (no save, no quality write).
prm  = getenv('RESYNC_PRM'); logf = getenv('RESYNC_LOG');
fSave = strcmpi(getenv('RESYNC_SAVE'),'1');
fQual = strcmpi(getenv('RESYNC_QUAL'),'1');
try, diary(logf); catch, end
fprintf('=== resync_clu (SAVE=%d QUAL=%d) ===\nprm: %s\n', fSave, fQual, prm);
try
    So = irc('call','loadParam_',{prm,0},2); P = So.out1;
    Sc = irc('call','load_cached_',{P},2); S0 = Sc.out1; P = Sc.out2;
    set(0,'UserData',S0);
    S_clu = S0.S_clu;
    nClu0 = S_clu.nClu;
    snr0 = snr_sample_(S_clu);
    report_sync_('BEFORE (desynced)', S_clu);

    tR = tic;
    % Rebuild derived fields from viClu individually (skip mrWavCor - not needed for the quality CSV
    % and S_clu_update_ crashes rebuilding it from a desynced start). Keeps viClu numbering + empties.
    % omit viClu_update everywhere -> each function takes its FULL-REBUILD (empty) branch, allocating
    % fresh per-cluster arrays for all nClu (passing 1:nClu triggers the incremental branch that
    % assumes valid existing arrays and crashes on a desynced start).
    S_clu = call_step_('S_clu_refresh_', {S_clu, 0});     % cviSpk_clu, vnSpk_clu, viSite_clu
    % Empty (all-deleted) clusters get viSite_clu=NaN from mode([]); S_clu_wav_ then indexes with NaN
    % and crashes. Give them a placeholder site (1) so the rebuild proceeds; they stay empty (NaN/0
    % metrics) and the numbering is untouched.
    vs = double(S_clu.viSite_clu(:)); nEmpty = sum(isnan(vs) | vs<1);
    vs(isnan(vs) | vs<1) = 1; S_clu.viSite_clu = reshape(vs, size(S_clu.viSite_clu));
    if nEmpty>0, fprintf('  (%d empty clusters given placeholder site)\n', nEmpty); end
    S_clu = call_step_('S_clu_wav_',     {S_clu});        % tmrWav_clu / tmrWav_raw_clu (full rebuild)
    S_clu = call_step_('S_clu_position_',{S_clu});        % vrPosX_clu, vrPosY_clu
    S_clu = call_step_('S_clu_quality_', {S_clu, P});     % SNR, IsoDist, LRatio, ISI, Vpp/Vmin
    fprintf('resync (refresh+wav+position+quality) took %.1f s\n', toc(tR));

    ok = report_sync_('AFTER  (resynced)', S_clu);
    fprintf('nClu: %d -> %d   (preserved=%d)\n', nClu0, S_clu.nClu, nClu0==S_clu.nClu);
    fprintf('vrSnr_clu sample  before=%s  after=%s\n', mat2str(snr0,3), mat2str(snr_sample_(S_clu),3));

    S0.S_clu = S_clu; set(0,'UserData',S0);
    if fSave
        if ~ok, fprintf(2,'REFUSING SAVE: not synced.\n');
        else
            vcJrc = strrep(P.vcFile_prm,'.prm','_jrc.mat');
            irc('call','save0_',{vcJrc, 1});
            fprintf('SAVED (atomic, keeps .bak) -> %s\n', vcJrc);
        end
    end
    if fQual && ok
        irc('export-quality', prm);
        fprintf('quality exported -> %s\n', strrep(prm,'.prm','_quality.csv'));
    end
    if ~fSave && ~fQual, fprintf('DRY RUN: nothing written.\n'); end
    fprintf('=== DONE ===\n');
catch err
    fprintf(2,'ERROR: %s\n', err.message);
    for i=1:numel(err.stack), fprintf(2,'  at %s (line %d)\n', err.stack(i).name, err.stack(i).line); end
end
try, diary off; catch, end
end

function ok = report_sync_(tag, S_clu)
viClu=double(S_clu.viClu(:)); cvi=S_clu.cviSpk_clu; n=numel(viClu); bad=0; mixed=0;
for i=1:numel(cvi)
    vi=double(cvi{i}(:)); vi=vi(vi>=1&vi<=n); if isempty(vi), continue; end
    lb=viClu(vi); if any(lb~=i), bad=bad+1; end; if numel(unique(lb))>1, mixed=mixed+1; end
end
ok=(bad==0);
fprintf('  [%s] nClu=%d cache=%d desync=%d mixed=%d -> %s\n', tag, numel(cvi), numel(cvi), bad, mixed, ternary_(ok,'SYNCED','DESYNC'));
end
function s = snr_sample_(S_clu)
if isfield(S_clu,'vrSnr_clu') && ~isempty(S_clu.vrSnr_clu), v=double(S_clu.vrSnr_clu(:)); s=v(1:min(5,numel(v)))'; else s=[]; end
end
function s = ternary_(c,a,b), if c, s=a; else, s=b; end, end
function S = call_step_(fn, args)
% irc('call',...) returns [] when the inner function throws (test_ swallows it to error_log.mat).
R = irc('call', fn, args, 1);
if isempty(R) || ~isstruct(R) || ~isfield(R,'out1')
    error('resync:step','step %s failed (inner error logged to error_log.mat)', fn);
end
S = R.out1;
end
