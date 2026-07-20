function T = analyze_desync(vcPath, vcOutMd)
% ANALYZE_DESYNC  Read-only forensic on desynced _jrc.mat: how much of the viClu<->cviSpk_clu
% disagreement is a CLEAN LABEL PERMUTATION (grouping preserved, just renumbered) vs COMPOUNDED
% (grouping genuinely altered by a split/merge that ran on the mismatched index after the desync).
%
%   T = analyze_desync(path)            % path = _jrc.mat | manifest.csv (label,jrc) | folder | list
%   T = analyze_desync(path, out.md)    % also write a markdown report
%
%   NEVER writes/saves a _jrc.mat. For each cache cluster i it finds the dominant viClu label
%   d(i)=mode(viClu(cviSpk_clu{i})) and classifies the entry:
%     CLEAN  = pure (100% one label) AND complete (holds ALL of that label's spikes) -> a whole
%              cluster, merely renumbered. Grouping preserved; recoverable in principle.
%     PARTIAL= pure but a SUBSET of one label (that cluster's spikes are split across entries).
%     MIXED  = spikes from >1 viClu label in one entry -> grouping genuinely diverged (compounded).
%   pctSpkPreserved = spikes in CLEAN entries / all cached spikes  (approx. "science intact").
%   cacheCoverage   = cached spikes / total spikes (flags a subsampled cache, which would make the
%                     completeness test conservative -> more PARTIAL, fewer CLEAN).

if nargin<2, vcOutMd = ''; end
cs = local_resolve_(vcPath);
R = repmat(one_(''), numel(cs), 1);
fprintf('\n=== analyze_desync: %d file(s) ===\n', numel(cs));
for k = 1:numel(cs)
    R(k) = one_(cs{k});
    fprintf('  %-46s clean=%-5d partial=%-4d mixed=%-4d  sciPreserved=%5.1f%%  cover=%5.1f%%  %s\n', ...
        char(R(k).name), R(k).nClean, R(k).nPartial, R(k).nMixed, R(k).pctSpkPreserved, R(k).cacheCoverage, char(R(k).note));
end
T = struct2table(R, 'AsArray', true);
if ~isempty(vcOutMd), write_md_(vcOutMd, R); fprintf('wrote %s\n', vcOutMd); end
end


%--------------------------------------------------------------------------
function R = one_(vcFile)
R = struct('file',"", 'name',"", 'nClu',0, 'nClean',0, 'nPartial',0, 'nMixed',0, ...
    'pctSpkPreserved',0, 'cacheCoverage',0, 'isCleanPermutation',false, 'note',"");
if nargin<1 || isempty(vcFile), R.note = "empty-arg"; return; end
vcFile = char(vcFile); R.file = string(vcFile);
[~,nm,ex] = fileparts(vcFile); R.name = string([nm ex]);
if exist(vcFile,'file')~=2, R.note = "missing"; return; end
try, L = load(vcFile,'S_clu'); catch ME, R.note = string(ME.message); return; end
if ~isfield(L,'S_clu') || ~isfield(L.S_clu,'viClu') || ~isfield(L.S_clu,'cviSpk_clu'), R.note="noS_clu/fields"; return; end
S = L.S_clu; viClu = double(S.viClu(:)); cvi = S.cviSpk_clu; nClu = numel(cvi); nSpk = numel(viClu);
if nClu==0 || nSpk==0, R.note="empty"; return; end
R.nClu = nClu;
mx = max(max(viClu), nClu);
vn = accumarray(viClu(viClu>=1), 1, [mx,1]);   % # spikes per viClu label
nClean=0; nPartial=0; nMixed=0; spkClean=0; spkTot=0;
for i = 1:nClu
    vi = double(cvi{i}(:)); vi = vi(vi>=1 & vi<=nSpk); ni = numel(vi);
    if ni==0, continue; end
    spkTot = spkTot + ni;
    lb = viClu(vi); dom = mode(lb); p = mean(lb==dom);
    if p < 1
        nMixed = nMixed + 1;
    elseif dom>=1 && dom<=mx && ni==vn(dom)
        nClean = nClean + 1; spkClean = spkClean + ni;   % pure + whole cluster => cache{i}==find(viClu==dom)
    else
        nPartial = nPartial + 1;
    end
end
R.nClean=nClean; R.nPartial=nPartial; R.nMixed=nMixed;
R.pctSpkPreserved = 100*spkClean/max(spkTot,1);
R.cacheCoverage   = 100*spkTot/max(nSpk,1);
R.isCleanPermutation = (nMixed==0 && nPartial==0);
end


%--------------------------------------------------------------------------
function write_md_(vcFile, R)
L = {'# Desync forensic — clean permutation vs compounded', '', ...
    'For each corrupted `_jrc.mat`: CLEAN = whole cluster merely renumbered (grouping preserved); PARTIAL = one cluster split across cache entries; MIXED = a cache entry holds >1 viClu label (grouping genuinely altered/compounded). `sciPreserved` = spikes in CLEAN entries / cached spikes. `cover` <100% means the cache is subsampled (completeness test is then conservative).', '', ...
    '| file | nClu | clean | partial | mixed | sciPreserved | cover | cleanPerm |', '|---|---|---|---|---|---|---|---|'};
for k=1:numel(R)
    L{end+1} = sprintf('| `%s` | %d | %d | %d | %d | %.1f%% | %.1f%% | %d |', ...
        char(R(k).name), R(k).nClu, R(k).nClean, R(k).nPartial, R(k).nMixed, ...
        R(k).pctSpkPreserved, R(k).cacheCoverage, R(k).isCleanPermutation); %#ok<AGROW>
end
fid=fopen(vcFile,'w'); if fid<0, return; end
fprintf(fid,'%s\n',L{:}); fclose(fid);
end


%--------------------------------------------------------------------------
function cs = local_resolve_(vcPath)
if iscell(vcPath), cs={}; for i=1:numel(vcPath), cs=[cs; local_resolve_(vcPath{i})]; end, return; end %#ok<AGROW>
if isstring(vcPath), vcPath = char(vcPath); end
if isfolder(vcPath)
    d = dir(fullfile(vcPath,'**','*_jrc.mat')); cs = arrayfun(@(x)fullfile(x.folder,x.name), d, 'UniformOutput',0);
elseif endsWith(lower(vcPath),'.csv')
    txt = strsplit(fileread(vcPath), {char(13),char(10)}); txt = txt(~cellfun(@isempty,strtrim(txt)));
    if ~isempty(txt) && strcmpi(strtrim(txt{1}),'label,jrc'), txt(1)=[]; end
    cs = {}; for i=1:numel(txt), ix=find(txt{i}==',',1); if ~isempty(ix), p=strtrim(txt{i}(ix+1:end)); if ~isempty(p)&&~strcmpi(p,'NOTFOUND'), cs{end+1}=p; end, end, end %#ok<AGROW>
    cs = cs(:);
else
    cs = {vcPath};
end
end
