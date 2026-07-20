function R = check_jrc_one(vcFile)
% CHECK_JRC_ONE  Read-only integrity check of ONE sorted _jrc.mat. Returns a metrics struct.
%   Used by check_jrc_sync (interactive) and scan_jrc_report (batch). NEVER writes/saves.
%
%   Fields: file name verdict nClu nSpk nCluDesync nCacheMix pctSpkWrong nCluSpatial worstSiteSpan note
%
%   Definitive test (== S_clu_assert_synced_):  all( viClu(cviSpk_clu{i}) == i ), each cluster i.
%     PASS | DESYNC (clean permutation) | DESYNC-SEVERE (cache entries mix >1 viClu label).
%   Heuristic nCluSpatial: # clusters with >10% of spikes on sites >8 from the peak (min 50 spk).
%   See check_jrc_sync.m header for the full contract and limits.

R = struct('file',"", 'name',"", 'verdict',"SKIP", 'nClu',0, 'nSpk',0, 'nCluDesync',0, ...
    'nCacheMix',0, 'pctSpkWrong',0, 'nCluSpatial',0, 'worstSiteSpan',0, 'note',"");
if nargin<1 || isempty(vcFile), R.verdict = "SKIP:missing"; return; end
vcFile = char(vcFile);
R.file = string(vcFile);
[~, nm, ex] = fileparts(vcFile); R.name = string([nm ex]);
if exist(vcFile,'file') ~= 2, R.verdict = "SKIP:missing"; return; end
try
    W = load(vcFile, 'S_clu', 'viSite_spk');
catch ME
    R.verdict = "SKIP:loaderr"; R.note = string(ME.message); return;
end
if ~isfield(W,'S_clu') || ~isstruct(W.S_clu), R.verdict = "SKIP:noS_clu"; return; end
S = W.S_clu;
if ~isfield(S,'viClu') || ~isfield(S,'cviSpk_clu'), R.verdict = "SKIP:nofields"; return; end
viClu = double(S.viClu(:)); cvi = S.cviSpk_clu; nClu = numel(cvi); nSpk = numel(viClu);
if nClu==0 || nSpk==0, R.verdict = "SKIP:empty"; return; end
R.nClu = nClu; R.nSpk = nSpk;

% --- definitive invariant: viClu <-> cviSpk_clu ---
nBad=0; nMix=0; nWrong=0; nCache=0;
for i = 1:nClu
    vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=nSpk);
    if isempty(vi), continue; end
    lb = viClu(vi); nCache = nCache + numel(lb);
    nw = sum(lb ~= i);
    if nw>0, nBad=nBad+1; nWrong=nWrong+nw; end
    if numel(unique(lb))>1, nMix=nMix+1; end
end
R.nCluDesync = nBad; R.nCacheMix = nMix; R.pctSpkWrong = 100*nWrong/max(nCache,1);
if nBad==0, R.verdict = "PASS"; elseif nMix==0, R.verdict = "DESYNC"; else, R.verdict = "DESYNC-SEVERE"; end

% --- spatial-coherence heuristic (best-effort; candidate flag, not a verdict) ---
if isfield(W,'viSite_spk') && ~isempty(W.viSite_spk) && isfield(S,'viSite_clu')
    vSpk = double(W.viSite_spk(:)); vClu = double(S.viSite_clu(:));
    nFar = 8; fracTh = 0.10; minN = 50; nSp = 0; worst = 0;
    for i = 1:nClu
        vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=numel(vSpk));
        if numel(vi) < minN, continue; end
        vs = vSpk(vi);
        if i<=numel(vClu) && vClu(i)>=1, pk = vClu(i); else, pk = median(vs); end
        if mean(abs(vs - pk) > nFar) > fracTh
            nSp = nSp + 1; worst = max(worst, prctile(vs,95) - prctile(vs,5));
        end
    end
    R.nCluSpatial = nSp; R.worstSiteSpan = worst;
else
    R.note = "spatial:skipped(no viSite_spk/viSite_clu)";
end
end
