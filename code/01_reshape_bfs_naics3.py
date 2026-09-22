#!/usr/bin/env python3
"""Reshape the 3-digit NAICS BFS dataset from wide to long for Stata.

Input:  data/raw/bfs/naics3.csv -- wide, with id columns (naics3, description)
        followed by one column per year-week named YYYYwWW (e.g. 2006w01).
Output: data/processed/bfs_naics3_long.csv -- long, one row per
        (naics3, year, week) with columns:
            naics3, description, year, week, yearweek, value

Long format lets Stata handle it directly (`import delimited`, then it's ready
for xtset/tsset or collapse) instead of fighting 1,000+ variable-name columns.
"""

from __future__ import annotations

import argparse
import os
import re

import pandas as pd

YEARWEEK_RE = re.compile(r"^(\d{4})w(\d{2})$")


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", default=os.path.join(repo_root, "data", "raw", "bfs",
                                                    "naics3.csv"))
    ap.add_argument("--output", default=os.path.join(repo_root, "data", "processed",
                                                     "bfs_naics3_long.csv"))
    args = ap.parse_args()

    # Read naics3 as string to preserve codes exactly; values stay numeric.
    df = pd.read_csv(args.input, dtype={"naics3": "string", "description": "string"})

    id_cols = ["naics3", "description"]
    value_cols = [c for c in df.columns if YEARWEEK_RE.match(c)]
    unmatched = [c for c in df.columns if c not in id_cols and c not in value_cols]
    if unmatched:
        raise ValueError(f"Unexpected non-YYYYwWW columns: {unmatched}")

    long_df = df.melt(id_vars=id_cols, value_vars=value_cols,
                      var_name="yearweek", value_name="value")

    parts = long_df["yearweek"].str.extract(YEARWEEK_RE)
    long_df["year"] = parts[0].astype("int16")
    long_df["week"] = parts[1].astype("int8")

    long_df = long_df[["naics3", "description", "year", "week", "yearweek", "value"]]
    long_df = long_df.sort_values(["naics3", "year", "week"]).reset_index(drop=True)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    long_df.to_csv(args.output, index=False)

    sectors = long_df["naics3"].nunique()
    print(f"Reshaped {len(df)} rows x {len(value_cols)} week-columns "
          f"-> {len(long_df):,} long rows ({sectors} sectors, "
          f"{long_df.year.min()}w{long_df.week.min():02d}-"
          f"{long_df.year.max()}w{long_df.week.max():02d}).")
    print(f"Missing values: {long_df['value'].isna().sum():,}")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
