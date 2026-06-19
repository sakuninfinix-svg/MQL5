#!/usr/bin/env python3
"""
Download historical EURUSD H1 OHLCV data for 2020-2025.
Saves to /home/agus/MQL5/tools/output/eurusd_h1_2020_2025.csv

Strategies (in order):
  1. dukascopy-node CLI (Node.js) - most reliable for full range
  2. yfinance (Python) - fallback for recent 2 years
  3. daily aggregation from yfinance - last resort
"""

import os
import sys
import subprocess
import tempfile
import shutil
import csv
from datetime import datetime, timezone
import pandas as pd

OUTPUT_DIR = "/home/agus/MQL5/tools/output"
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "eurusd_h1_2020_2025.csv")
START_DATE = "2020-01-01"
END_DATE = "2025-12-31"


def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")


def mkdir_p(path):
    os.makedirs(path, exist_ok=True)


def parse_dukascopy_csv(csv_path):
    """Parse dukascopy-node CSV into DataFrame."""
    if not os.path.exists(csv_path) or os.path.getsize(csv_path) < 50:
        return None
    df = pd.read_csv(csv_path)
    df["timestamp"] = pd.to_datetime(df["timestamp"], unit="ms")
    for col in ["open", "high", "low", "close", "volume"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=["open", "high", "low", "close"])
    return df


def download_with_dukascopy(output_dir):
    """Download using dukascopy-node CLI."""
    npx = shutil.which("npx")
    if not npx:
        log("npx not found, skipping dukascopy-node")
        return None

    log("Using dukascopy-node to download EURUSD H1 2020-2025...")

    # dukascopy-node sometimes struggles with very large ranges,
    # so we download in yearly chunks and merge
    years = [2020, 2021, 2022, 2023, 2024, 2025]
    all_dfs = []

    for year in years:
        year_start = f"{year}-01-01"
        year_end = f"{year}-12-31" if year < 2025 else "2025-12-31"

        out_file = os.path.join(output_dir, f"eurusd_{year}.csv")
        if os.path.exists(out_file) and os.path.getsize(out_file) > 100:
            log(f"  {year}: cached file found, reusing")
            df = parse_dukascopy_csv(out_file)
            if df is not None and len(df) > 0:
                all_dfs.append(df)
                continue

        log(f"  Downloading {year}...")
        try:
            result = subprocess.run(
                [
                    npx, "--yes", "dukascopy-node",
                    "-i", "eurusd",
                    "-from", year_start,
                    "-to", year_end,
                    "-t", "h1",
                    "-f", "csv",
                    "-dir", output_dir,
                    "-v",
                    "-fl",
                    "-bp", "2000",
                    "-bs", "5",
                    "-r", "3",
                    "-re",
                ],
                capture_output=True,
                text=True,
                timeout=1800,
            )
            if result.returncode != 0:
                log(f"  dukascopy-node error for {year}: {result.stderr[:200]}")
                continue

            # dukascopy-node names files as eurusd-h1-bid-{from}-{to}.csv
            # find the generated csv
            generated = None
            for fn in os.listdir(output_dir):
                if fn.startswith(f"eurusd-h1-bid-{year}"):
                    generated = os.path.join(output_dir, fn)
                    break

            if generated and os.path.exists(generated):
                os.rename(generated, out_file)
                df = parse_dukascopy_csv(out_file)
                if df is not None and len(df) > 0:
                    all_dfs.append(df)
                    log(f"  {year}: {len(df)} bars")
                else:
                    log(f"  {year}: empty data")
            else:
                log(f"  {year}: no output file generated")

        except subprocess.TimeoutExpired:
            log(f"  {year}: download timed out after 30 minutes")
            continue
        except Exception as e:
            log(f"  {year}: download failed: {e}")
            continue

    if not all_dfs:
        return None

    result = pd.concat(all_dfs, ignore_index=True)
    result = result.sort_values("timestamp").drop_duplicates(subset=["timestamp"])
    # Remove weekends
    result = result[result["timestamp"].dt.dayofweek < 5]
    result = result.reset_index(drop=True)
    return result


