function [labels, info] = isosplit5(X, opts)
% ISOSPLIT5  Pure-MATLAB port of the FlatironInstitute ISO-SPLIT (v5) clustering.
%   labels = isosplit5(X) clusters the columns of X.
%   labels = isosplit5(X, opts) sets options.
%
%   Inputs:
%     X    : (M dims x N samples) data matrix.
%     opts : struct with optional fields
%              .isocut_threshold        (default 1.0)  dip-score cutoff; pairs of
%                                        clusters with dip_score < threshold are merged.
%              .min_cluster_size        (default 10)
%              .K_init                  (default 200)  number of initial parcels.
%              .max_iterations          (default 1000) safety cap.
%              .whiten_cluster_pairs    (default 1)    whiten the comparison axis.
%              .verbose                 (default 0)
%
%   Output:
%     labels : 1 x N integer labels (1..K). ISO-SPLIT assigns every point.
%
%   Method: over-segment into small parcels, then repeatedly take pairs of nearby
%   clusters and run a 1-D statistical dip test (isocut5) on the projection onto
%   the line between their centroids -- merge if unimodal, otherwise redistribute
%   along the optimal cutpoint. Reuses isocut5.m + jisotonic5.m.
%
%   Reference: github.com/flatironinstitute/isosplit5 (Magland & Barnett).

if nargin<1, test_isosplit5_(); return; end
if nargin<2, opts = struct(); end

isocut_threshold = getfield_default_(opts, 'isocut_threshold', 1.0);
min_cluster_size = getfield_default_(opts, 'min_cluster_size', 10);
K_init           = getfield_default_(opts, 'K_init', 200);
max_iterations   = getfield_default_(opts, 'max_iterations', 1000);
whiten_pairs     = getfield_default_(opts, 'whiten_cluster_pairs', 1);
verbose          = getfield_default_(opts, 'verbose', 0);

[~, N] = size(X);
info = struct();
if N == 0, labels = zeros(1,0); return; end
if N <= min_cluster_size, labels = ones(1, N); return; end

% ---- initial parcelation (over-segmentation into small clusters) ----
labels = parcelate_(X, min_cluster_size, K_init);
Kmax = max(labels);
if Kmax <= 1, labels = relabel_(labels); return; end

centroids = compute_centroids_(X, labels, Kmax);   % M x Kmax (NaN for empty)
comparisons_made = false(Kmax, Kmax);

% ---- iterative merge / redistribute ----
for iter = 1:max_iterations
    counts = label_counts_(labels, Kmax);
    active = find(counts > 0);
    if numel(active) <= 1, break; end

    ac = centroids(:, active);
    D = pdist2_(ac', ac');                 % active x active centroid distances
    for ii = 1:numel(active)
        D(ii,ii) = inf;
    end
    % mask pairs already settled at the current centroids
    sub = comparisons_made(active, active);
    D(sub) = inf;

    [p1, p2] = mutual_nn_pairs_(D);
    if isempty(p1), break; end
    k1s = active(p1); k2s = active(p2);

    [labels, changed] = compare_pairs_(X, labels, k1s, k2s, ...
        min_cluster_size, isocut_threshold, whiten_pairs);

    % mark these pairs as compared at the current centroids
    for ip = 1:numel(k1s)
        comparisons_made(k1s(ip), k2s(ip)) = true;
        comparisons_made(k2s(ip), k1s(ip)) = true;
    end
    % clusters whose membership changed: refresh centroid + reopen for comparison
    changed = unique(changed);
    for c = changed(:)'
        vi = (labels == c);
        if any(vi)
            centroids(:, c) = mean(X(:, vi), 2);
        else
            centroids(:, c) = nan;
        end
        comparisons_made(c, :) = false;
        comparisons_made(:, c) = false;
    end
    if verbose
        fprintf('  isosplit5 iter %d: %d active clusters\n', iter, numel(active));
    end
end

labels = relabel_(labels);
end %func


