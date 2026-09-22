#!/usr/bin/env python3
"""Download QWI firm-age panels and build the analysis .dta files.

What this produces
------------------
    data/processed/qwi_panel_firmage_L{LEVEL}.dta

Each is a state x NAICS x quarter x firm-age panel of QWI indicators, at the
3-, 4-, and 6-digit NAICS aggregation levels respectively.

How it works
------------
The Census QWI "sa" (sex x age) endpoint is queried one cell at a time, where a
cell is one (state, firmage-value) combination, pulling the entire time range in
a single call. firmage is crossed with agegrp=A00 (all worker ages); QWI does
not allow firmage and firmsize to be crossed with each other. Each cell is
cached as a parquet under data/raw/qwi/ so the download is resumable -- re-runs
skip cells already on disk, so pass --refresh to pick up quarters published
since a cell was written. The per-cell parquets are then concatenated per
level and written out as .dta.

firmage values (QWI): 0 = All, 1 = 0-1yr, 2 = 2-3yr, 3 = 4-5yr, 4 = 6-10yr,
5 = 11+yr. Value 0 (the total) is pulled alongside the five bands.

Dependencies
------------
    pandas, pyarrow, requests

Environment
-----------
    export CENSUS_API_KEY=...   # strongly recommended; without it the QWI API
                                # redirects to a "Missing Key" page once a few
                                # parallel requests are made, and the download
                                # fails. Get one free at
                                # https://api.census.gov/data/key_signup.html

Usage
-----
    python code/00_download_qwi.py                 # download + convert, all levels
    python code/00_download_qwi.py --levels 3      # just L3
    python code/00_download_qwi.py --download-only # fetch parquets, skip .dta
    python code/00_download_qwi.py --convert-only  # rebuild .dta from cached parquets
    python code/00_download_qwi.py --refresh       # pull quarters added since the
                                                  # cells were last downloaded
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

import requests

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW = PROJECT_ROOT / "data" / "raw"
PROCESSED = PROJECT_ROOT / "data" / "processed"
QWI_RAW = RAW / "qwi"
MANIFEST_PATH = QWI_RAW / "qwi_download_manifest.json"

# ----------------------------------------------------------------------------
# QWI query configuration
# ----------------------------------------------------------------------------

QWI_API = "https://api.census.gov/data/timeseries/qwi/sa"

# 50 states + DC (FIPS). QWI coverage starts in different years by state
# (WA ~1990, most 1995-1997, AK ~2002); states with no data in a requested
# quarter simply return no rows, so a single wide time range is safe.
QWI_STATES = [f"{fips:02d}" for fips in (
    1, 2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23,
    24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
    42, 44, 45, 46, 47, 48, 49, 50, 51, 53, 54, 55, 56,
)]

# The QWI API accepts a time-range query, so all quarters come back in one call.
QWI_TIME_RANGE = "from 1995 to 2026"

# Indicators pulled per cell (job flows, hires/separations, employment, earnings).
QWI_INDICATORS = [
    "Emp",       # beginning-of-quarter employment (stock)
    "EmpEnd",    # end-of-quarter employment
    "HirAEnd",   # end-of-quarter hires
    "HirN",      # new hires (no prior UI record at this employer)
    "Sep",       # total separations within the quarter
    "SepBeg",    # separations from beginning-of-quarter employment
    "FrmJbGn",   # job gains at growing firms
    "FrmJbLs",   # job losses at shrinking firms
    "HirR",      # recall hires (returning to same employer within a year)
    "EarnS",     # avg monthly earnings, stable (full-quarter) workers
    "EarnBeg",   # avg monthly earnings, beginning-of-quarter workers
]

# NAICS aggregation levels to pull. QWI suppression is non-zero, so a level
# cannot be safely collapsed from a finer one -- each is re-pulled at its
# published level.
DEFAULT_LEVELS = ["4"]

# The single panel this script builds: firm age, all worker ages.
PANEL_NAME = "panel_firmage"
FIRMAGE_VALUES = ["0", "1", "2", "3", "4", "5"]
FIXED_PARAMS = {"sex": "0", "ownercode": "A05", "agegrp": "A00"}

# Concurrency + retry knobs.
MAX_WORKERS = 6
MAX_RETRIES = 4
TIMEOUT_S = 300

# Cached cells are normally skipped outright. With --refresh, a cached cell is
# re-fetched only when the API has published a quarter newer than the one on
# disk. The staleness probe queries ind_level=A (one row per quarter) rather
# than the level being built, because the release frontier is a property of the
# (state, firmage) cell and not of the NAICS aggregation level -- QWI loads a
# state's whole release at once. Note that firmage 1-5 always trail firmage 0
# by one quarter: firm-age measures need the beginning-of-quarter firm
# characteristic, so the age bands are one quarter short by construction.
PROBE_IND_LEVEL = "A"


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


def _qwi_fetch(state: str, firmage: str, ind_level: str, *,
               get_fields: list[str] | None = None,
               time_range: str | None = None):
    """Fetch one (state, firmage, ind_level) cell. Returns a DataFrame or None
    (None = valid query with no data)."""
    import pandas as pd

    params = {
        "get": ",".join(get_fields or (QWI_INDICATORS + ["industry"])),
        "for": f"state:{state}",
        "time": time_range or QWI_TIME_RANGE,
        "firmage": firmage,
        "ind_level": ind_level,
        **FIXED_PARAMS,
    }
    api_key = os.environ.get("CENSUS_API_KEY")
    if api_key:
        params["key"] = api_key

    last_err = None
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(QWI_API, params=params, timeout=TIMEOUT_S,
                             allow_redirects=False)
            if r.status_code == 204:
                return None  # valid query, no data
            if 300 <= r.status_code < 400:
                # Unauthenticated redirect to the "Missing Key" HTML page.
                # Retrying without a key will not help, so fail hard.
                raise RuntimeError(
                    f"HTTP {r.status_code} redirect to "
                    f"{r.headers.get('Location', '?')}; is CENSUS_API_KEY set?"
                )
            if not r.ok:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:200]}")
            if not r.text.strip():
                return None
            ctype = r.headers.get("Content-Type", "")
            if "json" not in ctype.lower():
                raise RuntimeError(
                    f"non-JSON response (Content-Type={ctype!r}): {r.text[:200]}"
                )
            payload = r.json()
            if not payload or len(payload) < 2:
                return None
            return pd.DataFrame(payload[1:], columns=payload[0])
        except Exception as e:  # noqa: BLE001 -- retry any transient failure
            last_err = e
            time.sleep(2 ** attempt)  # exponential backoff
    raise RuntimeError(f"qwi fetch failed after {MAX_RETRIES} attempts: {last_err}")


def _cell_path(level: str, state: str, firmage: str) -> Path:
    return QWI_RAW / f"{PANEL_NAME}_L{level}" / f"state{state}_firmage{firmage}.parquet"


def _cached_max_time(path: Path) -> str | None:
    """Newest quarter in a cached cell, e.g. "2025-Q3". None if unreadable or
    empty -- either way the cell should be re-fetched."""
    import pandas as pd

    try:
        times = pd.read_parquet(path, columns=["time"])["time"]
    except Exception:  # noqa: BLE001 -- corrupt/partial parquet: treat as stale
        return None
    return str(times.max()) if len(times) else None


def _live_max_time(state: str, firmage: str, since_year: int) -> str | None:
    """Newest quarter the API currently publishes for this (state, firmage).
    None when the state publishes nothing at or after since_year (AK and MI
    left the QWI release, so they return HTTP 204 for recent quarters)."""
    df = _qwi_fetch(state, firmage, PROBE_IND_LEVEL, get_fields=["Emp"],
                    time_range=f"from {since_year} to {since_year + 2}")
    if df is None or df.empty or "time" not in df.columns:
        return None
    return str(df["time"].max())


def _stale_cells(level: str, cached: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Of the cells already on disk, return those the API has newer data for.
    Quarter strings ("2025-Q4") compare correctly as plain strings."""
    def probe(cell):
        state, fa = cell
        on_disk = _cached_max_time(_cell_path(level, state, fa))
        if on_disk is None:
            return cell, None, "unreadable"
        try:
            live = _live_max_time(state, fa, int(on_disk[:4]))
        except Exception as e:  # noqa: BLE001 -- probe failure: leave cell alone
            log(f"warn  probe state={state} firmage={fa}: {e}")
            return cell, on_disk, None
        return cell, on_disk, live

    stale = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        for cell, on_disk, live in pool.map(probe, cached):
            if on_disk is None or (live is not None and live > on_disk):
                stale.append(cell)
    return stale


