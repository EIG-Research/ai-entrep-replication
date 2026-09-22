# AI and Entrepreneurship

Replication code and data for [AI and Entrepreneurship: What is Really Happening?](https://eig.org/ai-and-entrepreneurship/) — a data-driven analysis
of whether new-business formation boomed, stalled, or declined in 2025, and
whether AI has begun to leave a mark on entrepreneurship in the aggregate.

Because no single timely, high-quality source can answer these questions, the
analysis **triangulates** across several administrative and survey datasets. 

The findings suggest:

- Likely employer business applications started rising in 2026, but fewer of them are of the type most likely to hire employees.
- Likely nonemployer applications rose sharply, but they are probably side-gigs since they don’t show up as individuals’ primary source of income.
- AI doesn’t seem to have much to do with any of this beyond the surge of likely nonemployers in the information and professional services sector.

---

## Repository structure

```
.
├── code/                       # analysis pipeline (Python + Stata)
│   ├── 00_download_qwi.py       # download QWI firm-age panels from the Census API
│   ├── 01_reshape_bfs_naics3.py # reshape 3-digit NAICS BFS series wide -> long
│   ├── 02_analysis.do           # build all figures + the Datawrapper workbook
│   └── run_all.sh               # runs steps 01 -> 02 (set STATA/PYTHON paths at top)
├── data/
│   ├── raw/                     # inputs as received (see Data sources below)
│   │   ├── bds/ bed/ bfs/ btos/ cps/ crosswalks/ deflators/ nes/ qwi/
│   │   └── ...
│   └── processed/               # cleaned/derived checkpoints (built by the code)
├── output/
│   ├── figures/                 # finished .png figures
│   ├── tables/
│   └── data_wrapper.xlsx        # one sheet per figure, for publication charts
└── README.md                # this file
```

---

## Data sources

All inputs are **public** but are **not redistributed in this repository** where files are large. The full data package may be downloaded from [Google Drive](https://drive.google.com/drive/folders/1CBiqU-wMVEMJs_i1NwTWBiKs8XW-VO8T?usp=sharing), or obtained from the sources below and placed under `data/raw/<source>/`.

| Dir | Source | Description | Access |
|---|---|---|---|
| `bfs/` | Census **Business Formation Statistics** | Monthly business applications & formations (BA, HBA, WBA, CBA, projected/spliced formations); national, state, county; a 3-digit NAICS series | census.gov/programs-surveys/bfs |
| `bed/` | BLS **Business Employment Dynamics** | Quarterly establishment births/deaths (flat file `bd.data.1.AllItems`) and annual firm births (`age_naics_size_ein` tables) | bls.gov/bdm |
| `cps/` | **Current Population Survey** (IPUMS) | Monthly microdata for self-employment (`classwkr`, `paidemp1`, weighted by `wtfinl`) | cps.ipums.org (extract `cps_00029`, see below) |
| `btos/` | Census **Business Trends and Outlook Survey** | AI-use rates by sector/subsector (Question 7) | census.gov/hfp/btos |
| `bds/` | Census **Business Dynamics Statistics** | MSA × sector employment (2022) for AI-exposure weighting | census.gov/programs-surveys/bds |
| `nes/` | Census **Nonemployer Statistics** | Annual state nonemployer establishment counts (2004–2023) | census.gov/programs-surveys/nonemployer-statistics |
| `qwi/` | Census **Quarterly Workforce Indicators** | State × NAICS × quarter × firm-age panels (see below) | api.census.gov/data/timeseries/qwi/sa |
| `deflators/` | BEA/FRED | `PCEPI.csv` price index for real-dollar conversion | fred.stlouisfed.org/series/PCEPI |
| `crosswalks/` | Census / reference | County↔MSA, state FIPS crosswalks | — |
| `ai_exposure/` | CPS AI exposure measures created by [this repo](https://github.com/EIG-Research/ai-cps-exposure). AI exposure by state-naics from a separate replication of Tucker (2026). | AI exposure measures mapped to CPS occupation codes | - |

### CPS extract (`cps_00029.dta`)

- **Samples** — IPUMS-CPS *Basic Monthly*, `2015-01` through `2026-06`
  (137 monthly samples). The analysis keeps `year >= 2015`, so earlier samples
  are unnecessary; extend the end date as new months are released.
- **Structure** — rectangular on person.
- Save the Stata file to `data/raw/cps/` and point `$cpsfile` in
  `code/0_config.do` at it. The extract number encodes the variable list, so
  bumping the file without checking the variables below will fail at run time.

**Variables the pipeline requires**

| Variable | Used for |
|---|---|
| `YEAR`, `MONTH` | Monthly date `ym`; the pre/post windows in the robustness regressions |
| `MISH` | Month in sample. `PAIDEMP1` is asked only of outgoing rotations, so `MISH 4/8` is the denominator for the employer/non-employer split |
| `WTFINL` | Final basic monthly person weight — every self-employment level and rate is weighted by it |
| `CPSIDP` | Person identifier; used to `tsset` the microdata |
| `AGE` | Sample restriction to ages 16–64 |
| `CLASSWKR` | Self-employment: `13` = self-employed, not incorporated; `14` = self-employed, incorporated |
| `PAIDEMP1` | Employer vs. non-employer split at the main job: `1` = No paid employees (non-employer), `2` = Yes (employer) |
| `OCC` | Occupation on the survey's own coding vintage; merge key for the AI-exposure scores in the CPS figures section |
| `OCC2010` | Occupation on a consistent 2010 basis; merge key for the occ2010 exposure file in the CPS robustness regressions |

IPUMS preselects `YEAR`, `SERIAL`, `MONTH`, `HWTFINL`, `CPSID`, `ASECFLAG`,
`PERNUM`, `WTFINL`, and `CPSIDP`, so they arrive whether or not you tick them.
The variables that must be selected explicitly are therefore **`MISH`, `AGE`,
`CLASSWKR`, `PAIDEMP1`, `OCC`, and `OCC2010`**.

`cps_00029` also carries `CPSIDV`, `SEX`, `EMPSTAT`, `LABFORCE`, `OCC1990`,
`IND`, `IND1990`, `UHRSWORKT`, `UHRSWORK1`, `WKSTAT`, `EMPSAME`, `EDUC`,
`SCHLCOLL`, and `LNKFW1MWT`. None are referenced by `02_analysis.do` — they are
left over from exploration and can be dropped from a rebuilt extract.

**Two things to watch**

- **Occupation coding changes in 2020.** `OCC` is on the 2010 basis through
  2019 and the 2018 basis from 2020 onward. `02_analysis.do` handles this by
  tagging `occ_vintage` and merging against a vintage-aware exposure file; the
  robustness regressions instead merge on `OCC2010` alone, so both variables
  are needed.
- **`PAIDEMP1` is outgoing-rotation only.** Roughly a quarter of the monthly
  sample answers it, which is why the employer/non-employer series are noisier
  than the headline self-employment rate and are blanked over 2020m1–2021m1.

---

### AI-exposure measure (`ai_exposure_state_naics_L{3,4,6}.dta`)

`data/processed/` also contains pre-built state × NAICS AI-exposure files — one
per NAICS aggregation level (3-, 4-, and 6-digit) — used by the QWI section of
`02_analysis.do`. They are a **replication of Tucker (2026, "You're (not)
hired"), Section 2**. They are provided as **inputs** to this project.

Each row is a (state × NAICS) cell:

| Column | Description |
|---|---|
| `statefip` | State FIPS code |
| `naics_2022` | NAICS code (2022 vintage) at the file's aggregation level |
| `beta`, `alpha`, `gamma` | AI-exposure scores; **β is the headline variant** used downstream |
| `acs_emp` | ACS employment in the cell (diagnostic) |
| `qwi_emp_2022` | 2022 QWI beginning-of-quarter employment (the quintile weight) |
| `quintile` | Employment-weighted AI-exposure quintile (1 = least, 5 = most exposed) |

---

## Requirements

**Python 3.9+**

```
pandas
pyarrow        # QWI parquet cache
requests       # Census API
```

**Stata** (tested with StataSE) with the user-contributed package:

```
ssc install reghdfe      # also pulls in ftools
```

(`tssmooth` and `xtile` are built in.)

---

## Setup

The QWI downloader calls the Census API, which requires a free key:

```bash
export CENSUS_API_KEY=...    # https://api.census.gov/data/key_signup.html
```

Without a key the API redirects to a "Missing Key" page and the download fails.

---

## Reproducing the analysis

### 1. Download QWI panels (prerequisite for the QWI section of `02_analysis.do`)

```bash
python code/00_download_qwi.py                 # all levels (L3, L4, L6)
python code/00_download_qwi.py --levels 4      # a single level
python code/00_download_qwi.py --convert-only  # rebuild .dta from cached parquets
```

This pulls state × NAICS × quarter × firm-age panels (1995-Q1 → present),
caches each (state × firm-age) cell as a resumable parquet under
`data/raw/qwi/`, and writes:

```
data/processed/qwi_panel_firmage_L3.dta
data/processed/qwi_panel_firmage_L4.dta
data/processed/qwi_panel_firmage_L6.dta
```

### 2. Run the main pipeline

Open `code/run_all.sh` and set the two paths at the top to match your machine:

```bash
STATA="/Applications/StataNow/StataSE.app/Contents/MacOS/stata-se"   # your Stata executable
PYTHON="/opt/anaconda3/bin/python3"                                  # a Python 3 with pandas
```

Then run it:

```sh ./code/run_all.sh                      # runs 01 (reshape) then 02 (analysis)
```

The script runs from `code/`, stops on the first error, and scans the Stata log
for an `r(###);` error marker (Stata batch mode does not always exit nonzero on
a do-file error).

- **`01_reshape_bfs_naics3.py`** reshapes `data/raw/bfs/naics3.csv` (wide) into
  `data/processed/bfs_naics3_long.csv` (long).
- **`02_analysis.do`** loads each source, indexes/smooths the series, and writes
  every figure to `output/figures/` plus one sheet per figure in
  `output/data_wrapper.xlsx`. It must be run from `code/`; Stata is invoked in batch mode.

---

## Outputs

- `output/figures/*.png` — BFS application series, application→employer
  transition rate, BFS-vs-BED comparison, CPS self-employment, non-employer
  proxies, AI-sector splits, BTOS/AI-exposure scatters, and the data-vintage
  revision comparison.
- `output/data_wrapper.xlsx` — the plotted values, one sheet per figure, for
  building the published Datawrapper charts.

---

## Contact

Economic Innovation Group (EIG) — nathan@eig.org

Data documentation, comments, and runall script built with assistance of Claude. 
