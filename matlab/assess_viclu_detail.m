function assess_viclu_detail()
% READ-ONLY. For each file, list the SPECIFIC viClu clusters flagged as two-neuron fusions.
% The cluster id printed IS the unit number in the exported spike-times CSV (column 2 = viClu).
% Loads only viClu + depth + time via HDF5. Never writes a _jrc.mat.
listf=getenv('DETAIL_LIST'); outf=getenv('DETAIL_CSV'); logf=getenv('DETAIL_LOG');
try, diary(logf); catch, end
lines=strsplit(fileread(listf),{char(13),char(10)}); lines=lines(~cellfun(@isempty,strtrim(lines)));
fid=fopen(outf,'w');
fprintf(fid,'file,viClu_unit,n_spikes,main_depth_um,secondary_depth_um,gap_um,pct_secondary,time_overlap\n');
for k=1:numel(lines)
    f=strtrim(lines{k}); [~,nm,ex]=fileparts(f);
    fprintf('\n=== %s ===\n', [nm ex]);
    detail_one_(f, [nm ex], fid);
end
fclose(fid);
fprintf('\nWrote %s\n', outf);
try, diary off; catch, end
end

function detail_one_(f, name, fid)
if exist(f,'file')~=2, fprintf('  missing\n'); return; end
try, viClu=double(h5read(f,'/S_clu/viClu')); viClu=viClu(:); catch, fprintf('  viClu read fail\n'); return; end
vT=firstok_(f,{'/viTime_spk','/S_clu/viTime_spk'}); vY=depth_(f);
if isempty(vY)||isempty(vT), fprintf('  no depth/time\n'); return; end
vY=vY(:); vT=vT(:); n=min([numel(viClu),numel(vY),numel(vT)]);
viClu=viClu(1:n); vY=vY(1:n); vT=vT(1:n);
idx=find(viClu>0); lab=viClu(idx); [labs,ord]=sort(lab); idxs=idx(ord);
b=[0;find(diff(labs));numel(labs)];
dGapUm=150;minN=100;minFrac=0.15;minFarN=50;minTimeOverlap=0.5;
nflag=0;
for g=1:numel(b)-1
    vi=idxs(b(g)+1:b(g+1)); L=labs(b(g)+1);
    if numel(vi)<minN, continue; end
    y=vY(vi); t=vT(vi); ymed=median(y);
    far=abs(y-ymed)>dGapUm; nf=sum(far);
    if nf<max(minFarN,minFrac*numel(vi)), continue; end
    gap=abs(median(y(far))-ymed); if gap<dGapUm, continue; end
    sn=prctile(t(~far),[5 95]); sf=prctile(t(far),[5 95]);
    ov=max(0,min(sn(2),sf(2))-max(sn(1),sf(1))); un=max(sn(2),sf(2))-min(sn(1),sf(1));
    if ~(un>0 && ov/un>=minTimeOverlap), continue; end
    nflag=nflag+1;
    fprintf('  unit %4d: n=%7d  main=%4.0fum  secondary=%4.0fum  gap=%4.0fum  %2.0f%% in secondary\n', ...
        L, numel(vi), ymed, median(y(far)), gap, 100*nf/numel(vi));
    fprintf(fid,'%s,%d,%d,%.0f,%.0f,%.0f,%.1f,%.2f\n', name, L, numel(vi), ymed, median(y(far)), gap, 100*nf/numel(vi), ov/max(un,1));
end
if nflag==0, fprintf('  (no flagged units)\n'); end
end

function v = firstok_(f, cands)
v=[]; for i=1:numel(cands), try, v=double(h5read(f,cands{i})); v=v(:); return; catch, end; end
end
function vY = depth_(f)
vY=[];
try
    mp=double(h5read(f,'/mrPos_spk'));
    if size(mp,1)==2, vY=mp(2,:)'; elseif size(mp,2)==2, vY=mp(:,2); elseif isvector(mp), vY=mp(:); end
catch, end
if ~isempty(vY), return; end
vs=firstok_(f,{'/viSite_spk','/S_clu/viSite_spk'}); xy=[];
for c={'/S_clu/P/mrSiteXY','/P/mrSiteXY'}, try, xy=double(h5read(f,c{1})); break; catch, end, end
if ~isempty(vs) && ~isempty(xy)
    if size(xy,1)==2, xy=xy'; end
    vs(vs<1|vs>size(xy,1))=1; vY=xy(vs,2);
end
end