def download_level(level: str, refresh: bool = False) -> dict:
    """Download every (state, firmage) cell for one NAICS level, cache each as a
    parquet, and concatenate into data/raw/qwi/panel_firmage_L{level}.parquet.

    A cell holds its entire time range in one file, so a cached cell is frozen
    at whatever the API held when it was written. refresh=True probes each
    cached cell and re-fetches the ones the API has since extended."""
    import pandas as pd

    tag = f"{PANEL_NAME}_L{level}"
    cell_dir = QWI_RAW / tag
    cell_dir.mkdir(parents=True, exist_ok=True)
    combined_path = QWI_RAW / f"{tag}.parquet"

    # Missing cells are always fetched (resumable).
    all_cells = [(state, fa) for state in QWI_STATES for fa in FIRMAGE_VALUES]
    missing = [c for c in all_cells if not _cell_path(level, c[0], c[1]).exists()]
    cached = [c for c in all_cells if c not in set(missing)]

    stale = []
    if refresh and cached:
        log(f"qwi.{tag}: probing {len(cached)} cached cells for newer quarters")
        stale = _stale_cells(level, cached)
        log(f"qwi.{tag}: {len(stale)} cached cells are behind the current release")

    jobs = missing + stale
    total = len(all_cells)
    log(f"qwi.{tag}: {len(jobs)} of {total} cells to fetch "
        f"({len(missing)} missing, {len(stale)} stale, "
        f"{total - len(jobs)} up to date)")

    done, errors = 0, []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futs = {pool.submit(_qwi_fetch, state, fa, level): (state, fa)
                for state, fa in jobs}
        for fut in as_completed(futs):
            state, fa = futs[fut]
            done += 1
            try:
                df = fut.result()
                if df is not None and not df.empty:
                    df.to_parquet(_cell_path(level, state, fa), index=False)
            except Exception as e:  # noqa: BLE001
                errors.append({"state": state, "firmage": fa, "error": str(e)})
                log(f"warn  {tag} state={state} firmage={fa}: {e}")
            if done % 25 == 0 or done == len(futs):
                log(f"qwi.{tag}: {done}/{len(futs)} fetched ({len(errors)} errors)")

    cells = sorted(cell_dir.glob("*.parquet"))
    if not cells:
        log(f"warn  qwi.{tag}: no data produced")
        return {"level": level, "rows": 0, "cells": 0, "fetched": len(jobs),
                "refreshed": len(stale), "errors": errors}

    combined = pd.concat([pd.read_parquet(p) for p in cells], ignore_index=True)
    combined.to_parquet(combined_path, index=False)
    log(f"saved {combined_path.relative_to(PROJECT_ROOT)} "
        f"({len(combined):,} rows from {len(cells)} cells)")
    return {"level": level, "rows": int(len(combined)), "cells": len(cells),
            "combined": str(combined_path.relative_to(PROJECT_ROOT)),
            "fetched": len(jobs), "refreshed": len(stale),
            "max_time": str(combined["time"].max()) if "time" in combined else None,
            "errors": errors}


