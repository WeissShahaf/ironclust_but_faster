function T = scan_jrc_report(vcManifest, vcOutDir, vcTitle)
% SCAN_JRC_REPORT  Batch integrity check of many sorted _jrc.mat, with per-session logs + an
% .md report of affected sessions. Read-only (uses check_jrc_one; never writes to any _jrc.mat).
%
%   scan_jrc_report(manifest, outDir, title)
%
%   manifest : text file, one line per dataset:  "label,full_path_to_jrc"
%              (path may be "NOTFOUND"/empty for sessions with no sort found). An optional
%              header line "label,jrc" is skipped.
%   outDir   : folder for outputs. Writes:
%                <outDir>\logs\<label>.log        (one per session, full metrics)
%                <outDir>\AFFECTED_REPORT.md      (consolidated report)
%   title    : (optional) title string for the .md report.
%
%   Returns the full results table T.

if nargin<3 || isempty(vcTitle), vcTitle = 'Sorted-dataset integrity scan'; end
assert(exist(vcManifest,'file')==2, 'manifest not found: %s', vcManifest);
vcLogDir = fullfile(vcOutDir, 'logs');
if ~isfolder(vcLogDir), mkdir(vcLogDir); end

% --- read manifest ---
cs = strsplit(fileread(vcManifest), {sprintf('\r\n'), sprintf('\n')});
cs = cs(~cellfun(@isempty, strtrim(cs)));
if ~isempty(cs) && strcmpi(strtrim(cs{1}), 'label,jrc'), cs(1) = []; end   % skip header
n = numel(cs);
[labels, paths] = deal(cell(n,1));
for k = 1:n
    ln = cs{k}; ix = find(ln==',', 1, 'first');   % split on FIRST comma
    if isempty(ix), labels{k} = strtrim(ln); paths{k} = '';
    else, labels{k} = strtrim(ln(1:ix-1)); paths{k} = strtrim(ln(ix+1:end)); end
end

% --- check each, write per-session log ---
R = repmat(check_jrc_one(''), n, 1);
lbl = strings(n,1);
fprintf('scan_jrc_report: %d dataset(s) from %s\n', n, vcManifest);
for k = 1:n
    lbl(k) = string(labels{k});
    p = paths{k};
    if isempty(p) || strcmpi(p,'NOTFOUND')
        R(k) = check_jrc_one('');  R(k).verdict = "SKIP:notfound";  R(k).name = string(labels{k});
    else
        R(k) = check_jrc_one(p);
    end
    write_log_(fullfile(vcLogDir, [safe_(labels{k}) '.log']), labels{k}, R(k));
    fprintf('  [%3d/%3d] %-38s %-14s (nClu=%d desync=%d mix=%d spatial=%d)\n', ...
        k, n, labels{k}, char(R(k).verdict), R(k).nClu, R(k).nCluDesync, R(k).nCacheMix, R(k).nCluSpatial);
end

T = struct2table(R, 'AsArray', true);
T = addvars(T, lbl, 'Before', 1, 'NewVariableNames', 'label');

% --- write the .md report ---
write_report_(fullfile(vcOutDir,'AFFECTED_REPORT.md'), vcTitle, vcManifest, lbl, R);
fprintf('\nWrote %s and %d per-session logs in %s\n', fullfile(vcOutDir,'AFFECTED_REPORT.md'), n, vcLogDir);
end


%--------------------------------------------------------------------------
function write_log_(vcFile, vcLabel, R)
fid = fopen(vcFile, 'w'); if fid<0, return; end
fprintf(fid, 'session : %s\n', vcLabel);
fprintf(fid, 'file    : %s\n', char(R.file));
fprintf(fid, 'verdict : %s\n', char(R.verdict));
fprintf(fid, 'nClu=%d  nSpk=%d\n', R.nClu, R.nSpk);
fprintf(fid, 'nCluDesync=%d  nCacheMixLabels=%d  pctSpkWrong=%.3f%%\n', R.nCluDesync, R.nCacheMix, R.pctSpkWrong);
fprintf(fid, 'nCluSpatialFlag=%d  worstSiteSpan=%d\n', R.nCluSpatial, round(R.worstSiteSpan));
if strlength(R.note)>0, fprintf(fid, 'note    : %s\n', char(R.note)); end
fclose(fid);
end


