# Sorted-dataset integrity — cross-repo summary (viClu<->cache desync)

Read-only scan via `check_jrc_one` / `scan_jrc_report`. **DESYNC = corrupted (the [O]-reorder desync); not repairable -> re-sort.** Duplicates below are collapsed to unique `_jrc.mat` files, with the sessions that reference each.

## Project_hierarchy
- entries: 167 | PASS: 64 | DESYNC entries: 40 | **unique corrupted files: 17** | load-error: 4 | not-found: 58

| unique corrupted _jrc.mat | verdict | nClu | desync | mix | %wrong | sessions affected |
|---|---|---|---|---|---|---|
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241024\trial0\ephys\preprocessed\catgt_afm17307_241024_hunting_pups_escape_g0\afm17307_241024_hunting_pups_escape_g0_imec0\afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 220 | 209 | 12 | 99.37% | afm17307_241024 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 799 | 792 | 117 | 99.39% | afm17307_241030_0, afm17307_241030_1, afm17307_241030_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241030\supercat_afm17307_241030_hunting_pups_escape_g0\afm17307_241030_hunting_pups_escape_g0_imec0\merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 114 | 85 | 12 | 52.36% | afm17307_241030_0, afm17307_241030_1, afm17307_241030_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17307\241031\supercat_afm17307_241031_hunting_pups_escape2_g0\afm17307_241031_hunting_pups_escape2_g0_imec0\afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 1122 | 1104 | 299 | 93.04% | afm17307_241031_0, afm17307_241031_1, afm17307_241031_2, afm17307_241031_3 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17313\241029\catgt_output\supercat_afm17313_241029_hunting_pups_escape_g0\afm17313_241029_hunting_pups_escape_g0_imec0\afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` | DESYNC-SEVERE | 314 | 313 | 79 | 99.36% | afm17313_241029_0, afm17313_241029_1, afm17313_241029_2, afm17313_241029_3 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241125\supercat_afm17372_241125_g0\afm17372_241125_g0_imec0\afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 219 | 216 | 46 | 98.14% | afm17372_241125_0, afm17372_241125_1, afm17372_241125_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241127\concat\supercat_afm17372_241127_g0\afm17372_241127_g0_imec0\afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` | DESYNC-SEVERE | 199 | 185 | 38 | 93.87% | afm17372_241127_0, afm17372_241127_1, afm17372_241127_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241129\concat\supercat_afm17372_20241129_0_g0\afm17372_20241129_0_g0_imec0\afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 257 | 81 | 61 | 28.69% | afm17372_241129_0, afm17372_241129_1, afm17372_241129_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241202\concat\supercat_afm17372_241202_0_g0\afm17372_241202_0_g0_imec0\afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 212 | 113 | 66 | 47.80% | afm17372_241202_0, afm17372_241202_1, afm17372_241202_2 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 197 | 176 | 15 | 90.67% | afm17372_241206_0, afm17372_241206_1 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 110 | 47 | 4 | 60.13% | afm17372_241206_0, afm17372_241206_1 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241206\concat\afm17372_241206_0_g0\afm17372_241206_0_g0_imec0\shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 191 | 184 | 19 | 97.87% | afm17372_241206_0, afm17372_241206_1 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` | DESYNC-SEVERE | 384 | 274 | 40 | 52.80% | afm17372_241209, afm17372_241209_01 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241209\trial0\ephys\preprocessed\catgt_afm17372_241209_0_g0\afm17372_241209_0_g0_imec0\optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` | DESYNC-SEVERE | 292 | 187 | 28 | 56.36% | afm17372_241209, afm17372_241209_01 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241210\trial0\ephys\preprocessed\catgt_afm17372_241210_0_g0\afm17372_241210_0_g0_imec0\afm17372_241210_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 287 | 282 | 28 | 97.63% | afm17372_241210 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241212\trial0\ephys\preprocessed\catgt_afm17372_241212_0_g0\afm17372_241212_0_g0_imec0\afm17372_241212_0_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 176 | 58 | 58 | 11.61% | afm17372_241212 |
| `\\gpfs.corp.brain.mpg.de\stem\data\project_hierarchy\data\np2\afm17372\241213\trial0\ephys\preprocessed\catgt_afm17372_241213_0_g0\afm17372_241213_0_g0_imec0\afm17372_241213_0_g0_tcat.imec0.lf_shortlist_IRC_jrc.mat` | DESYNC-SEVERE | 181 | 172 | 75 | 97.07% | afm17372_241213 |

## cuniform_NPX
- entries: 26 | PASS: 8 | DESYNC entries: 9 | **unique corrupted files: 5** | load-error: 2 | not-found: 7

| unique corrupted _jrc.mat | verdict | nClu | desync | mix | %wrong | sessions affected |
|---|---|---|---|---|---|---|
| `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18349\catgt_260317_afm18349_g0\260317_afm18349_g0_imec0\260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 209 | 188 | 35 | 88.12% | afm18349_260317_0, afm18349_260317_0_all_sites |
| `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260317_AFM-18367\supercat_260317_afm18367_g0\260317_afm18367_g0_imec0\test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 36 | 12 | 3 | 39.56% | afm18367_260317_0, afm18367_260317_0_hdbscan, afm18367_260317_1, afm18367_260317_1_hdbscan |
| `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18349\catgt_260320_afm18349_g0\260320_afm18349_g0_imec0\260320_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 259 | 237 | 18 | 92.39% | afm18349_260320_0 |
| `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260320_AFM-18367\260320_afm18367_g0\260320_afm18367_g0_imec0\260320_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 138 | 74 | 26 | 43.44% | afm18367_260320_0 |
| `\\gpfs.corp.brain.mpg.de\stem\data\Project_Motor\NPX\00_data\260324_AFM-18349\catgt_260324_afm18349_g0\260324_afm18349_g0_imec0\260324_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | DESYNC-SEVERE | 190 | 179 | 52 | 91.62% | afm18349_260324_0 |

