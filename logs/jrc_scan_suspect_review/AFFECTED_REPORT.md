# Tightened suspect review — PASS files re-scored (time-interleaved secondary depth population)

- Manifest: `D:\github\ironclustSW\logs\jrc_scan_suspect_review\manifest.csv`
- Datasets: **18**  ·  PASS: 18  ·  **DESYNC: 0**  ·  spatially-flagged (PASS): 4  ·  not-checked: 0
- Test: `all( viClu(cviSpk_clu{i}) == i )` per cluster (the [O]-reorder / desync signature). A **DESYNC verdict = corrupted → re-sort** (not repairable). Spatial flags are heuristic candidates to eyeball. A PASS is "currently self-consistent", not a proof of "never corrupted"; DI-01 `[U]` wrong-merges are undetectable here.

## ⛔ Affected — DESYNC (re-sort these)
_None._

## 🔍 Review — PASS but SUSPECT (tightened heuristic: a time-interleaved secondary depth population; eyeball for a two-neuron fusion)
| label | nClu | nCluSuspect | worstDepthGapUm | file |
|---|---|---|---|---|
| afm16505_231215_2_0#traces_cached_seg0_probe_jrc | 416 | 1 | 187 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16963_240526_sw#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 303 | 1 | 152 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 151 | 1 | 152 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm17365_241202_0 | 928 | 1 | 329 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |

## ⚠ Not checked (no sort found / load error)
_None._

## All results
| label | verdict | nClu | nCluDesync | nCacheMix | pctSpkWrong | nCluSuspect | file |
|---|---|---|---|---|---|---|---|
| afm16505_231213_0 | PASS | 335 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231213\ephys\sorted\IRC_hi_amps\Copy_of_monopolar_231212_test4_g0_tcat.imec0.ap_imec3B2_jrc.mat` |
| afm16505_231215_2_0#shortwin_traces_cached_seg0_probe_jrc | PASS | 491 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_0#traces_cached_seg0_probe_jrc | PASS | 416 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16924_240529_test | PASS | 181 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\240529\trial0\ephys\preprocessed\catgt_afm16924_240529_pup_retrieval_hunting_g0\afm16924_240529_pup_retrieval_hunting_g0_imec0\afm16924_240529_pup_retrieval_hunting_g0_tcat.imec0.ap_jrc.mat` |
| afm16924_240527_fixedTH | PASS | 72 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\catgt_afm16924_240527_pup_retrieval_hunting_g0\afm16924_240527_pup_retrieval_hunting_g0_imec0\afm16924_240527_pup_retrieval_hunting_g0_tcat.imec0.ap_imec32b2_jrc.mat` |
| afm16924_240522_test_last_good | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16963_240526_sw#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 303 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 682 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 436 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc | PASS | 636 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 151 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm17313_241024#afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | PASS | 427 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17365_241219_01_resorted2 | PASS | 492 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\catgt_afm17365_241219_g0\afm17365_241219_g0_imec0\afm17365_241219_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17365_241202_0 | PASS | 928 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17372_241129_0#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | PASS | 340 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0#260317_afm18367_g0_tcat.imec0.ap_IRC_jrc | PASS | 170 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260324_0 | PASS | 226 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_t0.imec0.ap_260324_afm18367_g0_t0.imec0.ap_PPN_CUN_margin120um_IRC_jrc.mat` |
| afm18367_260324_0_catgt_IRC | PASS | 159 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18367\260324_afm18367_g0\catgt_260324_afm18367_g0\260324_afm18367_g0_imec0\260324_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
