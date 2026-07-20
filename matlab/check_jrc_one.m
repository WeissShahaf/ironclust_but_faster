function R = check_jrc_one(vcFile)
% CHECK_JRC_ONE  Read-only integrity check of ONE sorted _jrc.mat. Returns a metrics struct.
%   Used by check_jrc_sync (interactive) and scan_jrc_report (batch). NEVER writes/saves.
%
%   Fields: file name verdict nClu nSpk nCluDesync nCacheMix pctSpkWrong nCluSuspect worstDepthGapUm note
%
%   Definitive test (== S_clu_assert_synced_):  all( viClu(cviSpk_clu{i}) == i ), each cluster i.
%     PASS | DESYNC (clean permutation) | DESYNC-SEVERE (cache entries mix >1 viClu label).
%
%   Heuristic (nCluSuspect) -- TIGHTENED, for the PASS backstop (a desync already baked into viClu
%   then re-cached passes the invariant). Flags a cluster only when it has a DISTINCT SECONDARY
%   DEPTH POPULATION that is INTERLEAVED IN TIME with the main one -- the two-neuron-fusion
%   signature. Drift (one unit whose depth ramps over time) is excluded by the time-overlap test.
%   Requires per-spike depth (mrPos_spk, or viSite_spk + P.mrSiteXY) and time (viTime_spk); else
%   skipped. Still a CANDIDATE to eyeball, not a verdict.
%
%   See check_jrc_sync.m for the full contract/limits (PASS != proof of clean; DI-01 undetectable).

R = struct('file',"", 'name',"", 'verdict',"SKIP", 'nClu',0, 'nSpk',0, 'nCluDesync',0, ...
    'nCacheMix',0, 'pctSpkWrong',0, 'nCluSuspect',0, 'worstDepthGapUm',0, 'note',"");
if nargin<1 || isempty(vcFile), R.verdict = "SKIP:missing"; return; end
vcFile = char(vcFile);
R.file = string(vcFile);
[~, nm, ex] = fileparts(vcFile); R.name = string([nm ex]);
if exist(vcFile,'file') ~= 2, R.verdict = "SKIP:missing"; return; end
try
    W = load(vcFile, 'S_clu', 'viSite_spk', 'viTime_spk', 'mrPos_spk', 'P');
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

% --- tightened spatial heuristic: time-interleaved secondary depth population ---
vY = local_depth_(W);
if ~isempty(vY) && isfield(W,'viTime_spk') && ~isempty(W.viTime_spk)
    vT = double(W.viTime_spk(:));
    dGapUm = 150;          % secondary population must sit >150 um from the cluster's median depth
    minN = 100;            % only test clusters with >=100 spikes
    minFrac = 0.15;        % secondary population must be >=15% of the cluster
    minFarN = 50;          % ...and >=50 spikes
    minTimeOverlap = 0.5;  % the two depth populations must overlap >=50% in time (else = drift)
    nSp = 0; worst = 0;
    for i = 1:nClu
        vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=numel(vY) & vi<=numel(vT));
        if numel(vi) < minN, continue; end
        y = vY(vi); t = vT(vi); ymed = median(y);
        far = abs(y - ymed) > dGapUm;
        nf = sum(far);
        if nf < max(minFarN, minFrac*numel(vi)), continue; end   % substantial secondary population
        gap = abs(median(y(far)) - ymed);
        if gap < dGapUm, continue; end                            % concentrated away, not a smooth tail
        sn = prctile(t(~far),[5 95]); sf = prctile(t(far),[5 95]);
        ov = max(0, min(sn(2),sf(2)) - max(sn(1),sf(1)));
        un = max(sn(2),sf(2)) - min(sn(1),sf(1));
        if un>0 && ov/un < minTimeOverlap, continue; end          % time-separated -> drift, skip
        nSp = nSp + 1; worst = max(worst, gap);
    end
    R.nCluSuspect = nSp; R.worstDepthGapUm = round(worst);
else
    R.note = "spatial:skipped(no per-spike depth/time)";
end
end


%--------------------------------------------------------------------------
function vY = local_depth_(W)
% per-spike depth (um): prefer mrPos_spk(:,2); else site Y via P.mrSiteXY indexed by viSite_spk.
vY = [];
if isfield(W,'mrPos_spk') && ~isempty(W.mrPos_spk) && size(W.mrPos_spk,2) >= 2
    vY = double(W.mrPos_spk(:,2)); return;
end
if isfield(W,'viSite_spk') && ~isempty(W.viSite_spk) && isfield(W,'P') && isstruct(W.P) ...
        && isfield(W.P,'mrSiteXY') && ~isempty(W.P.mrSiteXY) && size(W.P.mrSiteXY,2) >= 2
    mrXY = W.P.mrSiteXY; vs = double(W.viSite_spk(:));
    vs(vs<1 | vs>size(mrXY,1)) = 1;
    vY = double(mrXY(vs,2));
end
end
