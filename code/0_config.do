/*==============================================================================
  0_config.do

  Purpose: Shared setup sourced by the analysis do-files (`include 0_config.do').
           Defines every path global and the reusable programs.  Contains no
           analysis and writes nothing -- safe to re-include at any point.

  Programs defined here:
    reshapeBFS          raw BFS monthly CSV -> indexed/smoothed panel
    makeMA              MA + index transforms for a single time series
    btosRecodeSector    2-digit NAICS code -> sector name
    labelSector         BLS/FRED sector code (NAICS54, NAICSMNF, ...) -> name
    lowecaseVars        lower-case every variable name in memory
    btosCollectTimeCols name BTOS's auto-named biweekly response columns
    btosMakeLong        wide BTOS sheet -> long panel keyed on (byvar, q, date)
    esttabExcel         write an esttab regression table to a real .xlsx sheet

  NOTE: paths are relative to c(pwd), so callers must run from code/.
==============================================================================*/

* --- Paths ---
global base_dir "`c(pwd)'/../"
global raw_data "$base_dir/data/raw/"
global prcd_data "$base_dir/data/processed/"
global output "$base_dir/output"
global fig "$output/figures/"
global raw_bfs "$raw_data/bfs/"
global raw_bds "$raw_data/bds/"
global raw_bed "$raw_data/bed/"
global raw_cps "$raw_data/cps/"
global raw_btos "$raw_data/btos/"
global raw_nes "$raw_data/nes/"
global raw_def "$raw_data/deflators/"
global raw_xwlk "$raw_data/crosswalks/"
global raw_oews "$raw_data/oews/"
global raw_aiexp "$raw_data/ai_exposure/"
global prcd_fl "$prcd_data/formations/"

* set random seed
set seed 20260831

* IPUMS CPS extract in use.  Bump this when a new extract is pulled; the
* extract number encodes the variable list, so an older file may not carry
* every variable the analysis expects (e.g. paidemp1, mish, occ2010).
global cpsfile "cps_00029.dta"

* --- Macros ---
capture program drop reshapeBFS
program define reshapeBFS
    * reshapeBFS: turn a raw BFS monthly CSV into an analysis-ready panel.
    *   Input rows  : one per (sa, naics_sector, series, geo, year) with 12 month
    *                 columns jan..dec.
    *   Output      : a panel of (sa, geo, naics) over monthly date ym, with one
    *                 column per BFS series code, plus for each series:
    *                   ma_*    = 6-month trailing moving average
    *                   i_*     = series indexed so Jan-2019 = 100
    *                   i_ma_*  = the moving average, indexed to Jan-2019 = 100
    *                   ma_i_*  = moving average of the index
    *   BFS series codes used downstream:
    *     ba_ba  all business applications      ba_hba high-propensity applications
    *     ba_wba applications w/ planned wages  ba_cba applications from corporations
    *     bf_bf4q/8q  business formations within 4/8 quarters (actual)
    *     bf_pbf4q/8q projected formations      bf_sbf4q/8q spliced formations
    *     bf_dur4q/8q avg quarters from application to formation
    set type double
    * 1) Months (jan..dec) -> long, numbered 1-12 so reshape can use them
    local i = 0
    foreach m in jan feb mar apr may jun jul aug sep oct nov dec {
        local ++i
        rename `m' val`i'
    }
    reshape long val, i(sa naics_sector series geo year) j(month)

    * 2) Series -> wide: one column per BFS series code
    * valid var-name suffixes
    replace series = lower(series)               
    reshape wide val, i(sa naics_sector geo year month) j(series) string

    * tidy: strip the "val" stub off the new series columns
    foreach v of varlist val* {
        rename `v' `=subinstr("`v'", "val", "", 1)'
    }

    * rename key to match your spec and order/sort the panel
    rename naics_sector naics
    order  year month sa geo naics
    sort   sa geo naics year month

    gen ym = ym(year,month)
    format ym %tm
    egen panel = group(sa geo naics)
    tsset panel ym 
    * For each BFS series: 6-month trailing MA (window(5 1) = 5 lags + current),
    * a Jan-2019=100 index (t2 = the panel's 2019m1 value), an indexed MA, and
    * the MA of the index; then blank the first 5 months where the trailing
    * window is not yet full (missing L5).
    foreach v in ba_ba ba_cba ba_hba ba_wba bf_bf4q bf_bf8q bf_dur4q bf_dur8q bf_pbf4q bf_pbf8q bf_sbf4q bf_sbf8q {
        destring `v', replace force
        tssmooth ma ma_`v' = `v', window(5 1)
        replace ma_`v' = . if missing(`v')
        gen t1 = `v' if year == 2019 & month == 1
        bys panel: egen t2 = mean(t1)
        gen i_`v' = (`v' / t2) * 100
        drop t1 t2 
        gen t1 = ma_`v' if year == 2019 & month == 1
        bys panel: egen t2 = mean(t1)
        gen i_ma_`v' = (ma_`v' / t2) * 100
        drop t1 t2
        tssmooth ma ma_i_`v' = i_`v', window(5 1)
        * Blank the leading months where the trailing window is not yet full:
        * tssmooth silently averages over whatever it has, which would otherwise
        * show up as a real (but shorter-window) value at the start of the panel.
        * Unlike makeMA there is no year<2026 escape hatch here.
        foreach j in ma_`v' i_ma_`v' ma_i_`v' {
            replace `j' = . if missing(L5.`v') | missing(`v')
        }
    }
