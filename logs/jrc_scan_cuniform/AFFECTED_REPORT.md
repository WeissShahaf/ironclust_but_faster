# cuniform_NPX — sorted-dataset integrity scan (viClu<->cache desync)

- Manifest: `D:\github\ironclustSW\logs\jrc_scan_cuniform\manifest.csv`
- Datasets: **26**  ·  PASS: 8  ·  **DESYNC: 9**  ·  spatially-flagged (PASS): 8  ·  not-checked: 9
- Test: `all( viClu(cviSpk_clu{i}) == i )` per cluster (the [O]-reorder / desync signature). A **DESYNC verdict = corrupted → re-sort** (not repairable). Spatial flags are heuristic candidates to eyeball. A PASS is "currently self-consistent", not a proof of "never corrupted"; DI-01 `[U]` wrong-merges are undetectable here.

## ⛔ Affected — DESYNC (re-sort these)
| label | verdict | nClu | nCluDesync | nCacheMix | pctSpkWrong | file |
|---|---|---|---|---|---|---|
| afm18349_260317_0#260317_afm18349_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 209 | 188 | 35 | 88.12% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260320_0 | DESYNC-SEVERE | 259 | 237 | 18 | 92.39% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18349\catgt_260320_afm18349_g0\260320_afm18349_g0_imec0\260320_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260324_0 | DESYNC-SEVERE | 190 | 179 | 52 | 91.62% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18349\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260320_0 | DESYNC-SEVERE | 138 | 74 | 26 | 43.44% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18367\260320_afm18367_g0\260320_afm18367_g0_imec0\260320_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260317_0_all_sites#260317_afm18349_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 209 | 188 | 35 | 88.12% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0_hdbscan#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1_hdbscan#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |

## 🔍 Review — PASS but spatially flagged (heuristic; may be normal drift/large units)
| label | nClu | nCluSpatial | worstSiteSpan | file |
|---|---|---|---|---|
| afm18367_260317_0#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | 170 | 3 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | 170 | 3 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0_catgt_IRC | 159 | 1 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0 | 226 | 3 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_t0.imec0.ap_260324_afm18367_g0_t0.imec0.ap_PPN_CUN_margin120um_IRC_jrc.mat` |
| afm18367_260324_0_catgt_KS4 | 159 | 1 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0_catgt_KS3 | 159 | 1 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0_hdbscan#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | 170 | 3 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1_hdbscan#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | 170 | 3 | 75 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |

## ⚠ Not checked (no sort found / load error)
| label | verdict | note | file |
|---|---|---|---|
| afm18348_260317_0 | SKIP:notfound |  | `` |
| afm18348_260320_1 | SKIP:notfound |  | `` |
| afm18348_260324_0 | SKIP:notfound |  | `` |
| afm18349_260317_0#260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat. File might be corrupt. | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat` |
| _ | SKIP:notfound |  | `` |
| afm18349_260317_0_all_sites#260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat. File might be corrupt. | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat` |
| afm18367_A260324_KS25 | SKIP:notfound |  | `` |
| afm18367_S260324_SPI | SKIP:notfound |  | `` |
| afm18367_260324_0_catgt_SC2 | SKIP:notfound |  | `` |

## All results
| label | verdict | nClu | nCluDesync | nCacheMix | pctSpkWrong | nCluSpatial | file |
|---|---|---|---|---|---|---|---|
| afm18348_260317_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18348_260320_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18348_260324_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18349_260317_0#260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat` |
| afm18349_260317_0#260317_afm18349_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 209 | 188 | 35 | 88.12% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260320_0 | DESYNC-SEVERE | 259 | 237 | 18 | 92.39% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18349\catgt_260320_afm18349_g0\260320_afm18349_g0_imec0\260320_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260324_0 | DESYNC-SEVERE | 190 | 179 | 52 | 91.62% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18349\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | PASS | 170 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | PASS | 170 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260320_0 | DESYNC-SEVERE | 138 | 74 | 26 | 43.44% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18367\260320_afm18367_g0\260320_afm18367_g0_imec0\260320_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0_catgt_IRC | PASS | 159 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18349_260317_0_all_sites#260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_all_sites_jrc.mat` |
| afm18349_260317_0_all_sites#260317_afm18349_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 209 | 188 | 35 | 88.12% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_A260324_KS25 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18367_S260324_SPI | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18367_260324_0 | PASS | 226 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_t0.imec0.ap_260324_afm18367_g0_t0.imec0.ap_PPN_CUN_margin120um_IRC_jrc.mat` |
| afm18367_260324_0_catgt_KS4 | PASS | 159 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0_catgt_SC2 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm18367_260324_0_catgt_KS3 | PASS | 159 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0_hdbscan#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | PASS | 170 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0_hdbscan#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1_hdbscan#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | PASS | 170 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1_hdbscan#test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
