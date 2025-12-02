function S_clu = post_merge_classix(S_clu, P)
% Post-merge clustering using CLASSIX algorithm
% Applies CLASSIX clustering to spike features for cluster refinement
%
% Parameters:
%   classix_radius (default: 0.5) - Grouping radius in normalized space
%   classix_minPts (default: P.min_count) - Minimum spikes per cluster
%   classix_merge_tiny (default: 1) - Merge groups with < minPts
%   classix_use_mex (default: 1) - Use MEX acceleration (multi-threaded BLAS)
%   classix_verbose (default: 0) - Print detailed timing information

fprintf('Automated merging using CLASSIX...\n'); t1 = tic;

%% Get parameters
classix_radius = get_set_(P, 'classix_radius', 0.5);  % clustering radius
classix_minPts = get_set_(P, 'classix_minPts', P.min_count);  % min cluster size
classix_verbose = get_set_(P, 'classix_verbose', 0);  % detailed output
opts = struct();
opts.merge_tiny_groups = get_set_(P, 'classix_merge_tiny', 1);
opts.use_mex = get_set_(P, 'classix_use_mex', 1);  % enable MEX by default (multi-threaded)

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

%% Report CLASSIX statistics (if verbose)
if classix_verbose
    fprintf('  CLASSIX internal timing:\n');
    fprintf('    Prepare:   %0.3fs\n', out.t1_prepare);
    fprintf('    Aggregate: %0.3fs\n', out.t2_aggregate);
    fprintf('    Merge:     %0.3fs\n', out.t3_merge);
    if isfield(out, 't4_minPts')
        fprintf('    MinPts:    %0.3fs\n', out.t4_minPts);
    end
    fprintf('  Distance computations: %d (%.1f per spike)\n', out.dist, out.dist/nSpk_valid);
    fprintf('  Data scaling factor: 1/%.2f\n', out.scl);
    fprintf('  Effective radius: %.2f*%.2f = %.2f\n', classix_radius, out.scl, classix_radius*out.scl);
    fprintf('  Cluster sizes: min=%d, max=%d, median=%d\n', ...
        min(out.cs), max(out.cs), median(out.cs));
end

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
