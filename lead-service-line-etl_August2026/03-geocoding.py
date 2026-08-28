#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pandas", "requests", "geopandas"]
# ///
"""03-geocoding.py

Python replacement for 03-geocoding.R.

Geocodes the cleaned Montclair lead service line addresses using the US Census
batch geocoder: free, no API key, US only.

Why not Google, as the R script did:
    The Google Geocoding API requires a billing-enabled Cloud project. A demo
    key returns HTTP 200 with status REQUEST_DENIED and NA coordinates for
    every row, so the run appears to succeed while producing nothing.

Reads   data/lead_service_line_addresses.csv                    (output of 02)
Writes  data_intermediate/lead_service_line_addresses_geocoded.csv
        data_intermediate/lead_service_line_addresses_geocoded.gpkg

The output schema matches what the R pipeline produced, so 03b/04 are unchanged.

Coordinates already present in the previous release's geocoded CSV are reused,
so a re-run only sends genuinely new addresses to the geocoder. Results are
cached to disk after every batch, so an interrupted run resumes for free.

Run from the folder containing this file:
    uv run 03-geocoding.py
or:
    pip install pandas requests geopandas && python 03-geocoding.py
"""

from __future__ import annotations

import csv
import io
import json
import sys
import time
from pathlib import Path

import pandas as pd
import requests

# --- paths -----------------------------------------------------------------
# Resolved relative to this file, so the script works regardless of the
# directory it is launched from. This file belongs in the same folder as
# 01-pdf-ingestion.ipynb and the R scripts.

DIR = Path(__file__).resolve().parent
IN_CSV = DIR / "data" / "lead_service_line_addresses.csv"
OUT_DIR = DIR / "data_intermediate"
OUT_CSV = OUT_DIR / "lead_service_line_addresses_geocoded.csv"
OUT_GPKG = OUT_DIR / "lead_service_line_addresses_geocoded.gpkg"
CACHE_PATH = OUT_DIR / "_geocode_cache.json"

# --- geocoder --------------------------------------------------------------

BATCH_URL = "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
BENCHMARK = "Public_AR_Current"
BATCH_SIZE = 1000          # Census accepts up to 10000; smaller is more reliable
TIMEOUT = 600
MAX_RETRIES = 3

# Montclair bounding box, for flagging implausible results.
BBOX = {"lat_min": 40.78, "lat_max": 40.90, "lon_min": -74.26, "lon_max": -74.15}

# Column order of the geocoded CSV the R pipeline produced. Preserved so that
# 03b-annotate.R and 04-mapping.R see exactly what they saw before.
OUT_COLS = [
    "address", "zip", "town", "address_full", "suspected_lead",
    "psl_materials", "psl_other", "service_line", "csl_other",
    "latitude", "longitude",
]


def norm_key(value: object) -> str:
    """Match key for joining addresses across releases."""
    return " ".join(str(value).upper().split())


def load_cache() -> dict:
    if CACHE_PATH.exists():
        try:
            return json.loads(CACHE_PATH.read_text())
        except json.JSONDecodeError:
            print("  cache file unreadable, starting fresh")
    return {}


def save_cache(cache: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(cache))


def seed_from_previous(cache: dict) -> dict:
    """Reuse coordinates from the previous release's geocoded CSV.

    Those coordinates were produced with a paid Google key, so they are worth
    keeping rather than regenerating.
    """
    if not OUT_CSV.exists():
        print("no previous geocoded file found; geocoding everything")
        return cache

    prior = pd.read_csv(OUT_CSV, dtype=str)
    if not {"address", "latitude", "longitude"} <= set(prior.columns):
        print("previous geocoded file has an unexpected schema; ignoring it")
        return cache

    prior = prior.dropna(subset=["latitude", "longitude"])
    added = 0
    for address, lat, lon in zip(
        prior["address"], prior["latitude"], prior["longitude"]
    ):
        key = norm_key(address)
        if key in cache:
            continue
        try:
            cache[key] = [float(lat), float(lon)]
        except (TypeError, ValueError):
            continue
        added += 1

    print(f"reused {added} coordinates from the previous release")
    return cache


def geocode_batch(rows: list[tuple]) -> dict:
    """Send one batch to the Census geocoder.

    rows: (unique_id, street, city, state, zip)
    Returns {unique_id: (lat, lon)} for matched addresses only.

    The Census batch endpoint returns headerless CSV whose columns are:
        id, input_address, match_status, match_type, matched_address,
        "lon,lat", tiger_line_id, side
    Note the coordinate field is longitude first.
    """
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerows(rows)
    payload = buf.getvalue()

    last_error = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.post(
                BATCH_URL,
                files={"addressFile": ("addresses.csv", payload, "text/csv")},
                data={"benchmark": BENCHMARK},
                timeout=TIMEOUT,
            )
            resp.raise_for_status()
            break
        except requests.RequestException as exc:
            last_error = exc
            if attempt == MAX_RETRIES:
                print(f"    request failed after {MAX_RETRIES} attempts: {exc}")
                return {}
            wait = 5 * attempt
            print(f"    attempt {attempt} failed ({exc}); retrying in {wait}s")
            time.sleep(wait)
    else:
        print(f"    giving up: {last_error}")
        return {}

    matched = {}
    for record in csv.reader(io.StringIO(resp.text)):
        if len(record) < 6 or record[2] != "Match":
            continue
        try:
            lon_str, lat_str = record[5].split(",")
            matched[record[0]] = (float(lat_str), float(lon_str))
        except (ValueError, IndexError):
            continue

    if not matched:
        preview = resp.text[:300].replace("\n", " ")
        print(f"    no matches in response; first 300 chars: {preview}")

    return matched


