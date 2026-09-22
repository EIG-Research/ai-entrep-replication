#!/usr/bin/env bash
#
# Analysis pipeline. Runs each component in dependency order:
#   00_download_qwi.py  (Python)  -> data/raw/qwi/
#   01_reshape_bfs_naics3.py  (Python)  -> data/processed/bfs_naics3_long.csv
#   02_analysis.do            (Stata)   -> output figures + output/data_wrapper.xlsx
#
# Step 02 consumes the output of step 01, so 01 runs first.
#
# Usage:  ./code/run_all.sh
#
# (00_download_qwi.py pulls the raw QWI panels from the Census API. It is a
#  slow, one-time download and is not part of this run -- call it by hand if
#  you need to rebuild the .dta files.)

# ---- SET THIS: path to your Stata executable ----------------------------
STATA="/Applications/StataNow/StataSE.app/Contents/MacOS/stata-se"
PYTHON="/opt/anaconda3/bin/python3"
# -------------------------------------------------------------------------

set -euo pipefail

# Run from the code/ directory: 02_analysis.do derives its paths from c(pwd)/..
cd "$(dirname "$0")"

# Use the project virtualenv Python if present (it has pandas), else plain python3.
echo "=== [00 download] $PYTHON 00_download_qwi.py ==="
"$PYTHON" 00_download_qwi.py

echo "=== [01 reshape] $PYTHON 01_reshape_bfs_naics3.py ==="
"$PYTHON" 01_reshape_bfs_naics3.py

echo "=== [02 analysis] $STATA -b do 02_analysis.do ==="
if [ ! -x "$STATA" ] && ! command -v "$STATA" >/dev/null 2>&1; then
    echo "!!! Stata not found at '$STATA'. Edit the STATA variable at the top of this script." >&2
    exit 1
fi
"$STATA" -b do 02_analysis.do

# Stata batch mode does not reliably return nonzero on a do-file error, so scan
# the log it just wrote for an "r(###);" error marker.
LOG="$(ls -t 02_analysis_*.log 2>/dev/null | head -n1)"
if [ -n "$LOG" ] && grep -Eq '^r\([0-9]+\);' "$LOG"; then
    echo "!!! [02 analysis] Stata reported an error -- see $LOG" >&2
    exit 1
fi
[ -n "$LOG" ] && echo "    Stata log: $LOG"

echo ""
echo "All steps completed."
