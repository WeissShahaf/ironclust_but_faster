# Project_hierarchy — sorted-dataset integrity scan (viClu<->cache desync)

- Manifest: `D:\github\ironclustSW\logs\jrc_scan_project_hierarchy\manifest.csv`
- Datasets: **167**  ·  PASS: 64  ·  **DESYNC: 40**  ·  spatially-flagged (PASS): 36  ·  not-checked: 63
- Test: `all( viClu(cviSpk_clu{i}) == i )` per cluster (the [O]-reorder / desync signature). A **DESYNC verdict = corrupted → re-sort** (not repairable). Spatial flags are heuristic candidates to eyeball. A PASS is "currently self-consistent", not a proof of "never corrupted"; DI-01 `[U]` wrong-merges are undetectable here.

## ⛔ Affected — DESYNC (re-sort these)
| label | verdict | nClu | nCluDesync | nCacheMix | pctSpkWrong | file |
|---|---|---|---|---|---|---|
| afm17307_241024#afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 220 | 209 | 12 | 99.37% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_0#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_0#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_0 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_1 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_2 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_3 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241029_0 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_1 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_2 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_3 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17372_241125_0 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_1 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_2 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241127_0 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_1 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_2 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241129_0#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_1#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_2#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_0 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_1 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_2 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 197 | 176 | 15 | 90.67% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 110 | 47 | 4 | 60.13% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 191 | 184 | 19 | 97.87% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 197 | 176 | 15 | 90.67% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 110 | 47 | 4 | 60.13% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 191 | 184 | 19 | 97.87% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241209#afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 384 | 274 | 40 | 52.80% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209#optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 292 | 187 | 28 | 56.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01#afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 384 | 274 | 40 | 52.80% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01#optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 292 | 187 | 28 | 56.36% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241210 | DESYNC-SEVERE | 287 | 282 | 28 | 97.63% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241210\trial0\ephys\preprocessed\catgt_afm17372_241210_0_g0\afm17372_241210_0_g0_imec0\afm17372_241210_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241212 | DESYNC-SEVERE | 176 | 58 | 58 | 11.61% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241212\trial0\ephys\preprocessed\catgt_afm17372_241212_0_g0\afm17372_241212_0_g0_imec0\afm17372_241212_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241213 | DESYNC-SEVERE | 181 | 172 | 75 | 97.07% | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241213\trial0\ephys\preprocessed\catgt_afm17372_241213_0_g0\afm17372_241213_0_g0_imec0\afm17372_241213_0_g0_tcat.imec0.lf_shortlist_IRC_jrc.mat` |

## 🔍 Review — PASS but spatially flagged (heuristic; may be normal drift/large units)
| label | nClu | nCluSpatial | worstSiteSpan | file |
|---|---|---|---|---|
| afm16505_231213_0 | 335 | 3 | 20 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231213\ephys\sorted\IRC_hi_amps\Copy_of_monopolar_231212_test4_g0_tcat.imec0.ap_imec3B2_jrc.mat` |
| afm16505_231215_2_0#shortwin_traces_cached_seg0_probe_jrc | 491 | 1 | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_0#traces_cached_seg0_probe_jrc | 416 | 5 | 30 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_1#shortwin_traces_cached_seg0_probe_jrc | 491 | 1 | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_1#traces_cached_seg0_probe_jrc | 416 | 5 | 30 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_2#shortwin_traces_cached_seg0_probe_jrc | 491 | 1 | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_2#traces_cached_seg0_probe_jrc | 416 | 5 | 30 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc | 636 | 1 | 10 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 151 | 11 | 40 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 303 | 9 | 40 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 682 | 2 | 20 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | 436 | 2 | 19 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16924_240529_test | 181 | 2 | 16 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\240529\trial0\ephys\preprocessed\catgt_afm16924_240529_pup_retrieval_hunting_g0\afm16924_240529_pup_retrieval_hunting_g0_imec0\afm16924_240529_pup_retrieval_hunting_g0_tcat.imec0.ap_jrc.mat` |
| afm17365_241202_0 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241202_1 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241203_01 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241203_02 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241205 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241206 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241209 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241210_01 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241210_02 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241211 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241212 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241213_01 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241213_02 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241215 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241216 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_01 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_02 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241220 | 928 | 21 | 383 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_01_resorted2 | 492 | 5 | 192 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\catgt_afm17365_241219_g0\afm17365_241219_g0_imec0\afm17365_241219_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241024#afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | 427 | 67 | 233 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_0#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | 340 | 53 | 28 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_1#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | 340 | 53 | 28 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_2#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | 340 | 53 | 28 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |

