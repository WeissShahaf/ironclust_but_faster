function [labels, info] = hdbscan_fit(X, minClusterSize, minPts)
% HDBSCAN_FIT  Pure-MATLAB HDBSCAN* clustering.
%   labels = hdbscan_fit(X, minClusterSize, minPts)
%
%   Inputs:
%     X              : (n x d) data matrix, one row per point.
%     minClusterSize : smallest number of points that may form a cluster (>=2).
%     minPts         : core-distance neighborhood size (a.k.a. min_samples).
%   Output:
%     labels : (n x 1) integer labels in 1..K; 0 = noise.
%     info   : struct with .num_clusters.
%
%   Pipeline (Campello, Moulavi & Sander 2013):
%     1. core distance of each point  = distance to its minPts-th neighbor
%     2. mutual reachability distance  = max(core_i, core_j, d(i,j))
%     3. minimum spanning tree of the mutual-reachability graph (kNN graph +
%        component connection), via Kruskal + union-find
%     4. single-linkage hierarchy from the MST
%     5. condensed tree using minClusterSize
%     6. cluster selection by Excess of Mass (EOM) stability
%
%   Uses knnsearch when the Statistics and Machine Learning Toolbox is present,
%   otherwise a chunked brute-force kNN.

if nargin<1, test_hdbscan_fit_(); return; end
if nargin<2 || isempty(minClusterSize), minClusterSize = 10; end
if nargin<3 || isempty(minPts), minPts = 10; end

X = double(X);
n = size(X, 1);
info = struct('num_clusters', 0);
labels = zeros(n, 1);
if n == 0, return; end

mcs = max(2, round(minClusterSize));
if n < 2 * mcs
    labels = ones(n, 1); info.num_clusters = 1; return;   % too few points for >1 cluster
end
minPts  = max(1, min(round(minPts), n - 1));
k_graph = min(n - 1, max(minPts, 16));

