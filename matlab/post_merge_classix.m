function S_clu = post_merge_classix(S_clu, P)
% Post-merge clustering using CLASSIX algorithm
% Applies CLASSIX clustering to spike features for cluster refinement

fprintf('Automated merging using CLASSIX...\n'); t1 = tic;

%% Get parameters
classix_radius = get_set_(P, 'classix_radius', 0.5);  % clustering radius
classix_minPts = get_set_(P, 'classix_minPts', P.min_count);  % min cluster size
opts = struct();
opts.merge_tiny_groups = get_set_(P, 'classix_merge_tiny', 1);
opts.use_mex = 0;  % disable MEX initially for compatibility

%% Get spike features
global trFet_spk
if isempty(trFet_spk)
    trFet_spk = irc('call', 'load_spkfet_', {irc('call', 'get0_', {}), P});
end

% trFet_spk is (nSites_fet x nPcPerChan x nSpk)
% Reshape to (nSpk x nFeatures) for CLASSIX
[nSites, nPc, nSpk] = size(trFet_spk);
mrFet = reshape(permute(trFet_spk, [3, 1, 2]), nSpk, []);  % nSpk x (nSites*nPc)

%% Only cluster non-noise spikes
viSpk_valid = find(S_clu.viClu > 0);
nSpk_valid = numel(viSpk_valid);

if nSpk_valid < classix_minPts * 2
    fprintf('Too few spikes (%d) for CLASSIX clustering\n', nSpk_valid);
    return;
end

mrFet_valid = mrFet(viSpk_valid, :);

%% Apply CLASSIX
[viLabel_classix, ~, out] = classix(mrFet_valid, classix_radius, classix_minPts, opts);

%% Map labels back to viClu
nClu_pre = max(S_clu.viClu);
nClu_post = max(viLabel_classix);

viClu_new = zeros(nSpk, 1, 'like', S_clu.viClu);
viClu_new(viSpk_valid) = viLabel_classix;
S_clu.viClu = viClu_new;

%% Update cluster centers (icl)
% For each cluster, pick spike with highest delta as center
nClu = max(S_clu.viClu);
icl_new = zeros(nClu, 1, 'int32');
for iClu = 1:nClu
    viSpk_clu = find(S_clu.viClu == iClu);
    if ~isempty(viSpk_clu)
        [~, imax] = max(S_clu.delta(viSpk_clu));
        icl_new(iClu) = viSpk_clu(imax);
    end
end
S_clu.icl = icl_new(icl_new > 0);

%% Refresh cluster structure
S_clu = S_clu_refresh_(S_clu);

fprintf('CLASSIX merge: %d->%d clusters, took %0.1fs\n', nClu_pre, S_clu.nClu, toc(t1));
end %func

%% Helper function wrappers
function out1 = get_set_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = S_clu_refresh_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