end

capture program drop btosRecodeSector 
program define btosRecodeSector
    * Map a 2-digit NAICS sector code in variable `in' to full sector names in
    * a new variable `out' (e.g. "11" -> "Agriculture", "XX" -> multi-sector).
    args in out
    gen `out' = "Agriculture" if `in' == "11"
    replace `out' = "Mining, Quarrying, and Oil and Gas Extraction" if `in' == "21"
    replace `out' = "Utilities" if `in' == "22"
    replace `out' = "Construction" if `in' == "23"
    replace `out' = "Manufacturing" if `in' == "31"
    replace `out' = "Wholesale Trade" if `in' == "42"
    replace `out' = "Retail Trade" if `in' == "44"
    replace `out' = "Transportation and Warehousing" if `in' == "48"
    replace `out' = "Information" if `in' == "51"
    replace `out' = "Finance and Insurance" if `in' == "52"
    replace `out' = "Real Estate and Rental and Leasing" if `in' == "53"
    replace `out' = "Professional, Scientific, and Technical Services" if `in' == "54"
    replace `out' = "Management of Companies and Enterprises" if `in' == "55"
    replace `out' = "Administrative and Support and Waste Management and Remediation Services" if `in' == "56"
    replace `out' = "Educational Services" if `in' == "61"
    replace `out' = "Health Care and Social Assistance" if `in' == "62"
    replace `out' = "Arts, Entertainment, and Recreation" if `in' == "71"
    replace `out' = "Accommodation and Food Services" if `in' == "72"
    replace `out' = "Other Services (except Public Administration)" if `in' == "81"
    replace `out' = "Multi-unit companies operating in multiple sectors" if `in' == "XX"
end

capture program drop labelSector 
program define labelSector
    * Map BLS/FRED-style sector codes in `in' (NAICS11, NAICSMNF, NAICSRET, ...)
    * to full sector names in a new variable `out'.
    args in out
    gen `out' = "Agriculture" if `in' == "NAICS11"
    replace `out' = "Mining, Quarrying, and Oil and Gas Extraction" if `in' == "NAICS21"
    replace `out' = "Utilities" if `in' == "NAICS22"
    replace `out' = "Construction" if `in' == "NAICS23"
    replace `out' = "Manufacturing" if `in' == "NAICSMNF"
    replace `out' = "Wholesale Trade" if `in' == "NAICS42"
    replace `out' = "Retail Trade" if `in' == "NAICSRET"
    replace `out' = "Transportation and Warehousing" if `in' == "NAICSTW"
    replace `out' = "Information" if `in' == "NAICS51"
    replace `out' = "Finance and Insurance" if `in' == "NAICS52"
    replace `out' = "Real Estate and Rental and Leasing" if `in' == "NAICS53"
    replace `out' = "Professional, Scientific, and Technical Services" if `in' == "NAICS54"
    replace `out' = "Management of Companies and Enterprises" if `in' == "NAICS55"
    replace `out' = "Administrative and Support and Waste Management and Remediation Services" if `in' == "NAICS56"
    replace `out' = "Educational Services" if `in' == "NAICS61"
    replace `out' = "Health Care and Social Assistance" if `in' == "NAICS62"
    replace `out' = "Arts, Entertainment, and Recreation" if `in' == "NAICS71"
    replace `out' = "Accommodation and Food Services" if `in' == "NAICS72"
    replace `out' = "Other Services (except Public Administration)" if `in' == "NAICS81"
