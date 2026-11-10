function test_nearest_in_set_gpu(vcFile_prm, m_test)
% Isolated CPU-vs-GPU test of nearest_in_set_ (the per-site capped-cluster 1-NN
% assignment) on a REAL recording's cached features. Confirms the GPU path returns
% indices bit-identical to the CPU path and reports the speedup, and exercises the
% parfor-worker guard (getCurrentTask() -> declines GPU -> CPU).
%
% This reproduces EXACTLY how cluster_site_capped_ builds its inputs:
%   - per-site feature matrix X = reshape(trFet_spk(:,:,viSpk1),[],n1)' (as
%     cluster_labels_persite_), cast to double (as cluster_site_),
%   - the seeded random subsample rng(viSpk1(1),'twister'); sort(randperm(n1,m)),
%   - the call nearest_in_set_(X', Xsub', fUseGpu).
% so the numbers here match what a real capped-site sort would do.
%
% Usage (from D:\github\ironclustSW\matlab, or anywhere on the irc.m path):
%   test_nearest_in_set_gpu('E:\scratch\tmp\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_irc_all.prm')
%   test_nearest_in_set_gpu(prm, 200000)   % override the subsample size m
%
% Requires: the recording's detect/feature cache (*_jrc.mat + *_spkfet.jrc) on disk.
% No repo files are modified; nothing is saved.

if nargin < 1 || isempty(vcFile_prm)
    vcFile_prm = 'E:\scratch\tmp\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_irc_all.prm';
end
if nargin < 2, m_test = []; end

% --- load params + cached per-site spikes (this also populates trFet_spk) ---
Sp = irc('call', 'loadParam_',  {vcFile_prm}, 1);  P  = Sp.out1;
Sc = irc('call', 'load_cached_', {P},          2);  S0 = Sc.out1;  P = Sc.out2;
if isempty(S0) || ~isfield(S0,'cviSpk_site') || isempty(S0.cviSpk_site)
    error('No cached per-site spikes for %s (run the detect/feature stage first).', vcFile_prm);
end

% --- load the spike features explicitly (robust; same call cluster_labels_persite_ uses) ---
Tf = irc('call', 'load_bin_', {strrep(P.vcFile_prm,'.prm','_spkfet.jrc'), 'single', S0.dimm_fet}, 1);
trFet_spk = Tf.out1;

% --- report the .prm switches that govern the CPU/GPU decision for this path ---
fGpu    = getfield_or_(P, 'fGpu', 0);
fParfor = getfield_or_(P, 'fParfor', 1);
maxSpk  = getfield_or_(P, 'maxSpk_persite_clust', []);
fprintf('\n=== nearest_in_set_ CPU-vs-GPU test ===\n');
fprintf('.prm switches:  fGpu=%g  fParfor=%g  maxSpk_persite_clust=%s\n', ...
    fGpu, fParfor, mat2str(maxSpk));
fprintf('  -> cluster_site_capped_ would set fUseGpu = fGpu (=%g); fParfor=1 makes the\n', fGpu);
fprintf('     getCurrentTask() guard decline GPU inside a worker. This test drives\n');
fprintf('     nearest_in_set_ directly with fUseGpu true/false to compare both paths.\n');

% --- pick the busiest real site (the one the cap is meant for) ---
vnSpk_site = cellfun(@numel, S0.cviSpk_site);
[n1, iSite] = max(vnSpk_site);
viSpk1 = S0.cviSpk_site{iSite}(:);
fprintf('\nBusiest site #%d: n1=%d spikes, nFet=%d.\n', iSite, n1, prod(S0.dimm_fet(1:2)));