def convert_level(level: str) -> dict:
    """Convert data/raw/qwi/panel_firmage_L{level}.parquet into
    data/processed/qwi_panel_firmage_L{level}.dta (indicators numeric,
    lowercase column names)."""
    import pandas as pd

    src = QWI_RAW / f"{PANEL_NAME}_L{level}.parquet"
    dst = PROCESSED / f"qwi_{PANEL_NAME}_L{level}.dta"
    if not src.exists():
        log(f"warn  convert L{level}: {src.name} missing; run the download first")
        return {"level": level, "dta": None}

    PROCESSED.mkdir(parents=True, exist_ok=True)
    df = pd.read_parquet(src)
    for col in QWI_INDICATORS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    df.columns = [c.lower() for c in df.columns]
    df.to_stata(dst, write_index=False, version=118)
    log(f"saved {dst.relative_to(PROJECT_ROOT)} "
        f"({len(df):,} rows, {len(df.columns)} cols)")
    return {"level": level, "rows": int(len(df)),
            "dta": str(dst.relative_to(PROJECT_ROOT))}


# ----------------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--levels", nargs="+", default=DEFAULT_LEVELS,
                   choices=["3", "4", "6"],
                   help="NAICS aggregation levels to build (default: 3 4 6).")
    p.add_argument("--refresh", action="store_true",
                   help="Re-fetch cached cells that the API has extended since "
                        "they were written. Without this, cached cells are "
                        "skipped and the panel never advances past the quarter "
                        "it was first downloaded in.")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--download-only", action="store_true",
                   help="Fetch/cache parquets but do not write .dta files.")
    g.add_argument("--convert-only", action="store_true",
                   help="Rebuild .dta from cached parquets; no API calls.")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if not os.environ.get("CENSUS_API_KEY") and not args.convert_only:
        log("warn  CENSUS_API_KEY is not set. The QWI API will likely redirect "
            "to a Missing-Key page and the download will fail. Get a free key at "
            "https://api.census.gov/data/key_signup.html and export it.")

    QWI_RAW.mkdir(parents=True, exist_ok=True)
    if args.refresh and args.convert_only:
        log("warn  --refresh has no effect with --convert-only (no API calls).")

    manifest = {"started_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "time_range": QWI_TIME_RANGE, "indicators": QWI_INDICATORS,
                "levels": args.levels, "refresh": bool(args.refresh),
                "download": {}, "convert": {}}

    for level in args.levels:
        if not args.convert_only:
            log(f"==> download qwi {PANEL_NAME} L{level}")
            manifest["download"][f"L{level}"] = download_level(level, args.refresh)
        if not args.download_only:
            log(f"==> convert qwi {PANEL_NAME} L{level} -> .dta")
            manifest["convert"][f"L{level}"] = convert_level(level)

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True))
    log(f"done. manifest: {MANIFEST_PATH.relative_to(PROJECT_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
