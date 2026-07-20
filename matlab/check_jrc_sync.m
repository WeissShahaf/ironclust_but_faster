function varargout = check_jrc_sync(vcPath, fVerbose)
% CHECK_JRC_SYNC  Read-only integrity check for sorted _jrc.mat datasets.
%
%   Detects the viClu <-> cviSpk_clu DESYNC -- the machine-detectable signature of the
%   [O]-reorder corruption (CID-01) -- plus a best-effort spatial-coherence HEURISTIC that
%   flags clusters whose spikes span an implausible site range (the symptom a desync leaves
%   behind after it has been baked into viClu by a bad split/merge, which the invariant alone
%   would then miss).
%
%   T = check_jrc_sync(path)        % path = .prm | _jrc.mat | folder | cellstr list
%   T = check_jrc_sync(path, 0)     % quiet -- return the table only
%
%   *** NEVER writes or saves anything -- pure load() + check (see check_jrc_one). ***
%
%   Definitive test (identical to S_clu_assert_synced_):
%       all( S_clu.viClu(S_clu.cviSpk_clu{i}) == i )   for every cluster i
%   Verdicts:
%     PASS           -- cache and viClu agree; no active desync.
%     DESYNC         -- disagree, each cache entry -> one wrong label (clean permutation; single [O]).
%     DESYNC-SEVERE  -- cache entries mix MULTIPLE viClu labels (compounded desync).
%
%   Heuristic (nCluSpatial): # clusters with >10%% of spikes on sites >8 away from the peak site
%   (min 50 spikes/cluster). A CANDIDATE flag to eyeball, not a verdict -- drift / genuinely large
%   units can trip it. Only meaningful when the file has viSite_spk + S_clu.viSite_clu.
%
%   LIMITS: a PASS proves "currently self-consistent", not "never corrupted". Cannot detect the
%   DI-01 [U] multi-group merge bug (internally consistent by construction).
%
%   For a CSV of sessions with per-session logs + an .md report, use scan_jrc_report.

if nargin < 2, fVerbose = 1; end
csFiles = local_resolve_(vcPath);
if isempty(csFiles), error('check_jrc_sync: no _jrc.mat resolved from the input.'); end

R = repmat(check_jrc_one(''), numel(csFiles), 1);   % blank template with all fields
if fVerbose, fprintf('\n=== check_jrc_sync: %d file(s) ===\n', numel(csFiles)); end
for k = 1:numel(csFiles)
    R(k) = check_jrc_one(csFiles{k});
    if fVerbose, fprintf('  %s\n', local_line_(R(k))); end
end
T = struct2table(R, 'AsArray', true);
if fVerbose
    nFail = sum(startsWith([R.verdict], 'DESYNC'));
    nSpat = sum([R.nCluSpatial] > 0 & ~startsWith([R.verdict],'DESYNC') & ~startsWith([R.verdict],'SKIP'));
    fprintf('\n>>> %d DESYNC (corrupted; re-sort) | %d PASS-but-spatially-flagged (review) | of %d\n', ...
        nFail, nSpat, numel(csFiles));
end
if nargout, varargout{1} = T; end
end


%--------------------------------------------------------------------------
function s = local_line_(R)
s = sprintf('%-52s  %-14s  nClu=%-5d desync=%-5d mix=%-4d wrong=%5.2f%%  spatialFlag=%-4d span=%d  %s', ...
    char(R.name), char(R.verdict), R.nClu, R.nCluDesync, R.nCacheMix, R.pctSpkWrong, ...
    R.nCluSpatial, round(R.worstSiteSpan), char(R.note));
end


%--------------------------------------------------------------------------
function cs = local_resolve_(vcPath)
if iscell(vcPath)
    cs = {};
    for i = 1:numel(vcPath), cs = [cs; local_resolve_(vcPath{i})]; end %#ok<AGROW>
    return;
end
if isstring(vcPath), vcPath = char(vcPath); end
if isfolder(vcPath)
    d = dir(fullfile(vcPath, '**', '*_jrc.mat'));
    cs = arrayfun(@(x) fullfile(x.folder, x.name), d, 'UniformOutput', 0);
elseif endsWith(lower(vcPath), '_jrc.mat')
    cs = {vcPath};
elseif endsWith(lower(vcPath), '.prm')
    cs = {[vcPath(1:end-4) '_jrc.mat']};
else
    cs = {vcPath};
end
cs = cs(:);
end
