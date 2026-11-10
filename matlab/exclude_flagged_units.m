function exclude_flagged_units()
% EXCLUDE_FLAGGED_UNITS  Set column 2 (viClu unit id) to -2 ("excluded/deleted") for the flagged
% fusion units in each session's exported spike-times CSV.
%
% Input : exclude_manifest.csv  with columns  csv_path,units,kind  (units = space-separated ids).
% Env   : EXCL_MANIFEST, EXCL_LOG, EXCL_WRITE=1 (default = DRY RUN, writes nothing).
%
% Write mode: backs up <csv> -> <csv>.bak (once), rewrites via <csv>.tmp then movefile, refuses an
% empty temp. col1 = time (%.9g, matches original dlmwrite precision-9), remaining cols = integers.
manf = getenv('EXCL_MANIFEST'); logf = getenv('EXCL_LOG');
fWrite = strcmpi(getenv('EXCL_WRITE'),'1');
try, diary(logf); catch, end
fprintf('=== exclude_flagged_units (WRITE=%d) ===\n', fWrite);
rows = read_manifest_(manf);
for i = 1:numel(rows)
    csv = rows(i).csv; units = rows(i).units; kind = rows(i).kind;
    fprintf('\n[%s] %s\n  exclude units: %s\n', kind, csv, mat2str(units));
    if isempty(units), fprintf('  no units parsed - skip\n'); continue; end
    if exist(csv,'file') ~= 2, fprintf('  MISSING - skip\n'); continue; end
    try, M = readmatrix(csv, 'Delimiter',','); catch e, fprintf('  READ FAIL: %s\n', e.message); continue; end
    if size(M,2) < 2, fprintf('  <2 columns - skip\n'); continue; end
    sel = ismember(M(:,2), units);
    matched = intersect(unique(M(:,2))', units);
    fprintf('  rows total=%d  to_set_-2=%d (%.3f%%)  units matched=%s\n', ...
        size(M,1), sum(sel), 100*sum(sel)/size(M,1), mat2str(matched));
    missing = setdiff(units, matched);
    if ~isempty(missing), fprintf('  NOTE: units not present in this CSV: %s\n', mat2str(missing)); end
    if ~fWrite, fprintf('  DRY RUN: not written.\n'); continue; end
    M(sel,2) = -2;
    bak = [csv '.bak'];
    if exist(bak,'file') ~= 2, copyfile(csv, bak); fprintf('  backed up -> %s\n', bak); end
    tmp = [csv '.tmp'];
    fmt = ['%.9g' repmat(',%d',1,size(M,2)-1) '\n'];
    fid = fopen(tmp,'w');
    if fid < 0, fprintf('  FOPEN FAIL - skip (original kept)\n'); continue; end
    fprintf(fid, fmt, M'); fclose(fid);
    d = dir(tmp);
    if isempty(d) || d(1).bytes == 0, fprintf('  temp empty - abort (original kept)\n'); if exist(tmp,'file'), delete(tmp); end; continue; end
    movefile(tmp, csv, 'f');
    fprintf('  WROTE %d rows, %d relabeled -> %s (original at .bak)\n', size(M,1), sum(sel), csv);
end
fprintf('\n=== DONE ===\n');
try, diary off; catch, end
end

function rows = read_manifest_(manf)
% Robust manual parse of a (possibly quoted) csv_path,units,kind manifest with a header row.
% units parsed by extracting ALL integer tokens (\d+), immune to quoting / readtable type coercion.
rows = struct('csv',{},'units',{},'kind',{});
lines = strsplit(fileread(manf), {char(13),char(10)});
lines = lines(~cellfun(@isempty, strtrim(lines)));
for i = 1:numel(lines)
    L = strtrim(lines{i});
    if i==1 && contains(lower(L),'csv_path'), continue; end   % header
    parts = strsplit(L, ',');
    if numel(parts) < 2, continue; end
    csv = unquote_(parts{1});
    units = str2double(regexp(unquote_(parts{2}), '\d+', 'match'));
    kind = ''; if numel(parts) >= 3, kind = unquote_(parts{3}); end
    rows(end+1) = struct('csv',csv,'units',units(:)','kind',kind); %#ok<AGROW>
end
end

function s = unquote_(s)
s = strtrim(s);
if numel(s) >= 2 && s(1)=='"' && s(end)=='"', s = s(2:end-1); end
end
