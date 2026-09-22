/*==============================================================================
  02_analysis.do

  Purpose: Build the descriptive figures and the Datawrapper workbook for the
           entrepreneurship analysis. 
           Sources: BFS (business applications/formations), BED (establishment
           & firm births), CPS (self-employment), BTOS (AI use), BDS, NES
           (nonemployer statistics), QWI, and the 3-digit BFS series built in 01.

==============================================================================*/

*--------------------------------------------------
* PROGRAM SETUP
*--------------------------------------------------
capture log close
set more off
set linesize 80
set type double
local dt = "`c(current_date)' `c(current_time)'"
local dt = subinstr("`dt'", ":", "", .)
local dt = subinstr("`dt'", " ", "", .)
log using "02_analysis_`dt'.log", replace
di c(current_date) " " c(current_time)

* --- Paths & Macros ---
* 0_config.do holds every path global plus the shared programs used below:
* reshapeBFS, makeMA, esttabExcel, lowecaseVars, btos*/labelSector recodes.
include 0_config.do 


*==============================================================================
* BFS Series
*==============================================================================
* National, seasonally-adjusted, all-industry BFS applications indexed to
* 2019m1=100. Builds bfs_ba_compare_p1..p3.png (progressively adding HBA, WBA,
* CBA and spliced formations) and the "bfs_series" datawrapper sheet.

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
keep if year>=2015 