%--------------------------------------------------------------------------
function labels = parcelate_(X, target_parcel_size, target_num_parcels)
% Over-segment X (columns) into <= target_num_parcels parcels by repeatedly
% splitting the largest-radius parcel via farthest-point seeding.
[~, N] = size(X);
labels = ones(1, N);
no_split = false(1, max(1, target_num_parcels));
K = 1;
while K < target_num_parcels
    counts = accumarray(labels(:), 1, [K 1]);
    cand = find(counts(:) > target_parcel_size & ~no_split(1:K)');
    if isempty(cand), break; end
    % choose the candidate parcel with the largest radius
    bestRad = -inf; bestK = 0; bestInds = [];
    for k = cand(:)'
        inds = find(labels == k);
        c = mean(X(:, inds), 2);
        rad = max(sum(bsxfun(@minus, X(:, inds), c).^2, 1));
        if rad > bestRad, bestRad = rad; bestK = k; bestInds = inds; end
    end
    inds = bestInds;
    c = mean(X(:, inds), 2);
    d = sum(bsxfun(@minus, X(:, inds), c).^2, 1);
    [~, ia] = max(d);  A = X(:, inds(ia));
    dA = sum(bsxfun(@minus, X(:, inds), A).^2, 1);
    [~, ib] = max(dA); B = X(:, inds(ib));
    dB = sum(bsxfun(@minus, X(:, inds), B).^2, 1);
    assignB = dB < dA;
    if ~any(assignB) || all(assignB)
        no_split(bestK) = true;   % degenerate (e.g., duplicate points); leave intact
        continue;
    end
    K = K + 1;
    labels(inds(assignB)) = K;
end
labels = relabel_(labels);
end %func


%--------------------------------------------------------------------------
function [labels, changed] = compare_pairs_(X, labels, k1s, k2s, min_size, thresh, whiten_pairs)
changed = [];
for i = 1:numel(k1s)
    k1 = k1s(i); k2 = k2s(i);
    inds1 = find(labels == k1);
    inds2 = find(labels == k2);
    if isempty(inds1) || isempty(inds2), continue; end
    if numel(inds1) < min_size || numel(inds2) < min_size
        do_merge = true; L12 = [];
    else
        [do_merge, L12] = merge_test_(X(:, inds1), X(:, inds2), thresh, whiten_pairs);
    end
    if do_merge
        labels(inds2) = k1;
        changed(end+1) = k1; changed(end+1) = k2; %#ok<AGROW>
    else
        inds12 = [inds1, inds2];
        old = labels(inds12);
        labels(inds12(L12 == 1)) = k1;
        labels(inds12(L12 == 2)) = k2;
        if ~isequal(labels(inds12), old)
            changed(end+1) = k1; changed(end+1) = k2; %#ok<AGROW>
        end
    end
end
end %func


%--------------------------------------------------------------------------
function [do_merge, L12] = merge_test_(X1, X2, thresh, whiten_pairs)
N1 = size(X1, 2); N2 = size(X2, 2);
c1 = mean(X1, 2); c2 = mean(X2, 2);
V = c2 - c1;
if whiten_pairs
    V = whiten_dir_(X1, X2, V);
end
nv = norm(V);
if nv == 0      % identical centroids -> cannot separate, merge
    do_merge = true; L12 = []; return;
end
V = V / nv;
proj = [V' * X1, V' * X2];                  % 1 x (N1+N2)
[dip_score, cutpoint] = isocut5(proj);
do_merge = dip_score < thresh;
L12 = ones(1, N1 + N2);
L12(proj >= cutpoint) = 2;
end %func


%--------------------------------------------------------------------------
function V = whiten_dir_(X1, X2, V)
% Direction between centroids whitened by the pooled within-cluster covariance.
n1 = size(X1, 2); n2 = size(X2, 2);
c1 = mean(X1, 2); c2 = mean(X2, 2);
X1c = bsxfun(@minus, X1, c1);
X2c = bsxfun(@minus, X2, c2);
M = size(X1, 1);
C = (X1c * X1c' + X2c * X2c') / max(1, (n1 + n2));
lambda = 1e-6 * (trace(C) / max(1, M)) + 1e-12;
C = C + lambda * eye(M);
Vw = C \ V;
if all(isfinite(Vw)) && norm(Vw) > 0
    V = Vw;
end
end %func


%--------------------------------------------------------------------------
function C = compute_centroids_(X, labels, K)
M = size(X, 1);
C = nan(M, K);
for k = 1:K
    vi = (labels == k);
    if any(vi), C(:, k) = mean(X(:, vi), 2); end
end
end %func


%--------------------------------------------------------------------------
function cnt = label_counts_(labels, K)
cnt = accumarray(labels(:), 1, [K 1]);
end %func


%--------------------------------------------------------------------------
function [p1, p2] = mutual_nn_pairs_(D)
% Mutual nearest-neighbor pairs from a distance matrix (each index used once).
n = size(D, 1);
p1 = []; p2 = [];
[~, nn] = min(D, [], 2);
used = false(n, 1);
for i = 1:n
    j = nn(i);
    if i ~= j && isfinite(D(i, j)) && nn(j) == i && ~used(i) && ~used(j)
        p1(end+1) = i; p2(end+1) = j; %#ok<AGROW>
        used(i) = true; used(j) = true;
    end
end
end %func


%--------------------------------------------------------------------------
function D = pdist2_(A, B)
% Euclidean distance between rows of A (nA x d) and rows of B (nB x d).
AA = sum(A.^2, 2);
BB = sum(B.^2, 2)';
D = sqrt(max(0, bsxfun(@plus, AA, bsxfun(@minus, BB, 2 * (A * B')))));
end %func


%--------------------------------------------------------------------------
function out = relabel_(labels)
% Map labels to a contiguous 1..K range (row vector). ISO-SPLIT has no noise label.
[~, ~, ic] = unique(labels);
out = reshape(ic, 1, []);
end %func


%--------------------------------------------------------------------------
function v = getfield_default_(s, name, def)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = def;
end
end %func


%--------------------------------------------------------------------------
function test_isosplit5_()
% Quick visual/sanity test: three Gaussian blobs -> expect ~3 clusters.
rng_default_();
X = [randn(2, 500), bsxfun(@plus, randn(2, 500), [6;0]), bsxfun(@plus, randn(2, 400), [3;6])];
labels = isosplit5(X);
fprintf('test_isosplit5_: found %d clusters from 3 blobs (N=%d)\n', max(labels), size(X,2));
end %func


%--------------------------------------------------------------------------
function rng_default_()
try, rng(1); catch, end
end %func