%--------------------------------------------------------------------------
function write_report_(vcFile, vcTitle, vcManifest, lbl, R)
v = [R.verdict];
isDes  = startsWith(v,'DESYNC');
isSkip = startsWith(v,'SKIP');
isSpat = [R.nCluSpatial]'>0 & ~isDes(:) & ~isSkip(:);
L = {};
L{end+1} = sprintf('# %s', vcTitle);
L{end+1} = '';
L{end+1} = sprintf('- Manifest: `%s`', vcManifest);
L{end+1} = sprintf('- Datasets: **%d**  ·  PASS: %d  ·  **DESYNC: %d**  ·  spatially-flagged (PASS): %d  ·  not-checked: %d', ...
    numel(R), sum(v=="PASS"), sum(isDes), sum(isSpat), sum(isSkip));
L{end+1} = '- Test: `all( viClu(cviSpk_clu{i}) == i )` per cluster (the [O]-reorder / desync signature). A **DESYNC verdict = corrupted → re-sort** (not repairable). Spatial flags are heuristic candidates to eyeball. A PASS is "currently self-consistent", not a proof of "never corrupted"; DI-01 `[U]` wrong-merges are undetectable here.';
L{end+1} = '';

L{end+1} = '## ⛔ Affected — DESYNC (re-sort these)';
if any(isDes)
    L = [L, md_table_(lbl(isDes), R(isDes), {'label','verdict','nClu','nCluDesync','nCacheMix','pctSpkWrong','file'})];
else
    L{end+1} = '_None._';
end
L{end+1} = '';

L{end+1} = '## 🔍 Review — PASS but spatially flagged (heuristic; may be normal drift/large units)';
if any(isSpat)
    L = [L, md_table_(lbl(isSpat), R(isSpat), {'label','nClu','nCluSpatial','worstSiteSpan','file'})];
else
    L{end+1} = '_None._';
end
L{end+1} = '';

L{end+1} = '## ⚠ Not checked (no sort found / load error)';
if any(isSkip)
    L = [L, md_table_(lbl(isSkip), R(isSkip), {'label','verdict','note','file'})];
else
    L{end+1} = '_None._';
end
L{end+1} = '';

L{end+1} = '## All results';
L = [L, md_table_(lbl, R, {'label','verdict','nClu','nCluDesync','nCacheMix','pctSpkWrong','nCluSpatial','file'})];

fid = fopen(vcFile,'w'); if fid<0, warning('cannot write %s', vcFile); return; end
fprintf(fid, '%s\n', L{:});
fclose(fid);
end


%--------------------------------------------------------------------------
function C = md_table_(lbl, R, cols)
C = {['| ' strjoin(cols,' | ') ' |'], ['|' repmat('---|',1,numel(cols))]};
for k = 1:numel(R)
    cells = cell(1,numel(cols));
    for j = 1:numel(cols)
        switch cols{j}
            case 'label',        cells{j} = char(lbl(k));
            case 'verdict',      cells{j} = char(R(k).verdict);
            case 'note',         cells{j} = char(R(k).note);
            case 'file',         cells{j} = ['`' char(R(k).file) '`'];
            case 'pctSpkWrong',  cells{j} = sprintf('%.2f%%', R(k).pctSpkWrong);
            case 'worstSiteSpan',cells{j} = num2str(round(R(k).worstSiteSpan));
            otherwise,           cells{j} = num2str(R(k).(cols{j}));
        end
        cells{j} = strrep(cells{j}, '|', '\|');
    end
    C{end+1} = ['| ' strjoin(cells,' | ') ' |']; %#ok<AGROW>
end
end


%--------------------------------------------------------------------------
function s = safe_(s)
s = regexprep(char(s), '[^A-Za-z0-9._-]', '_');
if isempty(s), s = 'session'; end
end