## ⚠ Not checked (no sort found / load error)
| label | verdict | note | file |
|---|---|---|---|
| afm16505_231211_1 | SKIP:notfound |  | `` |
| afm16505_231212_2 | SKIP:notfound |  | `` |
| afm16505_231218_0 | SKIP:notfound |  | `` |
| afm16618_240214 | SKIP:notfound |  | `` |
| afm16618_240216 | SKIP:notfound |  | `` |
| afm16618_240226_0 | SKIP:notfound |  | `` |
| afm16618_240226_1 | SKIP:notfound |  | `` |
| afm16618_240228 | SKIP:notfound |  | `` |
| afm16618_240301 | SKIP:notfound |  | `` |
| afm16618_240307 | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| afm16924_240529_KS4_20250924 | SKIP:notfound |  | `` |
| afm16924_240526_fixedTH | SKIP:noS_clu |  | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\240526\trial0\ephys\preprocessed\catgt_afm16924_240526_pup_retrieval_g0\afm16924_240526_pup_retrieval_g0_imec0\afm16924_240526_pup_retrieval_g0_tcat.imec0.ap_NP1_jrc.mat` |
| afm16924_240529_KS4_20250924_SW | SKIP:notfound |  | `` |
| afm16924_240525_KS | SKIP:notfound |  | `` |
| afm16924_240525_KS_SPI | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| afm17365_241205_0 | SKIP:notfound |  | `` |
| afm17365_241205_1 | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| afm17307_241021 | SKIP:notfound |  | `` |
| afm17307_241023 | SKIP:notfound |  | `` |
| afm17307_241024#afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_short_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_short_jrc.mat. Not a binary MAT-file. Try load -ASCII to read as text. | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_short_jrc.mat` |
| afm17307_241025 | SKIP:notfound |  | `` |
| afm17307_241026 | SKIP:notfound |  | `` |
| afm17307_241027 | SKIP:notfound |  | `` |
| afm17307_241028 | SKIP:notfound |  | `` |
| afm17307_241029 | SKIP:notfound |  | `` |
| afm17307_241101_0 | SKIP:notfound |  | `` |
| afm17307_241101_1 | SKIP:notfound |  | `` |
| afm17307_241122_0 | SKIP:notfound |  | `` |
| afm17307_241122_1 | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| _ | SKIP:notfound |  | `` |
| afm17313_241016_0 | SKIP:notfound |  | `` |
| afm17313_241016_1 | SKIP:notfound |  | `` |
| afm17313_241017_0 | SKIP:notfound |  | `` |
| afm17313_241017_1 | SKIP:notfound |  | `` |
| afm17313_241018 | SKIP:notfound |  | `` |
| afm17313_241022 | SKIP:notfound |  | `` |
| afm17313_241023_0 | SKIP:notfound |  | `` |
| afm17313_241023_1 | SKIP:notfound |  | `` |
| afm17313_241023_2 | SKIP:notfound |  | `` |
| afm17313_241024#unipolar_afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\unipolar_afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat. Not a binary MAT-file. Try load -ASCII to read as text. | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\unipolar_afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241024_SPKGUI | SKIP:notfound |  | `` |
| afm17313_241025 | SKIP:notfound |  | `` |
| afm17313_241026 | SKIP:notfound |  | `` |
| afm17313_241027 | SKIP:notfound |  | `` |
| afm17313_241028_0 | SKIP:notfound |  | `` |
| afm17313_241028_1 | SKIP:notfound |  | `` |
| afm17313_241028_2 | SKIP:notfound |  | `` |
| afm17313_241028_3 | SKIP:notfound |  | `` |
| afm17313_241028_4#afm17313_241026_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241026_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat. Not a binary MAT-file. Try load -ASCII to read as text. | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241026_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241028_4#afm17313_241028_hunting_pups_escape_2_g0_tcat.imec0.ap_irc_jrc | SKIP:loaderr | Unable to read MAT-file \\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241028_hunting_pups_escape_2_g0_tcat.imec0.ap_irc_jrc.mat. Not a binary MAT-file. Try load -ASCII to read as text. | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241028_hunting_pups_escape_2_g0_tcat.imec0.ap_irc_jrc.mat` |
| _ | SKIP:notfound |  | `` |
| afm17372_241122_0 | SKIP:notfound |  | `` |
| afm17372_241122_1 | SKIP:notfound |  | `` |
| afm17372_241122_2 | SKIP:notfound |  | `` |
| afm17372_241215 | SKIP:notfound |  | `` |
| afm17372_241216 | SKIP:notfound |  | `` |
| afm17372_241219 | SKIP:notfound |  | `` |
| afm17372_241220 | SKIP:notfound |  | `` |

