function export_desync_clusters(vcManifest, vcCsvOut)
% EXPORT_DESYNC_CLUSTERS  Read-only. For each session->_jrc.mat in a manifest, classify EVERY
% cluster and write one CSV row per (session, cluster):
%   session, sort_file, cache_index, viclu_label, n_spikes, status
%
%   status:  clean   = pure AND holds ALL of one viClu label's spikes -> a whole cluster merely
%                       RENUMBERED. This is a SURVIVING cluster (grouping intact).
%            partial = pure but only a SUBSET of one label (that cluster split across cache entries).
%            mixed   = spikes from >1 viClu label in one entry (grouping genuinely altered).
%
%   cache_index  = the cluster number as shown in the GUI / used to index cviSpk_clu & per-cluster
%                  metadata (waveforms, position).
%   viclu_label  = the label those same spikes carry in S_clu.viClu (i.e. in a spike-time export).
%   For a CLEAN cluster: cviSpk_clu{cache_index} == find(viClu==viclu_label) exactly (same spikes).
%
%   Filter status=='clean' for the surviving clusters. NEVER writes/saves a _jrc.mat.
%
%   manifest: text, one line "session,full_path_to_jrc" (header "session,jrc" or "label,jrc" skipped;
%             path may repeat across sessions -- each file is loaded ONCE and cached).

lines = strsplit(fileread(vcManifest), {char(13), char(10)});
lines = lines(~cellfun(@isempty, strtrim(lines)));
if ~isempty(lines) && (strcmpi(strtrim(lines{1}),'session,jrc') || strcmpi(strtrim(lines{1}),'label,jrc')), lines(1)=[]; end

cache = containers.Map('KeyType','char','ValueType','any');
fid = fopen(vcCsvOut, 'w');
fprintf(fid, 'session,sort_file,cache_index,viclu_label,n_spikes,status\n');
nRow = 0; nSessSkip = 0;
for k = 1:numel(lines)
    ix = find(lines{k}==',', 1, 'first');
    if isempty(ix), continue; end
    sess = strtrim(lines{k}(1:ix-1)); f = strtrim(lines{k}(ix+1:end));
    if isempty(f) || strcmpi(f,'NOTFOUND'), nSessSkip=nSessSkip+1; continue; end
    if ~cache.isKey(f), cache(f) = classify_(f); end
    C = cache(f);                       % struct with .base, .idx, .dom, .ni, .status, .ok
    if ~C.ok, nSessSkip=nSessSkip+1; continue; end
    for j = 1:numel(C.idx)
        fprintf(fid, '%s,%s,%d,%d,%d,%s\n', sess, C.base, C.idx(j), C.dom(j), C.ni(j), C.status{j});
        nRow = nRow + 1;
    end
end
fclose(fid);
fprintf('export_desync_clusters: %d cluster-rows over %d sessions (%d skipped) -> %s\n', ...
    nRow, numel(lines)-nSessSkip, nSessSkip, vcCsvOut);
end


%--------------------------------------------------------------------------
function C = classify_(f)
C = struct('base','', 'idx',[], 'dom',[], 'ni',[], 'status',{{}}, 'ok',false);
[~,nm,ex] = fileparts(f); C.base = [nm ex];
if exist(f,'file')~=2, return; end
try, L = load(f, 'S_clu'); catch, return; end
if ~isfield(L,'S_clu') || ~isfield(L.S_clu,'viClu') || ~isfield(L.S_clu,'cviSpk_clu'), return; end
S = L.S_clu; viClu = double(S.viClu(:)); cvi = S.cviSpk_clu; nClu = numel(cvi); nSpk = numel(viClu);
if nClu==0 || nSpk==0, return; end
mx = max(max(viClu), nClu); vn = accumarray(viClu(viClu>=1), 1, [mx,1]);
idx = (1:nClu)'; dom = zeros(nClu,1); ni = zeros(nClu,1); status = cell(nClu,1);
for i = 1:nClu
    vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=nSpk); ni(i) = numel(vi);
    if ni(i)==0, dom(i)=0; status{i}='empty'; continue; end
    lb = viClu(vi); d = mode(lb); dom(i) = d; p = mean(lb==d);
    if p < 1, status{i} = 'mixed';
    elseif d>=1 && d<=mx && ni(i)==vn(d), status{i} = 'clean';
    else, status{i} = 'partial'; end
end
C.idx = idx; C.dom = dom; C.ni = ni; C.status = status; C.ok = true;
end