end

capture program drop lowecaseVars 
program define lowecaseVars
    * Rename every variable in memory to its lower-case form.
    * convers all variable names to lower case
    qui desc, varlist
    foreach v of varlist `r(varlist)' {
        local newname = lower("`v'")
        rename `v' `newname'
    }
end

capture program drop btosCollectTimeCols
program define btosCollectTimeCols
    * BTOS response waves import as short, auto-named columns (<=2 chars), one
    * per biweekly period. This stringifies the id vars, gathers those short
    * columns, and renames them to d<year><biweek> (zero-padded) by walking from
    * the last column (fixed anchor = 2023 biweek 19) and advancing the biweek,
    * rolling to the next year after biweek 26. Also blanks "." placeholders.
    * converts btos ID variables to strings
    foreach v of varlist questionid answerid {
        tostring `v', replace
    }
    * Walk the columns BACKWARDS from a fixed anchor: the last time column is
    * always biweek 2023-19 in this vintage.  A vintage that adds or drops
    * leading columns shifts every date, so re-check the anchor on new data.
    local year = 2023
    local biweek = 19
    * figure out the time columns
    * collect the time var cols
    local timeCols = ""
    qui desc, varlist
    foreach v of varlist `r(varlist)' {
        if strlen("`v'")<=2 {
            local timeCols = "`timeCols'" + " `v'"
        }
    }
    local nvars : word count `timeCols'
    forvalues i = `nvars'(-1)1 {
        * get the variable name from the list
        local var : word `i' of `timeCols'
        * build padded biweek string (01–26)
        local bistr = string(`biweek', "%02.0f")
        * build new name
        local newname = "d`year'`bistr'"
        * rename the variable
        rename `var' `newname'
        * replace periods 
        replace `newname' = "" if `newname'=="."
        * increment biweek
        local biweek = `biweek' + 1
        if `biweek' > 26 {
            local biweek = 1
            local year = `year' + 1
        }
    }
end

capture program drop btosMakeLong
program define btosMakeLong
    * Reshape a wide BTOS sheet to long, keyed by (byvars, questionid, date),
    * with one column per answer id (d1, d2, ...). `byvars' is the sheet's
    * grouping var (e.g. sector/subsector). Flow: pull collection start dates
    * from National.xlsx; pack (answerid|questionid|byvars) into one string key
    * and reshape long over the d<date> cols; strip "%" and flag "S"
    * suppressions; reshape wide over answer id; then unpack the key and attach
    * dates (year, biweek, start_date, weekly date wdate).
    args byvars
    * get start dates
    preserve 
        import excel using "$raw_btos/National.xlsx", clear first sheet("Collection and Reference Dates")
        lowecaseVars
        keep smpdt collectionstart
        drop if missing(smpdt)
        * in 20260519 vintage, this is no longer necessary
        *gen start_date = date(collectionstart,"MDY")
        rename collectionstart start_date
        format start_date %tdMon_DD_YY
        rename (smpdt) (date) 
        tostring date, replace
        keep date start_date
        tempfile dates
        save `dates'
    restore
    * now we reshape
    * first long by (answerid,questionid,byvars)-date-response
    * after that we make it wide to get (questionid,byvars)-date-response1-reponse2-...
    destring questionid, replace force
    drop if missing(questionid) 
    tostring questionid, replace
    * reshape takes only one j() variable, so pack the three identifiers into a
    * single pipe-delimited string key and split it back apart afterwards
    gen q_a = answerid+"|"+questionid+"|"+`byvars'
    keep q_a d*
    reshape long d, i(q_a) j(date)
    * clean the % variables
    replace d = subinstr(d,"%","",.)
    * flag suppressions
    gen d_s = d=="S"
    destring d, replace force
    * break the collapsed ids back apart
    split q_a, parse("|")
    destring q_a1, replace
    tostring date, replace 
    * combine questionid and the byvars
    gen panelvar = q_a2 + "|" + q_a3 + "|" + date
    keep panelvar q_a1 d d_s
    rename q_a1 ansid
    reshape wide d d_s, i(panelvar) j(ansid)
    split panelvar, parse("|")
    rename (panelvar1 panelvar2 panelvar3) (questionid byvars date)
    drop panelvar
    order byvars questionid date d*
    * clean up date vars
    merge m:1 date using `dates', nogen keep(1 3)    
    gen strdate = date
    tostring strdate, replace
    gen year = substr(strdate,1,4)
    gen biweek = real(substr(strdate, 5, 2))
    destring year, replace 
    destring biweek, replace
    * Calculate the date as the first day of the given biweekly period
    gen wdate = yw(year(start_date),week(start_date))
    format wdate %tw
    drop date strdate
    order byvars questionid year biweek start_date wdate d*
end

capture program drop makeMA
program define makeMA
    * makeMA: moving-average and index transforms for ONE time series.
    *   Usage : makeMA <var> <window> <base_year> <base_quarter> <base_month>
    *   Creates, for variable `v':
    *     ma_*    = trailing MA over `w' lags + the current period, so window(3 1)
    *               is a 4-quarter MA and window(5 1) a 6-month MA
    *     i_*     = `v' indexed to the base period = 100
    *     i_ma_*  = the MA, indexed to the base period
    *     ma_i_*  = the MA of the index
    *
    * The base period is matched on year & quarter & month TOGETHER, so the data
    * must carry all three.  Callers therefore add the dimension the frequency
    * lacks as a placeholder: quarterly data sets `gen month = 0' and passes
    * i_m == 0; monthly data sets `gen quarter = 0' and passes i_qtr == 0.
    *
    * Two constraints, both inherited from using an unconditional egen mean:
    *   - Assumes ONE series in memory (data are tsset on time alone).  With
    *     several panels loaded, t2 is the pooled mean and every index is wrong;
    *     use the per-panel version inside reshapeBFS instead.
    *   - No guard against a zero or missing base.  Unlike the inline code this
    *     replaced, a series that is 0 in the base period yields a missing index
    *     rather than being skipped, so callers must drop such series first
    *     (see the `drop *util*' in the BED sector block).
    args v w i_yr i_qtr i_m
    tssmooth ma ma_`v' = `v', window(`w' 1)
    replace ma_`v' = . if missing(`v')
    * t1 is non-missing only in the base period, so its mean over the whole
    * dataset IS the base value; t2 then broadcasts it to every row.
    gen t1 = `v' if year == `i_yr' & quarter == `i_qtr' & month == `i_m'
    egen t2 = mean(t1)
    gen i_`v' = (`v' / t2) * 100
    drop t1 t2 
    gen t1 = ma_`v' if year == `i_yr' & quarter == `i_qtr' & month == `i_m'
    egen t2 = mean(t1)
    gen i_ma_`v' = (ma_`v' / t2) * 100
    drop t1 t2
    tssmooth ma ma_i_`v' = i_`v', window(`w' 1)
    replace ma_i_`v' = . if missing(i_`v')
    * remove moving averages for less than the full number of lags
    * restricting to <2026 avoids dropping due to the 2025m10 hole from the shutdown
    * (the government shutdown suspended collection, so L`w' is missing for
    *  otherwise-valid later periods and the MA would be blanked wholesale)
    foreach j in ma_`v' i_ma_`v' ma_i_`v' {
        replace `j' = . if (missing(L`w'.`v') | missing(`v')) & year<2026
    }
end

capture program drop esttabExcel
program define esttabExcel
    * esttabExcel: write an esttab regression table into a real .xlsx sheet.
    *   esttabExcel m1 m2 m3 using "$output/tables/t1.xlsx", sheet("hba") ///
    *       <any esttab option>
    * esttab has no xlsx writer, so this routes through a tab-delimited temp
    * file. Tab, not csv: csv mode wraps every cell as ="..." and splits any
    * note containing a comma across columns.
    syntax anything(name=models) using/, [SHeet(string) *]
    if "`sheet'" == "" local sheet "Table1"
    if strpos("`using'", ".") == 0 local using "`using'.xlsx"
    tempfile stub
    qui esttab `models' using "`stub'.txt", replace tab `options'
    preserve
        * import delimited drops esttab's blank separator lines on the way in
        qui import delimited using "`stub'.txt", clear varnames(nonames) delimiter(tab) stringcols(_all) bindquote(nobind)
        qui export excel using "`using'", sheet("`sheet'", replace)
    restore
    di as result `"wrote `using' [`sheet']"'
end