## All results
| label | verdict | nClu | nCluDesync | nCacheMix | pctSpkWrong | nCluSpatial | file |
|---|---|---|---|---|---|---|---|
| afm16505_231211_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16505_231212_2 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16505_231213_0 | PASS | 335 | 0 | 0 | 0.00% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231213\ephys\sorted\IRC_hi_amps\Copy_of_monopolar_231212_test4_g0_tcat.imec0.ap_imec3B2_jrc.mat` |
| afm16505_231215_2_0#shortwin_traces_cached_seg0_probe_jrc | PASS | 491 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_0#traces_cached_seg0_probe_jrc | PASS | 416 | 0 | 0 | 0.00% | 5 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_1#shortwin_traces_cached_seg0_probe_jrc | PASS | 491 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_1#traces_cached_seg0_probe_jrc | PASS | 416 | 0 | 0 | 0.00% | 5 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_2#shortwin_traces_cached_seg0_probe_jrc | PASS | 491 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\shortwin_traces_cached_seg0_probe_jrc.mat` |
| afm16505_231215_2_2#traces_cached_seg0_probe_jrc | PASS | 416 | 0 | 0 | 0.00% | 5 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16505\231215\ephys\preprocessed\spk\traces_cached_seg0_probe_jrc.mat` |
| afm16505_231218_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240214 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240216 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240226_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240226_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240228 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240301 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16618_240307 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc | PASS | 636 | 0 | 0 | 0.00% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2 - Copy_jrc.mat` |
| afm16963_240526#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 151 | 0 | 0 | 0.00% | 11 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 303 | 0 | 0 | 0.00% | 9 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 682 | 0 | 0 | 0.00% | 2 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16963_240526_sw#shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc | PASS | 436 | 0 | 0 | 0.00% | 2 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16963\240526\trial0\ephys\preprocessed\SW_large_win\afm16963_240526_pup_retrieval_g0_imec0\shortwin_Hi_amps_monopolar_afm16963_240526_pup_retrieval_g0_tcat.imec0.ap_imec3b2_jrc.mat` |
| afm16924_240522_test_last_good | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240522 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_0 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_1 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240524 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240525 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240526 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240527 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240527_fixedTH | PASS | 72 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\catgt_afm16924_240527_pup_retrieval_hunting_g0\afm16924_240527_pup_retrieval_hunting_g0_imec0\afm16924_240527_pup_retrieval_hunting_g0_tcat.imec0.ap_imec32b2_jrc.mat` |
| afm16924_240529_test_last_good | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240522_test | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240522_test_hard_th | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240522_test_2sec_300gap | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240522_test_20sec_10secpad | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_hard_coded | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_2sec_1overlap | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_0_Kilosort4 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_0_Ks4_raw | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16924_240523_hard_coded | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_2sec_1overlap | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_0_K4 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240523_0_Kilosort4_raw | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529_test | PASS | 181 | 0 | 0 | 0.00% | 2 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\240529\trial0\ephys\preprocessed\catgt_afm16924_240529_pup_retrieval_hunting_g0\afm16924_240529_pup_retrieval_hunting_g0_imec0\afm16924_240529_pup_retrieval_hunting_g0_tcat.imec0.ap_jrc.mat` |
| afm16924_240529_KS4_20250924 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16924_240526_fixedTH | SKIP:noS_clu | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\240526\trial0\ephys\preprocessed\catgt_afm16924_240526_pup_retrieval_g0\afm16924_240526_pup_retrieval_g0_imec0\afm16924_240526_pup_retrieval_g0_tcat.imec0.ap_NP1_jrc.mat` |
| afm16924_240529_KS4_20250924_SW | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16924_240525_KS | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm16924_240529_commit20251010 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529_commit20251014 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529_commit20251015 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529_commit20251013 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240529_test2 | PASS | 271 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\afm16924\concat\supercat_afm16924_240522_g0\afm16924_240522_g0_imec0\KS2_whiten_afm16924_supercat.imec0.ap_imec3b2_2sec_chunks_jrc.mat` |
| afm16924_240525_KS_SPI | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17365_241202_0 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241202_1 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241203_01 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241203_02 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241205 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241205_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17365_241205_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17365_241206 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241209 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241210_01 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241210_02 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241211 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241212 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241213_01 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241213_02 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241215 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241216 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_01 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_02 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241220 | PASS | 928 | 0 | 0 | 0.00% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\concat\supercat_afm17365_241202_0_g0\afm17365_241202_0_g0_imec0\afm17365_241202_0_g0_tcat.imec0.ap_IRC_reordered_jrc.mat` |
| afm17365_241219_01_resorted2 | PASS | 492 | 0 | 0 | 0.00% | 5 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17365\supercat\catgt_afm17365_241219_g0\afm17365_241219_g0_imec0\afm17365_241219_g0_tcat.imec0.ap_IRC_jrc.mat` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241021 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241023 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241024#afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 220 | 209 | 12 | 99.37% | 19 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241024#afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_short_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_short_jrc.mat` |
| afm17307_241025 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241026 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241027 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241028 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241029 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241030_0#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | 43 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_0#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | 16 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | 43 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | 16 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2#afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | 43 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2#merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | 16 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_0 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | 56 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_1 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | 56 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_2 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | 56 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_3 | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | 56 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241101_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241101_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241122_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17307_241122_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241016_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241016_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241017_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241017_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241018 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241022 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241023_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241023_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241023_2 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241024#afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | PASS | 427 | 0 | 0 | 0.00% | 67 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241024#unipolar_afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241024\trial0\ephys\preprocessed\catgt_afm17313_241024_hunting_pups_escape_g0\afm17313_241024_hunting_pups_escape_g0_imec0\unipolar_afm17313_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241024_SPKGUI | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241025 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241026 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241027 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241028_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241028_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241028_2 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241028_3 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17313_241028_4#afm17313_241026_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241026_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17313_241028_4#afm17313_241028_hunting_pups_escape_2_g0_tcat.imec0.ap_irc_jrc | SKIP:loaderr | 0 | 0 | 0 | 0.00% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241028\trial4\ephys\preprocessed\catgt_afm17313_241028_hunting_pups_escape_2_g0\afm17313_241028_hunting_pups_escape_2_g0_imec0\afm17313_241028_hunting_pups_escape_2_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17313_241029_0 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | 107 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_1 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | 107 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_2 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | 107 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_3 | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | 107 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| _ | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241122_0 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241122_1 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241122_2 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241125_0 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | 4 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_1 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | 4 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_2 | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | 4 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241127_0 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_1 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_2 | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241129_0#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_0#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | PASS | 340 | 0 | 0 | 0.00% | 53 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_1#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_1#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | PASS | 340 | 0 | 0 | 0.00% | 53 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_2#afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | 21 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_2#monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc | PASS | 340 | 0 | 0 | 0.00% | 53 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\monopolar_of_afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_0 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_1 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_2 | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | 3 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 197 | 176 | 15 | 90.67% | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 110 | 47 | 4 | 60.13% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0#shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 191 | 184 | 19 | 97.87% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 197 | 176 | 15 | 90.67% | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 110 | 47 | 4 | 60.13% | 0 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1#shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc | DESYNC-SEVERE | 191 | 184 | 19 | 97.87% | 1 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241209#afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 384 | 274 | 40 | 52.80% | 34 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209#optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 292 | 187 | 28 | 56.36% | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01#afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 384 | 274 | 40 | 52.80% | 34 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01#optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc | DESYNC-SEVERE | 292 | 187 | 28 | 56.36% | 18 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241210 | DESYNC-SEVERE | 287 | 282 | 28 | 97.63% | 9 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241210\trial0\ephys\preprocessed\catgt_afm17372_241210_0_g0\afm17372_241210_0_g0_imec0\afm17372_241210_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241212 | DESYNC-SEVERE | 176 | 58 | 58 | 11.61% | 8 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241212\trial0\ephys\preprocessed\catgt_afm17372_241212_0_g0\afm17372_241212_0_g0_imec0\afm17372_241212_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241213 | DESYNC-SEVERE | 181 | 172 | 75 | 97.07% | 5 | `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241213\trial0\ephys\preprocessed\catgt_afm17372_241213_0_g0\afm17372_241213_0_g0_imec0\afm17372_241213_0_g0_tcat.imec0.lf_shortlist_IRC_jrc.mat` |
| afm17372_241215 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241216 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241219 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
| afm17372_241220 | SKIP:notfound | 0 | 0 | 0 | 0.00% | 0 | `` |