% ---- 1-2. core distances and mutual-reachability kNN edges ----
[idx, dst] = knn_(X, k_graph + 1);          % column 1 is the point itself
core = dst(:, minPts + 1);                  % distance to minPts-th neighbor
ii = repmat((1:n)', 1, k_graph);
jj = idx(:, 2:k_graph + 1);
dd = dst(:, 2:k_graph + 1);
mr = max(max(core(ii), core(jj)), dd);

a = ii(:); b = jj(:); w = mr(:);
lo = min(a, b); hi = max(a, b);
keep = lo ~= hi;
lo = lo(keep); hi = hi(keep); w = w(keep);
[uu, iu] = unique([lo, hi], 'rows');
E = [uu, w(iu)];

% ---- 3-4. MST then single-linkage hierarchy ----
mst = kruskal_mst_(E, n, X, core);
Z = linkage_from_mst_(mst, n);

% ---- 5. condensed tree ----
[rp, rc, rl, rs, baseCluster] = condense_tree_(Z, n, mcs);
if isempty(rp)
    labels = ones(n, 1); info.num_clusters = 1; return;
end
maxCluster = max([rp, rc(rc > n), baseCluster]);

% ---- 6. stability + EOM selection + labelling ----
stab = compute_stability_(rp, rc, rl, rs, n, maxCluster);
selected = get_clusters_eom_(rp, rc, stab, n, baseCluster, maxCluster);
labels = do_labelling_(rp, rc, n, selected, maxCluster);
info.num_clusters = numel(selected);
end %func


%--------------------------------------------------------------------------
function [idx, dst] = knn_(X, K)
% K nearest neighbors (including self as the first column).
n = size(X, 1);
if exist('knnsearch', 'file') == 2 || exist('knnsearch', 'file') == 6
    [idx, dst] = knnsearch(X, X, 'K', K);
    return;
end
idx = zeros(n, K); dst = zeros(n, K);
blk = max(1, floor(2e7 / max(1, n)));       % rows per block (bounds memory ~ blk*n)
for i0 = 1:blk:n
    vi = i0:min(i0 + blk - 1, n);
    D = pdist2_(X(vi, :), X);
    [s, o] = sort(D, 2);
    idx(vi, :) = o(:, 1:K);
    dst(vi, :) = s(:, 1:K);
end
end %func


%--------------------------------------------------------------------------
function mst = kruskal_mst_(E, n, X, core)
% Minimum spanning tree (Kruskal). If the kNN edge set leaves a forest, the
% remaining components are connected via mutual-reachability edges between
% component representatives.
[~, ord] = sort(E(:, 3), 'ascend');
E = E(ord, :);
uf = 1:n;
mst = zeros(n - 1, 3);
nE = 0;
for r = 1:size(E, 1)
    [ra, uf] = find_(uf, E(r, 1));
    [rb, uf] = find_(uf, E(r, 2));
    if ra ~= rb
        uf(ra) = rb;
        nE = nE + 1; mst(nE, :) = E(r, :);
        if nE == n - 1, break; end
    end
end
if nE < n - 1
    roots = zeros(1, n);
    for x = 1:n, [roots(x), uf] = find_(uf, x); end
    comps = unique(roots);
    reps = arrayfun(@(c) find(roots == c, 1), comps);
    R = X(reps, :);
    RD = pdist2_(R, R);
    cr = core(reps);
    RD = max(max(RD, cr(:) * ones(1, numel(reps))), ones(numel(reps), 1) * cr(:)');
    elist = zeros(0, 3);
    for i = 1:numel(reps)
        for j = i + 1:numel(reps)
            elist(end + 1, :) = [reps(i), reps(j), RD(i, j)]; %#ok<AGROW>
        end
    end
    [~, o] = sort(elist(:, 3), 'ascend'); elist = elist(o, :);
    for r = 1:size(elist, 1)
        [ra, uf] = find_(uf, elist(r, 1));
        [rb, uf] = find_(uf, elist(r, 2));
        if ra ~= rb
            uf(ra) = rb;
            nE = nE + 1; mst(nE, :) = elist(r, :);
        end
    end
end
mst = mst(1:nE, :);
end %func


%--------------------------------------------------------------------------
function Z = linkage_from_mst_(mst, n)
% Single-linkage dendrogram from MST edges. Z(s,:) = [child1 child2 dist size]
% and corresponds to internal node id n+s; points are ids 1..n, root = 2n-1.
[~, o] = sort(mst(:, 3), 'ascend');
mst = mst(o, :);
uf = 1:n;
node_id = 1:n;                       % tree-node id for each union-find root
size_node = ones(1, 2 * n - 1);
Z = zeros(n - 1, 4);
next = n;
for r = 1:size(mst, 1)
    [ra, uf] = find_(uf, mst(r, 1));
    [rb, uf] = find_(uf, mst(r, 2));
    if ra == rb, continue; end
    ia = node_id(ra); ib = node_id(rb);
    next = next + 1;
    sz = size_node(ia) + size_node(ib);
    Z(next - n, :) = [ia, ib, mst(r, 3), sz];
    size_node(next) = sz;
    uf(ra) = rb;
    node_id(rb) = next;
end
end %func


%--------------------------------------------------------------------------
function [rp, rc, rl, rs, baseCluster] = condense_tree_(Z, n, mcs)
% Condense the single-linkage tree. Returns parallel arrays of condensed-tree
% edges: parent cluster (rp), child (rc; >n cluster, <=n point), lambda (rl),
% child point-count (rs). Cluster ids start at baseCluster = n+1.
root = 2 * n - 1;
relabel = zeros(1, 2 * n - 1);
baseCluster = n + 1;
relabel(root) = baseCluster;
next_label = baseCluster + 1;
ignore = false(1, 2 * n - 1);
order = bfs_internal_(root, Z, n);

rp = []; rc = []; rl = []; rs = [];
for oi = 1:numel(order)
    node = order(oi);
    if ignore(node), continue; end
    L = Z(node - n, 1); R = Z(node - n, 2); dd = Z(node - n, 3);
    if dd > 0, lambda = 1 / dd; else, lambda = inf; end
    lc = node_size_pts_(L, Z, n);
    rcnt = node_size_pts_(R, Z, n);
    if lc >= mcs && rcnt >= mcs
        relabel(L) = next_label; next_label = next_label + 1;
        rp(end+1) = relabel(node); rc(end+1) = relabel(L); rl(end+1) = lambda; rs(end+1) = lc; %#ok<AGROW>
        relabel(R) = next_label; next_label = next_label + 1;
        rp(end+1) = relabel(node); rc(end+1) = relabel(R); rl(end+1) = lambda; rs(end+1) = rcnt; %#ok<AGROW>
    elseif lc < mcs && rcnt < mcs
        [rp, rc, rl, rs, ignore] = shed_(rp, rc, rl, rs, ignore, relabel(node), lambda, [subtree_nodes_(L, Z, n), subtree_nodes_(R, Z, n)], n);
    elseif lc < mcs
        relabel(R) = relabel(node);
        [rp, rc, rl, rs, ignore] = shed_(rp, rc, rl, rs, ignore, relabel(node), lambda, subtree_nodes_(L, Z, n), n);
    else
        relabel(L) = relabel(node);
        [rp, rc, rl, rs, ignore] = shed_(rp, rc, rl, rs, ignore, relabel(node), lambda, subtree_nodes_(R, Z, n), n);
    end
end
end %func


%--------------------------------------------------------------------------
function [rp, rc, rl, rs, ignore] = shed_(rp, rc, rl, rs, ignore, parent_label, lambda, subs, n)
% Record points that "fall out" of a cluster at this lambda and ignore the subtree.
for s = subs
    if s <= n
        rp(end+1) = parent_label; rc(end+1) = s; rl(end+1) = lambda; rs(end+1) = 1; %#ok<AGROW>
    end
    ignore(s) = true;
end
end %func


%--------------------------------------------------------------------------
function order = bfs_internal_(root, Z, n)
% Internal nodes in breadth-first order from root (parents before children).
order = zeros(1, 0);
q = root;
while ~isempty(q)
    x = q(1); q(1) = [];
    if x > n
        order(end+1) = x; %#ok<AGROW>
        q(end+1) = Z(x - n, 1); %#ok<AGROW>
        q(end+1) = Z(x - n, 2); %#ok<AGROW>
    end
end
end %func


%--------------------------------------------------------------------------
function nodes = subtree_nodes_(v, Z, n)
nodes = zeros(1, 0);
st = v;
while ~isempty(st)
    x = st(end); st(end) = [];
    nodes(end+1) = x; %#ok<AGROW>
    if x > n
        st(end+1) = Z(x - n, 1); %#ok<AGROW>
        st(end+1) = Z(x - n, 2); %#ok<AGROW>
    end
end
end %func


%--------------------------------------------------------------------------
function s = node_size_pts_(v, Z, n)
if v <= n, s = 1; else, s = Z(v - n, 4); end
end %func


%--------------------------------------------------------------------------
function stab = compute_stability_(rp, rc, rl, rs, n, maxCluster)
% EOM stability of each cluster. Index by (cluster id - n); root birth = 0.
nC = maxCluster - n;
birth = zeros(1, nC);
for r = 1:numel(rc)
    if rc(r) > n, birth(rc(r) - n) = rl(r); end
end
stab = zeros(1, nC);
for r = 1:numel(rp)
    idx = rp(r) - n;
    stab(idx) = stab(idx) + (rl(r) - birth(idx)) * rs(r);
end
end %func


%--------------------------------------------------------------------------
function selected = get_clusters_eom_(rp, rc, stab, n, baseCluster, maxCluster)
% Excess-of-Mass cluster selection. The root (baseCluster) is never selected
% on its own (standard HDBSCAN default).
clusterIds = baseCluster:maxCluster;
nC = maxCluster - n;
is_cluster = true(1, nC);
is_cluster(baseCluster - n) = false;
process = sort(clusterIds(clusterIds ~= baseCluster), 'descend');
for node = process
    ch = rc((rp == node) & (rc > n));
    if isempty(ch), subs = 0; else, subs = sum(stab(ch - n)); end
    if subs > stab(node - n)
        is_cluster(node - n) = false;
        stab(node - n) = subs;
    else
        desc = descendants_cluster_(node, rp, rc, n);
        if ~isempty(desc), is_cluster(desc - n) = false; end
    end
end
selected = clusterIds(is_cluster(clusterIds - n));
end %func


%--------------------------------------------------------------------------
function desc = descendants_cluster_(node, rp, rc, n)
desc = zeros(1, 0);
q = node;
while ~isempty(q)
    x = q(1); q(1) = [];
    ch = rc((rp == x) & (rc > n));
    for c = ch
        desc(end+1) = c; q(end+1) = c; %#ok<AGROW>
    end
end
end %func


%--------------------------------------------------------------------------
function labels = do_labelling_(rp, rc, n, selected, maxCluster)
labels = zeros(n, 1);
if isempty(selected), return; end
pointHost = zeros(1, n);
parentOf = zeros(1, maxCluster - n);
for r = 1:numel(rc)
    if rc(r) <= n
        pointHost(rc(r)) = rp(r);
    else
        parentOf(rc(r) - n) = rp(r);
    end
end
selMap = zeros(1, maxCluster - n);
selMap(selected - n) = 1:numel(selected);
for p = 1:n
    h = pointHost(p);
    while h > n && selMap(h - n) == 0
        h = parentOf(h - n);
    end
    if h > n && selMap(h - n) > 0
        labels(p) = selMap(h - n);
    end
end
end %func


%--------------------------------------------------------------------------
function [r, uf] = find_(uf, x)
% Union-find root with path compression.
r = x;
while uf(r) ~= r, r = uf(r); end
while uf(x) ~= r
    tmp = uf(x); uf(x) = r; x = tmp;
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
function test_hdbscan_fit_()
% Sanity test: two well-separated blobs plus scattered noise.
try, rng(1); catch, end
X = [randn(300, 2); bsxfun(@plus, randn(300, 2), [8, 0]); bsxfun(@plus, 20 * rand(40, 2), [-6, -6])];
labels = hdbscan_fit(X, 20, 10);
fprintf('test_hdbscan_fit_: %d clusters, %d noise points (N=%d)\n', ...
    numel(unique(labels(labels > 0))), sum(labels == 0), size(X, 1));
end %func
