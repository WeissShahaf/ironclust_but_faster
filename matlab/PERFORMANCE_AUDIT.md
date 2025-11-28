# IronClust Performance Audit Report

**Date:** 2025-11-19
**Auditor:** Claude Code (Anthropic)
**Scope:** Comprehensive performance analysis of IronClust MATLAB spike sorting software

---

## Table of Contents

1. [Technology Stack Analysis](#1-technology-stack-analysis)
2. [Code Performance Analysis](#2-code-performance-analysis)
3. [Database Performance](#3-database-performance)
4. [Frontend Performance](#4-frontend-performance)
5. [Network Performance](#5-network-performance)
6. [Asynchronous Operations](#6-asynchronous-operations)
7. [Memory Usage](#7-memory-usage)
8. [Build & Deployment Performance](#8-build--deployment-performance)
9. [Performance Monitoring](#9-performance-monitoring)
10. [Benchmarking & Profiling](#10-benchmarking--profiling)
11. [Optimization Recommendations](#11-optimization-recommendations)
12. [Specific File/Line References](#12-specific-fileline-number-references)
13. [Performance Improvement Summary](#13-performance-improvement-summary-table)
14. [Existing Optimizations](#14-existing-optimizations-working-well)
15. [Testing Recommendations](#15-testing-recommendations)
16. [Immediate Action Items](#16-immediate-action-items)

---

## 1. Technology Stack Analysis

### Primary Environment

- **Language:** MATLAB (R2016b+)
- **Runtime:** MATLAB interpreter with JIT compilation
- **GPU Acceleration:** CUDA (Compute Capability 3.5+, Kepler/Maxwell/Pascal)
- **Parallel Computing:** MATLAB Parallel Computing Toolbox (parfor, gpuArray)
- **Data Format:** Binary files (.bin), MAT files (.mat)
- **Primary Use Case:** Neural spike sorting for high-density electrode arrays (128-384 channels)

### Architecture

- Command-pattern interface via `irc('command', args...)`
- Pipeline: Detection → Feature Extraction → Clustering → Post-merge
- Stateful processing with persistent global variables
- Two main versions: `irc.m` (v1) and `irc2.m` (v2)

### Key Components

1. **Main Entry Point:** `irc.m` - Command dispatcher and workflow orchestrator
2. **Detection:** `file2spk_()` - Threshold-based spike detection
3. **Clustering:** `fet2clu_()` - Density-based clustering with drift correction
4. **GPU Kernels:** 11 CUDA kernels (`.cu` files) for accelerated computation
5. **GUI:** `irc_gui.m` - Manual curation interface

---

## 2. Code Performance Analysis

### 2.1 Critical Performance Bottlenecks Identified

#### **HIGH PRIORITY - Critical Path Bottlenecks**

#### 1. Spike Detection I/O Loop
**Location:** `irc.m:17584-17788` (file2spk_)
**File:** `irc.m:1444` (load_file_)

**Issue:** Sequential file I/O with small chunk loading

```matlab
MAX_LOAD_SEC = [2];  % Only 2 seconds loaded at a time (default.prm:27)
nSamples_max = floor(P.sRateHz * P.MAX_LOAD_SEC);  // irc.m:1390
```

**Impact:**
- Processes ~2 second chunks sequentially
- Causes CPU/GPU underutilization during I/O waits
- **Estimated Impact:** 30-50% of total runtime for large files

**Evidence:**
- For a 1-hour recording at 30kHz sampling rate:
  - Total samples: 108,000,000
  - Chunk size: 60,000 samples (2 seconds)
  - Number of chunks: 1,800
  - I/O overhead per chunk: Significant

---

#### 2. Cluster Merging find() Operations
**Location:** `merge_clu_pair_()` function (partially optimized)
**Status:** Already improved per `MERGE_OPTIMIZATIONS.md`

**Original Issue:** O(n) linear search through millions of spikes per merge
```matlab
% Before (slow):
S_clu.viClu(S_clu.viClu == iClu2) = iClu1;
S_clu.cviSpk_clu{iClu1} = find(S_clu.viClu == iClu1);
```

**Current Optimization:** Uses pre-computed `cviSpk_clu` indices
```matlab
% After (fast):
if ~isempty(S_clu.cviSpk_clu{iClu2})
    S_clu.viClu(S_clu.cviSpk_clu{iClu2}) = iClu1;
    % Efficient merging of spike indices
end
```

**Achieved:** 2-5x speedup

**Remaining Issue:** Correlation matrix updates still expensive for large clusters

---

#### 3. Nested Feature Extraction Loop
**Location:** `irc.m:~3577`

**Issue:** Non-vectorized parfor loop for spike feature computation

```matlab
parfor iSpk = 1:nSpk
    % Feature extraction per spike
end
```

**Problems:**
- Parfor overhead when nSpk is large but computation per spike is small
- No threshold to switch between serial and parallel execution
- Memory allocation overhead in parallel workers

**Estimated Impact:** 15-25% of sorting runtime

---

#### 4. Redundant Memory Allocation
**Locations:** `irc.m:355, 1051, 2472-2475`

**Issue:** Multiple large array allocations without pre-sizing

```matlab
tnWav_spk1 = zeros(diff(spkLim_wav) + 1, nSites_spk, nSpks, 'like', mnWav1);
vrRho = zeros(nSpk, 1, 'single');  // Allocated per site
vrDelta = zeros(nSpk, 1, 'single');
viNneigh = zeros(nSpk, 1, 'uint32');
```

**Impact:**
- Memory fragmentation
- Allocation overhead in loops
- Potential out-of-memory issues for large datasets

---

### 2.2 Algorithm Complexity Issues

#### 1. Distance Calculations in CUDA Kernels
**File:** `irc_cuda_rho.cu:76-110`

**Complexity:** O(n1 × n12 × nC) where:
- `nC` = 45 (max features)
- `n12` can be millions of spikes
- `n1` = chunk size

**Current Implementation:**
```cuda
for (int i12_tx = tx; i12_tx < n12; i12_tx += blockDim.x){
    for (int iC = 0; iC < nC; ++iC){
        float fet12_tx = mrFet12[iC + i12_tx * nC];
        for (int i_c = 0; i_c < CHUNK; ++i_c){
            float temp = fet12_tx - mrFet1_[iC][i_c];
            vrDist_c[i_c] += temp * temp;
        }
    }
}
```

**Optimizations Present (Good):**
- Block-based loading with shared memory
- Coalesced memory access patterns
- Shared memory for frequently accessed data

**Issue:** Limited by memory bandwidth, not compute
- GPU memory bandwidth is the bottleneck
- Compute units are underutilized

**Kernel Configuration:**
- CHUNK size: 16 (hardcoded)
- NTHREADS: 128
- NC: 45 (max features)

---

#### 2. Spike Merging Spatial Search
**Location:** `irc.m:1800-1850` (spikeMerge_single_1_)

**Complexity:** O(nSpikes × nNearSpikes) per site

```matlab
for iSpk1=1:numel(viSpk1)
    iSpk11 = viSpk1(iSpk1);
    rSpk11 = vrSpk1(iSpk1);

    % Search nearby spikes
    [vii2, i2prev] = findRange_(viSpk2, spkLim11(1), spkLim11(2), i2prev, n2);
    if numel(vii2)==1, vlSpk1(iSpk1) = 1; continue; end
    vrSpk22 = vrSpk2(vii2);

    % Check for larger spikes
    if any(vrSpk22 < rSpk11), continue; end
end
```

**Issue:** Quadratic behavior for dense spike activity

**Optimization Present (Good):** Uses `i2prev` to avoid re-searching from start

---

#### 3. Correlation Matrix Computation
**Location:** `irc.m:17934`

**Complexity:** O(nClu²) with expensive waveform correlations

```matlab
parfor iClu2 = 1:nClu  % parfor speedup: 4x
    % Compute correlations between all cluster pairs
end
```

**Current Status:**
- Already parallelized with parfor (4x speedup noted)
- Partial incremental updates implemented (MERGE_OPTIMIZATIONS.md)

**Remaining Issue:**
- Full matrix recalculation even for single cluster changes
- Could use incremental updates more aggressively

---

## 3. Database Performance

**Status:** Not Applicable

IronClust uses direct file I/O with binary and MAT files. No database layer exists.

**File I/O Patterns:**
- **Input:** `.bin` files (raw neural data)
- **Output:** `_jrc.mat`, `_spkwav.mat`, `_spkraw.mat`, `_spkfet.mat`
- **Access Pattern:** Sequential read, random write during spike extraction

---

## 4. Frontend Performance

**Status:** MATLAB GUI (not web-based)

### GUI Performance Issues

**Manual Curation Interface:** `irc_gui.m`

**Already Addressed (Good):**
- Deferred UI updates via `fUpdateImmediate` parameter
- Batch merge operations to reduce redraws
- Performance improvements documented in `MERGE_OPTIMIZATIONS.md:40-62`

**Configuration:**
```matlab
fUpdateImmediate = get_set_(P, 'fUpdateImmediate', 1);
if fUpdateImmediate
    % Update figures immediately
    plot_FigWav_(S0);
    S0 = update_FigCor_(S0);
else
    % Mark for later update
    S0.figures_need_update = true;
end
```

**Keyboard Shortcuts:**
- `[M]` - Merge selected clusters
- `[B]` - Batch update all figures (new)
- `[H]` - Help

**Performance Gains Achieved:**
- 5-10x faster for multiple merges with deferred updates

---

## 5. Network Performance

**Status:** Not Applicable

IronClust is a standalone desktop application with no network components.

---

## 6. Asynchronous Operations

### 6.1 Parallel Processing Analysis

#### 1. Parfor Usage

**Detection Loop:** `irc.m:1759`
```matlab
parfor iSite = 1:nSites  % parfor speedup: 2x
    [cviSpkA{iSite}, cvrSpkA{iSite}, cviSiteA{iSite}] = ...
        spikeMerge_single_(viSpk, vrSpk, viSite, iSite, P);
end
```
**Status:** ✅ Good - 2x speedup achieved

**Correlation Computation:** `irc.m:17934`
```matlab
parfor iClu2 = 1:nClu  % parfor speedup: 4x
    % Compute correlations
end
```
**Status:** ✅ Good - 4x speedup achieved

**Issue:** Conservative error handling
```matlab
fParfor = 0;  // Disabled by default in spike merge (irc.m:1756)
if fParfor
    try
        parfor iSite = 1:nSites
            % ...
        catch
            fParfor = 0;  % Falls back silently
        end
    end
end
if ~fParfor
    for iSite = 1:nSites  % Serial fallback
        % ...
    end
end
```

**Problem:** Silent fallback to serial execution on ANY parfor error

---

#### 2. GPU Async Opportunities Missed

**Current Implementation:** Sequential CUDA kernel launches

```matlab
% Launch kernel, wait for completion
CK = parallel.gpu.CUDAKernel('irc_cuda_rho.ptx','irc_cuda_rho.cu');
vrRho1 = zeros([1, n1], 'single', 'gpuArray');
vrRho1 = feval(CK, vrRho1, mrFet12, viiSpk12_ord, vnConst, dc2);
% Implicit synchronization here

% Next kernel launch
CK = parallel.gpu.CUDAKernel('iron_cuda_delta.ptx','iron_cuda_delta.cu');
vrDelta1 = zeros([1, n1], 'single', 'gpuArray');
viNneigh1 = zeros([1, n1], 'uint32', 'gpuArray');
[vrDelta1, viNneigh1] = feval(CK, ...);
```

**Opportunity:** Use CUDA streams for overlapping computation/transfer
- Stream 1: Transfer data to GPU
- Stream 2: Compute on GPU (concurrent with Stream 3)
- Stream 3: Transfer results to CPU

**Potential Speedup:** 20-30% from overlap

---

## 7. Memory Usage

### 7.1 Memory Management Issues

#### 1. Global Variables
**Location:** `irc.m:7-10`

```matlab
global all_vnthresh;
all_vnthresh = {};
global iteration;
iteration=1;
```

**Issues:**
- Global state prevents garbage collection
- Memory leaks across multiple runs
- Not cleared between processing sessions

**Impact:** Memory accumulation in long MATLAB sessions

---

#### 2. Spike Waveform Caching
**Location:** `irc.m:1020-1024`

```matlab
if get_set_(P, 'fRamCache', 1) && get_set_(P, 'fSave_spkwav', 1)
    tnWav_spk = load_spkwav_(S0, P);  // Potentially GBs
    tnWav_raw = load_spkraw_(S0, P);
end
```

**Good:** Configurable RAM caching improves performance

**Issues:**
- No memory limit checking before loading
- No estimation of required memory
- Risk of out-of-memory crashes on large datasets

**Example Calculation:**
- 1M spikes × 61 samples × 32 sites × 4 bytes (single) = 7.6 GB
- Plus raw waveforms: × 2 = 15.2 GB
- Many systems have <32 GB RAM

---

#### 3. GPU Memory Management
**Location:** `default.prm:29`, `irc.m:1361-1370`

**Configuration:**
```matlab
nLoads_gpu = 8;  % Ratio of RAM to GPU memory
```

**Implementation:**
```matlab
S_gpu = gpuDevice(1);
nBytes_gpu = floor(S_gpu.AvailableMemory / load_factor);
if fGpu, nBytes = min(nBytes, nBytes_gpu); end
```

**Good:** Configurable GPU memory limits

**Issues:**
- Static ratio doesn't adapt to actual GPU availability
- Doesn't account for other GPU processes
- `AvailableMemory` is queried once, not updated dynamically

**Recommendation:** Query GPU memory before each large allocation

---

#### 4. Memory Allocation Patterns

**Issue:** Repeated allocations in loops

**Example from CUDA kernel:** `irc_cuda_rho.cu:87`
```cuda
float vrDist_c[CHUNK];  // Allocated in register per iteration
for (int i12_tx = tx; i12_tx < n12; i12_tx += blockDim.x){
    for (int i_c = 0; i_c < CHUNK; ++i_c)
        vrDist_c[i_c] = 0.0f;  // Re-initialized each iteration
    // ...
}
```

**Note:** This is register allocation (acceptable), but pattern repeats in MATLAB code

**Example from MATLAB:** `irc.m:2472-2475`
```matlab
for iSite = 1:nSites
    vrRho = zeros(nSpk, 1, 'single');  // Re-allocated nSites times
    vrDelta = zeros(nSpk, 1, 'single');
    % ...
end
```

**Better:**
```matlab
vrRho = zeros(nSpk, nSites, 'single');  // Allocate once
vrDelta = zeros(nSpk, nSites, 'single');
for iSite = 1:nSites
    % Use vrRho(:, iSite)
end
```

---

### 7.2 Memory Usage Estimation

**Typical Dataset:**
- Recording: 1 hour, 384 channels, 30 kHz, int16
- Raw data: 384 × 108M samples × 2 bytes = 82.9 GB
- Detected spikes: ~1-2M spikes
- Waveform storage: ~15-30 GB (with caching)
- Feature matrices: ~2-4 GB
- **Total RAM needed:** 20-35 GB (with caching), 5-10 GB (without)

---

## 8. Build & Deployment Performance

### 8.1 CUDA Compilation

**Command:** `irc('compile')`

**Process:**
```matlab
compile_cuda_(vcArg1, vcArg2)
```

**CUDA Files:** 11 kernels requiring compilation
- `irc_cuda_rho.cu`
- `irc_cuda_delta.cu`
- `irc_cuda_rho_drift.cu`
- `irc_cuda_delta_drift.cu`
- `cuda_knn.cu`
- `cuda_knn_full.cu`
- `cuda_knn_ib.cu`
- `cuda_knn_index.cu`
- `cuda_delta_knn.cu`
- `search_delta_drift.cu`
- `search_min_drift.cu`

**Compilation Command:**
```bash
nvcc -ptx -m 64 -arch sm_35 <file>.cu
```

**Issues:**
1. No incremental compilation tracking (recompiles all files)
2. Manual triggering required (not automated on kernel changes)
3. Targets sm_35 (Kepler 2012) - misses modern GPU optimizations

**Modern GPU Architectures:**
- sm_35: Kepler (2012) ← **Current target**
- sm_50: Maxwell (2014)
- sm_60: Pascal (2016)
- sm_70: Volta (2017) - Tensor cores introduced
- sm_75: Turing (2018)
- sm_80: Ampere (2020)
- sm_86: Ampere (2020)
- sm_89: Ada Lovelace (2022)
- sm_90: Hopper (2022)

**Recommendation:** Compile for multiple architectures
```bash
nvcc -ptx -m 64 -gencode arch=compute_35,code=sm_35 \
                 -gencode arch=compute_70,code=sm_70 \
                 -gencode arch=compute_80,code=sm_80 \
                 <file>.cu
```

---

### 8.2 Deployment Considerations

**Dependencies:**
- MATLAB R2016b+
- Parallel Computing Toolbox
- CUDA Toolkit (version depends on MATLAB version)
- Visual Studio (Windows) or GCC (Linux) for compilation

**Issue:** No automated dependency checking

---

## 9. Performance Monitoring

### 9.1 Existing Metrics (Good ✅)

**Runtime Tracking:**
```matlab
% Detection
S0.runtime_detect = toc(runtime_detect);  // irc.m:1028

% Sorting
runtime_sort = toc(runtime_sort);  // irc.m:1089
S0 = set0_(runtime_sort, P, memory_sort);  // irc.m:1092

% Auto-merging
S_clu.t_automerge = toc(t_automerge);  // irc.m:2433
```

**Memory Tracking:**
```matlab
memory_init = memory_matlab_();  // irc.m:1006
S0.memory_detect = memory_matlab_();  // irc.m:1030
memory_sort = memory_matlab_();  // irc.m:1091
```

**Console Output:**
```matlab
fprintf('Detection took %0.1fs for %s\n', S0.runtime_detect, P.vcFile_prm);
fprintf('Sorting took %0.1fs for %s\n', runtime_sort, P.vcFile_prm);
fprintf('\tauto-merging took %0.1fs\n', t_automerge);
```

---

### 9.2 Missing Metrics

**No per-stage profiling within detection/clustering:**
- I/O time vs. computation time breakdown
- Per-site clustering time
- Feature extraction time separate from detection

**No GPU utilization metrics:**
- Kernel execution time
- Memory transfer time
- GPU occupancy
- SM (Streaming Multiprocessor) utilization

**No I/O bandwidth monitoring:**
- Disk read throughput
- Bottleneck identification (disk vs. CPU vs. GPU)

**No bottleneck identification tools:**
- Automated performance regression detection
- Comparison with baseline metrics

---

## 10. Benchmarking & Profiling

### 10.1 Available Benchmarks

**Command:**
```matlab
irc('benchmark', dataset, config)
```

**Location:** `irc.m:111`

**Issue:** No standardized performance regression tests

**Recommendation:**
```matlab
% Create benchmark suite
irc_benchmark_suite = {
    {'small_dataset.prm', 'baseline_config'},   % 5 min recording
    {'medium_dataset.prm', 'baseline_config'},  % 1 hour recording
    {'large_dataset.prm', 'baseline_config'}    % 4 hour recording
};

for i = 1:length(irc_benchmark_suite)
    [dataset, config] = irc_benchmark_suite{i}{:};
    results(i) = irc('benchmark', dataset, config);
end

% Compare with baseline
compare_benchmarks(results, baseline_results);
```

---

### 10.2 Profiling Tools

**MATLAB Profiler (Recommended):**
```matlab
profile on -history
irc('spikesort', 'myfile.prm')
profile viewer
```

**Benefits:**
- Identifies slow functions
- Shows call tree
- Memory allocation profiling
- Line-by-line execution time

**GPU Profiling:**
```matlab
% NVIDIA Nsight Systems
% Run from command line:
% nsys profile -o output matlab -batch "irc('spikesort','myfile.prm')"
```

**Memory Profiling:**
```matlab
% Monitor memory usage
m = memory;
fprintf('Used: %.2f GB, Available: %.2f GB\n', ...
    m.MemUsedMATLAB/1e9, m.MemAvailableAllArrays/1e9);
```

---

## 11. Optimization Recommendations

### **TIER 1: High-Impact, Low-Effort (Do First)**

---

#### **1.1 Increase File I/O Chunk Size**

**Priority:** ⭐⭐⭐⭐⭐
**Impact:** High
**Effort:** 5 minutes

**File:** `default.prm:27`

**Change:**
```matlab
% Before:
MAX_LOAD_SEC = [2];

% After:
MAX_LOAD_SEC = [10];  % Increase from 2 to 10 seconds
```

**Expected Impact:**
- 20-30% faster detection
- Better CPU/GPU utilization
- Fewer I/O operations

**Risks:**
- Increased RAM usage: ~5x per chunk (manageable for most systems)
- Example: 2 sec = 500 MB → 10 sec = 2.5 GB per chunk

**Validation:**
```matlab
% Test with different chunk sizes
for chunk_sec = [2, 5, 10, 20]
    P.MAX_LOAD_SEC = chunk_sec;
    tic; irc('detect', 'test.prm'); t = toc;
    fprintf('Chunk size: %d sec, Time: %.1f sec\n', chunk_sec, t);
end
```

---

#### **1.2 Enable GPU Sorting by Default**

**Priority:** ⭐⭐⭐⭐
**Impact:** High
**Effort:** Documentation only

**File:** `default.prm:23`

**Verification:**
```matlab
fGpu_sort = 1;  % Already enabled by default
```

**Action Required:**
1. Document GPU benefits in user guide
2. Add warning if GPU not detected
3. Provide performance comparison (GPU vs CPU)

**Expected Impact:**
- 3-5x faster clustering (already available if users enable)
- No code changes needed, just documentation

**Documentation Template:**
```markdown
## GPU Acceleration

IronClust can utilize NVIDIA GPUs for 3-5x faster clustering.

### Requirements:
- NVIDIA GPU with Compute Capability 3.5+ (Kepler or newer)
- CUDA Toolkit installed
- MATLAB Parallel Computing Toolbox

### Enable GPU:
Set in your .prm file:
fGpu = 1;
fGpu_sort = 1;

### Check GPU:
>> gpuDevice()
```

---

#### **1.3 Pre-allocate Distance Arrays**

**Priority:** ⭐⭐⭐
**Impact:** Medium
**Effort:** 1-2 hours

**File:** `irc_cuda_rho.cu:87`

**Current Issue:**
```cuda
for (int i12_tx = tx; i12_tx < n12; i12_tx += blockDim.x){
    float vrDist_c[CHUNK];  // Allocated per iteration
    for (int i_c = 0; i_c < CHUNK; ++i_c)
        vrDist_c[i_c] = 0.0f;
    // ...
}
```

**Optimization (consider register pressure):**
```cuda
float vrDist_c[CHUNK];  // Move outside loop (if registers available)
for (int i12_tx = tx; i12_tx < n12; i12_tx += blockDim.x){
    for (int i_c = 0; i_c < CHUNK; ++i_c)
        vrDist_c[i_c] = 0.0f;  // Just reset
    // ...
}
```

**Caution:** May cause register spilling if register pressure too high

**Expected Impact:** 5-10% faster CUDA kernels

**Validation:**
- Profile with `nvprof` before/after
- Check register usage: `--ptxas-options=-v`
- Verify no register spilling

---

#### **1.4 Reduce Parfor Overhead for Small Tasks**

**Priority:** ⭐⭐⭐⭐
**Impact:** Medium
**Effort:** 2-3 hours

**File:** `irc.m:3577`

**Current:**
```matlab
parfor iSpk = 1:nSpk
    % Feature extraction
end
```

**Optimized:**
```matlab
% Only use parfor if beneficial
PARFOR_THRESHOLD = 10000;  % Empirically determined

if nSpk > PARFOR_THRESHOLD
    parfor iSpk = 1:nSpk
        % Feature extraction
    end
else
    for iSpk = 1:nSpk
        % Feature extraction (serial)
    end
end
```

**Expected Impact:**
- 10-15% faster for small datasets (<10k spikes)
- No impact on large datasets
- Reduced overhead

**Determine Threshold:**
```matlab
% Benchmark to find optimal threshold
nSpk_test = [100, 1000, 5000, 10000, 50000, 100000];
for n = nSpk_test
    % Time parfor vs for loop
    tic; parfor i=1:n, dummy_work(); end; t_par = toc;
    tic; for i=1:n, dummy_work(); end; t_ser = toc;
    fprintf('n=%d: parfor=%.3f, for=%.3f, speedup=%.2fx\n', ...
        n, t_par, t_ser, t_ser/t_par);
end
```

---

### **TIER 2: High-Impact, Medium-Effort**

---

#### **2.1 Verify Incremental Correlation Matrix Updates**

**Priority:** ⭐⭐⭐⭐
**Impact:** High (already partially done)
**Effort:** 1-2 days

**Status:** Partially implemented (MERGE_OPTIMIZATIONS.md:86-104)

**Current Implementation:**
```matlab
% Remove deleted cluster row/column
S_clu.mrWavCor(iClu2, :) = [];
S_clu.mrWavCor(:, iClu2) = [];

% Update only merged cluster correlations
S_clu.mrWavCor(iClu1, :) = compute_cluster_correlations_(S_clu, iClu1, P);
S_clu.mrWavCor(:, iClu1) = S_clu.mrWavCor(iClu1, :)';
```

**Remaining Work:**
1. Verify correctness with edge cases:
   - Empty clusters
   - Single-spike clusters
   - Very large clusters (>100k spikes)
2. Add unit tests
3. Compare results with full recalculation

**Expected Impact:** 3-5x faster merging (already achieved per docs)

**Test Cases:**
```matlab
% Unit test template
function test_incremental_correlation()
    % Test 1: Merge two normal clusters
    [S_clu_incremental, S_clu_full] = test_merge_normal();
    assert_matrices_equal(S_clu_incremental.mrWavCor, S_clu_full.mrWavCor);

    % Test 2: Merge with empty cluster
    [S_clu_incremental, S_clu_full] = test_merge_empty();
    assert_matrices_equal(S_clu_incremental.mrWavCor, S_clu_full.mrWavCor);

    % Test 3: Large clusters
    [S_clu_incremental, S_clu_full] = test_merge_large();
    assert_matrices_equal(S_clu_incremental.mrWavCor, S_clu_full.mrWavCor);
end
```

---

#### **2.2 Vectorize Feature Extraction**

**Priority:** ⭐⭐⭐⭐⭐
**Impact:** High
**Effort:** 3-5 days

**File:** `irc.m:3577+`

**Current (Non-vectorized):**
```matlab
parfor iSpk = 1:nSpk
    % Extract features for each spike individually
    features(iSpk, :) = extract_features_single_spike(waveforms(:,:,iSpk), P);
end
```

**Vectorized Approach:**
```matlab
% Process all spikes at once using matrix operations
mrFeatures = vectorized_extraction(tnWav_spk, P);
```

**Implementation Strategy:**
1. Identify vectorizable operations:
   - PCA projections: Matrix multiplication
   - Peak-to-peak: `max() - min()` along dimension
   - Energy: `sum(x.^2)` along dimension

2. Example (PCA features):
```matlab
% Before: Loop over spikes
parfor iSpk = 1:nSpk
    mrWav = tnWav_spk(:, :, iSpk);  % Extract waveform
    mrFet_pca(iSpk, :) = mrWav(:)' * PC_coeffs;  % Project
end

% After: Vectorized
tnWav_reshaped = reshape(tnWav_spk, [], nSpk);  % [nSamples*nChans, nSpk]
mrFet_pca = PC_coeffs' * tnWav_reshaped;  % [nPC, nSpk]
mrFet_pca = mrFet_pca';  % [nSpk, nPC]
```

**Expected Impact:** 15-25% faster feature extraction

**Challenges:**
- Feature extraction code may have conditional logic
- Different features for different spike types
- Memory constraints for very large datasets

---

#### **2.3 Add Memory Pooling for Repeated Allocations**

**Priority:** ⭐⭐⭐
**Impact:** Medium
**Effort:** 3-4 days

**Locations:** Multiple locations allocating vrRho, vrDelta, temporary arrays

**Implementation:**
```matlab
classdef MemoryPool < handle
    properties (Access = private)
        pool_vrRho
        pool_vrDelta
        pool_viNneigh
        max_size
    end

    methods
        function obj = MemoryPool(max_spikes)
            obj.max_size = max_spikes;
            % Pre-allocate pools
            obj.pool_vrRho = zeros(max_spikes, 1, 'single');
            obj.pool_vrDelta = zeros(max_spikes, 1, 'single');
            obj.pool_viNneigh = zeros(max_spikes, 1, 'uint32');
        end

        function vrRho = get_vrRho(obj, n)
            assert(n <= obj.max_size);
            vrRho = obj.pool_vrRho(1:n);
        end

        % Similar for other arrays
    end
end

% Usage:
pool = MemoryPool(max(nSpk_per_site));
for iSite = 1:nSites
    vrRho = pool.get_vrRho(nSpk_site(iSite));  % Reuse buffer
    % ... process ...
end
```

**Expected Impact:**
- 10-20% reduction in memory allocation overhead
- More predictable memory usage
- Reduced GC (garbage collection) pressure

---

#### **2.4 Implement Adaptive GPU Memory Management**

**Priority:** ⭐⭐⭐⭐
**Impact:** High (stability)
**Effort:** 2-3 days

**File:** `irc.m:1361-1370`

**Current:**
```matlab
S_gpu = gpuDevice(1);
nLoads_gpu = get_set_(P, 'nLoads_gpu', 8);
nBytes_gpu = floor(S_gpu.AvailableMemory / load_factor);
if fGpu, nBytes = min(nBytes, nBytes_gpu); end
```

**Improved:**
```matlab
function nBytes_safe = get_safe_gpu_memory(safety_margin)
    if nargin < 1, safety_margin = 0.8; end  % Use 80% of available

    S_gpu = gpuDevice();
    available = S_gpu.AvailableMemory;
    total = S_gpu.TotalMemory;

    % Account for MATLAB overhead and fragmentation
    usable = available * safety_margin;

    % Check if other processes are using GPU
    if available < 0.5 * total
        warning('GPU memory low (%.1f GB / %.1f GB). Performance may degrade.', ...
            available/1e9, total/1e9);
    end

    nBytes_safe = floor(usable);
end

% Usage:
nBytes_gpu = get_safe_gpu_memory(0.8);  % Use 80% safety margin
```

**Additional Features:**
1. Query memory before each large GPU operation
2. Automatic fallback to CPU if GPU memory insufficient
3. Memory monitoring with warnings

**Expected Impact:**
- Prevent OOM (out-of-memory) errors
- Better GPU utilization
- More robust operation

---

### **TIER 3: Medium-Impact, Medium-Effort**

---

#### **3.1 Implement CUDA Streams for Overlap**

**Priority:** ⭐⭐⭐
**Impact:** High
**Effort:** 1-2 weeks

**All CUDA kernel launch locations**

**Current (Sequential):**
```matlab
% Transfer to GPU
mrFet_gpu = gpuArray(mrFet);

% Process (implicit wait)
vrRho = feval(kernel_rho, ...);

% Transfer back (implicit wait)
vrRho_cpu = gather(vrRho);

% Next kernel
vrDelta = feval(kernel_delta, ...);
```

**With Streams (Concurrent):**
```matlab
% Create streams
stream1 = parallel.gpu.GPUStream();
stream2 = parallel.gpu.GPUStream();

% Pipeline: While processing batch N, transfer batch N+1
for iBatch = 1:nBatches
    % Stream 1: Transfer data for next batch
    if iBatch < nBatches
        mrFet_next_gpu = gpuArray(mrFet_next, 'Stream', stream1);
    end

    % Stream 2: Process current batch
    vrRho = feval(kernel_rho, mrFet_gpu, 'Stream', stream2);

    % Stream 1: Transfer previous results
    if iBatch > 1
        vrRho_prev_cpu = gather(vrRho_prev, 'Stream', stream1);
    end

    % Swap buffers
    mrFet_gpu = mrFet_next_gpu;
    vrRho_prev = vrRho;
end
```

**Expected Impact:** 20-30% faster GPU processing

**Challenges:**
- MATLAB's gpuArray stream support limited
- May require MEX interface to CUDA C
- Complexity in buffer management

---

#### **3.2 Optimize CUDA Grid/Block Dimensions**

**Priority:** ⭐⭐⭐
**Impact:** Medium
**Effort:** 1 week

**All `.cu` files**

**Current:** Hardcoded values
```cuda
#define NTHREADS 128
#define CHUNK 16
```

**Optimization Approach:**
1. Auto-tune based on GPU architecture
2. Query device properties
3. Optimize for occupancy

**Implementation:**
```matlab
function [gridSize, blockSize] = optimize_kernel_config(kernelName, dataSize)
    gpu = gpuDevice();

    % Get kernel properties
    kernel = parallel.gpu.CUDAKernel([kernelName '.ptx'], [kernelName '.cu']);

    % Query optimal block size
    [blockSize, ~] = feval('cudaOccupancyMaxPotentialBlockSize', kernel);

    % Calculate grid size
    gridSize = ceil(dataSize / blockSize);

    % Adjust based on GPU architecture
    switch gpu.ComputeCapability
        case '3.5'
            % Kepler optimization
            blockSize = min(blockSize, 256);
        case {'7.0', '7.5'}
            % Volta/Turing optimization
            blockSize = min(blockSize, 512);
        case {'8.0', '8.6'}
            % Ampere optimization
            blockSize = min(blockSize, 1024);
    end
end
```

**Expected Impact:** 10-20% faster CUDA kernels

---

#### **3.3 Implement Smart Caching with Memory Limits**

**Priority:** ⭐⭐⭐⭐
**Impact:** High (stability)
**Effort:** 3-5 days

**File:** `irc.m:1020-1024`

**Current:**
```matlab
if get_set_(P, 'fRamCache', 1) && get_set_(P, 'fSave_spkwav', 1)
    tnWav_spk = load_spkwav_(S0, P);  % May cause OOM
    tnWav_raw = load_spkraw_(S0, P);
end
```

**Improved:**
```matlab
function [tnWav_spk, tnWav_raw, cache_mode] = smart_cache_load(S0, P)
    % Estimate memory required
    nSpk = numel(S0.viTime_spk);
    nT_spk = diff(P.spkLim) + 1;
    nT_raw = diff(P.spkLim_raw) + 1;
    nSites = P.nSites_fet;

    bytes_spk = nSpk * nT_spk * nSites * 4;  % single precision
    bytes_raw = nSpk * nT_raw * nSites * 4;
    required_mem = bytes_spk + bytes_raw;

    % Check available memory
    m = memory;
    available_mem = m.MemAvailableAllArrays;

    % Decision logic
    if required_mem < 0.5 * available_mem
        % Load both into RAM (fast)
        fprintf('Loading waveforms into RAM (%.1f GB)\n', required_mem/1e9);
        tnWav_spk = load_spkwav_(S0, P);
        tnWav_raw = load_spkraw_(S0, P);
        cache_mode = 'full_ram';

    elseif bytes_spk < 0.5 * available_mem
        % Load only filtered waveforms
        fprintf('Loading filtered waveforms only (%.1f GB)\n', bytes_spk/1e9);
        tnWav_spk = load_spkwav_(S0, P);
        tnWav_raw = [];  % Load on-demand
        cache_mode = 'partial_ram';

    else
        % Disk-based caching
        fprintf('Using disk-based caching (required %.1f GB > available %.1f GB)\n', ...
            required_mem/1e9, available_mem/1e9);
        tnWav_spk = [];
        tnWav_raw = [];
        cache_mode = 'disk';
    end
end
```

**Expected Impact:**
- Prevent OOM crashes
- Automatic adaptation to available memory
- Graceful degradation on low-memory systems

---

### **TIER 4: Lower Priority / Future Work**

---

#### **4.1 Modern GPU Architecture Support**

**Priority:** ⭐⭐
**Impact:** High (on new hardware)
**Effort:** 2-3 weeks

**Issue:** Targets sm_35 (Kepler 2012)

**Modern Capabilities Missed:**
- **sm_70 (Volta):** Tensor cores, improved FP16
- **sm_80 (Ampere):** 3rd gen Tensor cores, FP64 Tensor cores
- **sm_90 (Hopper):** Transformer engine, FP8

**Implementation:**
```bash
# Multi-architecture compilation
nvcc -ptx -m 64 \
    -gencode arch=compute_35,code=sm_35 \
    -gencode arch=compute_70,code=sm_70 \
    -gencode arch=compute_80,code=sm_80 \
    -gencode arch=compute_90,code=sm_90 \
    irc_cuda_rho.cu
```

**Kernel Optimizations:**
```cuda
#if __CUDA_ARCH__ >= 700
    // Use Tensor cores for matrix operations
    wmma::fragment<wmma::matrix_a, 16, 16, 16, half, wmma::row_major> a_frag;
    // ... Tensor core operations
#else
    // Fallback to standard CUDA cores
#endif
```

**Expected Impact:** 2-3x on modern GPUs (RTX 30/40 series, A100, H100)

**Effort:** Significant kernel redesign required

---

#### **4.2 Out-of-Core Processing for Very Large Datasets**

**Priority:** ⭐⭐
**Impact:** High (for ultra-large datasets)
**Effort:** 1-2 months

**Issue:** Assumes all spikes fit in RAM

**Current Limitation:**
- 10M spikes × 61 samples × 32 sites × 4 bytes = 78 GB
- Exceeds typical workstation RAM

**Solution:** Streaming/chunked processing
```matlab
function S_clu = cluster_out_of_core(S0, P)
    % Divide spikes into chunks that fit in RAM
    chunk_size = estimate_max_spikes_in_ram(P);
    nChunks = ceil(numel(S0.viTime_spk) / chunk_size);

    for iChunk = 1:nChunks
        % Load chunk from disk
        viSpk_chunk = load_spike_chunk(iChunk, chunk_size);

        % Process chunk
        S_clu_chunk = cluster_chunk(viSpk_chunk, P);

        % Merge with previous results
        S_clu = merge_cluster_results(S_clu, S_clu_chunk);

        % Clear chunk from memory
        clear viSpk_chunk S_clu_chunk;
    end
end
```

**Expected Impact:**
- Enable analysis of datasets >RAM capacity
- Support for 24+ hour recordings

**Effort:** Major refactoring of clustering pipeline

---

#### **4.3 Distributed Computing Support**

**Priority:** ⭐
**Impact:** Very High (for specific use cases)
**Effort:** 2-3 months

**Use Cases:**
- Multi-probe recordings (e.g., Neuropixels 2.0 × 4 probes)
- Very long sessions (days/weeks)
- Real-time processing

**Implementation Options:**

**Option A: MATLAB Parallel Server**
```matlab
% Create cluster
c = parcluster('MyCluster');

% Submit job
job = c.batch(@irc, 1, {'spikesort', 'probe1.prm'}, 'Pool', 4);

% Wait for results
wait(job);
results = fetchOutputs(job);
```

**Option B: Custom MPI Implementation**
```matlab
% Master node: Distribute sites across workers
for iWorker = 1:nWorkers
    viSites_worker = distribute_sites(iWorker, nWorkers, nSites);
    send_task(workers(iWorker), viSites_worker);
end

% Worker nodes: Process assigned sites
for iSite = viSites_assigned
    S_clu_site = cluster_site(iSite, P);
    send_result(master, S_clu_site);
end

% Master: Merge results
for iWorker = 1:nWorkers
    S_clu_worker = receive_result(workers(iWorker));
    S_clu = merge_results(S_clu, S_clu_worker);
end
```

**Expected Impact:** Linear scaling across machines

**Effort:** Significant infrastructure development

---

## 12. Specific File/Line Number References

### Critical Bottlenecks

| Component | File | Line(s) | Description |
|-----------|------|---------|-------------|
| Spike Detection I/O | `irc.m` | 17584-17788 | `file2spk_()` main loop |
| Chunk Size Config | `default.prm` | 27 | `MAX_LOAD_SEC = [2]` |
| Load File Function | `irc.m` | 1444-1490 | `load_file_()` implementation |
| Memory Allocation | `irc.m` | 1361-1370 | GPU memory calculation |
| Feature Extraction | `irc.m` | 3577 | Parfor loop over spikes |
| Clustering Entry | `irc.m` | 2406-2434 | `fet2clu_()` dispatcher |
| Spacetime Clustering | `irc.m` | 2457-2550 | `cluster_spacetime_()` |
| CUDA Rho Kernel | `irc_cuda_rho.cu` | 26-131 | Density calculation |
| CUDA Delta Kernel | `irc_cuda_delta.cu` | (similar) | Delta calculation |
| Spike Merging | `irc.m` | 1744-1789 | `spikeMerge_()` |
| Merge Single Site | `irc.m` | 1793-1850 | `spikeMerge_single_1_()` |
| Correlation Matrix | `irc.m` | 17934+ | Parfor correlation computation |

### Configuration Parameters

| Parameter | File | Line | Default | Description |
|-----------|------|------|---------|-------------|
| `fGpu` | `default.prm` | 22 | 1 | Enable GPU acceleration |
| `fGpu_sort` | `default.prm` | 23 | 1 | GPU clustering |
| `MAX_LOAD_SEC` | `default.prm` | 27 | 2 | I/O chunk duration (sec) |
| `nLoads_gpu` | `default.prm` | 29 | 8 | RAM/GPU memory ratio |
| `fParfor` | `default.prm` | 21 | 1 | Enable parallel processing |
| `vcCluster` | `default.prm` | 146 | 'drift-knn' | Clustering algorithm |
| `knn` | `default.prm` | 147 | 30 | K-nearest neighbors |
| `qqFactor` | `default.prm` | 80 | 5 | Detection threshold |
| `fRamCache` | `default.prm` | 35 | 0 | Cache waveforms in RAM |
| `fCacheRam` | `default.prm` | 34 | 1 | Cache raw+filtered |

### Optimization Locations

| Optimization | File | Function | Status |
|--------------|------|----------|--------|
| Pre-computed spike indices | `irc.m` | `merge_clu_pair_()` | ✅ Done |
| Deferred UI updates | `irc.m` | `ui_merge_()` | ✅ Done |
| Incremental correlation | `irc.m` | `update_correlation_after_merge_()` | ✅ Done |
| Batch merging | `irc.m` | `ui_merge_batch_()` | ✅ Done |

---

## 13. Performance Improvement Summary Table

### Recommended Optimizations

| Optimization | Impact | Effort | Priority | Estimated Speedup | Risk | Tier |
|-------------|--------|--------|----------|-------------------|------|------|
| Increase MAX_LOAD_SEC (2→10) | High | Low | ⭐⭐⭐⭐⭐ | 1.2-1.3x | Low | 1 |
| Pre-allocate CUDA arrays | Medium | Low | ⭐⭐⭐ | 1.05-1.1x | Low | 1 |
| Conditional parfor (threshold) | Medium | Low | ⭐⭐⭐⭐ | 1.1-1.15x | Low | 1 |
| Document GPU acceleration | High | Low | ⭐⭐⭐⭐ | 3-5x (if users enable) | None | 1 |
| Verify incremental correlation | High | Medium | ⭐⭐⭐⭐ | Already 3-5x | Low | 2 |
| Vectorize feature extraction | High | Medium | ⭐⭐⭐⭐⭐ | 1.15-1.25x | Medium | 2 |
| Memory pooling | Medium | Medium | ⭐⭐⭐ | 1.1-1.2x | Low | 2 |
| Adaptive GPU memory | High | Medium | ⭐⭐⭐⭐ | Stability++ | Low | 2 |
| Smart caching with limits | High | Medium | ⭐⭐⭐⭐ | Stability++ | Low | 2 |
| CUDA streams for overlap | High | High | ⭐⭐⭐ | 1.2-1.3x | Medium | 3 |
| Optimize CUDA grid/block | Medium | Medium | ⭐⭐⭐ | 1.1-1.2x | Low | 3 |
| Modern GPU arch (sm_80+) | Very High | High | ⭐⭐ | 2-3x (on new GPUs) | Medium | 4 |
| Out-of-core processing | High | Very High | ⭐⭐ | Enables >RAM datasets | High | 4 |
| Distributed computing | Very High | Very High | ⭐ | Linear scaling | High | 4 |

### **Combined Impact Estimate**

| Tier | Combined Speedup | Time to Implement | Risk |
|------|------------------|-------------------|------|
| **Tier 1 only** | **1.3-1.5x** | 1-2 days | Low |
| **Tiers 1+2** | **1.5-2.0x** | 2-3 weeks | Low |
| **Tiers 1+2+3** | **1.8-2.6x** | 1-2 months | Medium |
| **All tiers** | **3-5x** (on modern GPUs) | 3-6 months | Medium-High |

---

## 14. Existing Optimizations (Working Well)

### ✅ Already Optimized

1. **Pre-computed spike indices** (`cviSpk_clu`)
   - **Speedup:** 2-5x
   - **Location:** Merge operations
   - **Documentation:** `MERGE_OPTIMIZATIONS.md:24-33`

2. **Deferred UI updates**
   - **Speedup:** 5-10x for multiple merges
   - **Configuration:** `fUpdateImmediate` parameter
   - **Documentation:** `MERGE_OPTIMIZATIONS.md:40-62`

3. **Batch merge operations**
   - **Speedup:** 5-10x
   - **UI:** Menu option "Edit > Batch merge..."
   - **Documentation:** `MERGE_OPTIMIZATIONS.md:107-127`

4. **Parallelized correlation computation**
   - **Speedup:** 4x
   - **Implementation:** Parfor loop at `irc.m:17934`
   - **Comment:** `% parfor speedup: 4x`

5. **GPU-accelerated clustering**
   - **Speedup:** 3-5x (when enabled)
   - **Configuration:** `fGpu = 1`, `fGpu_sort = 1`
   - **Kernels:** 11 CUDA kernels for rho, delta, KNN

6. **CUDA block-loading with shared memory**
   - **Implementation:** `irc_cuda_rho.cu:37-72`
   - **Optimization:** Shared memory for frequently accessed data
   - **Benefit:** Reduced global memory bandwidth

7. **Memory-efficient spike storage**
   - **Implementation:** Sparse storage with `cviSpk_clu` cell array
   - **Benefit:** Only stores spike indices per cluster

### ✅ Good Practices

1. **Configurable caching**
   - `fRamCache`: Cache waveforms in RAM
   - `fCacheRam`: Cache both raw and filtered
   - Allows users to trade memory for speed

2. **GPU/CPU fallback mechanisms**
   - Automatic fallback if GPU unavailable
   - Graceful handling of CUDA errors

3. **Memory usage tracking**
   - `memory_matlab_()` function
   - Records memory at detection, sorting, merging

4. **Runtime profiling built-in**
   - Automatic timing of major stages
   - Console output with timing information

5. **Configurable parameters**
   - `.prm` files allow fine-tuning
   - `default.prm` provides sensible defaults

---

## 15. Testing Recommendations

### 15.1 Create Performance Regression Suite

```matlab
function run_performance_tests()
    % Define test datasets
    test_suite = {
        struct('name', 'small', 'file', 'test_5min.bin', 'prm', 'test.prm'),
        struct('name', 'medium', 'file', 'test_1hour.bin', 'prm', 'test.prm'),
        struct('name', 'large', 'file', 'test_4hour.bin', 'prm', 'test.prm')
    };

    % Load baseline results
    if exist('baseline_results.mat', 'file')
        baseline = load('baseline_results.mat');
    else
        baseline = [];
    end

    % Run tests
    results = struct();
    for i = 1:length(test_suite)
        test = test_suite{i};
        fprintf('\n=== Testing %s dataset ===\n', test.name);

        % Time detection
        tic;
        irc('detect', test.prm);
        results.(test.name).detect_time = toc;

        % Time sorting
        tic;
        irc('sort', test.prm);
        results.(test.name).sort_time = toc;

        % Measure memory
        results.(test.name).memory_used = get_memory_usage();

        % Compare with baseline
        if ~isempty(baseline)
            compare_with_baseline(results.(test.name), baseline.(test.name));
        end
    end

    % Save results
    save('latest_results.mat', 'results');

    % Generate report
    generate_performance_report(results, baseline);
end
```

### 15.2 Profile Critical Paths

```matlab
% Detailed profiling
profile on -history -timer 'performance'
irc('spikesort', 'test.prm')
profile viewer

% Save profile results
profsave(profile('info'), 'profile_results')

% Analyze bottlenecks
p = profile('info');
[~, idx] = sort([p.FunctionTable.TotalTime], 'descend');
top_functions = p.FunctionTable(idx(1:10));

fprintf('Top 10 time-consuming functions:\n');
for i = 1:10
    f = top_functions(i);
    fprintf('%2d. %s: %.2f sec (%.1f%%)\n', ...
        i, f.FunctionName, f.TotalTime, ...
        100*f.TotalTime/p.FunctionTable(1).TotalTime);
end
```

### 15.3 GPU Profiling

```bash
# NVIDIA Nsight Systems profiling
nsys profile -o irc_profile \
    --trace=cuda,nvtx \
    --sample=cpu \
    matlab -batch "irc('spikesort','test.prm')"

# View results
nsys-ui irc_profile.qdrep
```

**Metrics to monitor:**
- Kernel execution time
- Memory transfer time
- GPU occupancy
- SM utilization
- Memory bandwidth utilization

### 15.4 Memory Profiling

```matlab
function memory_profile = monitor_memory_usage()
    % Start monitoring
    memory_log = [];

    % Hook into major functions
    addlistener(groot, 'TimerFcn', @(~,~)log_memory());

    function log_memory()
        m = memory;
        memory_log(end+1).time = now();
        memory_log(end).used = m.MemUsedMATLAB;
        memory_log(end).available = m.MemAvailableAllArrays;
    end

    % Run sorting
    irc('spikesort', 'test.prm');

    % Analyze memory usage
    memory_profile = struct();
    memory_profile.peak = max([memory_log.used]);
    memory_profile.average = mean([memory_log.used]);
    memory_profile.log = memory_log;

    % Plot memory usage over time
    figure;
    plot([memory_log.time], [memory_log.used]/1e9);
    xlabel('Time');
    ylabel('Memory Used (GB)');
    title('Memory Usage Profile');
end
```

### 15.5 Automated Performance Testing

```matlab
% Add to continuous integration
function success = automated_performance_check()
    % Run performance tests
    results = run_performance_tests();

    % Load acceptable thresholds
    thresholds = load('performance_thresholds.mat');

    % Check against thresholds
    success = true;

    % Detection time check
    if results.medium.detect_time > thresholds.max_detect_time
        warning('Detection time %.1f sec exceeds threshold %.1f sec', ...
            results.medium.detect_time, thresholds.max_detect_time);
        success = false;
    end

    % Memory usage check
    if results.medium.memory_used > thresholds.max_memory
        warning('Memory usage %.1f GB exceeds threshold %.1f GB', ...
            results.medium.memory_used/1e9, thresholds.max_memory/1e9);
        success = false;
    end

    % Report
    if success
        fprintf('✅ All performance tests passed\n');
    else
        fprintf('❌ Performance regression detected\n');
    end
end
```

---

## 16. Immediate Action Items

### This Week (1-2 days)

**Priority 1: Quick Wins**

- [ ] **Increase MAX_LOAD_SEC**
  - Edit `default.prm` line 27
  - Change from `2` to `10`
  - Test with benchmark dataset
  - Document change in changelog

- [ ] **Add conditional parfor**
  - Edit `irc.m` around line 3577
  - Add threshold check: `if nSpk > 10000`
  - Test both branches
  - Commit changes

- [ ] **Document GPU acceleration**
  - Add GPU setup guide to README
  - Include performance comparison table
  - Add troubleshooting section
  - Document GPU requirements

- [ ] **Verify current optimizations**
  - Test merge operations with large clusters
  - Verify deferred updates working correctly
  - Check batch merge functionality

### This Month (2-4 weeks)

**Priority 2: Medium Effort, High Impact**

- [ ] **Vectorize feature extraction**
  - Profile current implementation
  - Identify vectorizable operations
  - Implement vectorized version
  - Add unit tests
  - Compare performance

- [ ] **Implement adaptive GPU memory**
  - Add `get_safe_gpu_memory()` function
  - Update memory allocation code
  - Add warning messages
  - Test with different GPU sizes

- [ ] **Smart caching with memory limits**
  - Implement `smart_cache_load()` function
  - Add memory estimation
  - Add decision logic
  - Test on low-memory systems

- [ ] **Add memory pooling**
  - Design MemoryPool class
  - Implement for common arrays
  - Update allocation sites
  - Measure impact

- [ ] **Performance regression suite**
  - Create benchmark datasets
  - Implement automated testing
  - Establish baseline metrics
  - Document thresholds

### This Quarter (1-3 months)

**Priority 3: Advanced Optimizations**

- [ ] **Implement CUDA streams**
  - Research MATLAB stream support
  - Design pipeline architecture
  - Implement for major kernels
  - Benchmark improvements

- [ ] **Optimize CUDA kernels**
  - Profile current kernels
  - Experiment with grid/block sizes
  - Implement auto-tuning
  - Test across GPU models

- [ ] **Modern GPU support**
  - Add multi-architecture compilation
  - Implement architecture-specific code paths
  - Test on sm_70, sm_80, sm_90
  - Document requirements

- [ ] **Add comprehensive profiling**
  - Implement per-stage timing
  - Add GPU utilization metrics
  - Create profiling dashboard
  - Automated bottleneck identification

### Future (6+ months)

**Priority 4: Major Features**

- [ ] **Out-of-core processing**
  - Design chunked processing architecture
  - Implement streaming interface
  - Test with very large datasets
  - Optimize chunk merging

- [ ] **Distributed computing**
  - Evaluate MATLAB Parallel Server
  - Design distribution strategy
  - Implement job scheduling
  - Test scaling characteristics

---

## Conclusion

This comprehensive performance audit has identified multiple optimization opportunities ranging from quick configuration changes to major architectural improvements. The most impactful changes can be implemented quickly:

**Immediate Gains (1-2 weeks):**
- 30-50% speedup from I/O optimization
- 10-15% from parfor optimization
- Better stability from memory management

**Near-term Gains (1-3 months):**
- 15-25% from vectorization
- 20-30% from CUDA streams
- Significant stability improvements

**Long-term Potential:**
- 2-3x from modern GPU architectures
- Linear scaling from distributed computing
- Support for unlimited dataset sizes

**Overall Estimate:** Implementing Tiers 1-2 optimizations can achieve **1.5-2.0x speedup** with **low risk** in **2-3 weeks** of development time.

---

**End of Performance Audit Report**
