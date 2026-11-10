function reexport_csv()
% REEXPORT_CSV  Re-write a session's spike-times CSV so it matches the sort's CURRENT viClu.
% Calls the same exporter the GUI uses (export_csv_ -> [time, viClu, site]) via irc('call',...).
% Loads NO waveforms (fLoadWav=0 inside load_cached_), so it is fast. Backs up any existing CSV
% to <csv>.bak_preexport before overwriting.
%
% Env: REEXPORT_PRM = full path to the .prm (the _jrc.mat next to it supplies viClu).
% Use AFTER a recovery for 241209 (clean viClu) or on the current sort for 241206 (stale CSV).
prm = getenv('REEXPORT_PRM');
csv = strrep(prm, '.prm', '.csv');
fprintf('=== reexport_csv ===\nprm: %s\n', prm);
if exist(prm,'file')~=2, fprintf(2,'PRM not found\n'); return; end
if exist(csv,'file')==2
    bak = [csv '.bak_preexport'];
    if exist(bak,'file')~=2, copyfile(csv, bak); fprintf('backed up existing CSV -> %s\n', bak); end
end
So = irc('call','loadParam_',{prm, 0}, 2); P = So.out1;
r  = irc('call','export_csv_',{P}, 1);   % writes <prm>.csv = [time(s), viClu, site]
vc = ''; if isstruct(r) && isfield(r,'out1'), vc = char(r.out1); end
fprintf('re-exported -> %s\n', vc);
% quick self-check: report row count + how many distinct positive units
if exist(csv,'file')==2
    M = readmatrix(csv, 'Delimiter',',');
    up = unique(M(M(:,2)>0,2));
    fprintf('CSV now: %d rows, %d positive units, min unit=%d max unit=%d\n', ...
        size(M,1), numel(up), min(M(:,2)), max(M(:,2)));
end
fprintf('=== DONE ===\n');
end
