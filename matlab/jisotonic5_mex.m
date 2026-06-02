function [B, MSEs] = jisotonic5_mex(A, weights)
% JISOTONIC5_MEX  Pure-MATLAB drop-in for the (missing) jisotonic5_mex MEX.
%   [B, MSEs] = jisotonic5_mex(A, weights)
%
%   Weighted isotonic (non-decreasing) regression via the Pool Adjacent
%   Violators Algorithm (PAVA). This reproduces the interface that
%   jisotonic5.m expects from its compiled MEX:
%       A       : input row vector
%       weights : per-sample weights (defaults to ones)
%       B       : best non-decreasing fit to A (same size as A)
%       MSEs(j) : weighted within-block sum of squared error of the isotonic
%                 fit to A(1:j); used by jisotonic5 'updown'/'downup' and by
%                 isocut5 to locate the optimal split.
%
%   Notes
%   -----
%   * The original repository ships jisotonic5.m but not jisotonic5_mex.cpp,
%     so isocut5/isosplit5/jisotonic5 fail at runtime. This file restores them
%     without any compilation step. A real jisotonic5_mex.mex* (if added later)
%     takes precedence over this .m file, so there is no conflict.
%   * The implementation mirrors the (commented-out) reference PAVA inside
%     jisotonic5.m. Author of the algorithm: J. Magland.

if nargin < 1
    % match jisotonic5_mex(1,1) probe used by jisotonic5.m
    B = 1; MSEs = 0; return;
end
if nargin < 2 || isempty(weights)
    weights = ones(size(A));
end

A = A(:)';
weights = weights(:)';
N = numel(A);

B = zeros(1, N);
MSEs = zeros(1, N);
if N == 0, return; end

% Per-block sufficient statistics (PAVA stack), 1..lastind active blocks.
ucount = zeros(1, N);   % number of original samples in block
wsum   = zeros(1, N);   % sum of weights
ssum   = zeros(1, N);   % sum of weight*value
sqsum  = zeros(1, N);   % sum of weight*value^2

ucount(1) = 1;
wsum(1)   = weights(1);
ssum(1)   = A(1) * weights(1);
sqsum(1)  = A(1)^2 * weights(1);
lastind   = 1;
MSEs(1)   = 0;

for j = 2:N
    lastind = lastind + 1;
    ucount(lastind) = 1;
    wsum(lastind)   = weights(j);
    ssum(lastind)   = A(j) * weights(j);
    sqsum(lastind)  = A(j)^2 * weights(j);
    MSEs(j) = MSEs(j-1);

    % pool adjacent violators
    while lastind > 1
        c1 = wsum(lastind-1); s1 = ssum(lastind-1); q1 = sqsum(lastind-1);
        c2 = wsum(lastind);   s2 = ssum(lastind);   q2 = sqsum(lastind);
        if (s1/c1) < (s2/c2)
            break;   % already isotonic
        end
        prevMSE = (q1 - s1^2/c1) + (q2 - s2^2/c2);
        % merge block (lastind) into block (lastind-1)
        ucount(lastind-1) = ucount(lastind-1) + ucount(lastind);
        wsum(lastind-1)   = c1 + c2;
        ssum(lastind-1)   = s1 + s2;
        sqsum(lastind-1)  = q1 + q2;
        newMSE = sqsum(lastind-1) - ssum(lastind-1)^2 / wsum(lastind-1);
        MSEs(j) = MSEs(j) + newMSE - prevMSE;
        lastind = lastind - 1;
    end
end

% expand block means back to per-sample fit
ii = 1;
for k = 1:lastind
    val = ssum(k) / wsum(k);
    uc  = ucount(k);
    B(ii:ii+uc-1) = val;
    ii = ii + uc;
end
end
