# Per-session grouping-survival (corrupted sorts)

`survival` = % of spikes in cleanly-permuted (whole-cluster, just-renumbered) clusters = grouping preserved. `mixed` = compounded clusters (genuinely regrouped). Low `cover` (<~90%) = subsampled cache, so survival is a conservative lower bound. All still DESYNC -> re-sort is the safe fix.

| session | survival | mixed clusters | nClu | cache cover | sort file |
|---|---|---|---|---|---|
| afm17372_241213 | 54.3% | 75 | 181 | 105% | `afm17372_241213_0_g0_tcat.imec0.lf_shortlist_IRC_jrc.mat` |
| afm17372_241129_0 | 59.2% | 61 | 257 | 48% | `afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_1 | 59.2% | 61 | 257 | 48% | `afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241129_2 | 59.2% | 61 | 257 | 48% | `afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260324_0 | 62.0% | 52 | 190 | 102% | `260324_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241127_0 | 62.7% | 38 | 199 | 100% | `afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_1 | 62.7% | 38 | 199 | 100% | `afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241127_2 | 62.7% | 38 | 199 | 100% | `afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` |
| afm17372_241206_0 | 63.9% | 15 | 197 | 88% | `afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1 | 63.9% | 15 | 197 | 88% | `afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_0 | 65.2% | 66 | 212 | 66% | `afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_1 | 65.2% | 66 | 212 | 66% | `afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241202_2 | 65.2% | 66 | 212 | 66% | `afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241212 | 66.0% | 58 | 176 | 102% | `afm17372_241212_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_0 | 68.3% | 299 | 1122 | 75% | `afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_1 | 68.3% | 299 | 1122 | 75% | `afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_2 | 68.3% | 299 | 1122 | 75% | `afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241031_3 | 68.3% | 299 | 1122 | 75% | `afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_0 | 69.3% | 12 | 114 | 102% | `merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1 | 69.3% | 12 | 114 | 102% | `merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2 | 69.3% | 12 | 114 | 102% | `merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_0 | 70.7% | 46 | 219 | 88% | `afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_1 | 70.7% | 46 | 219 | 88% | `afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241125_2 | 70.7% | 46 | 219 | 88% | `afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_0 | 71.2% | 117 | 799 | 79% | `afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_1 | 71.2% | 117 | 799 | 79% | `afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241030_2 | 71.2% | 117 | 799 | 79% | `afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241209 | 73.7% | 28 | 292 | 75% | `optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01 | 73.7% | 28 | 292 | 75% | `optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17313_241029_0 | 75.3% | 79 | 314 | 95% | `afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_1 | 75.3% | 79 | 314 | 95% | `afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_2 | 75.3% | 79 | 314 | 95% | `afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17313_241029_3 | 75.3% | 79 | 314 | 95% | `afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` |
| afm17372_241206_0 | 76.6% | 4 | 110 | 95% | `histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1 | 76.6% | 4 | 110 | 95% | `histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241209 | 79.6% | 40 | 384 | 92% | `afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm17372_241209_01 | 79.6% | 40 | 384 | 92% | `afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` |
| afm18367_260320_0 | 79.7% | 26 | 138 | 77% | `260320_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241210 | 82.5% | 28 | 287 | 103% | `afm17372_241210_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0 | 87.7% | 3 | 36 | 11% | `test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_0_hdbscan | 87.7% | 3 | 36 | 11% | `test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1 | 87.7% | 3 | 36 | 11% | `test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18367_260317_1_hdbscan | 87.7% | 3 | 36 | 11% | `test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260317_0 | 88.0% | 35 | 209 | 73% | `260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260317_0_all_sites | 88.0% | 35 | 209 | 73% | `260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_0 | 90.3% | 19 | 191 | 75% | `shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17372_241206_1 | 90.3% | 19 | 191 | 75% | `shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm18349_260320_0 | 90.4% | 18 | 259 | 78% | `260320_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` |
| afm17307_241024 | 91.8% | 12 | 220 | 87% | `afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` |
