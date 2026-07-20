# Desync forensic — clean permutation vs compounded

For each corrupted `_jrc.mat`: CLEAN = whole cluster merely renumbered (grouping preserved); PARTIAL = one cluster split across cache entries; MIXED = a cache entry holds >1 viClu label (grouping genuinely altered/compounded). `sciPreserved` = spikes in CLEAN entries / cached spikes. `cover` <100% means the cache is subsampled (completeness test is then conservative).

| file | nClu | clean | partial | mixed | sciPreserved | cover | cleanPerm |
|---|---|---|---|---|---|---|---|
| `afm17307_241024_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | 220 | 201 | 7 | 12 | 91.8% | 86.8% | 0 |
| `afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | 799 | 659 | 23 | 117 | 71.2% | 78.7% | 0 |
| `merged_afm17307_241030_hunting_pups_escape_g0_tcat.imec0.ap_IRC_jrc.mat` | 114 | 83 | 19 | 12 | 69.3% | 102.2% | 0 |
| `afm17307_241031_hunting_pups_escape2_g0_tcat.imec0.ap_IRC_jrc.mat` | 1122 | 774 | 49 | 299 | 68.3% | 74.8% | 0 |
| `afm17313_241029_hunting_pups_escape_g0_tcat.imec0.ap_IRC_PAG_jrc.mat` | 314 | 225 | 10 | 79 | 75.3% | 95.3% | 0 |
| `afm17372_241125_g0_tcat.imec0.ap_IRC_jrc.mat` | 219 | 159 | 14 | 46 | 70.7% | 88.0% | 0 |
| `afm17372_241127_g0_tcat.imec0.ap_shortlist_IRC_jrc.mat` | 199 | 149 | 12 | 38 | 62.7% | 99.9% | 0 |
| `afm17372_20241129_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 257 | 188 | 8 | 61 | 59.2% | 47.7% | 0 |
| `afm17372_241202_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 212 | 142 | 4 | 66 | 65.2% | 65.9% | 0 |
| `afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 197 | 113 | 69 | 15 | 63.9% | 88.5% | 0 |
| `histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 110 | 100 | 6 | 4 | 76.6% | 94.9% | 0 |
| `shortwaves_histo_afm17372_241206_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 191 | 168 | 4 | 19 | 90.3% | 75.4% | 0 |
| `afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` | 384 | 270 | 74 | 40 | 79.6% | 92.1% | 0 |
| `optimized_afm17372_241209_0_g0_tcat.imec0.ap_irc_jrc.mat` | 292 | 227 | 37 | 28 | 73.7% | 75.4% | 0 |
| `afm17372_241210_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 287 | 259 | 0 | 28 | 82.5% | 103.4% | 0 |
| `afm17372_241212_0_g0_tcat.imec0.ap_IRC_jrc.mat` | 176 | 118 | 0 | 58 | 66.0% | 102.5% | 0 |
| `afm17372_241213_0_g0_tcat.imec0.lf_shortlist_IRC_jrc.mat` | 181 | 102 | 4 | 75 | 54.3% | 105.1% | 0 |
| `260317_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | 209 | 172 | 2 | 35 | 88.0% | 72.8% | 0 |
| `test260317_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` | 36 | 32 | 1 | 3 | 87.7% | 10.7% | 0 |
| `260320_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | 259 | 231 | 10 | 18 | 90.4% | 78.3% | 0 |
| `260320_afm18367_g0_tcat.imec0.ap_IRC_jrc.mat` | 138 | 104 | 8 | 26 | 79.7% | 76.9% | 0 |
| `260324_afm18349_g0_tcat.imec0.ap_IRC_jrc.mat` | 190 | 135 | 3 | 52 | 62.0% | 101.9% | 0 |