#delimit;
    tw 
    (line i_ma_ba_ba ym, lcolor(black) lpat(solid) lw(.5)) 
    (line i_ma_ba_hba ym, lcolor(stc1) lpat(solid) lw(.5)) 
    , 
    legend(order(1 "BFS: BA" 2 "HBA" ) pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(`=monthly("2019m1", "YM")', lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
    yline(100, lcolor(gs8) lpat(solid))
    ylab(80(20)180)
;
#delimit cr
graph export "$fig/bfs_ba_compare_p1.png", replace width(2000)

#delimit;
    tw 
    (line i_ma_ba_ba ym, lcolor(black) lpat(solid) lw(.5)) 
    (line i_ma_ba_hba ym, lcolor(stc1%30) lpat(solid) lw(.5)) 
    (line i_ma_ba_wba ym, lcolor(stc2) lpat(solid) lw(.5)) 
    (line i_ma_ba_cba ym, lcolor(stc3) lpat(solid) lw(.5)) 
    , 
    legend(order(1 "BFS: BA" 2 "HBA" 3 "WBA" 4 "CBA") pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(`=monthly("2019m1", "YM")', lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
    yline(100, lcolor(gs8) lpat(solid))
    ylab(80(20)180)
;
#delimit cr
graph export "$fig/bfs_ba_compare_p2.png", replace width(2000)

#delimit;
    tw 
    (line i_ma_ba_ba ym, lcolor(black) lpat(solid) lw(.5)) 
    (line i_ma_ba_hba ym, lcolor(stc1%30) lpat(solid) lw(.5)) 
    (line i_ma_ba_wba ym, lcolor(stc2%30) lpat(solid) lw(.5)) 
    (line i_ma_ba_cba ym, lcolor(stc3%30) lpat(solid) lw(.5)) 
    (line i_ma_bf_sbf8q ym, lcolor(stc4) lpat(solid) lw(.5)) 
    , 
    legend(order(1 "BFS: BA" 2 "HBA" 3 "WBA" 4 "CBA" 5 "SBF8Q") pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(`=monthly("2019m1", "YM")', lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
    yline(100, lcolor(gs8) lpat(solid))
    ylab(80(20)180)
;
#delimit cr
graph export "$fig/bfs_ba_compare_p3.png", replace width(2000)

* create year-month variable for datawrapper
drop ym
tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym = year + "-" + month 
keep ym i_ma_ba_hba i_ma_ba_wba i_ma_ba_cba i_ma_bf_sbf8q
export excel using "$output/data_wrapper.xlsx", sheet("bfs_series") firstrow(variables) replace

*==============================================================================
* BFS Transition Rate
*==============================================================================
* Share of applications that become employer businesses within 4 quarters
* (bf_bf4q / ba_ba). Restricted to 2015-2021 so every cohort is fully observed.
* Builds bfs_transition_rate.png.

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
keep if year>=2015 & year<=2021
* r = % of applications that turned into employer businesses within 4 quarters
gen r = 100* bf_bf4q/ba_ba
#delimit;
    tw 
    (line r ym, lcolor(black) lpat(solid) lw(.5))
    ,
    ytitle("Percent of Applications""Becoming Employer Businesses")
    xtitle(" ")
    xline(708, lcolor(gs8) lpat(solid))
    yline(100, lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2022m1", "YM")', angle(45))
;
#delimit cr
graph export "$fig/bfs_transition_rate.png", replace width(2000)

*==============================================================================
* BFS Fix
*==============================================================================
* Compare the current BFS vintage against the Nov-2025 legacy vintage for HBA,
* to show the effect of the data revision. Loads the legacy file, tags its
* series with _old, and merges onto the current file by month.
* Builds bfs_legacy_compare.png and the "bfs_hba_legacy" sheet.

import delimited using "$raw_bfs/bfs_monthly_202511.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
keep ym ba_ba ba_cba ba_hba ba_wba bf_sbf8q 
foreach v in ba_ba ba_cba ba_hba ba_wba bf_sbf8q  {
    rename `v' `v'_old
}
tempfile bfsold
save `bfsold'

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
merge 1:1 ym using `bfsold', keep(1 3) nogen
keep if year>=2015

#delimit;
    tw 
    (line ba_hba ym, lcolor(stc1) lpat(solid) lw(.5))
    (line ba_hba_old ym, lcolor(stc2) lpat(solid) lw(.5))
    ,
    ytitle("Applications")
    xtitle(" ")
    xline(708, lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
    legend(order(1 "Latest HBA" 2 "Legacy (Nov 2025) HBA") pos(6) col(2))
;
#delimit cr
graph export "$fig/bfs_legacy_compare.png", replace width(2000)

* create year-month variable for datawrapper
tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym_str = year + "-" + month 
keep ym_str ba_hba ba_hba_old
export excel using "$output/data_wrapper.xlsx", sheet("bfs_hba_legacy") firstrow(variables) 

*==============================================================================
* BFS-BED Comparison
*==============================================================================
* Put BFS applications on the same quarterly, 2019q1=100 footing as BED
* establishment births and BED annual firm births, and plot them together
* (bfs_bed.png, "bfs_bed" sheet). Assembles three inputs: BED estab measures
* from the flat file, BED firm births from the t3 xlsx, and quarterly BFS.

* --- Load the tab-delimited flat file (~4.5M rows) ---
import delimited "$raw_bed/bd.data.1.AllItems", delimiter(tab) varnames(1) stringcols(_all) clear

* --- Parse fixed-width series_id components (1-based positions) ---
gen seasonal = substr(series_id, 3, 1)
gen state    = substr(series_id, 9, 2)
gen industry = substr(series_id, 14, 6)
* dataelement (2 = establishments)
gen delem    = substr(series_id, 21, 1)     
gen sizecls  = substr(series_id, 22, 2)
gen dataclass = substr(series_id, 24, 2)
* L = level, R = rate
gen ratelevel = substr(series_id, 26, 1) 

* --- Filter: national, SA, all sizes, total private, establishments ---
keep if seasonal=="S" & state=="00" & sizecls=="00" & delem=="2" & industry=="000000"
keep if substr(period,1,1)=="Q"

* --- Types ---
destring year, replace
destring value, replace force
* "Q03" -> 3
gen quarter = real(substr(period, 2, .))  

* --- Map (dataclass, ratelevel) -> output column name ---
gen measure = ""
replace measure = "bed_estabs_births"        if dataclass=="07" & ratelevel=="L"
replace measure = "bed_estabs_deaths"        if dataclass=="08" & ratelevel=="L"
replace measure = "bed_estabs_openings"      if dataclass=="03" & ratelevel=="L"
replace measure = "bed_estabs_closings"      if dataclass=="06" & ratelevel=="L"
replace measure = "bed_estabs_births_rate"   if dataclass=="07" & ratelevel=="R"
replace measure = "bed_estabs_deaths_rate"   if dataclass=="08" & ratelevel=="R"
replace measure = "bed_estabs_openings_rate" if dataclass=="03" & ratelevel=="R"
replace measure = "bed_estabs_closings_rate" if dataclass=="06" & ratelevel=="R"
drop if measure==""

* --- Levels are published in thousands -> convert to units ---
replace value = value*1000 if ratelevel=="L"

* --- Long -> wide: one column per measure, keyed by year-quarter ---
keep year quarter measure value
reshape wide value, i(year quarter) j(measure) string
foreach v of varlist value* {
    rename `v' `=subinstr("`v'", "value", "", 1)'
}
sort year quarter
gen yq = yq(year,quarter)
tempfile bed
save `bed'

*--------------------------------------------------------------
* BED t3 xlsx -> annual firm births (firms < 1 year old, all
* sizes, total private), assigned to Q1. Reproduces the
* bed_firm_births column in combined_quarterly.csv.
*--------------------------------------------------------------
* "Less than one year old / All sizes" block: A=year, B=Total Firms,
* data rows 279-310 (years 1994-2025) on the Total Private sheet.
import excel "$raw_bed/age_naics_size_ein_20251_t3.xlsx", sheet("Total Private") cellrange(A279:B310) clear
rename (A B) (year bed_firm_births)

* Strip thousands separators; "_" (n/a) and "N" (nondisclosure) -> missing.
replace bed_firm_births = subinstr(bed_firm_births, ",", "", .)
destring bed_firm_births, replace force
capture confirm string variable year
if !_rc destring year, replace
* BED firm data is annual -> assigned to Q1
gen quarter = 1
keep year quarter bed_firm_births
order year quarter bed_firm_births
sort year
gen yq = yq(year,quarter)
tempfile bedfbirths
save `bedfbirths'

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
gen quarter = quarter(dofm(ym))
gen yq = yq(year,quarter)
* Aggregate monthly BFS to quarterly totals, then attach the two BED tempfiles.
collapse (sum) ba_hba ba_wba, by(yq)
drop if yq>`=quarterly("2026q1", "YQ")'
merge 1:1 yq using `bed', keep(1 3) nogen
merge 1:1 yq using `bedfbirths', keep(1 3) nogen
format yq %tq
tsset yq
* makeMA v window base_year base_quarter base_month -> ma_/i_/i_ma_/ma_i_ series.
* It matches the base period on year & quarter & month, so quarterly data needs a
* placeholder month==0 (and monthly data a placeholder quarter==0) for the match
* to hit.  window 3 = 3 lags + current = 4-quarter trailing MA, 2019q1 = 100.
gen month = 0
foreach v in ba_hba ba_wba bed_estabs_births bed_firm_births {
    makeMA `v' 3 2019 1 0 
}
drop month
* Rebuild year from yq: it had come only from the merged BED files, so it was
* missing for BFS-only quarters. Do this before the year>=2015 filter.
drop year
gen year=year(dofq(yq))
keep if year>=2015

#delimit;
    tw 
    (line i_ma_ba_hba yq, lcolor(black%30) lpat(solid) lw(.5)) 
    (line i_ma_ba_wba yq, lcolor(stc2%30) lpat(solid) lw(.5)) 
    (line i_bed_firm_births yq, lcolor(stc6) lpat(solid) lw(.5))
    (line i_ma_bed_estabs_births yq, lcolor(stc6) lpat(dash) lw(.5))  
    , 
    legend(order(1 "BFS: HBA" 2 "WBA" 3 "BED: Firm Births" 4 "Estab Births") pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(`=quarterly("2019q1", "YQ")', lcolor(gs8) lpat(solid))
    xlab(`=quarterly("2015q1", "YQ")'(12)`=quarterly("2025q1", "YQ")', angle(45))
    yline(100, lcolor(gs8) lpat(solid))
;
#delimit cr
graph export "$fig/bfs_bed.png", replace width(2000)

* date formats for datawrapper
drop year quarter
gen year = year(dofq(yq))
gen quarter = quarter(dofq(yq))
tostring year, replace
tostring quarter, replace force
gen yq_str = year + "-Q" + quarter
keep yq_str i_ma_ba_hba i_ma_ba_wba i_bed_firm_births i_ma_bed_estabs_births
export excel using "$output/data_wrapper.xlsx", sheet("bfs_bed") firstrow(variables) 

*==============================================================================
* CPS FIGURES
*==============================================================================
* Self-employment rates from CPS microdata (ages 16-64, weighted by wtfinl),
* indexed to 2019m1=100. classwkr 13/14 = self-employed; paidemp 1/2 splits
* self-employment into non-employer vs employer (that question is asked only in
* outgoing rotations, mish 4/8). The 2020m1-2021m1 pandemic window is blanked
* for the emp/non-emp split. Builds cps_selfemp*.png and the cps_selfemp_* sheets.

use "$raw_cps/$cpsfile", clear
di "CPS monthly loaded: `=_N' observations"
* IPUMS `occ' switches coding schemes in 2020: occ2010 before, occ2018 after.
* ai_exposure_cps.dta is keyed on (vintage, occ) and carries both, so tagging the
* vintage lets one merge attach exposure scores across the whole sample -- this
* replaces the earlier in-line occ2010->occ2018 probabilistic crosswalk.
gen occ_vintage = cond(year >= 2020, 2018, 2010)
merge m:1 occ_vintage occ using $raw_aiexp/ai_exposure_cps.dta
*merge m:1 occ2010 using "$raw_aiexp/ai_exposure_occ2010.dta", keep(master match)
* diagnostic: unmatched masters are mostly NIU/blank occ codes
tab _merge
drop _merge
* time vars
gen ym = ym(year,month)
format ym %tm
gen quarter = quarter(dofm(ym))
gen yq = yq(year,quarter)
format yq %tq
tsset cpsidp ym 
* keep by age
keep if age >=16 & age <=64
* process AI vars
* gpt4_beta_q = prebuilt quintile of the GPT-4 occupational exposure score
* (1 = least exposed).  ai_exp_gt4 pools the top two quintiles despite the name.
gen ai_exp_q5 = gpt4_beta_q
gen ai_exp_gt4 = gpt4_beta_q>=4 if !missing(gpt4_beta_q)
* Weighted self-employment numerators and denominators:
*   selfemp           = all self-employed (classwkr 13/14)
*   selfemp_denom     = all persons 16-64
*   selfemp_ne / _e   = non-employer / employer self-employed (paidemp 1/2)
*   selfemp_ene_denom = denominator for the emp/non-emp split (mish 4/8 only)
gen selfemp = wtfinl if classwkr==13 | classwkr==14
gen selfemp_denom = wtfinl
gen selfemp_ne = wtfinl if (classwkr==13 | classwkr==14) & (paidemp1==1)
gen selfemp_e = wtfinl if (classwkr==13 | classwkr==14) & (paidemp1==2)
gen selfemp_ene_denom = wtfinl if mish==4 | mish==8
tempfile cpsxtract
save `cpsxtract'

use `cpsxtract', clear
collapse (sum) selfemp*, by(ym)
* Blank the emp/non-emp split over the pandemic window (2020m1-2021m1): the
* small outgoing-rotation subsample makes it too noisy to trust there.
foreach v in selfemp_ne selfemp_e selfemp_ene_denom {
    replace `v' = . if ym>=`=monthly("2020m1", "YM")' & ym<=`=monthly("2021m1", "YM")'
}
gen r_self_emp  = 100*selfemp/selfemp_denom
gen r_self_emp_ne  = 100*selfemp_ne/selfemp_ene_denom
gen r_self_emp_e  = 100*selfemp_e/selfemp_ene_denom
gen eshr = selfemp_e/(selfemp_e+ selfemp_ne)
gen neshr = selfemp_ne/(selfemp_e+ selfemp_ne)
tsset ym 
gen year = year(dofm(ym))
gen month = month(dofm(ym))
* placeholder quarter for makeMA's base-period match; window 5 = 6-month
* trailing MA, indexed to 2019m1 = 100
gen quarter = 0
foreach v in selfemp selfemp_denom selfemp_ne selfemp_e selfemp_ene_denom r_self_emp r_self_emp_e r_self_emp_ne {
    makeMA `v' 5 2019 0 1
}
drop quarter 
tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym_str = year + "-" + month 

* Datawrapper sheets now carry the self-employment RATE (percent) and its
* 6-month MA rather than the 2019m1 = 100 index.
preserve
    keep ym_str r_self_emp_e ma_r_self_emp_e
    export excel using "$output/data_wrapper.xlsx", sheet("cps_selfemp_emp") firstrow(variables) 
restore 
preserve
    keep ym_str r_self_emp_ne ma_r_self_emp_ne
    export excel using "$output/data_wrapper.xlsx", sheet("cps_selfemp_nemp") firstrow(variables) 
restore 

#delimit;
    tw 
    (scatter r_self_emp ym, mcolor(stc1) msymb(Oh) lpat(solid) )
    (line ma_r_self_emp ym, mcolor(stc1) msymb(Oh) lpat(solid) connect(1))
    , 
    legend(off)
    ytitle(" Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp.png", replace width(2000)

#delimit;
    tw 
    (scatter r_self_emp_e ym, mcolor(stc1) msymb(Oh) lpat(solid) )
    (line ma_r_self_emp_e ym if ym<`=monthly("2020m1", "YM")', lcolor(stc1) lw(.5))
    (line ma_r_self_emp_e ym if ym>`=monthly("2021m1", "YM")', lcolor(stc1) msymb(Oh) lw(.5))
    , 
    legend(off)
    ytitle("Employer Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp_e.png", replace width(2000)

#delimit;
    tw 
    (scatter r_self_emp_ne ym, mcolor(stc1) msymb(Oh) lpat(solid) )
    (line ma_r_self_emp_ne ym if ym<`=monthly("2020m1", "YM")', lcolor(stc1) lw(.5))
    (line ma_r_self_emp_ne ym if ym>`=monthly("2021m1", "YM")', lcolor(stc1) msymb(Oh) lw(.5))
    , 
    legend(off)
    ytitle("Non-Employer Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp_ne.png", replace width(2000)

use `cpsxtract', clear
drop if missing(ai_exp_gt4)
collapse (sum) selfemp*, by(ym ai_exp_gt4)
reshape wide self*, i(ym) j(ai_exp_gt4)
* Blank the emp/non-emp split over the pandemic window (2020m1-2021m1): the
* small outgoing-rotation subsample makes it too noisy to trust there.
foreach i of numlist 0(1)1 {
    foreach v in selfemp_ne`i' selfemp_e`i' selfemp_ene_denom`i' {
        replace `v' = . if ym>=`=monthly("2020m1", "YM")' & ym<=`=monthly("2021m1", "YM")'
    }
}
foreach i of numlist 0(1)1 {
    gen r_self_emp`i'  = 100*selfemp`i'/selfemp_denom`i'
    gen r_self_emp_ne`i'  = 100*selfemp_ne`i'/selfemp_ene_denom`i'
    gen r_self_emp_e`i'  = 100*selfemp_e`i'/selfemp_ene_denom`i'
    gen eshr`i' = selfemp_e`i'/(selfemp_e`i'+ selfemp_ne`i')
    gen neshr`i' = selfemp_ne`i'/(selfemp_e`i'+ selfemp_ne`i')
}
tsset ym 
gen year = year(dofm(ym))
gen month = month(dofm(ym))
* placeholder quarter for makeMA; 6-month trailing MA, 2019m1 = 100, run
* separately for the low- (0) and high- (1) AI-exposure suffixed series
gen quarter = 0
foreach i of numlist 0(1)1 {
    foreach v in selfemp`i' selfemp_denom`i' selfemp_ne`i' selfemp_e`i' selfemp_ene_denom`i' r_self_emp`i' r_self_emp_e`i' r_self_emp_ne`i' {
        makeMA `v' 5 2019 0 1
    }
}
drop quarter 
tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym_str = year + "-" + month 

#delimit;
    tw 
    (line ma_r_self_emp0 ym, mcolor(stc1) msymb(Oh) lpat(solid) connect(1))
    (line ma_r_self_emp1 ym, mcolor(stc1) msymb(Oh) lpat(solid) connect(1))
    , 
    legend(order(1 "Low AI Exposure" 2 "High AI Exposure") pos(6) cols(2))
    ytitle("Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp_ai.png", replace width(2000)

#delimit;
    tw 
    (line ma_r_self_emp_e0 ym if ym<`=monthly("2020m1", "YM")', lcolor(stc1) lw(.5))
    (line ma_r_self_emp_e0 ym if ym>`=monthly("2021m1", "YM")', lcolor(stc1) msymb(Oh) lw(.5))
    (line ma_r_self_emp_e1 ym if ym<`=monthly("2020m1", "YM")', lcolor(stc2) lw(.5))
    (line ma_r_self_emp_e1 ym if ym>`=monthly("2021m1", "YM")', lcolor(stc2) msymb(Oh) lw(.5))
    , 
    legend(order(1 "Low AI Exposure" 3 "High AI Exposure") pos(6) cols(2))
    ytitle("Employer Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp_e_ai.png", replace width(2000)

#delimit;
    tw 
    (line ma_r_self_emp_ne0 ym if ym<`=monthly("2020m1", "YM")', lcolor(stc1) lw(.5))
    (line ma_r_self_emp_ne0 ym if ym>`=monthly("2021m1", "YM")', lcolor(stc1) msymb(Oh) lw(.5))
    (line ma_r_self_emp_ne1 ym if ym<`=monthly("2020m1", "YM")', lcolor(stc2) lw(.5))
    (line ma_r_self_emp_ne1 ym if ym>`=monthly("2021m1", "YM")', lcolor(stc2) msymb(Oh) lw(.5))
    , 
    legend(order(1 "Low AI Exposure" 3 "High AI Exposure") pos(6) cols(2))
    ytitle("Non-Employer Self Emp Rate")
    xtitle(" ")
    xlab(, angle(45))
;
#delimit cr
graph export "$fig/cps_selfemp_ne_ai.png", replace width(2000)

preserve
    keep ym_str ma_r_self_emp_e0 ma_r_self_emp_e1
    export excel using "$output/data_wrapper.xlsx", sheet("cps_selfemp_emp_ai") firstrow(variables) 
restore 
preserve
    keep ym_str ma_r_self_emp_ne0 ma_r_self_emp_ne1
    export excel using "$output/data_wrapper.xlsx", sheet("cps_selfemp_nemp_ai") firstrow(variables) 
restore 

*==============================================================================
* BFS NE
*==============================================================================
* Proxy for "likely non-employer" applications = total applications minus the
* likely-employer subset (high-propensity, or planned-wages). Builds bfs_ne.png
* and the "bfs_ne" sheet.

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" & naics=="TOTAL"
gen ba_hba_ne = ba_ba - ba_hba 
gen ba_wba_ne = ba_ba - ba_wba 
keep if year>=2015
#delimit;
    tw 
    (line ba_hba_ne ym, lcolor(cyan) lpat(solid) lw(.5))  
    (line ba_wba_ne ym, lcolor(black) lpat(solid) lw(.5))  
    , 
    legend(order(1 "HBA-based Likely NE" 2 "WBA-based Likely NE") pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(`=monthly("2019m1", "YM")', lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
    yline(100, lcolor(gs8) lpat(solid))
;
#delimit cr
graph export "$fig/bfs_ne.png", replace width(2000)

tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym_str = year + "-" + month 
keep ym_str ba_hba_ne ba_wba_ne
export excel using "$output/data_wrapper.xlsx", sheet("bfs_ne") firstrow(variables) 

*==============================================================================
* BFS and NES
*==============================================================================
* State-level link between BFS "likely non-employer" applications and actual
* nonemployer establishment growth (Nonemployer Statistics, 2004-2023). Builds
* a state-year panel, regresses the log-change in NE establishments on the
* log-change in BFS-derived NE applications (with lags and st/year FEs), then a
* cross-state scatter (bfs_hba_nediff_nesd.png / "st_bfs_ne").
import delimited using "$raw_xwlk/national_state2020.txt", clear stringcols(_all)
tempfile stfips
save `stfips'

* Stack the annual state Nonemployer Statistics files (2004-2023): each file ->
* state establishment totals, appended into one tempfile `nes'.
local start = 1
foreach y of numlist 4(1)23 {
    local yr = "`y'"
    if strlen("`yr'") == 1 {
        local yr = "0`y'"
    }
    import delimited using "$raw_nes/nonemp`yr'st.txt", clear stringcols(1 2)
    collapse (sum) ne_estab=estab, by(st)
    gen year = 2000 + `yr'
    if `start' == 1 {
        tempfile nes
        save `nes'
    }
    else {
        append using `nes'
        save `nes', replace 
    }
    local start = 0
}

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & naics =="TOTAL"
collapse (sum) ba_ba ba_hba ba_wba ba_cba, by(geo year)
rename geo state
merge m:1 state using `stfips', keep(3) nogen
rename statefp st
keep year st state ba_*
merge 1:1 year st using `nes', keep(3) nogen
destring st, replace 
tsset st year
gen ldiff_ne_estab = ln(ne_estab)-ln(L1.ne_estab)

* For each application concept (HBA, then WBA): build the log first-difference
* of BFS-derived NE applications and regress the log-change in NE establishments
* on it, adding lags and state/year fixed effects across specifications.
foreach v in hba wba {
    di "#### `v' ####"
    gen ne_ba_`v' = ba_ba-ba_`v'
    gen ldiff_ne_ba_`v' = ln(ne_ba_`v')-ln(L1.ne_ba_`v')
    gen L1_ldiff_ne_ba_`v' = L1.ldiff_ne_ba_`v'

    reg ldiff_ne_estab ldiff_ne_ba_`v', vce(robust)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v', vce(robust) absorb(st)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v', vce(robust) absorb(year)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v', vce(robust) absorb(st year)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v' L1.ldiff_ne_ba_`v', vce(robust) absorb(st year)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v' L1.ldiff_ne_ba_`v' L2.ldiff_ne_ba_`v', vce(robust) absorb(st year)
    reghdfe ldiff_ne_estab ldiff_ne_ba_`v' L1.ldiff_ne_ba_`v' L2.ldiff_ne_ba_`v' L3.ldiff_ne_ba_`v', vce(robust) absorb(st year)
}
collapse (mean) ba_ba ldiff_ne_ba_hba ldiff_ne_ba_wba ldiff_ne_estab, by(st state) 
corr ldiff_ne_ba_hba ldiff_ne_estab 
corr ldiff_ne_ba_wba ldiff_ne_estab 

#delimit;
    tw 
    (scatter ldiff_ne_estab ldiff_ne_ba_hba [aw=ba_ba], msymb(Oh)) 
    , 
    legend(off)
    ytitle("Change in NE Estabs")
    xtitle("Change in BA-HBA")
;
#delimit cr
graph export "$fig/bfs_hba_nediff_nesd.png", replace width(2000)

keep state ba_ba ldiff_ne_estab ldiff_ne_ba_hba
export excel using "$output/data_wrapper.xlsx", sheet("st_bfs_ne") firstrow(variables) 

*==============================================================================
* BFS AI Sectors
*==============================================================================
* Applications in the two AI-exposed sectors -- NAICS 54 (professional/technical
* services) and NAICS 51 (information) -- versus everything else, indexed to
* 2019m1=100. Builds bfs_51_54.png / "bfs_5154".

import delimited using "$raw_bfs/bfs_monthly.csv", clear
reshapeBFS
keep if sa=="A" & geo=="US" 
gen ba_hba_ne = ba_ba - ba_hba 
keep ym naics ba_hba_ne ba_wba
* one column per NAICS sector so sector arithmetic can be done row-wise
reshape wide ba_hba_ne ba_wba, i(ym) j(naics) string
* "everything except 51 and 54" = total minus those two sectors
gen ba_hba_neNAICSNOT5154 = ba_hba_neTOTAL - ba_hba_neNAICS54 - ba_hba_neNAICS51
gen ba_wbaNAICSNOT5154 = ba_wbaTOTAL - ba_wbaNAICS54 - ba_wbaNAICS51
tsset ym
gen year = year(dofm(ym))
gen month = month(dofm(ym))
* placeholder quarter for makeMA; 6-month trailing MA, 2019m1 = 100
gen quarter = 0
drop *NAICS72*
foreach v of varlist ba* {
    makeMA `v' 5 2019 0 1
}
keep if year>=2015

#delimit;
    tw 
    (line i_ma_ba_hba_neNAICS54 ym, lcolor(stc1) lpat(solid) lw(.5)) 
    (line i_ma_ba_wbaNAICS54 ym , lcolor(stc1) lpat(dash) lw(.5)) 
    (line i_ma_ba_hba_neNAICS51 ym, lcolor(stc2) lpat(solid) lw(.5)) 
    (line i_ma_ba_wbaNAICS51 ym, lcolor(stc2) lpat(dash) lw(.5)) 
    (line i_ma_ba_hba_neNAICSNOT5154 ym, lcolor(gs8) lpat(solid) lw(.5)) 
    (line i_ma_ba_wbaNAICSNOT5154 ym, lcolor(gs8) lpat(dash) lw(.5)) 

    , 
    legend(order(1 "54: HBA-NE" 2 "WBA" 3 "51: BA" 4 "WBA" 5 "Total (exl. 51,54): HBA-NE" 6 "WBA") pos(6) cols(2) size(small))
    ytitle("Applications")
    xtitle(" ")
    xline(708, lcolor(gs8) lpat(solid))
    yline(100, lcolor(gs8) lpat(solid))
    xlab(`=monthly("2015m1", "YM")'(12)`=monthly("2026m1", "YM")', angle(45))
;
#delimit cr
graph export "$fig/bfs_51_54.png", replace width(2000)

tostring month, replace force
replace month = "0" + month if strlen(month) == 1
tostring year, replace force
gen ym_str = year + "-" + month 
keep ym_str i_ma_ba_hba_neNAICS54 i_ma_ba_wbaNAICS54 i_ma_ba_hba_neNAICS51 i_ma_ba_wbaNAICS51 i_ma_ba_hba_neNAICSNOT5154 i_ma_ba_wbaNAICSNOT5154
export excel using "$output/data_wrapper.xlsx", sheet("bfs_5154") firstrow(variables) 

*==============================================================================
* BFS and BTOS Detailed Industry
*==============================================================================
* Relate 3-digit NAICS business-application growth (2024->2025, from
* bfs_naics3_long.csv) to BTOS AI-use rates by subsector (question 7, 2024).
* Builds bfs_btos_naics3.png / "bfs_btos_naics3d".

import excel using "$raw_btos/AI Core Questions.xlsx", clear first sheet("Subsector Estimates")
* lower case all vars
lowecaseVars
btosCollectTimeCols
btosMakeLong subsector
rename byvars subsector
keep if questionid == "7" & !missing(d1)
tempfile btos_3d_legacy
save `btos_3d_legacy'
keep if year==2024
collapse (mean) btos_ai_use=d1, by(subsector)
tempfile btos3d
save `btos3d'

* Annual application totals per 3-digit NAICS, then the 2024->2025 log change
* (within each sorted naics3 group ba_ba[1]=2024, ba_ba[2]=2025); keep one row.
import delimited using "$prcd_data/bfs_naics3_long.csv", clear
collapse (sum) ba_ba=value (count) nwk=value, by(naics3 year)
keep if year==2024 | year==2025
sort naics3 year
* compare weekly averages, not raw annual sums
by naics3: gen ba_logdiff = ln(ba_ba[2]/nwk[2]) - ln(ba_ba[1]/nwk[1])
by naics3: keep if _n==1
gen subsector = naics3 
merge 1:1 subsector using `btos3d', keep(3) nogen
corr ba_logdiff btos_ai_use 
corr ba_logdiff btos_ai_use [aw=ba_ba]

#delimit;
    tw 
    (scatter ba_logdiff btos_ai_use [aw=ba_ba], msymb(Oh)) 
    (lfit ba_logdiff btos_ai_use [aw=ba_ba], msymb(Oh)) 
    , 
    legend(off)
    ytitle("Change in BA""2024 to 2025")
    xtitle("AI Use""2024")
;
#delimit cr
graph export "$fig/bfs_btos_naics3.png", replace width(2000)

keep naics3 ba_ba ba_logdiff btos_ai_use
export excel using "$output/data_wrapper.xlsx", sheet("bfs_btos_naics3d") firstrow(variables) 


*==============================================================================
* MSA 
*==============================================================================
* MSA-level version of the AI-exposure scatter: BFS county applications
* (2024->2025 log change, aggregated to MSA) vs an employment-weighted MSA AI
* exposure share built from BTOS sector AI-use x BDS sector employment.
* Builds bfs_btos_msa.png / "bfs_btos_msa".

import delimited using "$raw_xwlk/msa_county_reference17.txt", clear stringcols(_all)
gen fips = fipstate + fipscty
keep msa name_msa fips 
duplicates drop 
tempfile ctymsa
save `ctymsa'

import excel using "$raw_btos/AI Core Questions.xlsx", clear first sheet("Sector Estimates")
lowecaseVars
btosCollectTimeCols
btosMakeLong sector
rename byvars sector
keep if year == 2024 & questionid == "7"
collapse (mean) btos_ai_use=d1, by(sector)
tempfile btossec
save `btossec'

* BDS MSA-by-sector employment (2022). Collapse hyphenated NAICS ranges to the
* leading code so they join the BTOS sector AI-use rates, then compute
* AI-exposed employment (emp x AI-use share) and total emp per MSA.
import delimited using "$raw_bds/bds2023_msa_sec.csv", clear stringcols(2)
keep if year == 2022
replace sector = "31" if sector == "31-33"
replace sector = "44" if sector == "44-45"
replace sector = "48" if sector == "48-49"
merge m:1 sector using `btossec', keep(1 3) nogen
destring emp, replace force
gen emp_ai_sec_use = emp * (btos_ai_use/100)
collapse (sum) emp emp_ai_sec_use, by(msa)
tempfile bdsmsasecuse
save `bdsmsasecuse'

* Annual county business applications (BA<year> columns). Numeric-ize the BA
* columns, join counties to MSAs, sum to MSA, then reshape the BA<year> columns
* to long (one row per msa-year).
import excel using "$raw_bfs/bfs_county_apps_annual.xlsx", clear first cellrange(A3:Z3159)
ds BA*
local vars `r(varlist)'
foreach v of local vars {
    destring `v', replace force
}
gen fips = CountyCode 
merge 1:m fips using `ctymsa', keep(3) nogen
collapse (sum) BA* (first) name_msa, by(msa)
reshape long BA, i(msa) j(year)
rename BA ba_ba
keep if year==2024 | year==2025
sort msa year
by msa: gen ba_logdiff = ln(ba_ba[2]) - ln(ba_ba[1]) 
by msa: keep if _n==1
merge 1:1 msa using `bdsmsasecuse', keep(3) nogen
gen shr_ai = 100*emp_ai_sec_use/emp 
corr ba_logdiff shr_ai 
corr ba_logdiff shr_ai [aw=ba_ba]

#delimit;
    tw 
    (scatter ba_logdiff shr_ai [aw=ba_ba], msymb(Oh)) 
    (lfit ba_logdiff shr_ai [aw=ba_ba], msymb(Oh)) 
    , 
    legend(off)
    ytitle("Change in BA""2024 to 2025")
    xtitle("AI Use""2024")
;
#delimit cr
graph export "$fig/bfs_btos_msa.png", replace width(2000)

keep msa name_msa ba_logdiff shr_ai ba_ba
export excel using "$output/data_wrapper.xlsx", sheet("bfs_btos_msa") firstrow(variables) 

*==============================================================================
* BED Sector
*==============================================================================
* Sector-level firm births (annual, t3 xlsx) and establishment births
* (quarterly, flat file), indexed to 2019q1=100, for Information, Prof/Business
* Services, and everything-except-51/54. Builds the "bed_sector" sheet.
*--------------------------------------------------------------
* BED t3 xlsx -> firm births (firms < 1 yr old, all sizes) by
* supersector, national, annual (assigned to Q1). Same block on
* every sheet: cellrange A279:B310, col A=year, col B=Total Firms.
*--------------------------------------------------------------

* Sheet names paired positionally with project sector suffixes.
local sheets `" "Total Private" "Natural Resource and Mining" "Construction" "Manufacturing" "Wholesale Trade" "Retail Trade" "Trans. and Warehousing" "Information" "Financial Activities" "Prof. and Bus. Services" "Education and Health Service" "Leisure and Hospitality" "'
local suffixes "total nat_mining const manuf wholesl retail tw info fin prof_bus edu_health les_hosp"
local n : word count `suffixes'

tempfile stack
forvalues i = 1/`n' {
    local sh : word `i' of `sheets'
    local sf : word `i' of `suffixes'

    import excel "$raw_bed/age_naics_size_ein_20251_t3.xlsx", sheet("`sh'") cellrange(A279:B310) clear
    rename (A B) (year bed_firm_births)

    * strip thousands commas; "_" (n/a) and "N" (nondisclosure) -> missing
    replace bed_firm_births = subinstr(bed_firm_births, ",", "", .)
    destring bed_firm_births, replace force
    capture confirm string variable year
    if !_rc destring year, replace

    gen sector = "`sf'"
    if `i' > 1 append using `stack'
    save `stack', replace
}

use `stack', clear
* BED firm data is annual -> Q1
gen quarter = 1
order year quarter sector bed_firm_births
sort sector year
reshape wide bed_firm_births, i(year quarter) j(sector) string
tempfile bed_firm_sec
save `bed_firm_sec'

*--------------------------------------------------------------
* Raw BED flat file -> establishment BIRTHS by supersector,
* national, SA, all sizes, quarterly. Levels (count of births);
* set ratelevel to "R" instead of "L" for the birth rate.
*--------------------------------------------------------------
import delimited "$raw_bed/bd.data.1.AllItems", delimiter(tab) varnames(1) stringcols(_all) clear

* --- Parse series_id components (1-based positions) ---
gen seasonal  = substr(series_id, 3, 1)
gen state     = substr(series_id, 9, 2)
gen industry  = substr(series_id, 14, 6)
* 2 = establishment counts
gen delem     = substr(series_id, 21, 1)
gen sizecls   = substr(series_id, 22, 2)
* 07 = establishment births
gen dataclass = substr(series_id, 24, 2)
* L = level, R = rate
gen ratelevel = substr(series_id, 26, 1)

* --- Filter: national, SA, all sizes, establishment births, LEVEL ---
keep if seasonal=="S" & state=="00" & sizecls=="00" & delem=="2"
keep if dataclass=="07" & ratelevel=="L"
keep if substr(period,1,1)=="Q"

* --- Keep the 13 supersectors (display level 2) and label them ---
gen sector = ""
replace sector = "nat_mining"      if industry=="100010"
replace sector = "const"        if industry=="100020"
replace sector = "manuf"       if industry=="100030"
replace sector = "wholesl"           if industry=="200010"
replace sector = "retail"              if industry=="200020"
replace sector = "tw" if industry=="200030"
replace sector = "util"           if industry=="200040"
replace sector = "info"         if industry=="200050"
replace sector = "fin"           if industry=="200060"
replace sector = "prof_bus"       if industry=="200070"
replace sector = "edu_health"          if industry=="200080"
replace sector = "les_hosp" if industry=="200090"
replace sector = "oth_srv"      if industry=="200100"
* total private, kept so the ex-51/54 residual can be taken off the top line
replace sector = "total"      if industry=="000000"
* drops broad groups, any 3-digit
drop if sector==""

* --- Types and units ---
destring year, replace
destring value, replace force
* "Q03" -> 3
gen quarter = real(substr(period, 2, .))
* source is in thousands
gen estabs_births = value*1000

keep year quarter sector estabs_births
order year quarter sector estabs_births
reshape wide estabs_births, i(year quarter) j(sector) string
merge 1:1 year quarter using `bed_firm_sec', keep(1 3) nogen

* "All sectors except 51 (info) and 54 (prof/bus)" = total minus prof serv and info
* Residual-from-total rather than a rowtotal() of the remaining supersectors, so
* nothing is silently dropped if a supersector is missing or newly suppressed.
gen estabs_births_n5154 = estabs_birthstotal - (estabs_birthsinfo + estabs_birthsprof_bus)
gen bed_firm_births_n5154 = bed_firm_birthstotal - (bed_firm_birthsinfo + bed_firm_birthsprof_bus)
replace bed_firm_births_n5154 = . if quarter!=1
gen yq = yq(year,quarter)
format yq %tq
tsset yq

* utilities cannot be indexed as it is zero in 2019q1, unneceessary for figure
drop *util*
* placeholder month for makeMA; 4-quarter trailing MA, 2019q1 = 100.  Annual
* firm-birth series (bed*) only have a Q1 value, so their MA stays missing.
gen month = 0
foreach v of varlist estabs* bed* {
    makeMA `v' 3 2019 1 0
}
drop month
keep if year>=2015
tostring year, replace
tostring quarter, replace force
gen yq_str = year + "-Q" + quarter
keep yq_str i_ma_estabs_birthsinfo i_ma_estabs_birthsprof_bus i_ma_estabs_births_n5154 i_bed_firm_birthsinfo i_bed_firm_birthsprof_bus i_bed_firm_births_n5154
export excel using "$output/data_wrapper.xlsx", sheet("bed_sector") firstrow(variables) 

*==============================================================================
* QWI 
*==============================================================================
/*
QWI Firm age bins
┌──────┬────────────┐
│ Code │  Firm age  │
├──────┼────────────┤
│ 0    │ All ages   │
├──────┼────────────┤
│ 1    │ 0–1 years  │
├──────┼────────────┤
│ 2    │ 2–3 years  │
├──────┼────────────┤
│ 3    │ 4–5 years  │
├──────┼────────────┤
│ 4    │ 6–10 years │
├──────┼────────────┤
│ 5    │ 11+ years  │
└──────┴────────────┘
*/

* This block links the QWI firm-age panels (built by code/00_download_qwi.py)
* to the state x NAICS AI-exposure measure and asks whether employment at young
* firms in AI-exposed industries moved differently after AI's late-2022 arrival.
* It produces (1) the "qwi_exp" Datawrapper sheet -- seasonally adjusted
* end-of-quarter employment at 0-1yr firms, indexed to 2019q1, by exposure group
* -- and (2) difference-in-differences robustness regressions (log output only).
* LEVEL selects the NAICS depth; it must match an available L# panel and xwalk.
local LEVEL 4

* --- PCEPI price deflator -> quarterly, rebased so 2024q1 = 1.0 ---
* import delimited assumes a .csv extension, so this reads deflators/PCEPI.csv.
import delimited using "$raw_def/PCEPI", clear
g year = substr(observation_date, 1,4)
g month = substr(observation_date, 6,2)
destring year, replace 
destring month, replace
gen ym = ym(year, month)
gen quarter = quarter(dofm(ym))
gen yq = yq(year, quarter)
format yq %tq
collapse (mean) pcepi, by(yq)
* pcepi*(yq==2024q1) is 0 in every other quarter and the 2024q1 value in that
* one, so max() extracts the 2024q1 index level as the base.  Multiplying a
* nominal series by base/pcepi expresses it in constant 2024q1 dollars.
egen base = max(pcepi*(yq==`=quarterly("2024q1", "YQ")'))
g pce_deflator = base / pcepi
keep yq pce_deflator
tempfile pce_deflator
save `pce_deflator'

* --- AI-exposure crosswalk (state x NAICS): Eloundou `beta' score plus a
*     prebuilt employment-weighted `quintile'.  Add `median_exp': a 2-group
*     (1=below / 2=above median) split of beta, weighted by 2022 QWI employment. ---
use "$raw_aiexp/ai_exposure_state_naics_L`LEVEL'.dta", clear
* Employment-weighted cuts of beta across state x NAICS cells: median split and
* deciles.  aw (analytic weights) rather than pw here -- xtile treats them the
* same, but aw is the honest label for a cell-size weight.
xtile median_exp = beta [aw=qwi_emp_2022], nq(2)
xtile ai_nq10 = beta [aw=qwi_emp_2022], nq(10)
* Extreme-tail cut: the 10 least- (0) and 10 most- (1) exposed cells by COUNT of
* rows, not a percentile -- everything in between stays missing and drops out of
* any regression using it.
preserve
    keep if !missing(beta)
    sort beta
    gen beta_top_btm = .
    replace beta_top_btm = 0 if _n<=10
    replace beta_top_btm = 1 if _N-_n<10
    keep statefip naics_2022 beta_top_btm
    tempfile betatop
    save `betatop'
restore
* Same cuts at the industry level: collapse states out of beta with an
* employment-weighted mean, so exposure varies only across NAICS (ind_ prefix).
preserve
    keep if !missing(beta)
    bys naics_2022: egen t_qwi_emp_2022 = sum(qwi_emp_2022)
    collapse (first) t_qwi_emp_2022 (mean) ind_beta=beta [aw=qwi_emp_2022], by(naics_2022)
    sort ind_beta
    gen ind_beta_top_btm = .
    replace ind_beta_top_btm = 0 if _n<=10
    replace ind_beta_top_btm = 1 if _N-_n<10
    xtile ind_median_exp = ind_beta [aw=t_qwi_emp_2022], nq(2)
    xtile ind_ai_nq10 = ind_beta [aw=t_qwi_emp_2022], nq(10)
    keep naics_2022 ind_beta_top_btm ind_median_exp ind_ai_nq10
    tempfile betaind
    save `betaind'
restore
merge 1:1 statefip naics_2022 using `betatop', nogen 
merge m:1 naics_2022 using `betaind', nogen 
tempfile aie
save `aie'

* Analysis endpoint: the latest quarter through which we expect balanced-state
* reporting.  Late-reporting states are trimmed to this quarter below.
local ENDPOINT_QSTR "2025q2"
local ENDPOINT_Q   = tq(2025q2)

use "$prcd_data/qwi_panel_firmage_L`LEVEL'.dta", clear
* Quarterly date from "YYYY-QN" string.
gen year = real(substr(time, 1, 4))
gen qtr  = real(substr(time, 7, 1))
gen yq = yq(year, qtr)
format yq %tq
drop year qtr

* Window: through ENDPOINT_Q.  This trims late-period data from
* states that haven't yet reported through the endpoint, before we apply
* the balanced-state filter.
keep if inrange(yq, tq(2015q1), `ENDPOINT_Q')

* Numeric state and NAICS.
destring state, generate(statefip) force
destring industry, generate(naics_2022) force

* Canonical 2-digit NAICS sector: take the first two characters of the NAICS
* code, then collapse the combined sector ranges (31-33, 44-45, 48-49) to their
* leading code.  (Comment corrected: implementation uses substr(), not division.)
* NOTE: `sector' is not referenced anywhere below in this block -- it looks like
* a leftover from exploration.  Drop it, or use it, to keep the panel lean.
gen sector = substr(industry,1,2)
destring sector, replace force
replace sector = 31 if inlist(sector, 31, 32, 33)  
replace sector = 44 if inlist(sector, 44, 45)       
replace sector = 48 if inlist(sector, 48, 49)

* Attach AI-exposure quintile, beta, and 2022 QWI employment weight.
merge m:1 statefip naics_2022 using `aie', keepusing(beta quintile median_exp ai_nq10 beta_top_btm ind_beta_top_btm ind_median_exp ind_ai_nq10) keep(master match) nogen

* Attach the deflator and build real (constant 2024q1$) earnings measures.
* R-prefix = real; earns = avg monthly earnings of full-quarter (stable) workers,
* earnbeg = avg monthly earnings of beginning-of-quarter workers.
merge m:1 yq using `pce_deflator', keep(1 3) nogen
foreach v in earns earnbeg {
    gen R`v' = `v'*pce_deflator
}

* Balanced-state set: states with at least one non-null A00 cell at the
* endpoint quarter.  Indexed plots (Figs 3, 4, 5) restrict to this set so
* state composition is held fixed across the full window.  Figure 6
* (regression with state x NAICS FE) keeps all states.
preserve
    keep if agegrp == "A00" & yq == `ENDPOINT_Q' & !missing(emp)
    keep statefip
    duplicates drop
    tempfile bal_states
    save `bal_states'
    count
    display as text "Balanced state set (data at `ENDPOINT_QSTR'): `r(N)' states"
    levelsof statefip, local(bal_list)
    display "  states: `bal_list'"
restore
merge m:1 statefip using `bal_states', generate(_bal)
gen byte balanced = (_bal == 3)
drop _bal
label variable balanced "1 if state is in the balanced-through-`ENDPOINT_QSTR' set"

compress
tempfile age_panel
save `age_panel'

use `age_panel', clear
keep if balanced
gen tokeep = !missing(quintile) & !missing(emp)
tab tokeep
keep if !missing(quintile) & !missing(emp)
* ==========================================================================
* (1) Exposure-group employment series for the "qwi_exp" Datawrapper sheet.
* For each exposure quintile: total end-of-quarter employment summed over the
* firm-age bins, and -- via the fa0* copies -- the same for the youngest
* (0-1yr) cohort only.  ("fa0" = firm age 0-1yr, i.e. firmage bin 1.)
* ==========================================================================
* drop the all-firm-ages total (firmage==0) so bins 1-5 are additive
drop if firmage=="0"
* fa0* isolates the youngest cohort (firmage==1); plain names keep all bins.
foreach v in emp empend hiraend Rearns hirn {
    gen fa0`v' = `v' if firmage == "1"
}
* NOTE: only empend and fa0empend survive this collapse; fa0emp/fa0hiraend/
* fa0Rearns/fa0hirn are built above but dropped here.  Add them to the collapse
* list if you want hire- or earnings-based versions of the plot.
collapse (sum) empend fa0empend, by(quintile yq)
reshape wide empend fa0empend, i(yq) j(quintile)
gen year = year(dofq(yq))
gen quarter = quarter(dofq(yq))
tsset yq
* r(varlist) is captured ONCE here (empend1-5, fa0empend1-5), so the transform
* variables created inside the loop are not themselves re-transformed.  For each
* series build: ma_ = 3q trailing moving average; i_ = indexed to 2019q1=100;
* i_ma_ = indexed MA; ma_i_ = MA of the index; r_ = seasonally adjusted level.
* NOTE: only r_fa0empend* is exported below -- the ma_/i_/i_ma_/ma_i_ series are
* computed but currently unused.
* placeholder month for makeMA; 4-quarter trailing MA, 2019q1 = 100
gen month = 0
desc *1 *2 *3 *4 *5, varlist
local base `r(varlist)'
foreach v of local base {
    makeMA `v' 3 2019 1 0
}
drop month
foreach v of local base {
    * Seasonal adjustment: regress on quarter dummies (Q1 as base) and keep the
    * residual, then add the constant back so r_ stays on the original level
    * scale with calendar-quarter effects removed.
    qui reg `v' ib(1).quarter
    local cons = _b[_cons]
    predict r_`v', residuals
    replace r_`v' = r_`v' + `cons'
}
keep if year>=2015
tostring year, replace
tostring quarter, replace force
gen yq_str = year + "-Q" + quarter
* Export seasonally adjusted young-firm (0-1yr) end-of-quarter employment, one
* column per exposure quintile (r_fa0empend1..5), to the "qwi_exp" sheet.
keep yq_str r_fa0empend1 r_fa0empend2 r_fa0empend3 r_fa0empend4 r_fa0empend5
export excel using "$output/data_wrapper.xlsx", sheet("qwi_exp") firstrow(variables)

* Standalone fact for the text (log output only, no figure or sheet): average
* employment per age-0 firm.  fage "a) 0" = firms in their first year.
import delimited using "$raw_bds/bds2023_fa.csv", clear 
keep if fage =="a) 0"
destring emp, replace force
destring firms, replace force
collapse (sum) firms emp, by(year)
gen avg_emp_per_startup = emp/firms 
keep if year>=2015
list year avg_emp_per_startup

* ==========================================================================
* ROBUSTNESS
* ==========================================================================
* Three difference-in-differences tables, all written to
* $output/tables/regressions.xlsx via esttabExcel:
*   cps_ne_e      CPS self-employment (non-employer / employer) x occupational
*                 AI exposure
*   qwi           QWI young-firm employment x state-industry AI exposure
*   bfs_btos_n3   BFS 3-digit applications x BTOS measured AI use
* In every table `post' contrasts 2025 against a 2022-23 (or 2023) baseline; the
* intervening year is left missing so it drops out rather than being pooled.

* CPS REGRESSIONS
* compute additional exposure measures
* Two alternative exposure scores on occ2010: aioe (AI occupational exposure)
* and gpt4_beta (Eloundou et al. GPT-4 exposure).  For each, build a decile and
* an extreme-tail dummy = the 10 lowest (0) / 10 highest (1) occupations by row
* count, unweighted.  NOTE: only the gpt4_beta_* versions are used below.
use "$raw_aiexp/ai_exposure_occ2010.dta", clear
gen r = uniform()
foreach m in  aioe gpt4_beta {
    preserve
        keep if !missing(`m')    
        sort `m' r
        gen `m'_top_btm = .
        replace `m'_top_btm = 0 if _n<=10
        replace `m'_top_btm = 1 if _N-_n<10
        xtile `m'_q10 = `m', nq(10)
        keep occ2010 `m'_top_btm `m'_q10
        tempfile `m'top
        save ``m'top'
    restore
}
foreach m in  aioe gpt4_beta {
    merge 1:1 occ2010 using ``m'top', nogen
}
tempfile aiexp
save `aiexp'

* prep cps microdata
use "$raw_cps/$cpsfile", clear
keep if age >=16 & age <=64
di "CPS monthly loaded: `r(N)' observations"
merge m:1 occ2010 using `aiexp', keep(1 3) nogen
* time vars
gen ym = ym(year,month)
format ym %tm
* Weighted self-employment numerators and denominators:
*   selfemp           = all self-employed (classwkr 13/14)
*   selfemp_denom     = all persons 16-64
*   selfemp_ne / _e   = non-employer / employer self-employed (paidemp 1/2)
*   selfemp_ene_denom = denominator for the emp/non-emp split (mish 4/8 only)
gen selfemp = wtfinl if classwkr==13 | classwkr==14
gen selfemp_denom = wtfinl
gen selfemp_ne = wtfinl if (classwkr==13 | classwkr==14) & (paidemp1==1)
gen selfemp_e = wtfinl if (classwkr==13 | classwkr==14) & (paidemp1==2)
gen selfemp_ene_denom = wtfinl if mish==4 | mish==8
* process AI vars
* Three nested exposure cuts, coarse to sharp: top-two quintiles, top vs bottom
* decile (middle deciles left missing), and top-10 vs bottom-10 occupations.
gen ai_exp_q5 = gpt4_beta_q_occ2010
gen ai_exp_gt4 = gpt4_beta_q_occ2010>=4 if !missing(gpt4_beta_q_occ2010)
gen ai_exp_qtop_qbtm = .
replace  ai_exp_qtop_qbtm = 0 if gpt4_beta_q10 == 1
replace  ai_exp_qtop_qbtm = 1 if gpt4_beta_q10 == 10
* 0/100 outcomes restricted to outgoing rotations (mish 4/8), the only months
* PAIDEMP1 is asked.  Weighted by wtfinl in the models below, so coefficients
* read directly as percentage points of the population.
gen selfemp_ne_bnry = (classwkr==13 | classwkr==14) & (paidemp1==1) if mish==4 | mish==8
replace selfemp_ne_bnry = selfemp_ne_bnry*100
gen selfemp_e_bnry = (classwkr==13 | classwkr==14) & (paidemp1==2) if mish==4 | mish==8
replace selfemp_e_bnry = selfemp_e_bnry*100
* pre = 2022-23, post = 2025; 2024 stays missing and is excluded
gen post = .
replace post = 0 if year==2022 | year==2023
replace post = 1 if year==2025

* (1) & (5) are post-only means; (2)-(4) and (6)-(8) add the exposure x post
* interaction under each of the three cuts.  [aw=wtfinl] + vce(robust) is
* Stata's equivalent of [pw=wtfinl], so these are population-weighted with
* survey-robust SEs.  Each model is followed by a weighted pre-period mean.
eststo clear
eststo m1: reg selfemp_ne_bnry ib(0).post [aw=wtfinl], vce(robust)
summarize selfemp_ne_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m2: reg selfemp_ne_bnry ib(0).post##ib(0).ai_exp_gt4 [aw=wtfinl], vce(robust)
summarize selfemp_ne_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m3: reg selfemp_ne_bnry ib(0).post##ib(0).ai_exp_qtop_qbtm [aw=wtfinl], vce(robust)
summarize selfemp_ne_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m4: reg selfemp_ne_bnry ib(0).post##ib(0).gpt4_beta_top_btm [aw=wtfinl], vce(robust)
summarize selfemp_ne_bnry [aw=wtfinl] if e(sample) & post == 0

eststo m5: reg selfemp_e_bnry ib(0).post [aw=wtfinl], vce(robust)
summarize selfemp_e_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m6: reg selfemp_e_bnry ib(0).post##ib(0).ai_exp_gt4 [aw=wtfinl], vce(robust)
summarize selfemp_e_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m7: reg selfemp_e_bnry ib(0).post##ib(0).ai_exp_qtop_qbtm [aw=wtfinl], vce(robust)
summarize selfemp_e_bnry [aw=wtfinl] if e(sample) & post == 0
eststo m8: reg selfemp_e_bnry ib(0).post##ib(0).gpt4_beta_top_btm [aw=wtfinl], vce(robust)
summarize selfemp_e_bnry [aw=wtfinl] if e(sample) & post == 0

#delimit;
esttabExcel m1 m2 m3 m4 m5 m6 m7 m8 using "$output/tables/regressions.xlsx", 
    sheet("cps_ne_e") 
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) 
    drop(_cons)
    nobaselevels noomitted
    mtitles("(1)" "(2)" "(3)" "(4)" "(5)" "(6)" "(7)" "(8)") nonumbers nodepvars 
    stats(N r2_a, fmt(%9.0fc %9.3f) 
            labels("Observations" "Adj. R-squared")) 
    nonotes addnotes("1-4 is self employment in NE. 5-8 is self employment in E." 
                        "Robust standard errors in parentheses."
                        "* p<0.10, ** p<0.05, *** p<0.01")
;
#delimit cr

* robustness regressions
use `age_panel', clear
keep if balanced
keep if !missing(quintile) & !missing(emp)
drop if firmage=="0"
foreach v in emp empend hirn hiraend Rearns Rearnbeg {
    gen ln_`v' = ln(`v')
}
destring state, replace force
* young-firm (0-1yr) flag
gen su = firmage=="1" 
* post AI-arrival period: pre = 2022-23, post = 2025 (2024 left missing and so
* excluded).  Replaces the earlier continuous post = yq>=2022q4 split.
gen year = year(dofq(yq))
gen post = .
replace post = 0 if year==2022 | year==2023
replace post = 1 if year==2025
* top exposure quintile
gen ai_exp_gt4 = quintile>=4 if !missing(quintile)
* top vs bottom decile of state x NAICS beta; middle deciles left missing
gen ai_exp_qtop_qbtm = .
replace  ai_exp_qtop_qbtm = 0 if ai_nq10 == 1
replace  ai_exp_qtop_qbtm = 1 if ai_nq10 == 10
* Industry-level extreme-tail cut: the 10 least- and 10 most-exposed NAICS by
* employment-weighted mean beta, with the middle left missing.
* NOTE: this leaves only 20 industries in the estimation sample, so vce(cluster
* ind_FE) below has 20 clusters -- too few for cluster-robust asymptotics.
* Treat m5's stars with caution; wild-cluster bootstrap would be the fix.
gen ind_ai_exp_top_btm = . 
replace ind_ai_exp_top_btm = 0 if ind_beta_top_btm == 0
replace ind_ai_exp_top_btm = 1 if ind_beta_top_btm == 1
egen ind_FE = group(industry)

eststo clear
eststo m1: reg ln_empend ib(0).post if firmage=="1", vce(cluster ind_FE)
estadd local stfe "No"
estadd local indfe "No"
summarize ln_empend if e(sample) & post == 0
eststo m2: reghdfe ln_empend ib(0).post if firmage=="1", vce(cluster ind_FE) absorb(state ind_FE)
estadd local stfe "Yes"
estadd local indfe "Yes"
summarize ln_empend if e(sample) & post == 0
eststo m3: reghdfe ln_empend ib(0).ai_exp_gt4##ib(0).post if firmage=="1", vce(cluster ind_FE) absorb(state ind_FE)
estadd local stfe "Yes"
estadd local indfe "Yes"
summarize ln_empend if e(sample) & post == 0
eststo m4: reghdfe ln_empend ib(0).ai_exp_qtop_qbtm##ib(0).post if firmage=="1", vce(cluster ind_FE) absorb(state ind_FE)
estadd local stfe "Yes"
estadd local indfe "Yes"
summarize ln_empend if e(sample) & post == 0
eststo m5: reg ln_empend ib(0).ind_ai_exp_top_btm##ib(0).post if firmage=="1", vce(cluster ind_FE)
estadd local stfe "No"
estadd local indfe "No"
summarize ln_empend if e(sample) & post == 0

#delimit;
esttabExcel m1 m2 m3 m4 m5  using "$output/tables/regressions.xlsx", 
    sheet("qwi") 
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) 
    drop(_cons)
    nobaselevels noomitted
    mtitles("(1)" "(2)" "(3)" "(4)" "(5)" ) nonumbers nodepvars 
    stats(stfe indfe N r2_a, fmt(%s %s %9.0fc %9.3f) 
            labels("State FE" "Industry FE" "Observations" "Adj. R-squared")) 
    nonotes addnotes("" 
                        "Robust standard errors in parentheses."
                        "* p<0.10, ** p<0.05, *** p<0.01")
;
#delimit cr


* BFS-BTOS 3-DIGIT REGRESSIONS
* Reuse the full biweekly BTOS subsector panel saved above (question 7, d1 =
* share of firms reporting AI use) and average it to subsector-months.
use `btos_3d_legacy', clear
rename d1 btos_ai_use
gen month = month(dofd(start_date))
gen ym = ym(year,month)
format ym %tm
rename subsector naics3
collapse (mean) btos_ai_use, by(ym naics3)
* Fix each industry's exposure group at its 2023 (baseline-year) average AI use
* and merge it back onto every month, so the group assignment is pre-treatment
* and time-invariant rather than moving with the outcome window.
preserve
    keep if year(dofm(ym))==2023
    collapse (mean) btos_ai_use, by(naics3)
    xtile btos_ai_use_2023_q5 = btos_ai_use , nq(5)
    xtile btos_ai_use_2023_q2 = btos_ai_use , nq(2)
    keep naics3 btos_ai_use_2023_q5 btos_ai_use_2023_q2
    tempfile p1
    save `p1'
restore
merge m:1 naics3 using `p1', nogen
tempfile btos3d_ym
save `btos3d_ym'


* Weekly 3-digit BFS applications from 01_reshape_bfs_naics3.py.
import delimited using "$prcd_data/bfs_naics3_long.csv", clear
* parse year + week out of the string 
gen int yr = .
gen int wk = .
local pat "^ *([0-9][0-9][0-9][0-9])[^0-9]*([0-9]+) *$"
replace yr = real(ustrregexs(1)) if ustrregexm(yearweek, "`pat'")
replace wk = real(ustrregexs(2)) if ustrregexm(yearweek, "`pat'")
* Approximate week start as Jan 1 + 7*(wk-1); only the month is used downstream,
* so a day or two of slippage matters solely at month boundaries.
gen first_day = mdy(1,1,yr) + 7*(wk-1)
format first_day %td
gen ym = mofd(first_day)
format ym %tm
* weekly applications -> monthly totals per 3-digit industry
collapse (sum) ba=value, by(naics3 ym)
* keep(3): only industry-months present in both BFS and BTOS
merge 1:1 ym naics3 using `btos3d_ym', keep(3) nogen
sort ym naics btos_ai_use 
egen ind_FE = group(naics3)
gen ln_ba = ln(ba)
* pre = 2023, post = 2025; 2024 stays missing and is excluded
gen year = year(dofm(ym))
gen post = .
replace post = 0 if year==2023
replace post = 1 if year==2025
* top-quintile / above-median AI use as of 2023
gen btos_ai_use_2023_topq5 = btos_ai_use_2023_q5 == 5 if !missing(btos_ai_use_2023_q5)
gen btos_ai_use_2023_topq2 = btos_ai_use_2023_q2 == 2 if !missing(btos_ai_use_2023_q2)

* (1)-(3) regress log applications on the contemporaneous AI-use rate, adding
* industry then year-month FE; (4)-(6) are the post-only mean and its
* interaction with the fixed 2023 above-median / top-quintile groups.
eststo clear
eststo m1: reg ln_ba btos_ai_use, vce(cluster ind_FE)
estadd local indfe "No"
estadd local timefe "No"
eststo m2: reghdfe ln_ba btos_ai_use, vce(cluster ind_FE) absorb(ind_FE)
estadd local indfe "Yes"
estadd local timefe "No"
eststo m3: reghdfe ln_ba btos_ai_use, vce(cluster ind_FE) absorb(ind_FE ym)
estadd local indfe "Yes"
estadd local timefe "Yes"
eststo m4: reg ln_ba ib(0).post, vce(cluster ind_FE)
estadd local indfe "No"
estadd local timefe "No"
eststo m5: reg ln_ba ib(0).btos_ai_use_2023_topq2##ib(0).post, vce(cluster ind_FE)
estadd local indfe "No"
estadd local timefe "No"
eststo m6: reg ln_ba ib(0).btos_ai_use_2023_topq5##ib(0).post, vce(cluster ind_FE)
estadd local indfe "No"
estadd local timefe "No"

#delimit;
esttabExcel m1 m2 m3 m4 m5 m6 using "$output/tables/regressions.xlsx", 
    sheet("bfs_btos_n3") 
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) 
    drop(_cons)
    nobaselevels noomitted
    mtitles("(1)" "(2)" "(3)" "(4)" "(5)" "(6)" ) nonumbers nodepvars 
    stats(indfe timefe N r2_a, fmt(%s %s %9.0fc %9.3f) 
            labels("Industry FE" "Year-Month FE" "Observations" "Adj. R-squared")) 
    nonotes addnotes("Post is 2023 vs. 2025." 
                        "Robust standard errors in parentheses."
                        "* p<0.10, ** p<0.05, *** p<0.01")
;
#delimit cr

log close
