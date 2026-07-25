function assess_viclu()
% READ-ONLY. For each corrupt _jrc.mat, assess whether viClu (the SOURCE of the exported
% spike-times CSV) is a coherent clustering -- i.e. whether the CSV is trustworthy.
% Groups spikes BY viClu (not the cache), then flags viClu clusters with a distinct secondary
% depth population interleaved in time (the two-neuron-fusion signature of a mis-targeted merge).
% Loads only small arrays via HDF5 (viClu, depth, time) -- never the multi-GB waveforms. Never writes.
listf = getenv('ASSESS_LIST'); outf = getenv('ASSESS_CSV'); logf = getenv('ASSESS_LOG');
try, diary(logf); catch, end
lines = strsplit(fileread(listf), {char(13),char(10)});
lines = lines(~cellfun(@isempty, strtrim(lines)));
fid = fopen(outf,'w');
fprintf(fid,'file,nClu_viClu,nSpk_valid,nFusionSuspect,worstGapUm,pctSpkInSuspect,assessment\n');
fprintf('%-50s %5s %10s %5s %7s %7s  %s\n','file','nClu','nSpk','nFus','worstUm','%susp','ASSESSMENT');
fprintf('%s\n', repmat('-',1,116));
for k=1:numel(lines)
    f = strtrim(lines{k});
    R = assess_one_(f);
    fprintf(fid,'%s,%d,%d,%d,%d,%.2f,%s\n', R.name,R.nClu,R.nSpk,R.nFus,R.worst,R.pct,R.assess);
    fprintf('%-50s %5d %10d %5d %7d %6.1f%%  %s\n', shorten_(R.name,50), R.nClu,R.nSpk,R.nFus,R.worst,R.pct,R.assess);
end
fclose(fid);
fprintf('\nWrote %s\n', outf);
try, diary off; catch, end
end

function s = shorten_(nm,n), if numel(nm)<=n, s=nm; else, s=[nm(1:n-3) '...']; end, end

function R = assess_one_(f)
R = struct('name','','nClu',0,'nSpk',0,'nFus',0,'worst',0,'pct',0,'assess','SKIP');
[~,nm,ex]=fileparts(f); R.name=[nm ex];
if exist(f,'file')~=2, R.assess='SKIP:missing'; return; end
try, viClu = double(h5read(f,'/S_clu/viClu')); viClu=viClu(:);
catch e, R.assess=['SKIP:viClu']; return; end
vT = firstok_(f, {'/viTime_spk','/S_clu/viTime_spk'});
vY = depth_(f);
R.nClu = max([0;viClu]); R.nSpk = sum(viClu>0);
if isempty(vY) || isempty(vT), R.assess='NO-DEPTH/TIME'; return; end
vY=vY(:); vT=vT(:);
n = min([numel(viClu),numel(vY),numel(vT)]);
viClu=viClu(1:n); vY=vY(1:n); vT=vT(1:n);
idx=find(viClu>0); lab=viClu(idx); [labs,ord]=sort(lab); idxs=idx(ord);
b=[0;find(diff(labs));numel(labs)];
dGapUm=150; minN=100; minFrac=0.15; minFarN=50; minTimeOverlap=0.5;
nSp=0; worst=0; nSpkSusp=0;
for g=1:numel(b)-1
    vi=idxs(b(g)+1:b(g+1));
    if numel(vi)<minN, continue; end
    y=vY(vi); t=vT(vi); ymed=median(y);
    far=abs(y-ymed)>dGapUm; nf=sum(far);
    if nf<max(minFarN,minFrac*numel(vi)), continue; end
    gap=abs(median(y(far))-ymed); if gap<dGapUm, continue; end
    sn=prctile(t(~far),[5 95]); sf=prctile(t(far),[5 95]);
    ov=max(0,min(sn(2),sf(2))-max(sn(1),sf(1))); un=max(sn(2),sf(2))-min(sn(1),sf(1));
    if un>0 && ov/un<minTimeOverlap, continue; end
    nSp=nSp+1; worst=max(worst,gap); nSpkSusp=nSpkSusp+numel(vi);
end
R.nFus=nSp; R.worst=round(worst); R.pct=100*nSpkSusp/max(R.nSpk,1);
if nSp==0, R.assess='LIKELY-CLEAN';
elseif nSp<=2 && R.pct<5, R.assess='MINOR-REVIEW';
else, R.assess='SUSPECT'; end
end

function v = firstok_(f, cands)
v=[]; for i=1:numel(cands), try, v=double(h5read(f,cands{i})); v=v(:); return; catch, end; end
end

function vY = depth_(f)
vY=[];
try
    mp = double(h5read(f,'/mrPos_spk'));
    if     size(mp,1)==2, vY=mp(2,:)';
    elseif size(mp,2)==2, vY=mp(:,2);
    elseif isvector(mp),  vY=mp(:); end
catch, end
if ~isempty(vY), return; end
vs = firstok_(f, {'/viSite_spk','/S_clu/viSite_spk'});
xy = [];
for c = {'/S_clu/P/mrSiteXY','/P/mrSiteXY'}
    try, xy=double(h5read(f,c{1})); break; catch, end
end
if ~isempty(vs) && ~isempty(xy)
    if size(xy,1)==2, xy=xy'; end
    vs(vs<1|vs>size(xy,1))=1;
    vY = xy(vs,2);
end
end
