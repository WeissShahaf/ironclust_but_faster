function S_clu = measure_persite_timing(vcFile_prm, nTopSites, nWorkers)
% Measure the per-site clustering cost split: clustering algorithm vs. kNN graph.
%
% Runs the per-site, label-based clustering (the vcCluster = 'isosplit'/'hdbscan'/
% 'kmeans' path) on ONLY the N biggest detection sites (by spike count), reusing the
% already-cached spike features, and prints how much CPU-time goes to the clustering
% algorithm (t_clu) vs. the O(n^2) per-site kNN graph (t_knn). This reproduces the
% expensive "tail" of a full sort in minutes instead of the hours a whole re-sort
% would take, so the next optimization can be chosen from data rather than guesses:
%   * kNN dominates        -> a gpuArray pdist2 path for persite_knn_ is worth it
%                             (20 GB VRAM is ample; the kNN is chunked).
%   * clustering dominates -> GPU won't help the (sequential) isosplit/hdbscan cores;
%                             attack the tail with biggest-site-first (LPT) scheduling
%                             and/or per-site spike capping instead.
%
% Usage:
%   measure_persite_timing('E:\path\rec.prm')          % top 16 sites, .prm settings
%   measure_persite_timing('E:\path\rec.prm', 24)      % top 24 sites
%   measure_persite_timing('E:\path\rec.prm', 16, 8)   % override to 8 workers
%
% Inputs:
%   vcFile_prm : parameter file of a recording whose detect+feature stage is cached
%                (the *_jrc.mat and *_spkfet.jrc files must exist).
%   nTopSites  : number of largest sites to profile (default 16).
%   nWorkers   : optional override for nWorkers_clust (default: the .prm value).
%
% It does NOT run post-merge and does NOT modify any saved sorting results; it only
% exercises cluster_labels_persite_, which prints the t_clu/t_knn breakdown and the
% slowest sites. See cluster_labels_persite_ / cluster_site_ in irc.m and
% logs/changes_log20260625.md.

if nargin < 2 || isempty(nTopSites), nTopSites = 16; end
if nargin < 3, nWorkers = []; end

% --- load params + cached spike features (this also sets the global trFet_spk) ---
Sp = irc('call', 'loadParam_',  {vcFile_prm}, 1);   P  = Sp.out1;
Sc = irc('call', 'load_cached_', {P},          2);   S0 = Sc.out1;   P = Sc.out2;
if isempty(S0) || ~isfield(S0, 'cviSpk_site') || isempty(S0.cviSpk_site)
    error('measure_persite_timing:noCache', ...
        'No cached per-site spikes for %s (run the detect/feature stage first).', vcFile_prm);
end

% --- keep only the N biggest sites; blank the rest so the driver skips them fast ---
vnSpk_site = cellfun(@numel, S0.cviSpk_site);
nSites     = numel(vnSpk_site);
nTopSites  = max(1, min(nTopSites, nSites));
[vnSorted, viOrder] = sort(vnSpk_site, 'descend');
viKeep = viOrder(1:nTopSites);
S0_sub = S0;
for iSite = 1:nSites
    if ~any(iSite == viKeep), S0_sub.cviSpk_site{iSite} = []; end
end

% --- optional worker override (measurement courtesy; default = P.nWorkers_clust) ---
if ~isempty(nWorkers), P.nWorkers_clust = nWorkers; end

% --- plain-field reads (get_set_ is private to irc.m, so avoid it here) ---
vcCluster = 'isosplit';
if isfield(P, 'vcCluster') && ~isempty(P.vcCluster), vcCluster = P.vcCluster; end
knn = 50;
if isfield(P, 'knn') && ~isempty(P.knn), knn = P.knn; end

fprintf('\n=== per-site timing measurement: %s ===\n', vcFile_prm);
fprintf('vcCluster=%s, knn=%d; %d sites total, profiling the %d biggest (%d..%d spikes/site)\n', ...
    vcCluster, knn, nSites, nTopSites, vnSorted(nTopSites), vnSorted(1));

% --- dispatch to the matching per-site clusterer; it prints the t_clu/t_knn split ---
switch lower(vcCluster)
    case 'hdbscan',                        vcFunc = 'cluster_hdbscan_';
    case 'kmeans',                         vcFunc = 'cluster_kmeans_';
    case {'isosplit', 'isosplit5', 'isosplit6'}, vcFunc = 'cluster_isosplit_';
    otherwise
        fprintf(2, 'vcCluster=%s is not a per-site method; profiling with cluster_isosplit_ instead.\n', vcCluster);
        vcFunc = 'cluster_isosplit_';
end

t_all = tic;
Sr = irc('call', vcFunc, {S0_sub, P}, 1);
S_clu = Sr.out1;
fprintf('=== measurement wall-time: %.0fs (post-merge NOT run; nothing saved) ===\n', toc(t_all));
end %func
