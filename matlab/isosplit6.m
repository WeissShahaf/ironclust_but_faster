function labels = isosplit6(X, opts)
% ISOSPLIT6  Run the official ISO-SPLIT v6 (github.com/magland/isosplit6) through
% MATLAB's Python bridge, returning cluster labels for the columns of X.
%
%   Inputs:
%     X    : (M dims x N samples) data matrix.
%     opts : struct (currently unused by the v6 backend; accepted for signature
%            compatibility with isosplit5).
%   Output:
%     labels : 1 x N integer cluster labels (1..K).
%
%   Requirements: the isosplit6 Python package must be importable from the Python
%   interpreter configured for MATLAB:
%       >> pyenv                          % check / configure interpreter
%       $  pip install isosplit6 numpy    % in that interpreter
%
%   If the package (or a usable Python environment) is not available, this throws
%   an error. Callers (see cluster_isosplit_ in irc.m) catch it and fall back to
%   the pure-MATLAB isosplit5.m, matching the requested "try v6, else v5" behavior.

if nargin<2, opts = struct(); end %#ok<INUSD>

try
    np  = py.importlib.import_module('numpy');
    mod = py.importlib.import_module('isosplit6');
catch ME
    error('isosplit6:unavailable', ...
        ['isosplit6 not available via MATLAB Python ', ...
         '(configure pyenv and `pip install isosplit6`): %s'], ME.message);
end

% isosplit6 expects an (n_samples x n_features) array.
Xs  = double(X');
Xpy = np.array(Xs);
labels_py = mod.isosplit6(Xpy);

labels = double(labels_py);
labels = labels(:)';
if isempty(labels) || any(~isfinite(labels))
    error('isosplit6:badOutput', 'isosplit6 returned no/invalid labels.');
end
end %func
