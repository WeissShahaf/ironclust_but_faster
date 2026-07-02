








![IronClust logo](img/ironclust_logo.png)




# IronClust
Terabyte-scale, drift-resistant spike sorter for multi-day recordings from [high-channel-count probes](https://www.nature.com/articles/nature24636)

> **Note — this is a fork.** A performance- and workflow-focused fork of
> [IronClust](https://github.com/flatironinstitute/ironclust) (upstream:
> `flatironinstitute/ironclust`). It adds per-site/label-based and CLASSIX clustering,
> parallel and memory-bounded sorting, several manual-GUI improvements, and a number of
> robustness fixes, on top of retuned default parameters.
> **See [What's different from upstream IronClust](#whats-different-from-upstream-ironclust)
> for the full list.**

## Getting Started

## Probe drift handling
IronClust tracks the probe drift by computing the anatomical similarity between time chunks (~20 sec) where each chunk contains approximately equal number of spikes. For each chunk, the anatomical snapshot is computed from the joint distribution bwteen spike amplitudes and positions. Based on the anatomical similarity, each chunk is linked to 15 nearest chunks (self included) forming ~300 sec duration. The linkage is constrained within +/-64 steps (~1280 sec) to handle rigid drift occuring in faster time-scale while rejecting slower changes. The KNN-graph between the spikes is constrained to the linked chunks, such that the neighborhood of spikes from a given chunk is restricted to the spikes from the linked chunks. Thus, drift-resistance is achieved by including and excluding the neighbors based on the activity-inferred anatomical landscape surrounding the probe.

### Prerequisites

- Matlab 
- Matlab signal and image processing toolboxes
- (Optional) CUDA Toolkit (for GPU processing for significant speed-up)
- For terabyte-scale recording: At least 128GB RAM

### Installation
- Clone from Github
```
git clone https://github.com/WeissShahaf/ironclust_but_faster
```
(upstream project: `https://github.com/flatironinstitute/ironclust`)
- (optional) Compile GPU codes (.cu extension)
```
irc2 compile
```

## Quick tutorial

This command creates `irc2` folder in the recording directory and writes output files there.
```
irc2 `path_to_recording_file`
```
Examples 
```
irc2 [path_to_my_recording.mda] (output_dir)  # for .mda format
irc2 [path_to_my_recording.imec#.bin] (output_dir)  # for SpikeGLX Neuropixels recordings (requires `.meta` files)
irc2 [path_to_my_recording.bin] [myprobe.prb] (output_dir) # specify the probe file, output to `myprobe` the recording directory
irc2 [path_to_my_recording.dat] [myprobe.prb] (output_dir)  # for Intan (requires `info.rhd`) and Neuroscope (requires `.xml`) format
```
* `output_dir` (optional): default output location is `irc2` under the recording directory or `myprobe` if the probe file is specified
* `myprobe.prb`: required for Intan and Neuroscope formats. SpikeGLX does not require it if [Neuropixels probe](https://www.neuropixels.org/) is used.

IronClust caches the `path_to_prm_file` for subsequent commands. To display the currently selected parameter file, run
```
irc2 which
```

To select a parameter file (or a recording file):
```
irc2 select [path_to_my_param.prm]
irc2 select [path_to_my_recording]
```

Rerun using new parameters (up to four parameters can be specified, no spaces between name=value pairs):
```
irc2 rerun [path_to_my_param.prm] [name1=val1] [name2=val2] [name3=val3]
irc2 rerun [name1=val1] [name2=val2] [name3=val3] [name4=val4]  # uses a cached parameter file
```

To visualize the raw or filtered traces and see clustered spikes on the traces, run (press 'h' in the UI for further help)
```
irc2 traces [path_to_my_recording] 
irc2 traces [path_to_my_param.prm]
```

Manual clustering user interface
```
irc2 manual [path_to_my_recording] 
irc2 manual [path_to_my_param.prm]
```

This command shows the parameter file (`.prm` extension) used for sorting
```
irc2 edit `path_to_recording_file`
```

To select a new parameter file, run
```
irc2 select `path_to_prm_file`
```

You can re-run the sorting after updating the sorting parameter by running 
```
irc2 `path_to_recording_file`
```
IronClust only runs the part of sorting pipeline affected by the updated parameters. 

You can initialize the sorting output by running either of the following commands:
```
irc2 clear `path_to_recording_file`
irc2 clear `output_directory`
irc2 clear `path_to_prm_file`
```

## What's different from upstream IronClust

This fork tracks `flatironinstitute/ironclust` (diverged at upstream `master`, commit
`2d7b56c`) and adds the following. Items marked *(default change)* alter out-of-the-box
behaviour relative to upstream; everything else is additive or a bug fix.

### New clustering methods
- **Per-site, label-based clustering** — `vcCluster = 'kmeans' | 'hdbscan' | 'isosplit6'`.
  Each detection site is clustered independently on its local features (over-segmentation),
  then the normal cross-site post-merge collapses duplicates. HDBSCAN is a pure-MATLAB
  implementation; ISO-SPLIT tries the Python `isosplit6` backend and falls back to a bundled
  pure-MATLAB `isosplit5`. See [Clustering methods](#clustering-methods) and
  [matlab/CLUSTERING_METHODS.md](matlab/CLUSTERING_METHODS.md).
- **CLASSIX clustering** — `vcCluster = 'classix'` (fast sorting-based clustering) and, as a
  post-merge refinement, `post_merge_mode0 = 21`. See
  [matlab/CLASSIX_USAGE.md](matlab/CLASSIX_USAGE.md).
- Label-based methods keep their own labels (an internal `fLabelClu` flag makes `fet2clu_`
  skip the density-peak `postCluster_`).

### Performance
- **Parallel per-site clustering** — the kmeans/HDBSCAN/isosplit per-site loop runs across
  workers when `fParfor = 1` *(default change: `fParfor` is now `1`)*, capped by
  `nWorkers_clust`.
- **Per-site spike cap** — `maxSpk_persite_clust` bounds the O(n²) kNN/clustering cost on huge
  (usually noise) sites by clustering a random subsample and assigning the rest to the nearest
  member. `[]` = off (byte-identical to upstream). Example: a 1.1 M-spike site drops from
  ~80 min to ~90 s at `m = 50000`.
- **I/O and detection tuning** — larger load blocks (`MAX_LOAD_SEC = 10`, larger `nPad_filt`),
  Wiener detection filter by default, plus GUI/plot performance work. Details in
  `matlab/GUI_PERFORMANCE_OPTIMIZATIONS.md`, `matlab/MERGE_OPTIMIZATIONS.md`,
  `matlab/FIND_OPTIMIZATION_ANALYSIS.md`, and `matlab/GPU_USAGE_ANALYSIS.md`.

### Robustness & bug fixes
- Hardened the **post-merge and per-site paths** against empty / single-spike / gappy-label
  clusters (the many-small-cluster case produced by label methods + spike cap). No healthy run
  changes its output. (`logs/changes_log20260626.md`, `logs/plan_postmerge_robustness.md`.)
- Fixed **GUI "Merge auto"** silently discarding merges (a sign-flip regression in
  `post_merge_wav_`).
- Fixed cluster **merge / delete** bugs and added defensive sizing of cluster-quality arrays in
  manual curation.

### Manual curation / GUI
- **Deferred-edit workflow** — queue merges/deletes and apply them together with `u` (cancel
  with `Esc`).
- **Drift view shown by default.**
- **Probe-map site labels & region colouring** — in the probe map (`e`), press `c` to cycle
  site labels between channel #, site #, and anatomical region; in region mode the boxes are
  colour-coded by region (region source: `vcFile_site_region`).
  See [Manual curation → Probe map window](#probe-map-window).
- **Cluster annotations** — `1` / `2` / `3` / `4` mark a unit as single / multi / noise /
  axonal.

### Changed default parameters *(behaviour changes vs upstream)*

| Parameter | Upstream | This fork | Purpose |
|---|---|---|---|
| `fParfor` | `0` | `1` | parallelise per-site clustering |
| `MAX_LOAD_SEC` | `[]` | `10` | fewer, larger I/O blocks |
| `nPad_filt` | `300` | `150000` | 0.5 s filter-edge overlap at 30 kHz |
| `vcFilter_detect` | `''` | `'wiener'` | detection filter |
| `vcCommonRef` | `'mean'` | `'none'` | local referencing |
| `freqLimNotch` | `{}` | `{[48,52]}` | 50 Hz mains notch |
| `qqFactor` | `4.5` | `5` | detection threshold |
| `spkLim_ms` | `[-.25, .75]` | `[-.3, 1.25]` | wider waveform window |
| `blank_thresh` | `[]` | `8` | reject artifact bursts |
| `maxDist_site_spk_um` | `75` | `85` | waveform extraction radius |
| `post_merge_mode0` | `[12, 15, 17]` | `[12, 17]` | auto-merge sequence |
| `fCheckSites` | `0` | `1` | auto-reject bad sites |
| `fWav_raw_show` | `0` | `1` | show raw waveforms |
| `fText` | `1` | `0` | hide per-unit counts by default |
| `nShow_proj` | `500` | `50` | faster projection view |

### New parameters
- **Clustering:** `classix_*` (`radius`, `minPts`, `merge_tiny`, `use_mex`, `verbose`),
  `kmeans_*`, `hdbscan_*`, `isosplit_*`, `nWorkers_clust`, `maxSpk_persite_clust`.
- **Detection thresholds (opt-in, mostly commented in `default.prm`):** a fixed/global/smoothed
  threshold hierarchy (`fUseGlobalThresh`, `fSmoothThresh`, `vcSmoothMethod`, `nSmoothWindow`,
  `nSmoothOverlap`, `smoothSigma`) and `fDiagnosticMode`.
- **Manual GUI:** `vcFile_site_region` (CSV of site→region for the probe map).

`matlab/default.prm` is the authoritative parameter list with inline docs. Per-topic
documents live alongside the code
([CLUSTERING_METHODS.md](matlab/CLUSTERING_METHODS.md),
[CLASSIX_USAGE.md](matlab/CLASSIX_USAGE.md)) and dated change logs under [`logs/`](logs/).

## Clustering methods

The primary clustering algorithm is selected with the `vcCluster` parameter (set it in the
`.prm` file, then re-sort). The default `drift-knn` is the drift-resistant density-peak (DPC)
method described under [Probe drift handling](#probe-drift-handling).

In addition to the native DPC methods, IronClust includes **per-site, label-based** methods.
These cluster the spikes of each detection site independently and let the automated post-merge
combine matching units across sites:

| `vcCluster` | Method | Notes |
|---|---|---|
| `drift-knn` *(default)* | Drift-resistant KNN density-peak | native DPC |
| `spacetime` | Spatiotemporal decentralized DPC | native DPC, handles slow drift |
| `drift` | Fast drift clustering | native DPC |
| `xcov` | Waveform-covariance features | native DPC |
| `kmeans` | Per-site k-means | requires Statistics & ML Toolbox |
| `hdbscan` | Per-site HDBSCAN | pure MATLAB |
| `isosplit6` | Per-site ISO-SPLIT | tries Python `isosplit6`, falls back to pure-MATLAB `isosplit5` |
| `classix` | CLASSIX | label-based |

Each method has tunable parameters (e.g. `isosplit_isocut_threshold`, `hdbscan_minPts`,
`hdbscan_minClusterSize`, `kmeans_k`). See **[matlab/CLUSTERING_METHODS.md](matlab/CLUSTERING_METHODS.md)**
for the full parameter reference and `matlab/default.prm` for defaults.

To switch method, set `vcCluster` in your `.prm` (e.g. `vcCluster = 'isosplit6';`) and re-sort:
```
irc sort [path_to_my_param.prm]
```

## Manual curation

Open the manual curation GUI:
```
irc manual [path_to_my_param.prm]
```
The cluster waveform view uses a **deferred-edit** workflow: queue merges/deletes, then apply
them together with `u` (or cancel with `Esc`). Press `h` in the GUI for built-in help.

### Keyboard shortcuts (cluster waveform view)

| Key | Action |
|---|---|
| `←` / `→` | Select previous / next cluster |
| `Shift`+`←` / `→` | Move the second (comparison) cluster selection |
| `Home` / `End` | Jump to first / last cluster |
| `Space` | Zoom and auto-select the most similar cluster for comparison |
| `0` | Clear the second cluster selection |
| `↑` / `↓` | Increase / decrease the waveform amplitude scale |
| `z` | Zoom to the selected cluster |
| `r` | Reset the view |
| `m` | Queue a merge of the two selected clusters |
| `d` / `Delete` / `Backspace` | Queue deletion of the selected cluster |
| `s` | Auto-split the selected cluster |
| `u` | Apply all queued (pending) merges/deletes and update |
| `Esc` | Cancel all pending operations |
| `o` | Reorder clusters by probe coordinates |
| `1` / `2` / `3` / `4` | Annotate selected cluster as single / multi / noise / axonal |
| `w` | Toggle individual spike waveforms |
| `n` | Toggle cluster number/count labels |
| `a` | Refresh the selected cluster's spikes |
| `f` | Show cluster info / statistics |
| `t` | Time vs. amplitude view |
| `c` | Cross-correlogram |
| `i` | ISI histogram |
| `v` | ISI return map |
| `e` | Probe / amplitude map (in that window, `c` cycles channel #/site #/region labels + region colouring — see below) |
| `j` | Drift view |
| `p` | PSTH (requires a trial file) |
| `h` | Help |

### Probe map window

The probe map (opened with `e`, top-left) draws each site as a box coloured by the selected
cluster's peak-to-peak amplitude. That window has its own controls:

| Key | Action |
|---|---|
| `c` | Cycle the site labels: **channel #** → **site #** → **region** |
| `h` | Help |

In **region** mode the boxes are colour-coded by anatomical region (one colour per region).
Region labels are read from a CSV named by the `vcFile_site_region` parameter in your `.prm`:

```
vcFile_site_region = 'path/to/sites_region.csv';
```

The CSV holds `key,region` rows, where `key` is either a **channel number** (matched against
`viSite2Chan`) or a **1-based site index**; a header row is allowed. Sites the CSV does not
cover are labelled `?`. If the parameter is empty or the file is missing, `c` simply cycles
channel # ↔ site #.

## Importing multiple `.bin` files from [SpikeGLX](https://github.com/billkarsh/SpikeGLX)
```
irc2 import-spikeglx [path_to_my_recording.bin] [path_to_probe_file.prb] (path_to_output_dir)
```
- `path_to_output_dir` (optional): defalt location is 'probe_name' under the recording dorectory.
- Output format is [.mda format](https://users.flatironinstitute.org/~magland/docs/mountainsort_dataset_format/) 
- Probe file (`.prb`) is required unless Neuropixels probe is used. [`.prb` file format](https://github.com/JaneliaSciComp/JRCLUST/wiki/Probe-file)
- `path_to_my_recording.bin`: you may use a '\*' character to join multiple files, or provide a text (`.txt`) file containing a list of files to be merged in a specified order (a text file containing the list is created when you use '\*' character). 

## Importing multiple `.dat` files from [Intan RHD format](http://intantech.com/downloads.html?tabSelect=Software&yPos=0)
```
irc2 import-intan [path_to_my_recording.bin] [path_to_probe_file.prb] (path_to_output_dir)
```
- This step is not necessary if all channels are saved to a single file.
- `path_to_my_recording.bin`: Use '\*' character to join all channels that are saved to separate files.

## Deployment

- IronClust can run through SpikeForest2 or spikeinterface pipeline
- IronClust output can be exported to Phy, Klusters, and JRClust formats for manual clustering

## Export to Phy
Export to [Phy](https://github.com/kwikteam/phy-contrib/blob/master/docs/template-gui.md) for manual curation. You need to clone Phy and set the path `path_phy_x` where x={'pc,'mac','lin'} to open the output automatically.
```
irc2 export-phy [path_to_prm_file] (output_dir)   # default output location is `phy` under the output folder
```

If Phy doesn't open automatically, run the following python command to open Phy
```
phy template-gui path_to_param.py
```

## Export to Klusters
Export to [Klusters](http://neurosuite.sourceforge.net/) for manual curation. You can set the path `path_klusters_x` in `user.cfg` where x = {'pc', 'mac', 'lin'} to open the output automatically.
```
irc2 export-klusters [path_to_prm_file] (output_dir)
```
* output_dir (optional): default output location is `klusters` under the same directory.

If Klusters doesn't open automatically, open Klusters GUI and open `.par.#` file (#: shank number). 

## Export to JRCLUST
Export to [JRCLUST](https://github.com/JaneliaSciComp/JRCLUST) for manual curation. You need to clone JRCLUST and set the path `path_jrclust` in `user.cfg` (you need to create this file if it doesn't exist).
```
irc2 export-jrclust [path_to_prm_file]
```
* output_dir: it creates a new JRCLUST parameter file by appending `_jrclust.prm` at the same directory.

If JRCLUST doesn't open automatically, run `jrc manual [my_jrclust.prm]`

## Contributing

Please read [CONTRIBUTING.md](https://gist.github.com/PurpleBooth/b24679402957c63ec426) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

To display the current version, run
```
irc2 version
```

## Authors

- James Jun, Center for Computational Mathematics, Flatiron Institute
- Jeremy Magland, Center for Computational Mathematics, Flatiron Institute

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* We thank our collaborators and contributors of the ground-truth datasets to validate our spike sorting accuracy through spikeforest.flatironinstitute.org website.
* We thank [Loren Frank's lab](https://www.cin.ucsf.edu/HTML/Loren_Frank.html) for contributing the terabyte-scale 10-day continuous recording data.

* We thank [Dan English's lab](https://www.englishneurolab.com/) for contributing four-day uLED probe recordings.

