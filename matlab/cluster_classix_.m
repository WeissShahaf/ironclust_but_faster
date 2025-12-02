function S_clu = cluster_classix_(S0, P)
% Primary clustering using CLASSIX algorithm (bypasses density-peak clustering)
% Use this as an alternative to DPC-based clustering by setting P.vcCluster = 'classix'
%
% INDEPENDENT from post-merge method - can be used with ANY post_merge_mode0:
%   - vcCluster = 'classix' alone (CLASSIX sorting only - RECOMMENDED)
%   - vcCluster = 'classix' + post_merge_mode0 = [12,15,17] (CLASSIX + traditional merge)
%   - vcCluster = 'classix' + post_merge_mode0 = 21 (CLASSIX twice - not recommended)
%
% This is SEPARATE from post_merge_classix which refines existing clusters.
% cluster_classix_ performs initial clustering from scratch using only CLASSIX.
%
% Parameters:
%   classix_radius (default: 0.5) - Grouping radius in normalized space
%   classix_minPts (default: P.min_count) - Minimum spikes per cluster
%   classix_merge_tiny (default: 1) - Merge groups with < minPts
%   classix_use_mex (default: 1) - Use MEX acceleration (multi-threaded BLAS)
%   classix_verbose (default: 0) - Print detailed timing information

fprintf('CLASSIX primary clustering (bypassing DPC)...\n'); t_func = tic;

%% Get parameters
classix_radius = get_set_(P, 'classix_radius', 0.5);
classix_minPts = get_set_(P, 'classix_minPts', P.min_count);
classix_verbose = get_set_(P, 'classix_verbose', 0);
opts = struct();
opts.merge_tiny_groups = get_set_(P, 'classix_merge_tiny', 1);
opts.use_mex = get_set_(P, 'classix_use_mex', 1);

%% Load spike features
global trFet_spk
if isempty(trFet_spk)
    trFet_spk = load_bin_(strrep(P.vcFile_prm, '.prm', '_spkfet.jrc'), 'single', S0.dimm_fet);
end

% Reshape to (nSpk x nFeatures) for CLASSIX
[nSites, nPc, nSpk] = size(trFet_spk);
mrFet = reshape(permute(trFet_spk, [3, 1, 2]), nSpk, []);  % nSpk x (nSites*nPc)

fprintf('  Features: %d spikes x %d dimensions\n', nSpk, size(mrFet,2));

%% Apply CLASSIX
[viClu, explain, out] = classix(mrFet, classix_radius, classix_minPts, opts);

%% Report CLASSIX statistics (if verbose)
if classix_verbose
    fprintf('  CLASSIX internal timing:\n');
    fprintf('    Prepare:   %0.3fs\n', out.t1_prepare);
    fprintf('    Aggregate: %0.3fs\n', out.t2_aggregate);
    fprintf('    Merge:     %0.3fs\n', out.t3_merge);
    if isfield(out, 't4_minPts')
        fprintf('    MinPts:    %0.3fs\n', out.t4_minPts);
    end
    fprintf('  Distance computations: %d (%.1f per spike)\n', out.dist, out.dist/nSpk);
    fprintf('  Data scaling factor: 1/%.2f\n', out.scl);
    fprintf('  Effective radius: %.2f*%.2f = %.2f\n', classix_radius, out.scl, classix_radius*out.scl);
    fprintf('  Cluster sizes: min=%d, max=%d, median=%d\n', ...
        min(out.cs), max(out.cs), median(out.cs));
end

%% Build S_clu structure
% Create minimal structure required by postCluster_ and downstream functions
nClu = max(viClu);
S_clu = struct();
S_clu.viClu = int32(viClu);
S_clu.nClu = nClu;

% Dummy rho and delta (not used for CLASSIX, but required by some functions)
S_clu.rho = ones(nSpk, 1, 'single');
S_clu.delta = ones(nSpk, 1, 'single');
S_clu.ordrho = int32(1:nSpk)';

% Cluster centers: pick first spike in each cluster
% (could be improved by using group centers from out.gc)
icl = zeros(nClu, 1, 'int32');
for iClu = 1:nClu
    viSpk_clu = find(viClu == iClu);
    if ~isempty(viSpk_clu)
        icl(iClu) = viSpk_clu(1);
    end
end
S_clu.icl = icl(icl > 0);

% Nearest neighbor (not computed for CLASSIX-only mode)
S_clu.nneigh = int32(zeros(nSpk, 1));

% CLASSIX-specific outputs
S_clu.classix_out = out;  % Store CLASSIX output structure
S_clu.classix_explain = explain;  % Store explain function handle

% Timing
S_clu.t_runtime = toc(t_func);

% Parameters
S_clu.P = P;

fprintf('  CLASSIX clustering: %d clusters, took %0.1fs\n', nClu, S_clu.t_runtime);

end %func

%% Helper function wrappers
function out1 = get_set_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = load_bin_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