def download_with_yfinance():
    """Download recent ~2 years of H1 data using yfinance as fallback."""
    log("Trying yfinance for H1 data...")
    try:
        import yfinance as yf
        df = yf.download("EURUSD=X", period="2y", interval="1h")
        if df is None or len(df) == 0:
            log("yfinance returned no data")
            return None
        # Flatten multi-level columns
        df.columns = [col[0].lower() for col in df.columns]
        df = df.reset_index()
        df = df.rename(columns={"Datetime": "timestamp", "close": "Close",
                                 "high": "High", "low": "Low", "open": "Open",
                                 "volume": "Volume"})
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        for col in ["Open", "High", "Low", "Close", "Volume"]:
            df[col] = pd.to_numeric(df[col], errors="coerce")
        df = df.dropna(subset=["Open", "High", "Low", "Close"])
        df = df.sort_values("timestamp").drop_duplicates(subset=["timestamp"])
        log(f"yfinance: {len(df)} bars from {df['timestamp'].min()} to {df['timestamp'].max()}")
        return df
    except ImportError:
        log("yfinance not installed")
        return None
    except Exception as e:
        log(f"yfinance error: {e}")
        return None


def save_csv(df, path):
    mkdir_p(os.path.dirname(path))
    # Reorder to expected columns
    out = df[["timestamp", "open", "high", "low", "close", "volume"]].copy()
    out["timestamp"] = out["timestamp"].astype("int64") // 10**6  # ms timestamp
    out.to_csv(path, index=False)
    log(f"Saved {len(out)} bars to {path}")


def main():
    mkdir_p(OUTPUT_DIR)

    with tempfile.TemporaryDirectory(prefix="eurusd_") as tmpdir:
        log(f"Using temp dir: {tmpdir}")

        # Strategy 1: dukascopy-node
        df = download_with_dukascopy(tmpdir)

        # Strategy 2: yfinance fallback
        if df is None or len(df) < 1000:
            log("dukascopy-node failed, falling back to yfinance...")
            df2 = download_with_yfinance()
            if df2 is not None and len(df2) > 0:
                df = df2

        # Strategy 3: daily data as last resort
        if df is None or len(df) < 1000:
            log("All H1 sources failed, trying yfinance daily data...")
            try:
                import yfinance as yf
                df_daily = yf.download("EURUSD=X", start=START_DATE, end=END_DATE, interval="1d")
                if df_daily is not None and len(df_daily) > 0:
                    df_daily.columns = [col[0].lower() for col in df_daily.columns]
                    df_daily = df_daily.reset_index()
                    df_daily = df_daily.rename(
                        columns={"Date": "timestamp", "close": "close",
                                 "high": "high", "low": "low", "open": "open",
                                 "volume": "volume"})
                    df = df_daily
                    log(f"Daily data: {len(df)} bars")
            except Exception as e:
                log(f"Daily data error: {e}")

        if df is None or len(df) == 0:
            log("FAILED: All download methods exhausted")
            sys.exit(1)

        save_csv(df, OUTPUT_FILE)

        # Print summary
        bar_count = len(df)
        date_min = df["timestamp"].min()
        date_max = df["timestamp"].max()
        if isinstance(date_min, int):
            date_min = pd.to_datetime(date_min, unit="ms")
            date_max = pd.to_datetime(date_max, unit="ms")

        print(f"\n{'='*60}")
        print(f"  Download {'SUCCEEDED' if bar_count > 0 else 'FAILED'}")
        print(f"  Bars: {bar_count}")
        print(f"  Date range: {date_min} to {date_max}")
        print(f"  File: {OUTPUT_FILE}")
        print(f"{'='*60}")


if __name__ == "__main__":
    main()