def main() -> int:
    if not IN_CSV.exists():
        print(f"ERROR: input not found at {IN_CSV}")
        print("Run 02-data-cleaning.R first, or check the folder layout.")
        return 1

    df = pd.read_csv(IN_CSV, dtype=str)
    print(f"read {len(df)} rows from {IN_CSV.relative_to(DIR)}")

    for col in ("address", "zip", "town"):
        if col not in df.columns:
            print(f"ERROR: expected column '{col}' not found. Got: {list(df.columns)}")
            return 1

    # Built the same way the R script built it, so address_full is unchanged.
    df["address_full"] = (
        df["address"].fillna("") + ", " + df["town"].fillna("")
        + ", NJ, " + df["zip"].fillna("")
    )

    df["_key"] = df["address"].map(norm_key)

    cache = seed_from_previous(load_cache())

    todo = sorted({k for k in df["_key"] if k and k not in cache})
    print(f"{df['_key'].nunique()} unique addresses | {len(todo)} need geocoding")

    if todo:
        # One representative row per address supplies the street/city/zip parts.
        reps = df.drop_duplicates("_key").set_index("_key")
        n_batches = (len(todo) + BATCH_SIZE - 1) // BATCH_SIZE

        for batch_no, start in enumerate(range(0, len(todo), BATCH_SIZE), start=1):
            chunk = todo[start:start + BATCH_SIZE]
            rows = []
            for key in chunk:
                rep = reps.loc[key]
                rows.append((
                    key,
                    str(rep["address"] or ""),
                    str(rep["town"] or ""),
                    "NJ",
                    str(rep["zip"] or ""),
                ))

            print(f"  batch {batch_no}/{n_batches}: {len(rows)} addresses ...")
            found = geocode_batch(rows)
            print(f"    matched {len(found)}/{len(rows)}")

            for key in chunk:
                cache[key] = list(found[key]) if key in found else None

            save_cache(cache)
            time.sleep(1)

    df["latitude"] = df["_key"].map(lambda k: (cache.get(k) or [None, None])[0])
    df["longitude"] = df["_key"].map(lambda k: (cache.get(k) or [None, None])[1])
    df = df.drop(columns="_key")

    # --- checks ------------------------------------------------------------

    n_missing = int(df["latitude"].isna().sum())
    print()
    print(f"rows                : {len(df)}")
    print(f"missing coordinates : {n_missing}")

    if n_missing == len(df):
        print()
        print("ERROR: every address failed to geocode. Nothing was written.")
        print("Check network access and the response preview above.")
        return 1

    missing = df[df["latitude"].isna()]
    if len(missing):
        no_number = missing[~missing["address"].str.match(r"^\d", na=False)]
        print(f"  of which have no street number: {len(no_number)}")
        print("  (intersections, parks and similar; 04 drops these via flag_incomplete)")
        for addr in missing["address"].head(60):
            print(f"    {addr}")

    placed = df.dropna(subset=["latitude", "longitude"])
    outliers = placed[
        (placed["latitude"] < BBOX["lat_min"]) | (placed["latitude"] > BBOX["lat_max"])
        | (placed["longitude"] < BBOX["lon_min"]) | (placed["longitude"] > BBOX["lon_max"])
    ]
    print(f"coordinates outside Montclair bbox: {len(outliers)}")
    if len(outliers):
        print("  (bad geocodes; fix by hand in 03b-annotate.R)")
        print(outliers[["address", "latitude", "longitude"]].to_string(index=False))

    # --- export ------------------------------------------------------------

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    ordered = [c for c in OUT_COLS if c in df.columns]
    ordered += [c for c in df.columns if c not in ordered]
    df = df[ordered]

    df.to_csv(OUT_CSV, index=False)
    print(f"\nwrote {len(df)} rows to {OUT_CSV.relative_to(DIR)}")

    try:
        import geopandas as gpd
        from shapely.geometry import Point  # noqa: F401  (via points_from_xy)

        gdf = gpd.GeoDataFrame(
            placed.copy(),
            geometry=gpd.points_from_xy(placed["longitude"], placed["latitude"]),
            crs="EPSG:4326",
        )
        gdf.to_file(OUT_GPKG, driver="GPKG")
        print(f"wrote {len(gdf)} geometries to {OUT_GPKG.relative_to(DIR)}")
    except ImportError:
        print("geopandas not installed; skipped the .gpkg."
              " The CSV is what 03b/04 read, so this is not fatal.")

    print("\nNext: 03b-annotate.R, then 04-mapping.R")
    return 0


if __name__ == "__main__":
    sys.exit(main())