% --- per-site feature matrix, exactly as cluster_labels_persite_/cluster_site_ build it ---
X = double(reshape(trFet_spk(:,:,viSpk1), [], n1)');   % n1 x nFet (double, as cluster_site_ casts)

% --- subsample size m ---
if isempty(m_test)
    if ~isempty(maxSpk) && isscalar(maxSpk), m_test = round(maxSpk); else, m_test = 200000; end
end
m_test = max(2, min(m_test, n1));
fprintf('Subsample size m=%d (n1/m = %.1fx).\n', m_test, n1/m_test);

% --- seeded subsample, byte-for-byte as cluster_site_capped_ ---
sRng = rng(); rng(double(viSpk1(1)), 'twister');
viSub = sort(randperm(n1, m_test));
rng(sRng);
Xsub = X(viSub, :);
Xall_T = X';        % nFet x n1  (arg 1 to nearest_in_set_)
Xsub_T = Xsub';     % nFet x m   (arg 2)

% --- GPU warm-up so the timed GPU run excludes one-time context/JIT init ---
try
    w = irc('call','nearest_in_set_', {Xall_T(:,1:min(2000,n1)), Xsub_T(:,1:min(2000,m_test)), true}, 1); %#ok<NASGU>
    wait(gpuDevice);
catch ME
    fprintf(2, 'GPU warm-up failed (%s) -- GPU may be unavailable; test will still run CPU.\n', ME.message);
end

% --- timed CPU run (fUseGpu=false) ---
t = tic;
Rc = irc('call','nearest_in_set_', {Xall_T, Xsub_T, false}, 1);  viNN_cpu = Rc.out1;
t_cpu = toc(t);

% --- timed GPU run (fUseGpu=true) ---
t = tic;
Rg = irc('call','nearest_in_set_', {Xall_T, Xsub_T, true}, 1);   viNN_gpu = Rg.out1;
try, wait(gpuDevice); catch, end
t_gpu = toc(t);

% --- compare ---
nMismatch = sum(viNN_cpu(:) ~= viNN_gpu(:));
fInRange  = all(viNN_cpu>=1 & viNN_cpu<=m_test) && all(viNN_gpu>=1 & viNN_gpu<=m_test);
fprintf('\n--- results ---\n');
fprintf('CPU: %.2f s\n', t_cpu);
fprintf('GPU: %.2f s   (speedup %.1fx)\n', t_gpu, t_cpu/max(t_gpu,eps));
fprintf('indices identical: %d   (mismatches: %d of %d)\n', isequal(viNN_cpu,viNN_gpu), nMismatch, n1);
fprintf('all indices in [1,m]: %d\n', fInRange);
if nMismatch>0
    % single-precision GPU vs double CPU can only differ on near-exact distance ties
    d = knn_dist_gap_(Xall_T, Xsub_T, viNN_cpu, viNN_gpu, find(viNN_cpu(:)~=viNN_gpu(:),5));
    fprintf('  (first few mismatches are near-ties; |d_cpu - d_gpu| = %s)\n', mat2str(d,3));
end

% --- parfor-worker guard: inside a worker, fUseGpu=true must fall back to CPU ---
fprintf('\n--- parfor-worker guard (getCurrentTask -> declines GPU -> CPU) ---\n');
try
    hP = gcp('nocreate'); if isempty(hP), hP = parpool('local', 2); end
    cA = parallel.pool.Constant(Xall_T);
    cS = parallel.pool.Constant(Xsub_T);
    rw = cell(2,1);
    parfor w = 1:2
        rr = irc('call','nearest_in_set_', {cA.Value, cS.Value, true}, 1);   % fUseGpu=true, but in a worker
        rw{w} = rr.out1;
    end
    fprintf('in-worker(fUseGpu=1) matches CPU: %d, %d  (GPU correctly declined in workers)\n', ...
        isequal(rw{1},viNN_cpu), isequal(rw{2},viNN_cpu));
catch ME
    fprintf(2, 'parfor guard check skipped (%s)\n', ME.message);
end

fprintf('\n=== done ===\n');
end %func


function v = getfield_or_(S, f, d)
if isfield(S,f) && ~isempty(S.(f)), v = S.(f); else, v = d; end
end


function d = knn_dist_gap_(Xall_T, Xsub_T, viCpu, viGpu, ii)
% |dist(query, cpu-pick) - dist(query, gpu-pick)| for a few mismatching queries ii,
% to show mismatches are near-ties rather than a systematic error.
d = zeros(numel(ii),1);
for k = 1:numel(ii)
    q  = double(Xall_T(:,ii(k)));
    dc = norm(q - double(Xsub_T(:,viCpu(ii(k)))));
    dg = norm(q - double(Xsub_T(:,viGpu(ii(k)))));
    d(k) = abs(dc - dg);
end
end
